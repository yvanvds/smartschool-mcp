import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `create_year_plan`: makes a year plan of the user in the Lesfiches module
/// (`TeachingAssignmentService.createTeachingAssignment`, dartschool#229)
/// that takes all the user's lesfiches, so that `add_to_lesson_cluster` can
/// add any of them (#191).
///
/// Marked destructive, as the other writes of the Lesfiches module are, for
/// Claude Desktop and Codex to ask approval; not idempotent: a second call
/// makes a second year plan. The library sends the create once, never again
/// after logging in again. The name is checked before anything is sent
/// ([yearPlanNameArgument]).
ServerTool createYearPlanTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'create_year_plan',
    title: 'Make a Smartschool year plan',
    description:
        'Makes a new, empty year plan ("leeropdracht") in the user\'s '
        'Smartschool Lesfiches module, that takes all the user\'s lesfiches. '
        'Then add lesson clusters (the units of the year) with '
        'add_lesson_cluster, and titles and lesfiches to them with '
        'add_to_lesson_cluster. Before calling this tool, show the user the '
        'name, and only call this tool after the user has explicitly '
        'confirmed it. A name of more than $maxYearPlanNameLength '
        'characters is refused, and nothing is made. Every call makes a new '
        'year plan, also when one of that name exists. If the result says '
        'it may or may not have been made, do not call this tool again: '
        'check with list_year_plans, and tell the user. For requests like '
        '"maak een jaarplan Informatica 5".',
    inputSchema: Schema.object(
      properties: {
        'name': Schema.string(
          description:
              'The name of the year plan, as the user confirmed it: at most '
              '$maxYearPlanNameLength characters.',
          minLength: 1,
        ),
      },
      required: ['name'],
    ),
    annotations: ToolAnnotations(
      title: 'Make a Smartschool year plan',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _create(session, request.arguments ?? const {}),
);

Future<CallToolResult> _create(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final name = yearPlanNameArgument(
    arguments['name'],
    name: 'name',
    what: 'the year plan',
  );
  final TeachingAssignment plan;
  try {
    plan = await withYearPlanWrite(
      session,
      (client) => TeachingAssignmentService(
        client,
      ).createTeachingAssignment(name: name),
      what: 'the creation of the year plan "$name"',
      nothingDone: 'No year plan was made.',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return yearPlanWriteNotConfirmed(
      tool: 'create_year_plan',
      what: 'The year plan "$name"',
      why: 'a second call could make it twice',
      check:
          'list the year plans with list_year_plans to see whether it is '
          'there',
      error: error,
    );
  }
  log('create_year_plan: made a year plan');
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Made the year plan ${formatYearPlanLine(plan)}.',
          'Add its lesson clusters with add_lesson_cluster (year_plan '
              '${plan.id}).',
        ].join('\n'),
      ),
    ],
  );
}
