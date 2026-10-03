/// The lesfiche helpers of `list_lesfiches` and `plan_lesfiche`
/// (`lib/src/planner/lesfiches.dart`, #54): the kinds, the lesfiche id
/// argument, the filters, the order of the names, and one line per lesfiche
/// with its courses as the library names them (#87).
library;

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/planner/lesfiches.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

const _id = 'b0000000-0000-4000-8000-000000000001';

LessonContentItem _item({
  LessonContentType type = LessonContentType.lesson,
  String? typeName,
  String name = 'Herhaling: lussen',
  bool isVisible = true,
  DateTime? changed,
  List<LessonContentCourse> courses = const [],
  List<String> labels = const [],
  PlannerAssignmentType? assignmentType,
}) => LessonContentItem(
  id: _id,
  platformId: 4069,
  type: type,
  typeName: typeName ?? type.wireName ?? 'other',
  name: name,
  isVisible: isVisible,
  dateLastChanged: changed,
  courses: courses,
  labels: [
    for (final (index, text) in labels.indexed)
      LessonContentLabel(id: '4069_$index', text: text),
  ],
  assignmentType: assignmentType,
);

/// A course of a lesfiche, as the library names it from the school's course
/// list: [name] is null for a course the list does not name.
LessonContentCourse _course(String id, [String? name]) =>
    LessonContentCourse(id: id, platformId: 4069, name: name);

Matcher _toolError(Object? message) =>
    isA<ToolError>().having((e) => e.message, 'message', message);

void main() {
  group('LesficheKind', () {
    test('is lessons unless the argument names another kind', () {
      expect(LesficheKind.parse(null), LesficheKind.lessons);
      expect(LesficheKind.parse('assignments'), LesficheKind.assignments);
      expect(LesficheKind.parse('all'), LesficheKind.all);
    });

    test('keeps lessons, assignments, or every kind', () {
      final lesson = _item();
      final assignment = _item(type: LessonContentType.assignment);
      final other = _item(type: LessonContentType.other, typeName: 'events');
      expect([lesson, assignment, other].where(LesficheKind.lessons.includes), [
        lesson,
      ]);
      expect(
        [lesson, assignment, other].where(LesficheKind.assignments.includes),
        [assignment],
      );
      expect(
        [lesson, assignment, other].where(LesficheKind.all.includes),
        hasLength(3),
      );
      expect(LesficheKind.lessons.count(1), '1 lesson lesfiche');
      expect(LesficheKind.all.count(2), '2 lesfiches');
    });
  });

  group('lesficheArgument', () {
    test('takes the id list_lesfiches prints, also after "id "', () {
      expect(lesficheArgument(_id), _id);
      expect(lesficheArgument(' id $_id '), _id);
    });

    test('refuses anything else with a ToolError naming the form', () {
      for (final value in [
        null,
        '',
        '  ',
        'Herhaling: lussen',
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000002',
        42,
      ]) {
        expect(
          () => lesficheArgument(value),
          throwsA(
            _toolError(
              allOf(
                startsWith(
                  'lesfiche must be the id of a lesfiche as list_lesfiches '
                  'shows it, like b0000000-0000-4000-8000-000000000001; ',
                ),
                endsWith('is not. Nothing was sent.'),
              ),
            ),
          ),
          reason: '$value',
        );
      }
    });
  });

  group('lesficheMatches', () {
    final item = _item(
      name: 'Herhaling: Lussen',
      labels: ['JAAR 6', 'TRIMESTER 1'],
    );

    test('needs every label, whole, compared as normalLabel does', () {
      expect(normalLabel('  Trimester \t 1 '), 'trimester 1');
      bool matches(List<String> labels) => lesficheMatches(
        item,
        labels: {for (final label in labels) normalLabel(label)},
        words: const [],
      );
      expect(matches([]), isTrue);
      expect(matches(['jaar 6']), isTrue);
      expect(matches(['JAAR 6', 'trimester  1']), isTrue);
      expect(matches(['JAAR 6', 'TRIMESTER 2']), isFalse);
      expect(matches(['JAAR']), isFalse);
    });

    test('needs every word in the name, in any order', () {
      bool matches(List<String> words) =>
          lesficheMatches(item, labels: const {}, words: words);
      expect(matches(['lus', 'herh']), isTrue);
      expect(matches(['lussen', 'functies']), isFalse);
    });
  });

  test('compareLesficheNames sorts as a person does: numbers by value, '
      'case ignored', () {
    final names = [
      'Les 10: lijsten',
      'les 2: variabelen',
      'Les 1: eerste programma',
      'Les 01b',
      'Les 2',
      'Herhaling',
      'Les 12345678901234567890',
      'Les 9',
    ]..sort(compareLesficheNames);
    expect(names, [
      'Herhaling',
      'Les 1: eerste programma',
      'Les 01b',
      'Les 2',
      'les 2: variabelen',
      'Les 9',
      'Les 10: lijsten',
      'Les 12345678901234567890',
    ]);
    expect(compareLesficheNames('Les', 'Les'), 0);
    expect(compareLesficheNames('Les 1', 'Les 01'), isNot(0));
  });

  group('formatLesficheLine', () {
    test('gives the kind, name, labels, courses, visibility, last change and '
        'id', () {
      expect(
        formatLesficheLine(
          _item(
            isVisible: false,
            changed: DateTime(2026, 9, 7, 19, 51, 25),
            courses: [
              _course('c0000000-0000-4000-8000-000000000005', 'informatica'),
            ],
            labels: ['JAAR 6', ' ', 'TRIMESTER 1'],
          ),
        ),
        'lesson | Herhaling: lussen | labels JAAR 6, TRIMESTER 1 | '
        'informatica | hidden | changed 2026-09-07 | id $_id',
      );
    });

    test('names an assignment with its type, and any other kind as the '
        'module does', () {
      expect(
        formatLesficheLine(
          _item(
            type: LessonContentType.assignment,
            assignmentType: const PlannerAssignmentType(
              id: 'a0000000-0000-4000-8000-000000000004',
              name: 'Kleine Taak',
              abbreviation: 'KT',
            ),
          ),
        ),
        startsWith('assignment KT Kleine Taak | Herhaling: lussen |'),
      );
      expect(
        formatLesficheLine(_item(type: LessonContentType.assignment)),
        startsWith('assignment | '),
      );
      expect(
        formatLesficheLine(
          _item(type: LessonContentType.other, typeName: 'events', name: ''),
        ),
        'events | (no name) | no labels | no course | visible | id $_id',
      );
    });

    test('names the courses as the library does, once each name, and '
        'counts those it does not name', () {
      const informatica = 'c0000000-0000-4000-8000-000000000005';
      const chemie = 'c0000000-0000-4000-8000-000000000006';
      const wiskunde = 'c0000000-0000-4000-8000-000000000001';
      expect(
        formatLesficheCourses(
          _item(
            courses: [
              _course(informatica, 'informatica'),
              _course(chemie, 'chemie'),
            ],
          ),
        ),
        'informatica, chemie',
      );
      final item = _item(
        courses: [
          _course(informatica, 'informatica'),
          _course(chemie),
          _course(wiskunde),
        ],
      );
      expect(formatLesficheCourses(item), 'informatica, 2 unnamed courses');
      expect(
        formatLesficheCourses(
          _item(
            courses: [
              _course(informatica, 'informatica'),
              _course(chemie, 'informatica'),
              _course(wiskunde),
            ],
          ),
        ),
        'informatica, 1 unnamed course',
      );
      expect(formatLesficheCourses(item, withCourseNames: false), '3 courses');
      expect(
        formatLesficheCourses(
          _item(courses: [_course(chemie, 'chemie')]),
          withCourseNames: false,
        ),
        '1 course',
      );
      expect(formatLesficheCourses(_item()), 'no course');
      expect(
        formatLesficheCourses(_item(), withCourseNames: false),
        'no course',
      );
    });
  });
}
