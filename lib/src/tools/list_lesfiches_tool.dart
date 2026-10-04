import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// At most this many lesfiches are listed, with a note on how to ask for
/// fewer.
const maxLesficheLines = 200;

/// `list_lesfiches`: the user's lesfiches in the Lesfiches module (lesson
/// content), lessons by default, by name, filtered by label, name and kind:
/// what `plan_lesfiche` plans into the user's lesson hours.
ServerTool listLesfichesTool(SmartschoolSession session) => ServerTool(
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
        'be on the lesfiche) and query (words in the name). Only lesson '
        'lesfiches can be planned, with plan_lesfiche, hidden ones too. To '
        'plan a series of lesfiches into the user\'s next lessons of '
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
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final kind = LesficheKind.parse(arguments['type']);
  final labels = _labels(arguments['label']);
  final query = (arguments['query'] as String? ?? '').trim();
  final words = [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  final (all, courseError) = await withPlannerClient(session, (client) async {
    try {
      return (await LessonContentService(client).getItems(), null);
    } on SmartschoolLessonContentCourseListError catch (error) {
      // Only the course list that names the courses failed: its error
      // carries the lesfiches as read, without the names.
      log('lesfiches: $error');
      return (error.items, error);
    }
  });
  final shown = sortedByName(
    all.where(
      (item) =>
          kind.includes(item) &&
          lesficheMatches(item, labels: labels.keys.toSet(), words: words),
    ),
  );

  return CallToolResult(
    content: [
      TextContent(
        text: formatLesfiches(
          kind: kind,
          labels: labels.values.toList(),
          query: query,
          all: all,
          shown: shown,
          courseError: courseError,
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

/// What `list_lesfiches` answers: a header with what was asked for ([kind],
/// [labels], [query]) and how many of [all] lesfiches match, one line per
/// lesfiche of [shown] ([formatLesficheLine], at most [maxLesficheLines]),
/// and notes on the courses and on what can be planned.
///
/// The courses of [shown] are named by the library
/// ([LessonContentCourse.name]), unless the school's course list could not
/// be read ([courseError]): then only their number is given, with a note
/// when a lesfiche listed has a course. `getItems()` reads the course list
/// when any lesfiche has a course, also one that is not listed. When nothing
/// matches a filter on labels, the answer lists the labels the lesfiches of
/// [kind] do have.
String formatLesfiches({
  required LesficheKind kind,
  required List<String> labels,
  required String query,
  required List<LessonContentItem> all,
  required List<LessonContentItem> shown,
  required SmartschoolLessonContentError? courseError,
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
  final withCourseNames = courseError == null;
  final unnamed =
      withCourseNames &&
      listed.any((item) => item.courses.any((course) => course.name == null));
  final count = kind.count(shown.length);
  return [
    '${what.isEmpty ? count : '$count $what'}, $of, by name:',
    for (final item in listed)
      formatLesficheLine(item, withCourseNames: withCourseNames),
    if (shown.length > listed.length)
      'Note: only the first ${listed.length} of the ${shown.length} are '
          'shown: narrow the list with label or query.',
    if (courseError case SmartschoolLessonContentError(
      :final statusCode,
    ) when listed.any((item) => item.courses.isNotEmpty))
      'Note: the names of the courses could not be read from the school\'s '
          'course list${statusCode == null ? '' : ' (HTTP $statusCode)'}, so '
          'only the number of courses is shown.',
    if (unnamed)
      'A course that the school\'s course list does not name shows as '
          '"unnamed course".',
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
