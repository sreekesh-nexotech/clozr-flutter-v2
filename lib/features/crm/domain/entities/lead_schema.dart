export 'view_schema.dart';

import 'view_schema.dart';

/// The Leads layout is one instance of the shared Org View Settings shape, so
/// these are aliases rather than their own types — the parser, the matcher and
/// the "empty means built-in layout" contract are identical for every module.
///
/// Kept as names because the Leads screens read better with them, and because
/// every call site and test already speaks in these terms.
typedef LeadColumn = ViewColumn;
typedef LeadListSchema = ViewSchema;
