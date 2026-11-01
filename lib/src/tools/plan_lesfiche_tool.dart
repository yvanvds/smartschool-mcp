import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../goals/goals.dart';
import '../log.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// At most this many lesson hours per call of `plan_lesfiche`.
const maxPlanLesficheHours = 20;

/// `plan_lesfiche`: plans a lesson lesfiche of the user's Lesfiches module
/// into one or more lesson hours of the user's own planner (#54, #190): the
/// planner names each lesson after the lesfiche and copies its content.
///
/// Pupils see a lesson as soon as it is saved, so the tool is marked
/// destructive, like `plan_lesson`. An hour that already holds a lesson is
/// replaced only when `replace` is true (the product decision of #190):
/// without it a lesson's id is refused before anything is sent, so that
/// nothing typed in by hand is overwritten by accident.
///
/// One empty hour is filled with the library's `planLessonContent`, one
/// lesson replaced with `replaceWithLessonContent` ([fillLessonHour]); two
/// or more hours go in one request, `planLessonContentInto`, which reports
/// per hour whether the planner planned it ([_planIntoSeveral]). The library
/// reads the lesfiches and every hour again before it plans, and refuses an
/// id the user has no lesfiche with, an assignment lesfiche, and an hour that
/// is not the user's own, before sending anything; it sends each plan once.
ServerTool planLesficheTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'plan_lesfiche',
    title: 'Plan a lesfiche in Smartschool lesson hours',
    description:
        'Plans a lesfiche of the user\'s Smartschool Lesfiches module into '
        'lesson hours of the user\'s own planner: 1 to '
        '$maxPlanLesficheHours hours in one call, such as the same lesson in '
        'all parallel classes. Each hour becomes a lesson named after the '
        'lesfiche, and the planner copies its content. Pupils of the hour\'s '
        'classes see the lesson\'s name and public info as soon as it is '
        'saved. Only lesson lesfiches can be planned (hidden ones too): an '
        'assignment lesfiche, or an id the user has no lesfiche with, is '
        'refused. Only the user\'s own planner can be changed: list_planner '
        'also shows colleagues\' hours, and this tool refuses those. An hour '
        'is an empty lesson hour; an hour that already holds a lesson (one '
        'typed in by hand, say) is refused, so nothing is overwritten by '
        'accident, unless replace is true: then the lesson is replaced by '
        'the lesfiche, and its old name, info and goals are gone. Set '
        'replace only when the user explicitly asked to replace those '
        'lessons. First list the lesfiches with list_lesfiches and the hours '
        'with list_planner (planner me), and take the ids from there. Show '
        'the user, per hour, the date and time, the class, the course, the '
        'name of the lesfiche that goes there, and any lesson it replaces, '
        'and only call this tool after the user has explicitly confirmed '
        'it. For a series of lesfiches, one confirmation of the full mapping '
        'is enough; then call this tool once per lesfiche, with all its '
        'hours. Planning copies the lesfiche: the planner copies its public '
        'and private info, labels, learning goals, attachments and weblinks '
        'into the lesson, each attachment and weblink visible to pupils as '
        'the lesfiche says; the lesson keeps the course of the hour, not the '
        'lesfiche\'s, and a later change to the lesfiche does not reach the '
        'lesson. The result says per hour whether it was planned, and gives '
        'the new lesson\'s id: the hour\'s old id no longer exists. For a '
        'few seconds after a change list_planner can still show the old '
        'state: check a lesson with read_planned_element. If the result says '
        'the lessons may or may not have been saved, do not call this tool '
        'again for those hours: check them with read_planned_element and '
        'tell the user. To change a planned lesson, use '
        'edit_planned_element; to empty its hour again, clear_lesson; to '
        'keep a lesson typed in by hand as a lesfiche, '
        'save_lesson_as_lesfiche. For a lesfiche that does not exist yet, '
        'make it first with create_lesfiche.',
    inputSchema: Schema.object(
      properties: {
        'hours': Schema.list(
          description:
              'The ids of the lesson hours of your own planner, as '
              'list_planner (planner me) shows them and as the user '
              'confirmed them: empty lesson hours, like '
              'planned-placeholders/4069/…, and with replace also lessons, '
              'like planned-lessons/4069/…. At most $maxPlanLesficheHours; '
              'each is planned once.',
          items: Schema.string(minLength: 1),
          minItems: 1,
          maxItems: maxPlanLesficheHours,
        ),
        'lesfiche': Schema.string(
          description:
              'The id of a lesson lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'replace': Schema.bool(
          description:
              'Whether an hour that holds a lesson is replaced by the '
              'lesfiche (its old name, info and goals are gone). False by '
              'default: a lesson among the hours is then refused, and '
              'nothing is sent. Only true when the user explicitly asked to '
              'replace those lessons.',
        ),
      },
      required: ['hours', 'lesfiche'],
    ),
    annotations: ToolAnnotations(
      title: 'Plan a lesfiche in Smartschool lesson hours',
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
  final hours = _hoursArgument(arguments['hours']);
  final lesfiche = lesficheArgument(arguments['lesfiche']);
  final replace = _replaceArgument(arguments['replace']);
  final lessons = [
    for (final hour in hours)
      if (hour.type == PlannedElementType.lesson) hour,
  ];
  if (lessons.isNotEmpty && !replace) {
    throw ToolError(
      '${lessons.length == 1 ? 'hours holds a lesson' : 'hours holds '
                '${lessons.length} lessons'}, not an empty lesson hour: '
      '${lessons.join(', ')}. A lesson is only replaced by the lesfiche when '
      'replace is true, and then its old name, info and goals are gone. Set '
      'replace only when the user explicitly asked to replace '
      '${lessons.length == 1 ? 'that lesson' : 'those lessons'}; else leave '
      '${lessons.length == 1 ? 'it' : 'them'} out. Nothing was sent.',
    );
  }
  if (hours.length > 1) {
    return _planIntoSeveral(session, hours: hours, lesfiche: lesfiche);
  }
  final hour = hours.single;
  return fillLessonHour(
    session,
    tool: 'plan_lesfiche',
    hour: hour,
    what: 'the lesfiche $lesfiche',
    withGoals: true,
    fill: (planner, slot) => hour.type == PlannedElementType.lesson
        ? planner.replaceWithLessonContent(
            lesson: slot,
            lessonContentId: lesfiche,
          )
        : planner.planLessonContent(
            placeholder: slot,
            lessonContentId: lesfiche,
          ),
  );
}

/// The `hours` argument [value]: 1 to [maxPlanLesficheHours] ids of lesson
/// hours ([lessonHourArgument]: an empty lesson hour or a lesson), each
/// once, in the order given. A single id given as a text is taken as a
/// list of one.
///
/// Throws a [ToolError] that names the item for anything else, before
/// anything is sent.
List<PlannedElementRef> _hoursArgument(Object? value) {
  final items = value is List ? value : [value];
  final hours = <PlannedElementRef>[];
  for (final (index, item) in items.indexed) {
    final hour = lessonHourArgument(
      item,
      name: items.length == 1 ? 'hours' : 'item ${index + 1} of hours',
    );
    if (!hours.contains(hour)) hours.add(hour);
  }
  if (hours.isEmpty) {
    throw const ToolError(
      'hours is empty: pass the ids of the lesson hours, as list_planner '
      '(planner me) shows them. Nothing was sent.',
    );
  }
  if (hours.length > maxPlanLesficheHours) {
    throw ToolError(
      'hours holds ${hours.length} hours, and at most $maxPlanLesficheHours '
      'fit in one call: plan the others in another call. Nothing was sent.',
    );
  }
  return hours;
}

/// The `replace` argument [value]: false when absent.
bool _replaceArgument(Object? value) => switch (value) {
  null => false,
  final bool replace => replace,
  _ => throw ToolError(
    'replace must be true or false; $value is not. Nothing was sent.',
  ),
};

/// Plans the lesfiche [lesfiche] into the [hours] (two or more) in one
/// request, the library's `planLessonContentInto`, and says per hour
/// whether the planner planned it. The hours are read first, in the session
/// action of the write: the library takes them as read, and reads them
/// again before it sends.
Future<CallToolResult> _planIntoSeveral(
  SmartschoolSession session, {
  required List<PlannedElementRef> hours,
  required String lesfiche,
}) async {
  var read = <PlannedElementDetail>[];
  try {
    final result = await withPlannerWrite(session, (planner) async {
      read = [for (final hour in hours) await hour.read(planner)];
      return planner.planLessonContentInto(
        lessonContentId: lesfiche,
        targets: read,
      );
    });
    final planned = result.lessons;
    final goals = planned.isEmpty
        ? null
        : await nameGoalsAfterWrite(session, planned.first.goals);
    return _severalResult(result, lesfiche: lesfiche, goals: goals);
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    final where = read.length == hours.length
        ? [for (final hour in read) formatElementSummary(hour)]
        : [for (final hour in hours) '$hour'];
    return plannerWriteNotConfirmed(
      tool: 'plan_lesfiche',
      what:
          'The lesfiche $lesfiche in the ${hours.length} hours '
          '(${where.join('; ')})',
      done: 'saved, in all or some of them',
      check:
          'read each hour with read_planned_element (ids '
          '${hours.join(', ')}): an hour the planner no longer has under its '
          'id was planned, and list_planner (planner me) shows the lesson in '
          'its place, possibly only after a few seconds; an hour that is '
          'still there was not',
      error: error,
    );
  }
}

/// The result of the plan of [lesfiche] into several hours ([result]): a
/// line per hour, planned or not, and the first new lesson in full, with
/// its [goals] named. An error result when the planner did not plan every
/// hour.
CallToolResult _severalResult(
  PlannerBulkResult result, {
  required String lesfiche,
  required NamedGoals? goals,
}) {
  final outcomes = result.outcomes;
  final planned = result.lessons;
  final failed = result.failed;
  final lines = <String>[
    if (planned.isEmpty)
      'The planner planned the lesfiche $lesfiche into none of the '
          '${outcomes.length} hours.'
    else
      'Planned the lesfiche $lesfiche into '
          '${failed.isEmpty ? 'all ${outcomes.length}' : '${planned.length} of the ${outcomes.length}'} '
          'hours. Pupils of their classes see its name and public info now.',
    for (final outcome in outcomes) _outcomeLine(outcome),
    if (planned.isNotEmpty)
      'The old id of an hour that was planned no longer exists: use the '
          'lesson\'s new id.',
    if (failed.isNotEmpty)
      'Do not call plan_lesfiche again for the hours that were planned. '
          'Tell the user which hours were not planned and why; they were '
          'left as they were.',
    if (planned.isNotEmpty) ...[
      plannerListLagNote,
      '',
      if (planned.length > 1)
        'The first lesson as saved (the others hold the same content of the '
            'lesfiche, each in its own hour):',
      formatElementDetail(planned.first, goals: goals),
    ],
  ];
  return CallToolResult(
    isError: failed.isNotEmpty,
    content: [TextContent(text: lines.join('\n'))],
  );
}

/// One line of [_severalResult]: the hour, and its new lesson or why the
/// planner did not plan it.
String _outcomeLine(PlannerBulkOutcome outcome) {
  final target = outcome.target;
  final id = PlannedElementRef.of(target);
  final hour = '- The ${formatElementSummary(target)} ($id)';
  if (outcome.lesson case final lesson?) {
    final replaced = target.type == PlannedElementType.lesson
        ? 'replaced by the lesfiche (its old name, info and goals are gone)'
        : 'planned';
    return '$hour: $replaced; the lesson has the id '
        '${PlannedElementRef.of(lesson)}.';
  }
  log(
    'plan_lesfiche: the planner did not plan $id: '
    '${_encode(outcome.exception)}',
  );
  final reason = _reason(outcome.exception);
  return '$hour: not planned: the planner refused it'
      '${reason == null ? ' without a reason the server can show (its answer '
                'is in the server log)' : ' ("$reason")'}.';
}

/// What the planner gave as the reason it did not plan a target
/// ([exception], in a shape not seen live): a text, or the `message`,
/// `detail` or `title` of an object; at most 200 characters. Null when it
/// gives none of those.
String? _reason(Object? exception) {
  final text = switch (exception) {
    final String text => text,
    final Map<Object?, Object?> map => [
      map['message'],
      map['detail'],
      map['title'],
    ].whereType<String>().where((text) => text.trim().isNotEmpty).firstOrNull,
    _ => null,
  };
  final reason = text?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (reason == null || reason.isEmpty) return null;
  return reason.length <= 200 ? reason : '${reason.substring(0, 199)}…';
}

String _encode(Object? value) {
  try {
    return jsonEncode(value);
  } on Object {
    return '$value';
  }
}
