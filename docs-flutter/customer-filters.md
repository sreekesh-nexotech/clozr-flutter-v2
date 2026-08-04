# Customer Filters API (frontend guide)

Backing for the **"Filter Customers"** side-sheet: the multi-section panel with
Customer status, Account manager, Company, Source, Product/Service, Lifetime
value and Customer since — each with an **is / is not** toggle where applicable.

Two kinds of calls:

1. **Populate the panel** — small GET endpoints that return the option lists the
   user picks from (statuses, users, sources, products).
2. **Apply the filters** — the `/api/v1/crm/customers/` list endpoint. You can
   send filters two ways:
   - **`GET`** with query-string params (the classic way — works everywhere), or
   - **`QUERY`** with a JSON body (new; same filters, cleaner for big/complex
     filter sets — see [Part 3](#part-3--query-method-json-body)).

   Both hit the **same** endpoint and return the **same** result. There is no
   separate "filter" endpoint — `CustomerFilter` (`crm/filters/customer.py`) is
   the single source of truth for both.

Auth for everything here: authenticated user. Reads are RBAC- and tenant-scoped
(a user only sees customers their role/hierarchy/team grants). Base prefix:
`/api/v1/crm/` unless noted (`/api/v1/management/` for users).

---

## Part 1 — Populate the panel (option-list GETs)

All paginated (`StandardResultsSetPagination`, page size 100, `?page=`/
`?page_size=`); most accept `?search=`. Cache per org — they change rarely.

| Panel section | Endpoint | Use as filter value |
| :--- | :--- | :--- |
| **Customer status** | `GET /api/v1/crm/customer-statuses/` | `customer_status_id`. Full shape + the status-**type** endpoint and the chip counts are in [Part 1b](#part-1b--customer-statuses--status-types). Filter to active with `?is_active=true`. |
| **Account manager** | `GET /api/v1/management/users/` | `user_id` (the customer's `assigned_to`). Supports `?search=`. |
| **Source** | `GET /api/v1/crm/lead-sources/` | `lead_source_id`. The customer inherits its source from the lead it converted from (`source_lead.lead_source`). |
| **Product / Service** | `GET /api/v1/crm/products/` | `product_id`. Each → `{product_id, product_name, price, …}`. |

**Company**, **Lifetime value** and **Customer since** need no option endpoint —
Company is a free-text match on the customer name; the others are numeric / date
inputs.

---

## Part 1b — Customer statuses & status types

The Customers screen has two status concepts, **exactly parallel to Leads** (§6 /
§7.5 of the rulebook):

- **Customer Status** — the tenant's own, editable statuses (the chips you filter
  by and show on each row: *Active, Upsell In Progress, Completed, Lost, …*). A
  tenant can create/rename/recolor/reorder these.
- **Customer Status Type** — a **backend-fixed, global** classification each
  custom status maps to (N:1). The four types are **`active`, `completed`,
  `lost`, `upsell_in_progress`** (§7.5.2). Tenants **cannot** create/edit/delete
  types. Use the type (not the label) when you need outcome logic, because a
  tenant may rename "Completed" to "Won Deal" but it still maps to type
  `completed`.

This is independent of Lead status — a converted customer's status changes on its
own (a customer can go to `lost` while its originating lead stays Won).

### Customer statuses (CRUD)

```
GET /api/v1/crm/customer-statuses/          # list (paginated, ordered by position)
POST /api/v1/crm/customer-statuses/         # create
PATCH /api/v1/crm/customer-statuses/{customer_status_id}/
DELETE /api/v1/crm/customer-statuses/{customer_status_id}/
```

Each item:

```json
{
  "customer_status_id": "…uuid…",
  "name": "Upsell In Progress",
  "color": "#F5A623",
  "position": 3,
  "is_active": true,
  "is_default": false,
  "is_readonly": false,
  "status_type": "upsell_in_progress",
  "status_type_name": "Upsell In Progress",
  "is_completed": false,
  "is_lost": false,
  "is_upsell_in_progress": true
}
```

- **Filter values:** use `customer_status_id`. Show only `?is_active=true` in the
  panel.
- On **create/update**, `status_type` is required and must be one of the four
  fixed codes (send the code string, e.g. `"lost"`).
- `is_readonly`, `organization`, and the audit fields are server-managed.

### Customer status **types** (read-only, global)

```
GET /api/v1/crm/customer-statuses/status-types/
```

```json
[
  { "code": "active",             "name": "Active",             "position": 0 },
  { "code": "completed",          "name": "Completed",          "position": 1 },
  { "code": "lost",               "name": "Lost",               "position": 2 },
  { "code": "upsell_in_progress", "name": "Upsell In Progress", "position": 3 }
]
```

Use this to populate the `status_type` dropdown when creating/editing a custom
status, or to group statuses by type.

### Reorder statuses

```
POST /api/v1/crm/customer-statuses/reorder/
[ { "customer_status_id": "…", "position": 0 }, { "customer_status_id": "…", "position": 1 } ]
```

### The status **chips** (All / Active / Upsell In Progress / … with counts)

The top-of-list chips are just the customer statuses plus per-status counts.
Populate the chip labels/colors from `GET /customer-statuses/?is_active=true`
(ordered by `position`). Each chip's **count** is the customer list filtered to
that status — e.g. the "Active (23)" chip is
`GET /api/v1/crm/customers/?status__in=<active_id>` read from the response
`count`. The **"All"** chip is the unfiltered list `count`. Clicking a chip is the
same as applying that `status__in` filter (see Part 2).

> The chips group by the tenant's **custom status**, not by type (matching the
> Kanban grouping rule). If you need type-level rollups (e.g. all `lost`-type
> statuses together), map each custom status to its `status_type` via the list
> payload above.

---

## Part 2 — Apply the filters (GET)

```
GET /api/v1/crm/customers/?<params>
```

Standard paginated list response. Rows are trimmed to the org's `list`-view field
config plus the always-present `customer_id` and `name`. **All params combine with
AND.** Multi-value params accept a **comma-separated** list (`?status__in=a,b`)
and/or the **repeated-param** form (`?status__in=a&status__in=b`) — both work and
may be mixed.

Every panel section maps to a param below. The **is / is not** toggle picks
between the `__in` (include) and `__not` (exclude) variant.

### Customer status

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `status__in` | `?status__in=<customer_status_id>,<…>` |
| is not | `status__not` | `?status__not=<customer_status_id>` |

Single-value `status=<customer_status_id>` also accepted. Name matching:
`status__name` / `status__name__icontains`.

### Account manager

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `assigned_to__in` | `?assigned_to__in=<user_id>,<…>` |
| is not | `assigned_to__not` | `?assigned_to__not=<user_id>` |

Single-value `assigned_to=<user_id>` accepted. If the UI ever filters by the
multi-assignee set instead of the single manager, `assignees__in` /
`assignees__not` are also available. Convenience: `my_team=true` → customers on
any team the caller belongs to.

### Company

Customer has a dedicated **`organization_name`** field (the "Organization" row on
the detail page, e.g. *Kalyan Silks*) — copied from the source lead on conversion,
editable thereafter. Filter on it:

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `organization_name__in` | `?organization_name__in=Kalyan Silks,Aster` |
| is not | `organization_name__not` (via `organization_name`) | see note |

`organization_name__in` matches the **exact** company name; for partial matching
use `organization_name__icontains=<text>`. (If the panel's "Company" list is
instead the customer *name*, `name__in` / `name__icontains` / `name__not` work the
same way.)

> The dedicated `organization_name__not` exclude filter is not generated by the
> dynamic builder; exclude by company via `name__not` on the customer name, or ask
> backend to add `organization_name__not` if the panel needs it on this field.

### Industry

Customer has an **`industry`** FK (parallel to Lead), copied from the source lead
on conversion. Populate options from `GET /api/v1/crm/industries/`
(`{industry_id, name}`); filter with the `industry_id`.

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `industry__in` | `?industry__in=<industry_id>,<…>` |

Single-value `industry=<industry_id>` accepted; name matching via
`industry__name` / `industry__name__icontains`.

### Source

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `source_lead__lead_source__in` | `?source_lead__lead_source__in=<lead_source_id>,<…>` |
| is not | `source_lead__lead_source__not` | `?source_lead__lead_source__not=<lead_source_id>` |

Resolves through the originating lead's source. Customers created without a
source lead won't match any source filter.

### Product / Service

| Toggle | Param | Example |
| :--- | :--- | :--- |
| is | `products__in` | `?products__in=<product_id>,<…>` |
| is not | `products__not` | `?products__not=<product_id>` |

Maps to the customer's M2M `products`. Single-value `products=<product_id>`
accepted.

### Lifetime value (₹ lakhs)

Maps to the customer's `revenue` field. **Params are raw rupees** — the panel
shows lakhs, so multiply the input by 100,000 before sending.

| Field | Param |
| :--- | :--- |
| Min | `revenue__min=<rupees>` |
| Max | `revenue__max=<rupees>` |

Example — Min 1 lakh, Max 9 lakhs → `?revenue__min=100000&revenue__max=900000`.

### Customer since

Date-only range (inclusive). The chips (Today / Last 7 / 30 / 60 / 90 days /
This month) are computed client-side into a concrete `after`/`before` pair; the
From/To pickers set them directly.

| Field | Param |
| :--- | :--- |
| From | `created_at__after=YYYY-MM-DD` |
| To | `created_at__before=YYYY-MM-DD` |

> ⚠️ **Note the double underscore:** customer date params are `created_at__after`
> / `created_at__before` (Lead's are single-underscore `created_at_after`). Use
> the double-underscore form here.

Example — "Last 30 days" → `?created_at__after=2026-06-03&created_at__before=2026-07-03`.

### Other useful list params (not in the panel)

- **Free-text search:** `?search=<text>` — matches name, email, phone, address,
  org name, status name, product name/code, and assigned/assigning users.
- **Archive scope:** `?is_archived=true` includes archived; **default excludes**
  archived. (Field is `is_archived` — note the trailing `d`, unlike Lead's
  `is_archive`.)
- **Custom fields:** `?custom_fields.<name>=<value>` (needs the field
  `filterable=true`). Customers share the Lead custom-field schema. Ordering:
  `?ordering=custom_fields.<name>`. Catalog: `GET /api/v1/crm/customers/schema/`.
- **Ordering / paging:** `?ordering=<field>` (default `-created_at`), `?page=`,
  `?page_size=`.

### Full GET example

Customers that are **status = Active**, **not** managed by user X, **Company name
in {Ali Villa, Pillai Villa}**, **Source = Website**, **have Product A**,
**lifetime value 1–9 lakhs**, created in the **last 30 days**:

```
GET /api/v1/crm/customers/
  ?status__in=<active_id>
  &assigned_to__not=<userX_id>
  &name__in=Ali Villa,Pillai Villa
  &source_lead__lead_source__in=<website_id>
  &products__in=<productA_id>
  &revenue__min=100000&revenue__max=900000
  &created_at__after=2026-06-03&created_at__before=2026-07-03
```

**Reset All** = drop every filter param and re-fetch the bare list.

---

## Part 3 — QUERY method (JSON body)

`QUERY` is a newer HTTP method for **search with a request body** — think "GET,
but the filters go in a JSON body instead of the URL". Use it when the filter set
is large or awkward to URL-encode (many multi-selects, long ID lists). It hits
the **same** URL as the GET list and returns the **identical** response.

```
QUERY /api/v1/crm/customers/
Content-Type: application/json

{
  "status__in": ["<active_id>"],
  "assigned_to__not": ["<userX_id>"],
  "name__in": ["Ali Villa", "Pillai Villa"],
  "source_lead__lead_source__in": ["<website_id>"],
  "products__in": ["<productA_id>"],
  "revenue__min": 100000,
  "revenue__max": 900000,
  "created_at__after": "2026-06-03",
  "created_at__before": "2026-07-03"
}
```

**Body rules:**
- Keys are the **same param names** as the GET query string (the whole table in
  Part 2 applies unchanged).
- Multi-value params may be a **JSON array** (`"status__in": ["a", "b"]`) **or**
  the comma-string (`"status__in": "a,b"`) — both work.
- Booleans may be native JSON (`"is_archived": true`) or strings (`"true"`).
- **Pagination stays in the URL:** send `?page=` / `?page_size=` on the QUERY
  request's URL; the body carries only filters. Body values win if a key appears
  in both.

```
QUERY /api/v1/crm/customers/?page=2&page_size=50
{ "status__in": ["<active_id>"] }
```

**How to send it in JS** (fetch supports arbitrary methods):

```js
const res = await fetch("/api/v1/crm/customers/?page=1", {
  method: "QUERY",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({ status__in: [activeId], revenue__min: 100000 }),
});
```

> **Compatibility:** QUERY is safe/idempotent (a read; it never mutates). GET
> still works fully, so prefer QUERY for rich filter payloads but keep GET as the
> fallback if a proxy/library in your stack rejects non-standard methods. The
> Kanban/board and any other list variants keep using GET query params.

---

## Part 4 — Saved Filters (customer module)

A panel selection can be persisted as a **saved filter** and re-applied later.
Customer saved filters work **exactly like lead saved filters** — same endpoint,
same rules — just with `module: "customer"`.

Base path: `/api/v1/crm/saved-filters/`. A user only sees/edits **their own**
filters (scoped to user + org).

**Rules:**
- Max **5 per user per module** (400 on exceed).
- `(user, org, module, name)` is **unique** — duplicate name → 400.
- `module` ∈ `lead` | **`customer`** | `task` | `followup`. For this panel use
  **`customer`**.
- `filter_definition` is exactly the **param dict** from Part 2 (keys = filter
  param names; values = the strings you'd put in the URL — comma lists are fine).
  Every key is validated against `CustomerFilter`; **unknown keys → 400**.
- `visibility` is read-only (`private` in phase 1). `is_valid`/`invalid_reason`
  are server-set; a filter referencing a purged custom field is stored
  `is_valid:false` (grey it) and **fails inert** — it never runs.

### Create

```
POST /api/v1/crm/saved-filters/
{
  "module": "customer",
  "name": "My Active Customers",
  "filter_definition": {
    "status__in": "<active_id>",
    "revenue__min": 100000
  }
}
```

**201** → the created object (`saved_filter_id`, `module`, `name`,
`filter_definition`, `is_valid`, `invalid_reason`, `order`, timestamps).

### List

```
GET /api/v1/crm/saved-filters/?module=customer
```

### Apply

Re-apply a saved filter on the customer list (works on **GET**; combine with
extra live params, which take precedence over the stored ones):

```
GET /api/v1/crm/customers/?saved_filter_id=<saved_filter_id>
```

---

## Quick reference — panel section → param

| Panel section | is (include) | is not (exclude) |
| :--- | :--- | :--- |
| Customer status | `status__in` | `status__not` |
| Account manager | `assigned_to__in` | `assigned_to__not` |
| Company | `organization_name__in` (or `name__in`) | `name__not` |
| Industry | `industry__in` | — |
| Source | `source_lead__lead_source__in` | `source_lead__lead_source__not` |
| Product / Service | `products__in` | `products__not` |
| Lifetime value | `revenue__min` / `revenue__max` | — |
| Customer since | `created_at__after` / `created_at__before` | — |

---

## Detail page — default field visibility

The customer **detail page** fields are governed by the org's field config
(`view_type=detail`), fetched from `GET /api/v1/crm/customers/schema/?view_type=detail`.
On a fresh org the backend **seeds** the defaults to match the detail mockup:

- **Visible by default:** `name`, `organization_name`, `email`, `phone`, `source`
  (lead source), `value_need` (product/need), `revenue` (deal value), `industry`,
  `status`, `score`, `assigned_to` (account manager), `assignees`,
  `assigned_team`, `last_followup_at`, plus the "View more" block (`products`,
  `address`, `purpose`).
- **Hidden by default:** everything else (`sla_value`, `sla_unit`, `source_lead`,
  `is_archived`, `created_at`, `activity`, `status_entered_at`, scoring internals,
  audit fields, custom-field slots). Admins can turn any of these on via
  **View Settings** (`PUT /api/v1/management/org-field-config/`), exactly like Lead.

`organization_name` and `industry` are copied from the originating lead at
conversion and are editable on the customer afterward.
