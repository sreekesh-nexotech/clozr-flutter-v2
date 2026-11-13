# Unified Approvals — Mobile implementation route map (clozr-flutter-v2)

Status: **implemented 2026-11-10** (Phases 1–9 and the automated part of 11). Phase 10 is web-only by decision D1. Still open: Phase 0 test data, the manual production pass, and UAT (see §9).

Sources read for this plan
- Web feature: `Clozr-Webapp-ViteJS/clozr-webapp-vitejs/src/features/approvals/**` (≈2.5k lines), `core/http/approvalHold.ts`, `core/config/navigation.ts`, `core/constants/routes.ts`
- Backend contract: `clozr-webapp-vitejs/docs/backend/approvals.md` (rules BR-1…BR-18) and `approvals-backend-requests.md` (AP-1…AP-4)
- Mobile conventions: `lib/features/rewards` (clean 4-layer reference), `lib/features/crm/.../quote_approvals_screen.dart` + `due_date_approvals_screen.dart` (existing approval-style screens), `lib/features/auth/**` (permissions), `lib/features/shell/domain/nav_catalog.dart`, `docs-flutter/Flutter Coding Standards.md`
- Live check against production (`https://app.clozr.co.in/api/v1`, taken from `lib/core/config/api_config.dart`) with `superadmin@clozr.com`: `/approvals/`, `/approvals/counts/`, `/approvals/settings/` and the `mine|team|history` tabs all answer 200. `/auth/me/modules/` for this user returns `is_superuser`, `full_access` and a `settings` module. The list is empty, so **real request data must be created in Phase 0 to test against**.

---

## 0. Ground rules (apply to every phase)

1. **No new visual language.** Every surface reuses existing shared widgets and tokens; nothing is hand-styled. Approved building blocks (all already in `lib/core/widgets` or the CRM components):
   - Screen chrome: `DetailAppBar`, `AppHeaderBar`, `AppRefresh` / `RefreshIndicator`
   - Lists: `AppCard`, `ListSkeleton`, `EmptyState`, `ErrorState.forError(...)`, `AsyncStateView`, `ListHeader`, `SearchField`
   - Tabs / filters: `TabChip` (the same chips the Quote approvals screen uses), `SegmentedControl`, `core/filters/filter_sheet.dart`
   - Status: `StatusPill`, `AppAvatar`
   - Sheets / dialogs: `app_bottom_sheet.dart`, the same decision dialog pattern as `showDiscountDecisionDialog`, `PrimaryButton`, `AppTextField`
   - Tokens: `AppColors`, `AppTextStyles`, `AppDimens`, `flutter_screenutil` (`.w/.h/.r/.sp`), Phosphor icons. **No raw hex colours, no new fonts, no custom widgets for something one of the above already does.**
   - If something is genuinely missing (e.g. a vertical step timeline), first look for how Activity log / SLA clocks / Notes thread render timelines and reuse that; only then add one small widget to `lib/core/widgets`, not to the feature.
2. **Permissions follow the same bypass model as every other module** (details in §3). Short form: the Approvals entry and screen are *not* module-gated (web parity — `requires: 'signedIn'`, the server scopes rows), unknown access never blocks (`ModulePerm.open`), decide/escalate/withdraw are driven by the server's `can_*` flags (which already encode System Admin / superuser / Executive Leadership overrides), and the settings area is gated on `settings → update` through the existing `ensurePermission` / `hasPermission`.
3. **Architecture:** feature-first, same four layers and naming as `rewards`; Riverpod `FutureProvider` / `StateNotifierProvider`, provider names end in `Provider`; mock-mode seam via `ApiConfig.apiEnabled` exactly like `rewardsRepositoryProvider`. Immutable entities (`equatable`). No logic in widgets — rules live in plain Dart files under `application/` so they are unit-testable (the repo's `*_rules.dart` pattern).
4. **Tooling:** run everything with `fvm flutter ...` (global `flutter` breaks tests and the lockfile; 7 known baseline failures — compare against that, don't fix them here).
5. **Errors:** approval errors keep a *text* `code` (`APPROVAL_NOT_PENDING`, `APPROVAL_STALE`, …). `AppError` already carries `code` and `extra`; confirm in Phase 1 that a 409 body's `detail`/`code` reach it unmodified, extending `core/network/app_error.dart` additively only if not.
6. **Out of scope unless decided in §7:** admin settings editor on mobile, push-notification deep links beyond routing to the Approvals screen.

---

## 1. Feature scope — what "from scratch, like the web" means

| # | Web capability | Mobile deliverable | Phase |
|---|---|---|---|
| 1 | Sidebar entry **Approvals** (`/approvals`, everyone signed in) with pending-count badge | Drawer entry + badge, route, landing-safe (`landing: false`) | 2, 4 |
| 2 | **ApprovalsScreen** — 4 tabs (Waiting for me / My requests / Team / History), Type + Module + Status filters, search, requester/owner/project/date filters, pagination | Tabbed list of cards, search, filter sheet, load-more | 4 |
| 3 | Team tab visibility (`has_subordinates` / system admin, else only if the probe has rows) | Same rule using `ModuleAccess.hasSubordinates` + a 1-row probe | 4 |
| 4 | "Other approvals" strip (quote discounts / rewards / lifecycle counts) | Strip linking to existing mobile screens (Quote discount approvals today; rewards & lifecycle only if a mobile route exists — otherwise hidden, see §7 D3) | 4 |
| 5 | **Detail drawer** — status, change `from → to`, request note, requester/owner/approver/dates, decision note, record summary (keys vary per module), step timeline, Open record, Withdraw / Escalate / Reject / Approve | Detail screen with the same sections and the same `can_*` gating | 5 |
| 6 | **DecisionDialog** — approve (optional comment), reject (reason ≥ 10, ≤ 2000 chars), escalate (optional note) | Same three verdicts in the existing decision-dialog style; same copy | 5 |
| 7 | **Bulk decide** (select rows on Waiting-for-me, approve/reject up to 200, per-row result "N done · M skipped") | Multi-select mode on the pending tab + bulk bar | 6 |
| 8 | **Record banner** (`ApprovalBanner`) on lead / task / follow-up / ticket / project task / project detail while a request waits, with Withdraw / Escalate / Reject / Approve per `can_*` | One reusable banner component dropped into those six detail screens | 7 |
| 9 | **Pre-save comment prompt** (`useApprovalRequestNote`) when closing a record or changing owner would need approval | Same prompt before the save, driven by `approval_gates` on the record row (fallback `for-record`) | 7 |
| 10 | **Hold handling** — a save answering `202 APPROVAL_REQUIRED` means "sent for approval": toast with approver name, refresh approval caches, keep the record unchanged | One shared interpreter used by every write path + toast + invalidation | 3 |
| 11 | **Pending chip** on list/board cards for records sent this session (client-side store, backend AP-2) | `Sent for approval` chip on the six list/board cards, session-scoped | 7 |
| 12 | Bulk status change returns `pending` / `pending_ids` → "3 updated · 7 sent for approval · 1 skipped" | Reuse for existing mobile bulk status paths | 7 |
| 13 | Lead *convert* → `202 APPROVAL_REQUIRED` + approval when the tenant gates Won | Extend the existing lead conversion flow (it currently reads the old `conversion_requires_approval` flags) | 7 |
| 14 | Due-date approvals now live in this module; old `/sla/due-date-changes/*` endpoints are **deprecated** | Migrate `due_date_approvals_screen.dart` + `due_date_change.dart` onto `/approvals/?kind=due_date` and the new approve/reject; keep the old route working as a redirect | 8 |
| 15 | Notifications `ApprovalRequested/Decided/Escalated/Rerouted/Closed` | Route those notification types to the Approvals screen / record | 9 |
| 16 | **Settings → Approvals** (per-module close/owner-transfer switches, statuses, due-date rules) | Decision needed — see §7 D1. Planned as optional Phase 10. | 10 |

---

## 2. API surface → mobile data layer

Base: `ApiConfig.baseUrl + /api/v1` (already how `ApiService` is configured, so paths below are relative to that: `/approvals/...`).

| Endpoint | Used by | Repository method |
|---|---|---|
| `GET /approvals/` (`tab, scope, kind, module, status, requester, owner, project, created_after, created_before, search, page, page_size`) | list screen, Team probe | `fetchApprovals(query)` → `ApprovalPage` |
| `GET /approvals/{id}/` | detail | `fetchApproval(id)` → `ApprovalDetail` |
| `GET /approvals/counts/` (cached 60 s server-side; refetch ~60 s + on app resume) | drawer badge, tab badge, strip | `fetchCounts()` |
| `POST /approvals/{id}/approve/` `{note?}` | detail, banner | `approve(id, note)` |
| `POST /approvals/{id}/reject/` `{note ≥10}` | detail, banner | `reject(id, note)` |
| `POST /approvals/{id}/escalate/` `{note?}` | detail, banner | `escalate(id, note)` |
| `POST /approvals/{id}/withdraw/` | detail, banner | `withdraw(id)` |
| `POST /approvals/bulk-decide/` `{ids≤200, verdict, note?}` → `{updated, skipped_ids, errors[]}` | bulk bar | `bulkDecide(ids, verdict, note)` |
| `GET /approvals/for-record/?module&object_id` | pre-check when the record row has no gates | `fetchRecordApproval(module, id)` → `RecordApprovalState` |
| `GET/PATCH /approvals/settings/` | Phase 10 only | `fetchSettings()` / `saveSettings(patch)` |
| Changed record endpoints (`PATCH` lead/task/followup/issue/project-task/project; bulk status; lead convert) | Phase 3 + 7 | existing repos, plus the shared 202 interpreter |

**Error codes to switch on** (map each to the web's wording, never show raw codes): `APPROVAL_NOT_PENDING`, `APPROVAL_NOT_APPROVER`, `APPROVAL_STALE` (also refresh the list), `APPROVAL_ALREADY_PENDING`, `REJECTION_REASON_REQUIRED`, `ESCALATION_UNAVAILABLE`, `APPROVAL_REQUIRED` (success-with-202, not an error), `LOST_HAS_OPEN_INVOICES`, `PROJECT_HAS_OPEN_TASKS`, `PROJECT_GOVERNANCE_FIELD`.

---

## 3. Permissions — the bypass model this module must follow

How mobile does it today (verified in code), and what Approvals does at each layer:

| Layer | Existing mechanism | Approvals behaviour |
|---|---|---|
| Menu visibility | `nav_catalog.dart` `NavEntry.modules` + `ModuleAccess.canAny`; `access == null` (mock mode / loading / failed fetch) ⇒ not gated | New entry with **empty `modules`** (never gated), mirroring the web's `requires: 'signedIn'`. `landing: false` so it is never picked as a role's first screen (same as My Trainings). |
| Route guard | `ModuleGuard(module: ...)`; unknown access lets the screen through; server still refuses per request | **No `ModuleGuard`** on `/approvals` — comment it "Webapp: no module guard — the server scopes the rows", exactly like `Routes.dueDateApprovals`. |
| Write verbs | `modulePermProvider(module)` → `ModulePerm` (`open` when access unknown); `hasPermission` / `ensurePermission(ref, module, PermVerb.x)` shows `PermissionCopy` toast | Approve / Reject / Escalate / Withdraw buttons render from the server's per-row `can_decide`, `can_escalate`, `can_withdraw` (those flags already include the System Admin / superuser / Executive Leadership overrides and `decision_source = admin_override`). **Do not re-derive from role names.** Where a button is hidden by a flag, no toast is needed; where the server later refuses (403 `APPROVAL_NOT_APPROVER`), surface its message. |
| Admin overrides | Backend applies the overlays; app reads `/auth/me/modules/` (`isSuperuser`, `fullAccess`) — accounting additionally short-circuits on them (`AccPerm.open`) | Same: superuser/full-access sees the Team tab (`hasSubordinates || isSystemAdmin`), is never blocked client-side, and the pre-check/banner still ask the server. |
| In-record actions | Each record module's own `PermVerb.update` gate (task/lead/etc.) already guards status & owner edits | Unchanged; the new pre-check/hold logic runs **after** the existing `ensurePermission` passes, so a user who cannot edit never reaches an approval prompt. |
| Settings (Phase 10) | `settings` module, `PermVerb.update` | Read for anyone who reaches it; Save gated with `ensurePermission(ref, 'settings', PermVerb.update)` and `PermissionCopy.update`. |
| Fail-open vs fail-closed | `ModulePerm.open` while access is unknown | Counts / list failures degrade quietly (badge shows nothing, `quiet: true`), the list shows `ErrorState` with retry. **Never hide the entry because a fetch failed.** |

Acceptance for this section is in Phase 11 (permission matrix tests).

---

## 4. Target file layout

```
lib/features/approvals/
  domain/
    entities/
      approval.dart                 // Approval, ApprovalDetail, ApprovalStep, ApprovalUser, ApprovalPage,
                                    // ApprovalCounts, PendingApproval, ApprovalGates, RecordApprovalState,
                                    // BulkDecisionResult, ApprovalHold; enums kind/status/module/tab/scope
      approval_settings.dart        // (Phase 10)
    repositories/approvals_repository.dart
  application/
    approval_rules.dart             // closeNeedsApproval, isRejectionNoteValid (>=10, <=2000), hasNarrowingFilters,
                                    // BULK_DECIDE_MAX = 200, showTeamTab, label/route maps (kind, module, status, reason, outcome)
    approval_hold.dart              // readApprovalHold(status, body), recordOf(), readPendingIds()  (202 interpreter)
    providers/
      approvals_providers.dart      // repository DI, list, detail, counts, record-state, team probe
      approval_actions_providers.dart   // approve/reject/escalate/withdraw/bulk + cache invalidation
      approval_holds_provider.dart  // session-scoped Set<String> of held record ids (the "chip" store)
  infrastructure/
    data_sources/
      remote/approvals_remote_ds.dart   // Dio via ApiService; DTO -> entity mapping lives here
      local/approvals_mock_ds.dart      // mock mode, mirrors RewardsMockDataSource
    repositories/
      approvals_api_repository.dart
      approvals_repository_impl.dart    // mock-backed
  presentation/
    screens/
      approvals_screen.dart
      approval_detail_screen.dart
    components/
      approval_card.dart
      approval_change.dart              // "In progress -> Completed"
      approval_decision_dialog.dart     // approve / reject / escalate
      approval_banner.dart              // record-page strip
      approval_request_comment_dialog.dart  // "This needs approval" pre-save prompt
      pending_approval_chip.dart
      other_approvals_strip.dart
      approval_filter_sheet.dart
test/features/approvals/ …              // see Phase 11
```

Touch points outside the feature (additive only): `app/router/routes.dart` + `app_router.dart`, `features/shell/domain/nav_catalog.dart` + drawer badge, `features/notifications/application/notification_navigator.dart`, the six record detail screens + their list/board cards, `core/network/api_service.dart` (status-aware helpers if missing), `features/crm/.../due_date_*` (Phase 8).

---

## 5. Phased checklist

Each phase ends with: `fvm flutter analyze` clean for touched files, `fvm flutter test` no new failures vs the 7-failure baseline, and a manual pass in the app against production data where the phase touches the network.

### Phase 0 — Prerequisites & test data (no code)
- [ ] Confirm the six prod record APIs return `pending_approval` + `approval_gates` on **detail** reads (needed for banner/pre-check); record which modules don't (backend ask AP-1: CRM task/follow-up detail omits `owner`).
- [ ] Re-read the open web backend asks and note live status: **AP-1** task/follow-up `owner` on read, **AP-2** `pending_approval` on list/board rows (so the chip is session-only), **AP-3** ticket `owner_name`, **AP-4** people list for the Requested-by/Owner filters (CRM users get 403 on `/management/users/`).
- [ ] Create real test requests on a **non-critical org/user pair** (an approval needs a requester *with* a manager and a gated module — `project_task` and `project` are already enabled in the superadmin org; lead/task/followup/issue are off). Needed to exercise list, detail, decide, escalate, withdraw, bulk, banner.
- [ ] Decide §7 open questions D1–D4 with the product owner before Phase 5/8/10.

### Phase 1 — Domain, DTO mapping, repository (no UI)
- [x] `approval.dart` entities with tolerant parsing (unknown `module`/`kind`/`status`/`route_reason` must not throw — fall back like the web DTOs do). Include `display.from/to`, `record_summary` as an ordered key→string list (keys vary by module), `steps[]`, `can_decide/can_escalate/can_withdraw`, `record_visible`, `decision_source` (`admin_override`).
- [x] `approval_rules.dart` — pure functions ported from web `approval.ts`: `closeNeedsApproval(gates, statusCode)`, `isRejectionNoteValid`, `hasNarrowingFilters`, constants (`REJECTION_NOTE_MIN=10`, `APPROVAL_NOTE_MAX=2000`, `BULK_DECIDE_MAX=200`), label maps from `approvalView.ts` (kind, module, scope, status→pill, route reason, step outcome).
- [x] `approvals_repository.dart` interface + `approvals_remote_ds.dart` + `approvals_api_repository.dart`; `approvals_mock_ds.dart` + `approvals_repository_impl.dart` for mock mode.
- [x] Verify 409/403 bodies surface `code` + `detail` through `AppError` (additive change to `app_error.dart` only if required).
- [x] Unit tests: mapper (full list row, detail row, sparse row, unknown enums), rules, bulk-result parsing.

### Phase 2 — Routing & navigation shell
- [x] `Routes.approvals = '/approvals'` (+ detail route) with `RouteMeta` consistent with other pushed screens; register in `app_router.dart` with **no `ModuleGuard`**.
- [x] `nav_catalog.dart`: entry `key: 'approvals'`, label `Approvals`, icon from the existing Phosphor set (web uses `badge-check` → `PhosphorIconsRegular.sealCheck`, already used in the due-date empty state), `modules: []`, `landing: false`. Place it where the web puts it (check `navigation.ts` line ~85 for order).
- [x] Drawer renders it for every authenticated user (confirm the drawer's "empty `modules` ⇒ visible" path, as My Trainings does).
- [x] Extend `test/nav_module_gating_test.dart`: Approvals visible for a role with zero modules, visible with null access, never chosen by `landingPathFor`.

### Phase 3 — Hold interpreter & shared 202 handling (the cross-cutting core)
- [x] `approval_hold.dart`: `readApprovalHold(status, body)` → only when `status == 202` and `code == 'APPROVAL_REQUIRED'` (a due-date 202 is *not* a hold); `recordOf(...)` returns `body['record']` on a hold else the body; `readPendingIds(...)` handles bulk `pending_ids` and the due-date `pending_due_date_change.object_id` shape.
- [x] A status-aware write helper in `core/network/api_service.dart` (there is already `patchWithStatus`; add `postWithStatus`) so repositories can see 202 without every caller re-implementing it.
- [x] One notifier (`approval_holds_provider.dart`) that, on a hold: shows the toast (`detail`, fallback "Sent for approval."), marks `object_id` held for the chip, and invalidates counts / list / that record's `for-record` state / the record's own row provider. Call sites must not be able to forget it — route all gated writes through the helper.
- [x] Clear a held id when the record's approval resolves or the user leaves; mirror `useReleaseHoldsOnLeave`.
- [x] Tests: 202 envelope, 202 without envelope (ignored), bulk `pending_ids`, due-date shape, toast text, invalidation set.

### Phase 4 — Approvals list screen
- [x] `ApprovalsScreen` using `DetailAppBar`/`AppHeaderBar` like the Quote approvals screen. Tabs via `TabChip`: *Waiting for me* (default, shows the `pending_for_me` count), *My requests*, *Team*, *History*. Team shown when `hasSubordinates || isSystemAdmin`, otherwise only when a `tab=team&page_size=1` probe returns `count > 0`.
- [x] Tab + kind persisted in route query (`?tab=…&kind=…`) so a notification or the old due-date entry can deep-link (`?kind=due_date`).
- [x] Search (`SearchField`, 300 ms debounce, `search=` on `record_label`), and a filter sheet (`core/filters/filter_sheet.dart`): Type, Module, Status (hidden on Waiting-for-me), Reportees scope (Team tab only), Requested by (hidden on My requests), Owner, Project, Raised from/to. Day bounds: from `T00:00:00`, to `T23:59:59`.
- [x] People options for the two user filters: reuse the assignable-user lists already used on mobile (merged, name-sorted, a list that 403s is skipped) — the web's AP-4 workaround; swap to a `filter-options` endpoint if the backend ships one.
- [x] `ApprovalCard` (via `AppCard`): record label, kind icon + module · kind, `from → to` + quoted request note, requested-by + relative time, owner, `StatusPill` + "with <approver>" when pending. Tap opens detail.
- [x] Paging: load-more at 20/page (server max 200), `RefreshIndicator`, `ListSkeleton`, `ErrorState.forError` with retry, `EmptyState` with the exact per-tab copy from the web (pending / mine / team / history) and the "No requests match your filters" + clear-filters variant.
- [x] `OtherApprovalsStrip` from `counts.other` (quote discounts → `Routes.quoteApprovals`; hide rewards/lifecycle rows that have no mobile destination, per D3).
- [x] Counts: `FutureProvider.autoDispose` with `quiet: true`, refetched on a ~60 s timer and on app resume; drawer badge + tab badge read it.

### Phase 5 — Detail + decisions
- [x] Detail screen (decision D2) using `DetailAppBar` like other detail pages: status pill, module · kind, `from → to`, request note; Request block (Requested by, Record owner, Approver, Raised, Decided by, Decided, Decision note); Record block from `record_summary` (key → "Due date" style label); Timeline from `steps[]` with outcome labels and route-reason labels.
- [x] Footer actions only when pending **and** the matching flag is true: *Open record* (only when `record_visible`; route per module → lead / task / follow-up / ticket / ops task / project detail with the existing `?id=` convention), *Withdraw* (no body), *Escalate* (optional note), *Reject*, *Approve*.
- [x] `ApprovalDecisionDialog` with the web copy verbatim: Approve — optional comment, hint "The change applies now. Your comment goes to the activity log."; Reject — required reason ≥10 chars with the "At least 10 characters" hint, danger-styled confirm; Escalate — optional note, hint "This goes to your manager. You keep read-only sight of it." Max length 2000. Inline error text under the field on failure; busy state disables both buttons.
- [x] Done toasts: Approved / Rejected / Escalated / Request withdrawn. After success invalidate list, counts, this detail, and the affected record's row/banner providers (port `invalidateApprovalRecord.ts`: lead/task/followup/issue/project_task/project row providers).
- [x] Error handling per code: `APPROVAL_STALE` → show the message and refresh the list (request is now *superseded*); `APPROVAL_NOT_PENDING` → refresh; module-rule failures (open invoices, open tasks, completion note, dependencies, owner no longer eligible) show the module's own message and the request stays pending.

### Phase 6 — Bulk decide
- [x] Long-press / "Select" mode on the **Waiting for me** tab only; rows selectable only where `can_decide`; select-all selects decidable rows on the page; selection clears on tab/filter/page change.
- [x] Bulk bar (reuse the existing multi-select bar used by Leads/Tasks) with Approve / Reject / Clear; disabled above 200 selected.
- [x] Reuse `ApprovalDecisionDialog` (subject "N requests"); result toast `"<updated> done · <skipped> skipped"`; keep `errors[]` available to show per-row reasons.

### Phase 7 — Integrate with the six record modules (banner, pre-check, hold, chip)
Modules and their existing mobile screens: Lead (`lead_detail_screen.dart`, leads list), CRM task (`task_detail_screen.dart`, `tasks_screen`), Follow-up (`followup_detail_screen.dart`, `followups_screen`), Ticket (helpdesk ticket detail), Project task (operations task detail + `ops_tasks_remote_ds.dart` bulk), Project (project detail).
- [x] `ApprovalBanner`: reads `pending_approval` straight off the record's detail row (Map-based `…RowProvider`s already hold the raw body) and falls back to `for-record` only when the row lacks the key. Copy: "Closing to <to> is waiting for approval from <approver> (since <date>). The record stays as it is until then." Buttons by `can_*`. Mount once per detail screen near the header, matching the look of the lead "Conversion requested — waiting for a manager" row / quote discount banner so it blends.
- [x] `ApprovalRequestCommentDialog` + an async helper `askApprovalNote(...)` (port of `useApprovalRequestNote`): before a **close** or **owner change**, check gates (row first, `for-record` second, 30 s cache); if a request is already pending or no gate applies, return `''`; otherwise ask for the optional comment and return it or `null` if cancelled (nothing saved). If the gate check itself fails, **still save** (server is the authority; only the comment is lost).
- [x] Wire the helper into each module's status change and owner change (task/follow-up *reassign* flows already exist — `_reassign` in task detail, `reassign_owner_test.dart`), sending `request_note` with the normal PATCH. Preserve each module's field names: lead `status_id`/`lead_owner`; task, follow-up, ticket `status_id`/`owner`; project task `status`/`owner` (write-only, read from `owner_detail`); project `status`/`owner` (governance field — surface `PROJECT_GOVERNANCE_FIELD` 403 as the server words it).
- [x] Route every one of those writes through the Phase 3 helper so a `202` → toast + chip + cache refresh, and the screen keeps showing the record unchanged (use `record` from the envelope).
- [ ] Bulk status changes (ops tasks, any mobile bulk path): read `updated / pending / pending_ids / skipped_ids / errors` and toast `"3 updated · 7 sent for approval · 1 skipped"`; mark `pending_ids` held.
- [x] `PendingApprovalChip` on lead / task / follow-up / ticket / project task / project cards and board tiles ("Sent for approval", session-scoped; real data needs AP-2).
- [x] Lead **convert**: handle `202 {code: APPROVAL_REQUIRED, approval}` alongside the existing 202 handling in `lead_lifecycle_providers.dart`; when the tenant gates *Won*, the old `conversion_requires_approval` switch is superseded (`/crm/lead-rules/` returns `conversion_approval_superseded_by_approvals: true`) — read that flag so the existing "Conversion requested" copy and the new banner don't both appear. Keep the `409 APPROVAL_ALREADY_PENDING` message.
- [x] Per-module refusals when *requesting* (must pass the module's normal rules): lead→Lost needs `lost_reason`; `LOST_HAS_OPEN_INVOICES` → offer `credit_open_invoices: true`; `PROJECT_HAS_OPEN_TASKS` → offer `open_tasks_action: "cancel"`; task completion note; project-task open dependencies/subtasks; ticket open child tickets; ineligible new owner. Reuse the dialogs those flows already show.

### Phase 8 — Migrate due-date approvals onto the unified module
- [x] Replace the data source behind `due_date_approvals_screen.dart` (`/sla/due-date-changes/pending/`) with `/approvals/?tab=pending&kind=due_date`; decide via `/approvals/{id}/approve|reject`. Rejection now requires ≥10 chars; `APPROVAL_STALE` replaces `due_date_change_stale / _record_closed / _record_missing`.
- [x] Keep `Routes.dueDateApprovals` working as a redirect to `/approvals?kind=due_date` (web does the same) and keep the Tasks toolbar "Due date approvals (N)" count, now sourced from `counts.by_kind.due_date`.
- [x] Due-date requests are decided by the **record owner's** manager (or Project Manager), not the requester's — update any copy that says otherwise.
- [x] `due_date_change.dart`'s 202 path stays (it is *not* an `APPROVAL_REQUIRED` hold; see Phase 3 shape rules) but should mark the record held and invalidate approval caches.
- [x] Verify nothing else still calls the deprecated endpoints (they are "kept for one release").

### Phase 9 — Notifications
- [x] Add `ApprovalRequested`, `ApprovalDecided`, `ApprovalEscalated`, `ApprovalRerouted`, `ApprovalClosed` (and legacy `DueDateChangeRequested/Decided`) to `notification_links.dart` / `notification_navigator.dart` so a tap opens `/approvals` (Waiting-for-me for Requested/Escalated/Rerouted; My requests/History for Decided/Closed).
- [ ] Refresh counts when a push for these types arrives in the foreground.
- [x] Extend `test/notification_links_test.dart`.

### Phase 10 — Settings → Approvals (optional, pending D1)
- [ ] Only if approved: a screen reachable by users with `settings` (read) and editable with `settings → update`. Per-module switches *Approve closing* / *Approve reassignment*, close-status checkboxes (lead: won/lost/junk; task & follow-up: completed/cancelled; project task: *Include cancelled*; issue/project: none), the "Won supersedes Conversions need approval" note, and the due-date rules block (same fields as the existing mobile SLA due-date rules). Send only the changed subset on `PATCH /approvals/settings/`; Save/Discard bar; unsaved-changes guard; `PermissionCopy.update` when not allowed. Reuse existing switch / checkbox / form-row widgets from other mobile forms.
- [ ] If not approved, record "web-only" in §7 and skip.

### Phase 11 — Tests, QA, UAT
Unit / widget (`test/features/approvals/`):
- [ ] `approval_mapper_test.dart` — list row, detail row, steps, summary, unknown enums, null owner (AP-1).
- [ ] `approval_rules_test.dart` — `closeNeedsApproval` per module status codes, rejection validity (9 vs 10 chars, whitespace), bulk cap.
- [ ] `approval_hold_test.dart` — every 202 shape (Phase 3).
- [ ] `approval_actions_test.dart` — each verb's body, error-code → message, invalidation set.
- [ ] `approvals_screen_test.dart` — tab set (Team hidden / shown by `hasSubordinates` and by probe), empty copy per tab, filter-empty variant, bulk selection only for `can_decide`.
- [ ] **Permission matrix** (`approval_permissions_test.dart`): superuser/full-access, System Admin, plain CRM user (no `settings`), role with zero modules, access `null` (loading/failed/mock) — assert entry visible, route not blocked, buttons follow `can_*`, settings save gated, never landed on `/approvals` by `landingPathFor`.
- [ ] Banner/pre-check tests per module: gate on/off, already pending, gate-check failure still saves.
- [ ] Update `nav_module_gating_test.dart`, `notification_links_test.dart`, due-date tests (Phase 8).

Manual against production (`https://app.clozr.co.in`, `superadmin@clozr.com`):
- [ ] Login → Approvals appears in the drawer; list loads for each tab; counts badge matches `/approvals/counts/`.
- [ ] End-to-end with two users: raise (close + owner transfer + due-date) → appears in approver's *Waiting for me* → approve / reject (short reason blocked) / escalate / withdraw → requester sees it in *My requests* and *History*; bulk approve and bulk reject including a partial-failure set.
- [ ] Banner + chip on each of the six modules; `409 APPROVAL_ALREADY_PENDING` path; stale request path (change the record, then approve).
- [ ] Light/dark and small-width (320 px) checks, large-text check; compare against Quote approvals for visual parity.

UAT: add an Approvals sheet to the mobile UAT workbook using the existing generator and Blocked/fix-round workflow (see memory notes `uat-retest-workflow`, `crm-detail-screens-uat-workbook`), covering the §1 table rows 1–15.

### Phase 12 — Definition of done
- [ ] All §1 rows delivered or explicitly marked web-only in §7.
- [ ] No UI element invented outside the approved widget list in §0.1.
- [ ] §3 permission behaviours verified by tests and by the prod account.
- [ ] `fvm flutter analyze` clean; `fvm flutter test` shows only the 7 known baseline failures.
- [ ] No remaining caller of `/sla/due-date-changes/*`.
- [ ] This file updated with final status and any backend asks (AP-1…AP-4) still open.

---

## 6. Suggested order of delivery (smallest usable slice first)

1. Phases 0–2 → entry + empty shell reachable.
2. Phases 3–5 → read & decide requests end to end (the usable core).
3. Phase 7 → the part that *creates* requests from the six modules (largest risk surface; touch one module at a time: Project task → Project → Task → Follow-up → Ticket → Lead, starting with the two already gated in the prod org).
4. Phases 6, 8, 9 → bulk, due-date migration, notifications.
5. Phase 10 only if D1 says yes; Phases 11–12 run continuously, finalised at the end.

---

## 7. Open decisions (answer before the phase they block)

| ID | Question | Blocks | Recommendation |
|---|---|---|---|
| D1 | Does mobile get **Settings → Approvals**? Mobile has no Settings area today; web has it. | Phase 10 | **Decided: web-only for now.** |
| D2 | Detail as a **pushed screen** or **bottom sheet**? | Phase 5 | **Decided: pushed screen** (`/approvals/detail?id=`). |
| D3 | "Other approvals" strip: rewards and lifecycle have no mobile screen. Hide those rows, or link to the web? | Phase 4 | **Decided: hidden** until a mobile destination exists; quote discounts link to the existing screen. |
| D4 | Move the old `due_date_approvals_screen` fully into the unified screen now, or keep both until the backend drops the deprecated endpoints? | Phase 8 | **Decided: migrated now.** |

## 8. Risks / watch-outs

- **Every gated write must go through the Phase 3 helper**, otherwise a 202 is silently treated as success with the record "unchanged" and no feedback. Treat a missed call site as a bug in review.
- List/board rows carry no approval flag (AP-2), so chips are session-only and a second attempt can still hit `409 APPROVAL_ALREADY_PENDING` — message it kindly, don't treat it as a crash.
- CRM task/follow-up detail omits `owner` (AP-1): the Owner row can read "Not shown"; changing it still works and the gate still applies.
- `record_summary` keys differ per module — render generically (ordered key→value), never hard-code fields.
- Project governance field (`owner` on a project): non-governors get 403 `PROJECT_GOVERNANCE_FIELD`; don't pre-hide it, show the server's message.
- Counts endpoint is cached 60 s server-side; don't poll faster, and refresh explicitly after a local decision.

## 9. Implementation log (2026-11-10)

**New feature** — `lib/features/approvals/`
- `domain/entities/approval.dart` — tolerant entities (unknown enums render, never throw).
- `application/approval_rules.dart` — rules, labels, record routes, query params, error copy.
- `application/providers/approvals_providers.dart` — repository DI (mock / API), list, detail, counts (60 s + after any write), Team probe, tabs, `for-record` state, session "held records".
- `application/providers/approval_actions_providers.dart` — approve / reject / escalate / withdraw / bulk, plus approvals + record invalidation.
- `infrastructure/` — remote data source, API repository, mock seed + in-memory mock repository.
- `presentation/screens/approvals_screen.dart` (tabs, search, filter sheet, load-more, long-press bulk select) and `approval_detail_screen.dart`.
- `presentation/components/` — `approval_parts.dart` (card, status chip, change text, record banner, pending chip, other-approvals strip, count dot), `approval_decision_dialog.dart` (decision / bulk / request-comment dialogs, in the quote-discount dialog style), `approval_request_note.dart` (pre-save gate check, `writeWasHeld`, `projectTaskCloseCode`).

**Cross-cutting**
- `core/network/approval_hold.dart` + `ApiService.holds` — every `202` is read in `_run`; a held save returns its `record`, so existing callers keep working. `ApiService.postWithStatus` added.
- `network_providers.dart` `apiApprovalHoldProvider` → `ClozrShell` listener: toast (server wording), "Sent for approval" chip, approvals refresh. Delivered 350 ms late so it replaces a caller's own "Saved" toast.
- Routes `/approvals`, `/approvals/detail` (no `ModuleGuard`); drawer entry `approvals` (`modules: []`, `landing: false`) with the pending-count badge.
- Notifications `Approval*` / `DueDateChange*` open Approvals (`notifications_remote_ds.dart`, `notification_navigator.dart`).

**Module integration (Phase 7)**: banner + close pre-check + hold handling on lead, CRM task, follow-up, ticket, project task, project; lead owner transfer pre-check; lead conversion `202 APPROVAL_REQUIRED`; chip on lead / task / follow-up (`SchemaMobileCard.badge`), ticket, ops task and project cards. Ticket writes now pass `request_note` through `_buildUpdate`. `CrmTasksRepository.setTaskStatusByKey` takes `requestNote` and returns whether the move was held.

**Due dates (Phase 8)**: `/tasks/due-date-approvals` redirects to `/approvals?kind=due_date`; the toolbar count reads `counts.by_kind.due_date`; the old decision dialog and every `/sla/due-date-changes/*` call are removed. Toast copy is now "Sent for approval" (the owner's manager decides, not necessarily the requester's).

**Tests**: `test/features/approvals/` — mapper, rules, 202 interpreter, permission matrix + notification routing, and widget tests (list / tabs / deep link / empty state / reject rule / banner). `nav_module_gating_test.dart` updated (Approvals is visible to every role). Full suite: 1483 pass, 7 fail — exactly the known baseline (`crm_home_mapper`, `dashboard_mapper`, `lead_call_routing`, `people_mapper`, `project_filter_codec` ×2, `ticket_directory`). `fvm flutter analyze lib`: no errors or warnings.

**Verified against production** (`superadmin@clozr.com`): login, `/approvals/` with every filter the app sends (incl. local ISO dates without zone), `/approvals/counts/`, `/approvals/for-record/` for a project (`pending_approval: null`, `close_statuses: ["closed"]`), and the 404 body for an unknown id — all match the mappers.

**Known gaps / deviations**
- CRM task & follow-up: mobile's "Task owner" writes `assigned_to`, while the backend gates `owner` (the field the web sends). So there is no owner-transfer pre-check there. Changing which field mobile writes is a separate product decision.
- Ticket, project task and project owners are not editable on mobile today, so they have no owner pre-check. Status/close is covered.
- Mobile has no bulk status action, so "N updated · M sent for approval" has no caller. The shell still marks any `pending_ids` as held.
- The chip is session-only until backend AP-2 ships. Counts refresh every 60 s and after any write; a push does not refresh them directly.
- Not done here: a run on a device or emulator, the two-user end-to-end flow (the prod org has no requests yet — Phase 0), and the UAT sheet.
