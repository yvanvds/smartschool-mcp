import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planned_lesson_clusters.dart';
import '../planner/planner_access.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_planned_lesson_clusters`: the lesson clusters planned in the
/// user's own planner in a period (`PlannerService.getPlannedLessonClusters`),
/// or where one lesson cluster of a year plan was planned
/// (`getPlannedLessonClustersOf`, dartschool#230, #196). Only reads.
///
/// [now] gives today, for the default period.
ServerTool listPlannedLessonClustersTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'list_planned_lesson_clusters',
    title: 'List the planned lesson clusters in the Smartschool planner',
    description:
        'Lists the lesson clusters of year plans planned for classes in the '
        'user\'s own Smartschool planner (with plan_lesson_cluster, or in '
        'Smartschool itself): those planned in a period (from and until, by '
        'default from today to the end of the school year), or, with '
        'year_plan and cluster (ids from list_year_plans and '
        'read_year_plan), where that cluster was planned. One line each: '
        'the name of the cluster, the first and last day, the course, the '
        'classes, and the id for read_planned_element and '
        'trash_planned_lesson_cluster. A planned cluster in the trash is not '
        'listed. Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'from': Schema.string(
          description:
              'The first day, like 2026-11-16. Default: today. Not with '
              'cluster.',
        ),
        'until': Schema.string(
          description:
              'The last day, like 2027-06-30. Default: the end of the school '
              'year of from (31 August). Not with cluster.',
        ),
        'year_plan': Schema.string(
          description:
              'With cluster: the id of the year plan, as list_year_plans '
              'shows it.',
        ),
        'cluster': Schema.string(
          description:
              'Only where this lesson cluster of year_plan was planned: its '
              'id, as read_year_plan shows it.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the planned lesson clusters in the Smartschool planner',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}, now),
);

bool _given(Object? value) => value is String && value.trim().isNotEmpty;

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
  DateTime Function() now,
) async {
  final byCluster =
      _given(arguments['cluster']) || _given(arguments['year_plan']);
  if (byCluster) {
    if (_given(arguments['from']) || _given(arguments['until'])) {
      throw const ToolError(
        'Pass either from and until (the clusters planned in a period) or '
        'year_plan and cluster (where one cluster was planned), not both.',
      );
    }
    if (!_given(arguments['cluster']) || !_given(arguments['year_plan'])) {
      throw const ToolError(
        'Pass year_plan and cluster together: the id of the year plan from '
        'list_year_plans and that of its cluster from read_year_plan.',
      );
    }
    final planId = yearPlanArgument(arguments['year_plan']);
    final clusterId = clusterArgument(arguments['cluster']);
    final text = await withPlannerClient(session, (client) async {
      final plan = await readYearPlan(client, planId);
      final cluster = findCluster(plan, clusterId);
      final planned = await PlannerService(
        client,
      ).getPlannedLessonClustersOf(cluster);
      return formatPlannedClustersOf(planned, plan: plan, cluster: cluster);
    });
    return CallToolResult(content: [TextContent(text: text)]);
  }

  final today = now();
  final from = _given(arguments['from'])
      ? clusterDayArgument(arguments['from'], name: 'from')
      : DateTime(today.year, today.month, today.day);
  final until = _given(arguments['until'])
      ? clusterDayArgument(arguments['until'], name: 'until')
      : schoolYearEnd(from);
  if (until.isBefore(from)) {
    throw const ToolError('until must not be before from.');
  }
  final planned = await withPlanner(
    session,
    (planner) => planner.getPlannedLessonClusters(from: from, to: until),
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatPlannedClustersInPeriod(
          planned,
          from: from,
          until: DateTime(until.year, until.month, until.day, 23, 59, 59),
        ),
      ),
    ],
  );
}
