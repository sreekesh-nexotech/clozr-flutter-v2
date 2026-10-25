import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../application/providers/leads_providers.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/domain/entities/acc_masters.dart';

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
    this.diffAgainstRow = false,
    this.includeCustomFields = false,
    this.hiddenColumns = const {},
    this.initialChoices = const {},
    this.alwaysSendCustomBooleans = false,
    this.onValueChanged,
    this.mobileRequired = true,
    this.requiredOnly,
    this.webAddLeadForm = false,
    this.hints = const {},
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

  /// Whether [LeadSchemaFormState.payload] should carry **only the fields the
  /// user actually changed**, measured against [row].
  ///
  /// Off by default, and deliberately opt-in rather than inferred from `row`
  /// being non-null: the add-lead screen passes `row: {}` for a brand-new
  /// record, so "has a row" does not mean "is an edit". A create wants every
  /// box it rendered, an edit wants the difference.
  ///
  /// With it on, an untouched form yields an empty payload — which is what
  /// lets a caller say "Nothing to save" instead of posting a no-op PATCH that
  /// rewrites every configured column.
  final bool diffAgainstRow;

  /// Also render the org's custom fields and write them as
  /// `custom_fields: {<slug>: value}` (the lead form, like the webapp's).
  final bool includeCustomFields;

  /// Columns not rendered at all (a task's `committed_due_date` on create).
  final Set<String> hiddenColumns;

  /// The id a choice column starts on when creating (the org's default
  /// status / priority), until the user picks.
  final Map<String, String> initialChoices;

  /// Webapp task form: a custom boolean is always sent, unticked as false.
  final bool alwaysSendCustomBooleans;

  /// Told after a picker or date changes a value (the task form watches its
  /// type and due date).
  final VoidCallback? onValueChanged;

  /// Whether `mobile_no` is required even when the org has not fixed it. A
  /// lead needs a contact number; a customer (webapp Add customer) needs only
  /// its name.
  final bool mobileRequired;

  /// When set, exactly these columns are required (and starred) — nothing the
  /// schema flags `is_fixed` adds to it. The customer forms pass `{'name'}`:
  /// on web only the name is required, while the customer schema marks the
  /// SLA columns fixed, which made the form refuse to save without them.
  final Set<String>? requiredOnly;

  /// Webapp Add lead (`toLeadCreateForm` + `addLeadFields`): the org's layout
  /// plus Lead owner / Assignees / Team when the layout hides one, and the
  /// "Contact name" / "Contact phone" / "WhatsApp number" labels.
  final bool webAddLeadForm;

  /// Placeholder overrides by column (webapp Add customer: the name's
  /// "e.g. Acme Retail Pvt Ltd"); others keep "Enter <label>…".
  final Map<String, String> hints;

  bool _isRequiredCol(ViewColumn c, bool fallback) =>
      requiredOnly == null ? fallback : requiredOnly!.contains(c.name);

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

  /// What [_seed] put into the text and phone fields, kept so a later read can
  /// tell an edited box from an untouched one. Choice columns need no entry:
  /// `_choice`/`_multi` are only populated when the user picks something, and
  /// the record's own value stays readable through `_raw`.
  final Map<String, String> _seededText = {};
  final Map<String, String?> _seededPhone = {};

  /// Inline error per column name — the webapp shows field errors under the
  /// input they belong to, its own checks and the server's alike.
  final Map<String, String> _errors = {};

  /// One key per rendered column, so the first error can be scrolled to.
  final Map<String, GlobalKey> _fieldKeys = {};

  /// Webapp "WhatsApp same as phone": off by default; while on, the WhatsApp
  /// box mirrors the contact phone and is not editable.
  bool _whatsappSame = false;

  /// Quantity typed per selected product (blank means 1), for a lead's
  /// `products` — sent as `{product_id, quantity}` like the webapp.
  final Map<String, TextEditingController> _qty = {};

  List<ViewColumn> get _columns {
    final lead = widget.schema.column('lead_name') != null;
    final cols = [
      for (final c in widget.includeCustomFields ? widget.schema.formColumns : widget.schema.editableColumns)
        if (!widget.hiddenColumns.contains(c.name) && !(lead && neverLeadInputs(c.name))) c,
    ];
    if (!widget.webAddLeadForm) return cols;
    var order = cols.fold<int>(0, (m, c) => c.order > m ? c.order : m);
    for (final extra in addLeadAssignmentColumns) {
      if (!cols.any((c) => c.name == extra.name)) cols.add(extra.withOrder(++order));
    }
    return [for (final c in cols) c.withLabel(addLeadLabel(c.name) ?? c.label)];
  }

  /// Lead columns the webapp never renders as inputs, whatever the org's
  /// layout shows: the consent stamp (written by web-form intake only), the
  /// call telemetry (`CALL_STAT_KEYS`, read-only) and the dial-code
  /// companions (each phone input carries its own picker).
  static bool neverLeadInputs(String name) =>
      const {
        'consent_captured_at',
        'consent_notice_version',
        'last_call_at',
        'last_call_outcome',
        'consecutive_unanswered_calls',
        'calls_last_7d',
      }.contains(name) ||
      name.endsWith('_country_code');

  /// Webapp `ASSIGNMENT_FIELDS`: always on the Add lead form.
  static const addLeadAssignmentColumns = [
    ViewColumn(name: 'lead_owner', label: 'Lead owner', order: 0, type: 'foreignkey', inFields: true, relatedModel: 'User'),
    ViewColumn(name: 'assignees', label: 'Assignees', order: 0, type: 'manytomany', inFields: true, relatedModel: 'User'),
    ViewColumn(name: 'assigned_team', label: 'Team', order: 0, type: 'foreignkey', inFields: true, relatedModel: 'Team'),
  ];

  /// Webapp Add lead labels (LD-15).
  static String? addLeadLabel(String name) => switch (name) {
        'lead_name' => 'Contact name',
        'mobile_no' => 'Contact phone',
        'whatsapp_no' => 'WhatsApp number',
        _ => null,
      };

  static const unassignedOwner = '__unassigned__';
  static const noneOption = '__none__';
  static const indianMobileMessage =
      'Enter a 10-digit Indian mobile number starting with 6, 7, 8 or 9.';
  static const quantityMessage = 'Quantity must be more than 0, with at most 3 decimals.';

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
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Copies the record into the fields, once.
  void _seed() {
    final columns = _columns;
    if (columns.isEmpty) return;
    final row = widget.row;
    // A new lead has no record to wait for; an edit does.
    if (row == null) return;
    _seeded = true;

    final custom = row['custom_fields'] is Map ? row['custom_fields'] as Map : const {};
    for (final c in columns) {
      final raw = c.isCustom ? custom[c.customKey] : row[c.name];
      if (_isPhoneColumn(c)) {
        _phoneController(c.name).setPendingSeed(raw?.toString());
        _seededPhone[c.name] = raw?.toString();
      } else if (c.isChoice) {
        _raw[c.name] = raw;
        if (_isProducts(c) && raw is List) {
          for (final p in raw) {
            if (p is Map && p['product_id'] != null && p['quantity'] != null) {
              _qtyController('${p['product_id']}').text = _trimQty('${p['quantity']}');
            }
          }
        }
      } else {
        _controller(c.name).text = _textOf(raw);
        _seededText[c.name] = _controller(c.name).text;
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

  TextEditingController _qtyController(String productId) =>
      _qty.putIfAbsent(productId, TextEditingController.new);

  /// "1.000" → "1": the record pads quantities to three places.
  static String _trimQty(String q) {
    if (!q.contains('.')) return q;
    final t = q.replaceAll(RegExp(r'0+$'), '');
    return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
  }

  bool _isProducts(ViewColumn c) => c.name == 'products' && c.relatedModel == 'Product';
  bool _isOwner(ViewColumn c) => c.name == 'lead_owner' && c.relatedModel == 'User';
  bool get _isCreate => !widget.diffAgainstRow;

  bool get _hasBothPhones {
    final names = {for (final c in _columns) c.name};
    return names.contains('mobile_no') && names.contains('whatsapp_no');
  }

  /// Webapp `indianMobileProblem`: only a +91 number is checked, and its
  /// national part must be ten digits starting 6–9.
  static bool _indianMobileOk(PhoneController p) {
    if (p.iso2 != 'IN') return true;
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(p.digits.text.replaceAll(RegExp(r'\D'), ''));
  }

  /// Puts [errors] (column or API key → message) under their inputs and
  /// scrolls to the first one. API keys are folded onto the column they
  /// came from: `status_id` → `status`, `*_country_code` → the number,
  /// `first_name`/`last_name` → `lead_name`.
  void showErrors(Map<String, String> errors) {
    final columns = {for (final c in _columns) c.name};
    String? colFor(String key) {
      if (columns.contains(key)) return key;
      if (key == 'status_id' && columns.contains('status')) return 'status';
      if (key.endsWith('_country_code')) {
        final n = key.replaceFirst('_country_code', '_no');
        if (columns.contains(n)) return n;
      }
      if ((key == 'first_name' || key == 'last_name') && columns.contains('lead_name')) return 'lead_name';
      if (columns.contains('custom_fields.$key')) return 'custom_fields.$key';
      return null;
    }

    setState(() {
      _errors.clear();
      for (final e in errors.entries) {
        final col = colFor(e.key);
        if (col != null) _errors.putIfAbsent(col, () => e.value);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in _columns) {
        if (!_errors.containsKey(c.name)) continue;
        final ctx = _fieldKeys[c.name]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
        }
        break;
      }
    });
  }

  /// The current text of a plain or text-choice column (`task_type` gives the
  /// picked label, `due_date` the ISO date).
  String valueOf(String name) => _controller(name).text;

  /// Whether any server error key landed under an input.
  bool hasInlineError(String key) =>
      _errors.containsKey(key) ||
      (key == 'status_id' && _errors.containsKey('status')) ||
      ((key == 'first_name' || key == 'last_name') && _errors.containsKey('lead_name'));

  /// The id currently selected for a choice column — the user's pick if they
  /// made one, otherwise whatever the record holds.
  String? _selectedId(ViewColumn c) {
    if (_choice.containsKey(c.name)) return _choice[c.name];
    if (_isCreate && widget.initialChoices[c.name] != null) return widget.initialChoices[c.name];
    if (_isOwner(c)) {
      // A new lead starts as mine (webapp pre-fills me); a record with no
      // owner reads as Unassigned.
      final raw = _raw[c.name];
      if (raw == null) return _isCreate ? 'me' : unassignedOwner;
      final id = raw is Map ? raw['user_id']?.toString() : raw.toString();
      return id == null || id.isEmpty ? unassignedOwner : UserDirectory.mapUserId(id);
    }
    return _idOf(_raw[c.name], _optionsFor(c));
  }

  List<String> _selectedIds(ViewColumn c) =>
      _multi[c.name] ?? _idsOf(_raw[c.name], _optionsFor(c));

  TextEditingController _controller(String name) =>
      _text.putIfAbsent(name, TextEditingController.new);

  /// Whether [c] now holds something other than what the record seeded it with.
  ///
  /// Choice columns compare **resolved ids**, not the raw record value, and
  /// against the same fallback `_selectedId`/`_selectedIds` read through — so
  /// re-picking the value that was already set reads as unchanged, and a
  /// catalog arriving late does not register as an edit on its own.
  bool _isChanged(ViewColumn c) {
    if (c.name == 'whatsapp_no' && _whatsappSame) return true;
    if (_isProducts(c)) {
      final raw = _raw[c.name];
      final was = <String, String>{
        if (raw is List)
          for (final p in raw)
            if (p is Map && p['product_id'] != null) '${p['product_id']}': _trimQty('${p['quantity'] ?? '1'}'),
      };
      final now = <String, String>{
        for (final id in _selectedIds(c))
          id: _qtyController(id).text.trim().isEmpty ? '1' : _qtyController(id).text.trim(),
      };
      return was.length != now.length || now.entries.any((e) => was[e.key] != e.value);
    }
    if (_isPhoneColumn(c)) {
      final seeded = _seededPhone[c.name];
      final now = _phoneController(c.name).toE164();
      // A prefill race can leave the box briefly empty; that is not an edit.
      if (now == null) return false;
      return now != seeded;
    }
    switch (c.type) {
      case 'foreignkey':
        if (_isOwner(c)) return _choice.containsKey(c.name);
        return _selectedId(c) != _idOf(_raw[c.name], _optionsFor(c));
      case 'manytomany':
        final now = _selectedIds(c).toSet();
        final was = _idsOf(_raw[c.name], _optionsFor(c)).toSet();
        return now.length != was.length || !now.containsAll(was);
      default:
        return _controller(c.name).text != (_seededText[c.name] ?? '');
    }
  }

  /// The payload for `POST`/`PATCH`: every rendered field, under the name the
  /// API stores it as.
  ///
  /// Blank values are kept rather than dropped — the form was prefilled from
  /// the record, so an emptied box means "clear this".
  Map<String, dynamic> get payload {
    final out = <String, dynamic>{};
    final diffing = widget.diffAgainstRow && _seeded;
    final customChanged = _columns.any((c) => c.isCustom && (!diffing || _isChanged(c)));
    for (final c in _columns) {
      // Collected into one `custom_fields` object below.
      if (c.isCustom) continue;
      // An untouched field is not an instruction. Sending it anyway rewrote
      // every configured column on every save, and made an empty payload —
      // the caller's "nothing changed" signal — unreachable.
      if (diffing && !_isChanged(c)) continue;
      final key = widget.writeKey?.call(c) ?? LeadsRemoteDataSource.writeKeyFor(c);
      if (_isPhoneColumn(c)) {
        // Omitted rather than sent as null when blank: the field-emptied-vs-
        // never-touched distinction other columns lean on `schemaWriteValue`
        // for doesn't apply the same way here — a blank optional phone box
        // (whatsapp_no) omitting the key is the safer default than clearing
        // a number the record already had, should a prefill race leave it
        // looking empty for a frame.
        final source = c.name == 'whatsapp_no' && _whatsappSame ? 'mobile_no' : c.name;
        final value = _phoneController(source).toE164();
        if (value != null) out[key] = value;
        continue;
      }
      if (_isOwner(c)) {
        final picked = _selectedId(c);
        // Webapp: Unassigned is an explicit null; "me" on a create is left to
        // the server, which makes the creator the owner.
        if (picked == unassignedOwner) {
          out[key] = null;
        } else if (picked != null && !(_isCreate && picked == 'me')) {
          final id = UserDirectory.realUserId(picked);
          if (id != null) out[key] = id;
        }
        continue;
      }
      if (_isProducts(c)) {
        out[key] = [
          for (final id in _selectedIds(c))
            if (_known(c, id) != null)
              {
                'product_id': id,
                'quantity': _qtyController(id).text.trim().isEmpty ? '1' : _qtyController(id).text.trim(),
              },
        ];
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
          // value we could not resolve is not an instruction to clear it —
          // unless the user explicitly picked "No territory" on an edit.
          if (id != null) {
            out[key] = id;
          } else if (diffing && _choice.containsKey(c.name) && _choice[c.name] == null) {
            out[key] = null;
          }
        case 'manytomany':
          var ids = <String>[
            for (final id in _selectedIds(c))
              if (_writeId(c, _known(c, id)) != null) _writeId(c, _known(c, id))!,
          ];
          final owner = c.name == 'assignees' && widget.optionsByColumn.containsKey('assignees') ? _ownerOf() : null;
          if (owner != null) {
            // Webapp: assignees = [owner, ...extras]; the owner is always one.
            ids = [owner, ...ids.where((i) => i != owner)];
            if (ids.length == 1 && _isCreate) continue;
          }
          out[key] = widget.writeMulti?.call(c, ids) ?? ids;
        case 'boolean':
          // Webapp tri-state: Yes / No / blank (unknown), and a blank is left
          // out of a create rather than written as No.
          final b = _boolValue(c);
          if (b != null || !_isCreate) out[key] = b;
        default:
          // Typed coercion lives in `schemaWriteValue` — a number field's box
          // has to be sent as a number, and an empty one as null rather than
          // `""`, which the API rejects outright.
          final text = _choiceValue(c, _controller(c.name).text);
          final value = switch (_dealKind(c)) {
            _DealKind.money => _moneyValue(text),
            _DealKind.gstin => _gstin(text).isEmpty ? null : _gstin(text),
            _ => schemaWriteValue(c.type, text),
          };
          if (identical(value, absentValue)) continue;
          // Webapp: a blank optional field is simply not sent on a create.
          if (_isCreate && (value == null || value == '')) continue;
          out[key] = value;
      }
    }
    if (customChanged) {
      final custom = <String, dynamic>{
        // An edit sends the whole object, so fields this form does not show
        // keep their stored values.
        if (diffing && widget.row?['custom_fields'] is Map)
          ...Map<String, dynamic>.from(widget.row!['custom_fields'] as Map),
      };
      for (final c in _columns) {
        if (!c.isCustom) continue;
        final v = _customValue(c);
        if (v == null && _isCreate) continue;
        custom[c.customKey] = v;
      }
      if (custom.isNotEmpty) out['custom_fields'] = custom;
    }
    return out;
  }

  /// Yes → true, No → false, nothing picked → null.
  bool? _boolValue(ViewColumn c) => switch (_controller(c.name).text.trim().toLowerCase()) {
        'yes' => true,
        'no' => false,
        _ => null,
      };

  /// A custom field's value as the webapp sends it; null when blank.
  Object? _customValue(ViewColumn c) {
    if (c.type == 'boolean') return _boolValue(c) ?? (widget.alwaysSendCustomBooleans ? false : null);
    final text = _choiceValue(c, _controller(c.name).text).trim();
    if (text.isEmpty) return null;
    if (c.type == 'number' || c.type == 'decimal') return num.tryParse(text) ?? text;
    return text;
  }

  // ── deal / billing fields (webapp `dealFields.ts`) ──

  static _DealKind _dealKind(ViewColumn c) => switch (c.name) {
        'budget_min' || 'budget_max' => _DealKind.money,
        'gstin' => _DealKind.gstin,
        'billing_pincode' || 'delivery_pincode' => _DealKind.pincode,
        'billing_state_code' || 'delivery_state_code' => _DealKind.state,
        _ => _DealKind.none,
      };

  static const amountMessage = 'Enter an amount, e.g. 150000 or 150000.50';

  /// Webapp `parseMoney`: commas, spaces and ₹ are ignored; up to 2 decimals.
  static String _moneyText(String raw) => raw.replaceAll(RegExp(r'[,\s₹]'), '');
  static bool _moneyOk(String raw) {
    final t = _moneyText(raw);
    return t.isEmpty || RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(t);
  }

  /// Sent as a 2-place decimal string (`"150000.00"`), blank as null.
  static Object? _moneyValue(String raw) {
    final t = _moneyText(raw);
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n == null ? absentValue : n.toStringAsFixed(2);
  }

  static String _gstin(String raw) => raw.replaceAll(RegExp(r'\s'), '').toUpperCase();

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
    final found = <String, String>{};
    for (final c in _columns) {
      if (_isPhoneColumn(c)) {
        if (c.name == 'whatsapp_no' && _whatsappSame) continue;
        final phone = _phoneController(c.name);
        final required = widget._isRequiredCol(c, c.isFixed || (widget.mobileRequired && c.name == 'mobile_no'));
        if (required && phone.isBlank) {
          found[c.name] = 'This field is required.';
        } else if (!phone.isBlank && !_indianMobileOk(phone)) {
          found[c.name] = indianMobileMessage;
        } else if (!phone.isBlank && !phone.isComplete) {
          found[c.name] = phoneDigitsMessage(phone.rule);
        }
        continue;
      }
      if (_isProducts(c)) {
        for (final id in _selectedIds(c)) {
          final q = _qtyController(id).text.trim();
          if (q.isNotEmpty &&
              (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(q) || (double.tryParse(q) ?? 0) <= 0)) {
            found[c.name] = quantityMessage;
          }
        }
        continue;
      }
      // Only what the form marks with "*" is required. `is_protected` (folded
      // into isFixed) means the column can't be hidden from the org's layout —
      // the webapp never makes a picker such as Assigned Team mandatory for it,
      // and a role that cannot list teams could otherwise never save a lead.
      final picker = c.type == 'foreignkey' || c.type == 'manytomany' ||
          c.type == 'date' || c.type == 'datetime' || c.type == 'boolean';
      final required = widget._isRequiredCol(c, (c.isFixed && !picker) || c.name == 'lead_name' || c.isRequired);
      if (required && _isBlank(c)) {
        found[c.name] = c.name == 'lead_name' ? 'Enter a contact name' : 'This field is required.';
      } else if (_dealKind(c) == _DealKind.money && !_moneyOk(_controller(c.name).text)) {
        found[c.name] = amountMessage;
      } else if (c.isCustom) {
        final m = _customProblem(c);
        if (m != null) found[c.name] = m;
      }
    }
    showErrors(found);
    return [for (final c in _columns) if (found[c.name] != null) found[c.name]!];
  }

  /// Webapp `validateCustomFieldValue` messages for a filled custom field.
  String? _customProblem(ViewColumn c) {
    final t = _controller(c.name).text.trim();
    if (t.isEmpty) return null;
    switch (c.customType) {
      case 'number':
      case 'decimal':
        return num.tryParse(t) == null ? 'Must be a numeric value.' : null;
      case 'date':
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t) ? null : 'Must be a date (YYYY-MM-DD).';
      case 'datetime':
        return RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(t) ? null : 'Must be a date and time.';
      case 'dropdown':
      case 'multi_select':
        return c.hasChoices && !c.choices.any((ch) => ch.$1 == _choiceValue(c, t)) ? 'Pick one of the options.' : null;
      case 'email':
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Must be a valid email address.';
      case 'url':
        return RegExp(r'^https?://\S+$').hasMatch(t) ? null : 'Must be a valid URL (http:// or https://).';
      case 'text':
        return t.length > ViewColumn.customTextMax ? 'Must be at most 255 characters.' : null;
    }
    return null;
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
    if (override != null) {
      // Webapp: the additional-assignee picker never offers the primary owner.
      final owner = c.name == 'assignees' ? _ownerOf() : null;
      return owner == null ? override : [for (final o in override) if (o.id != owner) o];
    }
    if (_isOwner(c)) return _ownerOptions();
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
        // Webapp: "No territory" first, then the tree with groups greyed out.
        return [
          const CatalogOption(id: noneOption, name: 'No territory'),
          ...ref.read(territoryOptionsProvider),
        ];
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

  /// The picked primary owner (`assigned_to`) of a task form, if any.
  String? _ownerOf() {
    for (final col in _columns) {
      if (col.name == 'assigned_to') return _selectedId(col);
    }
    return null;
  }

  /// Webapp owner options: "Unassigned", "<me> (you)", then everyone else
  /// the server says may own a lead (`assignable-users?module=lead`).
  List<CatalogOption> _ownerOptions() {
    final me = UserDirectory.currentUserId;
    final users = ref.read(leadAssignableUsersProvider).valueOrNull ?? const [];
    final source = users.isNotEmpty
        ? users
        : [for (final u in ref.read(rosterProvider)) CatalogOption(id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name)];
    String myName = 'Me';
    final others = <CatalogOption>[];
    for (final u in source) {
      if (u.id == me) {
        myName = u.name.isEmpty ? myName : u.name;
      } else {
        others.add(CatalogOption(id: UserDirectory.mapUserId(u.id), name: u.name));
      }
    }
    return [
      const CatalogOption(id: unassignedOwner, name: 'Unassigned'),
      CatalogOption(id: 'me', name: '$myName (you)'),
      ...others,
    ];
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
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
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
    setState(() {
      _choice[c.name] = picked.isEmpty || picked.first == noneOption ? null : picked.first;
      _errors.remove(c.name);
      if (c.name == 'assigned_to' && _choice[c.name] != null) {
        for (final col in _columns) {
          if (col.name == 'assignees') {
            _multi[col.name] = [for (final id in _selectedIds(col)) if (id != _choice[c.name]) id];
          }
        }
      }
    });
  }

  /// Picks a value for a text column whose options the caller supplied. The
  /// **name** is written, not an id — the API stores this one as text.
  Future<void> _pickTextChoice(ViewColumn c) async {
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
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
    widget.onValueChanged?.call();
  }

  /// A date (or date+time) column. Picked, never typed: the box's text is sent
  /// to the API verbatim, so a hand-typed "24/6/26" is a 400 — and the column
  /// is usually a due date, which is exactly what a calendar is for.
  Widget _dateField(ViewColumn c, {required bool withTime}) {
    final current = DateTime.tryParse(_controller(c.name).text.trim());
    return AppTextField(
      label: c.label,
      required: c.isRequired,
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
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
    final ctrl = _controller(c.name);
    final current = DateTime.tryParse(ctrl.text.trim());
    final day = await pickSheetDate(context, ctrl.text);
    if (day == null || !mounted) return;
    if (!withTime) {
      setState(() {
        ctrl.text = sheetIsoDate(day);
        _errors.remove(c.name);
      });
      widget.onValueChanged?.call();
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

  bool get _dueDateBlank {
    for (final col in _columns) {
      if (col.name == 'due_date') return _controller('due_date').text.trim().isEmpty;
    }
    return false;
  }

  Widget _timeField(ViewColumn c) {
    // Webapp: a task's due time waits for its due date.
    if (c.name == 'due_time' && _dueDateBlank) {
      return Opacity(
        opacity: 0.55,
        child: AppTextField(
          label: c.label,
          readOnly: true,
          value: '',
          hint: 'Set a due date first',
          suffixIcon: PhosphorIconsRegular.clock,
        ),
      );
    }
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
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
    final ctrl = _controller(c.name);
    final picked = await pickSheetTime(context, ctrl.text);
    if (picked == null || !mounted) return;
    setState(() => ctrl.text = sheetTimeLabel(picked));
  }

  Future<void> _pickState(ViewColumn c, List<GstState> states) async {
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showOptionPicker(
      context: context,
      title: c.label,
      options: [
        const CatalogOption(id: noneOption, name: '—'),
        for (final st in states) CatalogOption(id: st.code, name: '${st.name} (${st.code})'),
      ],
      selected: {_controller(c.name).text.trim()},
      emptyNote: 'Loading states…',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _controller(c.name).text = picked.first == noneOption ? '' : picked.first;
      _errors.remove(c.name);
    });
  }

  Future<void> _pickMany(ViewColumn c) async {
    // A closing picker hands focus back to the last text box, popping the
    // keyboard over the form — let go of it first.
    FocusManager.instance.primaryFocus?.unfocus();
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
    setState(() {
      _multi[c.name] = picked.toList();
      _errors.remove(c.name);
    });
  }

  void _clearError(ViewColumn c) {
    if (_errors.remove(c.name) != null) setState(() {});
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
    ref.watch(leadAssignableUsersProvider);
    if (!_seeded) _seed();

    final columns = _columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in columns) ...[
          KeyedSubtree(
            key: _fieldKeys.putIfAbsent(c.name, GlobalKey.new),
            child: _decorated(c),
          ),
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

  /// [_field] plus what the webapp puts around it: the field's error, the
  /// WhatsApp-same-as-phone switch, the Unassigned owner hint and the
  /// per-product quantities.
  Widget _decorated(ViewColumn c) {
    final error = _errors[c.name];
    final showError = error != null && !_isPhoneColumn(c) && !_usesErrorText(c);
    final extras = <Widget>[
      if (c.name == 'whatsapp_no' && _hasBothPhones) _whatsappSameToggle(),
      _field(c),
      if (showError) _errorLine(error),
      if (_isOwner(c) && _selectedId(c) == unassignedOwner && error == null)
        _hint('No owner — the lead is seen through its team and assignees.'),
      if (c.isCustom && c.customType == 'text' && error == null)
        _hint('${_controller(c.name).text.length}/${ViewColumn.customTextMax}'),
      if (c.relatedModel == 'Territory' && error == null && _optionsFor(c).any((o) => o.disabled))
        _hint('Greyed-out groups only organise territories — pick one inside.'),
      if (_isProducts(c)) ..._quantityRows(c),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: extras);
  }

  /// Whether [_field] already renders [_errors] itself (as `errorText`).
  bool _usesErrorText(ViewColumn c) =>
      !_isTextChoice(c) &&
      c.type != 'foreignkey' &&
      c.type != 'manytomany' &&
      c.type != 'boolean' &&
      c.type != 'date' &&
      c.type != 'datetime' &&
      c.type != 'time';

  Widget _errorLine(String text) => Padding(
        padding: EdgeInsets.only(top: 6.h, left: 2.w),
        child: Text(text, style: AppText.caption(color: AppColors.error)),
      );

  Widget _hint(String text) => Padding(
        padding: EdgeInsets.only(top: 6.h, left: 2.w),
        child: Text(text, style: AppText.caption()),
      );

  Widget _whatsappSameToggle() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _whatsappSame = !_whatsappSame;
          _errors.remove('whatsapp_no');
        }),
        child: Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Row(
            children: [
              Icon(_whatsappSame ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square,
                  size: 18.sp, color: _whatsappSame ? AppColors.navy : AppColors.textMuted),
              SizedBox(width: 8.w),
              Text('WhatsApp same as phone', style: AppText.bodyStrong()),
            ],
          ),
        ),
      );

  List<Widget> _quantityRows(ViewColumn c) {
    final ids = [for (final id in _selectedIds(c)) if (_labelForId(c, id).isNotEmpty) id];
    if (ids.isEmpty) return const [];
    return [
      SizedBox(height: 8.h),
      for (final id in ids)
        Padding(
          padding: EdgeInsets.only(bottom: 6.h),
          child: Row(
            children: [
              Expanded(child: Text(_labelForId(c, id), style: AppText.body(), maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 8.w),
              Text('Qty', style: AppText.caption()),
              SizedBox(width: 8.w),
              SizedBox(
                width: 84.w,
                child: TextField(
                  controller: _qtyController(id),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (_errors.remove(c.name) != null) setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: '1',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(9.r)),
                  ),
                ),
              ),
            ],
          ),
        ),
      _hint('Lead value = price excl. GST × quantity.'),
    ];
  }

  Widget _field(ViewColumn c) {
    if (_isPhoneColumn(c)) {
      if (c.name == 'whatsapp_no' && _whatsappSame) {
        final mirror = _phoneController('mobile_no').toE164();
        return AppTextField(
          label: c.label,
          readOnly: true,
          value: mirror == null ? 'Same as contact phone' : mirror.replaceFirst('+91', '+91 '),
        );
      }
      return PhoneInputField(
        label: c.label,
        controller: _phoneController(c.name),
        required: widget._isRequiredCol(c, c.isFixed || (widget.mobileRequired && c.name == 'mobile_no')),
        hint: 'Enter ${c.label.toLowerCase()}…',
        errorText: _errors[c.name],
        onChanged: () => setState(() => _errors.remove(c.name)),
      );
    }
    switch (_dealKind(c)) {
      case _DealKind.money:
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          errorText: _errors[c.name],
          onChanged: (_) => _clearError(c),
          hint: 'e.g. 150000',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        );
      case _DealKind.gstin:
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          errorText: _errors[c.name],
          onChanged: (_) => _clearError(c),
          hint: 'e.g. 32ABCDE1234F1Z5',
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
            const _UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(15),
          ],
        );
      case _DealKind.pincode:
        return AppTextField(
          label: c.label,
          controller: _controller(c.name),
          errorText: _errors[c.name],
          onChanged: (_) => _clearError(c),
          hint: 'Enter ${c.label.toLowerCase()}…',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        );
      case _DealKind.state:
        final states = ref.watch(gstStatesProvider).valueOrNull ?? const [];
        final code = _controller(c.name).text.trim();
        final match = states.where((st) => st.code == code).firstOrNull;
        return AppTextField(
          label: c.label,
          readOnly: true,
          value: code.isEmpty ? '' : (match == null ? code : '${match.name} (${match.code})'),
          hint: states.isEmpty ? 'Loading states…' : 'Select a state',
          suffixIcon: PhosphorIconsRegular.caretDown,
          onTap: () => _pickState(c, states),
        );
      case _DealKind.none:
        break;
    }
    if (_isTextChoice(c)) {
      return AppTextField(
        label: c.label,
        required: c.isRequired,
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
        // Tri-state like the webapp: neither chip lit is "Unknown", and
        // tapping the lit chip again goes back to it.
        final current = _boolValue(c);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetFieldLabel(c.isRequired ? '${c.label} *' : c.label),
            Wrap(
              spacing: 8.w,
              children: [
                for (final v in const ['Yes', 'No'])
                  SelectChip(
                    label: v,
                    selected: current != null && (v == 'Yes') == current,
                    onTap: () => setState(() {
                      final ctrl = _controller(c.name);
                      ctrl.text = ctrl.text == v ? '' : v;
                      _errors.remove(c.name);
                    }),
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
          required: c.isRequired,
          controller: _controller(c.name),
          errorText: _errors[c.name],
          onChanged: (_) => _clearError(c),
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
          required: c.isRequired,
          controller: _controller(c.name),
          errorText: _errors[c.name],
          onChanged: (_) => _clearError(c),
          multiline: true,
          hint: 'Enter ${c.label.toLowerCase()}…',
        );

      default:
        final counted = c.isCustom && c.customType == 'text';
        return AppTextField(
          label: c.label,
          required: widget._isRequiredCol(c, c.isFixed || c.name == 'lead_name' || c.isRequired),
          controller: _controller(c.name),
          errorText: _errors[c.name],
          // A counted box repaints its "n/255" on every keystroke.
          onChanged: (_) => counted ? setState(() => _errors.remove(c.name)) : _clearError(c),
          hint: widget.hints[c.name] ?? 'Enter ${c.label.toLowerCase()}…',
          keyboardType: switch (c.customType) {
            'email' => TextInputType.emailAddress,
            'phone' => TextInputType.phone,
            'url' => TextInputType.url,
            _ => null,
          },
          inputFormatters: counted ? [LengthLimitingTextInputFormatter(ViewColumn.customTextMax)] : null,
        );
    }
  }
}

enum _DealKind { none, money, gstin, pincode, state }

/// GSTIN is typed in capitals, as the webapp forces it.
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
