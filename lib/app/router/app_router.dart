import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/auth/module_access_gate.dart';
import '../../features/auth/presentation/components/module_guard.dart';
import '../../core/auth/session_gate.dart';
import '../../core/config/api_config.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/shell/domain/nav_catalog.dart';
import '../../features/shell/presentation/clozr_shell.dart';
import 'routes.dart';

// CRM
import '../../features/crm/presentation/screens/crm_home_screen.dart';
import '../../features/crm/presentation/screens/leads_screen.dart';
import '../../features/crm/presentation/screens/lead_detail_screen.dart';
import '../../features/crm/presentation/screens/add_lead_screen.dart';
import '../../features/crm/presentation/screens/customers_screen.dart';
import '../../features/crm/presentation/screens/customer_detail_screen.dart';
import '../../features/crm/presentation/screens/edit_customer_screen.dart';
import '../../features/crm/presentation/screens/followups_screen.dart';
import '../../features/crm/presentation/screens/followup_detail_screen.dart';
import '../../features/crm/presentation/screens/tasks_screen.dart';
import '../../features/crm/presentation/screens/due_date_approvals_screen.dart';
import '../../features/crm/presentation/screens/edit_crm_task_screen.dart';
import '../../features/crm/presentation/screens/task_detail_screen.dart';
import '../../features/crm/presentation/screens/quotes_screen.dart';
import '../../features/crm/presentation/screens/quote_detail_screen.dart';
import '../../features/crm/presentation/screens/add_quote_screen.dart';
import '../../features/crm/presentation/screens/quote_approvals_screen.dart';
import '../../features/crm/presentation/screens/quote_win_loss_screen.dart';
import '../../features/crm/presentation/screens/payments_screen.dart';
import '../../features/crm/presentation/screens/payment_detail_screen.dart';
import '../../features/crm/presentation/screens/invoice_detail_screen.dart';
import '../../features/crm/presentation/screens/products_screen.dart';
import '../../features/crm/presentation/screens/product_detail_screen.dart';
import '../../features/crm/presentation/screens/billing_screen.dart';
import '../../features/crm/presentation/screens/reports_screen.dart';
// Operations
import '../../features/operations/presentation/screens/ops_home_screen.dart';
import '../../features/operations/presentation/screens/projects_screen.dart';
import '../../features/operations/presentation/screens/project_detail_screen.dart';
import '../../features/operations/presentation/screens/create_project_screen.dart';
import '../../features/operations/presentation/screens/edit_project_screen.dart';
import '../../features/operations/presentation/screens/ops_tasks_screen.dart';
import '../../features/operations/presentation/screens/ops_task_detail_screen.dart';
import '../../features/operations/presentation/screens/subtask_detail_screen.dart';
import '../../features/operations/presentation/screens/create_task_screen.dart';
import '../../features/operations/presentation/screens/edit_task_screen.dart';
// Helpdesk
import '../../features/helpdesk/presentation/screens/help_home_screen.dart';
import '../../features/helpdesk/presentation/screens/tickets_screen.dart';
import '../../features/helpdesk/presentation/screens/ticket_detail_screen.dart';
import '../../features/helpdesk/presentation/screens/create_ticket_screen.dart';
import '../../features/helpdesk/presentation/screens/edit_ticket_screen.dart';
import '../../features/helpdesk/presentation/screens/boards_screen.dart';
// Training
import '../../features/training/presentation/screens/lms_overview_screen.dart';
import '../../features/training/presentation/screens/lms_courses_screen.dart';
import '../../features/training/presentation/screens/lms_course_detail_screen.dart';
import '../../features/training/presentation/screens/lms_builder_screen.dart';
import '../../features/training/presentation/screens/lms_learners_screen.dart';
import '../../features/training/presentation/screens/lms_learner_detail_screen.dart';
import '../../features/training/presentation/screens/lms_my_courses_screen.dart';
import '../../features/training/presentation/screens/lms_player_screen.dart';
// Cross-cutting
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/rewards/presentation/screens/rewards_screen.dart';
import '../../features/people/presentation/screens/members_screen.dart';
import '../../features/people/presentation/screens/member_detail_screen.dart';
import '../../features/people/presentation/screens/teams_screen.dart';
import '../../features/people/presentation/screens/roles_screen.dart';
import '../../features/messages/presentation/screens/messages_screen.dart';
import '../../features/messages/presentation/screens/chat_screen.dart';
// Accounting
import '../../features/accounting/presentation/screens/acc_document_detail_screen.dart';
import '../../features/accounting/presentation/screens/acc_document_print_screen.dart';
import '../../features/accounting/presentation/screens/acc_home_screen.dart';
import '../../features/accounting/presentation/screens/acc_invoices_screen.dart';
import '../../features/accounting/presentation/screens/acc_money_screen.dart';
import '../../features/accounting/presentation/screens/acc_purchases_screen.dart';
import '../../features/accounting/presentation/screens/acc_vendor_detail_screen.dart';
import '../../features/accounting/presentation/screens/acc_vendors_screen.dart';
import '../../features/accounting/presentation/screens/acc_new_invoice_screen.dart';
import '../../features/accounting/presentation/screens/acc_periods_screen.dart';
import '../../features/accounting/presentation/screens/acc_report_screen.dart';
import '../../features/accounting/presentation/screens/acc_reports_screen.dart';
import '../../features/accounting/presentation/screens/acc_status_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// Builds a route whose page has no transition animation. Tab switches inside
/// the shell should feel instant, like the prototype's screen swaps.
///
/// `name` is what Sentry reads off `RouteSettings` for its navigation
/// breadcrumbs and screen transactions — without it these pages report as
/// `unknown`. Routes built from [_push] get it for free (GoRouter names the
/// pages it wraps itself); the ones built here supply their own page, so they
/// have to pass it.
GoRoute _r(String path, Widget child) => GoRoute(
      path: path,
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, name: path, child: child),
    );

/// Builds a route with the default push transition (for detail/create/edit
/// screens that are pushed on top and popped back).
GoRoute _push(String path, Widget child) => GoRoute(
      path: path,
      builder: (context, state) => child,
    );

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.dashboard,
  // Navigation breadcrumbs, so a crash report shows the path the user took to
  // reach it. Screen-load *transactions* are left to the shell navigator's
  // observer below: the ShellRoute is pushed once and stays for the whole
  // session, so timing it here would produce one transaction per session
  // instead of one per screen.
  observers: [SentryNavigatorObserver(enableAutoTransactions: false)],
  // Auth gate — active only when a backend is configured. Mock mode keeps the
  // original boot-straight-into-the-shell behavior. Merged with
  // [ModuleAccessGate] so the redirect below re-runs the moment the signed-in
  // user's role is actually known, not just on auth transitions.
  refreshListenable: Listenable.merge([SessionGate.instance, ModuleAccessGate.instance]),
  redirect: (context, state) {
    if (!ApiConfig.apiEnabled) return null;
    final status = SessionGate.instance.status;
    final loc = state.matchedLocation;
    // While restoring the saved session, hold on the splash — don't flash the
    // login screen at a returning user, and don't render an authed screen that
    // would fire 401s before we know the session state.
    if (status == SessionStatus.restoring) {
      return loc == Routes.splash ? null : Routes.splash;
    }
    final loggedIn = status == SessionStatus.authenticated;
    final atAuthRoute = loc == Routes.login || loc == Routes.splash;
    if (!loggedIn) return loc == Routes.login ? null : Routes.login;

    // A signed-in user lands on the Dashboard — but only a role that can
    // actually see it. [landingPathFor] falls back to Dashboard itself while
    // the role is still loading (`!gate.loaded`), so this is a no-op until
    // the real answer is in.
    final gate = ModuleAccessGate.instance;
    final landing = gate.loaded ? landingPathFor(gate.access) : Routes.dashboard;
    if (atAuthRoute) return landing;
    // Self-correct even off the auth route: someone parked on Dashboard while
    // their role was still resolving is moved the instant it resolves, rather
    // than waiting for their next manual navigation (or worse, staying put
    // long enough for the screen's own fetch to 403).
    if (loc == Routes.dashboard && gate.loaded && landing != Routes.dashboard) {
      return landing;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: Routes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => ClozrShell(child: child),
      // Every screen behind the login gate lives on this navigator, so this is
      // the observer that measures screen loads.
      observers: [SentryNavigatorObserver()],
      routes: [
        // CRM — each module's screens sit behind the webapp's ModuleGuard, so a
        // role without the module gets the lock panel instead of a 403.
        _r(Routes.home, const CrmHomeScreen()),
        _r(Routes.leads, const ModuleGuard(module: 'lead', child: LeadsScreen())),
        _push(Routes.leadDetail, const ModuleGuard(module: 'lead', child: LeadDetailScreen())),
        _push(Routes.addLead, const ModuleGuard(module: 'lead', child: AddLeadScreen())),
        _r(Routes.customers, const ModuleGuard(module: 'customer', child: CustomersScreen())),
        _push(Routes.customerDetail, const ModuleGuard(module: 'customer', child: CustomerDetailScreen())),
        _push(Routes.editCustomer, const ModuleGuard(module: 'customer', child: EditCustomerScreen())),
        _r(Routes.followups, const ModuleGuard(module: 'followup', child: FollowupsScreen())),
        _push(Routes.followupDetail, const ModuleGuard(module: 'followup', child: FollowupDetailScreen())),
        // A follow-up is a Task with `is_followup=true`, so the Task edit form
        // serves both — only the schema and the labels differ.
        _push(Routes.editFollowup, const ModuleGuard(module: 'followup', child: EditCrmTaskScreen(isFollowup: true))),
        _r(Routes.tasks, const ModuleGuard(module: 'task', child: TasksScreen())),
        _push(Routes.taskDetail, const ModuleGuard(module: 'task', child: TaskDetailScreen())),
        _push(Routes.editCrmTask, const ModuleGuard(module: 'task', child: EditCrmTaskScreen())),
        // Same schema-driven form, with no `?id=` — which is what puts it in
        // create mode.
        _push(Routes.addCrmTask, const ModuleGuard(module: 'task', child: EditCrmTaskScreen())),
        // Webapp: no module guard — the server scopes the rows.
        _push(Routes.dueDateApprovals, const DueDateApprovalsScreen()),
        _r(Routes.quotes, const ModuleGuard(module: 'quotation', child: QuotesScreen())),
        _push(Routes.quoteDetail, const ModuleGuard(module: 'quotation', child: QuoteDetailScreen())),
        _push(Routes.addQuote, const ModuleGuard(module: 'quotation', child: AddQuoteScreen())),
        _push(Routes.editQuote, const ModuleGuard(module: 'quotation', child: AddQuoteScreen())),
        _push(Routes.quoteApprovals, const ModuleGuard(module: 'quotation', child: QuoteApprovalsScreen())),
        _push(Routes.quoteWinLoss, const ModuleGuard(module: 'quotation', child: QuoteWinLossScreen())),
        _r(Routes.payments, const ModuleGuard(module: 'payment', child: PaymentsScreen())),
        _push(Routes.paymentDetail, const ModuleGuard(module: 'payment', child: PaymentDetailScreen())),
        _push(Routes.invoiceDetail, const ModuleGuard(module: 'payment', child: InvoiceDetailScreen())),
        _r(Routes.products, const ProductsScreen()),
        _push(Routes.productDetail, const ProductDetailScreen()),
        _r(Routes.billing, const BillingScreen()),
        _r(Routes.reports, const ReportsScreen()),
        // Operations
        _r(Routes.opsHome, const OpsHomeScreen()),
        _r(Routes.opsProjects, const ProjectsScreen()),
        _push(Routes.projectDetail, const ProjectDetailScreen()),
        _push(Routes.createProject, const CreateProjectScreen()),
        _push(Routes.editProject, const EditProjectScreen()),
        _r(Routes.opsTasks, const OpsTasksScreen()),
        _push(Routes.opsTaskDetail, const OpsTaskDetailScreen()),
        _push(Routes.opsSubtask, const SubtaskDetailScreen()),
        _push(Routes.createTask, const CreateTaskScreen()),
        _push(Routes.editTask, const EditTaskScreen()),
        // Helpdesk
        _r(Routes.helpHome, const HelpHomeScreen()),
        _r(Routes.tickets, const TicketsScreen()),
        _push(Routes.ticketDetail, const TicketDetailScreen()),
        _push(Routes.createTicket, const CreateTicketScreen()),
        _push(Routes.editTicket, const EditTicketScreen()),
        _r(Routes.helpBoards, const BoardsScreen()),
        // Training
        _r(Routes.lmsOverview, const LmsOverviewScreen()),
        _r(Routes.lmsCourses, const LmsCoursesScreen()),
        _push(Routes.lmsCourseDetail, const LmsCourseDetailScreen()),
        _push(Routes.lmsBuilder, const LmsBuilderScreen()),
        _r(Routes.lmsLearners, const LmsLearnersScreen()),
        _push(Routes.lmsLearnerDetail, const LmsLearnerDetailScreen()),
        _r(Routes.lmsMy, const LmsMyCoursesScreen()),
        _push(Routes.lmsPlayer, const LmsPlayerScreen()),
        // Cross-cutting
        _r(Routes.dashboard, const DashboardScreen()),
        _push(Routes.notifications, const NotificationsScreen()),
        _r(Routes.rewards, const RewardsScreen()),
        _r(Routes.members, const MembersScreen()),
        _push(Routes.memberDetail, const MemberDetailScreen()),
        _r(Routes.teams, const TeamsScreen()),
        _r(Routes.roles, const RolesScreen()),
        _push(Routes.messages, const MessagesScreen()),
        _push(Routes.chat, const ChatScreen()),
        // Accounting (plan §4). Home is the landing for the Accountant /
        // Finance Viewer roles, whose grants are all `acc_*`.
        _r(Routes.accHome, const AccHomeScreen()),
        _r(Routes.accInvoices, const AccInvoicesScreen()),
        _push(Routes.accNewInvoice, const AccNewInvoiceScreen()),
        _push(Routes.accDocumentDetail, const AccDocumentDetailScreen()),
        _push(Routes.accDocumentPrint, const AccDocumentPrintScreen()),
        _push(Routes.accStatus, const AccStatusScreen()),
        _r(Routes.accMoney, const AccMoneyScreen()),
        _r(Routes.accPurchases, const AccPurchasesScreen()),
        _push(Routes.accVendors, const AccVendorsScreen()),
        _push(Routes.accVendorDetail, const AccVendorDetailScreen()),
        _push(Routes.accReports, const AccReportsScreen()),
        _push(Routes.accReport, const AccReportScreen()),
        _push(Routes.accPeriods, const AccPeriodsScreen()),
      ],
    ),
  ],
);
