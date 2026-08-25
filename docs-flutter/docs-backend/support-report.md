# In-app Tech Support reporting

Backend contract for **Workspace → Tech Support** (`/support`) and the
"Report this" form inside every `ErrorNotice`. Answers `TS1` in
[operations-backend-requests.md](operations-backend-requests.md).

A tenant's user files a report; the ticket appears in the **provider's own
helpdesk workspace** as an ordinary `Issue`, so the provider triages product
complaints with the same Helpdesk screens documented in
[helpdesk.md](helpdesk.md).

Source of truth: `support/views.py`, `support/serializers.py`,
`support/services.py`, route in `nexocrm/urls.py`.

---

## 1 — The endpoint

```http
POST /api/v1/support/report/
Authorization: Bearer <JWT>
Content-Type: application/json
```

```jsonc
{
  "subject": "Helpdesk → Tickets failed to load",   // required, ≤280, non-blank
  "description": "…the user's own words…",          // required, non-blank
  "priority": "Medium",                             // Low|Medium|High|Critical, default Medium
  "context": {                                      // optional diagnostics
    "route": "/helpdesk/tickets",
    "server_detail": "…",
    "app_version": "…",
    "user_agent": "…"
  }
}
```

```jsonc
// 202 Accepted
{ "reference": "TKT-0042", "issue_id": "…uuid" }
```

`reference` is the provider org's `TKT-` sequence, generated in `Issue.save()`.
Show it to the user as their ticket number.

### Status codes

| Status | Body `code` | Meaning |
| :--- | :--- | :--- |
| `202` | — | Filed. `reference` + `issue_id` returned. |
| `400` | — | Validation. DRF field errors (blank subject/description, bad `priority`, oversized `context`). |
| `401`/`403` | — | Not authenticated. |
| `429` | — | Throttled — 10/min per user (see §4). |
| `502` | `support_report_failed` | The ticket could not be created. Fall back to the `support@clozr.io` mailbox. |
| `503` | `support_not_configured` | `SUPPORT_ISSUE_WEBHOOK_KEY_ID` unset or names a revoked key. Same fallback. |

The read-back endpoint (`GET /support/report/`, "my submitted reports") is
**not implemented** — see §6.

---

## 2 — Why this is a proxy, not a direct webhook call

The frontend's own analysis (TS1) is correct and is what this implements. A Vite
bundle is public, so a webhook `key_id` shipped in `VITE_*` is public too:

* **HMAC is impossible in the browser** — signing client-side ships the signing
  secret to every visitor.
* **The `Origin` check is not authentication** — trivially forged by anything
  that isn't a browser, so anyone with devtools could file tickets into the
  provider workspace, attributed to any tenant they like.

So the browser calls **our** authenticated API and the **server** holds the key.
The reporter's identity is read from the JWT and **cannot be supplied in the
body** — that is the whole security property of this endpoint.

### Transport: direct service call, not an HTTP self-call

TS1 proposed forwarding over HTTP to our own `/webhooks/issues/{key_id}/` with
HMAC. This implementation instead calls `create_issue_from_intake()`
**in-process**. Same code path, same resulting ticket, but:

* no gunicorn thread blocks waiting on another gunicorn thread (we run 4 workers
  × 4 threads — self-calls risk deadlock under load);
* the per-IP rate limiter is not applied against our own server's address;
* no base-URL configuration, no TLS hop, no HMAC round-trip to ourselves.

The public webhook view remains the only *untrusted* entrypoint. This path is
already authenticated, so re-running that defence stack would be redundant.

---

## 3 — What the ticket looks like in the provider workspace

| Field | Value |
| :--- | :--- |
| `organization` | the **provider's** org (from the configured key) — never the caller's |
| `channel` | `"api"` |
| `reported_for` | `"self"` — the reporter hit the problem themselves |
| `subject` / `description` / `priority` | from the body |
| `issue_type`, `status`, `assigned_to`, `assigned_team` | the key's configured defaults |
| `status` fallback | the provider org's `is_default` `IssueStatus` when the key sets none |
| `customer` | **null** — see §5 |
| `raised_by` | **null** — the reporter is not a `User` in the provider's org |
| `custom_fields` | `form.*` — diagnostics + server-resolved identity (below) |

### Identity in `custom_fields`

Resolved server-side from the JWT and merged **last**, so a caller cannot
overwrite them by putting the same keys in `context`:

| Key | Source |
| :--- | :--- |
| `form.reporter_user_id` | `request.user.user_id` |
| `form.reporter_email` | `request.user.email` |
| `form.reporter_name` | `request.user.get_full_name()` |
| `form.tenant_org_id` | `request.org.organization_id` |
| `form.tenant_org_name` | `request.org.name` |

Everything in `context` lands as `form.<key>`. Values are coerced to strings and
truncated to 2000 chars; at most 25 keys, key names truncated to 64 chars. Over
25 keys is a `400` (a client bug worth surfacing); long values truncate silently.

> Because `Issue` has no `CustomFieldDefinition` layer (helpdesk.md known gap
> #5), these are freeform JSON — visible on the ticket detail, but **not**
> filter facets. Triage by `issue_type`/`priority`, not by reporter.

---

## 4 — Gates, permissions, throttling

**No CRM permission is required** — only `IsAuthenticated`. Reporting a broken
screen is not a CRM capability, and a role-less user (who sees nothing anywhere,
per helpdesk.md §1) must still be able to tell us the product is broken.

**Exempt from all three middleware gates.** This is required, not incidental:

| Gate | Where | Why exempt |
| :--- | :--- | :--- |
| Razorpay mandate | `organizations/middleware.py` | 403s every business endpoint until the mandate is signed — and the support form is shown *precisely* to users stuck there. |
| Suspended-write | same tuple, same file | A suspended org must still be able to ask for help paying. |
| Mandatory course | `lms/middleware.py` | A learner locked out by an incomplete course must be able to report that the LMS itself is broken. |

Exempting this path grants a blocked org **no** access to its own CRM data: the
endpoint writes one row into the *provider's* workspace and returns two fields.

**Throttle:** `10/min` per user (`ScopedRateThrottle`, scope `support_report`),
so an error boundary retrying in a loop cannot flood the provider's helpdesk.
`ScopedRateThrottle` is registered globally but applies only to views declaring
a `throttle_scope` — currently just this one.

---

## 5 — Known limitation: no SLA

Support tickets arrive **unlinked to a `Customer`**, so the SLA snapshot never
fires (it keys off the real `customer` FK — helpdesk.md §8). The ticket has
`sla_deadline: null`, so it lands in SLA Watch's `on_track` bucket and can never
breach.

This is a deliberate product decision, not a bug. The provider **links the
customer manually** during triage if the ticket warrants an SLA.

> ⚠️ Setting `customer` on an existing ticket does **not** retroactively compute
> `sla_deadline` — the snapshot runs only in the create path. A manually linked
> ticket still has no SLA clock. If support reports need one, the fix is either
> SLA defaults on `IssueWebhookKey` (applies to all webhook tickets) or
> recomputing the snapshot when `customer` transitions from null.

`IssueWebhookKey.default_customer` (helpdesk.md §15) does **not** help here: all
support reports arrive through one shared provider key, so pinning would
attribute every tenant's report to a single customer. That field exists for
*tenants* issuing one key per customer portal. The provider maps the reporter
manually, using `form.tenant_org_id` / `form.reporter_email` from
`custom_fields`.

---

## 6 — Not built: reading back my reports

`GET /api/v1/support/report/` is **not implemented**, matching TS1's own note
that the page ships without it.

It cannot be a loosened filter on an existing endpoint: the tickets live in the
provider's org, and every CRM read is org-scoped by both the thread-local tenant
context and explicit `organization=` filtering. Exposing them to a tenant
session needs a purpose-built, reporter-scoped read that matches on
`custom_fields["form.reporter_user_id"]` and returns a deliberately narrow
projection (reference, subject, status name, created_at) — never the full
`IssueSerializer`, which would leak the provider's internal assignees, notes and
audit trail.

---

## 7 — Configuration

```bash
# .env — key_id of the IssueWebhookKey in the PROVIDER's workspace
SUPPORT_ISSUE_WEBHOOK_KEY_ID=<uuid>
```

Create the key in the provider's own org via
`POST /api/v1/crm/issue-webhook-keys/` (helpdesk.md §15) and put its `key_id`
here. The plaintext `secret` is **not** needed — the in-process call does not
authenticate against itself; only the `key_id` is read, to resolve the target
org and the ticket defaults.

Set `default_issue_type` / `default_status` / `default_assigned_team` on that key
to route incoming product reports straight to the right queue.

The key resolves through the same 60s cache as the public webhook, so rotating
or revoking it takes effect within a minute with no redeploy. Unset (the
default) → every report gets `503 support_not_configured`, logged at ERROR.
Leaving it unset in production silently drops every report, so treat that log
line as an alert.

---

## 8 — Tenant-context isolation (implementation note)

This is the one place in the codebase where a request writes a row into a tenant
**other than the caller's**, so the context switch is handled explicitly.

`create_issue_from_intake` switches both tenant mechanisms to the provider org
and does not restore them — correct for the public webhook, which bypasses
`OrganizationMiddleware` entirely, but wrong mid-request. Two distinct leaks:

1. **Thread-local** — the service's `finally` sets it to `None`, which would
   leave `TenantAwareManager` unfiltered for the rest of the request.
2. **Postgres RLS GUC** — `set_rls_org` uses `set_config(..., is_local=true)`,
   which is *transaction*-scoped. The service's `transaction.atomic()` is a
   **nested** block (a savepoint) inside the transaction opened by
   `OrganizationMiddleware.__call__`, **not** a new transaction — so exiting it
   does not restore the GUC. Verified empirically.

`support/services.py` snapshots both before the call and restores them in a
`finally`. `support/tests/test_support_report.py::
test_caller_org_context_is_restored_after_filing` asserts both directly and
fails on the unguarded version.

---

Tests: `support/tests/test_support_report.py`.
