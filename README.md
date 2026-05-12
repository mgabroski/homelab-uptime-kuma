# homelab-uptime-kuma

Uptime Kuma — self-hosted service health monitoring for the homelab program.

Stage 1, Project 2 — Core Lab Control Layer.

---

## What This Is

Uptime Kuma watches every service in the homelab and tells you the moment
anything stops working. Instead of finding out a service is broken when you
try to use it, you know immediately — before anyone else does. It works by
quietly checking each service at a configured interval — in this project,
the Portainer monitor is configured with a 60-second heartbeat during first
setup — and flagging anything that stops answering. Think of it as a
smoke alarm for your infrastructure: silent when everything is fine, loud
the instant something goes wrong.

---

## Why This Matters

In a real engineering environment, no one manually checks whether services
are running. Monitoring tools do it continuously, so engineers know about
failures before users do. Without this layer, a homelab is just a collection
of services you hope are working. With it, the lab becomes something you
actively operate. Uptime Kuma is the same category of tool as Datadog,
PagerDuty, and Pingdom — this is the self-hosted, privacy-respecting version
that runs entirely on your own hardware with no external dependencies.

---

## Stack

| Component     | Technology              | Version                    |
| ------------- | ----------------------- | -------------------------- |
| Runtime       | Docker + Docker Compose | Latest stable              |
| Application   | Uptime Kuma             | 1.23.13                    |
| Architecture  | ARM64 (Apple M2)        | Native multi-arch image    |
| Reverse proxy | Caddy                   | Project 4 — not yet active |

---

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/homelab-uptime-kuma.git
cd homelab-uptime-kuma
corepack enable
yarn install
docker volume create homelab-uptime-kuma-data
docker network create homelab-internal  # skip if already exists from Project 1
make up
```

Open <http://localhost:3001> and create your admin account immediately.
Enable MFA before doing anything else.

---

## Available Commands

```bash
make up            # start service in background
make down          # stop and remove container (volume preserved)
make restart       # restart container
make logs          # follow live logs
make ps            # show container status
make pull          # pull pinned image without restarting
make update        # pull new image version and restart
make backup        # stop service, export data volume to backups/, restart service
make restore-test  # restore backup into test volume, boot-test it, clean up
make verify-runtime # verify healthcheck, localhost binding, mounts, and HTTP
make clean         # stop container and remove container resources
make validate      # auto-format, then run all linters
make validate-check # check formatting and linting without modifying files

# yarn.lock is intentionally not committed for this config-only repo.
make help          # show all commands
```

---

## Architecture

Single container deployment. Uptime Kuma joins `homelab-internal` to reach
`homelab-portainer` by Docker hostname — no host port needed for monitoring.

```plaintext
Browser ──► localhost:3001
                │
    ┌───────────▼────────────┐
    │  homelab-uptime-kuma   │
    │  louislam/uptime-kuma  │
    │                        │
    │  /app/data ◄────────── homelab-uptime-kuma-data (volume)
    └───────────┬────────────┘
                │ homelab-internal network
    ┌───────────▼────────────┐
    │  homelab-portainer     │
    │  http://homelab-       │
    │  portainer:9000        │
    └────────────────────────┘
```

Full architecture detail: [docs/architecture.md](docs/architecture.md)

Architecture diagram: [docs/assets/architecture-diagram.png](docs/assets/architecture-diagram.png)

---

## Security Posture

- Port 3001 bound to `127.0.0.1` — localhost only until Caddy in Project 4
- No default credentials — admin account created by operator on first login
- No Docker socket or host filesystem access
- Privilege escalation blocked via `security_opt: no-new-privileges:true`
- MFA required — must be enabled during first-login hardening

Full security detail: [docs/security.md](docs/security.md)

---

## Backup and Restore

```bash
make backup        # stops service, exports volume, restarts — SQLite-safe
make restore-test  # restores backup, boots test instance, verifies HTTP, cleans up
```

Full restore procedure: [docs/runbook.md](docs/runbook.md)

---

## What I Learned

1. **Docker internal networking is the right way to monitor containers** —
   using `http://homelab-portainer:9000` instead of `http://localhost:9000`
   means Uptime Kuma talks to Portainer the way containers are supposed to
   talk to each other: via the internal network, not via the host. localhost
   inside a container refers to the container itself, not the host machine.

1. **SQLite backup requires the application to be stopped** — copying a live
   SQLite database can produce a tarball that looks valid but may not restore
   cleanly because a write may have been mid-transaction. The stop-copy-start
   pattern is the correct approach at this scale. A backup that cannot restore
   is worse than no backup.

1. **The first-login window is a real security consideration** — Uptime Kuma
   has no default credentials, but the admin account creation endpoint is open
   on localhost from the moment the container starts until the first login
   completes. Completing setup immediately after `make up` is a documented
   operational requirement, not a suggestion.

---

## How This Scales

In production, this monitoring role is played by tools like Datadog, Prometheus
with Alertmanager, or PagerDuty — each with dedicated on-call routing, escalation
policies, and SLA tracking. The patterns here are identical: define a check, set a
threshold, route an alert. What changes at scale is the alerting layer — a homelab
can absorb a Slack message; a production system needs paging, escalation, and an
audit trail. The Uptime Kuma deployment here would be replaced by a HA-deployed
Prometheus stack in production, but the mental model of "check, threshold, alert"
carries forward exactly.

---

## Portfolio Assets

The repo includes a generated architecture diagram at
`docs/assets/architecture-diagram.png`. Real screenshots must be captured
from the running service during the portfolio pass and stored under
`docs/assets/screenshots/` using the names documented in that folder.
Screenshots are not fabricated in this initial commit.

---

## Demo Flow

**Before the demo — create the Portainer monitor:**

1. Run `make up`
1. Open <http://localhost:3001> and create the admin account
1. Enable MFA under Settings → Security → Two Factor Authentication
1. Click **Add New Monitor**
1. Type: `HTTP(s)`
1. Friendly Name: `Portainer`
1. URL: `http://homelab-portainer:9000`
1. Heartbeat Interval: `60` seconds
1. Accepted Status Codes: `200-299`
1. Save — wait for the first check to complete

**The demo itself (under 5 minutes):**

1. Show the dashboard — Portainer listed as UP with response time graph
1. Open a second terminal and run `make down` in the homelab-portainer directory
1. Switch back to Uptime Kuma — watch the monitor detect failure and go red in real time
1. Run `make up` in homelab-portainer — watch Uptime Kuma detect recovery
1. Show the incident history on the Portainer monitor detail page
1. Run `make backup` — show the backup file created in `backups/`
1. Run `make restore-test` — show the restore verification and boot-test output

---

## Documentation

| Document                                     | Contents                                           |
| -------------------------------------------- | -------------------------------------------------- |
| [docs/architecture.md](docs/architecture.md) | Components, storage, networking, persistence       |
| [docs/runbook.md](docs/runbook.md)           | Start, stop, backup, restore, update, troubleshoot |
| [docs/security.md](docs/security.md)         | Auth model, exposure scope, baseline compliance    |
| [docs/decisions.md](docs/decisions.md)       | Every meaningful decision and why                  |

---

## Program Context

This project is Stage 1, Project 2 of a 20-project homelab program across
two sessions on a MacBook M2.

Session 1 narrative: I can self-host real, useful applications responsibly.

Next project: homelab-vaultwarden — Bitwarden-compatible password manager,
localhost-first setup.
