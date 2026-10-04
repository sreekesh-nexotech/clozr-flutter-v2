import 'package:equatable/equatable.dart';

class BookPeriod extends Equatable {
  const BookPeriod({required this.id, this.periodNo, this.startDate, this.endDate, this.status = 'OPEN'});

  final String id;
  final int? periodNo;
  final String? startDate;
  final String? endDate;
  final String status;

  @override
  List<Object?> get props => [id, status];
}

class GstPeriod extends Equatable {
  const GstPeriod({
    required this.id,
    this.gstin,
    this.startDate,
    this.endDate,
    this.gstr1Status = 'OPEN',
    this.gstr3bStatus = 'OPEN',
    this.settled = false,
  });

  final String id;
  final String? gstin;
  final String? startDate;
  final String? endDate;
  final String gstr1Status;
  final String gstr3bStatus;
  final bool settled;

  @override
  List<Object?> get props => [id, gstr1Status, gstr3bStatus, settled];
}

class TdsPeriod extends Equatable {
  const TdsPeriod({required this.id, this.quarter, this.startDate, this.endDate, this.status = 'OPEN'});

  final String id;
  final int? quarter;
  final String? startDate;
  final String? endDate;
  final String status;

  @override
  List<Object?> get props => [id, status];
}

/// `GET periods/` — the register for one fiscal year (handover §8.7).
class PeriodRegister extends Equatable {
  const PeriodRegister({
    this.fiscalYearId,
    this.fyLabel,
    this.status,
    this.bookPeriods = const [],
    this.gstPeriods = const [],
    this.tdsPeriods = const [],
  });

  final String? fiscalYearId;
  final String? fyLabel;
  final String? status;
  final List<BookPeriod> bookPeriods;
  final List<GstPeriod> gstPeriods;
  final List<TdsPeriod> tdsPeriods;

  /// The GST period covering [day], if the register has one.
  GstPeriod? gstPeriodFor(DateTime day) {
    for (final p in gstPeriods) {
      final s = DateTime.tryParse(p.startDate ?? '');
      final e = DateTime.tryParse(p.endDate ?? '');
      if (s != null && e != null && !day.isBefore(s) && !day.isAfter(e)) return p;
    }
    return null;
  }

  @override
  List<Object?> get props => [fiscalYearId, bookPeriods, gstPeriods, tdsPeriods];
}

class FiscalYear extends Equatable {
  const FiscalYear({required this.id, this.label, this.startDate, this.endDate, this.status, this.isCurrent = false});

  final String id;
  final String? label;
  final String? startDate;
  final String? endDate;
  final String? status;
  final bool isCurrent;

  @override
  List<Object?> get props => [id, isCurrent];
}

class ChecklistItem extends Equatable {
  const ChecklistItem({required this.code, this.label, this.severity = 'INFO', this.status = 'PASS', this.detail});

  final String code;
  final String? label;
  final String severity; // BLOCK | WARN | INFO
  final String status; // PASS | FAIL
  final String? detail;

  bool get passed => status == 'PASS';

  @override
  List<Object?> get props => [code, severity, status];
}

/// A GST (or book / FY) period checklist — read-only on mobile.
class PeriodChecklist extends Equatable {
  const PeriodChecklist({this.items = const [], this.blocking = const [], this.canSettle = false});

  final List<ChecklistItem> items;
  final List<String> blocking;
  final bool canSettle;

  @override
  List<Object?> get props => [items, blocking, canSettle];
}
