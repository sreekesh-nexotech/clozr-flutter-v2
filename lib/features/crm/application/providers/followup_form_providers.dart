import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../followup_form_rules.dart';

/// `GET /management/custom-fields/?model_name=task` — the task custom-field
/// schema the webapp's Add follow-up form renders from (both kinds; the form
/// keeps the `all` + `followup` ones). Readable by every org user.
///
/// Unlike the option catalogs this one is allowed to fail: the sheet then says
/// so (the server still checks required fields on save), as the webapp does.
final taskCustomFieldDefsProvider = FutureProvider.autoDispose<List<TaskCustomFieldDef>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  final body = await ref.read(apiServiceProvider).get(
    '/management/custom-fields/',
    query: {'model_name': 'task', 'is_active': true, 'ordering': 'order', 'page_size': 100},
    quiet: true,
  );
  return TaskCustomFieldDef.listFromResponse(body);
});
