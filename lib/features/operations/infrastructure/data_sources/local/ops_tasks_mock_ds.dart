import '../../../../../app/theme/app_colors.dart';
import '../../../domain/entities/ops_task.dart';

/// Static ops-task seed — a 1:1 port of the prototype's `OTSEED` array. This is
/// the ONLY place ops-task sample data lives. To integrate the API, replace
/// this class with a remote data source returning `List<OpsTask>`.
class OpsTasksMockDataSource {
  const OpsTasksMockDataSource();

  // Colour tags map the prototype's hex values onto AppColors tokens.
  static const _blue = OpsColorTag('Blue', AppColors.blueBright); // #074ADB
  static const _amber = OpsColorTag('Amber', AppColors.warning); // #EDA032
  static const _purple = OpsColorTag('Purple', AppColors.pending); // #890DB6
  static const _green = OpsColorTag('Green', AppColors.success); // #0E8F3D
  static const _gray = OpsColorTag('Gray', AppColors.textMuted); // #848383

  List<OpsTask> fetchOpsTasks() => [
        OpsTask(
          id: 'OT-101', subject: 'Site measurement & validation', projId: 'PRJ-2401', group: 'Site works', status: 'completed', pri: 'Medium', assignees: const ['me'], milestone: false,
          start: '12 May 2026', startTime: '9:00 AM', end: '20 May 2026', endTime: '6:00 PM', endISO: '2026-05-20', expHrs: 16, progress: 100, weight: 1, dept: 'Projects', color: _blue,
          subtasks: [Subtask(title: 'Laser survey — ground floor', done: true, who: 'me', due: '14 May'), Subtask(title: 'As-built drawing check', done: true, who: 'rk', due: '18 May')],
          waitingOn: const [], notes: const [], desc: 'Verify site dimensions against the design set and flag deviations above 25mm.',
          actualStart: '12 May', actualEnd: '19 May', actualEndFull: '19 May, 5:20 PM',
        ),
        OpsTask(
          id: 'OT-102', subject: 'Joinery shop drawings', projId: 'PRJ-2401', group: 'Design', status: 'working', pri: 'High', assignees: const ['me', 'st'], milestone: false,
          start: '01 Jun 2026', startTime: '9:00 AM', end: '05 Jul 2026', endTime: '5:00 PM', endISO: '2026-07-05', expHrs: 40, progress: null, weight: 3, dept: 'Design', color: _amber,
          subtasks: [Subtask(title: 'Wardrobe & trial room units', done: true, who: 'me', due: '15 Jun'), Subtask(title: 'Cash counter & display bays', done: true, who: 'st', due: '25 Jun'), Subtask(title: 'Façade signage substrate', done: false, who: 'me', due: '04 Jul')],
          waitingOn: const ['OT-101'], notes: const [OpsNote(author: 'Sneha Thomas', time: '2d ago', body: 'Veneer sample approved by client — proceeding with final drawing set.')], desc: 'Full joinery shop drawing set for showroom floor units, issued for fabrication.',
        ),
        OpsTask(
          id: 'OT-103', subject: 'Façade signage approval', projId: 'PRJ-2401', group: 'Approvals', status: 'review', pri: 'High', assignees: const ['am'], milestone: true,
          start: '20 Jun 2026', startTime: '10:00 AM', end: '15 Jul 2026', endTime: '11:00 AM', endISO: '2026-07-15', expHrs: 6, progress: 60, weight: 2, dept: 'Projects', color: _purple,
          subtasks: [], waitingOn: const ['OT-102'], notes: const [], desc: 'Corporation signage permission and client sign-off on the illuminated façade band.',
        ),
        OpsTask(
          id: 'OT-104', subject: 'Trial room lighting install', projId: 'PRJ-2401', group: 'Site works', status: 'open', pri: 'Medium', assignees: const ['me', 'rk', 'dr'], milestone: false,
          start: '18 Jul 2026', startTime: '9:00 AM', end: '25 Jul 2026', endTime: '4:00 PM', endISO: '2026-07-25', expHrs: 24, progress: null, weight: 2, dept: 'MEP', color: _blue,
          subtasks: [Subtask(title: 'Conduit & wiring', done: false, who: 'dr', due: '20 Jul'), Subtask(title: 'Fixture mounting', done: false, who: 'rk', due: '23 Jul'), Subtask(title: 'Scene programming', done: false, who: 'me', due: '25 Jul')],
          waitingOn: const ['OT-102', 'OT-106'], notes: const [], desc: 'Install and commission trial room lighting per the approved lighting spec.',
        ),
        OpsTask(
          id: 'OT-105', subject: 'VM units fabrication', projId: 'PRJ-2402', group: 'Joinery', status: 'working', pri: 'High', assignees: const ['rk'], milestone: false,
          start: '05 Jun 2026', startTime: '9:00 AM', end: '30 Jun 2026', endTime: '6:00 PM', endISO: '2026-06-30', expHrs: 60, progress: 45, weight: 3, dept: 'Workshop', color: _green,
          subtasks: [Subtask(title: 'Frame fabrication', done: true, who: 'rk', due: '15 Jun'), Subtask(title: 'Powder coating', done: false, who: 'rk', due: '22 Jun'), Subtask(title: 'Assembly', done: false, who: 'fa', due: '27 Jun'), Subtask(title: 'QC & packing', done: false, who: 'rk', due: '30 Jun')],
          waitingOn: const [], notes: const [], desc: 'Fabricate 14 visual merchandising units at the Aluva workshop.',
        ),
        OpsTask(
          id: 'OT-106', subject: 'MEP coordination drawings', projId: 'PRJ-2402', group: 'Design', status: 'open', pri: 'Medium', assignees: const ['me'], milestone: false,
          start: '08 Jul 2026', startTime: '9:30 AM', end: '18 Jul 2026', endTime: '1:00 PM', endISO: '2026-07-18', expHrs: 20, progress: 0, weight: 2, dept: 'Design', color: _blue,
          subtasks: [], waitingOn: const [], notes: const [], desc: 'Coordinate HVAC, electrical and sprinkler layouts with the ceiling design.',
        ),
        OpsTask(
          id: 'OT-107', subject: 'Banquet acoustic panels', projId: 'PRJ-2405', group: 'Site works', status: 'completed', pri: 'Medium', assignees: const ['me'], milestone: false,
          start: '26 May 2026', startTime: '9:00 AM', end: '20 Jun 2026', endTime: '6:00 PM', endISO: '2026-06-20', expHrs: 48, progress: 100, weight: 2, dept: 'Projects', color: _green,
          subtasks: [Subtask(title: 'Panel framing', done: true, who: 'me', due: '05 Jun'), Subtask(title: 'Fabric wrapping & fixing', done: true, who: 'dr', due: '16 Jun')],
          waitingOn: const [], notes: const [], desc: 'Supply and install acoustic wall panelling in the main banquet hall.',
          actualStart: '26 May', actualEnd: '28 May', actualEndFull: '18 Jun, 4:32 PM',
        ),
        OpsTask(
          id: 'OT-108', subject: 'Stage rigging safety check', projId: 'PRJ-2405', group: 'Snagging', status: 'cancelled', pri: 'Low', assignees: const ['me'], milestone: false,
          start: '22 Jun 2026', startTime: '10:00 AM', end: '25 Jun 2026', endTime: '5:00 PM', endISO: '2026-06-25', expHrs: 8, progress: 0, weight: 1, dept: 'Projects', color: _gray,
          subtasks: [], waitingOn: const [], notes: const [], desc: 'Third-party rigging inspection — descoped, handled by hotel engineering.',
        ),
        OpsTask(
          id: 'OT-109', subject: 'Villa moodboards', projId: 'PRJ-2403', group: 'Design', status: 'open', pri: 'Low', assignees: const ['an'], milestone: false,
          start: '01 Aug 2026', startTime: '9:00 AM', end: '10 Aug 2026', endTime: '5:00 PM', endISO: '2026-08-10', expHrs: 12, progress: 0, weight: 1, dept: 'Design', color: _purple,
          subtasks: [], waitingOn: const [], notes: const [], desc: 'Interior moodboards for the three villa categories.',
        ),
        OpsTask(
          id: 'OT-110', subject: 'Deck furniture BOQ', projId: 'PRJ-2403', group: 'Design', status: 'review', pri: 'Medium', assignees: const ['me', 'an'], milestone: false,
          start: '01 Jul 2026', startTime: '9:00 AM', end: '12 Jul 2026', endTime: '3:00 PM', endISO: '2026-07-12', expHrs: 10, progress: 80, weight: 1, dept: 'Design', color: _amber,
          subtasks: [], waitingOn: const [], notes: const [], desc: 'Bill of quantities for outdoor deck furniture across 14 villas.',
        ),
      ];
}
