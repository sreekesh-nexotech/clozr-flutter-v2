import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

// The webapp's duplicate-lead notice (`DuplicateNotice`). The org's lead rules
// decide what a match does: `block` refuses the create (400 with
// `errors.duplicate`), `warn` saves it and returns the same block under
// `warnings` on the 201.

/// One existing lead or customer the new lead matched.
class DuplicateMatch {
  const DuplicateMatch({required this.id, required this.name, this.email = ''});

  final String id;
  final String name;
  final String email;
}

class LeadDuplicate {
  const LeadDuplicate({
    this.matchKeys = const [],
    this.leads = const [],
    this.customers = const [],
  });

  final List<String> matchKeys;
  final List<DuplicateMatch> leads;
  final List<DuplicateMatch> customers;

  bool get hasMatches => leads.isNotEmpty || customers.isNotEmpty;

  /// Parses one duplicate block. [allowUntyped] accepts a block with no
  /// `type` (a 201's `warnings` entry); anything typed other than
  /// `duplicate` is not ours.
  static LeadDuplicate? parse(Object? raw, {bool allowUntyped = false}) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type == null ? !allowUntyped : type != 'duplicate') return null;
    List<DuplicateMatch> rows(Object? v) => [
          if (v is List)
            for (final r in v)
              if (r is Map)
                DuplicateMatch(
                  id: '${r['lead_id'] ?? r['customer_id'] ?? r['id'] ?? ''}',
                  name: '${r['lead_name'] ?? r['customer_name'] ?? r['name'] ?? 'Untitled'}',
                  email: _clean(r['email']),
                ),
        ];
    final matched = raw['matched'] is Map ? raw['matched'] as Map : const {};
    return LeadDuplicate(
      matchKeys: [if (raw['match_keys'] is List) for (final k in raw['match_keys'] as List) '$k'],
      leads: rows(matched['leads']),
      customers: rows(matched['customers']),
    );
  }

  /// The server stringifies a missing value as `"None"`.
  static String _clean(Object? v) {
    final t = '${v ?? ''}'.trim();
    return t == 'None' || t == 'null' ? '' : t;
  }

  /// The first duplicate warning on a create response, if any.
  static LeadDuplicate? fromWarnings(Object? warnings) {
    if (warnings is! List) return null;
    for (final w in warnings) {
      final d = parse(w, allowUntyped: true);
      if (d != null) return d;
    }
    return null;
  }

  /// "email or phone", "email, phone or mobile number".
  String get keysText {
    final keys = [for (final k in matchKeys) k == 'mobile_no' ? 'mobile number' : k.replaceAll('_', ' ')];
    if (keys.isEmpty) return '';
    if (keys.length == 1) return keys.first;
    return '${keys.sublist(0, keys.length - 1).join(', ')} or ${keys.last}';
  }
}

/// The panel shown on Add lead after a duplicate match.
class DuplicateNotice extends StatelessWidget {
  const DuplicateNotice({
    super.key,
    required this.duplicate,
    required this.blocked,
    required this.onOpenLead,
    required this.onOpenCustomer,
    this.newLeadId,
    this.subject = 'lead',
  });

  final LeadDuplicate duplicate;

  /// Refused (block) rather than saved with a warning.
  final bool blocked;

  /// The lead a `warn` create saved, for "Open the new lead".
  final String? newLeadId;
  final ValueChanged<String> onOpenLead;
  final ValueChanged<String> onOpenCustomer;

  /// What the record being created is called in the copy — `lead` or
  /// `customer` (webapp `DuplicateNotice` `subject`). For `customer`,
  /// [newLeadId] is the new customer's id and opens through [onOpenCustomer].
  final String subject;

  @override
  Widget build(BuildContext context) {
    final accent = blocked ? AppColors.error : AppColors.warningDeep;
    final keys = duplicate.keysText;
    final String body;
    if (blocked) {
      final lead = keys.isEmpty
          ? 'Your workspace blocks duplicate ${subject}s.'
          : 'Your workspace blocks duplicate ${subject}s with a matching $keys.';
      body = '$lead ${duplicate.hasMatches ? 'Open the existing record instead, or change the matched field to continue.' : 'Change the matched field, or search the list for the existing record.'}';
    } else {
      final lead = keys.isEmpty
          ? 'The new $subject matches an existing record.'
          : 'The new $subject matches an existing record on $keys.';
      body = '$lead It was saved anyway — review the overlap and merge or delete whichever you do not need.';
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: blocked ? AppColors.tintRed : AppColors.tintAmber,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(PhosphorIconsRegular.warning, size: 16.sp, color: accent),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                    blocked
                        ? 'This $subject already exists'
                        : '${subject == 'lead' ? 'Lead' : 'Customer'} created — possible duplicate',
                    style: AppText.bodyStrong(color: accent)),
              ),
            ]),
            SizedBox(height: 6.h),
            Text(body, style: AppText.body()),
            if (!blocked && newLeadId != null && newLeadId!.isNotEmpty)
              _link('Open the new $subject',
                  () => (subject == 'lead' ? onOpenLead : onOpenCustomer)(newLeadId!)),
            if (duplicate.leads.isNotEmpty) ..._group('EXISTING LEADS', duplicate.leads, onOpenLead),
            if (duplicate.customers.isNotEmpty)
              ..._group('EXISTING CUSTOMERS', duplicate.customers, onOpenCustomer),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: AppText.bodyStrong(color: AppColors.navy)),
            SizedBox(width: 4.w),
            Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.navy),
          ]),
        ),
      );

  List<Widget> _group(String title, List<DuplicateMatch> rows, ValueChanged<String> onOpen) => [
        SizedBox(height: 10.h),
        Text(title, style: AppText.caption()),
        for (final r in rows)
          Padding(
            padding: EdgeInsets.only(top: 6.h),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: r.name, style: AppText.bodyStrong()),
                    if (r.email.isNotEmpty) TextSpan(text: ' · ${r.email}', style: AppText.body(color: AppColors.textMuted)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r.id.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onOpen(r.id),
                  child: Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Open', style: AppText.bodyStrong(color: AppColors.navy)),
                      SizedBox(width: 2.w),
                      Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.navy),
                    ]),
                  ),
                ),
            ]),
          ),
      ];
}
