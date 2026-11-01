/// Setting learning goals (#187): the `goals` of `create_lesfiche`,
/// `edit_lesfiche` and `edit_planned_element`, called over MCP on the real
/// server, session and library, against a fake Smartschool whose Lesfiches
/// module and planner store the goals of a goal write as sent
/// (`change-goals`, the create's `goals`: dartschool#223 and #226), and whose
/// goal selector (`test/support/fake_goals.dart`) checks and names them.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/edit_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/edit_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_curriculum_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// A goal of the eindtermen that the selector does not have.
const _madeUpGoalId = 'f0000000-0000-4000-8000-000000000099';

/// A goal of LLinkid, whose curriculum the selector does not read.
const _llinkidPlanId = 'a0000000-0000-4000-8000-000000000001';
const _llinkidGoalId = 'a0000000-0000-4000-8000-000000000002';

final _goal1 = fakeGoalRef(fakeGoal1Id, fakeEindtermenId, fakeEindtermenType);
final _miniGoal2 = fakeGoalRef(fakeMiniGoal2Id, fakeMiniDbId, 'miniDB');
final _madeUp = fakeGoalRef(
  _madeUpGoalId,
  fakeEindtermenId,
  fakeEindtermenType,
);
final _llinkid = fakeGoalRef(_llinkidGoalId, _llinkidPlanId, 'llinkid');

/// [_goal1] and [_miniGoal2] as the results name them.
const _goal1Line =
    '- Eindtermen derde graad, voorbeeld: Competenties voorbeeld > 01.01 De '
    'leerlingen passen een algoritme toe & meer. | id $fakeGoal1Id, '
    'leerplanId $fakeEindtermenId, type $fakeEindtermenType';
const _miniGoal2Line =
    '- Digitale vaardigheden, voorbeeld: GFL 1 Digitaal communiceren > Het '
    'platform > Je kan bestanden delen | id $fakeMiniGoal2Id, leerplanId '
    '$fakeMiniDbId, type miniDB';
const _llinkidLine =
    '- unknown to the goal selector (an id it does not have, or a goal of a '
    'source it does not read, such as LLinkid) | id $_llinkidGoalId, '
    'leerplanId $_llinkidPlanId, type llinkid';

/// A lesson lesfiche with a goal of the eindtermen and one of LLinkid.
final _lesfiche = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000041',
  name: 'Algoritmen',
  goals: [_goal1, _llinkid],
);

final _lesfichePath = fakeLesficheDetailPath(_lesfiche);
final _lesficheGoalsPath = '$_lesfichePath/change-goals';
final _lessonGoalsPath = '/planner/api/v1/${fakeOwnLesson.ref}/change-goals';

/// An assignment of the own planner.
final _ownAssignment = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000020',
  type: 'planned-assignments',
  name: 'Toets: lussen',
  from: plannerTime(2026, 11, 20, 11, 10),
  to: plannerTime(2026, 11, 20, 12, 0),
  deadline: true,
  organisers: [FakePlannerUser.me],
  groups: [fake6A1],
  courses: [fakeInformatica],
  assignmentType: FakeAssignmentType.ko,
);

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late FakeGoalSelector selector;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    selector = server.goals..loadSample();
    planner = server.planner
      ..lesfiches.add(_lesfiche)
      ..add(fakeOwnLesson, calendars: ['user/$fakePlannerMe'])
      ..add(_ownAssignment, calendars: ['user/$fakePlannerMe']);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        readLesficheTool(session),
        readCurriculumTool(session),
        createLesficheTool(session),
        editLesficheTool(session),
        readPlannedElementTool(session),
        editPlannedElementTool(session),
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

  /// Opens the session and forgets the requests so far.
  Future<void> openSession() async {
    await ok('list_lesfiches', {});
    server.requests.clear();
    planner.requests.clear();
    selector.requests.clear();
  }

  /// The POSTs that reached the Lesfiches module or the planner.
  List<String> posts() => [
    for (final request in planner.requests)
      if (request.method == 'POST') request.path,
  ];

  /// The goals of each check or naming the selector was asked, as their ids.
  List<List<String>> selectorAsked() => [
    for (final request in selector.requests)
      if (request.method == 'POST')
        [
          for (final goal
              in ((request.data! as Map)['selection'] as List).cast<Map>())
            goal['id'] as String,
        ],
  ];

  FakeLesfiche lesficheNow(String id) =>
      planner.lesfiches.singleWhere((each) => each.id == id);

  test('the tools take goals, and say that the list replaces them', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in [
      'create_lesfiche',
      'edit_lesfiche',
      'edit_planned_element',
    ]) {
      final tool = tools[name]!;
      final goals = tool.inputSchema.properties!['goals']! as ListSchema;
      final item = goals.items! as ObjectSchema;
      expect(item.required, ['id', 'leerplanId', 'type'], reason: name);
      expect(tool.description, contains('read_curriculum'), reason: name);
      expect(tool.description, contains('goal selector does not know'));
    }
    for (final name in ['edit_lesfiche', 'edit_planned_element']) {
      expect(
        tools[name]!.description,
        contains(
          'The list replaces all the goals: to add a goal, pass the goals it '
          'has now',
        ),
      );
    }
  });

  group('create_lesfiche', () {
    test('makes a lesfiche with the goals, checked and named by the goal '
        'selector, as read_curriculum shows them', () async {
      // The goal as Claude finds it: its id on its line, the leerplanId and
      // type in the header of read_curriculum.
      final curriculum = await ok('read_curriculum', {
        'curriculum': fakeMiniDbId,
      });
      expect(curriculum, contains('leerplanId $fakeMiniDbId and type miniDB'));
      expect(
        curriculum,
        contains('Je kan bestanden delen | id $fakeMiniGoal2Id'),
      );
      await openSession();

      final text = await ok('create_lesfiche', {
        'name': 'Lussen',
        'goals': [_goal1, _miniGoal2],
      });
      expect(text, contains('Goals:\n$_goal1Line\n$_miniGoal2Line\n'));
      final made = lesficheNow(fakeNewLesficheId(1));
      expect(made.goals, [_goal1, _miniGoal2]);
      final create = planner.requests.singleWhere(
        (request) => request.path == fakeLesficheCreatePath(),
      );
      expect((create.data! as Map)['goals'], [
        {..._goal1, 'goalId': fakeGoal1Id},
        {..._miniGoal2, 'goalId': fakeMiniGoal2Id},
      ]);
      // One check, before the create, which also names the goals.
      expect(selectorAsked(), [
        [fakeGoal1Id, fakeMiniGoal2Id],
      ]);
      expect(selector.requests.single.path, contains('/lesson-content/'));

      expect(
        await ok('read_lesfiche', {'lesfiche': made.id}),
        contains('Goals:\n$_goal1Line\n$_miniGoal2Line\n'),
      );
    });

    test('without goals sends none, and asks the selector nothing', () async {
      await openSession();
      final text = await ok('create_lesfiche', {'name': 'Lussen'});
      expect(text, contains('Goals: none'));
      expect(selector.requests, isEmpty);
    });

    test('refuses a made-up goal, a heading, a goal of another type and an '
        'LLinkid goal before anything is made', () async {
      await openSession();
      for (final (goal, why) in [
        (_madeUp, 'its curriculum has no goal with that id that can be picked'),
        (
          fakeGoalRef(fakeDomainId, fakeEindtermenId, fakeEindtermenType),
          'its curriculum has no goal with that id that can be picked',
        ),
        (
          fakeGoalRef(fakeMiniGoal2Id, fakeMiniDbId, fakeEindtermenType),
          'its curriculum has the type miniDB, not $fakeEindtermenType',
        ),
        (
          _llinkid,
          'the goal selector has no such goal (no curriculum with that '
              'leerplanId has it)',
        ),
      ]) {
        final text = await error('create_lesfiche', {
          'name': 'Lussen',
          'goals': [_goal1, goal],
        });
        expect(
          text,
          'A goal is not known to the goal selector as given, so it would be '
          'stored as a goal without a name. Nothing was sent.\n'
          '- id ${goal['id']}, leerplanId ${goal['leerplanId']}, type '
          '${goal['type']}: $why\n'
          'Find the goal with list_curricula and read_curriculum, and pass '
          'its id with the leerplanId and type of the curriculum\'s header.',
        );
      }
      expect(posts(), isEmpty);
      expect(planner.lesfiches, [_lesfiche]);
    });

    test('refuses goals that are not {id, leerplanId, type} with a goal id, '
        'without asking anyone', () async {
      await openSession();
      for (final (goals, message) in [
        (
          [fakeGoalRef(fakeGoal1Id, ' ', fakeEindtermenType)],
          'Goal 1 of goals has no leerplanId: pass each goal as {id, '
              'leerplanId, type}, as read_curriculum shows them (the id at the '
              'end of the goal\'s line, the leerplanId and type in its '
              'header). Nothing was sent.',
        ),
        (
          [fakeGoalRef('01.01', fakeEindtermenId, fakeEindtermenType)],
          'Goal 1 of goals has the id "01.01", which is not the id of a '
              'goal: take it from read_curriculum, where it ends the goal\'s '
              'line, like f0000000-0000-4000-8000-000000000011. Nothing was '
              'sent.',
        ),
        (
          [_goal1, fakeGoalRef(fakeGoal1Id, fakeMiniDbId, 'miniDB')],
          'Goal 2 of goals has the id of another goal of the list, with '
              'another leerplanId or type: id $fakeGoal1Id, leerplanId '
              '$fakeMiniDbId, type miniDB and id $fakeGoal1Id, leerplanId '
              '$fakeEindtermenId, type $fakeEindtermenType. Take them from '
              'read_curriculum. Nothing was sent.',
        ),
      ]) {
        expect(
          await error('create_lesfiche', {'name': 'Lussen', 'goals': goals}),
          message,
        );
      }
      expect(planner.requests, isEmpty);
      expect(selector.requests, isEmpty);
    });

    test('makes nothing when the selector cannot check the goals', () async {
      await openSession();
      selector.failWith = 500;
      expect(
        await error('create_lesfiche', {
          'name': 'Lussen',
          'goals': [_goal1],
        }),
        'The goals could not be checked: The goal selector gave an answer the '
        'server could not use (HTTP 500). Try again in a moment; the '
        'technical details are in the server log. Nothing was sent.',
      );
      expect(posts(), isEmpty);
    });
  });

  group('edit_lesfiche', () {
    test('adds a goal to the goals it has, keeping one of LLinkid that the '
        'selector cannot check, and names them', () async {
      await openSession();
      final text = await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'goals': [_goal1, _llinkid, _miniGoal2],
      });
      expect(text, startsWith('Changed the goals of the lesson lesfiche'));
      expect(
        text,
        contains('Goals:\n$_goal1Line\n$_llinkidLine\n$_miniGoal2Line\n'),
      );
      expect(lesficheNow(_lesfiche.id).goals, [_goal1, _llinkid, _miniGoal2]);
      final sent = planner.requests.singleWhere(
        (request) => request.path == _lesficheGoalsPath,
      );
      expect((sent.data! as Map)['newGoals'], [
        {..._goal1, 'goalId': fakeGoal1Id},
        {..._llinkid, 'goalId': _llinkidGoalId},
        {..._miniGoal2, 'goalId': fakeMiniGoal2Id},
      ]);
      // The check asks for the new goal only; the read back names them all.
      expect(selectorAsked(), [
        [fakeMiniGoal2Id],
        [fakeGoal1Id, _llinkidGoalId, fakeMiniGoal2Id],
      ]);
    });

    test('clears the goals with an empty list, and changes nothing for the '
        'goals it has', () async {
      await openSession();
      expect(
        await ok('edit_lesfiche', {
          'lesfiche': _lesfiche.id,
          'goals': [_llinkid, _goal1],
        }),
        startsWith('Nothing to change: the lesson lesfiche'),
      );
      final cleared = await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'goals': <Object>[],
      });
      expect(cleared, startsWith('Changed the goals of the lesson lesfiche'));
      expect(cleared, contains('Goals: none'));
      expect(lesficheNow(_lesfiche.id).goals, isEmpty);
    });

    test('refuses a made-up goal before anything is sent', () async {
      await openSession();
      final text = await error('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'name': 'Algoritmen en lussen',
        'goals': [_goal1, _madeUp],
      });
      expect(
        text,
        startsWith(
          'A goal is not known to the goal selector as given, so it would be '
          'stored as a goal without a name. Nothing was sent.\n'
          '- id $_madeUpGoalId',
        ),
      );
      expect(posts(), isEmpty);
      expect(lesficheNow(_lesfiche.id).name, 'Algoritmen');
    });
  });

  group('edit_planned_element', () {
    test('sets the goals of an own lesson, checked at the planner\'s place '
        'of the selector, and names them', () async {
      await openSession();
      final text = await ok('edit_planned_element', {
        'id': fakeOwnLesson.ref,
        'goals': [_miniGoal2, _goal1],
      });
      expect(text, startsWith('Changed the goals of the lesson'));
      expect(text, contains('Goals:\n$_miniGoal2Line\n$_goal1Line\n'));
      expect(planner.elements[fakeOwnLesson.ref]!.goals, [_miniGoal2, _goal1]);
      final sent = planner.requests.singleWhere(
        (request) => request.path == _lessonGoalsPath,
      );
      expect((sent.data! as Map)['goals'], [
        {..._miniGoal2, 'goalId': fakeMiniGoal2Id},
        {..._goal1, 'goalId': fakeGoal1Id},
      ]);
      expect(selectorAsked(), hasLength(2));
      for (final request in selector.requests) {
        expect(request.path, contains('/planner-lesson-content/'));
      }

      expect(
        await ok('read_planned_element', {'id': fakeOwnLesson.ref}),
        contains('Goals:\n$_miniGoal2Line\n$_goal1Line\n'),
      );

      final cleared = await ok('edit_planned_element', {
        'id': fakeOwnLesson.ref,
        'goals': <Object>[],
      });
      expect(cleared, startsWith('Changed the goals of the lesson'));
      expect(cleared, contains('Goals: none'));
      expect(planner.elements[fakeOwnLesson.ref]!.goals, isEmpty);
    });

    test('does not name goals when they do not change', () async {
      await openSession();
      final text = await ok('edit_planned_element', {
        'id': fakeOwnLesson.ref,
        'name': 'Lussen',
      });
      expect(text, isNot(contains('Goals')));
      expect(selector.requests, isEmpty);
    });

    test('refuses a made-up goal, and goals of an assignment, before '
        'anything is sent', () async {
      await openSession();
      expect(
        await error('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': 'Lussen',
          'goals': [_madeUp],
        }),
        startsWith(
          'A goal is not known to the goal selector as given, so it would be '
          'stored as a goal without a name. Nothing was sent.\n'
          '- id $_madeUpGoalId',
        ),
      );
      expect(
        await error('edit_planned_element', {
          'id': _ownAssignment.ref,
          'goals': [_goal1],
        }),
        'goals are for a lesson only; ${_ownAssignment.ref} is an assignment, '
        'whose goals this server does not change. Nothing was sent.',
      );
      expect(posts(), isEmpty);
      expect(planner.elements[fakeOwnLesson.ref]!.name, fakeOwnLesson.name);
    });

    test('says when the planner does not confirm the goals', () async {
      await openSession();
      planner.failing[_lessonGoalsPath] = 500;
      final text = await error('edit_planned_element', {
        'id': fakeOwnLesson.ref,
        'goals': [_goal1],
      });
      expect(text, startsWith('The change of the goals of the lesson'));
      expect(text, contains('may or may not have been'));
      expect(
        text,
        contains(
          'read the element with read_planned_element (id '
          '${fakeOwnLesson.ref}) and compare the goals',
        ),
      );
    });
  });
}
