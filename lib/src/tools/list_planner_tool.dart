import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// A period without `until` runs to this many days after `from`.
const defaultPlannerDays = 7;

/// At most this many elements are listed, with a note on how to ask for
/// fewer. A class planner holds about 45 elements a week.
const maxPlannerLines = 200;

/// The kinds of element `list_planner` can be limited to (its `types`).
enum PlannerKind {
  lessons('lessons', 'lesson', 'lessons', PlannedElementType.lesson),
  assignments(
    'assignments',
    'assignment',
    'assignments',
    PlannedElementType.assignment,
  ),
  emptyLessonHours(
    'empty_lesson_hours',
    'empty lesson hour',
    'empty lesson hours',
    PlannedElementType.placeholder,
  ),

  /// Every other type, also one the library does not know.
  other('other', 'other', 'other', null);

  const PlannerKind(this.argument, this.singular, this.plural, this.type);

  /// The name in the `types` argument.
  final String argument;

  final String singular;
  final String plural;

  /// The element type, or null for [other].
  final PlannedElementType? type;

  /// The kind of [element].
  static PlannerKind of(PlannedElement element) => values.firstWhere(
    (kind) => kind.type == element.type,
    orElse: () => other,
  );

  /// `1 lesson`, `2 lessons`.
  String count(int count) => '$count ${count == 1 ? singular : plural}';
}

/// `list_planner`: what is planned in a planner (the user's own, or that of
/// a class, a person or a room) in a period, per day.
///
/// [now] gives today, for the default period.
ServerTool listPlannerTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'list_planner',
    title: 'List a Smartschool planner',
    description:
        'Lists what is planned in a Smartschool planner in a period: your own '
        '(planner "me", the default), or that of a class, a person or a room '
        '(a planner id from search_planners). Grouped per day, in date order, '
        'one line per element: the time (for an assignment, its deadline), '
        'the kind (lesson; assignment with its type, such as "KO Kleine '
        'Overhoring"; empty lesson hour, an hour of the timetable without a '
        'lesson; or another planner type), the name, course, classes, who '
        'planned it, the room, and the id for read_planned_element. A class '
        'planner holds the elements of everyone who teaches the class: each '
        'of their timetable hours shows as an empty lesson hour until a '
        'lesson fills it. To see whether a room is free, list its planner for '
        'that day. A long period is fine, but at most $maxPlannerLines lines '
        'are shown: for fewer, pass types or a shorter period. The id of an '
        'empty lesson hour changes once the hour is filled, so take ids from '
        'a recent list. Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'planner': Schema.string(
          description:
              'Whose planner: me (your own, the default), or a planner id '
              'from search_planners, like group/4069_4256 (a class), '
              'user/4069_218_0 (a person) or location/4069_<id> (a room).',
        ),
        'from': Schema.string(
          description:
              'The first day, like 2026-10-05 (from the start of the day), or '
              'a date and time like 2026-10-05 14:30. Smartschool time '
              '(Belgium). Default: today.',
        ),
        'until': Schema.string(
          description:
              'The last day, like 2026-10-09 (to the end of the day), or a '
              'date and time. Default: $defaultPlannerDays days after from.',
        ),
        'types': UntitledMultiSelectEnumSchema(
          description:
              'Only these kinds: lessons, assignments (tests, tasks), '
              'empty_lesson_hours (hours of the timetable without a lesson) '
              'and/or other. Default: all.',
          values: [for (final kind in PlannerKind.values) kind.argument],
          minItems: 1,
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List a Smartschool planner',
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
  final planner = PlannerRef.parse(arguments['planner']);
  final (:from, :until) = plannerPeriodArguments(
    arguments,
    days: defaultPlannerDays,
    now: now,
  );
  final kinds = _kinds(arguments['types']);
  // The planner filters on the types it knows; other needs every type.
  final types = kinds == null || kinds.contains(PlannerKind.other)
      ? null
      : {for (final kind in kinds) kind.type!};

  final (calendar, elements) = await withPlanner(session, (service) async {
    final calendar = await planner.resolve(service);
    final elements = await service.getPlannedElements(
      calendar,
      from: from,
      to: until,
      types: types,
    );
    return (calendar, elements);
  });

  final shown = [
    for (final element in elements)
      if (kinds == null || kinds.contains(PlannerKind.of(element))) element,
  ];
  return CallToolResult(
    content: [
      TextContent(
        text: formatPlannerList(
          planner: planner,
          calendar: calendar,
          from: from,
          until: until,
          kinds: kinds,
          elements: shown,
        ),
      ),
    ],
  );
}

/// The kinds the `types` argument names, or null for all (absent, or all
/// of them).
Set<PlannerKind>? _kinds(Object? value) {
  if (value is! List) return null;
  final kinds = {
    for (final kind in PlannerKind.values)
      if (value.contains(kind.argument)) kind,
  };
  return kinds.isEmpty || kinds.length == PlannerKind.values.length
      ? null
      : kinds;
}

/// What `list_planner` answers: a header with the planner, the period and
/// the counts, then [elements] per day, at most [maxPlannerLines].
///
/// The organisers of an element in the user's own planner leave out the
/// user.
String formatPlannerList({
  required PlannerRef planner,
  required PlannerCalendar calendar,
  required DateTime from,
  required DateTime until,
  required Set<PlannerKind>? kinds,
  required List<PlannedElement> elements,
}) {
  final name = plannerName(calendar, elements);
  final who = planner.isMe
      ? 'your own planner (me)'
      : 'planner ${formatPlannerId(calendar)}${name == null ? '' : ' ($name)'}';
  final period =
      'from ${_moment(from, end: false)} to ${_moment(until, end: true)}';
  final only = kinds == null
      ? ''
      : ' (only ${[for (final kind in kinds) kind.plural].join(', ')})';
  if (elements.isEmpty) {
    return 'Planner: $who, $period$only: nothing planned.';
  }

  final counts = [
    for (final kind in PlannerKind.values)
      if (elements.where((e) => PlannerKind.of(e) == kind).length
          case final count when count > 0)
        kind.count(count),
  ];
  final sorted = sortedByTime(elements);
  final shown = sorted.take(maxPlannerLines).toList();
  final ownUserId = planner.isMe ? calendar.id : null;
  return [
    'Planner: $who, $period$only: ${elements.length} '
        '${elements.length == 1 ? 'element' : 'elements'} '
        '(${counts.join(', ')}).',
    for (final MapEntry(key: day, value: dayElements) in elementsByDay(
      shown,
    ).entries) ...[
      formatPlannerDay(day),
      for (final element in dayElements)
        '- ${formatElementLine(element, ownUserId: ownUserId)}',
    ],
    if (shown.length < sorted.length)
      'Note: only the first ${shown.length} of the ${sorted.length} are '
          'shown, up to ${formatPlannerDay(shown.last.period.from)}. For '
          'fewer, list a shorter period, or only some types (such as '
          'assignments).',
  ].join('\n');
}

/// [time] as the start ([end] false) or end of a period: the day when it is
/// the start or the end of that day, else the day and the time.
String _moment(DateTime time, {required bool end}) {
  final wholeDay = end
      ? time.hour == 23 && time.minute == 59
      : time.hour == 0 && time.minute == 0;
  return wholeDay
      ? formatPlannerDay(time)
      : '${formatPlannerDay(time)} ${formatPlannerClock(time)}';
}
