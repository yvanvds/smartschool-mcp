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
/// its label, course id, code and depth, and then its teachers with their
/// assignments, or, without any, whether it is a group header, a course
/// with sub-courses ([hasSubCourses], see [skoreHasSubCourses]), which
/// needs no teacher of its own, or a course without a teacher.
///
/// For example `  - Project 1 (3e graad) [PROJE1] | course id 1840 | code
/// PROJE1 | depth 1 | 2 teachers: Peeters, Piet (teacher id 1002,
/// assignment 34580); Dupré, Céline (teacher id 1003, assignment 34582)`.
String formatSkoreCourse(SkoreCourse course, {required bool hasSubCourses}) {
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
    else if (assignments.isNotEmpty)
      '$teachers: ${assignments.map(formatSkoreAssignment).join('; ')}'
    else if (hasSubCourses)
      'course with sub-courses, needs no teacher of its own'
    else
      'no teacher',
  ];
  return '${'  ' * course.depth}- ${parts.join(' | ')}';
}

/// Whether row [index] of [courses], the rows of a class in Skore's order,
/// is a course with sub-courses: the next row is deeper (#100). The tree
/// tells it, not the labels.
///
/// Such a course needs no teacher of its own: its sub-courses carry the
/// assignments, as a Skore administrator confirmed. A group header with
/// courses under it is one too, but it cannot get a teacher at all.
bool skoreHasSubCourses(List<SkoreCourse> courses, int index) =>
    index + 1 < courses.length &&
    courses[index + 1].depth > courses[index].depth;

/// Whether row [index] of [courses] still needs a teacher: a course, not a
/// group header, without a teacher and without sub-courses
/// ([skoreHasSubCourses]). These are the rows [formatSkoreCourse] marks
/// `no teacher`.
bool skoreNeedsTeacher(List<SkoreCourse> courses, int index) {
  final course = courses[index];
  return !course.isGroupHeader &&
      course.assignments.isEmpty &&
      !skoreHasSubCourses(courses, index);
}

/// [course] in a sentence: its label in quotes, then its course id, such as
/// `course "Project 1 (3e graad) [PROJE1]" (course id 1840)`.
String formatSkoreCourseName(SkoreCourse course) =>
    'course "${_courseLabel(course)}" (course id ${course.id})';

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

/// The names of [teachers] by teacher id, to name the teachers of a
/// gradebook with ([formatSkoreTeacherId]): its owner, readers and writers
/// are only ids (#44).
Map<int, String> skoreTeacherNames(List<SkoreTeacher> teachers) => {
  for (final teacher in teachers) teacher.id: teacher.name,
};

/// Teacher [id], named from [names] ([skoreTeacherNames]): for example
/// `Maes, Mira (teacher id 1006)`; only `teacher id 1999` for a teacher
/// Skore does not list (such as one who left the school).
String formatSkoreTeacherId(int id, Map<int, String> names) =>
    switch (names[id]) {
      final name? => '${skoreName(name)} (teacher id $id)',
      null => 'teacher id $id',
    };

/// A gradebook with the teachers it is shared with: its course, class and
/// gradebook id, its readers (who may read it) and writers (who may read and
/// change it), named from [names]. For example `Digitale vaardigheden |
/// class 5WW1 | gradebook id 34826 | readers: none | writers: Maes, Mira
/// (teacher id 1006)`.
String formatSkoreGradebook(
  SkoreGradebookShares gradebook,
  Map<int, String> names,
) {
  String teachers(List<int> ids) => ids.isEmpty
      ? 'none'
      : [for (final id in ids) formatSkoreTeacherId(id, names)].join('; ');
  return [
    skoreName(gradebook.courseName),
    'class ${skoreName(gradebook.className)}',
    'gradebook id ${gradebook.gradebookId}',
    'readers: ${teachers(gradebook.readerIds)}',
    'writers: ${teachers(gradebook.writerIds)}',
  ].join(' | ');
}

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

/// The reason in [message], the message of a
/// [SmartschoolSkoreChangeRefusedError]: without the name of the library's
/// method in front (`addTeacher: `, `createEvaluation: `) and its closing
/// `Nothing was saved.`, which the write tools say in their own words. Used
/// by the Skore tools and the gradebook tools alike.
String skoreRefusalReason(String message) {
  final reason = message
      .replaceFirst(RegExp(r'^[A-Za-z]+: '), '')
      .replaceFirst(RegExp(r'\s*Nothing was saved\.\s*$'), '')
      .trim();
  return reason.endsWith('.') ? reason : '$reason.';
}
