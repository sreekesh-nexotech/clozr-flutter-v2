# Org View Settings (Field Config) API

Org-wide, admin-managed control over **which columns appear** in a module's list
and detail views, their **order**, **width**, and **label** — plus the read-only
`is_protected` (fixed / non-hideable) flag.

This is the single source of truth for column visibility. It drives:

- `GET /api/v1/crm/leads/schema/` (and the equivalent `.../<module>/schema/`) — the
  column catalog the frontend renders the table/detail panel from.
- The **data endpoints** themselves: `GET /api/v1/crm/leads/` (list → `view_type=list`)
  and `GET /api/v1/crm/leads/{id}/` (detail → `view_type=detail`) trim their response
  payload to the visible fields for that view_type. Hiding a column hides its data too.

> Per-user view settings are **not** applied to these responses — org config is
> authoritative. Fixed columns (`is_protected`) are always visible regardless.

Backing model: `OrgModelFieldConfig` (one row per org × model × view_type × field).

---

## Concepts

| Term | Meaning |
| :--- | :--- |
| `model_name` | The module: `lead`, `customer`, `product`, `quotation`, `task`, `followup`, `payment`, `project`. (Lead & Customer share the `lead` custom-field schema, but each has its own field config. `project` supports `list`/`detail` only — see the coverage matrix.) |
| `view_type` | `list` (table columns), `detail` (detail-panel fields), `kanban` (board card — lead/customer/task/followup), `mobile` (mobile list-row card — all modules), or `both` (rows that apply to list **and** detail). A `GET`/`PUT` for `list` also returns/affects `both` rows; `kanban`/`mobile` are standalone (no `both` merge). |
| `field_name` | Built-in field key (e.g. `lead_name`, `status`, `lead_source`). Custom fields are managed separately via the custom-fields API and appear as `custom_fields.<name>`. |
| `is_visible` | Whether the column shows in that view. |
| `order` | Sort position (ascending). Must be unique within a `PUT`. |
| `width` | Column width in px (default 150). |
| `label_override` | Custom header label; `null` falls back to the canonical built-in label. |
| `is_protected` | **Read-only.** Fixed column — cannot be hidden. Attempting to set `is_visible:false` on it is a 400. See fixed-column list below. |

**Fixed columns** (cannot be hidden):
- **Lead list:** `lead_name`, `status`, `stage_entered_at`, `products`, `assignees`, `last_followup_at`, `activity`
- **Task / Follow-up list:** `title`, `status`, `related_to`, `priority`, `assigned_to`, `due_date`
- **Detail (all modules):** each module's primary name field (`lead_name`, `name`,
  `product_name`, `title`, `quotation_number`)
- **Kanban / Mobile cards:** only each module's primary name field is fixed
  (`lead_name` / `name` / `title` / `product_name` / `quotation_number` / `payment_date`);
  every other card field is freely toggleable.

Auth for all endpoints: authenticated user. **Writes require org admin.** Rate limit: 60/min/user.

---

## 1. Read the current config

```
GET /api/v1/management/org-field-config/?model_name=lead&view_type=list
```

Auto-seeds org defaults on first access (so a fresh org gets a sensible column set).

**Query params** (both required): `model_name`, `view_type` (`list` | `detail` | `both`).

**200 Response**

```json
{
  "model_name": "lead",
  "view_type": "list",
  "fields": [
    {
      "org_field_config_id": "…uuid…",
      "field_name": "lead_name",
      "label": "Lead Name",
      "label_override": null,
      "is_visible": true,
      "order": 1,
      "width": 200,
      "is_protected": true
    },
    {
      "org_field_config_id": "…uuid…",
      "field_name": "lead_score",
      "label": "Lead Score",
      "label_override": null,
      "is_visible": true,
      "order": 6,
      "width": 100,
      "is_protected": false
    }
    // … all configured fields, ordered by `order`
  ]
}
```

---

## 2. Edit the config — toggle visibility & reorder

```
PUT /api/v1/management/org-field-config/
```

**Admin only.** This is a **full replace / bulk upsert** for the given
`(model_name, view_type)`: send every field you want configured, each with its
visibility and order. Each item is upserted (`update_or_create`) keyed by
`(org, model_name, view_type, field_name)`.

> Recommended flow: `GET` the current config, mutate the array client-side
> (flip `is_visible`, renumber `order`), then `PUT` the whole array back.

**Request body**

```json
{
  "model_name": "lead",
  "view_type": "list",
  "fields": [
    { "field_name": "lead_name",        "is_visible": true,  "order": 1, "width": 200, "label_override": null },
    { "field_name": "status",           "is_visible": true,  "order": 2, "width": 120, "label_override": null },
    { "field_name": "lead_source",      "is_visible": true,  "order": 3, "width": 130, "label_override": "Source" },
    { "field_name": "lead_value",       "is_visible": true,  "order": 4, "width": 140, "label_override": null },
    { "field_name": "assignees",        "is_visible": true,  "order": 5, "width": 150, "label_override": null },
    { "field_name": "lead_score",       "is_visible": false, "order": 6, "width": 100, "label_override": null },
    { "field_name": "last_followup_at", "is_visible": true,  "order": 7, "width": 150, "label_override": null },
    { "field_name": "activity",         "is_visible": true,  "order": 8, "width": 150, "label_override": null },
    { "field_name": "email",            "is_visible": true,  "order": 9, "width": 180, "label_override": null }
  ]
}
```

The example above hides `lead_score` and makes `email` visible, and reorders columns
by their `order` values.

**Per-field item schema** (`OrgFieldConfigWriteItemSerializer`):

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `field_name` | string | ✅ | Must be a known built-in field for the model (see catalog via the module's `/schema/`). |
| `is_visible` | bool | ✅ | — |
| `order` | int ≥ 0 | ✅ | Must be **unique** across the request. |
| `width` | int ≥ 0 | ❌ (default 150) | px. |
| `label_override` | string \| null | ❌ (default null) | null → canonical label. |

**200 Response**: identical shape to the `GET` — the freshly persisted config,
ordered by `order`. Writing invalidates the affected module's cached list / detail /
board responses (the record-model cache version, e.g. `org:{org_id}:lead`; a
`followup` config bumps the shared `task` cache) so those endpoints reflect the
change immediately — no 300s TTL wait. `/schema/` is not cached and is always live.

### Validation errors (400)

| Condition | Message |
| :--- | :--- |
| Missing/blank `model_name` or `view_type` | `"This field is required."` |
| `view_type` not in list/detail/both/kanban/mobile | `"Must be one of list, detail, both, kanban, mobile."` |
| `fields` not a list | `"Must be a list."` |
| Unknown `field_name` for the model | `"Unknown field names for model 'lead': [...]"` |
| Duplicate `order` values | `"order values must be unique within the request."` |
| Hiding a fixed column | `"'status' is a protected field and cannot be hidden on list view."` |

**403** — non-admin caller: `"Only org admins can update field configuration."`

---

## Notes & gotchas

- **Ordering** is purely the `order` integers; gaps are fine, but values must be
  unique per request. The frontend should renumber sequentially before `PUT`.
- **`view_type` scoping.** A `PUT` with `view_type:list` only touches list rows; the
  same field can have different visibility/order in `detail`. Use `both` only for
  rows meant to apply everywhere.
- **Custom fields** aren't edited here. Create/reorder them via
  `POST /api/v1/management/custom-fields/` and `.../custom-fields/reorder/`; their
  list/detail visibility is controlled by `show_in_list` / `show_in_detail` on the
  definition and they surface as `custom_fields.<name>` columns.
- **Data-endpoint effect.** After a `PUT`, `GET /api/v1/crm/leads/` returns only the
  now-visible fields (plus always-present identity/mandatory fields:
  `lead_id`, `lead_name`, `assignees`, `status`). Nested-relation columns
  (`lead_source`, `lead_owner`, …) are included only when visible.
- There is **no `DELETE`**. Removing a column = set `is_visible:false`. Rows are
  seeded once and thereafter upserted.

---

## Coverage matrix — what's backed today

The View Settings screen shows **7 module tabs** × view-type sub-tabs
(List · Kanban · Detail · Mobile). Backend coverage:

| Module (`model_name`) | List | Detail | Kanban card | Mobile card |
| :--- | :---: | :---: | :---: | :---: |
| Leads (`lead`) | ✅ | ✅ | ✅ | ✅ |
| Customers (`customer`) | ✅ | ✅ | ✅ | ✅ |
| Tasks (`task`) | ✅ | ✅ | ✅ | ✅ |
| Follow-ups (`followup`) | ✅ | ✅ | ✅ | ✅ |
| Quotes (`quotation`) | ✅ | ✅ | — ¹ | ✅ |
| Payments (`payment`) | ✅ | ✅ | — ¹ | ✅ |
| Products (`product`) | ✅ | ✅ | — ¹ | ✅ |
| Projects (`project`) | ✅ ² | ✅ ² | — ¹ | — |

¹ Quotes/Payments/Products have **no Kanban board endpoint**, so `kanban` isn't
seeded for them (a card with nowhere to render). Their mobile card is served as a
trimmed list via `?view_type=mobile`. The **"Lead detail page (SOON)"** sub-tab maps
to the already-backed `detail` view_type — only the UI is pending.

² **Projects behave like the CRM modules for `list`/`detail`.** The `project`
module's `/schema/` (`GET /api/v1/projects/projects/schema/`), org-field-config,
and user-view-settings all work for `list` and `detail`, and the project **data**
endpoints (`GET /api/v1/projects/projects/` and `.../{id}/`) **are trimmed** to
the org's configured-visible columns (plus mandatory companions: identity +
`*_name`/`is_overdue`, and `task_count`/`done_count` on detail). The
`?view=list` slim projection is a separate fixed shape and is not further
trimmed. Projects have **no custom fields** (`custom_field_definitions` is
always `[]`) and no kanban/mobile card seeds. See
`docs/working/operations.md §5A / §11`.

### Kanban / Mobile cards — how they work

- **Seeded defaults.** Each org gets sensible card defaults on first access (lazy
  seed, same as list/detail). Kanban mirrors the frontend "always shown" core (e.g.
  leads: organization, lead_name, score, lead_value, source, owner); mobile is a
  compact list subset. Admins edit them with the same `PUT` as list/detail —
  `{"model_name":"lead","view_type":"kanban","fields":[…]}`.
- **The board respects the kanban config.** `GET /leads/board/` (and
  `/customers/board/`, `/tasks/board/`) trims each card to the org's **kanban**
  field set — the DRF `board` action resolves to `view_type=kanban`. Editing the
  kanban card via `PUT` reflects on the board **immediately** (the write invalidates
  the board's record-model cache; no 300s wait).
- **Fallback.** If an org has no kanban rows yet (e.g. seeded before this feature),
  the board falls back to the **list** config — cards keep rendering as before until
  an admin customizes the kanban card. Mobile falls back to list the same way.
- **Fixed field.** Only the module's primary name field is protected on a card;
  everything else is freely toggleable.
- **Custom fields** appear on cards too: a custom field with `show_in_list=true`
  surfaces on the kanban/mobile card (they reuse the list visibility flag).
- **Backfill** existing orgs with `manage.py backfill_kanban_mobile_config --all`
  (idempotent — never overwrites a customized card).

---

# Custom Fields API

Org-level **custom field definitions** for a module (Lead, Customer, Task). These are
managed separately from the org field config above: this API defines *what* custom
fields exist; their **list/detail visibility** is controlled by `show_in_list` /
`show_in_detail` on the definition (not by the org-field-config `PUT`). They surface
in the module schema and data payloads as `custom_fields.<field_name>` columns.

Backing model: `CustomFieldDefinition`. Base path: `/api/v1/management/custom-fields/`.

Auth: authenticated for reads; **org admin** for create/update/delete. Rate limit
60/min/user. Reads are cached 300s per org.

> **Model scope:** Lead and Customer **share** the `lead` custom-field schema — a
> field created with `model_name:"lead"` appears on both Leads and Customers. Tasks
> (`model_name:"task"`) have their own schema.

---

## 1. List custom fields

```
GET /api/v1/management/custom-fields/?model_name=lead
```

**Query params:** `model_name` (filter), `is_active` (`true`/`false`; defaults to
active-only). Supports `?search=` (label/field_name) and `?ordering=` (order/created_at/label).

Returns the definitions ordered by `order`.

---

## 2. Create a custom field

```
POST /api/v1/management/custom-fields/
```

**Admin only.**

**Request body**

```json
{
  "model_name": "lead",
  "label": "Budget",
  "field_type": "number",
  "is_required": false,
  "default_value": null,
  "choices": null,
  "show_in_list": true,
  "show_in_detail": true,
  "group": null,
  "filterable": true,
  "sortable": true
}
```

| Field | Notes |
| :--- | :--- |
| `model_name` | `lead` (shared with customer) or `task`. |
| `label` | Required, non-empty. |
| `field_name` | **Read-only** — auto-generated (slugified) from `label`, de-duplicated and collision-checked against existing + built-in field names. Not sent by the client. |
| `field_type` | e.g. `text`, `number`, `decimal`, `date`, `dropdown`, `multi_select`, `boolean`. **Immutable** once set (changing it would orphan stored data). |
| `choices` | **Required** for `dropdown` / `multi_select`; cleared to `null` otherwise. |
| `is_required` | Enforce on record create/update. |
| `default_value` | Optional default. |
| `show_in_list` / `show_in_detail` | Column visibility in list / detail views. |
| `group` | Optional grouping label for the form UI. |
| `filterable` | Allow `?custom_fields.<name>=…` filtering on the data endpoint. |
| `sortable` | Only `date` / `number` / `decimal` may be sortable. Auto-assigns a **slot** column (server-assigned, read-only); max **2 sortable Date + 2 sortable Number** per model. |
| `order` | Optional; auto-set to `max+1` when omitted/0. |

**Limit:** max **10 active** custom fields per (org, model). Exceeding → 400.

**201 Response**: the created definition (includes the generated `field_name`, assigned
`slot`, `order`, timestamps).

---

## 3. Update a custom field

```
PATCH /api/v1/management/custom-fields/{custom_field_id}/
```

**Admin only.** Editable: `label`, `is_required`, `default_value`, `choices`,
`show_in_list`, `show_in_detail`, `group`, `filterable`, `sortable`, `order`.
`field_type` and `field_name` cannot change (400 on attempt).

---

## 4. Reorder custom fields

```
POST /api/v1/management/custom-fields/reorder/
```

**Admin only.** Bulk-set the `order` of a module's fields.

```json
{
  "model_name": "lead",
  "order": [
    { "custom_field_id": "…uuid…", "order": 1 },
    { "custom_field_id": "…uuid…", "order": 2 }
  ]
}
```

All `custom_field_id`s must belong to the org + `model_name` (unknown IDs → 400).
**200 Response**: the reordered active definitions.

---

## 5. Deactivate (soft-delete)

```
DELETE /api/v1/management/custom-fields/{custom_field_id}/
```

**Admin only.** Reversible: sets `is_active=false` and frees the sortable slot.
**Blocked (400)** when:
- any record holds data for the field, **or**
- a saved filter / view-config references it (the dependents are returned so the admin
  can resolve them first).

**204** on success.

---

## 6. Purge (hard-delete / slot reclaim)

```
POST /api/v1/management/custom-fields/{custom_field_id}/purge/
```

**Admin only.** Irreversible: clears the field's stored values from every record (JSON
key + slot column), then deletes the definition so the slot is permanently freed. Still
**blocked (400)** if saved filters / view-configs reference the field — remove those first.

**204** on success.

---

## How custom fields relate to view settings

- A custom field with `show_in_list:true` appears in `GET /api/v1/crm/leads/schema/`
  under `custom_field_definitions` and as a `custom_fields.<name>` entry in the column
  set, with **`visible: true`** on the list view; with `show_in_detail:true` it appears
  as `visible: true` on the detail schema. Setting the flag to `false` removes the column
  from that view entirely. (Custom-field visibility is driven solely by these two flags —
  it is **not** configured through the org-field-config `PUT`.)
- In the data payload (`GET /api/v1/crm/leads/`), all custom-field values live inside the
  single `custom_fields` object on each record (keyed by `field_name`, e.g.
  `{"budget": 1800000}`). This object is **always** returned regardless of built-in
  column trimming (re-injected by the serializer), so custom values are never dropped.
- **Every custom field visible in the current view is always keyed** — a field with no
  stored value is returned as `null` (not omitted), so the client renders an empty cell
  rather than a missing column. The set is **scoped by view**: the **list** payload
  includes only `show_in_list=true` fields, **detail** only `show_in_detail=true`.
  (On write/form serialization all active fields are included.) Sortable and JSON-backed
  fields are merged transparently — the client never sees slot columns.
- Filter/sort on the data endpoint: `?custom_fields.<name>=<value>` (needs `filterable`)
  and `?ordering=custom_fields.<name>` (needs `sortable` + an assigned slot).
