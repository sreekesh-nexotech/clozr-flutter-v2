# Members (People / User Management) API

Backing for the **People → Members** screen: the org-wide member list with
Role, "Reports to" (reporting manager), Team, and Status columns, the search box,
the four filter dropdowns (**All roles / All teams / All statuses / Any manager**),
the **Invite member** action, and the per-row action menu (**Edit member,
Deactivate/Activate, Delete member**).

> Out of scope here (documented elsewhere / deferred): **Transfer System Admin**
> (§2.3 support-verified flow, not yet built) and **Reset password** (self-service
> flow lives in the Authentication API). Team CRUD and the manager/hierarchy tree
> endpoints have their own reference — see [team-api.md](team-api.md).

Two kinds of calls:

1. **Populate the filter dropdowns** — small GET endpoints returning the option
   lists (roles, teams, users-as-managers). Statuses are a fixed client-side set.
2. **Apply search + filters** — the same `GET /api/v1/management/users/` list
   endpoint with the query params below. There is **no** dedicated filter
   endpoint — filters are query params on the list, resolved by
   `UserManagementFilter` (`management/filters.py`).

Base prefix: `/api/v1/management/` for everything on this screen.
Auth: authenticated user; the org is resolved from the JWT (`request.org`) and
scopes every response. Permissions are enforced by `MapBasedPermission` against the
codenames in each endpoint's `permission_map`.

Pagination everywhere: `StandardResultsSetPagination` (page size 100, `?page=` /
`?page_size=`, max 200). Rate limit: **60/min per user** on the users viewset.

---

## Part 1 — Populate the filter dropdowns

| Dropdown | Endpoint | Notes |
| :--- | :--- | :--- |
| **All roles** | `GET /api/v1/management/roles/` | Org roles → `{role_id, name, description, is_custom, permission_level, is_active, …}`. Use `role_id` (UUID) as the filter value, or the role `name`. Supports `?search=` (name, description) and `?is_active=true`. Permission: `view_role`. |
| **All teams** | `GET /api/v1/management/teams/` | Org teams → `{team_id, name, description, manager, member_ids, …}`. Use `team_id` (UUID) as the filter value. Supports `?search=` (name, description). Permission: `view_team`. See [team-api.md](team-api.md). |
| **Any manager** | `GET /api/v1/management/users/` | The same members list — any org user can be a manager. Use their `user_id` as the filter value. Supports `?search=`. |

**All statuses** needs no endpoint — it is a fixed client-side set mapped onto the
`is_active` field (see [Status](#status) below).

---

## Part 2 — Apply search + filters

```
GET /api/v1/management/users/?<params>
```

Standard paginated list response; each row is a member object
([shape below](#the-member-object)). All params combine with **AND**. Backed by
`UserManagementFilter` + DRF `SearchFilter` + `OrderingFilter`.

### Free-text search

| Control | Param | Matches |
| :--- | :--- | :--- |
| Search box | `?search=<text>` | `username`, `email`, `first_name`, `last_name`, `user_id` |

Example: `?search=lakshmi` → members whose name/email/username contains "lakshmi".

### All roles

| Param | Value | Example |
| :--- | :--- | :--- |
| `role_id` | Role UUID | `?role_id=<role_uuid>` |
| `role_name` | Role name (case-insensitive exact) | `?role_name=Manager` |

Matches members assigned that role (`UserRole`).

### All teams

| Param | Value | Example |
| :--- | :--- | :--- |
| `team_id` | Team UUID | `?team_id=<team_uuid>` |

Matches members of that team. A user may belong to **multiple** teams (§3.3.1);
this matches if the user is a member of the given team (via `TeamMember`).

### Any manager

| Param | Value | Example |
| :--- | :--- | :--- |
| `manager_id` | Manager's user UUID | `?manager_id=<user_uuid>` |

Matches members whose **current** reporting manager is that user. The manager is
read from the member's **active** `UserHierarchy` row (`effective_to IS NULL`), so
a closed/historical manager relationship does **not** match — only the present one.

### Status

The "All statuses" chips map onto `is_active` (there is no separate status field):

| Chip | Meaning | Param |
| :--- | :--- | :--- |
| **Active** | Activated & enabled (`is_active=true`) | default list view (see below) |
| **Deactivated** | Disabled by an admin (`is_active=false`) | `?is_active=false` |
| **Invited** | Invited, not yet activated (`is_active=false`, never logged in) | `?is_active=false` then split client-side on `profile`/`last_login` |

> **Default scope:** the list returns **only active** members unless `is_active`
> is explicitly supplied. Pass `?is_active=false` to reveal deactivated **and**
> not-yet-activated (invited) members. "Invited" vs "Deactivated" is distinguished
> client-side: an invited user has never logged in (no last-login) — an activation
> email was sent and `is_active` flips to `true` on activation. There is no
> distinct `status` enum on the backend.

### Admin filter (extra)

| Param | Value | Note |
| :--- | :--- | :--- |
| `is_staff` | `true` / `false` | Filter to System Admins (`is_staff=true`) or non-admins. |

### Ordering & paging

| Param | Values |
| :--- | :--- |
| `ordering` | `created_at`, `username` (prefix `-` for desc). **Default `-created_at`**. |
| `page` / `page_size` | Page number / size (default 100, max 200). |

`date_joined` / `created_at` are also accepted as exact filters.

### Full example

Active **Managers** on **Team Central** reporting to **Lakshmi**, newest first:

```
GET /api/v1/management/users/
  ?role_name=Manager
  &team_id=<team_central_id>
  &manager_id=<lakshmi_user_id>
  &ordering=-created_at
```

**Reset** = drop every filter param and re-fetch the bare list (defaults to active
members).

---

## The member object

Returned on list / retrieve / create / update (`UserManagementSerializer`):

```json
{
  "id": 42,
  "user_id": "u-1234…",
  "username": "arjun.nair@kairali.in",
  "email": "arjun.nair@kairali.in",
  "first_name": "Arjun",
  "last_name": "Nair",
  "full_name": "Arjun Nair",
  "is_active": true,
  "is_staff": false,
  "is_protected": false,
  "role": { "role_id": "r-abcd…", "name": "Manager" },
  "scope": { "code": "hierarchy", "label": "Self + Reporting Hierarchy" },
  "manager": {
    "user_id": "u-5678…",
    "full_name": "Lakshmi Pillai",
    "email": "lakshmi.pillai@kairali.in"
  },
  "teams": [
    { "team_id": "t-1111…", "name": "Team Central" }
  ],
  "territories": [
    { "territory_id": "ter-1…", "name": "All India" }
  ],
  "profile": {
    "phone": "", "mobile": "", "profile_picture": null,
    "designation": "Business Owner",
    "timezone": "Asia/Kolkata", "language": "", "gender": "",
    "birth_date": null, "location": "", "bio": "", "preferences": {}
  }
}
```

> `full_name`, `is_protected`, `scope`, and `territories` are the fields the
> **member detail page** relies on — see [Part 4](#part-4--member-detail-page).
> **`scope` is returned on the retrieve (detail) response only**, not on the
> paginated list (it runs a per-user permission lookup).

Column mapping for the members table:

| Column | Source field |
| :--- | :--- |
| **Member** (name, email) | `first_name`/`last_name`, `email` |
| **Role** (badge + visibility sub-label) | `role.name` (visibility scope comes from the role's record-permission `permission_type` — Organization-wide / Self + Reporting Hierarchy / Team-based + Reporting Hierarchy) |
| **Reports to** | `manager.full_name` (`— (exempt)` when `manager` is `null`, i.e. the System Admin) |
| **Team** | `teams[]` (one or more; may be empty → `—`) |
| **Status** | `is_active` (+ last-login for Active-vs-Invited; see [Status](#status)) |

**Write-only fields** (accepted on create/update, never returned): `password`
(ignored on create — set via the activation link), `role_id` (Role UUID to assign),
`manager_id` (manager's user UUID, or `null`), and the flat profile writes `phone`,
`mobile`, `location`, `bio`.

- `role` / `manager` / `teams` / `profile` are **read-only** derived fields.
- `role` = the member's single assigned role; `manager` = the manager on the active
  hierarchy row; `teams` = all team memberships.

---

## Part 3 — Member actions

| Action | Method | Path | Permission |
| :--- | :--- | :--- | :--- |
| List members | GET | `/api/v1/management/users/` | `view_user_management` |
| Retrieve one | GET | `/api/v1/management/users/{user_id}/` | `view_user_management` |
| **Invite member** (create) | POST | `/api/v1/management/users/` | `create_user_management` |
| **Edit member** | PATCH / PUT | `/api/v1/management/users/{user_id}/` | `update_user_management` |
| **Deactivate / Activate** | PATCH | `/api/v1/management/users/{user_id}/` (`is_active`) | `update_user_management` |
| **Delete member** | DELETE | `/api/v1/management/users/{user_id}/` | `delete_user_management` |
| Set / change reporting manager | PATCH | `/api/v1/management/users/{user_id}/manager/` | `manage_hierarchy` |
| Resend activation email | POST | `/api/v1/auth/activate-account/resend/` | admin (`create_user`) |

`{user_id}` is the user UUID (`lookup_field = "user_id"`). List & retrieve are
cached 300s (varies by user + org); writes bump the cache version.

### Invite member (create)

```
POST /api/v1/management/users/
```

```json
{
  "user_id": "u-9999…",
  "email": "new.hire@kairali.in",
  "first_name": "New",
  "last_name": "Hire",
  "role_id": "r-abcd…",
  "manager_id": "u-5678…",
  "phone": "+91…"
}
```

- `user_id` and `email` are **required**; `username` defaults to the email.
- The member is created **inactive** (`is_active=false`) and an **activation
  email** is sent; the invitee sets their own password via that link (any
  `password` in the body is ignored). This is the "Invited" state on the list.
- `role_id` assigns the role; `manager_id` sets the reporting manager (and the
  hierarchy row). Both optional.

**201 Response** (wrapped, with the created member under `user`):

```json
{
  "message": "User created. Activation email sent.",
  "user": { "...": "the member object above" }
}
```

If the activation email fails to queue, the member is still created and the
response adds `"email_warning": "Failed to send activation email. You can resend it later."`
(and the message becomes "User created but activation email could not be sent.").

**400s:** duplicate `email` / `user_id` →
`{"email": ["A user with this email already exists."]}` (likewise `user_id`).

### Edit member

```
PATCH /api/v1/management/users/{user_id}/
```

Update any of `first_name`, `last_name`, `email`, `role_id`, `manager_id`, the
profile writes (`phone`, `mobile`, `location`, `bio`), and `is_active` / `is_staff`.
`PUT` for a full replace, `PATCH` for partial. **200** with the member object.

- Changing `role_id` **replaces** the member's existing role.
- Changing `manager_id` closes the current hierarchy row and opens a new one,
  recalculating the subordinate subtree's levels.
- **`is_staff` (admin rights)** may only be changed by an admin (`is_staff` caller);
  a non-admin attempting it gets **403**
  `{"detail": "Only admin users can grant or revoke admin privilege."}`.
- Optional `notify_via_email: true` sends the member an email when their
  active/inactive status changes.

### Deactivate / Activate

Deactivation is a PATCH setting `is_active: false` (Activate = `is_active: true`):

```
PATCH /api/v1/management/users/{user_id}/
{ "is_active": false }
```

Two guards run **before** the change (both inside one transaction; on a block
nothing is written):

- **Hierarchy re-parenting (§3.2.5).** If the member manages others, their direct
  reports are re-parented to the member's own manager (grandparent). When that
  would produce an invalid tree — the member has **no** manager (§3.2.1) or the
  grandparent is the System Admin and a report is non-admin (§3.2.3) — the request
  is **blocked with 409** so an admin can pick a new manager first:

  ```json
  { "code": "no_manager",
    "detail": "This user has no manager, so their direct reports cannot be automatically re-parented. …",
    "reports": [ { "user_id": "…", "full_name": "…" } ] }
  ```

  (`code` is `no_manager` or `system_admin_parent`; `reports` lists the affected
  direct reports.)

- **Sole-System-Admin floor (§2.2, §13.6.4).** Deactivating the tenant's **only
  active** System Admin (`is_staff=true, is_active=true`, no other active admin) is
  **blocked with 409** — an inactive admin does not count as a fallback:

  ```json
  { "code": "last_system_admin",
    "detail": "Cannot deactivate the only active System Admin. Assign System Admin rights to another active user first, or use the System Admin transfer flow." }
  ```

The same `last_system_admin` guard also blocks **revoking admin rights**
(`is_staff: false`) from the last active admin (`action` reads "remove admin rights
from"), and **deleting** the last active admin (below).

### Delete member

```
DELETE /api/v1/management/users/{user_id}/
```

**204** on success. Before deletion, the member's direct reports are re-parented
(same §3.2.5 rules and 409 blocks as Deactivate) and the sole-System-Admin floor
is enforced (`last_system_admin` 409). This matters because
`UserHierarchy.manager` is `on_delete=CASCADE` — a bare delete would orphan the
reports' hierarchy rows.

### Set / change reporting manager

The "Reports to" column can also be changed directly (independently of Edit):

```
PATCH /api/v1/management/users/{user_id}/manager/
{ "manager_id": "u-5678…" }
```

Closes the current active hierarchy row and opens a new one; recalculates the
subtree's levels. `manager_id: null` makes the member top-level (no manager).
**400** guards: self-management (`User cannot be their own manager.`), a **circular**
hierarchy (`This would create a circular hierarchy.`), and depth > 10
(`Hierarchy depth cannot exceed 10 levels.`). A `manager_id` not in the org → **404**.

### Resend activation email

For a member still in the "Invited" state:

```
POST /api/v1/auth/activate-account/resend/
{ "email": "new.hire@kairali.in" }      // or { "user_id": "u-9999…" }
```

Admin-only. Re-queues the activation email for an **inactive** user in the caller's
org. (The activation link itself is confirmed via
`POST /api/v1/auth/activate-account/confirm/` with `{uid, token, password}` — that
is the invitee's flow, not an admin action.)

---

## Notes on the "Reports to" visibility sub-label

The small sub-label under each role ("Organization-wide", "Self + Reporting
Hierarchy", "Team-based + Reporting Hierarchy") is the member's **visibility
scope** (§3.4.1). On the **detail** response it is now available directly as the
**`scope`** field (`{code, label}`, derived from the broadest `lead`-module
`RecordPermission.permission_type` across the member's roles; superuser/staff →
`all`). On the **list** response `scope` is omitted (N+1 guard) — there, derive
the badge from the role's `RecordPermission.permission_type` via the role
endpoint as before.

`— (exempt)` in "Reports to" means the member has no manager (`manager: null`) —
by rule only the **System Admin** is exempt (§3.2.1).

---

## Part 4 — Member detail page

The **Members → {member}** detail page (header, Member information, Performance &
records, Activity log). The **Availability** calendar is **not backed yet —
coming soon** (no attendance/leave model or endpoint exists).

### 4.1 Header + Member information — `GET /management/users/{user_id}/`

The enriched retrieve response (member object above) backs the header and the
Member-information block:

| UI line | Field |
| :--- | :--- |
| Name / avatar initials | `full_name`, `first_name`/`last_name` |
| Active / inactive | `is_active` |
| "ACCOUNT: Protected" badge | `is_protected` (`true` for superuser/staff) |
| Designation | `profile.designation` (new field; migration `accounts/0004`) |
| Email / Phone | `email` / `profile.phone` |
| Role & scope | `role.name` + `scope.label` (e.g. "System Admin" + "Organization-wide") |
| Reporting manager | `manager` (`null` → "— (top of hierarchy)") |
| Team | `teams[]` (`[]` → "No team") |
| Territory | `territories[]` — territories this user **manages** (`Territory.manager`; there is no per-user territory assignment — territory is a Lead attribute, §5.1.1) |
| Timezone | `profile.timezone` (raw IANA tz; the "(IST)" suffix is frontend-rendered) |

`designation` is writable via the profile serializers / `PATCH /users/{id}/`.

### 4.2 Performance & records — `GET /crm/dashboard-crm/member-performance/`

Owned-lead metrics for one user, **date-range filtered**.

- **Query:** `user_id` (required), `period` (default `this_month`), `from`/`to`
  (when `period=custom`).
- **Periods:** `this_month`, `last_month`, `this_quarter`, `last_quarter`,
  `ytd` (≈ "This year"), `all_time`, `last_30_days`, `last_90_days`, `week`,
  `custom`. (`last_quarter` = "Previous quarter" and `all_time` = "All time" were
  added for this page.)
- **Permission:** Admin, a team manager over the user, or self
  (`can_access_user_kpis`). Cached 120s.

**Response `200`:**

```json
{
  "user_id": "…",
  "period": "all_time",
  "owned_leads": { "open": 12, "closed": 8, "total": 20 },
  "deals_won": 5,
  "deal_value_won": "450000.00",
  "conversion_rate": 62.5
}
```

Definitions (leads **owned** by the user, `Lead.lead_owner`, filtered on
`created_at` except `all_time`):
- `owned_leads.open` — not converted, not lost, not archived.
- `owned_leads.closed` — won (converted) + lost.
- `deals_won` — won (converted) count.
- `deal_value_won` — Σ active `Payment.total_amount` on the user's won leads (₹).
- `conversion_rate` — won / (won + lost) × 100 over **decided** leads; `null`
  when nothing is decided in the range.

> Distinct from `GET /crm/dashboard-crm/user-kpis/` (new-leads / win-rate /
> first-response / quote KPIs). The member page's Performance block uses
> `member-performance/`.

### 4.3 Activity log — `GET /management/users/{user_id}/activity/`

Perm `view_user_management`. Query `?limit=<n>` (default 20, max 100).

Reverse-chronological feed composed from reliable lifecycle events + best-effort
audit rows:

```json
{
  "results": [
    { "type": "login",  "label": "Signed in",           "actor": "Manoj Varma", "timestamp": "…" },
    { "type": "role_assign", "label": "Role updated",    "actor": "Admin",       "timestamp": "…" },
    { "type": "joined", "label": "Joined the workspace", "actor": "Manoj Varma", "timestamp": "…" }
  ]
}
```

- `joined` — `User.date_joined`. Always present.
- `login` — `User.last_login` (most recent sign-in). Present once signed in.
- change events — `AuditLog` rows about this user
  (`model_name="User", record_id=user_id`): role assignments, updates.

> **Reliability:** joined/login come straight off the `User` row and always
> render. The audit change-rows are written **asynchronously by the Celery
> worker** — absent if it's down, but the feed still shows joined/login.
> `User.last_login` (not `AuditLog`) is the authoritative sign-in signal.

### 4.4 Availability — coming soon

The Availability heatmap (full-day / half-day / on-leave / weekend per member) has
**no backend** — no attendance/leave model or endpoint. Render "coming soon" until
a leave/attendance system is designed.

### Quick reference (detail page)

| Need | Call |
| :--- | :--- |
| Header + member info + role/scope | `GET /management/users/{user_id}/` |
| Performance block (with period) | `GET /crm/dashboard-crm/member-performance/?user_id=…&period=…` |
| Activity feed | `GET /management/users/{user_id}/activity/?limit=…` |
| Availability | — (coming soon; no endpoint) |
