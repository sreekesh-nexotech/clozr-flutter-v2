# Clozr Flutter — API Integration Architecture (data / infrastructure / application layers)

This is the working contract for wiring the presentation layer (already built,
mock-backed) to the NexoCRM Django API. Implementation agents MUST follow it.

## 0. Golden rules

1. **Presentation stays intact.** Screens keep reading the same providers and
   the same domain entities. The remote layer maps API JSON → the existing
   entities (display strings included). Only minimal presentation edits are
   allowed: wiring an existing `_submit()` / mutation call site to a new
   repository method. Never restyle, rename, or move screens/widgets.
2. **Mock mode keeps working.** `ApiConfig.apiEnabled` (from
   `--dart-define=API_BASE_URL=…`) decides remote vs mock in each feature's DI
   provider. With no base URL the app behaves exactly as before.
3. **Single ApiService.** All HTTP goes through
   `lib/core/network/api_service.dart` (Dio + auth interceptor + refresh).
   Repositories/data sources never construct Dio and never see raw
   DioException — `ApiService` throws `AppError`.
4. **Layering:** remote data source = HTTP call + JSON→entity mapping only.
   Repository impl = orchestration + Hive fallback caching (via `AppCache`).
   Providers call repositories. UI calls providers.
5. `flutter analyze` must stay clean; every new mapper gets a unit test.

## 1. Core (already built — reuse, do not re-create)

| File | Provides |
|---|---|
| `lib/core/config/api_config.dart` | `ApiConfig.baseUrl/apiPrefix/apiEnabled/defaultPageSize` |
| `lib/core/network/api_service.dart` | `ApiService.get/post/put/patch/delete/postForm` (returns decoded JSON, throws `AppError`) |
| `lib/core/network/auth_interceptor.dart` | bearer header, single-flight 401 refresh → retry once → logout |
| `lib/core/network/app_error.dart` | `AppError` (`type`, `message`, `statusCode`, `fieldErrors`) |
| `lib/core/network/paginated.dart` | `Paginated<T>.fromJson` / `Paginated.fromAny` for `{count,next,previous,results}` |
| `lib/core/network/api_endpoints.dart` | every endpoint path constant/builder |
| `lib/core/network/network_providers.dart` | `apiServiceProvider`, `tokenStorageProvider` |
| `lib/core/storage/token_storage.dart` | JWT pair in secure storage |
| `lib/core/storage/app_cache.dart` | Hive JSON cache: `AppCache.put/get/remove/clearAll`, box name constants |
| `lib/core/utils/relative_time.dart` | `relativeTime()`, `parseApiDate()`, `absoluteDate()` |
| `lib/core/utils/inr_format.dart` | `formatInr()`, `parseAmount()` |
| `lib/data/api/user_directory.dart` | `UserDirectory.mapUserId()` (uuid → `'me'`), `.register()`, `.hydrate()` |
| `lib/data/api/status_keys.dart` | API status-name/type → UI status-key mappers |
| `lib/features/auth/**` | session state (`sessionControllerProvider`), login/2FA |

## 2. Feature wiring pattern

For each feature slice `<x>`:

1. `infrastructure/data_sources/remote/<x>_remote_ds.dart`
   — class `<X>RemoteDataSource`, ctor takes `ApiService`. One method per
   endpoint. Maps JSON → domain entities right here (private `_lead(Map)` etc.
   mappers, or a shared `<x>_mappers.dart` next to it if large). No caching.
2. `infrastructure/repositories/<x>_api_repository.dart`
   — class `<X>ApiRepository implements <X>Repository`. Wraps the remote DS.
   Read methods: try remote → on success `AppCache.put`, on `AppError` of type
   network/timeout → serve `AppCache.get` fallback if present, else rethrow.
   Write methods: remote only (no cache write-through; bump/remove the list
   cache key so the next read refetches).
3. Extend the abstract repository in `domain/repositories/` with the write
   methods the UI needs (see per-feature briefs). Update the existing mock
   impl (`<x>_repository_impl.dart`) to implement them as harmless local
   returns so mock mode still compiles and works.
4. DI provider (in the feature's existing `application/providers/*.dart`):

```dart
final xRepositoryProvider = Provider<XRepository>((ref) {
  if (!ApiConfig.apiEnabled) return const XRepositoryImpl(XMockDataSource());
  return XApiRepository(
    XRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});
```

5. Tests in `test/features/<x>/` — JSON fixture map → entity assertions for
   every mapper (status keys, money strings, relative time inputs, user id
   mapping, null tolerance), plus repository fallback behavior with a fake
   remote DS.

## 3. Mapping conventions (API JSON → existing UI entities)

- **Money:** entities carry display strings + numeric twins. Use
  `parseAmount()` then `formatInr()` (e.g. `lead_value: 3650000` →
  `value: '₹36.5L'`, `valueNum: 3650000`).
- **Timestamps:** ISO strings → `relativeTime(parseApiDate(v))` for `time`
  fields; `absoluteDate()` for `createdOn`-style fields.
- **User ids:** every owner/assignee uuid goes through
  `UserDirectory.mapUserId(uuid)` so the signed-in user's uuid becomes `'me'`
  (keeps `isMine`/avatar logic intact). Also `UserDirectory.register(...)`
  any embedded user objects (uuid, full_name) so `MockUsers.of(id)` resolves
  names/initials for real users.
- **Status keys:** UI uses fixed keys (`StatusMeta$.*`). Map via
  `lib/data/api/status_keys.dart` helpers, preferring the server's
  `status_type` code when present and falling back to normalized name
  matching. Unknown → sensible default (documented per feature below).
- **Never crash on nulls/shape drift:** every field read is defensive
  (`as String?` + fallbacks). A malformed row is skipped, not fatal.
- **Pagination:** list fetches use `page_size` = `ApiConfig.defaultPageSize`
  and follow `next` up to a sane cap (3 pages) unless the feature brief says
  otherwise — the UI's providers expect a full in-memory list today.

## 4. Backend contract essentials

- Base: `${API_BASE_URL}/api/v1`. Auth: `Authorization: Bearer <access>`
  (RS256, 30-min access / 7-day refresh). Refresh: `POST /auth/login/refresh/`
  `{refresh}` → `{access}`. Login returns `access_token`/`refresh_token`
  (asymmetric — handled by auth feature).
- Pagination envelope: `{count, next, previous, results}`.
- Errors: `{code:<int>, message:<str>}` (+ `errors:{field:[msg]}` on 400).
  500s can be HTML — never parse. Handled centrally by `AppError`.
- Detail lookups use UUID fields (`lead_id`, `task_id`, `customer_id`, …).
- Follow-ups are CRM tasks with `is_followup=true` (same `/crm/tasks/`).
- CRM filter negation `__not`; PMO/helpdesk use `__not_in`. Lead dates
  `created_at_after` (single underscore); customer `created_at__after`.
- Schema endpoints (`…/schema/?view_type=list|detail|form`) drive dynamic
  columns; mobile maps rows onto its fixed card layouts instead, so schema
  fetches are optional (skip unless a field genuinely needs choices).

Full per-endpoint contracts: the other files in `docs-flutter/` (leads.md,
customer.md, task-schema-and-status-api.md, task-filters.md, operations.md,
operations-task.md, notes.md, members.md, team-api.md, roles.md, login.md,
admin_dashboard.md, admin_crm_dashboard.md, admin_operations_dashboard.md,
operations-backend-requests.md §5.2 for notifications).

## 5. Identity

`lib/features/auth` owns the session. After login/restore the session
controller stores the user's uuid in `UserDirectory.currentUserId` and
best-effort hydrates the org roster (`GET /management/users/`, ignore 403)
into `MockUsers.byId` so avatars/names resolve app-wide. The `'me'` sentinel
everywhere in the presentation layer keeps working through
`UserDirectory.mapUserId`.
