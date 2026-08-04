# Team Management API

Base URL: `/api/v1/management/`

All endpoints require authentication. The authenticated user's organization is resolved from the request (`request.org`) and used to scope all team operations. Permissions are enforced via `MapBasedPermission` against the actions listed in each endpoint.

Pagination (where applicable):
- `page_size` default: `100`, max: `200`
- Query params: `?page=<n>&page_size=<n>`

Common filtering / search params on list endpoints are noted per endpoint.

---

## 1. Teams

Routed via DRF router under `teams/`. Lookup field: `team_id` (UUID).

### 1.1 List Teams

- **Method / URL:** `GET /api/v1/management/teams/`
- **Permission:** `view_team`
- **Cache:** 300s, varies by user + org
- **Rate limit:** 60/min per user

**Query Parameters**

| Param | Type | Description |
|---|---|---|
| `search` | string | Searches `name`, `description` |
| `ordering` | string | `name`, `created_at` (prefix with `-` for desc); default `name` |
| `created_at` | datetime | Exact filter |
| `manager_id` | int (manager FK PK) | Filter by manager |
| `page` | int | Page number |
| `page_size` | int | Page size (max 200) |

**Response 200**

```json
{
  "count": 2,
  "next": null,
  "previous": null,
  "results": [
    {
      "team_id": "b1d2c3e4-5f67-4890-aaaa-bbbbbbbbbbbb",
      "name": "Sales East",
      "description": "East region sales team",
      "manager_id": "8c1d3e2a-1111-2222-3333-444444444444",
      "manager": {
        "user_id": "8c1d3e2a-1111-2222-3333-444444444444",
        "full_name": "Jane Doe",
        "email": "jane.doe@example.com"
      },
      "created_at": "2026-04-12T09:30:21.123456Z",
      "updated_at": "2026-05-01T14:11:08.901234Z"
    }
  ]
}
```

---

### 1.2 Create Team

- **Method / URL:** `POST /api/v1/management/teams/`
- **Permission:** `create_team`
- **Rate limit:** 60/min per user

**Request Body**

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string (≤200) | Yes | Team name (unique per org) |
| `description` | string | No | Free text |
| `manager_id` | UUID (`user_id`) | No | Manager user; must belong to caller's org |
| `member_ids` | UUID[] (`user_id`) | No | Write-only. Users to add as team members; must belong to caller's org |

**Example Request**

```json
{
  "name": "Sales East",
  "description": "East region sales team",
  "manager_id": "8c1d3e2a-1111-2222-3333-444444444444",
  "member_ids": [
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222"
  ]
}
```

**Response 201**

```json
{
  "team_id": "b1d2c3e4-5f67-4890-aaaa-bbbbbbbbbbbb",
  "name": "Sales East",
  "description": "East region sales team",
  "manager_id": "8c1d3e2a-1111-2222-3333-444444444444",
  "manager": {
    "user_id": "8c1d3e2a-1111-2222-3333-444444444444",
    "full_name": "Jane Doe",
    "email": "jane.doe@example.com"
  },
  "created_at": "2026-05-14T10:00:00.000000Z",
  "updated_at": "2026-05-14T10:00:00.000000Z"
}
```

**Error Responses**
- `400` — Validation error (e.g., duplicate name within org, invalid `manager_id`/`member_ids`)
- `403` — Missing `create_team` permission
- `429` — Rate limit exceeded

---

### 1.3 Retrieve Team

- **Method / URL:** `GET /api/v1/management/teams/{team_id}/`
- **Permission:** `view_team`
- **Cache:** 300s, varies by user + org

**Response 200** — same shape as the create response above.

**Errors**
- `404` — Team not found in caller's org

---

### 1.4 Update Team (Full)

- **Method / URL:** `PUT /api/v1/management/teams/{team_id}/`
- **Permission:** `update_team`

**Request Body** — all updatable fields (same as create). Providing `member_ids` **replaces** the entire member set.

```json
{
  "name": "Sales East - Renamed",
  "description": "Updated description",
  "manager_id": "8c1d3e2a-1111-2222-3333-444444444444",
  "member_ids": [
    "11111111-1111-1111-1111-111111111111"
  ]
}
```

**Response 200** — updated team object (same shape as retrieve).

---

### 1.5 Partial Update Team

- **Method / URL:** `PATCH /api/v1/management/teams/{team_id}/`
- **Permission:** `update_team`

**Request Body** — any subset of fields.

```json
{
  "description": "Now covers East + Central"
}
```

Reassigning the manager only:

```json
{
  "manager_id": "9d2e4f3b-5555-6666-7777-888888888888"
}
```

Replacing members (note: `member_ids` is a full replacement, not an additive operation — prefer the Team Members endpoints below for incremental changes):

```json
{
  "member_ids": [
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222",
    "33333333-3333-3333-3333-333333333333"
  ]
}
```

**Response 200** — updated team object.

---

### 1.6 Delete Team

- **Method / URL:** `DELETE /api/v1/management/teams/{team_id}/`
- **Permission:** `delete_team`

**Response 204** — empty body. Team and its `TeamMember` rows are removed (cascade via FK).

---

## 2. Team Members

Nested under a team. Lookup field: `team_member_id` (UUID).

### 2.1 List Members in a Team

- **Method / URL:** `GET /api/v1/management/teams/{team_id}/members/`
- **Permission:** `view_team_members`
- **Cache:** 900s, varies by user + org
- **Rate limit:** 60/min per user

**Response 200**

```json
{
  "count": 1,
  "next": null,
  "previous": null,
  "results": [
    {
      "team_member_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "team_id": "b1d2c3e4-5f67-4890-aaaa-bbbbbbbbbbbb",
      "team_name": "Sales East",
      "user_id": "11111111-1111-1111-1111-111111111111",
      "user": {
        "user_id": "11111111-1111-1111-1111-111111111111",
        "full_name": "Alice Example",
        "email": "alice@example.com"
      },
      "joined_at": "2026-05-14T10:00:00.000000Z"
    }
  ]
}
```

---

### 2.2 Add Member to a Team

- **Method / URL:** `POST /api/v1/management/teams/{team_id}/members/`
- **Permission:** `manage_team_members`
- **Rate limit:** 10/min per user

**Request Body**

| Field | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | Yes | User to add. Must belong to caller's org. |

```json
{
  "user_id": "11111111-1111-1111-1111-111111111111"
}
```

**Response 201**

```json
{
  "team_member_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "team_id": "b1d2c3e4-5f67-4890-aaaa-bbbbbbbbbbbb",
  "team_name": "Sales East",
  "user_id": "11111111-1111-1111-1111-111111111111",
  "user": {
    "user_id": "11111111-1111-1111-1111-111111111111",
    "full_name": "Alice Example",
    "email": "alice@example.com"
  },
  "joined_at": "2026-05-14T10:00:00.000000Z"
}
```

**Errors**
- `400` — `"User is already a member."`
- `404` — Team not in caller's org, or `user_id` not in caller's org
- `429` — Rate limit exceeded

---

### 2.3 Retrieve a Team Member

- **Method / URL:** `GET /api/v1/management/teams/{team_id}/members/{team_member_id}/`
- **Permission:** `view_team_members`

**Response 200** — same shape as the add-member response above.

---

### 2.4 Update a Team Member

- **Method / URL:** `PATCH /api/v1/management/teams/{team_id}/members/{team_member_id}/`
- **Permission:** `manage_team_members`
- **Rate limit:** 10/min per user

**Request Body** — only writable fields on `TeamMember`. Currently `team_member_id`, `team_id`, and `joined_at` are read-only, so this endpoint is reserved for future writable attributes (e.g., role within team).

```json
{}
```

**Response 200** — team member object.

---

### 2.5 Remove a Team Member

- **Method / URL:** `DELETE /api/v1/management/teams/{team_id}/members/{team_member_id}/`
- **Permission:** `manage_team_members`
- **Rate limit:** 5/min per user

**Response 204** — empty body.

---

## 3. All Team Members (Org-wide, Flat)

### 3.1 List All Members Across Teams

- **Method / URL:** `GET /api/v1/management/teams/members/`
- **Permission:** `view_team_members`

Returns every `TeamMember` row in the caller's organization, regardless of team.

**Query Parameters**

| Param | Type | Description |
|---|---|---|
| `team_id` | int (Team FK PK) | Restrict to a single team |
| `search` | string | Searches user `first_name`, `last_name`, `email` |
| `ordering` | string | `joined_at` (prefix with `-`); default `-joined_at` |
| `page` | int | Page number |
| `page_size` | int | Page size (max 200) |

**Response 200** — same item shape as section 2.1, paginated.

---

## 4. Notes & Caching Behavior

- Team list/retrieve responses are cached for 300s per user+org. On `create`/`update`/`destroy`, the team cache version is bumped (`org:<org_id>:team`), invalidating stale entries.
- Team member list responses are cached for 900s per user+org. On member create/update/destroy, the per-team cache version is bumped (`team:<team_id>:members`).
- Uniqueness: `(org_id, name)` is unique for teams; `(team_id, user_id)` is unique for team members.
- All write operations are subject to per-user rate limits as documented per endpoint; exceeding them returns `429 Too Many Requests`.
