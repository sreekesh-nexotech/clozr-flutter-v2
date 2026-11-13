import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../application/approval_rules.dart';
import '../../application/providers/approvals_providers.dart';
import '../../domain/entities/approval.dart';
import 'approval_decision_dialog.dart';

// The pre-check before a save that may need approval (webapp
// `useApprovalRequestNote`). It asks the server per record, so the same call
// serves a detail page and a board drop, whose rows carry no gates. If the
// check fails the save still goes: the server gates it anyway, and only the
// comment is lost.

const _gateTimeout = Duration(seconds: 6);

Future<RecordApprovalState> _stateOf(
    WidgetRef ref, String module, String objectId) async {
  if (objectId.isEmpty) return RecordApprovalState.unknown;
  try {
    return await ref
        .read(
            recordApprovalProvider((module: module, objectId: objectId)).future)
        .timeout(_gateTimeout);
  } on Object {
    return RecordApprovalState.unknown;
  }
}

/// Before closing [objectId] to a status of type [statusCode] (labelled
/// [statusLabel]): the comment to send as `request_note` ('' when no approval
/// is needed or none was written), or null when the person cancelled and
/// nothing should be saved.
Future<String?> approvalNoteForClose(
  BuildContext context,
  WidgetRef ref, {
  required String module,
  required String objectId,
  required String? statusCode,
  required String statusLabel,
}) async {
  final state = await _stateOf(ref, module, objectId);
  if (state.pending != null || !closeNeedsApproval(state.gates, statusCode)) {
    return '';
  }
  if (!context.mounted) return null;
  return askApprovalRequestComment(context, 'Closing to $statusLabel');
}

/// The same, before changing the owner of [objectId] to [ownerName].
Future<String?> approvalNoteForOwner(
  BuildContext context,
  WidgetRef ref, {
  required String module,
  required String objectId,
  required String ownerName,
}) async {
  final state = await _stateOf(ref, module, objectId);
  if (state.pending != null || !state.gates.ownerTransfer) return '';
  if (!context.mounted) return null;
  return askApprovalRequestComment(context,
      'Owner transfer to ${ownerName.isEmpty ? 'someone else' : ownerName}');
}

/// Runs [write] and says whether the server held it for approval on
/// [objectId] — read off the network layer's hold signal, so a caller can
/// undo its optimistic change without the repository returning anything new.
/// Errors from [write] propagate.
Future<bool> writeWasHeld(
    WidgetRef ref, String objectId, Future<void> Function() write) async {
  final holds = ref.read(apiServiceProvider).holds;
  final before = holds.value;
  await write();
  final after = holds.value;
  return after != null &&
      !identical(before, after) &&
      (objectId.isEmpty || after.heldIds.contains(objectId));
}

/// A project-task status's close code for the gate (webapp
/// `projectTaskCloseCode`): `cancelled`, `closed`, or null for an open one.
String? projectTaskCloseCode(CatalogOption? status) {
  if (status == null) return null;
  if (status.isCancelled) return 'cancelled';
  return status.isClosed ? 'closed' : null;
}

/// `{'request_note': note}` when there is one to send, else empty — spread
/// into a save's body.
Map<String, dynamic> requestNoteField(String? note) =>
    (note ?? '').trim().isEmpty ? const {} : {'request_note': note!.trim()};
