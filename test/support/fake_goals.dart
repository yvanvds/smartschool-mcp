import 'dart:convert';

import 'package:dio/dio.dart';

/// The base path of the goal selector's curricula (dartschool#222).
const fakeGoalApi = '/goal/selector/api/v1/leerplannen';

/// The ids of [FakeGoalSelector.loadSample], made up in the shapes of
/// dartschool's `test/goal_service_test.dart`.
const fakeEindtermenId = 'e0000000-0000-4000-8000-000000000001';
const fakeGodsdienstId = 'e0000000-0000-4000-8000-000000000003';
const fakeMiniDbId = 'e0000000-0000-5000-8000-000000000002';
const fakeDomainId = 'f0000000-0000-4000-8000-000000000010';
const fakeGoal1Id = 'f0000000-0000-4000-8000-000000000011';
const fakeGoal2Id = 'f0000000-0000-4000-8000-000000000012';
const fakeClusterId = 'f0000000-0000-4000-8000-000000000013';
const fakeGoal3Id = 'f0000000-0000-4000-8000-000000000014';
const fakeBasicGoalId = 'f0000000-0000-4000-8000-000000000015';
const fakeMiniTitleId = 'f0000000-0000-4000-8000-000000000020';
const fakeMiniSubtitleId = 'f0000000-0000-4000-8000-000000000021';
const fakeMiniGoal1Id = 'f0000000-0000-4000-8000-000000000022';
const fakeMiniGoal2Id = 'f0000000-0000-4000-8000-000000000023';

/// The `leerplanType` of the sample's eindtermen.
const fakeEindtermenType = 'eindtermen-derde-graad-doorstroom';

/// A stored goal, as a lesfiche or a planned lesson keeps it:
/// `{id, leerplanId, type}`.
Map<String, String> fakeGoalRef(String id, String leerplanId, String type) => {
  'id': id,
  'leerplanId': leerplanId,
  'type': type,
};

/// A node of a curriculum tree: a heading or a goal.
class FakeGoalNode {
  const FakeGoalNode({
    required this.id,
    required this.type,
    required this.title,
    this.prefix,
    this.deprecated = false,
    this.children = const [],
  });

  final String id;

  /// The selector's kind: `title`, `subtitle`, `goal`, `goal-basic`, ...
  final String type;

  /// HTML for the eindtermen, plain text for a mini-database.
  final String title;
  final String? prefix;
  final bool deprecated;
  final List<FakeGoalNode> children;

  /// The node, with only the children on the way to [keep] when it is not
  /// null (the naming of a selection), or null when none of [keep] is in it.
  Map<String, Object?>? toJson([Set<String>? keep]) {
    final kids = [for (final child in children) ?child.toJson(keep)];
    if (keep != null && !keep.contains(id) && kids.isEmpty) return null;
    return {
      'id': id,
      'type': type,
      'title': title,
      'metadata': type == 'title' && prefix == null
          ? null
          : {
              'prefix': prefix ?? '',
              'icon': 'target_lpd_redsoft',
              'isDeprecated': deprecated,
            },
      'children': kids,
    };
  }
}

/// A curriculum of the goal selector.
class FakeCurriculum {
  const FakeCurriculum({
    required this.id,
    required this.group,
    required this.title,
    required this.leerplanType,
    this.selectable = const ['goal'],
    this.visible = true,
    this.favourite = false,
    this.children = const [],
  });

  final String id;

  /// The name of its group in the list, such as `Overheid SO`.
  final String group;
  final String title;
  final String leerplanType;
  final List<String> selectable;
  final bool visible;
  final bool favourite;
  final List<FakeGoalNode> children;

  Map<String, Object?> listJson() => {
    'id': id,
    'title': title,
    'metadata': {'icon': null, 'isVisible': visible, 'isFavourite': favourite},
  };

  /// The tree, whole, or pruned to the goals [keep].
  Map<String, Object?> treeJson([Set<String>? keep]) => {
    'id': id,
    'type': leerplanType,
    'title': title,
    'metadata': {'isDeprecated': false},
    'config': {
      'typesThatCanBeSelected': selectable,
      'leerplanType': leerplanType,
    },
    'children': [for (final child in children) ?child.toJson(keep)],
  };
}

/// Smartschool's goal selector (`/goal/selector/api/v1/`, dartschool#222),
/// for logged-in requests. It serves, for either location
/// (`lesson-content`, `planner-lesson-content`) and any day:
/// - `GET leerplannen/{location}/list/{date}`: the [curricula] in groups, in
///   the order added;
/// - `GET leerplannen/{location}/{id}/{date}`: one curriculum as a tree;
///   `404` for an id it does not have, as live;
/// - `POST leerplannen/{location}/{date}` (`selection`, `isView`): one tree
///   per curriculum of the selection that it has, pruned to the goals asked
///   for and the nodes above them; a goal it does not have is left out, and
///   so is a curriculum it does not have, as live.
///
/// Every request is recorded in [requests]; [failWith] answers all of them
/// with that status instead.
class FakeGoalSelector {
  final List<FakeCurriculum> curricula = [];

  /// The selector's requests, as `METHOD path`, with a POST's body.
  final List<({String method, String path, Object? data})> requests = [];

  /// When set, every request is answered with this status (and `{}`).
  int? failWith;

  /// Adds the sample: the eindtermen with a heading, two goals (the second
  /// deprecated), a goal of basic literacy and a cluster with a goal; a
  /// curriculum of the philosophies of life without goals; and a
  /// mini-database of the school, hidden and a favourite, with a heading, a
  /// subheading and two goals.
  void loadSample() {
    curricula.addAll(const [
      FakeCurriculum(
        id: fakeEindtermenId,
        group: 'Overheid SO',
        title: 'Eindtermen derde graad, voorbeeld',
        leerplanType: fakeEindtermenType,
        selectable: ['goal', 'goal-basic'],
        children: [
          FakeGoalNode(
            id: fakeDomainId,
            type: 'title',
            title: 'Competenties voorbeeld',
            children: [
              FakeGoalNode(
                id: fakeGoal1Id,
                type: 'goal',
                title:
                    '<p>De leerlingen passen  een <strong>algoritme</strong> '
                    'toe &amp; meer.</p>',
                prefix: '01.01',
              ),
              FakeGoalNode(
                id: fakeGoal2Id,
                type: 'goal',
                title: '<p>Een oud doel.</p>',
                prefix: '01.02',
                deprecated: true,
              ),
              FakeGoalNode(
                id: fakeBasicGoalId,
                type: 'goal-basic',
                title: '<p>Een doel van basisgeletterdheid.</p>',
                prefix: '01.03',
              ),
              FakeGoalNode(
                id: fakeClusterId,
                type: 'cluster',
                title: 'Een cluster',
                children: [
                  FakeGoalNode(
                    id: fakeGoal3Id,
                    type: 'goal',
                    title: '<p>Een doel in een cluster.</p>',
                    prefix: '01.04',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      FakeCurriculum(
        id: fakeGodsdienstId,
        group: 'Overheid SO',
        title: 'Godsdienst, voorbeeld',
        leerplanType: 'godsdienst',
      ),
      FakeCurriculum(
        id: fakeMiniDbId,
        group: 'Minidatabanken',
        title: 'Digitale vaardigheden, voorbeeld',
        leerplanType: 'miniDB',
        visible: false,
        favourite: true,
        children: [
          FakeGoalNode(
            id: fakeMiniTitleId,
            type: 'title',
            title: 'Digitaal communiceren',
            prefix: 'GFL 1',
            children: [
              FakeGoalNode(
                id: fakeMiniSubtitleId,
                type: 'subtitle',
                title: 'Het platform',
                children: [
                  FakeGoalNode(
                    id: fakeMiniGoal1Id,
                    type: 'goal',
                    title: 'Je kan navigeren',
                  ),
                  FakeGoalNode(
                    id: fakeMiniGoal2Id,
                    type: 'goal',
                    title: 'Je kan bestanden delen',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  /// The selector's answer to [options], or null for a request that is not
  /// the selector's.
  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (!path.startsWith('$fakeGoalApi/')) return null;
    final data = options.data;
    requests.add((
      method: options.method,
      path: path,
      data: data is String ? jsonDecode(data) : data,
    ));
    if (failWith case final status?) return _json('{}', status: status);
    final route = path.substring(fakeGoalApi.length + 1).split('/');
    if (options.method == 'GET' && route.length == 3 && route[1] == 'list') {
      final groups = <String, List<Object?>>{};
      for (final curriculum in curricula) {
        (groups[curriculum.group] ??= []).add(curriculum.listJson());
      }
      return _json(
        jsonEncode([
          for (final MapEntry(:key, :value) in groups.entries)
            {'name': key, 'leerplanListItems': value},
        ]),
      );
    }
    if (options.method == 'GET' && route.length == 3) {
      for (final curriculum in curricula) {
        if (curriculum.id == route[1]) {
          return _json(jsonEncode(curriculum.treeJson()));
        }
      }
      return _json('{"title":"Not Found","status":404}', status: 404);
    }
    if (options.method == 'POST' && route.length == 2) {
      final body = requests.last.data;
      final selection = body is Map ? body['selection'] : null;
      final asked = <String, Set<String>>{};
      for (final goal in selection is List ? selection : const []) {
        if (goal case {
          'leerplanId': final String plan,
          'id': final String id,
        }) {
          (asked[plan] ??= {}).add(id);
        }
      }
      return _json(
        jsonEncode([
          for (final curriculum in curricula)
            if (asked[curriculum.id] case final ids?) curriculum.treeJson(ids),
        ]),
      );
    }
    return _json('{"title":"Not Found","status":404}', status: 404);
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
