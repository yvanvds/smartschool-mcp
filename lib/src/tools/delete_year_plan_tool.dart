import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `delete_year_plan`: deletes one of the user's year plans with its lesson
/// clusters (`TeachingAssignmentService.deleteTeachingAssignment`,
/// dartschool#229, #191). The lesfiches in its clusters stay in the user's
/// library; the year plan does not go to a trash: it is gone.
///
/// The year plan is found in the list of the user's year plans first, in
/// the session action of the delete. Marked destructive for approval, and
/// idempotent: a second call finds it no longer listed. The library retries
/// the delete after logging in again: it names what it deletes.
ServerTool deleteYearPlanTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'delete_year_plan',
    title: 'Delete a Smartschool year plan',
    description:
        'Deletes one of the user\'s year plans in the Smartschool Lesfiches '
        'module, by its id from list_year_plans, with all its lesson '
        'clusters, their titles and goals. This cannot be undone: a year '
        'plan does not go to a trash. The lesfiches in its clusters stay in '
        'the user\'s library, unchanged. Before calling this tool, show the '
        'user the year plan by name with its clusters, say that it cannot '
        'be undone, and only call this tool after the user has explicitly '
        'confirmed it. For requests like "verwijder mijn jaarplan Test".',
    inputSchema: Schema.object(
      properties: {'year_plan': yearPlanSchema()},
      required: ['year_plan'],
    ),
    annotations: ToolAnnotations(
      title: 'Delete a Smartschool year plan',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _delete(session, request.arguments ?? const {}),
);

Future<CallToolResult> _delete(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final planId = yearPlanArgument(arguments['year_plan']);
  TeachingAssignment? plan;
  try {
    await withYearPlanWrite(
      session,
      (client) async {
        plan = await readYearPlan(client, planId);
        await TeachingAssignmentService(client).deleteTeachingAssignment(plan!);
      },
      what: 'the delete of the year plan',
      nothingDone: 'Nothing was deleted.',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    log(
      'delete_year_plan: not confirmed '
      '(${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'})',
    );
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'The year plan "${plan?.name}" may or may not have been '
              'deleted: it was sent, but the Lesfiches module did not '
              'confirm it. List the year plans with list_year_plans to see '
              'whether it is still there, and tell the user what you found.',
        ),
      ],
    );
  }
  log('delete_year_plan: deleted a year plan');
  final clusters = plan!.clusters.length;
  return CallToolResult(
    content: [
      TextContent(
        text:
            'Deleted the year plan "${plan!.name}" with its $clusters '
            '${clusters == 1 ? 'lesson cluster' : 'lesson clusters'}. The '
            'lesfiches that were in them stay in your library, unchanged '
            '(list_lesfiches shows them).',
      ),
    ],
  );
}
