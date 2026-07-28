import '../../../domain/entities/followup.dart';

/// Static follow-up seed — a 1:1 port of the prototype's `followups` array.
class FollowupsMockDataSource {
  const FollowupsMockDataSource();

  List<Followup> fetchFollowups() => const [
        Followup(id: 'F901', kind: 'Call', contact: 'Ramesh Pillai', custId: 'C2001', leadId: null, company: 'Kalyan Silks', due: '16 Jun 2026', time: '09:30', status: 'overdue', owner: 'am', agenda: 'Discuss scope and share ballpark'),
        Followup(id: 'F902', kind: 'Email', contact: 'Aboobacker Haji', custId: 'C2002', leadId: null, company: 'Lulu Fashion Store', due: '17 Jun 2026', time: '10:00', status: 'due', owner: 'rk', agenda: 'Share revised estimate & timeline'),
        Followup(id: 'F903', kind: 'Meeting', contact: 'Jose Kuriakose', custId: 'C2003', leadId: null, company: 'Marari Sands Resort', due: '18 Jun 2026', time: '11:00', status: 'due', owner: 'fa', agenda: 'Design presentation — villa interiors'),
        Followup(id: 'F904', kind: 'Site visit', contact: 'Nikhil Menon', custId: 'C2004', leadId: null, company: 'Taj Gateway Annexe', due: '19 Jun 2026', time: '14:30', status: 'due', owner: 'dr', agenda: 'Banquet hall measurements'),
        Followup(id: 'F905', kind: 'Call', contact: 'Priya Varma', custId: 'C2005', leadId: null, company: 'Aster Medcity OPD', due: '20 Jun 2026', time: '16:00', status: 'done', owner: 'st', agenda: 'Handover feedback'),
        Followup(id: 'F906', kind: 'Email', contact: 'Suresh Nair', custId: 'C2006', leadId: null, company: 'KIMS Clinic', due: '21 Jun 2026', time: '09:30', status: 'overdue', owner: 'an', agenda: 'Follow up on sign-off'),
        Followup(id: 'F907', kind: 'Meeting', contact: 'Biju Thomas', custId: 'C2007', leadId: null, company: 'Federal Bank Aluva', due: '23 Jun 2026', time: '10:00', status: 'due', owner: 'am', agenda: 'Phase 2 kickoff'),
        Followup(id: 'F908', kind: 'Site visit', contact: 'Anand Krishnan', custId: 'C2008', leadId: null, company: 'Infopark Tower B', due: '25 Jun 2026', time: '11:00', status: 'due', owner: 'rk', agenda: 'Cabin layout walkthrough'),
        Followup(id: 'F909', kind: 'Call', contact: 'Geetha Mohan', custId: 'C2009', leadId: null, company: 'Technopark Tejaswini', due: '27 Jun 2026', time: '14:30', status: 'due', owner: 'fa', agenda: 'Upsell — signage add-on'),
        Followup(id: 'F910', kind: 'Email', contact: 'Sangeeth Raj', custId: null, leadId: 'L1010', company: 'Workafella Coworking', due: '30 Jun 2026', time: '16:00', status: 'done', owner: 'dr', agenda: 'Send intro deck'),
        Followup(id: 'F911', kind: 'Meeting', contact: 'Ashraf Ali', custId: 'C2010', leadId: null, company: 'Malabar Gold Showroom', due: '16 Jun 2026', time: '09:30', status: 'overdue', owner: 'st', agenda: 'Expansion scope discussion'),
        Followup(id: 'F912', kind: 'Site visit', contact: 'Mathew George', custId: 'C2011', leadId: null, company: 'Nirapara Supermarket', due: '17 Jun 2026', time: '10:00', status: 'due', owner: 'an', agenda: 'Store measurements'),
      ];
}
