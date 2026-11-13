# Workspace Deletion & Decommissioning API Reference

This document provides the complete API specification for workspace deletion, data reset, and decommissioning operations in Clozr / NexoCRM.

---

## 1. Soft-Delete Workspace (Primary Deletion Endpoint)

### Name / Purpose
Permanently soft-deletes and decommissions a tenant organization workspace. Stamped with `deleted_at = timezone.now()` and marked `is_active = False`. Immediately deactivates all member user accounts (`instance.users.all().update(is_active=False)`) per rulebook requirement **FR-ORG-003**, invalidates the tenant cache, and causes `OrganizationMiddleware` to block any subsequent requests targeting the organization with a `403 Forbidden`.

### Method + Path
`DELETE /api/v1/organizations/manage/{organization_id}/`

### Headers
- `Authorization: Bearer <jwt_access_token>`
- `Content-Type: application/json`

### Path / Query Params
- **Path Parameter:**
  - `organization_id` (`UUID`, required): The unique identifier of the organization to delete. Non-superusers are scoped to their own workspace; submitting any other organization ID yields a `404 Not Found`.
- **Query Parameters:** None.

### Request Body
None (empty body).

### Success Response
- **Status Code:** `204 No Content`
- **Body:** None (empty).

### Error Responses
- **`401 Unauthorized`** (Missing or invalid token):
  ```json
  {
    "detail": "Given token not valid for any token type",
    "code": "token_not_valid",
    "messages": [
      {
        "token_class": "AccessToken",
        "token_type": "access",
        "message": "Token is invalid or expired"
      }
    ]
  }
  ```
- **`403 Forbidden`** (User lacks `delete_organization` permission; only System Admins hold this):
  ```json
  {
    "code": 403,
    "message": "You do not have permission to perform this action."
  }
  ```
- **`403 Forbidden`** (Organization already inactive or soft-deleted):
  ```json
  {
    "error": "Organization is inactive or has been deleted."
  }
  ```
- **`404 Not Found`** (Organization ID not found or belongs to another tenant):
  ```json
  {
    "detail": "No Organization matches the given query."
  }
  ```
- **`429 Too Many Requests`** (Rate limit exceeded; max 2 requests per minute):
  ```json
  {
    "detail": "Request was throttled. Expected available in 30 seconds."
  }
  ```

### Pagination
None.

---

## 2. Retrieve Workspace Details & ID (Pre-Deletion Discovery)

### Name / Purpose
Retrieves the organization profile, metadata, settings, and status. Used by client applications to discover the tenant's `organization_id` or to verify its state prior to deletion.

### Method + Path
- **By ID:** `GET /api/v1/organizations/manage/{organization_id}/`
- **Self-Discovery (Caller Org):** `GET /api/v1/organizations/manage/?page_size=1`

### Headers
- `Authorization: Bearer <jwt_access_token>`
- `Content-Type: application/json`

### Path / Query Params
- **Path Parameter:**
  - `organization_id` (`UUID`, required for detail retrieval).
- **Query Parameters:**
  - `page_size` (`int`, optional, default `20`): Page size for list endpoint.

### Request Body
None.

### Success Response
- **Status Code:** `200 OK`
- **JSON Body:**
  ```json
  {
    "organization_id": "0de3f717-cb01-4ff1-9fd2-fdbd0a0e630c",
    "name": "Acme Global",
    "app_name": "Acme CRM",
    "subdomain": "acme",
    "dark_logo": "https://cdn.nexocrm.com/orgs/acme/dark_logo.jpg",
    "light_logo": "https://cdn.nexocrm.com/orgs/acme/light_logo.jpg",
    "profile_photo": null,
    "primary_color": "#1E40AF",
    "secondary_color": "#3B82F6",
    "website": "https://acme.example.com",
    "industry": "Software",
    "business_hours": {
      "open": "09:00",
      "close": "18:00"
    },
    "employee_count": "51-200",
    "annual_revenue": "10M-50M",
    "currency": "INR",
    "timezone": "Asia/Kolkata",
    "date_format": "DD/MM/YYYY",
    "first_day_of_week": 1,
    "financial_year_start_month": 4,
    "address_line1": "Level 4, Tech Park",
    "address_line2": "MG Road",
    "city": "Bengaluru",
    "state": "Karnataka",
    "state_code": "KA",
    "country": "IN",
    "postal_code": "560001",
    "default_email": "contact@acme.example.com",
    "support_email": "support@acme.example.com",
    "default_phone": "+919876543210",
    "wa_phone": "+919876543210",
    "settings": {
      "legal_name": "Acme Technologies Private Limited",
      "gst_number": "29AAAAA0000A1Z5",
      "pan": "AAAAA0000A"
    },
    "is_active": true,
    "restrtict_to_business_hours": false,
    "task_on_weekends": false,
    "billing_email": "finance@acme.example.com",
    "billing_contact_name": "Jane Doe",
    "billing_phone": "+919876543210",
    "billing_address": "Level 4, Tech Park",
    "billing_city": "Bengaluru",
    "billing_state": "Karnataka",
    "billing_country": "IN",
    "billing_postal_code": "560001",
    "tax_id": "29AAAAA0000A1Z5"
  }
  ```

### Error Responses
- **`401 Unauthorized`** (Token missing or expired).
- **`403 Forbidden`** (User lacks `view_organization` or `view_settings` permission).
- **`404 Not Found`** (Organization not found or inactive).

### Pagination
Paginated when accessed via `GET /api/v1/organizations/manage/` (`count`, `next`, `previous`, `results`).

---

## 3. Reset Workspace Business Data (Wipe Without Account Deletion)

### Name / Purpose
High-security destructive operation for organizations that wish to wipe their business data (leads, deals, customers, contacts, tickets, and tasks) while keeping the workspace active, preserving configuration (custom fields, statuses, templates, roles, integrations), and retaining the requesting admin user. Automatically snapshots a pre-reset Deep Archive backup and 14-day safety copy in AWS S3 before executing the wipe.

### Method + Path
`POST /api/v1/organizations/reset/`

### Headers
- `Authorization: Bearer <jwt_access_token>`
- `Content-Type: application/json`

### Path / Query Params
None.

### Request Body
- **Content-Type:** `application/json`
- **JSON Example:**
  ```json
  {
    "confirm": "acme",
    "replace_backup_id": "e8d75294-b778-4384-9344-939e44ff4b2b"
  }
  ```
  - `confirm` (`string`, required): Must exactly match the organization's subdomain.
  - `replace_backup_id` (`UUID`, optional): Required only when the organization's plan backup capacity is full.

### Success Response
- **Status Code:** `202 Accepted`
- **JSON Body:**
  ```json
  {
    "operation_id": "b1b11111-2222-3333-4444-555555555555",
    "kind": "reset",
    "status": "queued",
    "backup_id": null,
    "result_backup_id": null,
    "safety_backup_id": null,
    "replace_backup_id": null,
    "requested_by_email": "admin@acme.example.com",
    "retrieval": null,
    "progress": {
      "phase": "queued",
      "percent": 0
    },
    "result": {},
    "error": null,
    "created_at": "2026-11-03T19:00:00Z",
    "started_at": null,
    "finished_at": null,
    "can_cancel": true,
    "can_apply": false
  }
  ```

### Error Responses
- **`400 Bad Request`** (Subdomain confirmation failed):
  ```json
  {
    "code": "CONFIRM_MISMATCH",
    "error": "Type your organization's subdomain to confirm."
  }
  ```
- **`403 Forbidden`** (User is not a System Admin with `is_staff=True`):
  ```json
  {
    "detail": "You do not have permission to perform this action."
  }
  ```
- **`409 Conflict`** (Accounting journals exist — Gate G6 statutory retention block):
  ```json
  {
    "code": "ACCOUNTING_JOURNAL_EXISTS",
    "error": "Cannot reset organization data: accounting ledger journals exist and are subject to statutory retention regulations."
  }
  ```
- **`409 Conflict`** (Another operation in progress):
  ```json
  {
    "code": "OPERATION_IN_PROGRESS",
    "error": "Another backup, reset or restore is already in progress for this organization."
  }
  ```
- **`409 Conflict`** (Backup capacity reached):
  ```json
  {
    "code": "BACKUP_LIMIT_REACHED",
    "error": "Your plan keeps 3 backup(s). Choose one to replace.",
    "cap": 3,
    "used": 3,
    "candidates": []
  }
  ```
- **`503 Service Unavailable`** (S3 storage unconfigured):
  ```json
  {
    "code": "BACKUP_STORAGE_NOT_CONFIGURED",
    "error": "Backup storage is not configured."
  }
  ```
- **`429 Too Many Requests`** (Rate limited to 5 per hour).

### Pagination
None.

---

## 4. Poll Data Operation Progress (Reset Status)

### Name / Purpose
Checks the execution progress, status (`queued`, `snapshotting`, `applying`, `succeeded`, `failed`), and output summary of an asynchronous reset, backup, or restore data operation.

### Method + Path
`GET /api/v1/organizations/data-operations/{operation_id}/`

### Headers
- `Authorization: Bearer <jwt_access_token>`
- `Content-Type: application/json`

### Path / Query Params
- **Path Parameter:**
  - `operation_id` (`UUID`, required): The UUID returned by `POST /api/v1/organizations/reset/`.
- **Query Parameters:** None.

### Request Body
None.

### Success Response
- **Status Code:** `200 OK`
- **JSON Body:**
  ```json
  {
    "operation_id": "b1b11111-2222-3333-4444-555555555555",
    "kind": "reset",
    "status": "succeeded",
    "backup_id": null,
    "result_backup_id": "7890abcd-ef12-3456-7890-abcdef123456",
    "safety_backup_id": "8901bcde-f123-4567-8901-bcdef1234567",
    "replace_backup_id": null,
    "requested_by_email": "admin@acme.example.com",
    "retrieval": null,
    "progress": {
      "phase": "completed",
      "percent": 100
    },
    "result": {
      "deleted": {
        "leads": 420,
        "deals": 85,
        "customers": 130,
        "contacts": 210,
        "tickets": 64
      },
      "backup_id": "7890abcd-ef12-3456-7890-abcdef123456"
    },
    "error": null,
    "created_at": "2026-11-03T19:00:00Z",
    "started_at": "2026-11-03T19:00:02Z",
    "finished_at": "2026-11-03T19:00:15Z",
    "can_cancel": false,
    "can_apply": false
  }
  ```

### Error Responses
- **`401 Unauthorized`**
- **`403 Forbidden`**
- **`404 Not Found`**:
  ```json
  {
    "code": "NOT_FOUND",
    "error": "Operation not found."
  }
  ```

### Pagination
None (list available via `GET /api/v1/organizations/data-operations/`).

---

## 5. Cancel Subscription (Billing Decommissioning)

### Name / Purpose
Immediately cancels the live payment mandate / recurring subscription with Razorpay to halt future charges, and schedules local subscription cancellation at the end of the trial period or current prepaid cycle (`cancellation_effective_at`). Used prior to or alongside workspace termination.

### Method + Path
`POST /api/v1/billing/subscriptions/{subscription_id}/cancel/`

### Headers
- `Authorization: Bearer <jwt_access_token>`
- `Content-Type: application/json`

### Path / Query Params
- **Path Parameter:**
  - `subscription_id` (`UUID`, required): The identifier of the organization subscription.
- **Query Parameters:** None.

### Request Body
- **Content-Type:** `application/json`
- **JSON Example:**
  ```json
  {
    "reason": "Decommissioning workspace account"
  }
  ```

### Success Response
- **Status Code:** `200 OK`
- **JSON Body:**
  ```json
  {
    "subscription_id": "a9876543-210f-edcb-a987-6543210fedcb",
    "status": "active",
    "is_cancellation_scheduled": true,
    "cancellation_effective_at": "2026-11-30T23:59:59Z",
    "cancelled_at": "2026-11-03T19:05:00Z",
    "auto_renew": false,
    "current_period_end": "2026-11-30T23:59:59Z",
    "plan": {
      "plan_id": "c1234567-89ab-cdef-0123-456789abcdef",
      "name": "Growth Plan",
      "billing_cycle": "monthly"
    }
  }
  ```

### Error Responses
- **`400 Bad Request`** (Already scheduled):
  ```json
  {
    "code": "cancellation_already_scheduled",
    "detail": "Subscription cancellation is already scheduled."
  }
  ```
- **`400 Bad Request`** (Invalid subscription state):
  ```json
  {
    "code": "subscription_not_cancellable",
    "detail": "Only active or trial subscriptions can be cancelled."
  }
  ```
- **`403 Forbidden`** (User lacks `IsBillingAdmin` / System Admin role):
  ```json
  {
    "code": 403,
    "message": "You do not have permission to perform this action."
  }
  ```
- **`502 Bad Gateway`** (Payment gateway communication error; fails closed with no local modification):
  ```json
  {
    "code": "razorpay_cancel_failed",
    "detail": "Could not cancel with the payment provider; nothing was changed. Please retry."
  }
  ```

### Pagination
None.

