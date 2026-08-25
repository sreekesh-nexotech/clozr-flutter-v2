# Clozr — Mobile app (Flutter)

Mobile-first B2B CRM. This branch (`feat/presentation-layer`) contains the
**presentation layer**, reproducing the Clozr design prototype
(`Clozr CRM v4.dc.html`) pixel-for-pixel in Flutter.

## Stack
- Flutter **3.24.5** / Dart **3.5.4** (per `docs-flutter/Technical_stack.md`)
- State: **Riverpod** · Routing: **go_router** · Responsiveness: **flutter_screenutil** (390×844 canvas)
- Icons: **phosphor_flutter** · Charts: **fl_chart** + custom `Sparkline` · Font: **Manrope** (self-hosted)

> Note: the generated scaffold declared `sdk: ^3.11.0`; the constraint was
> lowered to `>=3.5.0 <4.0.0` to match the documented 3.24.5 toolchain.

## Toolchain (read this before your first run)
The 3.24.5 pin is **not optional** — the project does not compile on recent
Flutter releases:
- `phosphor_flutter` 2.1.0 (the latest and final release) does
  `class PhosphorIconData extends IconData`, and Flutter marked `IconData`
  as a `final class` in 3.43. See
  <https://docs.flutter.dev/release/breaking-changes/icondata-class-marked-final>.
- `CupertinoPageTransitionsBuilder` (used in `lib/app/theme/app_theme.dart`)
  moved out of the `material` library into `cupertino` in the same era, so it
  is no longer reachable through `package:flutter/material.dart`.

The pin is declared in `.fvmrc` and applied with [FVM](https://fvm.app):
```bash
dart pub global activate fvm     # once per machine
fvm install                      # reads .fvmrc → fetches 3.24.5
fvm use 3.24.5                   # links .fvm/flutter_sdk
```
Then prefix commands with `fvm` (VS Code picks the SDK up automatically via
`.vscode/settings.json`). A bare `flutter` on your PATH will use whatever
version you have installed globally and will fail to build.

## Run
```bash
fvm flutter pub get
fvm flutter run             # device / emulator
# Web (used for the pixel-comparison pass):
fvm flutter build web --web-renderer canvaskit --no-web-resources-cdn
```

## Crash reporting (Sentry)
Wired in `lib/core/monitoring/` and initialized from `app/bootstrap`. The DSN
ships in `sentry_config.dart` (a DSN is a public write-only ingest key), and
every knob is a `--dart-define`:

| Define | Default | Purpose |
| --- | --- | --- |
| `SENTRY_DSN` | the `clozr` project DSN | **Empty value turns reporting off** — the SDK still initializes and starts the app, it just drops every event |
| `SENTRY_ENVIRONMENT` | `production` / `profile` / `development` by build mode | Segregates the issue stream |
| `SENTRY_RELEASE` | derived from package metadata | Groups issues by build, e.g. `clozr@1.0.0+1`. CI should pass whatever it uploads debug symbols under |
| `SENTRY_TRACES_SAMPLE_PCT` | `20` in release, `100` otherwise | Share of performance transactions kept |

```bash
fvm flutter run --dart-define=SENTRY_DSN=          # reporting off
fvm flutter build apk --release --dart-define=SENTRY_RELEASE=clozr@1.0.0+1
```

What is captured: uncaught Dart/Flutter errors, 5xx responses from the
`ApiService` Dio, navigation and HTTP breadcrumbs, and screen-load transactions.
What is **not**: request/response bodies, headers, screenshots, the widget tree,
or any name/email — `sendDefaultPii` is off and only the user + org **ids** are
attached to an event. Expected failures (offline, timeout, 401/403/404,
validation) are filtered out so they don't bury real defects. Feature code should
call `AppMonitoring`, never `Sentry` directly.

> **Held at `sentry_flutter` 8.x**, and `package_info_plus` at 8.x with it —
> both because of the 3.24.5 toolchain pin, not preference. `pubspec.yaml`
> carries the full reasoning next to each constraint; `android/build.gradle.kts`
> carries the one Gradle workaround 8.x needs. All three notes come down
> together when the Flutter pin is lifted.

## Architecture (feature-first, 4 layers)
Per `docs-flutter/Folder structure - structure.csv`:
```
lib/
├─ app/        app-wide wiring — bootstrap, config, router, theme
├─ core/       cross-cutting: design-system widgets, utils, error
├─ data/mock/  shared mock seed (users, status maps)
└─ features/<feature>/
   ├─ domain/          entities + abstract repositories
   ├─ application/     Riverpod providers (state, no UI)
   ├─ infrastructure/  data_sources/local (mock) + repository impls
   └─ presentation/    screens + components (pure UI)
```

### Swappable static data
Every screen's sample data flows **entity → local mock data source →
repository impl → Riverpod provider → UI**. To wire the real API, replace the
`*_mock_ds.dart` data source (or override the repository provider in
`app/bootstrap/app_bootstrap.dart`) with a Dio/Retrofit-backed one — **no UI or
provider changes required**.

## Scope built (50+ screens across 9 modules)
CRM (Home dashboard, Leads, Customers, Follow-ups, Tasks, Quotes, Payments,
Invoices, Products, Billing, Reports + details/forms) · Operations (Home,
Projects, Tasks + detail/create/edit) · Helpdesk (Home, Tickets, Boards +
detail/edit) · Training/LMS (Overview, Courses, Builder, Learners, My courses,
Player) · Dashboard (Business/CRM/Operations/Helpdesk manager panels) ·
Notifications · Rewards · People (Members/Teams/Roles) · Messages/Chat, plus the
shared shell (status bar, bottom nav, drawer, toast).

See `docs-flutter/PRESENTATION_BUILD_CONTRACT.md` for the design-fidelity rules
and the core widget API.
