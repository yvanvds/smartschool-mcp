/// The planner helpers the planner tools share (`lib/src/planner/`): the
/// element and planner ids, the period arguments, the planner's errors as
/// tool errors, and how elements are written.
library;

import 'dart:async';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/planner/planner_access.dart';
import 'package:smartschool_mcp/src/planner/planner_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

const _uuid = 'e0000000-0000-4000-8000-000000000002';

Matcher _toolError(Object? message) =>
    isA<ToolError>().having((e) => e.message, 'message', message);

PlannedElement _element({
  String type = 'planned-lessons',
  String? name = 'Les',
  required DateTime from,
  required DateTime to,
  bool wholeDay = false,
  bool deadline = false,
  List<PlannerUser> organisers = const [],
  PlannerAssignmentType? assignmentType,
}) => PlannedElement(
  id: _uuid,
  platformId: 4069,
  type: PlannedElementType.fromWire(type),
  typeName: type,
  name: name,
  period: PlannerPeriod(
    from: from,
    to: to,
    wholeDay: wholeDay,
    deadline: deadline,
  ),
  organiserUsers: organisers,
  assignmentType: assignmentType,
);

/// A planner that only reads the school's assignment types, each time with
/// the next of [answers]: types, or an error to throw.
class _TypesPlanner implements PlannerService {
  _TypesPlanner(this.answers);

  final List<Object> answers;
  int reads = 0;

  /// Completed by the test to let the pending read finish.
  final gate = Completer<void>();

  @override
  Future<List<PlannerAssignmentType>> getAssignmentTypes() async {
    final answer = answers[reads++];
    await gate.future;
    if (answer is List<PlannerAssignmentType>) return answer;
    throw answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PlannedElementRef', () {
    test('parses the id list_planner prints, also after "id "', () {
      for (final value in [
        'planned-lessons/4069/$_uuid',
        ' id planned-lessons/4069/$_uuid ',
      ]) {
        final ref = PlannedElementRef.parse(value);
        expect(ref.typeName, 'planned-lessons');
        expect(ref.platformId, 4069);
        expect(ref.id, _uuid);
        expect(ref.type, PlannedElementType.lesson);
        expect('$ref', 'planned-lessons/4069/$_uuid');
      }
    });

    test('keeps a type the library does not know', () {
      final ref = PlannedElementRef.parse('planned-excursions/4069/$_uuid');
      expect(ref.type, PlannedElementType.other);
      expect(ref.typeName, 'planned-excursions');
    });

    test('is the id of an element', () {
      final element = _element(
        type: 'planned-placeholders',
        from: DateTime(2026, 10, 5, 10),
        to: DateTime(2026, 10, 5, 11),
      );
      expect(
        '${PlannedElementRef.of(element)}',
        'planned-placeholders/4069/$_uuid',
      );
      expect(
        PlannedElementRef.of(element),
        PlannedElementRef.parse(
          'planned-placeholders/4069/${_uuid.toUpperCase()}',
        ),
      );
    });

    test('refuses anything else with a ToolError naming the form', () {
      for (final value in [
        null,
        42,
        '',
        _uuid,
        'planned-lessons/$_uuid',
        'planned-lessons/4069/$_uuid/rename',
        'Planned-Lessons/4069/$_uuid',
        'lessons/4069/$_uuid',
        'planned-lessons/x4069/$_uuid',
        'planned-lessons/4069/',
        'planned-lessons/4069/a?b',
        'planned-lessons/4069/../x',
      ]) {
        expect(
          () => PlannedElementRef.parse(value, name: 'hour'),
          throwsA(
            _toolError(
              allOf(
                startsWith(
                  'hour must be the id of a planner element as list_planner '
                  'shows it',
                ),
                endsWith('${value is String ? '"$value"' : '$value'} is not.'),
              ),
            ),
          ),
          reason: '$value',
        );
      }
    });
  });

  group('PlannerRef', () {
    test('is me when absent, empty or "me" in any case', () {
      for (final value in [null, '', '  ', 'me', ' Me ']) {
        final ref = PlannerRef.parse(value);
        expect(ref.isMe, isTrue, reason: '$value');
        expect('$ref', 'me');
      }
    });

    test('takes the planner ids search_planners prints', () {
      for (final (value, type, id) in [
        ('user/4069_218_0', PlannerCalendarType.user, '4069_218_0'),
        ('group/4069_4256', PlannerCalendarType.group, '4069_4256'),
        ('location/4069_$_uuid', PlannerCalendarType.location, '4069_$_uuid'),
        ('GROUP/4069_4256', PlannerCalendarType.group, '4069_4256'),
      ]) {
        final ref = PlannerRef.parse(value);
        expect(ref.isMe, isFalse);
        expect(ref.calendar, PlannerCalendar(type, id), reason: value);
        expect('$ref', '${type.wireName}/$id');
        expect(formatPlannerId(ref.calendar!), '${type.wireName}/$id');
      }
    });

    test('refuses anything else with a ToolError naming the forms', () {
      for (final value in [
        '6WEWI1',
        'class/4069_4256',
        'group/4256',
        'user/4069_218',
        'location/$_uuid',
        'group/',
        7,
      ]) {
        expect(
          () => PlannerRef.parse(value, name: 'classes'),
          throwsA(
            _toolError(
              'classes must be me (your own planner) or a planner id as '
              'search_planners shows it, like user/4069_218_0 (a person), '
              'group/4069_4256 (a class) or location/4069_<id> (a room); '
              '${value is String ? '"$value"' : '$value'} is not.',
            ),
          ),
        );
      }
    });
  });

  group('classPlannersArgument', () {
    List<PlannerCalendar> classes(Object? value) =>
        classPlannersArgument(value, name: 'classes', max: 3);

    test('takes class planner ids, once each, in the order given', () {
      expect(
        classes(['group/4069_4256', ' GROUP/4069_4258 ', 'group/4069_4256']),
        [
          PlannerCalendar.group('4069_4256'),
          PlannerCalendar.group('4069_4258'),
        ],
      );
      expect(classes('group/4069_4256'), [PlannerCalendar.group('4069_4256')]);
    });

    test('refuses an item that is not a class planner id', () {
      for (final value in [
        'me',
        '',
        '6WEWI1',
        '4069_4256',
        'user/4069_218_0',
        'location/4069_$_uuid',
        7,
        null,
      ]) {
        expect(
          () => classes(['group/4069_4256', value]),
          throwsA(
            _toolError(
              'each item of classes must be the planner id of a class as '
              'search_planners shows it, like group/4069_4256; '
              '${value is String ? '"$value"' : '$value'} is not.',
            ),
          ),
        );
      }
    });

    test('refuses no classes, and more than max', () {
      for (final value in [null, <Object?>[]]) {
        expect(
          () => classes(value),
          throwsA(_toolError(startsWith('classes is empty: pass the planner'))),
        );
      }
      expect(
        () => classes([
          for (var i = 1; i <= 4; i++) 'group/4069_$i',
          'group/4069_1',
        ]),
        throwsA(
          _toolError(
            'classes holds 4 classes, and at most 3 fit in one call: ask for '
            'the others in another call.',
          ),
        ),
      );
    });
  });

  group('AssignmentTypes', () {
    const ko = PlannerAssignmentType(
      id: 'a',
      name: 'Kleine Overhoring',
      abbreviation: 'KO',
    );

    test('is one per session', () {
      final session = SmartschoolSession(fakeExtensionSettings());
      final other = SmartschoolSession(fakeExtensionSettings());
      expect(AssignmentTypes.of(session), same(AssignmentTypes.of(session)));
      expect(
        AssignmentTypes.of(session),
        isNot(same(AssignmentTypes.of(other))),
      );
    });

    test('reads the types once, also for reads at the same time', () async {
      final types = AssignmentTypes.of(
        SmartschoolSession(fakeExtensionSettings()),
      );
      final planner = _TypesPlanner([
        [ko],
      ]);

      final reads = [types.read(planner), types.read(planner)];
      planner.gate.complete();
      expect(await Future.wait(reads), [
        [ko],
        [ko],
      ]);
      expect(await types.read(planner), [ko]);
      expect(planner.reads, 1);
    });

    test('reads again after a read that failed', () async {
      final types = AssignmentTypes.of(
        SmartschoolSession(fakeExtensionSettings()),
      );
      final planner = _TypesPlanner([
        SmartschoolPlannerError('no types', statusCode: 403),
        [ko],
      ])..gate.complete();

      await expectLater(
        types.read(planner),
        throwsA(isA<SmartschoolPlannerError>()),
      );
      expect(await types.read(planner), [ko]);
      expect(await types.read(planner), [ko]);
      expect(planner.reads, 2);
    });
  });

  group('plannerPeriodArguments', () {
    DateTime now() => DateTime(2026, 10, 2, 16, 45);

    ({DateTime from, DateTime until}) period(
      Map<String, Object?> arguments, {
      int days = 7,
    }) => plannerPeriodArguments(arguments, days: days, now: now);

    test('runs from the start of today to the end of the day [days] days '
        'later', () {
      expect(period({}), (
        from: DateTime(2026, 10, 2),
        until: DateTime(2026, 10, 9, 23, 59, 59),
      ));
      expect(
        period({'from': '', 'until': ' '}, days: 28).until,
        DateTime(2026, 10, 30, 23, 59, 59),
      );
    });

    test('runs [days] days from a from given alone', () {
      expect(period({'from': '2026-12-30'}), (
        from: DateTime(2026, 12, 30),
        until: DateTime(2027, 1, 6, 23, 59, 59),
      ));
    });

    test('takes dates (whole days) and dates with a time', () {
      expect(period({'from': '2026-10-05', 'until': '2026-10-05'}), (
        from: DateTime(2026, 10, 5),
        until: DateTime(2026, 10, 5, 23, 59, 59, 999),
      ));
      expect(
        period({'from': '2026-10-07 10:00', 'until': '2026-10-07 12:30'}),
        (from: DateTime(2026, 10, 7, 10), until: DateTime(2026, 10, 7, 12, 30)),
      );
    });

    test('refuses an invalid date, and an until before from', () {
      expect(
        () => period({'until': '2026-02-30'}),
        throwsA(_toolError(startsWith('until must be a date like'))),
      );
      expect(
        () => period({'from': '2026-10-09', 'until': '2026-10-08'}),
        throwsA(_toolError('until must not be before from.')),
      );
      expect(
        () => period({'until': '2026-10-01'}),
        throwsA(
          _toolError(
            'until must not be before from (today when it is not given).',
          ),
        ),
      );
    });
  });

  group('plannerToolError', () {
    test('says an element that is gone is gone, and to list again', () {
      expect(
        plannerToolError(
          const SmartschoolPlannedElementNotFoundError(
            'The planner has no planned-placeholders ...',
            elementType: 'planned-placeholders',
            platformId: 4069,
            elementId: _uuid,
          ),
        ),
        _toolError(
          'The planner has no element planned-placeholders/4069/$_uuid (any '
          'more). It was removed, or its id changed: a lesson hour that is '
          'filled or cleared gets a new id. List the planner again with '
          'list_planner and take the id from there.',
        ),
      );
    });

    test('does not quote an answer the planner gave', () {
      const answer = 'secret answer of the planner';
      expect(
        plannerToolError(const SmartschoolPlannerError('Got: $answer')),
        _toolError(
          'The planner gave an answer the server could not use. Try again in '
          'a moment; the technical details are in the server log.',
        ),
      );
      expect(
        plannerToolError(
          const SmartschoolPlannerError('Got: $answer', statusCode: 403),
        ),
        _toolError(
          allOf(contains('could not use (HTTP 403).'), isNot(contains(answer))),
        ),
      );
    });

    test('does not quote an answer the Lesfiches module gave', () {
      const answer = 'secret answer of the module';
      expect(
        plannerToolError(const SmartschoolLessonContentError('Got: $answer')),
        _toolError(
          'The Lesfiches module gave an answer the server could not use. Try '
          'again in a moment; the technical details are in the server log.',
        ),
      );
      expect(
        plannerToolError(
          const SmartschoolLessonContentError('Got: $answer', statusCode: 500),
        ),
        _toolError(
          allOf(contains('could not use (HTTP 500).'), isNot(contains(answer))),
        ),
      );
    });

    test('passes on why the library refused a write before sending it, '
        'without its method name and its own "Nothing was sent"', () {
      expect(
        plannerToolError(
          const SmartschoolPlannerWriteRefusedError(
            'planLesson: the planner does not let you change '
            'planned-placeholders $_uuid (canUserReplace not set). Nothing '
            'was sent.',
          ),
        ),
        _toolError(
          'The planner refused the change before it was sent: the planner '
          'does not let you change planned-placeholders $_uuid '
          '(canUserReplace not set). List the planner again with '
          'list_planner (planner me) to see how it is now.',
        ),
      );
      expect(
        plannerToolError(
          const SmartschoolPlannerWriteRefusedError('Some other reason'),
        ),
        _toolError(
          'The planner refused the change before it was sent: Some other '
          'reason. List the planner again with list_planner (planner me) to '
          'see how it is now.',
        ),
      );
    });

    test('passes on what the library refused before sending', () {
      expect(
        plannerToolError(ArgumentError.value('x', 'id', 'is empty')),
        _toolError(
          'The planner request was refused before it was sent: id '
          'is empty.',
        ),
      );
    });

    test('leaves everything else to the session and the server', () {
      for (final error in [
        RangeError.index(3, [1]),
        StateError('bug'),
        const SmartschoolSessionExpiredError('refused'),
        const SmartschoolConnectionError('offline'),
        const SmartschoolPlannerSaveUnconfirmedError('maybe'),
      ]) {
        expect(plannerToolError(error), isNull, reason: '$error');
      }
    });
  });

  group('formatElementTime', () {
    test('a lesson hour, an assignment\'s deadline and a whole day', () {
      expect(
        formatElementTime(
          _element(
            from: DateTime(2026, 10, 5, 10, 20),
            to: DateTime(2026, 10, 5, 11, 10),
          ),
        ),
        '10:20–11:10',
      );
      expect(
        formatElementTime(
          _element(
            type: 'planned-assignments',
            from: DateTime(2026, 10, 6, 8, 30),
            to: DateTime(2026, 10, 6, 9, 20),
            deadline: true,
          ),
        ),
        '08:30 (deadline)',
      );
      for (final to in [
        DateTime(2026, 10, 8, 23, 59, 59),
        DateTime(2026, 10, 9),
      ]) {
        expect(
          formatElementTime(
            _element(from: DateTime(2026, 10, 8), to: to, wholeDay: true),
          ),
          'whole day',
          reason: '$to',
        );
      }
    });

    test('an element that ends on another day', () {
      expect(
        formatElementTime(
          _element(
            from: DateTime(2026, 10, 8),
            to: DateTime(2026, 10, 10, 23, 59, 59),
            wholeDay: true,
          ),
        ),
        'whole day until 2026-10-10',
      );
      expect(
        formatElementTime(
          _element(
            from: DateTime(2026, 10, 8, 20),
            to: DateTime(2026, 10, 9, 8),
          ),
        ),
        '20:00 until 2026-10-09 08:00',
      );
    });

    test('in the time of this PC, for a planner time with an offset', () {
      // A UTC DateTime, as DateTime.parse gives for a time with an offset.
      final summer = DateTime.parse('2026-10-05T10:20:00+02:00');
      final local = summer.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      expect(summer.isUtc, isTrue);
      expect(
        formatPlannerTime(summer),
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}',
      );
      expect(formatPlannerDay(summer), formatPlannerDay(local));
    });
  });

  test('formatPlannerPeriod gives whole days as the day, and a time when it '
      'is not the start or the end of the day', () {
    expect(
      formatPlannerPeriod(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 9, 23, 59, 59, 999),
      ),
      'from Monday 2026-10-05 to Friday 2026-10-09',
    );
    expect(
      formatPlannerPeriod(DateTime(2026, 10, 5, 8), DateTime(2026, 10, 5, 12)),
      'from Monday 2026-10-05 08:00 to Monday 2026-10-05 12:00',
    );
  });

  test('formatAssignmentType gives the abbreviation and the name, or the one '
      'a type has', () {
    for (final (abbreviation, name, text) in [
      ('KO', 'Kleine Overhoring', 'KO Kleine Overhoring'),
      ('', 'Kleine Overhoring', 'Kleine Overhoring'),
      ('KO', '', 'KO'),
    ]) {
      expect(
        formatAssignmentType(
          PlannerAssignmentType(
            id: 'a',
            name: name,
            abbreviation: abbreviation,
          ),
        ),
        text,
      );
    }
  });

  group('formatElementKind', () {
    test('names the type of an assignment, and the planner type of any '
        'other element', () {
      DateTime at(int hour) => DateTime(2026, 10, 5, hour);
      expect(
        formatElementKind(
          _element(
            type: 'planned-assignments',
            from: at(8),
            to: at(9),
            assignmentType: const PlannerAssignmentType(
              id: 'a',
              name: 'Grote Taak',
              abbreviation: 'GT',
            ),
          ),
        ),
        'assignment GT Grote Taak',
      );
      expect(
        formatElementKind(
          _element(type: 'planned-assignments', from: at(8), to: at(9)),
        ),
        'assignment',
      );
      expect(
        formatElementKind(
          _element(type: 'planned-school-activities', from: at(8), to: at(9)),
        ),
        'planned-school-activities',
      );
    });
  });

  test('formatElementLine leaves out the user as organiser, and the parts '
      'an element does not have', () {
    final element = _element(
      name: '  ',
      from: DateTime(2026, 10, 5, 10, 20),
      to: DateTime(2026, 10, 5, 11, 10),
      organisers: [
        const PlannerUser(id: fakePlannerMe, name: 'Jan Peeters'),
        const PlannerUser(id: '4069_1003_0', name: 'Wim Willems'),
      ],
    );
    expect(
      formatElementLine(element, ownUserId: fakePlannerMe),
      '10:20–11:10 | lesson | by Wim Willems | id planned-lessons/4069/$_uuid',
    );
    expect(
      formatElementLine(element),
      '10:20–11:10 | lesson | by Jan Peeters, Wim Willems | id '
      'planned-lessons/4069/$_uuid',
    );
  });

  test('formatElementSummary names the kind, the name, when, the classes '
      'and the course of an element, leaving out what it does not have', () {
    final lesson = PlannedElement(
      id: _uuid,
      platformId: 4069,
      type: PlannedElementType.lesson,
      typeName: 'planned-lessons',
      name: 'Lussen',
      period: PlannerPeriod(
        from: DateTime(2026, 11, 20, 11, 10),
        to: DateTime(2026, 11, 20, 12),
      ),
      participantGroups: const [
        PlannerGroup(id: '4069_2001', platformId: 4069, name: '6A1'),
        PlannerGroup(id: '4069_2002', platformId: 4069, name: '6A2'),
      ],
      courses: const [
        PlannerCourse(id: 'c1', platformId: 4069, name: 'informatica'),
      ],
    );
    expect(
      formatElementSummary(lesson),
      'lesson "Lussen" on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, '
      'informatica)',
    );
    expect(
      formatElementSummary(
        _element(
          type: 'planned-placeholders',
          name: null,
          from: DateTime(2026, 11, 20, 11, 10),
          to: DateTime(2026, 11, 20, 12),
        ),
      ),
      'empty lesson hour on Friday 2026-11-20 11:10–12:00',
    );
  });

  test('elementsByDay groups per day in time order', () {
    PlannedElement at(String name, DateTime from) => _element(
      name: name,
      from: from,
      to: from.add(const Duration(minutes: 50)),
    );
    final days = elementsByDay([
      at('c', DateTime(2026, 10, 6, 8, 30)),
      at('b', DateTime(2026, 10, 5, 14, 40)),
      at('a', DateTime(2026, 10, 5, 8, 30)),
    ]);
    expect(days.keys, [DateTime(2026, 10, 5), DateTime(2026, 10, 6)]);
    expect(
      [for (final e in days.values.expand((d) => d)) e.name],
      ['a', 'b', 'c'],
    );
  });

  group('plannerName', () {
    final elements = PlannerService.parsePlannedElements([
      fakeSlot.listJson(),
      fakeLesson.listJson(),
    ]);

    test('names a class, a person and a room after what the elements say', () {
      expect(plannerName(PlannerCalendar.group('4069_2003'), elements), '6B1');
      expect(
        plannerName(PlannerCalendar.user('4069_1003_0'), elements),
        'Wim Willems',
      );
      expect(plannerName(fakeLessonRoom, elements), '103');
      expect(plannerName(PlannerCalendar.group('4069_9'), elements), isNull);
      expect(plannerName(PlannerCalendar.group('4069_2003'), const []), isNull);
    });
  });

  group('formatElementDetail', () {
    PlannedElementDetail detail(Map<String, Object?> changes) =>
        PlannedElementDetail.fromJson({...fakeLesson.detailJson(), ...changes});

    test('reads labels, attachments and weblinks of any shape, leaving out '
        'what has no text', () {
      final text = formatElementDetail(
        detail({
          'labels': [
            {'text': ' JAAR 6 '},
            {'text': ''},
            {'color': 'aqua'},
            'TRIMESTER 1',
          ],
          'attachments': {'name': 'not a list'},
          'weblinks': [
            {'name': '', 'url': 'https://example.com/a'},
            {'name': 'Zonder adres'},
            {'name': '', 'url': ''},
            null,
          ],
        }),
      );
      expect(text, contains('\nLabels: JAAR 6\n'));
      expect(text, isNot(contains('Attachments')));
      expect(
        text,
        contains('\nWeblinks: https://example.com/a, Zonder adres\n'),
      );
    });

    test('cuts off a very long info text, with a note', () {
      final long = 'woord ' * 5000;
      final text = formatElementDetail(detail({'publicInfo': '<p>$long</p>'}));
      expect(
        text,
        contains(
          '\n[Cut off: showing the first $maxPlannerInfoLength of '
          '${long.trim().length} characters.]\n',
        ),
      );
    });
  });
}

/// The planner of room 103, where [fakeLesson] takes place.
final fakeLessonRoom = PlannerCalendar.location('4069_${fakeRoom103.id}');
