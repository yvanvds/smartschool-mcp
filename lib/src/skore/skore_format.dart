import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_search.dart';

// The output lines of the Skore tools, in the style of list_messages and
// list_intradesk_folder: a line that sums up, then one line per item with
// its parts separated by ` | `.

/// One class: name, Skore class id, group and report model.
///
/// For example `1B1 | class id 2376 | group 1B | model 1gr B-str.`.
String formatSkoreClass(SkoreClass skoreClass) => [
  skoreName(skoreClass.name),
  'class id ${skoreClass.id}',
  switch (skoreClass.groupName?.trim()) {
    final group? when group.isNotEmpty => 'group $group',
    _ => 'no group',
  },
  'model ${skoreName(skoreClass.modelName)}',
].join(' | ');

/// One row of a class's courses, indented two spaces per [SkoreCourse.depth]:
/// its label, course id, code and depth, and whether it is a group header,
/// or its teachers with their assignments.
///
/// For example `  - Project 1 (3e graad) [PROJE1] | course id 1840 | code
/// PROJE1 | depth 1 | 2 teachers: Peeters, Piet (teacher id 1002,
/// assignment 34580); Dupré, Céline (teacher id 1003, assignment 34582)`.
String formatSkoreCourse(SkoreCourse course) {
  final assignments = course.assignments;
  final teachers = assignments.length == 1
      ? 'teacher'
      : '${assignments.length} teachers';
  final parts = [
    _courseLabel(course),
    'course id ${course.id}',
    switch (course.code) {
      final code? when code.isNotEmpty => 'code $code',
      _ => 'no code',
    },
    'depth ${course.depth}',
    if (course.isGroupHeader)
      'group header, cannot get a teacher'
    else if (assignments.isEmpty)
      'no teacher'
    else
      '$teachers: ${assignments.map(formatSkoreAssignment).join('; ')}',
  ];
  return '${'  ' * course.depth}- ${parts.join(' | ')}';
}

/// Course [courseId] in a sentence: the label of [course] in quotes, then its
/// course id, such as `course "Project 1 (3e graad) [PROJE1]" (course id
/// 1840)`; only `course id 1840` when [course] is null (not read).
String formatSkoreCourseName(SkoreCourse? course, int courseId) =>
    course == null
    ? 'course id $courseId'
    : 'course "${_courseLabel(course)}" (course id $courseId)';

/// The label of [course] as the tools show it: Skore's label, else its
/// name.
String _courseLabel(SkoreCourse course) =>
    skoreName(course.label.trim().isEmpty ? course.name : course.label);

/// A teacher on a course: name, teacher id and the assignment, whose id is
/// also the gradebook's. For example `Janssens, Jan (teacher id 1001,
/// assignment 31882)`.
String formatSkoreAssignment(SkoreAssignment assignment) =>
    '${skoreName(assignment.teacherName)} (teacher id ${assignment.teacherId}, '
    'assignment ${assignment.id})';

/// The teacher of [assignment]: name and teacher id. For example `Janssens,
/// Jan (teacher id 1001)`.
String formatSkoreTeacherOf(SkoreAssignment assignment) =>
    '${skoreName(assignment.teacherName)} (teacher id ${assignment.teacherId})';

/// One teacher Skore lets assign: name and teacher id. For example
/// `Dupré, Céline | teacher id 1003`.
String formatSkoreTeacher(SkoreTeacher teacher) =>
    '${skoreName(teacher.name)} | teacher id ${teacher.id}';

/// The items of [items] in whose texts ([textsOf]) every word of [query]
/// occurs, ignoring case and accents, also as part of a longer word; all of
/// them when [query] has no words.
List<T> skoreMatches<T>(
  List<T> items,
  String? query,
  Iterable<String> Function(T item) textsOf,
) {
  final search = SearchQuery.parse(query ?? '');
  if (search == null) return items;
  return [
    for (final item in items)
      if (search.matches(textsOf(item))) item,
  ];
}

/// [name] on one line, every run of white space as one space (Skore's
/// labels hold double spaces), or `(no name)` when it is empty.
String skoreName(String name) {
  final words = name.trim().replaceAll(_whitespace, ' ');
  return words.isEmpty ? '(no name)' : words;
}

final _whitespace = RegExp(r'\s+');
