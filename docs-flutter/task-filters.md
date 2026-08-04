# Task Filters API

Backing for the **"Filter tasks by"** panel (the side-sheet with Assignee,
Task type, Priority and Due date, each with an **is / is not** toggle where
applicable), plus **Save view** (saved filters) and the **Kanban board**
(lanes + drag-drop status moves).

Three kinds of calls:

1. **Populate the panel** — small GET endpoints returning the option lists the
   user picks from (users, teams, statuses, priorities, task types).
2. **Apply the filters** — the same `GET /api/v1/crm/tasks/` list endpoint (and
   the `GET /api/v1/crm/tasks/board/` Kanban variant) with the query params below.
   There is **no** dedicated "filter" endpoint — filters are query params on the
   list. `TaskFilter` (`crm/filters/task.py`) is the single source of truth.
3. **Move a task's status** (Kanban drag-drop) — `PATCH /tasks/{id}/` for one card,
   `POST /tasks/bulk-status/` for many.

Auth for everything here: authenticated user. Reads are RBAC- and tenant-scoped.
Base prefix `/api/v1/crm/` unless noted (`/api/v1/management/` for users/teams).
Tasks and Follow-ups share this FilterSet; add `?is_followup=true` to scope to
follow-ups (it swaps the permission module and the schema/config keys).

---

## Part 1 — Populate the panel (option-list GETs)

All paginated (`StandardResultsSetPagination`, page size 100, `?page=`/`?page_size=`)
and most accept `?search=`. Cache per org — they change rarely.

| Panel section | Endpoint | Notes |
| :--- | :--- | :--- |
| **Assignee** | `GET /api/v1/management/users/` | Org users → use `user_id` as the value for `assigned_to` (and `assigned_by`). Supports `?search=`. |
| **Task type** | *(static)* | The type strings shown as chips (Call / Email / Meeting / Site visit / Quote / Follow-up / Admin / …). These are the org's configured task/follow-up types — for follow-ups, `GET /api/v1/crm/follow-up-types/`; regular task types come from the global `TaskType` set. Filter by the exact `task_type` string. |
| **Priority** | `GET /api/v1/crm/task-priorities/` | `{task_priority_id, name, color, weight, position}`. Use `task_priority_id` (or the `name` for name-matching). |
| **Status / Stage** (Kanban lanes) | `GET /api/v1/crm/crm-task-statuses/` | `{crm_task_status_id, name, status_type, color, position, is_active}`, position order. Use `crm_task_status_id` as `status_id`. |
| — status type catalog | `GET /api/v1/crm/crm-task-statuses/status-types/` | Read-only global fixed types (`open`/`in_progress`/`completed`/`cancelled`) if you need to group lanes by `status_type`. |
| **Team** | `GET /api/v1/management/teams/` | Org teams → use `team_id` for `assigned_team`. |

**Due date** needs no option endpoint — quick ranges + From/To pickers resolve to
a concrete `due_date_after`/`due_date_before` pair client-side (see below).

---

## Part 2 — Apply the filters

```
GET /api/v1/crm/tasks/?<params>
```

Standard list response (paginated, list-view-trimmed rows — only the columns the
org marked visible for the `task` list view, plus the always-present identity
fields `task_id`, `title`). All params combine with **AND**. Multi-value params
accept a **comma-separated** list (`?status__in=a,b`) and/or the **repeated-param**
form (`?assigned_to__in=a&assigned_to__in=b`). Every section supports **is**
(positive) and, where noted, **is not** (`__not`, implemented via `.exclude()`).

Same params also work on the Kanban board: `GET /api/v1/crm/tasks/board/`.

### Assignee (the panel's "is / is not" section)

The panel selects **users**; these map to the task's `assigned_to`.

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `assigned_to__in` | `?assigned_to__in=<user_id>,<user_id>` |
| is not | `assigned_to__not` | `?assigned_to__not=<user_id>,<user_id>` |

(Single-value `assigned_to=<user_id>` accepted.) Convenience:
`assigned_to_mode=me` (tasks assigned to the caller — the **"My tasks"** tab) or
`assigned_to_mode=unassigned` (omit for "all"). Also `unassigned=true|false`.
Assigned-by variants: `assigned_by` / `assigned_by__in` / `assigned_by__not`.

### Task type

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `task_type__in` | `?task_type__in=Call,Meeting` |
| is not | `task_type__not` | `?task_type__not=Call,Meeting` |

(Single-value `task_type=Call` accepted. Matches the exact `task_type` string.)

### Priority

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `priority__in` | `?priority__in=<task_priority_id>,<task_priority_id>` |
| is not | `priority__not` | `?priority__not=<task_priority_id>,<task_priority_id>` |

(Single-value `priority=<uuid>` accepted. `priority__name` / `priority__name__in`
match by name — "Low"/"Medium"/"High".)

### Status (Kanban lanes)

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `status_id` | `?status_id=<crm_task_status_id>` |
| is not | `status__not` | `?status__not=<crm_task_status_id>,<crm_task_status_id>` |

`status` / `status__in` also match by status **name** (case-insensitive,
underscore-tolerant: `in_progress` → "In Progress"). Use `status_id` (UUID) when
you need to pin a specific lane precisely (the board's "load more" uses it).

### Team

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `assigned_team__in` | `?assigned_team__in=<team_id>,<team_id>` |
| is not | `assigned_team__not` | `?assigned_team__not=<team_id>,<team_id>` |

Convenience: `my_team=true` → tasks on any team the caller belongs to.

### Due date (quick ranges + From/To)

Date-only range (inclusive). The chips resolve **client-side** to a concrete
`after`/`before` pair (like the Leads panel's Created chips); the From/To pickers
set them directly. The one exception, **Overdue**, is a server filter.

| Chip / field | Param(s) |
| :--- | :--- |
| **Overdue** | `is_overdue=true` (past due & not in a terminal status — completed/cancelled) |
| Today | `due_date_after=<today>&due_date_before=<today>` |
| Tomorrow | `due_date_after=<tomorrow>&due_date_before=<tomorrow>` |
| Next 7 / 30 / 60 / 90 days | `due_date_after=<today>&due_date_before=<today+N>` |
| From / To | `due_date_after=YYYY-MM-DD` / `due_date_before=YYYY-MM-DD` |

Aliases `due_date__gte` / `due_date__lte` also accepted. `is_completed=true|false`
filters by the completed **status type** (not name).

---

## Other useful list params (not in the panel but available)

- **Free-text search:** `?search=<text>` — matches title, description, location.
- **Follow-up scope:** `?is_followup=true|false`.
- **Archive scope:** `?is_archived=true|false` (list/board default to **not**
  archived; pass `true` to see only archived).
- **Related record:** `?related_to=lead` (by model) and `?related_to_id=<uuid>`
  (the linked record), plus `__in` variants.
- **Meeting window:** `meeting_from_after`/`_before`, `meeting_to_after`/`_before`.
- **Created / updated / completed:** `created_at_after`/`_before`,
  `updated_at_after`/`_before`, `completed_on_after`/`_before`.
- **Duration:** `duration_min` / `duration_max` (minutes).
- **Custom fields:** `?custom_fields.<name>=<value>` (needs the field's
  `filterable=true`). Ordering `?ordering=custom_fields.<name>` (needs `sortable`
  + a slot). Field catalog: `GET /api/v1/crm/tasks/schema/`.
- **Ordering / paging:** `?ordering=<field>` (default: incomplete first, newest
  first, then `task_id` as tiebreaker), `?page=`, `?page_size=`.

---

## Full example

Tasks that are **assigned to two users**, **not** of type **Call**, **High**
priority, on **Team North**, **not** in the **Completed** status, and **due in the
next 7 days**:

```
GET /api/v1/crm/tasks/
  ?assigned_to__in=<user1_id>,<user2_id>
  &task_type__not=Call
  &priority__in=<high_priority_id>
  &assigned_team__in=<team_north_id>
  &status__not=<completed_status_id>
  &due_date_after=2026-07-02&due_date_before=2026-07-09
```

**Reset All** = drop every filter param and re-fetch the bare list.

---

## Part 3 — Kanban board

```
GET /api/v1/crm/tasks/board/
GET /api/v1/crm/tasks/board/?is_followup=true       # follow-up board
GET /api/v1/crm/tasks/board/?lane_page_size=15       # cards/lane (default 20, max 50)
```

One call returns every active status as a lane (position order, zero-count lanes
included) with its `count` and first page of cards (list-view-trimmed, identical
to list rows), plus per-lane `next_page`/`next_url` for lazy "load more". Accepts
**all** the Part-2 filter params (and `custom_fields.*`, `saved_filter_id`).
Archived tasks excluded by default.

**Response**

```json
{
  "board_total": 165,
  "lane_page_size": 20,
  "lanes": [
    {
      "status_id": "<crm_task_status_id>",
      "status_name": "Open",
      "status_type": "open",
      "color": "#3B82F6",
      "position": 0,
      "count": 77,
      "cards": [ { "task_id": "...", "title": "...", "status": "Open", "related_to": {"model":"lead","id":"...","label":"..."}, "...": "" } ],
      "next_page": 2,
      "next_url": "/api/v1/crm/tasks/?status_id=<id>&page=2&page_size=20"
    }
  ]
}
```

**Load more within a lane** — when `count > lane_page_size`, follow `next_url`
(the list endpoint with `status_id` pinned + `page=2`), incrementing `page`. Pages
are disjoint from and contiguous with the board's first page (deterministic
`-created_at`, then `task_id`). `next_url` carries all active filters (including
`is_followup` and `saved_filter_id`) forward. Cached ~5 min; auto-invalidated on
any task write **and** any status add/rename/reorder/delete.

---

## Part 4 — Bulk actions (multi-select toolbar)

When rows are selected in the list, the toolbar exposes bulk operations. All are
**org- and RBAC-scoped** (each only touches tasks the caller may update/delete,
via `TaskService.get_base_queryset`), all accept `?is_followup=true` to target the
follow-up module, and all return `{ "success": true, "updated": <n>, "errors": [] }`.

| Bulk action | Request |
| :--- | :--- |
| Move / complete | `POST /tasks/bulk-status/` `{ task_ids, status_id }` |
| Change priority | `POST /tasks/bulk-priority/` `{ task_ids, priority_id }` |
| Archive / unarchive | `POST /tasks/bulk-archive/` `{ task_ids, is_archived }` |
| Assign to a user | `POST /tasks/bulk-assign/` `{ task_ids, assignee_id }` |
| Delete | `DELETE /tasks/bulk-delete/` `{ task_ids }` |

Common 400s across all four: `{"task_ids": "This field is required."}` and
`{"task_ids": "No valid tasks found."}`.

### Move a task's status (Kanban drag-drop)

### Single card

```
PATCH /api/v1/crm/tasks/{task_id}/
{ "status_id": "<crm_task_status_id>" }
```

Write the status by its `crm_task_status_id` (the read field `status` returns the
status **name**; writes go through `status_id`). Moving to a **completed**-type
status auto-stamps `completed_on`. A legacy `status` UUID on write is also accepted
and mapped onto `status_id`. Returns the updated task (200).

> Note: completing a task may be gated — if the org requires it, a task must have
> at least one linked note before it can move to a completed status (400 otherwise).

### Multiple cards (multi-select move)

```
POST /api/v1/crm/tasks/bulk-status/
{ "task_ids": ["<task_id>", "<task_id>"], "status_id": "<crm_task_status_id>" }
```

RBAC-scoped to tasks the caller may update. Stamps `completed_on` for cards moving
into a completed-type status. **200 Response**

```json
{ "success": true, "updated": 5, "errors": [] }
```

400s: `{"task_ids": "This field is required."}`,
`{"status_id": "Status not found or not in organization."}`,
`{"task_ids": "No valid tasks found."}`.

### Change task priority

```
POST /api/v1/crm/tasks/bulk-priority/
{ "task_ids": ["<task_id>", ...], "priority_id": "<task_priority_id>" }
```

Sets each selected task's `priority` in one query. `priority_id` must be a
`TaskPriority` in the caller's org (400 otherwise); it is required.

### Archive / unarchive tasks

```
POST /api/v1/crm/tasks/bulk-archive/
{ "task_ids": ["<task_id>", ...], "is_archived": true }
```

Sets `is_archived` on the selected tasks in one query (`is_archived=false`
un-archives). The list defaults to **not** archived, so archiving hides cards from
the default view. `is_archived` is required (400 if omitted).

### Assign tasks to a user

```
POST /api/v1/crm/tasks/bulk-assign/
{ "task_ids": ["<task_id>", ...], "assignee_id": "<user_id>" }
```

**Adds** the user to each task's `assignees` set (does not replace existing
assignees or the primary `assigned_to`). Idempotent — re-assigning the same user
is a no-op. Each newly-assigned task fires a `TaskAssigned` notification.
`assignee_id` must be a user in the caller's org (400 otherwise).

### Delete tasks

```
DELETE /api/v1/crm/tasks/bulk-delete/
{ "task_ids": ["<task_id>", ...] }
```

Hard-deletes the selected tasks (RBAC-scoped to the `delete` action). Returns the
count under `updated`. Requires `delete_task` (or `delete_followup`) permission.

---

## Part 5 — Saved Filters ("Save view")

The panel's selection can be persisted as a **saved filter** (the mock's
**Save view** button) and re-applied later. A saved filter stores the query-param
dict (`filter_definition`) and is re-applied via `?saved_filter_id=`.

Base path `/api/v1/crm/saved-filters/`. Backing model `SavedFilter`. CRUD is a
standard `ModelViewSet`. **A user only ever sees/edits their own filters** (scoped
to `request.user` + `request.org`). Reads need `view_settings`, writes need
`update_settings`.

**Limits & rules.**
- Max **5 saved filters per user per module** (400 on exceed).
- `(user, org, module, name)` is **unique** (duplicate name → 400).
- `module` ∈ `lead` | `task` | `followup`. For the tasks panel use **`task`**
  (or `followup` for the follow-up board).
- `visibility` is read-only (`private` in phase 1).
- `is_valid`/`invalid_reason` are server-set; a definition referencing a
  deactivated/purged custom field is stored `is_valid:false` and **fails inert**
  (never runs) until the field is restored.

### 1. List

```
GET /api/v1/crm/saved-filters/?module=task
```

`?module=` optionally scopes to one module. Ordered by `(module, order, created_at)`.

```json
[
  {
    "saved_filter_id": "…uuid…",
    "module": "task",
    "name": "My high-priority open tasks",
    "visibility": "private",
    "filter_definition": {
      "assigned_to_mode": "me",
      "priority__in": "<high_priority_id>",
      "status__not": "<completed_status_id>"
    },
    "is_valid": true,
    "invalid_reason": null,
    "order": 0,
    "created_at": "2026-07-02T09:12:44.512Z",
    "updated_at": "2026-07-02T09:12:44.512Z"
  }
]
```

### 2. Create

```
POST /api/v1/crm/saved-filters/
{
  "module": "task",
  "name": "My high-priority open tasks",
  "filter_definition": {
    "assigned_to_mode": "me",
    "priority__in": "<high_priority_id>",
    "status__not": "<completed_status_id>"
  },
  "order": 0
}
```

`filter_definition` is exactly the **query-param dict** from Part 2 (keys are
`TaskFilter` param names; values are the same strings you'd put in the URL —
comma-separated lists are fine). Every key is validated against `TaskFilter`'s
catalog + custom fields; **unknown keys → 400**:
`{ "filter_definition": "Unknown filter key(s): foo." }`. **201** returns the
created object.

### 3. Update / rename / reorder

```
PUT   /api/v1/crm/saved-filters/{saved_filter_id}/     # full
PATCH /api/v1/crm/saved-filters/{saved_filter_id}/     # partial
```

Editable: `name`, `filter_definition`, `order`. Same validation as create. **200**.

### 4. Delete

```
DELETE /api/v1/crm/saved-filters/{saved_filter_id}/
```

**204** on success.

### 5. Match count (optional, on demand)

```
GET /api/v1/crm/saved-filters/{saved_filter_id}/count/
```

Approximate count; cached 60s; **never** called implicitly on list render. Invalid
filter → `{ "count": null, "invalid_reason": "custom_fields.budget" }`.

### 6. Apply to the list / board

```
GET /api/v1/crm/tasks/?saved_filter_id=<uuid>
GET /api/v1/crm/tasks/board/?saved_filter_id=<uuid>
```

The stored `filter_definition` layers **under** any explicit params (explicit
params win) and runs through the same `TaskFilter`. Pagination is unchanged
(normal page-number). An **invalid** saved filter fails inert → **400**; an
unknown/foreign `saved_filter_id` → **404**. On the board, each lane's `next_url`
carries the `saved_filter_id` forward so "load more" stays consistent.

---

## Quick reference

| Purpose | Method & Path |
| :--- | :--- |
| Apply filters (list) | `GET /api/v1/crm/tasks/?<params>` |
| Apply filters (board) | `GET /api/v1/crm/tasks/board/?<params>` |
| "My tasks" | `?assigned_to_mode=me` |
| is / is not (assignee) | `assigned_to__in` / `assigned_to__not` |
| is / is not (status) | `status_id` / `status__not` |
| is / is not (priority) | `priority__in` / `priority__not` |
| is / is not (type) | `task_type__in` / `task_type__not` |
| Overdue | `?is_overdue=true` |
| Move one card | `PATCH /api/v1/crm/tasks/{task_id}/` `{ "status_id": "<uuid>" }` |
| Bulk move / complete | `POST /api/v1/crm/tasks/bulk-status/` `{ "task_ids": [...], "status_id": "<uuid>" }` |
| Bulk priority | `POST /api/v1/crm/tasks/bulk-priority/` `{ "task_ids": [...], "priority_id": "<uuid>" }` |
| Bulk archive | `POST /api/v1/crm/tasks/bulk-archive/` `{ "task_ids": [...], "is_archived": true }` |
| Bulk assign | `POST /api/v1/crm/tasks/bulk-assign/` `{ "task_ids": [...], "assignee_id": "<uuid>" }` |
| Bulk delete | `DELETE /api/v1/crm/tasks/bulk-delete/` `{ "task_ids": [...] }` |
| Save view (CRUD) | `/api/v1/crm/saved-filters/` (`module=task`) |
| Apply saved filter | `?saved_filter_id=<uuid>` |
| Panel: users | `GET /api/v1/management/users/` |
| Panel: priorities | `GET /api/v1/crm/task-priorities/` |
| Panel: statuses (lanes) | `GET /api/v1/crm/crm-task-statuses/` |
| Panel: teams | `GET /api/v1/management/teams/` |
