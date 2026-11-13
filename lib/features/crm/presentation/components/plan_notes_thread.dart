import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/crm_catalog.dart';

/// The notes of a payment plan or one of its payments.
///
/// `payment` is not a `related_to` model the API accepts, so the thread hangs
/// off the **source quotation** — a plan, its payments and its quote share one
/// thread. With no quote the thread stays local to the screen. It is the same
/// [NotesThread] every other CRM record uses, so a note here can carry a tag,
/// @mentions, several lines and inline attachments, and can be pinned, edited
/// and deleted.
class PlanNotesThread extends ConsumerWidget {
  const PlanNotesThread(
      {super.key, required this.quotationUuid, required this.localKey});

  final String quotationUuid;

  /// Keys the local-only thread when there is no quotation.
  final String localKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = CrmNotesSeed(
      quotationUuid.isEmpty ? localKey : quotationUuid,
      () => const [],
      apiModel: quotationUuid.isEmpty ? null : 'quotation',
    );
    final notes = ref.watch(crmNotesProvider(seed));
    final notifier = ref.read(crmNotesProvider(seed).notifier);
    return NotesThread(
      author: ref.watch(noteAuthorProvider),
      notes: notes,
      onAddNote: (body, atts) =>
          notifier.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) =>
          notifier.addReply(noteId, body, ref.read(noteAuthorProvider)),
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
      mentionables: [
        for (final u in ref
                .watch(assignableUsersForModuleProvider('task'))
                .valueOrNull ??
            const <CatalogOption>[])
          (id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name),
      ],
      currentUserId: UserDirectory.currentUserId,
      onAddTypedNote: (body, atts, typeId, typeName, mentions) =>
          notifier.addNote(body, atts, ref.read(noteAuthorProvider),
              noteTypeId: typeId,
              noteTypeName: typeName,
              mentionedUserIds: mentions,
              authorId: UserDirectory.currentUserId),
      onTogglePin: notifier.togglePin,
      onEditNote: (id, body) => notifier.editNote(id, body),
      onDeleteNote: notifier.deleteNote,
    );
  }
}
