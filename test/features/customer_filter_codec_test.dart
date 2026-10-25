import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/crm/application/filters/customer_filter_codec.dart';
import 'package:clozrapp/features/crm/application/filters/customers_filter_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = CustomerFilterCodec(currentUserId: 'me-uuid');
  final spec = buildCustomersFilterSpec(customers: const [], leads: const []);

  test('account manager is sent as assignees__in / __not (assigned_to is ignored server-side)', () {
    final v = FilterValues()..['owners'] = ChoiceValue(ids: {'u1', 'me'});
    expect(codec.encode(v), {'assignees__in': 'u1,me-uuid'});

    final out = FilterValues()..['owners'] = ChoiceValue(ids: {'u1'}, isNot: true);
    expect(codec.encode(out), {'assignees__not': 'u1'});
  });

  test('views saved with either key decode back to the account manager facet', () {
    for (final key in ['assignees__in', 'assigned_to__in']) {
      final v = codec.decode({key: 'u1,me-uuid'}, spec);
      expect(v.choice('owners')?.ids, {'u1', 'me'});
    }
  });

  test('there is no Company facet (not a webapp customer filter)', () {
    final ids = [for (final s in spec.sections) for (final f in s.fields) f.id];
    expect(ids, ['statuses', 'sources', 'owners', 'products', 'value', 'since']);
  });
}
