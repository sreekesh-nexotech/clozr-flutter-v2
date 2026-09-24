# Accounting-Readiness Backend Change — Flutter App Impact & Fix Plan

**Date:** 21 September 2026
**Source document:** `docs-flutter/NexoCRM_Accounting_Change_Document.pdf`
**App version:** 1.0.0+7 · `com.nexotech.clozrapp` · Flutter 3.24.5 (pinned)
**Backend audited:** `https://dev.clozr.tech` — change is **deployed** and verified live
**Method:** full-codebase review across four parallel audits, every finding cross-checked against real API responses from the Acme seed org
**Status:** report only — **no code was changed**

---

## How to read this

Every issue below is classified on two axes:

| Tag | Meaning |
|---|---|
| **LIVE** | Wrong on screen **right now**, today, in production |
| **ARMED** | Code is wrong but the trigger hasn't been pulled yet — fires the first time anyone uses the new field |
| **GO-LIVE** | Breaks when the accounting module is switched on |
| **GAP** | Missing UI for a capability the backend now offers |
| **PRE-EXISTING** | Real defect found during the audit, **not caused by this change** |

Priority = severity × likelihood. Work top-down.

---

## Executive summary

The backend change is backward-compatible **by design** and the app's mappers are defensive — nothing crashes, no screen fails to load, no data is lost. That is the good news and it is genuine.

But "doesn't crash" is not "correct". Two things are **wrong on screen today**, and several more are one user-action away.

**The headline:** every quote line in the app displays **"Qty 1"**, regardless of the real quantity. In the seed org, **22 of 29 line items (76%)** have a quantity other than 1 — including lines of 250 and 500 units. This is a money screen showing a number that is simply false.

### Priority table

| # | Issue | Tag | Severity | Effort |
|---|---|---|---|---|
| 1 | Quote lines all show "Qty 1" | LIVE | 🔴 Critical | S |
| 2 | Add Product rejects any non-numeric HSN/SAC | LIVE | 🔴 Critical | S |
| 3 | Totals stop reconciling once TDS is recorded | ARMED | 🔴 Critical | M |
| 4 | Settled instalment shows cash, not contracted amount | ARMED | 🔴 Critical | M |
| 5 | New-quote form silently posts qty 1 for "2.5" | LIVE | 🟠 High | S |
| 6 | Quote lines created with no `product_id` | LIVE | 🟠 High | S |
| 7 | "Tax Invoice" appears in the quote template picker | GO-LIVE | 🟠 High | S |
| 8 | Accountant role gets an empty, unusable app | GO-LIVE | 🟠 High | M |
| 9 | Mark-as-paid cannot record TDS or bank charge | GAP | 🟠 High | M |
| 10 | 409 accounting-veto is parsed only by luck | GO-LIVE | 🟡 Medium | S |
| 11 | Tickets cannot be marked billable | GAP | 🟡 Medium | M |
| 12 | 12% / 28% GST deprecation never surfaced | GAP | 🟡 Medium | S |
| 14 | GST states lookup not wired | GAP | 🟡 Medium | M |
| 15 | `line_discount` ignored — line maths looks wrong | ARMED | 🟡 Medium | S |
| 16 | "TAX-FREE" label becomes a lie | GO-LIVE | 🟡 Medium | S |
| 17 | `tax_rate` fallback maths will diverge | GO-LIVE | 🟡 Medium | S |
| 18 | Project financials / quotation link unbuilt | GAP | 🟡 Medium | M |
| 13 | `supply_nature` — **blocked on backend** | GAP | 🟢 Low | S |
| 19–27 | Smaller items | mixed | 🟢 Low | S |
| **P1–P6** | **Pre-existing defects found in passing** | PRE-EXISTING | 🔴–🟢 | mixed |

---

# 🔴 CRITICAL

## 1. Every quote line displays "Qty 1" — LIVE

**Files:** `lib/features/crm/infrastructure/data_sources/remote/quotes_remote_ds.dart:262` and `:309`
**Renders at:** `lib/features/crm/presentation/screens/quote_detail_screen.dart:456`

### What changed
`quantity` now supports fractional values, and the serializer returns it as a **decimal string**. Verified live:

```
"quantity": "1.000"      <- a String, not a number
"line_discount": "0.00"  <- also a String
"line_no": 0             <- an int
```

### Why it breaks

```dart
final qty = _int(m['quantity']) ?? _int(m['qty']) ?? 1;   // :262
int? _int(Object? v) => v is num ? v.toInt() : null;      // :309
```

`'1.000' is num` → `false` → `_int` returns `null`. There is no `qty` key. So `?? 1` fires **for every line on every quote**.

This is **not** a crash and **not** a dropped line — the `try/catch` is never entered. It is a silently wrong number.

### Real impact, measured

I checked 29 line items across 12 quotes on the seed org. **22 (76%) have a quantity other than 1:**

| Quote | Line | Real qty | Shown | Line total |
|---|---|---|---|---|
| QTN-00055 | product 01 | **250** | Qty 1 | ₹37,500 |
| QTN-00053 | product 01ABC | **500** | Qty 1 | ₹75,000 |
| QTN-00053 | Analytics Add-on | **25** | Qty 1 | ₹1,99,975 |
| QTN-00055 | NexoCRM Starter | **35** | Qty 1 | ₹52,465 |
| QTN-00058 | NexoCRM Pro | **3** | Qty 1 | ₹14,997 |

A rep opens QTN-00055 and sees `Qty 1 · ₹150` next to an amount of `₹37,500`. The quantity and the rate do not multiply to the amount beside them.

**The money itself is correct** — `total_price` goes through `parseAmount`, which handles decimal strings properly. Only the displayed quantity is wrong. But on a money screen that is a credibility failure, which is why this is Critical rather than Medium.

### Detailed fix

1. **Add a decimal-tolerant parser** next to `_int` in `quotes_remote_ds.dart:309`:
   - Accept `num` → `.toDouble()`; accept `String` → `double.tryParse`; otherwise `null`.
   - **Do not reuse `parseAmount`** — it returns `0` for unparseable input, and a quantity of 0 is a worse lie than 1. Keep `null` meaning "unknown" so the `?? 1` fallback still applies.
   - A parsed `"0.000"` must render as `0`, *not* fall back to 1 — so distinguish "unparseable" from "parsed as zero".
2. **Change the entity type** — `QuoteItem.qty` in `lib/features/crm/domain/entities/quote.dart:6` from `int` to `double`. Update the const constructor (`:18-24`) and `props` (`:27`).
3. **Add a display formatter** so `1.000` renders `1` and `2.500` renders `2.5`, never `1.0`. `lib/features/crm/application/record_rows.dart:181-185` already implements exactly this trailing-`.0` strip — hoist it into `lib/core/utils/inr_format.dart` as a shared `formatQty` rather than writing a second copy.
4. **Update the render site** at `quote_detail_screen.dart:456` (`'Qty ${it.qty} · ${it.rate}'`) to use the formatter.
5. **Fix the latent fallback** at `quotes_remote_ds.dart:271`: `amt = amtRaw != null ? parseAmount(amtRaw) : rate * qty`. If a deployment ever omits `total_price`, the line amount becomes `rate × 1` and the card under-reports by the whole quantity factor. With `qty` a real double this self-heals.
6. **Mock data** — `lib/features/crm/infrastructure/data_sources/local/quotes_mock_ds.dart:10-25` has ~20 `QuoteItem(qty: N)` int literals. Dart coerces int literals to double in a `double` parameter, so this likely compiles untouched — verify.

**Edge cases:** `quantity` may arrive as a JSON *number* on another deployment, so keep the `is num` branch. Negative quantities should render as-is, not be clamped.

---

## 2. Add Product now fails on any non-numeric HSN/SAC — LIVE

**File:** `lib/features/crm/presentation/components/add_product_sheet.dart:331` (input), `:253` (payload)

### What changed
`hsn_sac` is now format-validated server-side. I probed the live API to get the **exact rule**:

```
POST /api/v1/crm/products/  {"hsn_sac": "HSN940360"}
-> 400 {"hsn_sac": ["hsn_sac must be 4 to 8 digits when set."]}
```

| Input | Result |
|---|---|
| `940360` | ✅ accepted |
| `9403` | ✅ accepted |
| `HSN940360` | ❌ rejected |
| `n/a` | ❌ rejected |
| `940 360` | ❌ rejected |
| `-` | ❌ rejected |

**The rule is any 4–8 digits.** Note this is *more permissive* than {4,6,8} — a client validator stricter than the server would block valid codes, which is worse than the bug.

### Why it breaks
The field is unvalidated free text:

```dart
_field('HSN / SAC code', _hsn, 'e.g. 940360')       // :331 — no `number: true`
'hsn_sac': _hsn.text.trim(),                         // :253 — posted verbatim
```

`_field` only applies `TextInputType.number` + digits-only formatters when `number: true` is passed (`:654-687`). It isn't. So the user types anything, taps "Add product", and gets a raw DRF error toast on a save that worked before the change.

The same applies to the schema-driven twin at `lib/features/crm/presentation/components/lead_schema_form.dart:700-714`, where `hsn_sac` has no `choices`, falls to the `default:` branch, and renders as another free-text box.

**Mitigating:** the empty case is safe — `ProductsRemoteDataSource.createProduct` (`products_remote_ds.dart:115-125`) strips fields that trim to empty, so a blank HSN omits the key and still succeeds. And there is **no product edit form** (see #24), so create is the only exposure.

### Detailed fix

1. **Add a shared validator** in `lib/features/crm/application/product_form.dart` (already the pure, tested home for this sheet's rules):
   `bool isValidHsnSac(String v)` → strip whitespace, accept **empty** or `^\d{4,8}$`.
2. **Constrain the input** — change `:331` to `_field('HSN / SAC code', _hsn, 'e.g. 940360', number: true)`. That flips it to `TextInputType.number` with digits-only formatters in one edit. Add a `LengthLimitingTextInputFormatter(8)`.
3. **Guard the submit** — in `_submit()` (`:228`), before the `createProduct` call at `:246`, mirror the existing name check at `:234`: if non-empty and invalid, toast *"HSN/SAC must be 4 to 8 digits"* and return **without** setting `_saving`.
4. **Cover the schema path** — `_submitSchemaForm()` (`:201`) needs the same check on `form.payload['hsn_sac']`. Better: teach `LeadSchemaForm.validate()` (`lead_schema_form.dart:285-311`) a per-column rule keyed on `c.name == 'hsn_sac'` — that method already special-cases `mobile_no`, so the hook exists and every future schema form inherits it.

**Edge cases:** leading zeros must survive — keep it a `String`, never parse to int. Empty must stay allowed (the column is nullable). Trim before validating; `test/features/product_schema_test.dart:262-267` already asserts `'   '` is dropped.

---

## 3. Total / Paid / Balance stop reconciling once any TDS is recorded — ARMED

**File:** `lib/features/crm/presentation/screens/invoice_detail_screen.dart:114-115`, `:280-286`

### What changed
Per §B3, a record marked paid with `amount_paid` **plus** `tds_deducted` counts the TDS toward completion. **The cash figure and the settled figure now differ in the API.** Live today: `tds_deducted: '0.00'` on every record — so this is armed, not yet firing.

### Why it breaks
The header stat row pulls three numbers from three different fields and never reconciles them:

| Stat | Source | Meaning after the change |
|---|---|---|
| TOTAL | `total_amount` | gross |
| PAID | `summary.amount_paid` | **cash only** |
| BALANCE | `amount_remaining` | total − **settled** (cash + TDS) |

On a ₹1,00,000 instalment settled with ₹90,000 cash + ₹10,000 TDS the card reads **TOTAL ₹1L · PAID ₹90K · BALANCE ₹0** — three numbers that visibly don't add up, with nothing on screen explaining the ₹10,000. The app reads no TDS field anywhere (`grep tds_deducted` → zero hits in `lib/` and `test/`), so it cannot explain the gap even if it wanted to.

This fires the **first time any client** — web, API or import — settles a record with TDS.

### Detailed fix

1. Add `tdsNum` and `settledNum` to `InvoiceSummary` and `Invoice` (`lib/features/crm/domain/entities/invoice.dart`). Populate in `summaryFromApi` (`invoices_remote_ds.dart:62-73`) and `invoiceFromApi` (`:112-127`). If the plan exposes no settled aggregate, derive it as `totalNum - remainingNum` — that is the only self-consistent definition given `amount_remaining` drives completion — and treat `amount_paid` strictly as cash.
2. In `_headerCard`, render one consistent triple: **TOTAL**, **SETTLED** (= total − remaining), **BALANCE** (= remaining). Add a small secondary line under PAID reading e.g. *"₹90K cash · ₹10K TDS"*, shown **only** when `settled != cash`.
3. Prefer `summary.remainingNum` over `invoice.balance` when the summary has loaded, so PAID and BALANCE come from the same snapshot. Today PAID can come from the summary while BALANCE comes from an older list row — they can already disagree across a refresh.
4. Use `parseAmount` for every new field (it already handles decimal strings) — **not** `double.parse`.

**Edge cases:** summary null (mock mode, failed call) → fall back to the list row and hide the TDS line rather than guessing. Negative remaining (over-settlement) → clamp to 0 for display but don't hide it.

---

## 4. A settled instalment shows net cash, not its contracted amount — ARMED

**File:** `lib/features/crm/infrastructure/data_sources/remote/payments_remote_ds.dart:82-83`

```dart
final paidAmt = parseAmount(row['amount_paid']);
final amount = paidAmt > 0 ? paidAmt : parseAmount(row['amount_expected']);
```

Once a record is paid the displayed amount switches to **cash received**. With TDS withheld, a ₹1,00,000 instalment shows **₹90K** with a green "Paid" pill. Wrong in three places at once:

- the invoice-detail schedule row (`invoice_detail_screen.dart:518`)
- the Payments list card (`payment_card.dart:64`)
- the Payment detail header and Amount row (`payment_detail_screen.dart:185`, `:294`)

The schedule rows then sum to less than the invoice total, so anyone reconciling the page by hand finds a phantom shortfall.

### Detailed fix

1. Keep `amountNum` as the **gross/expected** figure (`amount_expected`, falling back to `amount_paid`). Add `paidCashNum`, `tdsNum`, `bankChargeNum`, `gstTdsNum`, `gstTcsNum` to `Payment` (`lib/features/crm/domain/entities/payment.dart`), all read via `parseAmount`.
2. Display gross as the row amount. On `payment_detail_screen._detailsCard` add rows "Received (cash)", "TDS deducted", "Bank charge" — shown only when non-zero.
3. ⚠️ **`allPaymentsProvider` (`payments_providers.dart:46-63`) rebuilds `Payment` field-by-field** for the optimistic paid override. Every new field must be copied there or it silently zeroes on settle. Strongly prefer adding a `copyWith` instead.
4. `payments_filter_spec.dart:135` filters on `amountNum` — switching to gross changes filter semantics. That is the correct direction; note it in the filter label.

---

# 🟠 HIGH

## 5. The new-quote form silently posts qty 1 when the user types "2.5" — LIVE

**File:** `lib/features/crm/presentation/screens/add_quote_screen.dart:148` (payload), `:290` (running total), `:709` (per-line total), `:676` (input)

Three separate places call `int.tryParse(line.qtyCtrl.text) ?? 1`. `int.tryParse('2.5')` → `null` → all three fall back to **1**. The line total, the quote total **and the POSTed quantity** are all 1×. The quote is created at 40% of the intended value with no error, no toast, no red field.

The backend now accepts fractional quantity — the only thing preventing it is the app. On iOS `TextInputType.number` shows a digits-only pad, so the user physically cannot type `.`.

Same fallback swallows other input: `''` → 1, `'0'` → 0 sent, `'-3'` → -3 sent. The submit guard at `:180-184` checks for a missing product but nothing checks quantity.

### Detailed fix

1. `lib/features/crm/application/quote_draft.dart:18` — change `QuoteDraftLine.quantity` from `int` to a decimal **string**, mirroring how `unitPrice` (`:22`) is already handled *for exactly this reason* ("the API takes decimals as strings, and round-tripping through a double loses paise"). `toJson()` (`:24-28`) then emits it directly. Alternative: keep a `double` and emit `toStringAsFixed(3)` — pick one, stay consistent with `unitPrice`.
2. `add_quote_screen.dart:676` — `keyboardType: const TextInputType.numberWithOptions(decimal: true)`, plus an `inputFormatters` entry allowing digits and at most one decimal point, max 3 decimal places (matching the server's `1.000`).
3. Replace all three `int.tryParse(...) ?? 1` with **one** private helper `double _qtyOf(_QuoteLine l)` using `double.tryParse`, called from `:148`, `:290` and `:709`. Today the same expression is duplicated three times — that is how a future fix in one place produces a preview that lies.
4. Add a submit guard in `_submit` (`:163-215`) beside the product guard: if any line's qty doesn't parse `> 0`, toast *"Every line needs a quantity greater than zero"* and return. **This is the piece that turns a silent 40%-value quote into a blocked save.**
5. `test/features/quote_create_test.dart:158-160` asserts `'quantity': 2` as an int — update to the chosen wire form.

**Edge case:** `_draft()` rebuilds on every keystroke for the running total, so the parser must not throw on partial input like `"2."`. Use `?? 0` for the *preview* (so a half-typed number reads ₹0 rather than jumping to 1×) but block at submit.

---

## 6. Quote lines are created with no `product_id`, so nothing tax-related is ever snapshotted — LIVE

**File:** `lib/features/crm/application/quote_draft.dart:24-28`, built at `add_quote_screen.dart:144-158`

The form **already has** the catalog product — `_QuoteLine.productId` at `:34` is a real product id, resolved at `:145`. But the payload is only `{description, quantity, unit_price}`. The new `product_id` write field is never sent.

Confirmed live: `product`, `hsn_sac`, `rate_pct`, `supply_nature`, `source_package` all come back `null`. For a mobile-created line they will **stay null forever**, because the snapshot happens at write time.

Consequences:
- **When accounting ships, every mobile-created quote line is un-invoiceable** — no HSN/SAC, no GST rate, no goods/service nature. Not retroactively fixable from the app, and it gets worse the longer it runs.
- **Package products don't explode.** The dropdown (`:648-656`) lists all active products including packages. Picking one on mobile writes a single opaque line; the same package on web writes component + adjustment lines. The two clients produce structurally different quotes.

**The money is right today** — `Product.priceNum` is the tax-exclusive `price`, and a package's `price` is server-derived from its composition, so the preview total matches either way. This is missing *structure*, not missing money.

### Detailed fix

1. Add `final String productId;` to `QuoteDraftLine` and emit `'product_id': productId` from `toJson()` when non-empty.
2. In `add_quote_screen.dart:144-158`, pass `productId: p.id` — `p` is already in scope from the pattern match at `:145`.
3. Keep sending `description` and `unit_price`; the backend has always required a description and `quote_create_test.dart:158` pins the shape.
4. **Handle explosion in the post-create UX.** `_submit` (`:205-207`) already invalidates `quotesProvider` / `leadQuotesProvider`, so the detail screen refetches and shows exploded lines. But the total the user saw on the form was a *single* package line while the created quote has N. Verify on dev that the exploded sum equals the package `price`; if not, switch the form preview to `composition.totalExcl`.
5. Org-scoping needs no extra work — the dropdown reads `productsProvider`, already org-scoped, so a foreign-org id is unreachable. `_submit`'s `on AppError` handler (`:211-215`) surfaces it readably if it ever happens.

---

## 7. "Tax Invoice" will appear in the quote template picker for every new org — GO-LIVE

**File:** `lib/features/crm/infrastructure/data_sources/remote/quotes_remote_ds.dart:130-154`; picker at `add_quote_screen.dart:359-370`

### ⚠️ First, a correction to the change document
The doc's path `/api/v1/quotations/quotation-templates/` **404s**. The real endpoint is `/quotations/templates/` — which is exactly what `api_endpoints.dart:96` already uses and `quote_create_test.dart:360` pins.

**The app's endpoint is correct. Do not "fix" it to the document's path.** `fetchTemplates` swallows every error (`:151-153` → `return const []`), so that regression would present as "the template chip row silently vanished" with no error anywhere.

### The actual problem
`fetchTemplates` sends `{page_size: 100, is_active: true}` and the mapper reads `template_id`, `template_name`/`name`, `is_default` — it **never reads `category`**. Every active template becomes a chip.

Verified live on the existing org: 5 templates returned, `?category=invoice` returns **0** — the backfill hasn't run, so Tax Invoice isn't seeded here. **For any org created from now on it is seeded**, and a sixth chip appears. Tapping it creates a quote whose `pdf_url` renders a GST tax-invoice layout populated from `hsn_sac`/`rate_pct` fields that are all null — a blank-tax "invoice" sent to a customer under a quote's cover.

### The filter direction matters

| template_name | category |
|---|---|
| Milestone Billing | `milestone` *(default)* |
| Subscription Proposal | `subscription` |
| Standard Quotation | `general` |
| Modern | `null` |
| Classic | `null` |

An **include** filter is wrong: `category == 'quote'` matches nothing, and `category != null` would hide Modern and Classic. It must be an **exclude**.

### Detailed fix
1. Add `final String? category;` to `QuoteTemplate` (`lib/features/crm/domain/repositories/quotes_repository.dart:51-60`), populated in the mapper (`quotes_remote_ds.dart:144-148`) from `row['category']` via the existing `_str` helper.
2. In `fetchTemplates`, after mapping, drop rows whose category lower-cases to `'invoice'`. **Filter client-side, not with a query param** — there is no documented "everything except invoice" server filter, and a wrong param name is silently ignored by DRF, giving you a filter that looks applied and isn't.
3. Use an explicit denylist constant `const _nonQuoteTemplateCategories = {'invoice'}` with a comment naming the change document, so when a deliberate invoice picker is wanted the one place to change is obvious.
4. Lower-case before comparing (`"Invoice"` is possible). Templates with `category == null` must be **kept**.

---

## 8. An Accountant / Finance Viewer user gets an empty, unusable app — GO-LIVE

**Files:** `lib/features/shell/domain/nav_catalog.dart:49-135`, `:166-178` · `lib/features/shell/presentation/app_drawer.dart:92-94` · `lib/features/dashboard/infrastructure/repositories/dashboard_api_repository.dart:32-41`

**Verified live:** all seven `acc_*` modules are **already returned** by `/auth/me/modules/` — `acc_setup`, `acc_document`, `acc_purchase`, `acc_settlement`, `acc_period`, `acc_journal`, `acc_report` (38 codenames total).

### Good news first
This causes **no crash and no visible change today**. `modules` is parsed into a plain `Map<String, ModulePermission>` (`module_access.dart:81-100`) — no enum, no `firstWhere`, no whitelist. There is **no `.byName(` anywhere in `lib/`**. Nothing iterates the server map to build UI: navigation is a static catalog (`nav_catalog.dart:49-135`) that asks the server for permission, never the reverse. The 7 new keys are silently ignored.

### The actual problem
A user whose grants are **only** `acc_*` fails `canAny` for all 11 `navCatalog` entries:

1. Drawer renders the "Menu" heading with **zero rows** beneath it.
2. `landingPathFor` matches nothing, falls through to `Routes.dashboard`.
3. Dashboard keeps the Business tab because `dashboardPanelModules['business'] = []` and `canAny([])` returns `true`.
4. Every `/crm/dashboard-new/*` call 403s; `dashboard_api_repository.dart:32` finds no section and no cache and throws.
5. **Final state: empty drawer + a full-screen "Forbidden" error with a Retry that can never succeed.** Only Logout works.

This triggers on **role assignment**, not on backend go-live.

### Detailed fix
1. Add an `accounting` `NavEntry` to `navCatalog` with `modules: ['acc_setup','acc_document','acc_purchase','acc_settlement','acc_period','acc_journal','acc_report']`. Until accounting screens exist, point `path` at `lib/core/widgets/placeholder_screen.dart` reading *"Accounting is available on the web app"* — a visible honest destination beats an empty menu. Register the route in `routes.dart` + `app_router.dart`.
2. Change `dashboardPanelModules['business']` from `[]` to `['dashboard']`. `canAny([])` returning true is what lands a user on a panel that 403s. This makes `visibleDashboardTabs` able to return empty — `dashboard_screen.dart:39` already handles that (`tabs.firstOrNull ?? 'business'`), and `landingPathFor` won't pick Dashboard once the accounting entry exists.
3. Keep everything null-safe on `access == null` (mock mode, failed fetch, first load). The existing fail-open idiom at `app_drawer.dart:53-54` covers it — **do not tighten it**.

---

## 9. Mark-as-paid cannot record TDS or bank charge — GAP

**File:** `payments_remote_ds.dart:43-54`; callers at `invoice_detail_screen.dart:465-484`, `payment_detail_screen.dart:144-166`, `record_payment_sheet.dart:133-178`

The PATCH sends exactly `{status: 'paid', amount_paid, paid_date, payment_method}`. None of `tds_deducted`, `bank_charge`, `bank_account_id`, `gateway_ref`, `treat_as`, `service_period_*`, `milestone_task`.

**Ordering is not a problem** — `status: 'paid'` travels in the same PATCH as the amounts, satisfying the "only accepted when paid" rule. There is no un-pay or delete flow in the app, so no reverse-ordering hazard.

**The consequence:** a user who received ₹90,000 net of ₹10,000 TDS has no way to say so. `amount_paid` is sent as the full gross, so the plan records ₹1,00,000 of cash that never arrived and the org's cash position is overstated. Nothing *looks* broken — the money is just wrong.

### Detailed fix
1. Add optional named params `tdsDeducted`, `bankCharge`, `gstTdsDeducted`, `gstTcsDeducted`, `bankAccountId`, `gatewayRef` through the chain: `PaymentsRemoteDataSource.markRecordPaid` → `PaymentsRepository.markRecordPaid` (`domain/repositories/payments_repository.dart:13-17`) → `PaymentsApiRepository` → `PaymentsRepositoryImpl` (mock no-op).
2. Send each only when non-null, formatted `toStringAsFixed(2)` like `amount_paid`.
3. In `record_payment_sheet.dart`, add a collapsible **"Deductions"** section in the settle branch with TDS and bank-charge fields. Drive `amount_paid` from `gross − tds − bankCharge`, or let the user enter cash received and derive TDS. Validate `>= 0` and `tds + charges <= gross`.
4. Keep the two one-tap paths ("Settle now", "Mark as paid") zero-friction; route through the sheet only when deductions are needed.

---

# 🟡 MEDIUM

## 10. The 409 accounting veto is parsed by accident, not design — GO-LIVE

**File:** `lib/core/network/app_error.dart:113-121`, `:137-167`

I traced the exact behaviour for `{"code":"ACCOUNTING_POSTING_REJECTED","cause":{…},"detail":"…","rule":"R7","next":"reopen_period"}`:

`_extractMessage` finds no `message` key, falls into the `['detail','error','non_field_errors']` loop at `:151` and **returns `detail`**. So the user **is** shown the backend's sentence in a red toast — not a blank, not "Something went wrong". That is the one genuinely good outcome here.

**But** `_typeForStatus(409)` has no branch → `AppErrorType.unknown`. So:
- No code can distinguish an accounting veto from a generic failure.
- `ErrorState.forError` titles it "Something went wrong".
- `code`, `rule`, `next` and `cause` are **all discarded** — the app can never act on `next: "reopen_period"` or explain rule R7.
- `sentry_dio` reports 5xx only, so these vetoes are **invisible in monitoring**.

### Detailed fix
1. Add `AppErrorType.conflict` and map `status == 409` in `_typeForStatus`. **Audit existing 409 consumers first** — `people_remote_ds.dart:255`, `roles_screen.dart:127-162`, `ops_tasks_remote_ds.dart:179`, `ops_task_detail_screen.dart:934` currently receive `unknown` and rely only on `message`; confirm none branch on `unknown`.
2. Add `final String? code;` and `final Map<String, dynamic>? extra;` (carrying `rule`, `next`, `cause`) to `AppError`, populated in `_fromResponse`. **Guard with `is String`** — the existing envelope sometimes puts an *int* status in `code` (`network_test.dart:107`).
3. Add `bool get isAccountingRejection => statusCode == 409 && code == 'ACCOUNTING_POSTING_REJECTED';`
4. At the three settle call sites, when `isAccountingRejection`, show a dismissible sheet rather than a 6-second toast — `detail` is a sentence plus a remedy, which a toast cannot carry. Keep the existing optimistic rollback (already correct at all three).
5. Give `ErrorState.forError` a `conflict` branch (lock icon, "Blocked by accounting").
6. Pin the exact `{code, cause, detail, rule, next}` shape in `test/core/network_test.dart`.

**Related (Low):** `_extractFieldErrors` (`:169-189`) skips only `detail|error|message|code|error_codes`, so `rule` and `next` become phantom field errors `{"rule":["R7"],"next":["reopen_period"]}`. Harmless today (nothing renders `fieldErrors`), but `_extractMessage` consults them as a last resort at `:158` — a future 409 without `detail` would show the user **"rule: R7"**. Add `cause`, `rule`, `next`, `next_action`, `hint` to the skip set.

---

## 11. Tickets cannot be marked billable — GAP (and it cannot break)

**Verified:** `grep -rni "billable" lib test` returns **zero hits**.

`TicketsRemoteDataSource.writePayload` (`tickets_remote_ds.dart:559-601`) is a strict **allow-list** — it builds a fresh map and copies only `subject`, `description`, `priority`, `channel`, `customer_id`, `issue_type`, `status_id`, `product_id`, `project_id`. Unknown keys are silently discarded. Both write paths go through it.

**Therefore the new "billable=true needs an amount or product, else 400" rule cannot fire from this app.** There is no combination of taps that produces an invalid billable row. This is a **gap, not a breakage** — an important distinction for planning.

Live API confirms the fields are present and safe: `billable: false`, `billable_amount: null`, `billable_product: null`, `billed_document_line_id: null`.

### Detailed fix (build before accounting ships)
1. **Entity** — add `billable` (bool, default false), `billableAmount` (keep as a decimal **string** to avoid float drift, mirroring `Quote`/`Invoice`), `billableAmountNum`, `billableProductId`, `billedDocumentLineId` to `lib/features/helpdesk/domain/entities/ticket.dart:89-119`. ⚠️ **Also add them to `Ticket.copyWith` at `:136-166`** — it enumerates every field by hand and will silently drop new ones.
2. **Read** — in `mapTicket` (`:383-435`) read all four, tolerating absent *and* null. The existing `_str` helper (`:439`) already returns null for non-strings.
3. **Write** — extend the allow-list. Copy the `product_id`/`project_id` pattern at `:591-599`, which distinguishes "absent" (leave alone) from "explicit null" (unlink) — exactly what `billable_product_id` needs. Reuse the `_uuidRe` check at `:571`/`:588` so a mock-mode non-UUID id is dropped rather than 400ing.
4. **Client-side guard, in the same change as the UI.** If the outgoing body sets `billable == true` with neither a non-null amount nor product, refuse locally. ⚠️ Careful with partial PATCH: the app may be turning `billable` on against a row that already has an amount server-side. Safest is a **UI-level guard in the edit screen**, where the current ticket's existing values are in hand, and to **always send `billable_amount` alongside `billable: true`** so the request is self-sufficient.
5. **UI** — a "Billing" block in `edit_ticket_screen.dart` (switch + amount + `pickTicketProduct` reuse) and a read-only row pair in `ticket_detail_screen.dart:450-467`. Show `billed_document_line_id` as a "Billed / Not yet billed" indicator only — server-set, never editable.
6. Org-scoping is already safe: `pickTicketProduct` (`ticket_form_fields.dart:200-221`) reads `productsProvider`, scoped to the logged-in org.

---

## 12. The 12% / 28% GST deprecation is never surfaced — GAP

`deprecated_rate` appears nowhere in `lib/` or `test/`. Worse, the app **actively offers** the deprecated rates: `add_product_sheet.dart:69` — `static const List<int> _gstOptions = [0, 5, 12, 18, 28];` — feeding both the built-in picker (`:372`) and the schema-driven `tax_rate` picker (`:186-187`).

**This is a clean gap with no accidental half-surface** — verified. The list serializer carries neither `tax_rate` nor `deprecated_rate`, so the response-driven product-card chips (`schema_columns.dart:64-88`, which iterate *list*-serializer keys) can never render a stray "Deprecated Rate" chip. And the detail Details card uses `recordRows`, which walks `schema.columns` rather than the payload, so it only appears if an admin adds the column deliberately.

**It can therefore only be built on the product detail screen** — the one screen whose `product.raw` comes from the detail endpoint (`product_detail_screen.dart:91-92`).

### Detailed fix
1. Add `final String? deprecatedRate;` to `Product` (`domain/entities/product.dart:64-87`), read `_str(row['deprecated_rate'])` in `productFromApi` (`products_remote_ds.dart:203-228`). Absent and null both → null; `_str` (`:324`) already does this, so it is a one-line read.
2. In `_pricingCard` (`product_detail_screen.dart:415-462`), when non-null render an amber banner under the "GST rate" row **using the server's own string**. Do not compose your own sentence and do not derive it from `product.gst` — the server owns the GST 2.0 rate list.
3. Write the null-check deliberately: on the list-row fallback path, "no warning" and "warning not loaded" look identical on screen.
4. Add `'deprecated_rate'` to `kProductDetailChromeColumns` (`product_columns.dart:38-65`) as cheap insurance against a duplicate row if an admin adds the column. A `kProductCardFrameColumns` entry is **not** needed — the field never reaches a card.
5. **Do not silently remove 12/28 from `_gstOptions`** — an org still legitimately selling at those rates would find the picker unable to express what they need, and the server still accepts them. Keep them with an inline "GST 2.0 deprecates this rate" note.

---

## 13. `supply_nature` — BLOCKED ON BACKEND, do not build yet 🟢 Low

**Verified live and exhaustively:** `supply_nature` is **absent from the product response entirely** — list *and* detail. It is also absent from the pre-change contract in `docs-flutter/docs-backend/products.md:99-110`, and there is no third product endpoint that could carry it (`/crm/product-types/` returns type ids only; `/crm/products/{id}/usage/` returns counts).

**The change document's "Req+Resp, LIVE NOW" is wrong for this field.**

Two consequences:

**(a) Do not build the picker yet.** You cannot verify the accepted value casing (`GOODS` vs `Goods`), cannot prefill an edit form, and cannot confirm the write is even accepted. Ask the backend to expose it on the detail serializer first.

**(b) The "required on create?" risk is effectively closed.** A field absent from the response is almost certainly not required on POST, and product creation demonstrably works today. Re-check the day it appears.

One thing to get right *when* it lands: if it appears in an org's schema without `choices`, `lead_schema_form.dart:612-617` renders it as a **free-text box** (a picker needs `_isTextChoice`), and whatever the user types is sent verbatim and rejected — precisely the failure the code's own comment at `:606-610` documents. Adding it to `_optionsByColumn` (step 1 below) defends against that unconditionally.

### Detailed fix — for when the field is exposed
1. Add `'supply_nature'` to `_optionsByColumn` in `add_product_sheet.dart:181-190`, beside the `tax_rate` entry that exists for this exact reason. Map `[CatalogOption(id:'GOODS',name:'Goods'), CatalogOption(id:'SERVICE',name:'Service')]`. `_choiceValue` resolves the picked **label** back to the stored **value**, so human labels are safe here (unlike `tax_rate`, which uses the value as the label because `schemaWriteValue` can't parse `"18%"`). This makes `_isTextChoice` true regardless of whether the server reports choices — defending against risk (b) unconditionally.
2. Add a "Nature of supply" segmented control next to the Billing unit picker (`:325-347`), defaulting to Goods for `item_type == 'product'`, Service otherwise. Send it at `:246-261`. Do this **even if optional** — the value drives GST treatment downstream, and letting the server guess is how the wrong tax lands on an invoice.
3. Add a read-only detail row — it renders automatically via `recordRows` once the org adds it to the layout, so the only work is to **not** add it to `kProductDetailChromeColumns`.

---

## 14. The GST states lookup is not wired — GAP

**Verified live:** `GET /api/v1/organizations/states/` returns **HTTP 200** with 38 rows of `{code, name, alpha}`.

The app has **no `/organizations/*` endpoint of any kind**. Zero hits for `state_code`, `place_of_supply`, `gst`, `igst`, `cgst`, `sgst`. There is no company-settings screen. The only org data is `OrgSummary` (id/name/is_primary) from `/auth/me/`.

This blocks the place-of-supply work in #16.

### Detailed fix — clone `countryCodesProvider`, an exact precedent
1. `api_endpoints.dart` — add `static const orgStates = '/organizations/states/';`
2. New `lib/core/models/gst_state.dart` — `{code, name, alpha}` with `fromJson`. **Store and send the 2-char NUMERIC `code`**; `alpha` ("KL") is display only. ⚠️ **Keep `code` a `String`, never an `int`** — leading zeros are significant (`"01"` = Jammu & Kashmir) and `int.parse` destroys them.
3. New `lib/core/network/providers/gst_states_provider.dart` — mirror `country_codes_provider.dart:18-30`. **`Paginated.fromAny` already handles a bare JSON array** (`paginated.dart:35-46`), which is what this endpoint returns — don't assume a DRF envelope.
4. **Do not ship a hardcoded 38-row fallback.** Fall back to empty with the picker disabled. (Unlike `countryCodesProvider`, whose `+91` default exists only because a phone field must have one.)
5. Reuse `lib/core/widgets/country_code_picker_sheet.dart` as the sheet template.

---

## 15. `line_discount` is ignored, so line maths looks wrong — ARMED

`line_discount` arrives as `'0.00'` and the mapper ignores it entirely — it cannot throw. But `total_price` is **net of the discount**, so once anyone sets a per-line discount the card shows `Qty 2 · ₹1,00,000` against an amount of `₹1,80,000` with no discount row. Combined with #1 (qty always 1) the row becomes doubly unreadable.

**Fix:** add `final double discount;` to `QuoteItem` (default 0), map via `parseAmount(m['line_discount'])` in `_items`. Render a sub-line only when `> 0`, e.g. `· −₹X off`. **Do not subtract it yourself** — `total_price` is already net, so recomputing double-counts.

**Edge case:** if the discount is ever a percentage rather than an absolute amount the label is wrong. The doc says "line total clamped ≥ 0", which reads as absolute — confirm against a real discounted quote before writing the label.

---

## 16. The "TAX-FREE" label becomes a lie for INCLUSIVE quotes — GO-LIVE

`quote_detail_screen.dart:487` hardcodes `'TOTAL · TAX-FREE'`; `add_quote_screen.dart:424` says *"Tax-free — product amounts only"*.

**Verified live:** `amounts_are` is **absent** from both the list and detail quote responses today, so no mapper can break and there is nothing to read. But these two labels are an **assertion about the money**, and once web-created quotes carry `amounts_are: "INCLUSIVE"` that assertion is false — the unit prices already contain GST, and a rep will quote ~18% too high.

**Fix:** don't build a tax UI yet (the field isn't in the payload). Instead:
1. Map `amounts_are` onto a nullable `Quote.amountsAre` when it appears.
2. Make the label conditional: TAX-FREE only while null or `EXCLUSIVE`; "TAX INCLUSIVE" otherwise.
3. Until then, add a code comment at `:434` and `:487` recording that the label is an assumption the backend can now contradict.

> ⚠️ **Verify before shipping anything here:** the server's default for `amounts_are` when the field is omitted on create. If it defaults to **INCLUSIVE**, this becomes **Critical immediately** — `Product.priceNum` is tax-*exclusive*, so every mobile-created quote would be stored ~18% light and the customer under-billed.

---

## 17. `tax_rate` fallback maths will diverge from the rate master — GO-LIVE

`products_remote_ds.dart:218-219`:
```dart
gstAmt: formatInr(serverGst ?? price * gst / 100),
gross:  formatInr(serverGross ?? price * (1 + gst / 100)),
```

**Today this is fine, and less urgent than it first looks.** The mapper already *prefers* the server's `gst_amount` / `price_incl` (`:171-174`), and **verified live: both the list and detail serializers carry both fields**, so `serverGst` / `serverGross` are always non-null and the `??` fallback at `:218-219` is effectively **dead code on this org**. It only wakes up if an org's view config drops those fields from the projection.

But the doc now says `tax_rate` is "**UI default only** — the effective GST rate is resolved by accounting's rate master later". Once the rate master can differ, that fallback prints a wrong gross with no signal it was computed rather than received.

**Fix:** add `final bool gstServerComputed;` (set to `serverGst != null`). When false, either suppress the GST amount / gross rows the way `gstKnown == false` already does (`product_detail_screen.dart:427-441` — the dash pattern is the right precedent), or label it "GST rate (indicative)". **Do not change the preference order at `:171-185`** — preferring server figures is already correct and is what makes this Medium rather than Critical. If you gate the card footer on the new flag, update `_hasFooter` (`product_card.dart:162-167`) too or you get an empty footer row.

**Verified clean:** quote line items do **not** use `tax_rate`. `add_quote_screen.dart:157` sends `priceNum`, and the running total at `:290` is `priceNum × qty` — tax-exclusive, server owns the tax. No quote money is at risk.

---

## 18. Project financials, quotation link and cost-centre are unbuilt — GAP

Four verified sub-answers, all reassuring:

- **(a) Does the app read the deprecated money columns? NO.** Zero hits in `lib/` for `total_costing_amount`, `total_purchase_cost`, `total_sales_amount`, `total_billable_amount`, `total_billed_amount`, `total_consumed_material_cost`, `gross_margin`, `per_gross_margin`, `cost_center`. `mapProject` reads exactly one money key — `estimated_costing` — which is **not** deprecated and stays writable.
- **(b) Does the app WRITE any now-read-only field? NO.** `projectWriteFields` (`project_write_fields.dart:57-87`) emits a closed set containing none of them. **No silent-ignore, no 400.** This was the biggest risk in the brief and it is clean.
- **(c) Is there a P&L / margin display that will silently go wrong? NO.** The Details tab shows seven rows, none of them a margin. When accounting takes over those columns, nothing in this app changes — it never showed them.
- **(d) Does the mapper tolerate `financials: null`? YES** — named-key reads only.

**Fix (new work, not a repair):**
1. When financials goes non-null, add a nested `ProjectFinancials` value object, `final ProjectFinancials? financials`, so "accounting not on yet" stays distinguishable from "zero". Mirror the `_cost` precedent (`projects_remote_ds.dart:296-302`): an **unset** amount renders blank, not "₹0". Parse via `parseAmount`. The block must survive `?view=list`, which will keep omitting it.
2. `project_write_fields.dart` — add `if (quotationId != null) 'quotation': quotationId`. Backend validates same-org **and same-customer**, so the picker must filter by the selected customer and be **cleared whenever the customer changes**, or the save 400s on a stale link the user can't see. Hide the field entirely for internal projects (`customer == null`).
3. Add a "Linked quotation" picker row after the Customer row in `create_project_screen.dart:197-215`, disabled until a customer is chosen.
4. ⚠️ Any new field must go into **both** `_toJson` and `_fromJson` in `projects_api_repository.dart:79-136` — see **P4**, where exactly this was forgotten.

---

# 🟢 LOW

**19. Line order ignores `line_no`.** `_items` (`quotes_remote_ds.dart:259-280`) appends in payload order and never sorts. Fine today, but once package explosion produces component + adjustment lines, ordering becomes the server's business. Read `line_no` and sort by it — use a **stable** sort, since every value is `0` today and sorting on an all-zero key must not reshuffle.

**20. Per-line rupee rounding drifts.** `amtNum: amt.round()` (`:277`) then summed at `quote_detail_screen.dart:446` — a sum-of-rounded, not a round-of-sum. Once `line_discount` produces paise, the detail subtotal can differ from the list card's `total_amount` by a few rupees. Carry the line total as a `double` and round only at the formatter.

**21. A plan settled entirely by TDS reads "Unpaid".** `status_keys.dart:158-165` falls back to `amountPaid > 0 ? 'partial' : 'unpaid'`. With cash ₹0 but TDS settling part of the plan, the pill says Unpaid beside a non-zero settled figure. Pass the settled figure (from #3) instead of `amount_paid` at `invoices_remote_ds.dart:126` and `invoice_detail_screen.dart:122`.

**22. `invoice_id` removal — smaller risk than it first appears.** Exactly one read exists: `payments_remote_ds.dart:93` — `invId: _str(row['quotation_number']) ?? _str(row['invoice_id'])`. **Verified live:** the record carries **both** `quotation_number` *and* a `payment` FK, so the fallback is effectively dead code. The app never reads `invoice_id` from the plan detail (which no longer exposes it) — that path renders raw through `recordRows`, so the list/detail inconsistency is cosmetic at worst. **Fix defensively now:** drop the fallback, add `planUuid` read from `row['payment']` (the durable non-deprecated FK), and make `paymentsForInvoiceProvider` (`payments_providers.dart:79-82`) match `planUuid` first. Copy `planUuid` in `allPaymentsProvider`'s field-by-field rebuild (`:46-63`) or it vanishes on optimistic settle. Replace the test at `finance_mappers_test.dart:358-363`.

**23. Accounting vetoes are invisible to monitoring.** `api_service.dart:56-65` reports 5xx only. A 409 rollback is a *systemic* refusal, not user error — you will want its rate after go-live. Add a Sentry breadcrumb for `isAccountingRejection` carrying `rule` and `next` (not `cause`).

**24. No product edit form exists.** `product_detail_screen.dart:305` toasts "coming soon". Good news for #2 (create is the only exposure) but `hsn_sac`, `supply_nature` and `tax_rate` can never be **corrected** from mobile. ⚠️ If you build it, note `updateProduct` (`products_remote_ds.dart:88-91`) sends the body verbatim with **no** empty-string stripping, unlike create — so an edit form sending `hsn_sac: ""` **will** hit the new validator where a create would not.

**25. `writePayload`'s silent allow-list is a trap.** `tickets_remote_ds.dart:559-601` drops unrecognised keys with no log and no throw. Whoever wires billable next will add the field, see a green "Ticket updated", and find it never persisted. Add a comment naming the allow-list, or a debug-mode assert on unrecognised keys.

**26. Dead auth fields.** `sidebar`, `full_access`, `is_staff`, `is_superuser`, `has_subordinates` are all parsed and **never read** (`module_access.dart:60-66`, `:97-98`). `sidebar` is the backend's own nav ordering — because it's discarded, **any module group the backend adds, including Accounting, is invisible until someone hand-edits `nav_catalog.dart`**. That is *why* #8 exists. Either honour `sidebar` (intersected with the catalog) or comment that it's intentionally unused. Also `has_subordinates`' doc comment claims it "gates 'My Team' surfaces" — it gates nothing; wire it or fix the comment.

**27. Product test fixtures have drifted from the real API.** `test/features/products_mapper_test.dart:156-171` — the `liveRow()` helper that the whole "live dev org" group is built on matches **neither** real key set:

| key | fixture | real list | real detail |
|---|---|---|---|
| `item_type`, `product_type_name`, `id` | ✅ | ❌ | ❌ |
| `description`, `billing_unit`, `hsn_sac`, `tax_rate` | ✅ | ❌ | ✅ |
| `gst_amount`, `price_excl`, `price_incl` | ❌ | ✅ | ✅ |
| `created_at`, `custom_fields` | ❌ | ✅ | ✅ |

So `liveRow()` is really *a detail row minus the computed price fields*, meaning every assertion on it exercises the app's **fallback arithmetic** rather than the server-computed path the live API actually takes. Coverage does exist (the tests at `:98-130` use their own inline rows), but the fixture named `liveRow` is the least live row in the file — a trap for the next reader. Rename it `detailRow()`, add the missing keys, drop the three phantom ones, and add a separate `listRow()`.

⚠️ **One thing inside this worth checking separately:** `product_type_name` is in the fixture but in **neither** real response. `_category` (`products_remote_ds.dart:299-307`) reads it first and returns `''` for a bare uuid. If it really is gone, the category chip, the grouping key and the filter facet are all empty on the live org — and `products_mapper_test.dart:174` passes only because the fixture supplies a field the server doesn't send. Confirm against the org's view config before calling it a regression. *(Not an accounting-change issue; found in passing.)*

> Note: this test file does not compile on Flutter 3.44.8, so it cannot be verified by running it on a machine using the unpinned SDK. Use `fvm`/the pinned 3.24.5.

**Also low:** `ModuleCatalog.builtIn` (`module_catalog.dart:75-89`) lacks an accounting group — affects mock/offline role creation only, and the live path is fully data-driven so an Accounting group appears with no code change. Billing (`billing.dart:165-172`) will count a new `accounting` plan feature but render only "N modules", never its name. `billing_screen.dart:400` hardcodes `'Place of supply: Karnataka (29) · Intra-state · CGST + SGST'` — prototype-only, unreachable against a real backend, but delete it or wire it once #14 lands.

---

# ⚪ PRE-EXISTING DEFECTS

**Found during this audit. Not caused by the accounting change** — but two of them are Critical and live, so they belong on the same work queue.

### P1. Every invoice and payment row shows "—" instead of the customer — 🔴 Critical, LIVE

`invoices_remote_ds.dart:115-116` reads `customer_id`, falling back to a nested `customer` map. **Verified live: the plan list has neither** — only `customer_name`. Same one level down: `payments_remote_ds.dart:88` reads `customer_id`, and the payment-records list has only `customer_name`.

So `custId` is null on every row, and:
- Payments screen → Invoices tab and the customer Payments tab show **"—"** as the company on every card
- Invoice detail subtitle reads **"— · "**
- The "Customer" button **always** toasts *"No customer linked — its lead has not converted yet"* even when a customer plainly exists
- Payment detail app-bar title is "—", the Customer chip never renders
- Customer filtering and search are dead

**Fix:** add `custName` to both `Invoice` and `Payment`, read `_str(row['customer_name'])`. Have `invoiceWho`/`paymentTitle` prefer the resolved party, then `custName`, then `custId`, then the dash. Keep reading `customer_id` for when the serializer adds it, and keep the nested `customer` form (the plan **detail** does expose it). Copy `custName` in `allPaymentsProvider`'s rebuild.

⚠️ **Measured caveat:** 25 of 29 plans have a non-null `customer_name`; **4 do not**. This fix recovers ~86% of rows — the rest still show a dash until the serializer exposes an id.

### P2. Every invoice card reads "0/0 settled" with an empty progress bar — 🟠 High, LIVE

`invoices_remote_ds.dart:98-111` counts settled/total from `row['records']`. **Verified live: the plan list has no `records` key** — only the detail does. So `of == 0` and `settled == 0` on every list row. `invoice_card.dart:101-116` renders a permanently empty progress bar and "0/0 settled".

The invoice **detail** header escapes this only because it prefers `summary.paidRecords/totalRecords` — which is why it has gone unnoticed.

**Fix:** in `Invoice.progress` (`invoice.dart:64`) use `of == 0 ? (totalNum == 0 ? 0 : paidNum / totalNum) : settled / of`, and gate the "X/Y settled" text on `of > 0`. Once #3 lands, prefer `(total − remaining) / total` so the bar tracks settlement rather than cash. **Do not fetch the summary per card.**

### P3. Projects "Estimated cost" filter returns zero results — 🟠 High, LIVE

The list is fetched with `?view=list`, whose slim projection has no `estimated_costing`, so `costNum` is 0 on every row. The cost range is then applied **twice** — server-side as `budget_min`/`budget_max`, and again locally at `projects_filter_spec.dart:250`, which sits **outside** the `if (!serverApplied)` guard.

Drag the minimum above ₹0 and the preview immediately reads "Show 0 projects"; applying empties the list even though the server returned matching rows. A max-only range works by accident.

**Fix:** move line 250 inside the `if (!serverApplied)` block. Pass `serverApplied: ApiConfig.apiEnabled` to `previewCount` (`projects_screen.dart:250`), matching line 165. Then delete `projectCostRupees` (`:41-47`) — it parses the **abbreviated display string** (`"₹18L"`) and its `RegExp(r'l')` matches any letter `l` anywhere; `Project.costNum` is the correct source and its doc comment says so.

### P4. Project cache silently drops `customerId` and `statusId` — 🟡 Medium, LIVE

`projects_api_repository.dart:79-136` — `_toJson` serialises 23 of 25 fields, omitting both. `_fromJson` rebuilds every cached project with `customerId: null`, `statusId: ''`. On the offline/cached path, customer filtering under-matches (falling back to a non-unique display name), and a status change from a cached row builds its body without the id it must send.

**Fix:** add both to `_toJson` and `_fromJson`. Both are JSON primitives so the "every field is a primitive" invariant holds. Old entries decode to today's wrong defaults — no worse than now, no migration needed. Add a `_fromJson(_toJson(p)) == p` test so the next field can't drift the same way.

### P5. Saved-view chip tap can throw `StateError` — 🟡 Medium, LIVE (race-dependent)

`final view = saved.filters.firstWhere((f) => f.id == id);` — **no `orElse`**, in a tap handler, against a freshly-read provider. If the list changed between render and tap, this throws.

**11 sites:** `projects_screen.dart:337`, `ops_tasks_screen.dart:316`, `leads_screen.dart:323`, `customers_screen.dart:290`, `products_screen.dart:247`, `tasks_screen.dart:363`, `followups_screen.dart:308`, `payments_screen.dart:220`, `quotes_screen.dart:261`, `members_screen.dart:232`, `teams_screen.dart:316`.

**Fix:** add `orElse: () => null`, widen the local to nullable, early-return with a toast — matching the inert-failure toast already two lines below.

### P6. Small ones
- `invoice_detail_screen.dart:185-194` skips `'payment_records'` and `'installments'`; the payload actually keys them `records`, `num_installments`, `remaining_installments`. If an org makes `records` visible it renders as a comma-joined wall of dashes.
- `invoices_remote_ds.dart:75` — `_int` uses `int.tryParse('$v')`, which returns null for `'3.0'`, so a decimal-string count silently becomes 0 ("0 of 0 settled"). Harden to `int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0`.
- `products_repository_impl.dart:57` reads `fields['hsn_code']` but every form sends `hsn_sac`. Mock mode only.

---

# ✅ Verified safe — no action needed

Worth recording, because several are things a reviewer would reasonably suspect:

**No crashes anywhere.** Every mapper reads named keys with defensive helpers and is wrapped in `try/catch`. New present-but-null fields, absent fields, and unknown extra fields are all inert. `record_summary` (always present, always null today) is handled — `recordValueText`/`_plain` return an em dash for null and for a Map with no name/title/label.

**No unknown-enum crash surface.** There is **no `.byName(` anywhere in `lib/`**, and no `values.firstWhere` over a server-supplied module or role string. The 7 new `acc_*` modules are silently ignored; the 2 new roles render as display strings.

**Nothing iterates the server module map to build UI** — navigation is a static catalog that asks for permission, never the reverse. So the accounting modules cannot produce blank menu rows.

**Money parsing is safe.** Every money field goes through `parseAmount` (`inr_format.dart:29-35`), which explicitly handles decimal strings. `'0.00'` → `0.0`. **Quantity is the only decimal that went through `_int` instead** — which is precisely issue #1.

**All money writes are PATCH, never PUT**, so the app cannot clobber server fields it doesn't know about.

**No project code is written that is now read-only**, and no project margin is displayed.

**The 400 guard-block path is fine** — `detail` is checked before field errors, so block reasons reach the user readably. `_writeStatus` (`quote_detail_screen.dart:697-731`) returns before any `invalidate` on error, so a rejected revert leaves the UI showing the true status. No optimistic update to roll back.

**Optimistic rollback on refusal is correct at all three settle sites.**

**The Hive cache is safe in both directions** — it stores raw JSON and re-maps on read, so mapper fixes ship correctly to users holding a warm cache. No cache-version bump needed.

**Quote number uniqueness is a non-event** — the app never writes `quotation_number`; per-org uniqueness strictly improves the lookup.

**There is no quote PDF/print-template viewer in the app.** `pdf_url` is in the payload but never read, so §B10's blast radius is exactly one control: the create-form chip row.

**Deprecated org numbering fields are entirely unused** — zero hits for `invoice_prefix` / `next_invoice_number`.

**Dashboards perform no client-side money arithmetic** — all 26 sections are server-computed aggregates, formatted as received.

---

# Recommended sequencing

**Sprint 1 — stop showing wrong numbers**
1. #1 quantity parsing *(highest value, smallest change)*
2. #2 HSN validation
3. P1 customer name on invoice/payment rows
4. P2 invoice card progress
5. #5 fractional qty in the new-quote form

**Sprint 2 — before anyone records a TDS**
6. #3 + #4 settlement maths *(do together; they share the entity change)*
7. #9 TDS capture on mark-as-paid
8. #6 send `product_id` on quote lines

**Sprint 3 — before accounting is switched on**
9. #7 template filter · #8 accounting nav entry · #10 409 handling · #16 tax label

**Sprint 4 — capability gaps**
10. #11 billable · #12 deprecation warning · #13 supply nature · #14 states lookup · #18 project links

**Backlog:** P3–P6, #15, #17, #19–#26

---

# Open questions for the backend team

1. 🔴 **What is the server's default for `amounts_are` when omitted on create?** This is the one genuinely unresolved risk. If it defaults to `INCLUSIVE`, **#16 becomes Critical immediately** — the app posts tax-exclusive catalog prices, so every mobile-created quote would be stored ~18% light and the customer under-billed. Settle this before any quote work ships.
2. 🟡 **When will `supply_nature` actually be exposed on the product response?** It is absent today, contrary to the change document. #13 is blocked until then.
3. 🟡 **Is `product_type_name` still sent on the product serializer?** See #27 — if not, the category chip and filter facet are empty on the live org.

**Already answered — no need to ask:**
- ✅ *The exact `hsn_sac` rule.* Probed directly against the live API: `"hsn_sac must be 4 to 8 digits when set."` → `^\d{4,8}$`, blank allowed. This was the single input most likely to make fix #2 wrong, and it is now settled. Do **not** implement the stricter {4,6,8} rule.
- ✅ *Whether `supply_nature` is required on create.* Effectively no — product creation works today without it.

**Also flag to the backend team:** `admin_dashboard.md:178` and `admin_operations_dashboard.md:109` show dashboard aggregates ranking by `total_sales_amount` — a now-deprecated column. Those must be re-pointed at the ledger when accounting ships, or Revenue-at-Risk silently zeroes. Nothing the client can fix.
