# homelab-uptime-kuma — Security

This document covers the security posture of the Uptime Kuma deployment.
All decisions reference SECURITY-BASELINE.md which defines the minimum
security standard for every project in this program.

---

## Auth Model

| Item        | Detail                                                                                                                                                           |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mechanism   | Built-in username and password — created by operator on first login                                                                                              |
| First login | Browser navigates to `http://localhost:3001` — UI forces account creation before any content is accessible                                                       |
| Username    | Chosen by operator at first login — no default username                                                                                                          |
| Password    | Chosen by operator — minimum 16 characters recommended                                                                                                           |
| Session     | JWT-based, managed internally by Uptime Kuma                                                                                                                     |
| MFA         | Available — TOTP-based. Required operator action: must be enabled during first-login hardening and verified in Step 6 before this control is considered complete |

---

## Default Credentials

None. Uptime Kuma ships with no factory-set credentials. The operator
creates the sole admin account on first visit to the UI. The risk window
is the gap between container start and first login — during that period,
anyone on localhost who reaches port 3001 could claim the admin account.

**Required action:** Navigate to `http://localhost:3001` and complete
first-login setup immediately after `make up`. Do not defer this step.
This is documented as a mandatory step in docs/runbook.md.

---

## Network Exposure

| Port | Bound To  | Scope          | Reason                                         |
| ---- | --------- | -------------- | ---------------------------------------------- |
| 3001 | 127.0.0.1 | Localhost only | Pre-Caddy — LAN exposure deferred to Project 4 |

No other ports are exposed to the host. Container-to-container
communication with Portainer occurs entirely inside `homelab-internal`
— no host port is needed or exposed for that path.

---

## Container Privilege Level

| Item                 | Detail                                                                                                                                                                 |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Privileged mode      | Not used                                                                                                                                                               |
| Container user       | Pending Step 6 verification. The compose file does not force a specific user. `docker exec homelab-uptime-kuma id` must be run and result documented during hardening. |
| Capability additions | None                                                                                                                                                                   |
| Privilege escalation | Blocked via `security_opt: no-new-privileges:true`                                                                                                                     |
| Healthcheck          | Internal HTTP healthcheck implemented in Docker Compose                                                                                                                |
| Special mounts       | None — no Docker socket, no host filesystem access                                                                                                                     |

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
| Command  | `make update`                                                                                                          |
| Never    | Use `latest` tag in committed compose config                                                                           |

---

## HTTPS

Currently HTTP only. Access is restricted to localhost, which reduces
the risk of this exception. HTTPS will be enforced when Caddy routes
the service via `uptime.local` in Project 4. This exception is documented
as DOD criterion 1.6 exception with resolution target Project 4.

---

## Security Control Status

This table clearly separates what is enforced by configuration, what
requires operator action, and what is intentionally deferred.

| Control                      | Status                         | Source of Enforcement                                             |
| ---------------------------- | ------------------------------ | ----------------------------------------------------------------- |
| Localhost-only binding       | ✅ Implemented                 | `docker-compose.yml` ports binding                                |
| No Docker socket             | ✅ Implemented                 | Absence in `docker-compose.yml` — verified in Step 6              |
| No deploy-time secrets       | ✅ Implemented                 | Service model — `.env.example` documents this                     |
| Privilege escalation blocked | ✅ Implemented                 | `security_opt: no-new-privileges:true`                            |
| Docker healthcheck           | ✅ Implemented                 | Internal Node HTTP check in `docker-compose.yml`                  |
| First admin account          | ⚠️ Operator action required    | Uptime Kuma first-login UI — complete immediately after `make up` |
| MFA                          | ⚠️ Operator action required    | Uptime Kuma UI — enable and verify in Step 6                      |
| Container runtime user       | ⏳ Pending Step 6 verification | Run `docker exec homelab-uptime-kuma id` and document result      |
| Backup restore proof         | ⏳ Pending Step 6 verification | Run `make restore-test` — must boot successfully                  |
| HTTPS                        | 🔜 Deferred                    | Project 4 Caddy — accepted while localhost-only                   |

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

| Baseline Area      | Status                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Secret handling    | ✅ No deploy-time secrets — documented explicitly                                                                                          |
| Authentication     | ✅ No default credentials — first-login flow forces account creation                                                                       |
| Network exposure   | ✅ Localhost only, 127.0.0.1 binding                                                                                                       |
| Container security | ✅ No socket mount, no privileged mode, privilege escalation blocked, healthcheck implemented. Container user pending Step 6 verification. |
| Data protection    | ✅ Named external volume. Backup and restore proof required in Step 6.                                                                     |
| Update strategy    | ✅ Manual with pinned version, documented in decisions                                                                                     |
| HTTPS              | ⚠️ Exception — HTTP only until Project 4, localhost-only scope accepted                                                                    |
| MFA                | ⚠️ Required operator action — must be enabled and verified in Step 6                                                                       |
