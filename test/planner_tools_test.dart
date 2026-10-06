/// `search_planners`, `list_planner` and `read_planned_element`, called over
/// MCP on the real server, session and library, against a fake Smartschool
/// whose planner serves dartschool's anonymised captures of the live
/// planner (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/planner/planner_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/search_planners_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _class6A1 = 'group/4069_2001';
const _piet = 'user/4069_1002_0';

/// Where the planner's lookup of a planner by its id goes
/// (`PlannerService.getCalendar`).
const _lookupPath = '/planner/api/v1/quick-search/planner/start';

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
          'enum': [
            'lessons',
            'assignments',
            'empty_lesson_hours',
            'meetings',
            'lesson_free_days',
            'other',
          ],
          'type': 'string',
        },
      });
      expect(listTool.description, contains('at most 200 lines'));
      expect(listTool.description, contains('search_planners'));
      expect(listTool.description, contains('read_planned_element'));
    });

    test('list_planner names the kinds it shows (#94), takes each of them '
        'in types, and says that other holds the kinds it does not name '
        '(#103)', () {
      final listTool = tools['list_planner']!;
      expect(
        listTool.description,
        contains(
          'meeting, such as a class council; lesson-free day, such as a '
          'holiday, which can run over several days; or the planner\'s name '
          'of another type',
        ),
      );
      expect(
        (listTool.inputSchema.properties!['types']! as Map)['description'],
        contains(
          'meetings (such as class councils), lesson_free_days (such as '
          'holidays) and/or other (every kind not named here, such as '
          'excursions)',
        ),
      );
      // A types value for every kind the header counts, in its order.
      expect([
        for (final kind in PlannerKind.values) kind.kind,
      ], PlannedElementKind.values);
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
      // The elements name the planner: no lookup.
      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-elements/$_piet',
      ]);
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

    test('says when nothing is planned, without a note for the user\'s own '
        'planner, and without looking it up', () async {
      expect(
        await list({'from': '2026-12-24', 'until': '2026-12-26'}),
        'Planner: your own planner (me), from Thursday 2026-12-24 to '
        'Saturday 2026-12-26: nothing planned.',
      );
      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-elements/user/$fakePlannerMe',
      ]);
    });

    test('names a planner with nothing planned with the planner\'s lookup '
        'of its id: a class, a colleague, a room, and the user\'s own '
        'planner given by its id (#102)', () async {
      // Nothing is planned in these days, so no element names the planner.
      // The planner names the user's own planner %quicksearch.me%, which
      // the library replaces with the user's name.
      for (final (id, field, name) in [
        (_class6A1, 'groups', '6A1'),
        (_piet, 'users', 'Piet Peeters'),
        (fakeRoom101.planner, 'miniDbItems', '101'),
        ('user/$fakePlannerMe', 'users', 'Jan Peeters'),
      ]) {
        planner.requests.clear();

        final text = await list({
          'planner': id,
          'from': '2026-12-24',
          'until': '2026-12-26',
        });

        expect(plannerRequests(), [
          'GET /planner/api/v1/planned-elements/$id',
          'POST $_lookupPath',
        ], reason: id);
        final calendarId = id.substring(id.indexOf('/') + 1);
        expect(planner.requests.last.data, {
          for (final kind in ['users', 'groups', 'miniDbItems'])
            kind: [if (kind == field) calendarId],
        }, reason: id);
        expect(
          text,
          'Planner: planner $id ($name), from Thursday 2026-12-24 to '
          'Saturday 2026-12-26: nothing planned.',
        );
      }
      expect(planner.writes, isEmpty);
    });

    test('looks up a planner when none of the kinds asked for is planned, '
        'as the planner was asked for those kinds only (#102)', () async {
      // 6A1 has its assignment on Tuesday, and lessons on Wednesday and
      // Friday.
      final text = await list({
        'planner': _class6A1,
        'from': '2026-10-07',
        'until': '2026-10-09',
        'types': ['assignments'],
      });

      expect(planner.calendarQueries.single['types'], 'planned-assignments');
      expect(plannerRequests().last, 'POST $_lookupPath');
      expect(
        text,
        'Planner: planner group/4069_2001 (6A1), from Wednesday 2026-10-07 '
        'to Friday 2026-10-09 (only assignments): nothing planned.',
      );
    });

    test('marks a person the planner counts as deleted, whom its lookup '
        'names (#102)', () async {
      planner.hits.add(
        FakePlannerHit.user(
          const FakePlannerUser('4069_1006_0', 'Karel Claes', 'Claes Karel'),
          deleted: true,
        ),
      );

      expect(
        await list({
          'planner': 'user/4069_1006_0',
          'from': '2026-10-05',
          'until': '2026-10-09',
        }),
        'Planner: planner user/4069_1006_0 (Karel Claes, deleted user), from '
        'Monday 2026-10-05 to Friday 2026-10-09: nothing planned.',
      );
    });

    test('says plainly when a planner id names no planner: the planner\'s '
        'lookup does not know it, and the planner answers it as an empty '
        'planner (#102)', () async {
      // As the live planner answered a room it does not have, and a group
      // that its search does not offer: an empty list.
      for (final (id, field) in [
        ('location/4069_10000000-0000-4000-8000-000000000999', 'miniDbItems'),
        ('group/4069_9', 'groups'),
      ]) {
        planner.requests.clear();

        final text = await list({
          'planner': id,
          'from': '2026-10-05',
          'until': '2026-10-09',
        });

        expect(plannerRequests(), [
          'GET /planner/api/v1/planned-elements/$id',
          'POST $_lookupPath',
        ]);
        expect((planner.requests.last.data as Map)[field], [
          id.substring(id.indexOf('/') + 1),
        ]);
        expect(
          text,
          'Planner: planner $id, from Monday 2026-10-05 to Friday '
          '2026-10-09: nothing planned.\n'
          'Note: the planner\'s search offers no class, person or room with '
          'the planner id $id, and Smartschool answers such an id as an '
          'empty planner, so this does not mean that a planner is free. '
          'Check the planner id with search_planners.',
        );
      }
    });

    test('says that the planner cannot be named when its lookup fails, and '
        'still says that nothing is planned (#102)', () async {
      planner.failing[_lookupPath] = 500;

      final text = await list({
        'planner': _piet,
        'from': '2026-12-24',
        'until': '2026-12-26',
      });

      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-elements/$_piet',
        'POST $_lookupPath',
      ]);
      expect(
        text,
        'Planner: planner $_piet, from Thursday 2026-12-24 to Saturday '
        '2026-12-26: nothing planned.\n'
        'Note: with nothing planned, the planner cannot be named, and '
        'looking up its id failed (the details are in the server log). '
        'Smartschool answers some planner ids that name no planner as an '
        'empty planner. If you expected elements, check the planner id with '
        'search_planners.',
      );
    });

    test('names the planner from the elements of the kinds left out, and '
        'then needs no note when none of the kinds asked for is planned '
        '(#93)', () async {
      // 6A1 has lessons, an assignment and an empty lesson hour from
      // Monday to Wednesday, and its element of another type on Thursday.
      final text = await list({
        'planner': _class6A1,
        'from': '2026-10-05',
        'until': '2026-10-07',
        'types': ['other'],
      });
      expect(
        text,
        'Planner: planner group/4069_2001 (6A1), from Monday 2026-10-05 to '
        'Wednesday 2026-10-07 (only other): nothing planned.',
      );
      // The elements read name the planner: no lookup (#102).
      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-elements/$_class6A1',
      ]);
    });

    group('names meetings and lesson-free days, counts them by kind (#94), '
        'and takes them in types (#103)', () {
      // The shapes of the live listing of #71, in the user's own planner,
      // next to its elements of the captures.
      setUp(() {
        for (final element in [fakeMeeting, fakeLessonFreeDay]) {
          planner.add(element, calendars: ['user/$fakePlannerMe']);
        }
      });

      test('a lesson-free day of a week on the day it starts, and a '
          'meeting', () async {
        final text = await list({'from': '2026-11-02', 'until': '2026-11-09'});
        expect(
          text,
          'Planner: your own planner (me), from Monday 2026-11-02 to Monday '
          '2026-11-09: 2 elements (1 meeting, 1 lesson-free day).\n'
          'Monday 2026-11-02\n'
          '- whole day until 2026-11-08 | lesson-free day | Herfstvakantie | '
          'Iedereen | id planned-lesson-free-days/4069/'
          'e0000000-0000-4000-8000-0000000000b2\n'
          'Monday 2026-11-09\n'
          '- 12:00–12:45 | meeting | BKR 6A1 | by Piet Peeters | room '
          'vergaderzaal | id '
          'planned-meetings/4069/e0000000-0000-4000-8000-0000000000b1',
        );
      });

      test('after the kinds named before, with the plural for two '
          'meetings', () async {
        planner.add(
          fakeMeeting.inSameHour(
            id: 'e0000000-0000-4000-8000-0000000000b3',
            type: 'planned-meetings',
            name: 'Personeelsvergadering',
          ),
          calendars: ['user/$fakePlannerMe'],
        );

        final text = await list({'from': '2026-11-02', 'until': '2026-11-20'});

        expect(
          text.split('\n').first,
          'Planner: your own planner (me), from Monday 2026-11-02 to Friday '
          '2026-11-20: 4 elements (1 empty lesson hour, 2 meetings, 1 '
          'lesson-free day).',
        );
        expect(
          text,
          contains(
            '- 12:00–12:45 | meeting | Personeelsvergadering | by Piet '
            'Peeters | room vergaderzaal |',
          ),
        );
      });

      test('lists only meetings for types meetings, and only lesson-free '
          'days for lesson_free_days, kept from every type read: the planner '
          'is not asked for them (#103)', () async {
        final meetings = await list({
          'from': '2026-11-02',
          'until': '2026-11-20',
          'types': ['meetings'],
        });
        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(
          meetings,
          'Planner: your own planner (me), from Monday 2026-11-02 to Friday '
          '2026-11-20 (only meetings): 1 element (1 meeting).\n'
          'Monday 2026-11-09\n'
          '- 12:00–12:45 | meeting | BKR 6A1 | by Piet Peeters | room '
          'vergaderzaal | id '
          'planned-meetings/4069/e0000000-0000-4000-8000-0000000000b1',
        );

        planner.requests.clear();
        final lessonFreeDays = await list({
          'from': '2026-11-02',
          'until': '2026-11-20',
          'types': ['lesson_free_days'],
        });
        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(
          lessonFreeDays,
          'Planner: your own planner (me), from Monday 2026-11-02 to Friday '
          '2026-11-20 (only lesson-free days): 1 element (1 lesson-free '
          'day).\n'
          'Monday 2026-11-02\n'
          '- whole day until 2026-11-08 | lesson-free day | Herfstvakantie | '
          'Iedereen | id planned-lesson-free-days/4069/'
          'e0000000-0000-4000-8000-0000000000b2',
        );
      });

      test('keeps under other only the kinds the tool does not name, no '
          'meetings or lesson-free days (#103)', () async {
        planner.add(
          fakeMeeting.inSameHour(
            id: 'e0000000-0000-4000-8000-0000000000b4',
            type: 'planned-school-activities',
            name: 'Infomoment',
          ),
          calendars: ['user/$fakePlannerMe'],
        );

        final text = await list({
          'from': '2026-11-02',
          'until': '2026-11-20',
          'types': ['other'],
        });

        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(
          text,
          'Planner: your own planner (me), from Monday 2026-11-02 to Friday '
          '2026-11-20 (only other): 1 element (1 other).\n'
          'Monday 2026-11-09\n'
          '- 12:00–12:45 | planned-school-activities | Infomoment | by Piet '
          'Peeters | room vergaderzaal | id '
          'planned-school-activities/4069/'
          'e0000000-0000-4000-8000-0000000000b4',
        );
      });

      test('reads every type when one of the kinds is kept here, as for '
          'lessons and meetings, and asks the planner for the types when '
          'none is (#103)', () async {
        final text = await list({
          'from': '2026-10-05',
          'until': '2026-11-20',
          'types': ['lessons', 'meetings'],
        });
        // Never planned-meetings, which was never tried live: the lessons
        // and the meetings are both kept here.
        expect(planner.calendarQueries.single, isNot(contains('types')));
        expect(
          text,
          'Planner: your own planner (me), from Monday 2026-10-05 to Friday '
          '2026-11-20 (only lessons, meetings): 2 elements (1 lesson, 1 '
          'meeting).\n'
          'Monday 2026-10-05\n'
          '- 10:20–11:10 | lesson | Lussen: for en while | informatica | '
          '6A1, 6A2 | room 101 | id '
          'planned-lessons/4069/e0000000-0000-4000-8000-000000000007\n'
          'Monday 2026-11-09\n'
          '- 12:00–12:45 | meeting | BKR 6A1 | by Piet Peeters | room '
          'vergaderzaal | id '
          'planned-meetings/4069/e0000000-0000-4000-8000-0000000000b1',
        );

        planner.requests.clear();
        final lessonHours = await list({
          'from': '2026-10-05',
          'until': '2026-11-20',
          'types': ['empty_lesson_hours', 'lessons'],
        });
        expect(
          planner.calendarQueries.single['types'],
          'planned-lessons,planned-placeholders',
        );
        expect(
          lessonHours.split('\n').first,
          'Planner: your own planner (me), from Monday 2026-10-05 to Friday '
          '2026-11-20 (only lessons, empty lesson hours): 2 elements (1 '
          'lesson, 1 empty lesson hour).',
        );
      });
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

      test('reads every type for other, and keeps the ones the tool does not '
          'name', () async {
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
          'meetings',
          'lesson_free_days',
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
      planner.failing['/planner/api/v1/planned-elements/group/4069_2001'] = 400;
      final text = await error('list_planner', {'planner': _class6A1});
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

    test('names a meeting and a lesson-free day (#94)', () async {
      for (final element in [fakeMeeting, fakeLessonFreeDay]) {
        planner.add(element, calendars: ['user/$fakePlannerMe']);
      }

      expect(
        await read(fakeMeeting.ref),
        startsWith(
          'Planner element '
          'planned-meetings/4069/e0000000-0000-4000-8000-0000000000b1\n'
          'Kind: meeting\n'
          'Name: BKR 6A1\n'
          'When: Monday 2026-11-09 12:00–12:45\n'
          'Organised by: Piet Peeters\n'
          'Room: vergaderzaal\n'
          '\n'
          'Public info',
        ),
      );
      expect(
        await read(fakeLessonFreeDay.ref),
        startsWith(
          'Planner element '
          'planned-lesson-free-days/4069/e0000000-0000-4000-8000-0000000000b2\n'
          'Kind: lesson-free day\n'
          'Name: Herfstvakantie\n'
          'When: Monday 2026-11-02 whole day until 2026-11-08\n'
          'Classes: Iedereen\n'
          '\n'
          'Public info',
        ),
      );
      expect(plannerRequests(), [
        'GET /planner/api/v1/planned-meetings/4069/'
            'e0000000-0000-4000-8000-0000000000b1',
        'GET /planner/api/v1/planned-lesson-free-days/4069/'
            'e0000000-0000-4000-8000-0000000000b2',
      ]);
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
