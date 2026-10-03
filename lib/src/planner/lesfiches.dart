import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';
import 'planner_format.dart';

// The lesfiches of Smartschool's Lesfiches module (lesson content), which
// `list_lesfiches` lists and `plan_lesfiche` plans into an empty lesson hour
// of the user's own planner: the kinds a tool lists, the lesfiche id a tool
// takes, the names of a lesfiche's courses, the order of the list, and one
// line per lesfiche. Both tools reach the module with `withPlannerClient`
// (`planner_access.dart`), which turns its errors into ToolErrors.

/// The kinds of lesfiche `list_lesfiches` lists (its `type`).
enum LesficheKind {
  /// Lesson lesfiches, the only ones `plan_lesfiche` plans.
  lessons('lessons', 'lesson lesfiche', 'lesson lesfiches'),

  /// Assignment lesfiches (a test, a task).
  assignments('assignments', 'assignment lesfiche', 'assignment lesfiches'),

  /// Every lesfiche, also of a kind the library does not know.
  all('all', 'lesfiche', 'lesfiches');

  const LesficheKind(this.argument, this.singular, this.plural);

  /// The name in the `type` argument.
  final String argument;

  final String singular;
  final String plural;

  /// The kind the `type` argument [value] names; [lessons] when it is
  /// absent. The input schema allows only the names of the kinds.
  static LesficheKind parse(Object? value) => values.firstWhere(
    (kind) => kind.argument == value,
    orElse: () => lessons,
  );

  /// Whether [item] is of this kind.
  bool includes(LessonContentItem item) => switch (this) {
    lessons => item.type == LessonContentType.lesson,
    assignments => item.type == LessonContentType.assignment,
    all => true,
  };

  /// `1 lesson lesfiche`, `2 lesson lesfiches`.
  String count(int count) => '$count ${count == 1 ? singular : plural}';
}

final _lesficheId = RegExp(r'^[0-9A-Za-z][0-9A-Za-z_-]*$');

/// [value], the argument [name] of a tool, as the id of a lesfiche as
/// `list_lesfiches` prints it (a UUID, like
/// `b0000000-0000-4000-8000-000000000001`). A leading `id `, as the tool
/// prints it, is allowed.
///
/// Throws a [ToolError] naming the expected form for anything else (such as
/// the id of a planner element, or a lesfiche's name), so that it never
/// goes into a request. Whether the user has a lesfiche with that id, and
/// whether it is a lesson, the library checks before it plans one.
String lesficheArgument(Object? value, {String name = 'lesfiche'}) {
  var text = value is String ? value.trim() : '';
  if (text.toLowerCase().startsWith('id ')) text = text.substring(3).trim();
  if (_lesficheId.hasMatch(text)) return text;
  throw ToolError(
    '$name must be the id of a lesfiche as list_lesfiches shows it, like '
    'b0000000-0000-4000-8000-000000000001; '
    '${value is String ? '"$value"' : '$value'} is not. Nothing was sent.',
  );
}

/// How many days around today `list_lesfiches` reads the user's own planner
/// for the names of the courses ([ownCourseNames]): 4 weeks before and
/// after.
const lesficheCourseDays = 28;

/// The period [ownCourseNames] reads around [now]: from the start of the day
/// [lesficheCourseDays] days before it to the end of the day
/// [lesficheCourseDays] days after it.
({DateTime from, DateTime until}) lesficheCoursePeriod(DateTime now) => (
  from: DateTime(now.year, now.month, now.day - lesficheCourseDays),
  until: DateTime(
    now.year,
    now.month,
    now.day + lesficheCourseDays,
    23,
    59,
    59,
  ),
);

/// The names of the user's courses by course id (in lower case), from the
/// elements of the user's own planner in [lesficheCoursePeriod] around
/// [now]: the courses of the lesson hours, lessons and assignments there.
///
/// The Lesfiches module names the courses of a lesfiche by id only
/// ([LessonContentCourse]), the same id as a planner element's
/// [PlannerCourse] (yvanvds/dartschool#101). A workaround until the library
/// names them; its removal is #87. A course without an element in the
/// period is not in the map.
Future<Map<String, String>> ownCourseNames(
  PlannerService planner, {
  required DateTime now,
}) async {
  final (:from, :until) = lesficheCoursePeriod(now);
  final elements = await planner.getPlannedElements(
    await planner.ownCalendar(),
    from: from,
    to: until,
  );
  return {
    for (final element in elements)
      for (final course in element.courses)
        if (course.name.trim() case final name when name.isNotEmpty)
          course.id.toLowerCase(): name,
  };
}

/// [text] for comparing labels: in lower case, with every run of white space
/// as one space, without white space around it.
String normalLabel(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Whether [item] has every label of [labels] (texts as [normalLabel] gives
/// them), and its name holds every word of [words] (in lower case).
bool lesficheMatches(
  LessonContentItem item, {
  required Set<String> labels,
  required List<String> words,
}) {
  final own = {for (final label in item.labels) normalLabel(label.text)};
  if (!labels.every(own.contains)) return false;
  final name = item.name.toLowerCase();
  return words.every(name.contains);
}

final _parts = RegExp(r'\d+|\D+');

/// Compares the names [a] and [b] as a person sorts them: ignoring case,
/// and with the numbers in them by their value, so that `Les 2` comes
/// before `Les 10`.
int compareLesficheNames(String a, String b) {
  final left = [for (final m in _parts.allMatches(a.toLowerCase())) m[0]!];
  final right = [for (final m in _parts.allMatches(b.toLowerCase())) m[0]!];
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final numbers = _isDigit(x) && _isDigit(y);
    final order = numbers ? _compareNumbers(x, y) : x.compareTo(y);
    if (order != 0) return order;
  }
  final byLength = left.length.compareTo(right.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

final _digits = RegExp(r'^\d');

/// Whether [part], a part of a name as [_parts] splits it, is a number.
bool _isDigit(String part) => _digits.hasMatch(part);

/// Compares two runs of digits by their value, however long they are.
int _compareNumbers(String x, String y) {
  final a = x.replaceFirst(RegExp('^0+(?=.)'), '');
  final b = y.replaceFirst(RegExp('^0+(?=.)'), '');
  final byLength = a.length.compareTo(b.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

/// [items] by name ([compareLesficheNames]), then by id.
List<LessonContentItem> sortedByName(Iterable<LessonContentItem> items) =>
    items.toList()..sort((a, b) {
      final byName = compareLesficheNames(a.name, b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });

/// What [item] is: `lesson`, `assignment KT Kleine Taak` (with its type), or
/// the module's name of any other kind.
String formatLesficheKind(LessonContentItem item) => switch (item.type) {
  LessonContentType.lesson => 'lesson',
  LessonContentType.assignment => [
    'assignment',
    if (item.assignmentType case final type?) formatAssignmentType(type),
  ].where((part) => part.isNotEmpty).join(' '),
  LessonContentType.other => item.typeName,
};

/// What a lesfiche line says of a course that [ownCourseNames] did not
/// name.
const unnamedCourse = 'course not in your planner';

/// The courses of [item], named with [courseNames] ([ownCourseNames]):
/// `informatica`, `informatica, 1 course not in your planner`, or `no
/// course`. Without [courseNames] (they could not be read), only how many:
/// `2 courses`.
String formatLesficheCourses(
  LessonContentItem item,
  Map<String, String>? courseNames,
) {
  final courses = item.courses;
  if (courses.isEmpty) return 'no course';
  if (courseNames == null) {
    return '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}';
  }
  final names = <String>[];
  var unnamed = 0;
  for (final course in courses) {
    final name = courseNames[course.id.toLowerCase()];
    if (name == null) {
      unnamed++;
    } else if (!names.contains(name)) {
      names.add(name);
    }
  }
  return [
    ...names,
    if (unnamed == 1) '1 $unnamedCourse',
    if (unnamed > 1) '$unnamed courses not in your planner',
  ].join(', ');
}

/// One line describing [item]: kind, name, labels, courses
/// ([formatLesficheCourses]), visible or hidden in the module, the day it
/// was last changed, and its id.
///
/// For example `lesson | Herhaling: lussen | labels JAAR 6, TRIMESTER 1 |
/// informatica | hidden | changed 2026-09-07 | id b0000000-…`. The day is
/// as the module gives it: its dates have no offset, so they are Smartschool
/// time, read as the time of this PC.
String formatLesficheLine(
  LessonContentItem item,
  Map<String, String>? courseNames,
) {
  final labels = [
    for (final label in item.labels)
      if (label.text.trim() case final text when text.isNotEmpty) text,
  ];
  return [
    formatLesficheKind(item),
    if (item.name.isEmpty) '(no name)' else item.name,
    if (labels.isEmpty) 'no labels' else 'labels ${labels.join(', ')}',
    formatLesficheCourses(item, courseNames),
    if (item.isVisible) 'visible' else 'hidden',
    if (item.dateLastChanged case final changed?)
      'changed ${formatPlannerDate(changed)}',
    'id ${item.id}',
  ].join(' | ');
}
