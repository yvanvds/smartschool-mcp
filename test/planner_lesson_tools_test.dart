/// `plan_lesson`, `edit_planned_element` and `clear_lesson` (#53), called
/// over MCP on the real server, session and library, against a fake
/// Smartschool whose planner serves dartschool's anonymised captures and
/// carries out the writes of dartschool#87 as the live planner did
/// (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/clear_lesson_tool.dart';
import 'package:smartschool_mcp/src/tools/edit_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_lesson_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/planner/api/v1';

/// The path of the fill of the empty lesson hour [slot].
String _fillPath(FakePlannedElement slot) =>
    '$_api/planned-placeholders/4069/${slot.id}/replace/planned-lessons/blanco';

/// The path of the edit [action] of [element].
String _editPath(FakePlannedElement element, String action) =>
    '$_api/${element.type}/4069/${element.id}/$action';

const _clearPath = '$_api/planned-elements/clear';

/// The body the web client sends to fill [fakeOwnSlot] (dartschool#87, as
/// tried live), with the lesson's [name] and info.
Map<String, Object?> _fillBody({
  required String name,
  String publicInfo = '',
  String privateInfo = '',
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
  'name': name,
  'info': '',
  'publicInfo': publicInfo,
  'privateInfo': privateInfo,
  'icon': 'document_observation',
};

/// An assignment of the fake's own planner, for the edits.
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
  visibleFrom: plannerTime(2026, 10, 1, 9, 0),
);

/// The id the fake gives the [n]th element its writes make: a lesson
/// (`4000`) or an empty lesson hour (`5000`).
String _made(String version, int n) =>
    'e0000000-0000-$version-9000-${n.toString().padLeft(12, '0')}';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner..loadCaptures();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listPlannerTool(session, now: () => DateTime(2026, 10, 5, 9, 30)),
        readPlannedElementTool(session),
        planLessonTool(session),
        editPlannedElementTool(session),
        clearLessonTool(session),
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

  /// The bodies of the requests to [path] that reached the planner.
  List<Object?> bodiesTo(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
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

    test('as writes Claude Desktop asks approval for every time: plan and '
        'clear are not idempotent, edit is', () {
      for (final (name, idempotent) in [
        ('plan_lesson', false),
        ('edit_planned_element', true),
        ('clear_lesson', false),
      ]) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isFalse, reason: name);
        expect(annotations.destructiveHint, isTrue, reason: name);
        expect(annotations.idempotentHint, idempotent, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
      }
    });

    test('with their arguments', () {
      expect(tools['plan_lesson']!.inputSchema.required, ['hour', 'name']);
      expect(tools['plan_lesson']!.inputSchema.properties!.keys, [
        'hour',
        'name',
        'public_info',
        'private_info',
      ]);
      expect(tools['edit_planned_element']!.inputSchema.required, ['id']);
      expect(tools['edit_planned_element']!.inputSchema.properties!.keys, [
        'id',
        'name',
        'public_info',
        'private_info',
      ]);
      expect(tools['clear_lesson']!.inputSchema.required, ['id']);
      expect(tools['clear_lesson']!.inputSchema.properties!.keys, ['id']);
    });

    test('tell Claude to get the user\'s explicit confirmation first, that '
        'only the own planner changes, who reads the info, and never to '
        'repeat a change that may have been saved', () {
      for (final name in [
        'plan_lesson',
        'edit_planned_element',
        'clear_lesson',
      ]) {
        final description = tools[name]!.description!;
        expect(
          description,
          contains('after the user has explicitly confirmed it'),
          reason: name,
        );
        expect(description, contains('Only the user\'s own'), reason: name);
        expect(description, contains('this tool refuses those'), reason: name);
        expect(
          description,
          contains('do not call this tool again for'),
          reason: name,
        );
        expect(description, contains('read_planned_element'), reason: name);
      }
      final plan = tools['plan_lesson']!.description!;
      expect(plan, contains('list_planner (planner me)'));
      expect(
        plan,
        contains(
          'Show the user, per hour, the date and time, the class, the course, '
          'and the new name and info',
        ),
      );
      expect(
        plan,
        contains(
          'For a whole week, one confirmation of the full list is enough; '
          'then call this tool once per hour.',
        ),
      );
      expect(
        plan,
        contains(
          'Private info is hidden from pupils, but colleagues who can see '
          'the lesson read it too.',
        ),
      );
      expect(plan, contains('Write the info as plain text'));
      expect(plan, contains('HTML in it is not interpreted'));
      expect(plan, contains('list_planner can still show the old state'));
      final edit = tools['edit_planned_element']!.description!;
      expect(edit, contains('a lesson or an assignment'));
      expect(edit, contains('An info replaces the whole info'));
      final clear = tools['clear_lesson']!.description!;
      expect(clear, contains('The empty lesson hour gets a new id'));
      expect(clear, contains('cannot be brought back'));
    });
  });

  group('plan_lesson', () {
    final fillPath = _fillPath(fakeOwnSlot);

    test(
      'fills an own empty lesson hour once, with the body of '
      'dartschool#87, and gives the lesson as saved with its new id',
      () async {
        final lessonId = 'planned-lessons/4069/${_made('4000', 1)}';
        expect(
          await ok('plan_lesson', {
            'hour': fakeOwnSlot.ref,
            'name': ' Lussen: for en while ',
            'public_info': 'Breng je laptop mee.',
            'private_info': 'Oefening 3 overslaan.',
          }),
          'Planned the lesson "Lussen: for en while" in the empty lesson hour '
          'on Friday 2026-11-20 11:10–12:00 (6A1, 6A2, informatica). Pupils of '
          '6A1, 6A2 see its name and public info now.\n'
          'The empty lesson hour ${fakeOwnSlot.ref} no longer exists: the '
          'lesson has the id $lessonId.\n'
          'For a few seconds after a change list_planner can still show the '
          'old state; read_planned_element shows the new state at once.\n'
          '\n'
          'Planner element $lessonId\n'
          'Kind: lesson\n'
          'Name: Lussen: for en while\n'
          'When: Friday 2026-11-20 11:10–12:00\n'
          'Course: informatica\n'
          'Classes: 6A1, 6A2\n'
          'Organised by: Jan Peeters\n'
          'Room: 101\n'
          '\n'
          'Public info (what pupils see):\n'
          'Breng je laptop mee.\n'
          '\n'
          'Private info (hidden from pupils, but colleagues who can read this '
          'element see it too):\n'
          'Oefening 3 overslaan.',
        );

        expect(planner.writes, ['POST $fillPath']);
        expect(bodiesTo(fillPath), [
          _fillBody(
            name: 'Lussen: for en while',
            publicInfo: '<p>Breng je laptop mee.</p>',
            privateInfo: '<p>Oefening 3 overslaan.</p>',
          ),
        ]);
        // The hour is gone, the lesson is in its place in each planner.
        expect(planner.elements, isNot(contains(fakeOwnSlot.ref)));
        for (final calendar in [
          'user/$fakePlannerMe',
          'group/4069_2001',
          'group/4069_2002',
          fakeRoom101.planner,
        ]) {
          expect(
            planner.calendars[calendar]!.map((element) => element.ref),
            allOf(contains(lessonId), isNot(contains(fakeOwnSlot.ref))),
            reason: calendar,
          );
        }
        expect(
          await ok('list_planner', {
            'from': '2026-11-20',
            'until': '2026-11-20',
          }),
          contains(
            '11:10–12:00 | lesson | Lussen: for en while | informatica | '
            '6A1, 6A2 | room 101 | id $lessonId',
          ),
        );
      },
    );

    test('turns the plain text of the info into the HTML of the planner\'s '
        'editor: a paragraph per blank line, a line break per line, and '
        '<, &, > and quotes escaped', () async {
      await ok('plan_lesson', {
        'hour': fakeOwnSlot.ref,
        'name': 'Lussen',
        'public_info':
            'Breng je <laptop> & "lader" mee, \'t is nodig.\r\n'
            'Ook een pen.\n'
            '\n'
            '\n'
            '  Hoofdstuk 3  \n',
        'private_info': '<b>niet vet</b>',
      });

      expect(bodiesTo(fillPath), [
        _fillBody(
          name: 'Lussen',
          publicInfo:
              '<p>Breng je &lt;laptop&gt; &amp; &quot;lader&quot; mee, '
              '&#39;t is nodig.<br />Ook een pen.</p><p>Hoofdstuk 3</p>',
          privateInfo: '<p>&lt;b&gt;niet vet&lt;/b&gt;</p>',
        ),
      ]);
      expect(
        await ok('read_planned_element', {
          'id': 'planned-lessons/4069/${_made('4000', 1)}',
        }),
        allOf(
          contains(
            'Public info (what pupils see):\n'
            'Breng je <laptop> & "lader" mee, \'t is nodig.\n'
            'Ook een pen.\n'
            '\n'
            'Hoofdstuk 3\n',
          ),
          endsWith('<b>niet vet</b>'),
        ),
      );
    });

    test('without info, the lesson has none', () async {
      expect(
        await ok('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Lussen'}),
        contains(
          'Public info (what pupils see):\n'
          '(none)\n',
        ),
      );
      expect(bodiesTo(fillPath), [_fillBody(name: 'Lussen')]);
    });

    test('refuses a colleague\'s empty lesson hour without any write: the '
        'library reads it again and refuses it', () async {
      expect(
        await error('plan_lesson', {'hour': fakeSlot.ref, 'name': 'Lussen'}),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains(
            'is not in your own planner: it is organised by Piet '
            'Peeters (4069_1002_0), not by $fakePlannerMe.',
          ),
          endsWith(
            'List the planner again with list_planner (planner me) to see how '
            'it is now. Nothing was changed in the planner.',
          ),
          isNot(contains('planLesson')),
          isNot(contains('Nothing was sent')),
        ),
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeSlot.ref));
    });

    test('refuses an own hour the planner does not let the user fill, '
        'without any write', () async {
      final locked = FakePlannedElement(
        id: 'e0000000-0000-5000-8000-000000000021',
        type: 'planned-placeholders',
        from: plannerTime(2026, 11, 20, 13, 0),
        to: plannerTime(2026, 11, 20, 13, 50),
        organisers: [FakePlannerUser.me],
        groups: [fake6A1],
        courses: [fakeInformatica],
        capabilities: {'canUserReplace': false},
      );
      planner.add(locked, calendars: ['user/$fakePlannerMe']);

      expect(
        await error('plan_lesson', {'hour': locked.ref, 'name': 'Lussen'}),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains('(canUserReplace not set)'),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('an hour that is no longer empty: the planner has no such hour any '
        'more, and nothing is sent', () async {
      planner.fillSlot(fakeOwnSlot.ref, name: 'In Smartschool zelf gepland');

      expect(
        await error('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Lussen'}),
        'The planner has no element ${fakeOwnSlot.ref} (any more). It was '
        'removed, or its id changed: a lesson hour that is filled or cleared '
        'gets a new id. List the planner again with list_planner and take '
        'the id from there. Nothing was changed in the planner.',
      );
      expect(planner.writes, isEmpty);
    });

    test('never fills an hour twice: a second call for the same hour finds '
        'it gone', () async {
      await ok('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Lussen'});
      expect(
        await error('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Lussen'}),
        startsWith('The planner has no element ${fakeOwnSlot.ref} (any more).'),
      );
      expect(planner.writes, ['POST $fillPath']);
    });

    test('refuses a lesson, an assignment, a malformed id and an empty '
        'name, before asking Smartschool', () async {
      for (final (arguments, message) in [
        (
          {'hour': fakeOwnLesson.ref, 'name': 'Lussen'},
          'hour must be an empty lesson hour of your own planner, as '
              'list_planner (planner me) shows it, with an id like '
              'planned-placeholders/4069/…; ${fakeOwnLesson.ref} is a lesson, '
              'not an empty lesson hour: change a lesson with '
              'edit_planned_element, or empty its hour first with '
              'clear_lesson. Nothing was sent.',
        ),
        (
          {'hour': 'id ${fakeAssignment.ref}', 'name': 'Lussen'},
          'hour must be an empty lesson hour of your own planner, as '
              'list_planner (planner me) shows it, with an id like '
              'planned-placeholders/4069/…; ${fakeAssignment.ref} is an '
              'assignment, not an empty lesson hour. Nothing was sent.',
        ),
        (
          {'hour': fakeOwnSlot.id, 'name': 'Lussen'},
          'hour must be the id of a planner element as list_planner shows it',
        ),
        (
          {'hour': fakeOwnSlot.ref, 'name': '   '},
          'name is empty: pass the name of the lesson. Nothing was sent.',
        ),
      ]) {
        expect(
          await error('plan_lesson', arguments),
          startsWith(message),
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
    });

    group('a fill that the planner does not confirm is reported as maybe '
        'saved, and never sent again', () {
      test('the planner answers the fill with an error', () async {
        planner.failing[fillPath] = 500;

        expect(
          await error('plan_lesson', {
            'hour': fakeOwnSlot.ref,
            'name': 'Lussen',
          }),
          'The lesson "Lussen" in the empty lesson hour on Friday 2026-11-20 '
          '11:10–12:00 (6A1, 6A2, informatica) may or may not have been '
          'saved: the change was sent, but the planner did not confirm it. Do '
          'not call plan_lesson again for it: first read the hour with '
          'read_planned_element (id ${fakeOwnSlot.ref}): when the planner no '
          'longer has it, the hour was filled, and list_planner (planner me) '
          'shows the lesson in its place, possibly only after a few seconds; '
          'when the hour is still empty, nothing was saved. Then tell the user '
          'what you found.',
        );
        expect(postsTo(fillPath), 1);
        expect(server.logins, 1);
      });

      test('the connection drops after the fill went out', () async {
        planner.lostAnswers.add(fillPath);

        expect(
          await error('plan_lesson', {
            'hour': fakeOwnSlot.ref,
            'name': 'Lussen',
          }),
          contains('may or may not have been saved'),
        );
        expect(postsTo(fillPath), 1);
        expect(server.logins, 1);
        // It was saved: the check the result asks for tells.
        expect(
          await error('read_planned_element', {'id': fakeOwnSlot.ref}),
          startsWith('The planner has no element ${fakeOwnSlot.ref}'),
        );
      });
    });

    group('Smartschool refuses the session for the fill, which the library '
        'does not send again; the session repeats the call', () {
      test('the repeat reads the hour again and fills it once', () async {
        server.expireSessionBefore((request) => isPostTo(request, fillPath));

        expect(
          await ok('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Lussen'}),
          startsWith('Planned the lesson "Lussen" in the empty lesson hour '),
        );
        expect(postsTo(fillPath), 2, reason: 'the refused one and the fill');
        expect(
          betweenPostsTo(fillPath),
          contains('GET $_api/planned-placeholders/4069/${fakeOwnSlot.id}'),
          reason: 'the repeat reads the hour again',
        );
        expect(planner.writes, ['POST $fillPath'], reason: 'filled once');
        expect(server.logins, 2);
        expect(
          planner.calendars['user/$fakePlannerMe']!
              .where((element) => element.name == 'Lussen')
              .length,
          1,
        );
      });

      test('the repeat finds that the hour was filled meanwhile, and sends '
          'no fill', () async {
        server.expireSessionBefore((request) {
          if (!isPostTo(request, fillPath)) return false;
          // The user fills the hour in Smartschool itself meanwhile.
          planner.fillSlot(fakeOwnSlot.ref, name: 'In Smartschool gepland');
          return true;
        });

        expect(
          await error('plan_lesson', {
            'hour': fakeOwnSlot.ref,
            'name': 'Lussen',
          }),
          allOf(
            startsWith(
              'The planner has no element ${fakeOwnSlot.ref} (any more).',
            ),
            endsWith('Nothing was changed in the planner.'),
          ),
        );
        expect(postsTo(fillPath), 1, reason: 'only the refused one');
        expect(planner.writes, isEmpty);
      });
    });
  });

  group('edit_planned_element', () {
    final renamePath = _editPath(fakeOwnLesson, 'rename');
    final publicPath = _editPath(fakeOwnLesson, 'change-public-info');
    final privatePath = _editPath(fakeOwnLesson, 'change-private-info');

    test('renames an own lesson and changes its public and private info, in '
        'that order, with the bodies of dartschool#87', () async {
      expect(
        await ok('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': 'Lussen: for, while en break',
          'public_info': 'Breng je laptop opgeladen mee & je lader.',
          'private_info': 'Oefening 3\nOefening 4',
        }),
        'Changed the name, the public info and the private info of the '
        'lesson "Lussen: for en while" on Monday 2026-10-05 10:20–11:10 '
        '(6A1, 6A2, informatica).\n'
        'For a few seconds after a change list_planner can still show the '
        'old state; read_planned_element shows the new state at once.\n'
        '\n'
        'Planner element ${fakeOwnLesson.ref}\n'
        'Kind: lesson\n'
        'Name: Lussen: for, while en break\n'
        'When: Monday 2026-10-05 10:20–11:10\n'
        'Course: informatica\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Jan Peeters\n'
        'Room: 101\n'
        '\n'
        'Public info (what pupils see):\n'
        'Breng je laptop opgeladen mee & je lader.\n'
        '\n'
        'Private info (hidden from pupils, but colleagues who can read this '
        'element see it too):\n'
        'Oefening 3\n'
        'Oefening 4',
      );
      expect(planner.writes, [
        'POST $renamePath',
        'POST $publicPath',
        'POST $privatePath',
      ]);
      expect(bodiesTo(renamePath), [
        {'newName': 'Lussen: for, while en break'},
      ]);
      expect(bodiesTo(publicPath), [
        {'newInfo': '<p>Breng je laptop opgeladen mee &amp; je lader.</p>'},
      ]);
      expect(bodiesTo(privatePath), [
        {'newInfo': '<p>Oefening 3<br />Oefening 4</p>'},
      ]);
    });

    test('changes only what is given; an empty info empties it', () async {
      expect(
        await ok('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'public_info': '',
        }),
        allOf(
          startsWith(
            'Changed the public info of the lesson "Lussen: for en while" on '
            'Monday 2026-10-05 10:20–11:10 (6A1, 6A2, informatica).\n',
          ),
          contains('Public info (what pupils see):\n(none)\n'),
        ),
      );
      expect(planner.writes, ['POST $publicPath']);
      expect(bodiesTo(publicPath), [
        {'newInfo': ''},
      ]);
    });

    test('sends nothing for what the element already has', () async {
      expect(
        await ok('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': ' Lussen: for en while ',
          'public_info': 'Breng je laptop mee.',
        }),
        startsWith(
          'Nothing to change: the lesson "Lussen: for en while" on Monday '
          '2026-10-05 10:20–11:10 (6A1, 6A2, informatica) already has what '
          'was given.\n\nPlanner element ${fakeOwnLesson.ref}\n',
        ),
      );
      expect(
        await ok('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': 'Lussen',
          'public_info': 'Breng je laptop mee.',
        }),
        startsWith(
          'Changed the name of the lesson "Lussen: for en while" on Monday '
          '2026-10-05 10:20–11:10 (6A1, 6A2, informatica).\n'
          'The public info already had the value given.\n',
        ),
      );
      expect(planner.writes, ['POST $renamePath']);
    });

    test('changes an own assignment at its own route', () async {
      planner.add(
        _ownAssignment,
        calendars: ['user/$fakePlannerMe', 'group/4069_2001'],
      );

      expect(
        await ok('edit_planned_element', {
          'id': _ownAssignment.ref,
          'name': 'Toets: lussen en functies',
          'public_info': 'Leerstof: hoofdstuk 3.',
        }),
        allOf(
          startsWith(
            'Changed the name and the public info of the assignment KO '
            'Kleine Overhoring "Toets: lussen" on Friday 2026-11-20 11:10 '
            '(deadline) (6A1, informatica).\n',
          ),
          contains('Name: Toets: lussen en functies\n'),
          contains('Leerstof: hoofdstuk 3.'),
        ),
      );
      expect(planner.writes, [
        'POST ${_editPath(_ownAssignment, 'rename')}',
        'POST ${_editPath(_ownAssignment, 'change-public-info')}',
      ]);
    });

    test('refuses a colleague\'s lesson and assignment without any write: '
        'the library reads them again and refuses them', () async {
      for (final (element, organiser) in [
        (fakeLesson, 'Wim Willems (4069_1003_0)'),
        (fakeAssignment, 'Piet Peeters (4069_1002_0)'),
      ]) {
        expect(
          await error('edit_planned_element', {
            'id': element.ref,
            'name': 'Overgenomen',
            'private_info': 'Van mij',
          }),
          allOf(
            startsWith('The planner refused the change before it was sent: '),
            contains(
              'is not in your own planner: it is organised by $organiser',
            ),
            endsWith('Nothing was changed in the planner.'),
          ),
          reason: element.ref,
        );
      }
      expect(planner.writes, isEmpty);
    });

    test('refuses an empty lesson hour, another kind of element, nothing to '
        'change and an empty name, before asking Smartschool', () async {
      for (final (arguments, message) in [
        (
          {'id': fakeOwnSlot.ref, 'name': 'Lussen'},
          'id must be a lesson or an assignment of your own planner; '
              '${fakeOwnSlot.ref} is an empty lesson hour, which has no name '
              'or info: fill it with plan_lesson. Nothing was sent.',
        ),
        (
          {'id': fakeExcursion.ref, 'name': 'Uitstap'},
          'id must be a lesson or an assignment of your own planner; '
              '${fakeExcursion.ref} is a planned-excursions. Nothing was sent.',
        ),
        (
          {'id': fakeOwnLesson.ref},
          'Nothing to change: pass at least one of name, public_info and '
              'private_info. Nothing was sent.',
        ),
        (
          {'id': fakeOwnLesson.ref, 'name': ' ', 'public_info': 'Hallo'},
          'name is empty: pass the new name, or leave name out to keep it. '
              'Nothing was sent.',
        ),
      ]) {
        expect(
          await error('edit_planned_element', arguments),
          message,
          reason: '$arguments',
        );
      }
      expect(server.requests, isEmpty);
    });

    test('a change the planner does not confirm: says which may or may not '
        'be saved, what was saved, and what was not sent', () async {
      planner.failing[publicPath] = 500;

      expect(
        await error('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': 'Lussen: for, while en break',
          'public_info': 'Nieuw',
          'private_info': 'Oefening 3',
        }),
        'The change of the public info of the lesson "Lussen: for en while" '
        'on Monday 2026-10-05 10:20–11:10 (6A1, 6A2, informatica) may or may '
        'not have been saved: the change was sent, but the planner did not '
        'confirm it. The name was saved. The private info was not sent. Do '
        'not call edit_planned_element again for it: first read the element '
        'with read_planned_element (id ${fakeOwnLesson.ref}) and compare the '
        'public info. Then tell the user what you found.',
      );
      expect(planner.writes, ['POST $renamePath', 'POST $publicPath']);
      expect(server.logins, 1);
    });

    test('a change refused after another was saved: says what was saved and '
        'what was not', () async {
      final noNotes = FakePlannedElement(
        id: 'e0000000-0000-4000-8000-000000000022',
        type: 'planned-lessons',
        name: 'Lussen',
        from: plannerTime(2026, 10, 6, 10, 20),
        to: plannerTime(2026, 10, 6, 11, 10),
        organisers: [FakePlannerUser.me],
        groups: [fake6A1],
        courses: [fakeInformatica],
        capabilities: {'canUserChangePrivateInfo': false},
      );
      planner.add(noNotes, calendars: ['user/$fakePlannerMe']);

      expect(
        await error('edit_planned_element', {
          'id': noNotes.ref,
          'name': 'Lussen: for en while',
          'private_info': 'Oefening 3',
        }),
        allOf(
          startsWith(
            'Of the lesson "Lussen" on Tuesday 2026-10-06 10:20–11:10 (6A1, '
            'informatica), the name was saved. The private info was not '
            'changed: The planner refused the change before it was sent: ',
          ),
          contains('(canUserChangePrivateInfo not set)'),
          isNot(contains('Nothing was changed')),
        ),
      );
      expect(planner.writes, ['POST ${_editPath(noNotes, 'rename')}']);
    });

    test('Smartschool refuses the session for a change: the library logs in '
        'again and sends it again, as it sets a value', () async {
      server.expireSessionBefore((request) => isPostTo(request, renamePath));

      expect(
        await ok('edit_planned_element', {
          'id': fakeOwnLesson.ref,
          'name': 'Lussen: for, while en break',
        }),
        startsWith('Changed the name of the lesson "Lussen: for en while" '),
      );
      expect(postsTo(renamePath), 2);
      expect(planner.writes, ['POST $renamePath']);
      expect(server.logins, 2);
    });
  });

  group('clear_lesson', () {
    test('clears an own lesson once, with the body of dartschool#87, and '
        'gives the empty lesson hour\'s new id', () async {
      final hourId = 'planned-placeholders/4069/${_made('5000', 1)}';
      expect(
        await ok('clear_lesson', {'id': fakeOwnLesson.ref}),
        'Cleared the lesson "Lussen: for en while" on Monday 2026-10-05 '
        '10:20–11:10 (6A1, 6A2, informatica): its name and info are gone, and '
        'the hour is an empty lesson hour again.\n'
        'The lesson ${fakeOwnLesson.ref} no longer exists. The empty lesson '
        'hour has a new id: $hourId. Use that one to fill the hour again.\n'
        'For a few seconds after a change list_planner can still show the '
        'old state; read_planned_element shows the new state at once.\n'
        '\n'
        'Planner element $hourId\n'
        'Kind: empty lesson hour\n'
        'When: Monday 2026-10-05 10:20–11:10\n'
        'Course: informatica\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Jan Peeters\n'
        'Room: 101',
      );
      expect(planner.writes, ['POST $_clearPath']);
      expect(bodiesTo(_clearPath), [
        {
          'type': 'planned-lessons',
          'elementId': fakeOwnLesson.id,
          'elementPlatformId': 4069,
        },
      ]);
      expect(
        await error('read_planned_element', {'id': fakeOwnLesson.ref}),
        startsWith('The planner has no element ${fakeOwnLesson.ref}'),
      );
      expect(
        await ok('list_planner', {'from': '2026-10-05', 'until': '2026-10-05'}),
        contains(
          '10:20–11:10 | empty lesson hour | informatica | 6A1, 6A2 | '
          'room 101 | id $hourId',
        ),
      );
    });

    test('refuses a colleague\'s lesson without any write', () async {
      expect(
        await error('clear_lesson', {'id': fakeLesson.ref}),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains(
            'is not in your own planner: it is organised by Wim '
            'Willems (4069_1003_0)',
          ),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
      expect(planner.elements, contains(fakeLesson.ref));
    });

    test('refuses an own lesson that is not in a lesson hour (one the planner '
        'lets the user trash) without any write', () async {
      final outside = FakePlannedElement(
        id: 'e0000000-0000-4000-8000-000000000023',
        type: 'planned-lessons',
        name: 'Inhaalles',
        from: plannerTime(2026, 10, 7, 16, 0),
        to: plannerTime(2026, 10, 7, 17, 0),
        organisers: [FakePlannerUser.me],
        groups: [fake6A1],
        capabilities: {'canUserTrash': true, 'canUserDelete': true},
      );
      planner.add(outside, calendars: ['user/$fakePlannerMe']);

      expect(
        await error('clear_lesson', {'id': outside.ref}),
        allOf(
          startsWith('The planner refused the change before it was sent: '),
          contains('(canUserTrash)'),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('a lesson that is gone: the planner has no such lesson any more, '
        'and nothing is sent', () async {
      planner.clearLesson(fakeOwnLesson.ref);

      expect(
        await error('clear_lesson', {'id': fakeOwnLesson.ref}),
        allOf(
          startsWith(
            'The planner has no element ${fakeOwnLesson.ref} (any more).',
          ),
          endsWith('Nothing was changed in the planner.'),
        ),
      );
      expect(planner.writes, isEmpty);
    });

    test('refuses an empty lesson hour, an assignment and a malformed id, '
        'before asking Smartschool', () async {
      for (final (id, message) in [
        (
          fakeOwnSlot.ref,
          'id must be a lesson of your own planner, like '
              'planned-lessons/4069/…; ${fakeOwnSlot.ref} is an empty lesson '
              'hour already. Nothing was sent.',
        ),
        (
          fakeAssignment.ref,
          'id must be a lesson of your own planner, like '
              'planned-lessons/4069/…; ${fakeAssignment.ref} is an '
              'assignment, not a lesson. Nothing was sent.',
        ),
        (
          'Lussen: for en while',
          'id must be the id of a planner element as list_planner shows it',
        ),
      ]) {
        expect(
          await error('clear_lesson', {'id': id}),
          startsWith(message),
          reason: id,
        );
      }
      expect(server.requests, isEmpty);
    });

    test('a clear that the planner does not confirm is reported as maybe '
        'done, and never sent again', () async {
      planner.lostAnswers.add(_clearPath);

      expect(
        await error('clear_lesson', {'id': fakeOwnLesson.ref}),
        'The lesson "Lussen: for en while" on Monday 2026-10-05 10:20–11:10 '
        '(6A1, 6A2, informatica) may or may not have been cleared: the change '
        'was sent, but the planner did not confirm it. Do not call '
        'clear_lesson again for it: first read the lesson with '
        'read_planned_element (id ${fakeOwnLesson.ref}): when the planner no '
        'longer has it, it was cleared, and list_planner (planner me) shows '
        'the empty lesson hour with a new id, possibly only after a few '
        'seconds; when the lesson is still there, it was not cleared. Then '
        'tell the user what you found.',
      );
      expect(postsTo(_clearPath), 1);
      expect(server.logins, 1);
    });

    test('Smartschool refuses the session for the clear, which the library '
        'does not send again: the session repeats the call, which reads the '
        'lesson again and clears it once', () async {
      server.expireSessionBefore((request) => isPostTo(request, _clearPath));

      expect(
        await ok('clear_lesson', {'id': fakeOwnLesson.ref}),
        startsWith('Cleared the lesson "Lussen: for en while" '),
      );
      expect(postsTo(_clearPath), 2, reason: 'the refused one and the clear');
      expect(
        betweenPostsTo(_clearPath),
        contains('GET $_api/planned-lessons/4069/${fakeOwnLesson.id}'),
        reason: 'the repeat reads the lesson again',
      );
      expect(planner.writes, ['POST $_clearPath'], reason: 'cleared once');
      expect(server.logins, 2);
    });
  });

  test('the flow of the issue: list the own empty hours, fill one, change '
      'it, clear it, and fill the hour again by its new id', () async {
    final week = await ok('list_planner', {
      'from': '2026-11-16',
      'until': '2026-11-20',
      'types': ['empty_lesson_hours'],
    });
    expect(week, contains('id ${fakeOwnSlot.ref}'));

    final planned = await ok('plan_lesson', {
      'hour': fakeOwnSlot.ref,
      'name': '[test] Lussen',
      'public_info': 'Voor de leerlingen',
      'private_info': 'Notities',
    });
    final lesson = RegExp(
      r'the lesson has the id (\S+)\.',
    ).firstMatch(planned)![1]!;
    expect(lesson, startsWith('planned-lessons/4069/'));

    await ok('edit_planned_element', {
      'id': lesson,
      'name': 'Lussen: for en while',
      'public_info': 'Breng je laptop mee',
    });
    expect(
      await ok('read_planned_element', {'id': lesson}),
      allOf(
        contains('Name: Lussen: for en while\n'),
        contains('Public info (what pupils see):\nBreng je laptop mee\n'),
        endsWith('Notities'),
      ),
    );

    final cleared = await ok('clear_lesson', {'id': lesson});
    final hour = RegExp(
      r'The empty lesson hour has a new id: (\S+)\.',
    ).firstMatch(cleared)![1]!;
    expect(hour, isNot(fakeOwnSlot.ref));

    expect(
      await error('plan_lesson', {'hour': fakeOwnSlot.ref, 'name': 'Opnieuw'}),
      startsWith('The planner has no element ${fakeOwnSlot.ref} (any more).'),
    );
    await ok('plan_lesson', {'hour': hour, 'name': 'Opnieuw'});

    expect(planner.writes, [
      'POST ${_fillPath(fakeOwnSlot)}',
      'POST $_api/$lesson/rename',
      'POST $_api/$lesson/change-public-info',
      'POST $_clearPath',
      'POST $_api/$hour/replace/planned-lessons/blanco',
    ]);
  });
}
