import '../../../core/network/app_error.dart';

/// What a refused project-task request was trying to do.
enum ProjectTaskAction { view, create, update, delete }

/// Webapp `projectTaskError.ts` (round 5, PLT-03): copy for a refused
/// project-task request.
///
/// A role without Operations › Tasks (`project_task`) gets DRF's generic 403 —
/// "You do not have permission to perform this action." — which says neither
/// what is missing nor what to do. Only that generic refusal is rewritten; a
/// 403 that explains itself (business hours, a plan without the feature, the
/// weekend rule) keeps its own message, and so does every non-403 failure.
const projectTaskForbiddenCopy = <ProjectTaskAction, String>{
  ProjectTaskAction.view:
      "Your role doesn't include Operations › Tasks, so project tasks can't be shown here. Ask a workspace admin to add it to your role.",
  ProjectTaskAction.create:
      "Your role can't create project tasks. Ask a workspace admin to add Operations › Tasks (create) to your role.",
  ProjectTaskAction.update:
      "Your role can't edit this project task. Ask a workspace admin to add Operations › Tasks (edit) to your role.",
  ProjectTaskAction.delete:
      "Your role can't delete project tasks. Ask a workspace admin to add Operations › Tasks (delete) to your role.",
};

final _genericForbidden = [
  RegExp(r'^you do not have permission to perform this action\.?$', caseSensitive: false),
  RegExp(r'^you do not have permission to do that\.?$', caseSensitive: false),
];

/// Whether [error] is the server's generic, unexplained 403.
bool isGenericForbidden(AppError? error) {
  if (error == null || error.type != AppErrorType.forbidden) return false;
  final message = error.message.trim();
  return message.isEmpty || _genericForbidden.any((re) => re.hasMatch(message));
}

/// The message to show for a failed project-task request of kind [action].
String projectTaskErrorMessage(AppError error, ProjectTaskAction action) =>
    isGenericForbidden(error) ? projectTaskForbiddenCopy[action]! : error.bareMessage;

/// [error] with its message replaced by [projectTaskErrorMessage] — for an
/// error state that renders `AppError.message`.
AppError projectTaskError(AppError error, ProjectTaskAction action) => AppError(
      type: error.type,
      message: projectTaskErrorMessage(error, action),
      statusCode: error.statusCode,
      fieldErrors: error.fieldErrors,
      cause: error.cause,
      code: error.code,
      extra: error.extra,
    );
