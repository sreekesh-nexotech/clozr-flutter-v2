// Operations notes were in memory only — a note on a task or subtask vanished
// on restart, and subtask threads were keyed by a *position* in the parent's
// list, which cannot identify a record at all.
//
// The thread is `/projects/comments/`, not `/crm/notes/`: the CRM collection
// rejects a projects task outright ("Invalid task ID or access denied") because
// its `task` model is the CRM interaction task, a different table.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/ops_comments_remote_ds.dart';

void main() {
  group('comment → note', () {
    /// A row exactly as the dev backend returns it.
    Map<String, dynamic> row() => {
          'comment_id': '59ee7151-ab59-4777-8a0c-56bd92ccbd00',
          'content': 'Site measurements confirmed.',
          'created_at': '2026-08-18T06:38:06.810581Z',
          'created_by_name': 'Admin Acme',
          'related_to_model': 'task',
          'related_to_object_id': 'dfc9c9cb-669e-4a0b-adc8-620edbd50707',
        };

    test('keeps the comment id, so a reload matches the optimistic entry', () {
      final n = OpsCommentsRemoteDataSource.noteFromComment(row());
      expect(n.id, '59ee7151-ab59-4777-8a0c-56bd92ccbd00');
      expect(n.body, 'Site measurements confirmed.');
    });

    test('bylines the author the server recorded', () {
      expect(OpsCommentsRemoteDataSource.noteFromComment(row()).author, 'Admin Acme');
    });

    test('an unnamed author is "Unknown", never blank', () {
      final n = OpsCommentsRemoteDataSource.noteFromComment(
          {...row(), 'created_by_name': ''});
      expect(n.author, 'Unknown');
    });

    test('a row with no timestamp still maps', () {
      final n = OpsCommentsRemoteDataSource.noteFromComment(
          {...row(), 'created_at': null});
      expect(n.time, '');
      expect(n.body, isNotEmpty);
    });
  });
}
