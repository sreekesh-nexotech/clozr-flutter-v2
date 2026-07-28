import '../../../domain/entities/crm_task.dart';

/// Static CRM-task seed — a 1:1 port of the prototype's `tasks` array.
class CrmTasksMockDataSource {
  const CrmTasksMockDataSource();

  List<CrmTask> fetchTasks() => const [
        CrmTask(id: 'TL-001', title: 'Call to discuss scope — Kalyan Silks', type: 'Call', leadId: 'L1001', status: 'todo', priority: 'High', assignee: 'am', due: '16 Jun 2026', dueNote: '2d overdue'),
        CrmTask(id: 'TL-002', title: 'Email capability deck & estimate — Lulu Fashion Store', type: 'Email', leadId: 'L1002', status: 'inprogress', priority: 'Medium', assignee: 'rk', due: '17 Jun 2026', dueNote: '1d overdue'),
        CrmTask(id: 'TL-003', title: 'Present layout options — Marari Sands Resort', type: 'Meeting', leadId: 'L1003', status: 'blocked', priority: 'Low', assignee: 'fa', due: '18 Jun 2026', dueNote: 'Today'),
        CrmTask(id: 'TL-004', title: 'Site survey — measurements — Taj Gateway Annexe', type: 'Site visit', leadId: 'L1004', status: 'done', priority: 'High', assignee: 'dr', due: '19 Jun 2026', dueNote: ''),
        CrmTask(id: 'TL-005', title: 'Send revised quote — Aster Medcity OPD', type: 'Quote', leadId: 'L1005', status: 'todo', priority: 'Medium', assignee: 'st', due: '20 Jun 2026', dueNote: 'In 2d'),
        CrmTask(id: 'TL-006', title: 'Follow up on sign-off — KIMS Clinic', type: 'Follow-up', leadId: 'L1006', status: 'inprogress', priority: 'Low', assignee: 'an', due: '21 Jun 2026', dueNote: 'In 3d'),
        CrmTask(id: 'TL-007', title: 'Prepare contract documents — Federal Bank Aluva', type: 'Admin', leadId: 'L1007', status: 'blocked', priority: 'High', assignee: 'am', due: '22 Jun 2026', dueNote: ''),
        CrmTask(id: 'TL-008', title: 'Call to discuss scope — Infopark Tower B', type: 'Call', leadId: 'L1008', status: 'done', priority: 'Medium', assignee: 'rk', due: '23 Jun 2026', dueNote: ''),
        CrmTask(id: 'TL-009', title: 'Email capability deck — Technopark Tejaswini', type: 'Email', leadId: 'L1009', status: 'todo', priority: 'Low', assignee: 'fa', due: '24 Jun 2026', dueNote: ''),
        CrmTask(id: 'TL-010', title: 'Present layout options — Workafella Coworking', type: 'Meeting', leadId: 'L1010', status: 'inprogress', priority: 'High', assignee: 'dr', due: '25 Jun 2026', dueNote: ''),
        CrmTask(id: 'TL-011', title: 'Site survey — measurements — Malabar Gold Showroom', type: 'Site visit', leadId: 'L1012', status: 'blocked', priority: 'Medium', assignee: 'st', due: '16 Jun 2026', dueNote: '2d overdue'),
        CrmTask(id: 'TL-012', title: 'Send revised quote — Nirapara Supermarket', type: 'Quote', leadId: 'L1011', status: 'todo', priority: 'High', assignee: 'an', due: '26 Jun 2026', dueNote: ''),
      ];
}
