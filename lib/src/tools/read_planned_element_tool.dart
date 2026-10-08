import 'package:dart_mcp/server.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_planned_element`: one element of the planner in full, with its
/// public and private info as plain text.
ServerTool readPlannedElementTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_planned_element',
    title: 'Read a Smartschool planner element',
    description:
        'Reads one element of the Smartschool planner (a lesson, an '
        'assignment, an empty lesson hour, a meeting, a lesson-free day, …) '
        'in full, by the id list_planner shows. Gives what its list line '
        'says, one field per line, plus its public info and private info as '
        'plain text, its labels, and its attachments and weblinks, each with '
        'when pupils see it; for an '
        'assignment also its type, from when pupils see it, whether it was '
        'announced and its status. Public info is what pupils see. Private '
        'info is hidden from pupils, but it is not private to its author: '
        'colleagues who can see the element read it too. The detail is up '
        'to date at once, while list_planner can show an old state for a '
        'few seconds after a change. Reading changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The id of the element, as list_planner shows it, like '
              'planned-lessons/4069/225c0b54-….',
          minLength: 1,
        ),
      },
      required: ['id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a Smartschool planner element',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final element = PlannedElementRef.parse(arguments['id']);
  final detail = await withPlanner(session, element.read);
  return CallToolResult(
    content: [TextContent(text: formatElementDetail(detail))],
  );
}
