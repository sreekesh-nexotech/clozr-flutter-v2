import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/view_schema.dart';
import '../../infrastructure/data_sources/remote/leads_remote_ds.dart';
import 'option_picker_sheet.dart';
import '../sheets/add_sheet_kit.dart';

/// A lead form built from the org's own layout rather than a fixed field list.
///
/// The org decides which fields exist on a lead, in what order and under what
/// labels (`GET /crm/leads/schema/?view_type=detail`), and — because the same
/// config trims the serializer — that layout is also exactly the set the API
/// will *store*. Rendering anything else produces boxes that accept input and
/// silently discard it, which is what the hand-written form did.
///
/// Values are read from and written under the schema's own field names, so a
/// field an admin adds tomorrow appears here with no code change.
class LeadSchemaForm extends ConsumerStatefulWidget {
  const LeadSchemaForm({
    super.key,
    required this.schema,
    required this.row,
  });

  /// The org's detail layout. Only [ViewSchema.editableColumns] are rendered.
  final ViewSchema schema;

  /// The lead's raw record, for prefill. Null/empty for a new lead.
  final Map<String, dynamic>? row;

  @override
  ConsumerState<LeadSchemaForm> createState() => LeadSchemaFormState();
}

class LeadSchemaFormState extends ConsumerState<LeadSchemaForm> {
  /// Text values, one controller per string/number/date column.
  final Map<String, TextEditingController> _text = {};

  /// Id explicitly chosen by the user, per `foreignkey` column. Absent until
  /// they pick one — which is what lets the record's own value show through.
  final Map<String, String?> _choice = {};

  /// Ids explicitly chosen, per `manytomany` column.
  final Map<String, List<String>> _multi = {};

  /// The record's raw value for each choice column, kept **unresolved**.
  ///
  /// The record and the catalogs load independently, and the payload does not
  /// hand back ids consistently (a status arrives as its display name). If the
  /// id were resolved once at seed time it would come out null whenever the
  /// catalog was still in flight, and the field would then save as cleared.
  /// Resolving on demand means a catalog arriving late simply fixes itself.
  final Map<String, Object?> _raw = {};

  /// Whether the record has been copied in yet — one-shot, so a late-arriving
  /// fetch never overwrites typing already in progress.
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(LeadSchemaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The schema and the record arrive independently; seed once both are here.
    if (!_seeded) _seed();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Copies the record into the fields, once.
  void _seed() {
    final columns = widget.schema.editableColumns;
    if (columns.isEmpty) return;
    final row = widget.row;
    // A new lead has no record to wait for; an edit does.
    if (row == null) return;
    _seeded = true;

    for (final c in columns) {
      final raw = row[c.name];
      if (c.isChoice) {
        _raw[c.name] = raw;
      } else {
        _controller(c.name).text = _textOf(raw);
      }
    }
  }

  /// The id currently selected for a choice column — the user's pick if they
  /// made one, otherwise whatever the record holds.
  String? _selectedId(ViewColumn c) => _choice.containsKey(c.name)
      ? _choice[c.name]
      : _idOf(_raw[c.name], _optionsFor(c));

  List<String> _selectedIds(ViewColumn c) =>
      _multi[c.name] ?? _idsOf(_raw[c.name], _optionsFor(c));

  TextEditingController _controller(String name) =>
      _text.putIfAbsent(name, TextEditingController.new);

  /// The payload for `POST`/`PATCH`: every rendered field, under the name the
  /// API stores it as.
  ///
  /// Blank values are kept rather than dropped — the form was prefilled from
  /// the record, so an emptied box means "clear this".
  Map<String, dynamic> get payload {
    final out = <String, dynamic>{};
    for (final c in widget.schema.editableColumns) {
      final key = LeadsRemoteDataSource.writeKeyFor(c);
      switch (c.type) {
        case 'foreignkey':
          // An id that no longer matches a catalog option is a value we could
          // not resolve — a display name the catalog has not loaded yet, most
          // often. Omitting the key leaves the field untouched; sending the
          // unresolved value would either 400 or overwrite it with rubbish.
          final id = _writeId(c, _known(c, _selectedId(c)));
          // Omitted rather than sent as null: null *clears* the field, and a
          // value we could not resolve is not an instruction to clear it.
          if (id != null) out[key] = id;
        case 'manytomany':
          out[key] = [
            for (final id in _selectedIds(c))
              if (_writeId(c, _known(c, id)) != null) _writeId(c, _known(c, id)),
          ];
        case 'boolean':
          out[key] = _controller(c.name).text.trim().toLowerCase() == 'yes';
        default:
          out[key] = _controller(c.name).text.trim();
      }
    }
    return out;
  }

  /// [id] if it is one this column's catalog actually offers, else null.
  ///
  /// An empty catalog answers null for everything — with nothing to check
  /// against, the safe move is to leave the field alone rather than guess.
  String? _known(ViewColumn c, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final o in _optionsFor(c)) {
      if (o.id == id) return id;
    }
    return null;
  }

  /// The `'me'` sentinel is a client-side convenience; the API needs the uuid.
  String? _writeId(ViewColumn c, String? id) =>
      c.relatedModel == 'User' ? UserDirectory.realUserId(id) : id;

  /// The catalog backing a choice column, picked by the model it points at.
  List<CatalogOption> _optionsFor(ViewColumn c) {
    switch (c.relatedModel) {
      case 'LeadStatus':
        return ref.read(leadStatusesProvider);
      case 'LeadSource':
        return ref.read(leadSourcesProvider);
      case 'Territory':
        return ref.read(territoryOptionsProvider);
      case 'Industry':
        return ref.read(industryOptionsProvider);
      case 'Product':
        return ref.read(productOptionsProvider);
      case 'Team':
        return ref.read(teamOptionsProvider);
      case 'User':
        return [
          for (final u in ref.read(rosterProvider))
            CatalogOption(id: u.id, name: u.name),
        ];
      default:
        return const [];
    }
  }

  // ── reading values out of the record ──

  static String _textOf(Object? raw) {
    if (raw == null) return '';
    if (raw is bool) return raw ? 'Yes' : 'No';
    if (raw is Map) return (raw['name'] ?? '').toString();
    return raw.toString();
  }

  /// The option id a record value refers to.
  ///
  /// The payload is not consistent about this: a source arrives as a nested
  /// object, a status as its **display name**, and some fields as a bare id.
  /// All three have to resolve to the same thing — the id the picker selects.
  static String? _idOf(Object? raw, List<CatalogOption> options) {
    if (raw == null) return null;

    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key.toString();
        if ((k.endsWith('_id') || k == 'id') && entry.value != null) {
          return entry.value.toString();
        }
      }
      // No id on the object — fall back to matching its name.
      return _byName((raw['name'] ?? '').toString(), options);
    }

    final s = raw.toString();
    if (s.isEmpty) return null;
    // A value that matches a known option id is already what we want; anything
    // else is a display name to look up. Deliberately **not** falling back to
    // the raw string: `status` arrives as "Qualified", and writing that to
    // `status_id` is a 400.
    for (final o in options) {
      if (o.id == s) return s;
    }
    return _byName(s, options);
  }

  static List<String> _idsOf(Object? raw, List<CatalogOption> options) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final id = _idOf(item, options);
      if (id != null && id.isNotEmpty) out.add(id);
    }
    return out;
  }

  static String? _byName(String name, List<CatalogOption> options) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final o in options) {
      if (o.name.trim().toLowerCase() == needle) return o.id;
    }
    return null;
  }

  String _labelForId(ViewColumn c, String? id) {
    if (id == null || id.isEmpty) return '';
    for (final o in _optionsFor(c)) {
      if (o.id == id) return o.name;
    }
    return '';
  }

  // ── pickers ──

  Future<void> _pickOne(ViewColumn c) async {
    final picked = await showOptionPicker(
      context: context,
      title: c.label,
      options: _optionsFor(c),
      selected: {if (_selectedId(c) != null) _selectedId(c)!},
      emptyNote: 'No ${c.label.toLowerCase()} options are configured for this '
          'organisation yet.',
    );
    // Dismissed without choosing — leave the field as it was.
    if (picked == null || !mounted) return;
    setState(() => _choice[c.name] = picked.isEmpty ? null : picked.first);
  }

  Future<void> _pickMany(ViewColumn c) async {
    final picked = await showOptionPicker(
      context: context,
      title: c.label,
      options: _optionsFor(c),
      selected: {..._selectedIds(c)},
      multi: true,
      emptyNote: 'No ${c.label.toLowerCase()} options are configured for this '
          'organisation yet.',
    );
    if (picked == null || !mounted) return;
    setState(() => _multi[c.name] = picked.toList());
  }

  // ── rendering ──

  @override
  Widget build(BuildContext context) {
    // Watched so a catalog resolving after the first paint re-renders the
    // pickers with real names instead of blanks.
    ref.watch(leadStatusCatalogProvider);
    ref.watch(leadSourceCatalogProvider);
    ref.watch(territoryCatalogProvider);
    ref.watch(industryCatalogProvider);
    if (!_seeded) _seed();

    final columns = widget.schema.editableColumns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in columns) ...[
          _field(c),
          SizedBox(height: 14.h),
        ],
      ],
    );
  }

  Widget _field(ViewColumn c) {
    switch (c.type) {
      case 'foreignkey':
        return AppTextField(
          label: c.label,
          readOnly: true,
          value: _labelForId(c, _selectedId(c)),
          hint: 'Select ${c.label.toLowerCase()}…',
          suffixIcon: PhosphorIconsRegular.caretDown,
          onTap: () => _pickOne(c),
        );

      case 'manytomany':
        final names = [
          for (final id in _selectedIds(c))
            if (_labelForId(c, id).isNotEmpty) _labelForId(c, id),
        ];
        return AppTextField(
          label: c.label,
          readOnly: true,
          value: names.join(', '),
          hint: 'Select ${c.label.toLowerCase()}…',
          suffixIcon: PhosphorIconsRegular.caretDown,
          onTap: () => _pickMany(c),
        );

      case 'boolean':
        final on = _controller(c.name).text.trim().toLowerCase() == 'yes';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetFieldLabel(c.label),
            Wrap(
              spacing: 8.w,
              children: [
                for (final v in const ['Yes', 'No'])
                  SelectChip(
                    label: v,
                    selected: (v == 'Yes') == on,
                    onTap: () => setState(() => _controller(c.name).text = v),
                  ),
              ],
            ),
          ],
        );

      case 'decimal':
      case 'integer':
      case 'number':
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        );

      case 'date':
      case 'datetime':
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          hint: 'YYYY-MM-DD',
        );

      default:
        return AppTextField(
          label: c.label,
          required: c.isFixed,
          controller: _controller(c.name),
          hint: 'Enter ${c.label.toLowerCase()}…',
        );
    }
  }
}
