import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/quote_detail_providers.dart';
import '../../application/report_export.dart';
import 'finance_widgets.dart';

/// "Exports" on Reports: the datasets a user may export as CSV. Quotations needs
/// the quotation export right (the same gate as the quote PDF).
class ReportExportsCard extends ConsumerStatefulWidget {
  const ReportExportsCard({super.key});

  @override
  ConsumerState<ReportExportsCard> createState() => _ReportExportsCardState();
}

class _ReportExportsCardState extends ConsumerState<ReportExportsCard> {
  bool _busy = false;

  Future<void> _export(ReportDataset d) async {
    final toast = ref.read(toastProvider.notifier);
    final chosen = await showDialog<Set<String>>(
        context: context, builder: (_) => _ColumnPicker(dataset: d));
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(apiServiceProvider)
          .postBytes(d.path, body: exportBody(d, chosen));
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/${exportFileName(d.label, DateTime.now())}');
      await file.writeAsBytes(bytes);
      final r = await OpenFile.open(file.path, type: 'text/csv');
      toast.show(r.type == ResultType.done
          ? '${d.label} exported'
          : '${d.label} exported — ${file.path.split('/').last} saved, but no app can open it.');
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      toast.showError(e.bareMessage);
    } on Object catch (e) {
      toast.showError('Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const d = quotationDataset;
    final canExport = ref.watch(quoteCanExportProvider);
    return FinanceCard(
      title: 'Exports',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canExport && !_busy ? () => _export(d) : null,
        child: Opacity(
          opacity: canExport ? 1 : 0.5,
          child: Row(children: [
            Icon(PhosphorIconsRegular.fileText,
                size: 22.sp, color: AppColors.navy),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.label,
                        style: AppText.custom(
                            size: 14.5,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text(canExport ? d.description : kExportDenied,
                        style: AppText.caption()),
                    Text(d.group, style: AppText.caption()),
                  ]),
            ),
            if (_busy)
              SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(PhosphorIconsRegular.downloadSimple,
                  size: 20.sp, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

class _ColumnPicker extends StatefulWidget {
  const _ColumnPicker({required this.dataset});
  final ReportDataset dataset;

  @override
  State<_ColumnPicker> createState() => _ColumnPickerState();
}

class _ColumnPickerState extends State<_ColumnPicker> {
  late final Set<String> _chosen = {...widget.dataset.columns};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Export ${widget.dataset.label}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final c in widget.dataset.columns)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(c),
                title: Text(columnLabel(c)),
                onChanged: (v) => setState(
                    () => v == true ? _chosen.add(c) : _chosen.remove(c)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: _chosen.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_chosen),
              child: const Text('Export CSV')),
        ],
      );
}
