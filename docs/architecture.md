# homelab-uptime-kuma — Architecture

## Overview

Uptime Kuma is deployed as a single container on a MacBook M2. It joins the
`homelab-internal` Docker bridge network to monitor `homelab-portainer` via
internal hostname resolution. The web UI is exposed on `127.0.0.1:3001` —
localhost only until Caddy is deployed in Project 4.

---

## Components

| Component   | Image                  | Version |
| ----------- | ---------------------- | ------- |
| Uptime Kuma | `louislam/uptime-kuma` | 1.23.13 |

The image publishes a multi-arch manifest and runs natively on ARM64.
Version is pinned to 1.23.13 — selected at project build time after
verifying tag availability. Tag 1.23.11 was rejected due to known Docker Hub
availability issues (ref: upstream issue #4890). See docs/decisions.md
Decision 001 for full version selection rationale.

SQLite is embedded — no separate database container is required. Data is
stored in `/app/data` inside the container. Because SQLite is file-based,
backups are taken with the service stopped to avoid copying a mid-write
database state. See Decision 011.

---

## Storage

| Type         | Name                       | Mount Path  | Purpose                                                                   |
| ------------ | -------------------------- | ----------- | ------------------------------------------------------------------------- |
| Named volume | `homelab-uptime-kuma-data` | `/app/data` | All monitor config, alert rules, status history, embedded SQLite database |

Volume is declared `external: true` per HQ-001. Created manually before
`docker compose up`. Docker Compose will not prefix the name. The volume
is independent of the container lifecycle — deleting and recreating the
container does not affect the volume.

---

## Networking

| Port | Protocol | Bound To  | Purpose                             |
| ---- | -------- | --------- | ----------------------------------- |
| 3001 | HTTP     | 127.0.0.1 | Uptime Kuma web UI — localhost only |

Port 3001 is the only host-exposed port. All other internal ports remain
within the container and are not exposed to the host.

| Network            | Type              | Purpose                                                                                                       |
| ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `homelab-internal` | bridge (external) | Internal service-to-service communication — enables Uptime Kuma to reach homelab-portainer by Docker hostname |

`homelab-proxy` is not joined until Project 4 when Caddy is deployed.

The container has a Docker healthcheck that performs an internal HTTP request
to `127.0.0.1:3001` using Node. This avoids adding curl or wget as image
dependencies and lets `docker compose ps` report whether the web process is
responding.

---

## Secrets

No secrets are required at deploy time. Uptime Kuma's admin account is
created interactively on first login via the web UI. No credentials are
passed via environment variables or `.env`. See docs/security.md for
the full auth model.

---

## Persistence

| Scenario                           | Outcome                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| Container stops and restarts       | All monitor config, history, and settings survive — volume is independent    |
| Container is deleted and recreated | All data survives — volume is external and unaffected by container lifecycle |
| Docker daemon restarts             | Container recovers automatically via `restart: unless-stopped`               |
| Volume is deleted                  | All data is permanently lost — run `make backup` before any volume deletion  |

---

## Reverse Proxy

| Item           | Status                                                                |
| -------------- | --------------------------------------------------------------------- |
| Caddy routing  | Not active — Project 4                                                |
| Local domain   | `uptime.local` — reserved in PORT-REGISTRY.md, activated in Project 4 |
| Current access | `http://localhost:3001`                                               |

HTTP-only access is a documented exception on DOD criterion 1.6.
Acceptable at this stage because access is localhost-only. HTTPS will
be enforced once Caddy routes the service in Project 4.

---

## Backup

| Item        | Detail                                                                                                                 |
| ----------- | ---------------------------------------------------------------------------------------------------------------------- |
| Approach    | Service is stopped, Alpine container mounts the volume read-only and tars contents to `backups/`, service is restarted |
| Why stopped | SQLite is file-based — copying mid-write produces a backup that may not restore cleanly                                |
| Location    | `backups/` — gitignored, local only                                                                                    |
| Filename    | `uptime-kuma-backup-YYYYMMDD-HHMMSS.tar.gz`                                                                            |
| Restore     | Stop container, remove volume, recreate volume, extract backup, restart                                                |
| Criticality | Medium — data loss means rebuilding all monitor configs from scratch; no credentials or personal data at risk          |

---

## Self-Monitoring Limitation

Uptime Kuma monitors other services, but no independent service monitors
Uptime Kuma itself at this stage. This is an accepted limitation for Project 2.
Uptime Kuma health is verified manually via `docker compose ps`, logs, and
browser access during the hardening pass. The full observability stack
(Prometheus, Grafana, Loki) in Session 2 Stage 7 provides the foundation
for closing this gap.

---

## Runtime Health

| Check                 | Mechanism                                   | Purpose                                                                       |
| --------------------- | ------------------------------------------- | ----------------------------------------------------------------------------- |
| Docker restart        | `restart: unless-stopped`                   | Recovers service after container or daemon restart                            |
| Container health      | Compose healthcheck using Node HTTP request | Detects whether the local Uptime Kuma web process responds                    |
| Operator verification | `make verify-runtime`                       | Confirms health, localhost binding, HTTP response, and no Docker socket mount |
| Restore proof         | `make restore-test`                         | Proves backups can boot into a working temporary instance                     |

---

## Current State

```plaintext
MacBook M2
│
├── Browser
│     └── http://localhost:3001 ──► homelab-uptime-kuma (127.0.0.1:3001)
│                                         │
│                                   /app/data
│                                         │
│                           homelab-uptime-kuma-data (named volume)
│
└── homelab-internal (bridge network)
      ├── homelab-uptime-kuma  ──► monitors ──► homelab-portainer:9000
      └── homelab-portainer
```

---

## Future State — Project 4

```plaintext
Browser ──► https://uptime.local
                │
           homelab-caddy (homelab-proxy network)
                │
           homelab-uptime-kuma
           (joins homelab-proxy in Project 4)
```
