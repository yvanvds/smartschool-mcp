import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../goals/goals.dart';
import '../log.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `set_lesson_cluster_goals`: sets the learning goals of a lesson cluster
/// of one of the user's year plans
/// (`TeachingAssignmentService.changeClusterGoals`, dartschool#229, #191).
///
/// The list replaces the goals ([goalsReplaceNote]). Before anything is
/// sent, it finds the year plan and the cluster in the user's year plans,
/// reads the cluster's goals, and checks the goals it does not have yet with
/// the goal selector ([checkGoals], at the Lesfiches module's location), as
/// the goal writes of #187 do. Marked destructive for approval, and
/// idempotent: it sets a value, and the library retries it after logging in
/// again. The result shows the cluster read back, its goals named.
ServerTool setLessonClusterGoalsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'set_lesson_cluster_goals',
    title: 'Set the learning goals of a Smartschool lesson cluster',
    description:
        'Sets the learning goals of a lesson cluster of one of the user\'s '
        'year plans in the Smartschool Lesfiches module, by the ids of '
        'read_year_plan. goals are learning goals as read_curriculum shows '
        'them, each {id, leerplanId, type}. $goalsReplaceNote A goal the '
        'goal selector does not know is refused, and nothing is changed. '
        'The goals of the lesfiches in the cluster stay as they are. Before '
        'calling this tool, show the user the cluster and the goals by '
        'name, and only call this tool after the user has explicitly '
        'confirmed it. The result shows the cluster with its goals. For '
        'requests like "geef de cluster Lussen de eindtermen over '
        'algoritmes".',
    inputSchema: Schema.object(
      properties: {
        'year_plan': yearPlanSchema(),
        'cluster': clusterSchema(),
        'goals': goalsSchema(
          description:
              'The learning goals the cluster gets, in place of all its '
              'goals, each {id, leerplanId, type} as read_curriculum shows '
              'them; an empty list removes them all. To add one, pass the '
              'goals read_year_plan shows plus the new one.',
        ),
      },
      required: ['year_plan', 'cluster', 'goals'],
    ),
    annotations: ToolAnnotations(
      title: 'Set the learning goals of a Smartschool lesson cluster',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _set(session, request.arguments ?? const {}),
);

Future<CallToolResult> _set(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final planId = yearPlanArgument(arguments['year_plan']);
  final clusterId = clusterArgument(arguments['cluster']);
  final goals = goalsArgument(arguments['goals']) ?? const <LearningGoalRef>[];
  String? clusterName;
  var unchanged = false;
  try {
    await withYearPlanWrite(session, (client) async {
      final service = TeachingAssignmentService(client);
      final plan = await readYearPlan(client, planId);
      final cluster = await service.getCluster(findCluster(plan, clusterId));
      clusterName = cluster.name;
      if (sameGoals(cluster.goals, goals)) {
        unchanged = true;
        return;
      }
      await checkGoals(
        client,
        goals,
        location: GoalLocation.lessonContent,
        stored: cluster.goals,
      );
      await service.changeClusterGoals(cluster, goals);
    }, what: 'the change of the goals of the lesson cluster');
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    // Setting the goals again is harmless, but Claude should check first.
    log(
      'set_lesson_cluster_goals: not confirmed '
      '(${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'})',
    );
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'The goals of the lesson cluster "$clusterName" may or may not '
              'have been changed: it was sent, but the Lesfiches module did '
              'not confirm it. Read the cluster with read_year_plan '
              '(year_plan $planId, cluster $clusterId) to see its goals now, '
              'and tell the user what you found.',
        ),
      ],
    );
  }
  log('set_lesson_cluster_goals: ${unchanged ? 'unchanged' : 'set'}');
  final shown = await yearPlanClusterReadBack(session, planId, clusterId);
  return CallToolResult(
    content: [
      TextContent(
        text: [
          unchanged
              ? 'The lesson cluster "$clusterName" has these goals already: '
                    'nothing was sent.'
              : 'Set the goals of the lesson cluster "$clusterName".',
          '',
          shown,
        ].join('\n'),
      ),
    ],
  );
}
