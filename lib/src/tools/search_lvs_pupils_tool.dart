import 'package:dart_mcp/server.dart';

import '../lvs/lvs_access.dart';
import '../lvs/lvs_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// `search_lvs_pupils`: the pupils whose name matches, in Smartschool's
/// pupil tracking system (LVS), each with their class and the ids
/// `read_lvs_pupil` takes ([LvsService.searchPupils], #153).
ServerTool searchLvsPupilsTool(SmartschoolSession session) => lvsTool(
  definition: Tool(
    name: 'search_lvs_pupils',
    title: 'Find a pupil in the pupil tracking system',
    description:
        "Finds pupils by name in Smartschool's pupil tracking system "
        '(leerlingvolgsysteem, LVS), among the pupils this account may see '
        'there. One line per pupil: name, class, pupil_id and class_id, the '
        'two ids read_lvs_pupil takes. Use it first when the user asks how a '
        'pupil is doing, or about their file in the LVS. When several pupils '
        'match, ask the user which one they mean (by name and class): never '
        'pick one yourself. When none match, the result says so. '
        '$lvsPrivacyRules Searching changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              "Part of the pupil's name: a first name, a last name or both.",
          minLength: 1,
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(
      title: 'Find a pupil in the pupil tracking system',
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
  final query = switch (arguments['query']) {
    final String text => text.trim(),
    _ => '',
  };
  if (query.isEmpty) {
    throw const ToolError(
      "query is empty: pass part of the pupil's name to look for.",
    );
  }
  final found = await withLvs(session, (lvs) => lvs.searchPupils(query));
  return CallToolResult(
    content: [TextContent(text: formatLvsMatches(query, found))],
  );
}
