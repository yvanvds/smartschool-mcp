/// `search_planners`, `list_planner` and `read_planned_element`, called over
/// MCP on the real server, session and library, against a fake Smartschool
/// whose planner serves dartschool's anonymised captures of the live
/// planner (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/search_planners_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _class6A1 = 'group/4069_2001';
const _piet = 'user/4069_1002_0';

/// `10:20` for the moment [iso] in the time of this PC.
String _clock(String iso) {
  final local = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// Whether this PC is in Belgian time in October (`+02:00`) and November
/// (`+01:00`) 2026, as the planner's own times are.
final _belgianTime =
    DateTime(2026, 10, 5).timeZoneOffset == const Duration(hours: 2) &&
    DateTime(2026, 11, 20).timeZoneOffset == const Duration(hours: 1);

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
        searchPlannersTool(session),
        listPlannerTool(session, now: () => DateTime(2026, 10, 5, 9, 30)),
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

  Future<String> list(Map<String, Object?> arguments) =>
      ok('list_planner', arguments);

  Future<String> read(String id) => ok('read_planned_element', {'id': id});

  /// The planner requests that reached the fake, as `METHOD path`.
  List<String> plannerRequests() => [
    for (final request in planner.requests) '${request.method} ${request.path}',
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

    test('in order, read-only and idempotent', () {
      expect(tools.keys, [
        'search_planners',
        'list_planner',
        'read_planned_element',
      ]);
      for (final tool in tools.values) {
        final annotations = tool.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: tool.name);
        expect(annotations.idempotentHint, isTrue, reason: tool.name);
        expect(annotations.openWorldHint, isTrue, reason: tool.name);
        expect(annotations.destructiveHint, isNot(true), reason: tool.name);
      }
    });

    test('search_planners says that pupils and staff are mixed, and '
        'points to list_planner', () {
      final search = tools['search_planners']!;
      expect(search.inputSchema.required, ['query']);
      expect(search.inputSchema.properties!.keys, ['query']);
      expect(
        search.description,
        contains(
          'The people found are pupils and staff alike, and the answer does '
          'not tell them apart',
        ),
      );
      expect(search.description, contains('Interimaris van'));
      expect(search.description, contains('list_planner takes "me"'));
    });

    test('list_planner takes a planner, a period and types, and says how '
        'to narrow down', () {
      final listTool = tools['list_planner']!;
      expect(listTool.inputSchema.required, isNull);
      expect(listTool.inputSchema.properties!.keys, [
        'planner',
        'from',
        'until',
        'types',
      ]);
      expect(listTool.inputSchema.properties!['types'], {
        'type': 'array',
        'description': isA<String>(),
        'minItems': 1,
        'items': {
          'enum': ['lessons', 'assignments', 'empty_lesson_hours', 'other'],
          'type': 'string',
        },
      });
      expect(listTool.description, contains('at most 200 lines'));
      expect(listTool.description, contains('search_planners'));
      expect(listTool.description, contains('read_planned_element'));
    });

    test('read_planned_element says who reads the private info', () {
      final readTool = tools['read_planned_element']!;
      expect(readTool.inputSchema.required, ['id']);
      expect(readTool.inputSchema.properties!.keys, ['id']);
      expect(readTool.description, contains('Public info is what pupils see'));
      expect(
        readTool.description,
        contains(
          'Private info is hidden from pupils, but it is not private to its '
          'author: colleagues who can see the element read it too.',
        ),
      );
    });
  });

  group('search_planners', () {
    Future<String> search(String query) =>
        ok('search_planners', {'query': query});

    test('finds classes, with the planner id list_planner takes', () async {
      expect(
        await search('6A'),
        'The planner finds 2 for "6A":\n'
        '- class | 6A1 | 6 Latijn 1 | planner group/4069_2001\n'
        '- class | 6A2 | 6 Latijn 2 | planner group/4069_2002',
      );
      expect(planner.requests.single.method, 'POST');
      expect(
        planner.requests.single.path,
        '/planner/api/v1/quick-search/planner/search',
      );
      expect(planner.requests.single.data, {
        'searchString': '6A',
        'searchOptions': <Object?>[],
      });
    });

    test('finds people: staff, a pupil with the class the planner shows, '
        'and a co-account with its description', () async {
      expect(
        await search('  janssens '),
        'The planner finds 3 for "janssens":\n'
        '- person | Jan Janssens | planner user/4069_1001_0\n'
        '- person | Lotte Janssens | listed as Janssens Lotte • 6A1 | '
        'planner user/4069_3001_0\n'
        '- person | ELS JANSSENS | Interimaris van Piet Peeters | planner '
        'user/4069_1004_1',
      );
      expect((planner.requests.single.data as Map)['searchString'], 'janssens');
    });

    test('finds a room', () async {
      expect(
        await search('101'),
        'The planner finds 1 for "101":\n'
        '- room | 101 | Locatie | planner '
        'location/4069_10000000-0000-4000-8000-000000000101',
      );
    });

    test('shows a hit of another kind without a planner id', () async {
      expect(
        await search('Bibliotheek'),
        'The planner finds 1 for "Bibliotheek":\n'
        '- other (partner) | Bibliotheek Springfield | no planner',
      );
    });

    test('says when it finds nothing', () async {
      expect(
        await search('xyz'),
        startsWith('The planner finds nothing for "xyz". Check the spelling'),
      );
    });

    test('lists at most 50 hits and counts the rest', () async {
      for (var i = 0; i < 60; i++) {
        planner.hits.add(FakePlannerHit.group('4069_${5000 + i}', '7X$i'));
      }
      final lines = (await search('7X')).split('\n');
      expect(lines.first, 'The planner finds 60 for "7X":');
      expect(lines.where((line) => line.startsWith('- ')), hasLength(50));
      expect(
        lines.last,
        '10 more not listed: look for a longer part of the name to find '
        'fewer.',
      );
    });

    test('refuses an empty query without asking the planner', () async {
      expect(
        await error('search_planners', {'query': '   '}),
        'query is empty: pass the name to look for.',
      );
      expect(planner.requests, isEmpty);
    });
  });

  group('list_planner', () {
    test('lists the user\'s own planner from today to 7 days ahead by '
        'default, without the user as organiser', () async {
      final text = await list({});

      final query = planner.calendarQueries.single;
      expect(
        planner.requests.single.path,
        '/planner/api/v1/planned-elements/user/$fakePlannerMe',
      );
      expect(
        DateTime.parse(query['from']!).isAtSameMomentAs(DateTime(2026, 10, 5)),
        isTrue,
        reason: query['from'],
      );
      expect(
        DateTime.parse(
          query['to']!,
        ).isAtSameMomentAs(DateTime(2026, 10, 12, 23, 59, 59)),
        isTrue,
        reason: query['to'],
      );
      expect(query, isNot(contains('types')));
      expect(
        text,
        'Planner: your own planner (me), from Monday 2026-10-05 to Monday '
        '2026-10-12: 1 element (1 lesson).\n'
        'Monday 2026-10-05\n'
        '- 10:20–11:10 | lesson | Lussen: for en while | informatica | '
        '6A1, 6A2 | room 101 | id '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000007',
      );
    });

    test('takes "me" in any case, and an until without a from', () async {
      final text = await list({'planner': ' ME ', 'until': '2026-10-05'});
      expect(
        text,
        startsWith(
          'Planner: your own planner (me), from Monday 2026-10-05 to Monday '
          '2026-10-05: 1 element (1 lesson).',
        ),
      );
    });

    test('lists an empty lesson hour without a name, and runs until 7 days '
        'after a from given alone', () async {
      final text = await list({'from': '2026-11-16'});

      expect(
        DateTime.parse(
          planner.calendarQueries.single['to']!,
        ).isAtSameMomentAs(DateTime(2026, 11, 23, 23, 59, 59)),
        isTrue,
      );
      expect(
        text,
        'Planner: your own planner (me), from Monday 2026-11-16 to Monday '
        '2026-11-23: 1 element (1 empty lesson hour).\n'
        'Friday 2026-11-20\n'
        '- 11:10–12:00 | empty lesson hour | informatica | 6A1, 6A2 | room '
        '101 | id planned-placeholders/4069/'
        'e0000000-0000-5000-8000-000000000006',
      );
    });

    test('lists a class planner per day: the elements of all who teach the '
        'class, an assignment with its type and deadline, a whole day, and '
        'an element of a type the library does not know', () async {
      final text = await list({
        'planner': _class6A1,
        'from': '2026-10-05',
        'until': '2026-10-09',
      });

      expect(
        planner.requests.single.path,
        '/planner/api/v1/planned-elements/group/4069_2001',
      );
      expect(
        text,
        'Planner: planner group/4069_2001 (6A1), from Monday 2026-10-05 to '
        'Friday 2026-10-09: 6 elements (3 lessons, 1 assignment, 1 empty '
        'lesson hour, 1 other).\n'
        'Monday 2026-10-05\n'
        '- 10:20–11:10 | lesson | Lussen: for en while | informatica | '
        '6A1, 6A2 | by Jan Peeters | room 101 | id '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000007\n'
        '- 14:40–15:30 | empty lesson hour | wiskunde | 6A1, 6B1 | by Piet '
        'Peeters | rooms 101, 102 | id '
        'planned-placeholders/4069/e0000000-0000-5000-8000-000000000001\n'
        'Tuesday 2026-10-06\n'
        '- 08:30 (deadline) | assignment KO Kleine Overhoring | Test: '
        'hoofdstuk 3 | Nederlands | 6A1 | by Piet Peeters | room 102 | id '
        'planned-assignments/4069/e0000000-0000-4000-8000-000000000003\n'
        'Wednesday 2026-10-07\n'
        '- 10:20–11:10 | lesson | Volleybal: de opslag | lichamelijke '
        'opvoeding | 6A1 | by Wim Willems | id '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000004\n'
        'Thursday 2026-10-08\n'
        '- whole day | planned-excursions | Uitstap naar Brussel | 6A1 | by '
        'Piet Peeters | id '
        'planned-excursions/4069/e0000000-0000-4000-8000-000000000005\n'
        'Friday 2026-10-09\n'
        '- 14:40–15:30 | lesson | Erfelijkheid | biologie | 6A1, 6A2 | by '
        'Wim Willems | room 103 | id '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000002',
      );
    });

    test('lists a colleague\'s planner, named after the colleague', () async {
      final text = await list({
        'planner': _piet,
        'from': '2026-10-05',
        'until': '2026-10-09',
      });
      expect(
        text,
        startsWith(
          'Planner: planner user/4069_1002_0 (Piet Peeters), from Monday '
          '2026-10-05 to Friday 2026-10-09: 3 elements (1 assignment, 1 '
          'empty lesson hour, 1 other).\n',
        ),
      );
      expect(RegExp(r'\| by Piet Peeters \|').allMatches(text), hasLength(3));
    });

    test('lists a room\'s planner, to see when the room is taken', () async {
      final text = await list({
        'planner': fakeRoom101.planner,
        'from': '2026-10-05 08:00',
        'until': '2026-10-05 12:00',
      });

      final query = planner.calendarQueries.single;
      expect(
        DateTime.parse(
          query['from']!,
        ).isAtSameMomentAs(DateTime(2026, 10, 5, 8)),
        isTrue,
      );
      expect(
        DateTime.parse(
          query['to']!,
        ).isAtSameMomentAs(DateTime(2026, 10, 5, 12)),
        isTrue,
      );
      expect(
        text,
        'Planner: planner '
        'location/4069_10000000-0000-4000-8000-000000000101 (101), from '
        'Monday 2026-10-05 08:00 to Monday 2026-10-05 12:00: 1 element (1 '
        'lesson).\n'
        'Monday 2026-10-05\n'
        '- 10:20–11:10 | lesson | Lussen: for en while | informatica | '
        '6A1, 6A2 | by Jan Peeters | room 101 | id '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000007',
      );
    });

    test('says when nothing is planned', () async {
      expect(
        await list({'from': '2026-12-24', 'until': '2026-12-26'}),
        'Planner: your own planner (me), from Thursday 2026-12-24 to '
        'Saturday 2026-12-26: nothing planned.',
      );
    });

    group('with types', () {
      Future<String> listTypes(List<String> types) => list({
        'planner': _class6A1,
        'from': '2026-10-05',
        'until': '2026-10-09',
        'types': types,
      });

      test('asks the planner for those types only', () async {
        final text = await listTypes(['assignments']);
        expect(planner.calendarQueries.single['types'], 'planned-assignments');
        expect(
          text,
          'Planner: planner group/4069_2001 (6A1), from Monday 2026-10-05 '
          'to Friday 2026-10-09 (only assignments): 1 element (1 '
          'assignment).\n'
          'Tuesday 2026-10-06\n'
          '- 08:30 (deadline) | assignment KO Kleine Overhoring | Test: '
          'hoofdstuk 3 | Nederlands | 6A1 | by Piet Peeters | room 102 | id '
          'planned-assignments/4069/e0000000-0000-4000-8000-000000000003',
        );
      });

      test('sends several types comma-separated', () async {
        final text = await listTypes(['empty_lesson_hours', 'lessons']);
        expect(
          planner.calendarQueries.single['types'],
          'planned-lessons,planned-placeholders',
        );
        expect(
          text.split('\n').first,
          'Planner: planner group/4069_2001 (6A1), from Monday 2026-10-05 '
          'to Friday 2026-10-09 (only lessons, empty lesson hours): 4 '
          'elements (3 lessons, 1 empty lesson hour).',
        );
      });

      test('reads every type for other, and keeps the ones that are not a '
          'lesson, assignment or empty lesson hour', () async {
        final text = await listTypes(['other']);
        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(
          text,
          'Planner: planner group/4069_2001 (6A1), from Monday 2026-10-05 '
          'to Friday 2026-10-09 (only other): 1 element (1 other).\n'
          'Thursday 2026-10-08\n'
          '- whole day | planned-excursions | Uitstap naar Brussel | 6A1 | '
          'by Piet Peeters | id '
          'planned-excursions/4069/e0000000-0000-4000-8000-000000000005',
        );
      });

      test('reads every type when all are named', () async {
        final text = await listTypes([
          'lessons',
          'assignments',
          'empty_lesson_hours',
          'other',
        ]);
        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(text, contains('6 elements'));
        expect(text, isNot(contains('(only')));
      });
    });

    test('prints the time of this PC for a lesson in summer time (+02:00) '
        'and one in winter time (+01:00)', () async {
      const summer = '2026-10-05T10:20:00+02:00';
      const summerEnd = '2026-10-05T11:10:00+02:00';
      const winter = '2026-11-20T11:10:00+01:00';
      const winterEnd = '2026-11-20T12:00:00+01:00';
      for (final (id, from, to) in [
        ('e0000000-0000-4000-8000-0000000000a1', summer, summerEnd),
        ('e0000000-0000-4000-8000-0000000000a2', winter, winterEnd),
      ]) {
        planner.add(
          FakePlannedElement(
            id: id,
            type: 'planned-lessons',
            name: 'Les',
            from: from,
            to: to,
            groups: [const FakePlannerGroup('4069_2009', '6C1')],
          ),
          calendars: ['group/4069_2009'],
        );
      }

      final text = await list({
        'planner': 'group/4069_2009',
        'from': '2026-10-01',
        'until': '2026-11-30',
      });

      final lines = text.split('\n').where((line) => line.startsWith('- '));
      expect(lines, [
        startsWith('- ${_clock(summer)}–${_clock(summerEnd)} | lesson | Les'),
        startsWith('- ${_clock(winter)}–${_clock(winterEnd)} | lesson | Les'),
      ]);
      if (_belgianTime) {
        // The planner's own clock: 10:20 in October, 11:10 in November.
        expect(lines, [
          startsWith('- 10:20–11:10 |'),
          startsWith('- 11:10–12:00 |'),
        ]);
      }
    });

    test('shows at most 200 elements, and says how to narrow down', () async {
      for (var i = 0; i < 250; i++) {
        final day = DateTime(2026, 9, 1).add(Duration(days: i ~/ 5));
        final hour = 8 + i % 5;
        planner.add(
          FakePlannedElement(
            id: 'e0000000-0000-5000-8000-${(1000 + i).toString().padLeft(12, '0')}',
            type: 'planned-placeholders',
            from: plannerTime(day.year, day.month, day.day, hour),
            to: plannerTime(day.year, day.month, day.day, hour, 50),
            groups: [fake6B1],
          ),
          calendars: ['group/4069_2003'],
        );
      }

      final text = await list({
        'planner': 'group/4069_2003',
        'from': '2026-09-01',
        'until': '2027-06-30',
      });

      final lines = text.split('\n');
      expect(
        lines.first,
        'Planner: planner group/4069_2003 (6B1), from Tuesday 2026-09-01 to '
        'Wednesday 2027-06-30: 251 elements (251 empty lesson hours).',
      );
      expect(lines.where((line) => line.startsWith('- ')), hasLength(200));
      expect(
        lines.last,
        'Note: only the first 200 of the 251 are shown, up to Saturday '
        '2026-10-10. For fewer, list a shorter period, or only some types '
        '(such as assignments).',
      );
    });

    group('refuses', () {
      test('a planner that is not me or a planner id, without asking the '
          'planner', () async {
        for (final value in [
          '6A1',
          'klas/4069_2001',
          'group/6A1',
          'user/4069_1002',
          'location/10000000-0000-4000-8000-000000000101',
        ]) {
          expect(
            await error('list_planner', {'planner': value}),
            'planner must be me (your own planner) or a planner id as '
            'search_planners shows it, like user/4069_218_0 (a person), '
            'group/4069_4256 (a class) or location/4069_<id> (a room); '
            '"$value" is not.',
          );
        }
        expect(planner.requests, isEmpty);
      });

      test('an invalid date, or an until before from', () async {
        expect(
          await error('list_planner', {'from': '5 oktober'}),
          'from must be a date like 2024-03-15, or a date and time like '
          '2024-03-15 14:30; "5 oktober" is not.',
        );
        expect(
          await error('list_planner', {
            'from': '2026-10-09',
            'until': '2026-10-05',
          }),
          'until must not be before from.',
        );
        expect(
          await error('list_planner', {'until': '2026-10-01'}),
          'until must not be before from (today when it is not given).',
        );
        expect(planner.requests, isEmpty);
      });
    });

    test('says when the planner gives an answer it cannot use, without '
        'quoting it', () async {
      final text = await error('list_planner', {'planner': 'group/4069_9999'});
      expect(
        text,
        'The planner gave an answer the server could not use (HTTP 400). Try '
        'again in a moment; the technical details are in the server log.',
      );
      expect(text, isNot(contains('Bad Request')));
    });

    test('logs in again when the session expired', () async {
      await list({'from': '2026-10-05', 'until': '2026-10-05'});
      final logins = server.logins;
      server.expireSessionBefore(
        (request) => request.uri.path.startsWith('/planner/'),
      );

      final text = await list({'planner': _class6A1, 'from': '2026-10-06'});

      expect(server.logins, logins + 1);
      expect(text, contains('Test: hoofdstuk 3'));
    });
  });

  group('read_planned_element', () {
    test('reads a colleague\'s lesson with its info as text, its labels, '
        'attachments and weblinks', () async {
      final text = await read(fakeLesson.ref);

      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-lessons/4069/'
            'e0000000-0000-4000-8000-000000000002',
      ]);
      expect(
        text,
        'Planner element '
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000002\n'
        'Kind: lesson\n'
        'Name: Erfelijkheid\n'
        'When: Friday 2026-10-09 14:40–15:30\n'
        'Course: biologie\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Wim Willems\n'
        'Room: 103\n'
        'Labels: JAAR 6, TRIMESTER 1\n'
        'Attachments: hoofdstuk4.pdf\n'
        'Weblinks: Opdracht (https://example.com/opdracht)\n'
        '\n'
        'Public info (what pupils see):\n'
        'Lees hoofdstuk 4\n'
        '\n'
        'Private info (hidden from pupils, but colleagues who can read this '
        'element see it too):\n'
        'Opmerkingen\n'
        'Boek meebrengen',
      );
      expect(text, isNot(contains('<')), reason: 'no raw HTML');
    });

    test('reads an assignment with its type, deadline, visibility, '
        'announcement and status', () async {
      final text = await read('id ${fakeAssignment.ref}');
      expect(
        text,
        'Planner element '
        'planned-assignments/4069/e0000000-0000-4000-8000-000000000003\n'
        'Kind: assignment KO Kleine Overhoring\n'
        'Name: Test: hoofdstuk 3\n'
        'When: Tuesday 2026-10-06 08:30 (deadline)\n'
        'Course: Nederlands\n'
        'Classes: 6A1\n'
        'Organised by: Piet Peeters\n'
        'Room: 102\n'
        'Visible to pupils from: 2026-09-26 10:50\n'
        'Announced: no\n'
        'Status: unresolved\n'
        '\n'
        'Public info (what pupils see):\n'
        '(none)\n'
        '\n'
        'Private info (hidden from pupils, but colleagues who can read this '
        'element see it too):\n'
        '(none)',
      );
    });

    test('reads an empty lesson hour of the own planner, which has no name '
        'or info', () async {
      expect(
        await read(fakeOwnSlot.ref),
        'Planner element '
        'planned-placeholders/4069/e0000000-0000-5000-8000-000000000006\n'
        'Kind: empty lesson hour\n'
        'When: Friday 2026-11-20 11:10–12:00\n'
        'Course: informatica\n'
        'Classes: 6A1, 6A2\n'
        'Organised by: Jan Peeters\n'
        'Room: 101',
      );
    });

    test('reads an element of a type the library does not know', () async {
      final text = await read(fakeExcursion.ref);
      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-excursions/4069/'
            'e0000000-0000-4000-8000-000000000005',
      ]);
      expect(
        text,
        startsWith(
          'Planner element '
          'planned-excursions/4069/e0000000-0000-4000-8000-000000000005\n'
          'Kind: planned-excursions\n'
          'Name: Uitstap naar Brussel\n'
          'When: Thursday 2026-10-08 whole day\n',
        ),
      );
    });

    test('says that an element the planner no longer has is gone, and to '
        'list the planner again', () async {
      const gone =
          'planned-placeholders/4069/e0000000-0000-5000-8000-00000000dead';
      expect(
        await error('read_planned_element', {'id': gone}),
        'The planner has no element $gone (any more). It was removed, or its '
        'id changed: a lesson hour that is filled or cleared gets a new id. '
        'List the planner again with list_planner and take the id from '
        'there.',
      );
    });

    test('says when the planner gives an answer it cannot use', () async {
      planner.failing['/planner/api/v1/planned-lessons/4069/'
              'e0000000-0000-4000-8000-000000000002'] =
          500;
      expect(
        await error('read_planned_element', {'id': fakeLesson.ref}),
        'The planner gave an answer the server could not use (HTTP 500). Try '
        'again in a moment; the technical details are in the server log.',
      );
    });

    test('refuses an id that is not an element id, without asking the '
        'planner', () async {
      for (final id in [
        'e0000000-0000-4000-8000-000000000002',
        'planned-lessons/4069',
        'lessons/4069/e0000000-0000-4000-8000-000000000002',
        'planned-lessons/school/e0000000-0000-4000-8000-000000000002',
        'planned-lessons/4069/e0000000 0000',
        'planned-lessons/4069/e0000000-0000-4000-8000-000000000002/rename',
      ]) {
        expect(
          await error('read_planned_element', {'id': id}),
          'id must be the id of a planner element as list_planner shows it: '
          'its type, platform and id, like '
          'planned-lessons/4069/225c0b54-0000-4000-8000-000000000000; "$id" '
          'is not.',
        );
      }
      expect(planner.requests, isEmpty);
    });
  });
}
