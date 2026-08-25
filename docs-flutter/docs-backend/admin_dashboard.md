# Admin Dashboard API

Backs the **Overview → Dashboard → Admin** tab: the KPI card row, Total receivables,
Top 5 outstanding, Top customers, Pipeline snapshot, Revenue trend, Critical overdue
projects, and Stuck items. Nine read-only endpoints, one per widget (+ two dropdown
feeds).

**Base path:** `/api/v1/crm/dashboard-new/`
**Code:** views `crm/views/dashboard/admin_dashboard.py`, services
`crm/services/dashboard/admin_dashboard.py`.

**Auth / access:** `Authorization: Bearer <JWT>`. Gated by `HasDashboardPermission`:
the caller must be **`is_staff`/superuser OR hold the `dashboard` module permission
(`view_dashboard`)**. Anyone else → **403**. (The per-user CRM/PMO/Helpdesk dashboards
under `dashboard-crm/*`, `dashboard-pmo/*`, `dashboard-issue/*` are separate and open
to all authenticated users — this doc covers only the Admin tab.)

**Method:** all **GET**. **Caching:** server-side, version-keyed, 2–5 min per
endpoint (invalidated on writes to the underlying models). All money is a **2-dp
string** (e.g. `"18400.00"`); the frontend formats to `₹18.4L` / `₹1.05cr`.

---

## Common query params

Every data endpoint (1–7) accepts these; the two dropdown feeds (8–9) do not.

| Param | Values | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `scope` | `own`, `team`, `admin` | `own` | Whose data. `own` = caller's owned/assigned records; `team` = caller's team subtree; `admin` = whole org. **`admin` requires an org-admin role** → else **403** `"Admin scope requires an Admin role."` The Admin dashboard normally calls with `scope=admin`. |
| `period` | `week`, `month` (=`this_month`), `year`, `this_month`, `last_month`, `this_quarter`, `last_quarter`, `ytd`, `all_time`, `last_30_days`, `last_90_days`, `custom` | `month` | Trend/time window. Matches the "Period: This month" selector. |
| `from`, `to` | `YYYY-MM-DD` | — | **Only for `period=custom`.** Span capped at `MAX_CUSTOM_RANGE_DAYS`; over that → 400. |

Invalid `scope`/`period`/`from`/`to` → **400** with `{"errors": {"<field>": "..."}}`.

> **Note on `period`:** the KPI trends and Revenue trend use it directly. Total
> receivables, Top customers, Critical overdue projects and Stuck items accept
> `period` for API consistency but their windows are fixed (aging buckets / "stuck ≥3
> days" / "overdue as of today") — `period` there only affects `scope` narrowing, not
> the buckets.

---

## 1. KPI cards — `GET /dashboard-new/customer-kpis/`

The five cards across the top: **Sales Pipeline, Payments collected, Overdue
receivables, Open tickets, Quote to cash.** Each `trend_pct` is current period vs the
previous same-length period (drives the ↑12.3% / ↓8% chips).

```jsonc
{
  "sales_pipeline":      { "amount": "1840000.00", "trend_pct": 12.3 },   // open-lead product value, all stages
  "payments_collected":  { "collected": "940000.00", "expected": "2220000.00", "trend_pct": 12.3 },
  "overdue_receivables": { "amount": "440000.00", "customer_count": 23, "trend_pct": 14.0 },  // "Across 23 customers"
  "open_tickets":        { "count": 147, "trend_pct": -8.0 },             // across all priorities
  "quote_to_cash_days":  { "median_days": 42 }                            // median, last period
}
```

---

## 2. Total receivables — `GET /dashboard-new/total-receivables/`

The "What's overdue today + what's coming in" panel. `total_amount` = overdue +
upcoming. **Upcoming buckets are cumulative** (`next_90` already includes `next_30` ⊇
`next_7`); overdue buckets are disjoint aging bands. Single aggregate query.

```jsonc
{
  "total_amount": "10500000.00",              // ₹1.05 cr
  "overdue": {
    "total_amount": "5440000.00",             // ₹54.40 L
    "0_30":    { "amount": "1820000.00", "count": 12 },
    "31_60":   { "amount": "1240000.00", "count": 8 },
    "61_90":   { "amount": "1360000.00", "count": 6 },
    "90_plus": { "amount": "1020000.00", "count": 4 }
  },
  "upcoming": {
    "total_amount": "5060000.00",             // ₹50.60 L (== next_90)
    "today":   { "amount": "640000.00",  "count": 3 },
    "next_7":  { "amount": "1210000.00", "count": 5 },
    "next_30": { "amount": "1850000.00", "count": 9 },   // cumulative
    "next_90": { "amount": "1360000.00", "count": 4 }    // cumulative → the upcoming total
  }
}
```
Bucketing: overdue by `today − due_date` (status `overdue`); upcoming by
`due_date − today` (status `pending`) with `today = due_date`, then `≤ today+7 / +30 /
+90`.

---

## 3. Top customers — `GET /dashboard-new/top-customers/`

Feeds **both** "Top 5 outstanding" (left) and "Top customers" (right, ₹ Value tab).
Two independent top-5 lists.

```jsonc
{
  "top_outstanding": [        // ranked by overdue receivable desc
    { "customer_id": "<uuid>", "name": "Kalyan Silks",
      "outstanding_amount": "1220000.00", "oldest_overdue_days": 112 },  // the "112d · ₹12.2L" row
    ...
  ],
  "top_by_value": [           // ranked by Sum(Payment.total_amount) desc (non-paid)
    { "customer_id": "<uuid>", "name": "Nirapara Supermarket",
      "total_value": "22200000.00",         // ₹2.22Cr — the "₹ Value" tab
      "outstanding_amount": "139998.67" },  // current overdue receivable — the "Dues" tab
    ...
  ]
}
```
UI notes:
- **Top 5 outstanding** (left card) reads `top_outstanding`; `oldest_overdue_days`
  renders as the red `112d` badge, bar width = `outstanding_amount` relative to the
  top row.
- **Top customers** (right card) reads `top_by_value`; the **₹ Value / Dues** toggle
  switches between `total_value` and `outstanding_amount` — both are on every row, no
  refetch. (`outstanding_amount` is the customer's current overdue receivable, `0.00`
  when they have none.)

---

## 4. Pipeline snapshot — `GET /dashboard-new/pipeline-snapshot/`

The lead-stage bar chart ("Lead stages across the organisation"). Lead-only slice of
the shared pipeline data.

```jsonc
{
  "crm": {
    "stages": [
      { "lead_status_id": "<uuid>", "name": "New",         "color": "#…", "position": 1, "count": 12, "value": "101785.00" },
      { "lead_status_id": "<uuid>", "name": "Qualified",   "color": "#…", "position": 2, "count": 30, "value": "165683.00" },
      { "lead_status_id": "<uuid>", "name": "Quote",       "color": "#…", "position": 3, "count": 4,  "value": "61085.00"  },
      { "lead_status_id": "<uuid>", "name": "Negotiation", "color": "#…", "position": 4, "count": 18, "value": "133588.00" },
      { "lead_status_id": "<uuid>", "name": "Won",         "color": "#…", "position": 5, "count": 40, "value": "21998.00"  },
      { "lead_status_id": "<uuid>", "name": "Lost",        "color": "#…", "position": 6, "count": 3,  "value": "0.00"      }
    ],
    "total": 107
  }
}
```
Every active lead status is returned (count `0` if empty), ordered by `position`.

- **`count`** — leads in that status.
- **`value`** — open-lead product value in that status (₹, 2-dp string). "Open" =
  not archived, not converted, not lost — same definition as the KPI "Sales Pipeline"
  card, so the per-stage values are consistent with that total.

The card's **₹ Value / Count** toggle switches which field the bars use — both are in
the payload, no refetch.

---

## 5. Revenue trend — `GET /dashboard-new/revenue-trend/`

The "Revenue received vs expected" area chart (green = Received, orange = Expected).
Bucketing: `week`/`month` → daily, `year` → monthly.

```jsonc
{
  "buckets": [
    { "label": "2026-01-01", "collected": "0.00",    "expected": "120000.00", "gap": "120000.00" },
    { "label": "2026-01-02", "collected": "50000.00","expected": "60000.00",  "gap": "10000.00" },
    ...
  ]
  // year → label is "Jan 2026", "Feb 2026", …; gap = expected − collected
}
```
Buckets are dense (every day/month in the window is present, zero-filled).

---

## 6. Critical overdue projects — `GET /dashboard-new/critical-overdue-projects/`

The "Critical overdue projects" table (Project / Owner / Overdue / ₹ Value). Active
projects past `expected_end_date`, ranked by `total_sales_amount` desc.

Extra param: `limit` (int 1–50, default 10) — over-range → 400.

```jsonc
{
  "projects": [
    { "project_id": "<uuid>", "name": "ERP Implementation",
      "total_sales_amount": "1240000.00",  // ₹12.4L
      "days_overdue": 8,                    // the red "8" badge
      "completion_pct": 35 },
    ...
  ]
}
```
The table shows Owner separately — resolve it from the project detail if the row needs
it (not included here to keep the widget query lean). `days_overdue` = `today −
expected_end_date`.

---

## 7. Stuck items — `GET /dashboard-new/stuck-items/`

The "Stuck items" panel with its three tabs. **Required** param `kind` selects the
tab; call once per tab.

| Tab in UI | `kind` |
| :--- | :--- |
| Project not created | `leads` |
| Overdue followups | `followups` |
| Overdue payments | `payments` |
| (Stuck tasks) | `tasks` |

"Stuck" = `updated_at` older than **3 days**. Returns top 5, ranked by a
value×staleness score.

```jsonc
{
  "kind": "payments",
  "items": [
    { "id": "<uuid>", "title": "Apex Manufacturing",
      "value": "500000.00",   // ₹5.4L  (for followups/leads: lead value; tasks: priority name)
      "stuck_days": 12,        // the red "12 days"
      "rank_score": 6000000.0 }
  ]
}
```
Per-kind `title`/`value` semantics:
- `leads` → `title`=lead name, `value`=lead product value (₹).
- `followups`/`tasks` → `title`=task title, `value`=priority **name** (string, e.g.
  `"High"`), plus the person is on the task; the UI shows the sub-owner + a date.
- `payments` → `title`=customer (or quotation no.), `value`=amount expected (₹).

Missing/invalid `kind` → 400 (`leads`, `tasks`, `followups`, `payments`).

---

## 8. Teams dropdown — `GET /dashboard-new/teams/`

Feeds the first dashboard filter dropdown. No params.

```jsonc
{
  "has_teams": true,
  "items": [
    { "label": "All team",   "value": "all" },
    { "label": "Sales North","value": "<team_id uuid>" },
    { "label": "Individual", "value": "individual" }
  ]
}
```
When `has_teams=false`, `items` has only "All team" + "Individual" (grey out the
second dropdown).

## 9. Users dropdown — `GET /dashboard-new/users/`

Feeds the second dropdown (users who can read a module). **Required** `module`;
optional `team_id`.

| Param | Values | Meaning |
| :--- | :--- | :--- |
| `module` | `crm`, `pmo`, `issue` | Which dashboard surface (crm→`lead`, pmo→`project`, issue→`issue` read perm). Required → 400 if missing/invalid. |
| `team_id` | UUID | Narrow to members of that team. Bad UUID → 400. |

```jsonc
{
  "users": [
    { "user_id": "<uuid>", "name": "Rahul Sharma", "email": "rahul@acme.com" },
    ...
  ]
}
```

---

## Error responses

| Status | When |
| :--- | :--- |
| **400** | invalid `scope`/`period`/`from`/`to`/`limit`/`kind`/`module`/`team_id` — body `{"errors": {"<field>": "..."}}`. |
| **403** | not `is_staff` and no `view_dashboard` perm → `{"detail": "You do not have permission to view the admin dashboard."}`. Also `scope=admin` without an admin role → `"Admin scope requires an Admin role."` |
| **401** | unauthenticated. |

## Quick reference

| # | Widget | Endpoint | Key params |
| :-- | :--- | :--- | :--- |
| 1 | KPI cards | `customer-kpis/` | scope, period |
| 2 | Total receivables | `total-receivables/` | scope |
| 3 | Top outstanding + Top customers | `top-customers/` | scope |
| 4 | Pipeline snapshot | `pipeline-snapshot/` | scope, period |
| 5 | Revenue trend | `revenue-trend/` | scope, period |
| 6 | Critical overdue projects | `critical-overdue-projects/` | scope, `limit` |
| 7 | Stuck items | `stuck-items/` | **`kind`** (req), scope |
| 8 | Teams dropdown | `teams/` | — |
| 9 | Users dropdown | `users/` | **`module`** (req), `team_id` |
