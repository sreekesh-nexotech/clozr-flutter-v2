import 'tour.dart';

/// Built-in draft tours for trying the runner before the real `mobile` tours
/// are published from the superadmin editor. Only used when the build sets
/// `--dart-define=ONBOARDING_SAMPLE_TOUR=true` AND the server has no mobile
/// tours; progress for them stays on the phone (the server does not know
/// these keys). Wording is the draft from the implementation plan.
const sampleTours = <Tour>[
  Tour(
    key: 'welcome',
    version: 1,
    title: 'Welcome to Clozr',
    description: 'A 30-second look around the app.',
    category: 'Getting started',
    order: 1,
    autoStart: true,
    startRoute: '/home',
    localOnly: true,
    steps: [
      TourStep(
          key: 'hello',
          route: '/home',
          placement: TourPlacement.center,
          title: 'Welcome to Clozr',
          body: 'A quick look around — it takes 30 seconds.'),
      TourStep(
          key: 'tabs',
          route: '/home',
          target: 'nav.tabs',
          title: 'Your main areas',
          body: 'Switch between home, your lists and boards here.'),
      TourStep(
          key: 'apps',
          route: '/home',
          target: 'nav.apps',
          title: 'All your apps',
          body: 'CRM, Operations, Helpdesk and more live here.'),
      TourStep(
          key: 'notifications',
          route: '/home',
          target: 'topbar.notifications',
          title: 'Notifications',
          body:
              'Approvals, mentions and reminders arrive here. Tap one to open it.'),
      TourStep(
          key: 'add',
          route: '/home',
          target: 'action.add',
          title: 'Create anything',
          body: 'Add a lead, task, ticket or note from anywhere.'),
      TourStep(
          key: 'done',
          route: '/home',
          placement: TourPlacement.center,
          title: 'You’re all set',
          body: 'Replay this tour any time from the menu › Product tours.'),
    ],
  ),
  Tour(
    key: 'leads',
    version: 1,
    title: 'Working with leads',
    description: 'Find, filter and add leads.',
    category: 'CRM',
    order: 2,
    startRoute: '/leads',
    prerequisite: 'welcome',
    localOnly: true,
    steps: [
      TourStep(
          key: 'list',
          route: '/leads',
          target: 'leads.list',
          title: 'Your leads',
          body: 'Newest first. Tap a lead to see its details.'),
      TourStep(
          key: 'search',
          route: '/leads',
          target: 'leads.search',
          title: 'Search',
          body: 'Find a lead by name, phone or email.'),
      TourStep(
          key: 'filters',
          route: '/leads',
          target: 'leads.filters',
          title: 'Filters',
          body: 'Narrow the list by status, owner, source and more.'),
      TourStep(
          key: 'add',
          route: '/leads',
          target: 'action.add',
          advance: TourAdvance.clickTarget,
          title: 'Add a lead',
          body: 'Tap + to add your first lead.'),
    ],
  ),
];
