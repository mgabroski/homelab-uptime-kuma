# homelab-uptime-kuma — Decisions

Every meaningful decision made during this project, with the reason.
Decisions are numbered sequentially. HQ-level decisions are referenced
but not duplicated here — see HQ-DECISIONS.md in the HQ project.

---

## Decision 001 — Image version: louislam/uptime-kuma:1.23.13

**Date:** 2026-05-12
**Status:** Confirmed — conservative v1 tag, pull verification required in Step 6

1.23.13 is a verified stable v1 tag selected intentionally for conservative
Session 1 deployment. Uptime Kuma v2 is the current recommended upstream
line, but this project stays on v1 until a deliberate migration decision is
made. Keeping v1 avoids turning Project 2 into a migration exercise and
maintains a stable first monitoring layer throughout Session 1.

Tag 1.23.11 was initially considered but had known Docker Hub availability
issues (ref: upstream issue #4890). 1.23.13 was selected because it is a
verified pullable v1 tag with ARM64 multi-arch support.

A v2 migration can be treated as a deliberate version decision in a later
project. When that decision is made, update both `docker-compose.yml` and
the `IMAGE_VERSION` variable in the Makefile together, document the
migration rationale here, and verify monitor and data integrity after
the first boot on v2.

**Step 6 verification required:**

```bash
docker compose pull
docker image inspect louislam/uptime-kuma:1.23.13 >/dev/null && echo "tag verified"
```

Check <https://github.com/louislam/uptime-kuma/releases> before any
future update.

---

## Decision 002 — No deploy-time secrets required

**Date:** 2026-05-12
**Status:** Confirmed

Uptime Kuma creates its admin account interactively on first login via
the web UI. No credentials need to be injected at container start time.
`.env.example` is committed as a placeholder per program standard, with
a comment documenting this decision explicitly rather than leaving the
file absent without explanation.

---

## Decision 003 — Monitor Portainer via internal Docker hostname

**Date:** 2026-05-12
**Status:** Confirmed

The Portainer monitor is configured with URL `http://homelab-portainer:9000`
rather than `http://localhost:9000` or an IP address. This is the correct
pattern — Docker's internal DNS resolves container names within a shared
network. Using localhost would resolve to the Uptime Kuma container itself,
not the host. Using an IP is fragile and breaks when containers are recreated.
Both containers must be on `homelab-internal` for this to work.

**Step 6 verification:**

```bash
docker run --rm --network homelab-internal alpine sh -c \
  'apk add --no-cache curl >/dev/null && curl -I http://homelab-portainer:9000'
```

---

## Decision 004 — HTTP monitor type for Portainer (not TCP)

**Date:** 2026-05-12
**Status:** Confirmed

The Portainer monitor uses HTTP type rather than TCP ping. HTTP validation
checks that the service returns an expected response code (200), not just
that the port is open. A port can be open while the service is in a broken
state — HTTP monitoring catches this where TCP cannot.

---

## Decision 005 — homelab-internal network declared external

**Date:** 2026-05-12
**Status:** Confirmed

Follows HQ-001. The network is declared `external: true` and must be
created manually before `docker compose up`. This ensures the network
name is exactly `homelab-internal` with no Docker Compose prefix, matching
the network that `homelab-portainer` already joined.

---

## Decision 006 — homelab-uptime-kuma-data volume declared external

**Date:** 2026-05-12
**Status:** Confirmed

Follows HQ-001. The volume is declared `external: true` and must be
created manually before `docker compose up`. This ensures the volume
name is exactly `homelab-uptime-kuma-data` with no Docker Compose prefix,
consistent with NAMING-CONVENTIONS.md Section 6.

---

## Decision 007 — MFA required at first login

**Date:** 2026-05-12
**Status:** Required operator action — not considered complete until verified in Step 6

Uptime Kuma supports TOTP-based MFA. It must be enabled immediately
after creating the admin account on first login. Navigate to Settings →
Security → Two Factor Authentication.

This is a required action, not an automated configuration. The security
doc marks it as pending verification until Step 6 confirms it has been
enabled and tested with logout and re-login. Recovery codes must be stored
outside the repository.

**Update this decision after Step 6 to record:**

```md
**Status:** Verified — [date]
MFA was enabled for the admin account and verified by logout/re-login.
Recovery codes stored outside the repository.
```

---

## Decision 008 — Port 3001 bound to 127.0.0.1

**Date:** 2026-05-12
**Status:** Confirmed — temporary until Project 4

Port 3001 is bound to `127.0.0.1` only. This is consistent with the
localhost-first default defined in SECURITY-BASELINE.md Section 3. LAN
exposure via Caddy at `uptime.local` is activated in Project 4.

---

## Decision 009 — No Docker socket mount

**Date:** 2026-05-12
**Status:** Confirmed

Uptime Kuma does not require access to the host Docker daemon. Unlike
Portainer, no socket mount is needed or present. Omitting it reduces
the container's host access to the minimum required — consistent with
the least-privilege principle in SECURITY-BASELINE.md Section 4.

**Step 6 verification:**

```bash
docker inspect homelab-uptime-kuma --format '{{json .Mounts}}'
```

Expected: only the data volume mount — no socket entry.

---

## Decision 010 — SQLite embedded, no separate database container

**Date:** 2026-05-12
**Status:** Confirmed

Uptime Kuma embeds SQLite for its data store. No separate database
container is required. This keeps the deployment simple and the
single-container pattern clean. At homelab scale, SQLite is appropriate.
At production scale, this would be replaced by a shared database cluster
with HA configuration.

SQLite backup consistency is addressed by stopping the service before
archiving the volume (see Decision 011).

---

## Decision 011 — Backup uses stop-copy-start pattern for SQLite safety

**Date:** 2026-05-12
**Status:** Confirmed

The Makefile backup target stops the container before archiving the
volume and restarts after — using a shell trap to guarantee the restart
happens even if the archive operation fails. This ensures SQLite is not
mid-write during the tar operation, which would produce a backup that
exists but may not restore cleanly. The downtime is brief — typically
under 10 seconds.

The trap pattern (`trap '...' EXIT`) is used so that `docker compose start`
is always called when the shell block exits, regardless of whether the
tar command succeeded or failed. Backup failure is acceptable. Backup
failure that leaves the monitoring service down is not.

---

## Decision 012 — Container user verification deferred to Step 6

**Date:** 2026-05-12
**Status:** Pending Step 6 hardening

The compose file does not force a specific container user via `user:`
directive. Whether Uptime Kuma runs as root or non-root internally
depends on the upstream image configuration. This must be verified
during Step 6 with `docker exec homelab-uptime-kuma id`.

No claim about container user is made before this is proven.

**Update this decision after Step 6 to record:**

```md
**Status:** Verified — [date]
Result: [actual output of docker exec homelab-uptime-kuma id]
Risk acceptance: [short explanation if root, or confirmation if non-root]
```

---

## Decision 013 — security_opt no-new-privileges:true added

**Date:** 2026-05-12
**Status:** Confirmed

`no-new-privileges:true` is added to the compose service definition.
This prevents any process inside the container from gaining new
privileges via setuid, setgid, or filesystem capabilities. It is a
low-risk, high-value hardening addition that requires no testing beyond
verifying the service starts and the UI is accessible after `make up`.

---

## Decision 014 — Compose healthcheck added

**Date:** 2026-05-12
**Status:** Confirmed — operator verification required after first run

A Docker Compose `healthcheck` is committed for Uptime Kuma. The check uses
Node, which is already required by the Uptime Kuma image, to perform an
internal HTTP request against `http://127.0.0.1:3001`. This avoids depending
on curl or wget being installed inside the container.

The healthcheck does not replace the full hardening pass. It gives Docker a
clear runtime signal, while `make verify-runtime` confirms container health,
localhost-only binding, HTTP response, and absence of Docker socket mounts.

**Step 6 verification required:**

```bash
docker inspect homelab-uptime-kuma --format '{{.State.Health.Status}}'
make verify-runtime
```

Expected result: health status becomes `healthy`, and `make verify-runtime`
prints `Runtime verification PASSED`.

---

## Decision 015 — Yamllint configuration committed

**Date:** 2026-05-12
**Status:** Confirmed

A project-level `.yamllint.yml` is committed because lint-staged runs
`yamllint` on YAML files. Without an explicit config, local environments can
produce noisy or inconsistent YAML lint results. The project disables only
`document-start` and `line-length`; both are intentional for readable Docker
Compose and tooling configuration files.

---

## Decision 016 — Root-level first-run helper removed from committed ZIP

**Date:** 2026-05-12
**Status:** Confirmed

`FIRST-RUN.md` is removed from the final project ZIP. It was useful as a
temporary setup note, but the project standards prefer a clean root and the
runbook already owns operational setup instructions. Keeping first-run steps
in `docs/runbook.md` avoids duplication and prevents stale setup notes.

---

## Decision 017 — Architecture diagram generated, screenshots remain real-only

**Date:** 2026-05-12
**Status:** Confirmed

The final ZIP includes `docs/assets/architecture-diagram.png` so the repo has
a real architecture asset from the first commit. Runtime screenshots are not
fabricated. They must be captured from the real Uptime Kuma dashboard after
`make up`, first login, MFA setup, and Portainer monitor creation.

---

## Exceptions Carried Forward

| Exception                       | DOD Criterion | Resolution Project |
| ------------------------------- | ------------- | ------------------ |
| No Caddy routing                | 1.6           | Project 4          |
| HTTP only                       | security.md   | Project 4          |
| Container user not yet verified | security.md   | Step 6             |
| MFA not yet verified            | security.md   | Step 6             |

---

## Decision 018 — Validation auto-formats before linting

**Date:** 2026-05-12
**Status:** Confirmed

`make validate` intentionally runs Prettier in write mode before yamllint and
markdownlint. This keeps a brand-new project smooth to commit: formatting is
fixed automatically, then semantic lint checks run on the normalized files.

For CI-style checks that must not modify files, use:

```bash
make validate-check
```

The pre-commit hook still uses lint-staged with `--concurrent false` so
Prettier runs before yamllint and markdownlint on staged files. This prevents
formatting drift while keeping the commit workflow fast and predictable.

---

## Decision 019 — Yarn lockfile treated as a local tooling artifact

**Date:** 2026-05-12
**Status:** Accepted

`yarn install` generates `yarn.lock` locally, but this repository does not commit it.
The project is a Docker Compose and documentation repository, not an application package.
The direct tool versions are pinned explicitly in `package.json`, and the lockfile is treated
as local machine state rather than project source.

**Impact:**

- `yarn.lock` is excluded from release ZIP packages.
- `yarn.lock` is listed in `.gitignore`.
- Developers can regenerate it with `yarn install` when preparing local tooling.

---

## Decision 020 — Tooling ignores generated dependency folders

**Date:** 2026-05-12
**Status:** Confirmed

Prettier, markdownlint, and yamllint ignore generated dependency folders and local
artifacts such as `node_modules/`, `.yarn/`, `backups/`, and `yarn.lock`.
Validation should check committed project files, not third-party package metadata
or generated local installation output.

This prevents false failures such as yamllint scanning YAML files inside
`node_modules/`. Project YAML validation is intentionally scoped to committed
root-level YAML files listed in the Makefile.

---

## Decision 021 — TypeScript peer dependencies are satisfied explicitly

**Date:** 2026-05-12
**Status:** Confirmed

The tooling stack can load JavaScript or TypeScript configuration files through
transitive config loaders. Even though this repository does not contain TypeScript
source code, Yarn reports peer dependency warnings unless `typescript` and
`@types/node` are present.

The project includes both packages as pinned development dependencies so
`yarn install` stays clean without unsupported Yarn configuration or warning
suppression. They are tooling-only dependencies and do not affect the Docker
Compose deployment.

---
