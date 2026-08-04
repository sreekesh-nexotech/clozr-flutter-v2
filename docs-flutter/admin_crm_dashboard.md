# Admin CRM Dashboard API

Backs the **Overview → Dashboard → CRM** tab: the KPI card row (New leads / Win rate /
First to response / Quote acceptance / Quote to cash), Lead funnel, Lead inflow trend,
Attention needed, Lead sources, Stuck items, and Employee performance — plus the
team/member drill-downs.

**Base path:** `/api/v1/crm/dashboard-crm/`
**Code:** views `crm/views/dashboard/admin_crm_dashboard.py` (+ team views in
`crm/views/dashboard/team_performance.py`); services
`crm/services/dashboard/admin_crm_dashboard.py` (+ `team_performance.py`).

**Auth / access:** `Authorization: Bearer <JWT>`. Gated by `HasDashboardPermission` —
the caller must be **`is_staff`/superuser OR hold the `dashboard` module permission
(`view_dashboard`)**. Regular CRM users get **403** (the CRM dashboard tab is
admin-only, same gate as the Admin `dashboard-new/*` tab).

**Method:** all **GET**. **Caching:** version-keyed, 2–5 min per endpoint. Money is a
**2-dp string** (`"464000.00"`); the FE formats to `₹4.64Cr` etc.

---

## Common query params

| Param | Values | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `scope` | `own`, `team`, `admin` | `own` | Whose data. `admin` (org-wide) requires an org-admin role → else 403. The Admin CRM tab calls with `scope=admin`. |
| `team_id` | UUID | — | **Filter-bar Team dropdown.** Narrows every widget to that team's members. Requires access to the team (`can_access_team`) → else 403; bad UUID → 400. Empty team → no rows. |
| `user_id` | UUID | — | **Filter-bar Member dropdown.** Narrows to a single member. Wins over `team_id` if both are sent. Requires access (`can_access_user_kpis`) → else 403. |
| `period` | `week`, `month`, `year`, `this_month`, `last_month`, `this_quarter`, `last_quarter`, `ytd`, `all_time`, `last_30_days`, `last_90_days`, `custom` | `month` | Trend window (KPIs / missed). |
| `from`, `to` | `YYYY-MM-DD` | — | Only for `period=custom` (the "Custom range" option). |

`team_id`/`user_id` apply to **all** widget endpoints (kpis, lead-funnel, lead-inflow-trend,
missed, lead-sources, stuck-items, employee-performance). Omit both to fall back to `scope`.

Invalid params → **400** `{"errors": {"<field>": "..."}}`.

### Filter-bar dropdown feeds
- **Team dropdown** options: `GET /api/v1/crm/dashboard-new/teams/` → `{has_teams, items:[{label, value}]}` (value is the `team_id`, or `"all"`/`"individual"`).
- **Member dropdown** options: `GET /api/v1/crm/dashboard-new/users/?module=crm[&team_id=<uuid>]` → `{users:[{user_id, name, email}]}` (pass `team_id` to list only that team's members).
- **Period / Custom range**: the `period` values above; "Custom range" → `period=custom&from=&to=`.

---

## 1. KPI cards — `GET /dashboard-crm/kpis/`

The five cards: **New leads, Win rate, First to response, Quote acceptance, Quote to
cash.** Each carries a `trend_pct` (current vs previous same-length period).

```jsonc
{
  "new_leads":          { "count": 142, "trend_pct": 18.3 },
  "win_rate":           { "pct": 23.0, "trend_pct": 4.3 },      // won/qualified ratio; trend in pct-points
  "first_response":     { "median_minutes": 14, "trend_pct": 3.0 },  // "First to response"
  "quote_acceptance":   { "pct": 52.0, "trend_pct": 5.0 },     // conversion rate
  "quote_to_cash_days": { "median_days": 42, "trend_pct": -3.0 }  // ← trend_pct now included
}
```
> `quote_to_cash_days.trend_pct` was recently added (current-vs-previous median), so the
> card's trend chip has data — no longer count/median-only.

---

## 2. Lead funnel — `GET /dashboard-crm/lead-funnel/`

The lead-stage bar chart ("Lead stages across the team"). CRM slice only.

```jsonc
{
  "crm": {
    "stages": [
      { "lead_status_id": "<uuid>", "name": "New",       "color": "#…", "position": 1, "count": 4 },
      { "lead_status_id": "<uuid>", "name": "Qualified", "color": "#…", "position": 2, "count": 7 },
      ...
    ],
    "total": 36
  }
}
```
Stages are the org's configured lead statuses (position-ordered), count `0` when empty.

---

## 3. Lead inflow trend — `GET /dashboard-crm/lead-inflow-trend/`

The "Won vs Created" area chart. **Always 12 buckets** (Jan–Dec of the current
calendar year); `period`/`from`/`to` are ignored here.

```jsonc
{
  "buckets": [
    { "label": "Jan 2026", "new_leads": 8, "won_leads": 3 },   // new_leads = Created, won_leads = Won
    { "label": "Feb 2026", "new_leads": 12, "won_leads": 5 },
    ...  // 12 entries
  ]
}
```

---

## 4. Attention needed — `GET /dashboard-crm/missed/`

The four "Attention needed" cards. Single endpoint, all four metrics with a
`trend_pct` delta.

```jsonc
{
  "payments_missed":  { "count": 12, "trend_pct": 3.0,  "direction": "worsening" },
  "followups_missed": { "count": 28, "trend_pct": 0.0,  "direction": "steady" },
  "tasks_missed":     { "count": 19, "trend_pct": -5.0, "direction": "improving" },
  "lost_after_quote": { "count": 14, "trend_pct": 3.0,  "direction": "worsening" }
}
```
> **`direction`** is the ready-to-render label: `worsening` / `steady` / `improving`.
> All four metrics are bad-when-up (missed / lost), so a higher count than the previous
> period is `worsening`, lower is `improving`, equal is `steady`. Render it directly —
> no need to interpret `trend_pct` client-side. (`trend_pct` remains for the % delta.)

---

## 5. Lead sources — `GET /dashboard-crm/lead-sources/`

The Lead sources table (Source / Leads / Won / Win% / Pipeline ₹). Every active source
returned (zero-filled).

```jsonc
{
  "sources": [
    { "id": "<uuid>", "name": "Website", "total_leads": 8, "won_leads": 3,
      "lost_leads": 2, "win_pct": 38.0,
      "won_amount": "46400000.00",       // realized: Sum(active Payment.total_amount) — ₹4.64Cr
      "pipeline_amount": "23593.00" },   // open pipeline: open-lead product value for this source
    ...
  ]
}
```
UI mapping: Leads=`total_leads`, Won=`won_leads`, Win%=`win_pct`. The **Pipeline (₹)**
column should use **`pipeline_amount`** (open-lead product value — not converted / lost /
archived, same definition as the KPI "Sales Pipeline" card). `won_amount` is the
*realized* won value, kept for the Leads/₹ Value toggle if you want won-value instead.

> Both fields are on every row now: `pipeline_amount` = open pipeline, `won_amount` =
> won/realized. Pick per the column's intent.

---

## 6. Stuck items — `GET /dashboard-crm/stuck-items/`

The Stuck items panel with its four tabs. **Required** `kind` selects the tab.

| UI tab | `kind` | What it lists |
| :--- | :--- | :--- |
| Stale Leads | `leads` | open leads (with products) untouched 3+ days |
| Quotes | `quotes` | non-converted quotations untouched 3+ days |
| Payments | `payments` | pending payment records untouched 3+ days |
| Won-NC | `won_nc` | leads marked **Won** but `is_converted=false`, untouched 3+ days |

"Stuck" = `updated_at` older than 3 days. Top 5, ranked by value × staleness.

```jsonc
{
  "kind": "quotes",
  "items": [
    { "id": "<uuid>", "title": "Workafella Coworking",  // customer (or quote no. / lead name)
      "owner": "Deepak Raj",       // ← owner display name (added for the CRM widget)
      "value": "18400000.00",      // ₹1.84Cr (quote total / lead value / payment amount)
      "stuck_days": 8,             // "8 days idle"
      "rank_score": 147200000.0 }
  ]
}
```
`owner` is present on **every** kind now. Per-kind `title`/`value`:
- `leads` / `won_nc` → title = lead name, value = lead product value (₹), owner = lead owner.
- `quotes` → title = customer/quote-no, value = quote `total_amount` (₹), owner = quote's lead owner (fallback creator).
- `payments` → title = customer/quote-no, value = amount expected (₹), owner = the quotation's lead owner.

Missing/invalid `kind` → 400 (one of `leads, payments, quotes, won_nc`).

---

## 7. Employee performance — `GET /dashboard-crm/employee-performance/`

The Employee performance table (Employee / Active / Won / ₹ Closed / First Response /
Last Active). **Paginated** (`count`/`next`/`results`, page size 25).

```jsonc
{
  "count": 12, "next": null, "previous": null,
  "results": [
    { "user_id": "<uuid>", "name": "Anjana M.", "email": "…",
      "open_leads": 1,                       // "Active"
      "won_leads": 4,                        // "Won"
      "closed_amount": "19800000.00",        // "₹ Closed" (₹1.98Cr)
      "first_response_median_minutes": 21,   // "First Response"
      "last_active_at": "2026-07-29T…Z" }    // "Last Active"
  ]
}
```

---

## 8. Team / member drill-downs (dashboard-crm/*, admin-gated)

Extra endpoints behind the same tab, with an additional per-team access guard on top of
the dashboard gate:

| Route | Returns | Access |
| :--- | :--- | :--- |
| `GET /dashboard-crm/teams-performance/` | teams + members structural overview | admin **or** team manager |
| `GET /dashboard-crm/team-kpis/?team_id=` | CRM+PMO+Issue KPIs aggregated over a team | `can_access_team` |
| `GET /dashboard-crm/user-kpis/?user_id=` | one user's KPIs | `can_access_user_kpis` |
| `GET /dashboard-crm/member-performance/?user_id=` | one member's performance detail | `can_access_user_kpis` |
| `GET /dashboard-crm/my-recent-wins/` | caller's recent won deals | self |

---

## Error responses

| Status | When |
| :--- | :--- |
| **400** | invalid `scope`/`period`/`from`/`to`/`kind` — `{"errors": {...}}`. |
| **403** | not `is_staff` and no `view_dashboard` → admin dashboard message; or `scope=admin` without an admin role; or team endpoints without team access. |
| **401** | unauthenticated. |

## Quick reference

| # | Widget | Endpoint | Key params |
| :-- | :--- | :--- | :--- |
| 1 | KPI cards | `kpis/` | scope, period |
| 2 | Lead funnel | `lead-funnel/` | scope, period |
| 3 | Lead inflow trend | `lead-inflow-trend/` | — (fixed calendar year) |
| 4 | Attention needed | `missed/` | scope, period |
| 5 | Lead sources | `lead-sources/` | scope, period |
| 6 | Stuck items | `stuck-items/` | **`kind`** (req: leads/quotes/payments/won_nc), scope |
| 7 | Employee performance | `employee-performance/` | scope, page |
