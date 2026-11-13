/// A Reports export dataset (webapp `reportDataset.ts`): the columns the user
/// picks and the endpoint that streams them as CSV.
class ReportDataset {
  const ReportDataset({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    required this.path,
    required this.columns,
  });
  final String key;
  final String label;
  final String description;
  final String group;

  /// Under `/report/`.
  final String path;
  final List<String> columns;
}

const quotationDataset = ReportDataset(
  key: 'quotation',
  label: 'Quotations',
  description: 'Quotes with totals, validity and payment type',
  group: 'Delivery & commerce',
  path: '/report/quotation-export/',
  columns: [
    'quotation_id', 'lead', 'template_name', 'status', 'total_amount', //
    'discount_type', 'discount_value', 'final_amount', 'payment_type',
    'valid_till', 'accepted_at', 'created_at', 'updated_at', 'created_by',
  ],
);

/// `final_amount` → "Final amount" (the label a column is offered under).
String columnLabel(String key) {
  final t = key.replaceAll('_', ' ').trim();
  return t.isEmpty ? key : t[0].toUpperCase() + t.substring(1);
}

/// `POST` body: the chosen columns in dataset order (the CSV's column order).
Map<String, dynamic> exportBody(ReportDataset d, Set<String> chosen) => {
      'data': [
        for (final c in d.columns)
          if (chosen.contains(c)) c
      ],
      'filters': <String, dynamic>{},
    };

/// `Quotations_20260805_110230.csv` (the webapp's fallback filename).
String exportFileName(String label, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final base = label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return '${base}_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.csv';
}
