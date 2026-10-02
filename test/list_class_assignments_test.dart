/// `list_class_assignments`, called over MCP on the real server, session
/// and library, against a fake Smartschool whose planner serves
/// dartschool's anonymised captures of the live planner and its workload
/// view (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_class_assignments_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _class6A1 = 'group/4069_2001';
const _class6A2 = 'group/4069_2002';

const _api = '/planner/api/v1';

const _types =
    'Assignment types of the school: GO Grote Overhoring, GT Grote Taak, KO '
    'Kleine Overhoring, KT Kleine Taak, MB Meebrengen, V Voorbereiding.';

/// The lines of the captured assignments of 6A1 and 6A2 in the week of
/// 2026-10-05, per day: three on Monday (two of them in the same hour, by
/// name), one on Tuesday.
const _monday =
    'Monday 2026-10-05\n'
    '- 09:20 (deadline) | assignment MB Meebrengen | Rekenmachine meebrengen '
    '| economie | 6A1, 6A2 | by An Claes | room 105 | id '
    'planned-assignments/4069/e0000000-0000-4000-8000-000000000013\n'
    '- 09:20 (deadline) | assignment KO Kleine Overhoring | Test: begroting | '
    'economie | 6A1, 6A2 | by An Claes | room 105 | id '
    'planned-assignments/4069/e0000000-0000-4000-8000-000000000014\n'
    '- 12:50 (deadline) | assignment GO Grote Overhoring | Toets: atoombouw | '
    'chemie | 6A1, 6A2, 6D2, 6D1, 6C2, 6C1 | by Wim Willems | room 104 | id '
    'planned-assignments/4069/e0000000-0000-4000-8000-000000000012';
const _tuesday =
    'Tuesday 2026-10-06\n'
    '- 08:30 (deadline) | assignment KO Kleine Overhoring | Test: hoofdstuk 3 '
    '| Nederlands | 6A1 | by Piet Peeters | room 102 | id '
    'planned-assignments/4069/e0000000-0000-4000-8000-000000000003';

/// Whether the moment [iso] the planner was sent is [expected].
Matcher _moment(DateTime expected) => predicate<String>(
  (iso) => DateTime.parse(iso).isAtSameMomentAs(expected),
  'the moment $expected',
);

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
    (connection, _) = await connect(
      tools: [
        listClassAssignmentsTool(
          session,
          now: () => DateTime(2026, 10, 5, 9, 30),
        ),
      ],
    );
  });

  Future<String> list(Map<String, Object?> arguments) async {
    final (result, text) = await callTool(
      connection,
      'list_class_assignments',
      arguments,
    );
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(Map<String, Object?> arguments) async {
    final (result, text) = await callTool(
      connection,
      'list_class_assignments',
      arguments,
    );
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// The planner requests that reached the fake, as `METHOD path`.
  List<String> plannerRequests() => [
    for (final request in planner.requests) '${request.method} ${request.path}',
  ];

  /// The request that reached the fake at [path].
  ({String method, String path, Map<String, String> query, Object? data})
  requestTo(String path) =>
      planner.requests.singleWhere((request) => request.path == path);

  test('is listed read-only and idempotent, takes classes and a period, and '
      'says it lists everyone\'s assignments and plans nothing', () async {
    final tool = (await connection.listTools(ListToolsRequest())).tools.single;

    expect(tool.name, 'list_class_assignments');
    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isTrue);
    expect(annotations.idempotentHint, isTrue);
    expect(annotations.openWorldHint, isTrue);
    expect(annotations.destructiveHint, isNot(true));
    expect(tool.inputSchema.required, ['classes']);
    expect(tool.inputSchema.properties!.keys, ['classes', 'from', 'until']);
    expect(tool.inputSchema.properties!['classes'], {
      'type': 'array',
      'description': contains('1 to 10 classes'),
      'items': {'type': 'string'},
    });
    for (final part in [
      'those of everyone who teaches the classes, not only your own',
      'search_planners',
      'at most 10',
      '"no assignments"',
      'read_planned_element',
      'workload limit',
      'list_planner with planner me',
      'this tool only reads and never plans anything',
      '"wanneer kan ik best een toets plannen in 6WEWI1?"',
    ]) {
      expect(tool.description, contains(part));
    }
  });

  test('lists two classes in one request, per day in date order: the '
      'assignments of everyone, every weekday without one as "no '
      'assignments", and the school\'s assignment types', () async {
    final text = await list({
      'classes': [_class6A1, _class6A2],
      'from': '2026-10-05',
      'until': '2026-10-11',
    });

    expect(plannerRequests(), [
      'POST $_api/workload/planned-elements',
      'POST $_api/workload/schedule',
      'GET $fakeAssignmentTypesPath',
    ]);
    for (final path in [
      '$_api/workload/planned-elements',
      '$_api/workload/schedule',
    ]) {
      final query = requestTo(path).query;
      expect(query['from'], _moment(DateTime(2026, 10, 5)));
      expect(query['to'], _moment(DateTime(2026, 10, 11, 23, 59, 59)));
    }
    expect(requestTo('$_api/workload/planned-elements').data, {
      'users': <Object?>[],
      'groups': ['4069_2001', '4069_2002'],
      'courses': <Object?>[],
    });
    expect(requestTo('$_api/workload/schedule').data, {
      'groups': ['4069_2001', '4069_2002'],
    });
    expect(
      text,
      'Assignments (tests and tasks, by anyone) of 6A1 (group/4069_2001), '
      '6A2 (group/4069_2002), from Monday 2026-10-05 to Sunday 2026-10-11: '
      '4 assignments.\n'
      '$_monday\n'
      '$_tuesday\n'
      'Wednesday 2026-10-07: no assignments\n'
      'Thursday 2026-10-08: no assignments\n'
      'Friday 2026-10-09: no assignments\n'
      '$_types',
    );
  });

  test(
    'lists a Saturday or Sunday only when an assignment falls on it',
    () async {
      planner.add(
        FakePlannedElement(
          id: 'e0000000-0000-4000-8000-000000000020',
          type: 'planned-assignments',
          name: 'Werkstuk',
          from: plannerTime(2026, 10, 10, 10),
          to: plannerTime(2026, 10, 10, 10, 50),
          deadline: true,
          organisers: [fakePiet],
          groups: [fake6A2],
          assignmentType: FakeAssignmentType.kt,
        ),
        calendars: ['group/${fake6A2.id}'],
      );

      final text = await list({
        'classes': [_class6A2],
        'from': '2026-10-07',
        'until': '2026-10-11',
      });

      expect(
        text,
        'Assignments (tests and tasks, by anyone) of 6A2 (group/4069_2002), '
        'from Wednesday 2026-10-07 to Sunday 2026-10-11: 1 assignment.\n'
        'Wednesday 2026-10-07: no assignments\n'
        'Thursday 2026-10-08: no assignments\n'
        'Friday 2026-10-09: no assignments\n'
        'Saturday 2026-10-10\n'
        '- 10:00 (deadline) | assignment KT Kleine Taak | Werkstuk | 6A2 | by '
        'Piet Peeters | id '
        'planned-assignments/4069/e0000000-0000-4000-8000-000000000020\n'
        '$_types',
      );
    },
  );

  test('gives the workload limit of a class that has one, with the days the '
      'planner\'s figure is not 0, and nothing for a class without', () async {
    planner.workloadSettings[fake6A1.id] = const FakeWorkloadSetting(
      'b0000000-0000-4000-8000-000000000002',
      'Max 2 per dag',
      limit: 2,
    );
    planner.workloadWeights[(fake6A1.id, '2026-10-05')] = 3;
    planner.workloadWeights[(fake6A1.id, '2026-10-06')] = 1;
    // Geen limiet: the figure is not shown, whatever it is.
    planner.workloadWeights[(fake6A2.id, '2026-10-05')] = 3;

    final text = await list({
      'classes': [_class6A1, _class6A2],
      'from': '2026-10-05',
      'until': '2026-10-09',
    });

    expect(
      text,
      endsWith(
        'Friday 2026-10-09: no assignments\n'
        'Workload limits the school set, with the planner\'s own figures:\n'
        '- 6A1: limit 2 per day (soft); 2026-10-05 is at 3, 2026-10-06 is '
        'at 1\n'
        '$_types',
      ),
    );
    expect(text, isNot(contains('- 6A2:')));
  });

  test(
    'gives a limit at which every day is at 0, as the planner gives it',
    () async {
      planner.workloadSettings[fake6A2.id] = const FakeWorkloadSetting(
        'b0000000-0000-4000-8000-000000000003',
        'Max 4 per week',
        limit: 4,
        period: 'week',
        type: 'hard',
      );

      final text = await list({
        'classes': [_class6A2],
        'from': '2026-10-12',
        'until': '2026-10-16',
      });

      expect(
        text,
        'Assignments (tests and tasks, by anyone) of 6A2 (group/4069_2002), '
        'from Monday 2026-10-12 to Friday 2026-10-16: no assignments.\n'
        'Workload limits the school set, with the planner\'s own figures:\n'
        '- 6A2: limit 4 per week (hard); every day is at 0\n'
        '$_types',
      );
    },
  );

  test(
    'says when a period has no assignments, without listing its days',
    () async {
      expect(
        await list({
          'classes': [_class6A1],
          'from': '2026-12-21',
          'until': '2027-01-01',
        }),
        'Assignments (tests and tasks, by anyone) of 6A1 (group/4069_2001), '
        'from Monday 2026-12-21 to Friday 2027-01-01: no assignments.\n'
        '$_types',
      );
    },
  );

  test('runs from today to 4 weeks ahead by default', () async {
    final text = await list({
      'classes': [_class6A1],
    });

    final query = requestTo('$_api/workload/planned-elements').query;
    expect(query['from'], _moment(DateTime(2026, 10, 5)));
    expect(query['to'], _moment(DateTime(2026, 11, 2, 23, 59, 59)));
    final lines = text.split('\n');
    expect(
      lines.first,
      'Assignments (tests and tasks, by anyone) of 6A1 (group/4069_2001), '
      'from Monday 2026-10-05 to Monday 2026-11-02: 4 assignments.',
    );
    // Monday 2026-10-05 to Monday 2026-11-02: 21 weekdays.
    expect(
      lines.where((line) => RegExp(r'^[A-Z][a-z]+day 20').hasMatch(line)),
      hasLength(21),
    );
    expect(lines[lines.length - 2], 'Monday 2026-11-02: no assignments');
  });

  test('counts and asks for a class named twice once', () async {
    for (var i = 1; i <= 3; i++) {
      planner.addClass(FakePlannerGroup('4069_${2100 + i}', '7A$i'));
    }
    final classes = [
      for (final id in [2001, 2002, 2003, 2004, 2005, 2006, 2007])
        'group/4069_$id',
      for (var i = 1; i <= 3; i++) 'group/4069_${2100 + i}',
    ];

    await list({
      'classes': [...classes, ' GROUP/4069_2001 '],
      'from': '2026-10-05',
      'until': '2026-10-09',
    });

    expect(
      (requestTo('$_api/workload/planned-elements').data as Map)['groups'],
      [for (final id in classes) id.substring('group/'.length)],
    );
  });

  test('reads the school\'s assignment types once per session, and again '
      'after a read that failed', () async {
    final arguments = {
      'classes': [_class6A1],
      'from': '2026-10-05',
      'until': '2026-10-09',
    };
    int typeReads() => [
      for (final request in planner.requests)
        if (request.path == fakeAssignmentTypesPath) request,
    ].length;

    planner.failing[fakeAssignmentTypesPath] = 403;
    final withoutTypes = await list(arguments);
    expect(withoutTypes, isNot(contains('Assignment types')));
    expect(withoutTypes, contains('$_tuesday\n'));
    expect(typeReads(), 1);

    planner.failing.clear();
    expect(await list(arguments), endsWith('\n$_types'));
    expect(await list(arguments), endsWith('\n$_types'));
    expect(typeReads(), 2);
  });

  test('lists the assignments when the workload cannot be read, and says '
      'that a limit is not shown', () async {
    planner.failing['$_api/workload/schedule'] = 500;

    final text = await list({
      'classes': [_class6A1],
      'from': '2026-10-05',
      'until': '2026-10-06',
    });

    expect(
      text,
      'Assignments (tests and tasks, by anyone) of 6A1 (group/4069_2001), '
      'from Monday 2026-10-05 to Tuesday 2026-10-06: 4 assignments.\n'
      '$_monday\n'
      '$_tuesday\n'
      'Note: the workload limits of these classes could not be read (HTTP '
      '500), so a limit is not shown; the assignments above are complete.\n'
      '$_types',
    );
  });

  test('shows at most 200 lines, whole days, and says where to go on', () async {
    for (var i = 0; i < 250; i++) {
      final day = DateTime(2026, 9, 1).add(Duration(days: i ~/ 5));
      planner.add(
        FakePlannedElement(
          id: 'e0000000-0000-4000-8000-${(1000 + i).toString().padLeft(12, '0')}',
          type: 'planned-assignments',
          name: 'Taak $i',
          from: plannerTime(day.year, day.month, day.day, 8 + i % 5),
          to: plannerTime(day.year, day.month, day.day, 8 + i % 5, 50),
          deadline: true,
          groups: [fake6B1],
          assignmentType: FakeAssignmentType.kt,
        ),
        calendars: ['group/${fake6B1.id}'],
      );
    }

    final lines = (await list({
      'classes': ['group/${fake6B1.id}'],
      'from': '2026-09-01',
      'until': '2026-10-31',
    })).split('\n');

    expect(
      lines.first,
      'Assignments (tests and tasks, by anyone) of 6B1 (group/4069_2003), '
      'from Tuesday 2026-09-01 to Saturday 2026-10-31: 250 assignments.',
    );
    // 33 days of a date and 5 assignments: 198 lines after the header.
    expect(lines.where((line) => line.startsWith('- ')), hasLength(165));
    expect(lines[193], 'Saturday 2026-10-03');
    expect(lines.sublist(199), [
      _types,
      'Note: only the days up to Saturday 2026-10-03 are shown (165 of the '
          '250 assignments). For the rest, list again from 2026-10-04.',
    ]);
  });

  group('refuses, without asking the planner,', () {
    test('more than 10 classes', () async {
      expect(
        await error({
          'classes': [for (var i = 0; i < 11; i++) 'group/4069_${3000 + i}'],
        }),
        'classes holds 11 classes, and at most 10 fit in one call: ask for '
        'the others in another call.',
      );
      expect(planner.requests, isEmpty);
    });

    test('no classes', () async {
      expect(
        await error({'classes': <String>[]}),
        'classes is empty: pass the planner ids of the classes, as '
        'search_planners shows them (like group/4069_4256).',
      );
      expect(planner.requests, isEmpty);
    });

    test('a class that is not a class planner id', () async {
      for (final value in [
        'me',
        '',
        '6A1',
        '4069_2001',
        'user/4069_1002_0',
        fakeRoom101.planner,
      ]) {
        expect(
          await error({
            'classes': [_class6A1, value],
          }),
          'each item of classes must be the planner id of a class as '
          'search_planners shows it, like group/4069_4256; "$value" is not.',
        );
      }
      expect(planner.requests, isEmpty);
    });

    test('an invalid date, or an until before from', () async {
      expect(
        await error({
          'classes': [_class6A1],
          'from': 'volgende week',
        }),
        'from must be a date like 2024-03-15, or a date and time like '
        '2024-03-15 14:30; "volgende week" is not.',
      );
      expect(
        await error({
          'classes': [_class6A1],
          'from': '2026-10-09',
          'until': '2026-10-05',
        }),
        'until must not be before from.',
      );
      expect(planner.requests, isEmpty);
    });
  });

  test('says when the planner gives an answer it cannot use, without '
      'quoting it', () async {
    final text = await error({
      'classes': ['group/4069_9999'],
    });
    expect(
      text,
      'The planner gave an answer the server could not use (HTTP 400). Try '
      'again in a moment; the technical details are in the server log.',
    );
    expect(text, isNot(contains('Bad Request')));
    expect(plannerRequests(), ['POST $_api/workload/planned-elements']);
  });
}
