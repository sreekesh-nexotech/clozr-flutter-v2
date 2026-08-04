# Module Access API — sidebar & dashboard gating (frontend)

**What this is for:** one call the frontend makes right after login to learn **which
modules the current user may see**, so it can render the **sidebar** and decide
**which dashboard** to show. It returns a ready-to-use, per-module CRUD map — the
frontend does **not** need to re-derive permissions from roles.

> TL;DR — call `GET /api/v1/auth/me/modules/`, render a sidebar item for each entry
> in `sidebar`, and gate buttons with the `can_*` flags in `modules`. Show the admin
> **Settings** area only if `modules.settings` exists, and the admin **Dashboard**
> only if `modules.dashboard` exists. The backend already applies the "admins &
> Executive Leadership get Settings + Dashboard, nobody else does" rule — trust it.

**Base prefix:** `/api/v1/auth/`
**Auth:** `Authorization: Bearer <JWT>`. The org is resolved from the token
(`organization_id` claim); the response is scoped to the current user in that org.
**Self-serve:** every authenticated user reads their **own** access — no admin
permission required.
**Rate limit:** 60/min per user.
**Cache:** response is cached 5 min per (user, org). It refreshes automatically when
the user's roles/permissions change (cache is version-keyed on `user:*`/`org:*`).

---

## Endpoint

### `GET /api/v1/auth/me/modules/`

No query params. Returns the current user's effective module-access map.

```jsonc
{
  "is_staff": false,          // true = system admin (Django is_staff)
  "is_superuser": false,
  "full_access": false,       // is_staff || is_superuser → sees every module
  "has_subordinates": true,   // user manages ≥1 person → show "My Team" views
  "roles": ["Executive Leadership"],   // the user's role names (display)
  "modules": {                // ONLY modules the user can at least read
    "dashboard": { "label": "Dashboard", "can_read": true, "can_create": true,
                   "can_update": true, "can_delete": true, "can_export": true,
                   "can_import": true, "can_approve": true },
    "lead":      { "label": "Lead", "can_read": true, "can_create": true,
                   "can_update": true, "can_delete": true, "can_export": true,
                   "can_import": true, "can_approve": true },
    "task":      { "label": "Task", "can_read": true, "...": "..." },
    "settings":  { "label": "Settings", "can_read": true, "...": "..." }
    // ... one entry per module the user can see
  },
  "sidebar": [                // module keys in display order (see below)
    "dashboard", "lead", "task", "followup", "customer", "quotation",
    "payment", "contact", "organization_contact", "product", "call_log",
    "report", "project", "project_task", "settings"
  ]
}
```

### Field reference

| Field | Type | Meaning |
| :--- | :--- | :--- |
| `is_staff` | bool | The user is a **System Admin** (Django `is_staff`). Bypasses all RBAC → gets every module. |
| `is_superuser` | bool | Platform superuser. Same effect as `is_staff` here. |
| `full_access` | bool | Convenience: `is_staff || is_superuser`. When `true`, `modules` contains **every** module with full CRUD. |
| `has_subordinates` | bool | The user manages at least one person (they are a manager in the reporting hierarchy). **Use this to show/hide "My Team" views** (e.g. Goals & Rewards → My Team). `true` for full-access users (they see the whole org). See ["My Team" gating](#my-team-vs-my-progress-goals--rewards) below. |
| `roles` | string[] | The user's role names (highest privilege first). Display / debugging only — **don't** gate UI on role names; gate on `modules`. |
| `modules` | object | Map of `module_name → { label, can_read, can_create, can_update, can_delete, can_export, can_import, can_approve }`. **Only modules the user can at least read are present.** A missing key means "no access — don't render it." |
| `sidebar` | string[] | The keys of `modules` in a sensible nav order: `dashboard` first, `settings` last, everything else in between. Convenience so the FE doesn't sort. |

The seven `can_*` flags are the same CRUD verbs the backend enforces per request.
Use them to show/hide **buttons** inside a module (e.g. hide "Delete" when
`can_delete` is false). Presence of the key itself is what gates the **sidebar
entry** / route.

---

## How to use it

```ts
// after login (and after every token refresh is fine — it's cached server-side)
const access = await api.get("/auth/me/modules/");

// 1. Sidebar: render one item per key, in order.
access.sidebar.forEach(key => renderNavItem(key, access.modules[key].label));

// 2. Admin areas — gate on presence, not on role name:
const showSettings   = "settings"  in access.modules;   // admins + Exec Leadership
const showAdminDash  = "dashboard" in access.modules;    // admins + Exec Leadership

// 3. Buttons inside a module:
const canDeleteLeads = access.modules.lead?.can_delete === true;

// 4. Route guard: block a route if its module key isn't present.
function canOpen(moduleKey: string) {
  return moduleKey in access.modules;
}
```

**Do**
- Treat a **missing** module key as "hide it." The list is already filtered to
  readable modules.
- Gate the admin **Settings** and **Dashboard** shells on
  `"settings" in modules` / `"dashboard" in modules`.
- Re-fetch after the user's roles change (e.g. an admin edits them) — or just
  re-fetch on app load / token refresh; it's cheap and cached.

**Don't**
- Don't hard-code "if role == 'Executive Leadership' show settings" on the client.
  The backend already decides this (see the rule below) and may change it without a
  frontend release. Always read `modules`.
- Don't assume `modules` contains every module — regular users get a short list.
- Don't rely on the JWT for permissions — the token carries only `user_id` and
  `organization_id`, **no** roles/permissions. This endpoint is the source of truth.

---

## "My Team" vs "My Progress" (Goals & Rewards)

The **Goals & Rewards** module (`milestone`) is visible to **every** user, but its
tabs are gated by *who reports to you* and *your role* — not by the module key alone.
Use these signals from this same response:

| Tab | Show it when | Backing endpoint |
| :--- | :--- | :--- |
| **My Progress** | always (any user with the `milestone` module) | `GET /api/v1/milestones/progress/` — returns the caller's own rows |
| **My Team** | `has_subordinates === true` | same `/progress/` — the backend widens the rows to the caller's reporting subtree automatically |
| **Approvals** | `is_staff \|\| is_superuser \|\| roles.includes("Executive Leadership")` | `GET /api/v1/milestones/rewards/` + approve/reject actions |

```ts
const showMyProgress = "milestone" in access.modules;         // everyone with the module
const showMyTeam     = access.has_subordinates === true;      // managers only
const showApprovals  =
  access.full_access || access.roles.includes("Executive Leadership");
```

Notes:
- **You don't need a separate call** to know if the user manages anyone —
  `has_subordinates` is included here. (There's also
  `GET /api/v1/management/hierarchy/subordinates/`, but it's admin-gated on
  `view_hierarchy`, so a normal user can't call it — use `has_subordinates` instead.)
- The backend **enforces** all three regardless of what the UI shows: `/progress/`
  is always scoped (own → subtree → all), and approve/reject reject a non-manager
  with 403. Hiding the tabs is a UX nicety, not the security boundary.
- **Authoring** milestones (create/edit/delete, `/milestones/`, `/tracks/`,
  `/steps/`, `/settings/`) stays admin/Exec-only — a normal user gets 403 there by
  design. Gate any "create milestone" UI on `access.modules.milestone?.can_create`.

---

## The access rules (what the backend decides for you)

The map is computed server-side by merging every role the user holds (the **most
permissive** flag wins across roles), then applying two overlays:

1. **Full-access users** — `is_staff` or `is_superuser` → **every** module with full
   CRUD. (These users bypass the whole RBAC engine.)
2. **Admin shell** — the `settings` and `dashboard` modules are **forced on** for:
   - full-access users (System Admins), **and**
   - anyone holding the **Executive Leadership** role.

   **Every other user** gets `settings` / `dashboard` only if their roles explicitly
   grant them — which the seeded roles do **not**. So in practice:

   | User | Settings | Dashboard | Other modules |
   | :--- | :---: | :---: | :--- |
   | System Admin (`is_staff`) | ✅ | ✅ | all |
   | Executive Leadership | ✅ | ✅ | all except Integrations write |
   | CRM User | ❌ | ❌ | CRM modules only |
   | PMO User | ❌ | ❌ | Project modules only |
   | Custom role | ❌* | ❌* | whatever the role grants |

   \* unless the custom role was explicitly given the `settings` / `dashboard` module.

> Why the overlay exists: Executive Leadership is seeded **without** the `settings`
> module (they must not manage Integrations), and `dashboard` is an admin-only module
> that isn't seeded to normal roles. The product decision is that leadership still
> lands on the admin dashboard and can open Settings, so the backend layers those two
> modules on top of the raw role grants — the frontend just reads the result.

---

## Module keys & labels

`modules` / `sidebar` use these stable `module_name` keys (labels are the `label`
field, provided so you don't hard-code display strings):

**CRM:** `lead`, `task`, `followup`, `customer`, `quotation`, `payment`, `contact`,
`organization_contact`, `product`, `call_log`, `report`, `issue`
**Projects (PMO):** `project`, `project_task`
**Admin / system:** `dashboard`, `settings`, `user_management`, `role`,
`organization`, `hierarchy`, `team`, `audit_log`, `automation`, `milestone`
**LMS:** `course`, `lms_module`, `quiz`, `course_enrollment`

Keys are the single source of truth (`ModulePermission.MODULE_CHOICES`); new modules
appear here automatically. If a key you don't recognize shows up, fall back to its
`label`.

---

## Related endpoints (for context — not needed for sidebar gating)

- `GET /api/v1/auth/me/` — the current user profile + role list (no permissions).
- `GET /api/v1/management/users/<user_id>/permissions/` — the **raw** aggregated
  role permissions for a user (admin tool; a user may read their own). This returns
  the un-overlaid role rows (no `settings`/`dashboard` overlay, empty for `is_staff`
  users) and a `record_permissions` breakdown — use it for the **role/permission
  admin UI**, not for rendering the sidebar. For the sidebar, always use
  `/auth/me/modules/`.
- `GET /api/v1/management/permissions/module-catalog/` — the static grantable-module
  taxonomy for the **role-editor** modal (admin-gated). Not per-user.

---

## Notes / edge cases

- **No org context** (a token without `organization_id`) → `400`. Normal logins
  always carry it.
- **Unauthenticated** → `401`.
- The endpoint never returns a module the user cannot **read**; a role that somehow
  grants only `can_export` without `can_read` is filtered out (won't render).
- Record-level visibility (which *rows* a user sees within a module — owned / team /
  hierarchy) is **not** part of this response; it's enforced per-request by the API.
  This endpoint answers only "which modules render at all."
