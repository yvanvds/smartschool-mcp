import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'skore_access.dart';

// Changing Skore, shared by the Skore tools that write (`add_skore_teacher`,
// `replace_skore_teacher`): running a write, how a change Skore refused or
// did not confirm is reported, and reading the course a write is about.
//
// The library does the checks before each write (it reads the class and the
// teachers again, and refuses a course that is not in the class or is a group
// header, an assignment that is not the course's, a teacher already on the
// course or not one Skore lets assign, and a current teacher with "Mijn
// lesgroepen"), sends the save (`saveOwner`) once, never again after logging
// in again, and throws a [SmartschoolSkoreSaveUnconfirmedError] when Skore's
// answer does not confirm a save that went out. That is why repeating a
// write's action, as [SmartschoolSession.run] does when Smartschool refused
// the session, cannot make a change twice: a refused session means the save
// was not carried out, the repeat reads the class again (a teacher who is on
// the course by then is refused), and an unconfirmed save is not a refused
// session, so it is not repeated.

/// What a Skore write tool adds to an error that came before anything was
/// saved.
const nothingChangedInSkore = 'Nothing was changed in Skore.';

/// Runs the Skore write [write] with [withSkore], for a tool that changes
/// Skore.
///
/// A [ToolError] (a check refused the change, the account lacks the rights,
/// a read before the save failed) says that nothing was changed: from the
/// writes, every [SmartschoolSkoreError] means that nothing was saved. A
/// [SmartschoolSkoreSaveUnconfirmedError] is thrown as it is: the change may
/// or may not have been saved ([skoreWriteNotConfirmed]).
Future<T> withSkoreWrite<T>(
  SmartschoolSession session,
  Future<T> Function(SkoreService skore) write,
) async {
  try {
    return await withSkore(session, write);
  } on ToolError catch (error) {
    throw ToolError('${error.message} $nothingChangedInSkore');
  }
}

/// The result of a Skore write that went out without Skore confirming it
/// ([error]): [what] (like `Assigning teacher id 1005 to course id 2142 of
/// class id 2516`) may or may not have been saved. Claude must not call
/// [tool] again for it, but first [check] (like `read the class with
/// list_skore_courses …: when …, it was saved; when …, nothing was saved`)
/// and tell the user.
///
/// The library's message can quote Skore's answer, so it goes to the log
/// only.
CallToolResult skoreWriteNotConfirmed({
  required String tool,
  required String what,
  required String check,
  required SmartschoolSkoreSaveUnconfirmedError error,
}) {
  log(
    '$tool: Skore did not confirm a save, not retrying: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            '$what may or may not have been saved: the change was sent, but '
            'Skore did not confirm it. Do not call $tool again for it: first '
            '$check. Then tell the user what you found.',
      ),
    ],
  );
}

/// Course [courseId] of class [classId] as Skore lists it now
/// ([SkoreService.getCourses]), or null when the class has no such course.
///
/// The writes return only the assignment they saved, so a write tool reads
/// the course itself to name it (its label) and, for a replace, the teacher
/// it replaces (a workaround until yvanvds/dartschool#102; its removal is
/// #74). It refuses nothing itself: the library reads the class again and
/// refuses a course that does not fit.
Future<SkoreCourse?> readSkoreCourse(
  SkoreService skore,
  int classId,
  int courseId,
) async => (await skore.getCourses(
  classId,
)).where((c) => c.id == courseId && c.classId == classId).firstOrNull;
