# Quotation Schema & List/Detail View — Frontend API Guide

This document covers everything the frontend needs to render the **Quotes list
view** (screenshot: search, status tabs, List/Kanban toggle, `QUOTE / LEAD /
STATUS / ITEMS / AMOUNT / VALID TILL / OWNER / ACTIVITY / ACTIONS` columns) and
the **Quote detail page**, driven by the same Org View Settings engine as
Lead/Task (see `docs/apis/org-view-settings-api.md` for the generic contract).

All routes are under `/api/v1/quotations/`. Auth: authenticated user; column
config writes (`PUT /org-field-config/`) require **org admin**.

---

## 1. Quote list schema — the column catalog

```
GET /api/v1/quotations/quotations/schema/?view_type=list
GET /api/v1/quotations/quotations/schema/?view_type=detail
```

Single source of truth for which columns to render, in what order, and which
are fixed. Auto-seeds org defaults on first access — a new org immediately gets
a sensible layout. Response shape is identical to the Lead/Task schema (see
`docs/working/task-schema-and-status-api.md §1` for the general shape).

> **Use `view_type=detail` for the "New quote" / edit form too — not `form`.**
> `?view_type=form` falls back to a flat, unordered catalog built by
> introspecting `Quotation`'s raw model fields only (`model_class._meta.get_fields()`).
> Since `template_name`, `lead_name`, `owner`, `line_items`, and `pdf_url` are
> `SerializerMethodField`s (not real model fields), **none of them appear under
> `form`** — you'd be missing the template picker's display name, the line-items
> entry rows, and the owner field entirely. `view_type=detail` returns the full,
> ordered `all_fields.columns` catalog (§2) including those synthetic fields, so
> both the **create** modal and the **detail/edit** panel should drive off the
> same `detail` schema call.

**200 Response** (`view_type=list`):

```jsonc
{
  "model": "Quotation",
  "view_type": "list",
  "has_org_config": true,
  "has_user_settings": false,
  "fields": { "...": "per-field metadata (type, choices, label)" },
  "custom_field_definitions": [],
  "all_fields": {
    "columns": [
      { "name": "quotation_number", "label": "Quote No.",   "order": 1,  "visible": true, "width": 140, "is_protected": true,  "is_fixed": true },
      { "name": "quotation_title",  "label": "Title",       "order": 2,  "visible": true, "width": 200, "is_protected": false, "is_fixed": false },
      { "name": "status",           "label": "Status",      "order": 3,  "visible": true, "width": 120, "is_protected": false, "is_fixed": false },
      { "name": "total_amount",     "label": "Amount",      "order": 4,  "visible": true, "width": 120, "is_protected": false, "is_fixed": false },
      { "name": "currency",         "label": "Currency",    "order": 5,  "visible": true, "width": 90,  "is_protected": false, "is_fixed": false },
      { "name": "valid_until",      "label": "Valid Until", "order": 6,  "visible": true, "width": 130, "is_protected": false, "is_fixed": false },
      { "name": "created_at",       "label": "Issued",      "order": 7,  "visible": true, "width": 130, "is_protected": false, "is_fixed": false },
      { "name": "payment_type",     "label": "Payment Type","order": 9,  "visible": false,"width": 130, "is_protected": false, "is_fixed": false },
      { "name": "due_date",         "label": "Due Date",    "order": 10, "visible": false,"width": 130, "is_protected": false, "is_fixed": false },
      { "name": "notes",            "label": "Notes",       "order": 15, "visible": false,"width": 220, "is_protected": false, "is_fixed": false }
    ],
    "sorting": [],
    "filters": []
  }
}
```

**How to render the list:**

- Iterate `all_fields.columns` **in `order`** (already sorted ascending).
- Show a column only when `visible === true`.
- `quotation_number` is the only **fixed/protected** column on the list view
  (globally protected as each module's anchor field — see the coverage matrix
  in `docs/apis/org-view-settings-api.md`).
- The list UI's `ITEMS`, `OWNER`, and `ACTIVITY` columns are **not yet**
  built-in schema columns (see **Gaps** below) — today only the fields listed
  above are schema-driven; `ITEMS`/`OWNER` must be read off the **detail**
  columns (`line_items`, `owner`) or the record payload directly until the
  list seed is extended.

### Default fixed column set (seeded for every new org)

| Order | Field              | Fixed | Notes |
| :---- | :----------------- | :---- | :---- |
| 1     | `quotation_number` | ✅    | e.g. "QTN-00016" |
| 2     | `quotation_title`  |       | |
| 3     | `status`           |       | Human-readable status name |
| 4     | `total_amount`     |       | |
| 5     | `currency`         |       | |
| 6     | `valid_until`      |       | |
| 7     | `created_at`       |       | Labeled "Issued" |
| 9–15  | (other, hidden by default) | | `payment_type`, `due_date`, `notes` |

---

## 2. Quote **detail page**

Rendered the same way as Lead/Task detail: the schema endpoint
(`view_type=detail`) is the source of truth for which fields the "Quote
information" panel shows, and the record endpoint returns the quote data
trimmed to exactly the org-configured detail columns.

### Two calls per page

```
GET /api/v1/quotations/quotations/schema/?view_type=detail   # what to render + order (once, cacheable)
GET /api/v1/quotations/quotations/{quotation_id}/             # the record itself (detail-trimmed)
```

### Creating a quote (the "New quote" modal)

Populate the modal from the **same `view_type=detail` schema** call above (per
the note in §1) — it's the only schema call that includes `template`, `lead`,
`customer`, `owner`, and `line_items`. Then:

```
POST /api/v1/quotations/quotations/
```

```jsonc
{
  "lead": "<lead_id>",                       // required
  "template": "<template_id>",               // optional — falls back to the org's default template
  "quotation_title": "Website Revamp",       // optional
  "valid_until": "2026-09-04",               // optional — falls back to org default validity (days)
  "payment_type": "installment_custom",      // lumpsum | subscription | installment_even | installment_custom
  "num_installments": 3,                     // required if payment_type = installment_even (>= 2)
  "currency": "INR",
  "notes": "Pricing valid for 30 days from the date of issue.",
  "field_values": { "...": "template placeholder values" },
  "line_items": [
    { "description": "Website Revamp", "quantity": 1, "unit_price": "184991.00" }
  ],
  "owner_id": "<user_id>"                    // optional — defaults to the creating user, see §2 owner note
}
```

- `owner` is **not** sent on create — the server always stamps `owner` =
  the requesting user (`perform_create` → `BaseCRMViewSet.perform_create`),
  regardless of `owner_id`. Reassign afterwards via `PATCH` (§2a) if needed.
- `customer` is **not** sent on create either — a quote starts against a
  `lead`; `customer` is populated once/if the lead converts.
- **201 Response**: the full detail-shaped object (§2's record example),
  including the server-generated `quotation_number` (e.g. `"QTN-00017"`).

### Default detail columns seeded for a new org

Matches the "Quote information" panel + Line items panel + Owner block in the
UI:

| Order | Field           | Label       | Shown in UI as |
| :---- | :-------------- | :---------- | :------------- |
| 1     | `quotation_number` | Quote No. | Header ("QTN-00016") — fixed/protected |
| 2     | `quotation_title`  | Title     | Quote title |
| 3     | `status`           | Status    | Status pill / Accept & invoice / Reject actions |
| 4     | `total_amount`     | Amount    | Quote total |
| 5     | `currency`         | Currency  | Currency |
| 6     | `valid_until`      | Valid Until | Valid until |
| 7     | `payment_type`     | Payment Type | Payment type |
| 8     | `template_name`    | Template  | Template (resolved name, e.g. "Standard") |
| 9     | `created_at`       | Issued    | Issued |
| 10    | `due_date`         | Due Date  | Due date |
| 11    | `lead` / `lead_name` | Lead    | Lead — raw `lead_id` (deep-link target) + resolved name, both keyed the same order |
| 12    | `customer` / `customer_name` | Company | Company — raw `customer_id` (deep-link target, `Related → Customer` link) + resolved name |
| 13    | `owner`            | Quote Owner | Owner block — `{user_id, full_name, email, avatar}`, set to the **creating user** at quote-creation time |
| 14    | `line_items`       | Line Items  | Line items panel (qty/rate/amount) |
| 16    | `pdf_url`          | PDF       | Link to the rendered PDF (see §3) |

> **Gap fixed (2026-08-06).** The detail schema previously seeded none of
> `template`/`template_name`, `lead`/`lead_name`, `customer`/`customer_name`,
> `owner`, `line_items`, or `pdf_url` — so even though `QuotationSerializer`
> already produced all of these, the `?fields=` param built from the (empty)
> schema silently stripped them from every detail response, and the UI showed
> "—" / "Unassigned" / an empty line-items table for real data. `lead` and
> `customer_name` were added in a follow-up pass (frontend needed both the raw
> id for deep-linking and the resolved display name). Existing orgs need
> `manage.py backfill_quotation_detail_config --all` (see §5) to pick up the
> new columns — the fix only affects **newly seeded** orgs automatically.

### The record endpoint (`GET /quotations/quotations/{quotation_id}/`)

Returns the quote **trimmed to the detail-visible columns** above. Abbreviated
example once an org has backfilled (§5):

```jsonc
GET /api/v1/quotations/quotations/1743b07f-.../
{
  "quotation_id": "1743b07f-...",
  "quotation_number": "QTN-00002",
  "quotation_title": "",
  "template_name": "Standard",
  "status": { "quotation_status_id": "...", "name": "Accepted", "color": "#10B981", "is_converted": true, "...": "" },
  "total_amount": "184991.00",
  "currency": "INR",
  "valid_until": "2026-09-04",
  "due_date": null,
  "payment_type": "installment_custom",
  "lead": "<lead_id>",
  "lead_name": "Kalyan Silks",
  "customer": "<customer_id-or-null>",
  "customer_name": "<customer-name-or-null>",
  "owner": { "user_id": "...", "full_name": "NewVersion Admin", "email": "admin@newversion.com", "avatar": null },
  "line_items": [
    { "line_item_id": "...", "description": "Website Revamp", "quantity": "1.00", "unit_price": "184991.00", "total_price": "184991.00" }
  ],
  "pdf_url": "https://.../api/v1/quotations/quotations/1743b07f-.../render/?output=pdf",
  "created_at": "2026-07-01T08:21:15Z"
}
```

- `owner` is **read-only as a rich object**; write via `owner_id: "<user_id>"`
  on `PATCH`/`POST` (org-scoped — a cross-org user is rejected with 400).
  Semantically, "owner" = "the user who created the quote" (set automatically
  by `perform_create`) — there is no separate "send" action today.
- `line_items` mirrors the create/update payload shape (`description`,
  `quantity`, `unit_price`, `total_price` — `total_price` is server-computed).
  On `PATCH`, sending `line_items` **replaces the whole set**.
- `customer` is the raw `customer_id` (nullable — set once the lead converts);
  `customer_name` is its resolved display name (`Customer.name`, `null` when
  `customer` is `null`). Use `customer` as the `Related → Customer` link
  target (`GET /api/v1/crm/customers/{customer_id}/`) and `customer_name` for
  display — no extra call needed just to show the company name.
- `lead` is likewise the raw `lead_id` alongside the resolved `lead_name`.

---

## 2a. The other detail-page panels (existing endpoints — no new work)

The header (title / status pill / Accept & invoice / Reject actions), **Notes**,
**Files**, the **Payments / invoice** breakdown (once a quote is Accepted), and
the **Audit log** are rendered from these:

| Panel | Endpoint |
| :---- | :------- |
| **Edit** (title, template, payment config, valid until, notes, …) | `PATCH /api/v1/quotations/quotations/{quotation_id}/` (any writable field; `view_type=form` schema lists them) |
| **Status dropdown / Accept & invoice / Reject** | `PATCH /api/v1/quotations/quotations/{quotation_id}/` with `{"status_id": "<quotation_status_id>"}`. Moving into an `is_converted` status auto-creates the invoice (`Payment` + `PaymentRecord`s, §2b); moving out deletes them. |
| **Reassign owner** | `PATCH /api/v1/quotations/quotations/{quotation_id}/` with `{"owner_id": "<user_id>"}` |
| **Delete** | `DELETE /api/v1/quotations/quotations/{quotation_id}/` |
| **Line items** — edit | `PATCH /api/v1/quotations/quotations/{quotation_id}/` with `{"line_items": [...]}` (§2 — full-set replace) |
| **Notes** tab — list/add | `GET/POST /api/v1/crm/notes/?content_type_model=quotation&object_id=<quotation_id>` (create: `{"related_to": "quotation", "related_to_id": "<quotation_id>", "content": "..."}`) |
| **Notes** tab — reply/pin/delete | `POST /api/v1/crm/notes/{note_id}/replies/`, `PATCH /api/v1/crm/notes/{note_id}/` (`is_pinned`), `DELETE /api/v1/crm/notes/{note_id}/` |
| **Files** tab — list | `GET /api/v1/crm/attachments/?related_to=quotation&related_to_id=<quotation_id>` |
| **Files** tab — upload | `POST /api/v1/crm/attachments/` (multipart) with `file_upload=<file>&related_to=quotation&related_to_id=<quotation_id>` |
| **Files** tab — delete | `DELETE /api/v1/crm/attachments/{attachment_id}/` |
| **Payments / Invoice** panel | `GET /api/v1/quotations/payments/?quotation=<quotation_id>` → then `GET /api/v1/quotations/payments/{payment_id}/summary/` (§2b) |
| **Audit log** (bottom of page) | `GET /api/v1/access-control/audit-logs/?model_name=Quotation&record_id=<quotation_id>` (paginated, newest first) |

> **Note on the detail's `team_notes` field.** `QuotationSerializer` also
> embeds a lightweight `team_notes` array (title/content/pinned/created_by/
> created_at) pre-fetched in one query per detail request — a read-only
> convenience snapshot. It is **not** how notes are created or replied to; use
> the `/crm/notes/` endpoints above for all writes, and prefer them for reads
> too if you need pagination, threading, or attachments on a note.

> **Known gap — `QuotationAttachment`.** `QuotationSerializer.attachments`
> exposes the legacy `quotations.QuotationAttachment` model (nested,
> read-only) — but there is **no CRUD endpoint for it** (no viewset, no
> route). It will always read back empty for new quotes. The **Files** tab
> above uses the separate, working, generic `crm.Attachment` polymorphic
> table (`related_to=quotation`) — use that, not the `attachments` field on
> the quote object.

### 2b. Payments / Invoice panel

Once a quote's status flips to an `is_converted` status ("Accepted"), a
`Payment` (with one or more `PaymentRecord` installments, per the quote's
`payment_type`) is auto-created:

```
GET /api/v1/quotations/payments/?quotation=<quotation_id>         # find the payment for this quote
GET /api/v1/quotations/payments/{payment_id}/summary/              # total/paid/remaining/record counts
GET /api/v1/quotations/payments/{payment_id}/receipt/?output=pdf   # payment receipt PDF (WeasyPrint, on-demand — same pattern as §3)
GET /api/v1/quotations/payment-records/?payment=<payment_id>       # individual installments (mark paid, etc.)
PATCH /api/v1/quotations/payment-records/{record_id}/              # mark a record paid/overdue, fix amounts
```

`summary` response:

```json
{
  "payment_id": "...",
  "payment_type": "installment_custom",
  "total_amount": "184991.00",
  "amount_paid": "50000.00",
  "amount_remaining": "134991.00",
  "currency": "INR",
  "status": "partially_paid",
  "next_due_date": "2026-09-15",
  "total_records": 3,
  "pending_records": 2,
  "paid_records": 1,
  "overdue_records": 0
}
```

Reverting status away from Accepted **deletes** the Payment + its records
(§9.8 in the rulebook then locks monetary fields once any record is `paid`
— see `QuotationSerializer._PAID_LOCKED_FIELDS`).

---

## 3. The PDF ("Quote total" / print/download)

No PDF file is generated ahead of time or stored — `pdf_url` in the detail
payload just points at the existing **on-demand render endpoint**:

```
GET /api/v1/quotations/quotations/{quotation_id}/render/?output=html   # HTML preview (default)
GET /api/v1/quotations/quotations/{quotation_id}/render/?output=pdf    # PDF download (WeasyPrint)
```

- `output=html` returns `{ "html": "<...>", "quotation_number": "QTN-00002" }`.
- `output=pdf` streams a `Content-Disposition: attachment` PDF response —
  point a download/print button straight at this URL (it needs the same
  Bearer auth header as any other API call, so a plain `<a href>` won't work
  unless the request is authenticated; fetch it and blob it, or open via a
  signed/proxied link).
- Nothing is cached — every call regenerates the PDF from the quote's current
  data + its `QuotationTemplate` HTML file.

---

## 4. Status workflow (Draft → Sent → Accepted / Rejected / Expired)

Quotes reference an org-editable **`QuotationStatus`** (not a fixed global
type table like Task's `status_type` — see rulebook §9.2–9.4 for the
lifecycle).

```
GET    /api/v1/quotations/statuses/                        # list org statuses
POST   /api/v1/quotations/statuses/                        # create
GET    /api/v1/quotations/statuses/{quotation_status_id}/  # retrieve
PATCH  /api/v1/quotations/statuses/{quotation_status_id}/   # update
DELETE /api/v1/quotations/statuses/{quotation_status_id}/  # delete
```

**Status object (read):**

```json
{
  "quotation_status_id": "9a7579c8-...",
  "name": "Sent",
  "color": "#3B82F6",
  "position": 1,
  "is_active": true,
  "is_default": false,
  "is_converted": false,
  "is_readonly": true
}
```

- `is_converted: true` marks the "Accepted" status — moving a quote **into**
  a converted status auto-creates a `Payment` + `PaymentRecord`s (invoice);
  moving **out** deletes them (see `handle_quotation_accepted` /
  `_delete_quotation_payments` in `quotations/views.py`).
- `is_readonly: true` marks a system-seeded status (Draft/Sent/Accepted/
  Rejected/Expired) — blocked from edit/delete for non-superusers.
- Write the quote's status via `PATCH .../{quotation_id}/` with
  `{"status_id": "<quotation_status_id>"}` (not the nested `status` object).

---

## 5. Editing the Quote column layout (admin)

Reuse the Org View Settings API with `model_name=quotation`:

```
GET /api/v1/management/org-field-config/?model_name=quotation&view_type=list
GET /api/v1/management/org-field-config/?model_name=quotation&view_type=detail
PUT /api/v1/management/org-field-config/         # admin only
```

```json
PUT /api/v1/management/org-field-config/
{
  "model_name": "quotation",
  "view_type": "detail",
  "fields": [
    { "field_name": "owner", "order": 13, "is_visible": true, "width": 160, "label_override": null }
  ]
}
```

Full request/response contract: `docs/apis/org-view-settings-api.md`.

### Backfilling existing orgs

Per-org quote column config is seeded **lazily** the first time the schema or
org-field-config endpoint is hit for `quotation` — so a brand-new org gets the
full default layout (including `owner`/`line_items`/`pdf_url`/`template_name`/
`lead_name`) automatically. Orgs seeded **before** the 2026-08-06 fix carry the
old, narrower config and need a one-time backfill:

```bash
python manage.py backfill_quotation_detail_config --all --dry-run   # preview
python manage.py backfill_quotation_detail_config --all             # apply
python manage.py backfill_quotation_detail_config --org-id <uuid>   # single org
python manage.py backfill_quotation_detail_config --all --force     # also overwrite customized orgs (loses their choices)
```

Idempotent; skips orgs whose config no longer matches a known default set
(treated as admin-customized) unless `--force` is passed.

---

## Gaps (not yet built — flagging for follow-up, not implemented here)

- **No `status-counts` action.** The list UI's tab counts (`All (0)`,
  `Draft`, `Sent`, `Accepted`, `Rejected`, `Expired`) have no backing
  endpoint yet, unlike `crm/views/issue.py`'s `status-counts` action. Today
  the frontend would need to call `?status=<name>` per tab and read
  `response.count`, or a facet endpoint would need to be added (mirrors the
  Issue/Task pattern).
- **No Kanban board endpoint** (`GET /quotations/quotations/board/`) despite
  the list UI showing a List/Kanban toggle. `kanban` isn't seeded in
  `_CARD_SEED_MAP` for `quotation` (see `docs/apis/org-view-settings-api.md`
  coverage matrix, footnote ¹) — only `mobile` has a card seed today.
- **`ITEMS`/`OWNER`/`ACTIVITY` list columns** shown in the screenshot aren't
  in the **list** schema seed (only **detail** was extended by this fix) —
  `line_items`/`owner` currently only surface as detail columns. Extending
  the list seed (and `QuotationListSerializer`, which already has its own
  `get_owner`) would be a follow-up if the list table needs them natively
  rather than assembled client-side.
- **No `customer_name`/company field on Quotation** — the "Company" block on
  detail depends on the separate `customer` FK + a follow-up call to the
  Customer endpoint; there's no denormalized name on the quote itself.

---

## Quick reference

| Purpose | Method & Path |
| :------ | :------------ |
| Quote list columns | `GET /api/v1/quotations/quotations/schema/?view_type=list` |
| Quote detail fields | `GET /api/v1/quotations/quotations/schema/?view_type=detail` |
| **Quote detail record** | `GET /api/v1/quotations/quotations/{quotation_id}/` (detail-trimmed) |
| Quote detail — change status | `PATCH /api/v1/quotations/quotations/{quotation_id}/` `{ "status_id": "<id>" }` |
| Quote detail — reassign owner | `PATCH /api/v1/quotations/quotations/{quotation_id}/` `{ "owner_id": "<user_id>" }` |
| **Render HTML** | `GET /api/v1/quotations/quotations/{quotation_id}/render/?output=html` |
| **Render/download PDF** | `GET /api/v1/quotations/quotations/{quotation_id}/render/?output=pdf` |
| Org quote statuses (CRUD) | `/api/v1/quotations/statuses/` |
| List/create quotes | `/api/v1/quotations/quotations/` |
| Edit quote columns (admin) | `GET/PUT /api/v1/management/org-field-config/` (`model_name=quotation`) |
| Backfill existing orgs | `python manage.py backfill_quotation_detail_config --all` |
