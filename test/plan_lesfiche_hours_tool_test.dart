/// `plan_lesfiche` into several hours and over a lesson, and
/// `save_lesson_as_lesfiche` (#190), called over MCP on the real server,
/// session and library, against a fake Smartschool whose planner plans a
/// lesfiche into several hours at once (`planned-elements/
/// replace-with-lesson-content`), replaces a lesson by a lesfiche
/// (`planned-lessons/replace/planned-lessons/...`) and saves a lesson as a
/// lesfiche (`.../save-in-source-module`), with the requests of
/// dartschool#224 and #225 (`test/support/fake_planner.dart`), and whose
/// goal selector names the goals the lessons get.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/save_lesson_as_lesfiche_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/planner/api/v1';
const _bulkPath = '$_api/planned-elements/replace-with-lesson-content';

final _goal1 = fakeGoalRef(fakeGoal1Id, fakeEindtermenId, fakeEindtermenType);

/// [_goal1] as the results name it.
const _goal1Line =
    '- Eindtermen derde graad, voorbeeld: Competenties voorbeeld > 01.01 De '
    'leerlingen passen een algoritme toe & meer. | id $fakeGoal1Id, '
    'leerplanId $fakeEindtermenId, type $fakeEindtermenType';

/// A lesson lesfiche of informatica with a goal of the eindtermen and
/// private info.
final _algoritmen = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000041',
  name: 'Algoritmen',
  publicInfo: '<p>Hoofdstuk 5</p>',
  privateInfo: '<p>Oefening 2 overslaan</p>',
  courses: [fakeInformatica],
  goals: [_goal1],
);

/// An empty lesson hour of the own planner, 11:10–12:00 on [day] November
/// 2026, of [group] in room 101.
FakePlannedElement _ownHour(String id, int day, FakePlannerGroup group) =>
    FakePlannedElement(
      id: 'e0000000-0000-5000-8000-0000000000$id',
      type: 'planned-placeholders',
      from: plannerTime(2026, 11, day, 11, 10),
      to: plannerTime(2026, 11, day, 12, 0),
      organisers: [FakePlannerUser.me],
      groups: [group],
      courses: [fakeInformatica],
      rooms: [fakeRoom101],
    );

/// The parallel class 6A2's hour, on Monday 23 November.
final _hour6A2 = _ownHour('31', 23, fake6A2);

/// A lesson typed in by hand in the own planner, on Friday 27 November.
final _typed = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000032',
  type: 'planned-lessons',
  name: 'Herhaling',
  from: plannerTime(2026, 11, 27, 11, 10),
  to: plannerTime(2026, 11, 27, 12, 0),
  organisers: [FakePlannerUser.me],
  groups: [fake6A1],
  courses: [fakeInformatica],
  rooms: [fakeRoom101],
  publicInfo: '<p>Zelf getypt</p>',
  goals: [_goal1],
);

/// The id the fake gives the [n]th lesson its writes make.
String _lessonId(int n) =>
    'planned-lessons/4069/e0000000-0000-4000-9000-${'$n'.padLeft(12, '0')}';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    server.goals.loadSample();
    planner = server.planner
      ..loadCaptures()
      ..loadLesfiches()
      ..lesfiches.add(_algoritmen);
    for (final hour in [_hour6A2, _typed]) {
      planner.add(
        hour,
        calendars: [
          'user/$fakePlannerMe',
          for (final group in hour.groups) 'group/${group.id}',
        ],
      );
    }
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
        listLesfichesTool(session),
        readLesficheTool(session),
        planLesficheTool(session),
        saveLessonAsLesficheTool(session),
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

  /// The bodies of the POSTs to [path] that reached the planner.
  List<Object?> bodiesTo(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
  ];

  /// How many POSTs to [path] reached the fake Smartschool.
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

    test('save_lesson_as_lesfiche as a write Claude Desktop asks approval '
        'for every time, not idempotent, with its arguments', () {
      final save = tools['save_lesson_as_lesfiche']!;
      final annotations = save.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isFalse);
      expect(annotations.openWorldHint, isTrue);
      expect(save.inputSchema.required, ['lesson']);
      expect(save.inputSchema.properties!.keys, ['lesson', 'name']);
      for (final phrase in [
        'only call it after the user has explicitly confirmed it',
        'Every call makes a new lesfiche',
        'never call it again for a lesson that was saved',
        'do not call this tool again: first look for it with list_lesfiches',
        'The lesson itself stays as it is, and keeps no link to the '
            'lesfiche',
        'plan_lesfiche',
      ]) {
        expect(save.description, contains(phrase));
      }
    });
  });

  group('plan_lesfiche into several hours', () {
    test('plans one lesfiche into the hours of parallel classes in one '
        'request, and says per hour what became of it', () async {
      final text = await ok('plan_lesfiche', {
        'hours': [fakeOwnSlot.ref, _hour6A2.ref],
        'lesfiche': _algoritmen.id,
      });
      expect(
        text,
        startsWith(
          'Planned the lesfiche ${_algoritmen.id} into all 2 hours. Pupils '
          'of their classes see its name and public info now.\n'
          '- The empty lesson hour on Friday 2026-11-20 11:10–12:00 (6A1, '
          '6A2, informatica) (${fakeOwnSlot.ref}): planned; the lesson has '
          'the id ${_lessonId(1)}.\n'
          '- The empty lesson hour on Monday 2026-11-23 11:10–12:00 (6A2, '
          'informatica) (${_hour6A2.ref}): planned; the lesson has the id '
          '${_lessonId(2)}.\n'
          'The old id of an hour that was planned no longer exists: use the '
          'lesson\'s new id.\n'
          'For a few seconds after a change list_planner can still show the '
          'old state; read_planned_element shows the new state at once.\n'
          '\n'
          'The first lesson as saved (the others hold the same content of '
          'the lesfiche, each in its own hour):\n'
          'Planner element ${_lessonId(1)}\n',
        ),
      );
      // The lesson carries the lesfiche's private info and goals, named.
      expect(text, contains('Name: Algoritmen\n'));
      expect(text, contains('Goals:\n$_goal1Line\n'));
      expect(text, contains('Oefening 2 overslaan'));

      // One request, with the body of dartschool#224.
      expect(planner.writes, ['POST $_bulkPath']);
      expect(bodiesTo(_bulkPath), [
        {
          'platformId': 4069,
          'sourceId': _algoritmen.id,
          'sourceType': 'lesson',
          'courses': [
            {'platformId': 4069, 'id': fakeInformatica.id},
          ],
          'visibility': <Object?>[],
          'plannedElements': [
            {
              'plannedElementId': fakeOwnSlot.id,
              'platformId': 4069,
              'plannedElementType': 'planned-placeholders',
            },
            {
              'plannedElementId': _hour6A2.id,
              'platformId': 4069,
              'plannedElementType': 'planned-placeholders',
            },
          ],
        },
      ]);
      expect(
        await ok('read_planned_element', {'id': _lessonId(2)}),
        allOf(contains('Name: Algoritmen\n'), contains('Classes: 6A2\n')),
      );
    });

    test('an hour given twice is planned once', () async {
      await ok('plan_lesfiche', {
        'hours': [fakeOwnSlot.ref, _hour6A2.ref, fakeOwnSlot.ref],
        'lesfiche': _algoritmen.id,
      });
      expect(
        ((bodiesTo(_bulkPath).single! as Map)['plannedElements'] as List)
            .length,
        2,
      );
    });

    test('refuses a lesson among the hours without replace, before asking '
        'Smartschool: nothing typed in by hand is overwritten', () async {
      for (final arguments in [
        {
          'hours': [_hour6A2.ref, _typed.ref],
          'lesfiche': _algoritmen.id,
        },
        {
          'hours': [_typed.ref],
          'lesfiche': _algoritmen.id,
          'replace': false,
        },
      ]) {
        expect(
          await error('plan_lesfiche', arguments),
          'hours holds a lesson, not an empty lesson hour: ${_typed.ref}. A '
          'lesson is only replaced by the lesfiche when replace is true, and '
          'then its old name, info and goals are gone. Set replace only when '
          'the user explicitly asked to replace that lesson; else leave it '
          'out. Nothing was sent.',
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
      expect(planner.elements[_typed.ref]!.name, 'Herhaling');
    });

    test('with replace, replaces a lesson typed in by hand and fills an '
        'empty hour in one request', () async {
      final text = await ok('plan_lesfiche', {
        'hours': [_hour6A2.ref, _typed.ref],
        'lesfiche': fakeLesficheFuncties.id,
        'replace': true,
      });
      expect(
        text,
        contains(
          '- The lesson "Herhaling" on Friday 2026-11-27 11:10–12:00 (6A1, '
          'informatica) (${_typed.ref}): replaced by the lesfiche (its old '
          'name, info and goals are gone); the lesson has the id '
          '${_lessonId(2)}.\n',
        ),
      );
      expect(planner.writes, ['POST $_bulkPath']);
      expect(planner.elements, isNot(contains(_typed.ref)));
      expect(
        await ok('read_planned_element', {'id': _lessonId(2)}),
        allOf(
          contains('Name: Functies\n'),
          contains('Goals: none'),
          isNot(contains('Zelf getypt')),
        ),
      );
    });

    test('with replace, one lesson is replaced with the request of '
        'dartschool#224', () async {
      final path =
          '$_api/planned-lessons/replace/planned-lessons/4069/${_typed.id}';
      expect(
        await ok('plan_lesfiche', {
          'hours': [_typed.ref],
          'lesfiche': _algoritmen.id,
          'replace': true,
        }),
        allOf(
          startsWith(
            'Replaced the lesson "Herhaling" on Friday 2026-11-27 '
            '11:10–12:00 (6A1, informatica) with the lesfiche '
            '${_algoritmen.id}: its old name, info and goals are gone, and '
            'the new lesson holds the content of the lesfiche '
            '${_algoritmen.id}. Pupils of 6A1 see its name and public info '
            'now.\n'
            'The lesson ${_typed.ref} no longer exists: the new lesson has '
            'the id ${_lessonId(1)}.\n',
          ),
          contains('Name: Algoritmen\n'),
          contains('Goals:\n$_goal1Line\n'),
        ),
      );
      expect(planner.writes, ['POST $path']);
      expect((bodiesTo(path).single! as Map)['sourceId'], _algoritmen.id);
    });

    test('an hour the planner does not plan is reported with its reason, '
        'and the others are planned', () async {
      planner.bulkExceptions[_hour6A2.ref] = {
        'message': 'Dit lesuur kan niet vervangen worden.',
      };

      expect(
        await error('plan_lesfiche', {
          'hours': [fakeOwnSlot.ref, _hour6A2.ref],
          'lesfiche': _algoritmen.id,
        }),
        allOf(
          startsWith(
            'Planned the lesfiche ${_algoritmen.id} into 1 of the 2 hours.',
          ),
          contains(
            '- The empty lesson hour on Monday 2026-11-23 11:10–12:00 (6A2, '
            'informatica) (${_hour6A2.ref}): not planned: the planner '
            'refused it ("Dit lesuur kan niet vervangen worden.").\n',
          ),
          contains(
            'Do not call plan_lesfiche again for the hours that were '
            'planned. Tell the user which hours were not planned and why; '
            'they were left as they were.',
          ),
          contains('Planner element ${_lessonId(1)}\n'),
        ),
      );
      expect(planner.writes, ['POST $_bulkPath']);
      expect(planner.elements, contains(_hour6A2.ref));
    });

    test('a colleague\'s hour among the hours refuses them all, before '
        'anything is sent', () async {
      expect(
        await error('plan_lesfiche', {
          'hours': [fakeOwnSlot.ref, fakeSlot.ref],
          'lesfiche': _algoritmen.id,
        }),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains('is not in your own planner'),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeOwnSlot.ref));
    });

    test('a plan the planner does not confirm is reported as maybe saved, '
        'and never sent again', () async {
      planner.lostAnswers.add(_bulkPath);

      expect(
        await error('plan_lesfiche', {
          'hours': [fakeOwnSlot.ref, _hour6A2.ref],
          'lesfiche': _algoritmen.id,
        }),
        'The lesfiche ${_algoritmen.id} in the 2 hours (empty lesson hour on '
        'Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica); empty lesson '
        'hour on Monday 2026-11-23 11:10–12:00 (6A2, informatica)) may or '
        'may not have been saved, in all or some of them: the change was '
        'sent, but the planner did not confirm it. Do not call plan_lesfiche '
        'again for it: first read each hour with read_planned_element (ids '
        '${fakeOwnSlot.ref}, ${_hour6A2.ref}): an hour the planner no longer '
        'has under its id was planned, and list_planner (planner me) shows '
        'the lesson in its place, possibly only after a few seconds; an hour '
        'that is still there was not. Then tell the user what you found.',
      );
      expect(postsTo(_bulkPath), 1);
      expect(server.logins, 1);
    });
  });

  group('save_lesson_as_lesfiche', () {
    final savePath = '$_api/${_typed.ref}/save-in-source-module';

    test('saves an own lesson as a new lesfiche, with its goals, and the '
        'lesfiche is then planned into another hour', () async {
      final id = fakeNewLesficheId(1);
      final text = await ok('save_lesson_as_lesfiche', {
        'lesson': _typed.ref,
        'name': '  Herhaling: lussen 2027  ',
      });
      expect(
        text,
        startsWith(
          'Saved the lesson "Herhaling" on Friday 2026-11-27 11:10–12:00 '
          '(6A1, informatica) as the lesson lesfiche "Herhaling: lussen '
          '2027" in your own library',
        ),
      );
      expect(
        text,
        contains(
          'Its id is $id: plan it into other hours with plan_lesfiche, read '
          'it with read_lesfiche, and change it with edit_lesfiche.\n',
        ),
      );
      expect(text, contains('Goals:\n$_goal1Line'));
      expect(text, contains('Zelf getypt'));
      expect(planner.writes, ['POST $savePath']);
      expect(bodiesTo(savePath), [
        {'newName': 'Herhaling: lussen 2027'},
      ]);
      // The lesson stays as it is.
      expect(planner.elements[_typed.ref]!.name, 'Herhaling');

      expect(
        await ok('list_lesfiches', {'query': 'lussen 2027'}),
        contains('| id $id'),
      );
      expect(
        await ok('plan_lesfiche', {
          'hours': [_hour6A2.ref],
          'lesfiche': id,
        }),
        allOf(
          contains('Name: Herhaling: lussen 2027\n'),
          contains('Goals:\n$_goal1Line\n'),
        ),
      );
    });

    test('takes the lesson\'s name when name is left out', () async {
      expect(
        await ok('save_lesson_as_lesfiche', {'lesson': _typed.ref}),
        contains('as the lesson lesfiche "Herhaling" in your own library'),
      );
      expect(bodiesTo(savePath), [
        {'newName': 'Herhaling'},
      ]);
    });

    test('refuses an empty lesson hour, an assignment and an empty name, '
        'before asking Smartschool', () async {
      for (final (arguments, message) in [
        (
          {'lesson': fakeOwnSlot.ref},
          'lesson must be a lesson of your own planner, like '
              'planned-lessons/4069/…; ${fakeOwnSlot.ref} is an empty lesson '
              'hour, which has nothing to save. Nothing was sent.',
        ),
        (
          {'lesson': 'planned-assignments/4069/x'},
          'lesson must be a lesson of your own planner',
        ),
        (
          {'lesson': _typed.ref, 'name': ' '},
          'name is empty: give the lesfiche a name.',
        ),
      ]) {
        expect(
          await error('save_lesson_as_lesfiche', arguments),
          startsWith(message),
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
    });

    test('refuses a colleague\'s lesson without any write', () async {
      expect(
        await error('save_lesson_as_lesfiche', {'lesson': fakeLesson.ref}),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains('is not in your own planner'),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('a save the list does not confirm is reported as maybe made, and '
        'never sent again', () async {
      planner.lostAnswers.add(savePath);

      expect(
        await error('save_lesson_as_lesfiche', {'lesson': _typed.ref}),
        'A lesfiche of the lesson "Herhaling" on Friday 2026-11-27 '
        '11:10–12:00 (6A1, informatica) may or may not have been made: the '
        'change was sent, but the planner did not confirm it. Do not call '
        'save_lesson_as_lesfiche again for it: first look for it with '
        'list_lesfiches (query "Herhaling"): a second call makes a second '
        'lesfiche. Then tell the user what you found.',
      );
      expect(postsTo(savePath), 1);
      expect(server.logins, 1);
    });
  });
}
