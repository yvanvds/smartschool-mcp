import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_year_plans`: the user's year plans in the Lesfiches module, the
/// teaching assignments of `TeachingAssignmentService.getTeachingAssignments`
/// (dartschool#229), one line each with which lesfiches it takes and its
/// clusters by name ([formatYearPlans], #191). Only reads.
ServerTool listYearPlansTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_year_plans',
    title: 'List the Smartschool year plans',
    description:
        'Lists the user\'s year plans ("leeropdrachten", teaching '
        'assignments) in the Smartschool Lesfiches module: each a collection '
        'of the user\'s lesfiches split into lesson clusters (the units of '
        'the year), with which lesfiches it takes, its clusters by name and '
        'its id. Read one with its clusters, their goals and their titles '
        'and lesfiches in order with read_year_plan. Listing changes nothing '
        'in Smartschool. For requests like "welke jaarplannen heb ik in '
        'Lesfiches?".',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'List the Smartschool year plans',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final plans = await withPlannerClient(
      session,
      (client) => TeachingAssignmentService(client).getTeachingAssignments(),
    );
    return CallToolResult(content: [TextContent(text: formatYearPlans(plans))]);
  },
);
