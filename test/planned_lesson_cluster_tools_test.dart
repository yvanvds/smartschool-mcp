/// A lesson cluster of a year plan planned for classes in the planner
/// (#196, part 2 of #191): `plan_lesson_cluster`,
/// `list_planned_lesson_clusters` and `trash_planned_lesson_cluster`, and
/// how `list_planner` and `read_planned_element` name a planned cluster and
/// its moments. Called over MCP on the real server, session and library,
/// against a fake Smartschool whose planner plans, lists and trashes a
/// cluster with the requests of dartschool#230 (as tried live there,
/// `test/support/fake_planner.dart`) and whose Lesfiches module keeps the
/// year plans (`test/support/fake_year_plans.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_planned_lesson_clusters_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_lesson_cluster_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_planned_lesson_cluster_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/planner/api/v1';
const _planPath = '$_api/planned-lesson-clusters/';

const _planId = 'c0000000-0000-4000-8000-000000000001';
const _clusterId = 'c0000000-0000-4000-8000-000000000002';
const _otherClusterId = 'c0000000-0000-4000-8000-000000000003';
const _clusterPath =
    '$fakeYearPlansApi/4069/$_planId/lesson-clusters/4069/$_clusterId';

final _lussen = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000061',
  name: 'Lussen 1',
);
final _lussen2 = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000062',
  name: 'Lussen 2',
);

/// The id the fake gives the [n]th element its writes make, with [version]
/// as its third part.
String _madeId(int n, [String version = '4000']) =>
    'e0000000-0000-$version-9000-${'$n'.padLeft(12, '0')}';

/// The planned cluster the first plan makes.
final _plannedRef = 'planned-lesson-clusters/4069/${_madeId(1)}';

/// The moment the first plan makes of the own empty lesson hour of Friday
/// 2026-11-20 (after the two lesfiches of its content).
final _momentRef = 'planned-lesson-cluster-moments/4069/${_madeId(4, '6000')}';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner..loadCaptures();
    planner.lesfiches.addAll([_lussen, _lussen2]);
    server.yearPlans.plans.add(
      FakeYearPlan(
        id: _planId,
        name: 'Informatica 5',
        clusters: [
          FakeLessonCluster(
            id: _clusterId,
            name: 'Lussen',
            entries: [
              FakeClusterEntry.lesfiche(_lussen),
              FakeClusterEntry.lesfiche(_lussen2),
            ],
          ),
          FakeLessonCluster(id: _otherClusterId, name: 'Recursie'),
        ],
      ),
    );
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    DateTime now() => DateTime(2026, 11, 1, 9, 30);
    (connection, _) = await connect(
      tools: [
        listPlannerTool(session, now: now),
        readPlannedElementTool(session),
        planLessonClusterTool(session),
        listPlannedLessonClustersTool(session, now: now),
        trashPlannedLessonClusterTool(session),
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

  /// The plan of the cluster Lussen for 6A1, informatica, in the week of
  /// Monday 2026-11-16, by the own empty lesson hour of Friday 2026-11-20
  /// (classes 6A1 and 6A2).
  Map<String, Object?> planArguments({
    String cluster = _clusterId,
    String? hour,
    String from = '2026-11-16',
    String until = '2026-11-20',
    List<String>? classes = const ['6A1'],
  }) => {
    'year_plan': _planId,
    'cluster': cluster,
    'hour': hour ?? fakeOwnSlot.ref,
    'from': from,
    'until': until,
    'classes': ?classes,
  };

  Map<String, Object?> week() => {
    'from': '2026-11-16',
    'until': '2026-11-20',
    'types': ['empty_lesson_hours', 'lesson_cluster_moments'],
  };

  test('the plan and the trash ask approval and are not idempotent; the '
      'list only reads', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in [
      'plan_lesson_cluster',
      'trash_planned_lesson_cluster',
    ]) {
      final annotations = tools[name]!.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse, reason: name);
      expect(annotations.destructiveHint, isTrue, reason: name);
      expect(annotations.idempotentHint, isFalse, reason: name);
      expect(
        tools[name]!.description,
        contains('after the user has explicitly confirmed it'),
        reason: name,
      );
    }
    expect(tools['plan_lesson_cluster']!.description, contains('pupils'));
    expect(tools['plan_lesson_cluster']!.inputSchema.required, [
      'year_plan',
      'cluster',
      'hour',
      'from',
      'until',
    ]);
    final list = tools['list_planned_lesson_clusters']!.toolAnnotations!;
    expect(list.readOnlyHint, isTrue);
    expect(list.idempotentHint, isTrue);
  });

  test('plans a cluster for a class of an own hour: list_planner shows its '
      'moments, read_planned_element names the planned cluster and its '
      'link, the lists find it; the trash gives the hours back', () async {
    final planned = await ok('plan_lesson_cluster', planArguments());
    expect(
      planned,
      startsWith(
        'Planned the lesson cluster "Lussen" of the year plan "Informatica '
        '5" for 6A1 (informatica) from Monday 2026-11-16 to Friday '
        '2026-11-20. Pupils of 6A1 see its moments now',
      ),
    );
    expect(planned, contains('The planned cluster has the id $_plannedRef'));
    expect(planned, contains('Kind: planned lesson cluster'));
    expect(
      planned,
      contains('When: from Monday 2026-11-16 to Friday 2026-11-20'),
    );
    expect(
      planned,
      contains(
        'Planned from: the lesson cluster $_clusterId of the year plan '
        '$_planId',
      ),
    );
    expect(
      planned,
      contains('Lesfiches planned, in order:\n1. Lussen 1\n2. Lussen 2'),
    );

    final body =
        planner.requests
                .where((r) => r.method == 'POST' && r.path == _planPath)
                .single
                .data!
            as Map;
    expect(body['lessonClusterId'], _clusterId);
    expect(body['period'], {
      'dateTimeFrom': '2026-11-16',
      'dateTimeTo': '2026-11-20',
      'wholeDay': true,
    });
    expect((body['participants'] as Map)['groups'], ['4069_2001']);
    expect(body['courses'], [
      {'id': fakeInformatica.id, 'platformId': '4069'},
    ]);

    final listed = await ok('list_planner', week());
    expect(listed, contains('1 element (1 lesson cluster moment)'));
    expect(
      listed,
      contains(
        '- 11:10–12:00 | lesson cluster moment | of planned lesson cluster '
        'Lussen ($_plannedRef) | informatica | 6A1, 6A2 | room 101 | id '
        '$_momentRef',
      ),
    );

    final moment = await ok('read_planned_element', {'id': _momentRef});
    expect(moment, contains('Kind: lesson cluster moment'));
    expect(moment, isNot(contains('Name:')));
    expect(
      moment,
      contains(
        'Moment of the planned lesson cluster:\n- Lussen | from Monday '
        '2026-11-16 to Friday 2026-11-20 | informatica | 6A1 | id '
        '$_plannedRef',
      ),
    );
    final detail = await ok('read_planned_element', {'id': _plannedRef});
    expect(detail, contains('Planner element $_plannedRef'));
    expect(detail, contains('Kind: planned lesson cluster'));
    expect(detail, contains('Lesfiches planned, in order:'));

    final line =
        '- Lussen | from Monday 2026-11-16 to Friday 2026-11-20 | '
        'informatica | 6A1 | id $_plannedRef';
    final inPeriod = await ok('list_planned_lesson_clusters', {});
    expect(
      inPeriod,
      startsWith(
        'Lesson clusters planned in your own planner from Sunday 2026-11-01 '
        'to Tuesday 2027-08-31 (1), each with its id at the end:\n$line',
      ),
    );
    final ofCluster = await ok('list_planned_lesson_clusters', {
      'year_plan': _planId,
      'cluster': _clusterId,
    });
    expect(
      ofCluster,
      startsWith(
        'The lesson cluster "Lussen" of the year plan "Informatica 5" is '
        'planned 1 time, each with its id at the end:\n$line',
      ),
    );
    expect(
      await ok('list_planned_lesson_clusters', {
        'year_plan': _planId,
        'cluster': _otherClusterId,
      }),
      startsWith(
        'The lesson cluster "Recursie" of the year plan "Informatica 5" is '
        'not planned for any class.',
      ),
    );

    final trashed = await ok('trash_planned_lesson_cluster', {
      'id': _plannedRef,
    });
    expect(
      trashed,
      startsWith(
        'Moved the planned lesson cluster "Lussen" from Monday 2026-11-16 to '
        'Friday 2026-11-20 (6A1, informatica) to the planner\'s trash: '
        'pupils no longer see its moments',
      ),
    );
    expect(planner.writes, [
      'POST $_planPath',
      'POST $_api/planned-lesson-clusters/4069/${_madeId(1)}/trash',
    ]);
    expect(
      await ok('list_planner', week()),
      contains('1 element (1 empty lesson hour)'),
    );
    expect(
      await ok('list_planned_lesson_clusters', {
        'year_plan': _planId,
        'cluster': _clusterId,
      }),
      contains('is not planned for any class'),
    );
    expect(
      await ok('list_planned_lesson_clusters', {
        'from': '2026-11-16',
        'until': '2026-11-20',
      }),
      'No lesson clusters are planned in your own planner from Monday '
      '2026-11-16 to Friday 2026-11-20. Plan one with plan_lesson_cluster.',
    );
  });

  test('refuses before sending anything: an unknown cluster, a colleague\'s '
      'hour, an assignment, a class not of the hour, a day with a time, '
      'until before from, two school years', () async {
    for (final (arguments, refusal) in [
      (
        planArguments(cluster: 'c0000000-0000-4000-8000-000000000099'),
        'The year plan "Informatica 5" has no lesson cluster with id '
            'c0000000-0000-4000-8000-000000000099. Nothing was sent. Its '
            'clusters, each with its id at the end:\n- Lussen | id '
            '$_clusterId',
      ),
      (
        planArguments(hour: fakeSlot.ref),
        'hour is not a lesson hour of your own planner: the empty lesson '
            'hour on Monday 2026-10-05 14:40–15:30 (6A1, 6B1, wiskunde) is '
            'organised by Piet Peeters. Plan a lesson cluster in one of your '
            'own lesson hours',
      ),
      (
        planArguments(hour: fakeAssignment.ref),
        'hour must be a lesson hour of your own planner of the classes and '
            'the course',
      ),
      (
        planArguments(classes: ['6B1']),
        'classes holds "6B1", which is not a class of the empty lesson hour',
      ),
      (
        planArguments(from: '2026-11-16 08:00'),
        'from must be a day like 2026-11-16',
      ),
      (
        planArguments(from: '2026-11-20', until: '2026-11-16'),
        'until (2026-11-16) is before from (2026-11-20)',
      ),
      (
        planArguments(from: '2027-08-30', until: '2027-09-03'),
        'are in different school years',
      ),
    ]) {
      expect(
        await error('plan_lesson_cluster', arguments),
        contains(refusal),
        reason: '$arguments',
      );
    }
    expect(planner.writes, isEmpty);
  });

  test('a cluster the Lesfiches module no longer has: the library\'s '
      'refusal, worded, with nothing sent', () async {
    server.yearPlans.failing[_clusterPath] = 404;
    final text = await error('plan_lesson_cluster', planArguments());
    expect(
      text,
      'The planner refused the change before it was sent: you have no '
      'lesson cluster with the id given (any more) in your year plans in '
      'Lesfiches. Nothing was changed in the planner.',
    );
    expect(planner.writes, isEmpty);
  });

  test('a plan the planner does not confirm: maybe planned, never sent '
      'again, with how to check', () async {
    planner.lostAnswers.add(_planPath);
    final text = await error('plan_lesson_cluster', planArguments());
    expect(
      text,
      startsWith(
        'The lesson cluster "Lussen" of the year plan "Informatica 5" for '
        '6A1 (informatica) from Monday 2026-11-16 to Friday 2026-11-20 may '
        'or may not have been planned',
      ),
    );
    expect(
      text,
      contains(
        'Do not call plan_lesson_cluster again for it: first list where the '
        'cluster is planned with list_planned_lesson_clusters (year_plan '
        '$_planId, cluster $_clusterId)',
      ),
    );
    expect(planner.writes, ['POST $_planPath']);
  });

  test('the trash refuses a moment, an assignment and a colleague\'s '
      'planned cluster before sending anything', () async {
    await ok('plan_lesson_cluster', planArguments());
    expect(
      await error('trash_planned_lesson_cluster', {'id': _momentRef}),
      contains(
        'is a lesson cluster moment, one lesson hour of a planned '
        'cluster',
      ),
    );
    expect(
      await error('trash_planned_lesson_cluster', {'id': fakeAssignment.ref}),
      contains('is an assignment: use trash_assignment'),
    );
    final colleagues = FakePlannedElement(
      id: 'e0000000-0000-4000-8000-000000000090',
      type: 'planned-lesson-clusters',
      name: 'Erfelijkheid',
      from: plannerTime(2026, 11, 16),
      to: plannerTime(2026, 11, 20, 23, 59, 59),
      wholeDay: true,
      organisers: [fakeWim],
      groups: [fake6A1],
    );
    planner.add(colleagues, calendars: const []);
    expect(
      await error('trash_planned_lesson_cluster', {'id': colleagues.ref}),
      contains(
        'the planned lesson cluster "Erfelijkheid" from Monday 2026-11-16 to '
        'Friday 2026-11-20 (6A1) is not in your own planner: it is organised '
        'by Wim Willems',
      ),
    );
    expect(planner.writes, ['POST $_planPath']);
  });

  test(
    'list_planned_lesson_clusters takes a period or a cluster, not both',
    () async {
      expect(
        await error('list_planned_lesson_clusters', {
          'cluster': _clusterId,
          'from': '2026-11-16',
        }),
        startsWith('Pass either from and until'),
      );
      expect(
        await error('list_planned_lesson_clusters', {'cluster': _clusterId}),
        startsWith('Pass year_plan and cluster together'),
      );
      expect(planner.requests, isEmpty);
    },
  );
}
