# Roles & Permissions API

Backing for **People → Roles & Permissions**: the seeded/custom role list, the role
detail (visibility scope + capability cards), the **Add role** / **Edit role**
modals, and delete.

Two kinds of role:

- **Seeded** (`is_custom: false`) — created when the org registers (Admin, Manager,
  User, Telecaller; surfaced in the UI as System Admin / Executive Leadership / …).
  **Non-editable and non-deletable.**
- **Custom** (`is_custom: true`) — created by the org. Editable and deletable (when
  no members are assigned).

Capabilities are grouped into **business-module cards** (CRM, PMO; Helpdesk/HRMS/…
are `coming_soon`). A role grants a card as a bundle — full CRUD on every module in
the group plus a record-level **visibility scope** (`all` / `hierarchy` / `team`)
chosen per group, with optional per-module overrides. The card catalog comes from
the module-catalog endpoint; the flat module list is a developer registry
(`access_control/module_groups.py`).

**Base prefix:** `/api/v1/management/`
**Auth (all endpoints):** `Authorization: Bearer <JWT>`. Org is resolved from the
token (`request.org`) and scopes every response. `Content-Type: application/json`
on writes. No CSRF (token auth, not session).
**Permissions:** `MapBasedPermission` against `<action>_role` codenames
(`view_role`, `create_role`, `update_role`, `delete_role`). Superusers/`is_staff`
bypass.
**Rate limit:** 60/min per user (all role endpoints).
**Pagination:** `StandardResultsSetPagination` — page size 100, `?page=` /
`?page_size=` (max 200); envelope `{count, next, previous, results}`.

---

## The role object

Returned by list / retrieve / create / update:

```jsonc
{
  "role_id": "d34ed887-89ae-4155-9b0d-e70cb4de2133",
  "name": "Manager",
  "description": "Oversees a team's pipelines, approvals and reports.",
  "is_custom": true,          // false = seeded
  "is_seeded": false,         // convenience = !is_custom (read-only)
  "is_editable": true,        // custom roles only
  "is_deletable": true,       // custom AND no members assigned
  "is_active": true,
  "permission_level": 40,
  "user_count": 1,            // members holding this role
  "users": [
    { "user_id": "u-…", "full_name": "Arjun Nair", "email": "arjun@acme.com" }
  ],
  "module_permissions": [     // per-module CRUD (flat)
    { "module_name": "lead", "can_read": true, "can_create": true,
      "can_update": true, "can_delete": true, "can_export": true,
      "can_import": true, "can_approve": true }
  ],
  "record_permissions": [     // per-module visibility scope (flat)
    { "module_name": "lead", "permission_type": "hierarchy",
      "can_read": true, "can_update": true, "can_delete": true, "can_share": true }
  ],
  "grouped_permissions": [    // the same perms folded into cards (for the edit modal)
    { "group": "crm", "modules": [
        { "module_name": "lead", "can_read": true, "can_create": true,
          "can_update": true, "can_delete": true, "can_export": true,
          "can_import": true, "can_approve": true, "permission_type": "hierarchy" }
    ]}
  ]
}
```

- `is_custom` is **read-only / server-set** — a client cannot forge a seeded role or
  flip the flag; it is always `true` for API-created roles.
- `is_seeded` / `is_editable` / `is_deletable` are read-only UI signals so the
  frontend renders the SEEDED / NON-DELETABLE / CUSTOM badges and enables/disables
  the Edit & Delete buttons without hardcoding the rule.
- `module_groups` is a **write-only** input field (see Create/Update); it never
  appears in responses — read the stored perms back via `grouped_permissions`.

---

## 1. Module-group catalog (populate the capability cards)

- **Name / purpose:** The grantable business-module cards (CRM, PMO, …) the Add/Edit
  role modal renders, with each card's member modules and the selectable visibility
  scopes. Static, org-agnostic (a code registry).
- **Method + path:** `GET /api/v1/management/permissions/module-catalog/`
- **Headers:** `Authorization: Bearer <JWT>`.
- **Path / query params:** none.
- **Request body:** none.
- **Success response — 200:**

```json
{
  "groups": [
    { "key": "crm", "label": "CRM", "description": "Leads, customers, quotes & payments",
      "coming_soon": false,
      "modules": [
        { "module_name": "lead", "label": "Lead" },
        { "module_name": "customer", "label": "Customer" }
      ] },
    { "key": "pmo", "label": "PMO", "description": "Projects & project tasks",
      "coming_soon": false,
      "modules": [
        { "module_name": "project", "label": "Project" },
        { "module_name": "project_task", "label": "Project Task" }
      ] }
  ],
  "default_module_crud": {
    "can_read": true, "can_create": true, "can_update": true, "can_delete": true,
    "can_export": true, "can_import": true, "can_approve": true
  },
  "visibility_scopes": [
    { "value": "all", "label": "All Records" },
    { "value": "owned", "label": "Owned Records" },
    { "value": "assignee", "label": "Assigned Records" },
    { "value": "team", "label": "Team Records" },
    { "value": "hierarchy", "label": "Hierarchy Records" },
    { "value": "filtered", "label": "Filtered Records" }
  ]
}
```

- **Error responses:**
  - `401` `{ "detail": "Authentication credentials were not provided." }`
  - `403` `{ "detail": "You do not have permission to perform this action." }`
    (needs `manage_role` or `view_settings`)
- **Pagination:** none (single static payload).

> `coming_soon: true` groups are shown as locked cards; granting one is rejected on
> create/update (see §3 errors). CRM and PMO are the only enabled groups today.

---

## 2. List roles

- **Name / purpose:** The left-hand role list (seeded + custom) with member counts.
- **Method + path:** `GET /api/v1/management/roles/`
- **Headers:** `Authorization: Bearer <JWT>`.
- **Query params:**

  | Param | Type | Description |
  | :--- | :--- | :--- |
  | `is_custom` | bool | `true` = custom only, `false` = seeded only |
  | `is_active` | bool | active/inactive filter |
  | `permission_level` | int | exact match |
  | `created_by` | user PK | exact match |
  | `search` | string | matches `name`, `description` |
  | `ordering` | string | `name`, `permission_level` (prefix `-` for desc). Default `permission_level, name`. |
  | `page` / `page_size` | int | pagination (size default 100, max 200) |

- **Request body:** none.
- **Success response — 200:**

```json
{
  "count": 5,
  "next": null,
  "previous": null,
  "results": [
    { "role_id": "…", "name": "Admin", "is_custom": false, "is_seeded": true,
      "is_editable": false, "is_deletable": false, "permission_level": 100,
      "user_count": 1, "users": [ … ], "module_permissions": [ … ],
      "record_permissions": [ … ], "grouped_permissions": [ … ] }
  ]
}
```

- **Error responses:** `401` (unauthenticated); `403` (missing `view_role`).
- **Pagination:** yes (envelope above). Cached 300s per user + org.

---

## 3. Create a custom role (Add role)

- **Name / purpose:** Create a new custom role from the Add-role modal.
- **Method + path:** `POST /api/v1/management/roles/`
- **Headers:** `Authorization: Bearer <JWT>`, `Content-Type: application/json`.
- **Path / query params:** none.
- **Request body (recommended — group-based):**

```json
{
  "name": "Regional Lead",
  "description": "Handles the north region pipeline.",
  "permission_level": 40,
  "module_groups": [
    { "group": "crm", "visibility": "hierarchy",
      "module_overrides": {
        "payment": { "can_delete": false, "permission_type": "owned" }
      } },
    { "group": "pmo", "visibility": "team" }
  ]
}
```

- `module_groups[]` — one entry per checked card:
  - `group` (required) — a catalog group key (`crm` / `pmo`).
  - `visibility` (default `all`) — the record scope for **this** group
    (`all` / `hierarchy` / `team` / `owned` / `assignee` / `filtered`).
  - `module_overrides` (optional) — `{ <module_name>: { …crud…, "permission_type": … } }`
    to override CRUD and/or scope for specific modules **within** that group.
- A group grant expands to a `ModulePermission` (full CRUD by default) **and** a
  `RecordPermission` (group scope) for every module in the group; only granted
  modules get rows.
- `is_custom` is ignored if sent — created roles are always custom.
- The flat `module_permissions` / `record_permissions` arrays are also accepted (for
  power use) and layer **on top** of the group expansion.

- **Success response — 201:** the created role object (see [role object](#the-role-object)).
- **Error responses:**
  - `400` unknown / coming-soon group:
    ```json
    { "module_groups": [ { "group": ["Module group 'helpdesk' is not available yet."] } ] }
    ```
  - `400` override targets a module not in the group, an unknown override key, or an
    invalid `visibility`/`permission_type`:
    ```json
    { "module_groups": [ { "module_overrides": ["'project' is not a module of group 'crm'."] } ] }
    ```
  - `400` duplicate role name (unique per org):
    `{ "name": ["role with this name already exists."] }`
  - `401` / `403` (missing `create_role`).
- **Pagination:** n/a.

---

## 4. Retrieve one role

- **Name / purpose:** Role detail pane (scope + capability cards).
- **Method + path:** `GET /api/v1/management/roles/{role_id}/`
- **Headers:** `Authorization: Bearer <JWT>`.
- **Path params:** `role_id` (UUID).
- **Request body:** none.
- **Success response — 200:** the role object.
- **Error responses:** `401`; `403` (missing `view_role`); `404`
  `{ "detail": "No Role matches the given query." }` (unknown / other-org role).
- **Pagination:** n/a. Cached 300s per user + org.

---

## 5. Update / edit a role (Edit role)

- **Name / purpose:** Edit a **custom** role's name, description, scope, or
  capabilities. Seeded roles are rejected.
- **Method + path:** `PATCH /api/v1/management/roles/{role_id}/` (partial) or
  `PUT /api/v1/management/roles/{role_id}/` (full).
- **Headers:** `Authorization: Bearer <JWT>`, `Content-Type: application/json`.
- **Path params:** `role_id` (UUID).
- **Request body:** same shape as create — send `module_groups` (recommended) to
  replace the capability set, and/or `name` / `description` / `permission_level` /
  `is_active`. Supplying `module_groups` (or the flat arrays) **replaces** the
  role's existing module/record permissions.

```json
{
  "description": "Updated responsibilities.",
  "module_groups": [
    { "group": "crm", "visibility": "team" },
    { "group": "pmo", "visibility": "team" }
  ]
}
```

- **Success response — 200:** the updated role object.
- **Error responses:**
  - `403` editing a seeded role:
    ```json
    { "detail": "Seeded roles cannot be edited. Create a custom role instead." }
    ```
  - `400` — same `module_groups` validation errors as create; duplicate name.
  - `401`; `403` (missing `update_role`); `404`.
- **Pagination:** n/a.

---

## 6. Delete a role

- **Name / purpose:** Delete a **custom** role. Seeded roles, and custom roles that
  still have members, are rejected.
- **Method + path:** `DELETE /api/v1/management/roles/{role_id}/`
- **Headers:** `Authorization: Bearer <JWT>`.
- **Path params:** `role_id` (UUID).
- **Request body:** none.
- **Success response — 204:** empty body.
- **Error responses:**
  - `403` deleting a seeded role:
    ```json
    { "detail": "Seeded roles cannot be deleted." }
    ```
  - `409` role still has members (`UserRole` FK is CASCADE — a bare delete would
    strip those users of their role):
    ```json
    { "code": "role_in_use",
      "detail": "Cannot delete this role while 3 member(s) are assigned to it. Reassign or remove those members first.",
      "member_count": 3 }
    ```
  - `401`; `403` (missing `delete_role`); `404`.
- **Pagination:** n/a.

> The UI can pre-disable the Delete button using `is_deletable` (false for seeded
> roles and for custom roles with `user_count > 0`); the 403/409 above are the
> server-side enforcement.

---

## 7. Related permission endpoints (fine-grained, optional)

Roles bundle permissions, but the individual `ModulePermission` / `RecordPermission`
rows are also directly manageable (admin tooling; the role modal doesn't need them):

| Purpose | Method + path | Permission |
| :--- | :--- | :--- |
| List / CRUD module (CRUD) permissions | `…/permissions/modules/` | `manage_role` or `view_settings` (writes: `update_settings`) |
| Module perms for one role | `GET …/permissions/modules/by_role/?role_id=<uuid>` | same |
| List / CRUD record (visibility) permissions | `…/permissions/records/` | same |
| Record perms for one role | `GET …/permissions/records/by_role/?role_id=<uuid>` | same |
| Record perms for one module | `GET …/permissions/records/by_module/?module_name=<name>` | same |
| Effective permissions for a user | `GET …/users/{user_id}/permissions/` | — |
| Assign roles to a user | `POST …/users/{user_id}/roles/` | — |

These share the same auth / rate limit / pagination conventions. Base prefix
`/api/v1/management/`.

---

## Notes for the frontend

- **Badges:** `is_seeded` → `SEEDED`; seeded → also `NON-DELETABLE`; `!is_custom`
  hides Edit/Delete. `is_custom` → `CUSTOM`.
- **Member count** per role = `user_count`; the expanded member list = `users[]`.
- **Visibility scope** picker maps to `permission_type` on the record perms
  (`all` = Organization-wide, `hierarchy` = Self + Reporting Hierarchy, `team` =
  Team-based + Reporting Hierarchy). The System Admin (Admin seeded role) is always
  Organization-wide and cannot be changed — it's seeded, so Edit is disabled.
- **Admin-only cards** (User Management, Settings, Integrations, Billing) are **not**
  in the module-catalog groups — they're governed by the `is_staff` bypass, not by
  grantable role permissions, so they render as fixed/locked on the frontend.
