/// Path builders for every backend resource.
///
/// Paths are relative — the host and version prefix come from
/// `Env.current.apiBaseUrl`, so nothing here needs to change between
/// dev / staging / prod.
///
/// PROVISIONAL: these mirror the modules that already have repositories in
/// `lib/features/`. Reconcile each one against the backend contract before the
/// integration PR lands.
// TODO(clozr): confirm paths against the API spec 2026-07-28
class Endpoints {
  const Endpoints._();

  // ── Resource roots ──
  static const String _leads = '/leads';
  static const String _customers = '/customers';
  static const String _followups = '/followups';
  static const String _crmTasks = '/crm/tasks';
  static const String _quotes = '/quotes';
  static const String _payments = '/payments';
  static const String _invoices = '/invoices';
  static const String _products = '/products';
  static const String _tickets = '/tickets';
  static const String _projects = '/projects';
  static const String _opsTasks = '/ops/tasks';
  static const String _members = '/members';
  static const String _teams = '/teams';
  static const String _roles = '/roles';
  static const String _courses = '/courses';
  static const String _learners = '/learners';
  static const String _conversations = '/conversations';
  static const String _notifications = '/notifications';
  static const String _dashboard = '/dashboard';
  static const String _rewards = '/rewards';

  // ── CRM ──

  /// Collection of leads.
  static String leads() => _leads;

  /// A single lead.
  static String leadById(String id) => '$_leads/$id';

  /// Collection of customers.
  static String customers() => _customers;

  /// A single customer.
  static String customerById(String id) => '$_customers/$id';

  /// Collection of follow-ups.
  static String followups() => _followups;

  /// A single follow-up.
  static String followupById(String id) => '$_followups/$id';

  /// Collection of CRM tasks.
  static String crmTasks() => _crmTasks;

  /// A single CRM task.
  static String crmTaskById(String id) => '$_crmTasks/$id';

  /// Collection of quotes.
  static String quotes() => _quotes;

  /// A single quote.
  static String quoteById(String id) => '$_quotes/$id';

  /// Collection of payments.
  static String payments() => _payments;

  /// A single payment.
  static String paymentById(String id) => '$_payments/$id';

  /// Collection of invoices.
  static String invoices() => _invoices;

  /// A single invoice.
  static String invoiceById(String id) => '$_invoices/$id';

  /// Collection of products.
  static String products() => _products;

  /// A single product.
  static String productById(String id) => '$_products/$id';

  // ── Helpdesk ──

  /// Collection of tickets.
  static String tickets() => _tickets;

  /// A single ticket.
  static String ticketById(String id) => '$_tickets/$id';

  // ── Operations ──

  /// Collection of projects.
  static String projects() => _projects;

  /// A single project.
  static String projectById(String id) => '$_projects/$id';

  /// Collection of operations tasks.
  static String opsTasks() => _opsTasks;

  /// A single operations task.
  static String opsTaskById(String id) => '$_opsTasks/$id';

  // ── People ──

  /// Collection of workspace members.
  static String members() => _members;

  /// A single member.
  static String memberById(String id) => '$_members/$id';

  /// Collection of teams.
  static String teams() => _teams;

  /// Collection of roles.
  static String roles() => _roles;

  // ── Training (LMS) ──

  /// Collection of courses.
  static String courses() => _courses;

  /// A single course.
  static String courseById(String id) => '$_courses/$id';

  /// Collection of learner records.
  static String learners() => _learners;

  /// A single learner record.
  static String learnerById(String id) => '$_learners/$id';

  // ── Cross-cutting ──

  /// Collection of conversations.
  static String conversations() => _conversations;

  /// Messages inside a conversation.
  static String messagesFor(String conversationId) =>
      '$_conversations/$conversationId/messages';

  /// Collection of notifications.
  static String notifications() => _notifications;

  /// Marks a notification read.
  static String notificationRead(String id) => '$_notifications/$id/read';

  /// Aggregated dashboard payload.
  static String dashboard() => _dashboard;

  /// Rewards and goal progress.
  static String rewards() => _rewards;
}
