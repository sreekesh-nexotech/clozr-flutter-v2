import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../infrastructure/data_sources/remote/ops_comments_remote_ds.dart';
import '../../../../data/api/roster.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/note.dart';
import 'ops_tasks_providers.dart';

/// Stateful notes thread for a single Operations record (#13). Holds the shared
/// [NoteEntry] list the core `NotesThread` renders; new notes prepend and replies
/// append. Seeded once from the record's mock notes and kept in memory for the
/// session (a real API-backed store slots in behind the same interface).
class OpsNotesNotifier extends StateNotifier<List<NoteEntry>> {
  OpsNotesNotifier(super.seed, this._me, {this.remote, this.recordId = '', this.isProject = false}) {
    if (_remoteWired) _load();
  }

  /// The signed-in user, so a note is bylined with whoever actually wrote it.
  final NoteAuthor _me;

  /// `/projects/comments/`, or null in mock mode.
  final OpsCommentsRemoteDataSource? remote;

  /// The task (or project) the thread hangs off. Empty when there is nothing to
  /// persist against — a subtask row that arrived without its `task_id`.
  final String recordId;
  final bool isProject;

  bool get _remoteWired => remote != null && recordId.isNotEmpty;

  Future<void> _load() async {
    try {
      final rows = await remote!.fetch(recordId: recordId, isProject: isProject);
      if (mounted) state = rows;
    } on Object {
      // Offline or refused: the thread stays as it is rather than blanking.
    }
  }

  /// Re-reads the thread. Used by pull-to-refresh on the detail screens.
  Future<void> reload() => _remoteWired ? _load() : Future.value();

  void addNote(String body, List<NoteAttachment> attachments) {
    final entry = NoteEntry(
      id: 'note-${DateTime.now().microsecondsSinceEpoch}',
      author: _me.name,
      time: 'now',
      body: body,
      avatarColor: _me.color,
      attachments: attachments,
    );
    state = [entry, ...state];
    if (!_remoteWired) return;
    // Optimistic: the entry is already on screen, so the post runs behind it
    // and the stored row (with its real id and server timestamp) replaces the
    // local one on success.
    unawaited(() async {
      try {
        final saved = await remote!.add(
            recordId: recordId, body: body, isProject: isProject);
        if (saved == null || !mounted) return;
        state = [for (final n in state) n.id == entry.id ? saved : n];
      } on Object {
        // Keep the optimistic entry rather than dropping what was typed.
      }
    }());
  }

  void addReply(String noteId, String body) {
    final next = <NoteEntry>[];
    for (final n in state) {
      if (n.id == noteId) {
        n.replies.add(NoteReply(author: _me.name, time: 'now', body: body, avatarColor: _me.color));
      }
      next.add(n);
    }
    state = next;
  }
}

NoteEntry _fromOpsNote(String recordId, int i, dynamic n) => NoteEntry(
      id: 'seed-$recordId-$i',
      author: n.author as String,
      time: n.time as String,
      body: n.body as String,
      avatarColor: AppColors.navy,
    );

/// The comment data source, or null in mock mode — which is what keeps the
/// in-memory behaviour there.
final opsCommentsRemoteDataSourceProvider =
    Provider<OpsCommentsRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return OpsCommentsRemoteDataSource(ref.watch(apiServiceProvider));
});

/// Notes for a project / ops-task detail, keyed by record id. Task records seed
/// from their mock notes; projects (no seeded notes) start empty.
final opsNotesProvider =
    StateNotifierProvider.family<OpsNotesNotifier, List<NoteEntry>, String>((ref, id) {
  final remote = ref.watch(opsCommentsRemoteDataSourceProvider);
  final task = ref.read(opsTaskByIdProvider(id));
  final seed = <NoteEntry>[];
  // The mock seed only: in API mode the thread is whatever the server holds.
  if (remote == null && task != null) {
    for (var i = 0; i < task.notes.length; i++) {
      seed.add(_fromOpsNote(id, i, task.notes[i]));
    }
  }
  return OpsNotesNotifier(seed, ref.watch(noteAuthorProvider),
      remote: remote, recordId: id);
});

/// Notes on one **subtask**, keyed by the subtask's own `task_id`.
///
/// A subtask is a task (`operations-task.md` §3C), so its thread is the same
/// `/projects/comments/` collection its parent uses. This was keyed by
/// `"<taskId>#<index>"` and held in memory, so a note survived only until the
/// screen was left — and could not have been keyed to a record even in
/// principle, since a position in a list is not an id.
final subtaskNotesProvider =
    StateNotifierProvider.family<OpsNotesNotifier, List<NoteEntry>, String>(
        (ref, subtaskId) {
  return OpsNotesNotifier(<NoteEntry>[], ref.watch(noteAuthorProvider),
      remote: ref.watch(opsCommentsRemoteDataSourceProvider),
      recordId: subtaskId);
});
