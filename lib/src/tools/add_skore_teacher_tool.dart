import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_writes.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `add_skore_teacher`: assigns a teacher to a course of a class in Skore, a
/// new assignment ("lesopdracht"), with the library's
/// [SkoreService.addTeacher] (dartschool#71).
///
/// It changes Skore for the whole school, so the tool is marked destructive
/// (for Claude Desktop to ask for approval before every call). The library
/// reads the class and the teachers again and refuses a change that does
/// not fit, saving nothing; it sends the save once, never again after
/// logging in again, and a save Skore does not confirm is reported as maybe
/// saved ([skoreWriteNotConfirmed]).
ServerTool addSkoreTeacherTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'add_skore_teacher',
    title: 'Assign a teacher to a course of a class in Skore',
    description:
        'Assigns a teacher to a course of a class in Skore, the Smartschool '
        'module for scores and reports: a new assignment (Skore\'s '
        '"lesopdracht"), as the green + on the class\'s page in Skore adds. '
        'The new assignment holds all pupils of the class and has a '
        'gradebook of its own; the teachers already on the course keep '
        'theirs. Before calling this tool, read the class with '
        'list_skore_courses and look up the teacher with '
        'list_skore_teachers; show the user the class, the course (its '
        'label), the teachers it has now and the teacher to assign, and only '
        'call this tool after the user has explicitly confirmed it. If the '
        'teacher to assign already has an assignment on the course, nothing '
        'needs to happen: do not call this tool. To give a course another '
        'teacher instead of one it has, use replace_skore_teacher, not this '
        'tool: this tool adds a teacher next to those on the course. A group '
        'header cannot get a teacher. The server reads the class and the '
        'teachers again before it saves, and refuses a change that does not '
        'fit, saving nothing: the result says why. The result gives the '
        'assignment as saved, with its assignment id. If the result says '
        'the change may or may not have been saved, do not call this tool '
        'again for it: read the class with list_skore_courses and tell the '
        'user. Only for an account with the rights for score management in '
        'Skore; without them, the tool says so.',
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
        'teacher_id': Schema.int(
          description:
              'The teacher id of the teacher to assign, from '
              'list_skore_teachers.',
          minimum: 1,
        ),
      },
      required: ['class_id', 'course_id', 'teacher_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Assign a teacher to a course of a class in Skore',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, request.arguments ?? const {}),
);

Future<CallToolResult> _add(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final classId = requiredIntArgument(arguments, 'class_id');
  final courseId = requiredIntArgument(arguments, 'course_id');
  final teacherId = requiredIntArgument(arguments, 'teacher_id');

  try {
    final assignment = await withSkoreWrite(
      session,
      (skore) => skore.addTeacher(
        classId: classId,
        courseId: courseId,
        teacherId: teacherId,
      ),
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Assigned ${skoreName(assignment.teacherName)} to '
                '${formatSkoreCourseName(assignment.course)} of class id '
                '$classId in Skore: a new assignment, which holds all pupils '
                'of the class.',
            'Saved: ${formatSkoreAssignment(assignment)}. The assignment id '
                'is also the id of its gradebook.',
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // The course by id only: the error carries nothing of the course the
    // library read (dartschool#120).
    return skoreWriteNotConfirmed(
      tool: 'add_skore_teacher',
      what:
          'Assigning teacher id $teacherId to course id $courseId of class id '
          '$classId',
      check:
          'read the class with list_skore_courses (class_id $classId): when '
          'course id $courseId lists teacher id $teacherId, it was saved; '
          'when it does not, nothing was saved',
      error: error,
    );
  }
}
