import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../goals/goals.dart';
import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'lesfiche_bulk.dart';
import 'lesfiche_detail.dart';
import 'lesfiches.dart';
import 'planner_access.dart';

// The year plans of the Lesfiches module (#191): the teaching assignments
// ("leeropdrachten") of `TeachingAssignmentService` (dartschool#229), each a
// collection of the user's lesfiches split into lesson clusters, which hold
// titles and lesfiches in order, with learning goals. Shared by
// `list_year_plans`, `read_year_plan`, `create_year_plan`,
// `add_lesson_cluster`, `add_to_lesson_cluster`, `set_lesson_cluster_goals`
// and `delete_year_plan`.
//
// The tools name a year plan and a cluster by their ids (UUIDs) only, as
// `list_year_plans` and `read_year_plan` print them; the library also needs
// their platform, which the tools take from the list of the user's year
// plans ([findYearPlan], one read before every write): a year plan or a
// cluster that is not in it is refused there, with the plans or clusters
// there are, before anything is sent.
//
// The library sends a create or an add once, never again after logging in
// again, and throws a [SmartschoolLessonContentSaveUnconfirmedError] when
// the module's answer does not confirm a write that went out; a refused
// session means that the write was not sent, so [SmartschoolSession.run]
// may repeat the action of a single write with the reads before it. A tool
// that makes two writes (a title, then lesfiches) gives each a session
// action of its own, so that a repeat never sends the first one again.

/// The longest name of a year plan or a cluster, and the longest title, the
/// module takes ([TeachingAssignmentService.maxNameLength]).
const maxYearPlanNameLength = TeachingAssignmentService.maxNameLength;

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

/// [value], the argument [name] of a tool, as the id of a year plan or a
/// cluster ([what], like `year plan`) as `list_year_plans` and
/// `read_year_plan` print it: a UUID. A leading `id `, as the tools print
/// it, is allowed.
///
/// Throws a [ToolError] naming the expected form for anything else (such as
/// a name), so that it never goes into a request.
String yearPlanIdArgument(
  Object? value, {
  required String name,
  required String what,
  required String shownBy,
}) {
  var text = value is String ? value.trim() : '';
  if (text.toLowerCase().startsWith('id ')) text = text.substring(3).trim();
  if (_uuid.hasMatch(text)) return text;
  throw ToolError(
    '$name must be the id of a $what as $shownBy shows it, like '
    'c0000000-0000-4000-9000-000000000001; '
    '${value is String ? '"$value"' : '$value'} is not. $nothingSent',
  );
}

/// The `year_plan` argument [value] ([yearPlanIdArgument]).
String yearPlanArgument(Object? value) => yearPlanIdArgument(
  value,
  name: 'year_plan',
  what: 'year plan',
  shownBy: 'list_year_plans',
);

/// The `cluster` argument [value] ([yearPlanIdArgument]).
String clusterArgument(Object? value) => yearPlanIdArgument(
  value,
  name: 'cluster',
  what: 'lesson cluster',
  shownBy: 'read_year_plan',
);

/// The input schema of a `year_plan` argument.
Schema yearPlanSchema() => Schema.string(
  description:
      'The id of the year plan, as list_year_plans shows it at the end of '
      'its line.',
  minLength: 1,
);

/// The input schema of a `cluster` argument.
Schema clusterSchema() => Schema.string(
  description:
      'The id of the lesson cluster, as read_year_plan shows it at the end '
      'of its line.',
  minLength: 1,
);

/// [value], the argument [name] of a tool, as the name of a year plan or a
/// cluster or the text of a title ([what], like `the year plan`): without
/// the white space around it.
///
/// Throws a [ToolError] for an empty text, and for one longer than
/// [maxYearPlanNameLength] characters (the module refuses it with a bare
/// `400`, seen live), so that it never goes into a request.
String yearPlanNameArgument(
  Object? value, {
  required String name,
  required String what,
}) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) {
    throw ToolError('$name is empty: give $what a name. $nothingSent');
  }
  if (text.length > maxYearPlanNameLength) {
    throw ToolError(
      '$name is ${text.length} characters long, and the Lesfiches module '
      'takes at most $maxYearPlanNameLength for $what: shorten it. '
      '$nothingSent',
    );
  }
  return text;
}

/// The year plan of the user's year plans ([plans],
/// [TeachingAssignmentService.getTeachingAssignments]) with the id [id]
/// (ignoring case).
///
/// Throws a [ToolError] that lists the year plans with their ids when none
/// has that id, before anything is sent.
TeachingAssignment findYearPlan(List<TeachingAssignment> plans, String id) {
  for (final plan in plans) {
    if (plan.id.toLowerCase() == id.toLowerCase()) return plan;
  }
  throw ToolError(
    'You have no year plan with id $id (any more). $nothingSent '
    '${plans.isEmpty ? 'You have no year plans: make one with create_year_plan.' : 'Your year plans, each with its id at the end:\n${[for (final plan in plans) '- ${formatYearPlanLine(plan)}'].join('\n')}'}',
  );
}

/// The cluster of [plan] (in the short form a year plan lists them) with
/// the id [id] (ignoring case).
///
/// Throws a [ToolError] that lists the clusters of [plan] with their ids
/// when it has none with that id, before anything is sent.
LessonCluster findCluster(TeachingAssignment plan, String id) {
  for (final cluster in plan.clusters) {
    if (cluster.id.toLowerCase() == id.toLowerCase()) return cluster;
  }
  throw ToolError(
    'The year plan "${plan.name}" has no lesson cluster with id $id. '
    '$nothingSent '
    '${plan.clusters.isEmpty ? 'It has no clusters: add one with add_lesson_cluster.' : 'Its clusters, each with its id at the end:\n${[for (final cluster in plan.clusters) '- ${cluster.name} | id ${cluster.id}'].join('\n')}'}',
  );
}

/// Reads the user's year plans with [client] and returns the one with the
/// id [id] ([findYearPlan]).
Future<TeachingAssignment> readYearPlan(
  SmartschoolClient client,
  String id,
) async => findYearPlan(
  await TeachingAssignmentService(client).getTeachingAssignments(),
  id,
);

/// Which lesfiches [plan] takes, in a few words.
String formatContentFilter(TeachingAssignment plan) =>
    switch (plan.contentFilter) {
      TeachingAssignmentContentFilter.all => 'takes all your lesfiches',
      TeachingAssignmentContentFilter.none => 'takes no lesfiches',
      TeachingAssignmentContentFilter.particular =>
        'takes the lesfiches of some labels, courses or assignment types',
      TeachingAssignmentContentFilter.other => 'takes an unknown selection',
    };

/// One line describing [plan]: its name, which lesfiches it takes, its
/// clusters by name, hidden or a favourite, and its id.
String formatYearPlanLine(TeachingAssignment plan) {
  final clusters = plan.clusters;
  return [
    if (plan.name.isEmpty) '(no name)' else plan.name,
    formatContentFilter(plan),
    if (clusters.isEmpty)
      'no clusters'
    else
      '${clusters.length} ${clusters.length == 1 ? 'cluster' : 'clusters'}: '
          '${[for (final cluster in clusters) cluster.name.isEmpty ? '(no name)' : cluster.name].join(', ')}',
    if (!plan.isVisible) 'hidden',
    if (plan.isFavourite) 'favourite',
    'id ${plan.id}',
  ].join(' | ');
}

/// What `list_year_plans` answers: the year plans [plans], one line each.
String formatYearPlans(List<TeachingAssignment> plans) {
  if (plans.isEmpty) {
    return 'You have no year plans in Lesfiches. Make one with '
        'create_year_plan.';
  }
  return [
    'Your year plans in Lesfiches (${plans.length}), each with its id at '
        'the end:',
    for (final plan in plans) '- ${formatYearPlanLine(plan)}',
    'Read one with its clusters and their lesfiches with read_year_plan.',
  ].join('\n');
}

String _count(int? count, String singular, String plural) =>
    '${count ?? 0} ${count == 1 ? singular : plural}';

/// One line describing [cluster], as `getClusters` gives it: its name, how
/// many lesson and assignment lesfiches and goals it has, the estimate of
/// its teaching hours, hidden, and its id.
///
/// The goals counted are the cluster's own, those its `Goals:` lists: the
/// module's `numberOfGoals` also counts those of its lesfiches (seen live,
/// #206). An estimate of 0 hours is the module's for none: left out.
String formatClusterLine(LessonCluster cluster) => [
  if (cluster.name.isEmpty) '(no name)' else cluster.name,
  _count(cluster.numberOfLessons, 'lesson lesfiche', 'lesson lesfiches'),
  _count(
    cluster.numberOfAssignments,
    'assignment lesfiche',
    'assignment lesfiches',
  ),
  _count(cluster.goals.length, 'goal', 'goals'),
  if (cluster.teachingHoursEstimate case final hours? when hours > 0)
    'about ${_number(hours)} teaching ${hours == 1 ? 'hour' : 'hours'}',
  if (!cluster.isVisible) 'hidden',
  'id ${cluster.id}',
].join(' | ');

String _number(num value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// One line describing [entry], an entry of a cluster's content: `title
/// "Week 1"`, or a lesfiche by kind, name, its teaching hours and goals,
/// and its id.
String formatClusterEntry(LessonClusterEntry entry) => switch (entry) {
  LessonClusterTitle(:final text) => 'title "$text"',
  LessonClusterLesfiche(
    :final item,
    :final teachingHoursEstimate,
    :final numberOfGoals,
  ) =>
    [
      formatLesficheKind(item),
      if (item.name.isEmpty) '(no name)' else item.name,
      if (teachingHoursEstimate case final hours? when hours > 0)
        '${_number(hours)} teaching ${hours == 1 ? 'hour' : 'hours'}',
      if (numberOfGoals case final goals?) _count(goals, 'goal', 'goals'),
      'id ${item.id}',
    ].join(' | '),
};

/// A cluster of a year plan as `read_year_plan` reads it: the cluster in
/// full, and its content in order.
typedef ClusterRead = ({
  LessonCluster cluster,
  List<LessonClusterEntry> content,
});

/// What `read_year_plan` answers: [plan]'s line, then each of [clusters]
/// with its goals (named by [goals], which names those of every cluster)
/// and its content in order.
String formatYearPlan(
  TeachingAssignment plan,
  List<ClusterRead> clusters, {
  required NamedGoals goals,
  bool onlyOne = false,
}) {
  final lines = [
    'Year plan ${formatYearPlanLine(plan)}',
    if (clusters.isEmpty) ...[
      '',
      'It has no lesson clusters yet: add one with add_lesson_cluster.',
    ],
  ];
  for (final (index, (:cluster, :content)) in clusters.indexed) {
    lines
      ..add('')
      ..add(
        '${onlyOne ? 'Cluster' : 'Cluster ${index + 1}'}: '
        '${formatClusterLine(cluster)}',
      )
      ..addAll([
        for (final line in formatNamedGoals((
          refs: cluster.goals,
          curricula: goals.curricula,
          error: goals.error,
        )))
          '  $line',
      ]);
    if (content.isEmpty) {
      lines.add('  Content: none');
    } else {
      lines
        ..add('  Content, in order:')
        ..addAll([
          for (final (n, entry) in content.indexed)
            '  ${n + 1}. ${formatClusterEntry(entry)}',
        ]);
    }
  }
  return lines.join('\n');
}

/// What a year-plan write adds to an error that came before the module
/// changed anything.
const yearPlanUnchanged = 'Nothing was changed.';

/// Runs the year-plan write [write] on the session; [what] names it (like
/// `the creation of the year plan "Informatica 5"`) for the errors.
///
/// The library's errors become [ToolError]s that end in [nothingDone]
/// ([yearPlanWriteToolError]). A [ToolError] of [write] itself (a check
/// before sending), a [SmartschoolLessonContentSaveUnconfirmedError] (the
/// write may or may not have been made) and a login or connection failure
/// are thrown as they are.
Future<T> withYearPlanWrite<T>(
  SmartschoolSession session,
  Future<T> Function(SmartschoolClient client) write, {
  required String what,
  String nothingDone = yearPlanUnchanged,
}) async {
  try {
    return await session.run(write);
  } on SmartschoolLessonContentSaveUnconfirmedError {
    rethrow;
  } catch (error) {
    final toolError = yearPlanWriteToolError(
      error,
      what: what,
      nothingDone: nothingDone,
    );
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of a year-plan write that came
/// before the module changed anything, ending in [nothingDone]; null for
/// anything else.
///
/// - [SmartschoolLessonContentWriteRefusedError]: the module refused the
///   write: `404` for a year plan or cluster it does not know (any more),
///   `403` for lesfiches the year plan does not take, any other with its
///   status;
/// - an [ArgumentError]: the library refused the write before sending it;
/// - the other errors of the module ([plannerToolError]), which come from a
///   read before the write.
ToolError? yearPlanWriteToolError(
  Object error, {
  required String what,
  required String nothingDone,
}) {
  switch (error) {
    case SmartschoolLessonContentWriteRefusedError(:final statusCode):
      log('year plans write: refused (HTTP $statusCode)');
      return ToolError(switch (statusCode) {
        404 =>
          'The Lesfiches module answered $what with HTTP 404: it no longer '
              'has that year plan or lesson cluster (removed meanwhile, in '
              'Smartschool itself). List them again with list_year_plans. '
              '$nothingDone',
        403 =>
          'The Lesfiches module refused $what (HTTP 403): the year plan does '
              'not take these lesfiches (its selection of lesfiches leaves '
              'them out), or does not let you change it. $nothingDone',
        _ =>
          'The Lesfiches module refused $what (HTTP $statusCode). '
              '$nothingDone',
      });
    case ArgumentError(:final name, :final message) when error is! RangeError:
      log('year plans write: refused before sending ($name)');
      return ToolError(
        '${capitalised(what)} was refused before it was sent: '
        '${name == null ? '' : '$name '}$message. $nothingDone',
      );
  }
  final toolError = plannerToolError(error);
  if (toolError == null) return null;
  return ToolError('${toolError.message} $nothingDone');
}

/// The result of a year-plan write that went out without the module
/// confirming it ([error]): [what] (like `The year plan "Informatica 5"`)
/// may or may not have been [done] (a past participle). [also] comes after
/// that. Claude must not call [tool] again for it ([why] says what a second
/// call could do, like `a second call could add it twice`: its own words,
/// not [done]'s, #225), but first [check] and tell the user.
CallToolResult yearPlanWriteNotConfirmed({
  required String tool,
  required String what,
  required String check,
  required String why,
  required SmartschoolLessonContentSaveUnconfirmedError error,
  String done = 'made',
  String? also,
}) {
  // Without the library's message, which names the plan.
  log(
    '$tool: the Lesfiches module did not confirm a year-plan write, not '
    'retrying (${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'})',
  );
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '$what may or may not have been $done: it was sent, but the '
              'Lesfiches module did not confirm it.',
          ?also,
          'Do not call $tool again for it: $why. First $check. Then tell the '
              'user what you found.',
        ].join(' '),
      ),
    ],
  );
}

/// Reads the clusters of [plan] in full and the content of each (only the
/// cluster [only] when it is given), and names the goals of those clusters
/// ([nameGoals]: one request for all), with [client]. Only reads.
Future<({List<ClusterRead> clusters, NamedGoals goals})> readYearPlanClusters(
  SmartschoolClient client,
  TeachingAssignment plan, {
  String? only,
}) async {
  final service = TeachingAssignmentService(client);
  final clusters = [
    for (final cluster in await service.getClusters(plan))
      if (only == null || cluster.id.toLowerCase() == only.toLowerCase())
        cluster,
  ];
  final reads = <ClusterRead>[
    for (final cluster in clusters)
      (cluster: cluster, content: await service.getClusterContent(cluster)),
  ];
  final refs = <LearningGoalRef>[];
  for (final cluster in clusters) {
    for (final goal in cluster.goals) {
      if (!refs.any((known) => sameGoals([known], [goal]))) refs.add(goal);
    }
  }
  return (clusters: reads, goals: await nameGoals(client, refs));
}

/// The cluster [clusterId] of the year plan [planId] read back after a
/// write, as `read_year_plan` shows it, in a session action of its own (the
/// write is never repeated for it). When the read fails, the write still
/// went through: the text says so, and how to read it.
Future<String> yearPlanClusterReadBack(
  SmartschoolSession session,
  String planId,
  String clusterId,
) async {
  try {
    return await withPlannerClient(session, (client) async {
      final plan = await readYearPlan(client, planId);
      final read = await readYearPlanClusters(client, plan, only: clusterId);
      return formatYearPlan(
        plan,
        read.clusters,
        goals: read.goals,
        onlyOne: true,
      );
    });
  } on Object catch (error) {
    final message = switch (error) {
      ToolError(:final message) => message,
      SmartschoolProblem(:final message) => message,
      _ => null,
    };
    if (message == null) rethrow;
    log('year plans: reading the cluster back after a write failed');
    return 'Reading the cluster back failed: $message Read it with '
        'read_year_plan (year_plan $planId, cluster $clusterId).';
  }
}

/// The lesfiches of [taken] (those the year plan takes,
/// [TeachingAssignmentService.getLessonContent]) with the ids [ids], in
/// that order.
///
/// Throws a [ToolError] for an id that is none of them, before anything is
/// sent: it is not one of the user's lesfiches, it is in the trash, or the
/// year plan's selection leaves it out ([plan]'s filter says which).
List<LessonContentItem> takenLesfiches(
  TeachingAssignment plan,
  List<LessonContentItem> taken,
  List<String> ids,
) {
  final (:found, :unknown) = findLesfiches(taken, ids);
  if (unknown.isNotEmpty) {
    throw ToolError(
      'The year plan "${plan.name}" (which ${formatContentFilter(plan)}) '
      'does not take the lesfiches with ${unknown.length == 1 ? 'id ${unknown.single}' : 'the ids ${unknown.join(', ')}'}: '
      'they are not among your lesfiches (list_lesfiches shows them, with '
      'their ids), are in the trash, or its selection of lesfiches leaves '
      'them out. $nothingSent',
    );
  }
  for (final item in found) {
    if (item.type == LessonContentType.other) {
      throw ToolError(
        '${capitalised(lesficheTitle(item))} (id ${item.id}) is of the kind '
        '"${item.typeName}", which this server cannot add to a cluster: '
        'only lesson and assignment lesfiches. $nothingSent',
      );
    }
  }
  // The same lesfiche once, even when the module lists it twice.
  final once = <LessonContentItem>[];
  for (final item in found) {
    if (!once.any((known) => known.id.toLowerCase() == item.id.toLowerCase())) {
      once.add(item);
    }
  }
  return once;
}
