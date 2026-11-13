import 'package:clozrapp/features/operations/application/ops_task_write_fields.dart';
import 'package:flutter_test/flutter_test.dart';

/// Webapp parity C15: a subtask's due must sit inside its parent's window.
void main() {
  const start = '2026-11-10T09:00:00+05:30';
  const end = '2026-11-20T18:00:00+05:30';
  test('inside the window is fine', () {
    expect(
        subtaskWindowError(DateTime.parse('2026-11-15T12:00:00+05:30'),
            parentStartIso: start, parentEndIso: end),
        isNull);
  });
  test('before the parent start / after the parent end is refused', () {
    expect(
        subtaskWindowError(DateTime.parse('2026-11-09T12:00:00+05:30'),
            parentStartIso: start, parentEndIso: end),
        "Due can't be before the parent task's start");
    expect(
        subtaskWindowError(DateTime.parse('2026-11-21T12:00:00+05:30'),
            parentStartIso: start, parentEndIso: end),
        "Due can't be after the parent task's end");
  });
  test('blank parent bounds are open', () {
    expect(subtaskWindowError(DateTime(2030), parentStartIso: '', parentEndIso: ''),
        isNull);
  });
}
