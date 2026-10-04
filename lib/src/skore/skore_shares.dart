import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../problems.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'skore_access.dart';
import 'skore_format.dart';
import 'skore_writes.dart';

// Sharing a teacher's gradebook with other teachers, and no longer sharing
// it, for `share_skore_gradebook` and `unshare_skore_gradebook` (#44), on the
// library's `shareGradebook` and `unshareGradebook` (dartschool#74).
//
// The library changes the shares for one teacher per call. Before each, it
// reads the owner's gradebooks again (and, to share, the teachers), refuses a
// change that does not fit, and saves nothing when the teacher already has
// the access asked (to unshare: has none). Its save (`saveShared`) holds the
// complete readers and writers of that one gradebook, so sending it again
// does not change the outcome: the library sends it again after logging in
// again, and a repeat of a call by [SmartschoolSession.run] reads the
// gradebook again first. After the save it reads the gradebooks again, and
// throws a [SmartschoolSkoreSaveUnconfirmedError] unless they show exactly
// what it saved: a teacher reported as done is certain. It returns the
// gradebook after the call with what it read before and whether it saved
// anything ([SkoreGradebookShareChange], dartschool#103), which the result
// reports per teacher.

/// At most this many teachers per call of `share_skore_gradebook` or
/// `unshare_skore_gradebook`: more than teach one class.
const maxSkoreShareTeachers = 50;

/// What a change of a gradebook's shares that Skore refused tells Claude to
/// read again.
const rereadSkoreGradebook =
    'Read the gradebook again with list_skore_gradebook_shares (and the '
    'teachers with list_skore_teachers)';

/// The `owner_id` argument of the tools that change a gradebook's shares.
Schema skoreOwnerIdSchema() => Schema.int(
  description:
      'The teacher id of the owner of the gradebook: the teacher of its '
      'assignment in list_skore_courses.',
  minimum: 1,
);

/// The `gradebook_id` argument of the tools that change a gradebook's
/// shares.
Schema skoreGradebookIdSchema() => Schema.int(
  description:
      'The gradebook id: the assignment id in list_skore_courses, or the '
      'gradebook id in list_skore_gradebook_shares.',
  minimum: 1,
);

/// The `teacher_ids` argument of the tools that change a gradebook's
/// shares: 1 to [maxSkoreShareTeachers] teacher ids.
Schema skoreShareTeachersSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.int(minimum: 1),
  minItems: 1,
  maxItems: maxSkoreShareTeachers,
);

/// What happened to one teacher of a change of a gradebook's shares.
enum _Outcome {
  /// Saved, and confirmed by reading the gradebook again
  /// ([SkoreGradebookShareChange.saved]).
  changed,

  /// The teacher already had that access (to unshare: had none), so nothing
  /// was saved ([SkoreGradebookShareChange.saved] false).
  unchanged,

  /// Refused, failed or not confirmed: the change stopped here.
  failed,

  /// After the teacher that failed.
  notTried,
}

/// Shares gradebook [gradebookId] of teacher [ownerId] with [teacherIds],
/// with [access], or, when [access] is null, no longer shares it with them;
/// the result of [tool].
///
/// First reads the teachers, to name them in the result (the join #44 asked
/// for: the library gives the teachers of a gradebook by id). Then makes the
/// change for one teacher after the other, each in a session action of its
/// own, and stops at the first that fails: a change Skore refused, a login
/// or connection that failed, or a save Skore did not confirm. The result
/// says per teacher what was done, from the library's result (whether it
/// saved anything, and the access the teacher had before), and gives the
/// gradebook after the change; it is an error when the change stopped. It
/// names the gradebook from the first result, or, when the save for the
/// first teacher is not confirmed, from the error, which carries the
/// gradebook as the library read it before the save (dartschool#120). So by
/// its id only when the change stopped at the first teacher before a save
/// (refused, or a login or connection that failed): nothing was returned
/// then.
Future<CallToolResult> changeSkoreShares(
  SmartschoolSession session, {
  required String tool,
  required int ownerId,
  required int gradebookId,
  required List<int> teacherIds,
  required SkoreShareAccess? access,
}) async {
  final names = skoreTeacherNames(
    await withSkoreWrite(session, (skore) => skore.getTeachers()),
  );
  String teacher(int id) => formatSkoreTeacherId(id, names);

  // The gradebook after the last change, and named from the first result
  // (or from the error of a first save Skore did not confirm).
  SkoreGradebookShareChange? gradebook;
  var named = _gradebookName(null, gradebookId, ownerId, names);
  final outcomes = <(int, _Outcome, SkoreShareAccess?)>[];
  int? stoppedAt;
  String? why;
  var unconfirmed = false;
  for (final teacherId in teacherIds) {
    if (stoppedAt != null) {
      outcomes.add((teacherId, _Outcome.notTried, null));
      continue;
    }
    try {
      final change = await withSkore(
        session,
        (skore) => access == null
            ? skore.unshareGradebook(
                ownerId: ownerId,
                gradebookId: gradebookId,
                teacherId: teacherId,
              )
            : skore.shareGradebook(
                ownerId: ownerId,
                gradebookId: gradebookId,
                teacherId: teacherId,
                access: access,
              ),
        reread: rereadSkoreGradebook,
      );
      if (gradebook == null) {
        named = _gradebookName(change, gradebookId, ownerId, names);
      }
      gradebook = change;
      outcomes.add((
        teacherId,
        change.saved ? _Outcome.changed : _Outcome.unchanged,
        change.accessBefore,
      ));
      continue;
    } on ToolError catch (error) {
      why = error.message;
    } on SmartschoolProblem catch (problem) {
      why = problem.message;
    } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
      unconfirmed = true;
      if (gradebook == null &&
          error is SmartschoolSkoreShareSaveUnconfirmedError) {
        named = _gradebookName(error.before, gradebookId, ownerId, names);
      }
      why = skoreNotConfirmed(
        tool: tool,
        what: access == null
            ? 'Unsharing $named with ${teacher(teacherId)}'
            : 'Sharing $named with ${teacher(teacherId)} with '
                  '${access.name} access',
        check:
            'read the gradebooks with list_skore_gradebook_shares '
            '(teacher_id $ownerId): ${_check(gradebookId, teacherId, access)}',
        error: error,
      );
    }
    stoppedAt = teacherId;
    outcomes.add((teacherId, _Outcome.failed, null));
  }

  final accessText = access == null ? null : _accessText(access);
  final changed = outcomes.any((o) => o.$2 == _Outcome.changed);
  final heading = switch ((stoppedAt, access)) {
    (final id?, null) => 'Unsharing $named in Skore stopped at ${teacher(id)}:',
    (final id?, _?) =>
      'Sharing $named in Skore with $accessText stopped at ${teacher(id)}:',
    (null, null) when changed =>
      'Stopped sharing $named in Skore with these teachers:',
    (null, null) =>
      'Nothing changed in Skore: $named was not shared with these teachers, '
          'so nothing was saved:',
    (null, _?) when changed => 'Shared $named in Skore with $accessText:',
    (null, _?) =>
      'Nothing changed in Skore: $named was already shared with these '
          'teachers that way, so nothing was saved:',
  };
  final untried = outcomes.any((o) => o.$2 == _Outcome.notTried)
      ? ' The teachers listed after them were not tried.'
      : '';
  return CallToolResult(
    isError: stoppedAt != null,
    content: [
      TextContent(
        text: [
          heading,
          for (final (teacherId, outcome, before) in outcomes)
            '- ${teacher(teacherId)}: '
                '${_outcomeText(outcome, access, before, unconfirmed)}',
          if (stoppedAt != null)
            unconfirmed
                ? '$why$untried'
                : '$why Nothing was saved for ${teacher(stoppedAt)}.$untried',
          if (gradebook != null && !unconfirmed) ...[
            'The gradebook now:',
            '- ${formatSkoreGradebook(gradebook, names)}',
          ],
        ].join('\n'),
      ),
    ],
  );
}

/// Gradebook [gradebookId] of teacher [ownerId] in a sentence, with the
/// course and class of [gradebook] (null when the library gave none):
/// for example `gradebook 34826 ("Digitale vaardigheden", class 5WW1) of
/// Willems, Wim (teacher id 1005)`.
String _gradebookName(
  SkoreGradebookShares? gradebook,
  int gradebookId,
  int ownerId,
  Map<int, String> names,
) {
  final owner = formatSkoreTeacherId(ownerId, names);
  if (gradebook == null) return 'gradebook $gradebookId of $owner';
  return 'gradebook $gradebookId ("${skoreName(gradebook.courseName)}", '
      'class ${skoreName(gradebook.className)}) of $owner';
}

/// [access] in a sentence, with what it allows.
String _accessText(SkoreShareAccess access) => switch (access) {
  SkoreShareAccess.read => 'read access (they may read it)',
  SkoreShareAccess.write => 'write access (they may read and change it)',
};

/// What happened to a teacher who had [before] (null: no access through a
/// share), for a change to [access] (null: unshare).
String _outcomeText(
  _Outcome outcome,
  SkoreShareAccess? access,
  SkoreShareAccess? before,
  bool unconfirmed,
) => switch ((outcome, access)) {
  (_Outcome.notTried, _) => 'not tried',
  (_Outcome.failed, null) =>
    unconfirmed
        ? 'may or may not have been unshared (see below)'
        : 'not unshared (see below)',
  (_Outcome.failed, _?) =>
    unconfirmed
        ? 'may or may not have been shared (see below)'
        : 'not shared (see below)',
  (_Outcome.unchanged, null) => 'was not shared with them; nothing saved',
  (_Outcome.unchanged, final access?) =>
    'already had ${access.name} access; nothing saved',
  (_Outcome.changed, null) => 'unshared (had ${before?.name} access)',
  (_Outcome.changed, final access?) =>
    before == null
        ? 'shared with ${access.name} access'
        : 'now ${access.name} access instead of ${before.name} access',
};

/// How to tell from list_skore_gradebook_shares whether a change of teacher
/// [teacherId] to [access] (null: unshare) was saved.
String _check(int gradebookId, int teacherId, SkoreShareAccess? access) {
  final among = switch (access) {
    SkoreShareAccess.read => 'among its readers',
    SkoreShareAccess.write => 'among its writers',
    null => 'among its readers or writers',
  };
  return access == null
      ? 'when gradebook $gradebookId no longer lists teacher id $teacherId '
            '$among, it was saved; when it still does, nothing was saved'
      : 'when gradebook $gradebookId lists teacher id $teacherId $among, it '
            'was saved; when it does not, nothing was saved';
}
