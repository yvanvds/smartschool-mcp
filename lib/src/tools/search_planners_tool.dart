import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// At most this many hits are listed; the rest are counted.
const maxListedPlanners = 50;

/// `search_planners`: the planners of classes, people and rooms whose name
/// holds some text, with the planner id `list_planner` takes.
ServerTool searchPlannersTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'search_planners',
    title: 'Find Smartschool planners',
    description:
        'Finds the planner of a class, a person or a room in the Smartschool '
        'planner by name, with the planner\'s own search: "6WE" finds the '
        'classes 6WEWI1 and 6WEWI2, a last name every person with that name, '
        '"611" the room. Lists each hit with its kind (class, person, room), '
        'its name, what the planner says about it, and the planner id to '
        'pass to list_planner, like group/4069_4256. The people found are '
        'pupils and staff alike, and the answer does not tell them apart: '
        'a pupil is often shown with a class after the name, and a '
        'co-account has an id of its own and a description such as '
        '"Interimaris van …". When several hits could be meant, ask the user '
        'which one. Your own planner needs no search: list_planner takes '
        '"me". Searching changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'The name or part of it: a class (6WEWI1, 6WE), a first or '
              'last name, or a room (611).',
          minLength: 1,
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(
      title: 'Find Smartschool planners',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _search(session, request.arguments ?? const {}),
);

Future<CallToolResult> _search(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final query = (arguments['query'] as String? ?? '').trim();
  if (query.isEmpty) {
    throw const ToolError('query is empty: pass the name to look for.');
  }
  final hits = await withPlanner(
    session,
    (planner) => planner.searchCalendars(query),
  );
  return CallToolResult(
    content: [TextContent(text: formatPlannerHits(query, hits))],
  );
}

/// What `search_planners` answers: [hits], the planners the search for
/// [query] found, one per line, at most [maxListedPlanners].
String formatPlannerHits(String query, List<PlannerSearchResult> hits) {
  if (hits.isEmpty) {
    return 'The planner finds nothing for "$query". Check the spelling, or '
        'look for a part of the name: a class like 6WE, a last name, a room '
        'number.';
  }
  final listed = hits.take(maxListedPlanners).toList();
  final left = hits.length - listed.length;
  return [
    'The planner finds ${hits.length} for "$query":',
    for (final hit in listed) '- ${formatPlannerHit(hit)}',
    if (left > 0)
      '$left more not listed: look for a longer part of the name to find '
          'fewer.',
  ].join('\n');
}

/// One hit: kind, name, what the planner says about it, and its planner id.
///
/// For example `class | 6WEWI1 | 6 Wetenschappen-Wiskunde 1 | planner
/// group/4069_4256`, or `person | Lotte Janssens | listed as Janssens Lotte
/// • 6A1 | planner user/4069_3001_0`. A hit of another kind has no planner.
String formatPlannerHit(PlannerSearchResult hit) {
  final listedAs = _sameWords(hit.title, hit.name) ? null : hit.title.trim();
  final calendar = hit.calendar;
  return [
    switch (hit.kind) {
      PlannerSearchResultKind.group => 'class',
      PlannerSearchResultKind.user => 'person',
      PlannerSearchResultKind.location => 'room',
      PlannerSearchResultKind.other => 'other (${hit.typeName})',
    },
    hit.name.trim().isEmpty ? '(no name)' : hit.name.trim(),
    if (hit.description.trim() case final description
        when description.isNotEmpty)
      description,
    if (listedAs != null && listedAs.isNotEmpty) 'listed as $listedAs',
    calendar == null ? 'no planner' : 'planner ${formatPlannerId(calendar)}',
  ].join(' | ');
}

/// Whether [a] and [b] hold the same words, in any order and case: the
/// search list's title of a person is the name, last name first.
bool _sameWords(String a, String b) {
  String words(String text) =>
      (text.toLowerCase().split(RegExp(r'\s+'))
            ..removeWhere((word) => word.isEmpty)
            ..sort())
          .join(' ');
  return words(a) == words(b);
}
