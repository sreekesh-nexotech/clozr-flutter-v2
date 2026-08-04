# Operations → Tasks — Frontend Integration

Backend endpoints for the **Operations / Tasks** screens — the top-level task
**list** (§1–2, §4–5) and the task **detail page** (§3, §3A–3E). Both are
distinct from the per-project task lanes on the project detail page, which live
in [operations.md](operations.md) Part B.

**Detail page quick index:** [§3 retrieve](#3-task-detail-retrieve) ·
[§3A completed lock](#3a-completed-task-field-lock) ·
[§3B activity/audit](#3b-task-activity--audit-log) ·
[§3C subtasks](#3c-subtasks-tab) ·
[§3D dependencies](#3d-dependencies-waiting-on--blocking) ·
[§3E notes & files](#3e-notes--files-on-a-task)

The list page has:

- the **task list table** (Task + sub-label, Status pill, Project, Priority,
  Assigned-to avatars, Expected end, row actions),
- the **status tab strip** (`All (3) · Open (1) · Working (0) · Pending Review
  (0) · Completed (2) · Cancelled (0)`),
- the **"My Tasks" / "All"** scope toggle,
- the **filter drawer** — Project / Status / Priority / Type / Assignee facets,
  each with an **is / is not** toggle, plus a **"Milestones only"** checkbox,
- **column sorting**, **search**, the **List / Kanban** view toggle (Kanban is
  a separate board endpoint, out of scope here), and the **saved-filter chips**
  row (bookmark toggle → "My Tasks" / "All").

Base path: `/api/v1/projects/` (task resources) and `/api/v1/crm/`
(saved filters — shared endpoint across all modules).

> **Field-name note.** The task's title field is **`subject`** (the UI labels
> the column "Task"). The Type facet is the org's **`TaskType`** set
> (Design / Procurement / Installation …); Status is the org's
> **`ProjectTaskStatus`** set (Open / Working / … ) — the SAME statuses used by
> the project detail lanes.

## Common headers

| Header          | Value                          | Notes |
|-----------------|--------------------------------|-------|
| `Authorization` | `Bearer <access JWT>`          | The token's `organization_id` claim scopes every query to the org. Required. |
| `Content-Type`  | `application/json`             | For `POST`/`PATCH`/`PUT`/`QUERY` JSON bodies. |

No CSRF token is needed — the API is JWT-authenticated.

Common error envelope (DRF, via the global exception handler):

```json
{ "code": 403, "message": "Permission Denied", "errors": { "detail": "You do not have permission to perform this action." } }
```

- **401** — missing/expired token.
- **403** — RBAC: list/detail need `view_task`; writes need `create_task` /
  `update_task` / `delete_task`. Also returned when the org's plan lacks the
  `projects` feature, when the org is inactive, or when the Razorpay mandate
  gate blocks the org.
- **404** — task not in the caller's org / outside their record-level scope
  (hierarchy / team / owned visibility — a task you can't see 404s, never
  disclosed).

**Record-level scope.** The task list is scoped by
`ProjectTaskService.get_base_queryset` — the single source of truth shared with
the AI tool layer. Precedence is the standard resolver (`all > hierarchy > team
> owned > assignee`), so a plain member sees only the tasks their role's
record-permission grants, not every task in the org.

Pagination (all list endpoints): standard envelope, page size 100.

```json
{ "count": 3, "next": null, "previous": null, "results": [ … ] }
```

---

## 1. Task list (table view)

### Name / purpose
List tasks for the table — powers the rows, the search box, the filter drawer,
the "My Tasks"/"All" toggle, sorting, and saved-filter application.

### Method + path
`GET /api/v1/projects/tasks/`
`QUERY /api/v1/projects/tasks/` — same endpoint, **filter params in the request
body** instead of the URL (parity with Leads/Customers/Projects). Use it when
the drawer builds long facet sets that would blow past URL-length limits.

```
QUERY /api/v1/projects/tasks/?page=1&ordering=exp_end_date
Content-Type: application/json

{
  "status__in": ["<uuid>", "<uuid>"],       // JSON lists supported
  "priority__not_in": "Low",
  "type__in": "<uuid>,<uuid>",
  "is_milestone": true                       // booleans supported
}
```

The body carries **filter params only** (the facet/search keys in the table
below). Control params — `page`, `page_size`, `saved_filter_id`, `ordering` —
stay in the URL query string; body-supplied copies are **ignored**. On a key
collision the body wins over the URL. Response, errors, and pagination are
identical to GET. QUERY responses are never served from the list cache.

### Headers
Common headers (GET: auth only — no body. QUERY: plus `Content-Type: application/json`).

### Path / query params

**Multi-value transport:** every `__in` / `__not_in` param accepts **both**
forms and merges them — CSV (`?p=a,b`), repeated (`?p=a&p=b`), or mixed
(`?p=a,b&p=c` → `[a,b,c]`). In a QUERY body or a saved-filter definition, a
native JSON array works too.

Facet params (filter drawer):

| Param | Type | Purpose |
|---|---|---|
| `search` | string | Case-insensitive match on the task **subject** (search box). |
| `project__in` | csv of `project_id` UUIDs | Project facet, **is** mode. |
| `project__not_in` | csv of UUIDs | Project facet, **is not**. Standalone (no-project) tasks are kept. |
| `status__in` | csv of `project_task_status_id` UUIDs | Status facet, is. |
| `status__not_in` | csv of UUIDs | Status facet, is not. Tasks with **no status** are kept. |
| `priority__in` | csv of `Urgent,High,Medium,Low` | Priority facet, is. |
| `priority__not_in` | csv | Priority facet, is not. |
| `type__in` | csv of `task_type_id` UUIDs | Type facet, is (Design / Procurement / Installation …). |
| `type__not_in` | csv of UUIDs | Type facet, is not. Tasks with **no type** are kept. |
| `assignees__in` | csv of `user_id` UUIDs | Assignee facet, is — matches any task where **any** of these users is an assignee (multi-assignee M2M). |
| `assignees__not_in` | csv of UUIDs | Assignee facet, is not — tasks where **none** of these users is an assignee (tasks with an empty assignee set are kept). |
| `is_milestone` | `true` | **"Milestones only"** checkbox. |
| `my_tasks` | `true` | **"My Tasks"** toggle — tasks the caller is on via the primary assignee FK **or** the M2M. Omit / `All` = no-op. |

Single-value / convenience params (same facets, singular form):
`project=<uuid>`, `status=<uuid>`, `priority=High`, `type=<uuid>`,
`assignees=<uuid>` (any-assignee), `assigned_to=<uuid>` (the primary FK only),
`assigned_to__in`.

Other useful params: `ownership=all|me|unassigned`, `unassigned=true`
(nobody on it at all), `is_standalone=true|false` (no project / has project),
`task_group=<uuid>`, `task_group_isnull=true`, `is_subtask=true|false`,
`has_subtasks=true|false`, `parent=<task_uuid>` (a task's direct subtasks),
`is_overdue=true|false`, `due_within_days=N`,
`last_updated=today|this_week|this_month`,
`start_date_after|before`, `end_date_after|before`.

Sorting:

| Param | Values |
|---|---|
| `ordering` | One of `subject`, `priority`, `progress`, `exp_start_date`, `exp_end_date`, `completed_on`, `created_at`, `updated_at`, `status__position`, `project__project_name`, `assigned_to__first_name` — prefix with `-` for descending. Unknown values are ignored. Default: `-created_at`. |

Representation:

| Param | Values |
|---|---|
| `view` | `list` → a **slim 19-field** row for the table/lane: `task_id, subject, project, project_name, task_group, task_group_name, type, task_type_name, status, status_name, priority, is_milestone, pending_dependency_count, is_overdue, progress, computed_progress, assigned_to, assignees, exp_end_date`. Drops costing/billing totals, template/parent linkage, duration/time bookkeeping, and the nested `created_by`/`modified_by`. `assigned_to` collapses to `{user_id, full_name}`; `assignees` keeps its embedded stack. Applies to GET/QUERY **list** only — the detail retrieve always returns the full shape. Omit for the full row. |

Saved filter:

| Param | Purpose |
|---|---|
| `saved_filter_id` | Apply a stored filter (module **`project_task`**) as a base layer; explicit query params above override its stored keys. See §4. |

Pagination: `page`, `page_size`.

### Request body
GET: none. QUERY: JSON object of **filter params only** — values may be
scalars, CSV strings, booleans, or native JSON arrays. Control params (`page`,
`page_size`, `saved_filter_id`, `ordering`) belong in the URL, not the body.

### Success response
`200 OK`

```jsonc
{
  "count": 3,
  "next": null,
  "previous": null,
  "results": [
    {
      "task_id": "5cbf187a-…",
      "subject": "Snag list & handover",           // TASK column (title)
      "project": "0e1b9270-…",                      // project_id UUID (null ⇒ standalone)
      "project_name": "Technopark Tejaswini — 4F office interiors",  // PROJECT column
      "project_type_name": "Implementation",        // (null if the project has no type)
      "task_group": "7f39d91e-…",                   // lane on the detail page (null ⇒ "No group")
      "task_group_name": "Site Work",               // sub-label under the task title
      "type": "fb59b033-…",                          // task_type_id UUID (null ⇒ no type)
      "task_type_name": "Installation",
      "status": "acb8c200-…",                        // project_task_status_id UUID (null ⇒ no status)
      "status_name": "Open",                         // STATUS pill label
      "priority": "High",                            // PRIORITY pill (Urgent | High | Medium | Low)
      "is_milestone": true,                          // 🚩 milestone flag on the row
      "pending_dependency_count": 1,                 // "Waiting on N" badge (0 ⇒ hidden)
      "assigned_to": {                               // primary assignee (nested user or null)
        "user_id": "f126141c-…",
        "email": "manoj@…",
        "first_name": "Manoj",
        "last_name": "Varma",
        "full_name": "Manoj Varma",
        "is_active": true
      },
      "assignees": [                                 // full assignee set → avatar stack ("+1")
        { "user_id": "f126141c-…", "first_name": "Manoj", "last_name": "Varma", "email": "…" }
      ],
      "exp_start_date": "2026-06-28T06:13:41Z",
      "exp_end_date": "2026-06-30T06:13:41Z",        // EXPECTED END column
      "is_overdue": false,                           // red date when true
      "progress": "0.000000",
      "computed_progress": 0.0,                      // subtask rollup for parents (JSON number)
      "subtask_count": 0,
      "comment_count": 0,
      "organization": "91a35d33-…",
      "company_name": "Nexotech",
      "created_by": { "user_id": "…", "first_name": "…", "last_name": "…", "email": "…" },
      "modified_by": null,
      "created_at": "2026-06-28T06:13:41Z",
      "updated_at": "2026-06-28T06:13:41Z"
      // …plus costing/billing/date fields not used by this screen
    }
  ]
}
```

### Error responses
- `400` — invalid filter value, or a broken saved filter (fails **inert**,
  never runs widened; a stored definition whose *value* fails field validation
  400s with the field errors rather than silently widening).
- `401` / `403` / `404` — see the common table above.

### Pagination
Standard envelope, page size 100; `page` / `page_size`.

---

## 2. Status tab counts

### Name / purpose
Per-status task counts for the header tab strip
(`All (3) · Open (1) · Working (0) · … · Cancelled (0)`). Every active status
is returned **zero-filled** so the tab strip is stable.

### Method + path
`GET /api/v1/projects/tasks/status-counts/`
`QUERY /api/v1/projects/tasks/status-counts/` — same aggregate, **filter params
in the body** (parity with the list, §1), so the tab strip and the list can
share one transport. Returns `{total, no_status, statuses}` (never the list
payload).

### Headers
Common headers (GET: auth only. QUERY: plus `Content-Type: application/json`).

### Path / query params
Accepts the **same** filter params as the list (§1) **except the status facet**
(`status`, `status__in`, `status__not_in`) — those are stripped so selecting a
Status tab doesn't zero out the other tabs. Every other active facet still
narrows the counts (e.g. `priority__in`, `my_tasks`, `project__in`,
`saved_filter_id`).

### Request body
None.

### Success response
`200 OK`

```jsonc
{
  "total": 3,          // the "All" tab
  "no_status": 0,      // tasks with no status assigned (still counted in "total")
  "statuses": [
    { "project_task_status_id": "…", "status": "Open",          "color": "#…", "position": 0, "is_closed": false, "is_cancelled": false, "count": 1 },
    { "project_task_status_id": "…", "status": "Working",        "color": "#…", "position": 1, "is_closed": false, "is_cancelled": false, "count": 0 },
    { "project_task_status_id": "…", "status": "Pending Review", "color": "#…", "position": 2, "is_closed": false, "is_cancelled": false, "count": 0 },
    { "project_task_status_id": "…", "status": "Completed",      "color": "#…", "position": 3, "is_closed": true,  "is_cancelled": false, "count": 2 },
    { "project_task_status_id": "…", "status": "Cancelled",      "color": "#…", "position": 4, "is_closed": true,  "is_cancelled": true,  "count": 0 }
  ]
}
```

`total == count` on the list endpoint with the same non-status filters applied.

### Error responses
`401` / `403` — see common table.

---

## 3. Task detail (retrieve)

### Name / purpose
Full task record — powers the **task detail page** (header, Task-information
panel, Subtasks/Description/Files tabs, Dependencies) and the row's "view" (👁)
action.

### Method + path
`GET /api/v1/projects/tasks/{task_id}/`

### Success response
`200 OK` — the full task object (the same shape as a list row, above, plus the
costing/billing/date/template fields) with these **detail-only additions**:

| Field | Type | Drives |
|---|---|---|
| `task_code` | string \| null | The **Task ID** row — `"PRJ-1010-t3"`. Composed from the project's generated code + this task's per-project ordinal. `null` for a standalone task (no project) or a project whose code was never minted — fall back to the UUID. |
| `subtask_done_count` | int | The right half of the Subtasks tab's **"N/M done"** counter (`subtask_done_count`/`subtask_count`). Counts direct subtasks in a **closed** status. |
| `dependencies` | array | **"Waiting on"** — the tasks this task depends on. |
| `dependents` | array | **"Blocking"** — the tasks waiting on this one. |

Both dependency arrays use the same element shape, resolved server-side so no
second fetch is needed to label a chip:

```jsonc
{
  "task_depends_on_id": "…",   // DELETE this id to remove the edge (§6)
  "task_id": "…",              // the OTHER task in the edge
  "subject": "Electrical first fix",   // chip label
  "status": "acb8c200-…",
  "status_name": "Open",
  "is_closed": false
}
```

> `dependencies` / `dependents` are **detail-only** — they are omitted from list
> rows so a 100-row page doesn't pay for the extra joins. On the list, use the
> scalar `pending_dependency_count` ("Waiting on N" badge) instead.

Other panel fields already present on the full object: `department` (free text —
there is no Department model, so no lookup endpoint), `color` (the **Color tag**
swatch, free-form string), `is_milestone`, `exp_start_date`, `exp_end_date`,
`assignees` (avatar list), `description`, `progress` / `computed_progress`.

### Error responses
`401` / `403` / `404` (out of the caller's record scope).

---

## 3A. Completed-task field lock

The banner **"This task is completed — fields are locked. Reopen to edit."** is
**enforced server-side**, not just in the UI.

While a task sits in a **closed** status (`is_closed=true`, cancelled included),
`PATCH /tasks/{task_id}/` rejects edits to any other field with `400`:

```jsonc
// PATCH {"subject": "Renamed", "priority": "Low"}  → 400
{ "code": 400, "message": "…", "errors": {
    "subject":  "This task is completed and its fields are locked. Reopen the task to edit.",
    "priority": "This task is completed and its fields are locked. Reopen the task to edit."
}}
```

Every locked field in the request is reported, so the client can highlight them all.

**Always writable while closed:** `status` (changing it *is* the reopen),
`completed_by`, `completed_on`, `progress` — these follow the status transition
rather than being user edits.

**Reopening:** `PATCH {"status": "<open-status-uuid>"}`. A reopen request **may
carry other field edits in the same call** — moving to a non-closed status
unlocks the rest of the payload, so "reopen and rename" is one round-trip.

> This is the inverse of the pre-existing **completion transition** rule (a task
> can't *enter* a closed status while its subtasks or dependencies are still
> open — also a `400`, on the `status` key). The two work together: gated on the
> way in, locked once in.

---

## 3B. Task activity / audit log

### Name / purpose
The detail page's **Audit log** panel ("Milestone reached — Manoj Varma ·
3 months ago").

### Method + path
`GET /api/v1/projects/tasks/{task_id}/activity/`

Mirrors the project equivalent (`/projects/{id}/activity/`). Gated by
**`view_task`** on a task the caller can already see — so a PM **without**
`view_audit_log` still reads their own task's history, unlike the org-wide
`/api/v1/access-control/audit-logs/` endpoint (which 403s for them).

### Success response
`200 OK` — paginated `AuditLog` rows for **this task only**, newest first, each
carrying a server-rendered `summary` + `event_type` on top of the raw diff:

```jsonc
{
  "count": 4, "next": null, "previous": null,
  "results": [
    {
      "summary": "Milestone reached",          // pre-humanized — render as-is
      "event_type": "field_changed",           // stable enum (below)
      "action": "update",
      "user_full_name": "Manoj Varma",
      "user_email": "manoj@…",
      "timestamp": "2026-04-17T08:00:00Z",
      "changes": { "request_body": { "is_milestone": true } }   // raw diff kept
    }
  ]
}
```

`event_type` enum: `created | updated | field_changed | deleted |
child_created | child_updated | child_deleted`.

Humanized summaries include `"Task created"`, `"Status changed to Completed"`,
`"Priority changed to High"`, `"Assignee changed to …"`, `"Expected end changed
to …"`, and the special-cased **`"Milestone reached"`** when `is_milestone`
flips on. `changes` is always preserved for tooling.

> **Scope:** the feed covers **direct edits to the task**. Child events
> (comments, notes, attachments, subtask writes) roll up to the **parent
> project's** feed, not the task's — read `/projects/{project_id}/activity/`
> for those.

### Error responses
`401` / `403` (no `view_task`) / `404` (task outside the caller's scope).

---

## 3C. Subtasks tab

| Need | Call |
|---|---|
| **"N/M done" counter** | Already on the detail payload: `subtask_done_count` / `subtask_count`. No extra call. |
| **List the subtasks** | `GET /api/v1/projects/tasks/?parent=<task_id>` — standard paginated list; add `&view=list` for slim rows. |
| **Add a subtask** (inline input) | `POST /api/v1/projects/tasks/` with `{"parent_task": "<task_id>", "subject": "…", "project": "<project_id>"}`. |
| **Tick a subtask done** | `PATCH /api/v1/projects/tasks/{subtask_id}/` with `{"status": "<closed-status-uuid>"}`. |

> `bulk-create` does **not** accept subtasks (it rejects rows with `parent_task`
> set, returning the offending indices) — create them one at a time.

Note the parent's own completion is gated: closing a parent while a subtask is
still open returns `400` on `status` (see §3A).

---

## 3D. Dependencies ("Waiting on" / "Blocking")

Read them **inline from the task detail** (§3, `dependencies` / `dependents`).
Mutations go through the edges collection:

| UI action | Method + path | Body |
|---|---|---|
| **+ Add** a blocker | `POST /api/v1/projects/task-dependencies/` | `{"task": "<this_task_id>", "depends_on": "<blocker_task_id>"}` |
| **×** Remove a blocker | `DELETE /api/v1/projects/task-dependencies/{task_depends_on_id}/` | — |
| List edges directly | `GET /api/v1/projects/task-dependencies/?task=<id>` (waiting-on) or `?depends_on=<id>` (blocking) | — |

Permissions: reads need `view_task`; **create/delete need `update_task`**.

Validation (all `400`): self-dependency, duplicate edge, cross-org, cross-project
(unless the org's `allow_cross_project_dependencies` setting is on), and
**cycle detection** (BFS over the graph).

> **Deleting a task that another task depends on is blocked** — remove the edge
> first, so unblocking is never silent. The delete returns **409 Conflict** with
> the blockers named, so the toast can be specific:
>
> ```jsonc
> { "detail": "Cannot delete this task because other tasks depend on it.",
>   "errors": { "dependencies": ["'Design freeze' depend(s) on this task. Remove the dependency first."] },
>   "blocking_tasks": ["Design freeze"] }   // capped at 10
> ```
>
> Only the **blocker** side is protected — deleting the dependent task is fine.

---

## 3E. Notes & Files on a task

Both hang off shared polymorphic endpoints, not task-specific routes:

| Panel | List | Create |
|---|---|---|
| **Notes** | `GET /api/v1/crm/notes/?related_to=project_task&related_to_id=<task_id>` | `POST /api/v1/crm/notes/` `{"content": "…", "related_to": "project_task", "related_to_id": "<task_id>"}` |
| **Files** | `GET /api/v1/crm/attachments/?related_to=project_task&related_to_id=<task_id>` | `POST /api/v1/crm/attachments/` (same `related_to` keys) |

**`related_to` is symmetric** — the same discriminator works on read and write,
so a generic notes/files panel can use one `recordType` value throughout.

| Value | Model |
|---|---|
| `project_task` | `projects.Task` — **the PMO task on this page** |
| `task` | `crm.Task` — the CRM interactions task (a different resource) |

> ⚠️ **`project_task`, not `task`.** Both models have the underlying
> content-type name `"task"`, so the discriminator is what separates them.
> Passing `task` returns CRM task notes, not this page's. An unrecognised value
> returns **0 rows** (it does not silently return everything).
>
> Delete a file with `DELETE /api/v1/crm/attachments/{attachment_id}/` (the
> UUID; the numeric `id` also still resolves).
>
> `ProjectAttachment` (`/api/v1/projects/project-attachments/`) is
> **project-scoped only** — it cannot hold task files.

The detail payload's `comment_count` counts the **projects `Comment`** model
(`/api/v1/projects/comments/?related_to=task&related_to_id=<task_id>`), which is
a separate thread from CRM Notes — gated by the org's `enable_task_comments`
setting. Pick one and stay consistent; the Notes panel in the mockup maps
naturally to CRM Notes.

---

## 4. Saved filters (the chips row)

Saved filters use the **shared** `/api/v1/crm/saved-filters/` endpoint with
**`module: "project_task"`**. This is a DISTINCT module from `task` (the
CRM interactions Task) — they use different tables and FilterSets, so a
`project_task` filter never appears under the CRM Task list and vice-versa.

Contract is identical to the other modules (Leads/Projects): a 6-field DTO,
private-by-default, **max 5 per user per module**, definitions validated against
the Task FilterSet keys on save (unknown key → 400), soft-disabled if they later
reference a purged field (§10.4).

### 4.1 Create a saved filter

`POST /api/v1/crm/saved-filters/`

```json
{
  "module": "project_task",
  "name": "My high-priority milestones",
  "visibility": "private",
  "filter_definition": {
    "priority": "High",
    "is_milestone": true,
    "type__in": ["<task_type_id>", "<task_type_id>"]
  }
}
```

`filter_definition` keys must be valid `TaskFilter` params (the §1 facet keys).

**Success** `201 Created`:

```json
{
  "saved_filter_id": "a6514af9-…",
  "module": "project_task",
  "name": "My high-priority milestones",
  "visibility": "private",
  "filter_definition": { "priority": "High", "is_milestone": true, "type__in": ["…","…"] },
  "is_valid": true
}
```

**Errors**
- `400` — unknown filter key(s): `{ "errors": { "filter_definition": ["Unknown filter key(s): nope__in."] } }`
- `400` — duplicate name for this user+module, or the 5-per-module limit reached
  (limit enforced on **add** only), or an empty `{}` definition.

### 4.2 List / update / delete

- `GET /api/v1/crm/saved-filters/?module=project_task` — the chips row (the
  caller's own + shared).
- `PATCH /api/v1/crm/saved-filters/{saved_filter_id}/` — rename / edit definition.
- `DELETE /api/v1/crm/saved-filters/{saved_filter_id}/` — remove a chip.
- `GET /api/v1/crm/saved-filters/{saved_filter_id}/count/` — the count a chip
  would yield (uses the projects Task base queryset).

### 4.3 Apply a saved filter

Pass `?saved_filter_id=<id>` to the list (§1) or status-counts (§2). The stored
definition is a **base layer**; explicit query params override its keys. An
invalid/broken filter fails **inert** (never widens the result set).

```
GET /api/v1/projects/tasks/?saved_filter_id=a6514af9-…&priority=Urgent
```

---

## 5. Row actions & create

The list-row action menu (👁 view / ✎ edit / ⋯) and the **+ New Task** button
map to the standard task CRUD on the same collection:

| UI action | Method + path | Notes |
|---|---|---|
| **+ New Task** | `POST /api/v1/projects/tasks/` | Body is the task shape; `subject` required. `organization` / `created_by` are stamped server-side. If `status` is omitted the org default status is applied (the `is_default` status, or the first **open** status by position when none is flagged) — the response returns `status` + `status_name` populated. If unassigned and the org's `auto_assign_task_to_manager` setting is on, it's assigned to the project manager. When a `project` is given, a **`task_code`** (`PRJ-1010-t3`) is minted and returned. |
| ✎ **Edit** | `PATCH /api/v1/projects/tasks/{task_id}/` | Partial update. `assignees` is a write-only list of `user_id`s (omit to leave unchanged); the primary `assigned_to` is always kept in the set. **Rejected with 400 while the task is in a closed status** — see §3A. |
| **Set / clear milestone** | `PATCH …/{task_id}/` with `{"is_milestone": true\|false}` | No separate endpoint — `is_milestone` is a writable field. Turning it on records a **"Milestone reached"** activity event (§3B). |
| **Change status** (inline) | `PATCH …/{task_id}/` with `{"status": "<uuid>"}` | Completion-transition rules are validated (400 on an illegal transition — open subtasks or open dependencies). Always allowed even on a completed task: this is the **reopen** (§3A). |
| **Delete** | `DELETE /api/v1/projects/tasks/{task_id}/` | `204` on success. **`409`** if another task depends on this one — the body names the blockers (§3D). |

Assignment is guarded: you may assign a task only to **yourself, a subordinate,
or a teammate** (admins/owners exempt) — otherwise `403`.

### Bulk actions (multi-select toolbar)

| Action | Method + path | Body |
|---|---|---|
| Bulk assign | `POST /api/v1/projects/tasks/bulk-assign/` | `{ "task_ids": [...], "assignee_ids": [...], "mode": "replace"\|"add"\|"remove" }` (legacy singular `assignee_id` also accepted). |
| Bulk status | `POST /api/v1/projects/tasks/bulk-status/` | `{ "task_ids": [...], "status_id": "<uuid>" }` |
| Bulk delete | `POST /api/v1/projects/tasks/bulk-delete/` | `{ "task_ids": [...] }` (max 200) |
| Bulk create | `POST /api/v1/projects/tasks/bulk-create/` | `{ "tasks": [ {…}, … ] }` (top-level only, max 200) |

All bulk actions respect the caller's record-level scope and bump the task
cache version.

---

## Notes for the frontend

- **`subject`, not `title`** — the create/edit body field is `subject`, even
  though the column header reads "Task".
- **Two assignee axes.** `assigned_to` is the single "primary" owner (one user);
  `assignees` is the multi-assignee set behind the avatar stack ("+1"). The
  Assignee facet (`assignees__in` / `assignees__not_in`) matches the M2M;
  `assigned_to__in` matches only the primary FK.
- **`no_status` / null-FK survival.** "is not" facets deliberately keep rows
  whose FK is null (an un-triaged task with no status still shows under
  "Status is not X"). Mirror this in the drawer's copy if needed.
- **Kanban** view uses a separate board endpoint (not covered here).
- **`task_code` is display-only and stable.** The per-project ordinal never
  recycles — deleting `PRJ-1010-t3` does **not** hand that code to the next
  task created, so a code always refers to at most one task, ever. Codes are
  not searchable/filterable yet; `task_id` remains the lookup key for every
  endpoint. Existing tasks were backfilled, ordered by creation time.
- **The completed lock is real** (§3A) — a direct `PATCH` from a script hits the
  same `400` as the UI, so the banner isn't a client-side courtesy. Disable the
  inputs on a closed task and route the user through Reopen.
- **Dependency labels come free on detail** (§3, `dependencies`/`dependents`) —
  don't resolve blocker UUIDs against `/tasks/` one by one.
- **`PATCH` is genuinely partial.** Cross-field date rules (task dates vs the
  project's window, start-before-end) are evaluated against the merged record but
  only *raise* for fields your request actually touches — sending
  `exp_start_date`, `exp_end_date`, or `project`. A metadata-only edit
  (milestone, priority, assignee, status, group) never fails on a stored date the
  user isn't editing. Creates still validate in full.
