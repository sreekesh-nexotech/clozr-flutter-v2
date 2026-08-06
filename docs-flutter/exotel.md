# Exotel — Org Telephony Integration — API Guide

Backs the **Communication → Exotel Call → Integration configuration** admin screen
(the "Exotel Call · Connected" page) plus in-CRM click-to-call and inbound-call
routing.

Exotel is the org's telephony provider. Once connected, an org can:
- **Place outbound calls** from Lead/Customer detail (click-to-call).
- **Receive inbound calls routed to the right agent** by the CRM (Programmable
  Connect passthru).
- Get every call **logged, linked to a contact, and (optionally) transcribed**.

All admin/config endpoints mount under **`/api/v1/crm/exotel/`**. Two endpoints are
**unauthenticated webhooks** and mount under **`/webhooks/exotel/`** and
**`/api/v1/crm/exotel/webhook/`** — Exotel calls those, not the frontend.

Everything is **org-scoped by the JWT** — you never pass an org id. There is exactly
**one `CRMExotelSettings` row per org**.

---

## What an org must provide to connect their account

For an org's Exotel account to be **connected and usable**, these inputs are
**required** and must be captured in the frontend. They live in **two different
tables** and therefore belong in **two different UI surfaces**.

### A. Org-level connection credentials — `CRMExotelSettings` (one row per org)

These five (plus the `enabled` toggle) are what "connects the account" and are all
validated as required when `enabled: true`. Store them via
`POST/PATCH /api/v1/crm/exotel/settings/` (§1):

| Input | Required | From (Exotel dashboard) |
|-------|----------|-------------------------|
| `account_sid` | ✅ | Account SID |
| `api_key` | ✅ | API key (Basic-Auth username) |
| `api_token` | ✅ | API token (Basic-Auth secret; write-only) |
| `subdomain` | ✅ | API subdomain (default `api.exotel.com`, or `<company>.exotel.com`) |
| `webhook_verify_token` | ✅ | Org-chosen unique secret — guards the webhooks + identifies the tenant |

`record_call` and `default_incoming_agent` are optional refinements, not connection
requirements.

### B. Per-user agent config — `CRMTelephonyAgent` (one row per calling user)

The account being connected is **not** enough to place or receive a call — each user
who calls must also be a telephony agent:

| Input | Required | Meaning |
|-------|----------|---------|
| `mobile_no` | ✅ | The phone Exotel rings first (the agent's own device) |
| `exotel_number` | ✅ | The agent's ExoPhone, used as the outbound `CallerId` |
| `exotel_enabled` | ✅ (`true`) | Must be on for the user to place/receive calls |

> ⚠️ **`exotel_number` is per-user, not an org connection field** — it does **not**
> belong in the org settings form. It lives on a **separate per-user UI** (an "Agents"
> screen) backed by `/api/v1/crm/exotel/agents/` (§5). Until a user has an enabled
> agent row, `POST /api/v1/crm/exotel/call/` and inbound routing fail for that user.

**Summary:** the org form must contain the five §A fields (settings endpoint, §1); the
per-user agent fields (§B) go on a separate Agents screen backed by the agents endpoint
(§5).

---

> **Read this first.**
> 1. **Three secrets, two directions.** `api_key` + `api_token` authenticate the CRM
>    **to** Exotel (Basic Auth, outbound). `webhook_verify_token` is the org's **own**
>    secret guarding traffic **from** Exotel → CRM; it's unique per org and doubles as
>    the tenant identifier on the webhooks (Exotel sends no JWT). See §7.
> 2. **The admin UI shown is inaccurate.** It exposes only "Exotel API key" +
>    transcription mode. The real settings model needs `account_sid`, `api_key`,
>    `api_token`, `subdomain`, `webhook_verify_token`, `record_call`, and (new)
>    `default_incoming_agent`. Transcription is a **separate** endpoint
>    (`transcription-settings/`), not part of Exotel settings. See §1, §6.
> 3. **Two UI surfaces.** Org connection credentials live on the settings form (§1);
>    per-user telephony config (`mobile_no`, `exotel_number`, `exotel_enabled`) lives
>    on a separate **Agents** screen backed by `/api/v1/crm/exotel/agents/` (§5). A
>    user without an enabled agent row gets 400 "You are not configured as a telephony
>    agent" when calling.

---

## 1. Settings — `GET/POST/PATCH/DELETE /api/v1/crm/exotel/settings/`

The org's single Exotel configuration row. Backs the integration-configuration form.

**Auth:** `HasSettingsPermission` — org admin (`is_staff`)/superuser always pass;
otherwise `view_settings` for GET, `update_settings` for writes. **Create/update/
delete additionally require org-admin** (the view rejects non-admins with 403 even
if they have `update_settings`).

**Fields**

| Field | Type | Notes |
|-------|------|-------|
| `enabled` | bool | Master on/off. When `true`, the required fields below must all be present (serializer validation). |
| `account_sid` | string | Exotel account SID (appears in API URL path). Required when enabled. |
| `api_key` | string | Basic-Auth username. Required when enabled. |
| `api_token` | string | **write-only** — Basic-Auth password/secret. Never returned. Required when enabled. |
| `has_api_token` | bool | **read-only** — whether a token is stored (so the UI can show "•••• set"). |
| `subdomain` | string | Default `api.exotel.com`; some accounts use `<company>.exotel.com`. Required when enabled. |
| `webhook_verify_token` | string | **unique across all orgs.** The `?key=` secret on both webhooks + the tenant identifier. Required when enabled. |
| `record_call` | bool | Whether Exotel records calls (default false). |
| `default_incoming_agent` | FK (agent user_id) | **new** — fallback agent to ring for an inbound call that can't be matched to a contact's owner/assignee. Nullable. |
| `created_at` / `updated_at` | datetime | read-only |

### `GET`
Returns the settings row, or **404** `{"detail": "Exotel settings not configured…"}`
if none exists yet.

### `POST` (create)
Creates the row. **400** if one already exists (`"Use PATCH to update."`). **403**
for non-admins. When `enabled: true`, missing required fields → **400** per-field
(`"This field is required when Exotel is enabled."`).

```jsonc
// POST /api/v1/crm/exotel/settings/
{
  "enabled": true,
  "account_sid": "myaccount",
  "api_key": "exo_live_abc123",
  "api_token": "shhh-secret",
  "subdomain": "myaccount.exotel.com",
  "webhook_verify_token": "a-long-random-unique-string",
  "record_call": true,
  "default_incoming_agent": "b1f2…-user-uuid"   // optional
}
// → 201; response omits api_token, includes "has_api_token": true
```

### `PATCH` (update)
Partial update. **404** if not yet created, **403** for non-admins.

### `DELETE`
Removes the row (**204**). **403** for non-admins, **404** if none.

---

## 2. Integration status — `GET /api/v1/crm/exotel/status/`

Cheap health check for the UI badge ("Connected" / "Not configured").

**Auth:** `HasSettingsPermission`.

```jsonc
// → 200
{ "enabled": true, "configured": true }
```
- `enabled` — the `enabled` flag on settings.
- `configured` — **all** of `account_sid`, `api_key`, `api_token`, `subdomain`,
  `webhook_verify_token` are present.

---

## 3. Place a call (click-to-call) — `POST /api/v1/crm/exotel/call/`

Initiates an outbound call: Exotel first rings the **agent's** phone, then bridges to
the customer.

**Auth:** `IsAuthenticated` (any logged-in user — but the caller must be a configured
telephony agent, see §5).

**Request**
```jsonc
{
  "to_number": "+919812345678",     // required — the customer
  "from_number": "+919800000000",   // optional — defaults to agent.mobile_no
  "caller_id": "+914040404040",     // optional — defaults to agent.exotel_number (ExoPhone)
  "related_to": "lead",             // optional — record the call was initiated from
  "related_to_id": "…uuid…"         //   ("lead" | "customer" | "contact"); both or neither
}
```

**Call-log linking.** If `related_to` + `related_to_id` are supplied (and the record
exists in the caller's org), the resulting call log links **directly to that record** —
so a call started from a specific lead is attached to *that* lead even if the number
matches another record. If they're omitted or the record isn't found, the log falls
back to reverse-resolving the **dialed number** (Contact → Lead → Customer, first
match). Cross-org ids are ignored (never linked). Both fields must be sent together or
the request is **400**.

**Success → 200**
```jsonc
{
  "call_sid": "abc123…",
  "call_log_id": "…uuid…",
  "status": "Ringing",
  "payload": { /* raw Exotel Call object */ }
}
```

**Errors** — **400**:
- `"related_to and related_to_id must be provided together."` (serializer validation)
- `ExotelError` messages:
  - "Exotel integration is disabled" / "…not fully configured"
  - "You are not configured as a telephony agent"
  - "Exotel is not enabled for this telephony agent"
  - "Missing telephony agent mobile number" / "…exotel number"
  - "Exotel number … is not valid for this account"
  - "Exotel API error: …" (upstream rejection)

Behind the scenes it registers a `StatusCallback` pointing at the §7 webhook so call
progress flows back, creates a `CRMCallLog` (org-stamped, `status: Ringing`, linked
per the rules above), and fires an FCM "ringing" banner to the caller's devices. The
log is **created at dial time**; final `status`, `duration`, `end_time`, and
`recording_url` are filled in later by the status webhook (§7); `cdn_recording_url`
(the playable copy) is set shortly after by the async re-host (§4a).

---

## 4. Contact lookup — `GET /api/v1/crm/exotel/contact/?phone_number=…`

Reverse-lookup a phone number to a CRM record (used for caller-ID popups).

**Auth:** `IsAuthenticated`.

Returns the first match across **Contact → Lead → Customer** (in that precedence),
or `{}` if none:
```jsonc
{ "type": "lead", "id": "…uuid…", "name": "Ada Lovelace", "mobile_no": "+91…", "phone": "…" }
```

---

## 4a. Call logs & recordings — `GET /api/v1/crm/call-logs/`

How the frontend **lists calls and reaches recordings**. Standard CRM viewset
(`CRMCallLogViewSet`) — paginated, org-scoped, RBAC-gated by `view_call_log`.

**To show one record's calls** (e.g. a "Calls" tab on a lead/customer/contact detail):
```
GET /api/v1/crm/call-logs/?related_to=lead&related_to_id=<lead_id>
```
This is the mirror of the §3 linking — `related_to` is the model name
(`lead` / `customer` / `contact` / `deal` / `task`) and `related_to_id` is the record's
UUID.

**Useful query params** (all optional, combinable):

| Param | Example | Meaning |
|-------|---------|---------|
| `related_to` / `related_to_id` | `lead` / `<uuid>` | Calls linked to a specific record |
| `type` | `Incoming` \| `Outgoing` | Direction |
| `caller` / `receiver` | `<user_id>` | Agent involved |
| `created_at_after` / `created_at_before` | `2026-01-01` | Date range |
| `start_time_after` / `start_time_before` | ISO datetime | Call-time range |
| `search` | `follow up` | Matches summary / from / to number |
| `telephony_medium` | `Exotel` | Provider |

**Recording fields on each call-log row:**

| Field | Notes |
|-------|-------|
| `recording_url` | **read-only** — the **original provider URL** (Exotel-hosted, `recordings.exotel.com/…`). Kept untouched for audit/re-download. **Do not embed this in the web app** — it 403s (see below). |
| `cdn_recording_url` | **read-only** — the **playable** URL: the CRM's own Bunny-CDN copy, set once the async re-host completes (seconds after the call ends). **The frontend binds this to `<audio src>`.** `null` = re-host still in flight (or failed) → show "processing". |
| `recording_file` | The recording in the CRM's own storage (`call_recordings/`). For Exotel calls this is **auto-populated**: when a terminal webhook carries a `RecordingUrl`, `fetch_exotel_recording` downloads it into `recording_file`. |
| `transcript` / `call_summary` / `transcription_status` | **read-only** — AI transcription outputs (see §6). Runs automatically for Exotel calls once the recording is fetched, **if** the org/user is entitled (`can_transcribe`). |

> **Recording flow (Exotel):** status webhook gives a remote `recording_url` →
> `fetch_exotel_recording` (Celery) streams it into `recording_file` → **always
> re-hosts on Bunny CDN and sets `cdn_recording_url`** (independent of transcription
> entitlement; `recording_url` stays the original Exotel URL) → if `can_transcribe`
> passes, chains `transcribe_call_recording` (Sarvam transcript → Gemini summary →
> `CallRecordingReady` notification). All async; nothing blocks the call. Download
> is size-capped (25 MB), idempotent on resends, and the transcribe step skips a
> duplicate upload when `cdn_recording_url` is already set.

> **Why the re-host matters:** `recordings.exotel.com` URLs **403 when embedded** in
> the web app (Exotel hotlink/referer protection — direct navigation works, an
> `<audio>` tag from the app's origin doesn't; the server-IP whitelist only covers
> backend fetches). Only a URL we own is browser-playable. Frontend rule: **play
> `cdn_recording_url`; if it's `null`, treat the recording as "processing"** and
> optionally offer `recording_url` as an open-in-new-tab fallback.
> Backfill for pre-existing logs: `manage.py rehost_exotel_recordings` (supports
> `--dry-run` / `--limit`; also migrates legacy rows whose `recording_url` was
> rewritten to the CDN URL in place by the old pipeline).

Two convenience sub-endpoints let a user act on a call from its detail view (call-log
id is the **`crm_call_log_id` UUID**):
- `POST /api/v1/crm/exotel/call-logs/<uuid>/note/` — add a note to the call.
- `POST /api/v1/crm/exotel/call-logs/<uuid>/task/` — create a follow-up task from the call.

---

## 5. Telephony agents — `GET/POST/PATCH/DELETE /api/v1/crm/exotel/agents/`

Per-user telephony config. **Required to place (§3) or receive (§8) calls** — a user
without an agent row (or with `exotel_enabled=false`) can't use Exotel. Manage them
here; this is the "Agents" screen the frontend needs.

**Auth:** `HasSettingsPermission` — list/retrieve need `view_settings`;
**create/update/delete require org admin** (`is_staff` or the System Admin role).
Org-scoped: only this org's agents are visible/editable.

**Fields**

| Field | Type | Notes |
|-------|------|-------|
| `user` | user_id (UUID) | **the agent identifier** — one agent per user. Write on create; the record is looked up by it. Must belong to the caller's org. |
| `user_email` | string | **read-only** — convenience for display. |
| `user_name` | string | **read-only** — full name or username. |
| `mobile_no` | string | the phone Exotel rings first (the agent's own device). Required when `exotel_enabled`. |
| `exotel_number` | string | the agent's ExoPhone, used as the outbound `CallerId`. Required when `exotel_enabled`. |
| `exotel_enabled` | bool | must be `true` for the user to place/receive calls. |
| `default_medium` | enum | `Twilio` / `Exotel` (optional). |
| `created_at` / `updated_at` | datetime | read-only |

### `GET` (list) — `/api/v1/crm/exotel/agents/`
Paginated list of the org's agents.

### `GET` (retrieve) / `PATCH` / `DELETE` — `/api/v1/crm/exotel/agents/<user_id>/`
Look up / update / remove a single agent **by the user's `user_id`**.

### `POST` (create) — `/api/v1/crm/exotel/agents/`
```jsonc
{
  "user": "…user-uuid…",           // required — the CRM user this agent is for
  "mobile_no": "+919800000001",    // required when exotel_enabled
  "exotel_number": "+914040404040",// required when exotel_enabled — the ExoPhone
  "exotel_enabled": true,
  "default_medium": "Exotel"       // optional
}
// → 201
```

**Errors:**
- **403** — non-admin attempting create/update/delete
  (`"Only organization admins may manage telephony agents."`).
- **400** `{"user": "User does not belong to this organization."}` — cross-org user.
- **400** `mobile_no` / `exotel_number` `"Required when exotel_enabled is true."`

The same row also drives **inbound routing** (§8): the agent rung for an incoming call
is the one whose user owns/is assigned the caller's matched record (or the
`default_incoming_agent` fallback).

---

## 6. Transcription settings — `GET/POST/PATCH /api/v1/crm/transcription-settings/`

**Separate from Exotel settings** (the admin UI conflates them). Controls AI
transcription/summary at the org level.

**Auth:** `HasSettingsPermission`.

| Field | Type | Notes |
|-------|------|-------|
| `transcription_enabled` | bool | |
| `summary_enabled` | bool | |
| `allowed_scope` | enum | `all_users` \| `admins_only` \| `selected_users` |
| `allowed_users` | list of `user_id` | only meaningful for `selected_users` |
| `updated_at` | datetime | read-only |

The UI's "Global auto / User-specific auto / Manual (one-click)" radio maps onto
`transcription_enabled` + `allowed_scope` (Global auto ≈ enabled + `all_users`;
User-specific ≈ `selected_users`; Manual ≈ transcription off / on-demand).

### Dual-channel (speaker-labeled) transcripts

When the Exotel **account/flow records dual-channel** (one call leg per stereo
channel — enabled by Exotel support, not the API; the dashboard default is "single
normal"), the pipeline detects the 2-channel recording, transcribes **each leg
separately** in one Sarvam batch job with word timestamps, and interleaves them by
time into a labeled transcript:

```
Agent: hello, how can I help you today
Customer: I wanted to ask about the pricing
Agent: sure, let me pull that up
```

- **Detection is by decoded channel count, not file extension** — a stereo MP3 is
  split the same as a stereo WAV. Mono recordings (all recordings made before dual
  is enabled, and incoming calls until the flow's Record applet is set to dual)
  keep the existing unlabeled transcript. Nothing needs re-configuring app-side.
- **Labels are deterministic**, from Exotel's first-leg-on-left-channel convention:
  outgoing → left=`Agent`, incoming → left=`Customer`. Only Exotel-medium call logs
  use the split (an ordinary stereo upload has the same speech on both channels).
- If Sarvam returns no timestamps, the transcript degrades to two labeled blocks
  (`Agent: <full text>` / `Customer: <full text>`); on any dual-path failure it
  falls back to the normal mono transcription — transcription never fails over
  labeling.
- Summaries (Gemini/Ollama) are prompted to use the speaker labels when present.

---

## 7. Status / call-event webhook — `GET|POST /api/v1/crm/exotel/webhook/?key=<webhook_verify_token>`

**Called by Exotel, not the frontend.** `AllowAny`, no auth — protected only by the
`?key=` token matching the org's `webhook_verify_token`. Accepts **both**:
- **POST** — the `StatusCallback` mechanism (auto-attached to outbound calls; reads the
  form body).
- **GET** — the **Passthru applets** in the incoming call flow (reads URL query params).

Both feed the same `process_webhook`.

Purpose: receive **after-the-fact call events** (answered / completed, duration,
recording URL) and update the matching `CRMCallLog` (keyed by `CallSid`). Marks missed
calls (§9), enqueues the recording→transcription fetch, and fires the call banner.

**Exotel flow wiring — paste this URL in all of these** (async where offered):
- Outbound `StatusCallback` → set automatically by the CRM (nothing to paste).
- Connect applet **"After the call conversation ends…"** Passthru → this URL.
- Connect applet **"If nobody answers…"** Passthru → this URL (drives missed-call §9).

- **Tenancy:** the org is resolved from the unique `webhook_verify_token` in `?key=`
  (Exotel sends no JWT), then the thread-local + RLS context are set so the call-log
  update and contact-linking work. Rejects with **403** if the token matches no org;
  logs every request to `CRMIntegrationRequest` (with the HTTP method).

---

## 8. Inbound-call routing (Programmable Connect) — `GET /webhooks/exotel/passthru/?key=<webhook_verify_token>`

**Called by Exotel during an incoming call, not the frontend.** This is the endpoint
that **redirects incoming calls to the right CRM agent**.

- **Where it's configured (Exotel side):** in the org's **App Bazaar call flow →
  Connect applet → "Configure parameters dynamically by providing a URL (Call Center
  Connect)"**. Paste `https://<crm-host>/webhooks/exotel/passthru/?key=<the org's
  webhook_verify_token>`. (This is **not** a plain "status callback" field.)
- **Auth / tenancy:** unauthenticated; the org is resolved from the unique
  `webhook_verify_token` in `?key=`. Bypasses `OrganizationMiddleware` (mounted under
  `/webhooks/`) and sets the tenant + RLS context itself.

**Request (Exotel → CRM, GET query params):** `CallSid`, `CallFrom` (caller),
`CallTo`/`To` (the ExoPhone), `Direction=incoming`, etc.

**Response (CRM → Exotel, `application/json`):**
```jsonc
{
  "fetch_after_attempt": false,
  "destination": { "numbers": ["+919812345678"] },  // agent's mobile_no to ring
  "outgoing_phone_number": "+914040404040",          // the ExoPhone
  "record": true,
  "recording_channels": "dual",
  "max_ringing_duration": 45,
  "max_conversation_duration": 3600
}
```

**Routing logic:** look up `CallFrom` against Lead/Customer/Contact → ring the
**owner/assignee** of the matched record (must be an `exotel_enabled` telephony agent
with a `mobile_no`). If no match / no ringable agent → fall back to
`default_incoming_agent`. If that's also unset → return **empty** `destination.numbers`
so Exotel takes its dashboard fallback branch.

Side effects: creates/updates the inbound `CRMCallLog` (org-stamped, `receiver` set,
linked to the contact) and fires the ringing banner — so the call appears in the CRM
immediately, before the §7 status webhook arrives. Idempotent with §7 (same `CallSid`).

**Responses:** always JSON. **403** (empty destination) for missing/unknown key or a
disabled integration; **200** with the routing body otherwise. On internal error it
returns an empty destination (never a hard 5xx that would drop the caller).

---

## 9. Screen-pop banner & missed calls (real-time)

**Screen-pop / incoming-call banner.** Every call state transition
(`ringing → in_progress → ended`) is delivered to the agent over **two channels, always**:

1. **WebSocket** (primary, for a focused browser tab) — see the connection guide below.
   This fires **even if the agent has no registered FCM device** (the common desk-agent
   case), which plain FCM could not cover.
2. **FCM data push** (fallback, for mobile / backgrounded tabs) — the same payload as a
   `call_banner` data message to the agent's `UserDevice` tokens.

Both carry the **identical `data` payload**; the client **de-dupes** on
`call_sid` + `call_state` (it may receive the same transition twice). Payload:

| Key | Meaning |
|-----|---------|
| `related_to` | `lead` / `customer` / `contact` (empty if unmatched) |
| `related_to_id` | the matched record's UUID |
| `related_to_name` | display name of the matched record |
| `lead_id` / `lead_name` | **backward-compat** — populated only when `related_to == lead` |
| `call_state` | `ringing` / `in_progress` / `ended` |
| `call_sid`, `call_log_id`, `from_number`, `to_number`, `direction`, `final_status`, `duration_seconds`, `start_time` | call context |

The client navigates/pops using `related_to` + `related_to_id` (e.g. `/leads/<id>`,
`/customers/<id>`).

### WebSocket connection guide (frontend)

- **URL:** `wss://<host>/ws/crm/calls/?token=<access-JWT>` — use `wss://` on HTTPS
  (e.g. `wss://dev.clozr.tech/ws/crm/calls/?token=…`), `ws://` only for local http.
- **Token:** the **same access JWT** used for REST calls, passed as the `?token=`
  query param (WebSockets can't send an `Authorization` header). No separate handshake.
- **Served by** the WebSocket process (Uvicorn `:8001`), the same one behind
  `/ws/whatsapp/*` and `/ws/emails/*`. It's per-**user** — one connection per logged-in
  user is enough; every device/tab the user opens can connect independently.
- **On connect:** the socket is accepted immediately (it joins group `call_{user_id}`
  server-side). **Rejected connections close with code `4001`** (missing/invalid token)
  — the client should treat 4001 as "re-auth / refresh token", not retry blindly.
- **Keepalive:** send `{"type":"ping"}` and the server replies `{"type":"pong"}`. All
  real actions stay on REST — the socket is receive-only for call events.
- **Messages received** are exactly:
  ```json
  { "type": "call_banner", "data": { …the payload table above… } }
  ```
  Handle only `type === "call_banner"` for now. De-dupe against the FCM push on
  `data.call_sid` + `data.call_state`.

Minimal client:
```js
const ws = new WebSocket(`wss://dev.clozr.tech/ws/crm/calls/?token=${accessToken}`);
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg.type === "call_banner") renderCallBanner(msg.data); // dedupe on call_sid+call_state
};
ws.onclose = (e) => { if (e.code === 4001) refreshTokenAndReconnect(); };
setInterval(() => ws.readyState === 1 && ws.send(JSON.stringify({type: "ping"})), 30000);
```

**Missed calls.** An **incoming** call that reaches a terminal-without-answer status
(`No Answer` / `Busy` / `Failed` / `Canceled`, and not `AnsweredBy=human`) is marked
`is_missed = true` on the call log. On the first `false → true` transition (idempotent
across webhook resends) the CRM:
- creates a **`MissedCall`** `CRMNotification` for the intended agent (the call's
  `receiver`, else the matched record's owner/assignee, else `default_incoming_agent`);
  for **unrouted** misses (no match, no default agent) it notifies the **org admins**
  (`is_staff`) so the call isn't lost;
- auto-creates a **follow-up `Task`** ("Call back …", type Call) linked to the call log
  and assigned to that agent (unassigned for unrouted misses).

`MissedCall` is preference-gated like other notification events (a user can mute it).

---

## Endpoint summary

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET/POST/PATCH/DELETE | `/api/v1/crm/exotel/settings/` | Settings perm + admin for writes | Org Exotel config (§1) |
| GET | `/api/v1/crm/exotel/status/` | Settings perm | Connected/configured badge (§2) |
| POST | `/api/v1/crm/exotel/call/` | Authenticated (agent) | Click-to-call, optional `related_to`/`related_to_id` (§3) |
| GET | `/api/v1/crm/exotel/contact/?phone_number=` | Authenticated | Caller-ID lookup (§4) |
| GET | `/api/v1/crm/call-logs/?related_to=&related_to_id=` | `view_call_log` | List calls + recordings for a record (§4a) |
| GET/POST/PATCH/DELETE | `/api/v1/crm/exotel/agents/` | Settings perm + admin for writes | Per-user telephony agents (§5) |
| POST | `/api/v1/crm/exotel/call-logs/<uuid>/note/` | Authenticated | Add note to a call log |
| POST | `/api/v1/crm/exotel/call-logs/<uuid>/task/` | Authenticated | Add follow-up task to a call log |
| GET/POST/PATCH | `/api/v1/crm/transcription-settings/` | Settings perm | AI transcription config (§6) |
| POST | `/api/v1/crm/exotel/webhook/?key=` | AllowAny (token) | Status callback from Exotel (§7) |
| GET | `/webhooks/exotel/passthru/?key=` | AllowAny (token) | Inbound-call routing to agent (§8) |
