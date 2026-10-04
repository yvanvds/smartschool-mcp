import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `plan_assignment`: plans an assignment (a test, a task, something to
/// bring along) in the user's own planner, anchored on one of the user's own
/// lesson hours: for the hour's classes (or some of them), its course and its
/// rooms, due at the start of the hour and running to its end.
///
/// Pupils of the classes see the assignment as soon as it is made, so the
/// tool is marked destructive (for Claude Desktop to ask for approval before
/// every call). The library sends the create once, never again after logging
/// in again: a create the planner does not confirm is reported as maybe
/// saved ([plannerWriteNotConfirmed]), and Claude is told not to call the
/// tool again for it, as that could plan the assignment twice.
ServerTool planAssignmentTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'plan_assignment',
    title: 'Plan a test or task in the Smartschool planner',
    description:
        'Plans an assignment (a test, a task, something to bring along) in '
        'the user\'s own Smartschool planner, in one of the user\'s own '
        'lesson hours: for the classes of that hour (or some of them, with '
        'classes), its course and its room, due at the start of the hour. '
        'The hour itself stays as it is. Pupils of the classes see a new '
        'assignment at once. Planning it does not send a notification; '
        'Smartschool\'s separate "aankondigen" (announce) is not offered. '
        'Only the user\'s own planner can be changed: list_planner also shows '
        'colleagues\' hours, and this tool refuses those. Take the id of the '
        'hour (an empty lesson hour or a lesson) from list_planner (planner '
        'me). Before calling this tool, first check the other tests and '
        'tasks of the class(es) with list_class_assignments. Show the user '
        'the class(es), the date and hour, the type, the name and the info, '
        'and only call this tool after the user has explicitly confirmed it. '
        'The type is one of the school\'s assignment types, by its '
        'abbreviation or name, such as KO or Kleine Overhoring '
        '(list_class_assignments lists them). Private info is hidden from '
        'pupils, but colleagues who can see the assignment read it too. Write '
        'the info as plain text, with a blank line between paragraphs; HTML '
        'in it is not interpreted, it shows as text. The result gives the '
        'assignment as saved, with its id. To change its name or info, use '
        'edit_planned_element; to remove it, trash_assignment. If the result '
        'says the assignment may or may not have been saved, do not call this '
        'tool again for it, as that could plan it twice: first check the '
        'class\'s assignments with list_class_assignments (or the assignment '
        'with read_planned_element, once list_planner shows its id) and tell '
        'the user. For requests like "plan een kleine overhoring over '
        'hoofdstuk 3 in 6WEWI1 dinsdag het 3e uur".',
    inputSchema: Schema.object(
      properties: {
        'hour': Schema.string(
          description:
              'The id of a lesson hour of your own planner, as list_planner '
              '(planner me) shows it: an empty lesson hour '
              '(planned-placeholders/4069/…) or a lesson '
              '(planned-lessons/4069/…). The assignment is due at its start.',
          minLength: 1,
        ),
        'type': Schema.string(
          description:
              'One of the school\'s assignment types, by its abbreviation or '
              'name, such as KO or Kleine Overhoring, as the user confirmed '
              'it.',
          minLength: 1,
        ),
        'name': Schema.string(
          description:
              'The name of the assignment, as the user confirmed it. Pupils '
              'see it.',
          minLength: 1,
        ),
        'public_info': Schema.string(
          description:
              'What pupils see with the assignment, as plain text: a blank '
              'line between paragraphs. Default: none.',
        ),
        'private_info': Schema.string(
          description:
              'Notes pupils do not see, as plain text. Colleagues who can '
              'see the assignment read them too. Default: none.',
        ),
        'classes': Schema.list(
          description:
              'Only for some of the classes of the hour, when it is shared by '
              'several and the assignment is for one of them: each by its '
              'name as list_planner shows it (like 6A1) or its planner id '
              '(like group/4069_2001). Default: all classes of the hour.',
          items: Schema.string(),
        ),
      },
      required: ['hour', 'type', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Plan a test or task in the Smartschool planner',
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
  final hour = lessonHourArgument(arguments['hour']);
  final typeName = arguments['type'] as String? ?? '';
  if (typeName.trim().isEmpty) {
    throw const ToolError(
      'type is empty: pass one of the school\'s assignment types by its '
      'abbreviation or name, such as KO or Kleine Overhoring '
      '(list_class_assignments lists them). Nothing was sent.',
    );
  }
  final name = (arguments['name'] as String? ?? '').trim();
  if (name.isEmpty) {
    throw const ToolError(
      'name is empty: pass the name of the assignment. Nothing was sent.',
    );
  }
  final wanted = lessonHourClassesArgument(arguments['classes']);
  final publicInfo = plainTextToHtml(arguments['public_info'] as String? ?? '');
  final privateInfo = plainTextToHtml(
    arguments['private_info'] as String? ?? '',
  );
  final assignmentTypes = AssignmentTypes.of(session);

  // What the create was sent with, for its result when the planner does
  // not confirm it.
  ({
    PlannedElementDetail hour,
    PlannerAssignmentType type,
    List<PlannerGroup> classes,
  })?
  sent;
  try {
    final assignment = await withPlannerWrite(session, (planner) async {
      final type = assignmentTypeArgument(
        typeName,
        await assignmentTypes.read(planner),
      );
      final slot = await hour.read(planner);
      await _refuseUnlessOwn(planner, slot);
      final classes = lessonHourClasses(slot, wanted);
      final course = slot.courses.firstOrNull;
      if (course == null) {
        throw ToolError(
          'The ${formatElementSummary(slot)} has no course, which an '
          'assignment needs: plan it in a lesson hour of the course.',
        );
      }
      sent = (hour: slot, type: type, classes: classes);
      try {
        return await planner.planAssignment(
          groupIds: [for (final group in classes) group.id],
          course: course,
          type: type,
          name: name,
          due: slot.period.from,
          until: slot.period.to,
          publicInfo: publicInfo,
          privateInfo: privateInfo,
          locations: slot.locations,
        );
      } on SmartschoolPlannerWriteRefusedError catch (error) {
        // The school's types changed since the session read them: say so
        // with the types as the library's check read them, which every tool
        // on the session takes from now on. Any other refusal is worded by
        // plannerToolError.
        if (error.reason != PlannerWriteRefusalReason.unknownAssignmentType) {
          rethrow;
        }
        log('planner: $error');
        assignmentTypes.replace(error.assignmentTypes);
        throw _typeGone(typeName, type, error.assignmentTypes);
      }
    });
    final slot = sent!.hour;
    final classes = elementClasses(assignment);
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Planned the ${formatElementSummary(assignment)}, in the '
                '${formatElementSummary(slot)}, which stays as it is. Pupils'
                '${classes.isEmpty ? '' : ' of $classes'} see it now; it was '
                'not announced.',
            'The assignment has the id ${PlannedElementRef.of(assignment)}: '
                'change its name or info with edit_planned_element, or move '
                'it to the trash with trash_assignment.',
            plannerListLagNote,
            '',
            formatElementDetail(assignment),
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    // Only the create throws it, after [sent] was set.
    final (hour: slot, :type, :classes) = sent!;
    final day = formatPlannerDate(slot.period.from);
    final names = classes.map((group) => group.name).join(', ');
    final ids = classes.map((group) => 'group/${group.id}').join(', ');
    return plannerWriteNotConfirmed(
      tool: 'plan_assignment',
      what:
          'The assignment ${formatAssignmentType(type)} "$name" for $names '
          'on ${formatPlannerDay(slot.period.from)} '
          '${formatPlannerClock(slot.period.from)} (deadline)',
      check:
          'list the assignments of $names on that day with '
          'list_class_assignments (classes $ids, from and until $day): when '
          'your assignment "$name" is there, it was saved, possibly only '
          'shown after a few seconds; when it is not, nothing was saved',
      error: error,
    );
  }
}

/// The error for [type], the school's assignment type that [typeName] named
/// as the session read the types, which the library refused as no longer
/// one of the school's: with [types], the school's types as the library's
/// check read them (as [assignmentTypeArgument] lists them), which the user
/// chooses from.
ToolError _typeGone(
  String typeName,
  PlannerAssignmentType type,
  List<PlannerAssignmentType> types,
) => ToolError(
  '$plannerRefused: type "$typeName" named the assignment type '
  '${formatAssignmentType(type)}, which is no longer one of the school\'s '
  'assignment types: they changed since the server read them. '
  '${schoolAssignmentTypes(types)} Ask the user which one to use instead, '
  'and pass it by its abbreviation or its name; list_class_assignments '
  'lists them too.',
);

/// Refuses [hour] unless it is in the user's own planner (the user is one of
/// its organisers): a class planner also shows colleagues' hours, and an
/// assignment is only planned in an own hour. The library's create does not
/// check this, as it takes no hour.
Future<void> _refuseUnlessOwn(
  PlannerService planner,
  PlannedElementDetail hour,
) async {
  final me = (await planner.ownCalendar()).id;
  if (hour.organiserUsers.any((user) => user.id == me)) return;
  final organisers = [
    for (final user in hour.organiserUsers)
      if (user.name.trim().isNotEmpty) user.name.trim(),
  ];
  throw ToolError(
    'hour is not a lesson hour of your own planner: the '
    '${formatElementSummary(hour)} is organised by '
    '${organisers.isEmpty ? 'someone else' : organisers.join(', ')}. Plan an '
    'assignment in one of your own lesson hours, as list_planner (planner '
    'me) shows them.',
  );
}
