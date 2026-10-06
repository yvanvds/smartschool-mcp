import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';
import 'planner_format.dart';

// The lesfiches of Smartschool's Lesfiches module (lesson content), which
// `list_lesfiches` lists and `plan_lesfiche` plans into an empty lesson hour
// of the user's own planner: the kinds a tool lists, the lesfiche id a tool
// takes, the names of a lesfiche's courses, the order of the list, and one
// line per lesfiche. Both tools reach the module with `withPlannerClient`
// (`planner_access.dart`), which turns its errors into ToolErrors. One
// lesfiche in full, with its weblinks and attachments, is in
// `lesfiche_detail.dart`.

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

/// The courses of [item], by the names the library gave them
/// ([LessonContentCourse.name], from the school's course list):
/// `informatica`, `informatica, chemie`, `informatica, 1 unnamed course`
/// (a course the course list does not name), or `no course`. A name is
/// given once, also for two courses of that name. Without
/// [withCourseNames] (the names could not be read), only how many: `2
/// courses`.
String formatLesficheCourses(
  LessonContentItem item, {
  bool withCourseNames = true,
}) {
  final courses = item.courses;
  if (courses.isEmpty) return 'no course';
  if (!withCourseNames) {
    return '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}';
  }
  final names = <String>[];
  var unnamed = 0;
  for (final course in courses) {
    final name = course.name;
    if (name == null) {
      unnamed++;
    } else if (!names.contains(name)) {
      names.add(name);
    }
  }
  return [
    ...names,
    if (unnamed == 1) '1 unnamed course',
    if (unnamed > 1) '$unnamed unnamed courses',
  ].join(', ');
}

/// The note when the school's course list could not be read ([error]), so
/// that only the number of a lesfiche's courses is shown
/// ([formatLesficheCourses] without its names).
String lesficheCourseListNote(SmartschoolLessonContentError error) =>
    'Note: the names of the courses could not be read from the school\'s '
    'course list'
    '${error.statusCode == null ? '' : ' (HTTP ${error.statusCode})'}, so '
    'only the number of courses is shown.';

/// The note under lesfiches with a course that the school's course list
/// does not name ([formatLesficheCourses]).
const unnamedLesficheCourseNote =
    'A course that the school\'s course list does not name shows as '
    '"unnamed course".';

/// One line describing [item]: kind, name, labels, courses
/// ([formatLesficheCourses], by name unless not [withCourseNames]), visible
/// or hidden in the module, the day it was last changed, and its id.
///
/// For example `lesson | Herhaling: lussen | labels JAAR 6, TRIMESTER 1 |
/// informatica | hidden | changed 2026-09-07 | id b0000000-…`. The day is
/// as the module gives it: its dates have no offset, so they are Smartschool
/// time, read as the time of this PC.
String formatLesficheLine(
  LessonContentItem item, {
  bool withCourseNames = true,
}) {
  final labels = [
    for (final label in item.labels)
      if (label.text.trim() case final text when text.isNotEmpty) text,
  ];
  return [
    formatLesficheKind(item),
    if (item.name.isEmpty) '(no name)' else item.name,
    if (labels.isEmpty) 'no labels' else 'labels ${labels.join(', ')}',
    formatLesficheCourses(item, withCourseNames: withCourseNames),
    if (item.isVisible) 'visible' else 'hidden',
    if (item.dateLastChanged case final changed?)
      'changed ${formatPlannerDate(changed)}',
    'id ${item.id}',
  ].join(' | ');
}
