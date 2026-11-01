import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_filter.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'planner_access.dart';
import 'planner_format.dart';

// The lesson clusters of a year plan planned for classes in the planner
// (#196, part 2 of #191): `planLessonCluster`, `getPlannedLessonClusters`,
// `getPlannedLessonClustersOf` and `trashPlannedLessonCluster` of
// `PlannerService` (dartschool#230). Shared by `plan_lesson_cluster`,
// `list_planned_lesson_clusters` and `trash_planned_lesson_cluster`.
//
// A planned cluster runs over whole days and keeps its link to the cluster
// (unlike a lesson planned from a lesfiche, a copy). In its period the
// planner shows the lesson hours of its classes and course in the own
// planner as lesson cluster moments, which pupils see.

/// [value], the argument [name] of a tool, as the id of a lesson hour of
/// the user's own planner whose classes and course a lesson cluster is
/// planned for: an empty lesson hour (`planned-placeholders/4069/<id>`), a
/// lesson (`planned-lessons/4069/<id>`) or a moment of a lesson cluster
/// planned before (`planned-lesson-cluster-moments/4069/<id>`).
///
/// Throws a [ToolError] for anything else, so that it never goes into a
/// request.
PlannedElementRef clusterHourArgument(Object? value, {String name = 'hour'}) {
  final hour = PlannedElementRef.parse(value, name: name);
  if (hour.type
      case PlannedElementType.placeholder ||
          PlannedElementType.lesson ||
          PlannedElementType.lessonClusterMoment) {
    return hour;
  }
  throw ToolError(
    '$name must be a lesson hour of your own planner of the classes and the '
    'course, as list_planner (planner me) shows it: an empty lesson hour '
    '(planned-placeholders/4069/…), a lesson (planned-lessons/4069/…) or a '
    'lesson cluster moment (planned-lesson-cluster-moments/4069/…); $hour '
    'is ${hour.type == PlannedElementType.assignment ? 'an assignment' : 'a ${hour.typeName}'}. '
    '$nothingSent',
  );
}

/// The last day of the school year (1 September to 31 August) of [day].
DateTime schoolYearEnd(DateTime day) =>
    DateTime(day.month >= 9 ? day.year + 1 : day.year, 8, 31);

final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The argument [name] of a tool ([value]) as a day, like `2026-11-16`, at
/// midnight in the time of this PC.
///
/// Throws a [ToolError] for anything else, also a date with a time: a
/// lesson cluster is planned over whole days.
DateTime clusterDayArgument(Object? value, {required String name}) {
  final text = value is String ? value.trim() : '';
  if (!_day.hasMatch(text)) {
    throw ToolError(
      '$name must be a day like 2026-11-16 (a lesson cluster is planned over '
      'whole days); ${value is String ? '"$value"' : '$value'} is not. '
      '$nothingSent',
    );
  }
  return parseDateArgument(name, text);
}

/// The `from` and `until` arguments of `plan_lesson_cluster`: the first and
/// the last day of the period, both in one school year (1 September to 31
/// August), as the planner takes it.
///
/// Throws a [ToolError] that says what to fix for a day that is not one,
/// until before from, or two school years, before anything is sent.
({DateTime from, DateTime until}) clusterPeriodArguments(
  Map<String, Object?> arguments,
) {
  final from = clusterDayArgument(arguments['from'], name: 'from');
  final until = clusterDayArgument(arguments['until'], name: 'until');
  if (until.isBefore(from)) {
    throw ToolError(
      'until (${formatPlannerDate(until)}) is before from '
      '(${formatPlannerDate(from)}): pass the first day as from and the last '
      'as until. $nothingSent',
    );
  }
  if (schoolYearEnd(from) != schoolYearEnd(until)) {
    throw ToolError(
      'from (${formatPlannerDate(from)}) and until '
      '(${formatPlannerDate(until)}) are in different school years, and the '
      'planner plans a lesson cluster within one (1 September to 31 '
      'August): plan it in two calls. $nothingSent',
    );
  }
  return (from: from, until: until);
}

/// What `list_planned_lesson_clusters` answers for [planned], the clusters
/// planned in the own planner from [from] to [until].
String formatPlannedClustersInPeriod(
  List<PlannedLessonCluster> planned, {
  required DateTime from,
  required DateTime until,
}) {
  final period = formatPlannerPeriod(from, until);
  if (planned.isEmpty) {
    return 'No lesson clusters are planned in your own planner $period. Plan '
        'one with plan_lesson_cluster.';
  }
  return [
    'Lesson clusters planned in your own planner $period (${planned.length}), '
        'each with its id at the end:',
    for (final cluster in _byDays(planned))
      '- ${formatPlannedClusterLine(cluster)}',
    _readOrTrash,
  ].join('\n');
}

/// What `list_planned_lesson_clusters` answers for [planned], where the
/// lesson cluster [cluster] of the year plan [plan] was planned.
String formatPlannedClustersOf(
  List<PlannedLessonCluster> planned, {
  required TeachingAssignment plan,
  required LessonCluster cluster,
}) {
  final which =
      'The lesson cluster "${cluster.name}" of the year plan '
      '"${plan.name}"';
  if (planned.isEmpty) {
    return '$which is not planned for any class. Plan it with '
        'plan_lesson_cluster.';
  }
  return [
    '$which is planned ${planned.length} '
        '${planned.length == 1 ? 'time' : 'times'}, each with its id at the '
        'end:',
    for (final cluster in _byDays(planned))
      '- ${formatPlannedClusterLine(cluster)}',
    _readOrTrash,
  ].join('\n');
}

const _readOrTrash =
    'Read one with read_planned_element, or move it to the trash with '
    'trash_planned_lesson_cluster. list_planner (planner me) shows the '
    'lesson hours of a planned cluster as lesson cluster moments.';

/// [planned] by their first day, then their last, then their name.
List<PlannedLessonCluster> _byDays(List<PlannedLessonCluster> planned) =>
    sortedByTime(planned).cast<PlannedLessonCluster>();
