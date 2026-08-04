# Automations API — Frontend Integration

Base path: `/api/v1/automation/`

Everything under this app is **System-Admin-only**. `is_staff` users bypass the
permission map; non-admins need the `automation` module permission
(`view_automation` for reads, `manage_automation` for writes). Non-permitted
users get **403**.

All list endpoints are paginated with the standard envelope
(`{count, next, previous, results}`, page size 100, `?page=` / `?page_size=`).

This document covers the two admin screens in the mockups:

1. **Automations list** — `/rules/` + `/rules/summary/`
2. **Automation logs** + **Run-details modal** — `/executions/` and
   `/rules/{rule_id}/executions/`

---

## 1. Automations list page

### `GET /api/v1/automation/rules/`

Returns the org's rules, ordered by `priority` (ascending — **P1 is highest
priority**), then newest first.

#### Query parameters (all optional, combinable)

| Param          | Values                                                        | Notes |
|----------------|--------------------------------------------------------------|-------|
| `status`       | `active` \| `paused` \| `draft`                              | Powers the status tabs. |
| `model`        | `lead` \| `customer` \| `task` \| `followup` \| `quote`      | Powers the "All models" dropdown. |
| `trigger_type` | `event` \| `schedule`                                        | Optional extra filter. |
| `search`       | free text                                                    | Case-insensitive match on **name OR description**. |
| `page`, `page_size` | integers                                                | Standard pagination. |

An **unknown value** for `status`/`model`/`trigger_type` is ignored (the filter
is simply not applied) — it never 400s the list, so a stale UI filter is safe.

#### Result row shape

```jsonc
{
  "rule_id": "0d4f…",
  "name": "Assign & prioritise hot leads",
  "description": "Route qualified, high-intent leads to a senior rep and open a…",
  "status": "active",                       // active | paused | draft
  "priority": 1,                            // render as "P1"
  "trigger": { "type": "event", "model": "lead", "on": ["create", "update"] },
  "trigger_summary": "created / updated",   // ← ready-to-render string under the model name
  "condition": { … },
  "actions": [ … ],
  "version": 3,
  "is_valid": true,
  "invalid_reason": null,                   // set when a rule references a purged custom field
  "capability_version": "1",
  "next_run_at": "2026-07-21T09:00:00Z",    // scheduled rules only, else null
  "last_run_at": "…",                       // scheduled rules only (legacy field), else null
  "last_run_stats": { "matched": 6, "applied": 6, … },  // scheduled rules only
  "last_run": {                             // ← unified "Last run" + "Last result" columns
    "at": "2026-07-17T09:58:00Z",
    "status": "applied",                    // applied | skipped | failed
    "result": "Success",                    // Success | No match | Error  (pill text)
    "records_affected": 3,                  // the "N records" line
    "duration_ms": 420
  },
  "consecutive_failures": 0,                // ≥5 auto-pauses the rule (circuit breaker)
  "created_at": "…",
  "updated_at": "…"
}
```

**Rendering the columns**

| UI column     | Field |
|---------------|-------|
| Automation    | `name` + `description` |
| Trigger       | `trigger.model` (title-cased) + `trigger_summary` |
| Status        | `status` |
| Priority      | `"P" + priority` |
| Last run      | `last_run.at` (format relative/absolute client-side) — show **“Never run”** when `last_run` is `null` |
| Last result   | `last_run.result` pill + `last_run.records_affected` + " records" |

> **Why `last_run` and not `last_run_at`?** `last_run_at`/`last_run_stats` are
> only populated for **scheduled** rules. `last_run` is derived from the newest
> execution and therefore works for **event rules too** — always use `last_run`
> for these two columns. It's computed in one extra query for the whole page.

### `GET /api/v1/automation/rules/summary/`

Status-tab counts. Honours the **same `model` / `trigger_type` / `search`
filters** as the list, so the tab numbers match a filtered view.

```json
{ "counts": { "active": 3, "paused": 3, "draft": 1, "all": 7 } }
```

### Row actions

| Icon        | Call | Notes |
|-------------|------|-------|
| Edit (✏️)    | `PATCH /rules/{rule_id}/` | See §3. |
| Pause/Play  | `PATCH /rules/{rule_id}/` with `{"status": "paused"}` or `{"status": "active"}` | Activating a **scheduled** rule schedules its first run automatically. |
| Duplicate   | `POST /rules/{rule_id}/duplicate/` | See below. |
| View logs   | Navigate to logs filtered by this rule (`/executions/?rule={rule_id}`). |

#### `POST /api/v1/automation/rules/{rule_id}/duplicate/`

Clones a rule. The copy is always created as **`draft`** with a unique
`name` (`"X (copy)"`, then `"X (copy 2)"`, …) and the next free `priority`, so it
never collides or fires on creation. Returns **201** with the full new rule
(same shape as a retrieve). Requires `manage_automation`.

---

## 2. Automation logs page

### `GET /api/v1/automation/executions/`

Cross-rule firing log, newest first, paginated.

#### Query parameters

| Param    | Values | Notes |
|----------|--------|-------|
| `rule`   | `rule_id` (UUID) | Filter to one rule. |
| `status` | `applied` \| `skipped` \| `failed` | Maps to outcomes **Success / No match / Error**. |
| `model`  | `lead` \| `customer` \| `task` \| `followup` \| `quote` | |
| `since`  | ISO datetime | `created_at >= since`. Use for the "From" date filter. |
| `until`  | ISO datetime | `created_at <= until`. Use for the "To" date filter. |

> **Outcome filter mapping** (the "All outcomes" dropdown): `Success → applied`,
> `No match → skipped`, `Error → failed`.

There is also a per-rule variant: `GET /rules/{rule_id}/executions/` (same rows,
scoped to one rule).

#### Row shape

```jsonc
{
  "execution_id": "…",
  "rule_id": "…",
  "rule_name": "Assign & prioritise hot leads",
  "rule_version": 3,
  "trigger_kind": "event",                  // event | schedule
  "trigger_label": "Lead updated",          // ← ready-to-render "Trigger" column
                                            //    e.g. "Scheduled · daily 09:00"
  "model": "lead",
  "record_uid": "…",                        // the triggering record (event runs)
  "status": "applied",
  "result": "Success",                      // Success | No match | Error
  "records_affected": 3,                    // "Records affected" column
  "duration_ms": 420,
  "actions_applied": [ … ],                 // ← powers the Run-details modal (see §2.1)
  "error": "",                              // populated when status = failed
  "created_at": "2026-07-17T09:58:00Z"      // the "When" column
}
```

### 2.1 Run-details modal

Open the modal from an execution row; render from **that same row's**
`actions_applied` (no extra fetch needed). Each element is one record the run
created or updated:

```jsonc
// UPDATED a record
{
  "action": "update_fields",
  "model": "lead",
  "record_uid": "…",
  "record_label": "Anand Textiles",         // human label for the record header
  "set": { "lead_owner": "Anjana Menon", "is_upsell": "Yes" },  // post-change values (back-compat)
  "changes": {                              // ← the before→after diff rows
    "lead_owner":  { "from": "Rahul Krishnan", "to": "Anjana Menon" },
    "priority_lead": { "from": "No", "to": "Yes" }
  }
}

// CREATED a record
{
  "action": "create_row",
  "model": "followup",
  "record_uid": "…",
  "record_label": "Call — Anand Textiles",
  "changes": {                              // create has no "from"
    "title": { "from": null, "to": "Anand Textiles" },
    "task_type": { "from": null, "to": "Call" },
    "due_date": { "from": null, "to": "2026-07-17" }
  }
}
```

**Rendering**

* Modal header: `result` pill + `rule_name`, then `trigger_label · created_at ·
  {duration_ms} ms`.
* One card per element in `actions_applied`, labelled `UPDATED`/`CREATED`
  (from `action`), titled `record_label`.
* One diff row per key in `changes`: strike-through `from` → highlighted `to`.
  A `from` of `null` renders as the empty "—" chip (a create, or a field that
  was previously unset).

> Values in `changes`/`set` are **display strings** — FK fields already resolve
> to the target's name/title (e.g. an owner shows the user's name, not a UUID).

---

## 2.2 Automation **detail** page

### `GET /api/v1/automation/rules/{rule_id}/`

Retrieve returns **everything the list row has, plus** three detail-only things:

| Field | Powers |
|-------|--------|
| `created_by_name`, `modified_by_name` | the "Created by" / "Last updated" rows in the **Automation details** card (also present on the list — they're cheap). |
| `currently_matches` | the **"Currently matches — N records"** row. Live `COUNT` of records the condition matches right now. `null` if the condition can't compile (purged custom field). |
| `describe` | the human-readable **summary banner** + **WHEN / IF / THEN** sections. |

> `describe` and `currently_matches` are returned **only** by retrieve, never by
> the list — the list stays lean. Don't expect them on `/rules/` rows.

Also reuse for this page:
* **Automation details card** → `status`, `priority` (→ "P{priority}"),
  `created_by_name`, `created_at`, `updated_at`, `currently_matches`.
* **Recent runs card** → `GET /rules/{rule_id}/executions/` (first page); "View
  all" → the logs page filtered by this rule.

### The `describe` payload

The frontend **cannot** build these strings itself — the spec stores FK values as
UUIDs and custom fields by id; resolving them to names ("Qualified", "Anjana
Menon") needs server-side org-scoped lookups. `describe` does that:

```jsonc
{
  "trigger": {
    "summary": "created / updated",                       // short (same as list trigger_summary)
    "sentence": "When a Lead is created or updated and its Status and Lead Score change"
  },

  // Labeled condition tree. Mirrors the stored condition; null => matches every record.
  // Render groups as the ALL OF / ANY OF boxes; render each leaf from its `text`.
  "conditions": {
    "kind": "group", "op": "and", "label": "ALL OF",
    "nodes": [
      { "kind": "leaf", "field": "status", "field_label": "Status",
        "operator": "eq", "operator_label": "is",
        "value_label": "Qualified", "text": "Status is Qualified" },
      { "kind": "group", "op": "or", "label": "ANY OF", "nodes": [
        { "kind": "leaf", "field_label": "Lead Score", "operator": "gte",
          "value_label": "80", "text": "Lead Score ≥ 80" },
        { "kind": "leaf", "fn": "days_since", "field_label": "Created At",
          "operator": "gte", "value_label": "30 days",
          "text": "Created At ≥ 30 days ago" }
      ] }
    ]
  },

  // Numbered THEN cards. `kind` = create | update; `title` is card heading;
  // each `changes` row is a "Label → value" line (FK values already resolved).
  "actions": [
    { "kind": "update", "model": "lead", "title": "Update the Lead",
      "changes": [ { "field": "lead_owner", "label": "Owner", "value": "Anjana Menon" },
                   { "field": "is_upsell", "label": "Upsell", "value": "Yes" } ] },
    { "kind": "create", "model": "task", "title": "Create a Task",
      "changes": [ { "field": "title", "label": "Title", "value": "…" },
                   { "field": "task_type", "label": "Task Type", "value": "Call" } ] }
  ],

  // The single-sentence banner at the top of the detail page.
  "summary": "When a Lead is created or updated and its Status and Lead Score change and Status is Qualified and (Lead Score ≥ 80 or Created At ≥ 30 days ago), then set Owner → Anjana Menon, Upsell → Yes on the Lead and create a Task (Title → …, Task Type → Call)."
}
```

**Node kinds in `conditions`**

| `kind`    | Shape | Render |
|-----------|-------|--------|
| `group`   | `{op: and\|or, label: "ALL OF"\|"ANY OF", nodes: […]}` | the grouped box; recurse into `nodes`. |
| `leaf`    | `{field_label, operator, operator_label, value_label, text}` | one condition row — just print `text`, or compose from the parts. |
| `related` | `{entity, label: "Related Customer", op, nodes: […]}` | a cross-model group (e.g. a Task rule testing its Lead). Recurse into `nodes`. |

`conditions` is `null` when the rule has no condition → render "Applies to every
record" (or similar). Boolean values render as `Yes`/`No`; multi-value (`in`)
values render comma-joined.

---

## 3. Authoring (create / edit) — quick reference

These already existed; included so the list page's Edit/New buttons are covered.

| Method & path | Purpose |
|---------------|---------|
| `POST /rules/` | Create. Body: `name`, `description`, `status`, `priority`, `trigger`, `condition`, `actions`. `priority` is **required and unique per org**. |
| `PATCH /rules/{rule_id}/` | Partial update (also used for pause/resume). Bumps `version`, snapshots the spec. |
| `DELETE /rules/{rule_id}/` | Delete a rule. |
| `GET /rules/capabilities/?model=<model>` | Form-driving schema (fields, operators, FK option sources, date functions) for the rule builder. |
| `POST /rules/validate/` | Dry-validate an unsaved `{trigger, condition, actions}`. Returns `{valid: true, matching_count}` or 400 with `{trigger|condition|actions: […]}`. |
| `POST /rules/preview/` | Count records matching an unsaved `{trigger, condition}` (dry-run). |
| `POST /rules/{rule_id}/preview/` | Same, for a saved rule. |
| `GET /rules/schedules/` | Scheduled rules with `next_run_at` / `last_run_at` / `last_run_stats`. |

**Validation errors** are returned by the project's handler wrapped as
`{"errors": {"<field>": ["…"]}}`.

**Trigger spec shapes**

```jsonc
// event
{ "type": "event", "model": "lead", "on": ["create", "update"],
  "changed_fields": ["status"] }            // changed_fields optional, update-only

// schedule
{ "type": "schedule", "model": "task",
  "frequency": { "every": "daily", "at": "09:00" } }   // every: hourly|daily|weekly|monthly
                                                        // weekly adds "day": 0-6 (Mon=0)
                                                        // monthly adds "day": 1-31
```

---

## 4. New / Edit automation **builder** page

### 4.1 Driving the form — `GET /rules/capabilities/?model=<model>`

Everything the WHEN / IF / THEN form needs comes from **capabilities** (already
existed). When the user switches the **model tab** (Lead / Customer / Task /
Follow-up / Quote) or the **trigger type**, re-fetch `?model=<key>`.

The IF condition builder (field picker → `is`/`is not` → value) is driven entirely
by `models.<model>.condition_fields`. Each field descriptor:

```jsonc
{ "name": "lead_source", "label": "Source", "type": "fk",
  "operators": ["eq","in","not","is_set","is_empty"],
  "fk_target": "lead_source",
  "widget": "select",
  "options": [ { "value": "…uuid…", "label": "Website" }, … ] }   // inline for config tables
```

* **Field picker** ("RECORD FIELDS" list, searchable) → `condition_fields[*].label`.
  Custom fields are merged in with `is_custom: true` and `name: "cf:<uuid>"`.
* **is / is not / operators** → `operators` (labels + cardinality in the top-level
  `operators` map). `eq`→"is", `not`→"is not", `in`→"is any of", etc.
* **Value control** → for `type:"fk"` render the inline `options` chips
  (Website / Referral / … , New / Qualified / …). Large sets (user/lead/customer/
  template) instead carry `widget:"async_select"` + `options_source` (an endpoint
  to typeahead against) — no inline options.
* **All of / Any of** → the condition tree's group `op` (`and`/`or`). **Add group**
  nests another group; one hop of **related-entity** groups is allowed.
* Date functions (`days_since` / `days_until` / `is_overdue`) come from the
  top-level `date_functions` map.

The THEN builder uses `models.<model>.action_fields`, `creatable`, and
`create_required` from the same payload.

### 4.2 Live preview — `POST /rules/describe/`

The **Live preview** panel (WHEN / IF / THEN sentences + "Matches N records right
now") is driven by this one endpoint. Call it (debounced) on every change to the
draft. It is built for an **incomplete** rule — it never 400s on a half-built
draft.

**Request** — the in-progress form state (any part may be missing/empty):

```jsonc
{ "trigger":   { "type": "event", "model": "lead", "on": ["create"] },
  "condition": { … },          // optional; omit/empty => matches every record
  "actions":   [ … ] }          // optional; omit/empty while still building
```

**Response** (always 200):

```jsonc
{
  "describe": {                          // null until a trigger model is chosen
    "trigger": { "summary": "created", "sentence": "When a Lead is created" },
    "conditions": { … },                 // labeled tree (see §2.2); null => match-all
    "condition_summary": "Any record matches",   // ← the "IF" preview line
    "actions": [ … ],                    // labeled THEN cards (see §2.2)
    "summary": "When a Lead is created."
  },
  "matching_count": 127,                 // ← "Matches 127 records right now"; null if uncountable
  "valid": false,                        // true only when fully saveable (well-formed + ≥1 action)
  "errors": {                            // NON-blocking, per section; {} when clean
    // "condition": "Unknown field 'x' for model 'lead'.",
    // "actions":   "Action 0: type must be one of ['create_row','update_fields']…"
  }
}
```

**How the builder uses it**

* WHEN line → `describe.trigger.sentence`.
* IF line → `describe.condition_summary` (renders "Any record matches" when no
  condition set — as in the mockup).
* THEN cards → `describe.actions` (each `{title, changes:[{label,value}]}`).
* "Matches N records" chip → `matching_count` (hide/skeleton when `null`).
* Inline "fix this" hints → `errors[section]`, shown **without** blocking the
  preview — the valid parts still render.
* **Activate** button enabled ⇔ `valid === true`.

> `matching_count` reflects **trigger + condition only** (what records the rule
> would act on) — actions don't affect it. It's `null` when the condition can't
> be compiled yet (e.g. a half-typed condition), so treat `null` as "not counted",
> not "0".

### 4.3 Saving

* **Save draft** → `POST /rules/` with `status: "draft"`.
* **Activate** → `POST /rules/` with `status: "active"` (only when
  `describe.valid` was true). Editing an existing rule uses `PATCH
  /rules/{rule_id}/`.
* `priority` is **required and unique per org** (the "Priority" field, default
  shown as 10 in the mockup). A clash returns 400 `{"priority": […]}`.
* `validate` (§3) remains the strict pre-save check; `describe` is the permissive
  live-preview one. Both are optional to call — `POST /rules/` re-validates
  server-side regardless.

### 4.4 Supported models & action constraints

The engine has **three different model sets** — they are NOT the same, and the
builder UI must respect the differences:

| Capability | Models | Notes |
|------------|--------|-------|
| **Trigger** (the WHEN "which record fires this") | `lead`, `customer`, `task`, `followup`, `quote` | All 5. Follow-up = a Task with `is_followup=true`. Only **create / update** — deletes are never a trigger. |
| **Update** (`update_fields` target) | `lead`, `customer`, `task`, `followup`, `quote` | Same 5, each with its own whitelisted, non-system field set (see `action_fields`). |
| **Create** (`create_row` target) | `lead`, `task`, `followup` **only** | You **cannot** create a `customer` or `quote` from a rule. Required fields: lead → `first_name`; task/followup → `title` + `task_type`. |

**⚠️ `update_fields` acts ONLY on the record that triggered the rule.** There is no
cross-model update. The action's `model` **must equal the trigger model** — the
engine loads the target by the *triggering record's* UUID, so pointing an update
at any other model fails at run time (`DoesNotExist` → a `failed` execution; 5 in
a row trips the circuit breaker and pauses the rule).

> **Builder rule:** the "Update the ___" model dropdown in the THEN section must
> list **only the trigger model** (a Lead-triggered rule → only "Lead"). Do **not**
> populate it from a related-entities list — cross-model access exists for
> **conditions** (a Lead rule can *read* its related Customer's fields, via
> `models.<model>.related_entities`), but **not** for update actions.

**`create_row` field notes**

* `create_row` is the only way a rule touches a *different* record than the
  trigger. Creatable targets are `lead` / `task` / `followup` only (above).
* For a **`followup`** create, `task_type` must be one of the org's active
  **Follow-up Type** names (e.g. "Call", "Email", "Meeting") — surface these from
  the org's follow-up-type config, not free text. A regular **`task`** uses the
  fixed `task_type` choices (`Task`/`Call`/`Meeting`/`Email`/`Deadline`).
  *(Backend note: the executor does not currently reject an unknown followup
  `task_type`; a bad value would create a malformed follow-up with no status —
  so the builder should constrain this to valid names.)*
* A rule-created task/follow-up is created with **no status/priority** unless the
  action's `set`/`values` include them; set a status explicitly if the workflow
  needs one (e.g. "Open").

**FK values are UUIDs, resolved per org.** Every condition/action value that is an
FK (status, source, owner, priority, team, …) is stored as **that org's UUID**,
never a name. Resolve names → UUIDs from `GET /rules/capabilities/?model=…`
(`options: [{value, label}]`) before saving. A rule that hardcodes another org's
UUIDs — e.g. a shared **starter template** — will not match/apply in a different
org. Templates should carry field + option *labels* and be resolved against the
current org's capabilities at save time.

---

## 5. Starter-template payloads

These are the exact `POST /rules/` bodies for the three "Or start from a template"
cards. **All were validated and executed end-to-end against the backend — they
work** — with one hard requirement: every `‹…›` placeholder below is a **config
UUID that must be resolved against the current org** from
`GET /rules/capabilities/?model=…` before POSTing (see the FK note above). The
labels in `‹›` are what to look up; substitute the org's matching `value`.

Set `status` to `"draft"` (Save draft) or `"active"` (Activate), and pick an unused
`priority`.

### Template 1 — Assign hot leads

> "When a Lead is created or updated and it is Qualified and score ≥ 80, assign an
> owner and create a call."

```jsonc
{
  "name": "Assign hot leads",
  "description": "Assign qualified, high-intent leads to an owner and open a call.",
  "status": "draft",
  "priority": 10,
  "trigger": { "type": "event", "model": "lead", "on": ["create", "update"] },
  "condition": {
    "op": "and",
    "nodes": [
      { "field": "status",     "operator": "eq",  "value": "‹lead_status: Qualified UUID›" },
      { "field": "lead_score", "operator": "gte", "value": 80 }
    ]
  },
  "actions": [
    { "type": "update_fields", "model": "lead",
      "set": { "lead_owner": "‹user: chosen owner UUID›" } },
    { "type": "create_row", "model": "task",
      "values": { "title": "Call hot lead", "task_type": "Call" } }
  ]
}
```

### Template 2 — Follow up on stale deals

> "Every day, for Leads in Negotiation not updated in 7 days, create a follow-up
> call." — **the create-follow-up-call this asks about works.**

```jsonc
{
  "name": "Follow up on stale deals",
  "description": "Nudge reps when a negotiation goes quiet for a week.",
  "status": "draft",
  "priority": 11,
  "trigger": { "type": "schedule", "model": "lead",
               "frequency": { "every": "daily", "at": "09:00" } },
  "condition": {
    "op": "and",
    "nodes": [
      { "field": "status", "operator": "eq", "value": "‹lead_status: Negotiation UUID›" },
      { "fn": "days_since", "field": "updated_at", "operator": "gte", "value": 7 }
    ]
  },
  "actions": [
    { "type": "create_row", "model": "followup",
      "values": { "title": "Follow-up call", "task_type": "Call" } }
  ]
}
```

> `task_type: "Call"` must be one of the org's active **Follow-up Types**. "Call"
> is seeded by default; on a customised org, resolve to a real follow-up-type name.

### Template 3 — Escalate overdue tasks

> "Every day, for open Tasks that are overdue, set priority to High."

```jsonc
{
  "name": "Escalate overdue tasks",
  "description": "Bump any open task past its due date to High priority.",
  "status": "draft",
  "priority": 12,
  "trigger": { "type": "schedule", "model": "task",
               "frequency": { "every": "daily", "at": "08:00" } },
  "condition": {
    "op": "and",
    "nodes": [
      { "field": "status",   "operator": "eq", "value": "‹task_status: Open UUID›" },
      { "fn": "is_overdue",  "field": "due_date", "value": true }
    ]
  },
  "actions": [
    { "type": "update_fields", "model": "task",
      "set": { "priority": "‹task_priority: high UUID›" } }
  ]
}
```

**Placeholder → capabilities lookup**

| Placeholder | Resolve from `capabilities` (`?model=…`) |
|-------------|------------------------------------------|
| `‹lead_status: … UUID›`   | `models.lead.condition_fields[name="status"].options` → match label |
| `‹task_status: Open UUID›` | `models.task.condition_fields[name="status"].options` → "Open" |
| `‹task_priority: high UUID›` | `models.task.action_fields[name="priority"].options` → "high" |
| `‹user: owner UUID›`      | `lead_owner` is an `async_select` (`options_source`) → the users list endpoint |

> Before showing "Use this template", the FE can confirm the pieces exist for the
> org (e.g. a "Qualified" lead status) and either pre-fill or prompt. A missing
> config row means the resolved value would be absent — don't POST a `null` FK.

---

## Notes for the frontend team

* **Priority is 1-based and unique per org.** Lower = higher priority. Render as
  `P{priority}`. A create/edit with a taken priority returns 400.
* **Seeded starter rules** (created DRAFT by `seed_automation_rules`) appear like
  any other rule; nothing special to handle.
* **`invalid_reason`** — when non-null (rule references a purged custom field),
  show the ⚠️ marker seen on some rows in the mockup; the rule is stored but
  won't execute until fixed.
* **Circuit breaker** — a rule auto-moves to `paused` after 5 consecutive
  failed runs (`consecutive_failures`), with `invalid_reason` explaining why.
