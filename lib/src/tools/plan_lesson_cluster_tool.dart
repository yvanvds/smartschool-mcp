import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planned_lesson_clusters.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `plan_lesson_cluster`: plans a lesson cluster of one of the user's year
/// plans for classes and a course over whole days
/// (`PlannerService.planLessonCluster`, dartschool#230, #196): for the
/// classes (or some of them) and the course of one of the user's own lesson
/// hours. The planned cluster keeps its link to the cluster.
///
/// In the period the planner shows the lesson hours of those classes and
/// that course as lesson cluster moments, which pupils see, so the tool is
/// marked destructive (for Claude Desktop to ask for approval before every
/// call). The reads (the year plan, the hour) go first, in a session action
/// of their own; the library sends the plan once, never again after logging
/// in again, and a plan the planner does not confirm is reported as maybe
/// made ([plannerWriteNotConfirmed]): a second call would plan the cluster
/// twice.
ServerTool planLessonClusterTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'plan_lesson_cluster',
    title: 'Plan a lesson cluster in the Smartschool planner',
    description:
        'Plans a lesson cluster of one of the user\'s year plans (Lesfiches) '
        'for classes and a course over a period of whole days, in the '
        'user\'s own Smartschool planner: for the classes (or some of them, '
        'with classes) and the course of one of the user\'s own lesson '
        'hours, as list_planner (planner me) shows them. Take the year plan '
        'and the cluster by their ids from list_year_plans and '
        'read_year_plan. Unlike plan_lesfiche, which copies a lesfiche into '
        'a lesson, a planned cluster stays linked to its cluster. In the '
        'period, the planner shows the lesson hours of those classes and '
        'that course in the user\'s planner as lesson cluster moments, and '
        'pupils of the classes see them at once. Before calling this tool, '
        'show the user the cluster and its year plan by name, the classes, '
        'the course and the first and last day, say that pupils see the '
        'moments, and only call this tool after the user has explicitly '
        'confirmed it. The result gives the planned cluster with its id; '
        'trash_planned_lesson_cluster takes it out again. If the result '
        'says the cluster may or may not have been planned, do not call '
        'this tool again for it, as that could plan it twice: first check '
        'with list_planned_lesson_clusters (year_plan and cluster) and tell '
        'the user. For requests like "plan de cluster Lussen voor 6A1 van '
        '16 tot 27 november".',
    inputSchema: Schema.object(
      properties: {
        'year_plan': yearPlanSchema(),
        'cluster': clusterSchema(),
        'hour': Schema.string(
          description:
              'The id of a lesson hour of your own planner, of the classes '
              'and the course to plan the cluster for, as list_planner '
              '(planner me) shows it: an empty lesson hour '
              '(planned-placeholders/4069/…), a lesson '
              '(planned-lessons/4069/…) or a lesson cluster moment. It can '
              'be in any week: only its classes and course are used.',
          minLength: 1,
        ),
        'from': Schema.string(
          description: 'The first day of the period, like 2026-11-16.',
          minLength: 1,
        ),
        'until': Schema.string(
          description:
              'The last day of the period, like 2026-11-27, in the same '
              'school year as from.',
          minLength: 1,
        ),
        'classes': Schema.list(
          description:
              'Only for some of the classes of the hour, when it is shared by '
              'several: each by its name as list_planner shows it (like 6A1) '
              'or its planner id (like group/4069_2001). Default: all '
              'classes of the hour.',
          items: Schema.string(),
        ),
      },
      required: ['year_plan', 'cluster', 'hour', 'from', 'until'],
    ),
    annotations: ToolAnnotations(
      title: 'Plan a lesson cluster in the Smartschool planner',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _plan(session, request.arguments ?? const {}),
);

Future<CallToolResult> _plan(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final planId = yearPlanArgument(arguments['year_plan']);
  final clusterId = clusterArgument(arguments['cluster']);
  final hour = clusterHourArgument(arguments['hour']);
  final (:from, :until) = clusterPeriodArguments(arguments);
  final wanted = lessonHourClassesArgument(arguments['classes']);

  // The reads, in a session action of their own: the year plan and its
  // cluster, and the hour with its classes and course.
  final (plan, cluster, classes, course) = await withPlannerClient(session, (
    client,
  ) async {
    final plan = await readYearPlan(client, planId);
    final cluster = findCluster(plan, clusterId);
    final planner = PlannerService(client);
    final slot = await hour.read(planner);
    await refuseUnlessOwnHour(planner, slot, plan: 'a lesson cluster');
    final classes = lessonHourClasses(slot, wanted);
    final course = slot.courses.firstOrNull;
    if (course == null) {
      throw ToolError(
        'The ${formatElementSummary(slot)} has no course, which a planned '
        'lesson cluster needs: take a lesson hour of the course. '
        '$nothingSent',
      );
    }
    return (plan, cluster, classes, course);
  });

  final names = classes.map((group) => group.name).join(', ');
  final period = formatPlannerPeriod(
    from,
    DateTime(until.year, until.month, until.day, 23, 59, 59),
  );
  final what =
      'The lesson cluster "${cluster.name}" of the year plan "${plan.name}" '
      'for $names (${course.name}) $period';
  try {
    final planned = await withPlannerWrite(
      session,
      (planner) => planner.planLessonCluster(
        cluster: cluster,
        from: from,
        to: until,
        groupIds: [for (final group in classes) group.id],
        courses: [course],
      ),
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Planned the lesson cluster "${cluster.name}" of the year plan '
                '"${plan.name}" for $names (${course.name}) $period. Pupils '
                'of $names see its moments now: in that period, list_planner '
                '(planner me) shows the lesson hours of ${course.name} of '
                'those classes as lesson cluster moments.',
            'The planned cluster has the id ${PlannedElementRef.of(planned)} '
                'and stays linked to the cluster: move it to the trash with '
                'trash_planned_lesson_cluster, which gives the lesson hours '
                'back.',
            plannerListLagNote,
            '',
            formatElementDetail(planned),
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    return plannerWriteNotConfirmed(
      tool: 'plan_lesson_cluster',
      what: what,
      done: 'planned',
      check:
          'list where the cluster is planned with '
          'list_planned_lesson_clusters (year_plan $planId, cluster '
          '$clusterId): when it is planned for $names $period, it was '
          'planned; when it is not, nothing was planned',
      error: error,
    );
  }
}
