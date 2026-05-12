# homelab-uptime-kuma — Security

This document covers the security posture of the Uptime Kuma deployment.
All decisions reference SECURITY-BASELINE.md which defines the minimum
security standard for every project in this program.

---

## Auth Model

| Item        | Detail                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| Mechanism   | Built-in username and password — created by operator on first login                                                       |
| First login | Browser navigates to `http://localhost:3001` — UI forces account creation before any content is accessible                |
| Username    | Chosen by operator at first login — no default username                                                                   |
| Password    | Chosen by operator — minimum 16 characters recommended                                                                    |
| Session     | JWT-based, managed internally by Uptime Kuma                                                                              |
| MFA         | ✅ Enabled and verified — TOTP configured, logout/re-login confirms code is required. Recovery codes stored off-repo. |

---

## Default Credentials

None. Uptime Kuma ships with no factory-set credentials. The operator
creates the sole admin account on first visit to the UI. The risk window
is the gap between container start and first login — during that period,
anyone on localhost who reaches port 3001 could claim the admin account.

**Completed:** Admin account created and MFA enabled immediately after
first `make up`. First-login window closed. Verified 2026-05-12.

---

## Network Exposure

| Port | Bound To  | Scope          | Reason                                         |
| ---- | --------- | -------------- | ---------------------------------------------- |
| 3001 | 127.0.0.1 | Localhost only | Pre-Caddy — LAN exposure deferred to Project 4 |

Verified with `make verify-runtime` — output confirmed `3001/tcp -> 127.0.0.1:3001`.
No other ports are exposed to the host. Container-to-container communication
with Portainer occurs entirely inside `homelab-internal` — confirmed via
incident log showing `EHOSTUNREACH 172.19.0.2:9000` on Portainer stop.

---

## Container Privilege Level

| Item                 | Detail                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------- |
| Privileged mode      | Not used                                                                                                    |
| Container user       | ✅ Verified 2026-05-12 — runs as root: `uid=0(root) gid=0(root) groups=0(root)`. Upstream image behaviour, accepted. See Decision 012. |
| Capability additions | None                                                                                                        |
| Privilege escalation | Blocked via `security_opt: no-new-privileges:true`                                                          |
| Healthcheck          | ✅ Verified healthy — `make verify-runtime` confirmed status `healthy`                                      |
| Special mounts       | ✅ Verified — no Docker socket, no host filesystem mounts. Confirmed via `make verify-runtime`.             |

---

## Secret Handling

| Item                | Detail                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------ |
| Deploy-time secrets | None required                                                                                          |
| Storage mechanism   | Not applicable at deploy time — credentials set via UI on first login                                  |
| `.env` file         | Not required for this service — `.env.example` committed with explanatory comment per program standard |
| `.env.example`      | Present — documents that no deploy-time secrets exist                                                  |
| Secrets in compose  | None                                                                                                   |

If notification channel credentials (Slack tokens, SMTP passwords, etc.)
are added via the Uptime Kuma UI in future, they are stored in the volume
only — never in any committed file.

---

## Update Strategy

| Item     | Detail                                                                                                                 |
| -------- | ---------------------------------------------------------------------------------------------------------------------- |
| Approach | Manual — version pinned in `docker-compose.yml`, updated deliberately                                                  |
| Process  | Check GitHub releases for breaking changes, update version pin, run `make update`, verify monitors and data are intact |
| Command  | `make update` — runs `make backup` first automatically                                                                 |
| Never    | Use `latest` tag in committed compose config                                                                           |

---

## HTTPS

Currently HTTP only. Access is restricted to localhost, which reduces
the risk of this exception. HTTPS will be enforced when Caddy routes
the service via `uptime.local` in Project 4. This exception is documented
as DOD criterion 1.6 exception with resolution target Project 4.

---

## Security Control Status

| Control                      | Status                      | Source of Enforcement                                              |
| ---------------------------- | --------------------------- | ------------------------------------------------------------------ |
| Localhost-only binding       | ✅ Verified                 | `docker-compose.yml` + `make verify-runtime` 2026-05-12            |
| No Docker socket             | ✅ Verified                 | `make verify-runtime` confirmed no socket mount 2026-05-12         |
| No deploy-time secrets       | ✅ Implemented              | Service model — `.env.example` documents this                      |
| Privilege escalation blocked | ✅ Implemented              | `security_opt: no-new-privileges:true`                             |
| Docker healthcheck           | ✅ Verified healthy         | `make verify-runtime` confirmed `healthy` 2026-05-12               |
| First admin account          | ✅ Completed                | Created immediately after first `make up` 2026-05-12               |
| MFA                          | ✅ Verified                 | TOTP enabled, logout/re-login confirmed 2026-05-12                 |
| Container runtime user       | ✅ Verified — root          | `uid=0(root)` — upstream behaviour, accepted. See Decision 012.    |
| Internal DNS monitoring      | ✅ Verified                 | Incident log shows `EHOSTUNREACH 172.19.0.2:9000` — correct path   |
| Backup restore proof         | ✅ Verified                 | `make restore-test` PASSED 2026-05-12                              |
| HTTPS                        | 🔜 Deferred                 | Project 4 Caddy — accepted while localhost-only                    |

---

## Never-Do List

| Never Do                                             | Reason                                                                                             |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Expose port 3001 to `0.0.0.0` before Caddy           | Opens the admin creation endpoint and authenticated UI to the LAN without HTTPS                    |
| Delay first-login account creation                   | Leaves the account creation endpoint open on localhost                                             |
| Disable MFA once configured                          | Removes a meaningful protection layer on the sole admin account                                    |
| Mount the Docker socket                              | This service has no need for host Docker access — adding it expands attack surface with no benefit |
| Store notification credentials in any committed file | Credentials belong in the Uptime Kuma UI only, persisted in the volume                             |
| Use `latest` image tag in committed compose file     | Breaks reproducibility and risks silent breaking changes                                           |

---

## Security Baseline Compliance

This project complies with SECURITY-BASELINE.md. All deviations are
documented in docs/decisions.md with written reasons and accepted risk.

| Baseline Area      | Status                                                                                                                            |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Secret handling    | ✅ No deploy-time secrets — documented explicitly                                                                                 |
| Authentication     | ✅ No default credentials, first-login completed, MFA enabled and verified                                                        |
| Network exposure   | ✅ Localhost only, 127.0.0.1 binding verified                                                                                     |
| Container security | ✅ No socket mount, no privileged mode, privilege escalation blocked, healthcheck verified healthy. Runs as root — upstream behaviour, accepted. |
| Data protection    | ✅ Named external volume, backup taken, restore-test passed                                                                       |
| Update strategy    | ✅ Manual with pinned version, backup-first update via `make update`                                                              |
| HTTPS              | ⚠️ Exception — HTTP only until Project 4, localhost-only scope accepted                                                           |
| MFA                | ✅ Enabled and verified 2026-05-12                                                                                                |
