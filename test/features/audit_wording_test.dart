import 'package:clozrapp/core/utils/audit_wording.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI/UX audit #36: file events read as files, not "Attachment".
void main() {
  test('attachment summaries become plain file wording', () {
    expect(plainAuditSummary("Attachment 'a.txt' created"), "File 'a.txt' uploaded");
    expect(plainAuditSummary("Attachment 'a.txt' updated"), "File 'a.txt' renamed");
    expect(plainAuditSummary("Attachment 'a.txt' deleted"), "File 'a.txt' deleted");
  });
  test('other summaries are untouched', () {
    expect(plainAuditSummary('Task created'), 'Task created');
    expect(plainAuditSummary("Status changed to 'Open'"), "Status changed to 'Open'");
  });
  test('related change on an attachment', () {
    expect(plainRelatedChange('Attachment', 'create'), 'Uploaded file');
    expect(plainRelatedChange('Attachment', 'delete'), 'Deleted file');
    expect(plainRelatedChange('Note', 'create'), isNull);
  });
}
