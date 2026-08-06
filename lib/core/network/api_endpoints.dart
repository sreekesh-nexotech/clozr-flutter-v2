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
  static const leadStatuses = '/crm/lead-statuses/';
  static const leadSources = '/crm/lead-sources/';
  static const industries = '/crm/industries/';
  static const territories = '/crm/territories/';

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
  static const paymentRecords = '/quotations/payment-records/';
  static String paymentRecord(String id) => '/quotations/payment-records/$id/';

  // ── Billing (subscription invoices) ──
  static const billingInvoices = '/billing/invoices/';

  // ── Projects / operations ──
  static const projects = '/projects/projects/';
  static String project(String id) => '/projects/projects/$id/';
  static const projectStatusCounts = '/projects/projects/status-counts/';
  static const projectStatuses = '/projects/project-statuses/';
  static const projectTasks = '/projects/tasks/';
  static String projectTask(String id) => '/projects/tasks/$id/';
  static const projectTaskStatusCounts = '/projects/tasks/status-counts/';
  static const projectTaskStatuses = '/projects/project-task-statuses/';
  static const taskGroups = '/projects/task-groups/';

  // ── Helpdesk (issues) ──
  static const issues = '/crm/issues/';
  static String issue(String id) => '/crm/issues/$id/';
  static const issueStatuses = '/crm/issue-statuses/';
  static const issueTypes = '/crm/issue-types/';
  static String issueReplies(String id) => '/crm/issues/$id/replies/';

  // ── Management: members / roles / teams ──
  static const users = '/management/users/';
  static String user(String id) => '/management/users/$id/';
  static String userActivity(String id) => '/management/users/$id/activity/';
  static const roles = '/management/roles/';
  static String role(String id) => '/management/roles/$id/';
  static const teams = '/management/teams/';
  static String team(String id) => '/management/teams/$id/';
  static String teamMembers(String teamId) =>
      '/management/teams/$teamId/members/';
  static const allTeamMembers = '/management/teams/members/';

  // ── Dashboards ──
  static const dashboardNew = '/crm/dashboard-new';
  static const dashboardCrm = '/crm/dashboard-crm';
  static const dashboardPmo = '/crm/dashboard-pmo';
  static const dashboardIssue = '/crm/dashboard-issue';
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
