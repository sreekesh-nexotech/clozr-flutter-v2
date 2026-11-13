import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/quote_detail_providers.dart';

/// Fetches a quote's PDF and hands it to the phone's PDF viewer (where it can
/// be saved or shared) — the Quote detail "Download PDF", reused by the lead's
/// Quotes tab (UI/UX audit #58). Reports a refusal or failure as a toast.
Future<void> downloadQuotePdf(WidgetRef ref,
    {required String quoteId, String number = ''}) async {
  final toast = ref.read(toastProvider.notifier);
  if (!ref.read(quoteCanExportProvider)) {
    toast.showError(kExportDenied);
    return;
  }
  try {
    final bytes = await ref.read(quoteActionsDsProvider).pdf(quoteId);
    final dir = await getTemporaryDirectory();
    final name = (number.isEmpty ? quoteId : number)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/$name.pdf');
    await file.writeAsBytes(bytes);
    final result = await OpenFile.open(file.path, type: 'application/pdf');
    if (result.type != ResultType.done) {
      toast.show(result.message.isNotEmpty
          ? result.message
          : 'No app on this device can open this file.');
    }
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    toast.showError(e.bareMessage);
  } on Object catch (e) {
    toast.showError('Could not open the PDF: $e');
  }
}
