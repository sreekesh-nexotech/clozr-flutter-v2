/// Central route table. Path constants + per-route chrome metadata used by the
/// shell to decide which bottom nav (if any) to render.
///
/// Keep this in sync with `app_router.dart`. Nothing else in the app should
/// hardcode a path string.
library;

enum NavContext { crm, ops, help, dash, none }

class RouteMeta {
  final NavContext nav;
  final bool showNav;
  const RouteMeta(this.nav, this.showNav);
}

class Routes {
  Routes._();

  // Auth (outside the shell — no status bar / bottom nav chrome)
  static const splash = '/splash';
  static const login = '/login';

  // CRM
  static const home = '/home';
  static const leads = '/leads';
  static const leadDetail = '/leads/detail';
  static const addLead = '/leads/add';
  static const customers = '/customers';
  static const customerDetail = '/customers/detail';
  static const followups = '/followups';
  static const followupDetail = '/followups/detail';
  static const editFollowup = '/followups/edit';
  static const tasks = '/tasks';
  static const taskDetail = '/tasks/detail';
  static const editCrmTask = '/tasks/edit';
  static const addCrmTask = '/tasks/add';
  static const quotes = '/quotes';
  static const quoteDetail = '/quotes/detail';
  static const addQuote = '/quotes/add';
  static const payments = '/payments';
  static const paymentDetail = '/payments/detail';
  static const invoiceDetail = '/invoices/detail';
  static const products = '/products';
  static const productDetail = '/products/detail';
  static const billing = '/billing';
  static const reports = '/reports';

  // Operations
  static const opsHome = '/ops/home';
  static const opsProjects = '/ops/projects';
  static const projectDetail = '/ops/projects/detail';
  static const createProject = '/ops/projects/create';
  static const editProject = '/ops/projects/edit';
  static const opsTasks = '/ops/tasks';
  static const opsTaskDetail = '/ops/tasks/detail';
  static const opsSubtask = '/ops/tasks/subtask';
  static const createTask = '/ops/tasks/create';
  static const editTask = '/ops/tasks/edit';

  // Helpdesk
  static const helpHome = '/help/home';
  static const tickets = '/help/tickets';
  static const ticketDetail = '/help/tickets/detail';
  static const createTicket = '/help/tickets/create';
  static const editTicket = '/help/tickets/edit';
  static const helpBoards = '/help/boards';

  // Training
  static const lmsOverview = '/training/overview';
  static const lmsCourses = '/training/courses';
  static const lmsCourseDetail = '/training/courses/detail';
  static const lmsBuilder = '/training/builder';
  static const lmsLearners = '/training/learners';
  static const lmsLearnerDetail = '/training/learners/detail';
  static const lmsMy = '/training/my';
  static const lmsPlayer = '/training/player';

  // Cross-cutting
  static const dashboard = '/dashboard';
  static const notifications = '/notifications';
  static const rewards = '/rewards';
  static const members = '/members';
  static const memberDetail = '/members/detail';
  static const teams = '/teams';
  static const roles = '/roles';
  static const messages = '/messages';
  static const chat = '/chat';

  /// Chrome metadata per path.
  static const Map<String, RouteMeta> meta = {
    home: RouteMeta(NavContext.crm, true),
    leads: RouteMeta(NavContext.crm, true),
    leadDetail: RouteMeta(NavContext.crm, false),
    addLead: RouteMeta(NavContext.crm, false),
    customers: RouteMeta(NavContext.crm, true),
    customerDetail: RouteMeta(NavContext.crm, false),
    followups: RouteMeta(NavContext.crm, true),
    followupDetail: RouteMeta(NavContext.crm, false),
    editFollowup: RouteMeta(NavContext.crm, false),
    tasks: RouteMeta(NavContext.crm, true),
    taskDetail: RouteMeta(NavContext.crm, false),
    editCrmTask: RouteMeta(NavContext.crm, false),
    addCrmTask: RouteMeta(NavContext.crm, false),
    quotes: RouteMeta(NavContext.crm, true),
    quoteDetail: RouteMeta(NavContext.crm, false),
    addQuote: RouteMeta(NavContext.crm, false),
    payments: RouteMeta(NavContext.crm, true),
    paymentDetail: RouteMeta(NavContext.crm, false),
    invoiceDetail: RouteMeta(NavContext.crm, false),
    products: RouteMeta(NavContext.crm, true),
    productDetail: RouteMeta(NavContext.crm, false),
    billing: RouteMeta(NavContext.crm, true),
    reports: RouteMeta(NavContext.crm, false),
    opsHome: RouteMeta(NavContext.ops, true),
    opsProjects: RouteMeta(NavContext.ops, true),
    projectDetail: RouteMeta(NavContext.ops, false),
    createProject: RouteMeta(NavContext.ops, false),
    editProject: RouteMeta(NavContext.ops, false),
    opsTasks: RouteMeta(NavContext.ops, true),
    opsTaskDetail: RouteMeta(NavContext.ops, false),
    opsSubtask: RouteMeta(NavContext.ops, false),
    createTask: RouteMeta(NavContext.ops, false),
    editTask: RouteMeta(NavContext.ops, false),
    helpHome: RouteMeta(NavContext.help, true),
    tickets: RouteMeta(NavContext.help, true),
    ticketDetail: RouteMeta(NavContext.help, false),
    createTicket: RouteMeta(NavContext.help, false),
    editTicket: RouteMeta(NavContext.help, false),
    helpBoards: RouteMeta(NavContext.help, true),
    lmsOverview: RouteMeta(NavContext.crm, false),
    lmsCourses: RouteMeta(NavContext.crm, false),
    lmsCourseDetail: RouteMeta(NavContext.crm, false),
    lmsBuilder: RouteMeta(NavContext.crm, false),
    lmsLearners: RouteMeta(NavContext.crm, false),
    lmsLearnerDetail: RouteMeta(NavContext.crm, false),
    lmsMy: RouteMeta(NavContext.crm, false),
    lmsPlayer: RouteMeta(NavContext.crm, false),
    dashboard: RouteMeta(NavContext.dash, true),
    notifications: RouteMeta(NavContext.crm, false),
    rewards: RouteMeta(NavContext.crm, false),
    members: RouteMeta(NavContext.crm, false),
    memberDetail: RouteMeta(NavContext.crm, false),
    teams: RouteMeta(NavContext.crm, false),
    roles: RouteMeta(NavContext.crm, false),
    messages: RouteMeta(NavContext.crm, false),
    chat: RouteMeta(NavContext.crm, false),
  };

  static RouteMeta metaFor(String location) {
    // Strip query string.
    final path = location.split('?').first;
    return meta[path] ?? const RouteMeta(NavContext.crm, false);
  }
}
