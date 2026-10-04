import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_access.dart';
import '../skore/skore_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_courses`: the courses of one class in Skore, nested, with the
/// teachers assigned to each (Skore's "lesopdrachten").
ServerTool listSkoreCoursesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_courses',
    title: 'List the courses of a class in Skore',
    description:
        'Lists the courses of one class in Skore, the Smartschool module for '
        'scores and reports, with the teachers assigned to each (Skore\'s '
        '"lesopdrachten"), in Skore\'s order. One line per row: its label '
        'with the course code in square brackets, the course id, the code, '
        'its depth, and then which teachers are assigned: each with name, '
        'teacher id and assignment id; the assignment id is also the id of '
        'its gradebook. A row without a teacher says whether it is a group '
        'header (a heading for the courses under it, which cannot get a '
        'teacher), a course with sub-courses (which needs no teacher of its '
        'own: its sub-courses carry the assignments), or a course with "no '
        'teacher". The rows are nested: a row belongs to the nearest row '
        'above it with a smaller depth. Only the courses marked "no teacher" '
        'still need a teacher; the first line counts them as without a '
        'teacher. Use it for questions such as "wie geeft wiskunde in 3B1?" '
        'or "welke vakken van 5WW1 hebben nog geen leerkracht?" (the courses '
        'marked "no teacher"). Course codes are not unique within a class (a '
        'course and its sub-course can share one), so name a course by its '
        'course id. Take class_id from list_skore_classes. An empty list '
        'means that the class has no course structure in Skore yet, or that '
        'no class has that id. Only for an account with the rights for score '
        'management in Skore; without them, the tool says so. Reading '
        'changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'class_id': Schema.int(
          description: 'The Skore class id, from list_skore_classes.',
          minimum: 1,
        ),
      },
      required: ['class_id'],
    ),
    annotations: ToolAnnotations(
      title: 'List the courses of a class in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final classId = requiredIntArgument(arguments, 'class_id');
  final courses = await withSkore(
    session,
    (skore) => skore.getCourses(classId),
  );
  return CallToolResult(
    content: [TextContent(text: formatSkoreCourses(classId, courses))],
  );
}

/// What `list_skore_courses` answers: the rows of class [classId] in
/// Skore's order, nested by depth, after a line that counts them and the
/// courses that still need a teacher ([skoreNeedsTeacher]).
String formatSkoreCourses(int classId, List<SkoreCourse> courses) {
  if (courses.isEmpty) {
    return 'Skore lists no courses for class id $classId: the class has no '
        'course structure in Skore yet (Skore links one under Koppeling), '
        'or no class has that id. Take the class id from '
        'list_skore_classes.';
  }
  final headers = courses.where((course) => course.isGroupHeader).length;
  final assignable = courses.length - headers;
  // Not the courses with sub-courses: they need no teacher of their own
  // (#100).
  final withoutTeacher = [
    for (var index = 0; index < courses.length; index++)
      if (skoreNeedsTeacher(courses, index)) index,
  ].length;
  final counts = [
    '$assignable ${assignable == 1 ? 'course' : 'courses'}'
        '${withoutTeacher == 0 ? '' : ' ($withoutTeacher without a teacher)'}',
    if (headers > 0) '$headers group ${headers == 1 ? 'header' : 'headers'}',
  ];
  return [
    'Skore class id $classId: ${counts.join(' and ')}, in Skore\'s order; '
        'each row belongs to the nearest row above it with a smaller depth.',
    for (final (index, course) in courses.indexed)
      formatSkoreCourse(
        course,
        hasSubCourses: skoreHasSubCourses(courses, index),
      ),
  ].join('\n');
}
