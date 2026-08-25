# Products & Services — Admin Panel API Guide

This document covers the endpoints backing the **Catalog → Products & Services**
screen: the product list with category chips, the Products/Packages toggle, the
filter drawer (Category / Status / Price / Last updated), the Add-product modal,
and the row actions (view / edit / delete).

All routes are under `/api/v1/crm/`. Auth: authenticated user (JWT). Record
visibility follows RBAC (`view_product` + record-level scoping — see
`access_control`).

**Code:** views `crm/views/product.py`; serializers `crm/serializers/product.py`;
filters `crm/filters/product.py`; models `crm/models/product.py`; package pricing
`crm/services/package_pricing.py`.
**Tests:** `crm/tests/test_packages.py`, `test_product_filter.py`,
`test_product_bulk.py`, `test_product_type_crud.py`, `test_package_discount_gst.py`.

> **Read the schema endpoint first.** Like Leads, the product table is rendered
> from `GET /products/schema/` — column order, labels and visibility come from
> the org's View Settings, not a hardcoded client layout. Fetch and cache it
> before the list.

> **One catalog, two item types.** The **Products / Packages** toggle in the
> header is `?item_type=product` vs `?item_type=package` on the *same*
> endpoint — not a separate resource. Omit the param for the combined list.

---

## Endpoint index

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/products/schema/` | Field catalog + column config. Fetch first. |
| `GET` | `/products/` | The table. |
| `POST` | `/products/` | **Add product** modal. |
| `GET` | `/products/{product_id}/` | Row "view" (eye icon). |
| `PATCH`/`PUT` | `/products/{product_id}/` | Row "edit" (pencil). |
| `DELETE` | `/products/{product_id}/` | Row "delete" (bin). |
| `GET` | `/products/{product_id}/usage/` | Where a product is used (leads + quotes). |
| `POST` | `/products/bulk-activate/` | Checkbox column → Activate. |
| `POST` | `/products/bulk-deactivate/` | Checkbox column → Deactivate. |
| `POST`/`DELETE` | `/products/bulk-delete/` | Checkbox column → Delete. |
| `GET` `POST` | `/product-types/` | The **Category** chips + dropdown. |
| `GET` `PATCH` `DELETE` | `/product-types/{product_type_id}/` | Category admin. |

**Permissions:** `view_product` (list, retrieve, schema, usage),
`create_product`, `update_product` (incl. bulk activate/deactivate),
`delete_product` (incl. bulk delete). Product **types** reuse the same
`product` resource codenames — there is no separate category permission.

---

## 1. Product schema — `GET /products/schema/`

```
GET /api/v1/crm/products/schema/?view_type=list
GET /api/v1/crm/products/schema/?view_type=detail   # also backs the add/edit modal
```

Permission: `view_product`. Same `build_view_schema` contract as
[leads.md §1](leads.md) — `fields`, `custom_field_definitions`, `all_fields.columns`
with `order`/`visible`/`is_fixed`.

Products participate in the canonical custom-field system (§4) under the
**`product`** schema — its own field set, independent of `lead`. Sortable
Date/Number custom fields are slot-backed (`c_date_1/2`, `c_num_1/2`); the rest
live in the `custom_fields` JSON column.

Always read-only, never in the form: `id`, `product_id`, `organization`,
`owner`, `created_by`, `modified_by`, `created_at`, `updated_at`, `image_url`,
`image_path`. `product_name` is excluded from the *form* field list because the
modal renders it explicitly as the first input.

Mandatory columns — always returned regardless of config:
`product_id`, `product_name`, `product_type_name`.

---

## 2. Product list — `GET /products/`

```
GET /api/v1/crm/products/?page=1&page_size=20
```

Standard page-number pagination (`page_size` default 100, max 200):

```json
{ "count": 24, "next": "…?page=2", "previous": null, "results": [ /* Product objects */ ] }
```

### Product object shape

`ProductSerializer` uses `fields = "__all__"`, so every model column is present.
The ones the table actually binds:

| Field | Type | Notes |
| :--- | :--- | :--- |
| `product_id` | uuid | The id used everywhere. **Not** `id`. |
| `item_type` | `product` \| `package` | **Immutable after create.** |
| `product_name` | string (≤140) | The row title. Unique per org, **case-insensitive**. |
| `product_code` | string (≤140) \| null | The `PRD-NEXOCR-9AF0` subtitle. Unique per org (exact-match). |
| `product_type` | uuid \| null | Category FK — the write value. |
| `product_type_name` | string \| null | Category **label** — the read value for the chip. `null` when uncategorised. |
| `description` | string \| null | |
| `price` | decimal(18,6) | The `₹4,999` figure. For packages this is **derived** — see §7. |
| `currency` | string(3) | Defaults `INR`. The modal locks this field. |
| `tax_rate` | decimal(5,2) | The `0% GST` line. Defaults **0**; allowed values `0, 5, 12, 18, 28`. |
| `hsn_sac` | string(≤20) \| null | HSN/SAC code. **Not** covered by `?search=` — see the note below the filter table. |
| `billing_unit` | string(≤64) \| null | Free label ("per package", "per sq.ft."). |
| `is_active` | bool | The Active/Inactive pill. |
| `image_url` | url \| null | Read-only; set by uploading `image`. |
| `custom_fields` | object | Per-org custom fields. |
| `created_at` / `updated_at` | datetime | `updated_at` backs the "Last updated" filter. |

**Packages additionally carry** `components`, `adjustments` and six computed
totals (§7). **Plain products never expose `components`/`adjustments`** — the
serializer strips them, so don't branch on "key missing" meaning "empty".

Three fields are **stubbed at zero/null pending the quote↔product link** and are
present only for shape: `deals_count` (always `0`), `lifetime_revenue` (`null`),
`avg_per_deal` (`null`). Don't build UI that implies these are real yet.

### Filtering (`ProductFilter`)

The filter drawer maps to these params:

| Drawer control | Param | Values |
| :--- | :--- | :--- |
| **Category** checkboxes | `product_type` / `product_type__in` | `product_type_id` uuid(s) |
| **Status** Active/Inactive | `is_active` | `true` / `false` |
| **Price** buckets | `price_range` | `lt_10000`, `10000_to_50000`, `50000_to_100000`, `gt_100000` |
| **Last updated** | `last_updated` | `today`, `this_week`, `this_month` |
| Products/Packages toggle | `item_type` | `product`, `package` |
| Search box | `search` | icontains across `product_name`, `product_code`, `description`, and the category's `type_name` |

> ⚠️ **The search box placeholder says "Search products, code, HSN.." but
> `search` does NOT cover `hsn_sac`.** Typing an HSN code returns nothing.
> Either drop "HSN" from the placeholder, search HSN separately via
> `?hsn_sac__icontains=`, or ask for `hsn_sac` to be added to
> `ProductFilter.filter_search`. The auto-generated `hsn_sac`,
> `hsn_sac__icontains` and `hsn_sac__in` params do exist and work.

**`price_range` is multi-select and ORs the buckets**: send it repeated
(`?price_range=lt_10000&price_range=gt_100000`) to get "under ₹10,000 **or**
over ₹1,00,000". The buckets are inclusive at their shared edges
(`10000_to_50000` is `>= 10000 AND <= 50000`), so ₹50,000 matches **both**
adjacent buckets — harmless when OR-ing, but don't present them as a partition.

Beyond those, `ProductFilter` auto-generates a filter per model field
(`_build_model_filters`, depth 1), so every column is filterable by convention:

* text → `field`, `field__icontains`, `field__in`
* uuid → `field`, `field__in`
* bool → `field`
* number → `field`, `field__min`, `field__max`, `field__in`
* date/datetime → `field`, `field__after`, `field__before`, `field__in`

So `?price__min=1000&price__max=5000` and `?updated_at__after=2026-08-01` work
without being declared explicitly. Custom fields filter via
`?custom_fields.<name>=value` and sort via `?ordering=custom_fields.<name>`.

> ⚠️ **No `__not` negation params.** Unlike Leads and Issues, `ProductFilter`
> has no `__not` variants. If the drawer grows an "is not" toggle it needs
> backend work first.

---

## 3. Create product — `POST /products/`

Backs the **Add product** modal. Accepts `application/json` **or**
`multipart/form-data` (the latter to attach `image`).

```jsonc
{
  "product_name": "Reception joinery",     // required, ≤140, unique per org (case-insensitive)
  "product_code": "JN-RECEP",              // optional, unique per org (exact)
  "hsn_sac": "940360",
  "product_type": "<product_type_id uuid>",// the Category dropdown; omit → "Uncategorized"
  "billing_unit": "per package",
  "price": 320000,
  "tax_rate": 18,                          // one of 0, 5, 12, 18, 28
  "description": "What this product covers…",
  "is_active": true,
  "image": "<binary, multipart only>"
}
```

`organization`, `owner`, `created_by`, `modified_by`, `image_url` and
`image_path` are stamped server-side — do not send them. `currency` defaults to
`INR` (the modal shows it locked).

**Validation → 400**

| Rule | Response |
| :--- | :--- |
| Duplicate name (case-insensitive, per org) | `{"product_name": "A product named \"X\" already exists in your organization."}` |
| Duplicate code (exact, per org) | `{"product_code": "A product with code \"X\" already exists in your organization."}` |
| `tax_rate` not in {0,5,12,18,28} | `{"tax_rate": "tax_rate must be one of 0, 5, 12, 18, 28."}` |

The modal's note — *"Editing a price won't change existing quotes"* — is
accurate: quotes snapshot product name and price at generation time, so a later
price edit does not retro-change issued quotes.

Images upload to Bunny CDN under `Organizations/{org}/products/`; filenames are
sanitised and prefixed with random hex. Replacing an image deletes the old CDN
object first.

---

## 4. Retrieve / update / delete

* `GET /products/{product_id}/` — full object. Packages expand `components`,
  `adjustments` and totals.
* `PATCH /products/{product_id}/` — any writable field. Re-runs the uniqueness
  checks (excluding the row itself).
  **`item_type` cannot be changed** → `400 {"item_type": "item_type cannot be changed after creation."}`
* `DELETE /products/{product_id}/` — `204`, and best-effort CDN image cleanup.

**Delete is blocked when the product is a package component** (FK is `PROTECT`).
Rather than a 500, you get a `400` naming the blocking packages:

```jsonc
{
  "detail": "Cannot delete this product because it is used in one or more packages.",
  "packages": ["<product_id>", "…"]
}
```

Note the asymmetry: a product referenced by **leads or customers** deletes fine
via this endpoint (those FKs are `SET_NULL`) — only `bulk-delete` skips those.
See §6.

---

## 5. Usage — `GET /products/{product_id}/usage/`

"Where is this product used?" — backs the view (eye) action.

```jsonc
{
  "leads_count": 3,
  "leads":  [ { "lead_id": "…", "lead_name": "…", "first_name": "…", "last_name": "…",
                "email": "…", "status": "Negotiation", "created_at": "…" } ],
  "quotes_count": 2,
  "quotes": [ { "quotation_id": "…", "quotation_number": "QT-0007", "quotation_title": "…",
                "total_amount": "125000.00", "currency": "INR", "status": "Sent", "created_at": "…" } ]
}
```

> ⚠️ **Unpaginated.** Both arrays return every matching row. For a catalog
> staple linked to thousands of leads this is a large response — render it in a
> modal with client-side windowing, and expect it to be slow on hot products.
> `status` is a display **name**, `null` when unset.

---

## 6. Bulk actions (checkbox column)

All take `{"product_ids": ["<uuid>", …]}`. Missing or non-list → `400`.
Targets resolve through the permission-scoped queryset, so ids the caller
cannot see are reported back rather than acted on.

**`POST /products/bulk-activate/`** and **`POST /products/bulk-deactivate/`**

```jsonc
{ "success": true, "updated": 8, "is_active": true, "missing_ids": ["…"] }
```

These use a queryset `.update()`, so model `save()` does **not** run. If *no*
id matches, you get `400 {"product_ids": "No valid products found."}` — not a
zero-update success.

**`POST /products/bulk-delete/`** (also accepts `DELETE`)

Skip-referenced delete: a product referenced by any **lead**, **customer**, or
**package** is skipped with a reason rather than deleted.

```jsonc
{
  "success": true,
  "deleted": 2,
  "deleted_ids": ["…", "…"],
  "skipped": [ { "product_id": "…", "reason": "referenced by leads; referenced by packages" } ],
  "missing_ids": ["…"]
}
```

> **`success` is `true` even when everything was skipped.** It reports "the
> request was processed", not "your products are gone". Drive the UI off
> `deleted` / `skipped`, and surface `reason` — otherwise a user sees a success
> toast and an unchanged table.

Note the deliberate inconsistency with single delete (§4): lead/customer
references **block** here but **allow** there. Bulk is the cautious path
(losing linkage silently across many rows is worse than skipping); single
delete is the explicit one.

---

## 7. Packages

A package is a `Product` with `item_type="package"`, assembled from
`components` (which must be plain products) plus optional `adjustments`.

```jsonc
{
  "product_id": "…",
  "item_type": "package",
  "product_name": "Starter Bundle",
  "components": [
    { "package_component_id": "…", "component_product": "<product_id>",
      "product_name": "NexoCRM Pro", "product_code": "PRD-NEXOCR-9AF0",
      "billing_unit": "per seat", "quantity": 2, "position": 0,
      // priced live off the component product, not snapshotted:
      "unit_price": "4999.000000", "tax_rate": "18.00",
      "line_excl": "9998.00", "line_incl": "11797.64" }
  ],
  "adjustments": [
    { "package_adjustment_id": "…", "adjustment_type": "bundle_discount",
      "label": "Launch offer", "amount": "5000.00", "tax_rate": "0.00",
      "position": 0, "sign": -1, "amount_incl": "-5000.00" }
  ],
  "components_subtotal_excl": "9998.00",
  "components_subtotal_incl": "11797.64",
  "adjustments_total_excl":   "-5000.00",
  "adjustments_total_incl":   "-5000.00",
  "computed_total_excl":      "4998.00",
  "computed_total_incl":      "6797.64"
}
```

All six totals are **strings** (money, as elsewhere in this API). Adjustment
types: `service_charge`, `margin`, `misc_cost`, `bundle_discount`. `amount` is
stored **positive**; `sign` is derived from the type (discounts are `-1`).

**Rules enforced on write (all `400`):**

| Rule | Message key |
| :--- | :--- |
| Components/adjustments on a non-package | `components` — "Only packages can have components or adjustments." |
| A component that is itself a package | `components` — nested packages not allowed |
| A component from another org | `components` |
| A package containing itself | `components` |
| Duplicate component | `components` |
| `quantity < 1` | `components` |
| Active package with **zero** components | `components` — "An active package must have at least one component." |
| `bundle_discount` with non-zero `tax_rate` | `adjustments` — discounts carry no GST |
| `percent` key in an adjustment | `adjustments` — "use amount (flat ₹, excl GST)" |

**Derived pricing.** After any write, `price` is recomputed from the
composition (`computed_total_excl`) and saved. **Sending `price` on a package is
pointless** — it will be overwritten. Editing a component product's price does
*not* retro-update the package until the package itself is next saved.

**Replace-wholesale semantics.** Omitting `components`/`adjustments` leaves the
existing set untouched; sending `[]` clears it. Adjustments have no natural key,
so the whole set is deleted and re-created on every write — their
`package_adjustment_id`s change.

---

## 8. Categories — `/product-types/`

The chip row (`All / SaaS Platform / Mobile App / …`) and the modal's Category
dropdown.

| Field | Notes |
| :--- | :--- |
| `product_type_id` | uuid — the value `product_type` filters take |
| `type_name` | Unique per org, **case-insensitive** |

Duplicate name → `400 {"type_name": "A product type named \"X\" already exists in your organization."}`.

Deleting a type in use is blocked (`PROTECT`) with a `400` listing the blockers:

```jsonc
{ "detail": "Product type is in use.", "products": [ { "product_id": "…", "product_name": "…" } ] }
```

"Uncategorized" in the modal is **not a real type** — it is `product_type: null`.
Products with no type show `product_type_name: null`; the `All` chip is simply
the unfiltered list.

The list is paginated like everything else — pass `page_size` if you need every
category in one call to build the chip row.

---

## Notes for the frontend

* **`product_id`, not `id`**, in every path and payload.
* **Money is a string** on package totals (`"4998.00"`); `price` itself is a
  decimal with 6 dp — format, don't compare as floats.
* **`tax_rate` defaults to 0**, which is why every row shows `0% GST`. The
  modal's `18%` default is a *client-side* default; the backend does not
  assume one.
* **Uniqueness is case-insensitive on names, case-sensitive on codes.**
  "nexocrm pro" collides with "NexoCRM Pro"; `prd-001` and `PRD-001` do not.
* **`item_type` is set once.** The Add-product modal must decide product vs
  package up front — there is no later conversion.
* **Packages hide nothing when empty**: a plain product has *no*
  `components` key at all, rather than an empty array.

## Known gaps

1. **No `__not` filters** — no "is not" toggle is supported on any facet (§2).
2. **`search` doesn't cover HSN** despite the search box promising it (§2).
3. **`usage/` is unpaginated** and returns full lead/quote lists (§5).
4. **`deals_count` / `lifetime_revenue` / `avg_per_deal` are stubs** (`0`/`null`)
   pending the quote↔product link (§2).
5. **`bulk-activate`/`bulk-deactivate` bypass `save()`** (queryset update), so
   any future `Product.save()` side-effect will not fire for bulk paths (§6).
6. **Single delete and bulk delete disagree** on lead/customer references —
   bulk skips, single allows (§4/§6).
7. **No board/kanban endpoint** for products, unlike Leads and Issues.
