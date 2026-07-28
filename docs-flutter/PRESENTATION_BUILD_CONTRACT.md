# Clozr Presentation Layer — Build Contract (for module agents)

You are implementing the **presentation layer** of the Clozr mobile app in
Flutter, reproducing a designed HTML prototype **pixel-for-pixel**. The
foundation, shell, router, theme, core widgets and the CRM Leads reference
slice are already built and compiling. Your job: implement your assigned
module's screens by editing the existing **stub screen files** (same path,
same class name — do NOT rename or move them) and adding components / mock
data / providers under your feature folder.

## Sources of truth
- **Design prototype:** `/home/claude/repo/project/Clozr CRM v4.dc.html`
  (390×844 canvas). Read the exact line ranges given in your task. Every
  screen is a `<div data-screen-label="…">`. Inline styles are the spec —
  copy colours, sizes, paddings, radii, weights exactly.
- **View-model logic** (labels, colours, seed data, computed values) lives in
  the `<script>` after line 6864. The relevant `renderVals()` block for each
  screen is around lines 8383–10730.
- **Seed data** is already extracted into Dart under `lib/data/mock/` and each
  feature's `infrastructure/data_sources/local/`. Reuse it; do not invent new
  records. If your screen needs seed data not yet ported, add it to a mock data
  source following the CRM leads pattern.

## Golden rules
1. **Never hardcode hex/px in widgets.** Use `AppColors`, `AppText`,
   ScreenUtil extensions (`.w .h .r .sp`). Add a token to `AppColors` if a
   colour is genuinely missing.
2. **ScreenUtil everywhere.** Widths/gaps → `.w`, heights → `.h`, radii/padding
   → `.r`, font sizes → `.sp`. The design canvas is 390×844 — a raw design px
   maps 1:1 to `.w`/`.h`.
3. **Match the design, not the prototype's DOM.** Rebuild the visual with clean
   Flutter widgets; don't transliterate divs.
4. **Pure UI widgets.** Read state from Riverpod providers, call controllers.
   No business logic in widgets. Immutable state classes only.
5. **Static data is swappable.** All sample data flows entity → mock data
   source → repository impl → provider → UI. To integrate the API later, only
   the data source is replaced. Keep this seam intact.
6. **Reuse core widgets** (see below). Extract a component to
   `presentation/components/` when a card/row repeats.

## Icon translation (Phosphor)
The prototype uses `<i class="ph ph-foo-bar">`. In Flutter use
`phosphor_flutter`:
- `ph ph-foo-bar`  → `PhosphorIconsRegular.fooBar`
- `ph-fill ph-foo` → `PhosphorIconsFill.foo`
- `ph-bold ph-foo` → `PhosphorIconsBold.foo`
Kebab-case → camelCase. If unsure a name exists, grep
`/root/.pub-cache/hosted/pub.dev/phosphor_flutter-2.1.0/lib/src/phosphor_icons_regular.dart`.

## Foundation you build on (import & reuse — do not re-create)
Theme: `lib/app/theme/` → `AppColors`, `AppText`, `AppDimens`.
Router: `lib/app/router/routes.dart` → `Routes.*` path constants. Navigate with
  `context.go(Routes.x)` for tab/drawer destinations, `context.push(Routes.x)`
  for detail/create/edit. Detail screens read params via
  `GoRouterState.of(context).uri.queryParameters['id']`. Pass ids as
  `?id=…` query (see LeadsScreen → LeadDetailScreen).
Shell (already wraps every screen): status bar, bottom nav, drawer, toast,
  home indicator. **Do not** add your own status bar / bottom nav. Show a toast
  with `ref.read(toastProvider.notifier).show('…')`. Open the drawer with
  `ref.read(drawerOpenProvider.notifier).state = true` (AppHeaderBar already
  does this).

### Core widgets (lib/core/widgets/)
- `ListHeader(children:[…])` + `HeaderHairline()` — white top block for list
  screens (already clears the 56px status-bar gap).
- `AppHeaderBar()` — brand row (logo + workspace + messages + bell). Put it
  first inside `ListHeader`.
- `ScreenTitleRow(title:, onSearch:, onFilter:, hasSearchQuery:, filterCount:)`.
- `SearchField(controller:, onChanged:, onClose:, hint:)`.
- `TabChip` + `TabChipRow` — status/filter tabs (active = blue ring; optional
  `dotColor`).
- `DetailAppBar(section:, name:, onBack:, trailing:)` + `DetailIconAction` —
  back header for detail/form screens.
- `ClozrCard(child:, radius:, elevated:, onTap:)` + `ClozrDivider()`.
- `StatusPill.meta(StatusMeta)` / `StatusPill(label:,color:)`, `PriorityPill`.
- `InitialsAvatar` + `AvatarStack`.
- `EmptyState(icon:, title:, body:, ctaLabel:, onCta:)`.

### Data helpers (lib/data/mock/)
- `MockUsers.reps`, `MockUsers.of(id)`, `MockUsers.byId`, `.memberColors`.
- `StatusMeta$.lead / customer / task / followup / quote / payment / invoice /
  project / opsTask / ticket / lms` — `{label,color}` maps. `.priorityTone`,
  `.projectPriority`.

## Reference to copy patterns from
- List screen: `lib/features/crm/presentation/screens/leads_screen.dart`
- Card component: `lib/features/crm/presentation/components/lead_card.dart`
- Data flow: `lib/features/crm/{domain,infrastructure,application}` (leads)
- Detail screen: `lib/features/crm/presentation/screens/lead_detail_screen.dart`

## Definition of done for your module
- Every assigned screen implemented from its design lines, visually faithful.
- `flutter analyze` clean (no new errors/warnings).
- All sample data via the entity→mock-ds→repo→provider seam.
- Components extracted for repeated widgets.
- Reuse core widgets; no duplicated status bar / nav / header.
