import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/html_to_text.dart';
import 'planner_access.dart';

// How the planner tools write the planner: dates and times in the time of
// this PC (Belgium), one line per element, the days of a period, and the
// detail of one element.

/// Info text longer than this is cut off, with a note.
const maxPlannerInfoLength = 20000;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// [time] as `2026-10-05`, in the time of this PC.
String formatPlannerDate(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// [time] as `10:20`, in the time of this PC.
String formatPlannerClock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// [time] as `2026-10-05 10:20`, in the time of this PC.
String formatPlannerTime(DateTime time) =>
    '${formatPlannerDate(time)} ${formatPlannerClock(time)}';

/// The day of [time] as `Monday 2026-10-05`, in the time of this PC.
String formatPlannerDay(DateTime time) =>
    '${_weekdays[time.toLocal().weekday - 1]} ${formatPlannerDate(time)}';

/// The day [time] falls on in the time of this PC, at midnight.
DateTime plannerDayOf(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// The period from [from] to [until] as a tool names it: `from Monday
/// 2026-10-05 to Friday 2026-10-09`, with the time of an end that is not the
/// start ([from]) or the end ([until]) of its day: `from Monday 2026-10-05
/// 08:00 to Monday 2026-10-05 12:00`.
String formatPlannerPeriod(DateTime from, DateTime until) =>
    'from ${_moment(from, end: false)} to ${_moment(until, end: true)}';

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

/// [elements] in time order: by start, then end, then name and id, so that
/// the order does not depend on the planner's.
List<PlannedElement> sortedByTime(Iterable<PlannedElement> elements) =>
    elements.toList()..sort((a, b) {
      final byStart = a.period.from.compareTo(b.period.from);
      if (byStart != 0) return byStart;
      final byEnd = a.period.to.compareTo(b.period.to);
      if (byEnd != 0) return byEnd;
      final byName = (a.name ?? '').compareTo(b.name ?? '');
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });

/// [elements] per day they start on ([plannerDayOf]), the days in date
/// order and the elements of a day in time order ([sortedByTime]). Days
/// without elements are not in the map.
Map<DateTime, List<PlannedElement>> elementsByDay(
  Iterable<PlannedElement> elements,
) {
  final days = <DateTime, List<PlannedElement>>{};
  for (final element in sortedByTime(elements)) {
    days.putIfAbsent(plannerDayOf(element.period.from), () => []).add(element);
  }
  return days;
}

/// When [element] takes place, on the day it starts: `10:20–11:10`,
/// `08:30 (deadline)` for an assignment, `whole day`; with the date it ends
/// when that is another day.
String formatElementTime(PlannedElement element) {
  final PlannerPeriod(:from, :to, :wholeDay, :deadline) = element.period;
  if (deadline) return '${formatPlannerClock(from)} (deadline)';
  if (wholeDay) {
    // A whole day can end at midnight of the next day.
    final last = to.isAfter(from)
        ? to.subtract(const Duration(seconds: 1))
        : to;
    return plannerDayOf(last) == plannerDayOf(from)
        ? 'whole day'
        : 'whole day until ${formatPlannerDate(last)}';
  }
  return plannerDayOf(from) == plannerDayOf(to)
      ? '${formatPlannerClock(from)}–${formatPlannerClock(to)}'
      : '${formatPlannerClock(from)} until ${formatPlannerTime(to)}';
}

/// What a planned element is, as the planner tools name it and count it:
/// the kinds they name, and [other] for every other type, also one the
/// library does not know.
enum PlannedElementKind {
  lesson('lesson', 'lessons', PlannedElementType.lesson),
  assignment('assignment', 'assignments', PlannedElementType.assignment),
  emptyLessonHour(
    'empty lesson hour',
    'empty lesson hours',
    PlannedElementType.placeholder,
  ),

  /// A meeting, such as a class council (`planned-meetings`, seen live in
  /// #71).
  meeting('meeting', 'meetings', PlannedElementType.meeting),

  /// A lesson-free day, such as a holiday (`planned-lesson-free-days`, seen
  /// live in #71). One element can run over several days: the autumn
  /// holiday was one element of a week.
  lessonFreeDay(
    'lesson-free day',
    'lesson-free days',
    PlannedElementType.lessonFreeDay,
  ),

  /// Every other type. A line names it by the planner's name for it
  /// ([formatElementKind]).
  other('other', 'other', null);

  const PlannedElementKind(this.singular, this.plural, this.type);

  final String singular;
  final String plural;

  /// The element type, or null for [other].
  final PlannedElementType? type;

  /// The kind of [element].
  static PlannedElementKind of(PlannedElement element) => values.firstWhere(
    (kind) => kind.type == element.type,
    orElse: () => other,
  );

  /// `1 meeting`, `2 meetings`.
  String count(int count) => '$count ${count == 1 ? singular : plural}';
}

/// What [element] is: `lesson`, `assignment KO Kleine Overhoring` (with its
/// type), `empty lesson hour`, `meeting`, `lesson-free day`, or the
/// planner's name of any other type (`planned-school-activities`).
String formatElementKind(PlannedElement element) =>
    switch (PlannedElementKind.of(element)) {
      PlannedElementKind.assignment => [
        'assignment',
        if (element.assignmentType case final type?) formatAssignmentType(type),
      ].where((part) => part.isNotEmpty).join(' '),
      PlannedElementKind.other => element.typeName,
      final kind => kind.singular,
    };

/// [type], an assignment type, as the planner shows it: its abbreviation and
/// name, `KO Kleine Overhoring`, or the one it has.
String formatAssignmentType(PlannerAssignmentType type) => [
  if (type.abbreviation.isNotEmpty) type.abbreviation,
  if (type.name.isNotEmpty) type.name,
].join(' ');

/// The name of [element], or null when it has none (an empty lesson hour).
String? elementName(PlannedElement element) {
  final name = element.name?.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// The names of [items] that are not empty, joined with `, `.
String _names<T>(Iterable<T> items, String Function(T item) name) => [
  for (final item in items)
    if (name(item).trim() case final text when text.isNotEmpty) text,
].join(', ');

/// The courses of [element], joined: `wiskunde`.
String elementCourses(PlannedElement element) =>
    _names(element.courses, (course) => course.name);

/// The classes (and other groups) of [element], joined: `6A1, 6A2`.
String elementClasses(PlannedElement element) =>
    _names(element.participantGroups, (group) => group.name);

/// The people who organise [element], joined: `Piet Peeters`.
String elementOrganisers(PlannedElement element) =>
    _names(element.organiserUsers, (user) => user.name);

/// The rooms of [element]: `room 101`, `rooms 101, 102`, or null for none.
String? elementRooms(PlannedElement element) {
  final rooms = _names(element.locations, (location) => location.title);
  if (rooms.isEmpty) return null;
  return '${element.locations.length == 1 ? 'room' : 'rooms'} $rooms';
}

/// One line describing [element]: time, kind, name, course, classes, by
/// whom (the organisers, leaving out [ownUserId]), rooms and id.
///
/// For example `10:20–11:10 | lesson | Erfelijkheid | biologie | 6A1, 6A2 |
/// by Wim Willems | room 103 | id planned-lessons/4069/e0000000-…`. An empty
/// lesson hour has no name.
String formatElementLine(PlannedElement element, {String? ownUserId}) {
  final organisers = _names(
    element.organiserUsers.where((user) => user.id != ownUserId),
    (user) => user.name,
  );
  return [
    formatElementTime(element),
    formatElementKind(element),
    ?elementName(element),
    if (elementCourses(element) case final courses when courses.isNotEmpty)
      courses,
    if (elementClasses(element) case final classes when classes.isNotEmpty)
      classes,
    if (organisers.isNotEmpty) 'by $organisers',
    ?elementRooms(element),
    'id ${PlannedElementRef.of(element)}',
  ].join(' | ');
}

/// [element] in a few words, for the result of a write: its kind and name,
/// its day and time, and its classes and course, like `lesson "Lussen" on
/// Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica)` or `empty lesson
/// hour on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica)`.
String formatElementSummary(PlannedElement element) {
  final about = [
    elementClasses(element),
    elementCourses(element),
  ].where((part) => part.isNotEmpty).join(', ');
  return [
    formatElementKind(element),
    if (elementName(element) case final name?) '"$name"',
    'on ${formatPlannerDay(element.period.from)} ${formatElementTime(element)}',
    if (about.isNotEmpty) '($about)',
  ].join(' ');
}

/// The name of [calendar] as the elements of it tell it: the class, the
/// person or the room the elements name with that calendar's id; null when
/// none does.
String? plannerName(
  PlannerCalendar calendar,
  Iterable<PlannedElement> elements,
) {
  for (final element in elements) {
    final name = switch (calendar.type) {
      PlannerCalendarType.group => [
        ...element.participantGroups,
        ...element.organiserGroups,
      ].where((group) => group.id == calendar.id).firstOrNull?.name,
      PlannerCalendarType.user => [
        ...element.organiserUsers,
        ...element.participantUsers,
      ].where((user) => user.id == calendar.id).firstOrNull?.name,
      PlannerCalendarType.location =>
        element.locations
            .where((location) => location.calendar == calendar)
            .firstOrNull
            ?.title,
    };
    if (name != null && name.trim().isNotEmpty) return name.trim();
  }
  return null;
}

/// [html], an info text of the planner, as plain text, like a message
/// body; cut off at [maxPlannerInfoLength] characters with a note.
String plannerInfoText(String html) {
  final text = htmlToText(html).trim();
  if (text.length <= maxPlannerInfoLength) return text;
  return '${text.substring(0, maxPlannerInfoLength).trimRight()}\n'
      '[Cut off: showing the first $maxPlannerInfoLength of ${text.length} '
      'characters.]';
}

/// [detail] as text: what its list line says, one field per line, then its
/// labels, attachments and weblinks, and its public and private info as
/// plain text.
String formatElementDetail(PlannedElementDetail detail) {
  final placeholder = detail.type == PlannedElementType.placeholder;
  final assignment = detail.type == PlannedElementType.assignment;
  final organisers = elementOrganisers(detail);
  final people = _names(detail.participantUsers, (user) => user.name);
  final labels = _names(
    detail.labels ?? const <PlannerLabel>[],
    (label) => label.text,
  );
  final attachments = _names(
    detail.attachments ?? const <PlannerAttachment>[],
    (attachment) => attachment.name,
  );
  final weblinks = _names(
    detail.weblinks ?? const <PlannerWeblink>[],
    _weblink,
  );
  String info(String html) {
    final text = plannerInfoText(html);
    return text.isEmpty ? '(none)' : text;
  }

  return [
    'Planner element ${PlannedElementRef.of(detail)}',
    'Kind: ${formatElementKind(detail)}',
    if (!placeholder) 'Name: ${elementName(detail) ?? '(no name)'}',
    'When: ${formatPlannerDay(detail.period.from)} '
        '${formatElementTime(detail)}',
    if (elementCourses(detail) case final courses when courses.isNotEmpty)
      'Course: $courses',
    if (elementClasses(detail) case final classes when classes.isNotEmpty)
      'Classes: $classes',
    if (people.isNotEmpty) 'People: $people',
    if (organisers.isNotEmpty) 'Organised by: $organisers',
    if (_names(detail.locations, (location) => location.title) case final rooms
        when rooms.isNotEmpty)
      '${detail.locations.length == 1 ? 'Room' : 'Rooms'}: $rooms',
    if (assignment) ...[
      if (detail.visibleFrom case final visible?)
        'Visible to pupils from: ${formatPlannerTime(visible)}',
      if (detail.isAnnounced case final announced?)
        'Announced: ${announced ? 'yes' : 'no'}',
      if (detail.resolvedStatus case final status?) 'Status: $status',
    ],
    if (labels.isNotEmpty) 'Labels: $labels',
    if (attachments.isNotEmpty) 'Attachments: $attachments',
    if (weblinks.isNotEmpty) 'Weblinks: $weblinks',
    if (!placeholder) ...[
      '',
      'Public info (what pupils see):',
      info(detail.publicInfo),
      '',
      'Private info (hidden from pupils, but colleagues who can read this '
          'element see it too):',
      info(detail.privateInfo),
    ],
  ].join('\n');
}

/// [weblink] as `name (url)`, or the one of the two it has; empty when it
/// has neither.
String _weblink(PlannerWeblink weblink) {
  final name = weblink.name.trim();
  final url = weblink.url.trim();
  if (name.isEmpty || url.isEmpty) return '$name$url';
  return '$name ($url)';
}
