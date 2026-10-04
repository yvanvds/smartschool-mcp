import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_writes.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `replace_skore_teacher`: gives an assignment ("lesopdracht") of a course
/// of a class in Skore another teacher, with the library's
/// [SkoreService.replaceTeacher] (dartschool#71). The assignment, and its
/// gradebook, stay.
///
/// It changes Skore for the whole school, so the tool is marked destructive
/// (for Claude Desktop to ask for approval before every call). The library
/// reads the class and the teachers again and refuses a change that does
/// not fit, and refuses when the current teacher works with "Mijn
/// lesgroepen" for the course (it never deletes those groups), saving
/// nothing; it sends the save once, never again after logging in again, and
/// a save Skore does not confirm is reported as maybe saved
/// ([skoreWriteNotConfirmed]).
ServerTool replaceSkoreTeacherTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'replace_skore_teacher',
    title: 'Give an assignment of a course in Skore another teacher',
    description:
        'Gives an assignment (Skore\'s "lesopdracht") on a course of a class '
        'in Skore, the Smartschool module for scores and reports, another '
        'teacher, as choosing another name for it on the class\'s page in '
        'Skore does. The assignment and its gradebook stay, with the same '
        'assignment id; only its teacher changes: the teacher it had is no '
        'longer on the course. Each teacher on a course has an assignment of '
        'their own: take its assignment id from list_skore_courses. Before calling this tool, read the class with '
        'list_skore_courses and look up the new teacher with '
        'list_skore_teachers; show the user the class, the course (its '
        'label), the teacher of the assignment now and the new one, and only '
        'call this tool after the user has explicitly confirmed it. To add a '
        'teacher next to those on the course instead, use add_skore_teacher. '
        'A teacher who already has an assignment on the course cannot get '
        'another one. When the teacher of the assignment now works with '
        '"Mijn lesgroepen" (their own groups of pupils) for the course, '
        'nothing is saved: those groups have to be handled in Skore itself, '
        'and the server never deletes them. The server reads the class and '
        'the teachers again before it saves, and refuses a change that does '
        'not fit, saving nothing: the result says why. The result gives the '
        'assignment as saved. If the result says the change may or may not '
        'have been saved, do not call this tool again for it: read the class '
        'with list_skore_courses and tell the user. Only for an account with '
        'the rights for score management in Skore; without them, the tool '
        'says so.',
    inputSchema: Schema.object(
      properties: {
        'class_id': Schema.int(
          description: 'The Skore class id, from list_skore_classes.',
          minimum: 1,
        ),
        'course_id': Schema.int(
          description:
              'The course id of the course in that class, from '
              'list_skore_courses (not its code, which is not unique).',
          minimum: 1,
        ),
        'assignment_id': Schema.int(
          description:
              'The assignment id on that course whose teacher changes, from '
              'list_skore_courses.',
          minimum: 1,
        ),
        'teacher_id': Schema.int(
          description:
              'The teacher id of the new teacher, from list_skore_teachers.',
          minimum: 1,
        ),
      },
      required: ['class_id', 'course_id', 'assignment_id', 'teacher_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Give an assignment of a course in Skore another teacher',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _replace(session, request.arguments ?? const {}),
);

Future<CallToolResult> _replace(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final classId = requiredIntArgument(arguments, 'class_id');
  final courseId = requiredIntArgument(arguments, 'course_id');
  final assignmentId = requiredIntArgument(arguments, 'assignment_id');
  final teacherId = requiredIntArgument(arguments, 'teacher_id');

  try {
    final assignment = await withSkoreWrite(
      session,
      (skore) => skore.replaceTeacher(
        classId: classId,
        courseId: courseId,
        assignmentId: assignmentId,
        teacherId: teacherId,
      ),
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Gave assignment $assignmentId on '
                '${formatSkoreCourseName(assignment.course)} of class id '
                '$classId another teacher in Skore: '
                '${skoreName(assignment.teacherName)}'
                '${_insteadOf(assignment.replaced)}. The assignment and its '
                'gradebook stay; only its teacher changed.',
            'Saved: ${formatSkoreAssignment(assignment)}.',
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // The course and the teacher the assignment had, as the library read
    // them before the save, from its error (dartschool#120). Caught as the
    // base type, so that a save Skore did not confirm is never reported as an
    // unexpected error: by id for an error without them, which replaceTeacher
    // does not throw.
    final (course, had) = switch (error) {
      SmartschoolSkoreAssignmentSaveUnconfirmedError(
        :final course,
        :final replaced,
      ) =>
        (formatSkoreCourseName(course), replaced),
      _ => ('course id $courseId', null),
    };
    return skoreWriteNotConfirmed(
      tool: 'replace_skore_teacher',
      what:
          'Giving assignment $assignmentId on $course of class id $classId '
          'teacher id $teacherId${_insteadOf(had)}',
      check:
          'read the class with list_skore_courses (class_id $classId): when '
          'assignment $assignmentId has teacher id $teacherId, it was saved; '
          'when it still has '
          '${had == null ? 'the teacher it had' : formatSkoreTeacherOf(had)}, '
          'nothing was saved',
      error: error,
    );
  }
}

/// ` instead of Willems, Wim (teacher id 1005)`, the teacher of [replaced],
/// the assignment as the library read it before the save; empty when it is
/// null (never for a replace).
String _insteadOf(SkoreAssignment? replaced) =>
    replaced == null ? '' : ' instead of ${formatSkoreTeacherOf(replaced)}';
