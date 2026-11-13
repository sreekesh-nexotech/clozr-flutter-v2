/// A product's sales content (webapp `productSalesContent.ts`): features,
/// specifications, warranty summary, delivery lead time, images and a brochure,
/// which proposals and generated documents print. Pure.
const kContentMaxFeatures = 30;
const kContentFeatureChars = 300;
const kContentMaxSpecs = 50;
const kContentSpecLabelChars = 100;
const kContentSpecValueChars = 500;
const kContentWarrantyChars = 2000;
const kContentLeadNoteChars = 140;

class ContentMedia {
  const ContentMedia({required this.id, this.name = '', this.url = ''});
  final String id;
  final String name;
  final String url;
}

class SalesContent {
  const SalesContent({
    this.features = const [],
    this.specs = const [],
    this.warranty = '',
    this.leadDays,
    this.leadNote = '',
    this.images = const [],
    this.brochure,
  });
  final List<String> features;
  final List<({String label, String value})> specs;
  final String warranty;
  final int? leadDays;
  final String leadNote;
  final List<ContentMedia> images;
  final ContentMedia? brochure;

  factory SalesContent.fromRaw(Map<String, dynamic> raw) {
    String s(Object? v) => v == null ? '' : '$v'.trim();
    ContentMedia? media(Object? m) => m is Map && s(m['media_id']).isNotEmpty
        ? ContentMedia(
            id: s(m['media_id']), name: s(m['name']), url: s(m['url']))
        : null;
    final imgs = [
      for (final m
          in (raw['images'] is List ? raw['images'] as List : const []))
        if (media(m) case final x?) x,
    ];
    return SalesContent(
      features: [
        for (final f
            in (raw['features'] is List ? raw['features'] as List : const []))
          if (s(f).isNotEmpty) s(f),
      ],
      specs: [
        for (final r in (raw['specifications'] is List
            ? raw['specifications'] as List
            : const []))
          if (r is Map &&
              (s(r['label']).isNotEmpty || s(r['value']).isNotEmpty))
            (label: s(r['label']), value: s(r['value'])),
      ],
      warranty: s(raw['warranty_summary']),
      leadDays: raw['delivery_lead_time_days'] is num
          ? (raw['delivery_lead_time_days'] as num).toInt()
          : null,
      leadNote: s(raw['delivery_lead_time_note']),
      images: imgs,
      brochure: media(raw['brochure']),
    );
  }

  bool get isEmpty =>
      features.isEmpty &&
      specs.isEmpty &&
      warranty.isEmpty &&
      leadDays == null &&
      leadNote.isEmpty &&
      images.isEmpty &&
      brochure == null;

  /// "14 days · after advance payment" ('' when neither is set).
  String get leadTimeLabel => [
        if (leadDays != null) '$leadDays day${leadDays == 1 ? '' : 's'}',
        if (leadNote.isNotEmpty) leadNote,
      ].join(' · ');
}

/// The editor's draft, as typed.
class ContentDraft {
  ContentDraft({
    List<String>? features,
    List<({String label, String value})>? specs,
    this.warranty = '',
    this.leadDays = '',
    this.leadNote = '',
  })  : features = features ?? [],
        specs = specs ?? [];
  List<String> features;
  List<({String label, String value})> specs;
  String warranty;
  String leadDays;
  String leadNote;

  factory ContentDraft.from(SalesContent c) => ContentDraft(
        features: [...c.features],
        specs: [...c.specs],
        warranty: c.warranty,
        leadDays: c.leadDays?.toString() ?? '',
        leadNote: c.leadNote,
      );
}

List<String> cleanFeatures(Iterable<String> items) => [
      for (final f in items)
        if (f.split(RegExp(r'\s+')).join(' ').trim().isNotEmpty)
          f.split(RegExp(r'\s+')).join(' ').trim(),
    ];

List<({String label, String value})> cleanSpecs(
        Iterable<({String label, String value})> rows) =>
    [
      for (final r in rows)
        if (r.label.trim().isNotEmpty || r.value.trim().isNotEmpty)
          (label: r.label.trim(), value: r.value.trim()),
    ];

/// Problems by field ('features', 'specs', 'warranty', 'leadDays', 'leadNote').
Map<String, String> contentProblems(ContentDraft d) {
  final out = <String, String>{};
  final features = cleanFeatures(d.features);
  if (features.length > kContentMaxFeatures) {
    out['features'] = 'Up to $kContentMaxFeatures features.';
  } else if (features.any((f) => f.length > kContentFeatureChars)) {
    out['features'] =
        'Each feature can be at most $kContentFeatureChars characters.';
  }
  final specs = cleanSpecs(d.specs);
  if (specs.length > kContentMaxSpecs) {
    out['specs'] = 'Up to $kContentMaxSpecs specifications.';
  } else if (specs.any((r) => r.label.isEmpty)) {
    out['specs'] = 'Every specification needs a label.';
  } else if (specs.any((r) =>
      r.label.length > kContentSpecLabelChars ||
      r.value.length > kContentSpecValueChars)) {
    out['specs'] =
        'Labels can be at most $kContentSpecLabelChars and values $kContentSpecValueChars characters.';
  }
  if (d.warranty.trim().length > kContentWarrantyChars) {
    out['warranty'] = 'At most $kContentWarrantyChars characters.';
  }
  final days = d.leadDays.trim();
  if (days.isNotEmpty && !RegExp(r'^\d+$').hasMatch(days)) {
    out['leadDays'] = 'Enter whole days.';
  }
  if (d.leadNote.trim().length > kContentLeadNoteChars) {
    out['leadNote'] = 'At most $kContentLeadNoteChars characters.';
  }
  return out;
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

/// Only the changed keys (an untouched editor sends nothing; images and the
/// brochure are never part of this write, so they stay as stored).
Map<String, dynamic> contentPatch(SalesContent saved, ContentDraft d) {
  final patch = <String, dynamic>{};
  final features = cleanFeatures(d.features);
  if (!_sameList(features, cleanFeatures(saved.features))) {
    patch['features'] = features;
  }
  final specs = cleanSpecs(d.specs);
  final savedSpecs = cleanSpecs(saved.specs);
  if (specs.length != savedSpecs.length ||
      [for (var i = 0; i < specs.length; i++) specs[i] != savedSpecs[i]]
          .any((x) => x)) {
    patch['specifications'] = [
      for (final r in specs) {'label': r.label, 'value': r.value}
    ];
  }
  if (d.warranty.trim() != saved.warranty.trim()) {
    patch['warranty_summary'] =
        d.warranty.trim().isEmpty ? null : d.warranty.trim();
  }
  final days = d.leadDays.trim();
  if (days != (saved.leadDays?.toString() ?? '')) {
    patch['delivery_lead_time_days'] = days.isEmpty ? null : int.parse(days);
  }
  if (d.leadNote.trim() != saved.leadNote.trim()) {
    patch['delivery_lead_time_note'] =
        d.leadNote.trim().isEmpty ? null : d.leadNote.trim();
  }
  return patch;
}
