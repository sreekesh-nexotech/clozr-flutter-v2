# Customer — List View, Schema & Scoring — Frontend API Guide

This document covers what the frontend needs to render and manage the **Customer
list view**, bringing Customers to parity with Leads and Tasks: a schema-driven
column layout, an org-configurable (view-settings) list, synthetic display
columns, and a customer **Score**.

> **Scope:** this doc covers the **list** view (§1–§2), the **detail** view
> (§2b), and the **Kanban board** (§2c). Filtering/search and saved filters are in
> `docs/working/customer-filters.md`.

All routes are under `/api/v1/crm/` (customers/statuses) and
`/api/v1/management/` (field config / custom fields). Auth: authenticated user;
config/status writes require **org admin** (or the relevant customer permission).

---

## 1. Customer list schema — the column catalog

```
GET /api/v1/crm/customers/schema/?view_type=list
GET /api/v1/crm/customers/schema/?view_type=detail
GET /api/v1/crm/customers/schema/?view_type=form     # add/edit form fields
```

This is the **single source of truth** for which columns to render, in what
order, and which are fixed. It auto-seeds org defaults on first access, so a new
org immediately gets the correct layout. Shape is identical to the Lead/Task
schema.

**200 Response** (abbreviated):

```jsonc
{
  "model": "Customer",
  "view_type": "list",
  "has_org_config": true,
  "fields": { "...": "per-field metadata for the visible columns" },
  "custom_field_definitions": [ /* Lead/Customer share one custom-field schema */ ],
  "all_fields": {
    "columns": [
      { "name": "name",             "label": "Customer",       "order": 1, "visible": true,  "is_fixed": true },
      { "name": "status",           "label": "Status",         "order": 2, "visible": true,  "is_fixed": true },
      { "name": "source",           "label": "Source",         "order": 3, "visible": true,  "is_fixed": true },
      { "name": "value_need",       "label": "Value / Need",   "order": 4, "visible": true,  "is_fixed": true },
      { "name": "assignees",        "label": "Assignees",      "order": 5, "visible": true,  "is_fixed": true },
      { "name": "score",            "label": "Score",          "order": 6, "visible": true,  "is_fixed": false },
      { "name": "last_followup_at", "label": "Last Follow-up", "order": 7, "visible": true,  "is_fixed": true },
      { "name": "activity",         "label": "Activity",       "order": 8, "visible": true,  "is_fixed": true }
    ],
    "sorting": [],
    "filters": []
  }
}
```

### Default fixed column set (seeded for every new org)

Mirrors the customer list UI. **Every default column is fixed EXCEPT `score`** —
`score` is the only column an admin can hide or reorder.

| Order | Field              | Header        | Fixed | Notes |
| :---- | :----------------- | :------------ | :---- | :---- |
| 1     | `name`             | Customer      | ✅    | + `#code` subtitle (client-side from `customer_id`/code) |
| 2     | `status`           | Status        | ✅    | pill from `status_name`; "Since <date>" from `status_entered_at` |
| 3     | `source`           | Source        | ✅    | lead-source the customer converted from |
| 4     | `value_need`       | Value / Need  | ✅    | `{value, need}` — revenue + purpose |
| 5     | `assignees`        | Assignees     | ✅    | avatars |
| 6     | `score`            | Score         | —     | **only toggleable/movable default column** |
| 7     | `last_followup_at` | Last Follow-up| ✅    | timestamp + `last_followup_type` |
| 8     | `activity`         | Activity      | ✅    | last-modified timestamp |

**Rendering rules** (same as Lead/Task):
- Iterate `all_fields.columns` in `order`; render where `visible === true`.
- `is_fixed` columns cannot be hidden/removed — render their toggle as locked.
- Custom fields appear as `custom_fields.<name>` when flagged `show_in_list`.

---

## 2. Customer list response

```
GET /api/v1/crm/customers/           # paginated (page_size default 100)
GET /api/v1/crm/customers/?page=2&page_size=50
```

The response is **trimmed to the org's visible list columns** (driven by the same
view-settings config as the schema) — exactly like Leads and Tasks. Each row
carries the synthetic display columns below in addition to the customer's own
fields.

```jsonc
{
  "count": 33,
  "results": [
    {
      "customer_id": "…",
      "name": "Ramesh Pillai",
      "status": "<customer_status_id>",          // writable FK (UUID)
      "status_name": "Upsell In Progress",        // read-only — for the pill
      "status_type": "upsell_in_progress",        // read-only — backend-fixed type
      "status_entered_at": "2025-12-08T…Z",       // powers "Since 08 Dec 2025"
      "source": "Referral",                        // lead-source name, or null
      "value_need": { "value": "1800000.00", "need": "Showroom interiors" },
      "assignees": [ { "user_id": "…", "full_name": "Divya Rao", "email": "…", "first_name": "Divya", "last_name": "Rao", "is_active": true } ],  // rich objects on read (same shape as Lead); WRITTEN as a list of user_id UUIDs
      "score": 70,                                 // customer_score (0–100)
      "last_followup_at": "2026-06-16T…Z",         // or null
      "last_followup_type": "Call",                // travels with last_followup_at
      "activity": "2026-06-18T…Z"                  // last-modified timestamp
    }
  ]
}
```

### Synthetic / display columns

| Column | Source | Notes |
| :----- | :----- | :---- |
| `status_name` | `status.name` | Human status name for the pill. `status` itself stays the writable UUID FK. |
| `status_type` | `status.status_type` | Backend-fixed code: `active` / `upsell_in_progress` / `completed` / `lost`. |
| `status_entered_at` | model field | Timestamp the customer entered its current status → the "Since <date>" subtitle. Stamped on create and every status change. |
| `source` | `source_lead.lead_source.name` | The lead-source the customer converted from. `null` if no source lead / no source. |
| `value_need` | `{value: revenue, need: purpose}` | Revenue amount + free-text purpose. `value`/`need` may be `null`. |
| `score` | `customer_score` | 0–100 customer score (see §4). |
| `last_followup_at` / `last_followup_type` | latest follow-up Task | Most-recent follow-up's timestamp + type. Batched per page (no N+1). |
| `activity` | `updated_at` | Last-activity timestamp for the Activity column. |

> These are **read-only** display columns — they are not accepted on
> create/update. `source`, `value_need`, `activity`, `last_followup_*` carry no
> `field_info` in the schema (like Lead's synthetic columns).

---

## 2b. Customer detail view

The detail page (customer profile) is driven by the **same schema mechanism** as
the list — just with `view_type=detail`. Fetch the layout, then fetch the record.

### 2b.1 Detail schema — which fields to render

```
GET /api/v1/crm/customers/schema/?view_type=detail
```

Same response shape as §1. `all_fields.columns` are the detail fields in `order`;
render where `visible === true`. On the detail view `name` is **protected**
(`is_protected: true`, always visible); other fields are toggleable via View
Settings. The seeded defaults mirror the detail mockup:

**Visible by default** (in `detail_order`):

| Field | Label | Notes |
| :---- | :---- | :---- |
| `name` | Customer | protected (always visible) |
| `organization_name` | Organization | company/account name — copied from the source lead at conversion, editable after |
| `email` | Email | |
| `phone` | Phone | |
| `source` | Source | lead-source name the customer converted from (read-only) |
| `value_need` | Value / Need | `{value: revenue, need: purpose}` |
| `revenue` | Revenue | deal value (₹) |
| `industry` | Industry | FK → Industry; copied from source lead at conversion, editable after |
| `status` | Status | the status control (pill + dropdown) |
| `score` | Score | customer_score 0–100 |
| `assigned_to` | Assigned To | the **account manager** (Owner block) |
| `assignees` | Assignees | multi-assignee set (Owner block) |
| `assigned_team` | Assigned Team | Owner block |
| `last_followup_at` | Last Follow-up | + `last_followup_type` |
| `products` · `address` · `purpose` | — | the **"View more"** block of the Customer information card |

**Hidden by default** (available via View Settings, never shown unless an admin
enables them): `sla_value`, `sla_unit`, `source_lead`, `is_archived`,
`created_at`, `activity`, `status_entered_at`, and all internals (`assigned_by`,
scoring internals, `is_test`, `is_duplicate`, custom-field slots).

> This matches Lead: every non-UI field is explicitly seeded `visible=false` so
> the detail schema never leaks internal fields.

### 2b.2 Retrieve a customer

```
GET /api/v1/crm/customers/{customer_id}/
```

Like the list, the response is **trimmed to the org's detail-visible fields**
(plus the always-present `customer_id` and `name`) — **once the detail config
exists**. That config seeds lazily on the first `schema/?view_type=detail` call,
so fetch the detail schema (§2b.1) before relying on the trim; until then the
retrieve returns the full serializer payload. Writable FKs return their UUID with
a read-only `*_name` companion for display (`status`/`status_name`,
`industry`/`industry_name`). `organization_name` and `industry` are writable on
the customer (via `PATCH`).

**200 Response** (fields shown assume the default detail config):

```jsonc
{
  "customer_id": "…",
  "name": "Ramesh Pillai",
  "organization_name": "Kalyan Silks",       // "Organization" row
  "email": "ramesh@kalyansilks.in",
  "phone": "+91 94100 11000",

  "status": "<customer_status_id>",           // writable FK (UUID)
  "status_name": "Upsell In Progress",        // read-only — the pill
  "status_type": "upsell_in_progress",        // read-only — backend-fixed type
  "status_entered_at": "2025-12-08T…Z",       // "Customer since / Since <date>"

  "source": "Referral",                        // lead-source name (read-only)
  "value_need": { "value": "1800000.00", "need": "Showroom interiors" },
  "revenue": "1800000.00",                     // deal value
  "industry": "<industry_id>",                 // writable FK (UUID)
  "industry_name": "Retail",                   // read-only — the "Industry" row
  "products": [
    { "product_id": "…", "product_name": "Showroom interiors", "quantity": 1 }
  ],
  "purpose": "Showroom interiors",
  "address": "…",

  "score": 100,                                // customer_score (0–100)

  "assigned_to": "<user_id>",                  // account manager (Owner block)
  "assignees": [                               // READ: rich user objects (same shape as Lead)
    { "user_id": "…", "full_name": "Divya Rao", "email": "…", "first_name": "Divya", "last_name": "Rao", "is_active": true }
  ],                                           // WRITE: send a list of user_id UUIDs — `"assignees": ["<user_id>", …]`
  "assigned_team": "<team_id>",

  "last_followup_at": "2026-06-16T…Z",
  "last_followup_type": "Call",                // companion, travels with the above

  // §7.6.1 — every Lead/Deal tied to this customer over its lifetime
  // (original conversion + upsells). Powers the "Leads" tab + the UPSELL/CONVERTED badges.
  "linked_leads": [
    { "lead_id": "…", "lead_name": "Ramesh Pillai", "is_upsell": true, "is_converted": true }
  ]
}
```

> **Which keys appear:** the retrieve payload is trimmed to the org's
> detail-visible fields (above) **plus** the companions the viewset always adds on
> retrieve — `status_name`, `status_type`, `industry_name`, `last_followup_type`,
> `status_entered_at`, and `linked_leads`. Other serializer fields
> (`activity`, `created_at`, `updated_at`, scoring internals,
> custom-field slots) are **not** in the default detail payload unless an admin
> makes them detail-visible via View Settings.

**Header / badges** (client-side from the payload above):

| UI element | Source |
| :--------- | :----- |
| `#C2001 · Kalyan Silks` subtitle | customer code (client-side) + `organization_name` |
| **Customer since 08-Dec-2025** | `status_entered_at` (or `created_at`) |
| **₹18L** | `revenue` (format to lakhs client-side) |
| **CUSTOMER STATUS** control | `status` (write) + `status_name`/`status_type` (display) |
| **CONVERTED** badge | present when `linked_leads` has a converted source lead |
| **UPSELL** badge | any `linked_leads[].is_upsell === true` |
| Lead score `100 / 100` | `score` |

The **Customer Activity** tabs are separate endpoints — see §2b.3.

### 2b.3 Detail-page activity tabs

Each tab on the customer detail page is backed by an **existing** list endpoint,
scoped to the one customer. The generic-relation tabs (Tasks, Follow-ups, Files,
Call log, Notes) use the **`related_to` / `related_to_id`** pattern — where
`related_to=customer` (the lowercased model name) and `related_to_id` is the
`customer_id` UUID. All are paginated (`?page=`/`?page_size=`).

| Tab | Endpoint | Scope to this customer |
| :-- | :------- | :--------------------- |
| **Tasks** | `GET /api/v1/crm/tasks/` | `?related_to=customer&related_to_id={customer_id}&is_followup=false` |
| **Follow-ups** | `GET /api/v1/crm/tasks/` | `?related_to=customer&related_to_id={customer_id}&is_followup=true` |
| **Files** | `GET /api/v1/crm/attachments/` | `?related_to=customer&related_to_id={customer_id}` |
| **Call log** | `GET /api/v1/crm/call-logs/` | `?related_to=customer&related_to_id={customer_id}` |
| **Notes** ("Add note") | `GET · POST /api/v1/crm/notes/` | list: `?related_to=customer&related_to_id={customer_id}` · create: POST with `related_to=customer` + `related_to_id={customer_id}` |
| **Payments** (invoice header) | `GET /api/v1/quotations/payments/` | `?customer_id={customer_id}` (Payment → Quotation → Customer) — **see the Payments-tab subsection below** |
| — payment installments (rows) | `GET /api/v1/quotations/payment-records/` | `?customer_id={customer_id}` (or `?payment={payment_id}`) |
| **Quotations** | `GET /api/v1/quotations/quotations/` | `?customer_id={customer_id}` |
| **Leads** | `GET /api/v1/crm/leads/` | `?parent_customer={customer_id}` (add `&is_upsell=true` for only upsell leads) |
| **Audit log** | `GET /api/v1/access-control/audit-logs/` | `?model_name=Customer&record_id={customer_id}&ordering=-timestamp` |

Notes:

- **Uploading a file** (Files tab): `POST /api/v1/crm/attachments/` (multipart)
  with `file_upload=<file>&related_to=customer&related_to_id={customer_id}`.
- **Adding a note** (the header "Add note" button): `POST /api/v1/crm/notes/`
  with the note body + `related_to=customer&related_to_id={customer_id}`.
- **Leads tab — two options.** For a quick, non-paginated list use the
  `linked_leads` array already embedded in the retrieve payload (§2b.2). For a
  full **paginated / filterable** list use `GET /leads/?parent_customer={id}` —
  this returns the customer's upsell leads (the ones spawned from it). The
  original **source lead** is not a child of the customer, so it appears in
  `linked_leads` (via `source_lead`) but **not** in `?parent_customer=` — combine
  both if you need the complete set.
- **Audit `model_name` is `Customer`** (case-insensitive), `record_id` is the
  `customer_id`. Task/customer writes are audited; FK-UUID fields in
  `changes.request_body` are enriched with sibling `<field>_name` values on read.

#### Payments tab — invoice header + installment rows

The **Payments** tab renders in **two levels** from **two existing endpoints**, both
scoped by `?customer_id={customer_id}` (no customer-specific route — the filters
walk `Payment → Quotation → Customer`). A `Payment` is auto-created only when a
quote reaches an **Accepted** (`is_converted`) status — hence *"Invoice … (from
accepted quote)"*. **Both endpoints skip the cache** (always fresh after a record is
marked paid).

**1) Invoice header card** — one `Payment` (the "invoice"):

```
GET /api/v1/quotations/payments/?customer_id={customer_id}
```

```jsonc
{
  "payment_id": "…uuid…",
  "quotation_number": "QUO-2041",          // → "Invoice #… (from accepted quote)"
  "payment_type": "installment_custom",     // drives the row "Milestone" tag (see below)
  "total_amount": "3650000.00",             // → "Invoice total  ₹36.5L"
  "amount_paid": "1460000.00",              // → "Paid  ₹14.6L"       (live: Σ paid records)
  "amount_remaining": "2190000.00",         // → "Balance due  ₹21.9L" (total − paid)
  "currency": "INR",
  "status": "active",                        // active | completed | cancelled → header "Due"/"Paid" pill
  "next_due_date": "2026-07-01",
  "records": [ … full PaymentRecord objects … ]   // the rows are embedded here too
}
```

- `amount_paid` / `amount_remaining` are **computed live** in the serializer
  (`Σ amount_paid` of `status="paid"` records; `total − paid`) — never trust a stale
  stored value.
- The embedded `records` array is the same list as endpoint (2), so a single
  `/payments/?customer_id=` call can render the whole tab. Use (2) when you need
  server-side filtering/pagination of the rows alone.
- A per-invoice summary (counts of paid/pending/overdue) is also available at
  `GET /api/v1/quotations/payments/{payment_id}/summary/`, and a printable receipt at
  `…/{payment_id}/receipt/?output=html|pdf`.

**2) Installment rows** — the `PaymentRecord`s (each row in the list):

```
GET /api/v1/quotations/payment-records/?customer_id={customer_id}
GET /api/v1/quotations/payment-records/?payment={payment_id}     # rows of one invoice
```

```jsonc
{
  "record_id": "…uuid…",
  "invoice_id": "…payment_id…",            // parent Payment
  "installment_number": 1,
  "amount_expected": "720000.00",           // → row amount "₹7.2L"
  "amount_paid": "720000.00",
  "due_date": "2026-06-10",                 // → row date "10 Jun 2026"
  "paid_date": "2026-06-10",
  "status": "paid",                          // paid | pending | overdue | cancelled → "Paid"/"Due" chip
  "payment_method": "bank_transfer",         // → "Bank transfer" (bank_transfer|upi|card|cash|cheque)
  "notes": "Advance · 40%"                   // → row LABEL ("Advance · 40%", "Phase one · 30%")
}
```

**UI-mapping notes (no backend field for these — derive on the FE):**

- **Row label** ("Advance · 40%", "Phase one · 30%") = the record's **`notes`**.
  Auto-generated records get generic notes ("Full lumpsum payment", "Installment 2
  of 4"); **milestone** invoices (`installment_custom`) are where a user names each
  record — set `notes` to the human label on create/patch.
- **The "· Milestone" tag** on each row is derived from the parent
  **`payment_type == "installment_custom"`** (there is no per-row type field). Map:
  `lumpsum` → (no tag) · `installment_even` → "Installment" · `subscription` →
  "Subscription" · `installment_custom` → **"Milestone"**.
- **The "40%" / "30%" percentage** has **no stored field** — compute it as
  `amount_expected ÷ payment.total_amount` on the client.
- **Status chip:** `paid` → green "Paid"; `pending`/`overdue` → amber "Due"
  (distinguish overdue by `due_date < today` if you want a separate style);
  `cancelled` → hidden/struck.

**Marking a milestone paid** (the FE action behind a row): `PATCH
/api/v1/quotations/payment-records/{record_id}/` with
`{"status":"paid","amount_paid":"…","paid_date":"…","payment_method":"upi"}`. Every
record mutation **recalculates the parent invoice** (`amount_paid`, `next_due_date`,
auto-completes/cancels) — so re-fetch the header after. `amount_paid` may not exceed
the invoice's remaining balance → **400**. New rows can only be **added** to an
`installment_custom` invoice (`POST /payment-records/`); other types are
system-generated.

---

## 2c. Customer Kanban board

The **List / Kanban** toggle on the Customers screen switches to a board grouped
by customer status. Parity with `GET /leads/board/` and `GET /tasks/board/`.

```
GET /api/v1/crm/customers/board/
```

One call returns **every active status lane** (in `position` order, zero-count
lanes included), each with its total `count` and its **first page** of cards, plus
a per-lane `next_page`/`next_url` for lazy "load more". Unlike Leads, no lane is
excluded by status type — Active / Upsell In Progress / Completed / Lost all
appear. Archived customers are excluded by default.

**Query params** (all optional):

| Param | Default | Notes |
| :---- | :------ | :---- |
| `lane_page_size` | `20` | cards per lane in this response (max `50`). |
| any list filter | — | every `CustomerFilter` param + `custom_fields.*` + `saved_filter_id` works, applied to all lanes (e.g. `?search=`, `?assigned_to__in=`, `?revenue__min=`). |
| `is_archived` | excluded | pass `?is_archived=true` to show archived instead. |

Cards are **byte-identical to list rows** — same trimming and the same synthetic
columns (`status_name`, `status_type`, `source`, `value_need`, `score`,
`last_followup_at`/`_type`, `activity`). Render them with the list schema (§1).

**200 Response:**

```jsonc
{
  "board_total": 33,                    // sum of all lane counts (after filters)
  "lane_page_size": 20,
  "lanes": [
    {
      "status_id": "<customer_status_id>",
      "status_name": "Active",
      "status_type": "active",          // backend-fixed code
      "color": "#22C55E",
      "position": 0,
      "count": 23,                       // TOTAL in this lane (not just this page)
      "cards": [ /* up to lane_page_size list-shaped customer rows */ ],
      "next_page": 2,                    // null when the lane fits one page
      "next_url": "/api/v1/crm/customers/?status=<id>&page=2&page_size=20"
    },
    {
      "status_id": "<customer_status_id>",
      "status_name": "Upsell In Progress",
      "status_type": "upsell_in_progress",
      "color": "#F59E0B",
      "position": 1,
      "count": 4,
      "cards": [ /* … */ ],
      "next_page": null,
      "next_url": null
    }
    // … one lane per active CustomerStatus (Completed, Lost, …), zero-count included
  ]
}
```

### Load more within a lane

When a lane has `next_page`, fetch the next page **from the list endpoint** using
`next_url` verbatim (it pins `status`, `page`, `page_size` and echoes your active
board filters). Successive pages are **disjoint** and continue the same ordering
(`-created_at`, then `customer_id`), so you can append them to the lane:

```
GET /api/v1/crm/customers/?status=<id>&page=2&page_size=20   ← next_url
→ standard paginated list response ({count, results:[…]})
```

Move a card between lanes with the existing update endpoints (`PATCH
/customers/{id}/` with a new `status`, or `POST /customers/bulk-status/`).

> **Caching:** the board response is cached ~300s per user/org (like the lead
> board). A customer write bumps the cache version, so moves/edits reflect on the
> next fetch.

---

## 3. Editing the Customer list layout (admin)

Reuse the Org View Settings API with `model_name=customer`:

```
GET /api/v1/management/org-field-config/?model_name=customer&view_type=list
PUT /api/v1/management/org-field-config/          # admin only
```

- `order` values must be **unique** within the payload.
- Attempting to hide a **fixed** column (`name`, `status`, `source`,
  `value_need`, `assignees`, `last_followup_at`, `activity`) returns **400** —
  keep those toggles locked. Only `score` (and any non-default column) is
  toggleable.
- After a successful `PUT`, re-fetch the schema (§1) to re-render.

Full contract: `docs/working/org-view-settings-api.md`.

---

## 4. Customer Score

Each customer has a **0–100 score** (`customer_score`), computed by a
deterministic weighted engine (`crm/services/customer_scoring.py`) — the
customer analogue of lead scoring. Five signals:

| Signal | Max | Basis |
| :----- | :-- | :---- |
| Recency of last activity | 25 | days since last Task/Note/Call |
| Interaction count (90d)  | 20 | interactions in the last 90 days |
| Revenue value            | 20 | revenue vs org percentiles |
| Engagement consistency   | 15 | inverse of staleness |
| Health / completeness    | 20 | status type + products + contactability |

- The score is **persisted** on the customer and returned as the `score` column.
  `customer_score_breakdown` (JSON) holds the per-signal split and
  `customer_score_updated_at` the last computation time.
- **Recompute on demand** (whole org):

  ```
  POST /api/v1/crm/customers/recalculate-scores/
  → { "message": "Customer scores recalculated for N customers.", "scored": N }
  ```

- Scores also refresh **automatically** when a Task / Note / Call linked to the
  customer is created or updated (debounced, async via Celery), and via a nightly
  batch task (`crm.tasks.recalculate_customer_scores`).

---

## 5. Related endpoints (unchanged, for completeness)

| Purpose | Method & Path |
| :------ | :------------ |
| List / create customers | `/api/v1/crm/customers/` |
| Retrieve / update / delete | `/api/v1/crm/customers/{customer_id}/` |
| **List schema** | `GET /api/v1/crm/customers/schema/?view_type=list` |
| **Detail schema** | `GET /api/v1/crm/customers/schema/?view_type=detail` |
| **Kanban board** | `GET /api/v1/crm/customers/board/` |
| **Recalculate scores** | `POST /api/v1/crm/customers/recalculate-scores/` |
| Bulk assign | `POST /api/v1/crm/customers/bulk-assign/` |
| Bulk status | `POST /api/v1/crm/customers/bulk-status/` |
| Upsell → new lead | `POST /api/v1/crm/customers/{customer_id}/upsell/` |
| Customer statuses (CRUD) | `/api/v1/crm/customer-statuses/` |
| Fixed status types | `GET /api/v1/crm/customer-statuses/status-types/` |
| Customer custom fields | `/api/v1/management/custom-fields/?model_name=customer` |
| Edit list columns (admin) | `GET/PUT /api/v1/management/org-field-config/` (`model_name=customer`) |
| **Tasks tab** | `GET /api/v1/crm/tasks/?related_to=customer&related_to_id={id}` |
| **Follow-ups tab** | `GET /api/v1/crm/tasks/?is_followup=true&related_to=customer&related_to_id={id}` |
| **Files tab** | `GET/POST /api/v1/crm/attachments/?related_to=customer&related_to_id={id}` |
| **Call log tab** | `GET /api/v1/crm/call-logs/?related_to=customer&related_to_id={id}` |
| **Notes** | `GET/POST /api/v1/crm/notes/?related_to=customer&related_to_id={id}` |
| **Payments tab** | `GET /api/v1/quotations/payments/?customer_id={id}` |
| — installments | `GET /api/v1/quotations/payment-records/?customer_id={id}` |
| **Quotations** | `GET /api/v1/quotations/quotations/?customer_id={id}` |
| **Leads tab** | `GET /api/v1/crm/leads/?parent_customer={id}` (`&is_upsell=true`) |
| **Audit log** | `GET /api/v1/access-control/audit-logs/?model_name=Customer&record_id={id}` |

---

## 6. Seeding / backfill (FYI — no frontend action)

- **Per-org** customer list/detail column config is seeded **lazily** on first
  schema/config access.
- `status_entered_at` is backfilled to `created_at` for existing customers by the
  migration; the score defaults to `20` until the first recalculation.
- For **existing** orgs seeded before this change, run
  `manage.py backfill_customer_list_config --all` (`--dry-run` to preview,
  `--force` to overwrite customized orgs) to pick up the new default columns.
- **Demo Payments** (to populate the Payments tab): `manage.py seed_quotations_data
  [--count N] [--flush]` creates Accepted quotations → `Payment` + `PaymentRecord`
  rows for existing customers (all four payment types, realistic paid/overdue
  status). Run `seed_leads_data` + `seed_customers_data` first. Idempotent per run;
  `--flush` clears prior quotation seed data.

---

## 7. Customer statuses (CRM Settings)

The **CRM Settings → Customer Status** screen manages the org's customer
statuses. Each status maps to exactly one of the 4 backend-fixed **status types**
(Active → Completed → Lost → Upsell In Progress, §7.5). Admins can add / edit /
delete statuses and **reorder them within a type** via the drag handle. All
endpoints are served by `CustomerStatusViewSet` and mount under
`/api/v1/crm/customer-statuses/`. Reads require `view_customer`; writes require the
matching `add_/change_/delete_customer` permission.

| Action | Method | Path |
| :--- | :--- | :--- |
| List statuses | GET | `/api/v1/crm/customer-statuses/` |
| Fixed status types (read-only, global) | GET | `/api/v1/crm/customer-statuses/status-types/` |
| Create status | POST | `/api/v1/crm/customer-statuses/` |
| Retrieve one | GET | `/api/v1/crm/customer-statuses/{customer_status_id}/` |
| Update | PUT / PATCH | `/api/v1/crm/customer-statuses/{customer_status_id}/` |
| Delete | DELETE | `/api/v1/crm/customer-statuses/{customer_status_id}/` |
| Reorder (within type) | POST | `/api/v1/crm/customer-statuses/reorder/` |

The status object shape (list / retrieve / create / update):

```jsonc
{
  "customer_status_id": "a4c1…",
  "name": "Upsell In Progress",
  "status_type": "upsell_in_progress",   // written & read as the type CODE
  "status_type_name": "Upsell In Progress",
  "color": "#9013FE",
  "position": 3,
  "is_active": true,
  "is_default": false,
  "is_completed": false,                  // read-only, derived from the type
  "is_lost": false,
  "is_upsell_in_progress": true,
  "is_readonly": false
}
```

`status_type` is the type **code** (`active` / `completed` / `lost` /
`upsell_in_progress`). `organization`, `created_by`, `modified_by`, `owner`,
`is_readonly` are read-only.

### List statuses

```
GET /api/v1/crm/customer-statuses/
```

Returns the org's statuses **already banded by type** then by within-type
`position` (`ORDER BY status_type.position, position`), so the UI renders the fixed
type order directly.

### Status type catalog

```
GET /api/v1/crm/customer-statuses/status-types/
```

The 4 global fixed types, read-only, ordered by `position`. Each item →
`{code, name, position}`. Tenants cannot create/edit/delete these.

**200 Response**

```jsonc
[
  {"code": "active", "name": "Active", "position": 0},
  {"code": "completed", "name": "Completed", "position": 1},
  {"code": "lost", "name": "Lost", "position": 2},
  {"code": "upsell_in_progress", "name": "Upsell In Progress", "position": 3}
]
```

### Create / update a status

```
POST  /api/v1/crm/customer-statuses/
PATCH /api/v1/crm/customer-statuses/{customer_status_id}/
```

```jsonc
{ "name": "Onboarding", "status_type": "active", "color": "#4A90E2", "position": 1 }
```

Create returns **201**; `organization` / `created_by` are stamped automatically.

> When `position` is supplied on create/update it must respect type-order banding
> (see Reorder) — a position landing inside another type's band returns **400**.
> System-protected statuses (`is_readonly: true`) return **403** for non-superusers.

### Delete a status

```
DELETE /api/v1/crm/customer-statuses/{customer_status_id}/
```

Returns **204** on success. Blocked with **400** when:

- any customer references the status —
  `{"detail": "Cannot delete this customer status because it is referenced by existing customers."}`
- it is the **last** status mapped to its type (§7.5) —
  `{"detail": "Cannot delete the last customer status mapped to its status type."}`

System-protected statuses return **403** for non-superusers.

### Reorder statuses (within a type)

```
POST /api/v1/crm/customer-statuses/reorder/
```

Body is a flat list of `{customer_status_id, position}`; each listed status has its
`position` set, omitted statuses keep their current `position`.

```jsonc
[
  { "customer_status_id": "a4c1…", "position": 2 },
  { "customer_status_id": "b8e2…", "position": 3 }
]
```

**200 Response**

```jsonc
{ "detail": "Reorder successful." }
```

> **Type-order banding (§7.5) is enforced.** The *resulting* order must keep each
> type's statuses contiguous and in the fixed type order
> (`active < completed < lost < upsell_in_progress`). You can freely reorder
> statuses **within** a type, but you cannot move one across a type boundary — e.g.
> placing a **Completed** status after a **Lost** status is rejected with **400**:
>
> ```jsonc
> { "detail": "Reordering would break status-type order: 'Completed' statuses must come before 'Lost' statuses." }
> ```
>
> On rejection nothing is written (the check runs before the transaction). The same
> banding rule is enforced on create/update whenever `position` is supplied.
