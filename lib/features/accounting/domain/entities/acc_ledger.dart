import 'package:equatable/equatable.dart';

/// One posted journal line.
class JournalLine extends Equatable {
  const JournalLine({
    required this.lineNo,
    this.accountCode,
    this.role,
    this.debit = '0',
    this.credit = '0',
    this.memo,
  });

  final int lineNo;
  final String? accountCode;
  final String? role;
  final String debit;
  final String credit;
  final String? memo;

  @override
  List<Object?> get props => [lineNo, accountCode, role, debit, credit];
}

/// A posted journal entry (handover §8.6). Read-only on mobile.
class JournalEntry extends Equatable {
  const JournalEntry({
    required this.id,
    this.entryNo,
    this.eventType,
    this.postingDate,
    this.narration,
    this.totalDebit = '0',
    this.totalCredit = '0',
    this.reversesEntryId,
    this.reversedByEntryId,
    this.lines = const [],
  });

  final String id;
  final String? entryNo;
  final String? eventType;
  final String? postingDate;
  final String? narration;
  final String totalDebit;
  final String totalCredit;
  final String? reversesEntryId;
  final String? reversedByEntryId;
  final List<JournalLine> lines;

  @override
  List<Object?> get props => [id, entryNo, lines];
}

/// A ledger event — what the posting engine received and what it did with it.
class LedgerEvent extends Equatable {
  const LedgerEvent({
    required this.id,
    this.eventType,
    this.status = 'RECEIVED',
    this.error,
    this.skipReason,
    this.receivedAt,
  });

  final String id;
  final String? eventType;
  final String status;
  final String? error;
  final String? skipReason;
  final String? receivedAt;

  @override
  List<Object?> get props => [id, status, error];
}
