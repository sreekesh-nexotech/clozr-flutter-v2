# Billing — Workspace Billing Page — Frontend API Guide

Backs the **Workspace → Billing** screen: the Current-plan card, Licenses (seats),
Storage, Payment-mandate (eNACH), Invoices & billing history, the **Change plan**
modal (Monthly/Yearly + Starter/Business/Enterprise), and the **Add licenses**
modal (prorated seat purchase).

All endpoints mount under **`/api/v1/billing/`** (code docstrings that say
`/billing/...` omit the `api/v1` prefix). Auth: **org admin (`is_staff`)** sees/edits
their own org's billing; **superuser** sees all and owns provider-only actions
(plan CRUD, void, trial-settings, webhook replay). Everything is org-scoped by the
JWT — you never pass an org id.

> **Read this first.**
> 1. **Seats are now first-class (§2, §6).** `licensed_user_count` is the **purchased
>    ceiling**; **active users** are counted live; `free_seats = purchased − active`
>    drives "8 / 8 used · 0 free to assign". Adding a license is an explicit,
>    **pay-then-activate**, System-Admin-only purchase (`add-licenses/` → Razorpay
>    Payment Link → activates on payment). Removing is next-cycle, no refund. Creating
>    a user now **consumes a free seat** and is **blocked (400 `no_free_license`)** when
>    none is free — it no longer silently buys one.
> 2. **Storage is now backed (§3)** — `GET /api/v1/billing/storage/` returns used vs.
>    cap. Usage is a per-org counter captured at the CDN chokepoint + nightly Bunny
>    reconciliation; cap is the `limits.storage_gb` plan feature. Display-only for now
>    (enforcement behind `STORAGE_CAP_ENFORCED`, default off).
> 3. **AI usage is now tracked (§3A)** — `GET /api/v1/billing/ai-usage/` returns this
>    month's call-transcription (audio minutes) + call-summary (LLM tokens) usage and
>    cost, with a per-event ledger at `…/ai-usage/records/`. Same per-org-counter +
>    nightly-reconcile pattern as storage; display-only (caps behind
>    `AI_USAGE_CAP_ENFORCED`, default off). Cost comes from an editable rate table.

---

## Concepts / models

| Model | Table | Role |
| :--- | :--- | :--- |
| `SubscriptionPlan` | `subscription_plans` | Pricing template (a "tier"). `monthly_price_per_user`, `annual_price_per_user`, `max_users`/`min_users`, `features` (JSON overrides), `is_public`. **Tiers are DB rows, not enums** — there is no hardcoded "Starter/Business/Enterprise"; the default new-org plan is named `"Standard"`. |
| `OrganizationSubscription` | `organization_subscriptions` | One per org. `base_plan`, `billing_frequency` (`monthly`/`annual`), `licensed_user_count` (**seats**), `current_period_start/end`, `status` (`trial`/`active`/`past_due`/`grace_period`/`suspended`/`cancelled`), mandate gate (`trial_requires_mandate`, `mandate_verified`), custom per-user price overrides. |
| `SubscriptionHistory` | `subscription_history` | Audit of plan/frequency/price/status changes (`change_type`, `old_value`/`new_value`, `changed_by`). |
| `UsageRecord` | `usage_records` | **The usage history.** One row per billable event: `user_added`, `user_removed`, `subscription_activated`, `billing_period_renewed`, `daily_snapshot`. Audit fields: `user`, `performed_by`, `price_per_user_snapshot`, `billable_delta`, `overage_count`. See §7. |
| `Invoice` + `InvoiceLineItem` | `invoices` | System-generated invoices. `invoice_number` (`INV-YYYY-MM-…`), period, `subtotal`/`tax_amount`/`total_amount`, `status` (`draft`/`pending`/`paid`/`overdue`/`void`), nested line items (`subscription`/`prorated`/…). |
| `Payment` + `InvoicePayment` | `payments` | Billing-side payments (distinct from the CRM `quotations.Payment`). |
| `RazorpaySubscription` / `RazorpayCustomer` / `RazorpayWebhookEvent` | `razorpay_*` | The mandate/auto-pay mirror. `method ∈ {upi, card, emandate}` — **eNACH = `emandate`**. |

---

## 1. Current-plan card

The whole card is one subscription object.

```
GET /api/v1/billing/subscriptions/
GET /api/v1/billing/subscriptions/{subscription_id}/
```

The list returns the caller's org's single subscription. Key fields → UI:

```jsonc
{
  "subscription_id": "…uuid…",
  "base_plan": "…plan_id…",
  "base_plan_name": "Business",            // → "Business"
  "billing_frequency": "monthly",          // → "billed monthly"
  "licensed_user_count": 8,                // → "8 seats"
  "current_period_end": "2026-07-01T…",    // → "renews 1 Jul 2026"
  "current_price_per_user": "6000.00",     // per-seat price for the active frequency
  "status": "active",
  "monthly_price_per_user": "6000.00",
  "annual_price_per_user": "…",            // (17%-off annual per-seat)
  "mandate_verified": true,
  "auto_renew": true
}
```

- **"₹48,000/mo"** = `licensed_user_count × current_price_per_user` (8 × 6000). The API
  returns the **per-seat** price; the FE multiplies by seats. There is no
  precomputed "monthly total" field.
- **Renewal date** = `current_period_end`.
- **"Change plan"** button → §5. **"Cancel"** button → `POST
  /subscriptions/{id}/cancel/` (`{ "reason"?, "cancel_at_cycle_end": true }`) — by
  default cancels at cycle end; the org keeps access until `current_period_end`.

---

## 2. Licenses (seats) card

The card shows **"8 / 8 used · 0 free to assign"** + **Add licenses** / **Remove**,
all served from the subscription object (§1):

- **"8 used"** = `active_user_count` (live count of active, billable users).
- **"/ 8"** = `licensed_user_count` (the **purchased ceiling**).
- **"0 free to assign"** = `free_seats` (= `licensed_user_count − active_user_count`).

**Adding / removing licenses is a billing action (System Admin only)** — see §6 for
the purchase flow and §7 for how it's billed. Distinct from **assigning** a user: an
admin creates a user via the management users API (`POST /api/v1/management/users/`),
which **consumes a free seat**. When `free_seats == 0`, user creation/reactivation is
**blocked with 400 `no_free_license`** — the admin must purchase a license first
(§13.4.1). Deactivating/deleting a user **frees** its seat (raising `free_seats`) but
does **not** lower the purchased ceiling — that only changes via the remove-licenses
flow (§6) at cycle end.

---

## 3. Storage card

**"14 GB / 50 GB"** — per-tenant attachment storage used vs. plan cap.

```
GET /api/v1/billing/storage/     # [IsAuthenticated, IsBillingAdmin]
```
```jsonc
{
  "used_bytes": 15032385536,
  "used_gb": 14.0,           // round(bytes / 1024³, 2) — coarse; 0.0 for a few MB
  "used_display": "14 GB",   // adaptive-unit string — render THIS on the card
  "limit_display": "50 GB",  // adaptive-unit string (null = unlimited plan)
  "limit_gb": 50,            // integer GiB cap  (null = unlimited plan)
  "limit_bytes": 53687091200,
  "percent": 28.0,           // null when unlimited → drives the bar
  "unlimited": false,
  "synced_at": "2026-07-15T03:30:00Z"   // last reconciliation
}
```

**Which field to display:** use **`used_display` / `limit_display`** for the "14 GB /
50 GB" text — they adapt the unit so small footprints stay legible (a 2 MB total returns
`used_display: "2 MB"`, whereas `used_gb` rounds to `0.0`). `used_bytes` is the exact
per-byte source (a 2 MB upload adds exactly 2,097,152); `used_gb` is a coarse 2-decimal
GiB value kept for backwards-compat. Drive the progress bar from `percent`.

How it works:
- **Used** = `OrganizationSubscription.storage_bytes_used`, a running per-org counter
  `F()`-incremented at the **single CDN chokepoint** (`BunnyCDNService.upload_file`,
  which now captures `file_obj.size`) and decremented on delete. A single 2 MB file
  therefore raises the counter by exactly its byte size; **no rounding happens at write
  time** — only the `*_gb` read value is rounded. A **nightly reconciliation**
  (`reconcile_storage_usage` Celery task, 03:30 UTC) recomputes each org's usage
  authoritatively from the Bunny Storage API (sums `Organizations/{id}/`,
  `legal-docs/{id}/`, `policies/{id}/`), correcting any drift. Backfill existing orgs
  with `manage.py backfill_storage_usage [--org <id>] [--dry-run]`.
- **Cap** = the `limits.storage_gb` plan feature (`billing/features/registry.py`;
  seeded per plan — Starter 5, Business 50, Enterprise unlimited). `null` = unlimited.
  GB↔bytes uses **GiB (1024³)**.
- **Enforcement is off by default** (`STORAGE_CAP_ENFORCED=false`) — the card is
  **display-only**; hitting the cap does **not** block uploads yet. Flip the env flag
  on (once reconciliation is trusted) and uploads over cap get a 403 `FeatureNotInPlan`.

---

## 3A. AI usage card (transcription + call-summary metering)

**"This month's AI usage"** — per-org **call-transcription** (audio) and **call-summary**
(LLM) consumption + cost. Same shape as the Storage card: a per-org running counter,
**display-only for now** (no cap enforcement). Both metered operations run in the call
recording pipeline (`crm/tasks.py::transcribe_call_recording`) — transcription is metered
by **audio seconds** (Sarvam returns no usage metadata), the summary by **LLM tokens**
(Groq/Gemini/Ollama), and cost is computed from a config rate table.

```
GET /api/v1/billing/ai-usage/            # [IsAuthenticated, IsBillingAdmin] — the card
GET /api/v1/billing/ai-usage/?month=2026-06     # optional ?month=YYYY-MM (defaults to current month)
```
```jsonc
{
  "period_month": "2026-07-01",   // first-of-month for the totals below
  "currency": "INR",
  "transcription": {
    "audio_seconds": 1830.0,      // total transcribed audio this month
    "audio_minutes": 30.5,        // render THIS on the card ("30.5 min transcribed")
    "cost": 0.0,                  // 0 until the Sarvam per-second rate is filled
    "record_count": 22            // number of transcriptions
  },
  "call_summary": {
    "total_tokens": 48200,        // input+output LLM tokens this month
    "cost": 0.23,                 // ₹ — Groq rate is filled (≈43k in + 5k out)
    "record_count": 22
  },
  "total_cost": 0.23              // transcription.cost + call_summary.cost
}
```

**Which field to display:** `transcription.audio_minutes` for the "N min" figure,
`call_summary.total_tokens` for "N tokens", and `total_cost` (with `currency`) for the
"₹/$ this month" amount. `audio_seconds` is the exact source; `cost` values are already
computed (6-dp precision on the ledger, floats here).

### The per-event ledger (drill-down)

For a "see every AI call" table, use the read-only ledger — one row per transcription /
summary event, org-scoped (org admins see their own org; superusers see all):

```
GET /api/v1/billing/ai-usage/records/                       # newest first, paginated
GET /api/v1/billing/ai-usage/records/?event_type=transcription   # or call_summary
GET /api/v1/billing/ai-usage/records/?created_after=2026-06-01&created_before=2026-06-30
```
```jsonc
{
  "ai_usage_id": "…uuid…",
  "event_type": "call_summary",       // "transcription" | "call_summary"
  "provider": "groq",                  // sarvam | groq | gemini | ollama | whisper
  "model": "llama-3.1-8b-instant",
  "input_tokens": 1000, "output_tokens": 500, "total_tokens": 1500,
  "audio_seconds": "0.000",            // non-zero only for transcription rows
  "cost": "0.007920", "currency": "INR",  // ₹ — (0.00005×1000 + 0.00008×500)/1000 × 88
  "rate_version": "groq:llama-3.1-8b-instant",   // which rate-table entry priced it
  "call_log": "…crm_call_log_id…", "call_log_id": "…", // the source call (drill-through)
  "user": "…user_id…", "user_name": "Manoj Varma",     // the call's caller/receiver
  "status": "success",
  "created_at": "2026-07-15T09:00:00Z"
}
```

How it works (mirrors the Storage card):
- **Metering** happens best-effort at the transcription task's chokepoint
  (`billing/services/ai_usage_service.py`): each event writes an append-only
  `AIUsageRecord` (frozen cost) and F()-upserts the per-`(org, month, event_type)`
  `AIUsageMonthly` counter — a metering failure **never** breaks the AI pipeline.
- **Cost** = a config rate table (`settings.AI_USAGE_RATES`, keyed `provider:model`;
  transcription is per-second, summary is per-1K-tokens in/out). Tokens/seconds are the
  ground truth; **rates are editable without a migration**. An unmatched rate yields
  cost 0 (usage still recorded).
- **Nightly reconciliation** (`reconcile_ai_usage_monthly` Celery task, **03:45 UTC** —
  staggered after storage) rebuilds the month's counters from the ledger, correcting any
  drift.
- **Caps are plumbed but off** — `limits.ai_tokens_per_month` /
  `limits.transcription_minutes_per_month` plan features exist and
  `ai_usage_service.enforce_cap` is wired, but enforcement only activates when
  `AI_USAGE_CAP_ENFORCED=true` (default off). Display/report only for now.

### How the cost is calculated

Every event follows the same two-step model: **meter the quantity** (exact, provider-
derived, stored on the `AIUsageRecord`), then **price it** from the config rate table
(`settings.AI_USAGE_RATES`, keyed `"<provider>:<model>"`, with a `"<provider>:*"`
wildcard fallback). The single implementation is
[`ai_usage_rates.compute_cost`](../../billing/services/ai_usage_rates.py); cost is
computed at write time and **frozen on the row** (with `rate_version` recording which
rate entry priced it). The monthly counter is just the sum of the per-row costs. An
unmatched rate → **cost 0** (usage still recorded). Values are quantized to 6 dp.

**Transcription — priced per second of audio**

- **Quantity:** `audio_seconds` — the decoded recording length (pydub
  `duration_seconds`, falling back to `CRMCallLog.duration`). Sarvam returns no usage
  metadata, so duration is the meter.
- **Formula:** `cost = per_second × audio_seconds`
  (`AI_USAGE_RATES["transcription"]["sarvam:saarika:v2.5"]["per_second"]`).
- **Example** — a 90 s call at `per_second = 0.001` → `0.001 × 90 = 0.090000`.
- The card shows **minutes** (`audio_seconds ÷ 60`) but the math runs in **seconds** — no
  rounding to whole minutes. To set the rate from a per-minute price: `per_second =
  price_per_minute ÷ 60`.

**Summary — priced per 1,000 tokens, input and output separately**

- **Quantity:** `input_tokens` + `output_tokens`, read straight from the LLM response
  (Groq `usage.prompt_tokens`/`completion_tokens`; Gemini `usage_metadata`; Ollama
  `prompt_eval_count`/`eval_count`).
- **Formula:** `cost = (in_per_1k × input_tokens + out_per_1k × output_tokens) ÷ 1000`
  (`AI_USAGE_RATES["summary"]["groq:llama-3.1-8b-instant"]`). Input and output are priced
  **independently** (output tokens cost more).
- **Example (real Groq rate)** — Llama 3.1 8B Instant is **$0.05/1M in, $0.08/1M out**.
  A summary using 2000 input + 300 output tokens → in INR at ₹88/USD ≈ **₹0.011**; a full
  1M in + 1M out would be `($0.05 + $0.08) × 88 = ₹11.44`.
- To set rates from a "per 1M tokens" price sheet: `per_1k = price_per_1M ÷ 1000`.

**Currency — billed in INR (₹).** Providers that price in USD (Groq, Gemini, Whisper)
are converted via a single config knob **`AI_USAGE_USD_TO_INR`** (default `88.0`,
overridable in `.env`). The rate expressions keep the USD origin visible so re-pricing is
a one-line FX change.

The rate table (in [`nexocrm/settings.py`](../../nexocrm/settings.py)):

```python
AI_USAGE_USD_TO_INR = config("AI_USAGE_USD_TO_INR", default=88.0, cast=float)
AI_USAGE_RATES = {
    "currency": "INR",
    "transcription": {                                   # ₹ per SECOND of audio
        "sarvam:saarika:v2.5": {"per_second": 0.0},      # ← fill from Sarvam pricing
        "whisper:whisper-1":   {"per_second": 0.0},      # $0.0001/s → 0.0001 * USD_TO_INR
    },
    "summary": {                                         # ₹ per 1,000 TOKENS
        # Groq Llama 3.1 8B Instant: $0.05/1M in, $0.08/1M out → ₹ at the FX rate:
        "groq:llama-3.1-8b-instant": {
            "in_per_1k":  0.00005 * AI_USAGE_USD_TO_INR,  # ≈ ₹0.0044
            "out_per_1k": 0.00008 * AI_USAGE_USD_TO_INR,  # ≈ ₹0.00704
        },
        "gemini:gemini-2.0-flash":   {"in_per_1k": 0.0, "out_per_1k": 0.0},  # ← fill (USD→INR)
        "ollama:*":                  {"in_per_1k": 0.0, "out_per_1k": 0.0},  # self-hosted → 0
    },
}
```

> **Filled so far: the active Groq summary model.** `groq:llama-3.1-8b-instant` carries
> real rates (₹ at ₹88/USD); the **transcription (Sarvam) rate and the other models are
> still `0.0`** — fill them from their price sheets to get a non-zero cost (Sarvam per
> **second**; USD models via `× AI_USAGE_USD_TO_INR`). The meters (`audio_seconds`,
> `total_tokens`) are always correct regardless. Changing a rate only affects **new** rows
> — existing rows keep their frozen cost (the stored tokens/seconds make a full recompute
> possible). `ollama:*` is self-hosted → 0 cost, tokens still tracked.

---

## 4. Payment mandate · eNACH

```
GET  /api/v1/billing/razorpay/mandate-status/          # the card's state
POST /api/v1/billing/razorpay/initiate-mandate/        # "Manage mandate" → set up / (re)authorize
POST /api/v1/billing/razorpay/cancel/                  # cancel the mandate
```

`mandate-status/` returns the `RazorpaySubscription` mirror:

```jsonc
{
  "razorpay_subscription_id": "sub_…",
  "method": "emandate",           // → "eNACH"  (upi | card | emandate)
  "status": "active",
  "mandate_verified": true,        // → "Auto-pay authorized"
  "short_url": "https://rzp.io/…", // hosted checkout to (re)authorize
  "paid_count": 3, "total_count": 120,
  "current_end": "2026-07-01T…"
}
```

- The **"Payment mandate" modal** (method = **eNACH** "Bank auto-debit" or **UPI
  AutoPay**) maps to the `method` body param: eNACH → `emandate`, UPI AutoPay →
  `upi` (`card` also supported). "Authenticate & register" / "Re-registration opens
  your bank's secure authentication" → call `initiate-mandate/` and redirect the
  admin to the returned **`short_url`** (the Razorpay hosted page). See the
  **Razorpay integration guide (§9)** for the full webhook lifecycle.
- **"HDFC Bank ••4821"** (bank + masked account) is **not** stored — the FE gets
  `method`/`status`/`mandate_verified`/`short_url` only. The **"authorized up to N
  seats"** copy corresponds to `RazorpaySubscription.mandate_cap_amount` (an
  **amount** cap set at registration = recurring × 2, added by the H6 merge) and the
  local `mandate_max_amount`; there is no per-seat cap field — the FE derives "N
  seats" from `mandate_cap_amount ÷ per-seat price` if it wants to show a seat number.
- **Mandate gate:** middleware **403**s most routes (`code: "mandate_required"`,
  `mandate_setup_url`) until `mandate_verified` is true — but all `/api/v1/billing/*`
  routes (incl. this card) are exempt, so the card always loads. Superusers bypass.

---

## 5. Change-plan modal

The modal uses **two endpoint families** — don't conflate them:

| Modal piece | Endpoint | Why |
| :--- | :--- | :--- |
| **The three tier cards** (Starter/Business/Enterprise: name, per-seat price, "Up to N seats", features) | **`GET /api/v1/billing/plans/`** (`SubscriptionPlan`) | The **catalogue** — this is the list you render. |
| Per-tier feature blurb ("core CRM", "SSO, audit, SLA") | `GET /api/v1/billing/plans/{plan_id}/resolved-features/` | Merged registry-defaults + plan overrides. |
| **Which card is highlighted** + Monthly/Yearly toggle position | **`GET /api/v1/billing/subscriptions/`** (`OrganizationSubscription`) | The org's **current** `base_plan` + `billing_frequency` — also the values the FE compares against for the banner. |
| **Preview** (the "charged today ₹X" / "effective 1 Jul" copy) | **`POST /api/v1/billing/subscriptions/{id}/change-plan/preview/`** `{ "plan_id", "billing_frequency"? }` | No writes — returns `direction` + `amount_charged_today` (upgrade) or `effective_date` (downgrade). |
| **Confirm change** (the write) | **`POST /api/v1/billing/subscriptions/{id}/change-plan/`** `{ "plan_id", "billing_frequency"?, "idempotency_key" }` | Applies the selection. **202** + `short_url` for an upgrade (awaiting payment); **200** for a scheduled downgrade. |
| Switch cycle only | `POST /api/v1/billing/subscriptions/{id}/change-billing-frequency/` `{ "new_frequency", "idempotency_key" }` | Monthly↔annual on the same tier — routed through the same §13.9 engine (M→Y upgrade, Y→M downgrade). |

- **`GET /plans/`** — org admins see only `is_active && is_public` plans (permission
  `HasSettingsPermission`; **read is org-admin-allowed**, writes are superuser-only).
  Each plan gives `name`, `monthly_price_per_user`, `annual_price_per_user`, `max_users`
  (→ "Up to N seats"), `features`. **Enterprise "Custom"** = a plan with a null/omitted
  public price (provider sets a per-org `custom_*_price_per_user`).
- **Monthly / Yearly toggle** = the `billing_frequency` field; "Save 17%" is the
  annual-vs-monthly per-seat delta the FE computes from the two plan prices on each card.
- **Render flow:** `GET /plans/` → render the cards; `GET /subscriptions/` → highlight
  the org's current `base_plan` and set the toggle to its `billing_frequency`; on
  Confirm → `POST …/change-plan/`.

### The modal-state banners — drive them from `change-plan/preview/`

The modal shows outcome banners — **NO CHANGE** (same plan+cycle), **EFFECTIVE
IMMEDIATELY** (upgrade / monthly→yearly), **EFFECTIVE 1 JUL** (downgrade at renewal).
**Call `POST …/change-plan/preview/` with the selected `plan_id` + toggle
`billing_frequency`** and render straight from its response — the backend now decides
the direction and timing for you (§13.9):

```jsonc
// POST /api/v1/billing/subscriptions/{id}/change-plan/preview/  { "plan_id", "billing_frequency"? }
{
  "direction": "upgrade",            // "upgrade" | "downgrade" | "noop"
  "from_plan": "Professional", "to_plan": "Enterprise",
  "from_frequency": "monthly", "to_frequency": "monthly",
  "licensed_user_count": 8,
  "price_delta_per_user": "1000.00", // per-seat uplift (upgrade only)
  "amount_charged_today": "4300.00", // day-prorated delta × seats + tax (0 for downgrade/noop)
  "currency": "INR",
  "period_start": "...", "period_end": "...",
  "effective_date": "2026-07-16T...",// now (upgrade) or cycle end (downgrade)
  "activates_immediately": true       // upgrade applies on payment; downgrade at renewal
}
```

- **`direction: "noop"`** → same plan+cycle → banner **NO CHANGE**, disable Confirm.
- **`direction: "upgrade"`** (higher tier, or Monthly→Yearly, §13.9.1/§13.9.3) → banner
  **"Charged today ₹`amount_charged_today`"**. On Confirm, `change-plan/` returns **202**
  + a Razorpay Payment Link `short_url`; redirect the admin to pay. The new plan applies
  **only after payment** (webhook), keeping the billing anchor. The recurring Razorpay
  debit reflects the new rate from next cycle.
- **`direction: "downgrade"`** (lower tier, or Yearly→Monthly, §13.9.2/§13.9.4) → banner
  **"Effective `effective_date`"**. On Confirm, `change-plan/` returns **200**; the change
  is recorded and applied at the next renewal — **no charge, no refund** this cycle.

**Backend behavior of `change-plan/` (the write):**

- **Requires `idempotency_key`** (§14.4.2) — a repeated key returns the existing change,
  never a second charge.
- **Upgrade** → creates a pending `PlanChange` + prorated `Invoice` + ad-hoc Payment Link
  (`reference_id="upgrade-<invoice>"`); does **not** touch `base_plan` until the
  `payment_link.paid` webhook fires `_activate_plan_upgrade` (see §9.2). Response 202.
- **Downgrade** → records a `scheduled` `PlanChange` (`effective_at = current_period_end`);
  applied at the renewal boundary by `plan_change_service.apply_scheduled_changes`. No
  Razorpay call now. Response 200.
- **Mandate cap (§13.5):** an upgrade whose new recurring exceeds the mandate cap returns
  **409 `mandate_cap_exceeded`** — nothing is persisted; the admin must re-register the
  mandate first.
- Missed-webhook recovery: `manage.py reconcile_plan_changes [--org --dry-run]` settles
  pending upgrades whose Razorpay link is confirmed `paid` (mirrors `reconcile_seat_purchases`).

> **Upgrade vs downgrade** is decided by `SubscriptionPlan.tier_rank` (seeded
> Starter=10 < Professional=20 < Enterprise=30) combined with frequency rank (annual >
> monthly), so Monthly→Yearly on the same tier counts as an upgrade. The FE never needs
> to compute the direction — `preview/` returns it.

### ⚠️ Frontend changes required (this replaces the old one-shot flow)

The old flow was "`POST change-plan/` once → refresh the plan card". That is **no longer
correct** — the endpoint URL, request body, and post-confirm handling all changed. The FE
must implement:

1. **Preview before Confirm.** When the admin picks a card / flips the toggle, call
   `POST …/change-plan/preview/` `{ plan_id, billing_frequency }` and render the banner
   from `direction` + `amount_charged_today` / `effective_date`. Do **not** compute the
   direction on the client — the backend owns it.
2. **URL + body change.** Confirm now posts to **`…/change-plan/`** (hyphen, was the
   DRF-default `change_plan/` with an underscore) and the body **must include a unique
   `idempotency_key`** (e.g. a UUID generated when the modal opens and reused across
   retries of the same intent). Missing key → `400 idempotency_key_required`.
3. **Branch on the response (this is the real new work):**
   - **202 (upgrade)** → the body has a Razorpay **`short_url`**. **Redirect the admin
     there to pay.** The plan does **not** change yet. On return from Razorpay, re-fetch
     `GET /subscriptions/` — the card flips to the new plan only once the webhook has
     settled (usually seconds; if it lags, it's the webhook-delivery path, §9.0/§9.3, not
     the FE). Optionally poll `GET /subscriptions/{id}/history/` for the `plan_changed`
     entry to confirm.
   - **200 (downgrade)** → no payment. Show "Effective `effective_date`" and refresh the
     card (it still shows the *current* plan until the cycle ends — that's correct).
4. **Handle `409 mandate_cap_exceeded`** on an upgrade Confirm: surface the "re-register
   your auto-pay mandate (higher cap) before upgrading" path (the eNACH card / §4), then
   let the admin retry the upgrade.
5. **`change-billing-frequency/` also changed** — it now goes through the same engine, so
   it too requires an `idempotency_key` and returns **202 + `short_url`** for Monthly→Yearly
   (treat it exactly like an upgrade Confirm) and **200** for Yearly→Monthly.

Because an upgrade is pay-then-apply, the modal's Confirm button for an upgrade should read
like a **checkout** ("Pay ₹X & upgrade"), mirroring the add-licenses modal (§6) — the two
flows share the same Payment-Link mechanics.

---

## 6. Add / remove licenses (System Admin only)

All three actions are on the subscription and require **`IsBillingAdmin`** (org admin
`is_staff` or superuser).

### Preview the charge (the modal's "Charged today ₹X")
```
POST /api/v1/billing/subscriptions/{id}/add-licenses/preview/
{ "seat_count": 2 }
```
Returns the **day-based** proration (§13.4.2) — no writes:
```jsonc
{
  "seat_count": 2, "free_seats_applied": 0, "chargeable_count": 2,
  "price_per_user": "6000.00", "amount_charged_today": "5200",   // 2 × 6000 × 13/30
  "activates_immediately": false, "period_end": "2026-07-01T…"
}
```
Proration = `seat_count × price_per_user × (days_remaining_incl_activation ÷ actual
days in this cycle)`; annual plans use the annual rate (§13.4.4); whole-rupee rounding.

> **`seat_count` is a DELTA — the number of seats to ADD, not a target total.**
> Adding N always charges for N and raises `licensed_user_count` by N. **Unassigned
> free seats do NOT reduce the charge or the count** — they are already in the ceiling;
> the add is new capacity on top of them. (Free seats only gate whether a *user* can be
> assigned, never the add-licenses charge.) So an org at `licensed=24, free=23` that
> adds 1 pays for 1 and ends at `licensed=25` — it does **not** net to ₹0, and it does
> **not** jump to 47. The **only** free-of-charge netting is §13.6.5 below.

### Buy licenses — pay-then-activate (§13.4.3)
```
POST /api/v1/billing/subscriptions/{id}/add-licenses/
{ "seat_count": 2, "idempotency_key": "<uuid the FE generates once per modal submit>" }
```
- Creates a pending `SeatPurchase` + a **pending Invoice** + an **ad-hoc Razorpay
  Payment Link** (NOT the mandate). Returns **202** with `short_url` — the FE redirects
  the admin to pay. **Seats are NOT added yet.**
- On successful payment, the `payment_link.paid` webhook (`seats-<invoice>` ref) adds
  the **chargeable** seat count (= `seat_count`, minus any §13.6.5 pending-removal
  restore) to `licensed_user_count`, marks the invoice paid, writes a `license_purchased`
  UsageRecord, and re-syncs Razorpay. **On failure/expiry, no seats** (§13.4.3).
- **Idempotent** (§14.4.2): the same `idempotency_key` returns the existing purchase +
  link — a double-click never double-charges.
- **Pending-removal netting** (§13.6.5): the **only** no-charge case — re-adding seats
  **scheduled for removal this cycle** (`pending_licensed_user_count` set) restores them
  for free (they were never relinquished) and cancels the pending removal; returns **200**
  `activated_immediately:true`. Unassigned *free* seats are **not** netted (see the delta
  note above). *(Prod bug fixed: activation previously added the requested `seat_count`
  to the ceiling instead of the chargeable delta, so an add jumped the ceiling far past
  the intended value — e.g. 23 free + add 1 → 47 instead of 25.)*
- **Mandate cap** (§13.5.2): if the new recurring would exceed `mandate_max_amount`,
  returns **409 `mandate_cap_exceeded`** (no link) — the admin must re-register the
  mandate at a higher cap.
- *"Simulate a failed payment (demo)"* is a **pure UI toggle** — no backend.

### Remove licenses (effective next cycle, no refund — §13.6)
```
POST /api/v1/billing/subscriptions/{id}/remove-licenses/
{ "seat_count": 1 }
```
- **No refund / no mid-cycle change** (§13.6.1): sets `pending_licensed_user_count`;
  the reduced ceiling applies at the next renewal.
- **409 `deactivate_users_first`** if the target would drop below active users
  (§13.6.3); **409 `below_admin_floor`** if below the admin floor / 1 (§13.6.4).
- Remove-then-re-add within the same cycle is free (§13.6.5) — the ceiling hasn't
  dropped yet, so those seats are still "free to assign".

---

## 7. Invoices & billing history + Usage history

### Invoices (the list at the bottom of the page)

```
GET /api/v1/billing/invoices/                      # list (org-scoped, newest first)
GET /api/v1/billing/invoices/{invoice_id}/         # one invoice + nested line_items
GET /api/v1/billing/invoices/{invoice_id}/pdf/     # the "eye" / "tap to view" → PDF download
```

```jsonc
{
  "invoice_number": "INV-2026-06",         // → row title
  "period_start": "2026-06-01T…",          // → "01 Jun 2026"
  "total_amount": "56640.00",              // → "₹56,640"
  "status": "paid",                         // → green "Paid"  (draft|pending|paid|overdue|void)
  "line_items": [ { "description": "…", "item_type": "subscription", "quantity": 8, "unit_price": "6000.00", "is_prorated": false, "subtotal": "48000.00" } ]
}
```

- **"GST invoices · tap to view"** → the per-invoice `pdf/` action (WeasyPrint,
  `Content-Disposition: attachment`).
- **⚠️ GST gap:** tax is a **flat 18%** applied only when the org's billing country is
  India and it's not tax-exempt. There is **no GSTIN, HSN/SAC, place-of-supply, or
  CGST/SGST/IGST split** on the invoice. If these are real GST invoices, the
  model/template need those fields. **Flag for product.** *(Fixed 2026-07-15: the PDF
  template previously referenced a non-existent `invoice.issue_date` field and would
  raise `AttributeError` on every PDF request — it now uses the invoice's `created_at`
  as the issue date. `org.billing_email` does exist and was never broken.)*
- Invoices are **read-only** (system-generated on charge/renewal). No create.
  Superuser-only: `POST /invoices/{id}/void/`.

### Usage history (seat add/remove audit) — `GET /api/v1/billing/usage/`

Read-only; org admins see their own org's rows. Each row is a billable event:

```jsonc
{
  "event_type": "user_added",              // user_added | user_removed | subscription_activated | billing_period_renewed | daily_snapshot
  "timestamp": "2026-06-12T…",
  "active_user_count": 8, "licensed_user_count": 7, "overage_count": 1,
  "user": "…user_id…", "user_name": "Divya Mishra",        // who was added/removed
  "performed_by": "…user_id…", "performed_by_name": "Manoj Varma",  // the admin who did it
  "price_per_user_snapshot": "6000.00",    // frozen at event time
  "billable_delta": "6000.00"              // what this event adds to the next invoice (0 for removals)
}
```

Use this to render an audit/history of seat changes (who added/removed which user,
when, at what price). See §8 for exactly which actions write these rows.

---

## 8. Usage tracking — how seat add/remove is recorded (backend behavior)

`licensed_user_count` and the `UsageRecord` history are driven by **`accounts.User`
lifecycle signals** in [billing/signals.py](../../billing/signals.py), not by any
billing endpoint. A row is written for every seat change:

| User action | Signal | Effect |
| :--- | :--- | :--- |
| **Create** a billable, active, non-superuser user | `post_save` (`created`) | `+1` seat, `user_added` UsageRecord (`user`, `performed_by`, price snapshot), Razorpay quantity re-synced. |
| **Reactivate** (`is_active` False→True, first time) | `post_save` | same as create. |
| **Deactivate** (`is_active` True→False) | `pre_save` | `−1` seat (floor 0), `user_removed` UsageRecord. |
| **Hard-delete** an *active, billable* user | **`post_delete`** | `−1` seat (floor 0), `user_removed` UsageRecord (`user=None` since the row is gone, `performed_by` = actor). **Added 2026-07-15** — previously a hard delete bypassed tracking entirely (see below). |

**Fix (2026-07-15): hard-delete now tracked.** Before this, seat/usage tracking
lived only on `pre_save` (deactivation). The management **`DELETE
/api/v1/management/users/{id}/`** path hard-deletes the row (`instance.delete()`),
which never fires `pre_save` — so deleting an active billable user left
`licensed_user_count` **too high** and wrote **no** `user_removed` record (the usage
history under-counted removals). A new `post_delete` handler (`handle_user_deleted`)
mirrors the deactivation logic, guarded so an **already-deactivated** user isn't
double-counted (it only acts when the deleted user was still `is_active` +
`is_billable`). Covered by `TestHandleUserDeleted` in
[billing/tests/test_signals.py](../../billing/tests/test_signals.py).

Non-billable users, superusers, and orgs without an active/trial/grace subscription
are ignored (no seat change, no record). Removals have `billable_delta = 0` (a
removed seat is still covered until period end — prepaid model).

---

## 9. Razorpay integration guide

How the billing surface actually moves money. The backend is a **thin control plane
over Razorpay Subscriptions + Payment Links**; the real charges and the source of
truth for "is this paid" come back as **webhooks**. Two rules to internalize:

1. **The frontend never charges.** It calls a backend endpoint, gets a Razorpay
   **`short_url`** (hosted page), and **redirects the user there**. The user pays on
   Razorpay's page.
2. **State changes on the webhook, not the API response.** The API call only *starts*
   a flow (creates a pending Subscription / Payment Link). The seat/plan/paid state
   flips only when Razorpay posts the corresponding **webhook** back. FE must poll or
   refresh after the redirect returns.

### 9.0 The webhook pipeline (applies to every flow)

`POST /api/v1/billing/razorpay/webhook/` — **`AllowAny`, no JWT**, HMAC-verified.
Configure this URL in the Razorpay dashboard with the events below and the secret
`RAZORPAY_WEBHOOK_SECRET`.

1. **Signature check** — `X-Razorpay-Signature` HMAC-SHA256 of the raw body with
   `RAZORPAY_WEBHOOK_SECRET`; 400 on mismatch.
2. **Idempotency** — `X-Razorpay-Event-Id` is upserted into `RazorpayWebhookEvent`
   (unique); a duplicate returns `already_processed` and is not re-run.
3. **Async dispatch** — persists, returns `{"status":"ok"}` within Razorpay's ~5s SLA,
   then `transaction.on_commit` → Celery `process_razorpay_webhook` → `handle_webhook`
   → the per-event handler (each runs in its own transaction; success → event
   `processed`, stale/unknown → `ignored`, error → `failed` + retry, max 5).

**Event → handler → effect** (`billing/services/mandate_service.py`):

| Razorpay event | Handler | Effect |
| :--- | :--- | :--- |
| `subscription.authenticated` | `_handle_authenticated` | mandate mirror → `authenticated`; **flips `mandate_verified=true`** (unlocks the gate); stamps `mandate_authorized_at`. |
| `subscription.activated` | `_handle_activated` | mirror → `active`; sets `trial_activated_at`, `current_period_start`. |
| `subscription.charged` | `_handle_charged` | **the money event** — creates the cycle Invoice + Payment (paid), advances the period, applies pending seat removals, bills mid-cycle arrears. Fires at trial end (first charge) and every renewal. |
| `subscription.pending` | `_handle_pending` | local → `past_due` + payment-failed email. |
| `subscription.halted` | `_handle_halted` | → grace period. |
| `subscription.cancelled` / `subscription.completed` | `_handle_*` | local cancel / `auto_renew=false`. |
| `payment_link.paid` | `_handle_payment_link_paid` | reconciles an **ad-hoc** Payment Link → marks its Invoice paid; if `reference_id` starts `seats-`, **activates the purchased seats**. |

> **You must register all of these events** in the Razorpay webhook config, or the
> corresponding local state never advances (e.g. no `subscription.charged` → invoices
> never appear and the trial never converts).

### 9.1 Mandate setup / (re)authorization — the eNACH card

```
POST /api/v1/billing/razorpay/initiate-mandate/   { "method": "emandate"|"upi"|"card", "plan_id": "<uuid>" }
→ { "short_url": "https://rzp.io/…", "razorpay_subscription_id": "sub_…", "razorpay_key_id": "…" }
```

**Backend** (`initiate_mandate`): resolves the plan, sets the local `mandate_max_amount`
(= recurring × 2), creates a Razorpay **customer + per-seat Plan + Subscription** with
**`start_at = trial_end`** (so the first real debit is deferred to trial end), and
saves a `RazorpaySubscription` (`status=created`) with the `short_url`.

**FE sequence:**
1. Open the "Payment mandate" modal → user picks eNACH / UPI AutoPay → POST above.
2. **Redirect to `short_url`** (Razorpay hosted authorization).
3. On return, **poll `GET /api/v1/billing/razorpay/mandate-status/`** until
   `mandate_verified: true`.
4. Webhooks that drive it: `subscription.authenticated` → `mandate_verified=true`
   (gate unlocks) → `subscription.activated` → at trial end `subscription.charged`
   creates the first invoice.

Re-registration (raising the mandate cap, e.g. after a `mandate_cap_exceeded` on
add-licenses) is the **same** call — it replaces the pending subscription and returns
a fresh `short_url`.

### 9.2 Change plan / billing frequency (§13.9)

```
POST /api/v1/billing/subscriptions/{id}/change-plan/preview/     { "plan_id", "billing_frequency"? }
POST /api/v1/billing/subscriptions/{id}/change-plan/             { "plan_id", "billing_frequency"?, "idempotency_key" }
POST /api/v1/billing/subscriptions/{id}/change-billing-frequency/ { "new_frequency": "monthly"|"annual", "idempotency_key" }
```

Plan changes are **asymmetric** (see §5 for the FE contract):

- **Upgrade** (higher tier / Monthly→Yearly) — pay-then-apply, **exactly like a seat
  addition (§9.3)**: the prorated *price-delta × seats* is collected via a **one-off
  Payment Link** (`reference_id="upgrade-<invoice>"`), the admin is redirected to
  `short_url`, and the `payment_link.paid` webhook runs `_activate_plan_upgrade` →
  swaps `base_plan`/`billing_frequency`, writes `plan_changed` usage+history, and
  enqueues **`sync_razorpay_plan`** (creates the new per-seat Razorpay plan and
  `update_subscription(new_plan_id=…, schedule_change_at="cycle_end")`, so the recurring
  debit reflects the new rate from next cycle). Billing anchor is preserved (§13.9.3).
- **Downgrade** (lower tier / Yearly→Monthly) — **no charge, no webhook**. A `scheduled`
  `PlanChange` is recorded and applied at the next renewal boundary by
  `plan_change_service.apply_scheduled_changes` (called from both `_handle_charged` and
  `SubscriptionManager.renew_subscription`). The recurring debit drops from next cycle.

Trial orgs skip the Razorpay recurring sync (they get the right plan when their recurring
sub starts at trial end). Missed-webhook recovery for a stuck upgrade:
`manage.py reconcile_plan_changes`.

### 9.3 User / seat addition — ad-hoc Payment Link (NOT the mandate)

The mandate **cannot** collect an ad-hoc mid-cycle charge, so seats use a **one-off
Payment Link** (§13.4.3). Flow:

```
POST /api/v1/billing/subscriptions/{id}/add-licenses/preview/  { "seat_count" }      # "Charged today ₹X"
POST /api/v1/billing/subscriptions/{id}/add-licenses/          { "seat_count", "idempotency_key" }
→ 202 { "short_url": "https://rzp.io/…", "seat_purchase_id", "amount", "invoice_number" }
   OR 200 { "activated_immediately": true }   # §13.6.5 pending-removal restore only, no charge
```

**FE sequence:**
1. Show the preview amount (day-prorated) in the modal.
2. On "Pay & activate" → POST add-licenses/ with a **client-generated
   `idempotency_key`** (one per modal submit; a retry with the same key never
   double-charges).
3. **202** → redirect to `short_url`. **200 `activated_immediately`** → a §13.6.5
   pending-removal was restored (no charge), just refresh the card.
4. **Seats do NOT increment on the 202** — they activate only when the
   **`payment_link.paid`** webhook (`reference_id="seats-<invoice>"`) fires →
   `_activate_seat_purchase` bumps `licensed_user_count` **by the chargeable delta**,
   marks the invoice paid, and
   schedules `sync_razorpay_plan_amount` (Celery) which calls Razorpay
   `update_subscription(new_quantity=…)` so the **recurring** debit picks up the new
   seat count from next cycle. On payment failure/expiry: **no seats** (invoice stays
   pending).
5. Poll/refresh the seats card after redirect. `409 mandate_cap_exceeded` → send the
   user to re-register the mandate (§9.1) first.

> **Removal** (`remove-licenses/`) makes **no Razorpay call** — it records
> `pending_licensed_user_count`; the reduced quantity is reconciled at the next
> `subscription.charged` (§9.4). No refund (§13.6).

> **⚠️ The `payment_link.paid` event MUST be enabled in the Razorpay dashboard.** Seat
> activation + invoice-paid depend entirely on this webhook — there is no automatic
> polling. If the event isn't configured (or the `webhooks` Celery worker is down), a
> **successfully paid** link leaves its invoice stuck at **"Pending"** forever. Symptom:
> `RazorpayWebhookEvent.objects.count() == 0` while SeatPurchases sit `pending`.
> **Recovery for missed webhooks:** `manage.py reconcile_seat_purchases [--org <id>]
> [--dry-run]` — it fetches each pending SeatPurchase's link from Razorpay and settles
> **only** the ones Razorpay confirms `paid`, through the same activation path (records
> the Payment, marks the invoice paid, bumps the seat ceiling). Idempotent.

### 9.4 Subscription renewal (recurring charge)

Fully Razorpay-driven — **no endpoint, no FE action**. Each cycle Razorpay debits the
mandate and posts **`subscription.charged`** → `_handle_charged`:
- creates the cycle **Invoice + Payment** (marked paid) → appears in "Invoices &
  billing history";
- advances `current_period_start/end` (from Razorpay's payload) and **applies a
  scheduled seat removal**: `licensed_user_count = max(pending_licensed_user_count OR
  licensed_user_count, active_users, 1)` — the purchased ceiling never silently
  collapses to the active-user count;
- bills any mid-cycle seat **arrears** for the closing period as prorated line items;
- stamps the immutable **`billing_anchor_date`** on first paid charge — all future
  period boundaries derive from it (drift-free across short months, via
  `billing.services.billing_cycle`).

Dunning (payment failures) is also webhook-driven: `subscription.pending` → `past_due`,
`subscription.halted` → grace period.

### 9.5 Razorpay config checklist (ops)

- Env: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` (all required).
- Dashboard webhook → `https://<host>/api/v1/billing/razorpay/webhook/`, secret =
  `RAZORPAY_WEBHOOK_SECRET`, events: all `subscription.*` in the table above **plus
  `payment_link.paid`**.
- Superadmin recovery: `GET /razorpay/webhook-events/` (log) and
  `POST /razorpay/webhook-events/{event_id}/replay/` to re-run a missed/failed event.

---

## Quick reference

| Purpose | Method & Path |
| :--- | :--- |
| Current plan / subscription | `GET /api/v1/billing/subscriptions/` |
| Cancel subscription | `POST /api/v1/billing/subscriptions/{id}/cancel/` |
| **Preview a plan change** | `POST /api/v1/billing/subscriptions/{id}/change-plan/preview/` |
| **Change plan (up/down/tier)** | `POST /api/v1/billing/subscriptions/{id}/change-plan/` |
| Switch monthly↔annual | `POST /api/v1/billing/subscriptions/{id}/change-billing-frequency/` |
| Subscription change history | `GET /api/v1/billing/subscriptions/{id}/history/` |
| Plan catalogue (modal tiers) | `GET /api/v1/billing/plans/` |
| Plan resolved features | `GET /api/v1/billing/plans/{id}/resolved-features/` |
| Mandate status (eNACH card) | `GET /api/v1/billing/razorpay/mandate-status/` |
| Set up / manage mandate | `POST /api/v1/billing/razorpay/initiate-mandate/` |
| Cancel mandate | `POST /api/v1/billing/razorpay/cancel/` |
| Invoices list | `GET /api/v1/billing/invoices/` |
| Invoice PDF (GST view) | `GET /api/v1/billing/invoices/{id}/pdf/` |
| **Usage history (seat audit)** | `GET /api/v1/billing/usage/` |
| Billing payments | `GET /api/v1/billing/payments/` |
| Org's resolved features | `GET /api/v1/billing/features/me/` |
| **Storage usage (card)** | `GET /api/v1/billing/storage/` |
| **AI usage (card)** | `GET /api/v1/billing/ai-usage/` |
| **AI usage ledger (drill-down)** | `GET /api/v1/billing/ai-usage/records/` |
| **Preview add-licenses charge** | `POST /api/v1/billing/subscriptions/{id}/add-licenses/preview/` |
| **Add licenses (pay-then-activate)** | `POST /api/v1/billing/subscriptions/{id}/add-licenses/` |
| **Remove licenses (next cycle)** | `POST /api/v1/billing/subscriptions/{id}/remove-licenses/` |
| Assign a user to a seat | `POST /api/v1/management/users/` (blocked 400 if no free seat) |
| **Mandate status (eNACH card)** | `GET /api/v1/billing/razorpay/mandate-status/` |
| **Set up / re-register mandate** | `POST /api/v1/billing/razorpay/initiate-mandate/` |
| Cancel mandate | `POST /api/v1/billing/razorpay/cancel/` |
| **Razorpay webhook receiver** | `POST /api/v1/billing/razorpay/webhook/` (AllowAny, HMAC — see §9) |
| Webhook event log (superadmin) | `GET /api/v1/billing/razorpay/webhook-events/` |
| Replay a webhook (superadmin) | `POST /api/v1/billing/razorpay/webhook-events/{id}/replay/` |

## Gaps summary (for product)

1. ~~**Seats** — no add/remove-licenses endpoint~~ — **implemented** (§2, §6): purchased
   ceiling vs active split, day-prorated pay-then-activate add, next-cycle removal,
   mandate-cap block, idempotency. Remaining open items: unpaid-purchase-link expiry
   job, and sourcing the real authorized mandate cap for pre-existing orgs.
2. ~~**Storage** — no backend~~ — **implemented** (§3): per-org counter at the CDN
   chokepoint + nightly Bunny reconciliation, `limits.storage_gb` cap,
   `GET /billing/storage/`. Display-only until `STORAGE_CAP_ENFORCED` is turned on.
2a. ~~**AI usage** — no token/cost tracking~~ — **implemented** (§3A): per-event ledger
   (`AIUsageRecord`) + monthly counter for call transcription (audio-seconds/Sarvam) and
   call summary (LLM tokens/Groq·Gemini·Ollama), cost from an editable rate table,
   `GET /billing/ai-usage/` + `…/records/`, nightly reconcile. Display-only until
   `AI_USAGE_CAP_ENFORCED` is on. Open items: **fill the `AI_USAGE_RATES` numbers**
   (ship as `0.0` placeholders → cost column is 0 until set); **chatbot** LLM tokens
   (`crm/services/chat_service`) are not yet metered (the model/service are generic
   enough to add it — `event_type` is a free field).
3. ~~**Change-plan states** — backend applies immediately with no upgrade-immediate /
   downgrade-at-renewal policy, no proration charge, and no preview endpoint~~ —
   **implemented** (§5, §9.2, §13.9): `tier_rank`-driven upgrade/downgrade split,
   day-prorated pay-then-apply upgrade via ad-hoc Payment Link, next-cycle downgrade,
   `change-plan/preview/` endpoint, mandate-cap block, idempotency, missed-webhook
   reconcile. Open item: two distinct custom plans at the same `tier_rank`+price read as
   `noop` (only affects per-org private plans, not the public catalogue).
4. **GST invoices** — flat 18% only; no GSTIN/HSN/place-of-supply/tax-split. (§7)
   *(Fixed: the phantom `invoice.issue_date` reference that broke every invoice PDF.)*
5. **Mandate card** — no stored bank name / masked account tail / seat-authorization
   cap. (§4)
6. ~~**Latent bug** — `change_billing_frequency` referenced an undefined
   `amount_paise`~~ — **fixed 2026-07-15** (now `per_seat_paise`).
