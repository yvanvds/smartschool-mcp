import 'package:dart_mcp/server.dart';

import '../goals/goals.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_curriculum`: the learning goals of one curriculum of Smartschool's
/// goal selector (`GoalService.getCurriculum`, dartschool#222), under their
/// headings, optionally only those that hold some words, as
/// [formatCurriculum] shows them (#186).
ServerTool readCurriculumTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_curriculum',
    title: 'Read the learning goals of a Smartschool curriculum',
    description:
        'Reads the learning goals of one curriculum of Smartschool\'s goal '
        'selector, by the id list_curricula shows: the goals that can be '
        'picked for a lesfiche or a lesson, under their headings, each with '
        'its number (such as 01.02), its text and its id, and whether it is '
        'a goal of basic literacy, an extension goal or deprecated. A goal '
        'is stored with three fields: its own id, and the leerplanId and '
        'type the answer gives once for the whole curriculum. Filter with '
        'query (words in the number, the text or the headings above the '
        'goal) to find the goal that fits a lesson; at most '
        '$maxGoalLines goals are listed. Reading changes nothing in '
        'Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'curriculum': Schema.string(
          description:
              'The id of the curriculum, as list_curricula shows it, like '
              'e0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'query': Schema.string(
          description:
              'Words that must all occur in the goal\'s number, text or '
              'headings, case-insensitive, in any order, like "programmeren '
              'algoritme". Default: every goal.',
        ),
      },
      required: ['curriculum'],
    ),
    annotations: ToolAnnotations(
      title: 'Read the learning goals of a Smartschool curriculum',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final id = (arguments['curriculum'] as String? ?? '').trim();
    if (id.isEmpty) {
      throw const ToolError(
        'curriculum is empty: pass the id of a curriculum as list_curricula '
        'shows it.',
      );
    }
    final query = (arguments['query'] as String? ?? '').trim();
    final curriculum = await withGoals(
      session,
      (goals) => goals.getCurriculum(id),
    );
    return CallToolResult(
      content: [TextContent(text: formatCurriculum(curriculum, query))],
    );
  },
);
