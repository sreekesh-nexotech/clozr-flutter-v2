# Issue Saved Filters API

Per-user **saved filters** for the Helpdesk → Tickets list (`module = "issue"`).
A saved filter is a named, stored bag of query params that the ticket list
re-applies on demand — it is *not* a separate query engine. The stored params go
through the **same `IssueFilter`** the list endpoint already uses, so a saved
filter can never express anything a plain `GET /issues/?…` cannot.

Two endpoints are involved:

1. **`/api/v1/crm/saved-filters/`** — CRUD for the filter chips themselves
   (shared across all modules; `module=issue` scopes it to tickets).
2. **`GET /api/v1/crm/issues/?saved_filter_id=<uuid>`** — apply one to the list.

Source of truth: `crm/views/saved_filter.py`, `crm/serializers/saved_filter.py`,
`crm/views/saved_filter_mixin.py`, `crm/services/saved_filter_apply.py`,
`crm/services/saved_filter_validation.py`, model `access_control.SavedFilter`.
Rulebook §10. For the ticket filter params themselves see the `IssueFilter`
catalog in [Part 4](#part-4--allowed-filter_definition-keys-for-moduleissue).

Auth: authenticated user. Everything is org-scoped **and** user-scoped — a user
only ever sees and edits their own filters.

---

## Part 1 — The saved-filter resource

### Object

| Field | Type | Writable | Notes |
| :--- | :--- | :--- | :--- |
| `saved_filter_id` | uuid | read-only | The id used in `?saved_filter_id=` and in detail URLs. |
| `module` | string | **write-only in practice** — send on create | `"issue"` for tickets. Full choice list below. |
| `name` | string (≤200) | yes | Chip label. Unique per user + org + module. |
| `visibility` | `"private"` \| `"shared"` | read-only | Phase 1 is private-only (§10.8); the field exists as a seam for team-shared filters later. Always returns `"private"`. |
| `filter_definition` | object | yes | Flat map of `IssueFilter` param keys → values. Stored and returned **verbatim** — never rewrite or normalize keys. |
| `is_valid` | bool | read-only | `false` ⇒ the filter references an unavailable custom field and **will not execute** (§10.4). |
| `invalid_reason` | string \| null | read-only | Names the offending field when `is_valid` is `false`. |
| `order` | int | yes | Chip ordering. Default `0`. |
| `created_at` / `updated_at` | datetime | read-only | |

`module` choices (one shared table serves every list): `lead`, `customer`,
`task`, `followup`, `product`, `project`, `issue`, `project_task`.
Note `task` (CRM interactions Task) and `project_task` (Operations Task) are
different models with different FilterSets — for tickets always use `issue`.

### Endpoints

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/api/v1/crm/saved-filters/?module=issue` | List the user's ticket filters. |
| `POST` | `/api/v1/crm/saved-filters/` | Create one. |
| `GET` | `/api/v1/crm/saved-filters/{saved_filter_id}/` | Retrieve. |
| `PATCH` / `PUT` | `/api/v1/crm/saved-filters/{saved_filter_id}/` | Update (rename, redefine, reorder). |
| `DELETE` | `/api/v1/crm/saved-filters/{saved_filter_id}/` | Delete. |
| `GET` | `/api/v1/crm/saved-filters/{saved_filter_id}/count/` | Match count for the chip (§10.6). |

**Permissions.** Because the queryset is already scoped to `request.user`, access
reuses the settings codenames rather than inventing per-resource ones:
reads (`list`, `retrieve`, `count`) need `view_settings`; all writes need
`update_settings`.

`?module=` is the only list filter. Omit it and you get the user's filters for
**every** module in one paginated page — always pass `module=issue` on the
tickets screen.

Results use the global `StandardResultsSetPagination` (page size 100,
`?page=` / `?page_size=`), so list responses are wrapped in
`{count, next, previous, results: [...]}`. `POST`/`PATCH` return the single
unwrapped row.

---

## Part 2 — Creating and updating

### Create

```http
POST /api/v1/crm/saved-filters/
Content-Type: application/json

{
  "module": "issue",
  "name": "My open high-priority",
  "filter_definition": {
    "assigned_to_me": "true",
    "priority__in": "High,Critical",
    "status__not": "3f1c…,9ab2…"
  },
  "order": 1
}
```

```jsonc
// 201
{
  "saved_filter_id": "0d5f8c2e-…",
  "module": "issue",
  "name": "My open high-priority",
  "visibility": "private",
  "filter_definition": { "assigned_to_me": "true", "priority__in": "High,Critical", "status__not": "3f1c…,9ab2…" },
  "is_valid": true,
  "invalid_reason": null,
  "order": 1,
  "created_at": "2026-08-07T10:14:22Z",
  "updated_at": "2026-08-07T10:14:22Z"
}
```

`organization` and `user` are stamped server-side from the request — do not send
them.

### Validation rules (all return `400` with a field-keyed body)

| Rule | Trigger | Response body |
| :--- | :--- | :--- |
| **Duplicate name** | Same `name` already exists for this user + org + `module`. | `{"name": "A saved filter named 'X' already exists for this module."}` |
| **Limit of 5** (§10.3) | Creating a 6th filter for `module=issue`. Enforced **only when the write adds a row** — editing an existing filter in place is never blocked by the ceiling, and a `PATCH` that doesn't change `module` doesn't count. | `{"module": "Limit of 5 saved filters per module reached."}` |
| **Empty definition** | `filter_definition` missing, not an object, or `{}`. | `{"filter_definition": "Add at least one filter before saving."}` |
| **Unknown key** | A key that is neither an `IssueFilter` param nor a `custom_fields.<name>` reference. | `{"filter_definition": "Unknown filter key(s): foo, bar."}` |

The duplicate-name check is a serializer pre-check in front of the DB
`unique_together` — without it the IntegrityError surfaces as a 500.

### Update

`PATCH` with any writable field. Renaming re-runs the duplicate check (excluding
the row itself); changing `filter_definition` re-runs validation and recomputes
`is_valid` / `invalid_reason`.

Writes bump the cache version `user:{user_id}:saved_filter`, which invalidates
that user's cached chip counts.

---

## Part 3 — Applying a saved filter to the ticket list

```
GET /api/v1/crm/issues/?saved_filter_id=<uuid>
```

Also works on the QUERY-verb form of the same collection
(`QUERY /api/v1/crm/issues/` with a JSON body) — `saved_filter_id` may sit in the
URL query string while the body carries additional params.

**Semantics**

* The stored definition is the **base layer**; explicit request params **override**
  it key-by-key. So `?saved_filter_id=X&priority=Low` runs the chip's definition
  with `priority` replaced by `Low`. This is what backs "chip active, user tweaks
  one facet".
* The control params `saved_filter_id`, `page`, `page_size` and `cursor` are
  stripped before the params reach the FilterSet.
* Empty values (`null`, `""`, `[]`) are dropped rather than passed through — an
  empty param would otherwise read as an active filter.
* Applying a filter does **not** change pagination. It is just a stored param
  dict, so the list keeps its normal page-number pagination with `count`/`page` —
  the range label and page selector keep working.
* Ordering, `?search=`, and every other list param behave exactly as they do
  without a saved filter.
* Custom-field conditions (`custom_fields.<name>` keys) are not FilterSet params;
  they are applied as queryset filters **after** the FilterSet runs.

**Errors**

| Status | When | Body |
| :--- | :--- | :--- |
| `404` | `saved_filter_id` doesn't exist, isn't this user's, isn't in this org, or belongs to a different `module`. Also covers a malformed uuid. | `{"detail": "Saved filter not found."}` |
| `400` | The filter is **inert** (`is_valid: false`) — it references a deactivated or purged custom field. | `{"saved_filter": "<invalid_reason>"}` |
| `400` | A stored param fails field validation (e.g. a stored uuid no longer parses). | `{"saved_filter": {"<param>": ["<error>"]}}` |

Both `400`s are the §10.4 **fail-inert** guarantee: a broken filter returns an
error rather than silently dropping the offending param and running a **widened**
query. A plain FilterSet drops params it can't clean, which would return *more*
rows than the user asked for — that is treated as a bug, not a fallback.

A filter goes invalid rather than being deleted when a referenced custom field is
deactivated, so **reactivating the field heals the chip** on the next save/apply.
Render such chips greyed and do not auto-run them.

### Chip counts

```
GET /api/v1/crm/saved-filters/{saved_filter_id}/count/
```

```jsonc
{ "count": 42 }
{ "count": null, "invalid_reason": "References unavailable field(s): sla_tier." }  // inert filter
```

Cached for 60s under the `user:{user_id}:saved_filter` cache version — the count
is **approximate by design** (§10.6). It is never invoked implicitly by list
rendering: a per-chip `COUNT` on every page load is prohibited. Call it lazily,
e.g. on chip hover or after the list settles.

The count runs against the org-scoped `Issue` base queryset
(`Issue.objects.filter(organization=org)`) with the definition applied.

---

## Part 4 — Allowed `filter_definition` keys for `module=issue`

The authoritative set is `IssueFilter.base_filters` (`crm/filters/issue.py`) —
anything outside it is rejected at save time. Values are stored as sent; use the
same string forms the query string uses. Multi-value params accept a
comma-separated list (`"High,Critical"`) or a JSON array (`["High","Critical"]`) —
arrays become repeated params on apply.

### Identity & text

| Key | Value |
| :--- | :--- |
| `issue_id` | uuid |
| `reference` / `reference__icontains` | Ticket ref, e.g. `TKT-1029`; `icontains` so `1029` alone matches. |
| `subject` / `subject__icontains` | string |
| `description__icontains` | string |
| `search` | Matches subject, description, reference **and** customer name. |

### Status, priority, channel

| Key | Value |
| :--- | :--- |
| `status`, `status__in` | `issue_status_id` uuid(s) — **not** the status name. |
| `status__not` | uuid(s) to exclude. |
| `priority`, `priority__in`, `priority__not` | `Low` \| `Medium` \| `High` \| `Critical`. |
| `channel`, `channel__in`, `channel__not` | `email` \| `whatsapp` \| `phone` \| `api`. Nullable on the model, so `__not` keeps channel-less tickets. |

### People, teams, categories

| Key | Value |
| :--- | :--- |
| `issue_type`, `issue_type__in`, `issue_type__not` | `issue_type_id` uuid(s). |
| `assigned_to`, `assigned_to__in`, `assigned_to__not` | `user_id` uuid(s). |
| `raised_by`, `raised_by__in`, `raised_by__not` | `user_id` uuid(s). |
| `assigned_team`, `assigned_team__in`, `assigned_team__not` | `team_id` uuid(s). |
| `assigned_to_me` | `"true"` — the "My Tickets" view; resolves against the requesting user at apply time. |
| `my_team` | `"true"` — tickets assigned to any team the requesting user belongs to. |

`assigned_to_me` / `my_team` resolve **per request**, so the same saved filter
means "mine" for whoever runs it. Since filters are private today this only
matters for chips that outlive a role change.

### Related records

| Key | Value |
| :--- | :--- |
| `related_to`, `related_to__in` | Content-type model name, e.g. `lead`. |
| `related_to_id`, `related_to_id__in`, `related_to_id__not` | uuid of the related record. |
| `customer`, `customer__in` | `customer_id` uuid(s). |
| `product`, `product__in` | `product_id` uuid(s). |
| `project`, `project__in` | `project_id` uuid(s). |
| `has_linked_tasks` | bool. |

`related_to` is a single generic slot; `customer` / `product` / `project` are
promoted real columns and **coexist** with it and with each other.

### Dates

| Key | Value |
| :--- | :--- |
| `opening_date`, `opening_date_after`, `opening_date_before` | `YYYY-MM-DD` |
| `resolution_date`, `resolution_date_after`, `resolution_date_before` | `YYYY-MM-DD` |
| `created_at`, `created_at_after`, `created_at_before` | `YYYY-MM-DD` (date part) |
| `updated_at`, `updated_at_after`, `updated_at_before` | `YYYY-MM-DD` (date part) |
| `sla_deadline_after`, `sla_deadline_before` | ISO datetime |
| `last_updated` | `today` \| `this_week` \| `this_month` |

Absolute dates are the safer thing to store. A relative key like `last_updated`
is evaluated at apply time, which is usually what a "recently touched" chip
wants — but note there is no relative-window key for the other date fields, so
"opened in the last 7 days" has to be stored as an absolute
`opening_date_after` and will drift.

### SLA & response

| Key | Value |
| :--- | :--- |
| `sla_breached` | bool |
| `has_sla` | bool — `true` ⇒ `sla_deadline` is set. |
| `first_response_time`, `first_response_time_min`, `first_response_time_max` | number |

`resolution_time` is a `TimeField` on the model, not a duration, and is
deliberately **not** exposed as a numeric filter.

### Custom fields

`custom_fields.<field_name>` — resolved against the org's active, **filterable**
custom fields. Referencing an inactive/purged field is not rejected at save; it
sets `is_valid: false` with an `invalid_reason` and the chip fails inert.

### The `is / is not` toggle

Every `__not` param excludes matching tickets **while keeping rows whose field is
`NULL`**. This is deliberate: a bare `.exclude(status__in=[…])` also drops
NULL-FK rows via SQL NULL semantics, which would hide un-triaged tickets from an
"is not X" filter.

---

## Notes for the frontend

* Read exactly six fields off the DTO: `saved_filter_id`, `name`,
  `filter_definition`, `is_valid`, `invalid_reason`, `order`. `saved_filter_id`
  and `name` are hard-required.
* Round-trip `filter_definition` keys verbatim. Do not translate them into a
  private schema and back — the keys *are* the contract, and an unrecognized key
  is a 400.
* Show the 5-per-module ceiling in the UI before the user hits the 400; editing
  an existing chip is always allowed even at the ceiling.
* Grey out chips with `is_valid: false`, surface `invalid_reason`, and don't
  auto-apply them.
* Don't fetch counts for every chip on page load — the endpoint is lazy and
  approximate on purpose.

Tests: `crm/tests/test_saved_filters.py`.
