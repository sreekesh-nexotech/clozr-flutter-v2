# Task Schema, Status Types & View Config — Frontend API Guide

This document covers everything the frontend needs to render and manage the **Task
list/detail views**, the **Task status workflow**, and **task custom fields** —
bringing Tasks to full parity with the Lead module.

Three things changed on the backend; each has a frontend impact:

1. **Task status now has a fixed "status type" workflow** (like Lead). Every
   org-editable task status maps to one of four global, backend-fixed **types**
   (`open`, `in_progress`, `completed`, `cancelled`). Completion / cancellation
   are derived from the *type*, not the status name — so an admin can rename
   "Completed" to "Done" without breaking automation.
2. **The Task list *and detail* views have an org-configurable layout**
   (visibility, order, width, protected/fixed columns) — driven by the same Org
   View Settings engine as Lead. On a fresh org the defaults are seeded
   automatically: the list gets the fixed front block with `due_date` pinned last;
   the **detail page** gets exactly the attributes the UI renders (Type, Status,
   Priority, Due date, Due time, Duration, Assigned team, Related, Description,
   Assignees) with every other field hidden — see **§1c**.
3. **A new `related_to` column** surfaces the record a task is linked to
   (e.g. `Lead #L1001 — Kalyan Silks`) as a first-class, fixed list column.

All routes are under `/api/v1/crm/` (statuses/config) and
`/api/v1/management/` (field config / custom fields). Auth: authenticated user;
writes to config/statuses require **org admin** (or the relevant task/settings
permission).

---

## 1. Task list/detail schema — the column catalog

```
GET /api/v1/crm/tasks/schema/?view_type=list
GET /api/v1/crm/tasks/schema/?view_type=detail
GET /api/v1/crm/tasks/schema/?view_type=form            # add/edit form fields
GET /api/v1/crm/tasks/schema/?view_type=list&is_followup=true   # follow-up variant
```

This is the **single source of truth** for which columns to render, in what
order, and which are fixed. It auto-seeds org defaults on first access, so a new
org immediately gets a sensible layout. **Task** and **Follow-up** keep
independent configs (`model_name` `task` vs `followup`) — pass `is_followup=true`
for the follow-up board.

**200 Response** (shape identical to the Lead schema):

```json
{
  "model": "task",
  "view_type": "list",
  "has_org_config": true,
  "has_user_settings": false,
  "fields": { "...": "per-field metadata (type, choices, label) for form rendering" },
  "custom_field_definitions": [ /* see §4 */ ],
  "all_fields": {
    "columns": [
      { "name": "title",       "label": "Task",        "order": 1,  "visible": true,  "width": 220, "is_protected": true,  "is_fixed": true },
      { "name": "status",      "label": "Status",      "order": 2,  "visible": true,  "width": 120, "is_protected": true,  "is_fixed": true },
      { "name": "related_to",  "label": "Related To",  "order": 3,  "visible": true,  "width": 180, "is_protected": true,  "is_fixed": true },
      { "name": "priority",    "label": "Priority",    "order": 4,  "visible": true,  "width": 110, "is_protected": true,  "is_fixed": true },
      { "name": "assigned_to", "label": "Assigned To", "order": 5,  "visible": true,  "width": 150, "is_protected": true,  "is_fixed": true },
      { "name": "task_type",   "label": "Type",        "order": 6,  "visible": true,  "width": 120, "is_protected": false, "is_fixed": false },
      { "name": "due_time",    "label": "Due Time",    "order": 20, "visible": false, "width": 110, "is_protected": false, "is_fixed": false },
      { "name": "created_at",  "label": "Created On",  "order": 25, "visible": true,  "width": 130, "is_protected": false, "is_fixed": false },
      { "name": "due_date",    "label": "Due Date",    "order": 99, "visible": true,  "width": 130, "is_protected": true,  "is_fixed": true }
    ],
    "sorting": [],
    "filters": []
  }
}
```

**How to render the list:**

- Iterate `all_fields.columns` **in `order`** (already sorted ascending).
- Show a column only when `visible === true`.
- `is_fixed` / `is_protected` columns cannot be hidden or removed by the user in
  the "customize columns" panel — render their toggle as disabled/locked.
- `due_date` is intentionally pinned **last** (order 99); every other visible
  column falls between the fixed front block and it.
- Custom fields appear as columns named `custom_fields.<field_name>` when their
  `show_in_list` flag is on (see §4).

### Default fixed column set (seeded for every new org)

| Order | Field         | Fixed | Notes |
| :---- | :------------ | :---- | :---- |
| 1     | `title`       | ✅    | Header label is "Task" |
| 2     | `status`      | ✅    | Human-readable status name (see §2) |
| 3     | `related_to`  | ✅    | Linked record object (see §3) |
| 4     | `priority`    | ✅    | |
| 5     | `assigned_to` | ✅    | |
| 6+    | (other visible built-ins, then hidden ones) | | admins can toggle these |
| 99    | `due_date`    | ✅    | Always the last column |

---

## 1b. Task Kanban board

```
GET /api/v1/crm/tasks/board/
GET /api/v1/crm/tasks/board/?is_followup=true      # follow-up board
GET /api/v1/crm/tasks/board/?lane_page_size=15     # cards per lane (default 20, max 50)
```

Returns the whole Kanban board in **one** call: every active task status becomes a
lane (in `position` order, zero-count lanes included), each with its total `count`
and its first page of cards. Cards are **byte-identical to list rows** (same
list-view column trimming, same `related_to` object). Accepts **all** list filters
(`TaskFilter` + `custom_fields.*`) and the `is_followup` scope. Archived tasks are
excluded by default (pass `?is_archived=true` to include).

**200 Response**

```json
{
  "board_total": 165,
  "lane_page_size": 20,
  "lanes": [
    {
      "status_id": "ae1f2c13-...uuid",
      "status_name": "Open",
      "status_type": "open",
      "color": "#3B82F6",
      "position": 0,
      "count": 77,
      "cards": [ { "task_id": "...", "title": "...", "status": "Open", "related_to": { "...": "" }, "...": "" } ],
      "next_page": 2,
      "next_url": "/api/v1/crm/tasks/?status_id=ae1f2c13-...&page=2&page_size=20"
    },
    {
      "status_id": "b95ee674-...uuid",
      "status_name": "Completed",
      "status_type": "completed",
      "color": "#10B981",
      "position": 2,
      "count": 87,
      "cards": [ "..." ],
      "next_page": 2,
      "next_url": "/api/v1/crm/tasks/?status_id=b95ee674-...&page=2&page_size=20"
    }
  ]
}
```

**Load more within a lane** — when a lane's `count > lane_page_size`, `next_page`
and `next_url` are set. `next_url` points at the **existing list endpoint** with
`status_id` pinned to that lane and `page=2`. Follow the `next_url` (or build
`GET /api/v1/crm/tasks/?status_id=<id>&page=N&page_size=<lane_page_size>&<same filters>`),
incrementing `page` each time. Page N is **disjoint from and contiguous with** the
board's first page — same deterministic ordering (`-created_at`, then `task_id`).

Notes:
- The lane key is the status **UUID** (`status_id` = `crm_task_status_id`), so
  renaming a status doesn't break load-more.
- `next_url` carries forward all active filters (search, priority, custom fields,
  `is_followup`, `saved_filter_id`) so paging stays consistent with the board.
- Response is cached (~5 min) and auto-invalidated on any task write **and** on any
  task-status add/rename/reorder/delete.

---

## 1c. Task **detail page**

The detail page is rendered the **same way as the Lead detail page**: the schema
endpoint (`view_type=detail`) is the source of truth for the **dynamic "Task
information" section**, and the record endpoint returns the task data trimmed to
exactly the org-configured detail columns.

### Two calls per page

```
GET /api/v1/crm/tasks/schema/?view_type=detail        # what to render + order (once, cacheable)
GET /api/v1/crm/tasks/{task_id}/                       # the record itself (detail-trimmed)
```

Pass `?is_followup=true` on **both** for the follow-up detail page (independent
`followup` config).

### The dynamic "Task information" section

Drive it exactly like the list view (§1) but from the **detail** schema's
`all_fields.columns`:

- Iterate `all_fields.columns` in `order`, render each where `visible === true`.
- `field_info.type` tells you how to render each value (date, time, integer,
  string, foreignkey…).
- Custom fields flagged `show_in_detail` appear as `custom_fields.<name>` columns.

**Default detail columns seeded for a new org** (matches the UI "Task information"
panel — everything else is seeded `visible:false` so no internal field leaks):

| Order | Field           | Label         | Shown in UI as |
| :---- | :-------------- | :------------ | :------------- |
| 1     | `title`         | Task          | Header title |
| 2     | `task_type`     | Type          | Type |
| 3     | `status`        | Status        | Status (name string) |
| 4     | `priority`      | Priority      | Priority |
| 5     | `due_date`      | Due Date      | Due date |
| 6     | `due_time`      | Due Time      | Due time |
| 7     | `duration`      | Duration      | Duration (minutes) |
| 8     | `assigned_team` | Assigned Team | Assigned team |
| 9     | `related_to`    | Related To    | "Related" block (see §3) |
| 10    | `description`   | Description   | Description tab |
| 11    | `assigned_to`   | Assigned To   | "Owner & Assignees" block (primary) |
| 12    | `assignees`     | Assignees     | "Owner & Assignees" block (full set, §1e) |

> **What changed / gap fixed.** Previously the detail view only seeded a handful
> of fields, so the schema builder defaulted **every other model field to
> `visible:true`** on detail — leaking internal fields (`assigned_by`,
> `meeting_from`/`meeting_to`, `send_reminder`, `reminder_before`, `is_archived`,
> the custom-field slot columns `c_date_*`/`c_num_*`, etc.). The detail seed now
> lists the full catalog with those explicitly `visible:false`, exactly like the
> Lead detail seed. `duration` (shown in the UI, previously not in the catalog at
> all) was added. Existing orgs pick up the new defaults via the backfill in §6.

### The record endpoint (`GET /tasks/{task_id}/`)

Returns the task **trimmed to the detail-visible columns** (plus always-present
`task_id`, the `related_to` display object, and the merged `custom_fields`
object scoped to `show_in_detail`). The fields you receive line up with the
schema's visible detail columns — the response is config-driven, identical in
spirit to the Lead detail endpoint. Renaming/hiding a field via the org-field
config (§5, `view_type=detail`) instantly changes both this payload and the
schema.

```jsonc
GET /api/v1/crm/tasks/a5e90248-.../
{
  "task_id": "a5e90248-...",
  "title": "Call to discuss scope — Kalyan Silks",
  "task_type": "Call",
  "status": "To do",                 // name string (write via status_id, see §3)
  "priority": { "task_priority_id": "...", "name": "High", "color": "#EF4444", "...": "" },
  "due_date": "2026-06-16",
  "due_time": "11:00:00",
  "duration": 30,                    // minutes
  "assigned_team": { "team_id": "...", "name": "Team North" },
  "assigned_to": { "user_id": "...", "full_name": "Anjana", "...": "" },
  "assignees": [ { "user_id": "...", "full_name": "Anjana", "...": "" } ],  // full set (§1e)
  "related_to": { "model": "lead", "id": "<lead_id>", "label": "Kalyan Silks" },
  "description": "Intro call to understand the fit-out scope…",
  "custom_fields": { "...": "detail-scoped custom values" }
}
```

### The other detail-page panels (existing endpoints — no new work)

The header (title / priority / status dropdown), the **Description** tab, the
**Files** tab, and the **Audit log** are rendered from these:

| Panel | Endpoint |
| :---- | :------- |
| **Status dropdown / "Mark complete"** | `PATCH /api/v1/crm/tasks/{task_id}/` with `{"status_id": "<crm_task_status_id>"}` — auto-stamps `completed_on` when moving to a `completed`-type status. (Note-gate applies: a task needs ≥1 note before it can move to a completed status → **400** otherwise.) |
| **Edit** | `PATCH /api/v1/crm/tasks/{task_id}/` (any writable field; `view_type=form` schema lists them) |
| **Delete** | `DELETE /api/v1/crm/tasks/{task_id}/` |
| **Description** tab | the `description` field on the task object above (edit via `PATCH`) |
| **Files** tab — list | `GET /api/v1/crm/attachments/?related_to=task&related_to_id=<task_id>` |
| **Files** tab — upload | `POST /api/v1/crm/attachments/` (multipart) with `file_upload=<file>&related_to=task&related_to_id=<task_id>` |
| **Files** tab — delete | `DELETE /api/v1/crm/attachments/{attachment_id}/` |
| **Audit log** (bottom of page) | `GET /api/v1/access-control/audit-logs/?model_name=Task&record_id=<task_id>` (paginated, newest first) |

> **UI note (per product):** the right-hand tab strip should be **Description**
> and **Files only** — drop the redundant **Activity** tab. The page already has
> the full **Audit log** timeline at the bottom (Record created / Details updated /
> Owner set / Record viewed …), which is the same information, so a separate
> Activity tab is duplicative.

#### Audit log — details

```
GET /api/v1/access-control/audit-logs/?model_name=Task&record_id=<task_id>&ordering=-timestamp
```

- **`model_name` for a task is `Task`** (matched case-insensitively) — **not**
  `CRMTask`. Both regular tasks and follow-ups audit under `Task`. (`CRMTask`
  returns `count: 0` because no rows use that name.)
- `record_id` is the task's `task_id` (UUID). Add `&action__in=create,update,delete`
  to filter event kinds, `&page=N` to page (newest first via `ordering=-timestamp`).
- Task writes **are** audited: each `PATCH /tasks/{id}/` (status change, field edit)
  writes an `update` row whose `changes.request_body` holds exactly the fields the
  request touched. FK-UUID fields are enriched on read with a sibling
  `<field>_name` for display:

```jsonc
{
  "audit_log_id": "…",
  "action": "update",
  "model_name": "Task",
  "record_id": "<task_id>",
  "user": { "…": "" },
  "timestamp": "2026-07-02T17:…Z",
  "changes": {
    "request_body": {
      "status": "b95ee674-…",   "status_name": "Completed",   // ← resolved for display
      "priority": "483599f9-…", "priority_name": "High",
      "assigned_to": "b965275d-…", "assigned_to_name": "Anjana Menon",
      "task_type": "Call",       // plain choice string — no _name (not an FK)
      "description": "…"
    }
  }
}
```

> **Bug fixed (2026-07-02).** `GET …/audit-logs/?model_name=Task` previously
> returned **HTTP 500** (`"Call" is not a valid UUID`). Cause: the read-side
> name-enricher (`access_control/audit_names.py`) treated the CRM task's
> CharField `task_type` (e.g. `"Call"`) as if it were the PMO
> `projects.TaskType` FK and fed the string into a UUID lookup, crashing the
> whole page. Fixed two ways: (1) non-UUID values are now skipped before any FK
> lookup (defensive), and (2) the enricher is CRM-Task-aware — `status`/`priority`
> resolve against `crm.CRMTaskStatus` / `crm.TaskPriority` (giving the correct
> `status_name`/`priority_name`), while `task_type`/`related_to` are recognized as
> non-FK strings. The endpoint now returns **200** with the full task history.

---

## 1d. Creating a task / follow-up (the "Add task" modal)

Both the **Add task** and **Add follow-up** modals POST to the **same** endpoint;
the only difference is the `is_followup` flag, which changes how `task_type` is
validated and which permission module is checked.

```
POST /api/v1/crm/tasks/                    # regular task
POST /api/v1/crm/tasks/                    # follow-up — set "is_followup": true in the body
```

### Regular task

```jsonc
POST /api/v1/crm/tasks/
{
  "title": "Follow up with lead",                 // required
  "task_type": "Call",                            // required — one of the 5 fixed types (below)
  "due_date": "2026-04-18",                        // optional (YYYY-MM-DD)
  "description": "Call the lead to discuss requirements",  // optional
  "assigned_to": "<user_id>",                      // optional — the primary assignee ("Assign to")
  "assignees": ["<user_id>", "<user_id>"],         // optional — full multi-assignee set (§1e)
  "status_id": "<crm_task_status_id>",             // optional — defaults to the org's default status
  "priority": "<task_priority_id>",                // optional
  "related_to": "lead", "related_to_id": "<lead_id>"       // optional — link to a record (§3)
}
```

**`task_type` for a regular task must be one of the five fixed CRM types:**

| Value      | Modal label |
| :--------- | :---------- |
| `Task`     | Task        |
| `Call`     | Call        |
| `Meeting`  | Meeting     |
| `Email`    | Email       |
| `Deadline` | Deadline    |

Populate the modal's **Type** dropdown from the schema endpoint —
`GET /api/v1/crm/tasks/schema/?view_type=form` → `fields.task_type.choices`
(returns exactly these `{value, label}` pairs). Sending anything else returns:

```json
{ "code": 400, "message": "Validation Error",
  "errors": { "task_type": ["\"Xyz\" is not a valid task type. Valid types: Call, Deadline, Email, Meeting, Task."] } }
```

**201 Response** (abbreviated — full task object):

```jsonc
{
  "task_id": "8d4d91b9-…",
  "title": "Follow up with lead",
  "task_type": "Call",
  "is_followup": false,
  "status": "Open",                 // name string; server applies the org default
  "due_date": "2026-04-18",
  "related_to": { "…": "" }
}
```

### Follow-up

Identical call **plus `"is_followup": true`**. For a follow-up, `task_type` is
validated against the **org's Follow-up Types** (not the fixed list above), so the
modal's Type dropdown must be populated from the follow-up-types endpoint:

```
GET /api/v1/crm/follow-up-types/          # e.g. Call, Email, Meeting, WhatsApp, Site Visit
```

```jsonc
POST /api/v1/crm/tasks/
{
  "title": "Follow up with lead",
  "task_type": "Call",              // must be an active FollowUpType name for this org
  "is_followup": true,
  "due_date": "2026-04-18",
  "assigned_to": "<user_id>"
}
```

Invalid follow-up type → **400** `"…is not a valid follow-up type for your organization."`
Follow-ups also support reminders (`reminder_choice`) and auto-sync to Google
Calendar for the assignee.

### Modal dropdown data sources

| Modal field | Endpoint |
| :---------- | :------- |
| **Type** (regular task) | `GET /api/v1/crm/tasks/schema/?view_type=form` → `fields.task_type.choices` |
| **Type** (follow-up) | `GET /api/v1/crm/follow-up-types/` |
| **Assign to** (primary) / **Assignees** (multi) | `GET /api/v1/management/users/` (org users) — see §1e for the multi-assignee `assignees` field |
| **Status** (if shown) | `GET /api/v1/crm/crm-task-statuses/` (§2) |
| **Priority** (if shown) | `GET /api/v1/crm/task-priorities/` |

> **Bugs fixed (2026-07-02).**
> 1. Creating a **regular** task previously failed with `"…is not a valid task
>    type"` for *every* value, while the same payload with `is_followup: true`
>    succeeded. Cause: regular tasks were validated against the PMO
>    `projects.TaskType` table (unrelated to CRM tasks, and empty on CRM-only
>    orgs). They are now validated against the `Task.task_type` model choices —
>    the canonical CRM list (Task/Call/Meeting/Email/Deadline). Verified live:
>    `POST /tasks/` with `task_type:"Call"` and no `is_followup` now returns **201**.
> 2. **Follow-up types were not seeded on org registration** (only by the demo-data
>    command), so a newly-registered org had an empty `follow-up-types` list and
>    *every* follow-up create 400'd. New orgs are now seeded with
>    Call/Email/Meeting/WhatsApp/Site Visit on registration (mirrors the
>    task-status / priority seeding).

---

## 1e. Multiple assignees

A task now supports **0..N assignees** (parity with project tasks). There are two
related fields:

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `assigned_to` | single user | The **primary / owner** assignee — drives notifications, completion attribution, and the single-assignee filters. |
| `assignees` | list of users | The **full assignee set**. Always includes the primary. |

### Writing (`assignees`)

Send a **list of `user_id` UUIDs** on create or PATCH:

```jsonc
POST /api/v1/crm/tasks/         // or PATCH /api/v1/crm/tasks/{task_id}/
{
  "title": "Design review",
  "task_type": "Meeting",
  "assigned_to": "<user_a>",              // optional primary
  "assignees": ["<user_b>", "<user_c>"]   // full set
}
```

Sync rules (the server keeps `assigned_to` and `assignees` consistent):

- **No `assigned_to` + a non-empty `assignees`** → the **first** in the list
  becomes the primary `assigned_to`.
- **`assigned_to` set** → it is **always** added to the set, even if omitted from
  `assignees`.
- **PATCH with `assignees`** → **replaces** the whole set (then re-adds the
  primary). Send `"assignees": []` to clear the extras (the primary stays).
- **PATCH without `assignees`** → the set is left **unchanged**.
- Duplicates are de-duped; a user from **another org** → **400**
  (`"Cannot assign task to a user from a different organization."`).

### Reading (`assignees`)

On the **detail** view (and any response where the `assignees` column is visible),
each task embeds the full user objects — same shape as `assigned_to`:

```jsonc
{
  "assigned_to": { "user_id": "<user_a>", "full_name": "Anjana Menon", "…": "" },
  "assignees": [
    { "user_id": "<user_a>", "full_name": "Anjana Menon", "…": "" },
    { "user_id": "<user_b>", "full_name": "Rahul Nair",   "…": "" }
  ]
}
```

- `assignees` is **write-only as input** (a UUID list) and **read as embedded
  users** — mirrors `assigned_to`.
- To avoid an N+1 on large lists, `assignees` is emitted **only when the column is
  visible** for the view (it's a default **detail** column — the "Owner &
  Assignees" block — and hidden on the list). It won't bloat list/board rows.
- Notifications: creating/updating a task sends a **TaskAssigned** notification to
  each **newly-added** assignee (the primary and pre-existing assignees aren't
  re-notified; the creator is never self-notified).

> **Migration/backfill:** `assignees` is a new M2M (`crm/migrations/0018_task_assignees.py`)
> and a new default **detail** column. Existing orgs pick up the column via
> `manage.py backfill_task_list_config --all` (re-seeds list+detail); the M2M
> itself starts empty for existing tasks — the primary `assigned_to` is folded in
> the first time a task's assignees are written.

---

## 2. Task status workflow (status ↔ status type)

Tasks reference an org-editable **`CRMTaskStatus`**. Each status maps to exactly
one of four **global, backend-fixed** `TaskStatusType`s:

| `code`        | `name`        | Meaning                          |
| :------------ | :------------ | :------------------------------- |
| `open`        | Open          | Not started (org default)        |
| `in_progress` | In Progress   | Working                          |
| `completed`   | Completed     | Terminal — done                  |
| `cancelled`   | Cancelled     | Terminal — dropped               |

- The type set is **immutable** — clients cannot create/edit/delete types.
- Multiple org statuses may share a type (e.g. "Reviewing" and "Blocked" both
  map to `in_progress`).
- **Completion is derived from `status_type === "completed"`**, never from the
  status name. Overdue = past due date AND not in a terminal type
  (`completed`/`cancelled`).
- Per-org constraints: exactly one default status, at most one `completed`
  status, at most one `cancelled` status.

### 2.1 List the fixed status types (read-only, global)

```
GET /api/v1/crm/crm-task-statuses/status-types/
```

```json
[
  { "code": "open",        "name": "Open",        "position": 0 },
  { "code": "in_progress", "name": "In Progress", "position": 1 },
  { "code": "completed",   "name": "Completed",   "position": 2 },
  { "code": "cancelled",   "name": "Cancelled",   "position": 3 }
]
```

Use this to populate the **status-type dropdown** when an admin creates/edits an
org status.

### 2.2 CRUD org task statuses

```
GET    /api/v1/crm/crm-task-statuses/                      # list org statuses
POST   /api/v1/crm/crm-task-statuses/                      # create
GET    /api/v1/crm/crm-task-statuses/{crm_task_status_id}/ # retrieve
PATCH  /api/v1/crm/crm-task-statuses/{crm_task_status_id}/ # update
DELETE /api/v1/crm/crm-task-statuses/{crm_task_status_id}/ # delete
POST   /api/v1/crm/crm-task-statuses/reorder/             # bulk reorder
```

**Status object (read):**

```json
{
  "crm_task_status_id": "1f0e...uuid",
  "name": "In Progress",
  "color": "#F59E0B",
  "position": 1,
  "is_active": true,
  "is_default": false,
  "is_readonly": true,
  "status_type": "in_progress",
  "status_type_name": "In Progress",
  "is_completed": false,
  "is_cancelled": false
}
```

- **Write** `status_type` by its **code** string (e.g. `"completed"`), same as the
  read value. It's optional/nullable but should always be set for new statuses.
- `status_type_name`, `is_completed`, `is_cancelled` are **read-only** derived
  fields — do not send them on write.
- `is_readonly === true` marks a system-seeded status — the API blocks
  edit/delete for non-superusers; disable those buttons in the UI.

**Create example:**

```json
POST /api/v1/crm/crm-task-statuses/
{
  "name": "Blocked",
  "color": "#EF4444",
  "position": 2,
  "status_type": "in_progress"
}
```

**Reorder:**

```json
POST /api/v1/crm/crm-task-statuses/reorder/
[
  { "crm_task_status_id": "uuid-a", "position": 0 },
  { "crm_task_status_id": "uuid-b", "position": 1 }
]
```

**Delete guard rails (expect 400):**

- Deleting a status referenced by existing tasks → *"…referenced by existing tasks."*
- Deleting the **last** status mapped to a given type → *"Cannot delete the last
  task status mapped to its status type."* (every type must keep ≥1 status).
- Deleting/editing a system (`is_readonly`) status as a non-superuser.

Related endpoints (unchanged, listed for completeness):
`/api/v1/crm/task-priorities/`, `/api/v1/crm/follow-up-types/`.

---

## 3. The `related_to` column

Tasks link to a CRM record (lead, customer, product, issue, quotation, …) via a
generic relation. The **read** representation on every task object is:

```json
"related_to": {
  "model": "lead",
  "id": "9648d3f1-6605-4f0f-b99b-6d0cc45066d0",
  "label": "Ishaan Malhotra 1"
}
```

- `model` — the linked record's type (`lead`, `customer`, `product`, `issue`,
  `quotation`, `deal`, `contact`).
- `id` — the record's UUID (e.g. `lead_id`). Use it to deep-link to the record.
- `label` — a human display name resolved server-side (lead name, customer name,
  product name, etc.); may be `null` if the record has no name or its type isn't
  labelable.
- `related_to` is `null` when the task isn't linked to anything.

**Writing the link** is unchanged — send the *write-only* pair on create/update:

```json
POST /api/v1/crm/tasks/
{
  "title": "Call to discuss scope",
  "task_type": "Call",
  "status_id": "<crm_task_status_id>",
  "related_to": "lead",
  "related_to_id": "<lead_id>"
}
```

> Note on `status` vs `status_id`: on **read**, tasks expose `status` as the
> human status **name** string. On **write**, send `status_id` (the
> `crm_task_status_id` UUID). A legacy `status` UUID on write is still accepted
> and mapped onto `status_id` for backward compatibility.

---

## 4. Task custom fields

Task custom fields use the **same** engine and endpoints as Lead/Customer, scoped
by `model_name=task`:

```
GET/POST      /api/v1/management/custom-fields/?model_name=task
PATCH/DELETE  /api/v1/management/custom-fields/{id}/
POST          /api/v1/management/custom-fields/reorder/
POST          /api/v1/management/custom-fields/{id}/purge/
```

- Max **10** custom fields per model. Only Date/Number fields are sortable
  (backed by physical slot columns); the rest live in a JSON blob.
- On task read/write, custom values are exposed under a merged `custom_fields`
  object. Filter with `?custom_fields.<name>=value` and sort with
  `?ordering=custom_fields.<name>` (slot-backed fields only).
- The task schema endpoint (§1) returns `custom_field_definitions` and injects
  `custom_fields.<name>` columns for fields flagged `show_in_list` /
  `show_in_detail`.

See `docs/working/org-view-settings-api.md` and the custom-fields section of the
Lead docs for the full field-definition payload — it is identical for tasks.

---

## 5. Editing the Task column layout (admin)

Reuse the Org View Settings API with `model_name=task` (or `followup`):

```
GET /api/v1/management/org-field-config/?model_name=task&view_type=list
GET /api/v1/management/org-field-config/?model_name=task&view_type=detail   # detail-page layout
PUT /api/v1/management/org-field-config/         # admin only (per view_type)
```

The **detail** layout is edited the same way — send `"view_type": "detail"` in the
PUT body to change which attributes appear in the detail page's "Task information"
section (and their order). Detail has no fixed/protected columns, so any field can
be toggled.

```json
PUT /api/v1/management/org-field-config/
{
  "model_name": "task",
  "view_type": "list",
  "fields": [
    { "field_name": "due_time", "order": 7, "is_visible": true, "width": 110, "label_override": null }
  ]
}
```

- `order` values must be **unique** within the payload.
- Attempting to hide a **fixed** column (`title`, `status`, `related_to`,
  `priority`, `assigned_to`, `due_date`) returns **400** — keep those toggles
  locked in the UI.
- After a successful `PUT`, re-fetch the schema (§1) to re-render.

Full request/response contract: `docs/working/org-view-settings-api.md`.

---

## 6. Seeding on org registration (FYI — no frontend action)

- **Global** `TaskStatusType` rows are seeded once by migration
  (`crm/migrations/0017_task_status_type.py`) and by
  `manage.py seed_crm_defaults`.
- **Per-org** default task statuses (Open/In Progress/Completed/Cancelled, each
  mapped to its type), **task priorities** (low/medium/high/critical), and
  **follow-up types** (Call/Email/Meeting/WhatsApp/Site Visit) are all seeded
  automatically when the organization is created.
- **Per-org** task column config is seeded **lazily** the first time the schema
  or org-field-config endpoint is hit for `task`/`followup` — so the very first
  `GET .../tasks/schema/` for a new org returns the full default layout.
- For **existing** orgs (seeded before this change), run:
  `manage.py backfill_task_list_config --all` (add `--dry-run` to preview,
  `--force` to overwrite customized orgs).

---

## Quick reference

| Purpose | Method & Path |
| :------ | :------------ |
| Task list columns | `GET /api/v1/crm/tasks/schema/?view_type=list` |
| Task detail fields | `GET /api/v1/crm/tasks/schema/?view_type=detail` |
| **Task detail record** | `GET /api/v1/crm/tasks/{task_id}/` (detail-trimmed) |
| Task detail — move status | `PATCH /api/v1/crm/tasks/{task_id}/` `{ "status_id": "<id>" }` |
| Task detail — files (list) | `GET /api/v1/crm/attachments/?related_to=task&related_to_id=<task_id>` |
| Task detail — files (upload) | `POST /api/v1/crm/attachments/` (multipart, `related_to=task`) |
| Task detail — audit log | `GET /api/v1/access-control/audit-logs/?model_name=Task&record_id=<task_id>` |
| **Task Kanban board** | `GET /api/v1/crm/tasks/board/` (`?lane_page_size=`, `?is_followup=true`) |
| Board lane "load more" | `GET /api/v1/crm/tasks/?status_id=<id>&page=N&page_size=<n>` |
| Follow-up variant | add `&is_followup=true` |
| Fixed status types | `GET /api/v1/crm/crm-task-statuses/status-types/` |
| Org task statuses (CRUD) | `/api/v1/crm/crm-task-statuses/` |
| Reorder statuses | `POST /api/v1/crm/crm-task-statuses/reorder/` |
| Task custom fields | `/api/v1/management/custom-fields/?model_name=task` |
| Edit task columns (admin) | `GET/PUT /api/v1/management/org-field-config/` (`model_name=task`) |
| List/create tasks | `/api/v1/crm/tasks/` |
| **Create task** (Add-task modal) | `POST /api/v1/crm/tasks/` (`task_type` ∈ Task/Call/Meeting/Email/Deadline) |
| **Multiple assignees** | `assignees: ["<user_id>", …]` on create/PATCH (§1e) — read back as embedded users on detail |
| **Create follow-up** | `POST /api/v1/crm/tasks/` + `"is_followup": true` (`task_type` = a FollowUpType) |
| Follow-up types (modal dropdown) | `GET /api/v1/crm/follow-up-types/` |
| "Assign to" users (modal dropdown) | `GET /api/v1/management/users/` |
