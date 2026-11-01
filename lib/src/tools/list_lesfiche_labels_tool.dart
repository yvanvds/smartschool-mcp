import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/lesfiche_labels.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_lesfiche_labels`: the labels a lesfiche can get
/// (`LessonContentService.getLabels`, dartschool#228): the school's labels
/// for the Lesfiches module, then the user's own, each with its colour and
/// id, as [formatLesficheLabels] lists them (#188). The labels module's
/// errors become [ToolError]s as the Lesfiches module's do
/// ([withPlannerClient]).
ServerTool listLesficheLabelsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_lesfiche_labels',
    title: 'List the labels of Smartschool lesfiches',
    description:
        'Lists the labels a lesfiche of the Smartschool Lesfiches module can '
        'get: the school\'s labels (such as JAAR 6 or TRIMESTER 1), then the '
        'user\'s own labels, each with its colour and id. They sort the '
        'user\'s lesfiches. Put labels on a lesfiche with '
        'create_lesfiche or edit_lesfiche (by their text), filter '
        'list_lesfiches by them, and make a new own label with '
        'create_lesfiche_label. Listing changes nothing in Smartschool. For '
        'requests like "welke labels kan ik op mijn lesfiches zetten?".',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'List the labels of Smartschool lesfiches',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final labels = await withPlannerClient(
      session,
      (client) => LessonContentService(client).getLabels(),
    );
    return CallToolResult(
      content: [TextContent(text: formatLesficheLabels(labels))],
    );
  },
);
