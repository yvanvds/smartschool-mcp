import 'package:dart_mcp/server.dart';

import '../goals/goals.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_curricula`: the curricula of Smartschool's goal selector
/// (`GoalService.getCurricula`, dartschool#222), in its groups, as
/// [formatCurricula] lists them (#186).
ServerTool listCurriculaTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_curricula',
    title: 'List the Smartschool curricula of learning goals',
    description:
        'Lists the curricula of learning goals that Smartschool\'s goal '
        'selector offers for lesfiches and lessons, in its groups and order: '
        'such as Overheid SO (the eindtermen per grade and finality), '
        'Levensbeschouwing SO (the curricula of the philosophies of life), '
        'Andere SO and Minidatabanken (the school\'s own mini-databases). '
        'One line per curriculum: its title, whether it is hidden in the '
        'selector or a favourite, and its id. Filter with query (words in '
        'the title). read_curriculum reads the goals of one, by that id; '
        'read_lesfiche and read_planned_element show the goals a lesfiche '
        'or a lesson has. Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the title of the curriculum, '
              'case-insensitive, in any order, like "eindtermen derde '
              'graad". Default: every curriculum.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the Smartschool curricula of learning goals',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final query = (request.arguments?['query'] as String? ?? '').trim();
    final groups = await withGoals(session, (goals) => goals.getCurricula());
    return CallToolResult(
      content: [TextContent(text: formatCurricula(groups, query))],
    );
  },
);
