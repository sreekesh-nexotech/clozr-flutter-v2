# Admin Operations (PMO) Dashboard API

Backs the **Overview → Dashboard → Operations** tab: the KPI card row (Active Projects /
Projects Overdue / Tasks Overdue / Avg Project Cycle / Avg Task Cycle), Project Status
donut, Overdue Tasks, Active Projects table, and Employee Performance.

**Base path:** `/api/v1/crm/dashboard-pmo/`
**Code:** views `crm/views/dashboard/admin_operations_dashboard.py`; services
`crm/services/dashboard/admin_operations_dashboard.py`.

**Auth / access:** `Authorization: Bearer <JWT>`. Gated by `HasDashboardPermission` —
the caller must be **`is_staff`/superuser OR hold the `dashboard` module permission
(`view_dashboard`)**. Regular users get **403** (admin-only, same gate as the Admin and
CRM tabs).

**Method:** all **GET**. **Caching:** version-keyed, 1–2 min per endpoint. Money is a
**2-dp string** (`"4200000.00"`); the FE formats to `₹42.0L` / `₹1.29Cr`.

---

## Common query params

| Param | Values | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `scope` | `own`, `team`, `admin` | `own` | Whose data. `admin` (org-wide) requires an org-admin role → else 403. The Operations tab calls with `scope=admin`. |
| `team_id` | UUID | — | **Filter-bar Team dropdown.** Narrows every widget to that team's members. Requires access (`can_access_team`) → else 403; bad UUID → 400. Empty team → no rows. |
| `user_id` | UUID | — | **Filter-bar Member dropdown.** Narrows to a single member. Wins over `team_id`. Requires access (`can_access_user_kpis`) → else 403. |
| `period` | `week`, `month`, `year`, `this_month`, `last_month`, `this_quarter`, `last_quarter`, `ytd`, `all_time`, `last_30_days`, `last_90_days`, `custom` | `month` | Trend window (KPIs). |
| `from`, `to` | `YYYY-MM-DD` | — | Only for `period=custom` (the "Custom range" option). |

`team_id`/`user_id` apply to **all** widget endpoints (kpis, project-status, overdue-tasks,
active-projects, employee-performance). Omit both to fall back to `scope`.

### Filter-bar dropdown feeds
- **Team dropdown** options: `GET /api/v1/crm/dashboard-new/teams/` → `{has_teams, items:[{label, value}]}` (value is the `team_id`, or `"all"`/`"individual"`).
- **Member dropdown** options: `GET /api/v1/crm/dashboard-new/users/?module=pmo[&team_id=<uuid>]` → `{users:[{user_id, name, email}]}`.
- **Period / Custom range**: the `period` values above; "Custom range" → `period=custom&from=&to=`.

Invalid params → **400** `{"errors": {"<field>": "..."}}`.

---

## 1. KPI cards — `GET /dashboard-pmo/kpis/`

The five cards: **Active Projects, Projects Overdue, Tasks Overdue, Avg Project Cycle,
Avg Task Cycle.** Counts are **live snapshots** ("in delivery right now"); each `trend_pct`
compares projects/tasks created this period vs last.

```jsonc
{
  "active_projects":   { "count": 6, "trend_pct": 2.3 },              // live: open, non-archived
  "projects_overdue":  { "count": 3, "total": 11, "trend_pct": -2.0 },// the "3 / 11" ratio
  "tasks_overdue":     { "count": 7, "trend_pct": -8.4 },             // across all projects
  "avg_project_cycle": { "days": 48.0, "trend_pct": 2.4 },            // start→handover
  "avg_task_cycle":    { "days": 3.2, "trend_pct": -8.4 }             // median completion
}
```
- **`projects_overdue`** now carries **`total`** = all live active projects (the "11"
  denominator); `count` = overdue-now (the "3").
- `count` values are live snapshots (not period-scoped); `trend_pct` is the period-over-
  period created delta (a directional signal for the chip).

---

## 2. Project Status — `GET /dashboard-pmo/project-status/`

The Project Status donut. Returns one row **per org-configured `ProjectStatus`** (all
active statuses, zero-filled, position-ordered) + a total.

```jsonc
{
  "total": 14,
  "statuses": [
    { "status_id": "<uuid>", "name": "Complete", "color": "#…", "is_closed": true,  "count": 4 },
    { "status_id": "<uuid>", "name": "On track", "color": "#…", "is_closed": false, "count": 5 },
    { "status_id": "<uuid>", "name": "At risk",  "color": "#…", "is_closed": false, "count": 2 },
    { "status_id": "<uuid>", "name": "Overdue",  "color": "#…", "is_closed": false, "count": 3 }
  ]
}
```
> The donut's segment labels/colors come from the org's own statuses (`name`/`color`).
> There is no fixed Complete/On-track/At-risk/Overdue enum server-side — map by `name`
> (and `is_closed` for terminal). `total` = sum of counts.

---

## 3. Overdue Tasks — `GET /dashboard-pmo/overdue-tasks/`

The "Overdue Tasks" list (top 5). Snapshot of incomplete project tasks past their
`exp_end_date`.

Extra param: **`sort`** — the ₹ Value / Days toggle:
- `days` (default) → most overdue first (`exp_end_date` asc)
- `value` → highest project ₹ value first

```jsonc
{
  "tasks": [
    { "task_id": "<uuid>", "title": "Install false ceiling grid",
      "exp_end_date": "2026-06-13", "days_overdue": 18,
      "assigned_to": { "id": "<uuid>", "name": "Manoj Varma" },   // owner
      "customer":    { "id": "<uuid>", "name": "Kalyan Silks" },  // ← added
      "project":     { "id": "<uuid>", "name": "…Showroom Fit-out", "value": "4200000.00" } }  // ₹42.0L
  ]
}
```
UI row: title, `customer.name · assigned_to.name`, `project.value` (₹), `days_overdue`.
`customer` is `null` if the project has none. `value` is the **project's**
`total_sales_amount` (tasks have no own value).

---

## 4. Active Projects — `GET /dashboard-pmo/active-projects/`

The Active Projects table. **Paginated** (`count`/`next`/`results`, page size 25).

Extra param: **`status`** — the All active / At risk / Overdue filter tabs:
- `all` (default) — all active (open) projects
- `risk` — ends within 7 days AND `percent_complete < 60`
- `overdue` — `expected_end_date < today`

```jsonc
{
  "count": 14, "next": "…?page=2", "previous": null,
  "results": [
    { "project_id": "<uuid>", "name": "Kalyan Silks — Showroom Fit-out",
      "manager": { "id": "<uuid>", "name": "Manoj Varma" },        // owner
      "status":  { "id": "<uuid>", "name": "Overdue", "color": "#…" },
      "expected_start_date": "2026-04-02", "expected_end_date": "2026-06-13",  // project period
      "progress_pct": 85,
      "days_remaining": -5,        // negative when past due
      "value": "4200000.00",       // ₹42.0L
      "health": "delayed" }        // delayed | at_risk | on_track
  ]
}
```
UI mapping: Project Name=`name`, Owner=`manager.name`, Status=`status.name` (+`health`),
Project Period=`expected_start_date`→`expected_end_date`, Progress=`progress_pct`, Days
Remaining=`days_remaining`, ₹ Value=`value`.

---

## 5. Employee Performance — `GET /dashboard-pmo/employee-performance/`

The Employee Performance table ("Delivery workload across the team"). **Paginated**
(page size 25). When `?scope=` is omitted it auto-resolves visible users (staff → all;
manager → self + subordinates; else self).

```jsonc
{
  "count": 5, "next": null, "previous": null,
  "results": [
    { "user_id": "<uuid>", "name": "Manoj Varma", "email": "…",
      "active_projects": 2,          // managed, open, not archived
      "open_tasks": 9,               // assigned, not completed
      "avg_task_cycle_days": 2.4,    // "Avg. Task Cycle"
      "tasks_overdue": 3,
      "last_active_at": "2026-07-29T…Z" }  // MAX(updated_at) over projects + tasks
  ]
}
```

---

## Other PMO endpoints (same tab, admin-gated)

Behind the same route group / gate, backing other Operations surface elements:

| Route | Returns |
| :--- | :--- |
| `GET /dashboard-pmo/tasks/` | paginated task list (`?sort=priority\|due`) |
| `GET /dashboard-pmo/top-tasks-needing-attention/` | top tasks by priority/overdue |
| `GET /dashboard-pmo/tasks-completed-grid/` | completed-tasks grid over the period |
| `GET /dashboard-pmo/schedule/` | schedule view of project tasks |

---

## Error responses

| Status | When |
| :--- | :--- |
| **400** | invalid `scope`/`period`/`from`/`to`/`status`/`sort` — `{"errors": {...}}`. |
| **403** | not `is_staff` and no `view_dashboard`; or `scope=admin` without an admin role. |
| **401** | unauthenticated. |

## Quick reference

| # | Widget | Endpoint | Key params |
| :-- | :--- | :--- | :--- |
| 1 | KPI cards | `kpis/` | scope, period |
| 2 | Project Status donut | `project-status/` | scope, period |
| 3 | Overdue Tasks | `overdue-tasks/` | **`sort`** (days/value), scope |
| 4 | Active Projects | `active-projects/` | **`status`** (all/risk/overdue), page |
| 5 | Employee Performance | `employee-performance/` | scope, page |
