import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/helpdesk/presentation/util/ticket_errors.dart';
import 'package:clozrapp/features/helpdesk/presentation/util/ticket_sla.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppError refusal(Map<String, List<String>> fields, {Map<String, dynamic>? codes}) => AppError(
        type: AppErrorType.validation,
        message: '${fields.keys.first}: ${fields.values.first.first}',
        statusCode: 400,
        fieldErrors: fields,
        extra: codes == null ? null : {'error_codes': codes},
      );

  test('the mandatory-note guard uses the webapp sentence', () {
    final e = refusal(
      {'status_id': ['A mandatory note must be added to the issue before placing it on hold.']},
      codes: {'status_id': ['note_required_before_hold']},
    );
    expect(e.fieldErrorCodes('status_id'), ['note_required_before_hold']);
    expect(ticketErrorMessage(e), 'Add a note before placing this ticket on hold');
  });

  test('other refusals keep the server words without the field prefix', () {
    final e = refusal(
      {'status': ['Cannot resolve this ticket. The following child tickets are still open: TKT-0020']},
      codes: {'status': ['children_block_resolution']},
    );
    expect(ticketErrorMessage(e),
        'Cannot resolve this ticket. The following child tickets are still open: TKT-0020');
  });

  test('created time-ago follows the webapp buckets', () {
    String ago(Duration d) => ticketTimeAgo(DateTime.now().subtract(d).toIso8601String());
    expect(ago(const Duration(seconds: 20)), 'Just now');
    expect(ago(const Duration(minutes: 5)), '5m ago');
    expect(ago(const Duration(hours: 3)), '3h ago');
    expect(ago(const Duration(days: 2)), '2d ago');
    expect(ticketTimeAgo(null), '—');
  });
}
