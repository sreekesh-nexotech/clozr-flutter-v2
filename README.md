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
