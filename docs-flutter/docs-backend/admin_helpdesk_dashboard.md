# Admin Helpdesk Dashboard API

Backs the **Overview → Dashboard → Helpdesk** tab: the KPI card row (Open Tickets /
SLA Breaches / Avg Resolution / First Response / Reopen Rate), Tickets by Category,
SLA Status & Priority Mix, Tickets Needing Attention, Ticket Flow Trend, and
Employee Performance.

**Base path:** `/api/v1/crm/dashboard-issue/`
**Code:** views `crm/views/dashboard/issue_dashboard.py`; services
`crm/services/dashboard/issue_dashboard.py`.
**Tests:** `crm/tests/test_issue_dashboard.py` (53).

**Auth / access:** `Authorization: Bearer <JWT>`.

> ⚠️ **This tab is NOT admin-gated, unlike the CRM and Operations dashboards.**
> `BaseDashboardView._check_permissions` only resolves the org — every
> authenticated user can call these endpoints. What varies is *whose data* they
> see, via `scope` (below). The `view_dashboard` permission is intended to pick
> which design the frontend renders (manager vs staff), **not** to gate access.
> Only `scope=admin` is privileged, and it 403s without an org-admin role.
> Contrast `dashboard-crm/*` and `dashboard-new/*`, which are `HasDashboardPermission`.

**Method:** all **GET**. **Caching:** version-keyed on the `issue` model, 60–300s
per endpoint — a ticket write invalidates it immediately.

**Ticket domain note:** the model is `Issue`, not "Ticket". `issue_id` is the id
everywhere; `TKT-0001` is the human-readable `reference`. See
[helpdesk.md](helpdesk.md) for the ticket resource itself.

---

## Common query params

| Param | Values | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `scope` | `own`, `team`, `admin` | `own` | Whose data. `admin` (org-wide) requires an org-admin role → else **403**. The Admin Helpdesk tab calls with `scope=admin`. |
| `period` | `week`, `month`, `year`, `this_month`, `last_month`, `this_quarter`, `last_quarter`, `ytd`, `all_time`, `last_30_days`, `last_90_days`, `custom` | `month` | The **Period** dropdown ("This month" in the screenshot). |
| `from`, `to` | `YYYY-MM-DD` | — | Only with `period=custom`. Sending them **without** `period=custom` is a 400; sending only one of the pair is a 400. |

Invalid params → **400** `{"errors": {"<field>": "..."}}`.

Two endpoints deviate and are called out in place: `ticket-flow-trend/` takes no
`period` (it takes a raw `from`/`to` pair), and `employee-performance/`
auto-resolves visibility when `scope` is omitted.

---

## Endpoint index

| # | Widget in the UI | Endpoint |
| :--- | :--- | :--- |
| 1 | The five KPI cards | `GET /dashboard-issue/kpis/` |
| 2 | *(no direct tile — status breakdown)* | `GET /dashboard-issue/tickets-by-status/` |
| 3 | **SLA Status & Priority Mix** (both donuts) | `GET /dashboard-issue/sla-priority-mix/` |
| 4 | Full attention list (paginated feed) | `GET /dashboard-issue/tickets-needing-attention/` |
| 5 | **Ticket Flow Trend** | `GET /dashboard-issue/ticket-flow-trend/` |
| 6 | **Employee Performance** table | `GET /dashboard-issue/employee-performance/` |
| 7 | Breached-SLA drill-down | `GET /dashboard-issue/tickets-crossed-sla/` |
| 8 | **Tickets Needing Attention** card (top 5) | `GET /dashboard-issue/top-tickets-needing-attention/` |
| 9 | Completed grid (priority × on-time) | `GET /dashboard-issue/tickets-completed-grid/` |
| 10 | **Tickets by Category** bar chart | `GET /dashboard-issue/tickets-by-category/` |

---

## 1. KPI cards — `GET /dashboard-issue/kpis/`

The five cards across the top. Each carries `trend_pct` — current period vs the
**previous period of the same length**, which is what the little ↓8% chip shows.

```jsonc
{
  "open_tickets":   { "count": 24,   "trend_pct": -8.0 },
  "sla_breaches":   { "count": 6,    "trend_pct": -3.3 },
  "avg_resolution": { "minutes": 252, "trend_pct": -2.3 },   // 4.2 hours
  "first_response": { "minutes": 8,   "trend_pct": -2.3 },
  "reopen_rate":    { "pct": 6.2,     "trend_pct": 8.4 }
}
```

Durations are **minutes** — the frontend formats `252` → `4.2 hours` and `8` →
`8 min`. `reopen_rate.pct` is already a percentage.

Two definitions worth knowing, because they are not what the labels suggest:

* **`open_tickets` is a point-in-time snapshot**, not a period count: tickets
  created before the period end that were still unresolved at that moment. That
  is why its trend compares two snapshots rather than two totals.
* **`first_response.minutes` is derived from `Issue.first_response_time`, which
  actually measures time-to-RESOLUTION**, not time to first reply (see
  [helpdesk.md §3](helpdesk.md#3--the-ticket-list-get-issues) — the field is
  misnamed at the model level and the dashboard inherits it). The true
  first-reply timestamp is `Issue.first_responded_at`, stamped by the first
  outbound reply, and it is **not** what this card reports. Treat the "8 min"
  figure as provisional until the model field is split.

---

## 2. Tickets by status — `GET /dashboard-issue/tickets-by-status/`

Per-`IssueStatus` counts for tickets **created in the period**. Every active
status is returned zero-filled, so the chart keeps a stable set of bars.

```jsonc
{
  "total": 25,
  "statuses": [
    { "status_id": "…", "name": "Open", "color": "#2563eb",
      "is_resolved": false, "is_on_hold": false, "count": 4 }
  ]
}
```

This is the **workflow lane** axis. For the "Tickets by Category" chart in the
screenshot you want endpoint 10 instead — a different axis entirely.

---

## 3. SLA status & priority mix — `GET /dashboard-issue/sla-priority-mix/`

Both donuts in one call, computed over **open** tickets in the period.

```jsonc
{
  "sla":      { "within_sla": 24, "at_risk": 5, "breached": 6 },
  "priority": { "low": 8, "medium": 15, "high": 8, "critical": 4 }
}
```

`at_risk` is a fixed **24-hour** band before the deadline — it is not
configurable here. (The ticket-list `summary/` endpoint has a tunable
`due_soon_minutes`; these two therefore do **not** reconcile, by design. See
[helpdesk.md §7](helpdesk.md#7--support-overview-get-issuessummary).)

The screenshot labels priorities *Urgent / High / Medium / Low*, but the model's
choices are **`Critical` / `High` / `Medium` / `Low`** — map `critical` → the
"Urgent" swatch.

---

## 4. Tickets needing attention — `GET /dashboard-issue/tickets-needing-attention/`

The full breached / at-risk / paused feed.

| Param | Default | Notes |
| :--- | :--- | :--- |
| `limit` | 20 | 1–100. Outside that range → 400. |

`period` is accepted and validated for API consistency but **does not filter** —
this is deliberately a "right now" snapshot.

```jsonc
{
  "tickets": [
    {
      "issue_id": "…",
      "title": "AC not cooling — 3rd floor",
      "priority": "Critical",
      "status": { "id": "…", "name": "On Hold", "color": "#7c3aed" },
      "assigned_to": { "id": "…", "name": "Fariz Ahmed" },
      "sla_status": "breached",          // breached | at_risk | within_sla
      "days_remaining": -2,              // negative = overdue; null when no deadline
      "sla_deadline": "2026-08-11T09:00:00Z"
    }
  ]
}
```

`status` and `assigned_to` are **nullable objects** — an un-triaged or
unassigned ticket returns `null` for either, not an empty object.

---

## 5. Ticket flow trend — `GET /dashboard-issue/ticket-flow-trend/`

The Opened-vs-Resolved area chart. **No `period` param** — this one takes a raw
date pair:

* Neither `from` nor `to` → 12 monthly buckets for the current calendar year
  (Jan…Dec, matching the screenshot's axis).
* Both supplied → one bucket per calendar month touching the range.
* Only one of the two → **400**. `from > to` → **400**.

```jsonc
{
  "buckets": [
    { "label": "Jan 2026", "opened": 18, "resolved": 15 },
    { "label": "Feb 2026", "opened": 22, "resolved": 20 }
  ]
}
```

Cached 300s — the longest of any endpoint here, since monthly buckets move slowly.

---

## 6. Employee performance — `GET /dashboard-issue/employee-performance/`

The table at the bottom. **Paginated, 25 per page** (`page`, `page_size`).

Scope resolution is special here. If `scope` is **omitted**, visibility is
auto-resolved from the caller: staff → everyone in the org; a manager → self +
transitive subordinates; anyone else → self only. An explicit `?scope=` still
wins. This is why the table "just works" for a manager without the frontend
computing a member list.

```jsonc
{
  "count": 5, "next": null, "previous": null,
  "results": [
    {
      "user_id": "…",
      "name": "Anjana Menon",
      "email": "anjana@…",
      "assigned_issues": 4,               // "Open Tickets" column
      "resolved_issues": 12,              // "Resolved"
      "avg_resolution_minutes": 240,      // "4.0h"
      "avg_first_response_minutes": 12,   // "12 min" — same caveat as the KPI card
      "sla_breaches": 0,                  // the pill; 0 renders green
      "last_active_at": "2026-08-13T09:12:00Z"   // "2 m ago"; null if never
    }
  ]
}
```

Row order follows the paginated user queryset, not a metric — sort client-side
if the design needs "worst SLA first".

`last_active_at` is the most recent `updated_at` across tickets the user is
**assigned to or raised**, so it reflects helpdesk activity only — not logins or
CRM work.

---

## 7. Tickets crossed SLA — `GET /dashboard-issue/tickets-crossed-sla/`

Paginated breached-ticket drill-down. **10 per page.**

| Param | Values | Default |
| :--- | :--- | :--- |
| `sort` | `value`, `days` | `value` |

```jsonc
{
  "count": 6, "next": "…", "previous": null,
  "results": [
    {
      "issue_id": "…",
      "display_number": "#2041",        // NOT the TKT- reference — see below
      "title": "AC not cooling — 3rd floor",
      "priority": "Critical",
      "assigned_to": { "id": "…", "name": "Fariz Ahmed" },
      "value": "464000.00",             // 2-dp string, as on the CRM dashboard
      "days_crossed": 2,
      "sla_deadline": "2026-08-11T09:00:00Z"
    }
  ]
}
```

Two things to get right here:

* **`display_number` is `#<integer pk>`, not the `TKT-` reference.** The ticket
  list and detail page show `reference` (`TKT-0001`); this endpoint shows the
  internal row id. They are different numbers for the same ticket. If the card
  must match the rest of the UI, fetch `reference` or treat this as opaque.
* **`sort=value` re-sorts the current page only.** The underlying queryset
  paginates stably by `sla_deadline` ascending, then each page is sorted by
  value descending in Python. So page 2 is *not* globally "the next most
  valuable" — it is the next page by deadline, internally sorted. `sort=days`
  has the same page-local character. Don't present it as a global ranking.

---

## 8. Top tickets needing attention — `GET /dashboard-issue/top-tickets-needing-attention/`

The **Tickets Needing Attention** card — a top-5 snapshot with value attached.
Takes `scope` only: no `period`, no `limit` (the limit is fixed at 5 server-side).

```jsonc
{
  "tickets": [
    {
      "issue_id": "…",
      "display_number": "#2041",       // integer pk, not the TKT- reference
      "title": "AC not cooling — 3rd floor",
      "priority": "Critical",
      "assigned_to": { "id": "…", "name": "Fariz Ahmed" },
      "sla_status": "breached",
      "days_remaining": -2,
      "value": "464000.00"
    }
  ]
}
```

Note this row shape differs from endpoint 4's: it **adds** `display_number` and
`value`, and **omits** the `status` block and `sla_deadline`. The screenshot's
`Overdue` / `Paused` / `2h left` chips come from `sla_status` + `days_remaining`,
not from a status name — so the card cannot show "On Hold" from this endpoint
alone.

Use this for the card; use endpoint 4 for the "View all tickets" screen.

---

## 9. Tickets completed grid — `GET /dashboard-issue/tickets-completed-grid/`

Resolved tickets bucketed by priority × on-time/late.

```jsonc
{
  "rows": [
    { "priority": "Critical", "before_due": 3, "after_due": 1 },
    { "priority": "High",     "before_due": 8, "after_due": 2 },
    { "priority": "Medium",   "before_due": 15, "after_due": 4 },
    { "priority": "Low",      "before_due": 8, "after_due": 0 }
  ]
}
```

All four priorities are always present, zero-filled, in severity order
(Critical → Low) — not alphabetical.

---

## 10. Tickets by category — `GET /dashboard-issue/tickets-by-category/`

The **Tickets by Category** bar chart (Complaint / Service Request / Question /
Feedback in the screenshot). Groups by **`IssueType`** — the ticket's category —
which is a different axis from endpoint 2's workflow status. A ticket has both.

```jsonc
{
  "total": 34,
  "uncategorized": 4,
  "categories": [
    { "issue_type_id": "…", "name": "Complaint",       "default_priority": "High",   "count": 9 },
    { "issue_type_id": "…", "name": "Feedback",        "default_priority": "Low",    "count": 4 },
    { "issue_type_id": "…", "name": "Question",        "default_priority": "Medium", "count": 7 },
    { "issue_type_id": "…", "name": "Service Request", "default_priority": "Medium", "count": 14 }
  ]
}
```

* Every category is returned **zero-filled** and ordered by `name`, so the bar
  set stays stable as tickets move between categories.
* **`issue_type` is nullable**, so untyped tickets are reported separately in
  `uncategorized` rather than dropped. `total` = sum of `categories[].count` +
  `uncategorized`. Render the uncategorised bucket (or state that you're
  omitting it) — silently charting only the named bars makes the total disagree
  with every other widget.
* Counts cover tickets **created in the period**, matching endpoint 2.

Category options for any filter UI come from
`GET /api/v1/crm/issue-types/` ([helpdesk.md §13](helpdesk.md#13--configuration-statuses--categories)).

---

## Notes for the frontend

* **Durations are minutes everywhere** (`avg_resolution`, `first_response`,
  `avg_resolution_minutes`, `avg_first_response_minutes`). Format client-side.
* **`trend_pct` is signed**: negative = down vs the previous period. For
  `open_tickets` and `sla_breaches`, down is *good* — the chip's colour is a
  product decision, not a backend one.
* **`scope=admin` 403s** for a non-admin. The Helpdesk tab itself is reachable
  by anyone, so handle that 403 by falling back to `scope=own` rather than
  showing an error page.
* **A user with no role assigned sees empty widgets, not an error** — the same
  deny-by-default described in [helpdesk.md §1](helpdesk.md#1--cross-cutting-rules).
  `is_staff`/superusers bypass it, so this will not reproduce on an admin login.
* **`period=custom` requires both `from` and `to`**; sending either without
  `period=custom` is a 400.
* **`first_response` is time-to-resolution, not first reply** (§1). Flagged in
  two places because it is the single most misleading number on this screen.

## Known gaps

1. **`first_response` measures the wrong thing** (see above). Fixing it means
   splitting `Issue.first_response_time`, which the list ordering and saved
   filters also read — a coordinated change, tracked in
   [helpdesk.md](helpdesk.md#open).
2. **`at_risk` is a hardcoded 24h band** here while the ticket-list `summary/`
   endpoint takes `due_soon_minutes`. The two surfaces will not agree.
3. **No team/member filter-bar params.** `dashboard-crm/*` accepts `team_id` and
   `user_id` on every widget; `dashboard-issue/*` accepts only `scope`. If the
   Helpdesk tab grows the same dropdowns, they need adding.
