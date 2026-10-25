import 'package:clozrapp/features/crm/presentation/components/lead_schema_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consent, call telemetry and dial codes are never lead inputs (webapp)', () {
    for (final n in ['consent_captured_at', 'consent_notice_version', 'last_call_at', 'last_call_outcome',
        'consecutive_unanswered_calls', 'calls_last_7d', 'mobile_country_code', 'whatsapp_country_code']) {
      expect(LeadSchemaFormState.neverLeadInputs(n), isTrue, reason: n);
    }
    for (final n in ['lead_name', 'mobile_no', 'email', 'assigned_team']) {
      expect(LeadSchemaFormState.neverLeadInputs(n), isFalse, reason: n);
    }
  });

  test('Add lead always carries owner, assignees and team, with the web labels', () {
    expect([for (final c in LeadSchemaFormState.addLeadAssignmentColumns) c.name], ['lead_owner', 'assignees', 'assigned_team']);
    expect(LeadSchemaFormState.addLeadLabel('lead_name'), 'Contact name');
    expect(LeadSchemaFormState.addLeadLabel('mobile_no'), 'Contact phone');
    expect(LeadSchemaFormState.addLeadLabel('whatsapp_no'), 'WhatsApp number');
    expect(LeadSchemaFormState.addLeadLabel('email'), isNull);
  });
}
