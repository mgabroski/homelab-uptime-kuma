# homelab-uptime-kuma — Runbook

Operational procedures for Uptime Kuma. All commands are run from the
`homelab-uptime-kuma` project root unless stated otherwise.

---

## Prerequisites

Before running any command on a new machine:

1. Docker Desktop installed and running
1. Corepack enabled: `corepack enable`
1. Yarn set to correct version: `yarn set version 4.10.3`
1. Yarn dependencies installed: `yarn install`
1. yamllint installed: `pip3 install yamllint==1.35.1`
1. Volume created manually: `docker volume create homelab-uptime-kuma-data`
1. Network created if not already present: `docker network create homelab-internal`

`homelab-internal` may already exist if homelab-portainer is running.
The `make up` target handles this safely with `|| true`.

---

## Start

```bash
make up
```

Creates the volume and network if they do not exist, then starts the
container in detached mode. The service is accessible at
`http://localhost:3001` within a few seconds.

**On first start:** navigate immediately to `http://localhost:3001` and
complete these steps before anything else:

1. Create the admin account — choose a strong password (minimum 16 characters)
1. Enable MFA under Settings → Security → Two Factor Authentication
1. Store MFA recovery codes safely outside the repository
1. Verify login by logging out and back in

Do not leave the first-login endpoint unclaimed after starting the service.

---

## First Monitor Setup — Portainer

After completing first-login setup, create the Portainer health monitor:

1. Click **Add New Monitor**
1. Type: `HTTP(s)`
1. Friendly Name: `Portainer`
1. URL: `http://homelab-portainer:9000`
1. Heartbeat Interval: `60` seconds
1. Accepted Status Codes: `200-299`
1. Save

The monitor should show green within 60 seconds. If it shows red, see
Troubleshooting — Portainer monitor shows DOWN immediately.

---

## Stop

```bash
make down
```

Stops and removes the container. The volume `homelab-uptime-kuma-data`
and the network `homelab-internal` are preserved. All monitor
configuration and history survive.

---

## Restart

```bash
make restart
```

Use restart for minor resets. Use `down` followed by `up` when
troubleshooting a container that is in a bad state.

---

## Check Status

```bash
make ps
```

---

## Follow Logs

```bash
make logs
```

Uptime Kuma logs monitor check results, login events, and errors.
Check here first when investigating unexpected behaviour.

---

## Update Image Version

Before updating, check the Uptime Kuma changelog at
<https://github.com/louislam/uptime-kuma/releases>

Update the version pin in `docker-compose.yml`:

```plaintext
image: louislam/uptime-kuma:NEW_VERSION
```

Also update the `IMAGE_VERSION` variable at the top of the Makefile to
match — this is used by `restore-test` to boot-test the correct version.

Document the version change and date in `docs/decisions.md` Decision 001.
Then run:

```bash
make update
```

`make update` runs `make backup` first, then pulls the new image and
restarts the service. Do not bypass this unless you intentionally accept
the risk of updating without a rollback point. After updating, verify:

- `http://localhost:3001` loads correctly
- All monitors are present and reporting
- No errors in `make logs`

---

## Backup

```bash
make backup
```

Stops the service, exports the contents of `homelab-uptime-kuma-data`
to `backups/uptime-kuma-backup-YYYYMMDD-HHMMSS.tar.gz`, then restarts
the service. The service is typically offline for under 10 seconds.

The service is stopped before backup to prevent copying a mid-write
SQLite database. A shell trap ensures the service is restarted even if
the archive operation fails — the backup exits non-zero on failure but
the monitoring service does not remain stopped.

Run before any volume deletion, image update, or destructive operation.
The `backups/` directory is gitignored and kept locally only.

---

## Restore

Full restore procedure. Run this when recovering from data loss or
moving the service to a new machine.

1. List available backups before doing anything:

```bash
ls -lh backups/
```

1. Run a backup if the current volume has any data worth preserving:

```bash
make backup
```

1. Stop the container:

```bash
make down
```

1. Remove the existing volume:

```bash
docker volume rm homelab-uptime-kuma-data
```

1. Recreate the empty volume:

```bash
docker volume create homelab-uptime-kuma-data
```

1. Restore from backup (restores the most recent backup by default):

```bash
docker run --rm \
  -v homelab-uptime-kuma-data:/target \
  -v "$(pwd)/backups:/backup:ro" \
  alpine \
  sh -c 'cd /target && tar xzf $(ls /backup/*.tar.gz | tail -1)'
```

1. Start the container and verify:

```bash
make up
```

Navigate to `http://localhost:3001` and confirm all monitors and
configuration are present.

---

## Test Restore Without Affecting Production

```bash
make restore-test
```

Restores the most recent backup into a temporary test volume, starts a
full Uptime Kuma instance from that restored data on port 3999, waits
up to 60 seconds for the service to respond via HTTP, then stops the
test container and removes the test volume. The command exits non-zero
if the service does not respond — this is a real pass/fail gate, not a
file listing.

Production volume and running container are not affected.

---

## Alert Behaviour — No External Channel Configured

No external alerting channels are configured in this deployment.
Alerts are visible in the Uptime Kuma dashboard only. This is intentional
for the localhost-only, pre-Caddy stage.

To add alerting in the future:

1. Log in to `http://localhost:3001`
1. Navigate to Settings → Notifications
1. Add a notification provider (Slack, email, Telegram, etc.)
1. Assign the notification to each monitor via the monitor edit page
1. Document the channel type in `docs/decisions.md`

Do not commit notification credentials to the repo. They are stored in
the Uptime Kuma UI only and persisted in the volume.

---

## Full Teardown

```bash
make clean
```

Stops and removes the container. The volume is preserved because it is
declared external. To also remove the volume permanently:

```bash
docker volume rm homelab-uptime-kuma-data
```

**Warning:** This destroys all monitor configuration and history. Run
`make backup` first.

---

## Verify Runtime

```bash
make verify-runtime
```

Checks the Docker Compose config, container health status, localhost-only
port binding, HTTP response, and absence of Docker socket mounts. Run this
after `make up` and after any update.

---

## Format and Validate Linting

```bash
make validate
```

`make validate` auto-formats supported files with Prettier, then runs
yamllint and markdownlint. Use the non-mutating check when you need CI-style
validation only:

```bash
make validate-check
```

---

## Step 6 Hardening Verification Checklist

Run these checks before marking the project hardened. Record results in
`docs/security.md` and `docs/decisions.md` where indicated.

### Verify image tag exists and pulls

```bash
docker compose pull
docker image inspect louislam/uptime-kuma:1.23.13 >/dev/null && echo "tag verified"
```

### Verify localhost-only port binding

```bash
docker port homelab-uptime-kuma
lsof -iTCP:3001 -sTCP:LISTEN
```

Expected: port 3001 is bound to `127.0.0.1`, not `0.0.0.0`.

### Verify no Docker socket mount

```bash
docker inspect homelab-uptime-kuma --format '{{json .Mounts}}'
```

Expected: only the Uptime Kuma data volume is mounted. No socket entry.

### Verify container runtime user

```bash
docker exec homelab-uptime-kuma id
docker inspect homelab-uptime-kuma --format '{{.Config.User}}'
```

Record the exact output in `docs/security.md` Container Privilege Level
and in `docs/decisions.md` Decision 012.

### Verify internal DNS to Portainer

```bash
docker exec homelab-uptime-kuma getent hosts homelab-portainer
```

### Verify Portainer is reachable across the internal network

```bash
docker run --rm --network homelab-internal alpine sh -c \
  'apk add --no-cache curl >/dev/null && curl -I http://homelab-portainer:9000'
```

Expected: Portainer returns an HTTP response.

### Verify persistence across restart

1. Create the Portainer monitor if not already done.
1. Run `make down` then `make up`.
1. Confirm monitor and admin login still exist.

### Verify backup and restore

```bash
make backup
make restore-test
```

Expected: `make restore-test` exits with success code and prints
`Restore boot test PASSED`.

### Verify MFA

1. Log out of Uptime Kuma.
1. Log back in.
1. Confirm TOTP code is required.
1. Confirm recovery codes are stored outside the repository.
1. Update `docs/decisions.md` Decision 007 status to verified.

### Verify Docker healthcheck

```bash
docker inspect homelab-uptime-kuma --format '{{.State.Health.Status}}'
make verify-runtime
```

Expected: the health status becomes `healthy` after the start period, and
`make verify-runtime` exits successfully.

---

## Troubleshooting

### Image pull fails on make up or make pull

**Symptom:** `make up` or `make pull` fails with a manifest or tag not found error.

**Cause:** The pinned Uptime Kuma image tag is not available from Docker Hub.

**Fix:**

```bash
docker manifest inspect louislam/uptime-kuma:1.23.13 >/dev/null && echo "tag exists"
```

If the tag does not exist, check <https://github.com/louislam/uptime-kuma/releases>
for the correct current tag. Update `docker-compose.yml` and the `IMAGE_VERSION`
variable in the Makefile to the verified tag. Document the change in
`docs/decisions.md` Decision 001.

---

### Portainer monitor shows DOWN immediately after setup

**Symptom:** The Portainer monitor is created but immediately shows DOWN
or unreachable.

**Cause:** The monitor URL is set to `http://localhost:9000` instead of
`http://homelab-portainer:9000`, or `homelab-portainer` is not running,
or the two containers are not on the same network.

**Fix:**

```bash
docker network inspect homelab-internal
```

Confirm both `homelab-uptime-kuma` and `homelab-portainer` appear under
`Containers`. If either is missing, restart the affected service with
`make up` in its respective project directory. Then update the monitor URL
in Uptime Kuma to `http://homelab-portainer:9000`.

---

### Container starts but UI is not accessible at localhost:3001

**Symptom:** `make up` completes without error but `http://localhost:3001`
returns a connection refused or timeout error.

**Cause:** The container may still be initialising, or the port binding
is not as expected.

**Fix:**

```bash
make ps
make logs
```

Check that the container status is `Up` and that port 3001 is bound to
`127.0.0.1:3001`. On first run, allow 10–15 seconds for initialisation.

---

### Volume data is missing after container recreation

**Symptom:** All monitors and configuration are gone after running
`make down` followed by `make up`.

**Cause:** The volume was not declared as `external: true` in
`docker-compose.yml`, causing Docker Compose to create and destroy a
prefixed volume alongside the container.

**Fix:**

```bash
docker volume ls | grep uptime-kuma
```

If you see `homelab-uptime-kuma_homelab-uptime-kuma-data` instead of
`homelab-uptime-kuma-data`, the external declaration is missing or the
volume was not created manually before first run. Restore from backup
using the restore procedure above.

---

### restore-test fails or port 3999 is already in use

**Symptom:** `make restore-test` fails, or Docker reports that port 3999
is already allocated.

**Cause:** A previous restore-test container may still be running, another
local process is using port 3999, or the restored Uptime Kuma data failed
to boot.

**Fix:**

```bash
docker ps --filter "name=homelab-uptime-kuma-restore-test"
docker logs homelab-uptime-kuma-restore-test 2>/dev/null || true
docker stop homelab-uptime-kuma-restore-test 2>/dev/null || true
docker volume rm homelab-uptime-kuma-restore-test 2>/dev/null || true
lsof -iTCP:3999 -sTCP:LISTEN
```

After cleanup, run:

```bash
make restore-test
```

---

### Login page shows but credentials are rejected

**Symptom:** Known credentials do not work after a restore or container
recreation.

**Cause:** The restored backup is from a different point in time than
when the credentials were set, or the volume data is from a different
instance.

**Fix:** Reset the admin password via the Uptime Kuma CLI inside the container:

```bash
docker exec -it homelab-uptime-kuma node extra/reset-password.js
```

Follow the prompts to set a new admin password.

---

### Docker healthcheck stays unhealthy

**Symptom:** `docker compose ps` shows `unhealthy`, or `make verify-runtime`
fails at the health status check.

**Cause:** The service may still be starting, the Node healthcheck command may
be failing, or Uptime Kuma may not be listening on port 3001 inside the
container.

**Fix:**

```bash
docker inspect homelab-uptime-kuma --format '{{json .State.Health}}'
make logs
curl -fsS http://localhost:3001/ >/dev/null && echo "UI responds"
```

Wait through the 30-second start period first. If the UI responds but the
healthcheck still fails, inspect the health log output and document the result
in `docs/decisions.md` before changing the healthcheck.

## Local Tooling Artifacts

`yarn install` generates or updates `yarn.lock`. Commit `yarn.lock` so every machine uses the same tooling dependency graph. Do not edit `yarn.lock` manually; it is excluded from Prettier formatting because Yarn owns its format.
