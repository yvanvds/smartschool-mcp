import 'package:dart_mcp/server.dart';

import '../planner/lesfiches.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `plan_lesfiche`: fills an empty lesson hour of the user's own planner
/// with a lesson lesfiche of the user's Lesfiches module: the planner names
/// the lesson after the lesfiche and takes over its content.
///
/// Like `plan_lesson`: pupils see the lesson as soon as it is saved, so the
/// tool is marked destructive, and it never fills an hour twice by itself
/// ([fillLessonHour]). The library reads the lesfiches before it plans one,
/// and refuses an id the user has no lesfiche with, or one of an assignment
/// lesfiche, before sending anything.
ServerTool planLesficheTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'plan_lesfiche',
    title: 'Plan a lesfiche in a Smartschool lesson hour',
    description:
        'Plans a lesfiche of the user\'s Smartschool Lesfiches module into an '
        'empty lesson hour of the user\'s own planner: the hour becomes a '
        'lesson named after the lesfiche, and the planner takes over its '
        'content. Pupils of the hour\'s classes see the lesson\'s name and '
        'public info as soon as it is saved. Only lesson lesfiches can be '
        'planned (hidden ones too): an assignment lesfiche, or an id the user '
        'has no lesfiche with, is refused. Only the user\'s own planner can '
        'be changed: list_planner also shows colleagues\' hours, and this '
        'tool refuses those. First list the lesfiches with list_lesfiches and '
        'the empty lesson hours with list_planner (planner me), and take the '
        'ids from there. Show the user, per hour, the date and time, the '
        'class, the course, and the name of the lesfiche that goes there, and '
        'only call this tool after the user has explicitly confirmed it. For '
        'a series of lesfiches, one confirmation of the full mapping is '
        'enough; then call this tool once per hour, in order. The result '
        'gives the lesson as saved, with what it took over from the lesfiche '
        '(its info, labels, attachments and weblinks, as far as the planner '
        'copies them) and its id: the hour\'s old id no longer exists. For a '
        'few seconds after a change list_planner can still show the old '
        'state: check a lesson with read_planned_element. If the result says '
        'the lesson may or may not have been saved, do not call this tool '
        'again for that hour: check the hour with read_planned_element and '
        'tell the user. To change a planned lesson, use '
        'edit_planned_element; to empty its hour again, clear_lesson.',
    inputSchema: Schema.object(
      properties: {
        'hour': Schema.string(
          description:
              'The id of an empty lesson hour of your own planner, as '
              'list_planner (planner me) shows it, like '
              'planned-placeholders/4069/….',
          minLength: 1,
        ),
        'lesfiche': Schema.string(
          description:
              'The id of a lesson lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
      },
      required: ['hour', 'lesfiche'],
    ),
    annotations: ToolAnnotations(
      title: 'Plan a lesfiche in a Smartschool lesson hour',
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
  final lesfiche = lesficheArgument(arguments['lesfiche']);
  return fillLessonHour(
    session,
    tool: 'plan_lesfiche',
    hour: hour,
    what: 'the lesfiche $lesfiche',
    fill: (planner, slot) =>
        planner.planLessonContent(placeholder: slot, lessonContentId: lesfiche),
  );
}
