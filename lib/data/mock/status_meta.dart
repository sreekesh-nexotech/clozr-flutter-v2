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
