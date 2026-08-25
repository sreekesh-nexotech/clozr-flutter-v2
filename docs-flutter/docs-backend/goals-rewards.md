# Goals & Rewards — Admin Panel API Guide

Backs the **Goals & Rewards** section: **My Progress**, **My Team** and
**Approvals**.

All routes mount under **`/api/v1/milestones/`**. Auth: JWT. Everything is
org-scoped from the token — you never pass an org id.

**Code:** `milestones/views.py`, `serializers.py`, `filters.py`, `levels.py`,
`rewards.py`. **Tests:** `milestones/tests/` (103).

> **Vocabulary — read this first.** The domain calls a campaign a **milestone**,
> and the reward lifecycle uses these five statuses:
>
> | Status | UI label |
> | :--- | :--- |
> | `locked` | Locked |
> | `achieved` | **Awaiting approval** (the Approvals tab 1) |
> | `approved` | **Fulfilment** (tab 2) — approved, not yet handed over |
> | `fulfilled` | **Fulfilled** (tab 3) |
> | `void` | Void (a rejected grant) |
>
> There is **no `pending`** — `?status=pending` returns **400**. "Awaiting
> approval" is `achieved`.

---

## Endpoint index

| Method | Path | Screen |
| :--- | :--- | :--- |
| `GET` | `/progress/` | My Progress cards · My Team roster |
| `GET` | `/progress/{progress_id}/` | one row |
| `GET` | `/rewards/` | Approvals list (all three tabs) |
| `GET` | **`/rewards/status-counts/`** | Tab badges + sidebar count |
| `GET` | **`/rewards/{grant_id}/history/`** | Who approved/rejected, and why |
| `POST` | `/rewards/{grant_id}/approve/` | **Approve** button |
| `POST` | `/rewards/{grant_id}/reject/` | **Reject** button |
| `POST` | `/rewards/{grant_id}/fulfill/` | **Mark delivered** button |
| `POST` | **`/rewards/bulk-action/`** | Bulk approve/reject/settle (**Import**) |
| `GET` | **`/tracks/{track_id}/progress/`** | **Closer Track** panel |
| `GET` | `/tracks/` | Track list (authoring) |
| `GET`/`PUT` | `/settings/` | "Approver mode" chip |
| `GET` `POST` `PATCH` `DELETE` | `/milestones/` | Campaign authoring |
| `POST` | `/milestones/{id}/activate/` · `/enroll/` | Authoring |
| `GET` `POST` `DELETE` | `/participants/` · `/steps/` | Authoring |

**Permissions.** Read surfaces (`/progress/`, `/rewards/`, and
`/tracks/{id}/progress/`) are open to **every authenticated participant** — a rep
must see their own progress. Authoring (`/milestones/`, `/participants/`,
`/tracks/`, `/steps/`, `/settings/`) is gated by the `milestone` module
permission. Everything is additionally scoped by **§3.4 visibility**: System
Admin / Executive Leadership see the whole org; everyone else sees themselves
plus their hierarchy subtree. **There is no leaderboard and no cross-peer
visibility** — that is deliberate.

---

## 1. My Progress — the campaign cards

```
GET /api/v1/milestones/progress/?participant_user={my_user_id}&current=true
```

One row per (participant × milestone × period). Paginated.

```jsonc
{
  "progress_id": "…",
  "milestone": "…", "milestone_name": "Monthly Deal Closer",
  "period_label": "1 Jul – 31 Jul 2026",     // → the card's date line
  "period_start": "2026-07-01T…", "period_end": "2026-08-01T…",  // end is EXCLUSIVE
  "participant_user": "…", "participant_name": "Manoj Varma",
  "current_value": "3.00",                    // → "3 / 5"
  "target_snapshot": "5.00",                  // frozen at enrolment
  "pct": "0.6000",                            // → the 60% bar (0–1, NOT 0–100)
  "achieved": false,
  "achieved_at": null,
  "last_swept_at": "2026-07-14T06:00:00Z",    // → "Last updated 14 Jul, 06:00"

  // reward state for THIS period — no second fetch, no client-side join
  "locked": false,                            // → the grey "Locked" chip
  "reward_status": "achieved",                // → "Achieved" / "Pending approval" chip
  "reward_grant": "…grant_id…",               // → post Approve/Reject straight to it
  "reward": { "title": "₹10,000 shopping voucher", "display_value": "₹10,000",
              "description": "…", "icon": "gift" }   // → the "YOU'LL GET" panel
}
```

**`pct` is a 0–1 decimal string** — multiply by 100 for the bar.
**`period_end` is exclusive**, which is why `period_label` renders the last day
as `period_end − 1 day`. Use `period_label` rather than formatting it yourself.

`reward` falls back to the milestone's current reward when no grant exists yet,
so the "YOU'LL GET" panel renders before the target is met. Once a grant exists
it is the **frozen snapshot** — later edits to the milestone never reach it.

### Card states → fields

| Card chip | Source |
| :--- | :--- |
| **Locked** | `locked: true` (a level step whose prior levels are incomplete) |
| **Achieved** | `achieved: true` |
| **Pending approval — you'll be notified** | `reward_status: "achieved"` |
| Fulfilled | `reward_status: "fulfilled"` |
| Void | `reward_status: "void"` |

### "Past periods (3)"

Omit `?current=true` to get every period for the milestone; the current one is
the highest `period_start`. Each past row carries its own `pct` and
`reward_status` — that is the `Fulfilled` / `Approved` / `Void` column in the
expanded list.

### Filters

| Param | Notes |
| :--- | :--- |
| `participant_user` | uuid(s), comma-separated |
| `milestone` | uuid(s) |
| `achieved` | `true`/`false` |
| `current` | `true` → only each milestone's latest period |
| `pct_min` / `pct_max` | 0–1 decimals |
| `milestone_type` | `one_shot` \| `repeatable` |
| `level_linked` | `true` → only milestones that are level steps |
| `search` | participant name or milestone name |
| `ordering` | `participant_name`, `milestone_name`, `pct` (prefix `-`) |

Multi-value params are comma-separated. Invalid values are a **400 field
error**, never a silent pass.

### Header stats

| Header | How |
| :--- | :--- |
| "MILESTONES ACHIEVED 5" | `GET /progress/?participant_user={id}&achieved=true` → `.count` |
| "CURRENT LEVEL · Level 2" | `/tracks/{id}/progress/` → `current_level` (§3) |
| Name / role / "Reports to" | `accounts` + `teams`, not this app |

---

## 2. My Team — the roster

Same endpoint, no `participant_user` filter — visibility scoping does the work:

```
GET /api/v1/milestones/progress/?current=true&ordering=participant_name
```

Every row you can see is someone in your subtree (or the whole org for
Admin/Exec). Columns map to `participant_name`, `milestone_name`,
`current_value`/`target_snapshot`, `pct` and `reward_status`.

"expiring on 31-Jul-2026" is `period_end − 1 day`; a milestone with no expiry
returns `period_end: null` and `period_label: "Lifetime"` → render "No expiry".

> This is a **management roster, not a leaderboard** — there is no rank field
> and none is coming. Sorting is client-driven via `?ordering=`.

---

## 3. Closer Track — the level panel

```
GET /api/v1/milestones/tracks/{track_id}/progress/          # the caller
GET /api/v1/milestones/tracks/{track_id}/progress/?user={user_id}
```

Everything the right-hand panel needs, in one call.

```jsonc
{
  "track": "…", "track_name": "Closer Track",
  "current_level": 2,             // → "CURRENT LEVEL · Level 2"
  "unlocked_up_to": 3,
  "next_step": { … },             // → the "UP NEXT" box; null when the track is done
  "steps": [
    { "step_id": "…", "sequence": 1, "milestone": "…",
      "milestone_name": "First 10 Conversions",
      "measure": "conversions_count",
      "target_value": "10.00", "current_value": "10.00", "pct": "1.0000",
      "state": "achieved",                    // achieved | in_progress | locked
      "achieved_at": "2026-05-02T…",
      "reward": { "title": "…" }, "reward_status": "fulfilled" }
  ]
}
```

`state` drives the rung rendering directly:

| `state` | Panel |
| :--- | :--- |
| `achieved` | green tick · "Achieved" |
| `in_progress` | filled dot · **"YOU ARE HERE"** — exactly one rung |
| `locked` | padlock · greyed |

`next_step` is the `in_progress` rung, repeated at the top as "UP NEXT" with its
`current_value / target_value` bar.

**Unlock is derived, never cached.** It is recomputed from actual achievement on
every call, so a rung can't be wrong because a `LevelParticipant` cache went
stale. Whether a level counts as complete follows the org's `unlock_gate`
setting (§5): `achieved` (default) or `approved`.

Passing `?user=` for someone outside your visibility scope returns **403**; an
unknown user returns **404**. A track with no steps returns `steps: []` and
`next_step: null` — render an empty panel, not an error.

---

## 4. Approvals

### The three tabs

```
GET /api/v1/milestones/rewards/?status=achieved&can_approve=true   # Awaiting approval
GET /api/v1/milestones/rewards/?status=approved                    # Fulfilment
GET /api/v1/milestones/rewards/?status=fulfilled                   # Fulfilled
```

```jsonc
{
  "grant_id": "…",
  "participant_name": "Anjana Menon", "participant_user": "…",
  "milestone_name": "Monthly Deal Closer",
  "status": "achieved",
  "reward_snapshot": { "title": "₹10,000 shopping voucher", "display_value": "₹10,000" },
  "target_snapshot": "5.00",
  "achieved_at": "2026-07-13T…",     // → "Achieved Yesterday"
  "approver": "…", "approved_at": "2026-07-02T…",   // → "Approved 02-Jul-2026"
  "fulfilled_by": "…", "fulfilled_at": "2026-07-05T…"  // → "Fulfilled 05-Jul-2026"
}
```

**`?can_approve=true`** narrows to grants *this user* may act on — Admin/Exec see
all; a reporting manager sees only their subtree and **never their own grants**.
Under `approver_mode: executive_leadership` a non-admin sees none. Use it on the
first tab so the buttons are never dead.

### Tab badges + the sidebar count

```
GET /api/v1/milestones/rewards/status-counts/
```
```jsonc
{
  "counts": { "locked": 0, "achieved": 3, "approved": 2, "fulfilled": 4, "void": 1 },
  "awaiting_approval": 3,   // → tab 1 badge, and the sidebar "Approvals 3"
  "fulfilment": 2,          // → tab 2
  "fulfilled": 4,           // → tab 3
  "total": 10
}
```

One aggregate query. It applies the same visibility scoping and filters as the
list **minus the `status` facet**, so each badge reports the count it would have
under the other active filters. Add `?can_approve=true` to match tab 1 exactly.

### Actions

| Button | Call | Rule |
| :--- | :--- | :--- |
| **Approve** | `POST /rewards/{grant_id}/approve/` | `achieved` → `approved`. Approver must pass `can_approve`. |
| **Reject** | `POST /rewards/{grant_id}/reject/` `{"note": "…"}` | → `void`. The note is stored and readable via `history/`. |
| **Mark delivered** | `POST /rewards/{grant_id}/fulfill/` | `approved` → `fulfilled`. **Admin/Exec only.** |

A wrong-state transition is a **400** (e.g. fulfilling a grant that was never
approved); an unauthorised one is **403**. All three return the updated grant.

### Bulk / Import

```jsonc
POST /api/v1/milestones/rewards/bulk-action/
{ "grant_ids": ["…", "…"], "action": "approve" | "reject" | "fulfill", "note": "" }
```
```jsonc
{ "success": false, "updated": 7, "action": "approve",
  "errors": [ { "grant_id": "…", "error": "not_found" } ] }
```

Backs the bulk controls and the **Import** flow (settling a batch of approved
rewards after an offline hand-over). Always **200** — read `updated`/`errors`,
not just `success`. Each grant is authorised and transitioned in its **own
savepoint**, so one bad row never rolls back its siblings. Ids outside your
visibility report `not_found` rather than being acted on.

### Grant history

```
GET /api/v1/milestones/rewards/{grant_id}/history/
```
```jsonc
[ { "from_status": "achieved", "to_status": "approved",
    "actor": "…", "actor_name": "Admin Acme", "note": "",
    "created_at": "2026-07-02T…" } ]
```

Append-only, oldest-first, unpaginated. **This is the only way to read a reject
`note`** — it is accepted by `reject/` and appears nowhere else.

---

## 5. Settings — the "Approver mode" chip

```
GET  /api/v1/milestones/settings/     # view_milestone
PUT  /api/v1/milestones/settings/     # update_milestone
```
```jsonc
{
  "approver_mode": "reporting_manager",  // | "executive_leadership"
  "sweep_cadence": 6,                     // hours → "refreshes about every 6 hours"
  "approval_required": true,              // false → grants auto-approve
  "unlock_gate": "achieved"               // | "approved" — when a level counts as done
}
```

---

## 6. Freshness

Progress is **swept on a schedule, not live**. `last_swept_at` on any progress
row backs "Progress refreshes about every 6 hours — not live to the second. Last
updated 14 Jul 2026, 06:00". The cadence is `settings.sweep_cadence`. A rep who
closes a deal will not see the bar move until the next sweep — say so in the UI,
as the current banner does.

---

## Notes for the frontend

* **`pct` is 0–1**, as a string. `"0.6000"` → 60%.
* **`period_end` is exclusive.** Prefer `period_label`; for "expiring on" use
  `period_end − 1 day`. `null` means no expiry ("Lifetime").
* **Money/valued rewards** live in `reward.display_value` (a display string) —
  there is no numeric amount field. `reward.title` is the only required key.
* **`?status=pending` is a 400.** Use `achieved`.
* **Invalid filter values 400**; unknown params are ignored.
* A user with **no role assigned** still sees their own rows — these read
  surfaces are participant-open and fail *open* for an org with no subscription.

## Known gaps

1. **No per-user "achievement count" aggregate.** The header's "MILESTONES
   ACHIEVED" needs `?achieved=true` and reads `.count` off a paginated response.
   Fine, but it costs a page fetch.
2. **`reward.display_value` is a free string**, so the FE cannot sort or total
   reward values. Deliberate — rewards are descriptive-only by design.
3. **No CSV import/export.** `bulk-action/` covers the Import button's settle
   flow by id; there is no file-upload parser.
4. **`LevelParticipant` is a cache with no endpoint.** `/tracks/{id}/progress/`
   derives state instead, which is correct but recomputes per call. Fine at
   panel scale; would need the cache if this ever became a bulk roster view.
