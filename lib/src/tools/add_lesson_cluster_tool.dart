import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `add_lesson_cluster`: adds a lesson cluster (a unit of the year) to the
/// end of one of the user's year plans
/// (`TeachingAssignmentService.addCluster`, dartschool#229, #191).
///
/// The year plan is found in the list of the user's year plans first
/// ([readYearPlan]), in the session action of the write. Marked destructive
/// for approval, and not idempotent: a second call adds a second cluster.
/// The library sends the add once, never again after logging in again.
ServerTool addLessonClusterTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'add_lesson_cluster',
    title: 'Add a lesson cluster to a Smartschool year plan',
    description:
        'Adds a new, empty lesson cluster (a unit of the year, such as '
        '"Lussen") to the end of one of the user\'s year plans in the '
        'Smartschool Lesfiches module, by the year plan\'s id from '
        'list_year_plans. Then add titles and lesfiches to it with '
        'add_to_lesson_cluster, and goals with set_lesson_cluster_goals. '
        'Before calling this tool, show the user the year plan and the '
        'name, and only call this tool after the user has explicitly '
        'confirmed it. A name of more than $maxYearPlanNameLength '
        'characters is refused, and nothing is made. Every call adds a new '
        'cluster, also when one of that name exists. If the result says it '
        'may or may not have been added, do not call this tool again: check '
        'with read_year_plan, and tell the user. For requests like "voeg '
        'aan mijn jaarplan een cluster Lussen toe".',
    inputSchema: Schema.object(
      properties: {
        'year_plan': yearPlanSchema(),
        'name': Schema.string(
          description:
              'The name of the cluster, as the user confirmed it: at most '
              '$maxYearPlanNameLength characters.',
          minLength: 1,
        ),
      },
      required: ['year_plan', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Add a lesson cluster to a Smartschool year plan',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, request.arguments ?? const {}),
);

Future<CallToolResult> _add(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final planId = yearPlanArgument(arguments['year_plan']);
  final name = yearPlanNameArgument(
    arguments['name'],
    name: 'name',
    what: 'the lesson cluster',
  );
  String? planName;
  final LessonCluster cluster;
  try {
    cluster = await withYearPlanWrite(
      session,
      (client) async {
        final plan = await readYearPlan(client, planId);
        planName = plan.name;
        return TeachingAssignmentService(client).addCluster(plan, name: name);
      },
      what: 'the add of the lesson cluster "$name"',
      nothingDone: 'No cluster was added.',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return yearPlanWriteNotConfirmed(
      tool: 'add_lesson_cluster',
      what: 'The lesson cluster "$name" of the year plan "$planName"',
      done: 'added',
      why: 'a second call could add it twice',
      check:
          'read the year plan with read_year_plan (year_plan $planId) to '
          'see whether it is there',
      error: error,
    );
  }
  log('add_lesson_cluster: added a cluster');
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Added the lesson cluster "${cluster.name}" to the end of the year '
              'plan "$planName": cluster id ${cluster.id}.',
          'Add titles and lesfiches to it with add_to_lesson_cluster '
              '(year_plan $planId, cluster ${cluster.id}).',
        ].join('\n'),
      ),
    ],
  );
}
