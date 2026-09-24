# Clozr Accounting — Frontend & Flutter Integration Handover

**Backend:** `nexocrm-django-api`, branch `app/accounting-dev`, commit `f1be31a` (2026-09-23).
**Base path:** `/api/v1/accounting/` (JWT bearer auth, organisation taken from the token, same as every other module).
**Audience:** the web (React/Vite) and mobile (Flutter) developers building the accounting screens described in `ACCOUNTING_WEBAPP_PLAN.md` and `ACCOUNTING_FLUTTER_PLAN.md`. This document is the API contract those plans code against. Where the two disagree, this document wins because it was verified against the code at the commit above.

Everything below was read from the serializers, views and services on that commit, not from older design documents. The Extension Architecture and Appendix C in `docs/rulebook/` are out of date in places (paths and error codes); do not code against them.

---

## 0. What changed since the plans were written, and what is still open

The backend commit `f1be31a` closed the plan gaps **G-1, G-2, G-3, G-4, G-5, G-6, G-7, G-8, G-10, G-12, G-13**, and `b3e1254` tightened permissions (W2) and GSTIN validation (W5). Concretely:

| Now available | Where |
|---|---|
| Bank accounts list + create + narrow PATCH (`is_default`, `is_active`, `method_aliases`, `print_on_invoice`) | §8.2 |
| Loans list + create, HSN rate-variant picker, chart of accounts list, document series list, fiscal-year list | §8.2, §8.1, §8.7 |
| Detail reads for receipts, advances, customer credits, vendor payments, vendor advances, each with child allocation rows | §8.4 |
| Document list filters `vendor`, `project`, `search`; inward columns `vendor_invoice_no`, `rcm_applies`, `tds_amount`, `payable`, `paid_amount` on document rows | §8.3 |
| GSTR-1 / GSTR-3B "mark filed" endpoints | §8.7 |
| Tenant attributes auto-close the previous effective-dated row (no more 500 on a second write) | §8.1 |
| `Idempotency-Key` header allowed by CORS | §5 |
| `Payment.amounts_are` writable while the plan has no linked accounting document | §9.2 |
| Batch customer tax-profile lookup for list badges | §8.2 |
| Money endpoints no longer honour `is_staff`; a seeded accounting role is required | §3 |

**Still open on the backend** (each has a client-side rule in §12 — read that section before building the affected screen): no existing-draft guard on the create-invoice endpoints; credit-note refund leg cannot name a bank account and the split is not validated; duplicate active vendor name is a 500; the document list returns full nested rows (no slim list serializer); no endpoints for expense/revenue categories, TDS natures, asset classes (embed the seed vocabularies in §7); no `customer_name`/`vendor_name` on document or settlement rows; report query parameters are not validated; PDF is a 501; document lines cannot be edited after creation; purchases post immediately (no draft); no period reopen; project financial rollup is not scheduled; `payment_method` on CRM payment records is free text resolved by alias; the plan-gate 403 body is flattened by the global handler; `upgrade_url` on the standard permission path is still `/billing/plans`.

---

## 1. Reading this document

- Every endpoint entry gives: method + path, required permission codename, request body, response, and the errors that are specific to it. Cross-cutting errors (401, RBAC 403, plan 403, activation 409, validation 400) are described once in §4 and not repeated.
- "Money" means a decimal **string** with two decimals (`"1250.00"`). Send strings, never floats. The one exception is the GST settlement proposal (§8.7), which uses integer rupees.
- Dates are `YYYY-MM-DD` in IST. Datetimes are ISO 8601 with offset.
- All ids are UUID strings. Foreign keys serialise as the target's public UUID (`customer` on a document is the CRM `customer_id`), never an integer primary key.
- `[req]` marks a required field. Everything else is optional.

---

## 2. Gating and how to decide what to render

Every accounting view runs three checks in this order, and a caller who fails an earlier check never learns the answer to a later one:

1. **RBAC** (module permission codename) → 403.
2. **Plan feature** `accounting` → 403.
3. **Activation** (tenant profile `activation_status == "ACTIVE"`) → 409 `ACCOUNTING_NOT_ACTIVE`. The setup endpoints (§8.1) skip this check; everything else enforces it.

Decide what to render from three pre-checks, not from error bodies:

| Question | Call | Read |
|---|---|---|
| Does this user hold accounting permissions? | `GET /api/v1/auth/me/modules/` | `modules.acc_document`, `modules.acc_setup`, … each `{label, can_read, can_create, can_update, can_delete, can_export, can_import, can_approve}`; `full_access` true for staff/superuser; `sidebar` lists readable modules in order. Cached 5 min server-side. |
| Is accounting in the plan? | `GET /api/v1/billing/features/me/` | `{plan, features: {accounting: bool, …}}` |
| Is accounting activated for this org? | `GET /api/v1/accounting/setup/tenant-profile/` (needs `view_acc_setup`) | `activation_status` ∈ `INACTIVE | ACTIVATING | ACTIVE | SUSPENDED`; 404 means the profile was never created. |

There is no activation endpoint readable without `view_acc_setup`. For a user who lacks it (the seeded CRM User, Accountant and Finance Viewer roles do not have `acc_setup`), the only signal is a 409 `ACCOUNTING_NOT_ACTIVE` from any accounting read. Both plans already do this: on app start, if the user has any `acc_*` read permission and the plan has the feature, fire one harmless GET (`GET accounting/documents/?page_size=1`) and cache "active"/"inactive" for the session; treat 409 `ACCOUNTING_NOT_ACTIVE` as inactive and hide the accounting navigation except the setup wizard entry.

---

## 3. Permissions

Seven RBAC modules; codenames are `<action>_<module>` with actions `view, create, update, delete, approve, export, import`.

| Module | Guards | `approve` means |
|---|---|---|
| `acc_setup` | tenant profile, tenant attributes, gates, activate, chart of accounts, series, bank accounts, party and product tax profiles, customer tax-profile batch | — |
| `acc_document` | sales documents (invoices, notes), render context, HSN rate picker | issue and cancel a document |
| `acc_purchase` | vendors, vendor bills, vendor notes, fixed assets, expenses | — |
| `acc_settlement` | receipts, advances, credits, vendor payments, vendor advances | — |
| `acc_period` | period register, fiscal years, checklists, GST settlement, challans, TDS deposit, income tax, closes, opening balances, filings | settle GST, close book/FY, mark GSTR filed |
| `acc_journal` | manual journal, ledger entries, ledger events, funding/banking forms, loans | control-account or reversing manual journal |
| `acc_report` | every report, project financials | — (`create` = rederive, `export` = CSV export) |

**Seeded roles** (created by `backfill_accounting_permissions --create-roles`): *Accountant* (all seven, full), *Finance Viewer* (read only, no export), *CRM User* grant (`acc_document` read/create/update/approve + `acc_settlement` read/create). A user with no accounting role gets 403 on everything, including staff users: **`is_staff` no longer bypasses money-posting endpoints** (all purchases forms, funding/banking forms, manual journal, every settlement write, every period posting/close/filing). Only a superuser bypasses. Do not QA the permission handling as a superuser.

Record-level visibility does not apply to accounting: a user with `view_acc_document` sees every document in the organisation.

The module catalog (`GET /api/v1/management/permissions/module-catalog/`) lists the `accounting` group with its seven modules and labels ("Accounting Setup", "Accounting Document", …). The role editor should render it like any other group; there is no per-module help text, so the "approve means" column above is the copy to use.

---

## 4. Error bodies

Four shapes reach the client. Map all four in one place (`toFailure` on web, `AppError` on Flutter).

**A. Structured guard (409, sometimes 400).** Every accounting business rule, the activation gate, and the CRM mark-paid veto:
```json
{"code": "CANCEL_NOT_ALLOWED", "cause": {"reason": "HAS_RECEIPT"}, "detail": "This document cannot be cancelled.", "next": "REVIEW_DOCUMENT_STATE"}
```
`code` is a machine string. `cause` is always an object (may be empty). `rule` and `next` are optional. The full code index is in Appendix B.

**B. Flattened (401, 403, 404, 405, 429).** Anything DRF raises with a `detail` string, after the global handler:
```json
{"code": 403, "message": "You do not have permission to perform this action."}
```
`code` is the **integer** HTTP status here. The plan-feature 403 comes out of the same flattening as `{"code": 403, "message": "Your current plan does not include this feature."}`; the `feature_not_in_plan` machine code, `current_plan` and `upgrade_url` do not survive the handler on the current commit. Distinguish plan-403 from RBAC-403 by the pre-checks in §2, never by parsing the message. Never render `upgrade_url` even when present; route to `/billing` (web) or "Upgrade on the web app" (mobile).

**C. Validation (400).** Serializer errors:
```json
{"code": 400, "message": "Validation Error", "errors": {"document_date": ["This field is required."]}, "error_codes": {"gstin": ["custom_code"]}}
```
`error_codes` is present only when a field carries a non-generic code. List-query validation (bad enum, page over 200, non-UUID filter) is also this shape.

**D. Ad-hoc view responses.** A handful of views return their own body without going through the handler. They keep exactly this shape:

| Endpoint | Status | Body |
|---|---|---|
| `PATCH documents/{id}/` on a non-draft | 409 | `{"code": "NOT_DRAFT", "detail": "...", "cause": {"status": "ISSUED"}}` |
| `PUT masters/parties/…/tax-profile/` with a bad GSTIN | 400 | `{"code": "GSTIN_INVALID", "detail": "...", "cause": {"gstin": "..."}}` |
| `GET reports/general-ledger/` without an account | 400 | `{"code": "ACCOUNT_REQUIRED", "detail": "..."}` |
| `POST reports/export/` with an unknown report | 400 | `{"code": "UNKNOWN_REPORT", "detail": "..."}` |
| `GET documents/{id}/pdf/` | 501 | `{"code": "PDF_NOT_IMPLEMENTED", "detail": "..."}` |
| `GET documents/{id}/journal/` | 501 | `{"detail": "...", "posted_journal_entry_id": null, "entries": []}` |
| any "not found" inside an accounting view (payment record, issue, vendor, receipt, GST period, …) | 404 | `{"detail": "Payment record not found."}` |
| party kind other than `customer`/`vendor` | 400 | `{"detail": "party_kind must be 'customer' or 'vendor'."}` |
| idempotent replay / test-source skip on a settlement, form or manual journal | 200 | `{"detail": "Event skipped (test source or before ledger start).", "skipped": true}` |

Rule for the mapper: if the body has a string `code`, it is A or D (use `code`, `cause`, `detail`); if `code` is a number, it is B or C (use `message`, `errors`); if there is only `detail`, it is a 404/400 from D.

**Warnings** (not errors) are a list of objects on documents, previews and forms: `[{"code": "LATE_INVOICE", "supply_date": "...", "document_date": "..."}]`. No message text is sent; the client owns the copy. Known codes: `POS_OVERRIDES_PARTY_STATE {pos, party_state}`, `POS_DEFAULTED_TO_TENANT {pos}`, `HSN_DIGITS_MISSING {line_no, required_digits, level}`, `LATE_INVOICE {supply_date, document_date}`, `DRAFT_CONFIG_USED {rows}`, `LATE_POSTED {original_date}`, `QUOTE_RATE_DIFFERS {line_no, quote_rate_pct, resolved_rate_pct}` (preview only), `CASH_LIMIT_WARNING`, `ITC_CLAIM_SHIFTED`, `RCM_LIABILITY_SHIFTED` (purchases).

**500s** are real bugs. The client shows a generic error and includes the request id if the transport exposes one. Two known 500s the client must pre-empt are listed in §12.

---

## 5. Idempotency and double-submit

Endpoints that post to the ledger accept an idempotency key and de-duplicate a retry with the same key + same payload:

- Header `Idempotency-Key: <client uuid>` **or** body field `event_id`. The header is now CORS-allowed; both clients standardise on **body `event_id`** (a v4 UUID generated when the form opens and kept for the life of that submit including retries) so behaviour is identical on web and mobile.
- Accepted by: every `settlement/*` write, every `purchases/*` and `forms/*` form, `journal/manual/`. Same key + different payload → 409 `ACCOUNTING_POSTING_REJECTED` with `cause.code = "IDEMPOTENCY_PAYLOAD_MISMATCH"`. Same key + same payload → the original result (or the `{skipped: true}` 200 for a skipped event).
- **Not accepted by** the document creation endpoints (`documents/invoices/`, `from-payment-record/`, `from-ticket/`, `credit-notes/`, `debit-notes/`), `issue`, `cancel`, `void`, the period endpoints, or masters. For these the client must disable the control after the first tap and never auto-retry a timeout without reading state first (§12.1).

---

## 6. Conventions

- **Pagination** (all lists): `?page=&page_size=` (max 200; over 200 is a 400, not clamped). Response `{"count", "next", "previous", "results": [...]}`. A page past the end is a 404 `{"code": 404, "message": "Invalid page."}`.
- **List filters** are validated: unknown enum values → 400 (shape C); unknown filter names are ignored. `is_active`-style booleans must be the literal strings `true`/`false`.
- **Ordering** is fixed per list and there is no `ordering` parameter. Do not offer server-side column sort.
- **Search** where present is case-insensitive "contains" on the fields named in the endpoint entry.
- **The five document dates**: `document_date` (what the client sets; the invoice date), `supply_date` (optional; date of supply), `tos_date` (time of supply), `rate_basis_date`, `posting_date` — the last three are derived by the backend at issue from `document_date`/`supply_date` and must be displayed read-only. `due_date` is a sixth, optional, client-set date.
- **Draft totals are provisional.** `taxable_total`, tax heads and `grand_total` on a DRAFT are recomputed at issue (rates, place of supply, reverse charge). Label them "estimated" until `status == "ISSUED"`.
- **Party snapshot.** `party_snapshot` on a document is the frozen party identity at issue (`gstin`, registration, state). On credit/debit notes it also carries `settlement` (the applied/refund/held split as strings). Treat it as read-only display data.

---

## 7. Vocabularies

### 7.1 Enumerations (from `accounting/constants.py`)

| Field | Values |
|---|---|
| `doc_type` | `TAX_INVOICE, BILL_OF_SUPPLY, EXPORT_INVOICE, CREDIT_NOTE, DEBIT_NOTE, RECEIPT_VOUCHER, REFUND_VOUCHER, SELF_INVOICE, PAYMENT_VOUCHER, VENDOR_BILL, VENDOR_CREDIT_NOTE, VENDOR_DEBIT_NOTE, PROFORMA` |
| `direction` | `OUTWARD` (first eight above) / `INWARD` (last five) — derived, never sent |
| document `status` | `DRAFT, ISSUED, CANCELLED, VOID_DRAFT` |
| `payment_state` | `NA, UNPAID, PARTIAL, PAID, WRITTEN_OFF` |
| `transaction_class` | `B2B, B2C, B2CL, EXPORT_LUT, EXPORT_WITH_TAX, SEZ, DEEMED, RCM_INWARD, IMPORT_SERVICE, NON_GST` |
| `tax_treatment` | `TAXABLE, NIL, EXEMPT, NON_GST, ZERO_RATED, RCM_OUTWARD` |
| `supply` | `INTRA, INTER` |
| `supply_nature` | `GOODS, SERVICE` |
| `amounts_are` | `EXCLUSIVE, INCLUSIVE` |
| `source_type` | `PLAN_RECORD, MILESTONE, PERIODIC, TICKET, MANUAL, OPENING, EXPENSE_FORM, BANK_FORM, PROVIDER_BILLING` |
| note `reason_code` | `RETURN, VALUE_CORRECTION, RATE_CORRECTION, DISCOUNT` |
| `itc_status` (tax line) | `NA, PENDING, ELIGIBLE, CLAIMED, BLOCKED, NOT_IN_2B, REVERSED_R37, RECLAIMED, LAPSED_16_4, REVERSED_CN` |
| tax `head` | `CGST, SGST, IGST, CESS`; `direction` `OUTPUT, INPUT, OUTPUT_RCM, INPUT_RCM` |
| `billing_mode` | `INVOICE_ON_DUE, INVOICE_ON_COMPLETION, PERIODIC, MANUAL` |
| `entity_type` (tenant) | `PROPRIETOR, PARTNERSHIP, LLP, PVT_LTD` |
| `entity_kind` (party) | `INDIVIDUAL_HUF, COMPANY, FIRM, OTHER` |
| party `registration_type` | `REGISTERED, UNREGISTERED, COMPOSITION, SEZ, OVERSEAS, GOVERNMENT` |
| `return_frequency` | `MONTHLY, QRMP` |
| `revenue_granularity` | `SINGLE, BY_CATEGORY` |
| `activation_status` | `INACTIVE, ACTIVATING, ACTIVE, SUSPENDED` |
| bank account `kind` | `BANK, CASH, GATEWAY` |
| fiscal year `status` | `OPEN, CLOSING, CLOSED, REOPENED`; book period `OPEN, CLOSED`; `gstr1_status` `OPEN, FILED`; `gstr3b_status` `OPEN, FILED, SETTLED`; TDS period `OPEN, DEPOSITED` |
| receipt `kind` / `status` / `treat_as` | `B3, B5, B8, B12` / `POSTED, REVERSED` / `ALLOCATED, ADVANCE, CUSTOMER_CREDIT` |
| receipt `source_account_kind` | `BANK, CASH, GATEWAY` |
| advance `status` | `OPEN, PARTIALLY_ADJUSTED, ADJUSTED, REFUNDED` |
| customer credit `source` / `status` | `OVERPAYMENT, UNAPPLIED_RECEIPT, CREDIT_NOTE_HOLD` / `OPEN, PARTIALLY_APPLIED, APPLIED, REFUNDED, CANCELLED` |
| credit application `kind` | `APPLY, REFUND, CONVERT_TO_ADVANCE` |
| vendor payment `kind` / `status` / `source_account_kind` | `D2, D4, A3_PAY` / `POSTED, REVERSED` / `BANK, CASH, OWNER` |
| vendor advance `status` | `ACTIVE, RELEASED` |
| loan `status` | `ACTIVE` or closed (the list exposes `is_active`) |
| ledger event `status` | `RECEIVED, PENDING_APPROVAL, POSTED, SKIPPED, REJECTED` |
| checklist item `severity` / `status` | `BLOCK, WARN, INFO` / `PASS, FAIL` |

### 7.2 Role strings (account references in forms)

Wherever a form takes `source_account`, `to_account`, `target`, or a manual-journal `role`, it is a **role string**, not an account UUID:

| Pattern | Meaning | Where the instance id comes from |
|---|---|---|
| `CASH` | cash in hand | — |
| `BANK:<bank_account_id>` | a bank account | `GET masters/bank-accounts/` (the create response also returns the ready-made `role`) |
| `GATEWAY_CLEARING:<provider>` | payment gateway clearing | `provider` of a `GATEWAY` kind bank account |
| `EXPENSE:<CATEGORY>` | an expense head | §7.3 expense categories |
| `PURCHASES` | trading purchases | — |
| `FIXED_ASSET:<asset_class_key>` | an asset class | §7.3 asset classes |
| `LOAN:<loan_id>` | a loan | `GET masters/loans/` |
| `OWNER` | owner's funds (sole proprietor) | — |
| `CAPITAL`, `DRAWINGS`, `PARTNER_CURRENT:<partner>` | equity | partner is a free label |
| `GST_CASH_LEDGER` | GST electronic cash ledger | default for GST interest/late fee |
| `REVENUE:<CATEGORY>` | revenue head | §7.3 revenue categories |

Non-instanced roles usable on a manual journal are the `role` column of the seed file `16b_role_bucket.csv` (78 rows, e.g. `AR`, `AP`, `OUTPUT_CGST`, `INPUT_IGST`, `TDS_RECEIVABLE`, `EXP_BANK_CHARGES`, `ROUND_OFF`). Roles marked `is_control` (`AR`, `AP`, `OUTPUT_*`, `INPUT_CGST/SGST/IGST`, `ADVANCE_CUSTOMER`, `CUSTOMER_CREDIT`, `VENDOR_ADVANCE`) require `allow_control_accounts: true` and `approve_acc_journal`.

### 7.3 Seed vocabularies (no endpoint; embed as constants, pack `v2026.09.20`)

**Expense categories** (`target` = `EXPENSE:<key>`; ITC column tells the UI whether to show an ITC hint):

`RENT_PREMISES, RENT_EQUIPMENT, RENT_RESIDENTIAL_STAFF, ELECTRICITY_WATER, TELECOM_INTERNET, SOFTWARE_SAAS_DOMESTIC, SOFTWARE_CLOUD_IMPORTED, PROFESSIONAL_FEES, LEGAL_FEES, AUDIT_ACCOUNTING, TECHNICAL_SERVICES, CONTRACTORS_JOBWORK, MANPOWER_SUPPLY, SECURITY_SERVICES, HOUSEKEEPING, FREIGHT_GTA, COURIER_POSTAGE, ADVERTISING_MARKETING, SPONSORSHIP, COMMISSION_BROKERAGE, DIRECTOR_FEES, PARTNER_REMUNERATION, STAFF_WELFARE_FOOD, STAFF_INSURANCE, TRAVEL_FARES, TRAVEL_HOTEL, VEHICLE_HIRE, FUEL, VEHICLE_REPAIRS_INSURANCE, INSURANCE_BUSINESS, REPAIRS_BUILDING, REPAIRS_EQUIPMENT, PRINTING_STATIONERY, OFFICE_SUPPLIES, GIFTS_SAMPLES, ENTERTAINMENT_MEALS, CLUB_MEMBERSHIP, CSR, DONATIONS, RATES_TAXES_LICENCES, TRAINING_RECRUITMENT, SUBSCRIPTIONS_TRADE_BODIES, PENALTIES_FINES, MISCELLANEOUS`

Blocked-ITC categories (show "no input credit"): `STAFF_WELFARE_FOOD, STAFF_INSURANCE, VEHICLE_HIRE, VEHICLE_REPAIRS_INSURANCE, GIFTS_SAMPLES, ENTERTAINMENT_MEALS, CLUB_MEMBERSHIP, CSR`. Not applicable (no GST): `ELECTRICITY_WATER, PARTNER_REMUNERATION, FUEL, DONATIONS, RATES_TAXES_LICENCES, PENALTIES_FINES`. Default TDS nature per category is in the seed CSV `16c_expense_categories.csv` (e.g. `RENT_PREMISES → RENT_LAND_BUILDING`, `PROFESSIONAL_FEES → PROFESSIONAL`, `CONTRACTORS_JOBWORK → CONTRACTOR`); the backend applies it automatically, the UI only needs it to pre-fill `tds_nature_override` when the user opens that field.

**Revenue categories** (`REVENUE:<key>`): `SALES_GOODS, SALES_SERVICES, SUBSCRIPTION_AMC, PROJECT_REVENUE, EXPORT, INTEREST_INCOME, BAD_DEBT_RECOVERED, MISC_INCOME, DISCOUNT_RECEIVED`.

**TDS natures** (`tds_nature`, `tds_nature_override`, `tds_nature_default`): `SALARY (192), INTEREST (194A), CONTRACTOR (194C), COMMISSION (194H), RENT_PLANT (194I(a)), RENT_LAND_BUILDING (194I(b)), PROFESSIONAL (194J(b)), TECHNICAL (194J(a)), DIRECTOR_FEES (194J(1)(ba)), PURCHASE_OF_GOODS (194Q), PARTNER_REMUNERATION (194T), DIVIDEND (194), BENEFIT_PERQUISITE (194R), FOREIGN_PAYMENT (195)`. Show the section in brackets; accountants think in sections.

**Asset classes** (`asset_class_key`): `LAND, BUILDING_RCC, BUILDING_NON_RCC, FACTORY_BUILDING, TEMPORARY_STRUCTURE, LEASEHOLD_IMPROVEMENTS, PLANT_MACHINERY, FURNITURE_FITTINGS, ELECTRICAL_INSTALLATIONS, OFFICE_EQUIPMENT, COMPUTERS_END_USER, SERVERS_NETWORKS, COMPUTER_SOFTWARE, MOTOR_CAR, TWO_WHEELER, GOODS_VEHICLE, INTANGIBLES, GOODWILL`. Classes with blocked ITC: `LAND, BUILDING_*, FACTORY_BUILDING, TEMPORARY_STRUCTURE, LEASEHOLD_IMPROVEMENTS, MOTOR_CAR, TWO_WHEELER`.

**Series default prefixes** (display only; the real series come from `GET setup/series/`): `TAX_INVOICE INV, BILL_OF_SUPPLY BOS, EXPORT_INVOICE EXP, CREDIT_NOTE CN, DEBIT_NOTE DN, RECEIPT_VOUCHER RV, REFUND_VOUCHER RFV, SELF_INVOICE SINV, PAYMENT_VOUCHER PV, VENDOR_BILL VB, VENDOR_CREDIT_NOTE VCN, VENDOR_DEBIT_NOTE VDN, PROFORMA PRO`; format `PREFIX/26-27/0001`.

**GST state codes**: `GET /api/v1/organizations/states/` → `[{code: "32", name: "Kerala", alpha: "KL"}, …]` (38 rows, any authenticated user, cache for the session).

### 7.4 Tenant attribute value shapes (`POST setup/tenant-attributes/`)

`value` is JSON. The backend unwraps these keys:

| `attribute` | `value` | Notes |
|---|---|---|
| `REGISTRATION_STATUS` | `{"status": "REGISTERED" \| "UNREGISTERED" \| "COMPOSITION"}` | Gate G2. `COMPOSITION` is refused at activation. |
| `GSTIN` | `{"gstin": "32AAAAA0000A1Z5"}` | Gate G2/G5; exactly one per workspace. |
| `ITC_ALLOWED` | `{"value": true}` | Gate G4, required explicitly. |
| `IS_TDS_DEDUCTOR` | `{"value": true}` | Gate G4; if true the profile needs `tan`. |
| `RULE_86B_EXEMPT` | `{"value": true}` | Optional; read by the GST proposal. |
| `PREV_FY_TURNOVER`, `RETURN_FREQUENCY` | `{"value": …}` | Accepted and stored; not read by any gate on this commit. Prefer `return_frequency` on the tenant profile. |

Any attribute name is accepted (free text); only the ones above have behaviour.

### 7.5 Party attribute value shapes (read side of the party tax profile)

`attributes[]` rows: `REGISTRATION_TYPE → {"type": "REGISTERED"}`, `GSTIN → {"gstin": "…"}`, `STATE → {"state_code": "32"}`. Older rows may hold a bare scalar; unwrap defensively.

---

## 8. Endpoint reference

All paths are relative to `/api/v1/accounting/`. "Perm" is the codename the caller must hold (superuser excepted). Bodies are JSON.

### 8.1 Setup and activation (`acc_setup`) — not behind the activation gate

| Method & path | Perm | Notes |
|---|---|---|
| `GET setup/tenant-profile/` | `view_acc_setup` | 200 profile; 404 `{detail}` when never created. |
| `PUT` or `POST setup/tenant-profile/` | `update_acc_setup` | First call creates (201, send all required fields); later calls are partial updates (200). |
| `GET setup/tenant-attributes/` | `view_acc_setup` | `[{attribute, value, effective_from, effective_to}]`, all rows including closed ones, ordered by attribute then newest first. |
| `POST setup/tenant-attributes/` | `update_acc_setup` | `{attribute [req], value [req] (JSON, §7.4), effective_from [req], effective_to, note}` → 201 `{attribute_id, attribute}`. A prior row that started earlier is closed at `effective_from − 1`; a prior row starting on/after `effective_from` is replaced. |
| `GET setup/gates/` | `view_acc_setup` | `{gates: [{gate: "G1"…"G10", passed, detail}], can_activate, activation_status}`; 404 without a profile. |
| `POST setup/activate/` | `create_acc_setup` | `{series_starts: {"TAX_INVOICE": 42, …}, on_date}` (both optional) → 200 `{activation_status, gate_report}`. 409 `GATE_FAILED_G<n>` with `cause.gate`; 409 `CONFIG_NOT_VERIFIED` (`next: "CONSOLE_VERIFY"`) on environments that require verified config. Seeds the chart of accounts, role map, series and the 12 book/GST/TDS periods. |
| `GET setup/accounts/?is_active=&page=` | `view_acc_setup` | Chart of accounts: `{account_id, code, name, bucket, is_active}`, ordered by code. |
| `GET setup/series/?page=` | `view_acc_setup` | `{series_id, doc_type, prefix, next_number, fiscal_year, fiscal_year_label, is_default}`, ordered by doc_type, prefix. Read-only. |

**Tenant profile fields:** `profile_id` (ro), `entity_type` (§7.1), `legal_name`, `pan`, `tan`, `state_code`, `ledger_start_date` (must be the first day of a month, gate G7), `settlement_tolerance` (money, default `10.00`), `default_billing_mode`, `default_amounts_are`, `sells_goods`, `exports`, `sells_on_marketplace`, `has_employees` (booleans), `revenue_granularity`, `return_frequency`, `no_itc_output_scheme` (`NONE | ALL_SUPPLIES`), `inventory_method`, `activation_status` (ro), `activated_at` (ro), `gate_report` (ro, the last gate evaluation).

**Gates** (what the wizard must satisfy): G1 profile has `entity_type`, `state_code`, `pan` · G2 `REGISTRATION_STATUS` set; `REGISTERED` needs a valid `GSTIN`; `COMPOSITION` refused · G3 FY is April–March (informational) · G4 `ITC_ALLOWED` and `IS_TDS_DEDUCTOR` set explicitly; `tan` when deductor · G5 exactly one GSTIN · G6 the ledger holds no entries (workspace reset guard) · G7 `ledger_start_date` set and day == 1 · G8 currency INR · G9 every open payment plan carries `amounts_are` and `billing_mode` · G10 config verified (production only).

**Ordering constraint the plans got wrong:** every masters endpoint (§8.2), bank accounts included, sits behind the activation gate, so "register bank accounts" and "mark customers B2B" are **post-activation** wizard steps, not pre-activation ones.

### 8.2 Masters

Every endpoint in this section is behind the activation gate (409 `ACCOUNTING_NOT_ACTIVE` before `setup/activate/` succeeds). That includes vendors, party and product tax profiles, bank accounts, loans and the HSN picker, so "mark a customer B2B" and "register a bank account" are post-activation steps.

**Vendors** (`acc_purchase`)

| Method & path | Perm | Notes |
|---|---|---|
| `GET masters/vendors/?is_active=&search=&page=` | `view_acc_purchase` | `search` matches `name` / `legal_name`; ordered by name. |
| `POST masters/vendors/` | `create_acc_purchase` | 201. |
| `GET / PUT / PATCH masters/vendors/{vendor_id}/` | view / update | |
| `DELETE masters/vendors/{vendor_id}/` | `delete_acc_purchase` | 409 `PARTY_HAS_BOOKS` (`cause: {party, party_id}`) once any book references it. Offer "Deactivate" (PATCH `is_active: false`) as the primary action. |

Fields: `vendor_id` (ro), `name` [req], `legal_name`, `email`, `phone`, `address`, `state_code`, `bank_account_no_masked`, `ifsc`, `is_body_corporate`, `is_gta_fcm_opted`, `is_small_transporter_declared`, `is_active`, `notes`. A duplicate active `name` (case-insensitive) is a **500** on this commit (§12.3).

**Party tax profile** (`acc_setup`) — customers and vendors

| Method & path | Perm | Notes |
|---|---|---|
| `GET masters/parties/{customer\|vendor}/{party_id}/tax-profile/` | `view_acc_setup` | 404 `{detail}` when the party has no profile yet (treat as "unregistered, no GSTIN"). |
| `PUT masters/parties/{customer\|vendor}/{party_id}/tax-profile/` | `update_acc_setup` | Creates (201) or updates (200). Bad GSTIN checksum → 400 `{code: "GSTIN_INVALID", cause: {gstin}}`; wrong length → validation 400. |
| `GET masters/parties/customer/tax-profiles/?ids=<uuid,uuid,…>` | `view_acc_setup` | Up to 200 ids, deduplicated. `{results: [{customer_id, registration_type, gstin, state, is_b2b}]}`; unknown customers come back with nulls and `is_b2b: false`. Two queries regardless of count — use it for list badges. |

Read shape: `{party_tax_profile_id, party_kind, party_id, state_code, pan, entity_kind, tds_applicable, is_body_corporate, currency, tds_nature_default, attributes: [{attribute, value, effective_from, effective_to}]}` (§7.5 for value shapes).
Write body: `state_code` (2 chars), `pan`, `entity_kind`, `tds_applicable`, `is_body_corporate`, `currency` (3), `tds_nature_default` (§7.3), `registration_type`, `gstin` (15), `effective_from` (defaults to today). `registration_type`, `gstin` and `state_code` become effective-dated attributes; earlier rows are closed automatically.

**Product tax profile** (`acc_setup`)

| Method & path | Perm | Notes |
|---|---|---|
| `GET masters/products/{product_id}/tax-profile/` | `view_acc_setup` | `{product_tax_profile_id, product_id, tax_treatment_default, rate_variant_key, is_rcm_outward, cess_applicable}`; 404 when none. |
| `PUT masters/products/{product_id}/tax-profile/` | `update_acc_setup` | Body: `tax_treatment_default` (`TAXABLE\|NIL\|EXEMPT\|NON_GST`), `rate_variant_key` (from the HSN picker), `is_rcm_outward`, `cess_applicable`. |

The product's own `hsn_sac`, `tax_rate` and `supply_nature` are CRM product fields (§9.4), not part of this profile.

**Bank accounts** (`acc_setup`, behind the activation gate)

| Method & path | Perm | Notes |
|---|---|---|
| `GET masters/bank-accounts/?is_active=&page=` | `view_acc_setup` | Ordered default first, then name. |
| `POST masters/bank-accounts/` | `create_acc_setup` | `{name [req], kind (BANK\|CASH\|GATEWAY, default BANK), provider (required for GATEWAY), account_no_masked, ifsc, branch, is_default}` → 201 `{bank_account_id, gl_account_id, role}` where `role` is the ready-to-use role string. |
| `PATCH masters/bank-accounts/{bank_account_id}/` | `update_acc_setup` | Only `is_default`, `is_active`, `method_aliases` (list of strings), `print_on_invoice`; anything else is silently ignored. `is_default: true` clears the other defaults. Returns the full row. |

Row: `{bank_account_id, name, kind, account_no_masked, ifsc, branch, provider, method_aliases, is_default, is_active, print_on_invoice, gl_account_code, gl_account_name}`. `method_aliases` are the lower-case payment-method strings (e.g. `["upi", "neft", "card"]`) that CRM payment records with that `payment_method` should book to this account (§9.1).

**Loans** (`acc_journal`)

| Method & path | Perm | Notes |
|---|---|---|
| `GET masters/loans/?is_active=&is_bank=&page=` | `view_acc_journal` | `{loan_id, lender, lender_name, is_bank, principal, opening_balance, status, is_active, gl_account_code, gl_account_name}`. No outstanding balance, rate or tenure on the model; outstanding = general ledger closing balance of `gl_account_code` (§8.8). |
| `POST masters/loans/` | `create_acc_journal` | `{lender_name [req], is_bank, principal, opening_balance}` → 201 `{loan_id, gl_account_id, role}`. |

**HSN / SAC rate variants** (`acc_document`)

`GET masters/hsn-rates/?hsn=<prefix>&supply_nature=GOODS|SERVICE&on_date=` (`view_acc_document`) → `{hsn, supply_nature, on_date, results: [{hsn_sac, variant_key, rate_pct, cess_pct, treatment, description, is_default_variant, match_level}]}`. Longest-prefix ladder (goods 8→6→4→2, services 6→4). Use it for the variant picker when issue returns `RATE_VARIANT_REQUIRED`, and to show the resolved rate on a product form.

### 8.3 Sales documents (`acc_document`)

**Document row** (identical on list and detail):
`document_id, doc_type, direction, number, fiscal_year (uuid), document_date, supply_date, tos_date, rate_basis_date, posting_date, due_date, customer (uuid), vendor (uuid), vendor_invoice_no, rcm_applies, tds_amount, payable, paid_amount, place_of_supply_state_code, supply, transaction_class, amounts_are, currency, taxable_total, tax_cgst, tax_sgst, tax_igst, tax_cess, round_off, grand_total, status, issued_at, issued_by, cancelled_at, cancelled_by, cancel_reason, payment_state, open_balance, settled_by, references_document (uuid), reason_code, with_gst, legacy_rate, source_type, source_id, quotation_id, payment_plan_id, payment_record_id, project (uuid), narration, terms, notes, warnings[], config_draft_rows[], party_snapshot{}, lines[], tax_lines[]`.
Line: `line_id, line_no, product (uuid), description, hsn_sac, supply_nature, qty, unit, unit_price, line_discount, taxable, tax_treatment, rate_pct, cess_pct, rate_variant_key, rate_match_level, tax_cgst, tax_sgst, tax_igst, tax_cess, recognition, service_period_start, service_period_end, quotation_line_item_id, issue_id`.
Tax line: `tax_line_id, head, direction, amount, rate_pct, gst_period (uuid), itc_status`.
No party names on the row (§12.5).

| Method & path | Perm | Request | Response / errors |
|---|---|---|---|
| `GET documents/` | `view_acc_document` | Filters: `doc_type`, `status`, `payment_state` (enums, validated), `transaction_class`, `customer`, `vendor`, `project` (uuids), `source_type`, `date_from`, `date_to` (on `document_date`), `search` (≤64 chars; contains on `number` and `vendor_invoice_no`), `page`, `page_size`. | Paginated rows, ordered `-document_date, -issued_at`. Full nested rows: keep `page_size` ≤ 50 on mobile. |
| `GET documents/{document_id}/` | `view_acc_document` | | Row. |
| `PATCH documents/{document_id}/` | `update_acc_document` | DRAFT only. Fields: `document_date, supply_date, due_date, place_of_supply_state_code, amounts_are, narration, terms, notes`. | Row. Non-draft → 409 `{code: "NOT_DRAFT", cause: {status}}`. Lines are not editable (§12.8). |
| `POST documents/invoices/` | `create_acc_document` | `{doc_type (default TAX_INVOICE; send only TAX_INVOICE, BILL_OF_SUPPLY, EXPORT_INVOICE or PROFORMA), document_date [req], supply_date, due_date, customer (uuid), place_of_supply_state_code, amounts_are, narration, lines [req]: [{line_no, product (uuid), description, hsn_sac, supply_nature, qty (3 dp, default 1), unit_price (6 dp), line_discount, rate_pct, tax_treatment (default TAXABLE)}]}` | 201 DRAFT row. Unknown customer/product ids are silently dropped to null, so resolve them before posting. |
| `POST documents/invoices/from-payment-record/` | `create_acc_document` | `{payment_record [req], document_date [req], supply_date}` | 201 DRAFT row (lines pro-rated from the plan/quote). 404 `{detail}`. **Creates a new draft every call** (§12.1). |
| `POST documents/invoices/from-ticket/` | `create_acc_document` | `{issue [req], document_date (default today), supply_date}` | 201 one-line DRAFT row. 404 `{detail}`. No billable/already-billed check (§12.24). |
| `POST documents/{id}/preview-tax/` | `view_acc_document` | none | `{document_id, supply, transaction_class, tax_treatment, amounts_are, lines: [{line_no, hsn_sac, supply_nature, tax_treatment, taxable, tax_cgst, tax_sgst, tax_igst, tax_cess, match_level, variant_key, rate_pct, cess_pct, rate_row_id, treatment}], totals: {taxable_total, tax_cgst, tax_sgst, tax_igst, tax_cess, round_off, grand_total}, config_rows: [{table, row_id, hsn_sac, variant_key, rate_pct, verification_status, confidence}], warnings: [{code: "QUOTE_RATE_DIFFERS", line_no, quote_rate_pct, resolved_rate_pct} \| {code: "HSN_DIGITS_MISSING", line_no, required_digits, level}]}`. The rate fields are null on a line that resolved to no rate row. Side-effect free; call it before issue and on every header change. |
| `POST documents/{id}/issue/` | `approve_acc_document` | `{advance_adjustments: [{advance_id, amount}]}` (optional; adjusts open taxed advances of the customer against this invoice) | 200 ISSUED row with `number`, derived dates, recomputed totals, tax lines and `warnings`. 409 codes: `CUSTOMER_REQUIRED`, `AMOUNTS_ARE_REQUIRED`, `HSN_DIGITS_REQUIRED` (`cause: {required_digits, line_no, hsn_sac}`, `next: ADD_HSN_TO_LINE`), `TRANSACTION_CLASS_NOT_ALLOWED` (`cause: {transaction_class, doc_type}` — export/SEZ needs `EXPORT_INVOICE`), `GSTIN_INVALID` (registered party with a bad GSTIN; `cause: {gstin, party_id, registration_type}`), `PERIOD_FILED_DATE_IN_OPEN_PERIOD` (`cause: {gst_period_id}`), `NUMBER_FORMAT_INVALID`, `NO_SERIES`, `RATE_VARIANT_REQUIRED` (`cause: {candidates[], hsn_sac, match_level, line_no}`, `next: PIN_VARIANT_ON_PRODUCT`), `RATE_NOT_FOUND`, `CONFIG_NOT_VERIFIED`, `ACCOUNTING_POSTING_REJECTED` (`cause.code` e.g. `NO_OPEN_BOOK_PERIOD`). |
| `POST documents/{id}/void/` | `update_acc_document` | none | 200 row with `status: VOID_DRAFT`. 409 `VOID_NOT_ALLOWED` unless DRAFT. |
| `POST documents/{id}/cancel/` | `approve_acc_document` | `{reason [req]}` | 200 CANCELLED row (tax reversed, receivable/payable reversed). 409 `CANCEL_NOT_ALLOWED`, `cause.reason` ∈ `NOT_ISSUED, HAS_RECEIPT, PARTIALLY_SETTLED, GSTR1_FILED, IRN_PRESENT, EWB_PRESENT, REFERENCED_BY_NOTE, CREDIT_ALREADY_APPLIED`; `next: REVIEW_DOCUMENT_STATE`. Works for inward documents too (`payable`-aware). |
| `GET documents/{id}/render-context/` | `view_acc_document` | | JSON print payload: `invoice_number, invoice_date, supply_date, due_date, doc_type, doc_type_label, transaction_class, place_of_supply_state_code, currency, supplier_name, supplier_legal_name, supplier_gstin, supplier_pan, supplier_state_code, supplier_address, supplier_email, supplier_phone, supplier_logo, recipient_name, recipient_organization, recipient_email, recipient_phone, recipient_address, recipient_gstin, lines: [{line_no, description, hsn_sac, supply_nature, qty, unit_price, line_discount, taxable, rate_pct, cess_pct, tax_cgst, tax_sgst, tax_igst, tax_cess}], taxable_total, tax_cgst, tax_sgst, tax_igst, tax_cess, round_off, grand_total, grand_total_in_words, narration, terms, notes`. No state names, bank details, HSN summary or QR (§12.7). |
| `GET documents/{id}/pdf/` | `view_acc_document` | | Always 501 `PDF_NOT_IMPLEMENTED`. Do not call. |
| `GET documents/{id}/journal/` | `view_acc_document` | | Always 501. Use `GET journal/entries/?document={id}`. |
| `POST documents/credit-notes/` | `create_acc_document` | `{references_document [req], reason [req] (RETURN\|VALUE_CORRECTION\|RATE_CORRECTION\|DISCOUNT), with_gst [req], document_date, discount_pre_agreed_and_linked, lines [req]: [{original_line_no [req], line_no, qty, unit_price, line_discount, description}], settlement_leg: {applied_to_open_balance, refund, held}}` | 201 ISSUED `CREDIT_NOTE` row (notes issue immediately; `settled_by: "CREDIT"`; `party_snapshot.settlement` holds the split). 404 `{detail}`. 409 `NOTE_NOT_ALLOWED` with `cause.reason` ∈ `ORIGINAL_NOT_ISSUED, ORIGINAL_LINE_NOT_FOUND, EXCEEDS_ORIGINAL (cause: grand_total, cap), NO_GST_NOTE_HAS_TAX, RATE_CORRECTION_NONZERO_TAXABLE, DISCOUNT_NOT_PRE_AGREED`; 409 `CN_CUTOFF_PASSED` (`cause.cutoff`). See §12.2 before using `settlement_leg`. |
| `POST documents/debit-notes/` | `create_acc_document` | Same as credit note without `discount_pre_agreed_and_linked`. | 201 `DEBIT_NOTE` row. |

Default settlement of a credit note when `settlement_leg` is omitted: `applied_to_open_balance = min(note total, original open balance)`, `refund = 0`, `held = total − applied` (held becomes a customer credit with `source: CREDIT_NOTE_HOLD`).

### 8.4 Settlement (`acc_settlement`) — customer money in, vendor money out

Every write here posts to the ledger, requires the real codename even for staff users, accepts `event_id`, and can answer 200 `{skipped: true}` for a test customer or a date before `ledger_start_date`. Lists take `?customer=` or `?vendor=`, `?status=` (use the enum values from §7.1; the parameter itself is free text) and paging. Every detail read returns 404 `{detail}` for an unknown id or another organisation's id.

**Receipts**

| Method & path | Perm | Request / response |
|---|---|---|
| `GET settlement/receipts/?customer=&status=` | `view_acc_settlement` | Rows `{receipt_id, customer_id, receipt_date, amount, method, source_account_kind, reference, tds_deducted, unallocated, treat_as, kind, status, journal_entry_id}`, newest first. |
| `GET settlement/receipts/{receipt_id}/` | `view_acc_settlement` | Row + `allocations: [{allocation_id, document_id, amount_applied, tds_applied, tolerance_written_off, source, status}]`. |
| `POST settlement/receipts/` | `create_acc_settlement` | `{customer [req], amount_received [req], source_account_kind [req] (BANK\|CASH\|GATEWAY), receipt_date [req], bank_account (required when BANK), gateway_provider (required when GATEWAY), tds_deducted, gst_tds_deducted, gst_tcs_deducted, bank_charge, fx_loss, fx_gain, targeted_document_ids: [uuid] (open ISSUED documents of this customer; empty = oldest first), tds_certificate_ref, method, reference, event_id}` → 201 receipt row. |
| `POST settlement/receipts/{receipt_id}/reverse/` | `update_acc_settlement` | `{reason}` → 201 `{entry_id}`. 409 `RECEIPT_NOT_POSTED` if already reversed; 409 `CREDIT_PARTLY_APPLIED` (`cause.credit_id`) when the credit this receipt created has already been applied somewhere. |

Allocation rule: pool = `amount_received + tds_deducted + gst_tds_deducted + gst_tcs_deducted + bank_charge + fx_loss − fx_gain`; applied to the targeted (or oldest) open documents; a shortfall within the tenant's `settlement_tolerance` is written off; anything left becomes a customer credit (`unallocated` > 0, `treat_as: CUSTOMER_CREDIT`). Show the user the resulting `unallocated` after posting. Cash receipts at or over the statutory cash limit (₹2 lakh) post with a `CASH_LIMIT_WARNING` warning, not an error.
Receipt errors (all 409, `code` = the specific code below, `cause` repeats it plus context): `AMOUNT_NOT_POSITIVE`, `UNKNOWN_SOURCE_ACCOUNT_KIND`, `BANK_ACCOUNT_REQUIRED`, `GATEWAY_PROVIDER_REQUIRED`, `TARGET_NOT_ISSUED`.

**Customer advances** (money received before any invoice; taxed at receipt for services)

| Method & path | Perm | Request / response |
|---|---|---|
| `GET settlement/advances/?customer=&status=` | `view_acc_settlement` | Rows `{advance_id, customer_id, supply_nature, supply, rate_pct, taxable, remaining_taxable, status}`. |
| `GET settlement/advances/{advance_id}/` | `view_acc_settlement` | Row + `receipt_id` + `adjustments: [{adjustment_id, document_id, adjusted_taxable, adjusted_tax_cgst, adjusted_tax_sgst, adjusted_tax_igst, adjusted_gross, journal_entry_id}]`. |
| `POST settlement/advances/` | `create_acc_settlement` | `{customer [req], amount_received [req], source_account_kind [req], receipt_date [req], supply [req] (INTRA\|INTER), supply_nature [req], rate_pct, taxable_supply (default true), bank_account, gateway_provider, method, reference, event_id}` → 201 **receipt row** (not the advance). To get the advance id, list `settlement/advances/?customer=` afterwards, or open the receipt and follow `advance detail.receipt_id` from the advances list (§12.12). |
| `POST settlement/advances/{advance_id}/adjust/` | `update_acc_settlement` | `{document [req] (an ISSUED invoice of the same customer), adjusted_taxable (default: as much as possible), event_id}` → 201 `{entry_id}`. 409 `ADVANCE_NOT_FOUND`, `ADVANCE_NOT_OPEN`, `TARGET_NOT_ISSUED`, `ADJUSTED_TAXABLE_INVALID`, `ADJUSTED_GROSS_EXCEEDS_OPEN_BALANCE`, `INVALID_ADVANCE_ADJUSTMENT`. |
| `POST settlement/advances/{advance_id}/refund/` | `update_acc_settlement` | `{source_account_kind [req] (BANK\|CASH), bank_account, refund_date, event_id}` → 201 `{entry_id}`. 409 `ADVANCE_ALREADY_SETTLED`. |

**Customer credits** (created by receipts and credit notes; never created directly)

| Method & path | Perm | Request / response |
|---|---|---|
| `GET settlement/customer-credits/?customer=&status=` | `view_acc_settlement` | Rows `{credit_id, customer_id, source, amount, remaining, status}`. |
| `GET settlement/customer-credits/{credit_id}/` | `view_acc_settlement` | Row + `source_receipt_id`, `source_document_id`, `applications: [{application_id, kind, document_id, amount, journal_entry_id}]`. |
| `POST settlement/customer-credits/{credit_id}/apply/` | `create_acc_settlement` | `{document [req], amount [req], event_id}` → 201 `{entry_id}`. 409 `CREDIT_NOT_FOUND`, `AMOUNT_EXCEEDS_CREDIT`, `AMOUNT_EXCEEDS_OPEN_BALANCE`, `TARGET_NOT_ISSUED`. |
| `POST settlement/customer-credits/{credit_id}/refund/` | `update_acc_settlement` | `{amount [req], source_account_kind [req] (BANK\|CASH), bank_account, refund_date, event_id}` → 201 `{entry_id}`. 409 `AMOUNT_EXCEEDS_CREDIT`, `CREDIT_NOT_FOUND`. This is the correct way to refund a credit note by bank (§12.2). |

**Vendor payments**

| Method & path | Perm | Request / response |
|---|---|---|
| `GET settlement/vendor-payments/?vendor=&status=` | `view_acc_settlement` | Rows `{payment_id, vendor_id, payment_date, amount, tds_now, source_account_kind, reference, kind, status, journal_entry_id}`. |
| `GET settlement/vendor-payments/{payment_id}/` | `view_acc_settlement` | Row + `allocations: [{allocation_id, document_id, amount_applied, status}]`. |
| `POST settlement/vendor-payments/` | `create_acc_settlement` | `{vendor [req], amount_paid [req], source_account_kind [req] (BANK\|CASH\|OWNER), payment_date [req], bank_account (required when BANK), owner (label when OWNER), tds_now, tds_nature (§7.3), targeted_document_ids: [uuid] (open vendor bills; empty = oldest first), method, reference, event_id}` → 201 payment row. **Vendors allow no unapplied remainder**: an amount above the open bills is 409 `PAYMENT_EXCEEDS_OPEN_BILLS`; with no open bill at all 409 `NO_OPEN_BILL` (use a vendor advance instead). 409 `TARGET_BILL_INVALID`, `BANK_ACCOUNT_REQUIRED`. |
| `POST settlement/vendor-payments/{payment_id}/reverse/` | `update_acc_settlement` | none → 201 `{entry_id}`. 409 `PAYMENT_NOT_POSTED`. |

**Vendor advances**

| Method & path | Perm | Request / response |
|---|---|---|
| `GET settlement/vendor-advances/?vendor=&status=` | `view_acc_settlement` | Rows `{advance_id, vendor_id, amount, tds_deducted, remaining, status}`. |
| `GET settlement/vendor-advances/{vendor_advance_id}/` | `view_acc_settlement` | Row + `payment_id` + `adjustments: [{adjustment_id, document_id, amount, journal_entry_id}]`. |
| `POST settlement/vendor-advances/` | `create_acc_settlement` | `{vendor [req], amount_paid [req], source_account_kind [req] (BANK\|CASH), payment_date [req], bank_account, tds, tds_nature, tds_base, tds_rate, method, reference, event_id}` → 201 **vendor payment row** (§12.12). |
| `POST settlement/vendor-advances/{vendor_advance_id}/adjust/` | `update_acc_settlement` | `{document [req] (a vendor bill), amount [req], event_id}` → 201 `{entry_id}`. 409 `VENDOR_ADVANCE_NOT_FOUND`, `AMOUNT_EXCEEDS_ADVANCE`. |

### 8.5 Purchases and manual-entry forms

All POST, all post to the ledger immediately (no draft, no preview — §12.9), all accept `event_id`, all require the real codename for staff users. Every form takes `document_date` [req]. Amounts are money strings; `lines[]` rows are `{description, hsn_sac (≤8), supply_nature (default SERVICE), qty (default 1), unit_price [req], line_discount, is_capital_goods}`.

**Purchases** (`create_acc_purchase`) — each returns the created inward document (the §8.3 row shape) so the UI can navigate straight to it.

| Path | Body | Returns |
|---|---|---|
| `purchases/vendor-bills/` | `{vendor [req], target [req] (EXPENSE:<CAT> or PURCHASES), lines [req], document_date [req], supply_date, vendor_invoice_no, vendor_invoice_date, place_of_supply_state_code, personal_use_flag, tds_nature_override, rcm_override: {applies: bool, reason}, event_id}` | 201 `VENDOR_BILL` row (ISSUED, `tds_amount`, `payable`, `rcm_applies` filled). |
| `purchases/vendor-debit-notes/` | `{bill [req], target [req], lines [req], document_date [req], vendor_invoice_no, vendor_invoice_date, personal_use_flag, tds_nature_override, rcm_override, event_id}` | 201 `VENDOR_DEBIT_NOTE` row. |
| `purchases/vendor-credit-notes/` | `{bill [req], taxable_credit [req], tax: {CGST, SGST, IGST}, target, settlement (ADJUST_AGAINST_AP default \| REFUND_RECEIVED \| HELD_BY_VENDOR), itc_was_blocked, source_account (role string, for REFUND_RECEIVED), round_off, document_date (default today), event_id}` | 201 `VENDOR_CREDIT_NOTE` row. |
| `purchases/fixed-assets/` | `{vendor [req], asset_class_key [req] (§7.3), lines [req], document_date [req], description, put_to_use_date, supply_date, vendor_invoice_no, vendor_invoice_date, place_of_supply_state_code, tds_nature_override, event_id}` | 201 `VENDOR_BILL` row booked to `FIXED_ASSET:<class>`. |
| `purchases/expenses/` | `{vendor [req], target [req], lines [req], document_date [req], source_account_kind [req] (BANK\|CASH\|OWNER), bank_account, owner, vendor_invoice_no, place_of_supply_state_code, personal_use_flag, tds_nature_override, event_id}` | 201 `{bill: <row>, payment_id, payment_entry_id}` — a bill and its payment in one call. |

Errors: 404 `{detail}` for vendor/bill; 409 `PURCHASE_REJECTED` (message in `detail` only: role not mapped, no fiscal year covers the date, no numbering series, unknown asset class, cannot resolve the credited expense account); 409 `RATE_VARIANT_REQUIRED` / `RATE_NOT_FOUND`; 409 `ACCOUNTING_POSTING_REJECTED`. Warnings on the returned row: `CASH_LIMIT_WARNING`, `ITC_CLAIM_SHIFTED`, `RCM_LIABILITY_SHIFTED`.

**Funding and banking** (`create_acc_journal`) — each returns 201 `{entry_id}` (loan-received also `loan_id`). `source_account` / `to_account` are role strings (§7.2). Rejections are 409 `FUNDING_REJECTED` / `BANKING_REJECTED` with the reason in `detail` only.

| Path | Body |
|---|---|
| `forms/funding/capital/` | `{amount [req], source_account [req], partner, document_date [req], event_id}` |
| `forms/funding/drawings/` | `{amount, source_account, drawings_account, partner, document_date}` — refused for `PVT_LTD` tenants ("use salary / dividend / director loan"). |
| `forms/funding/loan-received/` | `{amount, source_account, loan (uuid) or lender_name, is_bank, document_date}` → `{entry_id, loan_id}` (creates the loan when `lender_name` is given). |
| `forms/funding/loan-repaid/` | `{loan [req], principal [req], interest, tds, tds_nature (default INTEREST), source_account [req], close, document_date}`; 404 loan. |
| `forms/banking/transfer/` | `{amount, source_account, to_account, document_date}` — accounts must differ. |
| `forms/banking/charge/` | `{taxable, tax: {CGST, SGST, IGST}, itc_forward, source_account, document_date}` |
| `forms/banking/gateway-settlement/` | `{gross, fee_taxable, tax, to_account (BANK:…), source_account (GATEWAY_CLEARING:<provider>), itc_forward (default true), net, document_date}` — `net` must equal gross − fee − tax when given. |
| `forms/banking/interest/` | `{gross, tds, income_kind (default INTEREST), source_account, document_date}` |

### 8.6 Journal and ledger (`acc_journal`)

| Method & path | Perm | Request / response |
|---|---|---|
| `POST journal/manual/` | `create_acc_journal` (money) | `{document_date [req], posting_date, lines [req, ≥ 2]: [{role [req], instance_key, side [req] (Dr\|Cr), amount [req], tax_head, memo}], reason [req], allow_control_accounts (default false), reverses_entry_id, party_kind, party_id, event_id}` → 201 entry (shape below). 409 `APPROVAL_REQUIRED` (`cause: {control_roles, reversal, needs}`) when a control account or a reversal is used without `allow_control_accounts` / `approve_acc_journal`. **An unbalanced journal or an unknown role is a 500 on this commit** — validate Σ debit = Σ credit and restrict roles to the known list client-side (§12.10). |
| `GET journal/entries/?event_type=&document=&date_from=&date_to=&page=` | `view_acc_journal` | Rows ordered `-entry_no`; dates filter on `posting_date`. |
| `GET journal/entries/{entry_id}/` | `view_acc_journal` | One entry. |
| `GET journal/events/?event_type=&status=&page=` | `view_acc_journal` | Rows `{event_id, event_type, rule_id, status, skip_reason, error, journal_entry_id, occurred_at, received_at, processed_at}` ordered `-received_at`. `document`/date parameters are accepted but ignored here. |
| `GET journal/events/{event_id}/` | `view_acc_journal` | `event_id` is a string such as `api:<key>`. |

Entry: `{entry_id, entry_no, event_type, rule_id, document_date, posting_date, narration, total_debit, total_credit, reverses_entry_id, reversed_by_entry_id, late_posted, document_id, lines: [{line_no, account_code, role, instance_key, debit, credit, tax_head, party_kind, party_id, project_id, cost_centre_id, memo}]}`. Account names come from `GET setup/accounts/` (cache it once per session and join on `code`).

### 8.7 Periods (`acc_period`)

Reads need `view_acc_period`; postings `create_acc_period`; settle / close / mark-filed `approve_acc_period`. Everything except the reads is money-posting (no staff bypass). `posting_date` is optional everywhere and defaults to today.

| Method & path | Perm | Request / response |
|---|---|---|
| `GET periods/?fiscal_year_id=` | view | Register for one FY (latest FY when omitted): `{fiscal_year_id, fy_label, status, book_periods: [{book_period_id, period_no, start_date, end_date, status}], gst_periods: [{gst_period_id, gstin, start_date, end_date, gstr1_status, gstr3b_status, settled}], tds_periods: [{tds_period_id, quarter (1–4), start_date, end_date, status}]}`. 404 `{detail}` for an unknown `fiscal_year_id`. |
| `GET periods/fiscal-years/?status=&page=` | view | Rows `{fiscal_year_id, fy_label, start_date, end_date, status, is_current}`, newest first. The FY selector feed. |
| `GET periods/gst/{gst_period_id}/checklist/` | view | `{gst_period_id, gstin, start_date, end_date, gstr1_status, gstr3b_status, settled, items: [{code, label, severity (BLOCK\|WARN\|INFO), status (PASS\|FAIL), detail, count?, acknowledged?}], blocking, can_file_gstr1, can_settle}`. Item codes: `NO_UNPOSTED_EVENTS`, `GSTR1_FILED`, `GSTR3B_FILED`, `NO_ITC_NOT_IN_2B`, plus period-specific rows. |
| `POST periods/gst/{gst_period_id}/checklist/ack/` | create | `{code [req], ref_type, ref_id, note}` → 201 `{ack_id, code}` (acknowledges a WARN item). |
| `GET periods/gst/{gst_period_id}/settlement/proposal/?rule86b_applicable=&cash_fraction=` | view | `{proposal: {gst_period_id, utilisation: {<output head>: {<credit head>: int}}, cash: {head: int}, rcm_cash: {head: int}, carry_forward: {head: int}, credit_opening, cash_min, total_output, total_utilised, credit_available: {head: int}, rule86b: {applicable, cash_fraction, cash_min}}, aggregates: {out, rcm_out, fwd, rcm_cr, fwd_opening, rcm_opening}}`. **Integer rupees**, not decimal strings. Side-effect free. |
| `POST periods/gst/{gst_period_id}/settlement/proposal/save/` | create | Same body as the query parameters above → 201 same shape; persists the proposal on the period. |
| `POST periods/gst/{gst_period_id}/settlement/confirm/` | approve | `{utilisation, cash, rcm_cash (all optional — omit all three to settle with the server proposal), attest_gstr3b_filed, posting_date}` → 200 `{gst_period_id, settlement_entry_id, confirmed}`. 409 `PERIOD_ALREADY_SETTLED`, `GSTR3B_NOT_FILED` (file 3B first or pass `attest_gstr3b_filed: true`), `GST_CASH_LEDGER_INSUFFICIENT` (`cause: {balance, cash_payable}` → pay a challan first), `SETTLEMENT_CREDIT_EXCEEDS_AVAILABLE` (`cause: {head, drawn}`), `GST_RULE_86B_CASH_SHORTFALL` (`cause: {cash_min, cash_confirmed, cash_fraction}`). |
| `POST periods/gst/{gst_period_id}/challan/` | create | `{amount [req], source_account [req] (role string), ref [req], posting_date}` → 201 `{entry_id}`. |
| `POST periods/gst/{gst_period_id}/interest-latefee/` | create | `{amount or interest_by_head: {CGST, SGST, IGST, CESS}, ref [req], source_account (default GST_CASH_LEDGER), posting_date}` → 201 `{entry_id}` or `{entry_ids: []}` for a head-wise split. |
| `POST periods/gst/{gst_period_id}/gstr1-filed/` | approve | `{arn [req], filed_on (default today)}` → 200 `{gst_period_id, gstin, start_date, end_date, gstr1_status, gstr1_filed_on, gstr1_arn, gstr3b_status, gstr3b_filed_on, gstr3b_arn}`. 409 `GST_RETURN_ALREADY_FILED` (`cause: {which, status, gst_period_id}`). Locks the period against new outward documents (`PERIOD_FILED_DATE_IN_OPEN_PERIOD` at issue). |
| `POST periods/gst/{gst_period_id}/gstr3b-filed/` | approve | Same body and response. |
| `POST periods/tds/{tds_period_id}/deposit/` | create | `{source_account [req], interest, amounts_by_nature: {<nature>: amount} (override), challan_refs: [{…}], deposited_on, posting_date}` → 201 `{tds_period_id, deposit_entry_id, status}`. |
| `POST periods/income-tax/paid/` | create | `{amount [req], source_account [req], kind (ADVANCE default \| SELF_ASSESSMENT \| DEMAND), interest_penalty, ref, posting_date}` → 201 `{entry_id}`. |
| `GET periods/book/{book_period_id}/checklist/` | view | `{book_period_id, period_no, start_date, end_date, status, items, blocking, can_close}`; items `NO_UNPOSTED_EVENTS`, `GST_PERIOD_SETTLED`, `ALREADY_OPEN`. |
| `POST periods/book/{book_period_id}/close/` | approve | `{force}` → 200 `{book_period_id, status}`. Irreversible — there is no reopen. |
| `GET periods/fiscal-years/{fiscal_year_id}/close/checklist/` | view | `{fiscal_year_id, fy_label, status, items, blocking, can_close}`; items `ALL_BOOK_PERIODS_CLOSED`, `ALL_TDS_DEPOSITED`, `ALL_GST_SETTLED`, `FY_OPEN`. |
| `POST periods/fiscal-years/{fiscal_year_id}/close/` | approve | `{provision, partner_shares: {<partner>: fraction}, closing_value, opening_value, posting_date, force}` → 200 `{fiscal_year_id, status, steps: {<step>: entry_id \| [entry_ids] \| value}}`. Irreversible. |
| `POST periods/fiscal-years/{fiscal_year_id}/closing-stock/` | create | `{closing_value [req], opening_value, posting_date}` → 201 `{entry_id}`. |
| `POST periods/opening-balances/` | create | `{lines [req]: [{role [req], instance_key, side [req], amount [req]}], posting_date}` → 201 `{entry_id}`. Write-only: there is no read-back or preview. |

### 8.8 Reports (`acc_report`, `view_acc_report`)

Query parameters are **not validated** on this commit: a malformed date or a non-numeric `page` is a 500. Validate on the client and never send empty strings. Money is decimal strings. Reports are not cached server-side; debounce filter changes.

| Path & params | Response |
|---|---|
| `reports/trial-balance/?as_of=&fiscal_year_id=` | `{as_of, fiscal_year_id, groups: [{bucket, accounts: [{account_id, code, name, bucket, normal_side, debit, credit, opening_debit, opening_credit, movement_debit, movement_credit, closing_debit, closing_credit}], debit, credit}], total_debit, total_credit, balanced}` |
| `reports/general-ledger/?account_id=\|account_code=&date_from=&date_to=&page=&page_size=` | `{account: {account_id, code, name, bucket, normal_side}, date_from, date_to, opening_balance, page_opening_balance, page, page_size, count, num_pages, closing_balance, lines: [{line_id, entry_id, entry_no, posting_date, document_date, event_type, role, instance_key, party_kind, party_id, project_id, memo, debit, credit, running_balance}]}` — its own paging keys, not the standard envelope. 400 `ACCOUNT_REQUIRED` without an account. |
| `reports/ar-aging/?as_of=` · `reports/ap-aging/?as_of=` | `{as_of, buckets: ["0-30", "31-60", "61-90", "90+"], rows: [{customer_id \| vendor_id, customer_name \| vendor_name, "0-30", "31-60", "61-90", "90+", total}], totals}` — the one place party names are returned. |
| `reports/customer-statement/{customer_id}/?date_from=&date_to=` · `reports/vendor-statement/{vendor_id}/…` | `{party_kind, party_id, date_from, date_to, opening_balance, closing_balance, total_debit, total_credit, lines: [{date, kind (DOCUMENT\|RECEIPT\|PAYMENT), doc_type, reference, ref_id, debit, credit, balance}]}`. An unknown party returns 200 with no lines; check the party exists first. |
| `reports/gst-summary/?gst_period_id=\|date_from=&date_to=` | `{gst_period_id, date_from, date_to, periods: [{gst_period_id, start_date, end_date, sections: {<section>: {…heads}}}], grand_totals: {<section>: {…}}}` |
| `reports/tds-summary/?tds_period_id=\|fiscal_year_id=` | `{tds_period_id, fiscal_year_id, rows: [{nature_key, tds_period_id, start_date, end_date, quarter, base, deducted, deposited, pending, count}], totals: {base, deducted, deposited, pending, count}}` |
| `reports/itc-register/?gst_period_id=&itc_status=&date_from=&date_to=` | `{gst_period_id, itc_status, by_status: [{itc_status, …heads, count}], totals, availed: {formula, by_period: [{gst_period_id, …}], total}}` |
| `reports/pnl/?as_of=&fiscal_year_id=` | `{as_of, fiscal_year_id, income: [{account_id, code, name, amount}], expense: [...], total_income, total_expense, net_profit}` |
| `reports/balance-sheet/?as_of=&fiscal_year_id=` | `{as_of, fiscal_year_id, assets: [{account_id, code, name, amount, opening_amount}], liabilities, equity, net_profit, total_assets, total_liabilities, total_equity, liabilities_and_equity, balanced}` |
| `GET reports/project-financials/{project_id}/` | Live, not persisted: `{project_id, billed_taxable, billed_gross, credit_notes_taxable, collected, open_ar, purchase_taxable, expense_taxable, vendor_open_ap, gross_margin, as_of_entry_no}`; 404 `{detail}`. |
| `POST reports/project-financials/{project_id}/rederive/` (`create_acc_report`) | Recomputes and persists the rollup the project API's `financials` field reads; returns the same shape plus `updated_at`. |
| `POST reports/export/` (`export_acc_report`) | `{report [req]: "trial_balance" \| "general_ledger", as_of, fiscal_year_id, account_id, account_code, date_from, date_to}` → CSV stream with `Content-Disposition` (exposed by CORS). Only these two reports export; 400 `UNKNOWN_REPORT` otherwise. |

---

## 9. Changes to the CRM endpoints the apps already use

### 9.1 Payment records (mark-paid)

New read-only fields: `linked_document_id` (the ISSUED invoice for this instalment, null until issued), `posted_receipt_id` (the receipt the ledger posted when it was marked paid), `record_summary`:
```json
{"document": {"document_id", "number", "status", "grand_total", "open_balance", "payment_state"},
 "receipt":  {"receipt_id", "kind", "status", "amount", "receipt_date"}}
```
Either key may be absent; the whole field is `null` when accounting is inactive **or** nothing is linked yet (the two cases are indistinguishable; use the §2 activation state).

New writable settlement columns: `tds_deducted`, `bank_charge`, `gst_tds_deducted`, `gst_tcs_deducted`, `bank_account_id`, `gateway_ref`, `treat_as` (`ADVANCE | CUSTOMER_CREDIT`), `service_period_start`, `service_period_end`, `milestone_task` (task UUID, must be a milestone of the plan's project).

Validation on PATCH: `tds_deducted` and `bank_charge` are non-negative and **only accepted in a PATCH whose resulting status is `paid`** (send them together with `status: "paid"`); the remaining-balance ceiling is checked on the settled value `amount_paid + tds_deducted + bank_charge`; a record linked to an issued invoice may always be settled for exactly its own `amount_expected`. `amount_paid` is the cash actually received (net of TDS and bank charge).

What happens on `status: "paid"` when accounting is active: inside the same transaction the ledger posts a receipt. If an open ISSUED invoice exists for the customer (or the record's `linked_document_id`), it is allocated to it; if no invoice exists, a SERVICE plan posts a taxed advance unless `treat_as` is `CUSTOMER_CREDIT`, and a GOODS plan posts a customer credit. Money source resolution, in order: explicit `bank_account_id` → the literal method `cash` → a bank account whose `method_aliases` contains the (lower-cased) `payment_method` → the organisation's default bank → blank method and no bank → cash → **any other method with no bank → 409** `ACCOUNTING_POSTING_REJECTED` with `cause: {code: "NO_BANK_ACCOUNT_FOR_METHOD", method, record_id}` and the record is **not** marked paid. Rule for both apps: send `bank_account_id` for every non-cash method, or make sure the org has a default bank. `paid → unpaid` reverses the receipt; changing the amount of a paid record reverses and re-posts.

`invoice_id` is a deprecated alias of the plan id; stop reading it.

### 9.2 Payment plans

Writable: `billing_mode`, `auto_issue`, `amounts_are`, `project` (project UUID), `contract_ref`. `amounts_are` is locked with a field-level validation 400 once any record of the plan has `linked_document_id` or `posted_receipt_id`. Read-only `amount_paid` is cash only; `amount_remaining` is total minus settled value (cash + TDS + bank charge).

Backend behaviour the UI must reflect: for `INVOICE_ON_DUE` and `PERIODIC` plans the backend pre-creates a DRAFT invoice for every new schedule row (document date = due date) as soon as accounting is active and the quote has a customer; with `auto_issue` on, a row that is already due is issued immediately and a daily sweep issues the rest as they fall due. `MANUAL` creates nothing; `INVOICE_ON_COMPLETION` is driven by the milestone hook. Gate G9 requires every open plan to carry `amounts_are` and `billing_mode` before activation.

### 9.3 Quotations

Header: `amounts_are`, `place_of_supply_state_code`, `contract_ref` (writable). Lines: `product_id` and `line_discount` writable; `hsn_sac`, `supply_nature`, `rate_pct` read-only (copied from the product). Once any record is paid or linked, these fields are locked together with the monetary/config fields (`total_amount, line_items, payment_type, currency, num_installments, billing_period_days`) → 400 "This quotation has a recorded payment and is locked. Create a new quote and cancel the existing invoice instead."

### 9.4 Products

`hsn_sac` (4–8 digits or null), `tax_rate` ∈ `{0, 5, 12, 18, 28, 40}` (12 and 28 come back with a `deprecated_rate` message on read; the effective rate is resolved by the rate master at issue, so `tax_rate` is a UI default only), `supply_nature` (`GOODS | SERVICE`). Package/bundle adjustments carry no GST (`tax_rate` must be 0 on a `bundle_discount`).

### 9.5 Helpdesk issues

`billable` (bool), `billable_amount`, `billable_product_id` (write) / `billable_product` (read), `billed_document_line_id` (read-only, set at issue of the derived invoice and cleared on cancel). A billable ticket needs an amount or a product (validation 400).

### 9.6 Projects

`financials` (read-only) — the persisted rollup (§8.8 shape plus `updated_at`), `null` until someone has called rederive. It does not refresh on its own (§12.13).

### 9.7 Lookups used by the accounting screens

`GET /api/v1/organizations/states/` (state codes) · `GET /api/v1/billing/features/me/` (plan feature) · `GET /api/v1/auth/me/modules/` (permissions) · `GET /api/v1/management/permissions/module-catalog/` (role editor).

---

## 10. Flows

**10.1 Activation wizard** (`acc_setup`; nothing here needs activation)
1. `PUT setup/tenant-profile/` — entity type, legal name, PAN, TAN, state, `ledger_start_date` (first of a month), defaults (billing mode, amounts-are, tolerance), flags, return frequency.
2. `POST setup/tenant-attributes/` for `REGISTRATION_STATUS`, `GSTIN` (if registered), `ITC_ALLOWED`, `IS_TDS_DEDUCTOR` (§7.4), each with `effective_from` ≤ `ledger_start_date`.
3. `GET setup/gates/` → render the ten rows; loop until `can_activate`.
4. Fix open payment plans (gate G9): list active plans, PATCH `billing_mode` / `amounts_are` on those with nulls (§9.2).
5. `POST setup/activate/` with `series_starts` for a mid-life tenant (continue the old invoice numbering). 409 `GATE_FAILED_G<n>` → jump to that step.
6. **After activation:** `POST masters/bank-accounts/` for each bank (mark one default, alias the payment methods), `GET setup/series/` to show the numbering, optionally `POST periods/opening-balances/`.

**10.2 Invoice for a plan instalment** (`acc_document`)
1. Show the schedule row with `record_summary` (§9.1). If `document` exists, link to it; else, before offering "Create invoice", `GET documents/?source_type=PLAN_RECORD&status=DRAFT&customer=<id>` and match `payment_record_id` client-side (§12.1).
2. `POST documents/invoices/from-payment-record/` → open the draft.
3. Draft screen: `PATCH` header fields; `POST …/preview-tax/` to show final numbers and rate resolution; on `RATE_VARIANT_REQUIRED` at issue, open the HSN picker (`GET masters/hsn-rates/`) and pin the variant via the product tax profile (§8.2), then retry.
4. `POST …/issue/` (needs `approve_acc_document`) → show `number`, warnings.
5. Print: `GET …/render-context/` → HTML print sheet (web: browser print; Flutter: share sheet). `pdf/` is a 501.
6. Correct: `POST …/cancel/` (reason) while nothing is settled against it; otherwise `POST documents/credit-notes/`.

**10.3 Money in**
- CRM path (most users): the existing mark-paid PATCH with `status: "paid"`, `amount_paid`, `tds_deducted`, `bank_charge`, `bank_account_id`, `treat_as`; on 409 `ACCOUNTING_POSTING_REJECTED` keep the sheet open and show `cause`.
- Accounting path: `POST settlement/receipts/` with `targeted_document_ids`; then show `unallocated` and, when > 0, link to the customer's credits.
- Prepayment for services: `POST settlement/advances/` (taxed at receipt); later `…/adjust/` against the invoice, or `…/refund/`.
- Credit note with refund by bank: create the note with `held` = refund amount (or omit `settlement_leg`), then `POST settlement/customer-credits/{id}/refund/` with `source_account_kind: BANK` + `bank_account` (§12.2).

**10.4 Purchases** (`acc_purchase`, `acc_settlement`)
1. `POST masters/vendors/` (or pick one); set its tax profile (`registration_type`, `gstin`, `state_code`, `tds_applicable`, `entity_kind`, `tds_nature_default`) via `PUT masters/parties/vendor/{id}/tax-profile/` — this needs `acc_setup`, so the vendor form shows those fields only to users who hold it.
2. `POST purchases/vendor-bills/` (posts immediately; show a confirmation with client-computed totals first, §12.9) → open the bill (TDS and payable are on the row).
3. Pay: `POST settlement/vendor-payments/` with `targeted_document_ids` (full allocation only).
4. Same-day expense: `POST purchases/expenses/` (bill + payment in one).
5. Undo: `POST documents/{id}/cancel/` on the bill (needs `approve_acc_document`), or a vendor credit note.

**10.5 Month-end GST** (`acc_period`)
1. `GET periods/` → pick the GST period → `GET …/checklist/`; acknowledge WARN items with `…/checklist/ack/`.
2. `POST …/gstr1-filed/ {arn}` once GSTR-1 is filed on the portal.
3. `GET …/settlement/proposal/` → show the utilisation matrix (integers); let the accountant edit to match the portal; `POST …/settlement/proposal/save/` to keep it.
4. If cash is short: `POST …/challan/` per challan paid; `POST …/interest-latefee/` when applicable.
5. `POST …/gstr3b-filed/ {arn}` (or `attest_gstr3b_filed: true` on confirm) → `POST …/settlement/confirm/` (needs `approve_acc_period`).
6. TDS quarter: `GET reports/tds-summary/?tds_period_id=` → `POST periods/tds/{id}/deposit/`.
7. `POST periods/book/{id}/close/` after the checklist is clean. Irreversible.

**10.6 Year end**: `GET periods/fiscal-years/{id}/close/checklist/` → optionally `…/closing-stock/` and `periods/income-tax/paid/` → `POST …/close/` with provision / partner shares (needs `approve_acc_period`). Irreversible. The 1-April rollover creates the next FY automatically (Celery beat).

**10.7 Reports**: FY selector from `GET periods/fiscal-years/`; trial balance → account row → `reports/general-ledger/?account_id=` drill-down; statements per party; CSV only for trial balance and general ledger.

---

## 11. Screen map (both platforms)

| Screen (plan section) | Endpoints |
|---|---|
| Accounting setup wizard (web 4.1 / Flutter read-only status) | §8.1, `PATCH` plans (§9.2), `POST masters/bank-accounts/` after activate |
| Accounting overview (web 4.2) | `GET periods/`, `reports/ar-aging/`, `reports/ap-aging/`, `GET documents/?status=DRAFT`, `journal/events/?status=REJECTED` |
| Documents list / detail / draft editor (web 4.3–4.5, Flutter 4.2–4.4) | §8.3 |
| Credit / debit note modal (web 4.6) | `documents/credit-notes/`, `debit-notes/`, `customer-credits/{id}/refund/` |
| Invoice print / share (web 4.7, Flutter 4.6) | `render-context/` |
| Customer tax profile tab / vendor tax profile (web 5.3, 4.9) | `masters/parties/…/tax-profile/`, batch for list badges |
| Vendors (web 4.9, Flutter 4.7) | `masters/vendors/`, `documents/?vendor=`, `settlement/vendor-payments/?vendor=`, `reports/vendor-statement/{id}/` |
| Purchases forms (web 4.10, Flutter 4.8) | §8.5, `masters/bank-accounts/`, seed pickers §7.3 |
| Receipts / advances / credits / vendor payments (web 4.11–4.12, Flutter 4.5) | §8.4, `masters/bank-accounts/` |
| Bank accounts settings (web 4.8) | `masters/bank-accounts/` GET/POST/PATCH |
| Funding & banking forms (web 4.12) | §8.5 forms, `masters/loans/` |
| Manual journal + ledger (web 4.13) | §8.6, `setup/accounts/` |
| Periods & GST wizard (web 4.14, Flutter read-only) | §8.7 |
| Reports (web 4.15, Flutter 4.9) | §8.8 |
| Payment plan / record changes (web 5.2, Flutter 4.10) | §9.1, §9.2 |
| Quote builder, product form, ticket billing, project financials (web 5.1/5.4/5.5/5.6, Flutter 4.11) | §9.3–§9.6 |
| Role editor | module catalog + the "approve means" copy in §3 |

---

## 12. Client-side rules for the backend limitations that remain

Each of these is a backend gap that has **not** been closed on `f1be31a`; the rule keeps the app correct until it is.

1. **Duplicate drafts.** `from-payment-record/`, `from-ticket/` and `invoices/` create a new draft on every call and take no idempotency key. Disable the button on first tap; on a timeout do not retry blindly: re-query `GET documents/?source_type=…&status=DRAFT&customer=…` and match `payment_record_id` / `source_id` before creating. For plan records also remember the backend may already have pre-created a draft (§9.2), so always look before creating.
2. **Credit-note refund leg.** `settlement_leg.refund > 0` always posts to **cash** (the serializer drops `refund_account`), and the split is stored without checking it sums to the note total. Never send `refund`; compute `applied` and `held` yourself so they add up to the note total, and refund by bank through `customer-credits/{id}/refund/` afterwards.
3. **Vendor duplicate name → 500.** Before `POST masters/vendors/` or `PATCH is_active: true`, call `GET masters/vendors/?search=<name>` and block on a case-insensitive exact match of an active vendor; map a 500 on these two calls to "A vendor with this name already exists".
4. **Document lists are heavy** (nested lines and tax lines per row). Always send `doc_type`; `page_size` ≤ 50 on mobile, ≤ 100 on web; never build dashboards by paging the whole list.
5. **No party names on documents, receipts or journal lines.** Resolve customer names from the CRM customer endpoints and vendor names from a session-cached `GET masters/vendors/`. A user without CRM read (Finance Viewer) sees the short UUID plus the aging reports, which do carry names.
6. **Report parameters are unvalidated.** Validate dates (`YYYY-MM-DD`), `page`/`page_size` integers, and required ids client-side; a bad value is a 500.
7. **No PDF.** Render the HTML print sheet from `render-context/`; add state names (from the states lookup), the seller's `print_on_invoice` bank account (from `masters/bank-accounts/`) and an HSN summary computed from `lines` on the client.
8. **Lines are immutable after draft creation.** "Edit lines" = void the draft and create a new one; say so in the UI.
9. **Purchases post immediately.** Show a confirmation step with client-computed totals labelled "estimated"; there is no preview or draft for inward documents and no edit afterwards (only cancel / vendor notes).
10. **Manual journal.** Validate Σ debit = Σ credit, at least two lines, and roles restricted to the §7.2 list (plus instanced roles from the bank/loan lists) before posting; an unbalanced entry or unknown role is a 500, not a 409.
11. **Payment methods.** Keep one lower-case method vocabulary in both apps (`cash, upi, neft, imps, rtgs, card, cheque, gateway`), send `bank_account_id` for every non-cash method on mark-paid, and give admins the bank-account `method_aliases` editor so unattended records (webhooks, imports) resolve.
12. **Advance ids.** `POST settlement/advances/` and `POST settlement/vendor-advances/` return the receipt / payment row. Fetch the advances list for the party afterwards (newest first) to get the advance id for the detail screen.
13. **Project financials go stale.** Nothing schedules the rollup. After a settlement or document write from a project screen, call `POST reports/project-financials/{id}/rederive/` if the user holds `create_acc_report`; otherwise show `as_of_entry_no` / `updated_at` so staleness is visible. For a live figure use the GET.
14. **Plan-gate 403.** Its body is flattened to `{code: 403, message}`; never parse it. Pre-check `/billing/features/me/` and `/auth/me/modules/`. Ignore `upgrade_url` wherever it appears (it is still `/billing/plans` on the standard path).
15. **Tenant attributes.** Names are free text and values are JSON; use only the shapes in §7.4. Every write closes the previous row, so an edit is a new row with the corrected `effective_from`.
16. **FY-scoped document lists.** There is no `fiscal_year` filter on documents; derive `date_from`/`date_to` from the selected fiscal-year row.
17. **Test documents** (`is_test` customers) appear in lists without a flag. Nothing to do; expect them on staging.
18. **No reopen** for book periods or fiscal years. Confirmation dialogs must say "cannot be undone".
19. **Bank accounts need an active tenant.** `POST masters/bank-accounts/` answers 409 `ACCOUNTING_NOT_ACTIVE` before activation; order the wizard accordingly.
20. **Ledger events list** ignores `document` and date filters; filter by `event_type`/`status` only.
21. **Document journal.** `documents/{id}/journal/` is a 501; use `journal/entries/?document={id}`.
22. **Settlement `status` filter** is free text; send only the enum values from §7.1 or the list is empty.
23. **Invoice numbering follows the draft's creation date.** A draft created in March and re-dated into April at issue gets a previous-year number. When a `PATCH` moves `document_date` across 1 April, void the draft and create a new one.
24. **Ticket billing.** The backend does not check `billable` or `billed_document_line_id` on `from-ticket/`; hide "Bill this" unless `billable` is true and `billed_document_line_id` is null, and disable it after the first tap.
25. **Product/customer ids on manual invoices** that do not exist in the org are silently nulled; resolve them before posting.

---

## 13. Test-environment prerequisites

A staging environment is not usable for frontend work until all of these have run; otherwise every accounting call is 403 or 409:

```bash
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py seed_status_types
docker compose exec backend python manage.py seed_features            # creates the "accounting" feature flag
docker compose exec backend python manage.py seed_accounting_config --pack v2026.09.20
docker compose exec backend python manage.py seed_rule_versions
docker compose exec backend python manage.py backfill_accounting_permissions --create-roles   # Accountant, Finance Viewer, CRM User grant
```

Then: attach the `accounting` feature to the test org's plan; assign the seeded roles to test users (not superusers); set `ACCOUNTING_REQUIRE_VERIFIED_CONFIG=False` on staging (it defaults to `not DEBUG`, and with an unverified seed pack every issue fails `CONFIG_NOT_VERIFIED`); run Celery beat for `accounting.sweep_invoice_on_due` and `accounting.rollover_fiscal_year`.

---

## Appendix A — Route inventory (`/api/v1/accounting/`)

| Area | Routes |
|---|---|
| Setup | `GET/PUT/POST setup/tenant-profile/` · `GET/POST setup/tenant-attributes/` · `GET setup/gates/` · `POST setup/activate/` · `GET setup/accounts/` · `GET setup/series/` |
| Masters | `GET/POST masters/vendors/` · `GET/PUT/PATCH/DELETE masters/vendors/{id}/` · `GET/PUT masters/parties/{kind}/{id}/tax-profile/` · `GET masters/parties/customer/tax-profiles/` · `GET/PUT masters/products/{id}/tax-profile/` · `GET/POST masters/bank-accounts/` · `PATCH masters/bank-accounts/{id}/` · `GET/POST masters/loans/` · `GET masters/hsn-rates/` |
| Documents | `GET documents/` · `GET/PATCH documents/{id}/` · `POST documents/invoices/` · `POST documents/invoices/from-payment-record/` · `POST documents/invoices/from-ticket/` · `POST documents/credit-notes/` · `POST documents/debit-notes/` · `POST documents/{id}/preview-tax/` · `POST documents/{id}/issue/` · `POST documents/{id}/void/` · `POST documents/{id}/cancel/` · `GET documents/{id}/render-context/` · `GET documents/{id}/pdf/` (501) · `GET documents/{id}/journal/` (501) |
| Settlement | `GET/POST settlement/receipts/` · `GET settlement/receipts/{id}/` · `POST settlement/receipts/{id}/reverse/` · `GET/POST settlement/advances/` · `GET settlement/advances/{id}/` · `POST settlement/advances/{id}/adjust/` · `POST settlement/advances/{id}/refund/` · `GET settlement/customer-credits/` · `GET settlement/customer-credits/{id}/` · `POST settlement/customer-credits/{id}/apply/` · `POST settlement/customer-credits/{id}/refund/` · `GET/POST settlement/vendor-payments/` · `GET settlement/vendor-payments/{id}/` · `POST settlement/vendor-payments/{id}/reverse/` · `GET/POST settlement/vendor-advances/` · `GET settlement/vendor-advances/{id}/` · `POST settlement/vendor-advances/{id}/adjust/` |
| Purchases | `POST purchases/vendor-bills/` · `POST purchases/vendor-credit-notes/` · `POST purchases/vendor-debit-notes/` · `POST purchases/fixed-assets/` · `POST purchases/expenses/` |
| Forms | `POST forms/funding/capital/` · `drawings/` · `loan-received/` · `loan-repaid/` · `POST forms/banking/transfer/` · `charge/` · `gateway-settlement/` · `interest/` |
| Journal | `POST journal/manual/` · `GET journal/entries/` · `GET journal/entries/{id}/` · `GET journal/events/` · `GET journal/events/{id}/` |
| Periods | `GET periods/` · `GET periods/fiscal-years/` · `GET periods/book/{id}/checklist/` · `POST periods/book/{id}/close/` · `GET periods/gst/{id}/checklist/` · `POST periods/gst/{id}/checklist/ack/` · `GET periods/gst/{id}/settlement/proposal/` · `POST periods/gst/{id}/settlement/proposal/save/` · `POST periods/gst/{id}/settlement/confirm/` · `POST periods/gst/{id}/challan/` · `POST periods/gst/{id}/interest-latefee/` · `POST periods/gst/{id}/gstr1-filed/` · `POST periods/gst/{id}/gstr3b-filed/` · `POST periods/tds/{id}/deposit/` · `POST periods/income-tax/paid/` · `GET periods/fiscal-years/{id}/close/checklist/` · `POST periods/fiscal-years/{id}/close/` · `POST periods/fiscal-years/{id}/closing-stock/` · `POST periods/opening-balances/` |
| Reports | `GET reports/trial-balance/` · `general-ledger/` · `ar-aging/` · `ap-aging/` · `customer-statement/{id}/` · `vendor-statement/{id}/` · `gst-summary/` · `tds-summary/` · `itc-register/` · `pnl/` · `balance-sheet/` · `project-financials/{id}/` · `POST reports/project-financials/{id}/rederive/` · `POST reports/export/` |

## Appendix B — Structured error code index

| Code | Status | Raised by | `cause` / notes |
|---|---|---|---|
| `ACCOUNTING_NOT_ACTIVE` | 409 | every non-setup endpoint before activation | `{}` |
| `GATE_FAILED_G1` … `GATE_FAILED_G10` | 409 | `setup/activate/` | `{gate}` |
| `CONFIG_NOT_VERIFIED` | 409 | activate, issue, purchases (verified-config environments) | `{rows}`, `next: CONSOLE_VERIFY` |
| `CUSTOMER_REQUIRED`, `AMOUNTS_ARE_REQUIRED` | 409 | issue | `{}` / `{record_id}` |
| `HSN_DIGITS_REQUIRED` | 409 | issue | `{required_digits, line_no, hsn_sac}`, `next: ADD_HSN_TO_LINE` |
| `TRANSACTION_CLASS_NOT_ALLOWED` | 409 | issue | `{transaction_class, doc_type}` |
| `GSTIN_INVALID` | 409 at issue / 400 on party PUT | issue, party tax profile | `{gstin, party_id, registration_type}` / `{gstin}` |
| `PERIOD_FILED_DATE_IN_OPEN_PERIOD` | 409 | issue | `{gst_period_id}`, `next: USE_A_LATER_DATE_OR_CREDIT_NOTE` |
| `NUMBER_FORMAT_INVALID`, `NO_SERIES` | 409 | issue, notes | `{number}` / `{doc_type}` |
| `RATE_VARIANT_REQUIRED` | 409 | issue, preview, purchases | `{candidates[], hsn_sac, match_level, line_no}`, `next: PIN_VARIANT_ON_PRODUCT` |
| `RATE_NOT_FOUND`, `MIXED_NO_ITC_SUPPLY_UNSUPPORTED` | 409 | issue, purchases | |
| `VOID_NOT_ALLOWED` | 409 | void | `{reason}` |
| `CANCEL_NOT_ALLOWED` | 409 | cancel | `{reason}` ∈ NOT_ISSUED, HAS_RECEIPT, PARTIALLY_SETTLED, GSTR1_FILED, IRN_PRESENT, EWB_PRESENT, REFERENCED_BY_NOTE, CREDIT_ALREADY_APPLIED |
| `NOTE_NOT_ALLOWED` | 409 | credit/debit notes | `{reason}` ∈ ORIGINAL_NOT_ISSUED, ORIGINAL_LINE_NOT_FOUND, EXCEEDS_ORIGINAL, NO_GST_NOTE_HAS_TAX, RATE_CORRECTION_NONZERO_TAXABLE, DISCOUNT_NOT_PRE_AGREED |
| `CN_CUTOFF_PASSED` | 409 | credit notes with GST | `{cutoff}` |
| `ACCOUNTING_POSTING_REJECTED` | 409 | any posting; CRM mark-paid | `{code: NO_RULE \| NO_OPEN_BOOK_PERIOD \| IDEMPOTENCY_PAYLOAD_MISMATCH \| EMPTY_ENTRY \| UNBOUND_AMOUNT \| ALREADY_REVERSED \| CANNOT_REVERSE_A_REVERSAL \| REVERSAL_TARGET \| NO_BANK_ACCOUNT_FOR_METHOD, …}` |
| settlement codes (top-level `code` is the specific one) | 409 | §8.4 | `AMOUNT_NOT_POSITIVE, UNKNOWN_SOURCE_ACCOUNT_KIND, BANK_ACCOUNT_REQUIRED, GATEWAY_PROVIDER_REQUIRED, TARGET_NOT_ISSUED, RECEIPT_NOT_FOUND, RECEIPT_NOT_POSTED, ADVANCE_NOT_FOUND, ADVANCE_NOT_OPEN, ADVANCE_ALREADY_SETTLED, ADJUSTED_TAXABLE_INVALID, ADJUSTED_GROSS_EXCEEDS_OPEN_BALANCE, INVALID_ADVANCE_ADJUSTMENT, CREDIT_NOT_FOUND, AMOUNT_EXCEEDS_CREDIT, AMOUNT_EXCEEDS_OPEN_BALANCE, CREDIT_PARTLY_APPLIED, NO_OPEN_BILL, PAYMENT_EXCEEDS_OPEN_BILLS, TARGET_BILL_INVALID, PAYMENT_NOT_POSTED, VENDOR_PAYMENT_NOT_FOUND, VENDOR_ADVANCE_NOT_FOUND, AMOUNT_EXCEEDS_ADVANCE` |
| `SETTLEMENT_REJECTED` | 409 | settlement, when no specific code | `{}` |
| `PURCHASE_REJECTED`, `FUNDING_REJECTED`, `BANKING_REJECTED`, `REGISTRATION_REJECTED` | 409 | §8.5, bank/loan create | reason text in `detail` only |
| `APPROVAL_REQUIRED` | 409 | manual journal | `{control_roles, reversal, needs}` |
| `PERIOD_ALREADY_SETTLED`, `GSTR3B_NOT_FILED`, `GST_CASH_LEDGER_INSUFFICIENT`, `SETTLEMENT_CREDIT_EXCEEDS_AVAILABLE`, `GST_RULE_86B_CASH_SHORTFALL` | 409 | GST settlement confirm | see §8.7 |
| `GST_RETURN_ALREADY_FILED`, `GST_UNKNOWN_RETURN_KIND` | 409 | gstr1/3b-filed | `{which, status, gst_period_id}` |
| `PARTY_HAS_BOOKS` | 409 | vendor delete | `{party, party_id}` |
| `CONFIG_VALUE_CONFLICT`, `CONFIG_ROW_IMMUTABLE`, `CONFIG_RETROSPECTIVE_SUPERSEDE`, `CONFIG_LOOKUP_ERROR` | 409 | config console paths (not used by these clients) | |
| `NOT_DRAFT`, `ACCOUNT_REQUIRED`, `UNKNOWN_REPORT`, `PDF_NOT_IMPLEMENTED` | 409 / 400 / 400 / 501 | ad-hoc view responses (§4 D) | |
