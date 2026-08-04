# Lead Filters API

Backing for the **"Filter leads"** panel: the multi-section side-sheet with
Source, Product/Service, Stage, Users, Team, Created, Deal value and Lead Score,
each with an **is / is not** toggle where applicable.

Two kinds of calls:

1. **Populate the panel** — small GET endpoints that return the option lists the
   user picks from (sources, products, statuses/stages, users, teams).
2. **Apply the filters** — the same `GET /api/v1/crm/leads/` list endpoint (and
   the `GET /api/v1/crm/leads/board/` Kanban variant) with the query params
   documented below. There is **no** dedicated "filter" endpoint — filters are
   query params on the list. `LeadFilter` (`crm/filters/lead.py`) is the single
   source of truth.

Auth for everything here: authenticated user. Reads are RBAC- and tenant-scoped.
Base prefix: `/api/v1/crm/` unless noted (`/api/v1/management/` for users/teams).

---

## Part 1 — Populate the panel (option-list GETs)

All of these are paginated (`StandardResultsSetPagination`, page size 100,
`?page=`/`?page_size=`) and most accept `?search=`. Cache the results per org —
they change rarely.

| Panel section | Endpoint | Notes |
| :--- | :--- | :--- |
| **Source** | `GET /api/v1/crm/lead-sources/` | Each item → `{lead_source_id, name, color, lead_count, is_active, is_upsell, is_readonly}`. Filter to active with `?is_active=true`. Use `lead_source_id` as the filter value. See [Lead Sources admin](#lead-sources-admin-crm-settings) for the full object + management endpoints. |
| **Product / Service** | `GET /api/v1/crm/products/` | `{product_id, product_name, price, …}`. Use `product_id` as the filter value. |
| **Stage** | `GET /api/v1/crm/lead-statuses/` | `{lead_status_id, name, status_type, color, position, is_active}`, ordered by `position`. These are the pipeline stages (New / Qualified / Quote / Negotiation / Won / Lost). Use `lead_status_id`. |
| — stage type catalog | `GET /api/v1/crm/lead-statuses/status-types/` | Read-only global fixed types (§6.3) if you need to group stages by `status_type`. |
| **Select Users** | `GET /api/v1/management/users/` | Org users → use `user_id` as the filter value for `assignees` / `lead_owner`. Supports `?search=`. |
| — users assignable to one lead | `GET /api/v1/crm/leads/{lead_id}/assignable-users/` | Only active users; record-access checked. Useful for the assign action, not the filter panel. |
| **Team** | `GET /api/v1/management/teams/` | Org teams → use `team_id` for `assigned_team`. |
| **Territory** (if shown) | `GET /api/v1/crm/territories/` | `{territory_id, name, parent_territory, parent_name, manager, manager_detail, lead_count, color, is_group}`. Use `territory_id` as the filter value. See [Territories admin](#territories-admin-crm-settings) for the full object + management endpoints. |
| **Industry** (if shown) | `GET /api/v1/crm/industries/` | `{industry_id, name, lead_count, is_active}`. Use `industry_id` as the filter value. See [Lead Industries admin](#lead-industries-admin-crm-settings) for the full object + management endpoints. |

> The mock's Product/Service list shows industry-style labels (Office, Retail,
> Hospitality …); those are just the org's configured **products**. Populate from
> `/products/` and filter with `product`.

**Deal value** and **Created** need no option endpoint — they are free numeric /
date inputs. **Lead Score** (Hot / Warm / Cold) is a fixed client-side bucketing
over the numeric `lead_score` (see below); no endpoint required.

---

## Part 2 — Apply the filters

```
GET /api/v1/crm/leads/?<params>
```

Standard list response (paginated, list-view-trimmed rows — the response only
includes the columns marked visible in the org's field config for the `list`
view, plus the always-present identity fields `lead_id`, `lead_name`,
`assignees`, `status`). All params below combine with **AND**. Multi-value
params accept a **comma-separated** list (`?status__in=a,b`) and/or the
**repeated-param** form (`?status__in=a&status__in=b`) — both work and may be
mixed. Every section supports **is** (positive) and, where noted, **is not**
(`__not`, implemented via `.exclude()`).

Same params also work on the Kanban board: `GET /api/v1/crm/leads/board/`.

### Source

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `lead_source__in` | `?lead_source__in=<uuid>,<uuid>` |
| is not | `lead_source__not` | `?lead_source__not=<uuid>,<uuid>` |

(Single-value `lead_source=<uuid>` also accepted.)

### Product / Service

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `product__in` | `?product__in=<uuid>,<uuid>` |
| is not | `product__not` | `?product__not=<uuid>,<uuid>` |

Maps to the lead's M2M `products`. (Single-value `product=<uuid>` accepted.)

### Stage

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `status__in` | `?status__in=<uuid>,<uuid>` |
| is not | `status__not` | `?status__not=<uuid>,<uuid>` |

(Single-value `status=<uuid>` accepted. `status_name` / `status_name__icontains`
available for name matching.)

### Select Users

The panel selects **users**; these map to the lead's assignees by default.

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `assignees__in` | `?assignees__in=<user_id>,<user_id>` |
| is not | `assignees__not` | `?assignees__not=<user_id>,<user_id>` |

Owner-based variants if the UI later distinguishes owner vs assignee:
`lead_owner` / `lead_owner__in`, plus `owner_mode=me` (current user's leads) or
`owner_mode=unassigned`.

### Team

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `assigned_team__in` | `?assigned_team__in=<team_id>,<team_id>` |
| is not | `assigned_team__not` | `?assigned_team__not=<team_id>,<team_id>` |

Convenience: `my_team=true` → leads on any team the caller belongs to.

### Created

Date-only range (inclusive, whole-day). The chips (Today / Last 7 / 30 / 60 / 90
days / This month) are computed client-side into a concrete `after`/`before`
pair; the From/To pickers set them directly.

| Field | Param |
| :--- | :--- |
| From | `created_at_after=YYYY-MM-DD` |
| To | `created_at_before=YYYY-MM-DD` |

Example — "Last 7 days" resolves to
`?created_at_after=2026-06-24&created_at_before=2026-07-01`.

(`updated_at_after`/`_before` and `converted_on_after`/`_before` exist too.)

### Deal value (₹ lakhs)

Computed per lead from its products' prices, honoring the org's
`LeadRules.lead_value_calc` (`max` default, or `sum`). **Params are raw rupees** —
the panel shows lakhs, so multiply the input by 100,000 before sending.

| Field | Param |
| :--- | :--- |
| Min | `lead_value_min=<rupees>` |
| Max | `lead_value_max=<rupees>` |

Example — Min 5 lakhs, Max 20 lakhs → `?lead_value_min=500000&lead_value_max=2000000`.

### Lead Score

Fixed buckets over the numeric `lead_score` (0–100). Translate the chosen chip to
a min/max range:

| Chip | Range | Params |
| :--- | :--- | :--- |
| Hot (75+) | ≥ 75 | `?lead_score_min=75` |
| Warm (45–74) | 45–74 | `?lead_score_min=45&lead_score_max=74` |
| Cold (< 45) | < 45 | `?lead_score_max=44` |

If multiple chips are selected, send the union's widest bounds or issue one
request per bucket and merge client-side (the params express a single contiguous
range, not a set).

---

## Other useful list params (not in the panel but available)

- **Free-text search:** `?search=<text>` — matches lead_name, first/last name,
  email, phone, mobile_no, organization_name.
- **Archive scope:** `?is_archive=true|false` (list defaults to **not** archived).
- **Conversion:** `?is_converted=true|false`.
- **Aging in stage:** `?stale_days=14` (or `30`) — in current stage ≥ N days;
  or `?stage_entered_after=`/`?stage_entered_before=`.
- **My leads:** `?is_teams=true` — leads the caller owns or is assigned to.
- **Industry / Territory:** `industry__in` / `territory__in` (+ `__not` for
  industry), or `*_name` / `*_name__icontains`.
- **Custom fields:** `?custom_fields.<name>=<value>` (needs the field's
  `filterable=true`). Ordering: `?ordering=custom_fields.<name>` (needs
  `sortable` + an assigned slot). Custom-field values live inside the single
  `custom_fields` object on each row; the field catalog comes from
  `GET /api/v1/crm/leads/schema/` (custom fields surface as
  `custom_fields.<name>` entries).
- **Ordering / paging:** `?ordering=<field>` (default `-created_at`),
  `?page=`, `?page_size=`.

---

## Full example

Leads that are **Source = Website/Referral**, **not** in the **Lost** stage,
assigned to **two users**, on **Team North**, created in the **last 30 days**,
**deal value 5–20 lakhs**, and **Hot**:

```
GET /api/v1/crm/leads/
  ?lead_source__in=<website_id>,<referral_id>
  &status__not=<lost_status_id>
  &assignees__in=<user1_id>,<user2_id>
  &assigned_team__in=<team_north_id>
  &created_at_after=2026-06-01&created_at_before=2026-07-01
  &lead_value_min=500000&lead_value_max=2000000
  &lead_score_min=75
```

**Reset All** = drop every filter param and re-fetch the bare list.

---

## The QUERY method (search with a request body)

Every filter in [Part 2](#part-2--apply-the-filters) can also be sent as a **JSON
body** using the IETF **`QUERY`** HTTP method on the same collection URL, instead
of a long URL query string:

```
QUERY /api/v1/crm/leads/ HTTP/1.1
Content-Type: application/json

{
  "lead_source__in": "<website_id>,<referral_id>",
  "status__not": "<lost_status_id>",
  "assignees__in": ["<user1_id>", "<user2_id>"],
  "created_at_after": "2026-06-01",
  "lead_value_min": 500000,
  "lead_score_min": 75,
  "ordering": "-created_at"
}
```

`QUERY` is the standardised verb for **safe, idempotent search that carries a
body** — it behaves exactly like the `GET` list (same `LeadFilter`, saved
filters, custom-field filtering/ordering, RBAC, pagination, and list-view-trimmed
rows). It exists to avoid URL-length limits and keep filter values out of access
logs when a selection gets large (many ids, custom fields, nested chips).

**When to use it:** reach for `QUERY` when the filter set is big enough to strain
a URL (long `__in` lists, lots of custom fields); otherwise plain `GET` is fine.
The result is byte-identical to the equivalent `GET`.

**Body shape** — the **same flat param map** the GET query string uses (keys are
`LeadFilter` param names). Value conventions:

| Body value | Sent as | Note |
| :--- | :--- | :--- |
| `"1,2"` (string) | `?key=1,2` | comma-separated list, as in the URL |
| `[1, 2]` (array) | `?key=1&key=2` | array → repeated param (multi-value fields) |
| `true` / `false` (bool) | `?key=true` / `false` | lowercased for the boolean widgets |
| `null` | `?key=` | empty value |
| number | stringified | validated by the FilterSet exactly like GET |

**Pagination & URL params still work.** `page` / `page_size` / `saved_filter_id`
may be supplied **either** in the body **or** in the URL query string of the QUERY
request — URL params that the body doesn't override are preserved. So
`QUERY /api/v1/crm/leads/?page=2` with the filters in the body pages correctly,
and the response is the normal paginated `{count, results, …}` envelope.

Availability: bound on **`/api/v1/crm/leads/`** and **`/api/v1/crm/customers/`**
(both map the `query` verb to the same `list` pipeline). Same permission gate as
the list (`view_lead` / `view_customer`). The Kanban `board` endpoint stays
`GET`-only — use the URL params for it.

---

## Saved Filters API

The panel's selection can be persisted as a **saved filter** so the user can
re-apply it later. A saved filter just stores the query-param dict (the
`filter_definition`) and is re-applied to the list via `?saved_filter_id=`.

Base path: `/api/v1/crm/saved-filters/`. Backing model: `SavedFilter`
(`access_control/models.py`). CRUD is a standard `ModelViewSet`.

**Scope & auth.** A user only ever sees/edits **their own** filters — the
queryset is scoped to `request.user` + `request.org`. Reads need the
`view_settings` codename, writes need `update_settings` (same as UserViewSettings,
no per-resource codename). Rate-limited per the global throttle.

**Limits & rules.**
- Max **5 saved filters per user per module** (`MAX_PER_MODULE`; clean 400 on
  exceed). The ceiling is checked **only when a write adds a row** — creating a
  new filter, or an update that moves one to a different `module`. **Editing a
  filter in place** (rename, change `filter_definition`, reorder) is **never**
  blocked by the limit, even when the module is already at 5.
- `(user, org, module, name)` is **unique** — a duplicate name in a module returns
  a clean **400** with a user-safe message (`{"name": "A saved filter named '…'
  already exists for this module."}`). This is pre-checked in the serializer, so a
  duplicate never surfaces as a 500 from the DB constraint.
- `filter_definition` **must be a non-empty object.** An empty `{}` (a chip that
  filters nothing) is rejected with **400** (`{"filter_definition": "Add at least
  one filter before saving."}`) rather than saved as a greyed/inert chip. Only
  `saved_filter_id` + `name` are hard-required on the *response*, but on **write**
  at least one filter key is required.
- **Keys are round-tripped verbatim.** The stored `filter_definition` keys are
  never rewritten or normalised on save — they must be the exact `LeadFilter`
  param names the list URL uses, and they come back byte-identical on read.
  Values may be strings or numbers.
- `module` ∈ `lead` | `customer` | `task` | `followup` | `product`. For the Leads
  panel use `lead`.
- `visibility` is **read-only** (always `private` in phase 1; a seam for future
  team-shared filters).
- `is_valid` / `invalid_reason` are **server-set**. A definition that references a
  deactivated/purged custom field is stored as `is_valid:false` (greyed in the UI)
  rather than rejected — reactivating the field heals it. An invalid filter
  **fails inert**: it never runs (never widens the result set).

### 1. List saved filters

```
GET /api/v1/crm/saved-filters/?module=lead
```

`?module=` optionally scopes to one module (omit to get all of the user's).
Ordered by `(module, order, created_at)`.

**200 Response** — the standard **DRF-paginated envelope** (`{count, next,
previous, results}`, `StandardResultsSetPagination`). The rows live under
**`results`**; it is **never** a bare array, even for a single row.

```json
{
  "count": 1,
  "next": null,
  "previous": null,
  "results": [
    {
      "saved_filter_id": "…uuid…",
      "module": "lead",
      "name": "Hot North-team leads",
      "visibility": "private",
      "filter_definition": {
        "lead_source__in": "<website_id>,<referral_id>",
        "status__not": "<lost_status_id>",
        "assigned_team__in": "<team_north_id>",
        "created_at_after": "2026-06-01",
        "lead_value_min": 500000,
        "lead_score_min": 75
      },
      "is_valid": true,
      "invalid_reason": null,
      "order": 0,
      "created_at": "2026-07-01T09:12:44.512Z",
      "updated_at": "2026-07-01T09:12:44.512Z"
    }
  ]
}
```

### 2. Create a saved filter

```
POST /api/v1/crm/saved-filters/
```

**Request body** — send `module`, `name`, `filter_definition`, and optionally
`order`. Everything else is server-managed. The `filter_definition` is exactly the
**query-param dict** from [Part 2](#part-2--apply-the-filters) (keys are the
FilterSet param names; values are the same strings you'd put in the URL —
comma-separated lists are fine).

```json
{
  "module": "lead",
  "name": "Hot North-team leads",
  "filter_definition": {
    "lead_source__in": "<website_id>,<referral_id>",
    "status__not": "<lost_status_id>",
    "assigned_team__in": "<team_north_id>",
    "created_at_after": "2026-06-01",
    "lead_value_min": 500000,
    "lead_score_min": 75
  },
  "order": 0
}
```

**201 Response**: the **created object, unwrapped** (same shape as a single list
item above — not `{id:…}` and not wrapped in `results`), so the frontend can
refresh the chip in place. Every key in `filter_definition` is validated against
the module's FilterSet catalog + custom fields; **unknown keys → 400**:

```json
{ "filter_definition": "Unknown filter key(s): foo, bar." }
```

Other 400s (all user-safe, surfaced verbatim):

| Condition | 400 body |
| :--- | :--- |
| 6th filter in a module | `{"module": "Limit of 5 saved filters per module reached."}` |
| Duplicate name in the module | `{"name": "A saved filter named '…' already exists for this module."}` |
| Empty `filter_definition` (`{}` or missing) | `{"filter_definition": "Add at least one filter before saving."}` |
| Unknown filter key(s) | `{"filter_definition": "Unknown filter key(s): foo, bar."}` |

### 3. Update / rename / reorder

```
PUT   /api/v1/crm/saved-filters/{saved_filter_id}/     # full
PATCH /api/v1/crm/saved-filters/{saved_filter_id}/     # partial
```

Editable: `name`, `filter_definition`, `order`. (`visibility`, `is_valid`,
`invalid_reason` are read-only.) Same validation as create — duplicate-name,
empty-definition, and unknown-key all return the same user-safe **400**s. The
**5-per-module limit does not apply** to an in-place edit (only to writes that add
a row), so a user can always re-save an existing chip even when the module is
full. **200** with the **full updated object, unwrapped**.

### 4. Delete

```
DELETE /api/v1/crm/saved-filters/{saved_filter_id}/
```

**204** on success.

### 5. Match count (optional, on demand)

```
GET /api/v1/crm/saved-filters/{saved_filter_id}/count/
```

Approximate count of records the filter matches — **never** called implicitly on
list render (no per-chip COUNT on every page load). Cached 60s. Invalid filters
return `null`.

```json
{ "count": 42 }
```

Invalid filter → `{ "count": null, "invalid_reason": "custom_fields.budget" }`.

### 6. Apply a saved filter to the list

```
GET /api/v1/crm/leads/?saved_filter_id=<uuid>
```

The stored `filter_definition` is layered **under** any explicit params on the
request (explicit params win) and run through the same `LeadFilter`. Two
behavioral notes:

- **Pagination is unchanged.** A saved filter is just a stored param dict, so the
  list keeps its normal page-number pagination (`StandardResultsSetPagination`,
  `count`/`page`/`page_size`). `?saved_filter_id=` behaves exactly like passing the
  same filters inline — the range label and page selector work as usual.
- An **invalid** saved filter fails inert (returns a DRF validation error rather
  than silently running a widened query); an unknown/foreign `saved_filter_id`
  → **404**.

### 7. Apply a saved filter to the Kanban board

```
GET /api/v1/crm/leads/board/?saved_filter_id=<uuid>
```

The board applies the saved filter the same way the list does — the stored
`filter_definition` layers under explicit params and narrows lane counts + cards,
still returning the `{board_total, lane_page_size, lanes:[...]}` shape. Each lane's
`next_url` carries the `saved_filter_id` forward, so per-lane "load more"
(`GET /leads/?saved_filter_id=…&status=<lane>&page=2`) stays consistent. Invalid
filter → **400** (fail inert); unknown id → **404**.

> Saved filters apply on the `lead`, `task`, and `followup` list endpoints and on
> the Lead Kanban `board` endpoint (all reuse `SavedFilterApplyMixin.filter_queryset`).

---

## Lead Status admin (CRM Settings)

The **CRM Settings → Lead Status** screen manages the org's pipeline stages. Each
status maps to exactly one of the 5 backend-fixed **status types**
(New → In Progress → Won → Lost → Junk, §6). Admins can add / edit / delete
statuses and **reorder them within a type** via the drag handle. All endpoints are
served by `LeadStatusViewSet` and mount under `/api/v1/crm/lead-statuses/`.

**Scope & auth.** Reads require the `view_settings` permission (plus lead
`VIEW`); writes require `update_settings` (plus the matching lead
`CREATE`/`UPDATE`/`DELETE`). Every response is org-scoped.

| Action | Method | Path |
| :--- | :--- | :--- |
| List statuses | GET | `/api/v1/crm/lead-statuses/` |
| Fixed status types (read-only, global) | GET | `/api/v1/crm/lead-statuses/status-types/` |
| Create status | POST | `/api/v1/crm/lead-statuses/` |
| Retrieve one | GET | `/api/v1/crm/lead-statuses/{lead_status_id}/` |
| Update | PUT / PATCH | `/api/v1/crm/lead-statuses/{lead_status_id}/` |
| Delete | DELETE | `/api/v1/crm/lead-statuses/{lead_status_id}/` |
| Reorder (within type) | POST | `/api/v1/crm/lead-statuses/reorder/` |

The status object shape (returned on list / retrieve / create / update):

```json
{
  "lead_status_id": "b1f3…",
  "name": "Negotiation",
  "status_type": "in_progress",
  "status_type_name": "In Progress",
  "color": "#F5A623",
  "position": 3,
  "is_active": true,
  "is_default": false,
  "is_won": false,
  "is_lost": false,
  "is_junk": false,
  "is_readonly": false
}
```

`status_type` is written and read as its **code** (`new` / `in_progress` / `won` /
`lost` / `junk`). `is_won` / `is_lost` / `is_junk` are read-only flags derived from
the type. `organization`, `created_by`, `is_readonly` are read-only.

### List statuses

```
GET /api/v1/crm/lead-statuses/
```

Returns the org's statuses **already banded by type** then by within-type
`position` (`ORDER BY status_type.position, position`), so the UI renders the fixed
type order directly. Paginated (`StandardResultsSetPagination`).

### Status type catalog

```
GET /api/v1/crm/lead-statuses/status-types/
```

The 5 global fixed types, read-only, ordered by `position`. Each item →
`{code, name, position}`. Tenants cannot create/edit/delete these.

**200 Response**

```json
[
  {"code": "new", "name": "New", "position": 0},
  {"code": "in_progress", "name": "In Progress", "position": 1},
  {"code": "won", "name": "Won", "position": 2},
  {"code": "lost", "name": "Lost", "position": 3},
  {"code": "junk", "name": "Junk", "position": 4}
]
```

### Create a status

```
POST /api/v1/crm/lead-statuses/
```

```json
{ "name": "Demo Call", "status_type": "in_progress", "color": "#4A90E2", "position": 4 }
```

Returns **201** with the created status object. `organization` / `created_by` are
stamped automatically.

> Only **one** status of type `won` and **one** of type `lost` may exist per org
> (unique constraints) — creating a second returns **400**.
> The new status's `position` must respect type-order banding (see Reorder); a
> position that lands inside another type's band returns **400**.

### Update a status

```
PATCH /api/v1/crm/lead-statuses/{lead_status_id}/
```

Partial (`PATCH`) or full (`PUT`). Same banding rule applies when `position` is
changed. System-protected statuses (`is_readonly: true`) return **403** for
non-superusers.

### Delete a status

```
DELETE /api/v1/crm/lead-statuses/{lead_status_id}/
```

Returns **204** on success. Blocked with **400** when:

- any lead currently references the status —
  `{"detail": "Cannot delete this lead status because it is referenced by existing leads."}`
- it is the **last** status mapped to its type (§6.6) —
  `{"detail": "Cannot delete the last lead status mapped to its status type."}`

System-protected statuses (`is_readonly: true`) return **403** for non-superusers.

### Reorder statuses (within a type)

```
POST /api/v1/crm/lead-statuses/reorder/
```

Body is a flat list of `{lead_status_id, position}`; each listed status has its
`position` set. Statuses omitted from the body keep their current `position`.

```json
[
  { "lead_status_id": "b1f3…", "position": 2 },
  { "lead_status_id": "c7a9…", "position": 3 }
]
```

**200 Response**

```json
{ "detail": "Reorder successful." }
```

> **Type-order banding (§6.7) is enforced.** The *resulting* order must keep each
> type's statuses contiguous and in the fixed type order
> (`new < in_progress < won < lost < junk`). You can freely reorder statuses
> **within** a type, but you cannot move one across a type boundary — e.g. placing
> a **Won** status after a **Lost** status is rejected with **400**:
>
> ```json
> { "detail": "Reordering would break status-type order: 'Won' statuses must come before 'Lost' statuses." }
> ```
>
> On rejection nothing is written (the check runs before the transaction). The same
> banding rule is enforced on create/update whenever `position` is supplied.

---

## Lead Sources admin (CRM Settings)

The **CRM Settings → Lead sources** screen manages where an org's leads come from
("Website", "Referral", "LinkedIn", …). Each source carries a **colour dot**, a
live **lead count**, and an active toggle. One system source — **"Customer"** —
is special: picking it on a new lead marks that lead as an **upsell** to an
existing customer (§7.6), so it is protected (cannot be renamed or deleted). All
endpoints are served by `LeadSourceViewSet` and mount under
`/api/v1/crm/lead-sources/`.

**Scope & auth.** Reads require the `view_settings` permission (plus lead
`VIEW`); writes require `update_settings` (plus the matching lead
`CREATE`/`UPDATE`/`DELETE`). Every response is org-scoped.

| Action | Method | Path |
| :--- | :--- | :--- |
| List sources (with counts) | GET | `/api/v1/crm/lead-sources/` |
| Create source | POST | `/api/v1/crm/lead-sources/` |
| Retrieve one | GET | `/api/v1/crm/lead-sources/{lead_source_id}/` |
| Update / rename / recolour | PUT / PATCH | `/api/v1/crm/lead-sources/{lead_source_id}/` |
| Delete | DELETE | `/api/v1/crm/lead-sources/{lead_source_id}/` |
| Bulk activate / deactivate | POST | `/api/v1/crm/lead-sources/bulk-toggle/` |

The source object shape (returned on list / retrieve / create / update):

```json
{
  "lead_source_id": "a1b2…",
  "name": "Website",
  "description": "Lead from company website or landing page",
  "color": "#3B82F6",
  "lead_count": 14,
  "is_active": true,
  "is_upsell": false,
  "is_readonly": false
}
```

`organization`, `created_by`, `is_upsell`, and `is_readonly` are **read-only** —
a client cannot mint a second upsell source or flip protection via the API.

### List sources

```
GET /api/v1/crm/lead-sources/
```

Returns the org's sources, paginated (`StandardResultsSetPagination`). Each row
includes **`lead_count`** — the number of *non-deleted* leads currently
referencing that source — annotated directly on the query (no N+1), so the
settings UI renders the "14 leads" figures without calling the analytics
dashboard. Sources with no leads report `0`. Filter to active sources with
`?is_active=true`.

> `lead_count` is a live count on the settings list. The **dashboard**
> lead-sources endpoint (`/api/v1/crm/dashboard-crm/lead-sources/`) is a separate,
> period-scoped analytics view with won/lost/payment breakdowns — use that for
> reporting, this one for the settings screen.

### Colours

`color` is an optional **6-digit hex** string (`#RRGGBB`). It is validated on
write and normalised to upper-case; a non-hex value (e.g. `"red"`, `"#FFF"`)
returns **400**:

```json
{ "color": ["Colour must be a 6-digit hex value, e.g. #3B82F6."] }
```

An empty string is allowed (no dot colour). Defaults are seeded per source on org
creation (Website → blue, Referral → green, …).

### Create a source

```
POST /api/v1/crm/lead-sources/
```

```json
{ "name": "IndiaMART", "color": "#0F172A", "description": "Inbound from IndiaMART" }
```

Returns **201** with the created source object. `organization` / `created_by` are
stamped automatically; `name` is unique per org (a duplicate returns **400**).
`is_upsell`/`is_readonly` sent in the body are ignored (read-only).

### Update a source

```
PATCH /api/v1/crm/lead-sources/{lead_source_id}/
```

Partial (`PATCH`) or full (`PUT`) — rename, recolour, or toggle `is_active`.
The system **"Customer"** source (`is_readonly: true`) returns **403** for
non-superusers:

```json
{ "detail": "Cannot edit or delete a system-protected lead source." }
```

### Delete a source

```
DELETE /api/v1/crm/lead-sources/{lead_source_id}/
```

Returns **204** on success. The FK from `Lead.lead_source` is `SET_NULL`, so
deleting a source simply un-sets it on any leads that used it (their `lead_count`
drops accordingly). The protected **"Customer"** source (`is_readonly: true`)
returns **403** for non-superusers.

### Bulk activate / deactivate

```
POST /api/v1/crm/lead-sources/bulk-toggle/
```

```json
{ "lead_source_ids": ["a1b2…", "c3d4…"], "is_active": false }
```

Sets `is_active` on every listed source in one query. Returns
`{ "detail": "N source(s) updated." }`. A malformed body returns **400**.

### The "Customer" upsell source (§7.6)

Every org is seeded with exactly one **`is_upsell: true`** source named
**"Customer"** (enforced by a partial unique constraint). It backs the **UPSELL**
badge in the CRM Settings UI, and:

- Picking it as the source on a **new lead** flags that lead as an upsell to an
  existing customer.
- The `create_upsell_lead` service (triggered by the customer "Create upsell"
  action, §7.6.3) **auto-assigns** this source to the lead it creates, so upsell
  leads are attributable in source filters and reports.
- It is `is_readonly` — it cannot be renamed or deleted through the API (**403**),
  keeping the badge/behaviour stable.

Existing orgs are backfilled with the "Customer" source and default colours by
migration `crm/migrations/0026_leadsource_color_leadsource_is_readonly_and_more.py`.

---

## Lead Industries admin (CRM Settings)

The **CRM Settings → Lead industries** screen manages the industry verticals a
lead (or customer) can belong to ("Technology", "Retail", "Healthcare", …). Each
industry shows a live **lead count** and an active toggle. Endpoints are served by
`IndustryViewSet` and mount under `/api/v1/crm/industries/`. Unlike lead sources,
industries have **no colour dot and no system-protected row** — every industry is
fully editable/deletable.

**Scope & auth.** Reads require the `view_settings` permission (plus lead
`VIEW`); writes require `update_settings` (plus the matching lead
`CREATE`/`UPDATE`/`DELETE`). Every response is org-scoped.

| Action | Method | Path |
| :--- | :--- | :--- |
| List industries (with counts) | GET | `/api/v1/crm/industries/` |
| Create industry | POST | `/api/v1/crm/industries/` |
| Retrieve one | GET | `/api/v1/crm/industries/{industry_id}/` |
| Update / rename | PUT / PATCH | `/api/v1/crm/industries/{industry_id}/` |
| Delete | DELETE | `/api/v1/crm/industries/{industry_id}/` |
| Bulk activate / deactivate | POST | `/api/v1/crm/industries/bulk-toggle/` |

The industry object shape (returned on list / retrieve / create / update):

```json
{
  "industry_id": "e5f6…",
  "name": "Technology",
  "description": "Software, IT services and hardware",
  "lead_count": 8,
  "is_active": true
}
```

`organization` and `created_by` are read-only.

### List industries

```
GET /api/v1/crm/industries/
```

Returns the org's industries, paginated (`StandardResultsSetPagination`). Each row
includes **`lead_count`** — the number of *non-deleted* leads currently
referencing that industry — annotated on the query (no N+1), so the settings UI
renders the "8 leads" figures directly. Industries with no leads report `0`.
Filter to active industries with `?is_active=true`.

### Create an industry

```
POST /api/v1/crm/industries/
```

```json
{ "name": "Aerospace", "description": "Aviation and defence" }
```

Returns **201** with the created industry object. `organization` / `created_by`
are stamped automatically; `name` is unique per org (a duplicate returns **400**).

### Update an industry

```
PATCH /api/v1/crm/industries/{industry_id}/
```

Partial (`PATCH`) or full (`PUT`) — rename, edit the description, or toggle
`is_active`. **200** with the updated object.

### Delete an industry

```
DELETE /api/v1/crm/industries/{industry_id}/
```

Returns **204** on success. The FK from `Lead.industry` / `Customer.industry` is
`SET_NULL`, so deleting an industry simply un-sets it on any records that used it.

### Bulk activate / deactivate

```
POST /api/v1/crm/industries/bulk-toggle/
```

```json
{ "industry_ids": ["e5f6…", "a7b8…"], "is_active": false }
```

Sets `is_active` on every listed industry in one query. Returns
`{ "detail": "N industries updated." }`. A malformed body returns **400**.

### Seeding

Every org is seeded with a default industry list on creation (Technology, Finance,
Healthcare, Education, Manufacturing, Retail, Real Estate, Hospitality, Logistics,
Other — `crm.constants.DEFAULT_INDUSTRIES`). Run `seed_crm_defaults` to backfill
the list onto existing orgs (idempotent `get_or_create`).

> **Filtering leads by industry** uses `industry__in` / `industry__not` /
> `industry_name` on the list endpoint — see
> [Other useful list params](#other-useful-list-params-not-in-the-panel-but-available).

---

## Task Status admin (CRM Settings)

The **CRM Settings → Task status** screen manages the org's task workflow lanes
("To do", "In Progress", "Blocked", "Done", …). Each status carries a **colour
dot**, a **status-type badge**, a live **task count**, and a drag handle for
reordering. Each status maps to one of the backend-fixed **task status types**
(To do / In Progress / Completed / Cancelled). Endpoints are served by
`CRMTaskStatusViewSet` and mount under `/api/v1/crm/crm-task-statuses/`.

**Scope & auth.** Reads require `view_settings` (plus task `view_task`); writes
require `update_settings` (plus the matching task `update_task`/`delete_task`).
Every response is org-scoped.

| Action | Method | Path |
| :--- | :--- | :--- |
| List statuses (with counts) | GET | `/api/v1/crm/crm-task-statuses/` |
| Status type catalog (read-only, global) | GET | `/api/v1/crm/crm-task-statuses/status-types/` |
| Create status | POST | `/api/v1/crm/crm-task-statuses/` |
| Retrieve one | GET | `/api/v1/crm/crm-task-statuses/{crm_task_status_id}/` |
| Update / rename / recolour | PUT / PATCH | `/api/v1/crm/crm-task-statuses/{crm_task_status_id}/` |
| Delete | DELETE | `/api/v1/crm/crm-task-statuses/{crm_task_status_id}/` |
| Reorder | POST | `/api/v1/crm/crm-task-statuses/reorder/` |

The status object shape (returned on list / retrieve / create / update):

```json
{
  "crm_task_status_id": "d4e5…",
  "name": "In Progress",
  "status_type": "in_progress",
  "status_type_name": "In Progress",
  "color": "#F59E0B",
  "position": 1,
  "task_count": 7,
  "is_active": true,
  "is_default": false,
  "is_completed": false,
  "is_cancelled": false,
  "is_readonly": true
}
```

`status_type` is written and read as its **code** (`open` / `in_progress` /
`completed` / `cancelled`). `is_completed` / `is_cancelled` are read-only flags
derived from the type. `organization`, `created_by`, `is_readonly` are read-only.

### List statuses

```
GET /api/v1/crm/crm-task-statuses/
```

Returns the org's task statuses ordered by `position`, paginated
(`StandardResultsSetPagination`). Each row includes **`task_count`** — the number
of *non-archived* tasks in that status — annotated on the query (no N+1), so the
settings UI renders the "12 tasks" figures directly. Statuses with no tasks report
`0`.

> The count excludes **archived** tasks (`is_archived=True`), mirroring the Kanban
> board's lane counts. Tasks have no soft-delete field — `is_archived` is the
> exclusion flag (unlike leads, which use `deleted_at`).

### Status type catalog

```
GET /api/v1/crm/crm-task-statuses/status-types/
```

The backend-fixed task status types, read-only, ordered by `position`. Each item →
`{code, name, position}` (`open` / `in_progress` / `completed` / `cancelled`).

### Create a status

```
POST /api/v1/crm/crm-task-statuses/
```

```json
{ "name": "In Review", "status_type": "in_progress", "color": "#4A90E2" }
```

Returns **201** with the created status object. `organization` / `created_by` are
stamped automatically; `name` is unique per org (a duplicate returns **400**).

### Update a status

```
PATCH /api/v1/crm/crm-task-statuses/{crm_task_status_id}/
```

Partial (`PATCH`) or full (`PUT`) — rename, recolour, or toggle `is_active`.
System-protected statuses (`is_readonly: true`, the seeded defaults) return
**403** for non-superusers.

### Delete a status

```
DELETE /api/v1/crm/crm-task-statuses/{crm_task_status_id}/
```

Returns **204** on success. Blocked with **400** when the status is referenced by
existing tasks, or when it is the **last** status mapped to its type.
System-protected statuses (`is_readonly: true`) return **403** for non-superusers.

### Reorder statuses

```
POST /api/v1/crm/crm-task-statuses/reorder/
```

Body is a flat list of `{crm_task_status_id, position}`; each listed status has its
`position` set. Statuses omitted from the body keep their current `position`.

```json
[
  { "crm_task_status_id": "d4e5…", "position": 2 },
  { "crm_task_status_id": "f6a7…", "position": 3 }
]
```

Returns `{ "detail": "Reorder successful." }`.

### Seeding

Every org is seeded with the default task statuses on creation (Open, In Progress,
Completed, Cancelled — `crm.constants.DEFAULT_CRM_TASK_STATUSES`), each mapped to a
type and flagged `is_readonly` so the workflow stays intact.

---

## Territories admin (CRM Settings)

The **CRM Settings → Territories** screen manages the org's **hierarchical** sales
territory tree ("India → North → Delhi NCR", …). Each node has a name, an optional
**territory manager** (a user), a live **lead count**, and a **parent** — the tree
is an adjacency list (`parent_territory` self-FK), so the frontend builds the
nested view from the flat list. Endpoints are served by `TerritoryViewSet` and
mount under `/api/v1/crm/territories/`.

**Scope & auth.** Reads require `view_settings` (plus lead `VIEW`); writes require
`update_settings` (plus the matching lead `CREATE`/`UPDATE`/`DELETE`). Every
response is org-scoped.

| Action | Method | Path |
| :--- | :--- | :--- |
| List territories (with counts) | GET | `/api/v1/crm/territories/` |
| Create territory | POST | `/api/v1/crm/territories/` |
| Retrieve one | GET | `/api/v1/crm/territories/{territory_id}/` |
| Update / rename / re-parent | PUT / PATCH | `/api/v1/crm/territories/{territory_id}/` |
| Delete | DELETE | `/api/v1/crm/territories/{territory_id}/` |

The territory object shape (returned on list / retrieve / create / update):

```json
{
  "territory_id": "b8c9…",
  "name": "Delhi NCR",
  "parent_territory": "a1b2…",
  "parent_name": "North Zone",
  "manager": "u-1234…",
  "manager_detail": {
    "user_id": "u-1234…",
    "email": "rahul@acme.com",
    "full_name": "Rahul Krishnan",
    "is_active": true
  },
  "lead_count": 6,
  "color": "#60A5FA",
  "zone_label": "Delhi NCR",
  "is_group": false
}
```

- **`parent_territory`** — write with a `territory_id` (or `null` for a top-level
  node). `parent_name` is the read-only name of that parent for the tree UI.
- **`manager`** — write with a **`user_id`** (or `null`); read it back as the
  nested lightweight user object **`manager_detail`**. `organization`,
  `created_by` are read-only.

### List territories

```
GET /api/v1/crm/territories/
```

Returns the org's territories (flat), paginated
(`StandardResultsSetPagination`). Each row includes **`lead_count`** — the number
of *non-deleted* leads assigned **directly to that exact node** — annotated on the
query (no N+1). The frontend nests the tree by `parent_territory`.

> **The count is self-only — it is NOT rolled up to ancestors.** A parent zone
> ("North") shows the count of leads whose territory is literally "North" (usually
> `0`); the leaf regions under it ("Delhi NCR": 6) carry their own leads. This
> matches the settings UI, where parent nodes read "0 leads".

### Create a territory

```
POST /api/v1/crm/territories/
```

```json
{ "name": "Bengaluru", "manager": "u-5678…", "parent_territory": "a1b2…" }
```

Returns **201** with the created territory object. `manager` and
`parent_territory` are optional. `organization` / `created_by` are stamped
automatically; `name` is unique per org (a duplicate returns **400**).

### Update / re-parent a territory

```
PATCH /api/v1/crm/territories/{territory_id}/
```

Rename, reassign the `manager`, or **re-parent** by setting `parent_territory`.
A move that would create a **cycle** — making a node its own parent or a child of
one of its own descendants — is rejected with **400**:

```json
{ "parent_territory": ["A territory cannot be its own parent or descendant."] }
```

### Delete a territory

```
DELETE /api/v1/crm/territories/{territory_id}/
```

Returns **204** on success. Blocked with **400** when the territory is referenced
by existing leads:

```json
{ "detail": "Cannot delete this territory because it is referenced by existing leads." }
```

Deleting a node **orphans its children** (their `parent_territory` FK is
`SET_NULL`, so they become top-level) rather than cascading.

### Seeding

Territories are **not** seeded on org creation. The standalone
`seed_territories_data` management command seeds a demo zone→region hierarchy
(North/South/West/East zones + regions); the `manager` field is left null there.

---

## Lead Rules (CRM Settings)

The **CRM Settings** page's behaviour cards — **Lead Value**, **Conversion**, and
**Duplicate Detection** — are all backed by **one per-org `LeadRules` singleton**.
There is no per-card endpoint: every toggle on those three cards reads and writes
the same object at `/api/v1/crm/lead-rules/`.

**Scope & auth.** `HasSettingsPermission` — reads (`GET`) require `view_settings`;
writes (`PUT`/`PATCH`) require `update_settings` (superuser/staff bypass). The
object is auto-created with defaults on first access, so there is no create/delete
— only get and update.

| Action | Method | Path |
| :--- | :--- | :--- |
| Get the org's lead rules | GET | `/api/v1/crm/lead-rules/` |
| Replace all fields | PUT | `/api/v1/crm/lead-rules/` |
| Update some fields | PATCH | `/api/v1/crm/lead-rules/` |

The `LeadRules` object (returned by all three methods):

```json
{
  "lead_rules_id": "d4e5…",
  "conversion_mode": "status",
  "auto_convert_enabled": false,
  "auto_archive_lost_leads": false,
  "duplicate_detection": false,
  "duplicate_match_keys": ["email", "phone"],
  "duplicate_on_match": "warn",
  "duplicate_check_scope": "customers_only",
  "default_assignment_round_robin": false,
  "auto_assign_by_territory": false,
  "business_hours_only": false,
  "lead_value_calc": "max",
  "created_at": "2026-06-01T10:00:00Z",
  "updated_at": "2026-07-08T12:00:00Z"
}
```

`lead_rules_id`, `created_at`, `updated_at` are read-only.

> **PUT vs PATCH.** Every writable field carries a serializer default, so a **PUT**
> that omits a field resets it to that default (e.g. omitting `conversion_mode`
> writes back `"status"`). Use **PATCH** to change one card without touching the
> others.

### Lead Value card

| UI control | Field | Values |
| :--- | :--- | :--- |
| Value roll-up | `lead_value_calc` | `"sum"` (Sum of products) · `"max"` (Highest product value) — **default `max`** |

Drives how a lead's headline value is computed **from its products**. Note the
full resolution also honours **quote precedence** (§5.4.2): an *accepted* quote's
total wins over the highest quote total, which wins over this product roll-up —
see [`compute_lead_value`](../../crm/models/lead.py). The `lead_value_calc` toggle
only governs the no-quotes / products-only case.

### Conversion card

| UI control | Field | Values |
| :--- | :--- | :--- |
| Conversion mode | `conversion_mode` | `"status"` (Status only — Won is enough) · `"quote"` (Quote-gated — Won **and** an accepted quote) — **default `status`** |
| Auto-convert on Won + accepted quote | `auto_convert_enabled` | `true` / `false` — **default `false`** |

Both are enforced: quote-gating in the manual-convert path, and `auto_convert_enabled`
via the Won-status signal (auto-creates the Customer when a lead becomes Won **and**
has an accepted quote). "Accepted" = a quote whose status has `is_converted=true`.

### Duplicate Detection card

| UI control | Field | Values |
| :--- | :--- | :--- |
| (master toggle) | `duplicate_detection` | `true` / `false` — **default `false`**. When off, no check runs. |
| Match keys | `duplicate_match_keys` | list of field slugs, **ANDed** together — **default `["email", "phone"]`** |
| On match | `duplicate_on_match` | `"block"` · `"warn"` · `"merge"` — **default `warn`** |
| Check scope | `duplicate_check_scope` | `"customers_only"` · `"leads_and_customers"` — **default `customers_only`** |

```
PATCH /api/v1/crm/lead-rules/
```

```json
{
  "duplicate_detection": true,
  "duplicate_match_keys": ["email", "phone", "company"],
  "duplicate_on_match": "warn",
  "duplicate_check_scope": "leads_and_customers"
}
```

> **Match keys** are **ANDed** — a record is flagged only when *all* the keys match
> an existing record. Allowed values: the base keys **`email`, `phone`, `mobile_no`**
> plus any **active lead custom-field slug**. Keys are normalised on write
> (`lower`, spaces→`_`); an unknown key returns **400**:
>
> ```json
> { "duplicate_match_keys": ["Unknown match key(s): foo. Allowed: company, email, phone, ..."] }
> ```
>
> An empty list is rejected (`allow_empty=False`) — at least one key is required.
> The UI's "up to 4 keys" is a client-side cap; the backend imposes no count limit.

> **`merge`** is accepted by the API and implemented server-side (fills empty
> fields from the matched record) even though the settings UI only surfaces
> Block / Warn. `warn` creates the record then flags it `is_duplicate=true` with a
> non-blocking `warnings` array; `block` returns **400** and refuses creation.

> **Check scope** — `customers_only` runs the check on customer creation only;
> `leads_and_customers` also checks new leads and searches both tables. Custom-key
> matching only works against **leads** (Customer has no custom-field storage), so
> a custom match key is effectively lead-scoped.

#### Populating the "Add match keys" modal

There is **no dedicated "available match keys" endpoint.** The modal's option list
is composed client-side from two sources:

| Part of the modal | Source |
| :--- | :--- |
| Base chips (Email, Phone) | The fixed base keys `email` / `phone` / `mobile_no` (frontend-known). |
| Additional fields (Company, Website, WhatsApp, Mobile, GSTIN, …) | `GET /api/v1/management/custom-fields/?model_name=lead` — the org's active **lead custom fields**. |

The custom-fields list returns rows shaped
`{custom_field_id, model_name, field_name, label, field_type, order, …}`. The modal
shows each `label`, but the value written into `duplicate_match_keys` is the
`field_name` **slug** (e.g. label "Company" → slug `company`) — the same slug the
`lead-rules` validator checks against the org's active lead fields. See
[fields.md](fields.md) for the full custom-fields CRUD contract.

> **AI & Notes Visibility** (the fourth CRM Settings card) has **no backend field
> or endpoint** — it is not persisted by `lead-rules` or anything else. Omitted here
> deliberately; document it once/if it is implemented.

---

## Logging activity on a lead — Call logs & Attachments

Two related records commonly created **against a lead** from the lead detail view:
a **call log** and a **file attachment**. Both are **top-level resources** (no
nested `/leads/{id}/...` route) — the lead is named in the body via the shared
`related_to` / `related_to_id` generic-relation pattern (`related_to="lead"`,
`related_to_id=<lead_id>`). Both endpoints validate that the linked lead belongs
to the caller's org (cross-org guard in the generic-relation mixin).

### Create a call log

```
POST /api/v1/crm/call-logs/
```

Permission: **`create_call_log`** (`permission_resource="call_log"`, gated by
`MapBasedPermission`). Accepts `application/json` **or** `multipart/form-data`
(the latter when uploading a recording).

**Body:**

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `from_number` | string | **yes** | Caller number |
| `to_number` | string | **yes** | Callee number |
| `type` | `"Incoming"` / `"Outgoing"` | **yes** | Call direction |
| `related_to` | string | no* | `"lead"` to link this call to a lead (`*`link is optional for call logs; omit for an unlinked log) |
| `related_to_id` | UUID | no* | The `lead_id`. Required **if** `related_to` is given (both-or-neither). |
| `telephony_medium` | `"Manual"` / `"Twilio"` / `"Exotel"` | no | Default source |
| `status` | UUID | no | `crm_communication_status_id` |
| `duration` | duration | no | e.g. `"00:03:20"` |
| `start_time` / `end_time` | datetime | no | `end_time` must not precede `start_time` (else 400) |
| `caller` / `receiver` | UUID | no | `user_id` of the users |
| `recording_file` | file | no | Audio upload (multipart) — see below |

Example (link to a lead):

```json
{
  "from_number": "+911234567890",
  "to_number": "+919876543210",
  "type": "Outgoing",
  "telephony_medium": "Manual",
  "duration": "00:03:20",
  "related_to": "lead",
  "related_to_id": "<lead_id>"
}
```

**Read-only / server-set** (never sent): `organization`, `created_by`,
`recording_url`, `transcript`, `call_summary`, `transcription_status`.

**201** returns the full call log (`crm_call_log_id`, all fields, plus
`related_to_model` = `"lead"` and `related_to_object_id` = the `lead_id`). The
write-only `related_to`/`related_to_id` are not echoed.

**Create-time behaviour:**
- **Lead rescoring** — linking a call to a lead enqueues an async lead rescore
  (Redis-debounced 30s). (Linking to a customer rescores the customer.)
- **Recording upload / transcription** — a `recording_file` (multipart) kicks off
  an async Celery task (`transcribe_call_recording`) *if* the org's transcription
  is enabled: uploads to CDN → `recording_url`, transcribes → `transcript`,
  optional `call_summary`, then dispatches `CallRecordingReady` /
  `CallSummaryGenerated` notifications. `transcription_status` moves
  `pending → processing → completed`/`failed`.
- Parent-audit log entry is written on the lead.

### Create an attachment (linked to a lead)

```
POST /api/v1/crm/attachments/
```

Permission: **authenticated user only** (`IsAuthenticated`) — there is **no
`create_attachment` codename gate**; tenant isolation + the cross-org link guard
protect it. Accepts `multipart/form-data` (file upload) **or** `application/json`
(when the file is already hosted and you pass a URL).

**Body:**

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `related_to` | string | **yes** | `"lead"` (link is **required** for attachments) |
| `related_to_id` | UUID | **yes** | The `lead_id` |
| `file_upload` | file | one of* | The binary file (multipart). |
| `file` | URL string | one of* | Alternative to `file_upload` when already hosted. `*`exactly one of `file_upload`/`file` is required. |
| `name` | string | no | File name; **defaults to the uploaded filename** if omitted |
| `description` | string | no | Optional caption |

Multipart example (upload a file to a lead):

```
POST /api/v1/crm/attachments/    (multipart/form-data)
  file_upload:   <binary>
  related_to:    lead
  related_to_id: <lead_id>
  name:          Contract.pdf        (optional)
  description:   Signed contract      (optional)
```

JSON example (already-hosted file):

```json
{
  "file": "https://cdn.example.com/path/file.pdf",
  "related_to": "lead",
  "related_to_id": "<lead_id>",
  "name": "Contract.pdf"
}
```

The uploaded file is stored on the CDN; the model's `file` field holds the
resulting URL. `organization`, `created_by`, `uploaded_by` are set server-side.

**201** returns the attachment (`attachment_id`, `name`, `file` = CDN URL,
`description`, `uploaded_at`, `uploaded_by` (expanded), `related_to_model` =
`"lead"`, `related_to_object_id` = the `lead_id`, `object_id`, `content_type`).

**Create-time behaviour:**
- **No** lead rescoring (attachments are excluded from the rescore signal, unlike
  call logs/notes/tasks).
- **No** notification, **no** file size/MIME validation.
- Parent-audit log entry is written on the lead.

> Both endpoints accept **any** of these `related_to` targets, not just `lead`
> (e.g. `customer`, `contact`, `task`, `quotation`, …) — this section documents
> the lead case. The `related_to` value must be one of the mixin's allowed model
> names, and `related_to_id` the matching record's UUID.
