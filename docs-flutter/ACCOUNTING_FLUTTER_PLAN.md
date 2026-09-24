# Accounting module — Mobile app integration plan (clozr-flutter-v2)

Source of truth: `nexocrm-django-api` branch `claude/gracious-hamilton-96bufp` (accounting app under `/api/v1/accounting/`, plus the accounting columns added to quotations, products, issues and projects), read against `clozr-flutter-v2` on the same branch (Flutter 3.24.5 / Riverpod / GoRouter / Dio / Hive; feature-first 4-layer layout per `docs-flutter/API_INTEGRATION_GUIDE.md`).

The full endpoint inventory (fields, enums, error codes) is in the companion web plan `ACCOUNTING_WEBAPP_PLAN.md` §1 and §7. This document does not repeat every field; it states, for **every** backend capability, what mobile does with it, and then the concrete Flutter changes.

---

## 0. Read this first — the honest summary

1. **Mobile should not try to be the accounting console.** Period settlement, year-end close, manual journals, opening balances, the activation wizard and the utilisation-matrix editor are multi-column, multi-step, CA-facing tasks. On a 390 px canvas they would be slow to use and easy to get wrong, and every one of them posts irreversible journal entries. The web app owns them. Mobile owns the **field money path**: raise the invoice for a plan record or a ticket, look at a document, share it, record a receipt with TDS, capture a vendor expense, pay a vendor, and see who owes what. Everything else is read-only or absent on mobile, and §1 says which, item by item, so nothing is silently dropped.
2. Three existing mobile behaviours are **defects once accounting is active** and must be fixed even if no new screen ships: (a) `markRecordPaid` always sends `paid_date = today` and `amount_paid = amount_expected` — with TDS the cash amount is lower and the date is the customer's, not today's; (b) the add-quote form never sends `product_id` per line, so the derived invoice has no HSN/SAC and issue fails with `HSN_DIGITS_REQUIRED`; (c) money is rounded to whole rupees (`Payment.amountNum` is `int`, `Invoice.totalNum` is `int`) — accounting figures carry paise and the app must stop rounding anything it might display next to a ledger figure.
3. The same **backend gaps** that hurt the web hurt mobile harder because there is less room to work around them: no bank-account list (every receipt/expense/payment needs one), no detail read for receipts/payments, no `vendor`/`search` filter on documents, `Idempotency-Key` fine on Dio (no CORS) but keep the body `event_id` convention for parity. See §2.
4. Mobile has **no plan-feature gate today** (the drawer gates on `/auth/me/modules/` only; `BillingSubscription.features` is fetched but not used for navigation). Accounting is plan-gated (`accounting` feature, off on Starter) — the app needs a feature gate before it needs a single accounting screen, otherwise Starter users get a menu that 403s.
5. `AppError` carries `message`, `statusCode`, `fieldErrors` — not the 409 `code`/`cause`/`next` contract. An additive change to `core/network/app_error.dart` is a prerequisite.

---

## 1. Backend surface × mobile decision (complete)

Legend: **Build** = full mobile screen/sheet; **Read** = read-only on mobile; **Skip** = not on mobile in this cycle, with the reason; **Existing** = change to an existing screen.

### 1.1 Setup & activation (`acc_setup`)

| Capability | Mobile | Why |
|---|---|---|
| Tenant profile GET/PUT | **Read** (status card) | 20-field statutory form; web wizard owns it |
| Tenant attributes GET/POST | **Read** | append-only with a DB exclusion constraint (web plan G-3); a wrong tap on mobile is unrecoverable |
| Gates GET | **Read** | shown on the status screen so an admin can see why activation is blocked |
| Activate POST | Skip | one-way, seeds the books; desktop only |
| Opening balances POST | Skip | Dr/Cr grid |
| Register bank account POST | Skip | web; mobile only picks from the list once the list endpoint exists |
| Fix open payment plans (G9) | **Existing** — the plan detail lets a user set `billing_mode` (§5.2), which is the mobile-side half of the fix | |

### 1.2 Sales documents (`acc_document`)

| Capability | Mobile |
|---|---|
| List documents (all filters) | **Build** — Invoices list with tabs and filters |
| Retrieve document | **Build** — Document detail |
| PATCH draft header | **Build** — "Edit draft" sheet (8 fields) |
| Manual invoice create | **Build** — New invoice screen (simplified: product-driven lines; free-text lines allowed) |
| From payment record | **Existing** — "Issue invoice" on the plan detail row |
| From ticket | **Existing** — "Bill this ticket" on ticket detail |
| Preview tax | **Build** — part of the Issue sheet |
| Issue (approve) | **Build** — Issue sheet with advance adjustments |
| Void | **Build** |
| Cancel (approve) | **Build** — reason sheet |
| Render context | **Build** — Share/print sheet (HTML → `Share`/print via platform; see §4.6) |
| PDF (501) / journal (501) | Skip — never call |
| Credit note / Debit note | **Build (credit note only, RETURN and VALUE_CORRECTION reasons)**; DISCOUNT/RATE_CORRECTION and debit notes are Skip (rare, need the s.15(3) attestation and line-level rate edits — web) |

### 1.3 Purchases (`acc_purchase`)

| Capability | Mobile |
|---|---|
| Vendor bill (D1) | **Build** — Vendor bill sheet (single-target, up to N lines) |
| Expense (D3, bill + payment) | **Build** — the primary mobile purchase flow ("Record expense") |
| Fixed asset (D8) | Skip — capitalisation decisions are web |
| Vendor credit note (D6) / debit note (D7) | Skip |
| Purchases list | **Build** — Vendor bills list (documents by `doc_type`) |

### 1.4 Vendors & tax profiles

| Capability | Mobile |
|---|---|
| Vendor list/search, create, edit, deactivate | **Build** — vendors list + add/edit sheet (delete → 409 `PARTY_HAS_BOOKS` → offer deactivate) |
| Vendor tax profile GET/PUT | **Build** (same sheet as customer tax profile) |
| Customer party tax profile GET/PUT | **Existing** — Customer detail "Tax profile" sheet |
| Product tax profile GET/PUT | **Existing** — Product detail "Tax profile" card; write limited to `tax_treatment_default`, `is_rcm_outward`, `cess_applicable`; `rate_variant_key` set only from the Issue sheet's candidate picker |
| Register loan | Skip |

### 1.5 Settlement (`acc_settlement`)

| Capability | Mobile |
|---|---|
| Receipts list + Record receipt (B5/B8) | **Build** — Money screen "Receipts" tab + Record receipt sheet |
| Reverse receipt | **Build** (confirm + reason) |
| Advances list + Record advance (B3) | **Build (list)**, record advance **Build** (customer, amount, date, source, nature, supply, rate) |
| Adjust advance (B4) | **Read** — adjustments happen from the Issue sheet; standalone adjust Skip |
| Refund advance (B10) | Skip |
| Customer credits list | **Read** |
| Apply credit (B9) / refund credit (B7) | Skip |
| Vendor payments list + Record vendor payment (D2) | **Build** |
| Reverse vendor payment | **Build** |
| Vendor advances list + record (D4) / adjust (D5) | **Read** list; record/adjust Skip |

### 1.6 Banking & funding (`acc_journal`)

| Capability | Mobile |
|---|---|
| Transfer (G1), bank charge (G2), bank interest (G4) | Skip — bookkeeping tasks; no field need |
| Gateway settlement (G3) | Skip |
| Capital (A1), drawings (A2), loans (A4/A5) | Skip |

### 1.7 Journal & ledger (`acc_journal`)

| Capability | Mobile |
|---|---|
| Manual journal | Skip |
| Entries list / entry detail | **Read** — only as the "Journal" section inside Document detail (`journal/entries/?document=`) and behind receipt/payment rows (`journal/entries/{id}/`) |
| Events list / detail | **Read** — "Rejected postings" card on the accounting home (`status=REJECTED`), tap → event sheet with the error |

### 1.8 Periods & compliance (`acc_period`)

| Capability | Mobile |
|---|---|
| Period register | **Read** — Periods screen (three lists with status pills) |
| GST checklist | **Read** — items and blocking list; acknowledge Skip |
| Settlement proposal / save / confirm, challan, interest | Skip |
| TDS deposit | Skip |
| Income tax paid, closing stock | Skip |
| Book period close, FY close checklist / close | Skip; checklists **Read** |
| Opening balances | Skip |

### 1.9 Reports (`acc_report`)

| Report | Mobile |
|---|---|
| AR aging, AP aging | **Build** — summary cards + per-party rows |
| Customer statement, vendor statement | **Build** — from customer / vendor detail |
| P&L, Balance sheet | **Build** (compact: totals + expandable sections) |
| Trial balance | **Read** (bucket totals, expandable accounts; no export) |
| General ledger | Skip (paginated per-account drill-down; web) |
| GST summary, TDS summary, ITC register | **Read** — one card each on the Periods screen for the selected period |
| Project financials | **Existing** — project detail card; rederive Skip |
| Export CSV | Skip |

### 1.10 Existing endpoints with new accounting fields (all **Existing**)

Payment records (settlement columns, `record_summary`, 409 on mark-paid), payment plans (`billing_mode`, `auto_issue`, `project`, `contract_ref`), quotations (`amounts_are`, `place_of_supply_state_code`, `contract_ref`, line `product_id`/`line_discount`/`hsn_sac`/`supply_nature`/`rate_pct`, locks), products (`supply_nature`, `deprecated_rate`, 40 % slab, HSN validation), issues (`billable*`, `billed_document_line_id`), projects (`financials`), customers (delete 409), `/auth/me/modules/` (seven `acc_*` keys), module catalog (accounting group), `/billing/features/me/` (`accounting`), `/organizations/states/`.

---

## 2. Backend gaps that shape the mobile build

Same numbering as the web plan; only the mobile consequence is stated.

| # | Gap | Mobile consequence |
|---|---|---|
| G-1 | No `GET masters/bank-accounts/` | Record receipt / expense / vendor payment cannot offer a bank picker. **Ship these sheets only with CASH + "default bank" (omit `bank_account`, let the backend resolve the org default) until the list exists**, and say so in the sheet. This is the single biggest blocker for the mobile money path. |
| G-2 | `Idempotency-Key` not CORS-allowed | Not a mobile problem (Dio), but use body `event_id` anyway so web and mobile share one convention and one backend behaviour. |
| G-4 | No list for accounts, loans, series, FY, categories, TDS natures, asset classes | Mobile ships the expense-category, TDS-nature and asset-class lists as static Dart constants generated from the seed CSVs (global config; safe). FY switching is unavailable (single "current FY"). |
| G-5 | No detail read for receipts/payments | Detail = the list row already in memory; deep links must carry `?customer=`/`?vendor=` and find the row client-side. Cache the list rows in Hive so a detail opened from a notification still resolves offline. |
| G-6 | No `vendor`/`search`/`number` filter on documents; inward columns hidden | Vendor bills list is by `doc_type` only; the vendor detail "Bills" tab filters the loaded pages client-side (cap at 5 pages, then say "open on web"). No TDS/payable on purchase rows. |
| G-7 | No GSTR-1 filed endpoint | Not needed on mobile (read-only periods). |
| G-8 | `amounts_are` on old plans not fixable | Plan detail shows the G-9 warning when `amounts_are` is null and points to the web. |
| G-9 | No PDF | Share = HTML rendered from `render-context` via `printing`-style platform print or share-as-HTML/PDF (see §4.6); or simply share the invoice number + totals as text. Decide before R1; the plan assumes an HTML print sheet. |
| G-10 | No party tax-profile list | Customer list shows no B2B badge; detail only. |
| G-11 | Lines immutable after draft creation | "Void and recreate" copy on the draft. |
| G-12 | `upgrade_url` is a web path | Ignore; mobile shows "Upgrade on the web app". |
| G-13 | No FY list | Current FY only. |

---

## 3. Cross-cutting foundation (before any screen)

### 3.1 New feature slice `lib/features/accounting/`

Per the integration guide: `domain/entities`, `domain/repositories`, `application/providers`, `infrastructure/data_sources/remote` (+ `local` mock), `infrastructure/repositories` (api + mock impl), `presentation/{screens,sheets,components}`. Suggested entities (all immutable, `Equatable`, money kept as **String** with a `double` twin only for sorting):

- `AccDocument` (+ `AccDocumentLine`, `AccTaxLine`, `DocWarning`), `AccDocumentPage`
- `TaxPreview` (lines, totals, config rows, warnings)
- `Vendor`, `PartyTaxProfile`, `ProductTaxProfile`
- `AccReceipt`, `AccAdvance`, `AccCustomerCredit`, `AccVendorPayment`, `AccVendorAdvance`
- `JournalEntry`, `JournalLine`, `LedgerEvent`
- `PeriodRegister` (+ `BookPeriodRow`, `GstPeriodRow`, `TdsPeriodRow`), `PeriodChecklist`, `ChecklistItem`
- `TenantTaxProfile`, `TenantAttribute`, `GateResult`
- `AgingReport`, `PartyStatement`, `PnlReport`, `BalanceSheetReport`, `TrialBalanceReport`, `GstSummary`, `TdsSummary`, `ItcRegister`, `ProjectFinancials`
- `AccountingConflict` (code, detail, cause, next, rule) — see 3.4
- `accounting_seed.dart` — static catalogs: expense targets (43 keys + labels + default TDS nature + ITC hint), asset classes, TDS natures, doc types, transaction classes, status vocabularies

Data sources: `accounting_documents_remote_ds.dart`, `accounting_settlement_remote_ds.dart`, `accounting_purchases_remote_ds.dart`, `accounting_masters_remote_ds.dart`, `accounting_periods_remote_ds.dart`, `accounting_reports_remote_ds.dart`, `accounting_setup_remote_ds.dart`; one repository per area; mock impls return seed data so mock mode keeps working.

### 3.2 `core/network/api_endpoints.dart`

Add a `// ── Accounting ──` block with every path in web plan §1 (constants for collections, builders for `{id}` routes): `accDocuments`, `accDocument(id)`, `accInvoicesManual`, `accInvoiceFromRecord`, `accInvoiceFromTicket`, `accDocumentPreviewTax(id)`, `accDocumentIssue(id)`, `accDocumentVoid(id)`, `accDocumentCancel(id)`, `accDocumentRenderContext(id)`, `accCreditNotes`, `accDebitNotes`, `accVendorBills`, `accExpenses`, `accFixedAssets`, `accVendorCreditNotes`, `accVendorDebitNotes`, `accVendors`, `accVendor(id)`, `accPartyTaxProfile(kind, id)`, `accProductTaxProfile(id)`, `accBankAccounts`, `accLoans`, `accReceipts`, `accReceiptReverse(id)`, `accAdvances`, `accAdvanceAdjust(id)`, `accAdvanceRefund(id)`, `accCustomerCredits`, `accCreditApply(id)`, `accCreditRefund(id)`, `accVendorPayments`, `accVendorPaymentReverse(id)`, `accVendorAdvances`, `accVendorAdvanceAdjust(id)`, `accJournalManual`, `accJournalEntries`, `accJournalEntry(id)`, `accLedgerEvents`, `accLedgerEvent(id)`, `accSetupTenantProfile`, `accSetupTenantAttributes`, `accSetupGates`, `accSetupActivate`, `accPeriods`, `accBookChecklist(id)`, `accGstChecklist(id)`, `accFyCloseChecklist(id)`, the report paths, and `states = '/organizations/states/'`, `myFeatures = '/billing/features/me/'`.

### 3.3 Feature and module gating

- `planFeaturesProvider` (new, `FutureProvider<Set<String>?>`): `GET /billing/features/me/` → keys whose value is `true`; null in mock mode / on failure (same fail-open philosophy as `moduleAccessProvider`). Cache in Hive `settingsBox` for 15 min.
- `NavEntry` gains `planFeature: String?`; `AppDrawer.visible()` and `landingPathFor` also check it. Add the drawer entry: `NavEntry(key:'accounting', label:'Accounting', icon: PhosphorIconsRegular.calculator, path: Routes.accHome, planFeature:'accounting', modules:['acc_document','acc_purchase','acc_settlement','acc_report','acc_period','acc_setup'], children:[Invoices (acc_document), Purchases (acc_purchase), Vendors (acc_purchase), Money (acc_settlement), Reports (acc_report), Periods (acc_period), Status (acc_setup)])`.
- `ModuleAccess` already exposes per-module `canCreate/canUpdate/canApprove`; screens gate buttons with them exactly as the CRM screens do. Note `approve` on `acc_document` = issue/cancel.
- `Routes.meta`: new `NavContext.acc` with `showNav: true` for the four hub screens; `clozr_bottom_nav.dart` `_items` gains a `NavContext.acc` case: Home, Invoices, Purchases, Money. `_fallbackAddPath` for `/acc/purchases` → new expense, `/acc/invoices` → new invoice, `/acc/money` → record receipt; list screens register their own `AddAction` (`registerAdd`).

### 3.4 Error model (`core/network/app_error.dart`, additive)

- `AppErrorType.conflict` for 409 (currently falls to `unknown`).
- New fields `code: String?` (only when the body's `code` is a string), `cause: Map<String, dynamic>?`, `next: String?`, `rule: String?`, `feature: String?`, `currentPlan: String?` parsed in `_fromResponse`.
- `_extractMessage` must prefer `detail` for these bodies (it already does via the `detail` key).
- Helper getters: `isAccountingInactive` (`code == 'ACCOUNTING_NOT_ACTIVE'`), `isPlanBlocked` (`code == 'feature_not_in_plan'`), `isSkipped` is not an error (200 body `{skipped:true}` — handle in the data source, return a sealed `PostOutcome.skipped`).
- `ApiService.post` gains an optional `headers` map (harmless), but accounting data sources send `event_id` in the body.

### 3.5 Activation status

`accountingStatusProvider`: `GET setup/tenant-profile/` → `activation_status` (404 → INACTIVE). Every accounting screen watches it and renders an `EmptyState` ("Accounting is not activated for this workspace — set it up on the web app") when not ACTIVE; CRM screens use it to hide accounting affordances (tax profile, Issue invoice, Bill ticket, financials). Also catch `ACCOUNTING_NOT_ACTIVE` on any accounting call and invalidate this provider.

### 3.6 Money and dates

- Keep server strings; add `core/utils/money_format.dart`: `formatMoneyStr(String)` (₹ with paise, Indian grouping via `intl`), `formatMoneyCompact` for KPI tiles only. Do **not** use `parseAmount(...).round()` for anything accounting shows.
- Fix the rounding in existing entities where accounting figures will sit next to them: `Payment.amountNum`, `Invoice.totalNum/paidNum` should become `double` (or add `amountStr`). Keep the display strings.
- Dates: ISO `YYYY-MM-DD`; default to the device date; the backend interprets in IST — show an "IST" hint on issue/receipt date pickers.

### 3.7 Caching / offline policy (Hive, `AppCache`)

- New box `accountingCache`. Cache **reads only**: documents list pages (key per tab + filters), vendors, settlement lists, period register, reports (as-of today). Never cache a form or a preview.
- Writes are remote-only; on success `AppCache.remove` the affected keys (documents, settlement, reports, and the CRM `invoices`/`payment_records` keys when the write came from the payments screens).
- Offline: every posting sheet checks `connectivityProvider` and disables submit with "Posting needs a connection" — no queued posts (an idempotent replay from a stale queue would still post against a period that may have closed).

### 3.8 Shared accounting widgets (`presentation/components`)

`ConflictBanner` (code/detail/cause chips/next action), `WarningsStrip`, `DocStatusPill`/`PaymentStatePill`/`PeriodPill` (extend `StatusMeta$` with `accDocument`, `accPaymentState`, `accReceipt`, `accPeriod`, `accEvent` maps), `DocumentLinesList`, `TotalsCard`, `JournalEntryCard`, `PartyPickerSheet` (customers via `/crm/customers/?search=`, vendors via `masters/vendors/?search=`), `ProductLinePickerSheet` (reuse `add_product_sheet.dart` search; fills description/HSN/nature/unit price/rate), `StateCodePickerSheet` (`/organizations/states/`, cached), `SeedPickerSheet` (expense target / TDS nature), `MoneyField` (decimal string input, 2 dp), `SourceAccountChips` (CASH / Default bank / Gateway; bank list once G-1), `InvoiceShareSheet` (§4.6).

---

## 4. New mobile screens and sheets

Routes use the app's query-param convention (`?id=`). All under `NavContext.acc` unless noted.

### 4.1 Accounting home — `/acc/home` (`acc_report` for tiles; `acc_document`/`acc_settlement` for actions)

KPI tiles (`KpiCard`): Receivable (AR aging total + 90+), Payable (AP total), This month's GST (output − input from `gst-summary?gst_period_id=` current), TDS pending (`tds-summary` totals). "Needs attention" list: rejected postings (`journal/events/?status=REJECTED`), drafts older than 7 days, unsettled GST periods. Quick actions row: New invoice, Record receipt, Record expense, Pay vendor (each verb-gated). Pull-to-refresh invalidates the five providers.

### 4.2 Invoices — `/acc/invoices` (`acc_document`)

`ListHeader` + status chips (All / Draft / Issued / Cancelled) + tab chips by family (Invoices / Notes / Vouchers). Filter sheet: customer (picker), payment state, transaction class, date range, source type. Card per document: number or "Draft", customer name (resolve via `crmPartyLookupProvider`; fall back to `party_snapshot`), date, grand total, open balance, status + payment-state pills, source icon. Infinite scroll on `page`. `+` → New invoice (4.4). Empty states per chip.

### 4.3 Document detail — `/acc/documents/detail?id=` (`acc_document`)

`DetailAppBar` with number/status. Header card: doc type, dates, customer/vendor (tap → party detail), POS, INTRA/INTER, transaction class, amounts_are. Totals card (taxable, CGST/SGST/IGST/cess, round-off, grand total, open balance). Sections (underline tabs): Lines (`DocumentLinesList`), Tax (tax lines with ITC status), Journal (`journal/entries/?document=`), Links (quotation / plan record / project / ticket, back-link to the original document for notes), Warnings (+ `config_draft_rows` notice), Party snapshot. Actions by status (bottom `StickyActionBar` + overflow `ActionMenu`):

- DRAFT: Preview & Issue (4.5), Edit draft (sheet: document/supply/due date, POS, amounts_are, narration, terms, notes), Void (confirm).
- ISSUED: Record receipt (opens 4.8 with customer + `targeted_document_ids=[id]`), Credit note (4.7), Cancel (reason sheet; `CANCEL_NOT_ALLOWED` reasons mapped), Share (4.6).
- CANCELLED / VOID_DRAFT: Share only.

### 4.4 New invoice — `/acc/invoices/add` (`acc_document` create)

`OpsFormScaffold`-style full screen: doc type (TAX_INVOICE / BILL_OF_SUPPLY / EXPORT_INVOICE / PROFORMA), customer (picker; optional until issue), document date, supply date, due date, place of supply (picker; blank = auto), amounts are (default from tenant profile), narration. Lines: "Add product" (picker fills the line) or "Add free line" (description, HSN/SAC 4–8 digits, nature, qty, unit price, discount, treatment). No client totals; the footer says "Totals are computed at preview". Submit → 201 → push detail.

### 4.5 Issue sheet

Calls `preview-tax` on open; shows totals, per-line resolved rate/variant/match level, `config_rows` verification badges, warnings. Optional "Adjust advances" (open advances for the customer; amount per advance → `advance_adjustments`). Confirm → `issue`. Error handling: `RATE_VARIANT_REQUIRED` → inline candidate list → "Pin on product" (PUT product tax profile) → retry; `HSN_DIGITS_REQUIRED` → highlight line + "void and recreate"; `CUSTOMER_REQUIRED`/`AMOUNTS_ARE_REQUIRED` → open Edit draft; `CONFIG_NOT_VERIFIED` → rows list with "ask your CA"; `PERIOD_FILED_DATE_IN_OPEN_PERIOD`; `ACCOUNTING_POSTING_REJECTED` → `cause.code`. Success toast with number; warnings strip.

### 4.6 Share / print sheet

`render-context` → an in-app HTML/Widget invoice layout (supplier with GSTIN/PAN/state, recipient with GSTIN, lines, per-head totals, round-off, grand total, amount in words, narration/terms). Actions: Share as PDF (render the widget to PDF on-device — needs a PDF package such as `pdf` + `printing`; check the 3.24.5 pin before adding) or Share as text (number, date, totals) as the R1 fallback if the package cannot be pinned. State plainly that the server does not provide a PDF yet.

### 4.7 Credit note sheet (ISSUED outward invoices only)

Reason (RETURN / VALUE_CORRECTION), with GST toggle, document date, line picker (original lines; editable qty and unit price), settlement leg (apply to open balance / refund / hold as credit; simple radio with amount). Errors: `NOTE_NOT_ALLOWED` reasons, `CN_CUTOFF_PASSED`. Success → push the note.

### 4.8 Money — `/acc/money` (`acc_settlement`)

`SegmentedControl` tabs: Receipts, Vendor payments, Advances, Credits. Each: list (party/status filter chips) → row tap opens a detail sheet built from the row (kind, status, amount, TDS, unallocated, journal entry via `journal/entries/{id}/`, Reverse action). `+` → Record receipt (default tab) / Record vendor payment.

- **Record receipt sheet**: customer (picker), amount received, date, source (CASH / Default bank / Gateway + provider; bank picker after G-1), method chips (reuse the existing `_payMethods` but send codes), reference, TDS deducted + certificate ref (collapsed), bank charge (collapsed), target invoices (multi-select of the customer's open ISSUED documents; blank = oldest first), note on the outcome (allocated vs unapplied credit). `CASH_RECEIPT_LIMIT` warning copy on cash ≥ ₹2 lakh same day. 409 → `ConflictBanner` inside the sheet; nothing is invalidated.
- **Record advance sheet**: customer, amount, date, source, supply INTRA/INTER, nature GOODS/SERVICE, rate %, taxable toggle, method, reference.
- **Record vendor payment sheet**: vendor, amount, date, source (CASH / default bank / OWNER + name), TDS now + nature (seed picker), target bills (multi-select of vendor bills — client-filtered, G-6), method, reference; explain the full-allocation rule and point to Vendor advance (web) for prepayments.
- **Reverse** (receipt with reason; vendor payment confirm).

### 4.9 Purchases — `/acc/purchases` (`acc_purchase`)

List of vendor bills (`doc_type=VENDOR_BILL`; second chip for vendor notes) with vendor name (resolve from a cached `masters/vendors/?page_size=200` map), date, total, open balance, payment state. `+` menu: Record expense, Vendor bill.

- **Record expense sheet (D3)**: vendor (picker or "quick add vendor" inline: name + state), expense category (`SeedPickerSheet` with the category's default TDS nature and ITC hint), amount as one line (description, HSN/SAC optional, nature default SERVICE, qty 1, unit price) with "add line" for more, paid from (CASH / default bank / OWNER), date, vendor invoice no (optional), personal-use flag, TDS nature override (advanced). Confirm copy: "This posts the bill and the payment to the ledger now." Success shows bill number + "payment posted".
- **Vendor bill sheet (D1)**: same minus "paid from", plus supply date, vendor invoice date, POS, RCM override (advanced).

### 4.10 Vendors — `/acc/vendors`, `/acc/vendors/detail?id=` (`acc_purchase`)

List (search, active chip), Add/Edit sheet (name, legal name, email, phone, address, state, masked account no, IFSC, body corporate, GTA FCM opted, small-transporter declaration, notes), Deactivate (PATCH `is_active=false`), Delete (409 → offer deactivate). Detail: info rows, tabs Bills (client-filtered), Payments (`vendor-payments?vendor=`), Advances (read), Statement (`vendor-statement`), Tax profile (sheet: registration type, GSTIN, PAN, state, entity kind, TDS applicable, body corporate, default TDS nature, effective from).

### 4.11 Periods (read-only) — `/acc/periods` (`acc_period`)

Current FY header (label, status). Three collapsible lists: book periods (status), GST periods (GSTR-1/3B status, settled), TDS periods (status, quarter). Tap a GST period → checklist sheet (items with severity/status, blocking list, `can_settle`) and the GST summary card for that period; tap a TDS period → TDS summary rows. Footer copy: "Settle GST, deposit TDS and close periods on the web app."

### 4.12 Reports — `/acc/reports` (`acc_report`)

Report picker cards → each a screen with a compact filter bar: AR aging / AP aging (totals tile + party rows with bucket chips; tap → statement), P&L (income/expense sections, net), Balance sheet (assets/liabilities/equity, balanced badge), Trial balance (bucket totals, expandable accounts), Customer/Vendor statement (party + date range, running balance rows). GST/TDS/ITC live on the Periods screen. No export.

### 4.13 Accounting status — `/acc/status` (`acc_setup`)

Read-only: activation status, ledger start, entity type, state, registration/GSTIN/TDS deductor attributes, gates table (pass/fail + detail). CTA: "Complete setup on the web app." Reachable from the drawer child "Status" and from every "not activated" empty state.

---

## 5. Changes to existing mobile screens

### 5.1 Quotes (`features/crm` — `add_quote_screen.dart`, `quote_draft.dart`, `quote_detail_screen.dart`, `quotes_remote_ds.dart`, `quote.dart`)

- `QuoteDraftLine` gains `productId` and `lineDiscount`; `toJson` sends `product_id` when the line came from the product picker (it already reads `Product.priceNum`, so the id is in hand). This is the fix for defect (b).
- `QuoteDraft` gains `amountsAre` (EXCLUSIVE/INCLUSIVE, default from the tenant profile when active), `placeOfSupplyStateCode`, `contractRef`; `toCreateJson` sends them (schema-aware like the other fields). Add the three inputs to the form (a "Tax" section: amounts-are segmented control, POS picker, contract ref).
- Read side: parse `amounts_are`, `place_of_supply_state_code`, `contract_ref`, per-line `hsn_sac`, `supply_nature`, `rate_pct`, `line_discount`; `QuoteItem` gains `hsn`, `nature`, `ratePct`; the detail's line rows show "HSN 998313 · 18 %".
- Detail: locked banner when a record is paid or linked (needs the plan's records; the invoice summary already loaded on quote detail gives `paidRecords`; for linked, read `record_summary`/`linked_document_id` from the records list); map the revert-block 400 message to a notice with a link to the accounting document.

### 5.2 Payments / plan (`invoice_detail_screen.dart`, `payment_detail_screen.dart`, `record_payment_sheet.dart`, `payments_remote_ds.dart`, `invoices_remote_ds.dart`, entities)

- Entities: `Invoice` gains `billingMode`, `autoIssue`, `amountsAre`, `projectId`, `contractRef`; `Payment` (record) gains `tdsDeducted`, `bankCharge`, `gstTdsDeducted`, `gstTcsDeducted`, `bankAccountId`, `gatewayRef`, `treatAs`, `servicePeriodStart/End`, `milestoneTaskId`, `linkedDocumentId`, `postedReceiptId`, `recordSummary` (`RecordSummary{document{id, number, status, grandTotal, openBalance, paymentState}, receipt{id, kind, status, amount, date}}`). Mappers parse them; stop rounding to `int` (defect c).
- `invoice_detail_screen.dart`: "Billing settings" card (billing mode chips with one-line explanations, auto-issue switch, project picker from `/projects/projects/`, contract ref) → `PATCH /quotations/payments/{id}/` (new repository method `updatePlanBilling`); G-9 warning when `amounts_are` is null. Schedule rows show an "Invoice" line (number + status + payment state, tap → document detail) and "Receipt posted" when `posted_receipt_id` is set. Row action **Issue invoice** (visible when active, no `linked_document_id`, user `acc_document.canCreate`): sheet with document/supply date → `POST documents/invoices/from-payment-record/` → push document detail; offer "Issue now" (needs `canApprove`).
- `record_payment_sheet.dart`: add TDS deducted, bank charge, date received (currently forced to today — defect a), source (CASH / default bank; bank picker after G-1), treat-as (ADVANCE / CUSTOMER_CREDIT when the record has no linked document), gateway ref; compute and display "Cash + TDS + bank charge = settled value" against `amount_expected`; `markRecordPaid` signature gains these fields and sends `amount_paid` = cash only. On 409 `ACCOUNTING_POSTING_REJECTED`: roll back the optimistic `paidOverrideProvider` (already done for any error), show `ConflictBanner` with `cause`, keep the sheet open. Success: "Payment recorded · receipt posted" when the refreshed record carries `posted_receipt_id`.
- `payment_detail_screen.dart`: `MetaRow`s for TDS, bank charge, settled value, treat-as; "Accounting" card with the linked document and receipt chips; editing a paid record's amount/TDS/date shows the "re-posts the receipt" warning.
- Payments list card: small "INV/26-27/0042" chip from `record_summary`.

### 5.3 Customers (`customer_detail_screen.dart`, `customers_remote_ds.dart`)

- New tab **Accounting** (7th underline tab; only when active): open documents (`documents/?customer=`), receipts (`receipts?customer=`), open advances/credits, "Statement" button (4.12). CTA per tab: Record receipt / New invoice.
- Overflow menu: **Tax profile** sheet (GET 404 → empty; PUT; `acc_setup.canUpdate`): registration type, GSTIN (15 chars + checksum client-side), state, PAN, entity kind, TDS applicable, body corporate, currency, default TDS nature, effective from. Header shows "B2B · <GSTIN>" when present.
- Delete customer (if the app offers it): 409 `PARTY_HAS_BOOKS` → copy.

### 5.4 Products (`product_detail_screen.dart`, `add_product_sheet.dart`, `product_form.dart`, `products_remote_ds.dart`, `product.dart`)

- Parse `supply_nature` and `deprecated_rate`; `Product` gains `supplyNature`, `deprecatedRate`.
- Add-product sheet: supply nature chips (GOODS/SERVICE) if the org's schema shows it (schema-driven form already renders API fields — verify `supply_nature` arrives as a choice field; if not, add it explicitly like `product_name`); tax-rate options include 40; 12/28 labelled "deprecated"; HSN 4–8 digit validation.
- Detail: deprecated-rate warning row; **Tax profile** card (tax treatment default, RCM outward, cess applicable; pinned variant read-only with "set from an invoice preview") behind `acc_setup` + active.

### 5.5 Helpdesk (`ticket.dart`, `tickets_remote_ds.dart`, `create_ticket_screen.dart`, `edit_ticket_screen.dart`, `ticket_detail_screen.dart`)

- `Ticket` gains `billable`, `billableAmount`, `billableProductId`, `billedDocumentLineId`; mapper reads them; create/update payload builder writes `billable`, `billable_amount`, `billable_product_id`.
- Create/edit: "Billable" switch revealing amount and product (one required).
- Detail: Billing row (billable · amount/product · Billed badge) and action **Bill this ticket** (active, `acc_document.canCreate`, not billed) → `from-ticket` → document detail (+ optional issue). Lock the billable fields once billed.

### 5.6 Operations (`project.dart`, `projects_remote_ds.dart`, `project_detail_screen.dart`)

- Parse `financials` (nullable) into `ProjectFinancials`; Details tab gains a **Financials** card (billed, collected, open AR, expenses, open AP, gross margin, as-of) when non-null; empty copy otherwise. No rederive on mobile.

### 5.7 People (`add_role_sheet.dart`)

Nothing structural: the accounting group arrives from the module catalog. Verify the capability rows render the 7-module group and its description, and that the visibility scope defaults to "all" for that group (the backend seeds "all" for accounting).

### 5.8 Shell, drawer, dashboard, billing

- Drawer entry + `planFeature` gate (3.3); `landingPathFor` unchanged otherwise.
- Bottom nav `NavContext.acc` items; contextual `+` actions.
- Dashboard Business tab: optional AR/AP tiles (R4).
- Billing screen: shows the plan's feature list from `/billing/plans/` already; add "Accounting" to the label map if one exists.
- `docs-flutter/permissions.md` and `roles.md`: document the seven modules and the approve meanings; add `docs-flutter/accounting.md` (mobile scope table = §1 of this plan).

---

## 6. Rules every accounting screen must obey

1. **No client-side money math.** Totals, tax, allocation, TDS come from the server (`preview-tax`, response bodies). Any client sum is a hint and is labelled as such.
2. **Post once.** `event_id` = a v4 UUID (add the pure-Dart `uuid` package; no toolchain impact) generated when the sheet opens, reused across retries of that submission, discarded on 2xx/4xx. Submit button disabled while pending. Never auto-retry a 409.
3. **Online only for posts.** Disable submit when offline; never queue.
4. **Invalidate broadly.** After any accounting write: accounting providers for documents, settlement, reports, home; plus `paymentsProvider`/`invoicesProvider` when the write came from a CRM screen (the existing `markRecordPaid` already evicts both Hive keys).
5. **Gate affordances on activation.** CRM screens render accounting affordances only when `accountingStatusProvider` is ACTIVE; a 404 profile means "not set up", not an error.
6. **Skipped posts** (`{skipped:true}`) are a distinct success toast.
7. **Money-posting endpoints ignore `is_staff`.** A System Admin without the seeded codename gets 403 on expenses/vendor bills; show the permission copy, not an error state.
8. **Read-only where §1 says so.** Do not add "just a quick" settle/close/journal button on mobile.

---

## 7. Error and warning handling (mobile)

`AppError.code` + `cause` drive a single `conflictCopy(code, cause)` function in `presentation/config/accounting_copy.dart` with the same table as web plan §7 (document guards, settlement codes, purchase/funding/registration, `APPROVAL_REQUIRED`, `PARTY_HAS_BOOKS`, `feature_not_in_plan`, `ACCOUNTING_NOT_ACTIVE`). `ConflictBanner` renders title + detail + up to three `cause` chips + one `next` action (`PIN_VARIANT_ON_PRODUCT` → product tax profile sheet; `ADD_HSN_TO_LINE` → void & recreate; `USE_A_LATER_DATE_OR_CREDIT_NOTE` → credit note sheet; `CONSOLE_VERIFY` → informational). Warnings (`warnings[]` objects `{code,…}` or strings) → `WarningsStrip` with the copy from web plan §7. `ApiService.failures` already surfaces every failed write as a toast; accounting sheets additionally render the banner inline so the user sees the `cause`.

---

## 8. Status vocabularies to add (`data/mock/status_meta.dart`, `data/api/status_keys.dart`)

- `accDocument`: DRAFT (grey), ISSUED (navy), CANCELLED (error), VOID_DRAFT (muted).
- `accPaymentState`: NA, UNPAID (error), PARTIAL (warning), PAID (success), WRITTEN_OFF (muted).
- `accReceipt`: POSTED (success), REVERSED (error); advance OPEN/PARTIALLY_ADJUSTED/ADJUSTED/REFUNDED; credit OPEN/PARTIALLY_APPLIED/APPLIED/REFUNDED/CANCELLED.
- `accEvent`: RECEIVED, PENDING_APPROVAL, POSTED, REJECTED, SKIPPED.
- `accPeriod`: book OPEN/CLOSED; GSTR-1 OPEN/FILED; GSTR-3B OPEN/FILED/SETTLED; TDS OPEN/DEPOSITED; FY OPEN/CLOSING/CLOSED/REOPENED.
- `accActivation`: INACTIVE, ACTIVATING, ACTIVE, SUSPENDED.

---

## 9. Testing (per repo standards, `test/features/accounting/`)

- Mapper tests with JSON fixtures for every entity in 3.1 (money strings preserved, nullable FKs, enum fold-backs, `warnings` as objects and strings).
- `AppError` tests for the 409 contract (`code`, `cause`, `next`), `feature_not_in_plan`, and the 200 `{skipped:true}` outcome.
- Repository fallback tests (Hive cache on network error) for documents, vendors, settlement lists, period register.
- `quote_draft` test: `product_id`, `line_discount`, `amounts_are`, `place_of_supply_state_code` in the create body.
- `markRecordPaid` body test: cash-only `amount_paid`, `tds_deducted`, `bank_charge`, chosen `paid_date`.
- Nav tests: drawer/bottom-nav visibility by module set and by plan feature; `landingPathFor` unaffected for roles without accounting.
- `flutter analyze` clean.

---

## 10. Delivery order

| Phase | Scope | Backend dependency |
|---|---|---|
| R0 — foundation | 3.2 endpoints, 3.3 plan-feature gate + drawer/bottom nav, 3.4 error model, 3.5 status provider, 3.6 money strings (fix defect c), 3.7 cache box, 3.8 widgets, 4.13 status screen | none |
| R1 — sales money path | 4.2, 4.3, 4.4, 4.5, 4.6, 4.7; 5.1 quotes (fix defect b), 5.2 plan/record/record-payment (fix defect a), 5.3 customer tax profile + Accounting tab, 5.4 product fields, 5.5 ticket billing | G-8 decision for old plans; share/print package decision (G-9) |
| R2 — money out & vendors | 4.8 (receipts/vendor payments/advances/credits), 4.9 expense + vendor bill, 4.10 vendors, 5.6 project financials | **G-1** before any receipt/expense/payment sheet ships with a bank option (CASH + default-bank interim is acceptable only if product agrees) |
| R3 — visibility | 4.1 home, 4.11 periods (read), 4.12 reports | none |
| R4 — polish | dashboard tiles, offline empty states, notification deep links to documents/receipts (need G-5 for receipts) | G-5, G-6 |

Sizing (screens/sheets): R0 ≈ 1 screen + 10 shared pieces; R1 ≈ 3 screens + 5 sheets + 5 existing-screen changes; R2 ≈ 3 screens + 7 sheets; R3 ≈ 3 screens + 6 report views. Roughly half of the web build, by design.
