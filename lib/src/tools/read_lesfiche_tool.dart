import 'package:dart_mcp/server.dart';

import '../planner/lesfiche_detail.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_lesfiche`: one lesfiche of the user's Lesfiches module in full
/// (`LessonContentService.getDetailById`, dartschool#129), with its weblinks
/// and attachments, when pupils see them, and its public and private info
/// as plain text ([formatLesficheDetail]).
ServerTool readLesficheTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_lesfiche',
    title: 'Read a Smartschool lesfiche',
    description:
        'Reads one lesfiche of the user\'s Smartschool Lesfiches module in '
        'full, by the id and kind list_lesfiches shows. Gives its kind (an '
        'assignment with its type), name, icon, labels, courses, whether it '
        'is visible or hidden in the module, its weblinks (name, address, '
        'icon, when pupils see it, id) and its attachments (numbered, with '
        'file name, size, type, when pupils see it, id), and its public info '
        '(what pupils see) and private info (hidden from pupils) as plain '
        'text. When pupils see a weblink or an attachment counts from the '
        'lesson the lesfiche is planned in: always, never, from the start of '
        'that lesson, from its end, or a number of days after its end. Use '
        'it to tell the user what a lesfiche holds, to compare a lesfiche '
        'with a lesson planned from it (read_planned_element), or to reuse '
        'its text. read_lesfiche_attachment reads the text of an attachment, '
        'save_lesfiche_attachment saves one into the download folder. '
        'edit_lesfiche changes the lesfiche; set_lesfiche_weblink and '
        'remove_lesfiche_weblink change its weblinks, and '
        'add_lesfiche_attachments, set_lesfiche_attachment_visibility and '
        'remove_lesfiche_attachment its attachments, by the ids shown here. '
        'Pass '
        'type assignment for an assignment lesfiche: a lesfiche asked for as '
        'the other kind is not found. Reading changes nothing in '
        'Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
      },
      required: ['lesfiche'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a Smartschool lesfiche',
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
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final (:detail, :courseError) = await withPlannerClient(
    session,
    (client) => readLesficheDetail(client, type, id),
  );
  return CallToolResult(
    content: [
      TextContent(text: formatLesficheDetail(detail, courseError: courseError)),
    ],
  );
}
