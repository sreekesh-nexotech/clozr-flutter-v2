import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../application/customer_detail_rules.dart';
import '../../domain/entities/view_schema.dart';

/// The mobile list card from the webapp's **View Settings › <module> › Mobile
/// view** (`SchemaMobileViewEditor.tsx`), drawn the same way for every module
/// that uses it (Leads, Customers):
///
/// * header: a 46px initials avatar (+ unread badge), name / company /
///   subtitle on the left, status pill / value / time-ago on the right;
/// * every non-protected visible column as a "label … value" row;
/// * footer above a hairline: up to two assignee avatars with the column's
///   label, and a 40px call button.
///
/// Each slot is picked from the org's `mobile` schema with the webapp's own
/// priority lists and read from the API row ([raw]), so the card follows View
/// Settings. An empty schema (mock mode, or no layout loaded) falls back to
/// the `fallback*` values.
class SchemaMobileCard extends StatelessWidget {
  const SchemaMobileCard({
    super.key,
    required this.name,
    required this.raw,
    required this.schema,
    required this.statusLabel,
    required this.onTap,
    this.onCall,
    this.customFields = const {},
    this.notif = 0,
    this.statusColor,
    this.fallbackCompany = '',
    this.fallbackValue = '',
    this.fallbackTime = '',
    this.fallbackPeople = const [],
    this.mockCell,
  });

  /// The record's protected name column — never configurable away.
  final String name;

  /// The row exactly as the API sent it (trimmed to the `mobile` layout).
  final Map<String, dynamic> raw;

  /// `custom_fields` values, keyed by slug.
  final Map<String, Object?> customFields;

  /// The org's `mobile` column set.
  final ViewSchema schema;

  /// Unread count for the avatar badge; hidden at 0.
  final int notif;

  /// The status name, for a row that carries only an id (or no layout).
  final String statusLabel;

  /// The org's colour for the status — the dot on a status *row*. The header
  /// pill is amber for every status, as on the webapp.
  final Color? statusColor;

  /// Built-in slots for an empty schema.
  final String fallbackCompany;
  final String fallbackValue;
  final String fallbackTime;
  final List<String> fallbackPeople;

  /// Mock mode's value for a row column (there is no API row to read).
  final String? Function(ViewColumn column)? mockCell;

  final VoidCallback onTap;

  /// The call button's action. The webapp's card always draws the button;
  /// for a record with no one to call (a product) leave this null and a tap
  /// falls through to [onTap].
  final VoidCallback? onCall;

  // Webapp tokens (`index.css`).
  static const _text0 = Color(0xFF000000);
  static const _text1 = Color(0xFF1A1A1A);
  static const _text2 = Color(0xFF515151);
  static const _text3 = Color(0xFF717171);
  static const _text4 = Color(0xFF9AA0A6);
  static const _navy = Color(0xFF00113B);
  static const _surfaceMuted = Color(0xFFF1F1F1);
  static const _line = Color(0xFFECECEC);
  static const _danger = Color(0xFFDB1A1A);
  static const _warning = Color(0xFFE8920C);
  static const _warningBg = Color(0xFFFCF0DC);
  static const _secondary = Color(0xFFEBF0F4);

  @override
  Widget build(BuildContext context) {
    final live = schema.isNotEmpty;

    // The first of [names] that is a column of the org's mobile card — the
    // webapp's priority order. Only mobile-schema columns are ever read.
    String? pick(List<String> names) {
      for (final n in names) {
        if (schema.column(n) != null) return n;
      }
      return null;
    }

    final companyCol = pick(const ['organization_name', 'company_name', 'customer_name']);
    final subtitleCol = pick(const ['lead_need', 'requirement', 'title', 'subject', 'product_code']);
    final moneyCol = live
        ? schema.columns
            .map((c) => c.name)
            .where((n) => RegExp('value|amount|price|total').hasMatch(n))
            .firstOrNull
        : null;
    // With no layout (mock mode, or none loaded yet) the built-in slots show.
    final pillCol = live ? pick(const ['status', 'status_name', 'priority', 'lead_source', 'source']) : 'status';
    final timeCol = pick(const ['last_followup_at', 'due_date', 'updated_at', 'created_at']);
    final peopleCol = live ? pick(const ['assignees', 'assigned_to', 'lead_owner']) : 'assignees';

    final company = live ? _nameOf(raw[companyCol]) : fallbackCompany;
    final subtitle = subtitleCol == null || subtitleCol == schema.columns.firstOrNull?.name
        ? ''
        : _nameOf(raw[subtitleCol]);
    final pill = _pillText(pillCol);
    final money = live ? (moneyCol == null ? '' : _money(raw[moneyCol])) : fallbackValue;
    final time = live ? _timeAgo(raw[timeCol]) : fallbackTime;
    final people = live ? _people(raw[peopleCol]) : fallbackPeople;
    final peopleLabel = peopleCol == null ? null : (live ? schema.labelOf(peopleCol, 'Team') : 'Team');

    // Non-protected visible columns, in the org's order — the webapp's
    // toggleable extra rows. The field already drawn as the header pill is
    // not repeated as a row (a task's Status is toggleable, so the webapp's
    // card would show it twice).
    final extras = [for (final c in schema.columns) if (!c.isFixed && c.name != pillCol) c];

    return ClozrCard(
      radius: 12,
      padding: EdgeInsets.all(14.r),
      borderColor: _line,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line1(name, 15, FontWeight.w700, _text0),
                    if (company.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      _line1(company, 13, FontWeight.w400, _text2),
                    ],
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      _line1(subtitle, 12, FontWeight.w400, _text3),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (pill.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
                      decoration: BoxDecoration(color: _warningBg, borderRadius: BorderRadius.circular(6.r)),
                      child: Text(pill, style: AppText.custom(size: 11, weight: FontWeight.w600, color: _warning)),
                    ),
                  if (money.isNotEmpty) ...[
                    SizedBox(height: 5.h),
                    Text(money, style: AppText.custom(size: 14, weight: FontWeight.w700, color: _navy)),
                  ],
                  if (time.isNotEmpty) ...[
                    SizedBox(height: 5.h),
                    Text(time, style: AppText.custom(size: 11, weight: FontWeight.w400, color: _text3)),
                  ],
                ],
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            SizedBox(height: 10.h),
            for (final (i, c) in extras.indexed) ...[
              if (i > 0) SizedBox(height: 5.h),
              _fieldRow(c.label, _cell(c)),
            ],
          ],
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.only(top: 10.h),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            child: Row(
              children: [
                if (peopleLabel != null) ...[
                  _avatarStack(people),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(peopleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12, weight: FontWeight.w400, color: _text3)),
                  ),
                ] else
                  const Spacer(),
                GestureDetector(
                  onTap: onCall,
                  child: Container(
                    width: 40.w,
                    height: 40.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _surfaceMuted, borderRadius: BorderRadius.circular(10.r)),
                    child: Icon(PhosphorIconsRegular.phone, size: 17.sp, color: _navy),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line1(String text, double size, FontWeight weight, Color color) => Text(text,
      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: size, weight: weight, color: color));

  /// The webapp's `fieldRow`: label on the left, value on the right.
  Widget _fieldRow(String label, Widget value) {
    return Row(
      children: [
        Text(label, style: AppText.custom(size: 12, weight: FontWeight.w400, color: _text3)),
        SizedBox(width: 8.w),
        Expanded(child: Align(alignment: Alignment.centerRight, child: value)),
      ],
    );
  }

  /// A row value. Wraps rather than truncating, and folds line breaks and runs
  /// of spaces into one, as the webapp's row (normal HTML white-space) does.
  Widget _text(String s, {Color color = _text1, FontWeight weight = FontWeight.w500}) => Text(
      s.replaceAll(RegExp(r'\s+'), ' ').trim(),
      textAlign: TextAlign.right,
      style: AppText.custom(size: 12, weight: weight, color: color));

  /// One row's value, formatted as the webapp's `renderSchemaCell` does.
  Widget _cell(ViewColumn column) {
    final field = column.name;
    final Object? v;
    if (column.isCustom) {
      v = customFields[column.customKey];
    } else if (raw.isEmpty) {
      // Mock mode: no API row, so read the entity.
      v = mockCell?.call(column);
    } else {
      v = raw[field];
    }
    final empty = _text('—', color: _text4, weight: FontWeight.w400);
    if (_blank(v)) return empty;

    if (field == 'status' || field == 'status_name') {
      final label = _pillText(field);
      if (label.isEmpty) return empty;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(color: _surfaceMuted, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8.w,
              height: 8.w,
              decoration: BoxDecoration(color: statusColor ?? _text3, shape: BoxShape.circle)),
          SizedBox(width: 7.w),
          Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: _text1)),
        ]),
      );
    }

    if (field.contains('value') || field.contains('amount') || field == 'price' || field == 'total_amount' || field == 'revenue') {
      final scalar = v is Map && v.containsKey('value') ? v['value'] : v;
      final n = scalar is num ? scalar : num.tryParse('$scalar');
      if (n != null) return _text(_moneyCompact(n), weight: FontWeight.w600);
    }

    if (field.contains('score')) {
      final n = v is num ? v : num.tryParse('$v');
      if (n != null) {
        final pct = n.clamp(0, 100).toDouble();
        // The lead detail screen's score colours, so a score reads the same
        // on the card as on the record.
        final color = pct >= 75 ? AppColors.success : (pct >= 45 ? AppColors.warningDeep : AppColors.error);
        return Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 72.w,
              height: 6.h,
              color: _surfaceMuted,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(widthFactor: pct / 100, child: Container(color: color)),
            ),
          ),
          SizedBox(width: 9.w),
          Text(_num(n), style: AppText.custom(size: 13, weight: FontWeight.w700, color: color)),
        ]);
      }
    }

    if (v is List) {
      final names = v.map(_nameOf).where((s) => s.isNotEmpty).toList();
      if (names.isEmpty) return _text('${v.length}');
      if (field == 'assignees') return _avatarChips(names);
      return _text(names.join(', '));
    }

    if (field == 'activity' || field == 'last_followup_at') {
      final ago = _timeAgoLong(v);
      return _text(ago.isNotEmpty ? ago : _date(v), color: _text3, weight: FontWeight.w400);
    }
    if (field.endsWith('_at') || field.contains('date') || field == 'valid_until') return _text(_date(v));

    if (v is Map) {
      final n = _nameOf(v);
      return n.isEmpty ? empty : _text(n);
    }

    if (v is String && _uuid.hasMatch(v)) {
      final sibling = raw['${field}_name'];
      return sibling is String && sibling.isNotEmpty ? _text(sibling) : empty;
    }

    if (v is bool) return _text(v ? 'Yes' : 'No');
    return _text(v is num ? _num(v) : '$v');
  }

  static String _num(num n) => n == n.roundToDouble() && n is double ? '${n.toInt()}' : '$n';

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// The webapp's `fmtDate`: `DD-Mon-YYYY`, or the raw text when unparseable.
  static String _date(Object? v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    if (d == null) return '$v';
    return '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';
  }

  /// The webapp's shared `timeAgo`: Just now / Nm / Nh / Yesterday / Nd ago,
  /// then the date.
  static String _timeAgoLong(Object? iso) {
    if (iso is! String || iso.isEmpty) return '';
    final then = DateTime.tryParse(iso);
    if (then == null) return '';
    final mins = DateTime.now().difference(then).inMinutes;
    if (mins < 1) return 'Just now';
    if (mins < 60) return '${mins}m ago';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h ago';
    final days = hours ~/ 24;
    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d ago';
    return _date(iso);
  }

  /// The webapp's `moneyCompact`: ₹1.5L / ₹2Cr / ₹12,000.
  static String _moneyCompact(num n) {
    String trim(num x) => x.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    final abs = n.abs();
    if (abs >= 10000000) return '₹${trim(n / 10000000)}Cr';
    if (abs >= 100000) return '₹${trim(n / 100000)}L';
    return webMoney(n.round());
  }

  Widget _avatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 46.w,
          height: 46.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _surfaceMuted, borderRadius: BorderRadius.circular(12.r)),
          child: Text(_initials(name), style: AppText.custom(size: 15, weight: FontWeight.w700, color: _navy)),
        ),
        if (notif > 0)
          Positioned(
            top: -5.h,
            right: -5.w,
            child: Container(
              constraints: BoxConstraints(minWidth: 18.w),
              height: 18.w,
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text('$notif', style: AppText.custom(size: 10, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
      ],
    );
  }

  /// Up to two overlapping navy initials; a grey user placeholder when nobody
  /// is assigned, as the webapp draws it.
  Widget _avatarStack(List<String> people) {
    final shown = people.isEmpty ? [''] : people.take(2).toList();
    final size = 26.w;
    final step = size - 9.w;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (final (i, p) in shown.indexed)
            Positioned(
              left: step * i,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.isEmpty ? _surfaceMuted : _navy,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: p.isEmpty
                    ? Icon(PhosphorIconsRegular.user, size: 12.sp, color: _text4)
                    : Text(_initials(p), style: AppText.custom(size: 9, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  /// An Assignees *row*: the webapp's `AvatarChips` — up to three overlapping
  /// 28px initials on the light secondary fill, then "+N more".
  Widget _avatarChips(List<String> names) {
    final shown = names.take(3).toList();
    final size = 28.w;
    final step = size - 8.w;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size + step * (shown.length - 1),
          height: size,
          child: Stack(
            children: [
              for (final (i, n) in shown.indexed)
                Positioned(
                  left: step * i,
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _secondary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(_initials(n), style: AppText.custom(size: 10, weight: FontWeight.w700, color: _navy)),
                  ),
                ),
            ],
          ),
        ),
        if (names.length > 3) ...[
          SizedBox(width: 12.w),
          Text('+${names.length - 3} more', style: AppText.custom(size: 12, weight: FontWeight.w400, color: _text3)),
        ],
      ],
    );
  }

  /// The pill reads the `<field>_name` sibling first and never shows a raw id.
  String _pillText(String? col) {
    if (col == null) return '';
    if (schema.isEmpty) return statusLabel;
    final sibling = raw['${col}_name'];
    if (sibling is String && sibling.isNotEmpty) return sibling;
    final text = _nameOf(raw[col]);
    if (_uuid.hasMatch(text)) return col == 'status' ? statusLabel : '';
    return text;
  }

  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  static bool _blank(Object? v) => v == null || v == '' || (v is List && v.isEmpty);

  /// A display name from a string, number or `{full_name/name/label/title}`.
  static String _nameOf(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return '$v';
    if (v is Map) {
      for (final k in const ['full_name', 'name', 'label', 'title']) {
        final s = v[k];
        if (s is String && s.isNotEmpty) return s;
      }
      return '';
    }
    if (v is List) return v.map(_nameOf).where((s) => s.isNotEmpty).join(', ');
    return '$v';
  }

  static List<String> _people(Object? v) {
    if (v is List) return [for (final p in v) _nameOf(p)].where((s) => s.isNotEmpty).toList();
    final one = _nameOf(v);
    return one.isEmpty ? const [] : [one];
  }

  /// The header value. `value_need` arrives as `{value, need}`; the number is
  /// its `value`.
  static String _money(Object? v) {
    final s = v is Map ? v['value'] : v;
    final n = s is num ? s : num.tryParse('${s ?? ''}');
    return n == null || !n.isFinite ? '' : webMoney(n);
  }

  /// The webapp card's `timeAgo`: "5m ago" / "5h ago" / "5d ago".
  static String _timeAgo(Object? iso) {
    if (iso is! String || iso.isEmpty) return '';
    final then = DateTime.tryParse(iso);
    if (then == null) return '';
    final mins = (DateTime.now().difference(then).inSeconds / 60).round().clamp(0, 1 << 31);
    if (mins < 60) return '${mins}m ago';
    final hrs = (mins / 60).round();
    if (hrs < 24) return '${hrs}h ago';
    return '${(hrs / 24).round()}d ago';
  }

  /// First letters of the first two words, as the webapp's `initials()`.
  static String _initials(String name) => name
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0])
      .join()
      .toUpperCase();
}
