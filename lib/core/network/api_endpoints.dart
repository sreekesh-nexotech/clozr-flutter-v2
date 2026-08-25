/// Every backend route the app calls, in one place. Paths are relative to
/// `ApiConfig.baseUrl + ApiConfig.apiPrefix` (`/api/v1`). Detail routes use the
/// model's UUID field (`lead_id`, `task_id`, …), never the integer pk.
class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth (accounts app) ──
  static const login = '/auth/login/';
  static const loginRefresh = '/auth/login/refresh/';
  static const login2fa = '/auth/login/2fa/';
  static const login2faEnrolStart = '/auth/login/2fa/enrol/start/';
  static const login2faEnrolConfirm = '/auth/login/2fa/enrol/confirm/';
  static const logout = '/auth/logout/';
  static const me = '/auth/me/';
  static const myModules = '/auth/me/modules/';
  static const passwordReset = '/auth/password-reset/';
  static const passwordResetConfirm = '/auth/password-reset/confirm/';

  // ── CRM: leads ──
  static const leads = '/crm/leads/';
  static String lead(String id) => '/crm/leads/$id/';
  static const leadSchema = '/crm/leads/schema/';
  static const leadBoard = '/crm/leads/board/';
  static String leadConvert(String id) => '/crm/leads/$id/convert/';
  static String leadAssignableUsers(String id) =>
      '/crm/leads/$id/assignable-users/';
  static const leadStatuses = '/crm/lead-statuses/';
  static const leadSources = '/crm/lead-sources/';
  static const industries = '/crm/industries/';
  static const territories = '/crm/territories/';

  // ── CRM: Exotel telephony (click-to-call) ──
  static const exotelStatus = '/crm/exotel/status/';
  static const exotelCall = '/crm/exotel/call/';

  // ── CRM: saved filters (the saved-view chips above a list) ──
  static const savedFilters = '/crm/saved-filters/';
  static String savedFilter(String id) => '/crm/saved-filters/$id/';

  // ── CRM: customers ──
  static const customers = '/crm/customers/';
  static String customer(String id) => '/crm/customers/$id/';
  static const customerSchema = '/crm/customers/schema/';
  static const customerStatuses = '/crm/customer-statuses/';
  static String customerUpsell(String id) => '/crm/customers/$id/upsell/';

  // ── CRM: tasks & follow-ups (follow-up = task with is_followup=true) ──
  static const crmTasks = '/crm/tasks/';
  static String crmTask(String id) => '/crm/tasks/$id/';
  static const crmTaskSchema = '/crm/tasks/schema/';
  static const crmTaskStatuses = '/crm/crm-task-statuses/';
  static const taskPriorities = '/crm/task-priorities/';
  static const followUpTypes = '/crm/follow-up-types/';

  // ── CRM: call logs (telephony activity on a lead / customer) ──
  static const callLogs = '/crm/call-logs/';
  static String callLog(String id) => '/crm/call-logs/$id/';

  // ── CRM: notes / attachments / products ──
  static const notes = '/crm/notes/';
  static String note(String id) => '/crm/notes/$id/';
  static String noteReplies(String id) => '/crm/notes/$id/replies/';
  static const noteTypes = '/crm/note-types/';
  static const attachments = '/crm/attachments/';
  static String attachment(String id) => '/crm/attachments/$id/';
  static const products = '/crm/products/';
  static String product(String id) => '/crm/products/$id/';

  /// The org's own product categories — `product_type_id` + `type_name`. The
  /// category chips on the Products list read this, not a built-in list.
  static const productTypes = '/crm/product-types/';

  /// The org's Product layout (`org-view-settings-api.md` — `model_name:
  /// product`, list/detail/mobile; there is no kanban for this module).
  static const productSchema = '/crm/products/schema/';

  // ── CRM: notifications feed ──
  static const notifications = '/crm/notifications/';
  static String notification(String id) => '/crm/notifications/$id/';
  static const notificationsMarkAllRead = '/crm/notifications/mark-all-read/';
  static String notificationMarkRead(String id) =>
      '/crm/notifications/$id/mark-read/';

  // ── Quotations / payments ──
  static const quotations = '/quotations/quotations/';
  static String quotation(String id) => '/quotations/quotations/$id/';
  static const quotationSchema = '/quotations/quotations/schema/';
  static const quotationTemplates = '/quotations/templates/';
  static const quotationStatuses = '/quotations/statuses/';
  static const payments = '/quotations/payments/';
  static String payment(String id) => '/quotations/payments/$id/';

  /// Server-computed totals for one invoice: paid / remaining, the next due
  /// date, and the record counts by state
  /// (`quotation-schema-and-list-view-api.md` §2b).
  static String paymentSummary(String id) =>
      '/quotations/payments/$id/summary/';
  /// The org's Payment layout. `model_name: payment` in the view-settings engine
  /// is this collection — the invoice header — not `payment-records/`.
  static const paymentSchema = '/quotations/payments/schema/';
  static const paymentRecords = '/quotations/payment-records/';
  static String paymentRecord(String id) => '/quotations/payment-records/$id/';

  // ── Billing (subscription invoices) ──
  static const billingInvoices = '/billing/invoices/';

  // ── Projects / operations ──
  static const projects = '/projects/projects/';
  static String project(String id) => '/projects/projects/$id/';

  /// Archive **or restore** one project — `{"is_archive": true|false}`.
  /// A toggle, not a one-way action (`operations.md` §8).
  static String projectArchive(String id) =>
      '/projects/projects/$id/archive/';
  static const projectStatusCounts = '/projects/projects/status-counts/';
  static const projectStatuses = '/projects/project-statuses/';
  /// The Type facet on the projects drawer (`operations.md` §4).
  static const projectTypes = '/projects/project-types/';
  static const projectTasks = '/projects/tasks/';
  static String projectTask(String id) => '/projects/tasks/$id/';

  /// One task's own activity feed (`operations-task.md` §3B).
  ///
  /// Not the org-wide `/access-control/audit-logs/`: this one is gated by
  /// `view_task`, so a PM without `view_audit_log` still reads the history of a
  /// task they can already see. Rows arrive pre-humanized (`summary` +
  /// `event_type`) rather than as raw diffs.
  static String projectTaskActivity(String id) => '/projects/tasks/$id/activity/';
  static const projectTaskStatusCounts = '/projects/tasks/status-counts/';
  static const projectTaskStatuses = '/projects/project-task-statuses/';
  static const taskGroups = '/projects/task-groups/';
  /// The project Files tab (`operations.md` §15).
  static const projectAttachments = '/projects/project-attachments/';

  /// Dependency edges. Reads come inline on the task detail; this collection is
  /// for adding and removing them (`operations-task.md` §3D).
  static const taskDependencies = '/projects/task-dependencies/';
  static String taskDependency(String edgeId) =>
      '/projects/task-dependencies/$edgeId/';

  // ── Helpdesk (issues) ──
  static const issues = '/crm/issues/';
  static String issue(String id) => '/crm/issues/$id/';
  static const issueStatuses = '/crm/issue-statuses/';

  /// Per-status tab counts for the tickets list, under the same filters
  /// (`issue-filters.md`). Verified against the dev backend.
  static const issueStatusCounts = '/crm/issues/status-counts/';

  /// Support Overview — stats strip, SLA watch, workload and pipeline
  /// (`helpdesk.md` §7). Takes the same filters as the list.
  static const issueSummary = '/crm/issues/summary/';
  static const issueTypes = '/crm/issue-types/';
  static String issueReplies(String id) => '/crm/issues/$id/replies/';

  /// One ticket's own activity feed (`helpdesk.md` §10) — gated by `view_issue`
  /// rather than `view_audit_log`, unlike the org-wide audit trail.
  static String issueActivity(String id) => '/crm/issues/$id/activity/';

  /// The Operations tasks raised from one ticket (§10).
  static String issueTasks(String id) => '/crm/issues/$id/tasks/';

  // ── Access control: the audit trail behind every record's activity log ──
  static const auditLogs = '/access-control/audit-logs/';

  // ── Management: members / roles / teams ──
  static const users = '/management/users/';
  static String user(String id) => '/management/users/$id/';
  static String userActivity(String id) => '/management/users/$id/activity/';
  static const roles = '/management/roles/';
  static String role(String id) => '/management/roles/$id/';

  /// The grantable business-module cards and visibility scopes the Add/Edit
  /// role form offers (`roles.md` §1). Static and org-agnostic — a code
  /// registry, not org config.
  static const moduleCatalog = '/management/permissions/module-catalog/';
  static const teams = '/management/teams/';
  static String team(String id) => '/management/teams/$id/';
  static String teamMembers(String teamId) =>
      '/management/teams/$teamId/members/';
  static const allTeamMembers = '/management/teams/members/';

  // ── Dashboards ──
  static const dashboardNew = '/crm/dashboard-new';
  static const dashboardCrm = '/crm/dashboard-crm';
  static const dashboardPmo = '/crm/dashboard-pmo';

  /// The PMO KPI card figures (`admin_operations_dashboard.md` §1). Called with
  /// `scope=own` by the Operations home, which is the caller's own data — only
  /// `scope=admin` needs an org-admin role.
  static const dashboardPmoKpis = '/crm/dashboard-pmo/kpis/';

  /// Completed tasks split by priority and by whether they landed before or
  /// after their due date. Verified against the dev backend:
  /// `{"rows":[{"priority","before_due","after_due"}]}`.
  static const dashboardPmoCompletedGrid =
      '/crm/dashboard-pmo/tasks-completed-grid/';
  static const dashboardIssue = '/crm/dashboard-issue';

  /// The Helpdesk KPI card figures. Called with `scope=own` by the Helpdesk
  /// home — the caller's own tickets.
  static const dashboardIssueKpis = '/crm/dashboard-issue/kpis/';

  /// The Helpdesk home's SLA/priority donuts and resolved grid
  /// (`admin_helpdesk_dashboard.md` §3, §9) — both were computed on the device
  /// from the loaded ticket page before.
  static const dashboardIssueSlaPriorityMix =
      '/crm/dashboard-issue/sla-priority-mix/';
  static const dashboardIssueCompletedGrid =
      '/crm/dashboard-issue/tickets-completed-grid/';
  static const memberPerformance = '/crm/dashboard-crm/member-performance/';

  // ── Notification preferences ──
  static const myNotificationPrefsMatrix =
      '/crm/my-notification-preferences/matrix/';

  // ── LMS / training ──
  static const myCourses = '/lms/my-courses/';
  static String myCourse(String enrollmentId) => '/lms/my-courses/$enrollmentId/';

  // ── Rewards / milestones ──
  static const milestoneProgress = '/milestones/progress/';
  static const milestoneRewards = '/milestones/rewards/';

  // ── WhatsApp messages ──
  static const whatsappConversations = '/whatsapp/conversations/';
  static String whatsappConversation(Object conversationId) =>
      '/whatsapp/conversations/$conversationId/';
  static String whatsappMessages(Object conversationId) =>
      '/whatsapp/conversations/$conversationId/messages/';
  static String whatsappConversationRead(Object conversationId) =>
      '/whatsapp/conversations/$conversationId/read/';
  static const whatsappSendText = '/whatsapp/send/text/';
  static const whatsappSendTemplate = '/whatsapp/send/template/';
  static const whatsappTemplates = '/whatsapp/templates/';
  static const whatsappBadge = '/whatsapp/badge/';
}
