import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `clear_lesson`: empties a lesson hour of the user's own planner again.
///
/// The lesson's name and info are gone afterwards, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call).
/// The library sends the clear once; a clear that the planner does not
/// confirm is reported as maybe done ([plannerWriteNotConfirmed]).
ServerTool clearLessonTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'clear_lesson',
    title: 'Clear a lesson from a Smartschool lesson hour',
    description:
        'Empties a lesson hour of the user\'s own Smartschool planner again: '
        'the lesson in it is removed, with its name and its public and '
        'private info, and the hour becomes an empty lesson hour. The name '
        'and info cannot be brought back. Only the user\'s own lessons in a '
        'lesson hour of the timetable can be cleared: list_planner also '
        'shows colleagues\' lessons, and this tool refuses those. Before '
        'calling this tool, show the user the date and time, the class, the '
        'course and the name of the lesson, and only call it after the user '
        'has explicitly confirmed it. The empty lesson hour gets a new id, '
        'which the result gives: use that id, not the old one, to fill the '
        'hour again with plan_lesson. For a few seconds after a change '
        'list_planner can still show the lesson: check with '
        'read_planned_element. If the result says the lesson may or may not '
        'have been cleared, do not call this tool again for it: check it '
        'with read_planned_element and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The id of a lesson of your own planner, as list_planner '
              'shows it, like planned-lessons/4069/….',
          minLength: 1,
        ),
      },
      required: ['id'],
    ),
    annotations: ToolAnnotations(
      title: 'Clear a lesson from a Smartschool lesson hour',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _clear(session, request.arguments ?? const {}),
);

Future<CallToolResult> _clear(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = PlannedElementRef.parse(arguments['id']);
  if (id.type != PlannedElementType.lesson) {
    throw ToolError(
      'id must be a lesson of your own planner, like planned-lessons/4069/…; '
      '$id is ${switch (id.type) {
        PlannedElementType.placeholder => 'an empty lesson hour already',
        PlannedElementType.assignment => 'an assignment, not a lesson',
        _ => 'a ${id.typeName}, not a lesson',
      }}. Nothing was sent.',
    );
  }

  PlannedElementDetail? lesson;
  try {
    final hour = await withPlannerWrite(session, (planner) async {
      final read = lesson = await id.read(planner);
      return planner.clearLesson(read);
    });
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Cleared the ${formatElementSummary(lesson!)}: its name and info '
                'are gone, and the hour is an empty lesson hour again.',
            'The lesson $id no longer exists. The empty lesson hour has a new '
                'id: ${PlannedElementRef.of(hour)}. Use that one to fill the '
                'hour again.',
            plannerListLagNote,
            '',
            formatElementDetail(hour),
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    return plannerWriteNotConfirmed(
      tool: 'clear_lesson',
      what: lesson == null
          ? 'The lesson $id'
          : 'The ${formatElementSummary(lesson!)}',
      done: 'cleared',
      check:
          'read the lesson with read_planned_element (id $id): when the '
          'planner no longer has it, it was cleared, and list_planner '
          '(planner me) shows the empty lesson hour with a new id, possibly '
          'only after a few seconds; when the lesson is still there, it was '
          'not cleared',
      error: error,
    );
  }
}
