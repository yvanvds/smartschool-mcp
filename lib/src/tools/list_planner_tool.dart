import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
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

  final (calendar, elements, lookup) = await withPlanner(session, (
    service,
  ) async {
    final calendar = await planner.resolve(service);
    final elements = await _elements(
      service,
      planner,
      calendar,
      from: from,
      until: until,
      types: types,
    );
    final lookup = needsPlannerLookup(planner, calendar, kinds, elements)
        ? await _lookUp(service, calendar)
        : null;
    return (calendar, elements, lookup);
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
          lookup: lookup,
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

/// The [elements] of [kinds] (of every kind for null): those that
/// `list_planner` lists.
List<PlannedElement> _listed(
  Set<PlannerKind>? kinds,
  List<PlannedElement> elements,
) => [
  for (final element in elements)
    if (kinds == null || kinds.contains(PlannerKind.of(element))) element,
];

/// Whether `list_planner` looks [planner] up by its id
/// ([PlannerService.getCalendar]): only when it is not the user's own,
/// nothing of [kinds] is planned in it, and no element read ([elements],
/// of every kind read) names it ([plannerName]). A listing whose elements
/// name the planner sends no lookup.
///
/// With nothing planned, the header cannot name the planner from the
/// elements, and an id that names no planner can read as a free planner:
/// the planner answers a room it does not have, and a group its search
/// does not offer, with an empty list (see [PlannerService.getCalendar]
/// and [PlannerService.getPlannedElements]).
bool needsPlannerLookup(
  PlannerRef planner,
  PlannerCalendar calendar,
  Set<PlannerKind>? kinds,
  List<PlannedElement> elements,
) =>
    !planner.isMe &&
    _listed(kinds, elements).isEmpty &&
    plannerName(calendar, elements) == null;

/// What the planner's lookup of a planner by its id
/// ([PlannerService.getCalendar]) gave: what [named] it, null when the
/// planner does not know the id; or the planner's [error] when the lookup
/// failed.
typedef PlannerLookup = ({
  PlannerSearchResult? named,
  SmartschoolPlannerError? error,
});

/// Looks [calendar] up by its id ([PlannerService.getCalendar]).
///
/// Only a [SmartschoolPlannerError] is caught, which the log gets (the
/// library's message can quote the planner's answer): the lookup only names
/// the planner. Elements that were read are listed all the same; when
/// reading them failed ([_elements]), the planner's error for them is the
/// one reported. A refused session or a lost connection still goes to
/// [SmartschoolSession.run].
Future<PlannerLookup> _lookUp(
  PlannerService service,
  PlannerCalendar calendar,
) async {
  try {
    return (named: await service.getCalendar(calendar), error: null);
  } on SmartschoolPlannerError catch (error) {
    log('planner: $error');
    return (named: null, error: error);
  }
}

/// Reads the elements of [calendar], the planner [planner] names, from
/// [from] to [until], of [types] ([PlannerService.getPlannedElements]).
///
/// The planner answers a user or class id it does not have with HTTP `500`,
/// a [SmartschoolPlannerError] that does not say why (see
/// [PlannerService.getPlannedElements]). On a `500` for a planner other
/// than the user's own, the planner is looked up by its id ([_lookUp]):
/// when the lookup does not know the id either, a [ToolError] says so
/// ([unknownPlannerError]), rather than to try again. When the lookup names
/// the planner, or fails too, the planner did fail: its error is thrown
/// on, for [withPlanner] to word.
Future<List<PlannedElement>> _elements(
  PlannerService service,
  PlannerRef planner,
  PlannerCalendar calendar, {
  required DateTime from,
  required DateTime until,
  required Set<PlannedElementType>? types,
}) async {
  try {
    return await service.getPlannedElements(
      calendar,
      from: from,
      to: until,
      types: types,
    );
  } on SmartschoolPlannerError catch (error) {
    if (planner.isMe || error.statusCode != 500) rethrow;
    if (await _lookUp(service, calendar) case (named: null, error: null)) {
      log('planner: $error');
      throw ToolError(unknownPlannerError(calendar));
    }
    rethrow;
  }
}

/// What `list_planner` answers when the planner answers the elements of a
/// planner other than the user's own with HTTP `500`, and its lookup does
/// not know the id ([PlannerService.getCalendar] returns null): the planner
/// answers a user or class id it does not have so (see
/// [PlannerService.getPlannedElements]), and trying again cannot help.
String unknownPlannerError(PlannerCalendar calendar) =>
    'The planner\'s search offers no class, person or room with the '
    'planner id ${formatPlannerId(calendar)}, and Smartschool answers such '
    'an id with an error (HTTP 500), so trying again will not help. Check '
    'the planner id with search_planners.';

/// What `list_planner` adds when nothing is planned in a planner other than
/// the user's own, no element names it, and the planner's lookup does not
/// know its id: [PlannerService.getCalendar] returns null for no such
/// person, class or room, and for a group that the planner's search does
/// not offer.
///
/// The planner answers the elements of a room it does not have, and of a
/// group its search does not offer, with an empty list (see
/// [PlannerService.getPlannedElements]), the same as a planner with nothing
/// planned.
String unknownPlannerNote(PlannerCalendar calendar) =>
    'Note: the planner\'s search offers no class, person or room with the '
    'planner id ${formatPlannerId(calendar)}, and Smartschool answers such '
    'an id as an empty planner, so this does not mean that a planner is '
    'free. Check the planner id with search_planners.';

/// What `list_planner` adds when nothing is planned in a planner other than
/// the user's own, no element names it, and the planner's lookup by its id
/// failed (the planner's error goes to the log): whether the id names a
/// planner is then not known.
const unnamedPlannerNote =
    'Note: with nothing planned, the planner cannot be named, and looking '
    'up its id failed (the details are in the server log). Smartschool '
    'answers some planner ids that name no planner as an empty planner. If '
    'you expected elements, check the planner id with search_planners.';

/// What `list_planner` answers: a header with the planner, the period and
/// the counts by kind ([PlannedElementKind]: a meeting counts as a meeting,
/// not as other), then the [elements] of [kinds] per day, at most
/// [maxPlannerLines].
///
/// [elements] are every element read, also those of other kinds than
/// [kinds] (every type is read for a kind the planner is not asked for,
/// [PlannerKind.plannerType]): any of them can name the planner
/// ([plannerName]).
///
/// [lookup] is the planner's lookup of the planner by its id, or null when
/// it was not looked up ([needsPlannerLookup]). The header then names the
/// planner as the lookup does, and marks a person the planner counts as
/// deleted ([PlannerSearchResult.isDeleted]); when the lookup does not know
/// the id, [unknownPlannerNote] follows, and when it failed,
/// [unnamedPlannerNote].
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
  PlannerLookup? lookup,
}) {
  final named = lookup?.named;
  final name =
      plannerName(calendar, elements) ??
      switch (named?.name.trim()) {
        final name? when name.isNotEmpty => name,
        _ => null,
      };
  final about = [?name, if (named?.isDeleted ?? false) 'deleted user'];
  final who = planner.isMe
      ? 'your own planner (me)'
      : 'planner ${formatPlannerId(calendar)}'
            '${about.isEmpty ? '' : ' (${about.join(', ')})'}';
  final period = formatPlannerPeriod(from, until);
  final only = kinds == null
      ? ''
      : ' (only ${[for (final kind in kinds) kind.plural].join(', ')})';
  final listed = _listed(kinds, elements);
  if (listed.isEmpty) {
    return [
      'Planner: $who, $period$only: nothing planned.',
      if (lookup case (named: null, error: null)) unknownPlannerNote(calendar),
      if (lookup?.error != null) unnamedPlannerNote,
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
