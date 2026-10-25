import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../../core/widgets/search_field.dart';
import '../../../infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import '../lead_picker_sheet.dart' show ClozrDividerLine;

/// The "Quote for" picker: type to search the server, pick from the matches.
///
/// Searches server-side (debounced, first 20) rather than over a preloaded
/// list — the lead picker must exclude converted leads (`is_converted=false`)
/// and label upsell leads, which only the API rows carry. Rows show the LD /
/// CUST reference, never the raw uuid.
Future<PartyOption?> showPartyPickerSheet({
  required BuildContext context,
  required String title,
  required String hint,
  required Future<List<PartyOption>> Function(String search) search,
  required String noun,
}) {
  return showClozrSheet<PartyOption>(
    context: context,
    builder: (_) => _PartyPicker(title: title, hint: hint, search: search, noun: noun),
  );
}

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.title, required this.hint, required this.search, required this.noun});
  final String title;
  final String hint;
  final Future<List<PartyOption>> Function(String) search;

  /// "leads" / "customers" — for the empty text.
  final String noun;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<PartyOption> _rows = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = rows;
        _query = q.trim();
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e is AppError ? e.message : 'Could not load ${widget.noun}';
        _loading = false;
      });
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          SearchField(
            controller: _ctrl,
            hint: widget.hint,
            autofocus: false,
            onChanged: _onChanged,
            onClose: () {
              _ctrl.clear();
              _run('');
            },
          ),
          SizedBox(height: 10.h),
          Flexible(
            child: _loading && _rows.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 28.h),
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
                  )
                : _error != null || _rows.isEmpty
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 28.h),
                        child: Center(
                          child: Text(
                              _error ?? (_query.isEmpty ? 'No ${widget.noun} yet' : 'No ${widget.noun} match “$_query”'),
                              textAlign: TextAlign.center,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: _error != null ? AppColors.error : AppColors.textPlaceholder)),
                        ),
                      )
                    : Opacity(
                        opacity: _loading ? 0.6 : 1,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const ClozrDividerLine(),
                          itemBuilder: (_, i) => _row(_rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(PartyOption o) {
    final initials = o.label.trim().isEmpty
        ? '?'
        : o.label.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(o),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        child: Row(children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
            child: Text(initials, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              if (o.sub.isNotEmpty) ...[
                SizedBox(height: 2.h),
                Text(o.sub, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ]),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
        ]),
      ),
    );
  }
}
