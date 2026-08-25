# Helpdesk API

Backend contract for **Helpdesk → Tickets** (list, board, filter panel, detail
actions) and its supporting configuration surfaces.

The domain model is called **Issue**, not "ticket" — every route, field and
permission codename uses `issue`. "Ticket" is UI vocabulary only. The one place
the two meet is the human-readable `reference` (`TKT-0001`), which is generated
per org from the org's `DocumentNumbering` counter.

Everything below mounts under `/api/v1/crm/` unless stated otherwise.

Source of truth: `crm/views/issue.py`, `crm/filters/issue.py`,
`crm/serializers/issue.py`, `crm/models/issue.py`, `crm/services/issue_*.py`,
`crm/views/issue_webhook.py`, routes in `crm/urls.py`.

Related docs: [issue-filters.md](issue-filters.md) (saved filters — the chip row
above the list), [webhook-urls.md](webhook-urls.md), [permissions.md](permissions.md).

---

## Contents

1. [Cross-cutting rules](#1--cross-cutting-rules)
2. [Endpoint index](#2--endpoint-index)
3. [The ticket list](#3--the-ticket-list-get-issues)
4. [Filter panel — every param](#4--filter-panel--every-param)
5. [Status chips (`status-counts`)](#5--status-chips-get-issuesstatus-counts)
6. [Board view](#6--board-view-get-issuesboard)
7. [Support Overview (`summary`)](#7--support-overview-get-issuessummary)
8. [Create / retrieve / update / delete](#8--create--retrieve--update--delete)
9. [Bulk actions](#9--bulk-actions-checkbox-column)
10. [Ticket detail sub-resources](#10--ticket-detail-sub-resources)
11. [Notes & files on the detail page](#11--notes--files-on-the-detail-page)
12. [Assembling the detail page](#12--assembling-the-detail-page)
13. [Configuration: statuses & categories](#13--configuration-statuses--categories)
14. [Populating the filter dropdowns](#14--populating-the-filter-dropdowns)
15. [Inbound webhook keys](#15--inbound-webhook-keys)

---

## 1 — Cross-cutting rules

**Auth.** JWT bearer on every endpoint in this document except the public
webhook intake (§13). Org context is resolved by `OrganizationMiddleware` from
the token; never send `organization`.

**Plan gate.** `IssueViewSet`, `IssueStatusViewSet` and `IssueTypeViewSet` all
declare `required_feature = "helpdesk"`. An org whose plan lacks `helpdesk` gets
`403` on the whole module — checked *after* RBAC so plan details are not leaked
to a caller who wouldn't have been allowed in anyway. Note that an org with **no
subscription at all** resolves to an empty feature dict, which reads as denied.

**Permissions.** Module-level codenames, enforced by `MapBasedPermission`:

| Codename | Guards |
| :--- | :--- |
| `view_issue` | `list`, `query`, `retrieve`, `board`, `status-counts`, `summary`, `activity`, `GET tasks` |
| `create_issue` | `create` |
| `update_issue` | `update`, `partial_update`, `replies`, `POST tasks`, `bulk-assign`, `bulk-status`, `bulk-priority` |
| `delete_issue` | `destroy`, `bulk-delete` |

Record-level scope (`all > hierarchy > team > owned > assignee > filtered`) is
applied inside `IssueService.get_base_queryset` for **every** read *and* for the
bulk-action target lookup — a caller with `delete_issue` can still only delete
rows they can see. Ids outside scope come back as `not_found`, never as a
silent no-op.

> ⚠️ **A user with no role assigned sees nothing.** `apply_record_permissions`
> denies by default: no `UserRole` row ⇒ empty queryset on every list, not an
> error. If tickets "disappear" for a test account, check its roles before
> suspecting the filters. `is_staff`/superuser bypass record permissions
> entirely, so an admin account will not reproduce it.

Statuses and categories are read with `view_issue` but written with
`update_issue` — there is no separate settings permission for them.

**Pagination.** Global `StandardResultsSetPagination`: page-number, `page_size`
default **100**, max **200**. List responses are
`{count, next, previous, results: [...]}`. Applying a saved filter does not
change this.

**Caching.** `summary` is cached 60s and `board` 300s, both varied by user, org
and model version. Mutations bump `org:{org_id}:issue`, so a write invalidates
them immediately. If you write an Issue outside the viewset you must bump that
version yourself.

**The `QUERY` verb.** `GET /issues/` and `GET /issues/status-counts/` each have a
`QUERY` twin that takes the identical flat param map as a **JSON body** instead
of a query string. Use it when the filter set would blow the URL length limit
(long `__in` lists of UUIDs). Results are byte-identical to the GET. URL params
survive and body values win on key collision, so
`QUERY /issues/?page=2` with filters in the body works.

```http
QUERY /api/v1/crm/issues/ HTTP/1.1
Content-Type: application/json

{ "priority__in": ["High", "Critical"], "assigned_to__not": "…,…", "ordering": "-opening_date" }
```

Arrays in the body become repeated params, so multi-value filters read them
correctly. Booleans are lowercased to `"true"`/`"false"`.

---

## 2 — Endpoint index

### Tickets

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/issues/` | Ticket list (the table). |
| `QUERY` | `/issues/` | Same, filters in the body. |
| `POST` | `/issues/` | New Ticket. |
| `GET` | `/issues/{issue_id}/` | Ticket detail. |
| `PATCH` / `PUT` | `/issues/{issue_id}/` | Update. |
| `DELETE` | `/issues/{issue_id}/` | Delete. |
| `GET`/`QUERY` | `/issues/status-counts/` | The `All (25) · Open (4) …` chip row. |
| `GET` | `/issues/board/` | Kanban lanes + first page of cards. |
| `GET` | `/issues/summary/` | Support Overview panels. |
| `GET` | `/issues/{issue_id}/activity/` | Audit/activity feed. |
| `GET` / `POST` | `/issues/{issue_id}/tasks/` | Linked Operations tasks. |
| `POST` | `/issues/{issue_id}/replies/` | Send a customer reply on the ticket's channel. |
| `POST` | `/issues/bulk-assign/` | |
| `POST` | `/issues/bulk-status/` | |
| `POST` | `/issues/bulk-priority/` | |
| `POST` | `/issues/bulk-delete/` | |

### Notes & files on the ticket (polymorphic — §11)

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/notes/?related_to=issue&related_to_id={issue_id}` | The Notes panel. Top-level notes only. |
| `POST` | `/notes/` | Add note. |
| `PATCH` `DELETE` | `/notes/{note_id}/` | Edit / delete a note. |
| `GET` `POST` | `/notes/{note_id}/replies/` | The note's `Reply` thread. |
| `GET` | `/note-types/` | The `Tag` dropdown. |
| `GET` | `/attachments/?related_to=issue&related_to_id={issue_id}` | The Files tab. |
| `POST` | `/attachments/` | Upload (multipart). |
| `DELETE` | `/attachments/{attachment_id}/` | |

### Configuration

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` `POST` | `/issue-statuses/` | Status lanes (Open, In Progress, …). |
| `GET` `PATCH` `DELETE` | `/issue-statuses/{issue_status_id}/` | |
| `POST` | `/issue-statuses/reorder/` | Lane order. |
| `GET` `POST` | `/issue-types/` | Categories (Billing, Bug, …). |
| `GET` `PATCH` `DELETE` | `/issue-types/{issue_type_id}/` | |

### Saved filters — see [issue-filters.md](issue-filters.md)

| Method | Path |
| :--- | :--- |
| `GET` `POST` | `/saved-filters/?module=issue` |
| `GET` `PATCH` `DELETE` | `/saved-filters/{saved_filter_id}/` |
| `GET` | `/saved-filters/{saved_filter_id}/count/` |

### Inbound webhook keys

| Method | Path |
| :--- | :--- |
| `GET` `POST` | `/issue-webhook-keys/` |
| `GET` `PATCH` `DELETE` | `/issue-webhook-keys/{key_id}/` |
| `POST` | `/issue-webhook-keys/{key_id}/rotate/` |
| `GET` | `/issue-webhook-keys/{key_id}/submissions/` |
| `POST` `OPTIONS` | `/webhooks/issues/{key_id}/` — **public, unauthenticated** |

---

## 3 — The ticket list (`GET /issues/`)

Backs the table in the screenshot. One paginated page of `Issue` rows, already
permission-scoped, with notes and attachments batch-fetched for the page (not
per row).

```http
GET /api/v1/crm/issues/?page=1&page_size=25&ordering=-opening_date
```

### Response row

`IssueSerializer` uses `fields = "__all__"`, so every model column is present.
The fields the list screen actually reads:

| Field | Type | Notes |
| :--- | :--- | :--- |
| `issue_id` | uuid | The id used everywhere. **Not** `id`. |
| `reference` | string \| null | `TKT-0001`. Monotonic per org but **not gapless** — a rolled-back create burns a number, so never treat it as a ticket count. |
| `subject` | string (≤280) | The row title. |
| `description` | string \| null | |
| `status` | object \| null | Nested `IssueStatus`: `issue_status_id`, `name`, `color`, `position`, `is_resolved`, `is_on_hold`, `is_default`, `is_active`, `is_readonly`. Nullable — an un-triaged ticket has no status and still counts in "All". |
| `priority` | `Low` \| `Medium` \| `High` \| `Critical` | Non-null, defaults `Medium`. |
| `issue_type` | uuid \| null | Category id. |
| `type_name` | string \| null | Category label (the `Billing` / `Security` subtitle under the subject). |
| `assigned_to` | uuid \| null | |
| `assigned_to_name` | string | Assignee column. |
| `assigned_team` / `assigned_team_name` | uuid / string \| null | |
| `raised_by` / `raised_by_name` | uuid / string \| null | Requester column. |
| `customer` / `customer_name` | uuid / string \| null | |
| `customer_email`, `customer_phone` | string \| null | Real `customer` FK first; falls back to the legacy generic FK. |
| `product` / `product_name`, `project` / `project_name` | uuid / string \| null | |
| `channel`, `channel_display` | `email`\|`whatsapp`\|`phone`\|`api`, label | Nullable. |
| `reported_for`, `reported_for_display` | `self`\|`client` | Defaults `client`. |
| `opening_date`, `opening_time` | date, time | Set once at creation. Backs the `20d ago` Created column. |
| `resolution_date`, `resolution_time` | date, time \| null | Auto-stamped when the status `is_resolved`. |
| `sla_deadline` | datetime \| null | |
| `sla_remaining_seconds` | number \| null | **Signed** — negative means overdue by that many seconds. Pause-aware. Computed at read time, so it is exact. Test `< 0`, not `== 0`. |
| `sla_breached` | bool | **Stored**, flipped by the `check_sla_breaches` beat job, so it lags up to the beat interval. Do not present it as a matched pair with `sla_remaining_seconds`. Filtering uses this column. |
| `sla_paused_seconds`, `sla_hold_started_at` | int, datetime \| null | Drive the `Paused` SLA chip: a ticket in an `is_on_hold` status has `sla_hold_started_at` set. |
| `on_hold_reason` | string (≤200) \| null | Writable free text — the "waiting on customer" half of the paused chip. Auto-cleared when the ticket leaves the on-hold status. |
| `first_response_due_at` | datetime \| null | Respond-by target. Null when the customer has no first-response SLA configured — render no chip rather than a fabricated one. |
| `first_response_remaining_seconds` | number \| null | Signed, pause-aware. |
| `is_first_response_breached` | bool \| null | Read-time exact. |
| `first_responded_at` | datetime \| null | Stamped by the **first outbound reply only**. A status change to "In Progress" deliberately does not count as a response. |
| `first_response_time` | number \| null | ⚠️ **Misnamed** — this is time-to-**resolution** in minutes, not first response. The dashboards, list ordering and the `first_response_time*` filters all read it with that meaning. |
| `has_linked_tasks` | bool | From an `EXISTS` annotation — no per-row query. |
| `reopen_count` | int | |
| `parent_issue` | uuid \| null | |
| `custom_fields` | object \| null | Freeform JSON. Issue has **no** org-configurable `CustomFieldDefinition` layer (unlike Lead/Customer) — the public webhook folds unmapped payload keys in here as `form.<key>`. |
| `notes`, `attachments` | array | Batch-fetched for the page. |
| `content_type`, `object_id` | int, uuid \| null | Legacy generic link — see below. |

### `customer` / `product` / `project` vs the generic link

`customer`, `product` and `project` are **real FK columns** and coexist on one
ticket. The generic `content_type`/`object_id` pair is retained only for
"raised against an arbitrary record" (a lead, a deal, a call log) and is
deprecated as the customer/product/project channel. A caller still sending
`related_to=customer&related_to_id=<uuid>` gets the real FK mirrored for it, so
both representations stay consistent during migration. Prefer the real FKs.

The generic FK stores the model's custom `*_id` UUID, not its integer PK, so
Django's `content_object` always resolves to `None` — the serializer resolves it
manually, one query per row. That per-row cost is exactly why the three were
promoted; only tickets linked *solely* through the generic FK still pay it.

### Ordering

`?ordering=` accepts `opening_date`, `priority`, `status`, `first_response_time`,
each with a `-` prefix. Default `-opening_date,-opening_time`.

Two caveats: `priority` sorts **alphabetically** (`Critical, High, Low, Medium`),
not by severity — sort client-side if you need severity order. `status` sorts by
FK, not by lane `position`.

### Search

Two search transports reach the same rows:

* `?search=` through `IssueFilter.filter_search` — matches `subject`,
  `description`, `reference` **and** customer name. This is what the search box
  in the screenshot should use.
* DRF's own `SearchFilter` over the same four fields, for callers not going
  through the FilterSet.

---

## 4 — Filter panel — every param

This is the `Filter tickets` drawer. Every facet has an `is` / `is not` toggle:
send the base param (or `__in`) for **is**, and `__not` for **is not**.

Multi-value params accept **both** transports — `?status__in=a,b` and
`?status__in=a&status__in=b`, and a mix. (`CSVInFilter`; a bare `BaseInFilter`
would keep only the last value and silently break the QUERY verb and saved
filters.)

### The `is not` semantics — read this

Every `__not` param excludes matching tickets **while keeping rows whose field is
`NULL`**. This is deliberate. A plain `.exclude(status__in=[…])` also drops
NULL-FK rows through SQL NULL semantics, which would hide un-triaged tickets
from an "is not Open" filter. So "Assignee is not Deepak" **includes**
unassigned tickets, and "Category is not Billing" includes uncategorised ones.
Surface that in the UI if it would surprise the user.

### Status

| Param | Value |
| :--- | :--- |
| `status` | `issue_status_id` uuid — **not** the status name |
| `status__in` | uuid list |
| `status__not` | uuid list to exclude |

The chip row (`All / Open / In Progress / …`) filters with `status__in`. The
`Overdue (3)` chip is `sla_breached=true`, not a status.

### Priority

| Param | Value |
| :--- | :--- |
| `priority`, `priority__in`, `priority__not` | `Low` \| `Medium` \| `High` \| `Critical` |

### Assignee / requester / team

| Param | Value |
| :--- | :--- |
| `assigned_to`, `assigned_to__in`, `assigned_to__not` | `user_id` uuid(s) |
| `raised_by`, `raised_by__in`, `raised_by__not` | `user_id` uuid(s) |
| `assigned_team`, `assigned_team__in`, `assigned_team__not` | `team_id` uuid(s) |
| `assigned_to_me` | `true` — backs the **My Tickets** toggle |
| `my_team` | `true` — any team the requesting user belongs to |

`assigned_to_me` and `my_team` resolve against the **requesting user at request
time**, so a saved filter using them means "mine" for whoever runs it.

### Category (`issue_type`)

| Param | Value |
| :--- | :--- |
| `issue_type`, `issue_type__in`, `issue_type__not` | `issue_type_id` uuid(s) |

### Product / Project / Customer

| Param | Value |
| :--- | :--- |
| `customer`, `customer__in`, `customer__not` | `customer_id` uuid(s) |
| `product`, `product__in`, `product__not` | `product_id` uuid(s) |
| `project`, `project__in`, `project__not` | `project_id` uuid(s) |

Like every other `__not` facet these keep NULL-FK rows, so "Customer is not
Acme" includes tickets with no customer at all.

### Channel

| Param | Value |
| :--- | :--- |
| `channel`, `channel__in`, `channel__not` | `email` \| `whatsapp` \| `phone` \| `api` |

Nullable on the model, so `channel__not` keeps channel-less tickets.

### Generic related record

| Param | Value |
| :--- | :--- |
| `related_to`, `related_to__in` | content-type model name, e.g. `lead` |
| `related_to_id`, `related_to_id__in`, `related_to_id__not` | uuid of the related record |
| `has_linked_tasks` | bool — has at least one Operations task |

### Dates

| Param | Value |
| :--- | :--- |
| `opening_date`, `opening_date_after`, `opening_date_before` | `YYYY-MM-DD` |
| `resolution_date`, `resolution_date_after`, `resolution_date_before` | `YYYY-MM-DD` |
| `created_at`, `created_at_after`, `created_at_before` | `YYYY-MM-DD` (date part of the timestamp) |
| `updated_at`, `updated_at_after`, `updated_at_before` | `YYYY-MM-DD` (date part) |
| `sla_deadline_after`, `sla_deadline_before` | ISO datetime |
| `last_updated` | `today` \| `this_week` \| `this_month` |

`last_updated` is the only relative-window param, and it is evaluated at request
time. There is no relative equivalent for the other date fields, so "opened in
the last 7 days" has to be sent as an absolute `opening_date_after` — and a
saved filter storing that will drift.

### SLA

| Param | Value |
| :--- | :--- |
| `sla_breached` | bool — backs the `Overdue` chip. Reads the **stored** flag (see §3). |
| `has_sla` | bool — `true` ⇒ `sla_deadline` is set |
| `first_response_time`, `first_response_time_min`, `first_response_time_max` | number (minutes; the misnamed time-to-resolution field) |

`resolution_time` is a `TimeField`, not a duration, and is deliberately not
exposed as a numeric filter.

### Identity & text

| Param | Value |
| :--- | :--- |
| `issue_id` | uuid |
| `reference`, `reference__icontains` | `TKT-0001`; `icontains` so `0001` alone matches |
| `subject`, `subject__icontains` | string |
| `description__icontains` | string |
| `search` | subject + description + reference + customer name |

### Saved filters

`?saved_filter_id=<uuid>` layers a stored definition **under** the request's
explicit params — so `?saved_filter_id=X&priority=Low` runs the chip with
`priority` overridden. A filter referencing an unavailable field fails inert
(`400`) rather than running a widened query. Full contract in
[issue-filters.md](issue-filters.md).

---

## 5 — Status chips (`GET /issues/status-counts/`)

Backs `All (25) · Open (4) · In Progress (6) … · Overdue (3)`.

```http
GET /api/v1/crm/issues/status-counts/?assigned_to_me=true
QUERY /api/v1/crm/issues/status-counts/     # same params in a JSON body
```

Applies the **same** filters, saved filter and record-level scope as the list —
**minus the status facet itself** (`status`, `status__in`, `status__not` are
stripped). That is what makes each chip report the count it *would* have under
the other active filters, so clicking between chips doesn't zero out the row.

Every active status is returned zero-filled, so the chip row is stable.

```jsonc
{
  "total": 25,          // the "All" chip
  "overdue": 3,         // the "Overdue" chip — sla_breached=true under the same filters
  "no_status": 0,       // tickets with no status; counted in `total`
  "statuses": [
    {
      "issue_status_id": "…",
      "name": "Open",
      "color": "#2563eb",
      "position": 0,
      "is_resolved": false,
      "is_on_hold": false,
      "count": 4,
      "overdue_count": 1
    }
  ]
}
```

`total` is the sum of the per-status counts including `no_status`. Inactive
statuses are excluded from `statuses` but their tickets still count toward
`total`, so `sum(statuses[].count)` can be less than `total`.

---

## 6 — Board view (`GET /issues/board/`)

The `Board` toggle. One response carries every active status lane with its
count, its overdue badge, and the lane's first page of cards.

```http
GET /api/v1/crm/issues/board/?lane_page_size=20&priority__in=High,Critical
```

| Param | Default | Notes |
| :--- | :--- | :--- |
| `lane_page_size` | 20 | Clamped to 1–50. Deliberately smaller than the list's 100 so the initial payload stays light. |

Accepts every list filter plus `?saved_filter_id=`. Cards are produced by the
same `IssueSerializer` as table rows, so they are byte-identical.

```jsonc
{
  "board_total": 25,
  "board_overdue": 3,
  "lane_page_size": 20,
  "lanes": [
    {
      "status_id": "…", "status_name": "Open", "color": "#2563eb", "position": 0,
      "is_resolved": false, "is_on_hold": false,
      "count": 4, "overdue_count": 1,
      "cards": [ /* IssueSerializer rows */ ],
      "next_page": 2,
      "next_url": "/api/v1/crm/issues/?priority__in=High%2CCritical&status=…&page=2&page_size=20"
    }
  ]
}
```

**Load more** within a lane: follow `next_url` verbatim, or call
`GET /issues/?status=<lane>&page=N&page_size=<lane_page_size>`. The board's
in-lane ordering matches the list default (`-opening_date, -opening_time,
issue_id`), so page 2 is disjoint from the board's first page — the `issue_id`
tiebreaker is what guarantees that. `next_page`/`next_url` are `null` when the
lane has no more cards.

Zero-count lanes are included so the board renders a stable column set. Cached
300s per user/org.

---

## 7 — Support Overview (`GET /issues/summary/`)

Stats strip, SLA Watch, Workload and Pipeline for the helpdesk overview screen.
Accepts the same filters as the list.

| Param | Default | Notes |
| :--- | :--- | :--- |
| `due_soon_minutes` | 60 | The "Due < 1h" window. Clamped to 1 minute – 7 days. |

```jsonc
{
  "due_soon_minutes": 60,
  "stats": { "open": 17, "breached_now": 3, "due_today": 5, "closed_today": 2 },
  "sla_watch": {
    "breached":   { "total": 3, "items": [ /* ≤8 cards */ ] },
    "due_within": { "total": 2, "items": [] },
    "due_today":  { "total": 3, "items": [] },
    "on_track":   { "total": 9, "items": [] }
  },
  "workload": {
    "unassigned": { "total": 4, "items": [] },
    "by_agent": [ { "user": { "user_id": "…", "name": "Deepak Tiwari" }, "total": 6 } ]
  },
  "pipeline": [ { "issue_status_id": "…", "name": "Open", "color": "#2563eb", "position": 0, "is_resolved": false, "is_on_hold": false, "total": 4 } ]
}
```

Card shape: `issue_id`, `reference`, `subject`, `priority`, `created_at`,
`assignee` (`{user_id, name}` or `null`), `status_id`, `status_name`,
`sla_remaining_seconds` (signed), `has_linked_tasks`.

Notes:

* SLA Watch counts **open tickets only** (`status.is_resolved = false`) and the
  four buckets are mutually exclusive and ordered breached → due_within →
  due_today → on_track, so they sum to the open total. Tickets with no deadline
  land in `on_track` — they cannot breach.
* All SLA arithmetic runs in SQL against a **pause-aware** effective deadline
  (`sla_deadline` + accumulated hold time + any hold in flight), so a paused
  ticket does not slide toward "breached" while frozen.
* `items` is capped at 8 per bucket while `total` is uncapped — render
  "showing 8 of 23", not "8".
* "Today" is the **local** day, matching every other dashboard.
* `pipeline` is keyed by the org's real `IssueStatus` rows, never a fixed set of
  columns.
* Cached 60s, varied by user — every number is permission-scoped.

---

## 8 — Create / retrieve / update / delete

### Create — `POST /issues/`

Accepts `application/json` **or** `multipart/form-data` (the latter for the
inline first attachment).

```jsonc
{
  "subject": "Unable to download invoice PDF from portal",   // required, ≤280
  "description": "…",
  "status_id": "<issue_status_id uuid>",     // write-only; reads back as nested `status`
  "priority": "Critical",
  "issue_type": "<issue_type_id uuid>",
  "assigned_to": "<user_id uuid>",
  "assigned_team": "<team_id uuid>",
  "raised_by": "<user_id uuid>",
  "customer_id": "<customer_id uuid>",       // write-only → reads back as `customer` / `customer_name`
  "product_id": "<product_id uuid>",
  "project_id": "<project_id uuid>",
  "channel": "email",
  "reported_for": "client",
  "custom_fields": { "any": "json" },

  // optional inline children
  "note_content": "First triage note",
  "note_type_id": "<uuid>",
  "file_upload": "<binary, multipart only>",
  "attachment_name": "invoice.pdf"
}
```

`organization`, `owner`, `created_by`, `modified_by`, `opening_date`,
`opening_time` and `reference` are stamped server-side — do not send them.

**SLA snapshot.** On create, if the ticket has a `customer`, that customer's
`sla_value`/`sla_unit` are copied onto the ticket and `sla_deadline` is computed
as `created_at + delta`. The first-response target is copied too, but only if
the customer has one configured. A ticket with no customer gets **no SLA** — the
snapshot keys off the real `customer` FK, so it now applies regardless of what
else the ticket is linked to.

`status_id` is validated against the caller's org (`400` if the status belongs
to another org). Same for `customer_id` / `product_id` / `project_id`.

### Retrieve — `GET /issues/{issue_id}/`

Same shape as a list row. `notes` and `attachments` fall back to a per-instance
query here (no batch map), which is fine for a single ticket.

### Update — `PATCH /issues/{issue_id}/`

Any writable field. Two behaviours ride on the status change:

* **Mandatory note before hold.** Moving a ticket into an `is_on_hold` status
  requires at least one existing note, else `400`:

  ```json
  {"status_id": "A mandatory note must be added to the issue before placing it on hold."}
  ```

  The error carries `code: "note_required_before_hold"`, surfaced in the
  response's `error_codes` block — match on the code, not the sentence.

* **Resolution + SLA clock**, in `Issue.save()`: moving into an `is_resolved`
  status stamps `resolution_date`/`resolution_time` and computes
  `first_response_time` (time-to-resolution, minutes). Entering an `is_on_hold`
  status sets `sla_hold_started_at`; leaving it accumulates the elapsed time
  into `sla_paused_seconds` and logs `sla_paused` / `sla_resumed` activity
  events. Because this lives in `save()`, a queryset `.update()` skips it and
  would leave a paused ticket's clock frozen forever.

### Delete — `DELETE /issues/{issue_id}/`

Hard delete. `204`.

---

## 9 — Bulk actions (checkbox column)

All four take `issue_ids` and return `200` even on partial failure — read
`success`.

| Endpoint | Body |
| :--- | :--- |
| `POST /issues/bulk-assign/` | `{"issue_ids": ["…"], "assignee_id": "<user_id>"}` |
| `POST /issues/bulk-status/` | `{"issue_ids": ["…"], "status_id": "<issue_status_id>"}` |
| `POST /issues/bulk-priority/` | `{"issue_ids": ["…"], "priority": "High"}` |
| `POST /issues/bulk-delete/` | `{"issue_ids": ["…"]}` |

```jsonc
// assign / status / priority
{ "success": false, "updated": 8, "errors": [ { "issue_id": "…", "error": "not_found" } ] }

// delete
{ "success": true, "deleted": 8, "errors": [] }
```

Semantics worth knowing:

* Targets are resolved through the permission-scoped queryset. An id the caller
  cannot see is reported `not_found` — it is never silently acted on.
* `bulk-status` and friends save **each row individually**, not as a queryset
  `UPDATE`, so `Issue.save()` runs per ticket (resolution stamping, SLA
  hold/resume). Each save is in its own savepoint, so one bad row cannot roll
  back its successful siblings — hence the honest partial-success response.
* `bulk-status` enforces the same mandatory-note-before-hold rule as the
  serializer, per ticket. A ticket without a note fails with
  `error: "note_required_before_hold"` while the rest of the batch succeeds.
* Missing `issue_ids` (or `assignee_id` / `status_id` / `priority`) is a `400`.
  An unknown assignee or a status from another org is also `400`.
* Bulk actions write their own activity rows (`assignee_changed`,
  `status_changed`, `priority_changed`, each with `{"bulk": true}`) in one
  `bulk_create` — the audit middleware cannot do it, since a bulk request is one
  POST with no resolvable `record_id`.
* `bulk-delete` is a real delete and does **not** write per-ticket activity.

---

## 10 — Ticket detail sub-resources

### Activity — `GET /issues/{issue_id}/activity/`

Paginated audit feed for one ticket. Reads `AuditLog` rows: direct mutations via
`AuditMiddleware`, child rollups (a note/attachment/task write logs an update on
the parent), and explicitly-recorded events for paths that never see a request
(`sla_breached`, `sla_paused`, `sla_resumed`, `reopened`, `reply_sent`, bulk
actions).

Gated by `view_issue` and scoped through `get_object()`, so an agent without
`view_audit_log` still sees their own ticket's history — unlike the org-wide
`/access-control/audit-logs/` endpoint.

Each row carries `actor` (`{user_id, name, is_system}` — `is_system: true` for
the beat job and signal paths), a humanized summary, `changes`, and
`event_data`, the structured payload so the frontend can format its own sentence
rather than parsing ours.

⚠️ `event_type` is **derived on read, not stored**, so it cannot be filtered.
"Show me every SLA breach" needs a real column first.

**Empty feed?** `AuditLog` rows are written **only by the Celery worker**. A
ticket with no activity almost always means a dead worker, not a bug in the
activity code.

### Linked tasks — `GET` / `POST /issues/{issue_id}/tasks/`

`GET` returns the Operations tasks raised from this ticket, paginated, using the
**projects** `TaskSerializer` — a linked task *is* a `projects.Task` and the
Operations screens must show the same row.

`POST` creates one against this ticket. The ticket link is taken from the URL,
not the body, so a task cannot be created against a different ticket.

Unlink from the other side:
`PATCH /api/v1/projects/tasks/{task_id}/ {"ticket_id": null}`.

`GET` needs `view_issue`; `POST` needs `update_issue`.

### Reply — `POST /issues/{issue_id}/replies/`

Sends a customer-facing reply on the ticket's **own channel** and records it as a
`Note` of kind `reply_out`.

```jsonc
// request
{ "body": "We've re-issued your invoice — please try the download again." }

// 201
{
  "note": { "note_id": "…", "content": "…", "kind": "reply_out", "created_at": "…", "created_by_id": "…" },
  "dispatch": { "channel": "email", "to": "ishaan@…", "provider_message_id": "…" }
}
```

Two deliberate rules:

* **A failed dispatch creates nothing.** There is no reply that sits in the
  timeline but was never delivered. Retry is a fresh POST.
* **Provider errors pass through verbatim** — status code and error code
  unchanged, notably WhatsApp's `403 whatsapp_window_closed` (free-form replies
  are only legal inside Meta's 24-hour customer-care window). The composer needs
  to see the real code, so dispatch is synchronous, not a background job.

Only `email` and `whatsapp` are dispatchable. `phone` and un-set channels return
`400 reply_channel_not_dispatchable` rather than quietly filing an internal note.

| Code | Status | Meaning |
| :--- | :--- | :--- |
| `reply_channel_not_dispatchable` | 400 | `phone`, or no channel set. |
| `reply_recipient_missing` | 400 | No customer email/phone on the ticket. |
| `no_org_email_configured` | 400 | Org has no email sender. |
| `whatsapp_account_not_found` | 400 | No active WhatsApp account. |
| `whatsapp_window_closed` | 403 | Outside the 24h window — from the WhatsApp layer. |
| `email_send_failed` / `whatsapp_api_error` | 502 | Provider failure. |

The first successful reply stamps `first_responded_at`, stopping the respond-by
clock, and logs a `reply_sent` activity event.

---

## 11 — Notes & files on the detail page

Notes and attachments are **polymorphic** — they are not helpdesk resources.
They live on shared endpoints and link to any CRM record through
`content_type` + `object_id`. For a ticket, the link is
`related_to=issue` + `related_to_id=<issue_id>`.

Two things to know about how they are secured:

* **They re-apply the parent record's visibility.** These endpoints are not
  covered by the `view_issue` / `update_issue` codenames — they use
  `IsAuthenticated` — but they run the **same** record-level resolver the
  ticket list runs, against the linked record (rulebook §3.4.4). A note or file
  on a ticket you cannot see is not listed, not retrievable, not deletable, and
  cannot be created: reads filter it out (404 on detail) and writes return
  `403`. Deletes are checked against `can_delete` on the **parent**, not merely
  `can_read`. Staff and superusers bypass, as everywhere else.
* They are **not plan-gated**, so they stay reachable for an org whose plan
  lacks `helpdesk`. Since visibility is now enforced, this exposes no data the
  caller could not already reach — but a plan downgrade does not hide the
  timeline.

Both rules apply to every polymorphic parent (leads, customers, tasks,
projects, quotations…), not just tickets — see
`crm/services/generic_visibility.py`.

Writing a note or attachment against a ticket also bumps the parent's audit
trail — `crm/signals.py` rolls a child write up as an update on the Issue, which
is why they appear in the ticket's activity feed (§10).

### Notes panel — `/notes/`

```http
GET /api/v1/crm/notes/?related_to=issue&related_to_id=<issue_id>
```

Returns **top-level notes only** (`parent_note IS NULL`); replies come from the
thread endpoint below. Ordered newest-first, paginated.

```jsonc
// POST /api/v1/crm/notes/
{
  "content": "Put on hold pending the customer's confirmation of the account ID.",
  "title": "Optional, ≤140",
  "related_to": "issue",
  "related_to_id": "<issue_id>",
  "note_type_id": "<uuid>",        // the "Tag" dropdown; optional
  "is_pinned": 0,
  "mentioned_users": ["<user_id>"] // fires mention notifications
}
```

| Field | Notes |
| :--- | :--- |
| `note_id` | uuid |
| `content` | required |
| `title` | ≤140, optional |
| `kind` | `internal` \| `reply_out` \| `reply_in`. **Read-only in practice** — set by the system. The Notes panel shows internal notes; `reply_out` rows are what `POST /issues/{id}/replies/` creates (§10), so a ticket's full conversation is notes filtered by `kind`. |
| `note_type` | FK to NoteType — the `Tag` chip. `on_delete=RESTRICT`, so a type in use cannot be deleted. |
| `is_pinned` | **Integer**, not a boolean (`0`/`1`). |
| `parent_note` | uuid \| null — set only on replies. |
| `reply_count` | Denormalized count of direct replies, maintained on create/delete. |
| `mentioned_users` | M2M of `user_id`. |
| `created_by`, `created_at` | Stamped server-side. |

Filters: `related_to`, `related_to__in`, `related_to_id`, `related_to_id__in`,
`is_pinned`, `created_by`, `created_at[_after|_before]`,
`updated_at[_after|_before]`, `title`, `title__icontains`,
`content__icontains`, `search`.

`owner` defaults to the creator. Creating a note best-effort dispatches reply and
mention notifications — a notification failure never breaks note creation.

### Note threads — `/notes/{note_id}/replies/`

Backs the `Reply` link under each note.

* `GET` → that note's replies, **oldest-first**, paginated, with attachments
  prefetched.
* `POST` → creates a reply. `parent_note` is forced from the URL and
  `related_to`/`related_to_id` are stripped from the body — a reply always
  inherits its parent's record link and cannot be re-pointed at another ticket.
  Bumps the parent's `reply_count`.

Threading is one level deep in the UI, but the model does not enforce that — a
reply can itself carry replies.

### Files tab — `/attachments/`

```http
GET /api/v1/crm/attachments/?related_to=issue&related_to_id=<issue_id>
```

Ordered by `-uploaded_at`. Upload with `multipart/form-data`:

```
POST /api/v1/crm/attachments/
Content-Type: multipart/form-data

file_upload: <binary>
name:        invoice.pdf          # optional; defaults to the filename
related_to:  issue
related_to_id: <issue_id>
```

Or link an already-hosted file with JSON by sending `file` as a URL instead of
`file_upload`.

Files go to Bunny CDN under `Organizations/{org_uuid}/attachments/{unique}`;
filenames are sanitized and prefixed with a random hex, images are compressed via
Pillow and other types gzipped. `file` on the response is the CDN URL.

Fields: `attachment_id`, `name`, `file`, `uploaded_at`, `uploaded_by`.
Filters: the same `related_to*` pair plus `uploaded_by`,
`uploaded_at[_after|_before]`, `created_at[_after|_before]`, `name`,
`name__icontains`, `search`.

`DELETE /attachments/{attachment_id}/` takes the **UUID**; the legacy numeric pk
still resolves so older clients keep working.

Uploads count against the org's storage meter (`GET /billing/storage/`).

### Tag dropdown — `/note-types/`

Per-org note tags, ordered by `position`. **Reads are open to any authenticated
org member** so the Tag control populates for agents; writes still require
`update_settings`, since this is a config table. System-protected rows
(`is_readonly`) reject edits from non-superusers.

---

## 12 — Assembling the detail page

The screenshot's detail view is not one endpoint. Minimum set:

| Panel | Call |
| :--- | :--- |
| Header, Ticket information, Related chips, Description | `GET /issues/{issue_id}/` |
| Status dropdown options | `GET /issue-statuses/` |
| Assignee dropdown options | `GET /management/users/` |
| Category (Edit modal) | `GET /issue-types/` |
| Linked tasks tab + its count badge | `GET /issues/{issue_id}/tasks/` |
| Files tab | `GET /attachments/?related_to=issue&related_to_id={issue_id}` |
| Notes panel | `GET /notes/?related_to=issue&related_to_id={issue_id}` |
| Tag dropdown | `GET /note-types/` |
| Audit log | `GET /issues/{issue_id}/activity/` |

Notes on specific widgets:

* **Inline Status / Assignee / Priority edits** are ordinary
  `PATCH /issues/{issue_id}/` calls (`status_id`, `assigned_to`, `priority`).
  The status dropdown must handle the `note_required_before_hold` `400` when
  the user picks an on-hold status on a ticket with no notes — prompt for a note
  and retry rather than showing a raw error.
* **The `Related` chips** (`Ishaan Rao 25 — Customer`, `Analytics Add-on —
  Product / Service`) read the real FKs: `customer`/`customer_name`,
  `product`/`product_name`, `project`/`project_name`. All three can be set at
  once. Deep-link targets are `/crm/customers/{customer_id}/`,
  `/crm/products/{product_id}/`, `/projects/projects/{project_id}/`.
* **`via whatsapp · 20d ago`** is `channel_display` + `opening_date`/`created_at`.
* **`Resolution: Paused — waiting on customer`** reads `sla_hold_started_at`
  (set while the ticket sits in an `is_on_hold` status) plus **`on_hold_reason`**
  — a writable free-text field (≤200 chars) for the "waiting on customer" half.
  Send it on the same `PATCH` that moves the ticket into an on-hold status. It
  is **cleared automatically** when the ticket leaves hold, so it always
  describes the current pause; render the plain "Paused" label when it is null.
* **`SLA: 7 days`** is `sla_value` + `sla_unit` (the snapshot taken from the
  customer at creation), not `sla_deadline`.
* **The Linked tasks badge** (`2`) needs the tasks call for an exact number;
  the list/detail row's `has_linked_tasks` is only a boolean.
* **`Customer reply` composer** posts to `/issues/{issue_id}/replies/` and is
  only enabled for `channel` in (`email`, `whatsapp`) — the panel header in the
  screenshot reads "Sends via whatsapp" off `channel_display`. Expect and render
  `403 whatsapp_window_closed` (§10).
* **Audit log rows** come back humanized with an `actor`; `System · …` in the
  screenshot is `actor.is_system = true`, which is how the `sla_paused` event
  was written (from `Issue.save()`, with no request in flight).

---

## 13 — Configuration: statuses & categories

### Issue statuses — `/issue-statuses/`

The lanes: Open, In Progress, On Hold, Resolved, Closed, Duplicate.

| Field | Notes |
| :--- | :--- |
| `issue_status_id` | uuid — the value every `status*` filter takes |
| `name` | Unique per org |
| `color`, `position` | |
| `is_active` | Inactive statuses are excluded from chip rows and board lanes |
| `is_default` | At most one per org (DB constraint) |
| `is_resolved` | Terminal state — stamps resolution date/time, excluded from SLA Watch |
| `is_on_hold` | **Pauses the SLA timer** and requires a note before entering |
| `is_readonly` | System-protected: `403` on update or delete |

`?search=` over `name`; `?ordering=position|name`, default `position`.

`POST /issue-statuses/reorder/` with `{"order": ["<issue_status_id>", …]}` sets
`position` to the array index. `400` if `order` is empty.

`status` is `on_delete=RESTRICT` on Issue, so deleting a status still referenced
by any ticket fails at the DB level.

### Issue types (categories) — `/issue-types/`

Billing, Bug, Documentation, Feature Request, Integration, Performance…

| Field | Notes |
| :--- | :--- |
| `issue_type_id` | uuid — the value `issue_type*` filters take |
| `name` | ≤140, unique per org |
| `description` | |
| `default_priority` | `Low`\|`Medium`\|`High`\|`Critical`, default `Medium` |

`?search=` over `name`/`description`; `?ordering=name|default_priority`, default
`name`. `issue_type` is `on_delete=SET_NULL`, so deleting a category leaves its
tickets uncategorised.

Both config lists are paginated like everything else — pass `page_size` if you
need the whole set in one call for a dropdown.

---

## 14 — Populating the filter dropdowns

The filter drawer's option lists come from existing endpoints, not from a
helpdesk-specific one. There is **no** `/issues/filter-options/` aggregate — one
call per facet.

| Drawer facet | Endpoint | Option id → filter param |
| :--- | :--- | :--- |
| Status | `GET /api/v1/crm/issue-statuses/` | `issue_status_id` → `status__in` |
| Priority | *static* — `Low`, `Medium`, `High`, `Critical` | → `priority__in` |
| Assignee | `GET /api/v1/management/users/` | `user_id` → `assigned_to__in` |
| Category | `GET /api/v1/crm/issue-types/` | `issue_type_id` → `issue_type__in` |
| Product / Service | `GET /api/v1/crm/products/` | `product_id` → `product__in` |
| Project | `GET /api/v1/projects/projects/` | `project_id` → `project__in` |
| Customer | `GET /api/v1/crm/customers/` | `customer_id` → `customer__in` |
| Team | `GET /api/v1/management/teams/` | `team_id` → `assigned_team__in` |
| Channel | *static* — `email`, `whatsapp`, `phone`, `api` | → `channel__in` |

The drawer's "Search teammates / products / projects" boxes should use each
endpoint's own `?search=` and page through results rather than loading the full
list — all of these are paginated at 100.

---

## 15 — Inbound webhook keys

Lets an external form or system file tickets without a user session. Admin API
under `/api/v1/crm/issue-webhook-keys/`; guarded by `HasSettingsPermission`
(same as the lead webhook keys), and **creation** is additionally gated on the
`issue_webhooks` plan feature — existing keys keep working after a downgrade,
only new keys are blocked.

| Method | Path | Notes |
| :--- | :--- | :--- |
| `GET` | `/issue-webhook-keys/` | List, newest first. |
| `POST` | `/issue-webhook-keys/` | Create. **Returns the plaintext `secret` once** — it is never retrievable again. |
| `GET` | `/issue-webhook-keys/{key_id}/` | Only `secret_last_four` is exposed. |
| `PATCH` | `/issue-webhook-keys/{key_id}/` | Update defaults / origins / rate limit. |
| `DELETE` | `/issue-webhook-keys/{key_id}/` | **Soft** delete — sets `is_active=false` + `revoked_at`. `204`. |
| `POST` | `/issue-webhook-keys/{key_id}/rotate/` | New secret, returned once. |
| `GET` | `/issue-webhook-keys/{key_id}/submissions/` | Paginated recent `IssueFormSubmission` rows, for debugging intake. |

A key carries defaults applied to tickets it creates: `default_issue_type`,
`default_status`, `default_assigned_team`, `default_assigned_to`, plus
`allowed_origins`, `require_hmac` and `rate_limit_per_minute`. Every write
invalidates the key's cache entry, so changes take effect immediately.

### Public intake — `POST /api/v1/webhooks/issues/{key_id}/`

Unauthenticated. Defences, in order: body size cap (`413 payload_too_large`),
per-IP rate limit then per-key rate limit (`429 rate_limited`, `Retry-After: 60`),
unknown key (`404 key_not_found`), and optional HMAC-SHA256 over the raw body in
`X-Signature`. `X-Idempotency-Key` de-duplicates retries. `OPTIONS` handles CORS
preflight and only answers for an `Origin` in the key's `allowed_origins` —
anything else is a bare `403`.

Payload keys that don't map to a real column are folded into the ticket's
`custom_fields` under `form.<key>`. Tickets created this way get `channel: "api"`
and share the same `sla_delta` computation as authenticated creates, so their
SLA deadlines are identical.

---

## Known gaps

### Fixed

These were documented as gaps and have since been closed:

* ~~No `__not` for customer / product / project~~ — `customer__not`,
  `product__not` and `project__not` now exist and keep NULL-FK rows. (§4)
* ~~Notes and attachments bypass ticket permissions~~ — both endpoints now
  re-apply the parent record's visibility on read **and** write, across every
  polymorphic parent type. (§11)
* ~~`/note-types/` requires settings permission to read~~ — reads are now open
  to any authenticated org member; writes remain settings-gated. (§11)
* ~~No "on hold reason" field~~ — `Issue.on_hold_reason` added, auto-cleared on
  resume. (§3, §12)

### Open

Still true, and deliberately so — each is either a breaking change or a product
decision rather than a bug:

1. **`first_response_time` measures time-to-resolution**, not first response —
   the name is wrong and the filters inherit it. The real first-response fields
   are `first_response_due_at` / `first_responded_at` /
   `is_first_response_breached`. Renaming it would break the dashboards, the
   list ordering and every stored saved filter, so it needs a coordinated
   release. (§3)
2. **`sla_breached` lags.** Filtering and the `Overdue` chip read the stored
   flag refreshed by a beat job; `sla_remaining_seconds` is exact at read time.
   The two can disagree for up to one beat interval. (§3, §5)
3. **Activity `event_type` is not filterable** — it is derived on read. (§10)
4. **Priority sorts alphabetically**, not by severity. Fixing it changes result
   order for existing clients. (§3)
5. **Issue has no `CustomFieldDefinition` layer** — `custom_fields` is freeform
   JSON with no org-configurable schema, unlike Lead/Customer. Saved filters can
   still reference `custom_fields.<name>` keys.
6. **No aggregate filter-options endpoint** — the drawer needs one call per
   facet. (§14)
7. **`is_pinned` is an integer**, not a boolean. Changing the type breaks
   clients sending `0`/`1`. (§11)
8. **Notes/attachments are not plan-gated.** Visibility is enforced, so this
   leaks nothing, but a `helpdesk` downgrade does not hide the timeline. (§11)

---

Tests: `crm/tests/test_issue_list_features.py`, `test_issue_helpdesk_gaps.py`,
`test_issue_webhook_management.py`, `test_issue_dashboard.py`,
`test_saved_filters.py`.

Route definitions: `crm/urls.py:99-101` (router), `crm/urls.py:120` (webhook
keys), `crm/urls.py:145-156` (the QUERY-capable collection view).
