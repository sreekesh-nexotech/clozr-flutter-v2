# WhatsApp API — Complete Endpoint Reference

Every authenticated WhatsApp endpoint, mounted under **`/api/v1/whatsapp/`**.

> **Scope.** This is the full reference. For the *change-log* of the
> `feat/email-whatsapp` branch — what was deleted, what changed semantics, the
> 24-hour window rollout — see
> [email-whatsapp-frontend-handover.md](../handover/email-whatsapp-frontend-handover.md).
> That document covers ~9 endpoints (the ones that changed); this one covers all 29.

**Auth:** authenticated user; the org comes from the JWT (`request.org`).
**Plan gate:** most endpoints require the **`whatsapp`** plan feature
(`HasPlanFeature`) — a missing feature returns **403**, not 404.
**Admin tier:** account CRUD and webhook-key rotation require
`HasSettingsPermission` (System Admin).

---

## 0. Endpoint map

| # | Method · Path | Purpose |
| :-- | :--- | :--- |
| **Badge & conversations** |||
| 1 | `GET /badge/` | Unread total for the header chat icon |
| 2 | `GET /conversations/` | Conversation list (inbox) |
| 3 | `GET /conversations/<pk>/` | One conversation |
| 4 | `GET /conversations/<id>/messages/` | Message thread |
| 5 | `POST /conversations/<id>/read/` | Mark read, reset unread |
| 6 | `POST /conversations/<pk>/assign/` | Assign to an agent |
| 7 | `POST /conversations/<pk>/unassign/` | Clear assignment |
| 8 | `POST`/`DELETE /conversations/<pk>/star/` | Star / unstar (per user) |
| 9 | `GET /conversations/starred/` | The current user's starred list |
| **Sending** |||
| 10 | `POST /send/text/` | Free-form text — **window-gated** |
| 11 | `POST /send/image/` | Image, multipart — **window-gated** |
| 12 | `POST /send/document/` | Any other file, multipart — **window-gated** |
| 13 | `POST /send/template/` | Template — not window-gated |
| 14 | `POST /send/template/preview/` | Dry run: render without sending |
| **Media** |||
| 15 | `GET /media/<media_id>/` | Binary proxy — inbound **and** outbound media |
| **Templates** |||
| 16 | `GET /templates/` | Template list + statuses |
| 17 | `POST /templates/sync/` | Sync one account from Meta |
| 18 | `POST /templates/sync-all/` | Sync every account |
| 19 | `POST /templates/create/` | Submit a new template to Meta |
| 20 | `DELETE /templates/<pk>/` | Delete a template |
| 21 | `GET /templates/<pk>/variables/` | Slot inventory + saved mapping |
| 22 | `GET`/`PUT /templates/<pk>/variable-map/` | Read / write the mapping |
| **Canned responses** |||
| 23 | `GET`/`POST /canned-responses/` | List / create |
| 24 | `GET`/`PUT`/`DELETE /canned-responses/<pk>/` | Retrieve / update / delete |
| **Account admin** (System Admin) |||
| 25 | `GET`/`POST /accounts/` | List / connect an account |
| 26 | `GET`/`PUT`/`DELETE /accounts/<pk>/` | Manage one account |
| 27 | `POST /accounts/<pk>/rotate-webhook-key/` | New keyed webhook URL |
| 28 | `POST /accounts/<pk>/revoke-webhook-key/` | Disable the keyed URL |
| **WebSocket** |||
| 29 | `ws/whatsapp/inbox/?token=<JWT>` | Live inbound + outbound events |

Account and webhook-key management are documented in full in
[webhook-urls.md](webhook-urls.md).

---

## 1. Badge — header unread count

```
GET /api/v1/whatsapp/badge/
→ 200  { "unread_total": 9 }
```

Sum of `unread_count` across the org's conversations. Drives the `9+` chip on the
chat icon. Returns `{"unread_total": 0}` rather than an error when there is no org
context, so it is safe to poll unconditionally.

Refresh it on the `new_message` WebSocket event rather than on a timer.

---

## 2. Conversations

```
GET /api/v1/whatsapp/conversations/
GET /api/v1/whatsapp/conversations/<pk>/
```

Paginated (`StandardResultsSetPagination`). Each conversation carries the
window fields described in the handover — `window_open`, `window_expires_at` — which
decide whether the composer is unlocked.

### Messages

```
GET /api/v1/whatsapp/conversations/<conversation_id>/messages/
```

Reverse-chronological thread. Attachments arrive as media ids — fetch the binary
through §5.

### Read / assign / star

```
POST   /conversations/<id>/read/         → resets unread_count to 0
POST   /conversations/<pk>/assign/       { "assigned_to": "<user uuid>" }
POST   /conversations/<pk>/unassign/
POST   /conversations/<pk>/star/         → star (per-user, not per-org)
DELETE /conversations/<pk>/star/         → unstar
GET    /conversations/starred/           → the caller's starred conversations
```

**Starring is per user.** Two agents starring the same conversation keep
independent lists, so never cache a star state across users.

---

### When to clear the unread badge

**Rendering messages does not mark them read.** `unread_count` is server state
on the conversation, written in exactly two places:

| Written by | Effect |
| :--- | :--- |
| The inbound webhook task | `unread_count = unread_count + 1` per inbound message |
| `POST /conversations/<id>/read/` | `unread_count = 0` |

Nothing else touches it. In particular, **`GET /conversations/<id>/messages/`
has no side effect** — fetching, scrolling, or displaying a thread leaves the
count exactly where it was. A badge that survives a thread the agent has plainly
read means `POST /read/` was never called (or its response was never applied).

Note the badge is **unread-message state, not delivery state**. The per-message
`status` field (`sent` → `delivered` → `read`) is Meta's receipt for **outbound**
messages and is unrelated: in the sample response, message 3 has `"status":
"read"` because *the customer* read our template, and inbound message 4 shows
`"status": "delivered"` — neither of those clears our badge. Do not derive
unread state from `status`, `direction`, or timestamps; the only source of truth
is `unread_count` on the conversation.

#### The required sequence

```
1. Agent opens the conversation
2. GET  /conversations/<id>/messages/     ← render
3. POST /conversations/<id>/read/         ← REQUIRED; unread_count → 0
4. Set unread_count = 0 on the cached conversation row (or refetch)
5. GET  /badge/                           ← header count
```

Step 3 is the one that is easy to omit, and steps 4–5 are the ones that make the
UI agree with the server. `POST /read/` returns only
`{"message": "Conversation marked as read."}` — **no counts** — so the client
must either patch its local state to `0` itself or refetch
`GET /conversations/` and `GET /badge/`. Optimistically zeroing the local value
immediately is fine and preferred; the POST can settle in the background.

#### Rules that avoid the stale-badge bug

* **Fire `read/` on open, not on close or unmount.** A collapse/navigate handler
  is easy to miss (a route change, a tab switch, an unmount that never runs), and
  that is the classic cause of a badge that reappears when the panel collapses.
* **Fire it again when a `new_message` arrives while the thread is already
  open and focused.** The webhook increments the counter regardless of what the
  agent is looking at, so a message that lands in a visible thread re-raises the
  badge unless it is re-cleared. Guard on document/panel visibility — do not
  clear while the tab is backgrounded.
* **Clear per conversation, not globally.** There is no bulk mark-all-read
  endpoint; the header badge is the `Sum` of every conversation's `unread_count`,
  so it only reaches zero once each conversation has been read individually.
* **Refresh the badge after `read/`, not only after `new_message`.** The header
  count is computed server-side on request and will not change on its own.
* **Do not clear the badge on send.** Replying does not mark inbound messages
  read — only `POST /read/` does. In the sample data, sending `"halo"` left
  `unread_count` at 1 from the inbound `"HI"`.
* **Ignore a 404** — the conversation was deleted; drop it from the list and
  refresh the badge.

---

## 3. Sending

### Which sends the 24-hour window blocks

| Endpoint | Window-gated | On a closed window |
| :--- | :--- | :--- |
| `POST /send/text/` | ✅ | **403** `whatsapp_window_closed` |
| `POST /send/image/` | ✅ | **403** (checked *before* upload) |
| `POST /send/document/` | ✅ | **403** (checked *before* upload) |
| `POST /send/template/` | ❌ | Templates are how you reach a closed window |

### Error contract

Every send failure returns the same shape — **switch on `code`, never on `error`**:

```jsonc
{ "error": "Human-readable, safe to display",
  "code":  "stable_machine_code",
  "meta_error": "…" }               // only when Meta was the source
```

| `code` | HTTP | Meaning |
| :--- | :--- | :--- |
| `whatsapp_window_closed` | 403 | 24h window shut, or the contact never messaged in |
| `whatsapp_template_not_approved` | 400 | Template exists locally but isn't `APPROVED` |
| `whatsapp_template_rejected` | 400 | Meta rejected it (unknown name / param mismatch) |
| `whatsapp_variables_not_configured` | 400 | Template **has** `{{n}}` slots but no mapping saved |
| `whatsapp_variables_unresolved` | 400 | Mapping exists but a value resolved to null — see `unresolved[]` |
| `whatsapp_recipient_unsubscribed` | 403 | The matched Lead opted out |
| `whatsapp_account_not_found` | 404 | Bad `whatsapp_account_id`, or account inactive |
| `organization_required` | 400 | No org context |
| `whatsapp_no_message_id` | 502 | Meta accepted but returned no id — retry |
| `whatsapp_api_error` | 502 | Anything else from Meta — retry with backoff |

### Template send

```jsonc
POST /api/v1/whatsapp/send/template/
{
  "whatsapp_account_id": 1,
  "to": "919999888777",
  "template_name": "first_message",
  "language_code": "en_US"
  // "components": [...]   // optional; bypasses variable resolution entirely
  // "overrides": {...}    // optional; per-send values, same keys as the mapping
}
```

**Only `APPROVED` templates send.** Offer nothing else in the picker.

#### Variables: when a mapping is required

| Template shape | Mapping needed? |
| :--- | :--- |
| No `{{n}}` anywhere ("Hi Welcome to NexoCRM!") | ❌ **No** — sends as-is |
| `{{n}}` in the body | ✅ Yes |
| `{{n}}` in a TEXT header | ✅ Yes |
| `{{n}}` in a URL button | ✅ Yes |
| IMAGE/VIDEO/DOCUMENT header, no text slot | ❌ No |
| QUICK_REPLY / PHONE_NUMBER / COPY_CODE buttons | ❌ No |

Use `GET /templates/<pk>/variables/` (§6) to decide — if it returns no `body`,
`header`, or non-empty `buttons`, the template needs no configuration and sending
will succeed with no mapping.

> **Fixed bug.** Placeholder-free templates previously returned **400
> `whatsapp_variables_not_configured`** — asserting the template "requires
> variables" while the Integrations screen, parsing the same components, correctly
> reported it has none. The send path derived "needs variables" from *"the caller
> did not supply components"* instead of from the template. Every static approved
> template was unsendable. If the UI has a workaround for this, remove it.

`overrides` reach the real send, not just the preview — so a value an agent edits
in the preview dialog is what the customer receives.

### Preview (dry run)

```jsonc
POST /api/v1/whatsapp/send/template/preview/
{ "whatsapp_account_id": 1, "to": "919999888777",
  "template_name": "order_update", "language_code": "en_US" }
```

Resolves the mapping against the matched CRM record and returns the rendered text
plus the Meta payload **without calling Meta and without persisting a message**.
Use it to power a "this is what will be sent" confirmation. Same error codes as
the real send, so an unconfigured template fails here first — cheaply.

---

## 4. Text, emoji, images and documents (composer)

Three endpoints back the message composer. All three are **window-gated** — see
§3 — and all three return the same error envelope.

| Endpoint | Content-Type | Meta message type |
| :--- | :--- | :--- |
| `POST /api/v1/whatsapp/send/text/` | `application/json` | `text` |
| `POST /api/v1/whatsapp/send/image/` | `multipart/form-data` | `image` |
| `POST /api/v1/whatsapp/send/document/` | `multipart/form-data` | `document` |

### 4.1 Text — and emoji

```jsonc
POST /api/v1/whatsapp/send/text/
Content-Type: application/json
{
  "whatsapp_account_id": 1,
  "to": "919999888777",
  "body": "Thanks! 🎉 We'll get back to you shortly.",
  "reply_to_message_id": "wamid.HBg…"   // optional — quotes an earlier message
}
```

| Field | Required | Notes |
| :--- | :--- | :--- |
| `whatsapp_account_id` | ✅ | integer pk from `GET /accounts/` |
| `to` | ✅ | E.164 **without** `+`, max 20 chars |
| `body` | ✅ | max **4096** chars |
| `reply_to_message_id` | — | `wa_message_id` of the message being replied to |

**There is no emoji endpoint, and none is needed.** Emoji are ordinary Unicode
characters inside `body` — the emoji picker's only job is to insert the character
into the text input at the caret. Nothing about the payload changes.

Two things to get right on the frontend:

* **Count characters, not code units.** `"🎉".length === 2` in JavaScript, and a
  flag or a skin-tone emoji is longer still. If you enforce the 4096 limit with
  `.length` the counter drifts from what the backend measures. Use
  `[...body].length` (or `Intl.Segmenter`) for the display counter; the backend
  validates the decoded string.
* **Send UTF-8 JSON.** Django decodes the request body as UTF-8; no escaping,
  surrogate-pair splitting, or HTML entities are required or wanted.

Response `200`:

```jsonc
{ "message": "Text message sent successfully.",
  "wa_message_id": "wamid.HBg…",
  "message_id": 8412 }               // WhatsAppMessage pk — use to reconcile the optimistic bubble
```

### 4.2 Images

```
POST /api/v1/whatsapp/send/image/
Content-Type: multipart/form-data
```

| Part | Required | Notes |
| :--- | :--- | :--- |
| `whatsapp_account_id` | ✅ | integer |
| `to` | ✅ | E.164 without `+` |
| `image` | ✅ | the binary file part |
| `caption` | — | max **1024** chars; sent as Meta's image caption |

```js
const fd = new FormData();
fd.append("whatsapp_account_id", accountId);
fd.append("to", phone);
fd.append("image", file);            // File from <input type="file">
fd.append("caption", caption ?? "");
await fetch("/api/v1/whatsapp/send/image/", {
  method: "POST",
  headers: { Authorization: `Bearer ${token}` },   // NO Content-Type — let the browser set the boundary
  body: fd,
});
```

> **Do not set `Content-Type` yourself.** Setting `multipart/form-data` manually
> omits the `boundary` parameter and Django parses zero fields, producing a
> confusing 400 that names `image` as missing when the file was attached.

`image` is validated by DRF's `ImageField`, which **opens the file with Pillow**.
That means:

* Only real raster images pass — JPEG, PNG, GIF, WEBP, BMP. A renamed `.txt`,
  an SVG, or a corrupt file is rejected with a field error, not a Meta error.
* **SVG is not an image here.** If a user picks one, route it to
  `/send/document/`.
* Meta additionally accepts only `image/jpeg` and `image/png` for the `image`
  message type. A GIF or WEBP passes our validation and then fails at Meta with
  **502 `whatsapp_api_error`**. Filter the file picker to
  `image/jpeg,image/png` to avoid the round trip.

The MIME type sent to Meta is the browser-supplied `content_type`, defaulting to
`image/jpeg` when the browser sends none.

### 4.3 Documents

```
POST /api/v1/whatsapp/send/document/
Content-Type: multipart/form-data
```

| Part | Required | Notes |
| :--- | :--- | :--- |
| `whatsapp_account_id` | ✅ | integer |
| `to` | ✅ | E.164 without `+` |
| `document` | ✅ | the binary file part; any type |
| `filename` | — | max 256 chars — the name shown in WhatsApp |
| `caption` | — | max 1024 chars |

`document` is a plain `FileField`, so **anything uploads** — PDF, DOCX, XLSX,
CSV, ZIP, and also audio and video files. Use this endpoint for every
non-image attachment.

When `filename` is omitted the uploaded file's own name is used, so passing it
is only necessary to override the display name.

### 4.4 What is NOT implemented

The paperclip menu should only offer what the backend can send:

| Attachment type | Endpoint | Status |
| :--- | :--- | :--- |
| Image | `/send/image/` | ✅ |
| Document / any file | `/send/document/` | ✅ |
| Video (as a playable video bubble) | — | ❌ send via `/send/document/` |
| Audio / voice note | — | ❌ send via `/send/document/` |
| Sticker | — | ❌ |
| Location | — | ❌ |
| Contact card | — | ❌ |
| Reaction (emoji on a message) | — | ❌ |

`WhatsAppMessage.message_type` includes `video`, `audio`, `sticker`, `location`,
`contacts` and `reaction`, but those values are only ever written by the
**inbound** webhook — the model can store what a customer sends us; there is no
outbound endpoint for them. A video sent through `/send/document/` arrives as a
file attachment rather than an inline player. If inline video/audio or reactions
are needed, they are new backend work, not a frontend fix.

### 4.5 Size limits

| Layer | Limit | On exceed |
| :--- | :--- | :--- |
| Django `DATA_UPLOAD_MAX_MEMORY_SIZE` | **10 MB** (`.env`-tunable) | 400 |
| Meta — images | 5 MB | 502 `whatsapp_api_error` |
| Meta — documents | 100 MB | 502 `whatsapp_api_error` |

The effective ceiling is Django's 10 MB, and any reverse proxy in front may cap
lower still. **Validate size client-side before upload** — the request is
otherwise streamed in full only to be rejected. A practical cap: 5 MB images,
10 MB documents.

### 4.6 Failure handling in the composer

The upload is a single blocking request: the file goes to Meta's Media API
first, then the message is sent by the returned `media_id`. Nothing is persisted
unless Meta accepts, so a failed send leaves **no message row** — an optimistic
bubble must be removed, not left in a "failed" state pointing at a row that does
not exist.

| Situation | Response | Composer should |
| :--- | :--- | :--- |
| Window closed | 403 `whatsapp_window_closed` | Disable the composer, offer the template picker |
| File is not a valid image | 400, field error under `image` | Show inline, keep the file staged |
| File too large for Django | 400 | Show inline; ideally caught client-side first |
| Meta rejects the media | 502 `whatsapp_api_error` | Offer retry; surface `meta_error` in a detail row |
| Account inactive / wrong id | 404 `whatsapp_account_not_found` | Re-fetch `/accounts/` |

The window is checked **before** the upload, so a closed window costs no
bandwidth — but the whole file is still uploaded to Meta before the send is
attempted, which makes an upload spinner necessary for anything above ~1 MB.

---

## 5. Media proxy — rendering attachments

```
GET /api/v1/whatsapp/media/<media_id>/
```

Meta's media URLs are short-lived (~5 min) and require the account's access
token, so media **cannot** be linked directly from the browser — the raw URL
401s. This proxy resolves the `media_id` against Meta, streams the bytes back,
and caches the resolved URL for 4 minutes.

* Returns the **binary stream** with the stored `media_mime_type`, and
  `Content-Disposition: inline`.
* Requires the normal `Authorization: Bearer` header, so a bare
  `<img src="/api/v1/whatsapp/media/…">` will **not** authenticate. Fetch it and
  render from an object URL:

```js
const res = await fetch(`/api/v1/whatsapp/media/${mediaId}/`, {
  headers: { Authorization: `Bearer ${token}` },
});
const objectUrl = URL.createObjectURL(await res.blob());
// <img src={objectUrl}/> — and URL.revokeObjectURL(objectUrl) on unmount
```

* **`media_id`, not `message_id`.** The lookup is scoped to the caller's
  organization, so another tenant's `media_id` returns **404**.
* Applies to **both directions**. Outbound image/document rows store the
  `media_id` Meta returned at upload and never populate `media_url`, so a
  message you just sent renders through this same proxy. Do not expect
  `media_url` to be usable on outbound messages — it is only ever set by the
  inbound webhook.
* **404** means no message in this org carries that `media_id`; **502** means
  Meta refused the fetch (usually media older than 30 days, which Meta purges).
  Render a "media expired" placeholder rather than a broken image.

For a just-sent attachment the response contains `message_id` but no media id,
so the optimistic bubble should render the **local `File` object URL** and only
fall back to the proxy after the message list refetches.

---

## 6. Templates

```
GET  /templates/                       → list with `status`
POST /templates/sync/                  { "whatsapp_account_id": 1 }
POST /templates/sync-all/              → every account in the org
POST /templates/create/                → submit a new template to Meta
DELETE /templates/<pk>/
```

`status` carries Meta's full vocabulary: `APPROVED` · `PENDING` · `REJECTED` ·
`PAUSED` · `DISABLED` · `IN_APPEAL` · `PENDING_DELETION` · `LIMIT_EXCEEDED`.

⚠️ **Treat the list as open** — Meta adds statuses. Branch on
`status === "APPROVED"`, never on an enumeration of the failures.

Sync is asynchronous (Celery): a 200 means *queued*, not *complete*. Re-fetch
`/templates/` after a short delay rather than assuming the list is fresh.

### Variable introspection

```jsonc
GET /api/v1/whatsapp/templates/<pk>/variables/
→ 200
{
  "template_name": "order_update",
  "language": "en_US",
  "variables": {
    "body":    { "max_len": 1024, "indices": [1, 2] },
    "header":  { "max_len": 60, "indices": [1] },      // only when present
    "buttons": [ { "index": 0, "sub_type": "URL", "indices": [1] } ],
    "unsupported": [ { "type": "HEADER", "format": "IMAGE" } ]
  },
  "mapping": { … } | null
}
```

`body` and `header` **are absent entirely** when that component has no
placeholders — do not expect empty objects. A template needing no configuration
looks like `{"buttons": [], "unsupported": []}`.

`unsupported` lists components this backend cannot fill (media headers,
quick-reply buttons). They need no mapping — show them as informational, never as
an error.

Read tier: any agent composing a send can call this, not just admins.

### Variable mapping

```jsonc
GET /api/v1/whatsapp/templates/<pk>/variable-map/
→ 404 { "code": "whatsapp_variable_map_not_found" }   // when unconfigured

PUT /api/v1/whatsapp/templates/<pk>/variable-map/
{
  "mapping": {
    "body": {
      "1": { "source": "lead.first_name" },
      "2": { "source": "literal:TRK-0001" }
    }
  }
}
```

Sources: `lead.*`, `contact.*`, `custom.*`, `org.*`, `user.*`, `literal:<text>`.

**The mapping is keyed on (account, template name, language) — not the template's
`pk`.** A resync deletes and recreates template rows with new pks; the mapping
survives. Never cache a mapping against a template pk.

A 404 here means "not configured yet", which is a normal state for a template with
variables — prompt an admin to configure it rather than showing an error.

---

## 7. Canned responses

```jsonc
GET    /api/v1/whatsapp/canned-responses/          → list (org-scoped)
POST   /api/v1/whatsapp/canned-responses/          { "title": "…", "body": "…",
                                                     "shortcut": "/greet",
                                                     "category": "…" }
GET    /api/v1/whatsapp/canned-responses/<pk>/
PUT    /api/v1/whatsapp/canned-responses/<pk>/
DELETE /api/v1/whatsapp/canned-responses/<pk>/
```

Org-scoped shortcuts an agent inserts into the composer. Plain text — they are
**not** templates and carry no Meta approval, so they are only usable **inside**
the 24-hour window, exactly like `send/text/`.

Read fields: `canned_response_id`, `title`, `body`, `shortcut`, `category`,
`is_active`, `created_by_name`, `created_at`, `updated_at`. `shortcut` is the
slash-trigger to match on as the agent types; filter the picker to
`is_active: true`.

---

## 8. WebSocket

```
ws://<host>/ws/whatsapp/inbox/?token=<JWT>
```

Emits inbound **and outbound** messages (so drop any local-echo hack), plus
`conversation_update`. Events are **scoped per user** — an agent receives only
conversations they can see, so expect fewer events than a broadcast feed.

Refresh the badge (§1) on each `new_message`. If the event belongs to the
conversation currently open and visible, also re-`POST /read/` — the webhook
increments `unread_count` regardless of what the agent is viewing (§2).

---

## 9. Frontend checklist

- [ ] Badge from `GET /badge/`, refreshed on `new_message` **and after every `POST /read/`**
- [ ] `POST /conversations/<id>/read/` fires **on open** — rendering messages never clears unread
- [ ] Local `unread_count` zeroed optimistically (`read/` returns no counts)
- [ ] `read/` re-fires when a `new_message` lands in the open, visible thread
- [ ] Unread state read from `unread_count` only — never from a message's `status`
- [ ] Composer locked when `window_open` is false → offer templates
- [ ] Switch on `code`, never on `error` text
- [ ] Only `APPROVED` templates in the picker
- [ ] Before offering a template, call `/variables/` — no slots means no config needed
- [ ] Emoji picker only inserts the character into `body` — there is no emoji endpoint
- [ ] Character counter uses `[...body].length`, not `.length` (emoji are 2+ code units)
- [ ] Paperclip offers **image** and **file** only — no video/audio/location/contact/sticker sends exist
- [ ] Multipart uploads omit a manual `Content-Type` header (let the browser set the boundary)
- [ ] Client-side size check before upload (~5 MB images, 10 MB files)
- [ ] Failed send removes the optimistic bubble — nothing is persisted on failure
- [ ] Media loads through `/media/<id>/` with the auth header + object URL, not a bare `<img src>`
- [ ] Preview before send for templates with variables
- [ ] Star state is per user
- [ ] Treat template sync as async

---

## 10. Reference

- Routes: `whatsapp/urls.py` · Views: `whatsapp/views.py`
- Variable engine: `whatsapp/services/template_variables.py`
- Webhooks & keys: [webhook-urls.md](webhook-urls.md)
- Change log: [email-whatsapp-frontend-handover.md](../handover/email-whatsapp-frontend-handover.md)
- Rulebook §15.5 WhatsApp Business — the 24-hour window and template rule
