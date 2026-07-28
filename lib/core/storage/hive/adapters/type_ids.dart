/// The central registry of Hive `typeId`s.
///
/// `HiveTypeAdapterIdRule` requires every `@HiveType` to carry a unique,
/// sequentially allocated `typeId`. Duplicates are not a compile error — they
/// corrupt reads at runtime — so every adapter in this folder must take its id
/// from here and never inline a literal.
///
/// Rules:
///  * Allocate the next free number; never reuse one, even after deleting a
///    model. Reusing an id makes old on-disk data deserialise into the wrong
///    class.
///  * Keep [nextAvailable] accurate when you add an entry.
///
/// Usage: `@HiveType(typeId: HiveTypeIds.lead)`.
// TODO(clozr): add the generated adapters here once hive is a dependency 2026-07-28
class HiveTypeIds {
  const HiveTypeIds._();

  /// Workspace member / rep.
  static const int appUser = 0;

  /// CRM lead.
  static const int lead = 1;

  /// CRM customer.
  static const int customer = 2;

  /// CRM follow-up.
  static const int followup = 3;

  /// CRM task.
  static const int crmTask = 4;

  /// CRM quote.
  static const int quote = 5;

  /// CRM payment.
  static const int payment = 6;

  /// CRM invoice.
  static const int invoice = 7;

  /// CRM product.
  static const int product = 8;

  /// Helpdesk ticket.
  static const int ticket = 9;

  /// Operations project.
  static const int project = 10;

  /// Operations task.
  static const int opsTask = 11;

  /// People module team.
  static const int team = 12;

  /// People module role.
  static const int role = 13;

  /// LMS course.
  static const int course = 14;

  /// LMS learner record.
  static const int learnerRecord = 15;

  /// LMS activity entry.
  static const int lmsActivity = 16;

  /// Messages conversation.
  static const int conversation = 17;

  /// In-app notification.
  static const int appNotification = 18;

  /// Rewards entry.
  static const int reward = 19;

  /// The next id to hand out. Bump this whenever you add a model above.
  static const int nextAvailable = 20;
}
