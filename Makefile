BACKUP_DIR  := backups
TIMESTAMP   := $(shell date +%Y%m%d-%H%M%S)
BACKUP_FILE := $(BACKUP_DIR)/uptime-kuma-backup-$(TIMESTAMP).tar.gz
VOLUME_NAME := homelab-uptime-kuma-data
TEST_VOLUME := homelab-uptime-kuma-restore-test
# Must match the version pinned in docker-compose.yml
IMAGE_VERSION := louislam/uptime-kuma:1.23.13
YAML_FILES  := .commitlintrc.yml .lintstagedrc.yml .markdownlint.yml .prettierrc.yml .yamllint.yml .yarnrc.yml docker-compose.yml

.PHONY: up down restart logs ps pull update backup restore-test verify-runtime clean format validate validate-check help

up: ## Start Uptime Kuma in the background
	docker volume create $(VOLUME_NAME) 2>/dev/null || true
	docker network create homelab-internal 2>/dev/null || true
	docker compose up -d

down: ## Stop and remove the container (volume and network preserved)
	docker compose down

restart: ## Restart the container
	docker compose restart

logs: ## Follow live container logs
	docker compose logs -f

ps: ## Show container status
	docker compose ps

pull: ## Pull the pinned image without restarting
	docker compose pull

update: backup ## Backup data, pull new image version, and restart
	docker compose pull
	docker compose up -d

backup: ## Stop service, export the data volume to backups/, restart service — SQLite-safe
	@mkdir -p $(BACKUP_DIR)
	@set -e; \
	echo "Stopping service for consistent SQLite backup..."; \
	docker compose stop; \
	trap 'echo "Restarting service..."; docker compose start >/dev/null 2>&1 || true' EXIT; \
	docker run --rm \
		-v $(VOLUME_NAME):/data:ro \
		-v "$(PWD)/$(BACKUP_DIR):/backup" \
		alpine \
		sh -c 'cd /data && tar czf /backup/uptime-kuma-backup-$(TIMESTAMP).tar.gz .'; \
	echo "Backup written to $(BACKUP_FILE)"

restore-test: ## Restore latest backup into test volume, boot-test it, verify HTTP, clean up
	@test -d $(BACKUP_DIR) || \
		(echo "ERROR: No backups/ directory found. Run make backup first." && exit 1)
	@test -n "$$(ls -1 $(BACKUP_DIR)/*.tar.gz 2>/dev/null | tail -1)" || \
		(echo "ERROR: No backup files found in backups/. Run make backup first." && exit 1)
	@set -e; \
	echo "Cleaning up any previous test resources..."; \
	docker stop $(TEST_VOLUME) 2>/dev/null || true; \
	docker volume rm $(TEST_VOLUME) 2>/dev/null || true; \
	echo "Creating test volume..."; \
	docker volume create $(TEST_VOLUME) >/dev/null; \
	trap 'echo "Cleaning up test resources..."; docker stop $(TEST_VOLUME) 2>/dev/null || true; docker volume rm $(TEST_VOLUME) 2>/dev/null || true' EXIT; \
	echo "Restoring latest backup into test volume..."; \
	docker run --rm \
		-v $(TEST_VOLUME):/target \
		-v "$(PWD)/$(BACKUP_DIR):/backup:ro" \
		alpine \
		sh -c 'cd /target && tar xzf $$(ls -1 /backup/*.tar.gz | tail -1)'; \
	echo "Starting Uptime Kuma from restored volume on port 3999..."; \
	docker run -d --rm \
		--name $(TEST_VOLUME) \
		-p 127.0.0.1:3999:3001 \
		-v $(TEST_VOLUME):/app/data \
		$(IMAGE_VERSION); \
	echo "Waiting up to 60s for restored service to respond..."; \
	for i in $$(seq 1 30); do \
		if curl -fsS http://localhost:3999/ >/dev/null 2>&1; then \
			echo "Restore boot test PASSED — service started from restored data"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "Restore boot test FAILED — service did not respond within 60s"; \
	echo "Check logs with: docker logs $(TEST_VOLUME)"; \
	exit 1

verify-runtime: ## Verify running container, healthcheck, port binding, mounts, and HTTP response
	@set -e; \
	echo "Checking Docker Compose config..."; \
	docker compose config -q; \
	echo "Checking container is running..."; \
	docker inspect homelab-uptime-kuma >/dev/null; \
	echo "Checking Docker health status..."; \
	HEALTH="$$(docker inspect homelab-uptime-kuma --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}')"; \
	echo "Health status: $$HEALTH"; \
	test "$$HEALTH" = "healthy"; \
	echo "Checking localhost HTTP response..."; \
	curl -fsS http://localhost:3001/ >/dev/null; \
	echo "Checking port binding is localhost-only..."; \
	docker port homelab-uptime-kuma | grep '127.0.0.1:3001'; \
	echo "Checking no Docker socket is mounted..."; \
	! docker inspect homelab-uptime-kuma --format '{{json .Mounts}}' | grep -q '/var/run/docker.sock'; \
	echo "Runtime verification PASSED"

clean: ## Stop container and remove container resources (volume is preserved — external)
	docker compose down
	@echo "Container removed. Volume $(VOLUME_NAME) is preserved."
	@echo "To permanently delete the volume: docker volume rm $(VOLUME_NAME)"

format: ## Auto-format all supported project files with Prettier
	yarn prettier --write .

validate: format ## Auto-format, then run yamllint and markdownlint
	yamllint $(YAML_FILES)
	yarn markdownlint "**/*.md" --ignore node_modules --ignore .yarn --ignore backups

validate-check: ## Check formatting without modifying files, then run yamllint and markdownlint
	yarn prettier --check .
	yamllint $(YAML_FILES)
	yarn markdownlint "**/*.md" --ignore node_modules --ignore .yarn --ignore backups

help: ## Show all available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
