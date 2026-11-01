import 'dart:convert';

import 'package:dio/dio.dart';

import 'fake_planner.dart';

/// Where the teaching assignments (year plans) of the Lesfiches module are
/// read and written (dartschool#229).
const fakeYearPlansApi = '/lesson-content/api/v1/teaching-assignments';

/// The platform of the fake's year plans and clusters.
const _platform = 4069;

/// An entry of a lesson cluster: a title, or a lesfiche of the planner's
/// library.
class FakeClusterEntry {
  FakeClusterEntry.title(this.id, String this.text) : lesfiche = null;

  FakeClusterEntry.lesfiche(FakeLesfiche this.lesfiche)
    : id = lesfiche.id,
      text = null;

  final String id;
  final String? text;
  final FakeLesfiche? lesfiche;
}

/// A lesson cluster of a [FakeYearPlan], with its content in order.
class FakeLessonCluster {
  FakeLessonCluster({
    required this.id,
    required this.name,
    List<Map<String, String>>? goals,
    List<FakeClusterEntry>? entries,
  }) : goals = goals ?? [],
       entries = entries ?? [];

  final String id;
  final String name;

  /// Its learning goals, each `{id, leerplanId, type}` ([fakeGoalRef]).
  List<Map<String, String>> goals;
  final List<FakeClusterEntry> entries;

  int _count(String type) =>
      entries.where((entry) => entry.lesfiche?.type == type).length;

  /// The cluster in full, as `getClusters` and the writes give it.
  Map<String, Object?> toJson(FakeYearPlan plan, int position) => {
    'id': id,
    'platformId': _platform,
    'teachingAssignmentId': plan.id,
    'teachingAssignmentPlatformId': _platform,
    'name': name,
    'icon': 'box_curver_blue',
    'isVisible': true,
    'position': position,
    'publicInfo': {'text': '', 'attachments': [], 'weblinks': []},
    'privateInfo': {'text': '', 'attachments': [], 'weblinks': []},
    'goals': [
      for (final goal in goals) {...goal, 'goalId': goal['id']},
    ],
    'numberOfLessons': _count('lessons'),
    'numberOfAssignments': _count('assignments'),
    'numberOfGoals': goals.length,
    'teachingHoursEstimate': entries.where((e) => e.lesfiche != null).length,
    'numberOfAttachments': 0,
    'numberOfWebLinks': 0,
  };

  /// The cluster in short, as a teaching assignment lists it.
  Map<String, Object?> shortJson(int position) => {
    'id': id,
    'platformId': _platform,
    'name': name,
    'icon': 'box_curver_blue',
    'isVisible': true,
    'position': position,
  };
}

/// A teaching assignment (year plan) of the fake's account.
class FakeYearPlan {
  FakeYearPlan({
    required this.id,
    required this.name,
    this.contentFilter = 'all',
    List<FakeLessonCluster>? clusters,
  }) : clusters = clusters ?? [];

  final String id;
  final String name;

  /// `all`, `none` or `particular`.
  final String contentFilter;
  final List<FakeLessonCluster> clusters;

  Map<String, Object?> toJson() => {
    'id': id,
    'platformId': _platform,
    'name': name,
    'icon': 'box_curver_blue',
    'owner': {'id': fakePlannerMe, 'name': 'Jan Peeters'},
    'collaborators': [
      {
        'user': {'id': fakePlannerMe},
        'contentFilter': {'type': contentFilter},
      },
    ],
    'lessonClusters': [
      for (final (index, cluster) in clusters.indexed) cluster.shortJson(index),
    ],
    'visibility': true,
    'favourite': false,
  };
}

/// The year plans of the Lesfiches module (dartschool#229), in the shapes of
/// the library's parsers and of its documented requests: the list, one plan,
/// its lesfiches (those of [planner] for the filter `all`), its clusters and
/// their content, and the writes (a plan, a cluster, a title, lesfiches,
/// goals, the delete).
class FakeYearPlans {
  FakeYearPlans(this.planner);

  /// The planner, whose lesfiches a year plan with the filter `all` takes.
  final FakePlanner planner;

  /// The year plans of the fake's account, in order.
  final List<FakeYearPlan> plans = [];

  /// The requests, in order.
  final List<({String method, String path, Object? data})> requests = [];

  /// Paths answered with this status instead.
  final Map<String, int> failing = {};

  /// Paths of writes that are carried out, after which the connection drops
  /// before the answer arrives.
  final Set<String> lostAnswers = {};

  /// Statuses of the exception the add of lesfiches gives for these
  /// lesfiches, by id in lower case, instead of adding them (`403` for a
  /// lesfiche the filter does not take, seen live).
  final Map<String, int> addExceptions = {};

  int _made = 0;

  /// The writes, as `POST path` or `DELETE path`, in order.
  List<String> get writes => [
    for (final request in requests)
      if (request.method != 'GET') '${request.method} ${request.path}',
  ];

  String _newId() =>
      'c0000000-0000-4000-9000-${(++_made).toString().padLeft(12, '0')}';

  FakeYearPlan? _plan(String id) => plans
      .where((plan) => plan.id.toLowerCase() == id.toLowerCase())
      .firstOrNull;

  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (!path.startsWith('$fakeYearPlansApi/')) return null;
    requests.add((method: options.method, path: path, data: options.data));
    if (failing[path] case final status?) {
      return _json('{"status":$status}', status: status);
    }
    final answer = _answer(
      options.method,
      path.substring(fakeYearPlansApi.length + 1).split('/'),
      options.data,
    );
    if (options.method != 'GET' && lostAnswers.contains(path)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection reset by peer',
      );
    }
    return answer;
  }

  ResponseBody _answer(String method, List<String> route, Object? data) {
    final body = switch (data) {
      final String text when text.isNotEmpty => jsonDecode(text),
      final Map<String, Object?> map => map,
      _ => null,
    };
    switch ((method, route)) {
      case ('GET', [fakePlannerMe]):
        return _json(jsonEncode([for (final plan in plans) plan.toJson()]));
      case ('POST', [fakePlannerMe]):
        final name = (body as Map)['name'] as String;
        if (name.length > 50) return _json('', status: 400);
        final plan = FakeYearPlan(
          id: _newId(),
          name: name,
          contentFilter: (body['contentFilter'] as Map)['type'] as String,
        );
        plans.add(plan);
        return _json(jsonEncode(plan.toJson()), status: 201);
      case ('GET', [_, final id]):
        final plan = _plan(id);
        if (plan == null) return _json('{"status":404}', status: 404);
        return _json(jsonEncode(plan.toJson()));
      case ('DELETE', [_, final id]):
        final plan = _plan(id);
        if (plan == null) return _json('{"status":404}', status: 404);
        plans.remove(plan);
        return _json('', status: 204);
      case ('GET', [_, final id, 'lesson-content']):
        final plan = _plan(id);
        if (plan == null) return _json('{"status":404}', status: 404);
        return _json(
          jsonEncode([
            if (plan.contentFilter == 'all')
              for (final lesfiche in planner.lesfiches)
                if (!planner.trashedLesfiches.contains(
                  lesfiche.id.toLowerCase(),
                ))
                  _lesficheJson(lesfiche),
          ]),
        );
      case ('GET', [fakePlannerMe, _, final id, 'lesson-clusters']):
        final plan = _plan(id);
        if (plan == null) return _json('{"status":404}', status: 404);
        return _json(
          jsonEncode([
            for (final (index, cluster) in plan.clusters.indexed)
              cluster.toJson(plan, index),
          ]),
        );
      case ('POST', [fakePlannerMe, _, final id, 'lesson-clusters']):
        final plan = _plan(id);
        if (plan == null) return _json('{"status":404}', status: 404);
        final name = (body as Map)['name'] as String;
        if (name.length > 50) return _json('', status: 400);
        final cluster = FakeLessonCluster(id: _newId(), name: name);
        plan.clusters.add(cluster);
        return _json(
          jsonEncode(cluster.toJson(plan, plan.clusters.length - 1)),
          status: 201,
        );
      case (
        _,
        [_, final planId, 'lesson-clusters', _, final id, ...final rest],
      ):
        final plan = _plan(planId);
        final cluster = plan?.clusters
            .where((cluster) => cluster.id.toLowerCase() == id.toLowerCase())
            .firstOrNull;
        if (plan == null || cluster == null) {
          return _json('{"status":404}', status: 404);
        }
        return _clusterAnswer(method, plan, cluster, rest, body);
    }
    return _json('{"status":404}', status: 404);
  }

  ResponseBody _clusterAnswer(
    String method,
    FakeYearPlan plan,
    FakeLessonCluster cluster,
    List<String> rest,
    Object? body,
  ) {
    final position = plan.clusters.indexOf(cluster);
    switch ((method, rest)) {
      case ('GET', []):
        return _json(jsonEncode(cluster.toJson(plan, position)));
      case ('GET', ['lesson-cluster-content']):
        return _json(
          jsonEncode([
            for (final (index, entry) in cluster.entries.indexed)
              _entryJson(cluster, entry, index),
          ]),
        );
      case ('GET', ['goals']):
        return _json(
          jsonEncode([
            for (final goal in cluster.goals) {...goal, 'count': 0},
          ]),
        );
      case ('POST', ['titles']):
        final text = (body as Map)['text'] as String;
        if (text.length > 50) return _json('', status: 400);
        final entry = FakeClusterEntry.title(_newId(), text);
        cluster.entries.add(entry);
        return _json(
          jsonEncode(_entryJson(cluster, entry, cluster.entries.length - 1)),
        );
      case ('POST', ['lesson-content-from-teaching-assignment']):
        final added = <Map<String, Object?>>[];
        final exceptions = <String, Object?>{};
        for (final identifier
            in (body as Map)['lessonContentIdentifiers'] as List) {
          final id = ((identifier as Map)['id'] as String).toLowerCase();
          final lesfiche = planner.lesfiches
              .where((lesfiche) => lesfiche.id.toLowerCase() == id)
              .firstOrNull;
          final refused =
              addExceptions[id] ??
              (lesfiche == null || plan.contentFilter != 'all' ? 403 : null);
          if (refused != null || lesfiche == null) {
            exceptions['${_platform}_lesson_$id'] = {'status': refused ?? 403};
            continue;
          }
          cluster.entries.add(FakeClusterEntry.lesfiche(lesfiche));
          added.add(_lesficheJson(lesfiche));
        }
        return _json(
          jsonEncode({
            'lessonContent': added,
            'exceptions': exceptions.isEmpty ? <Object?>[] : exceptions,
          }),
          status: 201,
        );
      case ('POST', ['change-goals']):
        cluster.goals = [
          for (final goal in (body as Map)['newGoals'] as List)
            {
              'id': (goal as Map)['id'] as String,
              'leerplanId': goal['leerplanId'] as String,
              'type': goal['type'] as String,
            },
        ];
        return _json(jsonEncode(cluster.toJson(plan, position)));
    }
    return _json('{"status":404}', status: 404);
  }

  /// [lesfiche] as the module gives the lesfiches of a teaching assignment:
  /// the owner as a user object.
  Map<String, Object?> _lesficheJson(FakeLesfiche lesfiche) => {
    ...lesfiche.toJson(),
    'owner': {'id': lesfiche.owner, 'name': 'Jan Peeters'},
  };

  Map<String, Object?> _entryJson(
    FakeLessonCluster cluster,
    FakeClusterEntry entry,
    int position,
  ) {
    if (entry.lesfiche case final lesfiche?) {
      return {
        ..._lesficheJson(lesfiche),
        'lessonClusterId': cluster.id,
        'position': position,
        'teachingHoursEstimate': 1,
        'numberOfGoals': lesfiche.goals.length,
      };
    }
    return {
      'id': entry.id,
      'platformId': _platform,
      'lessonClusterId': cluster.id,
      'position': position,
      'text': entry.text,
      'type': 'titles',
    };
  }

  ResponseBody _json(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}
