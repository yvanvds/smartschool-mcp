import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/server_tool.dart';
import 'skore_format.dart';

// Reaching Smartschool's Skore module for the Skore tools: the session
// runner, Skore's errors as ToolErrors, and the access check of
// smartschool_status.

/// The rights the Skore tools need, as `smartschool_status` and the
/// messages name them.
const skoreRights =
    'the rights for score management in Skore (Rapporten > Modellen and '
    'Puntenboeken), as a Skore administrator has';

/// What a change Skore refused tells Claude to read again, to correct the
/// call: for the writes on the courses of a class (#43).
const rereadSkoreClass =
    'Read the class again with list_skore_courses (and the teachers with '
    'list_skore_teachers)';

/// Runs [action] with a [SkoreService] on the session's logged-in client.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; the
/// reads are, and so are the library's writes (see `skore_writes.dart`).
///
/// Skore's own errors, which [SmartschoolSession.run] passes on as they
/// are, become [ToolError]s ([skoreToolError], with [reread] for a change
/// Skore refused); login and connection failures stay
/// `SmartschoolProblem`s.
Future<T> withSkore<T>(
  SmartschoolSession session,
  Future<T> Function(SkoreService skore) action, {
  String reread = rereadSkoreClass,
}) async {
  try {
    return await session.run((client) => action(SkoreService(client)));
  } catch (error) {
    final toolError = skoreToolError(error, session.source, reread: reread);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of [SkoreService], or null for
/// anything else. [source] is where the user turns "Skore-beheer" off, and
/// [reread] what to read again after a change Skore refused (like
/// [rereadSkoreClass]).
///
/// - [SmartschoolSkoreAccessDeniedError]: Skore refused the request to the
///   account, which lacks the rights for that part of Skore. Skore sends
///   every request of a teacher without the rights on to Smartschool's
///   start page (yvanvds/dartschool#91); the library also takes HTTP 403 for
///   it.
/// - [SmartschoolSkoreMyGroupsError], from a write (`replaceTeacher`): the
///   current teacher of the assignment, named as the library read them
///   (dartschool#102; by id only when the error has no name), works with
///   "Mijn lesgroepen" for the course, so nothing was saved. Those groups are
///   handled in Skore itself; the library never deletes them, and no tool may
///   try another way.
/// - [SmartschoolSkoreChangeRefusedError], from a write: a check before the
///   save refused the change, so nothing was saved. Its message, which the
///   library writes from what it read and quotes nothing else of Skore's
///   answers, is the reason passed on, with [reread], so that Claude can
///   correct the call.
/// - Any other [SmartschoolSkoreError]: an answer the server cannot use
///   (an error page, data in an unknown shape). Not missing rights, which
///   the library reports from every call as the first error above. The
///   library's message can quote Skore's page, which may hold names, so it
///   goes to the log only.
///
/// A write that went out without Skore confirming it
/// ([SmartschoolSkoreSaveUnconfirmedError], deliberately not a
/// [SmartschoolSkoreError]) is not a [ToolError]: the write tools report it
/// themselves, with what to read to check it (`skoreWriteNotConfirmed` in
/// `skore_writes.dart`).
ToolError? skoreToolError(
  Object error,
  CredentialSource source, {
  String reread = rereadSkoreClass,
}) {
  switch (error) {
    case SmartschoolSkoreAccessDeniedError(:final area):
      log('skore: $error');
      return ToolError(skoreAccessDenied(area, source));
    case SmartschoolSkoreMyGroupsError(
      :final classId,
      :final courseId,
      :final teacherId,
      :final teacherName,
    ):
      log('skore: $error');
      final teacher = teacherName == null
          ? ' (teacher id $teacherId)'
          : ', ${skoreName(teacherName)} (teacher id $teacherId),';
      return ToolError(
        'Skore did not save the change: the current teacher of the '
        'assignment$teacher works with "Mijn lesgroepen", their own groups '
        'of pupils, for course id $courseId of class id $classId. Those '
        'groups have to be handled in Skore itself first: '
        'tell the user, who can make this change in Skore, where Skore asks '
        'to delete the groups (which cannot be undone). The server never '
        'deletes them; do not try another way to change this assignment.',
      );
    case SmartschoolSkoreChangeRefusedError(:final message):
      log('skore: $error');
      return ToolError(
        'Skore refused the change before saving it: ${_refusal(message)} '
        '$reread to correct the call.',
      );
    case SmartschoolSkoreError():
      log('skore: $error');
      return const ToolError(
        'Skore gave an answer the server could not use. Try again in a '
        'moment; the technical details are in the server log.',
      );
  }
  return null;
}

/// The reason in [message], the message of a
/// [SmartschoolSkoreChangeRefusedError]: without the name of the library's
/// method in front (`addTeacher: `) and its closing `Nothing was saved.`,
/// which the write tools say in their own words.
String _refusal(String message) {
  final reason = message
      .replaceFirst(RegExp(r'^[A-Za-z]+: '), '')
      .replaceFirst(RegExp(r'\s*Nothing was saved\.\s*$'), '')
      .trim();
  return reason.endsWith('.') ? reason : '$reason.';
}

/// What the Skore tools say when Skore refused [area] to the account.
String skoreAccessDenied(SkoreAccessArea area, CredentialSource source) =>
    _noRights([area], source);

/// That the account has no rights for score management, as Skore refused
/// it the parts of Skore in [refused].
String _noRights(List<SkoreAccessArea> refused, CredentialSource source) =>
    'This account has no rights for score management in Skore: Skore '
    'refused it its ${refused.map(_part).join(' and its ')}. The Skore '
    'tools need $skoreRights: ${_fix(source)}.';

/// [area] as the messages name it.
String _part(SkoreAccessArea area) => switch (area) {
  SkoreAccessArea.reportManagement =>
    'report management (Rapporten > Modellen)',
  SkoreAccessArea.gradebookManagement => 'gradebook management (Puntenboeken)',
};

/// What the user does about missing rights, to end a sentence with.
String _fix(CredentialSource source) =>
    "ask the school's Smartschool administrator for them, or turn off "
    '${source.name(Setting.skore)} ${source.where}, then ${source.restart}';

/// Whether the account can use the Skore tools, for `smartschool_status`:
/// the library's check of each part of Skore ([SkoreService.checkAccess]),
/// with one small read per part: the teachers (report management) and the
/// account's own gradebooks (gradebook management).
///
/// Access when Skore lets the account use both parts, as the tools need
/// ([skoreRights]); no access when it refuses it either or both, as it
/// refuses every request of a teacher without the rights (seen live,
/// yvanvds/dartschool#91).
///
/// Throws a [ToolError] when Skore gives an answer the server cannot use,
/// which is not taken for missing rights ([skoreToolError]), and a
/// `SmartschoolProblem` when it cannot log in or reach Smartschool.
Future<AccessCheck> checkSkoreAccess(SmartschoolSession session) async {
  final usable = await withSkore(session, (skore) => skore.checkAccess());
  final refused = [
    for (final area in SkoreAccessArea.values)
      if (!usable.contains(area)) area,
  ];
  if (refused.isEmpty) {
    return const AccessCheck.granted(
      'Skore lets it use both Rapporten > Modellen and Puntenboeken',
    );
  }
  final source = session.source;
  if (usable.isEmpty) return AccessCheck.denied(_noRights(refused, source));
  return AccessCheck.denied(
    'This account has only part of the rights for score management in '
    'Skore: Skore lets it use its ${usable.map(_part).join(' and its ')}, '
    'but refused it its ${refused.map(_part).join(' and its ')}. The Skore '
    'tools need $skoreRights: ${_fix(source)}.',
  );
}
