import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `trash_assignment`: moves an assignment of the user's own planner to the
/// planner's trash, where it can be restored in Smartschool for 30 days.
///
/// Pupils no longer see the assignment, so the tool is marked destructive
/// (for Claude Desktop to ask for approval before every call). The library
/// refuses a colleague's assignment, one the planner does not let the user
/// trash, and one with a linked Skore evaluation before sending anything;
/// it sends the trash once, and confirms it by reading the assignment again
/// (the planner answers `404`). A trash that the planner does not confirm is
/// reported as maybe done ([plannerWriteNotConfirmed]).
ServerTool trashAssignmentTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'trash_assignment',
    title: 'Move a test or task to the Smartschool planner\'s trash',
    description:
        'Moves an assignment (a test or task) of the user\'s own Smartschool '
        'planner to the planner\'s trash, by the id list_planner, '
        'list_class_assignments or plan_assignment gives. The planner no '
        'longer shows it and pupils no longer see it. It can be restored from '
        'the planner\'s trash in Smartschool for 30 days; this tool cannot '
        'restore it. Only the user\'s own assignments can be moved to the '
        'trash: list_planner and list_class_assignments also show '
        'colleagues\' assignments, and this tool refuses those, and an '
        'assignment with a linked Skore evaluation. Before calling this tool, '
        'read the assignment with read_planned_element, show the user its '
        'date and time, class, course, type and name, say that it can be '
        'restored from the planner\'s trash in Smartschool, and only call '
        'this tool after the user has explicitly confirmed it. To empty a '
        'lesson hour of a lesson, use clear_lesson instead. If the result '
        'says the assignment may or may not have been moved to the trash, do '
        'not call this tool again for it: check it with read_planned_element '
        'and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The id of an assignment of your own planner, as list_planner '
              'or list_class_assignments shows it, like '
              'planned-assignments/4069/….',
          minLength: 1,
        ),
      },
      required: ['id'],
    ),
    annotations: ToolAnnotations(
      title: 'Move a test or task to the Smartschool planner\'s trash',
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
  if (id.type != PlannedElementType.assignment) {
    throw ToolError(
      'id must be an assignment of your own planner, like '
      'planned-assignments/4069/…; $id is ${switch (id.type) {
        PlannedElementType.lesson => 'a lesson, not an assignment: empty its '
            'lesson hour with clear_lesson',
        PlannedElementType.placeholder => 'an empty lesson hour, not an '
            'assignment',
        _ => 'a ${id.typeName}, not an assignment',
      }}. Nothing was sent.',
    );
  }

  PlannedElementDetail? assignment;
  try {
    await withPlannerWrite(session, (planner) async {
      final read = assignment = await id.read(planner);
      await planner.trashAssignment(read);
    });
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Moved the ${formatElementSummary(assignment!)} to the planner\'s '
                'trash: the planner no longer has it, and pupils no longer '
                'see it.',
            'It can be restored from the planner\'s trash in Smartschool for '
                '30 days; this tool cannot restore it.',
            plannerListLagNote,
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    return plannerWriteNotConfirmed(
      tool: 'trash_assignment',
      what: assignment == null
          ? 'The assignment $id'
          : 'The ${formatElementSummary(assignment!)}',
      done: 'moved to the trash',
      check:
          'read the assignment with read_planned_element (id $id): when the '
          'planner no longer has it, it is in the trash; when it is still '
          'there, it was not moved',
      error: error,
    );
  }
}
