import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/operations/application/filters/project_filter_codec.dart';

/// The drawer fields that used to be matched only over already-downloaded rows.
/// `operations.md` §1 documents a param for each, so each is encoded now.
void main() {
  const codec = ProjectFilterCodec();

  Map<String, dynamic> encode(String field, FilterValue value) =>
      codec.encode(FilterValues({field: value}));

  group('health', () {
    test('is_overdue is never sent — it 500s the projects list', () {
      // Verified against dev (12 Aug 2026): `?is_overdue=true` and `=false`
      // both return an AssertionError 500, so encoding either side would take
      // the whole list down. Both stay with the local matcher.
      expect(encode('health', const RadioValue(id: 'overdue', defaultId: 'any')), isEmpty);
      expect(encode('health', const RadioValue(id: 'ontrack', defaultId: 'any')), isEmpty);
    });

    test('Due in 14 days is the one option with a working param', () {
      final out = encode('health', const RadioValue(id: 'risk', defaultId: 'any'));
      expect(out['due_within_days'], '14');
      expect(out.containsKey('is_overdue'), isFalse);
    });

    test('Any encodes nothing', () {
      expect(encode('health', const RadioValue(id: 'any', defaultId: 'any')), isEmpty);
    });
  });

  group('estimated cost', () {
    test('the slider is in lakhs; the params are in rupees', () {
      final out = encode('cost', const RangeValue(min: 5, max: 25));
      expect(out['budget_min'], '500000');
      expect(out['budget_max'], '2500000');
    });

    test('an open-ended range sends only the bound that is set', () {
      expect(encode('cost', const RangeValue(min: 10)),
          {'budget_min': '1000000'});
      expect(encode('cost', const RangeValue(max: 10)),
          {'budget_max': '1000000'});
      expect(encode('cost', const RangeValue()), isEmpty);
    });
  });

  group('date ranges', () {
    test('explicit bounds map onto _after / _before', () {
      final out = encode(
        'end',
        DateValue(from: DateTime(2026, 6, 1), to: DateTime(2026, 6, 30)),
      );
      expect(out['expected_end_date_after'], '2026-06-01');
      expect(out['expected_end_date_before'], '2026-06-30');
    });

    test('start uses its own field', () {
      final out = encode('start', DateValue(from: DateTime(2026, 1, 5)));
      expect(out['expected_start_date_after'], '2026-01-05');
      expect(out.containsKey('expected_end_date_after'), isFalse);
    });

    test('a quick chip resolves to the same window the local matcher uses', () {
      final (from, to) = FilterMatch.chipRange('next30');
      final out = encode('end', const DateValue(chip: 'next30'));

      expect(out['expected_end_date_after'], _iso(from!));
      expect(out['expected_end_date_before'], _iso(to!));
    });

    test('"overdue" has no lower bound, so only _before goes out', () {
      final out = encode('end', const DateValue(chip: 'overdue'));
      expect(out.containsKey('expected_end_date_after'), isFalse);
      expect(out.containsKey('expected_end_date_before'), isTrue);
    });
  });

  test('an untouched drawer encodes to nothing', () {
    expect(codec.encode(FilterValues()), isEmpty);
  });

  test('only genuinely unbacked fields stay local', () {
    // `health`, `cost`, `start` and `end` were listed here despite §1
    // documenting params for all four.
    expect(ProjectFilterCodec.localOnlyFields,
        {'assignees', 'teams', 'progress', 'health'});
  });
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
