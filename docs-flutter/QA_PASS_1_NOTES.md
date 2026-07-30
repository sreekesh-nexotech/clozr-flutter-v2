# QA Pass 1 — resolution notes

Resolutions for the 14 QA/QC findings on the presentation layer. All work is on
`feat/presentation-layer`; `flutter analyze lib` is clean.

| # | Finding | Resolution | Verified |
|---|---------|------------|----------|
| 1 | Bottom nav floating background | Rebuilt as a true two-layer frosted stack: an 88px `blur(32)` strip with a floating 64px rounded pill that adds its own `blur(52)` (`core`… `clozr_bottom_nav.dart`). | screenshot |
| 2 | Notification badge style | **Deferred** per instruction ("ignore for now"). | — |
| 3 | Filter modals not working | Built a spec-driven filter engine (`lib/core/filters/`, 7 control types) and wired the drawer into every list (Leads, Customers, Follow-ups, Tasks, Quotes, Payments, Products, Projects, Ops Tasks, Tickets, Members, Teams). CRM/Products fields follow `FILTER_AUDIT_spec.txt`; Ops/Helpdesk/People replicate the prototype's `modFilter`/`membersFilter`/`teamsFilter`. Draft-then-apply, Reset All, Apply-with-count. | screenshot |
| 4 | Saved filter ↔ state sync | Applying a saved view loads its values into the drawer draft (editable and re-savable via Save/Update view). | code |
| 5 | Applied-filter count on the filter icon | `AppHeaderBar.filterCount` badge = `FilterValues.activeCount`; a Clear affordance shows whenever any filter is active (`SavedChipRow.showClearAlways`). | code |
| 6 | Period modal obscured by nav | All bottom sheets now present on the root navigator (`showClozrSheet` → `useRootNavigator: true`), so the sheet and its Apply CTA sit above the bottom nav. | screenshot |
| 7 | Detail 3-dot actions not working | Shared `showActionMenu`/`MenuAction` sheet wired on every detail page (lead, customer, follow-up, CRM task, project, ops task, ticket) with the design's items; lock-aware. | screenshot |
| 8 | Lead-card Call button width | Standardized to a single compact fixed-size button across all lead-card states. | screenshot |
| 9 | Projects header `+` | Removed; add is handled by the contextual bottom-nav `+`. | screenshot |
| 10 | Projects nav `+` → Add project | Projects `+` opens Create Project; Ops Tasks `+` opens Create Task. | code |
| 11 | Task detail Color tag | Field removed from Task Detail and the Edit Task form. | screenshot |
| 12 | Subtask navigation | Subtask rows are tappable → a dedicated Subtask detail page (title, done toggle synced with the parent, assignee, due, "Part of" link, notes). | screenshot |
| 13 | Notes section parity | Shared `NotesThread` (reply threads + photo/file attachments, simulated) adopted across all modules; migrated off the old per-module note models. | screenshot |
| 14 | Contextual add | Bottom-nav `+` runs the current screen's registered `AddAction` (`contextual_add_provider.dart`); each list opens the matching add form/sheet, with a location-aware route fallback. | code |

## Notes / follow-ups
- Attachments (#13) are simulated (mock chips) — swap `NotesThread._addMockAttachment` for a real `image_picker`/`file_picker` + upload at API time.
- `SavedChipRow` currently lives under `features/crm/…` and is imported cross-feature by Helpdesk/Ops/People. It works and analyzes clean; a tidy-up would relocate it to `core/widgets`.
- Add sheets that lack a mutating mock store (People invite/team/role) show the design's success toast without persisting — they insert once repositories are writable.
