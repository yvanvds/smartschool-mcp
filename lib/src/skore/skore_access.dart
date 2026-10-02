import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/server_tool.dart';

// Reaching Smartschool's Skore module for the Skore tools: the session
// runner, Skore's errors as ToolErrors, and the access check of
// smartschool_status.

/// The rights the Skore tools need, as `smartschool_status` and the
/// messages name them.
const skoreRights =
    'the rights for score management in Skore (Rapporten > Modellen and '
    'Puntenboeken), as a Skore administrator has';

/// Runs [action] with a [SkoreService] on the session's logged-in client.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; the
/// reads are.
///
/// Skore's own errors, which [SmartschoolSession.run] passes on as they
/// are, become [ToolError]s ([skoreToolError]); login and connection
/// failures stay `SmartschoolProblem`s.
Future<T> withSkore<T>(
  SmartschoolSession session,
  Future<T> Function(SkoreService skore) action,
) async {
  try {
    return await session.run((client) => action(SkoreService(client)));
  } catch (error) {
    final toolError = skoreToolError(error, session.source);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of [SkoreService], or null for
/// anything else. [source] is where the user turns "Skore-beheer" off.
///
/// - [SmartschoolSkoreAccessDeniedError]: Skore refused the request to the
///   account (HTTP 403), which lacks the rights for that part of Skore.
/// - Any other [SmartschoolSkoreError]: an answer the server cannot use.
///   What Skore answers an account without the rights has not been
///   captured yet (yvanvds/dartschool#91): it most likely ends up here (an
///   HTML page instead of data), not as the error above. So, until it is,
///   the message says that the account usually lacks the rights (a
///   workaround; its removal is #74). The library's message can quote
///   Skore's page, which may hold names, so it goes to the log only.
///
/// The writes' errors (#43, #44: a [SmartschoolSkoreChangeRefusedError],
/// whose message says why a change was refused) need a case of their own,
/// before the last one.
ToolError? skoreToolError(Object error, CredentialSource source) {
  switch (error) {
    case SmartschoolSkoreAccessDeniedError(:final area):
      log('skore: $error');
      return ToolError(skoreAccessDenied(area, source));
    case SmartschoolSkoreError():
      log('skore: $error');
      return ToolError(
        'Skore gave an answer the server could not use; usually the account '
        'lacks $skoreRights. If so, ${_fix(source)}. Otherwise try again in '
        'a moment; the technical details are in the server log.',
      );
  }
  return null;
}

/// What the Skore tools say when Skore refused [area] to the account.
String skoreAccessDenied(SkoreAccessArea area, CredentialSource source) {
  final part = switch (area) {
    SkoreAccessArea.reportManagement =>
      'report management (Rapporten > Modellen)',
    SkoreAccessArea.gradebookManagement =>
      'gradebook management (Puntenboeken)',
  };
  return 'This account has no rights for score management in Skore: Skore '
      'refused it its $part. The Skore tools need $skoreRights: '
      '${_fix(source)}.';
}

/// What the user does about missing rights, to end a sentence with.
String _fix(CredentialSource source) =>
    "ask the school's Smartschool administrator for them, or turn off "
    '${source.name(Setting.skore)} ${source.where}, then ${source.restart}';

/// Whether the account can use the Skore tools, for `smartschool_status`:
/// one cheap read, the teachers Skore lets assign
/// ([SkoreService.getTeachers]).
///
/// An answer Skore refuses or the server cannot use is no access, with the
/// message the tools give. So is an empty list of teachers: a school's
/// Skore always has teachers, and an account without the rights may get an
/// empty answer (yvanvds/dartschool#91; a workaround, its removal is #74).
///
/// Throws a `SmartschoolProblem` when it cannot log in or reach
/// Smartschool.
Future<AccessCheck> checkSkoreAccess(SmartschoolSession session) async {
  final List<SkoreTeacher> teachers;
  try {
    teachers = await withSkore(session, (skore) => skore.getTeachers());
  } on ToolError catch (error) {
    return AccessCheck.denied(error.message);
  }
  if (teachers.isEmpty) {
    return AccessCheck.denied(
      'Skore lists no teachers that can be assigned, as it may for an '
      'account without $skoreRights. If so, ${_fix(session.source)}.',
    );
  }
  return AccessCheck.granted(
    'Skore lists ${teachers.length} '
    '${teachers.length == 1 ? 'teacher' : 'teachers'} that can be assigned',
  );
}
