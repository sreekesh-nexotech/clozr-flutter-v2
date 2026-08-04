# Notes API (Slack-style notes, threads, attachments)

Backing for the **Notes** panel — the timeline shown on a record's detail page:
a composer at the top ("Add a note…"), then a reverse-chronological list of
top-level notes, each with an author avatar/name, an optional **source tag**
(Call / Email / …), a timestamp, the note body, a **Reply** affordance, and any
**attachments**. Replies render indented under their parent (one level deep, like
a Slack thread).

The same panel appears on **every record type** that supports notes. A note is
polymorphic — it links to any of these via `related_to` + `related_to_id`:

| `related_to` | Record | Id field to pass as `related_to_id` |
| :--- | :--- | :--- |
| `lead` | Lead | `lead_id` |
| `customer` | Customer | `customer_id` |
| `product` | Product | `product_id` |
| `task` | Task | `task_id` |
| `task` | **Follow-up** (a Task with `is_followup=true`) | `task_id` |
| `issue` | Issue | `issue_id` |
| `deal` / `contact` / `organization_contact` | Deal / Contact / Org contact | `<x>_id` |
| `project` / `project_task` | PMO project / task | `project_id` / `task_id` |

> **Follow-ups reuse the Task model** (`is_followup=true`) — there is no separate
> `followup` type; pass `related_to="task"` with the follow-up's `task_id`.

Base path: `/api/v1/crm/notes/`. Auth: authenticated user (org-scoped;
cross-org linking is rejected). Attachments live in the separate polymorphic
attachment table (`/api/v1/crm/attachments/`) and point back at a note.

---

## 1. Load the notes for a record (top-level timeline)

```
GET /api/v1/crm/notes/?related_to=lead&related_to_id=<lead_id>
```

Returns **top-level notes only** (replies are loaded per-thread, §3) newest-first,
paginated (`StandardResultsSetPagination`, page size 100, `?page=`/`?page_size=`).

**200 Response** (one item shown; the panel renders one card per item)

```json
{
  "count": 3,
  "next": null,
  "previous": null,
  "results": [
    {
      "note_id": "…uuid…",
      "title": null,
      "content": "Client wants the quote split into two phases. Sharing revised numbers tomorrow.",
      "is_pinned": 0,
      "note_type": {
        "note_type_id": "…uuid…",
        "name": "Call",
        "color": "#16a34a",
        "position": 1,
        "is_active": true,
        "is_default": false,
        "is_readonly": false
      },
      "parent_note": null,
      "reply_count": 1,
      "attachments": [],
      "mentioned_users": [],
      "created_by": {
        "user_id": "…uuid…",
        "email": "priya@acme.com",
        "username": "priya",
        "first_name": "Priya",
        "last_name": "Nair",
        "full_name": "Priya Nair",
        "is_active": true
      },
      "owner": { "…user shape…": "…" },
      "modified_by": null,
      "related_to_model": "lead",
      "related_to_object_id": "…lead_id…",
      "created_at": "2026-06-30T16:20:00Z",
      "updated_at": "2026-06-30T16:20:00Z"
    }
  ]
}
```

**UI mapping**

| UI element | Field |
| :--- | :--- |
| Avatar initials + author name | `created_by.full_name` (initials derived client-side) |
| Source tag ("Call", "Email") + its colour | `note_type.name` + `note_type.color` |
| Timestamp ("Yesterday · 16:20") | `created_at` (format client-side) |
| Note body | `content` |
| Reply affordance / thread count | `reply_count` (>0 → thread exists) |
| Attachment chips / inline images | `attachments[]` (see §4) |
| Header count ("3 notes") | `count` |

---

## 2. Add a note (composer)

```
POST /api/v1/crm/notes/
```

**Request body**

```json
{
  "content": "Site survey done. Carpet area larger than quoted — revisit scope.",
  "related_to": "lead",
  "related_to_id": "<lead_id>",
  "note_type": "<note_type_id>",          // optional — the Call/Email/… source tag
  "title": null,                            // optional (≤140 chars)
  "is_pinned": 0,                           // optional
  "mentioned_user_ids": ["<user_id>", …]   // optional — @mentions (see §5)
}
```

- `related_to` + `related_to_id` are **required** for a top-level note (a reply
  omits them — see §3). Use the table above for the value pairs.
- `note_type` is the source tag; manage the catalog via
  `/api/v1/crm/note-types/` (§6). Omit for an untagged note.
- `created_by`/`owner`/`organization` are stamped server-side.

**201 Response**: the created note (same shape as a list item).

---

## 3. Replies (Slack-style thread, one level deep)

Each top-level note has a thread. Replies **inherit the parent's record link** and
never appear in the record's top-level timeline (§1) — they load only here.

### List a note's replies

```
GET /api/v1/crm/notes/<note_id>/replies/
```

Paginated, **oldest-first** (natural reading order under the parent). Each reply
has the same shape as a note, with `parent_note` set to the parent's `note_id`.

### Post a reply

```
POST /api/v1/crm/notes/<note_id>/replies/
```

**Request body** — only the body (+ optional mentions/attachments-after). Do **not**
send `related_to`/`related_to_id`/`parent_note`; the endpoint forces the reply onto
this parent and copies its record link.

```json
{
  "content": "Good — keep phase 1 under ₹25L so it clears their fast-track approval.",
  "mentioned_user_ids": []
}
```

**201 Response**: the created reply. Side effects: the parent's `reply_count` is
incremented, and a **reply notification** goes to the parent's author + prior
thread participants (§5).

**Errors**
- Replying to a reply → **400** (`"Cannot reply to a reply; replies are one level deep."`).
- Unknown/foreign `<note_id>` → **404**.

---

## 4. Attachments on a note or reply (paste/upload like Slack)

Attachments are the **polymorphic Attachment table** pointing at the note. They are
returned inline on the note (`attachments[]`) and created/deleted via the
attachments endpoint with `related_to="note"`.

### Attach a file to a note

```
POST /api/v1/crm/attachments/         (multipart/form-data)
```

| Field | Notes |
| :--- | :--- |
| `related_to` | `"note"` |
| `related_to_id` | the target `note_id` (a top-level note **or** a reply — both are notes) |
| `file_upload` | the file (compressed + stored on CDN; the resulting URL is saved to `file`) |
| `file` | *alternatively*, a URL string if already hosted |
| `name` | display name |
| `description` | optional |

Accepted types (per rulebook §11.6): Images, PDF, Excel, Markdown. Images render as
inline thumbnails in the UI; other files show as clickable chips.

**201 Response**: the attachment. It now appears under the note's `attachments`:

```json
"attachments": [
  {
    "attachment_id": "…uuid…",
    "name": "site-survey.pdf",
    "file": "https://cdn…/site-survey.pdf",
    "description": null,
    "uploaded_at": "2026-06-14T09:41:00Z",
    "uploaded_by_id": "…user_id…"
  }
]
```

### Remove an attachment

```
DELETE /api/v1/crm/attachments/<attachment_id>/
```

> **Flow:** create the note (or reply) first, then upload attachments against the
> returned `note_id`. The note serialization re-reads its attachments on the next
> fetch.

---

## 5. Mentions & notifications

- **@mentions:** send `mentioned_user_ids` (a list of `user_id` UUIDs from the
  frontend user picker — the server does not parse `@name` from text). Ids are
  scoped to the note's org; foreign ids are ignored. On read they are expanded
  under `mentioned_users` (full user shape). Each mentioned user (except the
  author) receives a **`NoteMention`** notification.
- **Replies:** posting a reply dispatches a **`NoteReply`** notification to the
  parent note's author and prior distinct thread participants (excluding the
  actor).

Both use the standard notification pipeline (in-app bell + configured channels,
honouring user/org preferences). View them via `GET /api/v1/crm/notifications/`.

---

## 6. Source tags (Note Types)

The coloured tag on each note ("Call", "Email", …) is a **Note Type**.

```
GET  /api/v1/crm/note-types/           # list (ordered by position)
POST /api/v1/crm/note-types/           # admin — create { name, color, position, is_active, is_default }
```

`note_type` on a note references a `note_type_id`; it's returned nested on reads.
System-protected types (`is_readonly`) can't be edited/deleted, and a type can't
be deleted while notes reference it. Managing note types requires settings
permission.

---

## 7. Edit / delete a note

```
PATCH  /api/v1/crm/notes/<note_id>/     # edit content/title/is_pinned/note_type/mentions
DELETE /api/v1/crm/notes/<note_id>/     # delete (deleting a reply decrements the parent's reply_count)
```

The record link (`related_to`) is set at create time; a PATCH need not resend it.

---

## 8. Filters & search (list endpoint)

On `GET /api/v1/crm/notes/`:

- **Record scope (required for a panel):** `related_to=<model>` + `related_to_id=<uuid>`
  (also `related_to__in`, `related_to_id__in`).
- **Text:** `?search=<text>` (title + content), or `?title__icontains=` / `?content__icontains=`.
- **Pinned:** `?is_pinned=1`.
- **Author:** `?created_by=<user_id>` (`created_by__in`).
- **Date:** `?created_at_after=YYYY-MM-DD` / `?created_at_before=YYYY-MM-DD` (also `updated_at_*`).
- **Paging:** `?page=` / `?page_size=`.

The list always returns **top-level notes only**; use §3 to fetch a thread's replies.

---

## Example: full panel lifecycle for a Lead

```
# 1. Load the panel
GET  /api/v1/crm/notes/?related_to=lead&related_to_id=<lead_id>

# 2. Add a note tagged "Call", mentioning a teammate
POST /api/v1/crm/notes/
{ "content": "…", "related_to": "lead", "related_to_id": "<lead_id>",
  "note_type": "<call_type_id>", "mentioned_user_ids": ["<user_id>"] }

# 3. Attach the survey PDF to that note
POST /api/v1/crm/attachments/  (multipart)
  related_to=note  related_to_id=<note_id>  file_upload=@survey.pdf  name=survey.pdf

# 4. Reply in the thread
POST /api/v1/crm/notes/<note_id>/replies/
{ "content": "Good — keep phase 1 under ₹25L." }

# 5. Expand the thread later
GET  /api/v1/crm/notes/<note_id>/replies/
```

The same five calls work verbatim for **customers, products, tasks, follow-ups,
issues, and projects** — only `related_to` / `related_to_id` change.
