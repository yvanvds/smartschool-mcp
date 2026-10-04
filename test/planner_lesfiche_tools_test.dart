/// `list_lesfiches` and `plan_lesfiche` (#54), called over MCP on the real
/// server, session and library, against a fake Smartschool whose Lesfiches
/// module serves dartschool's anonymised capture of the live list (#88),
/// whose course list names the courses of the lesfiches (dartschool#101,
/// #87), and whose planner serves dartschool's captures and plans a lesfiche
/// into an empty lesson hour with the request of dartschool#88, as the live
/// planner did (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/clear_lesson_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/planner/api/v1';

/// The path of the plan of a lesfiche into the empty lesson hour [slot]:
/// the route of a blank lesson without `/blanco` (dartschool#88).
String _planPath(FakePlannedElement slot) =>
    '$_api/planned-placeholders/4069/${slot.id}/replace/planned-lessons';

/// The body the web client sends to plan the lesfiche [sourceId] into
/// [fakeOwnSlot] (dartschool#88, as tried live): the slot's organisers,
/// classes, course, period and room, the lesfiche's id and its icon, and no
/// name or info.
Map<String, Object?> _planBody(
  String sourceId, {
  String icon = 'document_observation',
}) => {
  'organisers': {
    'users': [fakePlannerMe],
    'groups': <Object?>[],
  },
  'participants': {
    'groups': ['4069_2001', '4069_2002'],
    'users': <Object?>[],
    'userRoles': <Object?>[],
    'groupFilters': {'filters': <Object?>[], 'additionalUsers': <Object?>[]},
  },
  'courses': [
    {'platformId': 4069, 'id': 'c0000000-0000-4000-8000-000000000005'},
  ],
  'period': {
    'dateTimeFrom': plannerTime(2026, 11, 20, 11, 10),
    'dateTimeTo': plannerTime(2026, 11, 20, 12, 0),
    'wholeDay': false,
  },
  'locations': [
    {
      'id': '10000000-0000-4000-8000-000000000101',
      'platformId': 4069,
      'platformlName': 'Springfield Academy',
      'type': 'mini-db-item',
    },
  ],
  'sourceId': sourceId,
  'icon': icon,
};

/// The id the fake gives the [n]th lesson its writes make.
String _lessonId(int n) =>
    'planned-lessons/4069/e0000000-0000-4000-9000-${'$n'.padLeft(12, '0')}';

/// A lesson lesfiche of informatica with the labels JAAR 6 and [trimester].
FakeLesfiche _lesson(
  String id,
  String name, {
  String trimester = 'TRIMESTER 1',
}) => FakeLesfiche(
  id: 'b0000000-0000-4000-8000-0000000000$id',
  name: name,
  courses: [fakeInformatica],
  labels: ['JAAR 6', trimester],
);

/// An empty lesson hour of the own planner, 11:10–12:00 on [day] November
/// 2026, of 6A1 and 6A2 in room 101, like [fakeOwnSlot].
FakePlannedElement _ownHour(String id, int day) => FakePlannedElement(
  id: 'e0000000-0000-5000-8000-0000000000$id',
  type: 'planned-placeholders',
  from: plannerTime(2026, 11, day, 11, 10),
  to: plannerTime(2026, 11, day, 12, 0),
  organisers: [FakePlannerUser.me],
  groups: [fake6A1, fake6A2],
  courses: [fakeInformatica],
  rooms: [fakeRoom101],
);

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner
      ..loadCaptures()
      ..loadLesfiches();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    DateTime now() => DateTime(2026, 10, 5, 9, 30);
    (connection, _) = await connect(
      tools: [
        listPlannerTool(session, now: now),
        readPlannedElementTool(session),
        clearLessonTool(session),
        listLesfichesTool(session),
        planLesficheTool(session),
      ],
    );
  });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// The planner and Lesfiches requests, as `METHOD path`, in order.
  List<String> plannerRequests() => [
    for (final request in planner.requests) '${request.method} ${request.path}',
  ];

  /// What a call of list_lesfiches with [arguments] sends to the fake
  /// Smartschool once the session is open, as `METHOD path`. The session
  /// check reads the school's course list too, so a first call opens the
  /// session.
  Future<List<String>> listRequests(Map<String, Object?> arguments) async {
    await ok('list_lesfiches', arguments);
    server.requests.clear();
    await ok('list_lesfiches', arguments);
    return [...server.requests];
  }

  /// The bodies of the requests to [path] that reached the planner.
  List<Object?> bodiesTo(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
  ];

  /// How many POSTs to [path] reached the fake Smartschool, also those it
  /// refused because the session was not accepted.
  int postsTo(String path) =>
      server.requests.where((request) => request == 'POST $path').length;

  group('the tools are listed', () {
    late Map<String, Tool> tools;

    setUp(() async {
      tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
    });

    test('list_lesfiches as a read, plan_lesfiche as a write Claude Desktop '
        'asks approval for every time, not idempotent', () {
      final list = tools['list_lesfiches']!.toolAnnotations!;
      expect(list.readOnlyHint, isTrue);
      expect(list.idempotentHint, isTrue);
      expect(list.openWorldHint, isTrue);
      final plan = tools['plan_lesfiche']!.toolAnnotations!;
      expect(plan.readOnlyHint, isFalse);
      expect(plan.destructiveHint, isTrue);
      expect(plan.idempotentHint, isFalse);
      expect(plan.openWorldHint, isTrue);
    });

    test('with their arguments', () {
      final list = tools['list_lesfiches']!.inputSchema;
      expect(list.required ?? const <String>[], isEmpty);
      expect(list.properties!.keys, ['query', 'label', 'type']);
      expect((list.properties!['type']! as Map)['enum'], [
        'lessons',
        'assignments',
        'all',
      ]);
      final plan = tools['plan_lesfiche']!.inputSchema;
      expect(plan.required, ['hour', 'lesfiche']);
      expect(plan.properties!.keys, ['hour', 'lesfiche']);
    });

    test('list_lesfiches says whose lesfiches it lists, how they are '
        'sorted, and that only lessons can be planned', () {
      final description = tools['list_lesfiches']!.description!;
      expect(
        description,
        contains(
          'their own, and lesfiches shared with them if Smartschool lists '
          'those',
        ),
      );
      expect(description, contains('By default only lesson lesfiches.'));
      expect(description, contains('Sorted by name'));
      expect(
        description,
        contains(
          'Only lesson lesfiches can be planned, with plan_lesfiche, hidden '
          'ones too.',
        ),
      );
      expect(description, contains('list_planner (planner me)'));
      expect(description, contains('Listing changes nothing in Smartschool.'));
    });

    test('plan_lesfiche tells Claude to get the user\'s explicit '
        'confirmation of the mapping first, that only the own planner '
        'changes, and never to repeat a plan that may have been saved', () {
      final description = tools['plan_lesfiche']!.description!;
      for (final phrase in [
        'after the user has explicitly confirmed it',
        'Only the user\'s own',
        'this tool refuses those',
        'do not call this tool again for',
        'read_planned_element',
        'list_lesfiches',
        'list_planner (planner me)',
        'Only lesson lesfiches can be planned (hidden ones too)',
        'Show the user, per hour, the date and time, the class, the course, '
            'and the name of the lesfiche that goes there',
        'For a series of lesfiches, one confirmation of the full mapping is '
            'enough; then call this tool once per hour, in order.',
      ]) {
        expect(description, contains(phrase));
      }
    });
  });

  group('list_lesfiches', () {
    test('lists the lesson lesfiches by name: kind, name, labels, courses '
        'named after the school\'s course list, visible or hidden, last '
        'changed and id', () async {
      expect(
        await ok('list_lesfiches', {}),
        '2 lesson lesfiches, of the 3 lesfiches in the Lesfiches module, by '
        'name:\n'
        'lesson | Functies | no labels | informatica, chemie | visible | '
        'changed 2025-09-12 | id ${fakeLesficheFuncties.id}\n'
        'lesson | Herhaling: lussen | labels JAAR 6, TRIMESTER 1 | '
        'informatica | hidden | changed 2026-09-07 | id '
        '${fakeLesficheLussen.id}',
      );
      // The list, and the course list that names its courses; not the
      // planner, and nothing else.
      expect(await listRequests({}), [
        'GET $fakeLesfichesPath',
        'GET $fakeCourseListPath',
      ]);
      expect(planner.calendarQueries, isEmpty);
      expect(planner.writes, isEmpty);
    });

    test('a course that the course list does not name is counted, with a '
        'note', () async {
      const fysica = FakePlannerCourse(
        'c0000000-0000-4000-8000-000000000099',
        'fysica',
      );
      planner.lesfiches.add(
        const FakeLesfiche(
          id: 'b0000000-0000-4000-8000-000000000031',
          name: 'Krachten',
          courses: [fakeInformatica, fysica],
        ),
      );

      expect(
        await ok('list_lesfiches', {'query': 'krachten'}),
        '1 lesson lesfiche whose name holds "krachten", of the 4 lesfiches in '
        'the Lesfiches module, by name:\n'
        'lesson | Krachten | no labels | informatica, 1 unnamed course | '
        'visible | changed 2025-09-12 | id '
        'b0000000-0000-4000-8000-000000000031\n'
        'A course that the school\'s course list does not name shows as '
        '"unnamed course".',
      );
    });

    test('lists the assignment lesfiches with their type, or every '
        'lesfiche, and says only lessons can be planned', () async {
      expect(
        await ok('list_lesfiches', {'type': 'assignments'}),
        '1 assignment lesfiche, of the 3 lesfiches in the Lesfiches module, '
        'by name:\n'
        'assignment KT Kleine Taak | Taak: een eigen spel | labels Lussen | '
        'informatica | visible | changed 2025-09-05 | id '
        '${fakeLesficheGame.id}\n'
        'Only the lesson lesfiches can be planned, with plan_lesfiche.',
      );
      final all = await ok('list_lesfiches', {'type': 'all'});
      expect(
        all,
        startsWith(
          '3 lesfiches, of the 3 lesfiches in the Lesfiches module, by '
          'name:\n'
          'lesson | Functies |',
        ),
      );
      expect(
        all
            .split('\n')
            .where((line) => line.contains(' | id '))
            .map((line) => line.split(' | ')[1]),
        ['Functies', 'Herhaling: lussen', 'Taak: een eigen spel'],
      );
      expect(
        all,
        endsWith(
          'Only the lesson lesfiches can be planned, with plan_lesfiche.',
        ),
      );
    });

    test('keeps the lesfiches with every label given: the whole label, '
        'case-insensitive, the school\'s and the user\'s own', () async {
      planner.lesfiches.add(
        _lesson('11', 'Les 1: eerste programma', trimester: 'TRIMESTER 2'),
      );
      final both = await ok('list_lesfiches', {
        'label': ['jaar 6', ' Trimester  1 '],
      });
      expect(
        both,
        startsWith(
          '1 lesson lesfiche with the labels "jaar 6" and "Trimester  1", of '
          'the 4 lesfiches in the Lesfiches module, by name:\n'
          'lesson | Herhaling: lussen |',
        ),
      );
      expect(
        await ok('list_lesfiches', {
          'label': ['JAAR 6'],
        }),
        allOf(
          startsWith('2 lesson lesfiches with the label "JAAR 6",'),
          contains('| Les 1: eerste programma |'),
          contains('| Herhaling: lussen |'),
        ),
      );
      expect(
        await ok('list_lesfiches', {
          'type': 'all',
          'label': ['lussen'],
        }),
        contains('| Taak: een eigen spel |'),
      );
    });

    test('a label that no lesfiche has: the labels there are', () async {
      expect(
        await ok('list_lesfiches', {
          'label': ['JAAR'],
        }),
        'No lesson lesfiches with the label "JAAR" (of the 3 lesfiches in '
        'the Lesfiches module).\n'
        'The labels of your lesson lesfiches: JAAR 6, TRIMESTER 1.',
      );
      // Nothing listed to name, but the library reads the course list
      // when any lesfiche has a course, also one that is not listed.
      expect(
        await listRequests({
          'label': ['JAAR'],
        }),
        ['GET $fakeLesfichesPath', 'GET $fakeCourseListPath'],
      );
    });

    test('keeps the lesfiches whose name holds every word of query, in any '
        'order, case-insensitive', () async {
      expect(
        await ok('list_lesfiches', {'query': 'LUS herh'}),
        startsWith(
          '1 lesson lesfiche whose name holds "LUS herh", of the 3 '
          'lesfiches in the Lesfiches module, by name:\n'
          'lesson | Herhaling: lussen |',
        ),
      );
      expect(
        await ok('list_lesfiches', {'query': 'lussen functies'}),
        'No lesson lesfiches whose name holds "lussen functies" (of the 3 '
        'lesfiches in the Lesfiches module).',
      );
    });

    test('sorts by name with the numbers in order, as a series is '
        'planned', () async {
      planner.lesfiches.addAll([
        _lesson('12', 'Les 10: lijsten'),
        _lesson('13', 'Les 2: variabelen'),
        _lesson('14', 'les 1: eerste programma'),
      ]);
      final text = await ok('list_lesfiches', {
        'label': ['JAAR 6', 'TRIMESTER 1'],
      });
      expect(
        text
            .split('\n')
            .where((line) => line.contains(' | id '))
            .map((line) => line.split(' | ')[1]),
        [
          'Herhaling: lussen',
          'les 1: eerste programma',
          'Les 2: variabelen',
          'Les 10: lijsten',
        ],
      );
    });

    test('when the school\'s course list cannot be read, lists the '
        'lesfiches with how many courses they have, and says why', () async {
      // The session check reads the course list too: a first call opens the
      // session, then the list fails.
      await ok('list_lesfiches', {});
      planner.failing[fakeCourseListPath] = 500;

      expect(
        await ok('list_lesfiches', {'type': 'all'}),
        '3 lesfiches, of the 3 lesfiches in the Lesfiches module, by name:\n'
        'lesson | Functies | no labels | 2 courses | visible | changed '
        '2025-09-12 | id ${fakeLesficheFuncties.id}\n'
        'lesson | Herhaling: lussen | labels JAAR 6, TRIMESTER 1 | 1 course | '
        'hidden | changed 2026-09-07 | id ${fakeLesficheLussen.id}\n'
        'assignment KT Kleine Taak | Taak: een eigen spel | labels Lussen | '
        '1 course | visible | changed 2025-09-05 | id ${fakeLesficheGame.id}\n'
        'Note: the names of the courses could not be read from the school\'s '
        'course list (HTTP 500), so only the number of courses is shown.\n'
        'Only the lesson lesfiches can be planned, with plan_lesfiche.',
      );

      // A course list in a shape the library does not know (a course
      // without its id): no status to give.
      planner.failing.remove(fakeCourseListPath);
      planner.courseList.add(const FakePlannerCourse('', 'fysica'));
      expect(
        await ok('list_lesfiches', {}),
        allOf(
          contains('| Functies | no labels | 2 courses | visible |'),
          endsWith(
            'Note: the names of the courses could not be read from the '
            'school\'s course list, so only the number of courses is shown.',
          ),
        ),
      );
    });

    test('when the school\'s course list cannot be read and no lesfiche '
        'listed has a course, no note on the courses', () async {
      planner.lesfiches.add(
        const FakeLesfiche(
          id: 'b0000000-0000-4000-8000-000000000021',
          name: 'Vrij',
        ),
      );
      // The session check reads the course list too: a first call opens the
      // session, then the list fails. The other lesfiches have a course, so
      // the library reads it.
      await ok('list_lesfiches', {});
      planner.failing[fakeCourseListPath] = 500;

      expect(
        await ok('list_lesfiches', {'query': 'vrij'}),
        '1 lesson lesfiche whose name holds "vrij", of the 4 lesfiches in the '
        'Lesfiches module, by name:\n'
        'lesson | Vrij | no labels | no course | visible | changed '
        '2025-09-12 | id b0000000-0000-4000-8000-000000000021',
      );
    });

    test('a lesfiche without a course, and without lesfiches', () async {
      planner.lesfiches
        ..clear()
        ..add(
          const FakeLesfiche(
            id: 'b0000000-0000-4000-8000-000000000021',
            name: 'Vrij',
          ),
        );
      expect(
        await ok('list_lesfiches', {}),
        '1 lesson lesfiche, of the 1 lesfiches in the Lesfiches module, by '
        'name:\n'
        'lesson | Vrij | no labels | no course | visible | changed '
        '2025-09-12 | id b0000000-0000-4000-8000-000000000021',
      );
      // No course to name: the course list is not read.
      expect(await listRequests({}), ['GET $fakeLesfichesPath']);

      planner.lesfiches.clear();
      expect(
        await ok('list_lesfiches', {}),
        'You have no lesfiches in the Lesfiches module.',
      );
    });

    test('shows at most 200, with a note to narrow the list', () async {
      planner.lesfiches.addAll([
        for (var i = 0; i < 205; i++)
          FakeLesfiche(
            id: 'b0000000-0000-4000-8000-${'${1000 + i}'.padLeft(12, '0')}',
            name: 'Les ${i + 1}',
          ),
      ]);
      final lines = (await ok('list_lesfiches', {})).split('\n');
      expect(
        lines.first,
        '207 lesson lesfiches, of the 208 lesfiches in the Lesfiches module, '
        'by name:',
      );
      expect(lines.where((line) => line.contains(' | id ')), hasLength(200));
      expect(
        lines,
        contains(
          'Note: only the first 200 of the 207 are shown: narrow the list '
          'with label or query.',
        ),
      );
    });

    test('an answer of the Lesfiches module the server cannot use: an '
        'error that says so, without the answer', () async {
      planner.failing[fakeLesfichesPath] = 500;

      expect(
        await error('list_lesfiches', {}),
        'The Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log.',
      );
    });
  });

  group('plan_lesfiche', () {
    final planPath = _planPath(fakeOwnSlot);

    test('plans a lesson lesfiche into an own empty lesson hour once, with '
        'the request of dartschool#88, and gives the lesson as saved with '
        'its new id', () async {
      final lessonId = _lessonId(1);
      expect(
        await ok('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': 'id ${fakeLesficheFuncties.id}',
        }),
        'Planned the lesfiche ${fakeLesficheFuncties.id} in the empty lesson '
        'hour on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica). '
        'Pupils of 6A1, 6A2 see its name and public info now.\n'
        'The empty lesson hour ${fakeOwnSlot.ref} no longer exists: the '
        'lesson has the id $lessonId.\n'
        'For a few seconds after a change list_planner can still show the '
        'old state; read_planned_element shows the new state at once.\n'
        '\n'
        'Planner element $lessonId\n'
        'Kind: lesson\n'
        'Name: Functies\n'
        'When: Friday 2026-11-20 11:10–12:00\n'
        'Course: informatica\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Jan Peeters\n'
        'Room: 101\n'
        '\n'
        'Public info (what pupils see):\n'
        'Hoofdstuk 4\n'
        '\n'
        'Private info (hidden from pupils, but colleagues who can read this '
        'element see it too):\n'
        '(none)',
      );

      // The library reads the lesfiches and the hour before it plans.
      expect(
        plannerRequests(),
        containsAllInOrder([
          'GET $fakeLesfichesPath',
          'GET $_api/planned-placeholders/4069/${fakeOwnSlot.id}',
          'POST $planPath',
        ]),
      );
      expect(planner.writes, ['POST $planPath']);
      expect(bodiesTo(planPath), [_planBody(fakeLesficheFuncties.id)]);
      expect(planner.elements, isNot(contains(fakeOwnSlot.ref)));
      expect(
        await ok('list_planner', {'from': '2026-11-20', 'until': '2026-11-20'}),
        contains(
          '11:10–12:00 | lesson | Functies | informatica | 6A1, 6A2 | room '
          '101 | id $lessonId',
        ),
      );
    });

    test('plans a hidden lesfiche like any other: the lesson takes its '
        'name and labels', () async {
      expect(
        await ok('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': fakeLesficheLussen.id.toUpperCase(),
        }),
        allOf(
          contains('Name: Herhaling: lussen\n'),
          contains('Labels: JAAR 6, TRIMESTER 1\n'),
          contains('Public info (what pupils see):\n(none)\n'),
        ),
      );
      expect(bodiesTo(planPath), [_planBody(fakeLesficheLussen.id)]);
    });

    test('a planned lesfiche is cleared again with clear_lesson', () async {
      await ok('plan_lesfiche', {
        'hour': fakeOwnSlot.ref,
        'lesfiche': fakeLesficheLussen.id,
      });
      expect(
        await ok('clear_lesson', {'id': _lessonId(1)}),
        allOf(
          startsWith(
            'Cleared the lesson "Herhaling: lussen" on Friday 2026-11-20 '
            '11:10–12:00 (6A1, 6A2, informatica): its name and info are '
            'gone,',
          ),
          contains(
            'The empty lesson hour has a new id: '
            'planned-placeholders/4069/e0000000-0000-5000-9000-000000000002.',
          ),
        ),
      );
      expect(planner.elements, isNot(contains(_lessonId(1))));
    });

    test('refuses an assignment lesfiche without any write: the library '
        'reads the lesfiches and refuses it', () async {
      expect(
        await error('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': fakeLesficheGame.id,
        }),
        // In the tool's words, from the reason of the refusal
        // (dartschool#100), pointing to list_lesfiches.
        'The planner refused the change before it was sent: the lesfiche '
        '"Taak: een eigen spel" is an assignment lesfiche, not a lesson '
        'lesfiche: only a lesson lesfiche can be planned into a lesson hour. '
        'List the lesson lesfiches with list_lesfiches and take the id of one '
        'from there. Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeOwnSlot.ref));
    });

    test('refuses an id the user has no lesfiche with, without any '
        'write', () async {
      const unknown = 'b0000000-0000-4000-8000-000000000099';
      expect(
        await error('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': unknown,
        }),
        'The planner refused the change before it was sent: you have no '
        'lesfiche with the id given (any more). List your lesfiches with '
        'list_lesfiches and take the id of a lesson lesfiche from there. '
        'Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
    });

    test(
      'refuses a colleague\'s empty lesson hour without any write',
      () async {
        expect(
          await error('plan_lesfiche', {
            'hour': fakeSlot.ref,
            'lesfiche': fakeLesficheFuncties.id,
          }),
          allOf(
            startsWith('The planner refused the change before it was sent: '),
            contains('is not in your own planner'),
            endsWith('Nothing was changed in the planner.'),
          ),
        );
        expect(planner.writes, isEmpty);
      },
    );

    test('refuses a lesson as hour, and a lesfiche id that is not one, '
        'before asking Smartschool', () async {
      for (final (arguments, message) in [
        (
          {'hour': fakeOwnLesson.ref, 'lesfiche': fakeLesficheFuncties.id},
          'hour must be an empty lesson hour of your own planner',
        ),
        (
          {'hour': fakeOwnSlot.ref, 'lesfiche': fakeOwnLesson.ref},
          'lesfiche must be the id of a lesfiche as list_lesfiches shows it, '
              'like b0000000-0000-4000-8000-000000000001; '
              '"${fakeOwnLesson.ref}" is not. Nothing was sent.',
        ),
        (
          {'hour': fakeOwnSlot.ref, 'lesfiche': 'Herhaling: lussen'},
          'lesfiche must be the id of a lesfiche',
        ),
        (
          {'hour': fakeOwnSlot.ref, 'lesfiche': '  '},
          'lesfiche must be the id of a lesfiche',
        ),
      ]) {
        expect(
          await error('plan_lesfiche', arguments),
          startsWith(message),
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
    });

    test('an answer of the Lesfiches module the server cannot use: nothing '
        'is planned', () async {
      planner.failing[fakeLesfichesPath] = 500;

      expect(
        await error('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': fakeLesficheFuncties.id,
        }),
        'The Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log. Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeOwnSlot.ref));
    });

    group('a plan that the planner does not confirm is reported as maybe '
        'saved, and never sent again', () {
      test('the planner answers the plan with an error', () async {
        planner.failing[planPath] = 500;

        expect(
          await error('plan_lesfiche', {
            'hour': fakeOwnSlot.ref,
            'lesfiche': fakeLesficheFuncties.id,
          }),
          'The lesfiche ${fakeLesficheFuncties.id} in the empty lesson hour '
          'on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica) may or '
          'may not have been saved: the change was sent, but the planner did '
          'not confirm it. Do not call plan_lesfiche again for it: first read '
          'the hour with read_planned_element (id ${fakeOwnSlot.ref}): when '
          'the planner no longer has it, the hour was filled, and '
          'list_planner (planner me) shows the lesson in its place, possibly '
          'only after a few seconds; when the hour is still empty, nothing '
          'was saved. Then tell the user what you found.',
        );
        expect(postsTo(planPath), 1);
        expect(server.logins, 1);
      });

      test('the connection drops after the plan went out: a second call '
          'for the hour finds it gone, and plans nothing', () async {
        planner.lostAnswers.add(planPath);

        expect(
          await error('plan_lesfiche', {
            'hour': fakeOwnSlot.ref,
            'lesfiche': fakeLesficheFuncties.id,
          }),
          contains('may or may not have been saved'),
        );
        expect(postsTo(planPath), 1);
        expect(server.logins, 1);
        // It was saved: the check the result asks for tells, and a second
        // plan of the hour sends nothing.
        expect(
          await error('read_planned_element', {'id': fakeOwnSlot.ref}),
          startsWith('The planner has no element ${fakeOwnSlot.ref}'),
        );
        expect(
          await error('plan_lesfiche', {
            'hour': fakeOwnSlot.ref,
            'lesfiche': fakeLesficheFuncties.id,
          }),
          startsWith('The planner has no element ${fakeOwnSlot.ref}'),
        );
        expect(postsTo(planPath), 1);
        expect(
          planner.calendars['user/$fakePlannerMe']!
              .where((element) => element.name == 'Functies')
              .length,
          1,
        );
      });
    });

    test('Smartschool refuses the session for the plan, which the library '
        'does not send again: the session repeats the call, which reads the '
        'hour again and plans once', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' && request.uri.path == planPath,
      );

      expect(
        await ok('plan_lesfiche', {
          'hour': fakeOwnSlot.ref,
          'lesfiche': fakeLesficheFuncties.id,
        }),
        startsWith('Planned the lesfiche ${fakeLesficheFuncties.id} in the '),
      );
      expect(postsTo(planPath), 2, reason: 'the refused one and the plan');
      expect(planner.writes, ['POST $planPath'], reason: 'planned once');
      expect(server.logins, 2);
    });

    test('a series: the lesfiches in label and name order, planned one call '
        'per hour into the next lessons of the course and class', () async {
      planner.lesfiches.addAll([
        _lesson('12', 'Les 10: lijsten'),
        _lesson('13', 'Les 2: variabelen'),
        _lesson('14', 'Les 1: eerste programma'),
        _lesson('15', 'Les 3: herhaling', trimester: 'TRIMESTER 2'),
      ]);
      final hours = [fakeOwnSlot, _ownHour('31', 23), _ownHour('32', 27)];
      for (final hour in hours.skip(1)) {
        planner.add(
          hour,
          calendars: [
            'user/$fakePlannerMe',
            'group/4069_2001',
            'group/4069_2002',
            fakeRoom101.planner,
          ],
        );
      }

      // What Claude reads to propose the mapping.
      final lesfiches = await ok('list_lesfiches', {
        'label': ['JAAR 6', 'TRIMESTER 1'],
        'query': 'les',
      });
      final ids = [
        for (final line in lesfiches.split('\n'))
          if (line.contains(' | id ')) line.split(' | id ').last,
      ];
      expect(ids, [
        'b0000000-0000-4000-8000-000000000014',
        'b0000000-0000-4000-8000-000000000013',
        'b0000000-0000-4000-8000-000000000012',
      ]);
      final empty = await ok('list_planner', {
        'from': '2026-11-16',
        'until': '2026-11-27',
        'types': ['empty_lesson_hours'],
      });
      for (final hour in hours) {
        expect(empty, contains('id ${hour.ref}'));
      }

      // After the user confirmed the mapping: one call per hour, in order.
      for (final (hour, id) in [
        for (var i = 0; i < 3; i++) (hours[i], ids[i]),
      ]) {
        await ok('plan_lesfiche', {'hour': hour.ref, 'lesfiche': id});
      }

      expect(planner.writes, [
        for (final hour in hours) 'POST ${_planPath(hour)}',
      ]);
      final lessons = await ok('list_planner', {
        'from': '2026-11-16',
        'until': '2026-11-27',
        'types': ['lessons'],
      });
      expect(
        lessons
            .split('\n')
            .where((line) => line.contains('| lesson |'))
            .map((line) => line.split(' | ')[2]),
        ['Les 1: eerste programma', 'Les 2: variabelen', 'Les 10: lijsten'],
      );
      expect(
        lessons,
        contains('Friday 2026-11-20\n- 11:10–12:00 | lesson | Les 1'),
      );
      expect(
        lessons,
        contains('Monday 2026-11-23\n- 11:10–12:00 | lesson | Les 2'),
      );
      expect(
        lessons,
        contains('Friday 2026-11-27\n- 11:10–12:00 | lesson | Les 10'),
      );
    });
  });
}
