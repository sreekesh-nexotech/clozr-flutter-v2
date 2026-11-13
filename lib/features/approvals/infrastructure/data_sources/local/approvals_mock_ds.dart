/// Mock-mode seed for Unified Approvals — the same row shape the API sends,
/// so mock and API mode go through one mapper.
class ApprovalsMockDataSource {
  const ApprovalsMockDataSource();

  static Map<String, dynamic> _user(String id, String name) =>
      {'user_id': id, 'email': '', 'full_name': name};

  List<Map<String, dynamic>> rows() {
    final now = DateTime.now().toUtc();
    String ago(int hours) =>
        now.subtract(Duration(hours: hours)).toIso8601String();
    return [
      {
        'approval_id': 'mock-approval-1',
        'module': 'task',
        'kind': 'close',
        'object_id': 'mock-task-1',
        'record_label': 'Send proposal to Acme',
        'can_decide': true,
        'can_escalate': true,
        'can_withdraw': false,
        'requested_by': _user('u-ravi', 'Ravi Menon'),
        'record_owner': _user('u-ravi', 'Ravi Menon'),
        'current_approver': _user('u-me', 'Manoj Varma'),
        'route_reason': 'owner_manager',
        'display': {'from': 'In progress', 'to': 'Completed'},
        'request_note': 'Customer confirmed by phone',
        'status': 'pending',
        'created_at': ago(3),
        'record_summary': {
          'title': 'Send proposal to Acme',
          'status': 'In progress',
          'owner': 'Ravi Menon',
          'due_date': '2026-11-18',
        },
        'record_visible': true,
        'steps': [
          {
            'step_id': 's1',
            'approver': _user('u-me', 'Manoj Varma'),
            'reason': 'owner_manager',
            'outcome': '',
            'note': '',
            'assigned_at': ago(3),
            'acted_at': null,
          }
        ],
        'tabs': ['pending'],
      },
      {
        'approval_id': 'mock-approval-2',
        'module': 'lead',
        'kind': 'owner_transfer',
        'object_id': 'mock-lead-1',
        'record_label': 'Priya Nair',
        'can_decide': true,
        'can_escalate': true,
        'can_withdraw': false,
        'requested_by': _user('u-anu', 'Anu Joseph'),
        'record_owner': _user('u-anu', 'Anu Joseph'),
        'current_approver': _user('u-me', 'Manoj Varma'),
        'route_reason': 'owner_manager',
        'display': {'from': 'Anu Joseph', 'to': 'Ravi Menon'},
        'request_note': '',
        'status': 'pending',
        'created_at': ago(26),
        'record_summary': {'label': 'Priya Nair', 'status': 'Qualified'},
        'record_visible': true,
        'steps': const [],
        'tabs': ['pending'],
      },
      {
        'approval_id': 'mock-approval-3',
        'module': 'project_task',
        'kind': 'due_date',
        'object_id': 'mock-ops-task-1',
        'record_label': 'Site survey',
        'can_decide': false,
        'can_escalate': false,
        'can_withdraw': true,
        'requested_by': _user('u-me', 'Manoj Varma'),
        'record_owner': _user('u-me', 'Manoj Varma'),
        'current_approver': _user('u-lead', 'Deepa Thomas'),
        'route_reason': 'project_manager',
        'display': {'from': '12 Nov 2026', 'to': '19 Nov 2026'},
        'request_note': 'Client requested',
        'status': 'pending',
        'created_at': ago(50),
        'record_summary': {'title': 'Site survey', 'due_date': '2026-11-12'},
        'record_visible': true,
        'steps': const [],
        'tabs': ['mine'],
      },
    ];
  }
}
