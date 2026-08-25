# Operations → Projects — Frontend Integration

Backend endpoints for the **Operations / Projects** screens:

- **Part A — Projects list page** (§1–§8A): the list table, the status tab strip
  (`All (10) · Planning (2) · Active (5) …`), the filter drawer (Status / Type /
  Priority / Customer / Manager, each with an **is / is not** toggle, plus
  "Include archived projects"), column sorting, the **saved-filter chips** row,
  and the **New Project** create form (§8A).
- **Part B — Project detail page** (§9–§15): header + Project-information panel,
  the Tasks tab (grouped lanes with per-lane done counts, milestone flag,
  "Waiting on N" dependency badge, "No group" lane), the Files tab, the Notes
  panel, the Audit-log panel, and view-settings-driven layout.

Base path: `/api/v1/projects/` (project resources) and `/api/v1/crm/`
(saved filters + notes — shared with Leads/Customers/Tasks).

## Common headers

Every request:

| Header          | Value                          | Notes |
|-----------------|--------------------------------|-------|
| `Authorization` | `Bearer <access JWT>`          | The token's `organization_id` claim scopes every query to the org. Required. |
| `Content-Type`  | `application/json`             | For `POST`/`PATCH`/`PUT` JSON bodies. |

No CSRF token is needed — the API is JWT-authenticated (session/cookie CSRF
does not apply).

Common error envelope (DRF, via the global exception handler):

```json
{ "code": 403, "message": "Permission Denied", "errors": { "detail": "You do not have permission to perform this action." } }
```

- **401** — missing/expired token.
- **403** — RBAC: list/detail need `view_project`; writes need
  `create_project` / `update_project` / `delete_project`. Also returned when
  the org's plan lacks the `projects` feature, when the org is inactive, or
  when the Razorpay mandate gate blocks the org.
- **404** — object not in the caller's org / outside their record-level scope
  (hierarchy/team/owned visibility — a project you can't see 404s, it is never
  disclosed).

Pagination (all list endpoints): standard envelope, page size 100.

```json
{ "count": 10, "next": "…?page=2", "previous": null, "results": [ … ] }
```

---

# Part A — Projects list page

## 1. Project list (table view)

### Name / purpose
List projects for the table. Powers the rows (name, code, type, status pill,
customer, priority, progress, manager, expected end + overdue flag), search,
the filter drawer, sorting, and saved-filter application.

### Method + path
`GET /api/v1/projects/projects/`
`QUERY /api/v1/projects/projects/` — same endpoint, **filter params** in the
request body instead of the URL (parity with Leads/Customers). Use it when
the drawer builds long filter sets that would blow past URL-length limits.

```
QUERY /api/v1/projects/projects/?page=1&view=list&ordering=-expected_end_date
Content-Type: application/json

{
  "status__in": ["<uuid>", "<uuid>"],      // JSON lists supported
  "priority__not_in": "Low",
  "customer_isnull": true                  // booleans supported
}
```

The body carries **filter params only** (the facet/search keys from the table
below). Control params — `page`, `page_size`, `saved_filter_id`, `ordering`,
`view` — stay in the URL query string. On a key collision the body wins over
the URL. Response, errors, and pagination are identical to GET. QUERY
responses are never served from the list cache.

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
| `search` | string | Case-insensitive match on **project name OR customer name** (search box). |
| `status__in` | csv of `project_status_id` UUIDs | Status facet, **is** mode. |
| `status__not_in` | csv of UUIDs | Status facet, **is not** mode. Projects with **no status** are kept. |
| `project_type__in` | csv of `project_type_id` UUIDs | Type facet, is. |
| `project_type__not_in` | csv of UUIDs | Type facet, is not (null-type rows kept). |
| `priority__in` | csv of `High,Medium,Low` | Priority facet, is. |
| `priority__not_in` | csv | Priority facet, is not. |
| `customer__in` | csv of `customer_id` UUIDs | Customer facet, is. |
| `customer__not_in` | csv of UUIDs | Customer facet, is not (customer-less "Internal" rows kept). |
| `customer_isnull` | `true`/`false` | `true` → **Internal** projects only (no customer). |
| `manager__in` | csv of `user_id` UUIDs | Manager facet, is. |
| `manager__not_in` | csv of UUIDs | Manager facet, is not (unmanaged rows kept). |
| `include_archived` | `true` | "Include archived projects" checkbox. Default (param absent) hides archived. |
| `is_archived` | `true`/`false` | Archived-only / active-only. |

Other useful params: `ownership=all|me|unassigned`, `my_team=true`,
`is_overdue=true|false`, `due_within_days=N`,
`last_activity=today|this_week|this_month`, `budget_min` / `budget_max`,
`expected_end_date_after|before`, `expected_start_date_after|before`,
`created_at_after|before`, `status_name__in=Planning,Active` (names instead of
UUIDs), `project_name__icontains`.

Sorting:

| Param | Values |
|---|---|
| `ordering` | One of `project_name`, `priority`, `percent_complete`, `expected_start_date`, `expected_end_date`, `created_at`, `updated_at`, `status__position`, `customer__name`, `manager__first_name` — prefix with `-` for descending. Unknown values are ignored. Default: `-created_at`. |

Representation:

| Param | Values |
|---|---|
| `view` | `list` → slim read-only row for the table (see response below): drops the costing/margin totals, the reminder/email schedule block, and the nested `created_by`/`modified_by`/`assignees` objects; `manager` collapses to its `user_id`. Applies to GET/QUERY list only — the detail endpoint always returns the full shape. Omit for the full row. |

Saved filter:

| Param | Purpose |
|---|---|
| `saved_filter_id` | Apply a stored filter (module `project`) as a **base layer**; explicit query params above override its stored keys. See §6. |

Pagination: `page`, `page_size`.

### Request body
GET: none. QUERY: JSON object of **filter params only** (see the QUERY example
above) — values may be scalars, CSV strings, booleans, or native JSON arrays.
Control params (`page`, `page_size`, `saved_filter_id`, `ordering`, `view`)
belong in the URL, not the body.

### Success response
`200 OK`

```jsonc
{
  "count": 10,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 42,
      "project_id": "a1b2c3d4-…",
      "naming_series": "PRJ-1010",              // ← project code under the name
      "project_name": "Technopark Tejaswini — 4F office interiors",
      "description": null,
      "is_archived": false,
      "is_active": "Yes",
      "priority": "High",                        // High | Medium | Low
      "percent_complete_method": "Task Completion",
      "percent_complete": 75.0,                  // progress bar (0–100, JSON number)
      "status": "f0e1d2c3-…",                    // project_status_id UUID (null if none)
      "status_name": "Active",                   // status pill label
      "project_type": "9a8b7c6d-…",              // project_type_id UUID (null if none)
      "project_type_name": "Implementation",     // type sub-label (null if no type)
      "customer": "1122aabb-…",                  // customer_id UUID; null ⇒ render "Internal"
      "customer_name": "Technopark Tejaswini",   // CUSTOMER column (null ⇒ "Internal")
      "expected_start_date": "2026-01-05",
      "expected_end_date": "2026-06-28",
      "is_overdue": false,                       // red date + "Overdue" tag
      "estimated_costing": "0.000000",
      "visibility": "team",
      "manager": {                               // nested user or null
        "user_id": "55ee66ff-…",
        "email": "manoj@…",
        "username": "manoj@…",
        "first_name": "Manoj",
        "last_name": "Varma"
      },
      "manager_name": "Manoj Varma",
      "assignees": [ { "user_id": "…", "first_name": "…", "last_name": "…", "email": "…" } ],
      "assigned_team": null,
      "assigned_team_name": null,
      "organization": "…",
      "company_name": "Nexotech",
      "created_by": { "user_id": "…", "first_name": "…", "last_name": "…", "email": "…" },
      "modified_by": null,
      "created_at": "2026-07-01T10:00:00Z",
      "updated_at": "2026-07-20T08:30:00Z"
      // …plus reminder/costing fields not used by this screen
    }
  ]
}
```

The shape above is the **unconfigured** default. When the org has a `list`
view-settings config (§5A), the row is **trimmed** to the configured-visible
columns plus mandatory companions (`project_id`, `project_name`, the `*_name`
labels, `is_overdue`) — hiding a column hides its data. (`?view=list` is the
separate fixed 19-field projection below and is not further trimmed.)

With `?view=list` each row is exactly this 19-field slim shape (nothing else):

```jsonc
{
  "project_id": "a1b2c3d4-…",
  "naming_series": "PRJ-1010",
  "project_name": "Technopark Tejaswini — 4F office interiors",
  "is_archived": false,
  "status": "f0e1d2c3-…",
  "status_name": "Active",
  "project_type": "9a8b7c6d-…",
  "project_type_name": "Implementation",
  "customer": "1122aabb-…",
  "customer_name": "Technopark Tejaswini",
  "priority": "High",
  "percent_complete": 75.0,
  "manager": "55ee66ff-…",            // user_id string (not a nested object)
  "manager_name": "Manoj Varma",
  "expected_start_date": "2026-01-05",
  "expected_end_date": "2026-06-28",
  "is_overdue": false,
  "created_at": "2026-07-01T10:00:00Z",
  "updated_at": "2026-07-20T08:30:00Z"
}
```

### Error responses
- `400` — invalid filter value, or a broken saved filter (fails **inert**, never
  runs widened). This includes a stored definition whose *value* fails field
  validation (e.g. a malformed UUID): rather than silently dropping that facet
  and returning too many rows, the request 400s with the field errors:

```json
{ "code": 400, "message": "Validation Error", "errors": { "saved_filter": "References unavailable field(s): x." } }
```

```json
{ "code": 400, "message": "Validation Error", "errors": { "saved_filter": { "status__in": ["Enter a valid UUID."] } } }
```

- `404` — `saved_filter_id` that doesn't exist / isn't yours / isn't module
  `project`: `{ "detail": "Saved filter not found." }`
- `401` / `403` — see common errors.

### Pagination
Yes — standard envelope, page size 100, `?page=` / `?page_size=`.

---

## 2. Status tab counts

### Name / purpose
Per-status badge counts for the tab strip (`All (10) · Planning (2) · Active
(5) · On Hold (1) · Completed (1) · Cancelled (1)`). Applies the **same**
filters, saved filter, and record-level permission scope as the list — but
ignores the status facet itself, so selecting a tab never zeroes the other
tabs. One aggregate query; every active status is returned zero-filled.

### Method + path
`GET /api/v1/projects/projects/status-counts/`

### Headers
Common headers.

### Path / query params
Accepts **every** list param from §1 (`search`, facet params, `saved_filter_id`,
`include_archived`, …). `status` / `status__in` / `status__not_in` /
`status_name*` are stripped before counting. No pagination params.

### Request body
None.

### Success response
`200 OK`

```json
{
  "total": 10,
  "no_status": 0,
  "statuses": [
    { "project_status_id": "…", "name": "Planning",  "color": "#3B82F6", "position": 0, "is_closed": false, "count": 2 },
    { "project_status_id": "…", "name": "Active",    "color": "#10B981", "position": 1, "is_closed": false, "count": 5 },
    { "project_status_id": "…", "name": "On Hold",   "color": "#F59E0B", "position": 2, "is_closed": false, "count": 1 },
    { "project_status_id": "…", "name": "Completed", "color": "#8B5CF6", "position": 3, "is_closed": true,  "count": 1 },
    { "project_status_id": "…", "name": "Cancelled", "color": "#EF4444", "position": 4, "is_closed": true,  "count": 1 }
  ]
}
```

`total` = sum over all statuses **plus** `no_status` (projects with no status
assigned) — use it for the **All** tab.

### Error responses
`400` (broken saved filter, inert) / `401` / `403` — as in §1.

### Pagination
None (single aggregate).

---

## 3. Status facet options

### Name / purpose
Populate the **Status** section of the filter drawer (and the tab strip's
labels/colors when not using §2).

### Method + path
`GET /api/v1/projects/project-statuses/`

### Headers
Common headers. RBAC: `view_project` **or** `view_settings`.

### Path / query params
`page` / `page_size` only. Ordered by `position`.

### Request body
None.

### Success response
`200 OK`

```json
{
  "count": 5, "next": null, "previous": null,
  "results": [
    {
      "project_status_id": "f0e1d2c3-…",
      "name": "Planning",
      "color": "#3B82F6",
      "position": 0,
      "is_active": true,
      "is_default": true,
      "is_closed": false,
      "is_readonly": false,
      "created_at": "…", "updated_at": "…"
    }
  ]
}
```

Client-side: hide `is_active: false` rows from the facet; the "Search status…"
box filters locally.

### Error responses
`401` / `403`.

### Pagination
Yes (standard).

---

## 4. Type facet options

### Name / purpose
Populate the **Type** section (Implementation / Retainer / Internal Ops).

### Method + path
`GET /api/v1/projects/project-types/`

### Headers
Common headers. RBAC: `view_project_type` or `view_settings`.

### Path / query params
`page` / `page_size`.

### Request body
None.

### Success response
`200 OK`

```json
{
  "count": 3, "next": null, "previous": null,
  "results": [
    {
      "project_type_id": "9a8b7c6d-…",
      "project_type": "Implementation",
      "description": null,
      "created_at": "…", "updated_at": "…",
      "created_by": 1, "updated_by": null
    }
  ]
}
```

### Error responses
`401` / `403`.

### Pagination
Yes (standard).

---

## 5. Customer & Manager facet options

The Customer and Manager sections reuse existing endpoints:

- **Customers** — `GET /api/v1/crm/customers/?search=<text>` → paginated rows
  with `customer_id` + `name`. Use `customer_id` values in `customer__in` /
  `customer__not_in`. (See `docs/working/customer.md` for the full contract.)
- **Managers** — `GET /api/v1/management/users/?search=<text>` → paginated org
  users with `user_id`, `first_name`, `last_name`. Use `user_id` values in
  `manager__in` / `manager__not_in`. (See `docs/working/members.md`.)

The Priority facet is static: `High` / `Medium` / `Low` (no endpoint).

---

## 5A. Table columns (view settings)

Which columns the list table renders — and their order, width, and header label
— is driven by the shared **view-settings** subsystem (three endpoints, same as
Leads/Tasks). The `project` model is registered for both the `list` and
`detail` view types. Full mechanics live in
`docs/working/org-view-settings-api.md`; this section is the project-scoped
quick reference for rendering the **list** table (detail-panel layout is §11).

> **Behaviour matches Leads/Tasks — the data payload is server-trimmed.** The
> project list/detail responses (`GET /projects/projects/` and `.../{id}/`)
> return **only the org's configured-visible columns**, plus a fixed set of
> mandatory companions (identity + `*_name`/`is_overdue` labels, and
> `task_count`/`done_count` on detail). Hiding a column via the org config
> hides its data too — you don't have to trim client-side. Org config is the
> shared source of truth; **per-user view settings are metadata only** and are
> not applied to the payload (one user hiding a column must not strip it for
> everyone). The `?view=list` slim shape (§1) is a separate fixed projection
> and is **not** further trimmed by the config.

### 5A.1 Column catalog for the table

- **Method + path:** `GET /api/v1/projects/projects/schema/?view_type=list`
- **Headers:** Common headers. RBAC: `view_project` or `view_settings`.
- **Purpose:** the visible-column catalog for the table, merged from the org's
  column config + the caller's per-user overrides. **`fields` contains only the
  columns to render**, each with its `order`, `width`, `label`, and
  `is_protected` — render the header directly from it. The **full** built-in
  column catalog (visible or not) is **`all_fields.columns`** — an "add column"
  picker reads from there (see the shape note below `all_fields`).
- **Success:** `200 OK`

```jsonc
{
  "model": "Project",
  "view_type": "list",
  "has_org_config": true,
  "has_user_settings": false,
  "fields": {                          // dict keyed by field name — VISIBLE columns only
    "project_name":     { "name": "project_name", "type": "string", "label": "Project", "order": 1, "width": 240, "is_protected": true },
    "status":           { "name": "status", "type": "foreignkey", "related_model": "ProjectStatus", "related_field": "project_status_id", "label": "Status", "order": 2, "width": 120, "is_protected": false },
    "customer":         { "name": "customer", "type": "foreignkey", "label": "Customer", "order": 3, "width": 180, "is_protected": false },
    "priority":         { "name": "priority", "type": "string", "label": "Priority", "order": 4, "width": 110, "is_protected": false },
    "percent_complete": { "name": "percent_complete", "type": "decimal", "label": "Progress", "order": 5, "width": 140, "is_protected": false },
    "manager":          { "name": "manager", "type": "foreignkey", "label": "Project Manager", "order": 6, "width": 160, "is_protected": false },
    "expected_end_date":{ "name": "expected_end_date", "type": "date", "label": "Expected End", "order": 99, "width": 130, "is_protected": true }
  },
  "custom_field_definitions": [],      // always [] — projects have no custom fields
  "all_fields": {                      // NOT a flat dict — a config bag:
    "columns": [                       //   ← the FULL catalog the "add column" picker reads
      { "name": "project_name", "label": "Project", "order": 1, "visible": true,  "width": 240, "is_protected": true,  "is_fixed": true,  "field_info": { … }, "in_fields": true },
      { "name": "department",   "label": "Department", "order": 8, "visible": false, "width": null, "is_protected": false, "is_fixed": false, "field_info": { … }, "in_fields": false },
      …                                //   every built-in column, visible or not
    ],
    "sorting": {},                     // user prefs (empty when org config drives columns)
    "filters": {}
  }
}
```

**`all_fields` shape:** it is a config bag `{ columns, sorting, filters }`, **not**
a flat dict of every field. The "add column" picker iterates **`all_fields.columns`**
— each entry carries `name`, `label`, `order`, `visible`, `width`, `is_protected`,
`is_fixed`, `in_fields` (whether it's in the visible `fields` map above), and a
nested `field_info` (type/related-model). Hidden columns have `visible: false`.

There is **no top-level `is_visible` flag** — for `fields`, presence *is*
visibility; for `all_fields.columns`, use each entry's `visible`.

**Default-visible list columns** are seeded by the org-field-config default and
are the authoritative source for what `fields` returns:
`project_name, status, customer, priority, manager`, with `expected_end_date`
pinned last. `percent_complete` and `project_type` exist in the catalog
(`all_fields.columns`) but are **not** visible by default — enable them via the
admin config (§5A.2). **Fixed** (`is_protected: true`, cannot be hidden):
`project_name`, `expected_end_date`. The list **data** endpoint (§1) returns
exactly the configured-visible columns (plus mandatory companions), so the
schema's `fields` and the row payload always agree.

### 5A.2 Org-wide column config (admin)

- **Read:** `GET /api/v1/management/org-field-config/?model_name=project&view_type=list`
  — auto-seeds defaults on first access; returns `{model_name, view_type, fields: [...]}`
  (per-field `is_visible`/`order`/`width`/`label_override`/`is_protected`).
- **Write (admin):** `PUT /api/v1/management/org-field-config/` — full
  replace/bulk-upsert for `(project, list)`. Body:

```json
{
  "model_name": "project",
  "view_type": "list",
  "fields": [
    { "field_name": "project_name",      "is_visible": true,  "order": 1, "width": 240 },
    { "field_name": "status",            "is_visible": true,  "order": 2, "width": 120 },
    { "field_name": "customer",          "is_visible": true,  "order": 3, "width": 180 },
    { "field_name": "priority",          "is_visible": true,  "order": 4, "width": 110 },
    { "field_name": "percent_complete",  "is_visible": true,  "order": 5, "width": 140 },
    { "field_name": "manager",           "is_visible": true,  "order": 6, "width": 160 },
    { "field_name": "project_type",      "is_visible": true,  "order": 7, "width": 140, "label_override": "Type" },
    { "field_name": "expected_end_date", "is_visible": true,  "order": 99, "width": 130 }
  ]
}
```

  `400` on unknown `field_name`, duplicate `order`, or hiding a fixed column
  (`project_name`/`expected_end_date`); `403` for non-admins.

### 5A.3 Per-user column overrides

- `GET /api/v1/management/user-view-settings/?model_name=project&view_type=list`
  — the caller's saved layout (only they see it).
- `POST /api/v1/management/user-view-settings/`
  `{"model_name": "project", "view_type": "list", "settings": {"columns": [{"name": "project_name", "visible": true, "order": 1}, …]}}`
  — persist the user's column choices; `PATCH …/{id}/` to update.
- These surface in the `/schema/` response (`has_user_settings`) as the
  per-user layer; the frontend applies them on top of the org config.

---

## 6. Saved filters (chips row)

Shared endpoint across modules (leads, customers, tasks, follow-ups, products,
**projects**). All operations are **per-user** — you only ever see and edit
your own filters. Limit: **5 saved filters per user per module**; the
`visibility` field is read-only (`private`) in phase 1.

RBAC: `view_settings` for reads, `update_settings` for writes (same codenames
as user view settings).

`filter_definition` is a dict of the **§1 query-param keys** — exactly what
you'd put in the list URL. Multi-value keys accept either a native JSON array
(`{"status__in": ["<uuid>", "<uuid>"]}`, preferred) or a CSV string
(`{"status__in": "<uuid>,<uuid>"}`) — both apply identically. Unknown keys are
rejected on save; a definition that later references a removed field is stored
but soft-disabled (`is_valid: false`) and fails inert when applied; a stored
*value* that fails validation at apply time 400s inert (§1 errors) — a
definition never applies partially.

### 6.1 List my saved filters

- **Name / purpose:** Render the chips row for the Projects page.
- **Method + path:** `GET /api/v1/crm/saved-filters/?module=project`
- **Headers:** Common headers.
- **Path / query params:** `module=project` (omit to get all modules);
  `page` / `page_size`.
- **Request body:** None.
- **Success response:** `200 OK`

```json
{
  "count": 2, "next": null, "previous": null,
  "results": [
    {
      "saved_filter_id": "77aa88bb-…",
      "module": "project",
      "name": "High priority active",
      "visibility": "private",
      "filter_definition": { "priority__in": "High", "status_name__in": "Active" },
      "is_valid": true,
      "invalid_reason": null,
      "order": 0,
      "created_at": "…", "updated_at": "…"
    }
  ]
}
```

  Render `is_valid: false` chips greyed with `invalid_reason` as the tooltip;
  do not auto-apply them.
- **Error responses:** `401` / `403`.
- **Pagination:** Yes (standard) — with the 5-per-module cap it's always one page.

### 6.2 Save a filter

- **Name / purpose:** "Save filter" from the drawer — persist the currently
  selected facets as a named chip.
- **Method + path:** `POST /api/v1/crm/saved-filters/`
- **Headers:** Common headers + `Content-Type: application/json`.
- **Path / query params:** None.
- **Request body:**

```json
{
  "module": "project",
  "name": "Overdue implementations",
  "filter_definition": {
    "project_type__in": "9a8b7c6d-…",
    "is_overdue": "true",
    "priority__not_in": "Low"
  }
}
```

- **Success response:** `201 Created` — the created object (same shape as a
  §6.1 row, `is_valid` computed server-side).
- **Error responses:** `400` with a field-keyed body (surface `errors.<field>`
  verbatim):

```json
{ "code": 400, "message": "Validation Error", "errors": { "name": "A saved filter named 'Overdue implementations' already exists for this module." } }
```

```json
{ "code": 400, "message": "Validation Error", "errors": { "module": "Limit of 5 saved filters per module reached." } }
```

```json
{ "code": 400, "message": "Validation Error", "errors": { "filter_definition": "Unknown filter key(s): bogus_key." } }
```

```json
{ "code": 400, "message": "Validation Error", "errors": { "filter_definition": "Add at least one filter before saving." } }
```

  Plus `401` / `403`.
- **Pagination:** N/A.

### 6.3 Rename / update a filter

- **Name / purpose:** Rename a chip or overwrite its criteria.
- **Method + path:** `PATCH /api/v1/crm/saved-filters/{saved_filter_id}/`
- **Headers:** Common + JSON content type.
- **Path / query params:** `saved_filter_id` (UUID) in path.
- **Request body:** any subset of `name`, `filter_definition`, `order`:

```json
{ "name": "Overdue (impl.)" }
```

- **Success response:** `200 OK` — the updated object. Editing in place is
  never blocked by the 5-filter cap.
- **Error responses:** `400` (duplicate name / unknown keys, as §6.2), `404`
  (not yours / wrong id), `401` / `403`.
- **Pagination:** N/A.

### 6.4 Delete a filter

- **Name / purpose:** Remove a chip.
- **Method + path:** `DELETE /api/v1/crm/saved-filters/{saved_filter_id}/`
- **Headers:** Common headers.
- **Path / query params:** `saved_filter_id` in path.
- **Request body:** None.
- **Success response:** `204 No Content`.
- **Error responses:** `404` / `401` / `403`.
- **Pagination:** N/A.

### 6.5 Chip match count (optional)

- **Name / purpose:** Cached/approximate match count for a chip. **Never call
  this per-chip on page load** — only on demand (e.g. hover), per §10.6.
- **Method + path:** `GET /api/v1/crm/saved-filters/{saved_filter_id}/count/`
- **Headers:** Common headers.
- **Path / query params:** `saved_filter_id` in path.
- **Request body:** None.
- **Success response:** `200 OK`

```json
{ "count": 4 }
```

  Invalid filters return `{ "count": null, "invalid_reason": "…" }`. The value
  is cached ~60s and mirrors the list's default view (archived excluded unless
  the definition itself opts in).
- **Error responses:** `404` / `401` / `403`.
- **Pagination:** N/A.

### 6.6 Apply a filter

Not a separate endpoint — pass the chip's id to the list / counts endpoints:

```
GET /api/v1/projects/projects/?saved_filter_id=77aa88bb-…&page=1
GET /api/v1/projects/projects/status-counts/?saved_filter_id=77aa88bb-…
```

The stored definition is the base layer; any explicit query param in the URL
**overrides** the stored value for that key. A chip with `is_valid: false`
returns `400` (inert) — never a widened result set.

---

## 7. Refresh button

No dedicated endpoint — re-issue the current §1 request (and §2 for the tabs).
List responses are server-cached per user/org and version-invalidated on every
project write, so a refetch after any mutation is already fresh.

---

## 8. Row actions (used by this screen's ⋯ menu)

Quick reference; full contracts in `docs/working/projects-app-guide.md`.

| Action | Method + path | Body | Success |
|---|---|---|---|
| View | `GET /api/v1/projects/projects/{project_id}/` | — | `200` project object (§1 row shape) |
| Edit | `PATCH /api/v1/projects/projects/{project_id}/` | changed fields | `200` updated object |
| Create ("New Project") | `POST /api/v1/projects/projects/` | Full contract in **§8A**. | `201`; `naming_series` (the `PRJ-1011` code) is **auto-generated server-side** when omitted |
| Archive / unarchive | `POST /api/v1/projects/projects/{project_id}/archive/` | `{"is_archive": true}` (default true) | `200 {"success": true, "is_archived": true, "changed": true}` |
| Delete | `DELETE /api/v1/projects/projects/{project_id}/` | — | `204` |
| Bulk archive | `POST /api/v1/projects/projects/bulk-archive/` | `{"project_ids": […], "is_archive": true}` | `200 {"success": true, "updated": n, "errors": []}` |
| Bulk delete | `POST /api/v1/projects/projects/bulk-delete/` | `{"project_ids": […]}` (≤200) | `200 {"success": true, "deleted": n}` |
| Bulk status | `POST /api/v1/projects/projects/bulk-status/` | `{"project_ids": […], "status_id": "<uuid>", "notify": false}` | `200 {"success": true, "updated": n, "errors": []}` |
| Bulk manager | `POST /api/v1/projects/projects/bulk-manager/` | `{"project_ids": […], "manager_id": "<uuid>", "notify": false}` | `200 {"success": true, "updated": n, "errors": []}` |

Create/edit validation errors come back as field-keyed `400`s, e.g.
`{"errors": {"project_name": "Project with this name already exists."}}` or
`{"errors": {"expected_end_date": "Expected end date cannot be before the expected start date."}}`.

Duplicate-name note: uniqueness is per-org across **active** projects only —
a name is reusable after the old project is archived; unarchiving into a name
collision 400s with `errors.project_name`.

---

## 8A. Create project ("New Project" form)

### Name / purpose
Backs the **New Project** screen (Project Information · Project Settings · People
& Access). Creates one `Project` in the caller's org. Every field on the form is
supported by the backend — there are **no missing fields**. The only care the FE
needs is using the exact body keys below (several differ from the visible
labels), and that **Status / Project type are per-org FK UUIDs** while
**Priority / Visibility / Progress method are fixed string enums**.

### Method + path
`POST /api/v1/projects/projects/`

### Headers
Common headers. `Content-Type: application/json` (use `multipart/form-data` only
if you also send `attachment`). RBAC: **`create_project`**; plan-feature gate:
org plan must include `projects`.

### Request body — exact keys

Only **`project_name` is required**; everything else is optional and
server-defaulted (see below). ⚠️ marks keys whose name differs from the UI label
— an unknown key is **silently ignored** (the field falls to its default, no
error), so a wrong key looks like it "worked" but drops the value.

| UI field | **Body key** | Type / value | Notes |
|---|---|---|---|
| Project name * | `project_name` | string (≤140) | **Required.** Per-org unique among non-archived projects. |
| Description | `description` | string | |
| Customer | `customer` | **`customer_id` UUID** or `null` | Omit / `null` = internal project. |
| Expected start date | `expected_start_date` | `YYYY-MM-DD` | ⚠️ not `start_date`. |
| Expected end date | `expected_end_date` | `YYYY-MM-DD` | ⚠️ not `end_date`. Must be ≥ start. |
| Estimated cost (₹) | `estimated_costing` | decimal string | ⚠️ **not** `estimated_cost` / `total_sales_amount` (that one is read-only). |
| Status | `status` | **`project_status_id` UUID** | FK to per-org rows (§3 feed). Omit → org default status (**Planning**). |
| Project type | `project_type` | **`project_type_id` UUID** | FK to per-org rows (§4 feed). |
| Priority | `priority` | `"Low"` \| `"Medium"` \| `"High"` | Fixed enum. Default `"Medium"`. |
| Visibility | `visibility` | `"private"` \| `"team"` \| `"organization"` | Fixed enum, **lowercase** — the "Organization" option POSTs `"organization"`. Omit → org PMO default (fallback `"team"`). |
| Progress method | `percent_complete_method` | `"Manual"` \| `"Task Completion"` \| `"Task Progress"` \| `"Task Weight"` | ⚠️ **not** `progress_method`. Default `"Task Completion"`. |
| Project manager | `manager` | **`user_id` UUID** | ⚠️ **not** `project_manager`. |
| Assignees | `assignees` | array of **`user_id` UUIDs** | |
| Assigned team | `assigned_team` | **`team_id` UUID** | Omit / `null` = "No team". |

Extra optional keys (not on this form): `percent_complete` (accepted **only**
when `percent_complete_method="Manual"`, else dropped), `notes` (write-only →
creates a project Note), `attachment` (write-only file → forces
`multipart/form-data`), `naming_series` (leave out — server mints `PRJ-####`).

All FK inputs (`customer`, `manager`, `assignees`, `assigned_team`, `status`,
`project_type`) are **org-scoped** — a UUID from another org (or a stale one)
→ `400`.

### Example request (mirrors the form)

```json
POST /api/v1/projects/projects/
{
  "project_name": "Malabar Gold — Kochi showroom fit-out",
  "description": "Scope: showroom implementation.",
  "customer": null,
  "expected_start_date": "2026-08-10",
  "expected_end_date": "2026-09-30",
  "estimated_costing": "2500000",
  "status": "8bbfad46-7403-4f1f-9fec-b489f13f4ec2",
  "project_type": "cc473241-7380-44fe-a99b-bb232bce4317",
  "priority": "Medium",
  "visibility": "organization",
  "percent_complete_method": "Task Completion",
  "manager": "acaec99f-9001-48b0-ad30-0f2c4ae06240",
  "assignees": ["acaec99f-9001-48b0-ad30-0f2c4ae06240"]
}
```

Minimal valid body: `{ "project_name": "…" }` — the server fills status
(**Planning**), visibility (`team`), progress method (`Task Completion`),
estimated cost (`0`), and the `PRJ-####` code.

### Success response — `201 Created`
Returns the full project object (same shape as the §1 list row / §9 detail).
Server-stamped: `project_id`, `naming_series` (`PRJ-1020`), `organization`,
`created_by`, `created_at`. Relations expand on read — `manager` and each
`assignees[]` entry become nested user objects (`user_id`, `email`,
`first_name`, `last_name`, `full_name`, `is_active`); `customer` / `status` /
`project_type` / `assigned_team` return their UUID plus a `*_name` companion.

```jsonc
{
  "project_id": "…", "naming_series": "PRJ-1020",
  "project_name": "Malabar Gold — Kochi showroom fit-out",
  "status": "8bbfad46-…", "status_name": "Planning",
  "project_type": "cc473241-…", "project_type_name": "Internal",
  "priority": "Medium", "visibility": "organization",
  "percent_complete_method": "Task Completion", "percent_complete": 0.0,
  "estimated_costing": "2500000.000000",
  "expected_start_date": "2026-08-10", "expected_end_date": "2026-09-30",
  "customer": null, "customer_name": null,
  "manager": { "user_id": "acaec99f-…", "full_name": "Admin Acme", "email": "…", "is_active": true },
  "assignees": [ { "user_id": "acaec99f-…", "full_name": "Admin Acme", … } ],
  "assigned_team": null,
  "created_by": { "user_id": "…", "full_name": "…" }, "created_at": "…"
}
```

### Error responses
Field-keyed `400` envelope `{ "code": 400, "message": "Validation Error", "errors": { "<field>": ["…"] } }`:

| Case | Response |
|---|---|
| Missing `project_name` | `errors.project_name: ["This field is required."]` |
| Duplicate active name | `errors.project_name: ["…already exists."]` |
| `expected_end_date` < `expected_start_date` | `errors.expected_end_date: ["Expected end date cannot be before the expected start date."]` |
| Bad enum (e.g. `visibility: "Organization"`) | `errors.visibility: ["\"Organization\" is not a valid choice."]` (send lowercase) |
| Cross-org / stale FK UUID | `errors.<field>` invalid-pk |

`403` — no `create_project` permission, or plan lacks `projects`, or the org is
inactive / mandate-gated. `401` — missing/expired token.

### Dropdown feeds for the form
| Form control | Endpoint |
|---|---|
| Status | `GET /api/v1/projects/project-statuses/` (§3) → `project_status_id`, `name`, `color`, `is_default` |
| Project type | `GET /api/v1/projects/project-types/` (§4) → `project_type_id`, `project_type` |
| Priority / Visibility / Progress method | No endpoint — the fixed enums above (or read `GET /api/v1/projects/projects/schema/?view_type=form`). |
| Project manager & Assignees | `GET /api/v1/management/users/?search=<text>` → `user_id`, `first_name`, `last_name` |
| Assigned team | `GET /api/v1/management/teams/` → `team_id`, `name` |
| Customer (searchable) | `GET /api/v1/crm/customers/?search=<text>` → `customer_id`, `name` |

### Pagination
N/A (single-object create).

---

# Part B — Project detail page

Endpoints for the **project detail page**: header + Project-information panel,
the Tasks tab (grouped lanes with per-lane done counts, milestone flag,
"Waiting on N" dependency badge, "No group" lane), the Files tab, the Notes
panel, the Audit-log panel, and view-settings-driven layout. Auth + error
conventions are the common headers above. RBAC: reads need `view_project`; task
writes need `*_task`.

The three content **tabs** are pure client-side view switches over data already
covered here — no dedicated per-tab endpoint:

| Tab | Backing endpoint(s) |
|---|---|
| **Tasks** (default) | §12 task-groups (lanes + counts) + §13 tasks (rows) |
| **Files** | §15 project-attachments |
| **Activity** | §10 project activity (same feed as the Audit-log panel) |

Below the tabs, the **Notes** panel (§14) and **Audit log** panel (§10) render
their own sections regardless of the active tab.

## 9. Project retrieve (header + information panel)

### Method + path
`GET /api/v1/projects/projects/{project_id}/`

### Success response
`200 OK` — the full project object (same shape as the list row, see §1)
**plus** two rollup fields present only on retrieve:

```jsonc
{
  "project_id": "a1b2…",
  "naming_series": "PRJ-1010",
  "project_name": "Technopark Tejaswini — 4F office interiors",
  "status_name": "Active", "priority": "High",
  "percent_complete": 75.0, "percent_complete_method": "Task Completion",
  "customer_name": "Technopark Tejaswini", "project_type_name": "Implementation",
  "manager": { "user_id": "…", "first_name": "Manoj", "last_name": "Varma", … },
  "assignees": [ … ], "assigned_team_name": "Team South",
  "expected_start_date": "2026-03-02", "expected_end_date": "2026-06-28",
  "estimated_costing": "5400000.000000", "visibility": "organization",
  "description": "Full interior fit-out …",
  "task_count": 13,        // ← "TASKS 9/13 done" — countable tasks (templates + cancelled excluded)
  "done_count": 9          // ← closed-and-not-cancelled tasks
}
```

`task_count`/`done_count` are **retrieve-only** — they are absent (null → key
omitted) on the list endpoint to keep it lean.

The full field set above is what an unconfigured org gets. If the org has a
`detail` view-settings config (§11), the retrieve response is **trimmed** to the
configured-visible fields plus mandatory companions (identity, `*_name` labels,
`is_overdue`, `task_count`, `done_count`).

**`?view=detail` — panel projection.** `GET …/projects/{id}/?view=detail`
returns a fixed slim shape for the information panel: it keeps everything the
panel renders (identity, status, customer/manager/team, dates, priority,
description, assignees, visibility, `estimated_costing`, `percent_complete`(`_method`),
and the `task_count`/`done_count` rollup) but **drops** the two blocks the panel
never shows — the reminder/email **schedule** block (`frequency`, `from_time`,
`to_time`, `first_email`, `second_email`, `daily_time_to_send`, `day_to_send`,
`weekly_time_to_send`, `subject`, `message`, `holiday_list`, `collect_progress`)
and the internal **costing/margin** totals (`total_costing_amount`,
`total_purchase_cost`, `total_sales_amount`, `total_billable_amount`,
`total_billed_amount`, `total_consumed_material_cost`, `cost_center`,
`gross_margin`, `per_gross_margin`, `actual_time`). Like `?view=list`, this is a
fixed projection and bypasses the org view-settings trim. Omit `view` for the
full shape.

### Error responses
`404` (outside record-level scope) / `401` / `403`.

---

## 10. Project activity (audit-log panel)

### Name / purpose
The **Audit log** panel — this project's history (create, status/manager
changes, progress recalcs, and child rollups when a task/attachment/comment is
written). Gated by `view_project`, so a PM without the org-wide
`view_audit_log` codename still sees their own project's log (unlike
`/access-control/audit-logs/`).

### Method + path
`GET /api/v1/projects/projects/{project_id}/activity/`

### Path / query params
`page` / `page_size`. Ordered newest-first.

### Success response
`200 OK` — paginated AuditLog rows scoped to this project:

```jsonc
{
  "count": 4, "next": null, "previous": null,
  "results": [
    {
      "audit_log_id": "…",
      "action": "update",              // create | update | delete | …
      "model_name": "Project",
      "record_id": "a1b2…",            // this project
      "user_email": "manoj@…", "user_full_name": "Manoj Varma",
      "timestamp": "2026-07-21T09:00:00Z",
      "event_type": "field_changed",   // ← server-rendered enum (see below)
      "summary": "Status changed to Active",  // ← server-rendered human string
      "changes": {                     // raw diff, kept for tooling
        "request_body": { "status_name": "Active", "status": "…" }
      }
    },
    {
      "action": "update",
      "event_type": "child_created",
      "summary": "Task 'Civil & partition works' created",
      "changes": { "related_change": { "type": "Task", "action": "create", "label": "Civil & partition works", "record_id": "…" } }  // …child rollup
    }
  ]
}
```

**Pre-humanized fields** (render these directly — no client-side humanizer
needed):

- **`summary`** — a ready-to-display string ("Task 'Snag list' created",
  "Status changed to Active", "Project created", …).
- **`event_type`** — a stable enum for the row icon/grouping:
  `created | updated | field_changed | deleted | child_created | child_updated | child_deleted`.
  `child_*` = a Task/attachment/comment write rolled up onto the project;
  `field_changed` = a direct field diff on the project itself.

`changes` is still returned (raw diff) for tooling/detail. (Note: "Progress
recalculated" rows are emitted by the progress engine as normal `update`
entries.)

### Error responses
`404` / `401` / `403`.

---

## 11. View-settings schema (layout)

### Name / purpose
The **detail** counterpart of the list-column config in §5A — drives the
"Project information" panel's field order/visibility, identical to
`GET /crm/leads/schema/?view_type=detail`. The org-field-config and
per-user-override endpoints from §5A.2 / §5A.3 are the same, just with
`view_type=detail`.

### Method + path
`GET /api/v1/projects/projects/schema/?view_type=detail`

### Path / query params
`view_type`: `list` | `detail` | `form` | `add` (default `list`).

### Success response
`200 OK` — same envelope as §5A.1 (`fields` = visible panel fields only, no
`is_visible` flag; `all_fields` = the `{ columns, sorting, filters }` config bag
whose `columns[]` is the full field catalog — see the §5A.1 shape note;
`custom_field_definitions` always `[]`):

```jsonc
{
  "model": "Project",
  "view_type": "detail",
  "has_org_config": true,
  "has_user_settings": false,
  "fields": {                          // dict keyed by field name — VISIBLE panel fields only
    "project_name": { "name": "project_name", "type": "string", "label": "Project", "order": 1, "width": 240, "is_protected": true },
    "customer":     { "name": "customer", "type": "foreignkey", "label": "Customer", "order": 2, "width": 180, "is_protected": false },
    "status":       { … }, "priority": { … }, "percent_complete": { … }  // …16 detail fields by default
  },
  "custom_field_definitions": [],
  "all_fields": { "columns": [ … ], "sorting": {}, "filters": {} }  // columns[] = full catalog
}
```

The detail anchor `project_name` is fixed (`is_protected: true`). Same as §5A:
the project **retrieve** payload (§9) is server-trimmed to these
configured-visible fields (plus mandatory companions incl. `task_count` /
`done_count`), so the panel schema and the retrieve response always agree.

Org-wide config: `GET`/`PUT /api/v1/management/org-field-config/?model_name=project&view_type=detail`
(admin, §5A.2 shape). Per-user layout:
`POST /api/v1/management/user-view-settings/`
`{"model_name": "project", "view_type": "detail", "settings": {"columns": [{"name": "project_name", "visible": true, "order": 1}, …]}}`.

### Error responses
`401` / `403` (needs `view_project` or `view_settings`).

---

## 12. Task groups (Tasks-tab lanes)

### 12.1 List groups with counts

- **Method + path:** `GET /api/v1/projects/task-groups/?project={project_id}`
- **Query params:** `project`, `project__in`, `title__icontains`, `page`.
  Ordered by `position` then `created_at`.
- **Success:** `200 OK`

```jsonc
{
  "count": 5, "next": null, "previous": null,
  "results": [
    {
      "task_group_id": "…",
      "title": "Design",
      "position": 0,
      "project": "a1b2…",
      "task_count": 4,     // ← "4/4 done" — countable (templates + cancelled excluded)
      "done_count": 4,     // ← closed-and-not-cancelled
      "created_at": "…", "updated_at": "…", "created_by": …, "updated_by": …
    }
  ]
}
```

For the **"No group" lane**, fetch ungrouped tasks with §13's
`task_group_isnull=true` and count client-side (or read the project-level
`task_count`/`done_count` minus the grouped totals).

### 12.2 Create / rename / delete

- **New group** button: `POST /api/v1/projects/task-groups/` `{"title": "Site Work", "project": "<uuid>"}` → `201`
- Group header **⋯ menu → Rename:** `PATCH /api/v1/projects/task-groups/{id}/` `{"title": "…"}` → `200`
- Group header **⋯ menu → Delete:** `DELETE /api/v1/projects/task-groups/{id}/` → `204`
  (tasks in the group are **not** deleted — their `task_group` FK is `SET_NULL`,
  so they fall into the "No group" lane).
- RBAC: `create_task` / `update_task` / `delete_task`.

### 12.3 Reorder (drag handle)

- **Method + path:** `POST /api/v1/projects/task-groups/reorder/`
- **Body:** `[{"task_group_id": "<uuid>", "position": 0}, {"task_group_id": "<uuid>", "position": 1}]`
- **Success:** `200 {"detail": "Reorder successful."}`
- **Errors:** `400` (body not a list) / `403` (`update_task`).

---

## 13. Tasks within a project

`GET /api/v1/projects/tasks/?project={project_id}` — the task rows under each
lane. See `docs/working/task-schema-and-status-api.md` for the full field
contract. Detail-page-relevant params / fields:

| Param / field | Purpose |
|---|---|
| `?task_group={id}` / `?task_group__in=` | Tasks in a specific lane. |
| `?task_group_isnull=true` | **"No group" lane** — ungrouped tasks. `false` → grouped only. |
| `is_milestone` (writable) | The milestone flag icon. `PATCH tasks/{id}/ {"is_milestone": true}` — no separate endpoint. |
| `pending_dependency_count` (read-only) | **"Waiting on N"** badge — count of this task's incomplete predecessors (a dependency whose `depends_on` task is not closed-and-not-cancelled). |
| `subtask_count`, `comment_count` | Existing rollups. |
| `status_name`, `is_overdue`, `computed_progress` | Row rendering (chip, overdue/Working/Open, progress). `computed_progress` is a **JSON number** (`39.0`), not a string. |
| `exp_end_date` | Carries the date **and time** ("28 Jun, 17:00"). |

**Slim rows:** `GET …/tasks/?project={id}&view=list` returns a **19-field** lane
projection (drops costing/billing, template/parent linkage, time bookkeeping,
and the nested `created_by`/`modified_by`); `assigned_to` collapses to
`{user_id, full_name}`, `assignees` keeps its embedded stack. The detail
retrieve keeps the full shape. See operations-task.md §1 for the field list.

### 13.1 Task row actions

Standard REST on the tasks viewset (RBAC: `create_task` / `update_task` /
`delete_task`):

| Action (UI) | Method + path | Body | Success |
|---|---|---|---|
| **Add task** ("+ Add task" in a lane) | `POST /api/v1/projects/tasks/` | `{"subject": "…", "project": "<uuid>", "task_group": "<uuid|null>", "assigned_to": "<user uuid>", "exp_end_date": "2026-06-28T17:00:00Z", "priority": "Medium"}` | `201` task object |
| Edit task | `PATCH /api/v1/projects/tasks/{task_id}/` | changed fields | `200` |
| **Complete** (check the box) | `PATCH /api/v1/projects/tasks/{task_id}/` | `{"status": "<closed status uuid>"}` | `200` |
| **Reopen** (uncheck) | `PATCH /api/v1/projects/tasks/{task_id}/` | `{"status": "<open status uuid>"}` | `200` |
| Delete task | `DELETE /api/v1/projects/tasks/{task_id}/` | — | `204` |
| Set / clear milestone (flag icon) | `PATCH /api/v1/projects/tasks/{task_id}/` | `{"is_milestone": true}` | `200` |
| Move to another lane (drag between groups) | `PATCH /api/v1/projects/tasks/{task_id}/` | `{"task_group": "<uuid|null>"}` | `200` |

On create, when `status` is omitted the task inherits the org's default
`ProjectTaskStatus` — the `is_default` status, or (when none is flagged) the
first **open** status (`is_closed=false && is_cancelled=false`) by `position`.
The create response returns the resolved `status` + `status_name` populated (no
more `null`-status rows). If `ProjectSettings.auto_assign_task_to_manager` is on
and no assignee is given, the task is auto-assigned to the project manager.

The status UUIDs to PATCH for **complete** / **reopen** come from
`GET /api/v1/projects/project-task-statuses/` (see §13.4).

Completing a task is blocked by incomplete subtasks/dependencies →
`400` listing the blockers (e.g.
`{"errors": {"status": "Cannot complete this task. The following dependencies are not completed: …"}}`).

Bulk task actions (if the UI adds multi-select): `POST /tasks/bulk-status/`,
`/tasks/bulk-assign/`, `/tasks/bulk-delete/`, `/tasks/bulk-create/` — see
`docs/working/task-schema-and-status-api.md`.

### 13.2 "View all tasks" / "Manage all project tasks" links

The **View all tasks ↗** button and the **Manage all project tasks in
Operations › Tasks** footer link both deep-link to the standalone Tasks screen
pre-filtered to this project — same endpoint, no project-detail-specific call:
`GET /api/v1/projects/tasks/?project={project_id}` (add lane/assignee/status
filters as needed).

### 13.3 Dependencies ("Waiting on N")

The badge count comes from `pending_dependency_count` on the task row (above).
To read or wire the actual edges:

- **List a task's blockers:** `GET /api/v1/projects/task-dependencies/?task={task_id}`
  (each row has `depends_on`, `subject`).
- **Add an edge:** `POST /api/v1/projects/task-dependencies/`
  `{"task": "<uuid>", "depends_on": "<uuid>"}` — self-dependency, cross-org,
  cross-project (unless enabled), and cycle guards return field-keyed `400`s.
- **Remove an edge:** `DELETE /api/v1/projects/task-dependencies/{task_depends_on_id}/`.
- RBAC: `view_task` (read) / `update_task` (write).

### 13.4 Project task statuses (complete / reopen targets)

The status set a task PATCHes to for **complete** / **reopen** lives at:

`GET /api/v1/projects/project-task-statuses/`

> Note the path: it is `project-task-statuses/` (not `/projects/task-statuses/`,
> which 404s, and NOT `/crm/crm-task-statuses/`, which is the separate CRM-task
> resource).

Each row: `{ project_task_status_id, status, description, color, position,
is_active, is_closed, is_cancelled, is_system }`. To resolve targets client-side:

- **Complete** → the first status with `is_closed === true && is_cancelled === false` (by `position`).
- **Reopen** → the first status with `is_closed === false` (by `position`).
- The **default** a new task inherits is the row with `is_default === true`, or
  the first open status when none is flagged (see §13.1).

---

## 14. Notes panel

Shared CRM notes endpoint (`project` is in the allowlist):

- **List:** `GET /api/v1/crm/notes/?related_to=project&related_to_id={project_id}`
- **Add:** `POST /api/v1/crm/notes/` `{"related_to": "project", "related_to_id": "<uuid>", "content": "…"}`
- Threading, edit, delete per the notes contract (`docs/working/notes.md`).

---

## 15. Files tab

- **List (filtered):** `GET /api/v1/projects/project-attachments/?project={project_id}`
  — the `project` filter was previously missing (returned the whole org's
  attachments); now scoped. Also `?project__in=`, `?name__icontains=`.
- **Upload:** `POST /project-attachments/` multipart `{project, file_upload}` → Bunny CDN.
- **Delete:** `DELETE /project-attachments/{id}/` → CDN cleanup.
- RBAC: `view_project` (read) / `update_project` (write).
