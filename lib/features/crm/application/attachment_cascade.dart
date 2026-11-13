import '../domain/repositories/attachments_repository.dart';

/// Deletes a record **and** its files (UI/UX audit #09).
///
/// The server leaves a deleted record's attachments behind — they still show
/// in Reports › Attachments, pointing at nothing — so the app removes them.
/// Order matters: the files are listed first, the record is deleted (which may
/// be refused, e.g. a task others depend on — then nothing else happens), and
/// only then are the listed files removed. File removal is best effort; it
/// never turns a successful record delete into a failure.
Future<void> deleteRecordWithFiles(
  AttachmentsRepository repo, {
  required String relatedTo,
  required String recordId,
  required Future<void> Function() deleteRecord,
}) async {
  var ids = const <String>[];
  try {
    ids = [for (final f in await repo.getFiles(relatedTo, recordId)) f.id];
  } on Object {
    // Listing failed: still delete the record.
  }
  await deleteRecord();
  for (final id in ids) {
    try {
      // Quiet: the server may already have removed it with the record.
      await repo.deleteFile(id, quiet: true);
    } on Object {
      // Best effort.
    }
  }
}
