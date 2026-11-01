import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `trash_planned_lesson_cluster`: moves a lesson cluster planned in the
/// user's own planner to the planner's trash
/// (`PlannerService.trashPlannedLessonCluster`, dartschool#230, #196),
/// where it can be restored in Smartschool for 30 days. Its lesson hours
/// are given back; the cluster in the year plan stays as it is.
///
/// Pupils no longer see its moments, so the tool is marked destructive (for
/// Claude Desktop to ask for approval before every call). The library
/// refuses a colleague's planned cluster and one the planner does not let
/// the user trash before sending anything, sends the trash once, and
/// confirms it by reading the planned cluster again (the planner answers
/// `404`). A trash the planner does not confirm is reported as maybe done
/// ([plannerWriteNotConfirmed]).
ServerTool trashPlannedLessonClusterTool(SmartschoolSession session) =>
    ServerTool(
      definition: Tool(
        name: 'trash_planned_lesson_cluster',
        title:
            'Move a planned lesson cluster to the Smartschool planner\'s '
            'trash',
        description:
            'Moves a lesson cluster planned in the user\'s own Smartschool '
            'planner to the planner\'s trash, by the id '
            'list_planned_lesson_clusters, plan_lesson_cluster or a lesson '
            'cluster moment of list_planner gives '
            '(planned-lesson-clusters/4069/…). Pupils no longer see its '
            'moments, and its lesson hours show as they were. The lesson '
            'cluster in the year plan stays as it is. It can be restored '
            'from the planner\'s trash in Smartschool for 30 days; this tool '
            'cannot restore it. Only the user\'s own planned clusters can be '
            'moved to the trash. Before calling this tool, show the user the '
            'planned cluster (its name, classes, course, first and last '
            'day), say that it can be restored from the planner\'s trash in '
            'Smartschool, and only call this tool after the user has '
            'explicitly confirmed it. If the result says it may or may not '
            'have been moved to the trash, do not call this tool again for '
            'it: check it with read_planned_element and tell the user.',
        inputSchema: Schema.object(
          properties: {
            'id': Schema.string(
              description:
                  'The id of a planned lesson cluster of your own planner, '
                  'like planned-lesson-clusters/4069/….',
              minLength: 1,
            ),
          },
          required: ['id'],
        ),
        annotations: ToolAnnotations(
          title:
              'Move a planned lesson cluster to the Smartschool planner\'s '
              'trash',
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: false,
          openWorldHint: true,
        ),
      ),
      handler: (request) => _trash(session, request.arguments ?? const {}),
    );

Future<CallToolResult> _trash(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = PlannedElementRef.parse(arguments['id']);
  if (id.type != PlannedElementType.lessonCluster) {
    throw ToolError(
      'id must be a planned lesson cluster of your own planner, like '
      'planned-lesson-clusters/4069/…; $id is ${switch (id.type) {
        PlannedElementType.lessonClusterMoment => 'a lesson cluster moment, '
            'one lesson hour of a planned cluster: list_planner and '
            'read_planned_element name the planned cluster it belongs to, '
            'with its id, and only the whole planned cluster goes to the '
            'trash',
        PlannedElementType.assignment => 'an assignment: use '
            'trash_assignment',
        PlannedElementType.lesson => 'a lesson: empty its lesson hour with '
            'clear_lesson',
        _ => 'a ${id.typeName}, not a planned lesson cluster',
      }}. Nothing was sent.',
    );
  }

  PlannedElementDetail? planned;
  try {
    await withPlannerWrite(session, (planner) async {
      final read = planned = await id.read(planner);
      await planner.trashPlannedLessonCluster(read);
    });
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Moved the ${formatElementSummary(planned!)} to the planner\'s '
                'trash: pupils no longer see its moments, and its lesson '
                'hours show as they were. The lesson cluster in your year '
                'plan stays as it is.',
            'It can be restored from the planner\'s trash in Smartschool for '
                '30 days; this tool cannot restore it.',
            plannerListLagNote,
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    return plannerWriteNotConfirmed(
      tool: 'trash_planned_lesson_cluster',
      what: planned == null
          ? 'The planned lesson cluster $id'
          : 'The ${formatElementSummary(planned!)}',
      done: 'moved to the trash',
      check:
          'read it with read_planned_element (id $id): when the planner no '
          'longer has it, it is in the trash; when it is still there, it was '
          'not moved',
      error: error,
    );
  }
}
