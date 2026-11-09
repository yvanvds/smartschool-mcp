/// The year plans of the Lesfiches module (#191): `list_year_plans`,
/// `read_year_plan`, `create_year_plan`, `add_lesson_cluster`,
/// `add_to_lesson_cluster`, `set_lesson_cluster_goals` and
/// `delete_year_plan`, called over MCP on the real server, session and
/// library, against a fake Smartschool whose Lesfiches module keeps
/// teaching assignments and their clusters in the shapes of
/// `TeachingAssignmentService` (dartschool#229,
/// `test/support/fake_year_plans.dart`), with the lesfiches of the fake
/// planner and the goal selector of `test/support/fake_goals.dart`.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/add_lesson_cluster_tool.dart';
import 'package:smartschool_mcp/src/tools/add_to_lesson_cluster_tool.dart';
import 'package:smartschool_mcp/src/tools/create_year_plan_tool.dart';
import 'package:smartschool_mcp/src/tools/delete_year_plan_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/list_year_plans_tool.dart';
import 'package:smartschool_mcp/src/tools/read_year_plan_tool.dart';
import 'package:smartschool_mcp/src/tools/set_lesson_cluster_goals_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

final _lussen = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000061',
  name: 'Lussen 1',
);
final _lussen2 = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000062',
  name: 'Lussen 2',
);
final _toets = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000063',
  name: 'Toets lussen',
  type: 'assignments',
);

const _planId = 'c0000000-0000-4000-8000-000000000001';
const _clusterId = 'c0000000-0000-4000-8000-000000000002';
const _otherClusterId = 'c0000000-0000-4000-8000-000000000003';

final _goal1 = fakeGoalRef(fakeGoal1Id, fakeEindtermenId, fakeEindtermenType);
final _madeUp = fakeGoalRef(
  'f0000000-0000-4000-8000-000000000099',
  fakeEindtermenId,
  fakeEindtermenType,
);

const _yearPlansPath = '$fakeYearPlansApi/$fakePlannerMe';
const _clusterPath =
    '$fakeYearPlansApi/4069/$_planId/lesson-clusters/4069/$_clusterId';

void main() {
  late FakeSmartschool server;
  late FakeYearPlans yearPlans;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    server.planner.lesfiches.addAll([_lussen, _lussen2, _toets]);
    server.goals.loadSample();
    yearPlans = server.yearPlans;
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        listYearPlansTool(session),
        readYearPlanTool(session),
        createYearPlanTool(session),
        addLessonClusterTool(session),
        addToLessonClusterTool(session),
        setLessonClusterGoalsTool(session),
        deleteYearPlanTool(session),
      ],
    );
  });

  /// A year plan "Informatica 5" with the cluster "Lussen" (a title and two
  /// lesfiches, the eindterm goal 1) and the empty cluster "Recursie".
  FakeYearPlan addPlan({String filter = 'all'}) {
    final plan = FakeYearPlan(
      id: _planId,
      name: 'Informatica 5',
      contentFilter: filter,
      clusters: [
        FakeLessonCluster(
          id: _clusterId,
          name: 'Lussen',
          goals: [_goal1],
          entries: [
            FakeClusterEntry.title(
              'c0000000-0000-4000-8000-000000000009',
              'Week 1',
            ),
            FakeClusterEntry.lesfiche(_lussen),
            FakeClusterEntry.lesfiche(_toets),
          ],
        ),
        FakeLessonCluster(id: _otherClusterId, name: 'Recursie'),
      ],
    );
    yearPlans.plans.add(plan);
    return plan;
  }

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

  Object? bodyOf(String path) => yearPlans.requests
      .where((request) => request.method == 'POST' && request.path == path)
      .single
      .data;

  test('the reads are read-only, the writes ask approval; the creates and '
      'adds are not idempotent, the goals and the delete are', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    for (final name in ['list_year_plans', 'read_year_plan']) {
      expect(tools[name]!.toolAnnotations!.readOnlyHint, isTrue, reason: name);
    }
    for (final (name, idempotent) in [
      ('create_year_plan', false),
      ('add_lesson_cluster', false),
      ('add_to_lesson_cluster', false),
      ('set_lesson_cluster_goals', true),
      ('delete_year_plan', true),
    ]) {
      final annotations = tools[name]!.toolAnnotations!;
      expect(annotations.destructiveHint, isTrue, reason: name);
      expect(annotations.idempotentHint, idempotent, reason: name);
      expect(
        tools[name]!.description,
        contains('after the user has explicitly confirmed it'),
        reason: name,
      );
    }
    expect(
      tools['delete_year_plan']!.description,
      allOf(
        contains('cannot be undone'),
        contains('The lesfiches in its clusters stay in the user\'s library'),
      ),
    );
    expect(tools['add_to_lesson_cluster']!.inputSchema.properties!.keys, [
      'year_plan',
      'cluster',
      'title',
      'lesfiches',
    ]);
  });

  test('list_year_plans says there are none, then lists each plan with '
      'which lesfiches it takes, its clusters and its id', () async {
    expect(
      await ok('list_year_plans', {}),
      'You have no year plans in Lesfiches. Make one with create_year_plan.',
    );
    addPlan();
    expect(
      await ok('list_year_plans', {}),
      contains(
        '- Informatica 5 | takes all your lesfiches | 2 clusters: Lussen, '
        'Recursie | id $_planId',
      ),
    );
    expect(yearPlans.writes, isEmpty);
  });

  test('read_year_plan shows each cluster with its counts, its goals by '
      'name and its titles and lesfiches in order', () async {
    addPlan();
    final text = await ok('read_year_plan', {'year_plan': _planId});
    expect(
      text,
      allOf(
        startsWith('Year plan Informatica 5 | takes all your lesfiches'),
        contains(
          'Cluster 1: Lussen | 1 lesson lesfiche | 1 assignment lesfiche | '
          '1 goal | about 2 teaching hours | id $_clusterId',
        ),
        contains('  - Eindtermen derde graad, voorbeeld: Competenties'),
        contains(
          '  Content, in order:\n'
          '  1. title "Week 1"\n'
          '  2. lesson | Lussen 1 | 1 teaching hour | 0 goals | id '
          '${_lussen.id}\n'
          '  3. assignment | Toets lussen | 1 teaching hour | 0 goals | id '
          '${_toets.id}',
        ),
        contains(
          'Cluster 2: Recursie | 0 lesson lesfiches | 0 assignment '
          'lesfiches | 0 goals | id $_otherClusterId\n'
          '  Goals: none\n'
          '  Content: none',
        ),
      ),
    );

    final one = await ok('read_year_plan', {
      'year_plan': _planId,
      'cluster': _otherClusterId,
    });
    expect(one, contains('Cluster: Recursie'));
    expect(one, isNot(contains('Lussen |')));
    expect(yearPlans.writes, isEmpty);
  });

  test('the cluster line counts only the cluster\'s own goals, not those of '
      'its lesfiches the module counts too, and leaves out an estimate of 0 '
      'hours (#206)', () async {
    final goal2 = fakeGoalRef(
      fakeGoal2Id,
      fakeEindtermenId,
      fakeEindtermenType,
    );
    final goal3 = fakeGoalRef(
      fakeGoal3Id,
      fakeEindtermenId,
      fakeEindtermenType,
    );
    final withGoals = [
      for (final (n, name) in ['Lussen 1', 'Lussen 2'].indexed)
        FakeLesfiche(
          id: 'b0000000-0000-4000-8000-00000000007$n',
          name: name,
          goals: [goal2, goal3],
        ),
    ];
    server.planner.lesfiches.addAll(withGoals);
    yearPlans.plans.add(
      FakeYearPlan(
        id: _planId,
        name: 'Informatica 5',
        clusters: [
          FakeLessonCluster(
            id: _clusterId,
            name: 'Lussen',
            goals: [_goal1],
            entries: [for (final f in withGoals) FakeClusterEntry.lesfiche(f)],
          ),
          FakeLessonCluster(id: _otherClusterId, name: 'Recursie'),
        ],
      ),
    );
    expect(
      await ok('read_year_plan', {'year_plan': _planId}),
      allOf(
        contains(
          'Cluster 1: Lussen | 2 lesson lesfiches | 0 assignment lesfiches | '
          '1 goal | about 2 teaching hours | id $_clusterId\n'
          '  Goals:\n'
          '  - Eindtermen derde graad, voorbeeld: Competenties',
        ),
        contains(
          'Cluster 2: Recursie | 0 lesson lesfiches | 0 assignment '
          'lesfiches | 0 goals | id $_otherClusterId\n',
        ),
        isNot(contains('teaching hours | id $_otherClusterId')),
      ),
    );

    expect(
      await ok('set_lesson_cluster_goals', {
        'year_plan': _planId,
        'cluster': _clusterId,
        'goals': <Object>[],
      }),
      contains(
        'Lussen | 2 lesson lesfiches | 0 assignment lesfiches | 0 goals | '
        'about 2 teaching hours | id $_clusterId\n'
        '  Goals: none',
      ),
    );
  });

  test('read_year_plan refuses an id that is not one, before any login, and '
      'an unknown plan or cluster with the ones there are', () async {
    expect(
      await error('read_year_plan', {'year_plan': 'Informatica 5'}),
      contains(
        'year_plan must be the id of a year plan as list_year_plans '
        'shows it',
      ),
    );
    expect(server.logins, 0);

    addPlan();
    expect(
      await error('read_year_plan', {
        'year_plan': 'c0000000-0000-4000-8000-0000000000ff',
      }),
      allOf(
        contains('You have no year plan with id'),
        contains('- Informatica 5 | takes all your lesfiches'),
      ),
    );
    expect(
      await error('read_year_plan', {
        'year_plan': _planId,
        'cluster': 'c0000000-0000-4000-8000-0000000000ff',
      }),
      allOf(
        contains('has no lesson cluster with id'),
        contains('- Lussen | id $_clusterId'),
      ),
    );
  });

  test('a year plan is built from existing lesfiches: create_year_plan, '
      'add_lesson_cluster, add_to_lesson_cluster (a title, then the '
      'lesfiches in order), read back', () async {
    final made = await ok('create_year_plan', {'name': ' Informatica 6 '});
    expect(
      made,
      contains(
        'Made the year plan Informatica 6 | takes all your '
        'lesfiches | no clusters | id ',
      ),
    );
    final plan = yearPlans.plans.single;
    expect(bodyOf(_yearPlansPath), containsPair('name', 'Informatica 6'));
    expect(
      (bodyOf(_yearPlansPath) as Map)['contentFilter'],
      containsPair('type', 'all'),
    );

    final added = await ok('add_lesson_cluster', {
      'year_plan': plan.id,
      'name': 'Lussen',
    });
    final cluster = plan.clusters.single;
    expect(added, contains('cluster id ${cluster.id}'));

    final filled = await ok('add_to_lesson_cluster', {
      'year_plan': plan.id,
      'cluster': cluster.id,
      'title': 'Week 1',
      'lesfiches': [_lussen2.id, _lussen.id],
    });
    expect(
      filled,
      allOf(
        contains(
          'Added the title "Week 1" to the end of the lesson cluster '
          '"Lussen".',
        ),
        contains(
          'Added the lesson lesfiche "Lussen 2" and the lesson '
          'lesfiche "Lussen 1"',
        ),
        contains('  1. title "Week 1"\n  2. lesson | Lussen 2'),
        contains('  3. lesson | Lussen 1'),
      ),
    );
    final clusterPath =
        '$fakeYearPlansApi/4069/${plan.id}/lesson-clusters/4069/${cluster.id}';
    expect(yearPlans.writes, [
      'POST $_yearPlansPath',
      'POST $fakeYearPlansApi/$fakePlannerMe/4069/${plan.id}/lesson-clusters',
      'POST $clusterPath/titles',
      'POST $clusterPath/lesson-content-from-teaching-assignment',
    ]);
    expect(bodyOf('$clusterPath/lesson-content-from-teaching-assignment'), {
      'lessonContentIdentifiers': [
        {'id': _lussen2.id, 'type': 'lessons', 'platformId': 4069},
        {'id': _lussen.id, 'type': 'lessons', 'platformId': 4069},
      ],
    });
  });

  test(
    'names over 50 characters are refused before anything is sent',
    () async {
      addPlan();
      final long = 'x' * 51;
      expect(
        await error('create_year_plan', {'name': long}),
        contains('takes at most 50 for the year plan'),
      );
      expect(
        await error('add_lesson_cluster', {'year_plan': _planId, 'name': long}),
        contains('takes at most 50 for the lesson cluster'),
      );
      expect(
        await error('add_to_lesson_cluster', {
          'year_plan': _planId,
          'cluster': _clusterId,
          'title': long,
        }),
        contains('takes at most 50 for the title'),
      );
      expect(yearPlans.requests, isEmpty);
    },
  );

  test('add_to_lesson_cluster refuses a lesfiche the year plan does not '
      'take, and nothing to add, before anything is sent', () async {
    addPlan(filter: 'none');
    expect(
      await error('add_to_lesson_cluster', {
        'year_plan': _planId,
        'cluster': _clusterId,
        'title': 'Week 2',
        'lesfiches': [_lussen2.id],
      }),
      allOf(
        contains(
          '(which takes no lesfiches) does not take the lesfiches '
          'with id ${_lussen2.id}',
        ),
        contains('Nothing was sent.'),
      ),
    );
    expect(
      await error('add_to_lesson_cluster', {
        'year_plan': _planId,
        'cluster': _clusterId,
      }),
      contains('there is nothing to add'),
    );
    expect(yearPlans.writes, isEmpty);
  });

  test('add_to_lesson_cluster: a title the module does not confirm is maybe '
      'added, and the lesfiches are not sent', () async {
    addPlan();
    yearPlans.lostAnswers.add('$_clusterPath/titles');
    final text = await error('add_to_lesson_cluster', {
      'year_plan': _planId,
      'cluster': _clusterId,
      'title': 'Week 2',
      'lesfiches': [_lussen2.id],
    });
    expect(
      text,
      allOf(
        contains(
          'The title "Week 2" of the lesson cluster "Lussen" may or may '
          'not have been added',
        ),
        contains('The lesfiches were not sent.'),
        contains('Do not call add_to_lesson_cluster again'),
      ),
    );
    expect(yearPlans.writes, ['POST $_clusterPath/titles']);
  });

  test('add_to_lesson_cluster: lesfiches the module refuses after the title '
      'say that the title was added', () async {
    addPlan();
    yearPlans.addExceptions[_lussen2.id.toLowerCase()] = 403;
    final text = await error('add_to_lesson_cluster', {
      'year_plan': _planId,
      'cluster': _clusterId,
      'title': 'Week 2',
      'lesfiches': [_lussen2.id],
    });
    expect(
      text,
      allOf(
        contains('HTTP 403'),
        contains('The lesfiches were not added. The title "Week 2" was added.'),
      ),
    );
  });

  test('add_to_lesson_cluster: an answer that adds some lesfiches, refuses '
      'one and names one neither way says, from the library\'s record, which '
      'were added, without reading the cluster (#224); the log names no '
      'lesfiche', () async {
    addPlan();
    yearPlans.addExceptions[_toets.id.toLowerCase()] = 403;
    yearPlans.addUnanswered.add(_lussen.id.toLowerCase());

    final ((result, text), logged) = await captureLog(() async {
      final (connection, _) = await connect(
        tools: [addToLessonClusterTool(session)],
      );
      return callTool(connection, 'add_to_lesson_cluster', {
        'year_plan': _planId,
        'cluster': _clusterId,
        'title': 'Week 2',
        'lesfiches': [_lussen2.id, _toets.id, _lussen.id],
      });
    });
    expect(result.isError, isTrue, reason: text);
    expect(
      text,
      'The add of 3 lesfiches to the lesson cluster "Lussen" was sent, but '
      'the Lesfiches module did not confirm all of it. Its answer says what '
      'was done.\n'
      'Added to the end of the cluster (a lesfiche can be in a cluster '
      'twice, so do not add these again):\n'
      '- lesson | Lussen 2 | id ${_lussen2.id}\n'
      'Not added, with the exception the module gave for each (it answers '
      'HTTP 403 for a lesfiche the year plan does not take):\n'
      '- assignment | Toets lussen | id ${_toets.id} (HTTP 403, '
      '"{"status":403}")\n'
      'Not named in the answer, so they may or may not have been added '
      '(before adding one of these again, read the cluster with '
      'read_year_plan (year_plan $_planId, cluster $_clusterId): the module '
      'adds to its end):\n'
      '- lesson | Lussen 1 | id ${_lussen.id}\n'
      'The title "Week 2" was added.\n'
      'Do not call add_to_lesson_cluster again for those added: a second '
      'call adds them to the cluster twice. Tell the user which were added '
      'and which not, and ask before adding the others again.',
    );
    expect(
      yearPlans.requests.last.path,
      '$_clusterPath/lesson-content-from-teaching-assignment',
      reason: 'no read of the cluster after the add',
    );
    expect(yearPlans.writes, [
      'POST $_clusterPath/titles',
      'POST $_clusterPath/lesson-content-from-teaching-assignment',
    ]);
    expect(
      logged,
      contains(
        'add_to_lesson_cluster: the Lesfiches module did not confirm all of '
        'a write; its answer: 1 done, 1 with an exception (HTTP 403), 1 not '
        'named',
      ),
    );
    expect(logged, isNot(contains('Lussen')));
    expect(logged, isNot(contains('Toets')));
  });

  test('add_to_lesson_cluster: lesfiches without an answer may or may not '
      'have been added, with read_year_plan to check, and the title was '
      'added', () async {
    addPlan();
    yearPlans.lostAnswers.add(
      '$_clusterPath/lesson-content-from-teaching-assignment',
    );
    final text = await error('add_to_lesson_cluster', {
      'year_plan': _planId,
      'cluster': _clusterId,
      'title': 'Week 2',
      'lesfiches': [_lussen2.id, _lussen.id],
    });
    expect(
      text,
      allOf(
        contains(
          'The 2 lesfiches (the lesson lesfiche "Lussen 2" and the lesson '
          'lesfiche "Lussen 1") in the lesson cluster "Lussen" may or may not '
          'have been added',
        ),
        contains('The title "Week 2" was added.'),
        contains(
          'read the cluster with read_year_plan (year_plan $_planId, cluster '
          '$_clusterId) to see which are there',
        ),
        contains('Do not call add_to_lesson_cluster again'),
      ),
    );
    expect(yearPlans.writes, [
      'POST $_clusterPath/titles',
      'POST $_clusterPath/lesson-content-from-teaching-assignment',
    ], reason: 'sent once, never again after the lost answer');
  });

  test('set_lesson_cluster_goals checks the new goals with the goal selector, '
      'sets them, and sends nothing for the goals it has', () async {
    final plan = addPlan();
    expect(
      await error('set_lesson_cluster_goals', {
        'year_plan': _planId,
        'cluster': _otherClusterId,
        'goals': [_madeUp],
      }),
      contains('not known to the goal selector'),
    );
    expect(yearPlans.writes, isEmpty);

    final text = await ok('set_lesson_cluster_goals', {
      'year_plan': _planId,
      'cluster': _otherClusterId,
      'goals': [_goal1],
    });
    expect(
      text,
      allOf(
        startsWith('Set the goals of the lesson cluster "Recursie".'),
        contains('  - Eindtermen derde graad, voorbeeld: Competenties'),
      ),
    );
    expect(plan.clusters.last.goals, [_goal1]);

    final again = await ok('set_lesson_cluster_goals', {
      'year_plan': _planId,
      'cluster': _otherClusterId,
      'goals': [_goal1],
    });
    expect(
      again,
      startsWith(
        'The lesson cluster "Recursie" has these goals '
        'already: nothing was sent.',
      ),
    );
    expect(yearPlans.writes, hasLength(1));
  });

  test(
    'delete_year_plan deletes the plan and says that its lesfiches stay',
    () async {
      addPlan();
      final text = await ok('delete_year_plan', {'year_plan': _planId});
      expect(
        text,
        'Deleted the year plan "Informatica 5" with its 2 lesson clusters. The '
        'lesfiches that were in them stay in your library, unchanged '
        '(list_lesfiches shows them).',
      );
      expect(yearPlans.plans, isEmpty);
      expect(yearPlans.writes, ['DELETE $fakeYearPlansApi/4069/$_planId']);
      expect(await ok('list_lesfiches', {'type': 'all'}), contains('Lussen 1'));

      expect(
        await error('delete_year_plan', {'year_plan': _planId}),
        contains('You have no year plans'),
      );
      expect(yearPlans.writes, hasLength(1));
    },
  );
}
