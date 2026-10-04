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

    test('gives the types replace takes from then on, without reading them: '
        'the school\'s types changed', () async {
      const go = PlannerAssignmentType(
        id: 'b',
        name: 'Grote Overhoring',
        abbreviation: 'GO',
      );
      final types = AssignmentTypes.of(
        SmartschoolSession(fakeExtensionSettings()),
      );
      final planner = _TypesPlanner([
        [ko],
      ])..gate.complete();

      expect(await types.read(planner), [ko]);
      types.replace([go]);
      expect(await types.read(planner), [go]);
      expect(await types.read(planner), [go]);
      expect(planner.reads, 1);
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

    group('words why the library refused a write before sending it from '
        'its reason (dartschool#100), naming the element, without the '
        'library\'s message', () {
      const lead = 'The planner refused the change before it was sent';
      const message =
          'planLesson: planned-placeholders $_uuid (2026-11-20 13:00:00.000 '
          '- 2026-11-20 13:50:00.000) secret words of the library. Nothing '
          'was sent.';
      const listAgain =
          'List the planner again with list_planner (planner me) to see how '
          'it is now.';
      const piet = PlannerUser(id: '4069_1002_0', name: 'Piet Peeters');

      /// An element of 6A1 and informatica on Friday 2026-11-20 at
      /// [hour]:00 for 50 minutes, by [organisers].
      PlannedElement element({
        String type = 'planned-placeholders',
        String? name,
        int hour = 13,
        List<PlannerUser> organisers = const [piet],
        PlannerAssignmentType? assignmentType,
      }) => PlannedElement(
        id: _uuid,
        platformId: 4069,
        type: PlannedElementType.fromWire(type),
        typeName: type,
        name: name,
        period: PlannerPeriod(
          from: DateTime(2026, 11, 20, hour),
          to: DateTime(2026, 11, 20, hour, 50),
          deadline: type == 'planned-assignments',
        ),
        organiserUsers: organisers,
        participantGroups: const [
          PlannerGroup(id: '4069_2001', platformId: 4069, name: '6A1'),
        ],
        courses: const [
          PlannerCourse(id: 'c1', platformId: 4069, name: 'informatica'),
        ],
        assignmentType: assignmentType,
      );
      const hour =
          'empty lesson hour on Friday 2026-11-20 13:00–13:50 (6A1, '
          'informatica)';

      String? refused(
        PlannerWriteRefusalReason? reason, {
        PlannedElement? element,
        List<String> flags = const [],
        LessonContentItem? lessonContent,
      }) => plannerToolError(
        SmartschoolPlannerWriteRefusedError(
          message,
          reason: reason,
          element: element,
          capabilityFlags: flags,
          lessonContent: lessonContent,
        ),
      )?.message;

      test('every reason, without the library\'s message or its method', () {
        for (final reason in [...PlannerWriteRefusalReason.values, null]) {
          expect(
            refused(reason, element: element()),
            allOf(
              startsWith(lead),
              isNot(contains('secret words')),
              isNot(contains('planLesson')),
              isNot(contains('Nothing was sent')),
              isNot(contains('13:00:00.000')),
            ),
            reason: '$reason',
          );
        }
      });

      test('notOwn: who organises a colleague\'s element', () {
        expect(
          refused(PlannerWriteRefusalReason.notOwn, element: element()),
          '$lead: the $hour is not in your own planner: it is organised by '
          'Piet Peeters. Only the elements of your own planner can be '
          'changed, as list_planner (planner me) shows them.',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.notOwn,
            element: element(organisers: const []),
          ),
          contains(
            'is not in your own planner: it is organised by someone else.',
          ),
        );
        expect(
          refused(PlannerWriteRefusalReason.notOwn),
          contains(
            ': the element is not in your own planner: it is organised by '
            'someone else.',
          ),
        );
      });

      test('notAllowed: what the planner does not let the user do, and the '
          'capabilities that are not set', () {
        expect(
          refused(
            PlannerWriteRefusalReason.notAllowed,
            element: element(),
            flags: const ['canUserReplace'],
          ),
          '$lead: the planner does not let you fill the $hour: its '
          'capability canUserReplace is not set.',
        );
        final lesson = element(type: 'planned-lessons', name: 'Lussen');
        for (final (flags, words) in [
          (
            const ['canUserEdit', 'canUserRename'],
            'change or rename the lesson "Lussen" on Friday 2026-11-20 '
                '13:00–13:50 (6A1, informatica): its capabilities canUserEdit '
                'and canUserRename are not set.',
          ),
          (
            const ['canUserChangePublicInfo'],
            'change the public info of the lesson "Lussen"',
          ),
          (
            const ['canUserChangePrivateInfo'],
            'change the private info of the lesson "Lussen"',
          ),
          (
            const ['canUserSing'],
            'change the lesson "Lussen" on Friday 2026-11-20 13:00–13:50 '
                '(6A1, informatica): its capability canUserSing is not set.',
          ),
        ]) {
          expect(
            refused(
              PlannerWriteRefusalReason.notAllowed,
              element: lesson,
              flags: flags,
            ),
            contains('the planner does not let you $words'),
            reason: '$flags',
          );
        }
        expect(
          refused(
            PlannerWriteRefusalReason.notAllowed,
            element: element(
              type: 'planned-assignments',
              name: 'Toets',
              assignmentType: const PlannerAssignmentType(
                id: 'a',
                name: 'Kleine Overhoring',
                abbreviation: 'KO',
              ),
            ),
            flags: const ['canUserTrash'],
          ),
          '$lead: the planner does not let you trash the assignment KO Kleine '
          'Overhoring "Toets" on Friday 2026-11-20 13:00 (deadline) (6A1, '
          'informatica): its capability canUserTrash is not set.',
        );
        expect(
          refused(PlannerWriteRefusalReason.notAllowed, element: element()),
          '$lead: the planner does not let you change the $hour.',
        );
      });

      test('a lesson hour that changed since it was read, or that the server '
          'cannot fill', () {
        expect(
          refused(
            PlannerWriteRefusalReason.noLongerASlot,
            element: element(type: 'planned-lessons', name: 'Gepland'),
          ),
          '$lead: the lesson hour is not empty any more: the planner has the '
          'lesson "Gepland" on Friday 2026-11-20 13:00–13:50 (6A1, '
          'informatica) in its place. $listAgain',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.periodChanged,
            element: element(hour: 14),
          ),
          '$lead: the empty lesson hour moved since it was read: it is now the '
          'empty lesson hour on Friday 2026-11-20 14:00–14:50 (6A1, '
          'informatica). $listAgain',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.participantRoles,
            element: element(),
          ),
          '$lead: the $hour has participant roles or group filters, which '
          'this server does not know how to keep when it fills a lesson hour. '
          'Fill this hour in Smartschool itself.',
        );
      });

      test('trashable: a lesson outside the timetable, which is not '
          'cleared', () {
        final lesson = element(type: 'planned-lessons', name: 'Inhaalles');
        expect(
          refused(
            PlannerWriteRefusalReason.trashable,
            element: lesson,
            flags: const ['canUserTrash', 'canUserDelete'],
          ),
          '$lead: the lesson "Inhaalles" on Friday 2026-11-20 13:00–13:50 '
          '(6A1, informatica) is not a lesson in a lesson hour of the '
          'timetable, the only kind of lesson that is cleared: the planner '
          'lets you trash or delete it instead (its capabilities canUserTrash '
          'and canUserDelete are set). Remove it in Smartschool itself.',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.trashable,
            element: lesson,
            flags: const ['canUserDelete'],
          ),
          contains(
            'lets you delete it instead (its capability canUserDelete is '
            'set).',
          ),
        );
      });

      test('a lesfiche that is not the user\'s, or not a lesson one: points '
          'to list_lesfiches, not list_planner', () {
        LessonContentItem lesfiche(LessonContentType type, String typeName) =>
            LessonContentItem(
              id: 'b0000000-0000-4000-8000-000000000003',
              platformId: 4069,
              type: type,
              typeName: typeName,
              name: 'Taak: een eigen spel',
              isVisible: true,
            );

        expect(
          refused(PlannerWriteRefusalReason.unknownLessonContent),
          '$lead: you have no lesfiche with the id given (any more). List '
          'your lesfiches with list_lesfiches and take the id of a lesson '
          'lesfiche from there.',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.notALessonLessonContent,
            lessonContent: lesfiche(
              LessonContentType.assignment,
              'assignments',
            ),
          ),
          '$lead: the lesfiche "Taak: een eigen spel" is an assignment '
          'lesfiche, not a lesson lesfiche: only a lesson lesfiche can be '
          'planned into a lesson hour. List the lesson lesfiches with '
          'list_lesfiches and take the id of one from there.',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.notALessonLessonContent,
            lessonContent: lesfiche(LessonContentType.other, 'quizzes'),
          ),
          contains(
            ': the lesfiche "Taak: een eigen spel" is of the kind "quizzes", '
            'not a lesson lesfiche: ',
          ),
        );
        for (final reason in [
          PlannerWriteRefusalReason.unknownLessonContent,
          PlannerWriteRefusalReason.notALessonLessonContent,
        ]) {
          expect(refused(reason), isNot(contains('list_planner')));
        }
      });

      test('an assignment: a type the school no longer has, and a linked '
          'Skore evaluation', () {
        expect(
          refused(PlannerWriteRefusalReason.unknownAssignmentType),
          '$lead: the assignment type is no longer one of the school\'s '
          'assignment types: they changed since the server read them.',
        );
        expect(
          refused(
            PlannerWriteRefusalReason.linkedEvaluation,
            element: element(
              type: 'planned-assignments',
              name: 'Toets',
              organisers: const [],
            ),
          ),
          '$lead: the assignment "Toets" on Friday 2026-11-20 13:00 '
          '(deadline) (6A1, informatica) is linked to a Skore evaluation, '
          'which has to be unlinked in Smartschool first: only then can it be '
          'moved to the trash.',
        );
      });

      test('without a reason (an error made without one): the details are '
          'in the log', () {
        expect(
          refused(null, element: element()),
          '$lead. The technical details are in the server log.',
        );
      });
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
    test('names a meeting and a lesson-free day (#94), and counts them by '
        'their own kind', () {
      DateTime at(int hour) => DateTime(2026, 10, 5, hour);
      for (final (type, kind, text) in [
        ('planned-lessons', PlannedElementKind.lesson, 'lesson'),
        (
          'planned-placeholders',
          PlannedElementKind.emptyLessonHour,
          'empty lesson hour',
        ),
        ('planned-meetings', PlannedElementKind.meeting, 'meeting'),
        (
          'planned-lesson-free-days',
          PlannedElementKind.lessonFreeDay,
          'lesson-free day',
        ),
      ]) {
        final element = _element(type: type, from: at(8), to: at(9));
        expect(formatElementKind(element), text, reason: type);
        expect(PlannedElementKind.of(element), kind, reason: type);
      }
      expect(PlannedElementKind.meeting.count(1), '1 meeting');
      expect(PlannedElementKind.meeting.count(2), '2 meetings');
      expect(PlannedElementKind.lessonFreeDay.count(2), '2 lesson-free days');
      expect(PlannedElementKind.other.count(2), '2 other');
    });

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
      // A type the library knows but the tools do not name, and one the
      // library does not know.
      for (final type in ['planned-school-activities', 'planned-excursions']) {
        final element = _element(type: type, from: at(8), to: at(9));
        expect(formatElementKind(element), type);
        expect(PlannedElementKind.of(element), PlannedElementKind.other);
      }
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

    // The library parses these lists (yvanvds/dartschool#98), and refuses an
    // item without its id, or a list that is not one, with an error of its
    // own: only the shapes it accepts reach formatElementDetail.
    test('names the labels, attachments (by their fileName) and weblinks, '
        'leaving out what has no text', () {
      final text = formatElementDetail(
        detail({
          'labels': [
            {'id': 1, 'text': ' JAAR 6 '},
            {'id': 2, 'text': ''},
            {'id': 3, 'color': 'aqua'},
          ],
          'attachments': [
            {
              'id': 1,
              'fileName': ' rubriek.docx ',
              'fileSize': 18342,
              'mimeType': 'application/msword',
              'visibility': {'option': 'always', 'daysAfterEnd': null},
            },
            {'id': 2, 'name': 'not the planner\'s field'},
            {'id': 3, 'fileName': ''},
          ],
          'weblinks': [
            {'id': 1, 'name': '', 'url': ' https://example.com/a '},
            {'id': 2, 'name': 'Zonder adres'},
            {'id': 3, 'name': '', 'url': ''},
          ],
        }),
      );
      expect(text, contains('\nLabels: JAAR 6\n'));
      expect(text, contains('\nAttachments: rubriek.docx\n'));
      expect(
        text,
        contains('\nWeblinks: https://example.com/a, Zonder adres\n'),
      );
    });

    test('has no lines for lists the planner leaves out, or that are '
        'empty', () {
      for (final lists in [
        {'labels': null, 'attachments': null, 'weblinks': null},
        {'labels': [], 'attachments': [], 'weblinks': []},
      ]) {
        final text = formatElementDetail(detail(lists));
        expect(text, isNot(contains('Labels')));
        expect(text, isNot(contains('Attachments')));
        expect(text, isNot(contains('Weblinks')));
      }
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
