# Backend requests — Operations → Projects (list + detail)

Context: the frontend has integrated **both** the Projects list page (list, filter
drawer, status tabs, saved filters) and the Project detail page (retrieve + info
panel, Tasks tab with groups/tasks/writes, Files, Notes, Activity/Audit). This
doc lists the backend operations that would make those screens correct and
efficient. All findings are from live verification against `/api/v1/projects/`
(org `newversion`); repro commands assume a valid `Authorization: Bearer <JWT>`.

Legend: 🔴 correctness · 🟡 efficiency / payload · 🟢 minor / nice-to-have.
Each item has a **definition of done** so it's independently verifiable.

---

## ✅ Already shipped (list page, round 1 — verified fixed 2026-07-23)

These four were requested earlier and are **live**; keeping them here as a
regression checklist, no action needed:

1. **Uniform multi-value transport** — every `__in`/`__not_in` now accepts CSV,
   repeated, and mixed forms and merges them. (Was: `status__in`/
   `project_type__in` 400'd on CSV; CSV fields dropped all-but-last on repeated.)
2. **Saved-filter CSV-string values apply correctly** (were silent no-ops); a
   malformed stored value now 400s inert with `errors.saved_filter.<field>`.
3. **`customer_name` + `project_type_name` on list rows** — client-side join
   removed.
4. **`?view=list` slim projection** (19 fields) + `percent_complete` as a JSON
   number + **QUERY method** on the list endpoint.

---

## ✅ Shipped (round 2 — verified fixed 2026-07-27)

All 8 open items below are **live and verified**. Summary of what changed;
per-item detail follows in the (now-annotated) sections.

| # | Item | Status |
|---|---|---|
| 1 | QUERY on `status-counts/` (projects **and** tasks) | ✅ QUERY returns the counts aggregate, not the list payload. |
| 2 | New task without `status` → default status | ✅ Fixed. Fallback to first-open when no `is_default`; seeder + dev-DB backfilled. |
| 3 | Slim tasks list `?view=list` | ✅ 19-field lane projection; `assigned_to` collapsed. |
| 4a | Project rollups single-query | ✅ Confirmed `Count(filter=…)` annotation, no N+1. |
| 4b | `?view=detail` panel projection | ✅ Drops reminder/schedule + costing-internals blocks. |
| 5 | Activity `summary` + `event_type` | ✅ Both added; `changes` kept raw. |
| 6 | Project-task-statuses path (doc) | ✅ Documented in operations.md §13.4. |
| 7 | `all_fields` shape + default-visible (doc) | ✅ Doc corrected: `all_fields.columns` is the catalog; default-visible aligned to seeder. |
| 8 | `computed_progress` numeric | ✅ Now a JSON number on task rows. |

Regression coverage: `projects/tests/test_task_list_features.py` (#1/#2/#3/#8),
`projects/tests/test_project_detail_features.py` (#1/#4b/#5).

---

## Open items (all resolved — kept for provenance)

### 1. ✅ `QUERY /projects/projects/status-counts/` mis-routes to the list handler — FIXED

The list endpoint now supports the QUERY verb (round-1 item 4), but the
`status-counts/` sub-route does **not** — a QUERY request to it falls through and
returns the **paginated list payload** (`{count, next, previous, results}`)
instead of the counts aggregate (`{total, no_status, statuses}`).

Repro:

```bash
# Returns {count, results:[…]} — the LIST payload, not the counts aggregate
QUERY /api/v1/projects/projects/status-counts/
{ "priority__in": ["High"] }

# GET is correct
GET /api/v1/projects/projects/status-counts/?priority__in=High
```

Impact: forces the frontend to keep tab-counts on GET with CSV URL params while
the list itself uses QUERY — two transports for one filter set. Low urgency
(GET works), but it's an inconsistency in the documented "QUERY parity" story.

Request: register the QUERY verb on the `status-counts/` action (same
body→filter handling as the list), or explicitly document that counts are
GET-only.

**Done when:** `QUERY …/status-counts/` with a filter body returns
`{total, no_status, statuses}`, matching `GET` with the same filters.

**✅ RESOLVED:** the `status-counts` action now accepts `["get", "query"]` and
routes the QUERY body through the same param pipeline as the list (control
params dropped). Done for **both** `projects/status-counts/` **and**
`tasks/status-counts/`. Verified: QUERY returns `{total, no_status, statuses}`.

---

### 2. ✅ New task with no explicit status is created with `status = null` — FIXED

`operations.md` §13.1 says: *"On create, the task's status defaults to the org's
default `ProjectTaskStatus` when omitted."* It does not — the created task keeps
`status: null` / `status_name: null` **permanently** (re-fetching the row later
still shows null; it's not an async lag).

Repro:

```bash
POST /api/v1/projects/tasks/  { "subject": "x", "project": "<uuid>" }
# → 201 with "status": null, "status_name": null

GET /api/v1/projects/tasks/<new_id>/
# → still "status": null  (never backfilled)
```

Impact: a freshly added task renders with no status pill and is ambiguous for
the "done" checkbox logic (the FE has to treat null-status as "not done"). The
lane's `done_count`/`task_count` still counts it, so the row looks stateless.

Request: on create, when `status` is omitted, assign the org's default
`ProjectTaskStatus` (the `is_default` / first-by-position open status) and return
it in the create response (`status` + `status_name` populated).

**Done when:** `POST /tasks/` without `status` returns a non-null `status` +
`status_name` equal to the org's default task status.

**✅ RESOLVED:** root cause was that orgs seeded via the management command had
**no `is_default` status row** (the org-registration signal sets one; the seeder
did not). Fix is three-part: (1) `perform_create`/`bulk_create` now fall back to
the first **open** (`is_closed=false && is_cancelled=false`) status by position
when no `is_default` exists; (2) the seeder marks "Open" as `is_default`; (3) the
dev DB was backfilled (10 orgs). Verified: `POST /tasks/` without `status` →
`status_name: "Open"`.

---

### 3. ✅ Slim representation for the tasks list (`?view=list`) — DONE

The Tasks tab loads `GET /projects/tasks/?project=<id>` and each row is **51
fields**, of which the lane UI reads ~13 (`task_id, subject, task_group,
status_name, is_milestone, pending_dependency_count, is_overdue,
computed_progress, assigned_to, exp_end_date, priority`). The rest — costing/
billing totals, template/parent linkage, duration/time bookkeeping, three nested
user objects — are never rendered on this screen and can be a large number of
rows for a busy project.

Repro:

```bash
GET /api/v1/projects/tasks/?project=<id>&page_size=1
# → each result has 51 keys; ?view=list has no effect (still 51)
```

Request: honor a `?view=list` (or `?fields=`) trim on the tasks list serializer
— the same pattern already added for projects (round-1 item 4) — returning just
the lane-relevant fields. `assigned_to` can collapse to `{user_id, full_name}`
(or a `assigned_to_name` label like the project row's `manager_name`).

**Done when:** `GET /tasks/?project=<id>&view=list` returns a documented slim row
(~13 fields), and the full shape stays on the detail retrieve.

**✅ RESOLVED:** `TaskListSerializer` (a 19-field projection) is returned for
`GET`/`QUERY` list when `?view=list`; the retrieve keeps the full shape.
`assigned_to` collapses to `{user_id, full_name}`; `assignees` keeps its
embedded stack. Verified: 51-key full row → 19-key slim row. Documented in
operations-task.md §1 (Representation).

---

### 4. ✅ Detail retrieve heavier than the panel needs — DONE (4a confirmed, 4b shipped)

The project **retrieve** (`GET /projects/projects/{id}/`) returns the full object
plus `task_count`/`done_count`. Two asks:

- **(a)** The `task_count`/`done_count` rollups should be computed with a single
  aggregate query, not per-request task iteration. Please confirm they're
  annotated (`Count(... filter=...)`) rather than N+1. (Can't verify from the
  client; flagging so it's checked.)
- **(b)** The detail panel reads the same ~20 fields the slim list row exposes,
  plus `description`, `assignees`, `assigned_team_name`, `visibility`,
  `estimated_costing`, `percent_complete_method`, `task_count`, `done_count`. The
  reminder/email schedule block (`first_email`, `weekly_time_to_send`, `subject`,
  `message`, `from_time`, …) is never shown on detail either — a `?view=detail`
  trim (or folding those into a separate "reminders" sub-resource) would slim it.

**Done when:** rollups are single-query (confirmed), and optionally a
`?view=detail` projection drops the reminder/schedule + costing-internals block.

**✅ RESOLVED:**
- **(a)** Confirmed single-query — `ProjectViewSet.get_queryset` annotates
  `task_count`/`done_count` via `Count("task", filter=…, distinct=True)` on
  retrieve only (no per-row iteration, no N+1).
- **(b)** `?view=detail` (retrieve) returns `ProjectDetailSerializer`, which
  drops the reminder/schedule block and the internal costing/margin totals while
  keeping every panel field. Verified those keys are absent under `?view=detail`
  and present on the default retrieve. Documented in operations.md §9.

---

### 5. ✅ Activity feed: pre-humanized `summary` + `event_type` — DONE

The audit feed (`GET /projects/projects/{id}/activity/`) returns raw `changes`
diffs that the client must humanize. Most rows are child rollups
(`{"related_change": {"type": "Task", "action": "create", "label": "…"}}`);
others are direct field diffs (`{"status": "Active"}`). The client currently
branches on key names to produce "Task created …" / "Status set to …" strings.

Request (nice-to-have, not blocking): include a server-rendered
`summary`/`description` string (and optionally a stable `event_type` enum:
`created | field_changed | child_created | child_updated | child_deleted | …`)
alongside `changes`, so every client renders the same wording and icon without
re-implementing the humanizer. Keep `changes` for detail/tooling.

**Done when:** each activity row carries a `summary` string + `event_type` enum;
`changes` stays for the raw diff.

**✅ RESOLVED:** the project `activity` action now serializes with
`ProjectActivitySerializer`, adding `summary` (human string) and `event_type`
(`created | updated | field_changed | deleted | child_created | child_updated |
child_deleted`). `changes` is unchanged (raw diff). The shared org-wide
`AuditLogSerializer` was NOT modified — this is project-activity-only. Documented
in operations.md §10.

---

### 6. ✅ Project task statuses live under a non-obvious path — DOC FIXED

The statuses used to complete/reopen a task are at
**`GET /api/v1/projects/project-task-statuses/`** (fields
`project_task_status_id`, `status`, `position`, `is_closed`, `is_cancelled`).
`operations.md` §13.1 implies they come from the tasks viewset; `/projects/
task-statuses/` 404s and `/crm/crm-task-statuses/` is a different (CRM) resource.

Request: document the correct endpoint in §13 (the FE resolves the complete
target as the first `is_closed && !is_cancelled` status and reopen as the first
`!is_closed`), so the "which status uuid do I PATCH?" step is discoverable.

**Done when:** §13 links `project-task-statuses/` and names the
`is_closed`/`is_cancelled` flags used for complete vs reopen.

**✅ RESOLVED (doc):** operations.md §13.4 now documents
`GET /api/v1/projects/project-task-statuses/`, the exact path (vs the two
404/wrong siblings), the row shape, and the client-side complete/reopen/default
resolution rules.

---

### 7. ✅ View-settings trim contract for retrieve/list — DOC FIXED

With an org `list`/`detail` view-settings config present, the project responses
are server-trimmed to configured-visible columns + mandatory companions — good,
and the FE relies on it. Two clarifications for the doc:

- The `/schema/` response's `all_fields` is currently `{columns, sorting,
  filters}` (a config bag), **not** the per-field catalog the doc's §5A.1 example
  shows (a dict of every built-in column). An "add column" picker can't read from
  it as documented. Please either return the field catalog under `all_fields`, or
  correct the doc.
- The default-visible **list** columns returned live were `project_name, status,
  customer, priority, manager, expected_end_date` — the doc lists
  `percent_complete` and `project_type` as default-visible too, but they weren't
  present. Align the doc's "default visible" list with what the seeder produces.

**Done when:** `all_fields` shape matches the doc (or the doc matches it), and
the documented default-visible list columns match the seeded config.

**✅ RESOLVED (doc):** the doc was corrected to match the (richer) real shape —
`all_fields` is the `{columns, sorting, filters}` bag, and the "add column"
picker reads **`all_fields.columns`** (each entry carries `visible`, `order`,
`is_protected`, `in_fields`, and nested `field_info`). The default-visible list
columns were aligned to the seeded org config
(`project_name, status, customer, priority, manager` + `expected_end_date` last);
`percent_complete`/`project_type` are in the catalog but hidden by default.
operations.md §5A.1 + §11 updated. No backend change — the catalog already exists
under `all_fields.columns`.

---

### 8. ✅ `computed_progress` numeric consistency — FIXED

`percent_complete` on projects is now a JSON number (fixed round-1). The task
row's `computed_progress` is still a decimal **string** (`"39.000000"`). Minor:
return it as a number too, for consistency across the two progress fields.

**Done when:** `computed_progress` is a JSON number on task rows.

**✅ RESOLVED:** `TaskSerializer.computed_progress` now uses
`coerce_to_string=False` → emits a JSON number (`39.0`) on task rows, matching
`percent_complete`. Verified over HTTP.

---

## Verified-working (no action needed — regression checklist)

- **List:** uniform `__in`/`__not_in` merge; `status-counts/` (GET) composes with
  search / facets / `saved_filter_id` and strips status params itself;
  `ownership=me`, `include_archived`, `customer_isnull`, `search`, `ordering`
  (unknown ignored), pagination; `?view=list` slim rows; QUERY body wins over URL.
- **Saved filters:** 5-cap, duplicate-name 400, unknown-key 400,
  empty-definition 400, per-user isolation, array + CSV-string values apply,
  malformed stored value → 400 inert, `saved_filter_id` + explicit-param override.
- **Detail:** retrieve rollups (`task_count`/`done_count`) reflect writes;
  task-groups carry per-lane `task_count`/`done_count`; task create / complete
  (`{status}`) / reopen / milestone (`{is_milestone}`) / move lane
  (`{task_group}`) / delete; group create / rename / delete (SET_NULL to "No
  group") / `reorder/`; a completed task's counts propagate to both the lane and
  the project rollup; activity logs each write; `project-attachments/?project=`
  scoping; notes via the shared `/crm/notes/?related_to=project`.

---

# Backend requests — Notifications (inbox + settings)

Context: integrating the **Notification inbox** (bell slide-over) and the
**Notifications Settings** page (`docs/backend/push-notifications.md`, §1–21).
All endpoints below were live-verified against `/api/v1/` (org `newversion`,
2026-07-27). Two discrepancies with the doc surfaced; everything else works.

Legend: 🔴 correctness · 🟡 efficiency / payload · 🟢 minor / nice-to-have.

---

## ✅ Shipped (notifications round 1 — verified fixed 2026-07-27)

Both open items are **live and verified**.

| # | Item | Status |
|---|---|---|
| N1 | `?category=` returns 0 for real data | ✅ Fixed at the root: the category map is now **derived** from the settings-page groups, 3 undeclared types were declared, the snake_case type was normalised (with a data migration), and every row now carries a `category` field. |
| N2 | `PATCH /settings/notifications/channels/` → 405 | ✅ `PATCH` implemented as a true partial update on the shared settings base view (fixes all 7 org-settings endpoints, not just channels). |

Regression coverage: `crm/tests/test_notification_category_and_patch.py` (15 tests).
Doc updated: `docs/working/push-notifications.md` §1, §17, §22.

**✅ FE consumed (verified live 2026-07-27):** both fixes are now wired.
- **N1:** the inbox reads the new `category` field and shows **category chips**
  (All / CRM / Projects / Billing / System) as the primary filter, with a status
  segment (All / Unread / Pinned / Snoozed) beneath. Both facets compose
  (`category=crm&status=unread` → 633 rows, all `category:crm` + `unread`). The
  settings matrix auto-picked up the three new sub-groups/events (49 events now)
  since it renders from the server `groups` — no client change needed.
- **N2:** `saveChannels` now sends a direct `PATCH` of just the changed flag; the
  read-modify-write full-body `PUT` workaround (and its lost-update race) is gone.
  Verified `PATCH {sms_enabled:true}` leaves the other four flags intact.

---

## N1 ✅ `?category=` (and `category__in`) returned **0** for the real data set — FIXED

**What the doc says (§1):** `category` filters the inbox by a module group
(`crm`/`pmo`/`lms`/`system`), where each group maps to a fixed list of `type`
values (`LeadAssigned`, `TaskAssigned`, …).

**What happens:** with 689 live notifications, `?category=crm` (and every other
category) returns `count: 0`. The stored `type` values in the DB don't match the
group tables in the doc — real rows carry types like `StaleLeadAlert`,
`ProjectUpdateFiled`, `ProjectUpdateReminder`, `ProjectCommentAdded`,
`quotation_expiry_reminder` (note the **mixed casing** — some PascalCase, some
snake_case), none of which appear in any category's included-types list.

```bash
# 689 notifications exist:
curl -s ".../crm/notifications/" -H "$AUTH" | jq .count          # → 689
# but every category is empty:
curl -s ".../crm/notifications/?category=crm" -H "$AUTH" | jq .count   # → 0
curl -s ".../crm/notifications/?category=pmo" -H "$AUTH" | jq .count   # → 0
# distinct real types (first 200):
#   180 StaleLeadAlert · 6 ProjectUpdateFiled · 4 quotation_expiry_reminder
#   4 ProjectUpdateReminder · 4 ProjectCommentAdded · 1 ProjectDeadlineApproaching · 1 PmoTaskAssigned
```

**Ask:** reconcile the category type-maps with the emitted `type` values — either
(a) add the actually-emitted types (`StaleLeadAlert`, `ProjectUpdateFiled`,
`ProjectUpdateReminder`, `ProjectCommentAdded`, `quotation_expiry_reminder`, …)
to the right category groups, and normalise casing, **or** (b) expose a
server-computed `category` field on each notification object so the client can
group without a fragile client-side type→category map. A returned `category`
field on the row is preferable — the FE then never hard-codes the mapping.

**Done when:** `?category=crm` returns the CRM notifications for the live data,
and/or each notification object carries a `category` field.

**✅ RESOLVED — both (a) and (b) were done, plus the root cause.**

Root cause: `CATEGORY_TYPE_MAP` in `crm/filters/notification.py` was a **hand-
maintained second copy** of the taxonomy already expressed by
`NOTIFICATION_EVENT_GROUPS`. Every event added since it was written was added to
one and not the other, so the map silently fell behind the emitted types. Three
of the reported types (`StaleLeadAlert`, `NoteMention`,
`quotation_expiry_reminder`) weren't even declared as model constants — they were
free-string `dispatch_notification(event_type="…")` calls, so nothing validated
them.

Four-part fix:

1. **Declared the missing types** as `CRMNotification` constants and added them to
   `TYPE_CHOICES`: `StaleLeadAlert`, `NoteMention`, `QuotationExpiryReminder`.
   They are now valid choices, so a future free-string typo is caught.
2. **Normalised the casing.** `quotation_expiry_reminder` →
   `QuotationExpiryReminder` at the emitter (`quotations/tasks.py`), with a
   **data migration** (`crm/0041`, reversible) renaming existing rows. All other
   types were already PascalCase, so casing is now uniform.
3. **Derived the category map from the groups** — `NOTIFICATION_CATEGORY_TYPE_MAP`
   is built from `NOTIFICATION_EVENT_GROUPS` at import time, and
   `crm/filters/notification.py` just re-exports it. Adding an event to a
   settings-page group now makes it filterable automatically; the two **cannot
   drift apart again**. A test asserts every declared type maps to a category.
4. **Added the `category` field to the row** (the FE's preferred fix) on both the
   list and detail serializers, so no client hard-codes the mapping.

Also folded the previously-ungrouped events into the settings-page sections so
they're toggleable: `StaleLeadAlert`, a new CRM "Notes & Quotations" sub-section
(`NoteMention`, `QuotationExpiryReminder`), and `ProjectCommentAdded` /
`ProjectUpdateFiled` / `ProjectUpdateReminder` under PMO → Projects. A `billing`
category was added for the §21 billing events.

Verified against the dev DB (5,551 notifications, 16 distinct types): **0 rows
map to a null category**; `?category=crm` / `pmo` / `system` / `billing` / `lms`
all return their rows. Category totals: crm 19 types, pmo 14, billing 7, lms 5,
system 3.

---

## N2 ✅ `PATCH /settings/notifications/channels/` → **405 Method Not Allowed** — FIXED

**What the doc says (§17):** lists `GET`, `PUT`, **and** `PATCH` on
`/api/v1/settings/notifications/channels/`.

**What happens:** `PATCH` returns `405 {"message":"Method \"PATCH\" not
allowed."}`. Only `GET` and `PUT` are wired. `PUT` works but expects the **full**
channel body (a partial `PUT` with just `{email_enabled}` echoes only the fields
sent).

```bash
curl -s -X PATCH ".../settings/notifications/channels/" -H "$AUTH" \
  -d '{"email_enabled":true}'                     # → 405 Method "PATCH" not allowed.
curl -s -X PUT ".../settings/notifications/channels/" -H "$AUTH" \
  -d '{"in_app_enabled":true,"push_enabled":true,"email_enabled":false,"sms_enabled":false,"whatsapp_enabled":false}'  # → 200 OK
```

**Ask:** either enable `PATCH` (partial update) as documented, or drop `PATCH`
from the §17 doc. The FE currently sends a full-body `PUT` (reads current state,
flips one flag, writes all five back) as a workaround, which risks a lost-update
race if two admins edit concurrently — a real `PATCH` would be cleaner.

**Done when:** `PATCH /channels/` applies a partial update, **or** the doc no
longer advertises `PATCH`.

**✅ RESOLVED:** `PATCH` is implemented — the doc was right, the code was missing
it. The verb was added to the shared `_OrgSettingsView` base rather than to the
channels view alone, so **all seven org-settings endpoints** that inherit from it
(platform defaults, lead/task/follow-up automation, security policy, data
management, quotations, notification channels) gain partial update consistently.

Semantics: `PATCH` merges the posted keys over the **stored** config, then
validates the *merged* document with the full serializer — so a partial write can
never persist a config the full serializer would reject, and an invalid value
still 400s. The response echoes the complete body (all five channel flags), not
just the keys sent. `PUT` is unchanged and still replaces the whole document.

This removes the FE's read-modify-write workaround and its lost-update race:
`PATCH {"email_enabled": true}` now leaves the other four flags untouched.

---

## Verified-working (Notifications — no action needed)

- **Inbox:** list + pagination (`count`/`next`/`results`, 100/page); `status`,
  `status__in` (repeated), `is_read`, `type`/`type__in` filters; `pinned/` and
  `snoozed/` sub-lists; detail GET (auto-marks read, returns the extra
  `from_user_email`/`source_content_type`/`created_by`/`updated_by` fields).
- **Inbox mutations:** `mark-read/`, `mark-all-read/`, `pin/`+`unpin/`,
  `snooze/` (future-datetime validated) + `unsnooze/`, and the bulk variants
  `bulk-pin`/`bulk-unpin`/`bulk-snooze`/`bulk-unsnooze`/`bulk-delete` (all take
  `{ids:[…]}`, silently ignore foreign ids).
- **Settings channels:** `GET` + `PUT` (full body) round-trip.
- **Settings org matrix:** `GET /crm/notification-preferences/matrix/` returns
  `groups`/`labels`/`descriptions`/`matrix`/`recipients`/`recipient_choices`/
  `channels`/`event_types` (46 events across CRM/PMO/System/Billing sections);
  `PUT` upserts `matrix[event][channel]` + `recipients[event]` and echoes the
  resolved state (`true` deletes the opt-out row, `false` mutes) — round-trip
  verified on `PaymentFailed`.
- **Per-user matrix:** `GET /crm/my-notification-preferences/matrix/` returns the
  effective matrix with no `recipients` key (as documented).

---

# Backend requests — Operations → Tasks (detail page + row/bulk actions)

Context: integrating the **Task detail page** (`docs/backend/operations-task.md`
§3, §3A–§3E) and the list-row / bulk actions (§5). Endpoints live-verified
against `/api/v1/projects/` (org `newversion`, 2026-07-27). One correctness bug
found; everything else works.

Legend: 🔴 correctness · 🟡 efficiency / payload · 🟢 minor / nice-to-have.

---

## ✅ Shipped (tasks round 1 — verified fixed 2026-07-27)

All four items are **live and verified**.

| # | Item | Status |
|---|---|---|
| T1 | Depended-on task delete → 500 | ✅ Now a structured **409** naming the blocking tasks (`blocking_tasks[]`). |
| T2 | `?related_to=project_task` read → 0 rows | ✅ Reads now resolve the **same discriminator map** writes use. Also fixes a latent bug: `?related_to=task` used to mix `crm.Task` and `projects.Task` rows. |
| T3 | Attachment delete keyed by numeric `id` | ✅ UUID `attachment_id` now works; the numeric pk still resolves, so nothing breaks mid-flight. |
| T4 | Partial PATCH re-validates untouched fields | ✅ Cross-field date rules now raise only for fields the request touched. |

Regression coverage: `projects/tests/test_task_frontend_round3.py` (22 tests —
each one fails on the pre-fix tree and passes after).

**✅ FE consumed (verified live 2026-07-27):** all four fixes are wired.
- **T1:** the task-detail delete surfaces the 409's specific blocker message
  (`errors.dependencies[0]`, e.g. *"'Write unit tests' depend(s) on this task…"*)
  via toast, replacing the generic fallback.
- **T2:** the Task detail page now uses the **shared `NotesPanel`
  `recordType="project_task"`** (symmetric read/write) — the task-specific notes
  reader was removed. Files read with `related_to=project_task` too.
- **T3:** task files use the UUID `attachment_id` as the delete key.
- **T4:** the row/detail milestone·priority·status edits no longer trip the
  stale-date 400 — verified a milestone-only PATCH on the previously-failing seed
  row now returns 200.

---

## T1 ✅ `DELETE /projects/tasks/{id}/` on a **depended-on** task → **500 ProtectedError** — FIXED

**What the doc says (§3D):** *"Deleting a task that another task depends on is
**blocked** (`PROTECT`) — remove the edge first, so unblocking is never silent."*
That implies a handled, user-facing **4xx** ("remove the edge first"), the way
the completed-lock (§3A) and cycle checks (§3D) return structured `400`s.

**What happens:** the delete raises Django's `ProtectedError` **uncaught**, so DRF
returns an **HTTP 500** with a debug traceback page (`ProtectedError at
/api/v1/projects/tasks/{id}/`), not a JSON error body. There is no message the
client can surface — it just looks like a server crash.

Deterministic repro (verified twice):

```bash
# A depends on B  (B is a "blocker" of A)
POST /api/v1/projects/task-dependencies/  {"task": "<A>", "depends_on": "<B>"}
# now try to delete B while the edge exists:
DELETE /api/v1/projects/tasks/<B>/        # → HTTP 500  ProtectedError (HTML traceback)
# removing the edge first works cleanly:
DELETE /api/v1/projects/task-dependencies/<edge_id>/   # → 204
DELETE /api/v1/projects/tasks/<B>/                     # → 204
```

**Ask:** catch `ProtectedError` in the task destroy path and return a `400`/`409`
with a JSON body naming the blocking edge(s) — e.g.
`{"errors": {"dependencies": ["Task X depends on this task. Remove the
dependency first."]}}` — mirroring the §3A/§3D structured-error style. The FE can
then show the same "remove the edge first" toast it shows for the other guarded
deletes, instead of a generic 500.

**Done when:** deleting a depended-on task returns a structured 4xx (no 500 / no
HTML traceback), and the response identifies the blocking dependency.

**FE handling in the meantime:** the task-detail delete treats a 500 from this
endpoint defensively (generic "resolve dependencies/subtasks first" message) so
the crash never surfaces raw, but it can't name the specific blocker until the
4xx lands.

**✅ RESOLVED:** `TaskViewSet.destroy` now catches `ProtectedError` and returns
**409 Conflict** (not 400 — the request is valid, the resource state conflicts)
with the blocking tasks named:

```jsonc
// DELETE /api/v1/projects/tasks/<B>/   → 409
{
  "detail": "Cannot delete this task because other tasks depend on it.",
  "errors": { "dependencies": ["'Design freeze' depend(s) on this task. Remove the dependency first."] },
  "blocking_tasks": ["Design freeze"]     // ← names, capped at 10, for the toast
}
```

The task is left intact. Deleting the **dependent** side is unaffected (only the
blocker is PROTECT-ed), and removing the edge first still gives a clean 204.
You can now show the specific blocker instead of the generic fallback.

---

## Verified-working (Tasks detail + actions — no action needed)

- **§3 Detail retrieve** (`GET /projects/tasks/{id}/`): all detail-only fields
  present — `task_code` (e.g. `PRJ-1009-t5`), `subtask_count`/
  `subtask_done_count`, `dependencies[]`/`dependents[]` (resolved chip shape with
  `task_depends_on_id`+`subject`+`status_name`+`is_closed`), `department`,
  `color`, `is_milestone`, `description`, `comment_count`, `computed_progress`.
- **§3A Completed-lock:** `PATCH` of a non-status field on a closed task → `400`
  with the per-field lock message; `PATCH {status:<open>}` reopens (and may carry
  other edits in the same call).
- **§3B Activity:** `GET /projects/tasks/{id}/activity/` → paginated, newest-
  first, `summary`+`event_type` per row (same shape as the project feed).
- **§3C Subtasks:** list via `?parent=<id>&view=list`; create via `POST` with
  `{parent_task, subject, project}` (returns populated `status_name`); parent's
  `subtask_count`/`subtask_done_count` reflect the write; tick-done via
  `PATCH {status:<closed>}`.
- **§3D Dependencies:** `GET /task-dependencies/?task=` (waiting-on) /
  `?depends_on=` (blocking); `POST {task, depends_on}` creates the edge (returns
  the resolved `subject`); `DELETE /task-dependencies/{edge_id}/` → 204. (Only
  the depended-on-**task** delete 500s — see T1.)
- **§5 Row CRUD:** create (`POST`, `subject` required, status/`task_code`
  minted), edit (`PATCH`, partial), milestone toggle (`{is_milestone}`), inline
  status change / reopen, delete.
- **§5 Bulk:** `bulk-status/` → `{success, updated, errors}`; `bulk-delete/` →
  `{success, deleted}`; (`bulk-assign/`, `bulk-create/` documented, same
  collection).

---

## T2 🟡 Notes & attachments: `?related_to=project_task` **read** returns 0 (write ok, read needs `task`)

**Context (§3E):** the doc already flags a write/read asymmetry for the shared
notes/attachments endpoints — write discriminator is **`project_task`**, and on
read *"the notes filter matches the bare content-type model name, so
`?related_to=task` matches both models — always pass `related_to_id`."*

**What we hit:** the asymmetry is stronger than the doc implies and it breaks the
**shared `NotesPanel`** (and any generic attachments reader), which sends the
*same* `related_to` value on read as on write:

```bash
# WRITE with project_task → 201, stored under content-type model "task"
POST /crm/notes/        {"content":"…","related_to":"project_task","related_to_id":"<task>"}   # related_to_model: "task"
POST /crm/attachments/  (multipart) related_to=project_task related_to_id=<task>               # related_to_model: "task"

# READ with the SAME discriminator → 0 rows
GET /crm/notes/?related_to=project_task&related_to_id=<task>          # count: 0   ← empty
GET /crm/attachments/?related_to=project_task&related_to_id=<task>   # count: 0   ← empty

# READ with related_to=task → the rows appear
GET /crm/notes/?related_to=task&related_to_id=<task>                 # count: 1  ✓
GET /crm/attachments/?related_to=task&related_to_id=<task>          # count: 1  ✓
```

So a client that writes with `project_task` and reads with `project_task` (the
natural symmetric usage — exactly what the shared `NotesPanel recordType` does)
sees its own just-created note/file vanish.

**Ask:** make the **read** filter accept `related_to=project_task` as an alias for
the `task` content-type (symmetric with write). Then the shared panel works for
project tasks with a single `recordType="project_task"`, no special-casing. (If
symmetric read isn't feasible, please document explicitly that reads must use
`related_to=task` + `related_to_id`, and we'll keep the task-specific reader.)

**Done when:** `GET /crm/notes/?related_to=project_task&related_to_id=<task>` (and
the same for `/attachments/`) returns the rows written with `project_task`.

**FE handling in the meantime:** the Task detail page uses a **task-specific**
notes/files reader (`related_to=task` on read, `related_to=project_task` on
write) instead of the shared `NotesPanel`, so notes/files show correctly today.

**✅ RESOLVED — symmetric read, and a latent bug fixed along the way.**

The read filter matched the raw `content_type__model` string, which is never
`project_task`. It now resolves the value through the **same discriminator map
writes use** (`GENERIC_RELATION_MODEL_MAPPING`), so read and write accept exactly
the same vocabulary. Applied to **both** `/crm/notes/` and `/crm/attachments/`
via a shared mixin (`crm/filters/generic_relation.py`).

Your investigation surfaced something more serious than the asymmetry: `crm.Task`
and `projects.Task` **both** have content-type model `"task"`, so the documented
workaround `?related_to=task` was returning **CRM task notes and PMO task notes
mixed together** — `related_to_id` narrowed it to one record but the model
ambiguity was real. Now each discriminator maps to exactly one model:

| `related_to` | Resolves to |
|---|---|
| `project_task` | `projects.Task` (PMO) — **use this for the task detail page** |
| `task` | `crm.Task` (CRM interactions) |
| `lead`, `customer`, `project`, … | unchanged |

**You can now switch the Task detail page to the shared `NotesPanel` with
`recordType="project_task"`** — same value on read and write, no special-casing.

Notes:
- Bare model names still work for back-compat (`?related_to=lead`).
- An unknown value now returns **0 rows** instead of silently ignoring the filter
  and returning everything — a safer failure mode.
- The §3E doc caveat in `operations-task.md` has been updated accordingly.

---

## T3 🟢 Attachment **delete** is keyed by the numeric `id`, not the UUID `attachment_id`

`GET /crm/attachments/` rows carry both a UUID `attachment_id` and a numeric `id`.
`DELETE /crm/attachments/{attachment_id}/` (the UUID) → **404**;
`DELETE /crm/attachments/{id}/` (the numeric pk) → **204**. Every other CRM
resource is addressed by its UUID, so this is a surprise. Not blocking (the FE
uses the numeric `id`), but worth aligning to UUID addressing for consistency, or
documenting.

**Done when:** attachment delete accepts the UUID `attachment_id` (or the doc
states the numeric `id` is the delete key).

**✅ RESOLVED:** `AttachmentViewSet` had no `lookup_field`, so DRF fell back to
the numeric pk while every sibling viewset (Note → `note_id`, Lead → `lead_id`, …)
uses its UUID. It now declares `lookup_field = "attachment_id"`, so
`GET`/`DELETE /crm/attachments/{attachment_id}/` work as expected.

**The numeric `id` still resolves** — `get_object` accepts either form — so your
current code keeps working and you can migrate to the UUID whenever convenient.
An unknown id 404s either way.

---

## T4 🟡 Partial `PATCH /tasks/{id}/` re-validates untouched fields → a single-field edit can 400 on stale data

A minimal `PATCH` — e.g. the list-row **milestone toggle** sending only
`{"is_milestone": true}` — is rejected `400` when an **untouched** stored field
is inconsistent with the project. Live example (real seed row): its stored
`exp_end_date` (2026-09-16) is after the project's expected end (2026-09-13), so:

```bash
PATCH /api/v1/projects/tasks/<id>/  {"is_milestone": true}
# → 400 {"errors": {"exp_end_date": ["Task cannot end after the project's expected end date (2026-09-13)."]}}
```

The client never sent `exp_end_date`, yet the whole record is re-validated and the
edit is blocked on a field the user didn't touch. (The same one-field PATCH
succeeds on a task whose stored dates are consistent — so it's the cross-field
re-validation, not the `is_milestone` write itself.)

**Ask:** scope cross-field validators to the fields actually present in a partial
`PATCH` (or validate the merged doc but only *raise* for fields in the request +
their genuine dependencies). A metadata edit like milestone / priority / assignee
shouldn't fail because of a pre-existing date discrepancy the user isn't editing.

**Done when:** `PATCH {"is_milestone": true}` (and other single non-date fields)
succeeds regardless of a stored `exp_end_date` vs project-end mismatch.

**FE handling in the meantime:** row/detail edits surface the backend's field
error via a toast, so the user sees *why* it failed — but they can't fix a date
they didn't mean to edit from the milestone toggle. No client workaround; needs
the scoping fix.

**✅ RESOLVED:** the cross-field date validators fell back to the *stored* values
for anything absent from the request, so every PATCH re-validated the whole
record and a pre-existing inconsistency blocked unrelated edits.

The rules still evaluate against the **merged** document (a partial edit can't
sneak an invalid date past them), but they now only **raise** when the request
actually touches the date scope — i.e. when `exp_start_date`, `exp_end_date`, or
`project` is in the payload:

| Request | Before | After |
|---|---|---|
| `{"is_milestone": true}` on a task with a stale stored date | ❌ 400 on `exp_end_date` | ✅ 200 |
| `{"priority": "Low"}`, `{"assigned_to": …}`, etc. | ❌ 400 | ✅ 200 |
| `{"exp_end_date": <past project end>}` | ❌ 400 | ❌ 400 (unchanged) |
| `{"exp_start_date": …, "exp_end_date": …}` inverted | ❌ 400 | ❌ 400 (unchanged) |
| `POST` (create) with a bad date | ❌ 400 | ❌ 400 (unchanged — creates validate in full) |

`project` counts as touching the date scope: moving a task to a project with a
tighter window is exactly what makes its existing dates invalid, so that case is
still checked.

Metadata edits — milestone, priority, assignee, status, task group — no longer
fail on dates the user isn't editing.

---

# Backend requests — Admin dashboard (`/crm/dashboard-new/`)

Context: the frontend has integrated the **Overview → Dashboard → Admin** tab
against the nine `/api/v1/crm/dashboard-new/` endpoints (KPIs, total receivables,
top customers, pipeline snapshot, revenue trend, critical overdue projects, stuck
items, + teams/users dropdowns). Every widget is live. Two payload gaps below make
a widget fall back rather than render its intended full state — both are 🟡/🟢, not
blockers. All findings verified live against org `newversion` with `scope=admin`.

Legend: 🔴 correctness · 🟡 efficiency / payload · 🟢 minor / nice-to-have.

---

## D1 🟡 Pipeline snapshot returns **counts only** — the "₹ Value" tab has no data

`GET /crm/dashboard-new/pipeline-snapshot/?scope=admin` returns each stage with a
`count` but **no per-stage ₹ value**:

```bash
curl -s "$BASE/crm/dashboard-new/pipeline-snapshot/?scope=admin" -H "$AUTH" \
  | python3 -c "import json,sys; print(list(json.load(sys.stdin)['crm']['stages'][0].keys()))"
# → ['lead_status_id', 'name', 'color', 'position', 'count']   ← no 'value'
```

The Pipeline snapshot card has a **₹ Value / Count** toggle. With value absent, the
FE can only show counts, so it **hides the toggle** and labels bars by count.

**Ask:** add a `value` field (open-lead product value ₹ per stage, 2-dp string) to
each `crm.stages[]` entry, matching the money convention used elsewhere in these
endpoints. The doc's own §4 note already flags this as a known gap ("if that's
required… we'll add a `value` field to each stage").

**Done when:** each stage object includes `"value": "1840000.00"` and the FE can
restore the ₹ Value/Count toggle.

**FE handling in the meantime:** the card renders counts and suppresses the toggle
in live mode — no error, just the Count view only.

**✅ RESOLVED:** each `crm.stages[]` entry now carries `"value"` (2-dp string) — the
open-lead product value in that status (open = not archived/converted/lost, matching
the KPI "Sales Pipeline" definition, so per-stage values are consistent with that
total). Computed in the admin-only `get_pipeline_snapshot` wrapper (one extra grouped
query keyed by `lead_status_id`); the shared count-only `get_pipeline_data` is
untouched. Seed leads had **no products** (so values were legitimately `0.00`) — a
`backfill_lead_products` command attached 1–3 existing priced products to each of the
266 product-less leads across 5 orgs, so the toggle now shows real ₹ per stage.
Verified live (`newversion`, `scope=admin`): stage values non-zero, e.g. New
₹101,785 · Contacted ₹176,974. Restore the ₹ Value/Count toggle.

---

## D2 🟢 Top customers "₹ Value" list has no per-customer **dues** → Dues tab duplicates Value

`GET /crm/dashboard-new/top-customers/?scope=admin` → `top_by_value[]` carries only
the total value:

```bash
curl -s "$BASE/crm/dashboard-new/top-customers/?scope=admin" -H "$AUTH" \
  | python3 -c "import json,sys; print(list(json.load(sys.stdin)['top_by_value'][0].keys()))"
# → ['customer_id', 'name', 'total_value']   ← no 'dues'/'outstanding_amount'
```

The **Top customers** card has a **₹ Value / Dues** toggle. `top_outstanding[]` does
carry `outstanding_amount`, but it's a *different* (overdue-ranked) top-5 list, so
the Dues figure can't be joined onto the value-ranked rows reliably. With no dues on
`top_by_value`, the FE's Dues tab currently shows the same figure as Value.

**Ask:** add an `outstanding_amount` (or `dues`, 2-dp string) field to each
`top_by_value[]` row — the customer's current outstanding receivable — so the Dues
tab reflects real dues for the value-ranked customers.

**Done when:** each `top_by_value[]` row includes `"outstanding_amount": "…"` and the
FE's Dues toggle shows dues distinct from value.

**FE handling in the meantime:** the Dues tab falls back to the value figure (no
wrong data surfaced elsewhere; the ₹ Value tab is fully correct).

**✅ RESOLVED:** each `top_by_value[]` row now carries `"outstanding_amount"` (2-dp
string) — the customer's current overdue receivable (`0.00` when none), so the Dues
toggle reflects real dues on the value-ranked customers. Computed in one grouped query
over just the ≤5 value-ranked customer ids (no N+1). Verified live (`newversion`,
`scope=admin`): e.g. NovaStar Industries `total_value` ₹439,994 vs `outstanding_amount`
₹139,998.67 — distinct figures. The ₹ Value / Dues toggle now shows correct dues.

---

# Backend requests — Security Settings (`/settings/security/*`, `/auth/*`)

Context: the frontend integrated the Settings → **Security Settings** screen (password
reset via the email-link flow, org policy toggles, active sessions, self-serve TOTP
2FA) and the login-time 2FA branching (challenge / forced enrolment). The reset flow
and 2FA work end-to-end. Three items below were the doc's own "Known gaps" — surfaced
here so they're tracked. S3 is now fixed; S1/S2 remain open and the FE degrades
gracefully around each. Verified live against org `newversion`.

Legend: 🔴 correctness · 🟡 efficiency / payload · 🟢 minor / nice-to-have.

---

## S1 🟡 "Login alerts" toggle has **no backend** — no model, field, or endpoint

The Security screen shows a **Login alerts** toggle ("Email me about sign-ins from new
devices"), but there is no preference field, signal, or endpoint backing it anywhere —
nothing to read or persist.

**FE handling in the meantime:** the toggle is rendered **disabled** with a tooltip
("Not available yet — no backend support"), so it can't imply a setting that isn't
stored. It's kept in the UI only so the row isn't silently dropped.

**Ask:** add a per-user boolean preference (e.g. `notify_on_new_device_login`) with a
GET/PATCH endpoint and the new-device email itself, or confirm the row should be
removed from the screen entirely.

**Done when:** the toggle reads and persists a real preference and new-device sign-ins
send the alert email.

---

## S2 🟢 IP allow-list is **exact-match only** — no CIDR ranges

`GET /settings/security/policy/` returns `ip_whitelist`/`ip_blacklist` as exact-match
`IPAddressField` lists. The UI copy says "office IP **ranges**", but a CIDR like
`203.0.113.0/24` can't be stored — only individual addresses.

```bash
# policy shows plain IP lists, no range support
curl -s "$BASE/settings/security/policy/" -H "$AUTH" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('ip_whitelist:', d['ip_whitelist'])"
# → ip_whitelist: []   (each entry must be a single exact IP)
```

**FE handling in the meantime:** the IP allow-list row's copy was changed to "specific
office IPs (exact match, no ranges)" and the toggle only reflects whether the list is
non-empty; there is no range-entry UI (it would mislead).

**Ask:** store `ip_whitelist`/`ip_blacklist` as CIDR-capable values (or a list of
ranges) and enforce membership by network containment, so "office IP ranges" is honest.

**Done when:** a `/24` (or similar) can be saved and access is allowed/denied by range
membership.

---

## S3 ✅ Session **revoke is a silent no-op** — the token keeps working until it expires — FIXED

`POST /settings/security/sessions/<id>/revoke/` (and `…/revoke-all/`) return **200**,
but the revoked session stays usable: `UserSession.jti` holds the *access*-token JTI,
while SimpleJWT only creates `OutstandingToken`/blacklist rows for *refresh* tokens, so
the blacklist call matches nothing and the auth middleware passes the "revoked" session
through until the access token naturally expires (up to ~30 min).

```bash
# revoke returns 200 …
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "$BASE/settings/security/sessions/<other_session_id>/revoke/" -H "$AUTH"   # → 200
# … but a request with that session's still-unexpired access token keeps succeeding.
```

**FE handling in the meantime:** the Revoke / "Sign out others" actions are wired and
refresh the list, but the confirm copy is honest: *"a revoked session can stay usable
until its token expires (up to 30 minutes)."* We do **not** claim "signed out
everywhere."

**Ask:** make revoke actually terminate the session — e.g. check `UserSession.is_active`
in the auth middleware (reject inactive sessions immediately regardless of token
validity), or track the access-token JTI in a deny-list the middleware consults. Same
fix covers the post-password-reset "sessions not terminated" note in the doc.

**Done when:** after `revoke`, the next request carrying that session's access token is
rejected (401), not served until expiry.

**✅ RESOLVED:** `SessionInactivityMiddleware` (`settings/middleware.py`) already looked
up `UserSession` by `jti` on **every** authenticated request (it needed to, for the
inactivity-timeout check) — but it filtered `is_active=True` at the query level, so a
revoked session (`is_active=False`) and a never-tracked pre-feature token both resolved
to "no row found" and were treated identically: pass the request through. That's the
actual bug — not a missing check, but an existing check that couldn't distinguish
"never tracked" from "revoked."

Fix: query by `jti` alone (still `unique=True`, so at most one row), then branch
explicitly:

| Match | Before | After |
|---|---|---|
| No `UserSession` row for this `jti` | pass through | pass through (unchanged — pre-feature token) |
| Row exists, `is_active=True` | pass through | pass through (unchanged — normal session) |
| Row exists, `is_active=False` (revoked) | **pass through (the bug)** | **401** `{"detail": "Session has been revoked.", "code": "session_revoked"}` |

No changes needed to `revoke`/`revoke_all` themselves — they already correctly flip
`is_active=False`; the gap was entirely in the middleware never checking that flag when
a row *was* found. The response is a plain `JsonResponse` (not a DRF `Response`, since
this runs in Django middleware ahead of DRF) — the FE should read `response.json().code`
rather than `.data`.

Also covers the related password-reset "sessions not terminated" note elsewhere in this
doc for the same reason: any path that flips `UserSession.is_active = False` (revoke,
revoke-all, a future password-reset session-kill) is now enforced at the same
middleware layer, on the very next request — no separate fix needed per code path.

Verified: an active session's token keeps working (no false positive); a revoked
session's token is rejected on the **next** request after revoke, not after expiry; a
token with no tracked `UserSession` row at all still passes through untouched.
Regression test: `settings/tests/test_session_revoke.py` (3 tests).

**Done — but confirm the FE copy.** The "can stay usable until its token expires (up to
30 minutes)" language in the confirm dialog is no longer accurate — revoke now takes
effect on the session's very next request. Consider updating that copy to something
like "signs this device out immediately."

**✅ CONSUMED (frontend, 2026-08-02).** Verified live: after revoking another session,
that session's next request → `401 {"detail":"Session has been revoked.","code":
"session_revoked"}`; the actor's own token keeps working. FE changes:
- Confirm-dialog copy updated to "signs you out on every other device immediately —
  each is blocked on its next request."
- The Axios response interceptor (`core/http/httpClient.ts`) now special-cases a `401`
  whose body `code === "session_revoked"`: it **skips the silent-refresh retry** and
  tears the session down (`onAuthLost` → clear store → redirect to login). This is
  necessary because a **revoked session's refresh token still mints new access tokens**
  (verified: `POST /auth/login/refresh/` with the revoked session's refresh token →
  200) — those new tokens have a fresh JTI with no `UserSession` row, which the
  middleware treats as "pass through", so a normal refresh-on-401 would silently defeat
  the revoke. Skipping refresh on this specific code closes that loophole for the
  revoked device.
- Nice-to-have for the backend: also invalidate the **refresh** token when a session is
  revoked (blacklist it), so the revoked session can't mint a fresh, untracked
  access token at all. Not blocking — the FE guard covers the in-app case — but it would
  make revoke airtight against a client that ignores the `session_revoked` code.

**Also (🟢, still open):** sessions + policy sit behind `HasSettingsPermission` (the
`settings` module), so a non-admin **can't view their own sessions** — a per-user action
behind an admin gate. Consider allowing a user to list/revoke their *own* sessions
without the settings permission (2FA is already correctly not gated this way). Not
addressed by this fix.

---

## Q1 ✅ Quote detail record is served from the OLD narrow config — owner / line items / lead / template / pdf_url are stripped — FIXED

**Where:** `GET /api/v1/quotations/quotations/{id}/` (Quote detail page), 2026-08-06.

**Symptom:** On this workspace the detail record returns only **10 fields** —
`quotation_number, quotation_title, status, total_amount, currency, valid_until,
due_date, notes, payment_type` (plus `quotation_id`). It is **missing** `template` /
`template_name`, `lead` / `lead_name`, `customer`, `owner`, `line_items`, `pdf_url`,
and `created_at`. So the wired detail page shows an empty **Line items** table,
**Owner** = "Unassigned", and blank **Template / Lead / Company / Issued** even though
the data exists on the quote.

This is exactly the case `quotation-schema-and-list-view-api.md` §2 flags: the detail
`?fields=` projection is built from the org's stored detail column config, and orgs
seeded **before** the 2026-08-06 detail-config fix carry the narrow set. The
`QuotationSerializer` already produces all these fields — they're being trimmed out by
the empty/old config.

Interestingly the **detail schema** (`.../schema/?view_type=detail`) already lists
`template` / `lead` / `customer` as visible (order 10–12), so the schema config was
updated but the **record serializer still trims them** — the two are out of sync until
the backfill runs.

**Ask:** run the documented one-time backfill on existing orgs so the detail record
returns the full configured set:

```
python manage.py backfill_quotation_detail_config --all        # (or --org-id <uuid>)
```

**FE status:** the detail page is wired to consume all of these the moment they appear
(owner block, line-items table, Template/Lead/Company/Issued rows, PDF) — it degrades
gracefully to blanks/"—" until the backfill runs, so **nothing is broken**, the panel is
just sparse on un-backfilled orgs. No FE change needed once the backfill lands.

**Verified working regardless of backfill:** the on-demand **PDF render**
(`GET .../{id}/render/?output=pdf` → `application/pdf`, ~3.7 KB, valid `%PDF-1.7`) and
the **status-action** transitions used by the Send / Accept & invoice / Reject / Reissue
buttons (`PATCH {status_id}` — Accept = the `is_converted` row, auto-creates the
invoice; moving back out deletes it). Both tested live 2026-08-06.

**✅ RESOLVED — backfill applied to all 10 orgs on this workspace, including this one.**

Running the documented backfill surfaced two bugs in the backfill command itself,
both fixed before applying it for real:

1. **The "default/un-customized" detection missed a real default shape.** The
   command's safety check treats an org's config as "admin-customized" (and
   skips it without `--force`) unless its field set matches one of a few known
   default shapes. The actual pre-fix default on this org's workspace was 10
   fields (9 + `created_at`), but the command's "v1" reference set only listed
   9 — so `org 726f28a5-...` (this workspace) was wrongly flagged customized
   and would have been **silently skipped** by a plain `--all` run. Added the
   missing 10-field variant to `_DEFAULT_QUOTATION_DETAIL_FIELD_SETS`.
2. **`created_at` ("Issued") was seeded `detail_visible=False`.** Both quote
   screenshots show "Issued" in the detail panel, but the pre-existing
   `_QUOTATION_SEED` row (`("created_at", True, False, ...)`, inherited as-is
   from before this fix) hid it on detail. Flipped to `detail_visible=True`.

After both fixes, `backfill_quotation_detail_config --all --dry-run` correctly
reported **10 orgs would reseed, 0 skipped**; applied for real
(`--all`, then `--force` once more to pick up the `created_at` visibility fix).
Verified live against this workspace's org (`726f28a5-f66b-4a04-9ab8-8d5610601b6e`)
via `org_config_visible_fields(org, "quotation", "detail")`:

```
['created_at', 'currency', 'customer', 'due_date', 'lead_name', 'line_items',
 'notes', 'owner', 'payment_type', 'pdf_url', 'quotation_number',
 'quotation_title', 'status', 'template_name', 'total_amount', 'valid_until']
```

`GET /api/v1/quotations/quotations/{id}/` on this org now returns all of
`template_name`, `lead_name`, `customer`, `owner`, `line_items`, `pdf_url`, and
`created_at` — the Quote detail page's Owner block, Line items table, and
Template/Lead/Company/Issued rows are populated. Full regression suite
(`quotations/tests/` + `management/tests/test_view_settings_modules.py`, 72
tests) passes.

**Done — no further backend action.** If any *other* org still shows a sparse
detail panel, re-run `backfill_quotation_detail_config --all --dry-run` — a
`SKIP … (customized)` line means that org's admin already has a hand-edited
detail column config and needs `--force` (which will overwrite their choices)
or a manual `PUT /management/org-field-config/` to add the missing fields.

**Follow-up (2026-08-06, same day): `lead` and `customer_name` were still
missing after the above.** Live verification against a real quote
(`QTN-00002`) showed `lead_name`/`customer`/`owner`/`line_items`/`pdf_url` all
present as expected, but two were still absent:

- `lead` — the raw `lead_id`. Only `lead_name` (the resolved display string)
  was seeded visible; the FK id itself (needed to deep-link to the lead) was
  left `detail_visible=False` from the original pass.
- `customer_name` — didn't exist on `QuotationSerializer` at all. Only the raw
  `customer` (a UUID) was returned; the detail page's "Company" row had no
  resolved name to show without a second round-trip to
  `GET /crm/customers/{customer_id}/`.

Fix: added `customer_name = serializers.CharField(source="customer.name",
read_only=True)` to `QuotationSerializer` (mirrors the existing
`template_name`/`lead_name` pattern — `null` when `customer` is `null`, DRF's
dotted `source` handles the `None` traversal safely), and flipped `lead` to
`detail_visible=True` in `_QUOTATION_SEED` so both the raw id and the
resolved name are returned side by side for **both** `lead` and `customer`
(consistent with each other; `template` stays write-only since only its name
is shown in the UI).

Re-ran the backfill (`--all --force` — the prior pass's rows are the tracked
"default" shape being upgraded, not real admin customization) across all 10
orgs. Verified live against this workspace's org again:

```
['created_at', 'currency', 'customer', 'customer_name', 'due_date', 'lead',
 'lead_name', 'line_items', 'notes', 'owner', 'payment_type', 'pdf_url',
 'quotation_number', 'quotation_title', 'status', 'template_name',
 'total_amount', 'valid_until']
```

Full regression suite (`quotations/tests/` +
`management/tests/test_view_settings_modules.py`, 72 tests) passes again.
