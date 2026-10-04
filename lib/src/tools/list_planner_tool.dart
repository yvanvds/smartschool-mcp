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

/// The kinds of element `list_planner` can be limited to (its `types`): one
/// for each kind the planner tools name and count ([PlannedElementKind]).
///
/// The planner itself is asked only for lessons, assignments and empty
/// lesson hours ([plannerType]). The other kinds are kept here from every
/// type read: asking the planner for `planned-meetings` or
/// `planned-lesson-free-days` was never tried live (#103).
enum PlannerKind {
  lessons('lessons', PlannedElementKind.lesson, askPlanner: true),
  assignments('assignments', PlannedElementKind.assignment, askPlanner: true),
  emptyLessonHours(
    'empty_lesson_hours',
    PlannedElementKind.emptyLessonHour,
    askPlanner: true,
  ),
  meetings('meetings', PlannedElementKind.meeting),
  lessonFreeDays('lesson_free_days', PlannedElementKind.lessonFreeDay),

  /// Every type the tool does not name, also one the library does not know.
  other('other', PlannedElementKind.other);

  const PlannerKind(this.argument, this.kind, {bool askPlanner = false})
    : _askPlanner = askPlanner;

  /// The name in the `types` argument.
  final String argument;

  /// The kind of element, as the tools name and count it.
  final PlannedElementKind kind;

  final bool _askPlanner;

  String get plural => kind.plural;

  /// The type the planner is asked for, or null when the elements of this
  /// kind are kept here from every type read.
  PlannedElementType? get plannerType => _askPlanner ? kind.type : null;

  /// The kind of [element].
  static PlannerKind of(PlannedElement element) {
    final kind = PlannedElementKind.of(element);
    return values.firstWhere((value) => value.kind == kind);
  }
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
        'lesson; meeting, such as a class council; lesson-free day, such as '
        'a holiday, which can run over several days; or the planner\'s name '
        'of another type, such as planned-excursions), the name, course, '
        'classes, who planned it, the room, and the id for '
        'read_planned_element. A class planner holds the elements of '
        'everyone who teaches the class: each '
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
              'empty_lesson_hours (hours of the timetable without a lesson), '
              'meetings (such as class councils), lesson_free_days (such as '
              'holidays) and/or other (every kind not named here, such as '
              'excursions). Default: all.',
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
  // The planner filters on lessons, assignments and empty lesson hours. Any
  // other kind needs every type, and is kept here (formatPlannerList).
  final types = kinds == null || kinds.any((kind) => kind.plannerType == null)
      ? null
      : {for (final kind in kinds) kind.plannerType!};

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

  return CallToolResult(
    content: [
      TextContent(
        text: formatPlannerList(
          planner: planner,
          calendar: calendar,
          from: from,
          until: until,
          kinds: kinds,
          elements: elements,
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

/// What `list_planner` answers when nothing is planned in a planner other
/// than the user's own and no element names it ([plannerName]).
///
/// Smartschool answers a planner id that names no planner (such as
/// `group/4069_1`) as an empty planner, without an error, and the library
/// cannot name a planner by its id, so the two cannot be told apart
/// (yvanvds/dartschool#127). A workaround, whose removal is tracked in
/// #102.
const unnamedPlannerNote =
    'Note: with nothing planned, the planner cannot be named, and '
    'Smartschool answers a planner id that does not exist the same way. If '
    'you expected elements, check the planner id with search_planners.';

/// What `list_planner` answers: a header with the planner, the period and
/// the counts by kind ([PlannedElementKind]: a meeting counts as a meeting,
/// not as other), then the [elements] of [kinds] per day, at most
/// [maxPlannerLines].
///
/// [elements] are every element read, also those of other kinds than
/// [kinds] (every type is read for a kind the planner is not asked for,
/// [PlannerKind.plannerType]): any of them can name the planner
/// ([plannerName]). When nothing is planned in a planner other than the
/// user's own and none of them names it, [unnamedPlannerNote] follows.
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
  final period = formatPlannerPeriod(from, until);
  final only = kinds == null
      ? ''
      : ' (only ${[for (final kind in kinds) kind.plural].join(', ')})';
  final listed = [
    for (final element in elements)
      if (kinds == null || kinds.contains(PlannerKind.of(element))) element,
  ];
  if (listed.isEmpty) {
    return [
      'Planner: $who, $period$only: nothing planned.',
      if (!planner.isMe && name == null) unnamedPlannerNote,
    ].join('\n');
  }

  final counts = [
    for (final kind in PlannedElementKind.values)
      if (listed.where((e) => PlannedElementKind.of(e) == kind).length
          case final count when count > 0)
        kind.count(count),
  ];
  final sorted = sortedByTime(listed);
  final shown = sorted.take(maxPlannerLines).toList();
  final ownUserId = planner.isMe ? calendar.id : null;
  return [
    'Planner: $who, $period$only: ${listed.length} '
        '${listed.length == 1 ? 'element' : 'elements'} '
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
