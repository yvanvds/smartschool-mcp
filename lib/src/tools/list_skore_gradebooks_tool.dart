import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_gradebooks`: the user's own gradebooks in Skore of a school
/// year ([SkoreGradebookService.getGradebookYear], dartschool#148), then
/// those colleagues shared with them, each with its owner and what the user
/// may do in it (#167, dartschool#191), with the school years Skore offers;
/// optionally only those whose class or course holds some words.
///
/// The shared gradebooks come in a section of their own rather than behind
/// an option: a user does not think of a gradebook a colleague shared with
/// them (such as the behaviour gradebook of a class, shared with its
/// co-titularis) as another kind, and would not know to ask for it; and
/// they are one small request on top of the big read of the own ones,
/// which is kept in memory for the session ([SkoreGradebookYears]) and
/// needs them anyway to find a shared gradebook's id.
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
        'gradebook id, in Skore\'s order. Then, if any, the gradebooks '
        'colleagues shared with the user ("Gedeeld" in Skore, such as the '
        'behaviour gradebook of a class shared with its co-titularis), each '
        'with its owner and whether it is shared to read and write or to read '
        'only. The other gradebook tools take a shared gradebook\'s id as an '
        'own one\'s: one shared to read only can be read, not changed; in one '
        'shared to read and write, grades and feedback can be saved, but no '
        'evaluation created. Pass the gradebook id to '
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
/// query), one per line in Skore's order, first the user's own and then
/// those colleagues shared with them, each with its owner and what the user
/// may do in it (#167), and the school years Skore offers.
///
/// Without gradebooks shared with the user, it says nothing of them: the
/// result is the list of the user's own, as before.
String formatSkoreGradebookYear(SkoreGradebookYear year, String query) {
  final own = year.gradebooks;
  final shared = year.sharedGradebooks;
  final where = 'school year ${formatSkoreWorkyear(year.workyear)}';
  final workyears = formatSkoreWorkyears(year.workyears, year.workyear);
  if (query.isEmpty) {
    return [
      if (own.isEmpty)
        'The user has no gradebooks of their own in Skore for $where.'
      else ...[
        'The user has ${_gradebooks(own.length)} of their own in Skore for '
            '$where, in Skore\'s order:',
        for (final gradebook in own) '- ${formatSkoreOwnGradebook(gradebook)}',
      ],
      ..._shared(shared),
      workyears,
    ].join('\n');
  }
  List<SkoreGradebook> matching(List<SkoreGradebook> gradebooks) =>
      skoreMatches(gradebooks, query, (g) => [g.className, g.courseName]);
  final ownFound = matching(own);
  final sharedFound = matching(shared);
  final among = switch ((own.length, shared.length)) {
    (final count, 0) => 'the user\'s ${_gradebooks(count)}',
    (0, final count) => 'the ${_gradebooks(count)} shared with the user',
    (final count, final others) =>
      'the user\'s ${_gradebooks(count)} and the $others shared with them',
  };
  if (ownFound.isEmpty && sharedFound.isEmpty) {
    return 'None of $among in Skore for $where has "$query" in the name of '
        'its class or course. Look for a part of the name, such as 5WW or '
        'Wiskunde, or leave out query to list them all.\n'
        '$workyears';
  }
  return [
    'Skore finds ${ownFound.length + sharedFound.length} for "$query" among '
        '$among for $where, in Skore\'s order:',
    for (final gradebook in ownFound) '- ${formatSkoreOwnGradebook(gradebook)}',
    ..._shared(sharedFound),
    workyears,
  ].join('\n');
}

/// The lines of the gradebooks colleagues shared with the user ([shared],
/// Skore's tab "Gedeeld"), after a line that says what they are; none for
/// none.
List<String> _shared(List<SkoreGradebook> shared) => [
  if (shared.isNotEmpty) ...[
    'Shared with the user by colleagues ("Gedeeld" in Skore): '
        '${_gradebooks(shared.length)}, in Skore\'s order, each with its '
        'owner and what the user may do in it:',
    for (final gradebook in shared)
      '- ${formatSkoreSharedGradebook(gradebook)}',
  ],
];

/// [count] gradebooks in words: `1 gradebook`, `4 gradebooks`.
String _gradebooks(int count) =>
    '$count ${count == 1 ? 'gradebook' : 'gradebooks'}';
