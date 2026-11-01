/// The learning goals (#186): `list_curricula` and `read_curriculum`, and
/// the goals that `read_lesfiche` and `read_planned_element` show, called
/// over MCP on the real server, session and library, against a fake
/// Smartschool whose goal selector (`test/support/fake_goals.dart`) serves
/// the routes of dartschool#222 in the shapes of dartschool's tests, and
/// whose Lesfiches module and planner store goals
/// (dartschool#223, dartschool#226).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_curricula_tool.dart';
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

const _unknown =
    'unknown to the goal selector (an id it does not have, or a goal of a '
    'source it does not read, such as LLinkid)';

/// The goals of [_goal1], [_miniGoal2], [_madeUp] and [_llinkid] as the
/// reads show them.
const _goalLines =
    'Goals:\n'
    '- Eindtermen derde graad, voorbeeld: Competenties voorbeeld > 01.01 De '
    'leerlingen passen een algoritme toe & meer. | id $fakeGoal1Id, '
    'leerplanId $fakeEindtermenId, type $fakeEindtermenType\n'
    '- Digitale vaardigheden, voorbeeld: GFL 1 Digitaal communiceren > Het '
    'platform > Je kan bestanden delen | id $fakeMiniGoal2Id, leerplanId '
    '$fakeMiniDbId, type miniDB\n'
    '- $_unknown | id $_madeUpGoalId, leerplanId $fakeEindtermenId, type '
    '$fakeEindtermenType\n'
    '- $_unknown | id $_llinkidGoalId, leerplanId $_llinkidPlanId, type '
    'llinkid\n';

/// A lesson lesfiche with the four goals.
final _lesfiche = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000041',
  name: 'Algoritmen',
  goals: [_goal1, _miniGoal2, _madeUp, _llinkid],
);

/// An own lesson with the four goals.
final _lesson = fakeOwnLesson.withChanges(
  goals: [_goal1, _miniGoal2, _madeUp, _llinkid],
);

void main() {
  late FakeSmartschool server;
  late FakeGoalSelector selector;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    selector = server.goals..loadSample();
    server.planner
      ..lesfiches.add(_lesfiche)
      ..add(_lesson, calendars: ['user/$fakePlannerMe'])
      ..add(fakeOwnSlot, calendars: ['user/$fakePlannerMe']);
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listCurriculaTool(session),
        readCurriculumTool(session),
        readLesficheTool(session),
        readPlannedElementTool(session),
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

  /// The selector's requests, as `METHOD path`.
  List<String> selectorRequests() => [
    for (final request in selector.requests)
      '${request.method} ${request.path}',
  ];

  test(
    'the tools are read-only and idempotent, and point to each other',
    () async {
      final tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
      for (final name in ['list_curricula', 'read_curriculum']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isTrue, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
        expect(annotations.destructiveHint, isNot(true), reason: name);
      }
      expect(tools['list_curricula']!.description, contains('read_curriculum'));
      expect(tools['read_curriculum']!.description, contains('list_curricula'));
      expect(tools['read_curriculum']!.inputSchema.required, ['curriculum']);
      expect(tools['read_lesfiche']!.description, contains('leerplanId'));
      expect(
        tools['read_planned_element']!.description,
        contains('leerplanId'),
      );
    },
  );

  group('list_curricula', () {
    test('lists the curricula in the selector\'s groups and order, with '
        'their ids', () async {
      expect(
        await ok('list_curricula', {}),
        'The 3 curricula of the goal selector, in its groups:\n'
        'Overheid SO:\n'
        '- Eindtermen derde graad, voorbeeld | id $fakeEindtermenId\n'
        '- Godsdienst, voorbeeld | id $fakeGodsdienstId\n'
        'Minidatabanken:\n'
        '- Digitale vaardigheden, voorbeeld | hidden in the selector | a '
        'favourite | id $fakeMiniDbId\n'
        'read_curriculum reads the goals of one, by its id.',
      );
      expect(selectorRequests(), [
        matches(RegExp(r'^GET .*/lesson-content/list/\d{4}-\d\d-\d\d$')),
      ]);
    });

    test('filters by words in the title, leaving out empty groups', () async {
      expect(
        await ok('list_curricula', {'query': 'DERDE eindtermen'}),
        '1 curriculum whose title holds "DERDE eindtermen", of the 3 '
        'curricula of the goal selector, in its groups:\n'
        'Overheid SO:\n'
        '- Eindtermen derde graad, voorbeeld | id $fakeEindtermenId\n'
        'read_curriculum reads the goals of one, by its id.',
      );
      expect(
        await ok('list_curricula', {'query': 'wiskunde'}),
        'No curriculum whose title holds "wiskunde" (of the 3 curricula of '
        'the goal selector).',
      );
    });

    test('says so when the selector refuses the read, or gives an answer '
        'it cannot use', () async {
      selector.failWith = 403;
      expect(
        await error('list_curricula', {}),
        contains(
          'The goal selector of Smartschool refused the read to your '
          'account.',
        ),
      );
      selector.failWith = 500;
      expect(
        await error('list_curricula', {}),
        'The goal selector gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log.',
      );
    });
  });

  group('read_curriculum', () {
    test('lists the goals under their headings, with the fields they are '
        'stored with', () async {
      expect(
        await ok('read_curriculum', {'curriculum': fakeEindtermenId}),
        'Curriculum "Eindtermen derde graad, voorbeeld" | id '
        '$fakeEindtermenId\n'
        'Each goal of it is stored with its own id, leerplanId '
        '$fakeEindtermenId and type $fakeEindtermenType.\n'
        'Its 4 goals, under their headings:\n'
        'Competenties voorbeeld\n'
        '  - 01.01 De leerlingen passen een algoritme toe & meer. | id '
        '$fakeGoal1Id\n'
        '  - 01.02 Een oud doel. (deprecated) | id $fakeGoal2Id\n'
        '  - 01.03 Een doel van basisgeletterdheid. (basic literacy) | id '
        '$fakeBasicGoalId\n'
        '  Een cluster\n'
        '    - 01.04 Een doel in een cluster. | id $fakeGoal3Id',
      );
      expect(selectorRequests(), [
        matches(
          RegExp(
            '^GET .*/lesson-content/$fakeEindtermenId/'
            r'\d{4}-\d\d-\d\d$',
          ),
        ),
      ]);
    });

    test('a mini-database, with numbered headings and a subheading', () async {
      expect(
        await ok('read_curriculum', {'curriculum': fakeMiniDbId}),
        'Curriculum "Digitale vaardigheden, voorbeeld" | id $fakeMiniDbId\n'
        'Each goal of it is stored with its own id, leerplanId '
        '$fakeMiniDbId and type miniDB.\n'
        'Its 2 goals, under their headings:\n'
        'GFL 1 Digitaal communiceren\n'
        '  Het platform\n'
        '    - Je kan navigeren | id $fakeMiniGoal1Id\n'
        '    - Je kan bestanden delen | id $fakeMiniGoal2Id',
      );
    });

    test('finds goals by words in their number, text or headings', () async {
      expect(
        await ok('read_curriculum', {
          'curriculum': fakeEindtermenId,
          'query': 'cluster 01.04',
        }),
        endsWith(
          '1 of its 4 goals hold "cluster 01.04", under their headings:\n'
          'Competenties voorbeeld\n'
          '  Een cluster\n'
          '    - 01.04 Een doel in een cluster. | id $fakeGoal3Id',
        ),
      );
      expect(
        await ok('read_curriculum', {
          'curriculum': fakeMiniDbId,
          'query': 'platform DELEN',
        }),
        endsWith('    - Je kan bestanden delen | id $fakeMiniGoal2Id'),
      );
      expect(
        await ok('read_curriculum', {
          'curriculum': fakeEindtermenId,
          'query': 'breuken',
        }),
        endsWith(
          'None of its 4 goals holds "breuken" in its number, its text or '
          'its headings.',
        ),
      );
    });

    test('a curriculum without goals says so', () async {
      expect(
        await ok('read_curriculum', {'curriculum': fakeGodsdienstId}),
        endsWith('It has no goals that can be picked.'),
      );
    });

    test('an id the selector does not have, or that cannot be one, points '
        'to list_curricula', () async {
      const id = 'e0000000-0000-4000-8000-00000000dead';
      expect(
        await error('read_curriculum', {'curriculum': id}),
        'The goal selector has no curriculum with id $id. Take the id from '
        'list_curricula.',
      );
      selector.requests.clear();
      expect(
        await error('read_curriculum', {'curriculum': '../list'}),
        'The goal selector has no curriculum with id ../list. Take the id '
        'from list_curricula.',
      );
      expect(selectorRequests(), isEmpty, reason: 'nothing is sent');
      expect(
        await error('read_curriculum', {'curriculum': '  '}),
        contains('curriculum is empty'),
      );
    });
  });

  group('read_lesfiche', () {
    test('names the goals of a lesfiche, and says which are unknown', () async {
      final text = await ok('read_lesfiche', {'lesfiche': _lesfiche.id});
      expect(text, contains('\nAttachments: none\n$_goalLines\n'));
      final resolve = selector.requests.single;
      expect(resolve.method, 'POST');
      expect(
        resolve.path,
        matches(RegExp(r'/lesson-content/\d{4}-\d\d-\d\d$')),
      );
      expect(resolve.data, {
        'selection': [
          for (final goal in [_goal1, _miniGoal2, _madeUp, _llinkid])
            {...goal, 'goalId': goal['id']},
        ],
        'isView': true,
      });
    });

    test('a lesfiche without goals reads "Goals: none", without asking the '
        'selector', () async {
      server.planner.lesfiches.add(
        const FakeLesfiche(
          id: 'b0000000-0000-4000-8000-000000000042',
          name: 'Zonder doelen',
        ),
      );
      expect(
        await ok('read_lesfiche', {
          'lesfiche': 'b0000000-0000-4000-8000-000000000042',
        }),
        contains('\nAttachments: none\nGoals: none\n'),
      );
      expect(selector.requests, isEmpty);
    });

    test('a selector that fails does not lose the lesfiche: the goals are '
        'shown by their fields', () async {
      selector.failWith = 500;
      expect(
        await ok('read_lesfiche', {'lesfiche': _lesfiche.id}),
        allOf(
          contains('Name: Algoritmen\n'),
          contains(
            'Goals:\n'
            '- id $fakeGoal1Id, leerplanId $fakeEindtermenId, type '
            '$fakeEindtermenType\n',
          ),
          contains(
            'Note: the goal selector could not name the goals (HTTP 500), '
            'so they are shown by their ids. The technical details are in '
            'the server log.\n',
          ),
        ),
      );
    });
  });

  group('read_planned_element', () {
    test('names the goals of an own lesson, in the planner\'s place', () async {
      final text = await ok('read_planned_element', {'id': _lesson.ref});
      expect(text, contains('\n$_goalLines\nPublic info (what pupils see):'));
      final resolve = selector.requests.single;
      expect(
        resolve.path,
        matches(RegExp(r'/planner-lesson-content/\d{4}-\d\d-\d\d$')),
      );
    });

    test('a lesson without goals reads "Goals: none"; an empty lesson hour '
        'has no goals line', () async {
      server.planner.add(fakeOwnLesson, calendars: ['user/$fakePlannerMe']);
      // The same id as [_lesson]: replaced by the lesson without goals.
      expect(
        await ok('read_planned_element', {'id': fakeOwnLesson.ref}),
        contains('\nGoals: none\n\nPublic info (what pupils see):'),
      );
      expect(
        await ok('read_planned_element', {'id': fakeOwnSlot.ref}),
        isNot(contains('Goals')),
      );
      expect(selector.requests, isEmpty);
    });
  });
}
