import '../../core/storage/hive/boxes.dart';
import '../../core/utils/logger.dart';

/// The one place boxes and adapters are registered.
///
/// Keeping this centralised means startup and logout can never drift out of
/// sync with the box list — both derive from [HiveBoxes].
///
/// NOT WIRED YET: `hive` and `hive_flutter` are listed in
/// docs-flutter/Technical_stack.md but are not dependencies, so the methods
/// below log and return. `bootstrap()` does not call them. Implement all three
/// together when the caching layer lands.
// TODO(clozr): implement once hive_flutter is a dependency 2026-07-28
class HiveInit {
  const HiveInit._();

  /// Boxes opened during startup, in order.
  static const List<String> startupBoxes = HiveBoxes.all;

  /// Registers every adapter and opens [startupBoxes].
  ///
  /// Adapters must be registered before any box is opened, otherwise reads
  /// fail at runtime (QA.md security audit item 17). Take type ids from
  /// `HiveTypeIds` — never inline a literal.
  static Future<void> initialiseAsync() async {
    try {
      // Implementation outline, pending the hive dependency:
      //   await Hive.initFlutter();
      //   Hive.registerAdapter(LeadAdapter());   // typeId: HiveTypeIds.lead
      //   for (final name in startupBoxes) { await Hive.openBox<dynamic>(name); }
      AppLogger.warning(
        'HiveInit.initialiseAsync() is a no-op — hive_flutter is not a '
        'dependency yet. ${startupBoxes.length} boxes pending.',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Hive initialisation failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Clears every box listed in [HiveBoxes.clearedOnLogout].
  ///
  /// Call from the logout flow, alongside wiping `SecureStore`
  /// (QA.md security audit items 8 and 19). [HiveBoxes.settingsBox] survives
  /// so non-sensitive preferences persist across accounts.
  static Future<void> clearOnLogoutAsync() async {
    try {
      // Implementation outline, pending the hive dependency:
      //   for (final name in HiveBoxes.clearedOnLogout) {
      //     await Hive.box<dynamic>(name).clear();
      //   }
      AppLogger.warning(
        'HiveInit.clearOnLogoutAsync() is a no-op — hive_flutter is not a '
        'dependency yet. ${HiveBoxes.clearedOnLogout.length} boxes pending.',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Hive logout wipe failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
