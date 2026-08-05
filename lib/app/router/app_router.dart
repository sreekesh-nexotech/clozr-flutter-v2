import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_gate.dart';
import '../../core/config/api_config.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/shell/presentation/clozr_shell.dart';
import 'routes.dart';

// CRM
import '../../features/crm/presentation/screens/crm_home_screen.dart';
import '../../features/crm/presentation/screens/leads_screen.dart';
import '../../features/crm/presentation/screens/lead_detail_screen.dart';
import '../../features/crm/presentation/screens/add_lead_screen.dart';
import '../../features/crm/presentation/screens/customers_screen.dart';
import '../../features/crm/presentation/screens/customer_detail_screen.dart';
import '../../features/crm/presentation/screens/followups_screen.dart';
import '../../features/crm/presentation/screens/followup_detail_screen.dart';
import '../../features/crm/presentation/screens/tasks_screen.dart';
import '../../features/crm/presentation/screens/task_detail_screen.dart';
import '../../features/crm/presentation/screens/quotes_screen.dart';
import '../../features/crm/presentation/screens/quote_detail_screen.dart';
import '../../features/crm/presentation/screens/add_quote_screen.dart';
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

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// Builds a route whose page has no transition animation. Tab switches inside
/// the shell should feel instant, like the prototype's screen swaps.
GoRoute _r(String path, Widget child) => GoRoute(
      path: path,
      pageBuilder: (context, state) => NoTransitionPage(key: state.pageKey, child: child),
    );

/// Builds a route with the default push transition (for detail/create/edit
/// screens that are pushed on top and popped back).
GoRoute _push(String path, Widget child) => GoRoute(
      path: path,
      builder: (context, state) => child,
    );

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  // Auth gate — active only when a backend is configured. Mock mode keeps the
  // original boot-straight-into-the-shell behavior.
  refreshListenable: SessionGate.instance,
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
    // A signed-in user lands on the Dashboard, not the CRM home.
    return atAuthRoute ? Routes.dashboard : null;
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
      routes: [
        // CRM
        _r(Routes.home, const CrmHomeScreen()),
        _r(Routes.leads, const LeadsScreen()),
        _push(Routes.leadDetail, const LeadDetailScreen()),
        _push(Routes.addLead, const AddLeadScreen()),
        _r(Routes.customers, const CustomersScreen()),
        _push(Routes.customerDetail, const CustomerDetailScreen()),
        _r(Routes.followups, const FollowupsScreen()),
        _push(Routes.followupDetail, const FollowupDetailScreen()),
        _r(Routes.tasks, const TasksScreen()),
        _push(Routes.taskDetail, const TaskDetailScreen()),
        _r(Routes.quotes, const QuotesScreen()),
        _push(Routes.quoteDetail, const QuoteDetailScreen()),
        _push(Routes.addQuote, const AddQuoteScreen()),
        _r(Routes.payments, const PaymentsScreen()),
        _push(Routes.paymentDetail, const PaymentDetailScreen()),
        _push(Routes.invoiceDetail, const InvoiceDetailScreen()),
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
      ],
    ),
  ],
);
