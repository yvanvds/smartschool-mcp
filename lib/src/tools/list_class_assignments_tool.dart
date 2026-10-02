import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../session.dart';
import 'list_planner_tool.dart' show maxPlannerLines;
import 'server_tool.dart';

/// A period without `until` runs to this many days after `from`: 4 weeks.
const defaultClassAssignmentDays = 28;

/// At most this many classes per call.
const maxAssignmentClasses = 10;

/// `list_class_assignments`: the assignments (tests and tasks) of one or
/// more classes in a period, of everyone who plans them, per day, with the
/// workload limit the school set for a class: the facts to pick a moment
/// for a new test.
///
/// [now] gives today, for the default period.
ServerTool listClassAssignmentsTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'list_class_assignments',
    title: 'List the tests and tasks of classes',
    description:
        'Lists the assignments (tests and tasks) of one or more classes in a '
        'period, per day: those of everyone who teaches the classes, not '
        'only your own. Use it to see when a class already has a test, '
        'before choosing a moment for a new one. Pass the planner ids of the '
        'classes from search_planners (like group/4069_4256), at most '
        '$maxAssignmentClasses. Every day of the period is listed in date '
        'order, a day without assignments as "no assignments" (Saturday and '
        'Sunday only when something falls on them). Each assignment shows its '
        'deadline, its type (such as "KO Kleine Overhoring"), name, course, '
        'classes, who planned it, the room, and the id for '
        'read_planned_element. When the school set a workload limit for a '
        'class, the answer gives it with the planner\'s own figure per day; '
        'it also lists the school\'s assignment types. Other elements of the '
        'class, such as a trip, are not listed: list_planner with the class '
        'planner shows them. To choose a moment, also look at when the user '
        'has lessons with the class (list_planner with planner me). Propose '
        'moments to the user and let the user choose: this tool only reads '
        'and never plans anything. For questions like "wanneer kan ik best '
        'een toets plannen in 6WEWI1?" or "welke toetsen heeft 5WW1 '
        'volgende week?".',
    inputSchema: Schema.object(
      properties: {
        'classes': Schema.list(
          description:
              'The planner ids of the classes, from search_planners, like '
              'group/4069_4256: 1 to $maxAssignmentClasses classes, read '
              'in one request.',
          items: Schema.string(),
        ),
        'from': Schema.string(
          description:
              'The first day, like 2026-10-05 (from the start of the day), or '
              'a date and time like 2026-10-05 14:30. Smartschool time '
              '(Belgium). Default: today.',
        ),
        'until': Schema.string(
          description:
              'The last day, like 2026-10-30 (to the end of the day), or a '
              'date and time. Default: $defaultClassAssignmentDays days (4 '
              'weeks) after from.',
        ),
      },
      required: ['classes'],
    ),
    annotations: ToolAnnotations(
      title: 'List the tests and tasks of classes',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}, now),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
  DateTime Function() now,
) async {
  final classes = classPlannersArgument(
    arguments['classes'],
    name: 'classes',
    max: maxAssignmentClasses,
  );
  final (:from, :until) = plannerPeriodArguments(
    arguments,
    days: defaultClassAssignmentDays,
    now: now,
  );
  final groupIds = [for (final calendar in classes) calendar.id];
  final types = AssignmentTypes.of(session);

  final (assignments, workload, schoolTypes) = await withPlanner(session, (
    planner,
  ) async {
    final assignments = await planner.getAssignmentsOfGroups(
      groupIds: groupIds,
      from: from,
      to: until,
    );
    final workload = await _readOptionally(
      () => planner.getWorkloadSchedule(
        groupIds: groupIds,
        from: from,
        to: until,
      ),
    );
    final schoolTypes = await _readOptionally(() => types.read(planner));
    return (assignments, workload, schoolTypes);
  });

  return CallToolResult(
    content: [
      TextContent(
        text: formatClassAssignments(
          classes: classes,
          from: from,
          until: until,
          assignments: assignments,
          workload: workload,
          assignmentTypes: schoolTypes.value,
        ),
      ),
    ],
  );
}

/// What [read] gives, or the planner's error it failed with: a part of the
/// answer that the assignments do not need.
///
/// Only a [SmartschoolPlannerError] is caught, which the log gets (the
/// library's message can quote the planner's answer): a refused session or
/// a lost connection still goes to [SmartschoolSession.run].
Future<({T? value, SmartschoolPlannerError? error})> _readOptionally<T>(
  Future<T> Function() read,
) async {
  try {
    return (value: await read(), error: null);
  } on SmartschoolPlannerError catch (error) {
    log('planner: $error');
    return (value: null, error: error);
  }
}

/// What `list_class_assignments` answers: a header with the [classes] and
/// the period, every day of it with its [assignments] (Saturday and Sunday
/// only when something falls on them), at most [maxPlannerLines] lines,
/// then the workload limits the school set and the school's
/// [assignmentTypes].
///
/// [workload] is the planner's workload schedule of the classes, or the
/// error reading it failed with; [assignmentTypes] is null when they could
/// not be read.
String formatClassAssignments({
  required List<PlannerCalendar> classes,
  required DateTime from,
  required DateTime until,
  required List<PlannedElement> assignments,
  required ({
    Map<DateTime, List<PlannerGroupWorkload>>? value,
    SmartschoolPlannerError? error,
  })
  workload,
  required List<PlannerAssignmentType>? assignmentTypes,
}) {
  final schedule = workload.value ?? const {};
  // The name of a class as the schedule or an assignment gives it.
  String? className(PlannerCalendar calendar) =>
      [
        for (final day in schedule.values)
          for (final load in day)
            if (load.group.id == calendar.id && load.group.name != '')
              load.group.name,
      ].firstOrNull ??
      plannerName(calendar, assignments);

  final named = [
    for (final calendar in classes)
      switch (className(calendar)) {
        final name? => '$name (${formatPlannerId(calendar)})',
        null => formatPlannerId(calendar),
      },
  ];
  final header =
      'Assignments (tests and tasks, by anyone) of ${named.join(', ')}, '
      '${formatPlannerPeriod(from, until)}';
  final (:days, :note) = _days(from, until, assignments);
  return [
    if (assignments.isEmpty)
      '$header: no assignments.'
    else
      '$header: ${assignments.length} '
          '${assignments.length == 1 ? 'assignment' : 'assignments'}.',
    ...days,
    ..._workloadLimits(
      classes,
      schedule,
      (calendar) => className(calendar) ?? formatPlannerId(calendar),
    ),
    if (workload.error case SmartschoolPlannerError(:final statusCode))
      'Note: the workload limits of these classes could not be read'
          '${statusCode == null ? '' : ' (HTTP $statusCode)'}, so a limit is '
          'not shown; the assignments above are complete.',
    if (assignmentTypes != null && assignmentTypes.isNotEmpty)
      'Assignment types of the school: '
          '${assignmentTypes.map(formatAssignmentType).join(', ')}.',
    ?note,
  ].join('\n');
}

/// The lines of the days from [from] to [until] with their [assignments]:
/// a day with assignments as its date and one line per assignment, a day
/// without as `Wednesday 2026-10-07: no assignments`, Saturday and Sunday
/// only when an assignment falls on them. No lines when there are no
/// assignments at all.
///
/// At most [maxPlannerLines] lines, whole days only (the first day always),
/// with a [note] on where to go on.
({List<String> days, String? note}) _days(
  DateTime from,
  DateTime until,
  List<PlannedElement> assignments,
) {
  if (assignments.isEmpty) return (days: const [], note: null);
  final byDay = elementsByDay(assignments);
  final last = plannerDayOf(until);
  final days = <DateTime>{
    ...byDay.keys,
    for (
      var day = plannerDayOf(from);
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)
    )
      if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday)
        day,
  }.toList()..sort();

  final lines = <String>[];
  var shown = 0;
  for (final (index, day) in days.indexed) {
    final dayAssignments = byDay[day] ?? const [];
    final block = dayAssignments.isEmpty
        ? ['${formatPlannerDay(day)}: no assignments']
        : [
            formatPlannerDay(day),
            for (final element in dayAssignments)
              '- ${formatElementLine(element)}',
          ];
    if (index > 0 && lines.length + block.length > maxPlannerLines) {
      return (
        days: lines,
        note:
            'Note: only the days up to ${formatPlannerDay(days[index - 1])} '
            'are shown ($shown of the ${assignments.length} assignments). '
            'For the rest, list again from ${formatPlannerDate(day)}.',
      );
    }
    lines.addAll(block);
    shown += dayAssignments.length;
  }
  return (days: lines, note: null);
}

/// One line per class of [classes] for which the school set a workload limit
/// (a limit of 0 or more; `Geen limiet` is `-1`), under a heading: the
/// limit as the planner gives it, and the days the planner's figure is not
/// 0, such as `6A1: limit 2 per day (soft); 2026-10-06 is at 2`. No lines
/// when no class has a limit.
///
/// The figures are the planner's own, not interpreted: what they add up is
/// not known (dartschool#86).
List<String> _workloadLimits(
  List<PlannerCalendar> classes,
  Map<DateTime, List<PlannerGroupWorkload>> schedule,
  String Function(PlannerCalendar calendar) className,
) {
  final lines = <String>[];
  for (final calendar in classes) {
    // The days per limit, should the limit differ between days.
    final limits = <String, List<(DateTime, num)>>{};
    for (final MapEntry(key: day, value: loads) in schedule.entries) {
      for (final load in loads) {
        final limit = load.setting?.limit;
        if (load.group.id != calendar.id || limit == null || limit.value < 0) {
          continue;
        }
        limits.putIfAbsent(_formatLimit(limit), () => []).add((
          day,
          load.weight,
        ));
      }
    }
    for (final MapEntry(key: limit, value: days) in limits.entries) {
      final counted = [
        for (final (day, weight) in days)
          if (weight != 0) '${formatPlannerDate(day)} is at ${_figure(weight)}',
      ];
      lines.add(
        '- ${className(calendar)}: $limit; '
        '${counted.isEmpty ? 'every day is at 0' : counted.join(', ')}',
      );
    }
  }
  return [
    if (lines.isNotEmpty)
      'Workload limits the school set, with the planner\'s own figures:',
    ...lines,
  ];
}

/// [limit] as `limit 2 per day (soft)`.
String _formatLimit(PlannerWorkloadLimit limit) => [
  'limit ${_figure(limit.value)}',
  if (limit.period.isNotEmpty) 'per ${limit.period}',
  if (limit.type.isNotEmpty) '(${limit.type})',
].join(' ');

/// [value] without a decimal part when it has none: `2`, `1.5`.
String _figure(num value) =>
    value == value.truncate() ? '${value.truncate()}' : '$value';
