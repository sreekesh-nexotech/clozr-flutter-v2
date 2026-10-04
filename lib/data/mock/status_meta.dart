import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// A label + colour pair used by status pills across the app. Mirrors the
/// prototype's `{ label, color }` status maps 1:1.
class StatusMeta {
  final String label;
  final Color color;
  const StatusMeta(this.label, this.color);
}

/// All status vocabularies, keyed by the prototype's status codes. Widgets look
/// up a code here to render a pill — never hardcoding label/colour inline.
class StatusMeta$ {
  StatusMeta$._();

  // Leads (this.STATUS)
  static const lead = <String, StatusMeta>{
    'new': StatusMeta('New', AppColors.blueBright),
    'qualified': StatusMeta('Qualified', AppColors.success),
    'quote': StatusMeta('Quote sent', AppColors.navy),
    'negotiation': StatusMeta('Negotiation', AppColors.warning),
    'won': StatusMeta('Won', AppColors.pending),
    'lost': StatusMeta('Lost', AppColors.error),
    'archived': StatusMeta('Junk / Spam', AppColors.textMuted),
  };
  static const List<String> leadOrder = ['new', 'qualified', 'quote', 'negotiation', 'won'];
  static const List<String> leadAll = ['new', 'qualified', 'quote', 'negotiation', 'won', 'lost', 'archived'];

  // Customers (this.CSTATUS)
  static const customer = <String, StatusMeta>{
    'active': StatusMeta('Active', AppColors.success),
    'upsell': StatusMeta('Upsell In Progress', AppColors.warning),
    'completed': StatusMeta('Completed', AppColors.blueBright),
    'lost': StatusMeta('Lost', AppColors.error),
  };
  static const List<String> customerOrder = ['active', 'upsell', 'completed', 'lost'];

  // CRM tasks (this.TASKSTATUS)
  static const task = <String, StatusMeta>{
    'todo': StatusMeta('To do', AppColors.textMuted),
    'inprogress': StatusMeta('In Progress', AppColors.warning),
    'blocked': StatusMeta('Blocked', AppColors.error),
    'done': StatusMeta('Done', AppColors.blueBright),
  };

  // Follow-ups (this.FUSTATUS)
  static const followup = <String, StatusMeta>{
    'overdue': StatusMeta('Overdue', AppColors.error),
    'due': StatusMeta('Upcoming', AppColors.blueBright),
    'done': StatusMeta('Done', AppColors.success),
  };

  // Quotes (this.QSTATUS)
  static const quote = <String, StatusMeta>{
    'draft': StatusMeta('Draft', AppColors.textMuted),
    'sent': StatusMeta('Sent', AppColors.warning),
    'accepted': StatusMeta('Accepted', AppColors.success),
    'rejected': StatusMeta('Rejected', AppColors.error),
    'expired': StatusMeta('Expired', AppColors.errorDeep),
  };

  // Payments (this.PAYSTATUS)
  static const payment = <String, StatusMeta>{
    'paid': StatusMeta('Paid', AppColors.success),
    'due': StatusMeta('Due', AppColors.warning),
    'overdue': StatusMeta('Overdue', AppColors.error),
    'scheduled': StatusMeta('Scheduled', AppColors.blueBright),
  };

  // Invoices (this.INVSTATUS)
  static const invoice = <String, StatusMeta>{
    'unpaid': StatusMeta('Unpaid', AppColors.error),
    'partial': StatusMeta('Partial', AppColors.warning),
    'completed': StatusMeta('Completed', AppColors.success),
  };

  // Projects (this.PROJSTATUS)
  static const project = <String, StatusMeta>{
    'planning': StatusMeta('Planning', AppColors.blueBright),
    'active': StatusMeta('Active', AppColors.success),
    'onhold': StatusMeta('On Hold', AppColors.warning),
    'completed': StatusMeta('Completed', AppColors.navy),
    'cancelled': StatusMeta('Cancelled', AppColors.textMuted),
  };

  // Ops tasks (this.OPSTS)
  static const opsTask = <String, StatusMeta>{
    'open': StatusMeta('Open', AppColors.blueBright),
    'working': StatusMeta('Working', AppColors.success),
    'review': StatusMeta('Pending Review', AppColors.pending),
    'completed': StatusMeta('Completed', AppColors.navy),
    'cancelled': StatusMeta('Cancelled', AppColors.textMuted),
  };

  // Tickets (this.TKTSTS)
  static const ticket = <String, StatusMeta>{
    'new': StatusMeta('New', AppColors.blueBright),
    'open': StatusMeta('Open', AppColors.success),
    'pending': StatusMeta('Pending', AppColors.warning),
    'resolved': StatusMeta('Resolved', AppColors.pending),
    'closed': StatusMeta('Closed', AppColors.textMuted),
  };

  // LMS (this.LMSST)
  static const lms = <String, StatusMeta>{
    'notstarted': StatusMeta('Not started', AppColors.textMuted),
    'inprogress': StatusMeta('In progress', AppColors.warning),
    'completed': StatusMeta('Completed', AppColors.success),
    'overdue': StatusMeta('Overdue', AppColors.error),
  };

  // ── Accounting (keys are the API's own enum values, handover §7.1) ──

  static const accDocument = <String, StatusMeta>{
    'DRAFT': StatusMeta('Draft', AppColors.textMuted),
    'ISSUED': StatusMeta('Issued', AppColors.navy),
    'CANCELLED': StatusMeta('Cancelled', AppColors.error),
    'VOID_DRAFT': StatusMeta('Void', AppColors.textPlaceholder),
  };

  static const accPaymentState = <String, StatusMeta>{
    'UNPAID': StatusMeta('Unpaid', AppColors.error),
    'PARTIAL': StatusMeta('Part paid', AppColors.warning),
    'PAID': StatusMeta('Paid', AppColors.success),
    'WRITTEN_OFF': StatusMeta('Written off', AppColors.textMuted),
  };

  /// Receipts and vendor payments.
  static const accPosting = <String, StatusMeta>{
    'POSTED': StatusMeta('Posted', AppColors.success),
    'REVERSED': StatusMeta('Reversed', AppColors.error),
  };

  /// Advances, customer credits and vendor advances share one palette.
  static const accBalance = <String, StatusMeta>{
    'OPEN': StatusMeta('Open', AppColors.blueBright),
    'ACTIVE': StatusMeta('Open', AppColors.blueBright),
    'PARTIALLY_ADJUSTED': StatusMeta('Part adjusted', AppColors.warning),
    'PARTIALLY_APPLIED': StatusMeta('Part applied', AppColors.warning),
    'ADJUSTED': StatusMeta('Adjusted', AppColors.success),
    'APPLIED': StatusMeta('Applied', AppColors.success),
    'RELEASED': StatusMeta('Released', AppColors.success),
    'REFUNDED': StatusMeta('Refunded', AppColors.textMuted),
    'CANCELLED': StatusMeta('Cancelled', AppColors.error),
  };

  static const accEvent = <String, StatusMeta>{
    'RECEIVED': StatusMeta('Received', AppColors.blueBright),
    'PENDING_APPROVAL': StatusMeta('Needs approval', AppColors.pending),
    'POSTED': StatusMeta('Posted', AppColors.success),
    'REJECTED': StatusMeta('Rejected', AppColors.error),
    'SKIPPED': StatusMeta('Skipped', AppColors.textMuted),
  };

  /// Book, GST-return, TDS and fiscal-year period states.
  static const accPeriod = <String, StatusMeta>{
    'OPEN': StatusMeta('Open', AppColors.blueBright),
    'CLOSED': StatusMeta('Closed', AppColors.textMuted),
    'FILED': StatusMeta('Filed', AppColors.success),
    'SETTLED': StatusMeta('Settled', AppColors.navy),
    'DEPOSITED': StatusMeta('Deposited', AppColors.success),
    'CLOSING': StatusMeta('Closing', AppColors.warning),
    'REOPENED': StatusMeta('Reopened', AppColors.pending),
  };

  static const accActivation = <String, StatusMeta>{
    'INACTIVE': StatusMeta('Not activated', AppColors.textMuted),
    'ACTIVATING': StatusMeta('Activating', AppColors.warning),
    'ACTIVE': StatusMeta('Active', AppColors.success),
    'SUSPENDED': StatusMeta('Suspended', AppColors.error),
  };

  // Priority tag tones (this.TAGTONE) — bg + fg
  static const Map<String, ({Color bg, Color fg})> priorityTone = {
    'high': (bg: AppColors.tintRedSoft, fg: AppColors.error),
    'High': (bg: AppColors.tintRedSoft, fg: AppColors.error),
    'medium': (bg: AppColors.tintAmber, fg: AppColors.warningDeep),
    'Medium': (bg: AppColors.tintAmber, fg: AppColors.warningDeep),
    'low': (bg: AppColors.bgHover, fg: AppColors.textMuted),
    'Low': (bg: AppColors.bgHover, fg: AppColors.textMuted),
    'Urgent': (bg: AppColors.tintRedSoft, fg: AppColors.error),
  };

  /// Project priority dot colours (this.PROJPRI).
  ///
  /// `Urgent` is one of the four [priorityKey] folds and one the org's own
  /// catalog uses; without it every urgent task and project drew the neutral
  /// grey fallback, reading as *less* pressing than a High one.
  /// Urgent shares High's red, as [priorityTone] already does on the CRM side —
  /// matching it rather than restyling the three existing levels.
  static const Map<String, Color> projectPriority = {
    'Urgent': AppColors.error,
    'High': AppColors.error,
    'Medium': AppColors.warningDeep,
    'Low': AppColors.success,
  };
}
