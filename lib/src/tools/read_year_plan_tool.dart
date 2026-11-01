import 'package:dart_mcp/server.dart';

import '../planner/planner_access.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_year_plan`: one year plan of the user (a teaching assignment,
/// dartschool#229) with its lesson clusters in full (counts, teaching hours,
/// goals named by the goal selector) and the content of each, its titles
/// and lesfiches in order ([formatYearPlan], #191); or only one cluster.
/// Only reads: the list of year plans, the clusters, the content of each,
/// and one request to name the goals.
ServerTool readYearPlanTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_year_plan',
    title: 'Read a Smartschool year plan',
    description:
        'Reads one year plan of the Smartschool Lesfiches module, by its id '
        'from list_year_plans: which lesfiches it takes, and each lesson '
        'cluster with its number of lesson and assignment lesfiches, its '
        'estimate of teaching hours, its learning goals by name, and its '
        'content in order: titles (such as "Week 1") and lesfiches, each '
        'lesfiche with its id. With cluster, only that cluster. Reading '
        'changes nothing in Smartschool. For requests like "toon mijn '
        'jaarplan Informatica 5".',
    inputSchema: Schema.object(
      properties: {
        'year_plan': yearPlanSchema(),
        'cluster': Schema.string(
          description:
              'Optional: the id of one lesson cluster of the year plan, to '
              'read only that one.',
        ),
      },
      required: ['year_plan'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a Smartschool year plan',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) async {
    final arguments = request.arguments ?? const {};
    final planId = yearPlanArgument(arguments['year_plan']);
    final clusterId = switch (arguments['cluster']) {
      null => null,
      final String text when text.trim().isEmpty => null,
      final value => clusterArgument(value),
    };
    final text = await withPlannerClient(session, (client) async {
      final plan = await readYearPlan(client, planId);
      if (clusterId != null) findCluster(plan, clusterId);
      final read = await readYearPlanClusters(client, plan, only: clusterId);
      return formatYearPlan(
        plan,
        read.clusters,
        goals: read.goals,
        onlyOne: clusterId != null,
      );
    });
    return CallToolResult(content: [TextContent(text: text)]);
  },
);
