import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// At most this many lesfiches are listed, with a note on how to ask for
/// fewer.
const maxLesficheLines = 200;

/// `list_lesfiches`: the user's lesfiches in the Lesfiches module (lesson
/// content), lessons by default, by name, filtered by label, name and kind:
/// what `plan_lesfiche` plans into the user's lesson hours.
///
/// [now] gives today, for the period of the own planner that names the
/// courses ([ownCourseNames]).
ServerTool listLesfichesTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'list_lesfiches',
    title: 'List your Smartschool lesfiches',
    description:
        'Lists the user\'s lesfiches in the Smartschool Lesfiches module: '
        'the lessons and assignments the user keeps there to plan into the '
        'planner (their own, and lesfiches shared with them if Smartschool '
        'lists those). By default only lesson lesfiches. One line per '
        'lesfiche: its kind (an assignment with its type, such as "KT Kleine '
        'Taak"), name, labels (such as JAAR 6 and TRIMESTER 1), courses, '
        'whether it is visible or hidden in the module, the day it was last '
        'changed, and its id for plan_lesfiche. Sorted by name, with numbers '
        'in order (Les 2 before Les 10); when the user wants another order, '
        'order the list yourself. Filter with label (every label given must '
        'be on the lesfiche) and query (words in the name). Courses are named '
        'after the user\'s own planner of the 4 weeks before and after '
        'today; a course without a lesson hour there is not named. Only '
        'lesson lesfiches can be planned, with plan_lesfiche, hidden ones '
        'too. To plan a series of lesfiches into the user\'s next lessons of '
        'a course and class: list the lesfiches with their labels, list the '
        'empty lesson hours with list_planner (planner me), and propose the '
        'user a mapping of lesfiches onto hours, in label and name order. '
        'Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the name of the lesfiche, '
              'case-insensitive, in any order. Default: any name.',
        ),
        'label': Schema.list(
          description:
              'Labels the lesfiche must all have, like ["JAAR 6", '
              '"TRIMESTER 1"]: the whole text of each label, '
              'case-insensitive. Default: any labels.',
          items: Schema.string(),
        ),
        'type': UntitledSingleSelectEnumSchema(
          description:
              'lessons (the default; only these can be planned with '
              'plan_lesfiche), assignments (tests and tasks) or all.',
          values: [for (final kind in LesficheKind.values) kind.argument],
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List your Smartschool lesfiches',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}, now),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
  DateTime Function() now,
) async {
  final today = now();
  final kind = LesficheKind.parse(arguments['type']);
  final labels = _labels(arguments['label']);
  final query = (arguments['query'] as String? ?? '').trim();
  final words = [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  final (all, shown, courses) = await withPlannerClient(session, (
    client,
  ) async {
    // Without the library's course names (yvanvds/dartschool#101): one
    // request, as before 0.3.3. The courses are named after the own planner
    // until #87.
    final all = await LessonContentService(
      client,
    ).getItems(withCourseNames: false);
    final shown = sortedByName(
      all.where(
        (item) =>
            kind.includes(item) &&
            lesficheMatches(item, labels: labels.keys.toSet(), words: words),
      ),
    );
    // The planner names the courses; nothing to name, nothing to read.
    final courses = shown.any((item) => item.courses.isNotEmpty)
        ? await _courseNames(PlannerService(client), today)
        : (value: const <String, String>{}, error: null);
    return (all, shown, courses);
  });

  return CallToolResult(
    content: [
      TextContent(
        text: formatLesfiches(
          kind: kind,
          labels: labels.values.toList(),
          query: query,
          all: all,
          shown: shown,
          courseNames: courses.value,
          courseError: courses.error,
          coursePeriod: lesficheCoursePeriod(today),
        ),
      ),
    ],
  );
}

/// The `label` argument [value], a list of texts (the input schema
/// allows no other): the labels as given, by their text as [normalLabel]
/// compares them. An empty one is left out.
Map<String, String> _labels(Object? value) {
  final labels = <String, String>{};
  for (final item in value is List ? value.whereType<String>() : <String>[]) {
    final label = normalLabel(item);
    if (label.isNotEmpty) labels.putIfAbsent(label, () => item.trim());
  }
  return labels;
}

/// The names of the user's courses ([ownCourseNames]), or the planner's
/// error reading them failed with: the lesfiches are listed without them.
///
/// Only a [SmartschoolPlannerError] is caught, which the log gets: a refused
/// session or a lost connection still goes to [SmartschoolSession.run].
Future<({Map<String, String>? value, SmartschoolPlannerError? error})>
_courseNames(PlannerService planner, DateTime now) async {
  try {
    return (value: await ownCourseNames(planner, now: now), error: null);
  } on SmartschoolPlannerError catch (error) {
    log('planner: $error');
    return (value: null, error: error);
  }
}

/// What `list_lesfiches` answers: a header with what was asked for ([kind],
/// [labels], [query]) and how many of [all] lesfiches match, one line per
/// lesfiche of [shown] ([formatLesficheLine], at most [maxLesficheLines]),
/// and notes on the courses and on what can be planned.
///
/// [courseNames] names the courses ([ownCourseNames], read in
/// [coursePeriod]); it is null when they could not be read ([courseError]).
/// When nothing matches a filter on labels, the answer lists the labels the
/// lesfiches of [kind] do have.
String formatLesfiches({
  required LesficheKind kind,
  required List<String> labels,
  required String query,
  required List<LessonContentItem> all,
  required List<LessonContentItem> shown,
  required Map<String, String>? courseNames,
  required SmartschoolPlannerError? courseError,
  required ({DateTime from, DateTime until}) coursePeriod,
}) {
  if (all.isEmpty) {
    return 'You have no lesfiches in the Lesfiches module.';
  }
  final what = [
    if (labels.isNotEmpty)
      'with the ${labels.length == 1 ? 'label' : 'labels'} '
          '${_and([for (final label in labels) '"$label"'])}',
    if (query.isNotEmpty) 'whose name holds "$query"',
  ].join(' and ');
  final of = 'of the ${all.length} lesfiches in the Lesfiches module';
  final matching = what.isEmpty ? kind.plural : '${kind.plural} $what';
  if (shown.isEmpty) {
    return [
      'No $matching ($of).',
      if (labels.isNotEmpty) _labelsHint(kind, all),
    ].join('\n');
  }
  final listed = shown.take(maxLesficheLines).toList();
  final unnamed =
      courseNames != null &&
      listed.any(
        (item) => item.courses.any(
          (course) => !courseNames.containsKey(course.id.toLowerCase()),
        ),
      );
  final count = kind.count(shown.length);
  return [
    '${what.isEmpty ? count : '$count $what'}, $of, by name:',
    for (final item in listed) formatLesficheLine(item, courseNames),
    if (shown.length > listed.length)
      'Note: only the first ${listed.length} of the ${shown.length} are '
          'shown: narrow the list with label or query.',
    if (courseError case SmartschoolPlannerError(:final statusCode))
      'Note: the names of the courses could not be read from your planner'
          '${statusCode == null ? '' : ' (HTTP $statusCode)'}, so only the '
          'number of courses is shown.',
    if (unnamed)
      'Courses are named after your own planner from '
          '${formatPlannerDate(coursePeriod.from)} to '
          '${formatPlannerDate(coursePeriod.until)}; a course without a lesson '
          'hour there shows as "$unnamedCourse".',
    if (listed.any((item) => item.type != LessonContentType.lesson))
      'Only the lesson lesfiches can be planned, with plan_lesfiche.',
  ].join('\n');
}

/// The labels the lesfiches of [kind] among [all] have, as a hint after a
/// filter on labels that matched nothing.
String _labelsHint(LesficheKind kind, List<LessonContentItem> all) {
  final labels = <String, String>{};
  for (final item in all.where(kind.includes)) {
    for (final label in item.labels) {
      final text = label.text.trim();
      if (text.isNotEmpty) labels.putIfAbsent(normalLabel(text), () => text);
    }
  }
  if (labels.isEmpty) return 'None of your ${kind.plural} has a label.';
  final sorted = labels.values.toList()..sort(compareLesficheNames);
  return 'The labels of your ${kind.plural}: ${sorted.join(', ')}.';
}

/// [items] as `a`, `a and b`, `a, b and c`.
String _and(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
