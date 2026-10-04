import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_access.dart';
import '../skore/skore_format.dart';
import 'server_tool.dart';

/// `list_skore_teachers`: the teachers Skore lets assign to a course, with
/// their teacher ids; optionally only those whose name holds some words.
ServerTool listSkoreTeachersTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_teachers',
    title: 'List the teachers in Skore',
    description:
        'Lists the teachers that Skore, the Smartschool module for scores '
        'and reports, lets assign to a course: one line per teacher with '
        'the name as Skore shows it (last name first) and the teacher id '
        'Skore uses, which is the Smartschool user id, in Skore\'s order. '
        'To find someone, pass query with (part of) the name. Who is '
        'assigned to the courses of a class is shown by list_skore_courses. '
        'Only for an account with the rights for score management in Skore; '
        'without them, the tool says so. Reading changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the name, in any order, '
              'ignoring case and accents, also as part of a longer word: '
              'celine dupre finds Dupré, Céline. Default: all of them.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the teachers in Skore',
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
  final query = (arguments['query'] as String? ?? '').trim();
  final teachers = await withSkore(session, (skore) => skore.getTeachers());
  return CallToolResult(
    content: [TextContent(text: formatSkoreTeachers(teachers, query))],
  );
}

/// What `list_skore_teachers` answers: the [teachers] whose name holds
/// every word of [query] (all of them for an empty query), one per line, in
/// Skore's order.
String formatSkoreTeachers(List<SkoreTeacher> teachers, String query) {
  if (teachers.isEmpty) {
    return 'Skore lists no teachers that can be assigned.';
  }
  final found = skoreMatches(teachers, query, (teacher) => [teacher.name]);
  final all =
      '${teachers.length} ${teachers.length == 1 ? 'teacher' : 'teachers'}';
  if (query.isEmpty) {
    return [
      'Skore lists $all that can be assigned:',
      for (final teacher in teachers) '- ${formatSkoreTeacher(teacher)}',
    ].join('\n');
  }
  if (found.isEmpty) {
    return 'None of the $all that Skore can assign has "$query" in the name. '
        'Look for a part of the name, or leave out query to list them all.';
  }
  return [
    'Skore finds ${found.length} of its $all for "$query":',
    for (final teacher in found) '- ${formatSkoreTeacher(teacher)}',
  ].join('\n');
}
