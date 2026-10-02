import 'package:dart_mcp/server.dart';

import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `plan_lesson`: fills an empty lesson hour of the user's own planner with
/// a lesson: a name, and optionally the info pupils see and private info.
///
/// Pupils see the lesson as soon as it is saved, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call),
/// and it never fills an hour twice by itself: see [fillLessonHour].
ServerTool planLessonTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'plan_lesson',
    title: 'Plan a lesson in a Smartschool lesson hour',
    description:
        'Fills an empty lesson hour of the user\'s own Smartschool planner '
        'with a lesson: a name, and optionally public info (what pupils see) '
        'and private info. Pupils of the hour\'s classes see the name and the '
        'public info as soon as it is saved. Only the user\'s own planner can '
        'be changed: list_planner also shows colleagues\' hours, and this '
        'tool refuses those. First list the empty lesson hours with '
        'list_planner (planner me) and take the id of the hour from there. '
        'Show the user, per hour, the date and time, the class, the course, '
        'and the new name and info, and only call this tool after the user '
        'has explicitly confirmed it. For a whole week, one confirmation of '
        'the full list is enough; then call this tool once per hour. Private '
        'info is hidden from pupils, but colleagues who can see the lesson '
        'read it too. Write the info as plain text, with a blank line between '
        'paragraphs; HTML in it is not interpreted, it shows as text. The '
        'result gives the lesson as saved, with its id: the hour\'s old id no '
        'longer exists. For a few seconds after a change list_planner can '
        'still show the old state: check a lesson with read_planned_element. '
        'If the result says the lesson may or may not have been saved, do '
        'not call this tool again for that hour: check the hour with '
        'read_planned_element and tell the user. To change a planned lesson, '
        'use edit_planned_element; to empty its hour again, clear_lesson.',
    inputSchema: Schema.object(
      properties: {
        'hour': Schema.string(
          description:
              'The id of an empty lesson hour of your own planner, as '
              'list_planner (planner me) shows it, like '
              'planned-placeholders/4069/….',
          minLength: 1,
        ),
        'name': Schema.string(
          description:
              'The name of the lesson, as the user confirmed it. Pupils see '
              'it.',
          minLength: 1,
        ),
        'public_info': Schema.string(
          description:
              'What pupils see with the lesson, as plain text: a blank line '
              'between paragraphs. Default: none.',
        ),
        'private_info': Schema.string(
          description:
              'Notes pupils do not see, as plain text. Colleagues who can '
              'see the lesson read them too. Default: none.',
        ),
      },
      required: ['hour', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Plan a lesson in a Smartschool lesson hour',
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
  final hour = emptyHourArgument(arguments['hour']);
  final name = (arguments['name'] as String? ?? '').trim();
  if (name.isEmpty) {
    throw const ToolError(
      'name is empty: pass the name of the lesson. Nothing was sent.',
    );
  }
  final publicInfo = plainTextToHtml(arguments['public_info'] as String? ?? '');
  final privateInfo = plainTextToHtml(
    arguments['private_info'] as String? ?? '',
  );
  return fillLessonHour(
    session,
    tool: 'plan_lesson',
    hour: hour,
    what: 'the lesson "$name"',
    fill: (planner, slot) => planner.planLesson(
      placeholder: slot,
      name: name,
      publicInfo: publicInfo,
      privateInfo: privateInfo,
    ),
  );
}
