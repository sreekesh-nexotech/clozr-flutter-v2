import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../domain/entities/course.dart';
import '../../../domain/entities/learner_record.dart';
import '../../../domain/entities/lms_activity.dart';

/// Static LMS seed — a 1:1 port of the prototype's `LMS_COURSES`, `LMS_RECS`
/// and `LMS_ACTIVITY` arrays. This is the ONLY place LMS sample data lives; to
/// integrate the API, replace this class with a remote data source returning
/// the same entities and nothing else changes. Glyphs and tint/accent colours
/// are resolved to typed [IconData] / [Color] here (the design's inline seed).
class LmsMockDataSource {
  const LmsMockDataSource();

  List<Course> fetchCourses() => [
        Course(
          id: 'LC-01',
          title: 'CRM Fundamentals',
          sub: 'Core CRM workflows',
          status: 'published',
          sequential: true,
          mandatory: true,
          role: 'All Roles',
          deadline: '20 Aug 2026',
          deadlineISO: '2026-08-20',
          tint: AppColors.blueSubtle,
          accent: AppColors.blueBright,
          icon: PhosphorIconsFill.usersThree,
          desc:
              'This course introduces the core concepts of Customer Relationship Management (CRM) and how teams use CRM systems to manage leads, track customer interactions, and organize sales workflows. By the end you will understand how CRM platforms help sales, marketing and support teams work more efficiently.',
          modules: const [
            CourseModule(id: 'm1', title: 'Core CRM workflows', dur: '12 min', video: true, res: ['CRM Workflow Guide.pdf']),
            CourseModule(id: 'm2', title: 'Sales pipeline stages', dur: '9 min', video: true, res: []),
            CourseModule(id: 'm3', title: 'Follow-ups & tasks', dur: '11 min', video: true, res: ['Follow-up Playbook.pdf']),
            CourseModule(id: 'm4', title: 'Quotes & payments', dur: '14 min', video: true, res: []),
          ],
        ),
        Course(
          id: 'LC-02',
          title: 'Sales Pipeline Mastery',
          sub: 'Qualify, quote & close',
          status: 'published',
          sequential: true,
          mandatory: false,
          role: 'Sales rep',
          deadline: '15 Sep 2026',
          deadlineISO: '2026-09-15',
          tint: AppColors.tintGreen,
          accent: AppColors.success,
          icon: PhosphorIconsFill.trendUp,
          desc:
              'Master the pipeline end-to-end — qualification frameworks, quoting discipline and negotiation habits that close deals faster.',
          modules: const [
            CourseModule(id: 'm1', title: 'Qualifying leads', dur: '10 min', video: true, res: []),
            CourseModule(id: 'm2', title: 'Building winning quotes', dur: '13 min', video: true, res: ['Quote Checklist.pdf']),
            CourseModule(id: 'm3', title: 'Negotiation & closing', dur: '15 min', video: true, res: []),
          ],
        ),
        Course(
          id: 'LC-03',
          title: 'Project Management Basics',
          sub: 'Plan & deliver projects',
          status: 'published',
          sequential: false,
          mandatory: false,
          role: 'All Roles',
          deadline: '30 Jun 2026',
          deadlineISO: '2026-06-30',
          tint: AppColors.tintAmber,
          accent: AppColors.warningDeep,
          icon: PhosphorIconsFill.briefcase,
          desc:
              'Plan, schedule and deliver interior fit-out projects — scoping, task breakdown, dependencies and handover discipline.',
          modules: const [
            CourseModule(id: 'm1', title: 'Project setup & scoping', dur: '11 min', video: true, res: ['Scoping Template.pdf']),
            CourseModule(id: 'm2', title: 'Tasks & dependencies', dur: '9 min', video: true, res: []),
            CourseModule(id: 'm3', title: 'Tracking progress', dur: '8 min', video: true, res: []),
            CourseModule(id: 'm4', title: 'Handover & closure', dur: '10 min', video: true, res: []),
          ],
        ),
        Course(
          id: 'LC-04',
          title: 'Admin & Permissions',
          sub: 'Roles, scopes & settings',
          status: 'published',
          sequential: false,
          mandatory: false,
          role: 'Manager',
          deadline: '31 Jul 2026',
          deadlineISO: '2026-07-31',
          tint: const Color(0xFFF3E8FA),
          accent: AppColors.pending,
          icon: PhosphorIconsFill.shieldCheck,
          desc:
              'Configure roles, visibility scopes and workspace settings safely — who sees what, and why.',
          modules: const [
            CourseModule(id: 'm1', title: 'Roles & visibility scopes', dur: '9 min', video: true, res: ['Roles Matrix.pdf']),
            CourseModule(id: 'm2', title: 'Teams & hierarchy', dur: '7 min', video: true, res: []),
            CourseModule(id: 'm3', title: 'Workspace settings', dur: '8 min', video: true, res: []),
          ],
        ),
        Course(
          id: 'LC-05',
          title: 'Helpdesk SLA Playbook',
          sub: 'Tickets & SLA timers',
          status: 'draft',
          sequential: true,
          mandatory: false,
          role: 'All Roles',
          deadline: '',
          deadlineISO: '',
          tint: AppColors.tintRed,
          accent: AppColors.error,
          icon: PhosphorIconsFill.headset,
          desc:
              'Respond, resolve and stay inside SLA — triage rules, priority handling and escalation paths.',
          modules: const [
            CourseModule(id: 'm1', title: 'Ticket triage basics', dur: '8 min', video: true, res: []),
            CourseModule(id: 'm2', title: 'SLA timers & breaches', dur: '10 min', video: false, res: []),
          ],
        ),
        Course(
          id: 'LC-06',
          title: 'Site Safety Induction',
          sub: 'On-site conduct & PPE',
          status: 'published',
          sequential: true,
          mandatory: true,
          role: 'All Roles',
          deadline: '30 Sep 2026',
          deadlineISO: '2026-09-30',
          tint: AppColors.tintNavy,
          accent: AppColors.navy,
          icon: PhosphorIconsFill.hardHat,
          desc:
              'Mandatory site conduct — PPE, tool handling and incident reporting for everyone visiting active sites.',
          modules: const [
            CourseModule(id: 'm1', title: 'PPE & site conduct', dur: '9 min', video: true, res: ['Site Safety Card.pdf']),
            CourseModule(id: 'm2', title: 'Incident reporting', dur: '6 min', video: true, res: []),
          ],
        ),
      ];

  List<LearnerRecord> fetchRecords() => const [
        LearnerRecord(rid: 'me', courses: [
          CourseProgress(courseId: 'LC-01', mods: [60, 0, 0, 0]),
          CourseProgress(courseId: 'LC-04', mods: [100, 100, 100]),
          CourseProgress(courseId: 'LC-03', mods: [0, 0, 0, 0]),
          CourseProgress(courseId: 'LC-02', mods: [0, 0, 0]),
          CourseProgress(courseId: 'LC-06', mods: [80, 0]),
        ]),
        LearnerRecord(rid: 'an', courses: [
          CourseProgress(courseId: 'LC-01', mods: [100, 100, 100, 100]),
          CourseProgress(courseId: 'LC-02', mods: [100, 100, 100]),
          CourseProgress(courseId: 'LC-04', mods: [100, 100, 100]),
          CourseProgress(courseId: 'LC-06', mods: [20, 0]),
        ]),
        LearnerRecord(rid: 'am', courses: [
          CourseProgress(courseId: 'LC-01', mods: [100, 100, 100, 100]),
          CourseProgress(courseId: 'LC-02', mods: [70, 45, 0]),
        ]),
        LearnerRecord(rid: 'rk', courses: [
          CourseProgress(courseId: 'LC-01', mods: [100, 80, 40, 25]),
          CourseProgress(courseId: 'LC-02', mods: [30, 0, 0]),
        ]),
        LearnerRecord(rid: 'fa', courses: [
          CourseProgress(courseId: 'LC-01', mods: [45, 15, 0, 0]),
          CourseProgress(courseId: 'LC-03', mods: [40, 20, 0, 0]),
        ]),
        LearnerRecord(rid: 'dr', courses: [
          CourseProgress(courseId: 'LC-01', mods: [0, 0, 0, 0]),
          CourseProgress(courseId: 'LC-06', mods: [100, 100]),
        ]),
        LearnerRecord(rid: 'st', courses: [
          CourseProgress(courseId: 'LC-04', mods: [100, 100, 100]),
          CourseProgress(courseId: 'LC-03', mods: [80, 55, 40, 45]),
        ]),
        LearnerRecord(rid: 'rj', courses: [
          CourseProgress(courseId: 'LC-06', mods: [0, 0]),
        ]),
      ];

  List<LmsActivity> fetchActivity() => const [
        LmsActivity(dot: AppColors.success, who: 'Arjun Nair', what: 'completed CRM Fundamentals', time: '2 hours ago'),
        LmsActivity(dot: AppColors.warning, who: 'Rahul Krishnan', what: 'resumed Sales Pipeline Mastery', time: '4 hours ago'),
        LmsActivity(dot: AppColors.blueBright, who: 'Sneha Thomas', what: 'started Project Management Basics', time: '4 hours ago'),
        LmsActivity(dot: AppColors.success, who: 'Sneha Thomas', what: 'completed all modules in Admin & Permissions', time: '5 hours ago'),
        LmsActivity(dot: AppColors.error, who: 'Fariz Ahmed', what: 'went overdue on Project Management Basics', time: '6 hours ago'),
      ];
}
