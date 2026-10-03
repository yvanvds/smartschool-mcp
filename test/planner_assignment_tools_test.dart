/// `plan_assignment` and `trash_assignment` (#55), and the edit of a planned
/// assignment with `edit_planned_element` (#53), called over MCP on the real
/// server, session and library, against a fake Smartschool whose planner
/// serves dartschool's anonymised captures and its workload view, and makes
/// and trashes an assignment with the requests of dartschool#89, as the live
/// planner did (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/edit_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/list_class_assignments_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_assignment_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_assignment_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/planner/api/v1';

/// The create of an assignment (dartschool#89), without its query.
const _createPath = '$_api/planned-assignments/blanco';

/// The path of the trash of [element].
String _trashPath(FakePlannedElement element) =>
    '$_api/planned-assignments/4069/${element.id}/trash';

/// The id the fake gives the [n]th element its writes make.
String _madeId(int n) => 'e0000000-0000-4000-9000-${'$n'.padLeft(12, '0')}';

/// The element id of the [n]th assignment the fake makes.
String _assignmentId(int n) => 'planned-assignments/4069/${_madeId(n)}';

/// Room 101, as the web client sends a location (`platformlName` is its own
/// spelling).
const _room101 = {
  'id': '10000000-0000-4000-8000-000000000101',
  'platformId': 4069,
  'platformlName': 'Springfield Academy',
  'type': 'mini-db-item',
};

/// The body the web client sends to create an assignment (dartschool#89, as
/// tried live): the own account as the only organiser, the [groups] as
/// participants, course informatica, the period of the hour from
/// [from] to [to] as a deadline due at [from], the name, an empty `info`,
/// the info texts, the type's id, the icon and room 101.
Map<String, Object?> _createBody({
  required String name,
  required String type,
  List<String> groups = const ['4069_2001', '4069_2002'],
  String? from,
  String? to,
  String publicInfo = '',
  String privateInfo = '',
}) {
  final due = from ?? plannerTime(2026, 11, 20, 11, 10);
  return {
    'organisers': {
      'users': [fakePlannerMe],
      'groups': <Object?>[],
    },
    'participants': {
      'groups': groups,
      'users': <Object?>[],
      'userRoles': <Object?>[],
    },
    'courses': [
      {'platformId': 4069, 'id': 'c0000000-0000-4000-8000-000000000005'},
    ],
    'period': {
      'dateTimeFrom': due,
      'dateTimeTo': to ?? plannerTime(2026, 11, 20, 12, 0),
      'wholeDay': false,
      'deadline': true,
      'dateTime': due,
    },
    'name': name,
    'info': '',
    'publicInfo': publicInfo,
    'privateInfo': privateInfo,
    'assignmentType': type,
    'icon': 'flags_red_yellow',
    'locations': [_room101],
  };
}

/// An assignment of the fake's own planner, to move to the trash.
FakePlannedElement _ownAssignment({
  String id = 'e0000000-0000-4000-8000-000000000020',
  bool hasLinkedEvaluation = false,
  Map<String, bool> capabilities = const {},
}) => FakePlannedElement(
  id: id,
  type: 'planned-assignments',
  name: 'Toets: lussen',
  from: plannerTime(2026, 11, 20, 11, 10),
  to: plannerTime(2026, 11, 20, 12, 0),
  deadline: true,
  organisers: [FakePlannerUser.me],
  groups: [fake6A1],
  courses: [fakeInformatica],
  rooms: [fakeRoom101],
  assignmentType: FakeAssignmentType.ko,
  visibleFrom: plannerTime(2026, 10, 1, 9, 0),
  hasLinkedEvaluation: hasLinkedEvaluation,
  capabilities: capabilities,
);

const _schoolTypes =
    'The school\'s assignment types are GO Grote Overhoring, GT Grote Taak, '
    'KO Kleine Overhoring, KT Kleine Taak, MB Meebrengen, V Voorbereiding.';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner
      ..loadCaptures()
      ..loadWorkloadCaptures();
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
        listClassAssignmentsTool(session, now: now),
        editPlannedElementTool(session),
        planAssignmentTool(session),
        trashAssignmentTool(session),
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

  /// The requests to [path] that reached the planner.
  List<({String method, String path, Map<String, String> query, Object? data})>
  postsToPlanner(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request,
  ];

  /// How many POSTs to [path] reached the fake Smartschool, also those it
  /// refused because the session was not accepted.
  int postsTo(String path) =>
      server.requests.where((request) => request == 'POST $path').length;

  bool isPostTo(RequestOptions request, String path) =>
      request.method == 'POST' && request.uri.path == path;

  /// The requests that reached the fake Smartschool between the first and
  /// the last POST to [path], also those it refused.
  List<String> betweenPostsTo(String path) {
    final first = server.requests.indexOf('POST $path');
    final last = server.requests.lastIndexOf('POST $path');
    return server.requests.sublist(first + 1, last);
  }

  /// The own assignments named [name] in the planner of [calendar].
  List<FakePlannedElement> named(String calendar, String name) => [
    for (final element in planner.calendars[calendar]!)
      if (element.type == 'planned-assignments' && element.name == name)
        element,
  ];

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

    test('as writes Claude Desktop asks approval for every time, not '
        'idempotent', () {
      for (final name in ['plan_assignment', 'trash_assignment']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isFalse, reason: name);
        expect(annotations.destructiveHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isFalse, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
      }
    });

    test('with their arguments', () {
      final plan = tools['plan_assignment']!.inputSchema;
      expect(plan.required, ['hour', 'type', 'name']);
      expect(plan.properties!.keys, [
        'hour',
        'type',
        'name',
        'public_info',
        'private_info',
        'classes',
      ]);
      expect(plan.properties!['classes'], {
        'type': 'array',
        'description': contains('Default: all classes of the hour'),
        'items': {'type': 'string'},
      });
      final trash = tools['trash_assignment']!.inputSchema;
      expect(trash.required, ['id']);
      expect(trash.properties!.keys, ['id']);
    });

    test('tell Claude that pupils see a new assignment at once, to check the '
        'class\'s tests first, to get the user\'s explicit confirmation, '
        'that only the own planner changes, that the trash can be restored, '
        'and never to repeat a write that may have been made', () {
      for (final name in ['plan_assignment', 'trash_assignment']) {
        final description = tools[name]!.description!;
        for (final part in [
          'after the user has explicitly confirmed it',
          'Only the user\'s own',
          'this tool refuses those',
          'do not call this tool again for',
          'read_planned_element',
        ]) {
          expect(description, contains(part), reason: '$name: $part');
        }
      }
      final plan = tools['plan_assignment']!.description!;
      for (final part in [
        'Pupils of the classes see a new assignment at once. Planning it does '
            'not send a notification; Smartschool\'s separate "aankondigen" '
            '(announce) is not offered.',
        'first check the other tests and tasks of the class(es) with '
            'list_class_assignments',
        'Show the user the class(es), the date and hour, the type, the name '
            'and the info',
        'list_planner (planner me)',
        'such as KO or Kleine Overhoring',
        'Private info is hidden from pupils, but colleagues who can see the '
            'assignment read it too.',
        'HTML in it is not interpreted',
        'as that could plan it twice',
        'edit_planned_element',
        'trash_assignment',
        '"plan een kleine overhoring over hoofdstuk 3 in 6WEWI1 dinsdag het '
            '3e uur"',
      ]) {
        expect(plan, contains(part));
      }
      final trash = tools['trash_assignment']!.description!;
      for (final part in [
        'It can be restored from the planner\'s trash in Smartschool for 30 '
            'days; this tool cannot restore it.',
        'say that it can be restored from the planner\'s trash in '
            'Smartschool',
        'an assignment with a linked Skore evaluation',
        'clear_lesson',
      ]) {
        expect(trash, contains(part));
      }
      // Editing an assignment goes through edit_planned_element (#53).
      expect(
        tools['edit_planned_element']!.description,
        allOf(
          contains('a lesson or an assignment'),
          contains(
            'Of an assignment (a test or task, such as one planned with '
            'plan_assignment) only the name and the info change here',
          ),
        ),
      );
      expect(
        tools['list_class_assignments']!.description,
        contains('plan_assignment plans the test the user chose'),
      );
    });
  });

  group('plan_assignment', () {
    test('plans an assignment in an own empty lesson hour once, with the '
        'request of dartschool#89 (answered 201), for the hour\'s classes, '
        'course, room and period, and gives it as saved with its id', () async {
      final id = _assignmentId(1);
      expect(
        await ok('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'KO',
          'name': ' Test: lussen ',
          'public_info': 'Leerstof: hoofdstuk 3',
          'private_info': 'Oefening 3 overslaan.',
        }),
        'Planned the assignment KO Kleine Overhoring "Test: lussen" on '
        'Friday 2026-11-20 11:10 (deadline) (6A1, 6A2, informatica), in the '
        'empty lesson hour on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, '
        'informatica), which stays as it is. Pupils of 6A1, 6A2 see it now; '
        'it was not announced.\n'
        'The assignment has the id $id: change its name or info with '
        'edit_planned_element, or move it to the trash with '
        'trash_assignment.\n'
        'For a few seconds after a change list_planner can still show the '
        'old state; read_planned_element shows the new state at once.\n'
        '\n'
        'Planner element $id\n'
        'Kind: assignment KO Kleine Overhoring\n'
        'Name: Test: lussen\n'
        'When: Friday 2026-11-20 11:10 (deadline)\n'
        'Course: informatica\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Jan Peeters\n'
        'Room: 101\n'
        'Visible to pupils from: 2026-10-02 16:30\n'
        'Announced: no\n'
        'Status: unresolved\n'
        '\n'
        'Public info (what pupils see):\n'
        'Leerstof: hoofdstuk 3\n'
        '\n'
        'Private info (hidden from pupils, but colleagues who can read this '
        'element see it too):\n'
        'Oefening 3 overslaan.',
      );

      expect(planner.writes, ['POST $_createPath']);
      final [create] = postsToPlanner(_createPath);
      expect(create.query, {'waitForRefresh': 'true'});
      expect(
        create.data,
        _createBody(
          name: 'Test: lussen',
          type: FakeAssignmentType.ko.id,
          publicInfo: '<p>Leerstof: hoofdstuk 3</p>',
          privateInfo: '<p>Oefening 3 overslaan.</p>',
        ),
      );
      // The hour stays; the assignment is in the planners of its classes,
      // of the user and of its room.
      expect(planner.elements, contains(fakeOwnSlot.ref));
      for (final calendar in [
        'user/$fakePlannerMe',
        'group/4069_2001',
        'group/4069_2002',
        fakeRoom101.planner,
      ]) {
        expect(named(calendar, 'Test: lussen'), hasLength(1));
      }
      expect(
        await ok('list_class_assignments', {
          'classes': ['group/4069_2001'],
          'from': '2026-11-20',
          'until': '2026-11-20',
        }),
        contains(
          'Friday 2026-11-20\n'
          '- 11:10 (deadline) | assignment KO Kleine Overhoring | Test: '
          'lussen | informatica | 6A1, 6A2 | by Jan Peeters | room 101 | id '
          '$id',
        ),
      );
      expect(
        await ok('list_planner', {'from': '2026-11-20', 'until': '2026-11-20'}),
        allOf(
          contains(
            '11:10 (deadline) | assignment KO Kleine Overhoring | Test: '
            'lussen | informatica | 6A1, 6A2 | room 101 | id $id',
          ),
          contains(
            '11:10–12:00 | empty lesson hour | informatica | 6A1, 6A2 | room '
            '101 | id ${fakeOwnSlot.ref}',
          ),
        ),
      );
    });

    test('plans in an own lesson, for one of its classes by name, of a type '
        'by its name: the lesson stays', () async {
      expect(
        await ok('plan_assignment', {
          'hour': 'id ${fakeOwnLesson.ref}',
          'type': ' kleine   TAAK ',
          'name': 'Programma: lussen',
          'classes': ['6a2'],
        }),
        allOf(
          startsWith(
            'Planned the assignment KT Kleine Taak "Programma: lussen" on '
            'Monday 2026-10-05 10:20 (deadline) (6A2, informatica), in the '
            'lesson "Lussen: for en while" on Monday 2026-10-05 10:20–11:10 '
            '(6A1, 6A2, informatica), which stays as it is. Pupils of 6A2 see '
            'it now; it was not announced.\n',
          ),
          contains('Public info (what pupils see):\n(none)\n'),
        ),
      );
      expect(
        postsToPlanner(_createPath).single.data,
        _createBody(
          name: 'Programma: lussen',
          type: FakeAssignmentType.kt.id,
          groups: ['4069_2002'],
          from: plannerTime(2026, 10, 5, 10, 20),
          to: plannerTime(2026, 10, 5, 11, 10),
        ),
      );
      expect(planner.elements, contains(fakeOwnLesson.ref));
      expect(named('group/4069_2002', 'Programma: lussen'), hasLength(1));
      expect(named('group/4069_2001', 'Programma: lussen'), isEmpty);
    });

    test('takes classes by planner id too, each once, and a type as the '
        'tools write it', () async {
      await ok('plan_assignment', {
        'hour': fakeOwnSlot.ref,
        'type': 'KO Kleine Overhoring',
        'name': 'Test',
        'classes': ['group/4069_2001', '6A1', '4069_2001'],
      });
      expect(
        (postsToPlanner(_createPath).single.data! as Map)['participants'],
        {
          'groups': ['4069_2001'],
          'users': <Object?>[],
          'userRoles': <Object?>[],
        },
      );
    });

    test('refuses classes that are not the hour\'s, without any write: it '
        'names the hour\'s classes', () async {
      expect(
        await error('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'KO',
          'name': 'Test',
          'classes': ['6A1', '6B1', 'group/4069_2003'],
        }),
        'classes holds "6B1" and "group/4069_2003", which are not classes of '
        'the empty lesson hour on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, '
        'informatica). Its classes are 6A1 (group/4069_2001) and 6A2 '
        '(group/4069_2002): name some of those, or leave classes out for all '
        'of them. Nothing was changed in the planner.',
      );
      expect(
        await error('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'KO',
          'name': 'Test',
          'classes': ['6WEWI1'],
        }),
        startsWith(
          'classes holds "6WEWI1", which is not a class of the empty lesson '
          'hour on Friday 2026-11-20',
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses a type that is not the school\'s, without any write: it '
        'lists the school\'s types', () async {
      expect(
        await error('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'Toets',
          'name': 'Test',
        }),
        'type "Toets" is not one of the school\'s assignment types: pass one by '
        'its abbreviation or its name. $_schoolTypes Nothing was changed in '
        'the planner.',
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses a colleague\'s hour or lesson, without any write: an '
        'assignment is only planned in an own hour', () async {
      for (final (element, organiser) in [
        (fakeSlot, 'Piet Peeters'),
        (fakeLesson, 'Wim Willems'),
      ]) {
        expect(
          await error('plan_assignment', {
            'hour': element.ref,
            'type': 'KO',
            'name': 'Test',
          }),
          allOf(
            startsWith('hour is not a lesson hour of your own planner: the '),
            contains('is organised by $organiser.'),
            endsWith(
              'Plan an assignment in one of your own lesson hours, as '
              'list_planner (planner me) shows them. Nothing was changed in '
              'the planner.',
            ),
          ),
          reason: element.ref,
        );
      }
      expect(
        await error('plan_assignment', {
          'hour': fakeSlot.ref,
          'type': 'KO',
          'name': 'Test',
        }),
        startsWith(
          'hour is not a lesson hour of your own planner: the empty lesson '
          'hour on Monday 2026-10-05 14:40–15:30 (6A1, 6B1, wiskunde) is '
          'organised by Piet Peeters.',
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses an own hour without classes or without a course, without '
        'any write', () async {
      final noClasses = FakePlannedElement(
        id: 'e0000000-0000-5000-8000-000000000031',
        type: 'planned-placeholders',
        from: plannerTime(2026, 11, 20, 13, 0),
        to: plannerTime(2026, 11, 20, 13, 50),
        organisers: [FakePlannerUser.me],
        courses: [fakeInformatica],
      );
      final noCourse = FakePlannedElement(
        id: 'e0000000-0000-5000-8000-000000000032',
        type: 'planned-placeholders',
        from: plannerTime(2026, 11, 20, 14, 0),
        to: plannerTime(2026, 11, 20, 14, 50),
        organisers: [FakePlannerUser.me],
        groups: [fake6A1],
      );
      for (final hour in [noClasses, noCourse]) {
        planner.add(hour, calendars: ['user/$fakePlannerMe']);
      }

      expect(
        await error('plan_assignment', {
          'hour': noClasses.ref,
          'type': 'KO',
          'name': 'Test',
        }),
        'The empty lesson hour on Friday 2026-11-20 13:00–13:50 (informatica) '
        'has no classes, so it cannot get an assignment: plan it in a lesson '
        'hour of the classes. Nothing was changed in the planner.',
      );
      expect(
        await error('plan_assignment', {
          'hour': noCourse.ref,
          'type': 'KO',
          'name': 'Test',
        }),
        'The empty lesson hour on Friday 2026-11-20 14:00–14:50 (6A1) has no '
        'course, which an assignment needs: plan it in a lesson hour of the '
        'course. Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses an assignment or another element as the hour, a malformed '
        'id, an empty type or name, and empty classes, before asking '
        'Smartschool', () async {
      final hour = fakeOwnSlot.ref;
      for (final (arguments, message) in [
        (
          {'hour': fakeAssignment.ref, 'type': 'KO', 'name': 'Test'},
          'hour must be a lesson hour of your own planner, as list_planner '
              '(planner me) shows it: an empty lesson hour '
              '(planned-placeholders/4069/…) or a lesson '
              '(planned-lessons/4069/…); ${fakeAssignment.ref} is an '
              'assignment. Nothing was sent.',
        ),
        (
          {'hour': fakeExcursion.ref, 'type': 'KO', 'name': 'Test'},
          'hour must be a lesson hour of your own planner, as list_planner '
              '(planner me) shows it: an empty lesson hour '
              '(planned-placeholders/4069/…) or a lesson '
              '(planned-lessons/4069/…); ${fakeExcursion.ref} is a '
              'planned-excursions. Nothing was sent.',
        ),
        (
          {'hour': 'dinsdag het 3e uur', 'type': 'KO', 'name': 'Test'},
          'hour must be the id of a planner element as list_planner shows it',
        ),
        (
          {'hour': hour, 'type': '  ', 'name': 'Test'},
          'type is empty: pass one of the school\'s assignment types by its '
              'abbreviation or name, such as KO or Kleine Overhoring '
              '(list_class_assignments lists them). Nothing was sent.',
        ),
        (
          {'hour': hour, 'type': 'KO', 'name': ' '},
          'name is empty: pass the name of the assignment. Nothing was sent.',
        ),
        (
          {'hour': hour, 'type': 'KO', 'name': 'Test', 'classes': <String>[]},
          'classes is empty: name some of the classes of the lesson hour, or '
              'leave classes out for all of them. Nothing was sent.',
        ),
        (
          {
            'hour': hour,
            'type': 'KO',
            'name': 'Test',
            'classes': ['6A1', ' '],
          },
          'each item of classes must be a class of the lesson hour, by its '
              'name as list_planner shows it (like 6A1) or its planner id '
              '(like group/4069_2001); " " is not. Nothing was sent.',
        ),
      ]) {
        expect(
          await error('plan_assignment', arguments),
          startsWith(message),
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
    });

    test(
      'passes on why the library refused the create before sending it: '
      'a type the school no longer has, after the session read the types',
      () async {
        // The session reads the school's types once, here.
        await ok('list_class_assignments', {
          'classes': ['group/4069_2001'],
        });
        planner.assignmentTypes.remove(FakeAssignmentType.ko);

        // In the tool's words, with the school's types as they are now,
        // which the server reads again (the refusal does not carry them,
        // yvanvds/dartschool#119).
        expect(
          await error('plan_assignment', {
            'hour': fakeOwnSlot.ref,
            'type': 'KO',
            'name': 'Test',
          }),
          'The planner refused the change before it was sent: type "KO" '
          'named the assignment type KO Kleine Overhoring, which is no longer '
          'one of the school\'s assignment types: they changed since the '
          'server read them. The school\'s assignment types are GO Grote '
          'Overhoring, GT Grote Taak, KT Kleine Taak, MB Meebrengen, V '
          'Voorbereiding. Ask the user which one to use instead, and pass it '
          'by its abbreviation or its name; list_class_assignments lists them '
          'too. Nothing was changed in the planner.',
        );
        expect(planner.writes, isEmpty);

        // Every tool on the session has the types as they are now.
        expect(
          await ok('list_class_assignments', {
            'classes': ['group/4069_2001'],
          }),
          contains(
            'Assignment types of the school: GO Grote Overhoring, GT Grote '
            'Taak, KT Kleine Taak, MB Meebrengen, V Voorbereiding.',
          ),
        );
        expect(
          await error('plan_assignment', {
            'hour': fakeOwnSlot.ref,
            'type': 'KO',
            'name': 'Test',
          }),
          startsWith(
            'type "KO" is not one of the school\'s assignment types: pass one '
            'by its abbreviation or its name. The school\'s assignment types '
            'are GO Grote Overhoring, GT Grote Taak, KT Kleine Taak, ',
          ),
        );
        expect(planner.writes, isEmpty);
      },
    );

    group('a create that the planner does not confirm is reported as maybe '
        'saved, with how to check it, and never sent again', () {
      test('the planner answers the create with an error', () async {
        planner.failing[_createPath] = 500;

        expect(
          await error('plan_assignment', {
            'hour': fakeOwnSlot.ref,
            'type': 'KO',
            'name': 'Test: lussen',
          }),
          'The assignment KO Kleine Overhoring "Test: lussen" for 6A1, 6A2 on '
          'Friday 2026-11-20 11:10 (deadline) may or may not have been saved: '
          'the change was sent, but the planner did not confirm it. Do not '
          'call plan_assignment again for it: first list the assignments of '
          '6A1, 6A2 on that day with list_class_assignments (classes '
          'group/4069_2001, group/4069_2002, from and until 2026-11-20): when '
          'your assignment "Test: lussen" is there, it was saved, possibly '
          'only shown after a few seconds; when it is not, nothing was saved. '
          'Then tell the user what you found.',
        );
        expect(postsTo(_createPath), 1);
        expect(server.logins, 1);
      });

      test('the connection drops after the create went out', () async {
        planner.lostAnswers.add(_createPath);

        expect(
          await error('plan_assignment', {
            'hour': fakeOwnSlot.ref,
            'type': 'KO',
            'name': 'Test: lussen',
            'classes': ['6A1'],
          }),
          allOf(
            startsWith(
              'The assignment KO Kleine Overhoring "Test: lussen" for 6A1 on '
              'Friday 2026-11-20 11:10 (deadline) may or may not have been '
              'saved',
            ),
            contains('(classes group/4069_2001, from and until 2026-11-20)'),
          ),
        );
        expect(postsTo(_createPath), 1);
        expect(server.logins, 1);
        // It was made: the check the result asks for finds it.
        expect(
          await ok('list_class_assignments', {
            'classes': ['group/4069_2001'],
            'from': '2026-11-20',
            'until': '2026-11-20',
          }),
          contains('Test: lussen'),
        );
      });
    });

    test('Smartschool refuses the session for the create, which the library '
        'does not send again: the session repeats the call, which reads the '
        'hour again and makes the assignment once', () async {
      server.expireSessionBefore((request) => isPostTo(request, _createPath));

      expect(
        await ok('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'KO',
          'name': 'Test: lussen',
        }),
        startsWith(
          'Planned the assignment KO Kleine Overhoring "Test: lussen" ',
        ),
      );
      expect(postsTo(_createPath), 2, reason: 'the refused one and the create');
      expect(
        betweenPostsTo(_createPath),
        contains('GET $_api/planned-placeholders/4069/${fakeOwnSlot.id}'),
        reason: 'the repeat reads the hour again',
      );
      expect(planner.writes, ['POST $_createPath'], reason: 'made once');
      expect(server.logins, 2);
      expect(named('group/4069_2001', 'Test: lussen'), hasLength(1));
    });

    test('never makes an assignment twice by itself: a second call makes a '
        'second one, which is why Claude is told not to repeat it', () async {
      for (var i = 0; i < 2; i++) {
        await ok('plan_assignment', {
          'hour': fakeOwnSlot.ref,
          'type': 'KO',
          'name': 'Test: lussen',
        });
      }
      expect(planner.writes, ['POST $_createPath', 'POST $_createPath']);
      expect(named('group/4069_2001', 'Test: lussen'), hasLength(2));
    });
  });

  group('trash_assignment', () {
    test('moves an own assignment to the planner\'s trash once, with the '
        'request of dartschool#89, and confirms the planner no longer has '
        'it', () async {
      final assignment = _ownAssignment();
      planner.add(
        assignment,
        calendars: ['user/$fakePlannerMe', 'group/4069_2001'],
      );

      expect(
        await ok('trash_assignment', {'id': assignment.ref}),
        'Moved the assignment KO Kleine Overhoring "Toets: lussen" on Friday '
        '2026-11-20 11:10 (deadline) (6A1, informatica) to the planner\'s '
        'trash: the planner no longer has it, and pupils no longer see it.\n'
        'It can be restored from the planner\'s trash in Smartschool for 30 '
        'days; this tool cannot restore it.\n'
        'For a few seconds after a change list_planner can still show the old '
        'state; read_planned_element shows the new state at once.',
      );
      final trashPath = _trashPath(assignment);
      expect(planner.writes, ['POST $trashPath']);
      expect([for (final post in postsToPlanner(trashPath)) post.data], [null]);
      expect(planner.trash, [assignment]);
      // The library read the assignment again after the trash: 404.
      final last = planner.requests.last;
      expect(
        '${last.method} ${last.path}',
        'GET $_api/planned-assignments/4069/${assignment.id}',
      );
      expect(
        await error('read_planned_element', {'id': assignment.ref}),
        startsWith('The planner has no element ${assignment.ref}'),
      );
      expect(
        await ok('list_class_assignments', {
          'classes': ['group/4069_2001'],
          'from': '2026-11-20',
          'until': '2026-11-20',
        }),
        startsWith(
          'Assignments (tests and tasks, by anyone) of 6A1 (group/4069_2001), '
          'from Friday 2026-11-20 to Friday 2026-11-20: no assignments.',
        ),
      );
    });

    test('refuses a colleague\'s assignment without any write: the library '
        'reads it again and refuses it', () async {
      expect(
        await error('trash_assignment', {'id': fakeAssignment.ref}),
        'The planner refused the change before it was sent: the assignment '
        'KO Kleine Overhoring "Test: hoofdstuk 3" on Tuesday 2026-10-06 08:30 '
        '(deadline) (6A1, Nederlands) is not in your own planner: it is '
        'organised by Piet Peeters. Only the elements of your own planner can '
        'be changed, as list_planner (planner me) shows them. Nothing was '
        'changed in the planner.',
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeAssignment.ref));
    });

    test('refuses an own assignment with a linked Skore evaluation, or one '
        'the planner does not let the user trash, without any write', () async {
      final evaluated = _ownAssignment(
        id: 'e0000000-0000-4000-8000-000000000041',
        hasLinkedEvaluation: true,
      );
      final locked = _ownAssignment(
        id: 'e0000000-0000-4000-8000-000000000042',
        capabilities: {'canUserTrash': false},
      );
      for (final assignment in [evaluated, locked]) {
        planner.add(assignment, calendars: ['user/$fakePlannerMe']);
      }

      const assignment =
          'assignment KO Kleine Overhoring "Toets: lussen" on Friday '
          '2026-11-20 11:10 (deadline) (6A1, informatica)';
      expect(
        await error('trash_assignment', {'id': evaluated.ref}),
        'The planner refused the change before it was sent: the $assignment '
        'is linked to a Skore evaluation, which has to be unlinked in '
        'Smartschool first: only then can it be moved to the trash. Nothing '
        'was changed in the planner.',
      );
      expect(
        await error('trash_assignment', {'id': locked.ref}),
        'The planner refused the change before it was sent: the planner does '
        'not let you trash the $assignment: its capability canUserTrash is '
        'not set. Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
    });

    test('an assignment that is gone: the planner has no such element any '
        'more, and nothing is sent', () async {
      final assignment = _ownAssignment();
      planner
        ..add(assignment, calendars: ['user/$fakePlannerMe'])
        ..trashElement(assignment.ref);

      expect(
        await error('trash_assignment', {'id': assignment.ref}),
        allOf(
          startsWith(
            'The planner has no element ${assignment.ref} (any more).',
          ),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses a lesson, an empty lesson hour, another element and a '
        'malformed id, before asking Smartschool', () async {
      for (final (id, message) in [
        (
          fakeOwnLesson.ref,
          'id must be an assignment of your own planner, like '
              'planned-assignments/4069/…; ${fakeOwnLesson.ref} is a lesson, '
              'not an assignment: empty its lesson hour with clear_lesson. '
              'Nothing was sent.',
        ),
        (
          fakeOwnSlot.ref,
          'id must be an assignment of your own planner, like '
              'planned-assignments/4069/…; ${fakeOwnSlot.ref} is an empty '
              'lesson hour, not an assignment. Nothing was sent.',
        ),
        (
          fakeExcursion.ref,
          'id must be an assignment of your own planner, like '
              'planned-assignments/4069/…; ${fakeExcursion.ref} is a '
              'planned-excursions, not an assignment. Nothing was sent.',
        ),
        (
          'Toets: lussen',
          'id must be the id of a planner element as list_planner shows it',
        ),
      ]) {
        expect(
          await error('trash_assignment', {'id': id}),
          startsWith(message),
          reason: id,
        );
      }
      expect(server.requests, isEmpty);
    });

    group('a trash that the planner does not confirm is reported as maybe '
        'done, and never sent again', () {
      late FakePlannedElement assignment;

      setUp(() {
        assignment = _ownAssignment();
        planner.add(assignment, calendars: ['user/$fakePlannerMe']);
      });

      test('the planner answers the trash with an error', () async {
        planner.failing[_trashPath(assignment)] = 500;

        expect(
          await error('trash_assignment', {'id': assignment.ref}),
          'The assignment KO Kleine Overhoring "Toets: lussen" on Friday '
          '2026-11-20 11:10 (deadline) (6A1, informatica) may or may not have '
          'been moved to the trash: the change was sent, but the planner did '
          'not confirm it. Do not call trash_assignment again for it: first '
          'read the assignment with read_planned_element (id '
          '${assignment.ref}): when the planner no longer has it, it is in '
          'the trash; when it is still there, it was not moved. Then tell the '
          'user what you found.',
        );
        expect(postsTo(_trashPath(assignment)), 1);
        expect(server.logins, 1);
        expect(planner.elements, contains(assignment.ref));
      });

      test('the connection drops after the trash went out', () async {
        planner.lostAnswers.add(_trashPath(assignment));

        expect(
          await error('trash_assignment', {'id': assignment.ref}),
          contains('may or may not have been moved to the trash'),
        );
        expect(postsTo(_trashPath(assignment)), 1);
        expect(server.logins, 1);
        // It was trashed: the check the result asks for tells.
        expect(
          await error('read_planned_element', {'id': assignment.ref}),
          startsWith('The planner has no element ${assignment.ref}'),
        );
      });
    });

    test('Smartschool refuses the session for the trash, which the library '
        'does not send again: the session repeats the call, which reads the '
        'assignment again and trashes it once', () async {
      final assignment = _ownAssignment();
      planner.add(assignment, calendars: ['user/$fakePlannerMe']);
      final trashPath = _trashPath(assignment);
      server.expireSessionBefore((request) => isPostTo(request, trashPath));

      expect(
        await ok('trash_assignment', {'id': assignment.ref}),
        startsWith(
          'Moved the assignment KO Kleine Overhoring "Toets: lussen" ',
        ),
      );
      expect(postsTo(trashPath), 2, reason: 'the refused one and the trash');
      expect(
        betweenPostsTo(trashPath),
        contains('GET $_api/planned-assignments/4069/${assignment.id}'),
        reason: 'the repeat reads the assignment again',
      );
      expect(planner.writes, ['POST $trashPath'], reason: 'trashed once');
      expect(planner.trash, [assignment]);
      expect(server.logins, 2);
    });
  });

  test('a colleague\'s assignment can be neither changed nor moved to the '
      'trash', () async {
    expect(
      await error('edit_planned_element', {
        'id': fakeAssignment.ref,
        'name': 'Overgenomen',
      }),
      contains('is not in your own planner: it is organised by Piet Peeters'),
    );
    expect(
      await error('trash_assignment', {'id': fakeAssignment.ref}),
      contains('is not in your own planner: it is organised by Piet Peeters'),
    );
    expect(planner.writes, isEmpty);
    expect(
      await ok('read_planned_element', {'id': fakeAssignment.ref}),
      contains('Name: Test: hoofdstuk 3\n'),
    );
  });

  test('the flow of the issue: check the class\'s tests, find the own hour, '
      'plan a test, read it, change it with edit_planned_element, and move '
      'it to the trash', () async {
    expect(
      await ok('list_class_assignments', {
        'classes': ['group/4069_2001'],
        'from': '2026-11-16',
        'until': '2026-11-20',
      }),
      contains('no assignments'),
    );
    expect(
      await ok('list_planner', {
        'from': '2026-11-20',
        'until': '2026-11-20',
        'types': ['empty_lesson_hours'],
      }),
      contains('id ${fakeOwnSlot.ref}'),
    );

    final planned = await ok('plan_assignment', {
      'hour': fakeOwnSlot.ref,
      'type': 'KO',
      'name': '[test] Kleine overhoring hoofdstuk 3',
      'public_info': 'Leerstof: hoofdstuk 3',
      'private_info': 'Versie A en B',
      'classes': ['6A1'],
    });
    final id = RegExp(
      r'The assignment has the id (\S+):',
    ).firstMatch(planned)![1]!;
    expect(id, _assignmentId(1));

    expect(
      await ok('read_planned_element', {'id': id}),
      allOf(
        contains('Kind: assignment KO Kleine Overhoring\n'),
        contains('When: Friday 2026-11-20 11:10 (deadline)\n'),
        contains('Classes: 6A1\n'),
        endsWith('Versie A en B'),
      ),
    );

    expect(
      await ok('edit_planned_element', {
        'id': id,
        'name': 'Kleine overhoring: hoofdstuk 3 en 4',
        'public_info': 'Leerstof: hoofdstuk 3 en 4',
      }),
      startsWith(
        'Changed the name and the public info of the assignment KO Kleine '
        'Overhoring "[test] Kleine overhoring hoofdstuk 3" on Friday '
        '2026-11-20 11:10 (deadline) (6A1, informatica).\n',
      ),
    );
    expect(
      await ok('read_planned_element', {'id': id}),
      allOf(
        contains('Name: Kleine overhoring: hoofdstuk 3 en 4\n'),
        contains(
          'Public info (what pupils see):\nLeerstof: hoofdstuk 3 en 4\n',
        ),
      ),
    );

    expect(
      await ok('trash_assignment', {'id': id}),
      startsWith(
        'Moved the assignment KO Kleine Overhoring "Kleine overhoring: '
        'hoofdstuk 3 en 4" on Friday 2026-11-20 11:10 (deadline) (6A1, '
        'informatica) to the planner\'s trash',
      ),
    );
    expect(
      await error('read_planned_element', {'id': id}),
      startsWith('The planner has no element $id'),
    );

    expect(planner.writes, [
      'POST $_createPath',
      'POST $_api/$id/rename',
      'POST $_api/$id/change-public-info',
      'POST $_api/$id/trash',
    ]);
    expect(postsToPlanner('$_api/$id/rename').single.data, {
      'newName': 'Kleine overhoring: hoofdstuk 3 en 4',
    });
    expect(postsToPlanner('$_api/$id/change-public-info').single.data, {
      'newInfo': '<p>Leerstof: hoofdstuk 3 en 4</p>',
    });
    expect(planner.elements, contains(fakeOwnSlot.ref));
  });
}
