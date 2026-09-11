import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/utils/phone_rules.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/phone_controller.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../application/record_rows.dart';
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
    this.optionsByColumn = const {},
    this.writeKey,
    this.writeMulti,
  });

  /// The org's detail layout. Only [ViewSchema.editableColumns] are rendered.
  final ViewSchema schema;

  /// The lead's raw record, for prefill. Null/empty for a new lead.
  final Map<String, dynamic>? row;

  /// Options for columns whose catalog the schema cannot name.
  ///
  /// A `foreignkey` column says which model it points at, so its catalog is
  /// resolvable. A plain `string` column that is really a choice does not —
  /// a follow-up's `task_type` is stored as text but must be one of the org's
  /// follow-up types. Supplying options here renders such a column as a picker
  /// instead of a free-text box, and the picked **name** is what gets written.
  final Map<String, List<CatalogOption>> optionsByColumn;

  /// The API key a column is written under, when it differs from the column
  /// name. Defaults to the Lead mapping, which renames `status` to `status_id`.
  ///
  /// Pluggable because the modules disagree: a **customer** writes its status as
  /// plain `status` (verified against a live org — `{status: <uuid>}` is
  /// accepted), so reusing the Lead mapping here would post `status_id` and have
  /// it silently ignored.
  final String Function(ViewColumn column)? writeKey;

  /// The value a `manytomany` column is written as, given the chosen ids.
  /// Defaults to the bare id list, which is what `assignees` wants.
  ///
  /// Pluggable because the shape is per-field, not per-type: a customer's
  /// `products` is a list of **objects** (`{product_id, quantity}`), and posting
  /// bare ids there is a 400 — *"Expected a dictionary, but got str"*.
  final Object? Function(ViewColumn column, List<String> ids)? writeMulti;

  @override
  ConsumerState<LeadSchemaForm> createState() => LeadSchemaFormState();
}

class LeadSchemaFormState extends ConsumerState<LeadSchemaForm> {
  /// Text values, one controller per string/number/date column.
  final Map<String, TextEditingController> _text = {};

  /// Country + national-digits state, one per phone column (`mobile_no`,
  /// `whatsapp_no`) — kept separate from [_text] since a phone box carries a
  /// selected country alongside its digits, not just a string.
  final Map<String, PhoneController> _phone = {};

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
    for (final c in _phone.values) {
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
      if (_isPhoneColumn(c)) {
        _phoneController(c.name).setPendingSeed(raw?.toString());
      } else if (c.isChoice) {
        _raw[c.name] = raw;
      } else {
        _controller(c.name).text = _textOf(raw);
      }
    }
  }

  /// `mobile_no` / `whatsapp_no` (Lead) and `phone` (Customer) — every
  /// contact-number column this shared form is asked to render, across the
  /// modules that reuse it. Each rendered as a country-code phone field
  /// instead of a plain text box, regardless of the generic `type: 'string'`
  /// the schema reports them as. Customer's own schema names its column
  /// `phone`, not `mobile_no` — confirmed against a live
  /// `GET /crm/customers/schema/?view_type=detail` response — so both names
  /// have to be recognised here for the two modules to behave alike.
  bool _isPhoneColumn(ViewColumn c) =>
      c.name == 'mobile_no' || c.name == 'whatsapp_no' || c.name == 'phone';

  PhoneController _phoneController(String name) =>
      _phone.putIfAbsent(name, PhoneController.new);

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
      final key = widget.writeKey?.call(c) ?? LeadsRemoteDataSource.writeKeyFor(c);
      if (_isPhoneColumn(c)) {
        // Omitted rather than sent as null when blank: the field-emptied-vs-
        // never-touched distinction other columns lean on `schemaWriteValue`
        // for doesn't apply the same way here — a blank optional phone box
        // (whatsapp_no) omitting the key is the safer default than clearing
        // a number the record already had, should a prefill race leave it
        // looking empty for a frame.
        final value = _phoneController(c.name).toE164();
        if (value != null) out[key] = value;
        continue;
      }
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
          final ids = <String>[
            for (final id in _selectedIds(c))
              if (_writeId(c, _known(c, id)) != null) _writeId(c, _known(c, id))!,
          ];
          out[key] = widget.writeMulti?.call(c, ids) ?? ids;
        case 'boolean':
          out[key] = _controller(c.name).text.trim().toLowerCase() == 'yes';
        default:
          // Typed coercion lives in `schemaWriteValue` — a number field's box
          // has to be sent as a number, and an empty one as null rather than
          // `""`, which the API rejects outright.
          final text = _choiceValue(c, _controller(c.name).text);
          final value = schemaWriteValue(c.type, text);
          if (!identical(value, absentValue)) out[key] = value;
      }
    }
    return out;
  }

  /// Friendly, field-level validation the schema itself does not encode.
  ///
  /// `is_fixed` covers most org-mandated boxes, but two gaps are hard API
  /// requirements no flag names: `first_name` (written from `lead_name`) is
  /// required on every create regardless of the org's layout, and a contact
  /// number the org bothered to configure should be a real one. Left
  /// unchecked, both used to surface only after a round trip, as the
  /// backend's raw `"first_name: This field is required."` / `"Enter a valid
  /// phone number (at least 7 digits)."`.
  ///
  /// Returns one message per problem field, in schema order, so a caller can
  /// show the first or all of them.
  List<String> validate() {
    final errors = <String>[];
    for (final c in widget.schema.editableColumns) {
      if (_isPhoneColumn(c)) {
        final phone = _phoneController(c.name);
        final required = c.isFixed || c.name == 'mobile_no';
        if (required && phone.isBlank) {
          errors.add('${c.label} is required');
        } else if (!phone.isBlank && !phone.isComplete) {
          errors.add('${c.label}: ${phoneDigitsMessage(phone.rule)}');
        }
        continue;
      }
      final required = c.isFixed || c.name == 'lead_name';
      if (required && _isBlank(c)) {
        errors.add('${c.label} is required');
      }
    }
    return errors;
  }

  bool _isBlank(ViewColumn c) {
    switch (c.type) {
      case 'foreignkey':
        return _selectedId(c) == null;
      case 'manytomany':
        return _selectedIds(c).isEmpty;
      default:
        return _controller(c.name).text.trim().isEmpty;
    }
  }

  /// The stored value for a **model choice** column, given what the box shows.
  ///
  /// The picker leaves the human label in the field — which is right for a
  /// caller-supplied catalog, where the API stores the name it is given — but a
  /// model choice is validated against its `value` (`days`, not `Days`). So the
  /// label is resolved back here rather than at pick time, which keeps the field
  /// readable and the payload correct.
  ///
  /// Anything that matches no choice is passed through untouched: the server is
  /// the authority on its own value set, and rewriting an unrecognised entry
  /// would only hide the error it is about to return.
  String _choiceValue(ViewColumn c, String text) {
    if (!c.hasChoices) return text;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;
    for (final (value, label) in c.choices) {
      if (label == trimmed || value == trimmed) return value;
    }
    return text;
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

  /// The catalog backing a choice column: a caller's override first, then the
  /// model the column points at.
  List<CatalogOption> _optionsFor(ViewColumn c) {
    final override = widget.optionsByColumn[c.name];
    if (override != null) return override;
    // The field's own model choices, when the schema reported them. Ahead of the
    // related-model switch below because a choice field has no related model.
    if (c.hasChoices) {
      return [
        for (final (value, label) in c.choices)
          CatalogOption(id: value, name: label),
      ];
    }
    switch (c.relatedModel) {
      case 'LeadStatus':
        return ref.read(leadStatusesProvider);
      case 'CRMTaskStatus':
        return ref.read(taskStatusOptionsProvider);
      case 'TaskPriority':
        return ref.read(taskPriorityOptionsProvider);
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

  /// Picks a value for a text column whose options the caller supplied. The
  /// **name** is written, not an id — the API stores this one as text.
  Future<void> _pickTextChoice(ViewColumn c) async {
    final options = _optionsFor(c);
    final current = _controller(c.name).text.trim();
    final picked = await showOptionPicker(
      context: context,
      title: c.label,
      options: options,
      // Matched on either side: a record seeds the box with the stored value
      // (`days`), a previous pick leaves the label (`Days`), and both have to
      // pre-select the same row.
      selected: {
        for (final o in options)
          if (o.name == current || o.id == current) o.id,
      },
      emptyNote: 'No ${c.label.toLowerCase()} options are configured for this '
          'organisation yet.',
    );
    if (picked == null || !mounted) return;
    final name = picked.isEmpty
        ? ''
        : options.firstWhere((o) => o.id == picked.first).name;
    setState(() => _controller(c.name).text = name);
  }

  /// A date (or date+time) column. Picked, never typed: the box's text is sent
  /// to the API verbatim, so a hand-typed "24/6/26" is a 400 — and the column
  /// is usually a due date, which is exactly what a calendar is for.
  Widget _dateField(ViewColumn c, {required bool withTime}) {
    final current = DateTime.tryParse(_controller(c.name).text.trim());
    return AppTextField(
      label: c.label,
      readOnly: true,
      value: current == null
          ? null
          : withTime
              ? '${sheetDateLabel(current)} · ${sheetTimeLabel(TimeOfDay.fromDateTime(current))}'
              : sheetDateLabel(current),
      hint: 'Select ${c.label.toLowerCase()}…',
      suffixIcon: PhosphorIconsRegular.calendarBlank,
      onTap: () => _pickDate(c, withTime: withTime),
    );
  }

  Future<void> _pickDate(ViewColumn c, {required bool withTime}) async {
    final ctrl = _controller(c.name);
    final current = DateTime.tryParse(ctrl.text.trim());
    final day = await pickSheetDate(context, ctrl.text);
    if (day == null || !mounted) return;
    if (!withTime) {
      setState(() => ctrl.text = sheetIsoDate(day));
      return;
    }
    // A datetime column needs both halves, so the time picker follows. Skipping
    // it means midnight rather than discarding the date just chosen.
    final picked = await pickSheetTime(
        context, current == null ? '' : sheetTimeLabel(TimeOfDay.fromDateTime(current)));
    if (!mounted) return;
    final time = picked ?? const TimeOfDay(hour: 0, minute: 0);
    setState(() => ctrl.text = '${sheetIsoDate(day)}T${sheetTimeLabel(time)}:00');
  }

  Widget _timeField(ViewColumn c) {
    return AppTextField(
      label: c.label,
      readOnly: true,
      value: sheetTimeText(_controller(c.name).text),
      hint: 'Select ${c.label.toLowerCase()}…',
      suffixIcon: PhosphorIconsRegular.clock,
      onTap: () => _pickTime(c),
    );
  }

  Future<void> _pickTime(ViewColumn c) async {
    final ctrl = _controller(c.name);
    final picked = await pickSheetTime(context, ctrl.text);
    if (picked == null || !mounted) return;
    setState(() => ctrl.text = sheetTimeLabel(picked));
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

  /// Whether this column is a picker despite being typed as plain text.
  ///
  /// True when the caller supplied options **or** the schema reported the field's
  /// own model choices. The latter matters: a choice field with no picker renders
  /// as a free-text box, and anything typed into it is rejected — the API
  /// validates against the value set (`"23" is not a valid choice`).
  bool _isTextChoice(ViewColumn c) =>
      c.type != 'foreignkey' &&
      c.type != 'manytomany' &&
      (widget.optionsByColumn.containsKey(c.name) || c.hasChoices);

  Widget _field(ViewColumn c) {
    if (_isPhoneColumn(c)) {
      return PhoneInputField(
        label: c.label,
        controller: _phoneController(c.name),
        required: c.isFixed || c.name == 'mobile_no',
        hint: 'Enter ${c.label.toLowerCase()}…',
        onChanged: () => setState(() {}),
      );
    }
    if (_isTextChoice(c)) {
      return AppTextField(
        label: c.label,
        readOnly: true,
        value: _controller(c.name).text,
        hint: 'Select ${c.label.toLowerCase()}…',
        suffixIcon: PhosphorIconsRegular.caretDown,
        onTap: () => _pickTextChoice(c),
      );
    }
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
        return _dateField(c, withTime: false);

      case 'datetime':
        return _dateField(c, withTime: true);

      case 'time':
        return _timeField(c);

      // Long-form prose (a follow-up's description). A single-line box would
      // hide most of what is already stored in it.
      case 'text':
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          multiline: true,
          hint: 'Enter ${c.label.toLowerCase()}…',
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
