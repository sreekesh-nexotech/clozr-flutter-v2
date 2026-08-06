import '../../../domain/entities/lead_file.dart';

/// Static attachment seed for the Files tab.
///
/// The Files tab had no data source before (it rendered a fixed empty state),
/// so there is nothing to port 1:1. A couple of leads carry files so the list
/// renders in mock mode; every other lead keeps the empty state.
class AttachmentsMockDataSource {
  const AttachmentsMockDataSource();

  List<LeadFile> fetchFilesForLead(String leadId) =>
      _seed[leadId] ?? const <LeadFile>[];

  static const Map<String, List<LeadFile>> _seed = {
    'L1001': [
      LeadFile(id: 'AT-001', name: 'Showroom moodboard.pdf', url: 'https://cdn.example.com/showroom-moodboard.pdf', description: 'Concept directions for the ground floor', uploadedBy: 'am', uploadedAt: '2d ago'),
      LeadFile(id: 'AT-002', name: 'Floor plan — level 1.dwg', url: 'https://cdn.example.com/floor-plan-l1.dwg', description: '', uploadedBy: 'rk', uploadedAt: '5d ago'),
      LeadFile(id: 'AT-003', name: 'Site photos.zip', url: 'https://cdn.example.com/site-photos.zip', description: 'Measurement visit, 12 shots', uploadedBy: 'me', uploadedAt: '9 Jul'),
    ],
    'L1003': [
      LeadFile(id: 'AT-004', name: 'Resort brief.docx', url: 'https://cdn.example.com/resort-brief.docx', description: 'Client-supplied requirements', uploadedBy: 'fa', uploadedAt: '1d ago'),
    ],
  };
}
