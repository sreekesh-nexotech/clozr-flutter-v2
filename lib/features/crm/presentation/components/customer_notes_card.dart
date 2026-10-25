import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/note.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/customer_activity_tabs_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/customer.dart';

/// The customer's Notes card — the webapp `NotesPanel` (`recordType=customer`,
/// `historyKinds=['lead']`): composer with tag + @mention + attachments, reply,
/// author-only pin / edit / delete (toasts "Note added", "Reply posted",
/// "Note updated", "Pinned"/"Unpinned", "Note deleted"; dialog "Delete note?").
///
/// Notes rolled up from the converted lead are tagged "From lead LD-…" and are
/// read-only history: no reply, pin, edit or delete. Other rolled-up notes get
/// their source tag ("Task · Call back").
///
/// Pass [threadKey] to scroll to / focus the composer from "Add note"
/// (`Scrollable.ensureVisible(threadKey.currentContext!)` +
/// `threadKey.currentState?.focusComposer()`).
class CustomerNotesCard extends ConsumerWidget {
  const CustomerNotesCard({super.key, required this.customer, this.threadKey});

  final Customer customer;
  final GlobalKey<NotesThreadState>? threadKey;

  CrmNotesSeed _seed() => CrmNotesSeed(
        customer.id,
        () => [
          NoteEntry(
            id: '${customer.id}-n0',
            author: 'You',
            time: '2h ago',
            via: 'Call',
            body: 'Spoke with ${customer.name.split(' ').first}. Ongoing work on track; discussing an upsell.',
          ),
          NoteEntry(
            id: '${customer.id}-n1',
            author: 'Anjana Menon',
            time: '1d ago',
            via: 'Email',
            avatarColor: AppColors.blueBright,
            body: 'Shared the revised BOQ. Client happy with progress on ${customer.project}.',
          ),
        ],
        apiModel: 'customer',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = _seed();
    final notifier = ref.read(crmNotesProvider(seed).notifier);
    final tags = ref.watch(customerNoteTagsProvider(customer.id)).valueOrNull ?? const {};
    final history = {for (final e in tags.entries) if (e.value.readOnly) e.key};

    // Tagged notes carry their source as the pill; history notes lose their
    // author id so the author-only actions (pin / edit / delete) stay off.
    final notes = [
      for (final n in ref.watch(crmNotesProvider(seed)))
        if (tags[n.id] case final tag?)
          NoteEntry(
            id: n.id,
            author: n.author,
            time: n.time,
            body: n.body,
            via: tag.text,
            avatarColor: n.avatarColor,
            pinned: n.pinned,
            authorId: tag.readOnly ? null : n.authorId,
            noteType: n.noteType,
            replies: n.replies,
            attachments: n.attachments,
          )
        else
          n,
    ];

    void readOnlyToast() =>
        ref.read(toastProvider.notifier).show('Notes from the converted lead are read-only.');

    return NotesThread(
      key: threadKey,
      author: ref.watch(noteAuthorProvider),
      notes: notes,
      onAddNote: (body, atts) => notifier.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) {
        if (history.contains(noteId)) return readOnlyToast();
        notifier.addReply(noteId, body, ref.read(noteAuthorProvider));
      },
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
      mentionables: [
        for (final u in ref.watch(assignableUsersForModuleProvider('customer')).valueOrNull ?? const <CatalogOption>[])
          (id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name),
      ],
      currentUserId: UserDirectory.currentUserId,
      onAddTypedNote: (body, atts, typeId, typeName, mentions) => notifier.addNote(
        body,
        atts,
        ref.read(noteAuthorProvider),
        noteTypeId: typeId,
        noteTypeName: typeName,
        mentionedUserIds: mentions,
        authorId: UserDirectory.currentUserId,
      ),
      onTogglePin: (id) {
        if (history.contains(id)) return readOnlyToast();
        notifier.togglePin(id);
      },
      onEditNote: (id, body) async =>
          history.contains(id) ? 'Notes from the converted lead are read-only.' : notifier.editNote(id, body),
      onDeleteNote: (id) async =>
          history.contains(id) ? 'Notes from the converted lead are read-only.' : notifier.deleteNote(id),
    );
  }
}
