# Leads — Mobile Admin App API Guide

This document covers the endpoints backing the **Leads** screen of the admin
panel mobile app (list with status filter chips, "My leads" toggle, and lead
cards showing name, company, deal note, status pill, value, timestamp,
avatars, and a call action).

All routes are under `/api/v1/crm/`. Auth: authenticated user (JWT). Record
visibility follows RBAC (`view_lead` + record-level scoping — see
`access_control`); the "My leads" filter is a client-side use of `owner_mode=me`
(or `assignees=<my user_id>`), not a separate endpoint.

> **Read the schema endpoint first.** The lead card in the mobile UI (status
> pill, value, avatars, "Team"/"+1 more" assignee summary) is **dynamically
> rendered from the schema response**, not hardcoded — fetch and cache the
> schema before rendering the list so column order/labels/visibility match the
> org's configuration.

---

## 1. Lead schema — `GET /leads/schema/`

```
GET /api/v1/crm/leads/schema/?view_type=list
GET /api/v1/crm/leads/schema/?view_type=detail    # also used for the add/edit form
```

Permission: `view_lead`.

This is the single source of truth for which fields exist, their types, and
(for `list`/`detail`) which columns to render, in what order, and which are
fixed/hidden per the org's view settings. **Fetch this before the list/board
endpoints** — the mobile lead card binds its fields (name, status pill color,
value, assignee avatars, last-activity timestamp) off this response rather
than a fixed client-side layout, so a stale or skipped schema fetch will
render the wrong columns.

Query params:
| Param | Values | Notes |
|---|---|---|
| `view_type` | `list` (default) \| `detail` | Use `detail` for the create/edit form as well as the detail screen (system fields like `lead_score`, `is_converted`, `created_by` are always excluded, regardless of `view_type`). |

**200 Response** (abbreviated, `view_type=list`):

```jsonc
{
  "model": "Lead",
  "view_type": "list",
  "has_org_config": true,
  "has_user_settings": false,
  "fields": {
    "lead_name":  { "name": "lead_name",  "type": "string", "max_length": 255 },
    "status":     { "name": "status",     "type": "foreignkey", "choices": [ /* ... */ ] },
    "lead_value": { "name": "lead_value", "type": "decimal" },
    "custom_fields.budget": {
      "name": "custom_fields.budget",
      "label": "Budget",
      "type": "decimal",
      "is_custom": true,
      "is_required": false,
      "filterable": true,
      "sortable": true
    }
  },
  "custom_field_definitions": [
    { "custom_field_id": "...", "field_name": "budget", "label": "Budget", "field_type": "decimal", "is_required": false, "order": 5, "group": "lead" }
  ],
  "all_fields": {
    "columns": [
      { "name": "lead_name",  "label": "Lead",     "order": 1, "visible": true, "width": 200, "is_fixed": true,  "field_info": { "...": "..." } },
      { "name": "status",     "label": "Status",   "order": 2, "visible": true, "width": 150, "is_fixed": true },
      { "name": "lead_value", "label": "Value",    "order": 3, "visible": true, "width": 120, "is_fixed": false },
      { "name": "assignees",  "label": "Assigned", "order": 4, "visible": true, "width": 160, "is_fixed": true },
      { "name": "activity",   "label": "Activity", "order": 5, "visible": true, "width": 140, "is_fixed": true }
    ],
    "sorting": {},
    "filters": {}
  }
}
```

Notes:
- `has_org_config` / `has_user_settings` tell the client whether column
  order/visibility comes from an org-wide config (wins if present) or a
  per-user fallback.
- `custom_field_definitions` lists the org's active Lead custom fields
  (shared schema with Customer); each is also folded into `fields` as
  `custom_fields.<field_name>`.
- System-managed fields are **never** returned: `id`, `lead_id`,
  `organization`, `owner`, `created_by`, `modified_by`, `created_at`,
  `updated_at`, `lead_score`, `lead_score_breakdown`,
  `lead_score_updated_at`, `custom_fields` (raw blob — use the
  `custom_fields.*` entries instead), `is_duplicate`, `is_converted`,
  `converted_to_deal`, `converted_on`, `routing_status`, `deleted_at`,
  `is_archive`, `is_test`.

---

## 2. Lead list — `GET /leads/`

```
GET /api/v1/crm/leads/?page=1&page_size=20
```

Permission: `view_lead`. Record-level visibility resolved via the standard
`all > hierarchy > team > owned > assignee > filtered` precedence.

Standard page-number pagination (`page_size` default 100, max 200):

```json
{
  "count": 8,
  "next": "http://.../leads/?page=2",
  "previous": null,
  "results": [ /* Lead objects, list-view field set per schema */ ]
}
```

Each result is trimmed to the org's configured **list** columns (from §1),
plus a fixed set that is always included regardless of config:
`lead_id`, `lead_name`, `assignees`, `status`.

### Lead object shape (list view)

```jsonc
{
  "lead_id": "uuid",
  "lead_name": "Aboobacker Haji",
  "organization_name": "Lulu Fashion Store",
  "status": "Negotiation",        // status name, not the FK id
  "status_id": "uuid",
  "lead_value": 3650000,          // computed — see "lead_value precedence" below
  "lead_source": { "...": "..." },
  "assignees": [
    { "user_id": "uuid", "first_name": "Ravi", "last_name": "K", "full_name": "Ravi K", "email": "...", "is_active": true }
  ],
  "lead_owner": { "user_id": "uuid", "full_name": "..." },
  "activity": "2026-08-04T05:12:00Z",       // = updated_at, drives "5h ago"/"Yesterday"
  "last_followup_at": "2026-08-03T10:00:00Z",
  "last_followup_type": "call",
  "custom_fields": { "budget": 5000000 },
  "is_converted": false,
  "created_at": "2026-07-20T09:00:00Z"
}
```

- **`lead_value`** (→ the "₹36.5L" figure on the card): computed per §5.4 —
  accepted-quote total, else highest-quote total, else product sum/max
  (org-configurable via `LeadRules.lead_value_calc`).
- **`status`** is a display **name** (e.g. `"Won"`, `"Negotiation"`) —
  use it directly for the status pill label/color mapping from the schema's
  `choices`.
- **`assignees`** drives the avatar stack + "Team"/"+1 more" summary; render
  the first N avatars and count the remainder client-side.
- `meta_qa` (Meta Lead Ads Q&A) is **detail-only** — never present on list
  rows, to avoid N+1 queries.

### Filtering (`LeadFilter`)

Common params (see `docs/working/lead-filters.md` for the exhaustive list):

| Param | Example | Notes |
|---|---|---|
| `status` / `status__in` | `?status__in=id1,id2` | |
| `status_name` / `status_name__icontains` | | |
| `lead_source` / `lead_source__in` | | |
| `assignees` / `assignees__in` | | |
| `assigned_team` / `assigned_team__in` | | |
| `owner_mode` | `me` \| `unassigned` | Powers the "My leads" toggle. |
| `is_teams` | `true` | Leads where I'm owner OR assignee. |
| `my_team` | `true` | Leads assigned to any team I belong to. |
| `is_archive` | `true`/`false` | Default excludes archived leads. |
| `search` | `?search=aboobacker` | icontains across name/company/email/phone. |
| `lead_value_min` / `lead_value_max` | | Filters on the computed lead value. |
| `stale_days` | `?stale_days=14` | Leads whose current stage is ≥N days old. |
| `custom_fields.<name>` | `?custom_fields.budget=5000000` | Any custom field, by slug. |
| `ordering` | `?ordering=-lead_value` | Supports `custom_fields.<name>` too. |
| `saved_filter_id` | `?saved_filter_id=uuid` | Applies a saved filter (module `lead`) on top of the above. |

Negation variants exist for FK filters: `status__not`, `lead_source__not`,
`assignees__not`, `assigned_team__not`, `product__not`, `industry__not`
(comma-separated UUIDs, excluded).

### `QUERY /leads/` — same filters, JSON body

For filter payloads too large/complex for a query string, the collection URL
also accepts the IETF **`QUERY`** verb (safe, idempotent, GET-with-body).
Behaves identically to `GET /leads/` — same pagination, same response shape —
but params are supplied as a flat JSON object body instead of (or layered
under) the query string:

```
QUERY /api/v1/crm/leads/
Content-Type: application/json

{ "status__in": "id1,id2", "search": "aboobacker", "ordering": "-lead_value" }
```

Body keys win over URL query params on collision.

---

## 3. Lead detail — `GET /leads/{lead_id}/`

Permission: `view_lead`. Returns the **detail**-view field set from §1
(typically the full field list), plus `meta_qa` (Meta Lead Ads form Q&A, if
the lead originated from a Meta ad) and full `notes`.

---

## 4. Kanban board — `GET /leads/board/`

```
GET /api/v1/crm/leads/board/?lane_page_size=20
```

Permission: `view_lead`. Cached 5 min per user+org. Not the screen shown in
the screenshot (that's the flat filtered list), but shares the same card shape
and is the backing endpoint for a status-lane / Kanban view of the same data.

Accepts every `LeadFilter` param from §2 (plus `custom_fields.*`). Defaults to
excluding archived and converted leads unless `is_archive`/`is_converted` are
explicitly passed.

```jsonc
{
  "board_total": 8,
  "lane_page_size": 20,
  "lanes": [
    {
      "status_id": "uuid",
      "status_name": "Negotiation",
      "status_type": "in_progress",
      "color": "#f5a623",
      "position": 2,
      "count": 3,
      "cards": [ /* list-trimmed Lead objects, same shape as §2 */ ],
      "next_page": 2,
      "next_url": "/api/v1/crm/leads/?status=<status_id>&page=2&page_size=20"
    }
  ]
}
```

`next_url` paginates a single lane further via the regular list endpoint
(§2) — "load more" within a lane, not a board-specific endpoint.

---

## 5. Create lead — `POST /leads/`

Permission: `create_lead`. Body: writable fields from the `detail` schema
(§1). Server stamps `organization`, `owner`, `created_by`, `modified_by`, and
`lead_owner` (defaults to the creator unless explicitly supplied).

**Duplicate detection** runs on create if the org has lead duplicate-checking
enabled (`LeadRules.duplicate_check_scope != "customers_only"`), matching on
the org's configured keys (e.g. email/phone):

| Org mode | Behavior |
|---|---|
| `block` | `400` with `{"duplicate": {...match details...}}`; lead **not** created. |
| `warn` | `201`; lead created with `is_duplicate=true`, response includes `"warnings": [{...}]`. |
| `merge` | `200` (not 201); no new row — empty fields on the oldest matching lead are filled in and that existing lead is returned. |

---

## 6. Update lead — `PUT`/`PATCH /leads/{lead_id}/`

Permission: `update_lead`, and only the lead owner, an assignee, or an org
admin may call it. **Converted leads are frozen** (`403`) — edit the resulting
Customer instead. Moving `status` to a Won-type status requires an accepted
quotation when the org is in quote-gated conversion mode (§7.1.1).

## 7. Delete lead — `DELETE /leads/{lead_id}/`

Permission: `delete_lead`, lead owner only. Converted leads cannot be deleted
(`403`).

---

## 8. Convert lead — `POST /leads/{lead_id}/convert/`

Permission: `convert_lead`. If the caller lacks approval rights
(`approve_lead` + hierarchy rules), returns `202` with a pending
`LeadConversionApproval` instead of converting immediately:

```json
{ "message": "Lead conversion approval requested.", "lead_id": "uuid", "approval_id": "uuid", "status": "pending" }
```

Otherwise converts immediately and returns `201` with the new `Customer`.

- `POST /leads/{lead_id}/approve-conversion/` — approve a pending request (permission `approve_lead`); `201` + Customer.
- `POST /leads/{lead_id}/reject-conversion/` — reject a pending request (permission `approve_lead`); `200`.

---

## 9. Bulk actions

All permission `update_lead` (delete variant needs `delete_lead`). Body always
includes `lead_ids: [uuid, ...]`. Response shape is uniform:
`{ "success": true, "updated": N, "errors": [] }`.

| Endpoint | Method | Extra body | Notes |
|---|---|---|---|
| `/leads/bulk-archive/` | `POST` | `is_archive: bool` | |
| `/leads/bulk-delete/` | `DELETE` | — | Rejects (`400`) if any target lead is converted. |
| `/leads/bulk-status/` | `POST` | `status_id: uuid` | Skips converted leads; quote-gate applies per lead for Won-type statuses; auto-archives leads moved to a Lost-type status. |
| `/leads/bulk-assign/` | `POST` | `assignee_id: uuid` | Adds (does not replace) the assignee; skips converted leads. |

---

## 10. Supporting endpoints

- `GET /leads/{lead_id}/assignable-users/?search=` — active org users eligible
  for assignment to this lead (paginated). Requires read access to the lead.
- `GET /leads/recalculate-scores/` → **`POST /leads/recalculate-scores/`** —
  on-demand lead-score recalculation for the org.
- `GET /leads/phone-country-codes/` (also `GET /phone-country-codes/`) —
  static list of `{name, iso2, dial_code, flag}` for the phone country-code
  picker on the create/edit form.

## 11. Lead configuration (settings)

Used by CRM Settings, not the mobile Leads screen directly, but referenced by
the schema's `choices`/filters:

- `lead-statuses/` — CRUD + `POST lead-statuses/reorder/` (banded by the fixed
  `LeadStatusType` order — new < in_progress < won < lost < junk) +
  `GET lead-statuses/status-types/`.
- `lead-lost-reasons/` — CRUD.
- `lead-sources/` — CRUD + `POST lead-sources/bulk-toggle/`.
- `territories/` — CRUD, hierarchical (`parent_territory`).
