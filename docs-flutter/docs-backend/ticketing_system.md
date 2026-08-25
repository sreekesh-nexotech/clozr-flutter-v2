# Ticketing system — mobile integration guide

**Audience:** the mobile app team wiring in-app problem reporting.
**Endpoint:** `POST /api/v1/support/report/` — live and verified.
**Backend contract:** [`support-report.md`](support-report.md) (backend repo, `docs/apis/`).
**Web reference implementation:** `src/features/techSupport/`.

Every fact in this doc was verified live against the dev backend on 2026-08-13
(tenant *Acme Corp* → provider *Nexotech Solutions*). Where behaviour differs from
what you'd guess, it's called out.

---

## 0. The 60-second version

A user hits a problem in your app, types what happened, and taps send. A ticket appears
in **Clozr's own helpdesk workspace** — not the user's. You call one authenticated
endpoint with a subject, a description, and a bag of diagnostics. You get back a ticket
reference to show them.

```http
POST /api/v1/support/report/
Authorization: Bearer <the user's JWT>
Content-Type: application/json
```
```jsonc
{ "subject": "Tickets list won't load",
  "description": "…the user's own words…",
  "priority": "Medium",
  "context": { "screen": "TicketsList", "platform": "android", "app_version": "2.4.0 (312)" } }
```
```jsonc
// 202 Accepted
{ "reference": "TKT-0042", "issue_id": "4efc137f-…" }
```

That's the whole integration. The rest of this doc is edge cases.

---

## 1. What you do NOT need

Read this before you start, because it removes work you might otherwise plan for.

| Not needed | Why |
| :--- | :--- |
| **A webhook key or API key** | The server holds it. There is no key in the app, no key in your `.env`, nothing to ship, rotate, or leak. |
| **HMAC / request signing** | The endpoint authenticates with the user's ordinary JWT. |
| **A "who is this" field** | Identity comes from the JWT — see §4. Sending it does nothing. |
| **A separate support login** | Uses the session the user already has. |
| **Special handling when the user is blocked** | The endpoint is exempt from all three gates — see §6. |

> ### ⚠️ If someone hands you a webhook key, don't use it
> There is a public intake at `/webhooks/issues/{key_id}/`, and it is tempting to call it
> directly. **Don't.** It authenticates by `Origin` header or HMAC signature — the first is
> meaningless from a mobile app, and the second would require shipping a signing secret
> inside your binary, where anyone can extract it. A leaked key lets anyone file tickets
> into the provider's helpdesk as any tenant they like, and there's one shared key, so
> rotating it breaks every client at once. The endpoint in this doc exists precisely so no
> client ever holds that key.

---

## 2. Request

### Fields

| Field | Type | Required | Notes |
| :--- | :--- | :---: | :--- |
| `subject` | string, ≤280 | ✅ | Non-blank. Whitespace-only is rejected. |
| `description` | string | ✅ | Non-blank. The user's own words. |
| `priority` | enum | — | `Low` \| `Medium` \| `High` \| `Critical`. **Capitalised exactly.** Defaults to `Medium` when omitted. |
| `context` | object | — | Diagnostics. Free-form, see below. Omit it entirely and the report still files. |

> **`Urgent` is not a priority.** The four values above are the whole set — `"Urgent"`
> returns `400 invalid_choice`. If your UI says "Urgent", map it to `Critical`.

### `context` — free-form, and that's deliberate

**Any keys you like.** They are not validated against a schema; each lands on the ticket as
`form.<your_key>`. The web app sends `route`/`server_detail`/`app_version`/`user_agent`
because that's what a browser knows. **Send mobile-shaped keys instead** — verified working:

```jsonc
"context": {
  "screen":       "TicketsList",       // where they were, your navigation's name for it
  "platform":     "android",           // android | ios
  "os_version":   "14",
  "device_model": "Pixel 7",
  "app_version":  "2.4.0 (312)",       // include the build number
  "network":      "wifi",              // wifi | cellular | offline — explains timeouts
  "server_detail": "500 on GET /crm/issues/"   // when a failed request prompted this
}
```

Suggested additions a mobile app has and the web doesn't: `locale`, `timezone`,
`free_disk_mb`, `session_id`, and — if you have one — your crash reporter's `trace_id`.
That last one is the single most useful field you can send.

**Limits** (all verified):

- **At most 25 keys.** 26+ → `400 {"context": ["At most 25 context keys are allowed."]}`.
  This is a hard rejection, not a truncation, so don't dump an unbounded state object.
- Values are coerced to strings and **truncated to 2000 chars** silently.
- Key names truncate to 64 chars.

---

## 3. Responses

| Status | `code` | What to do |
| :--- | :--- | :--- |
| **202** | — | Filed. Show `reference` as their ticket number. |
| **400** | — | Validation. DRF field errors — render them against the fields. |
| **401** | — | Not authenticated. Refresh the token or send them to login. |
| **429** | — | Throttled — **10/min per user**. Back off; do **not** auto-retry. |
| **502** | `support_report_failed` | The ticket write failed. Offer the email fallback. |
| **503** | `support_not_configured` | Server-side misconfiguration. Same fallback. |

### Error body shape

```jsonc
// 400
{ "code": 400, "message": "Validation Error",
  "errors": { "subject": ["This field may not be blank."] },
  "error_codes": { "priority": ["invalid_choice"] } }   // present on some errors

// 502 / 503
{ "detail": "Support reporting is not configured on this server.",
  "code": "support_not_configured" }
```

Note the two shapes differ: a `400` carries `errors`, while `502`/`503` carry `detail` +
a string `code`. Branch on the **string** `code` for the latter — on a `400` the `code`
field is the integer `400`, which is a status echo, not a machine code.

### Three rules for handling failures

1. **Never clear the user's typed text on failure.** They wrote it to send it; wiping the
   field throws away the only thing of value. Web keeps it on screen and lets them retry.
2. **Never auto-retry.** The throttle exists because an error-boundary retry loop can
   flood the provider's helpdesk. On `429`, tell the user to wait a minute.
3. **Keep an email fallback** (`support@clozr.io`) for `502`/`503`. Both mean the report
   never reached the helpdesk, and the user should not be left with a dead end.

The web app collapses `502` and `503` into one message naming the mailbox, because the
distinction is an operator concern the user can do nothing about. Recommend the same.

---

## 4. Identity is server-resolved — you cannot set it

The reporter is read from the JWT and merged **last**, overwriting anything you send.
These land on the ticket automatically:

`form.reporter_user_id` · `form.reporter_email` · `form.reporter_name` ·
`form.tenant_org_id` · `form.tenant_org_name`

**Verified:** a request whose `context` claimed `reporter_email: attacker@evil.com` and
`tenant_org_name: Evil Inc` produced a ticket with the real JWT-derived values. This is
the security property of the endpoint — so don't bother sending identity fields, and don't
build a UI that asks the user for their email.

---

## 5. What the user should see

The web implementation, for parity:

**Two entry points.** A dedicated **Tech Support** screen (deliberate reporting: subject +
description + priority), and an inline **"Report this"** form on any error state (reactive:
the app names the failure, the user just describes it). Both post the same body.

**On the error path, don't offer to report everything.** Web gates the "Report this" action
on the failure being *ours* — a `5xx` only. A permissions error or a validation failure is
the system working as designed, and escalating those files support tickets about healthy
software and buries the real outages. Offering it on a `403` also tells the user something
is broken when it isn't.

**On the error path, don't ask for a priority.** Someone reporting a broken screen is
describing a fault, not triaging it. Web sends `Medium` and only shows the picker on the
deliberate Tech Support screen.

**On success**, show `reference` (e.g. "TKT-0042") and let them copy it.

---

## 6. It works when the rest of the app doesn't

The endpoint is exempt from all three middleware gates — mandate, suspended-write, and
mandatory-course. This is the point, not a footnote: those gates `403` every business
endpoint, and the support form is shown *precisely* to users stuck behind them.

**So: if your app has a blocking gate screen, put a "Contact support" action on it, and
wire it to this endpoint.** It will work even while every other call is returning `403`.
Verified — a mandate-blocked user gets `403` on `/crm/leads/` and `202` here.

Also: **no CRM permission is required**, only authentication. A role-less user who can see
nothing anywhere can still tell you the product is broken.

---

## 7. Not available

- **There is no "my submitted reports" list.** `GET /api/v1/support/report/` does not
  exist. The tickets live in the provider's workspace, which a tenant session cannot read
  — exposing them needs a purpose-built reporter-scoped endpoint that hasn't been built.
  **Don't design a history screen around this.** If you want one, it needs a backend ask
  first ([`support-report.md`](support-report.md) §6).
- **No attachments or screenshots.** The endpoint takes JSON only. A screenshot would need
  a separate upload; not built.
- **No SLA on these tickets.** They arrive unlinked to a customer, so no deadline is
  computed. Don't promise the user a response time.

---

## 8. Checklist

- [ ] `POST /api/v1/support/report/` with the user's existing Bearer token
- [ ] `subject` (≤280, non-blank) + `description` (non-blank) validated client-side first
- [ ] `priority` from the four capitalised values, or omitted for `Medium`
- [ ] `context` with mobile diagnostics — **≤25 keys** — incl. crash `trace_id` if you have one
- [ ] `202` → show `reference`; typed text cleared only on success
- [ ] `400` → field errors; `429` → back off, no auto-retry; `502`/`503` → email fallback
- [ ] Failure never clears the user's text
- [ ] "Report this" offered on `5xx` only, not on `403`/validation
- [ ] "Contact support" reachable from any blocking gate screen (§6)
- [ ] No history screen, no attachment picker, no identity fields (§4, §7)

---

## 9. Verified behaviour

Live against dev, 2026-08-13, `admin@seed.acme.com` (Acme Corp → Nexotech Solutions):

| Case | Result |
| :--- | :--- |
| Happy path | `202 {reference:"TKT-0001", issue_id:…}` |
| Cross-tenant write | Ticket in provider org; reporter's org recorded in `custom_fields` |
| Mobile-shaped `context` | ✅ all of `screen`/`platform`/`os_version`/`device_model`/`network` stored as `form.*` |
| Identity spoofing via `context` | ✅ **overwritten** with JWT values |
| `priority` omitted | Defaults to `Medium` |
| `priority: "Urgent"` | `400 invalid_choice` |
| `subject` 281 chars | `400 no more than 280 characters` |
| Blank `subject` | `400 may not be blank` |
| 26 `context` keys | `400 At most 25 context keys are allowed.` |
| No `context` at all | `202` — it's optional |
| Unauthenticated | `401` |
| 11 requests in a minute | `429` |

Ticket shape: `channel: "api"`, `reported_for: "self"`, status = the key's default
(`Open`), `customer` and `raised_by` both `null`.
