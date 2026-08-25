# Meta Ads — Lead Ads Integration — Frontend & Backend Guide

Backs the **Meta (Facebook/Instagram) Lead Ads** integration: real-time webhook
ingestion, historical bulk pull, **automatic** promotion to CRM leads, and
**per-form questions & answers** surfaced on the CRM lead detail.

All meta-ads endpoints mount under **`/api/v1/meta-ads/`**. The integration is
billing-gated by the **`meta_ads` plan feature** (the webhook is deliberately
ungated). Everything is org-scoped by the JWT — you never pass an org id.
Deeper internals: the in-app `meta_ads/COMPREHENSIVE_DOCUMENTATION.md`.

---

## 1. Data model (two tables + a form cache)

| Model | Table | Role |
| :--- | :--- | :--- |
| `MetaIntegrationSettings` | — | **One per org** (OneToOne). Meta App creds + tokens (Fernet-encrypted), `page_id`, `verify_token`, `ad_account_id`, `graph_api_version` (default `v23.0`), `is_active`. |
| `MetaLeadForm` | `meta_lead_forms` | Per-org cache of a Lead Ad form's **questions** metadata (`unique (organization, form_id)`), refreshed on a 24 h TTL. See §4. |
| `MetaAdsLead` | — | **Staging row** per lead (dedup key `leadgen_id`). Holds `field_data` (flat dict), **`qa`** (ordered Q&A, §5), `raw_payload` (full Graph response), processing state, and `promoted_lead` FK → `crm.Lead`. |

`crm.Lead` has **no** Meta columns — the link is `MetaAdsLead.promoted_lead`
(reverse accessor `lead.meta_ads_source`), plus legacy `custom_fields` keys (§6).

---

## 2. How a lead flows in — webhook → staging → CRM (all automatic)

```
Meta webhook  POST /api/v1/meta-ads/webhook/         (HMAC-verified, fast-ACK 200)
  → Celery process_meta_lead_task(leadgen_id, page_id)
      → Graph API GET /{leadgen_id}?fields=…,field_data   (field_data = ordered Q&A array)
      → form questions via 24 h TTL cache  (MetaLeadForm, §4)
      → upsert MetaAdsLead  (field_data flat dict + qa ordered list + raw_payload)
      → transaction.on_commit → promote_staged_leads_task.delay(org)
          → crm.Lead created  (lead_source = "Meta Ads")
```

**Promotion is automatic** (rulebook §15.4 "leads auto-create in CRM"). Once the
org's integration is configured, a webhook lead lands in **both** the staging
table and the CRM lead list within seconds — no manual step. The promote task:

- is **idempotent** — only picks `is_processed=False, error_message=""` rows;
- is **row-locked** (`select_for_update(skip_locked=True)`) so concurrent runs
  (one chain fires per webhook lead) divide the backlog instead of double-creating;
- **self-requeues** (`apply_async(countdown=2)`) whenever it processed a *full*
  batch, draining the staging table until a partial/empty batch is drawn.

`POST /api/v1/meta-ads/promote/` remains only as a **manual re-trigger** (e.g. to
retry after an operator clears a stuck `error_message`).

---

## 3. Historical sync — `bulk-pull` (auto-promotes, self-paced)

```
POST /api/v1/meta-ads/bulk-pull/     → 202 {"message": "Bulk pull task enqueued."}
```

`bulk_pull_meta_leads_task` paginates `GET /{page_id}/leadgen_forms`, then per
form `GET /{form_id}/leads?since=…` back **~2 years**, upserts each lead
(`bulk_create(update_conflicts=True, unique_fields=["leadgen_id"])`, incl. `qa`),
and — when any new rows were staged — **chains promotion** of the whole backlog.

**Meta rate limits:** the task **paces itself** — `time.sleep(BULK_PULL_PAGE_DELAY)`
(setting/env **`METAADS_BULK_PULL_PAGE_DELAY`, default 1 s**) between every Graph
API page fetch (forms pages, per-form, and lead pages), so a large sync trickles
instead of bursting. Reactive backstops (unchanged): the Graph client's urllib3
`Retry` on **429/5xx** (honors `Retry-After`) + a module-level **circuit breaker**
(5 failures → open 300 s). Promotion makes **zero** Meta calls (pure DB
staging→Lead), so its `batch_size` (100) is a DB batch and never touches Meta
limits.

---

## 4. Form questions cache — `MetaLeadForm`

**Each lead can come from a different form with different questions.** The Graph
form fetch (`GET /{form_id}?fields=id,name,status,questions`) returns the question
metadata `[{key, label, type, options?}]`; `meta_ads/services.get_or_fetch_form`
caches it per org (`unique (organization, form_id)`) and refreshes only when older
than **24 h**. On a Graph error it returns the **stale cached row** (or `None`) —
ingestion never fails on a form lookup.

---

## 5. Per-lead Q&A — `MetaAdsLead.qa`, frozen at ingest

Each staged lead stores **`qa`**: its answers joined to the form's question
labels, **in form order**, frozen at ingest (forms get edited later; the labels
the person actually answered are the correct ones):

```jsonc
"qa": [
  {"key": "full_name", "question": "Full name",           "type": "FULL_NAME",       "answer": "Priya S"},
  {"key": "email",     "question": "Email address",        "type": "EMAIL",           "answer": "priya@example.com"},
  {"key": "budget",    "question": "What's your budget?",  "type": "SHORT_ANSWER",    "answer": "50k"},
  {"key": "interests", "question": "Interests",            "type": "MULTIPLE_CHOICE", "answer": ["a", "b"]}
]
```

- Multi-select answers keep the **list**; single answers are scalars.
- A key with no matching question (form edited/deleted, or a built-in field
  without metadata) falls back to a titled key (`custom_extra_question` →
  "Custom Extra Question", `type: "CUSTOM"`).
- `GET /api/v1/meta-ads/leads/` (staging list) includes `qa`.
- Re-running bulk-pull re-freezes labels at pull time (the cache may have refreshed).

### 5.1 How the join works

Meta gives us the questions and the answers **separately**, and neither the
answer carries its question text:

```
questions   (form,  cached)  [{"key": "budget",  "label": "What's your budget?", "type": "SHORT_ANSWER"}, …]
field_data  (lead,  per-lead)[{"name": "budget", "values": ["50k"]},                                      …]
```

The **join key is Meta's slug** (`questions[].key` == `field_data[].name` — Meta
guarantees this equality for custom questions). `build_qa`
([meta_ads/services.py](../meta_ads/services.py)):

1. Indexes the questions into `{key: question}` (O(1) lookup).
2. Iterates the **answer** array (not the questions) — so the output preserves
   the order the person filled the form and only contains **answered** questions.
3. Per answer: looks up its question by slug, emits
   `{key, question=label, type, answer}`.

It runs **once at ingest**; the result is frozen onto `MetaAdsLead.qa`.

### 5.2 Design rationale — why frozen materialization, not a live join

| Choice | Why |
| :--- | :--- |
| **Freeze `qa` at ingest** (not join at read-time) | The form owner can rename/delete questions later; the label the person actually answered under is the correct one. A live join against the current form would rewrite history. Also: reads become a plain column fetch, no per-view lookup. |
| **Store on `MetaAdsLead`** (not a separate answers table / EAV) | A lead's Q&A is a small, read-together, write-once bundle — a JSON column is the right grain. An EAV `MetaLeadAnswer` table would add rows + joins for zero query benefit (we never filter/sort by individual answers — that's the deliberately-out-of-scope "map to custom field" feature, §10.1). |
| **Cache questions in `MetaLeadForm`** (not re-fetch per lead) | Many leads share one form. One Graph call per form per 24 h vs one per lead. |
| **Key-based join** (not positional) | Meta's `name`/`key` equality is the documented contract; positional pairing would break the moment the answer array omits an optional/unanswered question. |

### 5.3 Known edge cases (accepted — documented, not code-changed)

- **Duplicate question keys → label drift.** Meta does **not** guarantee unique
  `key`s within a form (e.g. two free-text questions slugged identically, or
  `custom_question_N` collisions). The `{key: question}` index is **last-wins**,
  so colliding questions all resolve to the *last* one's label. **Answers stay
  correct** (they come from `field_data`); only the displayed *question label* may
  be wrong for the collided keys. Rare in practice; if it becomes real, switch
  `build_qa` to consume duplicates positionally (per-key FIFO buckets).
- **Answer shape is scalar-or-list.** `answer` is a **string** for a single
  value, a **list** for multi-select, and `[]` for an answered-but-empty field.
  The FE must handle all three (this matches the legacy flat `field_data`
  convention used elsewhere). If a single shape is preferred later, normalize
  `answer` to always-list (needs a `backfill_meta_qa` re-run + this doc updated).
- **Empty/absent `label` on built-ins.** Meta may return no `label` for
  `FULL_NAME`/`EMAIL`/`PHONE` (the label is implied by `type`). The slug fallback
  handles it (`full_name` → "Full Name"); `type` is the more reliable signal for
  built-ins and is always emitted.
- **First-lead thundering herd on a new form.** A burst of webhook leads for a
  form not yet cached each run `get_or_fetch_form`, all miss, and all call the
  Graph API; the `filter().first()` → `update_or_create` is not atomic against a
  concurrent insert (a brief `unique (organization, form_id)` race is possible,
  though `update_or_create` retries). Bounded and self-healing (next lead reads
  the now-cached row); not hardened deliberately.

### 5.4 Alternatives considered (and why not)

- **Live join at read-time** (don't store `qa`; join `field_data` × current
  `MetaLeadForm` when the lead is viewed). Rejected: rewrites labels after form
  edits, and adds a lookup to every lead-detail read.
- **Normalized `MetaLeadAnswer` rows** (one row per answer, FK to a
  `MetaFormQuestion`). Rejected: EAV overhead with no upside — we read the whole
  Q&A together and never query a single answer. Only justified if/when answers
  must become filterable CRM fields (§10.1), which is a different feature.
- **Store answers keyed by question label** (`{"What's your budget?": "50k"}`).
  Rejected: loses order, type, and multi-value fidelity, and breaks on duplicate
  labels — strictly worse than the slug-keyed array.
- **Map answers onto `crm.Lead` custom fields at promotion** (make them
  first-class, filterable). This is the **right long-term** answer for *querying*
  Q&A, but it's the explicitly-deferred admin-mapping feature (§10.1); the frozen
  `qa` display works today without any per-org configuration.

---

## 6. On the CRM lead detail — `meta_qa`

**`GET /api/v1/crm/leads/{lead_id}/`** (retrieve only) returns:

```jsonc
"meta_qa": {
  "form_name": "Summer Campaign",
  "platform": "facebook",            // or "instagram"
  "items": [ { "key", "question", "type", "answer" }, ... ]   // ordered, §5 shape
}
```

- `null` when the lead was not promoted from Meta.
- **Detail-only by design** — the list endpoint never computes it (the viewset
  sets the `include_meta_qa` context flag only on `retrieve`), so list responses
  add **zero** queries per row. The FE renders a "Form responses" section when
  `meta_qa` is non-null.
- **Promotion field mapping** (`promote_staged_leads_task`): `first_name` ←
  `first_name` / first token of `full_name` / else `"Meta Lead"`; `last_name` ←
  `last_name` / remainder of `full_name`; `email` ← `email`; `mobile_no` ←
  `phone_number` / `phone`; `lead_source` ← the org's auto-created **"Meta Ads"**
  `LeadSource`.
- **Compat:** promotion also writes the legacy `custom_fields` keys
  (`meta_raw_fields`, `meta_form_name`, `meta_leadgen_id`, `meta_platform`), but
  **`meta_qa` is the canonical display source** — it carries labels, types, and
  order; the blob doesn't.

---

## 7. Endpoints reference (permissions are exact)

| Purpose | Method & Path | Auth |
| :--- | :--- | :--- |
| Webhook (Meta → us) | `GET`/`POST /api/v1/meta-ads/webhook/` | **Public**, CSRF-exempt, HMAC (`X-Hub-Signature-256`) |
| Integration settings | `GET/PUT/PATCH /api/v1/meta-ads/settings/` | `HasSettingsPermission` + `meta_ads` feature |
| Staged leads list (incl. `qa`) | `GET /api/v1/meta-ads/leads/` | `IsAuthenticated` + `meta_ads` |
| Historical sync (auto-promotes) | `POST /api/v1/meta-ads/bulk-pull/` → 202 | `IsAuthenticated` + `meta_ads` |
| Manual promote re-trigger | `POST /api/v1/meta-ads/promote/` `{batch_size?}` → 202 | `IsAuthenticated` + `meta_ads` |
| Resolve/refresh page token | `POST /api/v1/meta-ads/resolve-token/` `{page_id?}` | `HasSettingsPermission` + `meta_ads` |
| Lead detail Q&A | `GET /api/v1/crm/leads/{id}/` → `meta_qa` | (CRM lead RBAC) |

### Settings endpoint contract
`GET` returns the settings with **secrets masked** (`meta_app_secret`,
`system_user_access_token`, `page_access_token` → `"••••••••"`). To set a secret,
`PATCH` its **write-only plaintext** counterpart — `meta_app_secret_plaintext`,
`system_user_access_token_plaintext`, `page_access_token_plaintext` — which the
backend Fernet-encrypts on save. `organization`, `page_token_refreshed_at`, and
the encrypted columns are read-only. `GET` **auto-creates** an inactive stub row
if none exists (so the settings page always loads).

### Webhook behavior (ops-relevant)
- **GET** = verification handshake: echoes `hub.challenge` iff `hub.verify_token`
  matches an **active** integration; else 403.
- **POST** = ingestion: looks up settings by `page_id` (Redis-cached), verifies
  HMAC with the decrypted app secret (403 on mismatch), then enqueues one
  `process_meta_lead_task` per `leadgen` change. It returns **200 for every
  benign case** (non-`page` object, no entries, unknown `page_id`) **on purpose**
  — a non-200 makes Meta retry. So "webhook returns 200 but no lead appears"
  almost always means *no settings for that page_id* (check the logs), not a code
  error.

---

## 8. Token architecture (dual-token)

- **System User (SU) token** — permanent, Fernet-encrypted, the primary auth for
  **lead-level** Graph calls (`get_lead`).
- **Page access token** — auto-resolved from the SU token via `GET /me/accounts`,
  used for **page-level** calls. Refresh it with
  `POST /api/v1/meta-ads/resolve-token/` (picks the requested/existing page, or
  the first page; updates `page_id` + token, busts the settings cache).
- `refresh_page_token_task` exists to refresh all active orgs' page tokens, **but
  it is NOT registered in `CELERY_BEAT_SCHEDULE`** — page-token refresh is
  currently **manual** via `resolve-token/`. See §10.

---

## 9. Backfill (rows staged before the Q&A feature)

Old `MetaAdsLead` rows have `qa=[]` but their `raw_payload` preserves the original
ordered `field_data` array. Rebuild:

```
manage.py backfill_meta_qa [--organization-id <uuid>] [--dry-run] [--batch-size 500]
```

Fetches each distinct form's questions once (TTL cache), joins per row, batched
`bulk_update`. Rows with no raw field_data are skipped; already-promoted CRM
leads' `custom_fields` blobs are untouched — their `meta_qa` starts working as
soon as the staging row's `qa` is backfilled (the lead detail reads the staging
row live via the `promoted_lead` reverse FK).

---

## 10. Known gaps (product / ops)

1. **No admin question→custom-field mapping** — answers are display-only; mapping
   a form question to a filterable `CustomFieldDefinition` is a future feature
   (out of scope this iteration).
2. **`refresh_page_token_task` is not beat-scheduled** — page tokens are refreshed
   only when someone calls `resolve-token/`. Add a beat entry if unattended
   long-lived orgs are expected (the SU token is permanent, so this only affects
   the derived page token).
3. Rulebook §15.4's **Conversion-API status push-back** (CRM status → Meta) is
   unimplemented (tracked in docs/audit).
