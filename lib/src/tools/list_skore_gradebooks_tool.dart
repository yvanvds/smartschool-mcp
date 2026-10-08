import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_gradebooks`: the user's own gradebooks in Skore of a school
/// year ([SkoreGradebookService.getGradebookYear], dartschool#148), with the
/// school years Skore offers; optionally only those whose class or course
/// holds some words.
///
/// Offered to every account, without a switch: the gradebook needs no
/// extra rights in Smartschool.
ServerTool listSkoreGradebooksTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_gradebooks',
    title: 'List the user\'s gradebooks in Skore',
    description:
        'Lists the user\'s own gradebooks in Skore, the Smartschool module '
        'for scores and reports, as its gradebook ("Puntenboek") lists them, '
        'for one school year: one line per gradebook with its class, its '
        'course (with the grade Skore adds, such as "(6e j DO)") and its '
        'gradebook id, in Skore\'s order. Pass the gradebook id to '
        'read_skore_gradebook for its periods and pupils. Without '
        'workyear_id, the gradebooks of Skore\'s current school year; the '
        'result also lists the school years Skore offers, each with its '
        'workyear id, to ask for an earlier one. To find a gradebook, pass '
        'query with (part of) the name of its class or course, such as 5WW '
        'or Wiskunde. An account without gradebooks of its own in that '
        'school year gets a sentence saying so. Reading changes nothing in '
        'Skore.',
    inputSchema: Schema.object(
      properties: {
        'workyear_id': Schema.int(
          description:
              'The school year, by the workyear id this tool lists with the '
              'school years Skore offers. Default: Skore\'s current school '
              'year.',
          minimum: 1,
        ),
        'query': Schema.string(
          description:
              'Words that must all occur in the name of the class or of the '
              'course, ignoring case and accents, also as part of a longer '
              'word: 5WW finds 5WW1 and 5WW2. Default: all gradebooks of the '
              'school year.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the user\'s gradebooks in Skore',
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
  final workyearId = intArgument(arguments, 'workyear_id');
  final query = (arguments['query'] as String? ?? '').trim();
  final years = SkoreGradebookYears.of(session);
  final year = await withSkoreGradebook(
    session,
    (gradebooks) => years.read(gradebooks, workyearId: workyearId),
  );
  return CallToolResult(
    content: [TextContent(text: formatSkoreGradebookYear(year, query))],
  );
}

/// What `list_skore_gradebooks` answers: the gradebooks of [year] whose
/// class or course holds every word of [query] (all of them for an empty
/// query), one per line in Skore's order, and the school years Skore
/// offers.
String formatSkoreGradebookYear(SkoreGradebookYear year, String query) {
  final gradebooks = year.gradebooks;
  final where = 'school year ${formatSkoreWorkyear(year.workyear)}';
  final workyears = formatSkoreWorkyears(year.workyears, year.workyear);
  if (gradebooks.isEmpty) {
    return 'The user has no gradebooks of their own in Skore for $where.\n'
        '$workyears';
  }
  final all = _gradebooks(gradebooks.length);
  if (query.isEmpty) {
    return [
      'The user has $all of their own in Skore for $where, in Skore\'s '
          'order:',
      for (final gradebook in gradebooks)
        '- ${formatSkoreOwnGradebook(gradebook)}',
      workyears,
    ].join('\n');
  }
  final found = skoreMatches(
    gradebooks,
    query,
    (g) => [g.className, g.courseName],
  );
  if (found.isEmpty) {
    return 'None of the user\'s $all in Skore for $where has "$query" in the '
        'name of its class or course. Look for a part of the name, such as '
        '5WW or Wiskunde, or leave out query to list them all.\n'
        '$workyears';
  }
  return [
    'Skore finds ${found.length} for "$query" among the user\'s $all for '
        '$where, in Skore\'s order:',
    for (final gradebook in found) '- ${formatSkoreOwnGradebook(gradebook)}',
    workyears,
  ].join('\n');
}

/// [count] gradebooks in words: `1 gradebook`, `4 gradebooks`.
String _gradebooks(int count) =>
    '$count ${count == 1 ? 'gradebook' : 'gradebooks'}';
