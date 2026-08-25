# Notification Preference Settings

## Context

This doc captures how the existing notification preference system works, so admins and the frontend team know how to operate it without changing code.

The motivation was Resend quota pressure — being able to turn off categories of email at the org level is the lever that solves it without code changes.

---

## What exists today

Three layers of control, evaluated by [`should_send_channel`](../crm/services/notification_dispatch.py) on every send:

1. **Org-wide channel kill switch** — `Organization.settings["notification_channels"]`. Hard block. If `email_enabled=False` for an org, *no* per-event email of any kind leaves for that org. (Auth/billing emails go via Resend directly and bypass this — see "What this does NOT control" below.)
2. **Per-user, per-event override** — `UserNotificationPreference` row. Wins over the org default but cannot bypass the kill switch.
3. **Org per-event default** — `NotificationPreference` row. Absent ⇒ defaults to `True` (opt-out model).

Backed by:
- [`crm/models/communication.py:594-636`](../crm/models/communication.py#L594-L636) — `NotificationPreference` model (org-level, per event × channel)
- [`crm/models/communication.py:638-688`](../crm/models/communication.py#L638-L688) — `UserNotificationPreference` model
- [`crm/views/notification_preferences.py`](../crm/views/notification_preferences.py) — both ViewSets with CRUD + matrix action
- [`crm/serializers/communication.py:210-249`](../crm/serializers/communication.py#L210-L249) — serializers
- [`crm/services/notification_dispatch.py:43-132`](../crm/services/notification_dispatch.py#L43-L132) — `should_send_channel` + `invalidate_preference_cache` (sentinel-versioned, 5-min TTL)
- [`crm/tests/test_notification_settings.py`](../crm/tests/test_notification_settings.py) — full coverage incl. 3-tier precedence

---

## The three endpoints

### 1. Org channel kill switch (hardest hammer)

**`/api/v1/settings/notifications/channels/`** — handled by [`NotificationChannelSettingsView`](../settings/views.py), permission `HasSettingsPermission` (admin).

`GET` — current state.
`PUT` — set the flags:

```json
{
  "in_app_enabled": true,
  "push_enabled": true,
  "email_enabled": false,
  "sms_enabled": false,
  "whatsapp_enabled": false
}
```

Setting `email_enabled=false` immediately silences **all per-event email notifications** (Lead*, Task*, PMO*, LMS*, system events going through `dispatch_notification`). Transactional Resend mail (activation, password reset, billing) is NOT routed through this — those are direct sends.

### 2. Org per-event defaults (the matrix)

**`/api/v1/crm/notification-preferences/`** — [`NotificationPreferenceViewSet`](../crm/views/notification_preferences.py), permission `HasSettingsPermission` (admin).

Two ways to interact:

#### A. Matrix-style (recommended for the settings page UI)

`GET /api/v1/crm/notification-preferences/matrix/`

```json
{
  "event_types": ["LeadAssigned", "LeadStatusChanged", "TaskAssigned", "CallRecordingReady", "..."],
  "channels": ["in_app", "email", "push", "sms", "whatsapp"],
  "matrix": {
    "LeadAssigned":         { "in_app": true, "email": true,  "push": true, "sms": true, "whatsapp": true },
    "CallRecordingReady":   { "in_app": true, "email": false, "push": true, "sms": true, "whatsapp": true }
  },
  "groups": { "CRM Notifications": {}, "PMO Notifications": {}, "System Notifications": {} }
}
```

`PUT /api/v1/crm/notification-preferences/matrix/` with the same shape — atomically upserts/deletes rows. Semantics:
- `true` → delete the opt-out row (restore default-on).
- `false` → upsert a row with `is_enabled=False`.

Cache is invalidated automatically. Affects every user in the org unless they have a per-user override.

#### B. CRUD on individual rows

Standard DRF ModelViewSet: `GET / POST / PUT / PATCH / DELETE /api/v1/crm/notification-preferences/[<pk>/]`.

Body for POST/PUT:
```json
{ "event_type": "CallRecordingReady", "channel": "email", "is_enabled": false }
```

### 3. Per-user override (user controls their own inbox)

**`/api/v1/crm/my-notification-preferences/`** — [`UserNotificationPreferenceViewSet`](../crm/views/notification_preferences.py), permission `IsAuthenticated` (any logged-in user, scoped to their own rows).

Same shape as the org endpoint. The `GET matrix` action resolves through the full 3-tier precedence, so the user sees their **effective** state (org kill switch and event default factored in).

---

## Reference: event types and channels

Centralised in [`crm/models/communication.py`](../crm/models/communication.py):

- **Channels** (line 510-523): `in_app`, `email`, `push`, `sms`, `whatsapp`.
- **Event types** (line 186-236, choices at 532): full list below — see `_NOTIFICATION_TITLES` in [`crm/tasks.py:593-617`](../crm/tasks.py#L593-L617) for human labels.
- **UI grouping** (line 545-591): `NOTIFICATION_EVENT_GROUPS` dict for the settings page layout — keys "CRM Notifications", "PMO Notifications", "System Notifications".

### Channels (5)

| Key | Label | Status |
| --- | --- | --- |
| `in_app` | In-App | Live (creates `CRMNotification` row) |
| `email` | Email | Live (Resend SMTP via `send_system_email`) |
| `push` | Push | Live (FCM) |
| `sms` | SMS | Stubbed (logs only) |
| `whatsapp` | WhatsApp | Stubbed (logs only — needs pre-approved templates) |

### Event types — the full matrix (34 entries)

Order matches [`NOTIFICATION_EVENT_TYPE_CHOICES`](../crm/models/communication.py#L532) which is what the matrix endpoint returns. The `groups` field on the matrix response only includes the 27 entries surfaced in `NOTIFICATION_EVENT_GROUPS`; the rest are valid event types but not shown by the default UI grouping (see note below the table).

#### CRM Notifications

**Leads**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `LeadAssigned` | Lead Assigned | [`crm/views/lead.py:55`](../crm/views/lead.py) | ✅ |
| `LeadStatusChanged` | Lead Status Changed | [`crm/views/lead.py:91`](../crm/views/lead.py) | ✅ |
| `LeadNoteAdded` | Lead Note Added | [`crm/signals.py:551`](../crm/signals.py) | ✅ |
| `LeadConverted` | Lead Converted | [`crm/services/conversion.py:189`](../crm/services/conversion.py) | ✅ |

**Tasks & Follow-ups**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `TaskAssigned` | Task Assigned | [`crm/views/task.py:24`](../crm/views/task.py) | ✅ |
| `TaskDueReminder` | Task Due Reminder | [`crm/tasks.py:1107`](../crm/tasks.py) (hourly Beat) | ✅ |
| `FollowUpDueReminder` | Follow-up Due Reminder | [`crm/tasks.py:1107`](../crm/tasks.py) (hourly Beat) | ✅ |
| `TaskCompleted` | Task Completed | [`crm/signals.py:626`](../crm/signals.py) | ✅ |
| `TaskNoteAdded` | Task Note Added | [`crm/signals.py:582`](../crm/signals.py) | ✅ |

**Calls**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `CallRecordingReady` | Call Recording Ready | [`crm/tasks.py:334`](../crm/tasks.py) | ✅ |
| `CallSummaryGenerated` | Call Summary Generated | [`crm/tasks.py:432`](../crm/tasks.py) | ✅ |
| `CallBanner` | Call Banner | FCM-only banner (no `CRMNotification` row) | ❌ (toggle-only) |

#### PMO Notifications

**Projects**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `ProjectAssigned` | Project Assigned | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `ProjectStatusChanged` | Project Status Changed | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `ProjectDeadlineApproaching` | Project Deadline Approaching | [`projects/tasks.py:142`](../projects/tasks.py) (daily Beat 08:00 UTC) | ✅ |
| `ProjectCompleted` | Project Completed | [`projects/signals.py:87`](../projects/signals.py) | ✅ |

**Tasks**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `PmoTaskAssigned` | PMO Task Assigned | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `PmoTaskDueReminder` | PMO Task Due Reminder | [`projects/tasks.py:192`](../projects/tasks.py) (daily Beat 08:00 UTC) | ✅ |
| `PmoTaskStatusChanged` | PMO Task Status Changed | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `PmoTaskCompleted` | PMO Task Completed | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `PmoTaskCommentAdded` | PMO Task Comment Added | [`projects/signals.py:87`](../projects/signals.py) | ✅ |

**Team**

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `ProjectMemberAdded` | Project Member Added | [`projects/signals.py:87`](../projects/signals.py) | ✅ |
| `ProjectMemberRemoved` | Project Member Removed | [`projects/signals.py:87`](../projects/signals.py) | ✅ |

#### System Notifications

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `UserAdded` | User Added | [`accounts/signals.py:92`](../accounts/signals.py) | ✅ |
| `PasswordChanged` | Password Changed | [`accounts/views/password_reset.py:177`](../accounts/views/password_reset.py) | ✅ |
| `SystemUpdate` | System Update | (reserved — no current dispatcher) | ✅ |

#### LMS (valid event types — toggleable via API, but NOT in the default UI grouping)

| Event type | Human label | Where it fires | In UI group? |
| --- | --- | --- | --- |
| `LMSCourseAssigned` | LMS Course Assigned | [`lms/services/notification.py:14`](../lms/services/notification.py) | ❌ |
| `LMSNudge` | LMS Nudge | [`lms/services/notification.py:25`](../lms/services/notification.py) | ❌ |
| `LMSDeadlineReminder` | LMS Deadline Reminder | [`lms/services/notification.py:48`](../lms/services/notification.py) (daily Beat 09:00 UTC) | ❌ |
| `LMSCourseCompleted` | LMS Course Completed | [`lms/services/notification.py:70`](../lms/services/notification.py) | ❌ |
| `LMSDeadlineMissed` | LMS Deadline Missed | [`lms/services/notification.py:91`](../lms/services/notification.py) (daily Beat 00:20 UTC) | ❌ |

#### Legacy (kept for backward-compat with existing rows; not actively dispatched)

| Event type | Human label | Notes |
| --- | --- | --- |
| `Mention` | Mention | Legacy |
| `Task` | Task | Legacy (use `TaskAssigned`) |
| `Assignment` | Assignment | Legacy |
| `WhatsApp` | WhatsApp | Legacy |

### Notes on the matrix you'll see in the API

- **`event_types`** in the response is the full 34-entry list in `NOTIFICATION_EVENT_TYPE_CHOICES` order (legacy → CRM → System → PMO → LMS, then `CallBanner` appended).
- **`groups`** in the response only contains the 27 entries inside `NOTIFICATION_EVENT_GROUPS`. LMS, `CallBanner`, and the 4 legacy types are NOT grouped. If the frontend wants to render them as a section, either extend [`NOTIFICATION_EVENT_GROUPS`](../crm/models/communication.py#L545-L591) or hard-code a fallback bucket on the client.
- **`matrix["<event>"]["<channel>"]`** is `true` unless an explicit opt-out row exists (org-level matrix) or `should_send_channel` resolves to `false` (user-level matrix).

---

## Concrete recipes

### Stop ALL email notifications org-wide while testing

```bash
curl -X PUT https://dev.clozr.tech/api/v1/settings/notifications/channels/ \
  -H "Authorization: Bearer <admin-jwt>" -H "Content-Type: application/json" \
  -d '{"in_app_enabled": true, "push_enabled": true,
       "email_enabled": false, "sms_enabled": false, "whatsapp_enabled": false}'
```

Auth/billing emails still go via Resend (they bypass this).

### Stop just the high-volume CRM emails

```bash
curl -X PUT https://dev.clozr.tech/api/v1/crm/notification-preferences/matrix/ \
  -H "Authorization: Bearer <admin-jwt>" -H "Content-Type: application/json" \
  -d '{
    "matrix": {
      "CallRecordingReady":     { "email": false },
      "CallSummaryGenerated":   { "email": false },
      "TaskDueReminder":        { "email": false },
      "FollowUpDueReminder":    { "email": false },
      "StaleLeadAlert":         { "email": false }
    }
  }'
```

In-app + push notifications still fire for these events.

### A specific user mutes their own task-assigned emails

```bash
curl -X PUT https://dev.clozr.tech/api/v1/crm/my-notification-preferences/matrix/ \
  -H "Authorization: Bearer <user-jwt>" -H "Content-Type: application/json" \
  -d '{ "matrix": { "TaskAssigned": { "email": false } } }'
```

### Inspect what a user will actually receive

`GET /api/v1/crm/my-notification-preferences/matrix/` (with that user's JWT) returns the fully resolved matrix.

---

## What this does NOT control

These send paths do **not** go through `dispatch_notification` and therefore ignore preferences:

- **Auth flow** — activation, password reset, admin-status-change emails ([`accounts/utils/email.py`](../accounts/utils/email.py), [`accounts/tasks.py`](../accounts/tasks.py)).
- **Billing** — trial, invoice, grace, suspension, payment-failed ([`billing/emails.py`](../billing/emails.py)).

Rationale: these are transactional/operational, not preferential. If you need a kill switch on them too, use `EMAIL_SYNC_ENABLED`-style flags or set `DEFAULT_FROM_EMAIL=""` (forces `send_system_email` to error out permanently — already handled by the `is_permanent` classifier).

---

## Critical files (read-only — nothing to edit)

| File | Why |
| --- | --- |
| [`crm/models/communication.py`](../crm/models/communication.py) | Models, channel constants, event-type constants, UI groups |
| [`crm/views/notification_preferences.py`](../crm/views/notification_preferences.py) | Both ViewSets + matrix action |
| [`crm/serializers/communication.py`](../crm/serializers/communication.py) | DRF serializers |
| [`crm/services/notification_dispatch.py`](../crm/services/notification_dispatch.py) | `should_send_channel`, `invalidate_preference_cache`, `dispatch_notification` |
| [`crm/urls.py`](../crm/urls.py) | URL registrations (lines 102-110) |
| [`settings/views.py`](../settings/views.py) | Org channel kill-switch endpoint (lines 320-339) |
| [`crm/tests/test_notification_settings.py`](../crm/tests/test_notification_settings.py) | Reference for behaviour |

---

## Verification

1. **Confirm endpoints respond**
   ```bash
   curl -H "Authorization: Bearer <admin>" https://dev.clozr.tech/api/v1/crm/notification-preferences/matrix/
   curl -H "Authorization: Bearer <admin>" https://dev.clozr.tech/api/v1/settings/notifications/channels/
   curl -H "Authorization: Bearer <user>"  https://dev.clozr.tech/api/v1/crm/my-notification-preferences/matrix/
   ```
   Expect 200 + JSON shape as documented above.

2. **Turn off `CallRecordingReady` email for the org**, then trigger a fake `CallRecordingReady` dispatch and confirm `send_notification_email` is NOT enqueued for that event but IS for `LeadAssigned`.

3. **Set `email_enabled=false` org-wide**, dispatch any preference-gated event, confirm zero `send_notification_email` tasks queued in `nexocrm-celery-worker` logs.

4. **Per-user override**: as a non-admin user, mute `TaskAssigned` email, have an admin assign them a task, confirm only push/in-app fire — no email.

5. **Cache invalidation**: change a preference via the matrix endpoint, immediately dispatch the event, confirm the new value takes effect (the sentinel-versioned cache should flip within the same request).
