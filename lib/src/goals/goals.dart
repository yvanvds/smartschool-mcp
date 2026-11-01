import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';

// The learning goals of Smartschool's goal selector (`GoalService`,
// dartschool#222): the curricula it offers (the eindtermen, the curricula of
// the philosophies of life, the school's own mini-databases), each as a tree
// of headings and goals, as `list_curricula` and `read_curriculum` show them
// (#186), and the naming of the goals a lesfiche or a planned lesson stores,
// for `read_lesfiche` and `read_planned_element`.
//
// Every goal is shown with the three fields a lesfiche or a lesson stores
// for it (a `LearningGoalRef`: `id`, `leerplanId`, `type`), in the words of
// [formatGoalRef], so that a goal write (#187) can take them from any of
// these tools.

/// At most this many goals are listed by `read_curriculum`, with a note on
/// how to ask for fewer.
const maxGoalLines = 200;

/// Runs [action] with a [GoalService] on the session's logged-in client.
/// The selector's own errors become [ToolError]s ([goalToolError]); login
/// and connection failures stay `SmartschoolProblem`s.
///
/// The service only reads, so [action] may run twice (when Smartschool
/// refuses the session).
Future<T> withGoals<T>(
  SmartschoolSession session,
  Future<T> Function(GoalService goals) action,
) async {
  try {
    return await session.run((client) => action(GoalService(client)));
  } catch (error) {
    final toolError = goalToolError(error);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of the goal selector or of
/// [GoalService]'s checks, or null for anything else.
///
/// - [SmartschoolCurriculumNotFoundError], and the [ArgumentError] of an ID
///   that cannot be one: the selector has no curriculum with that ID; take
///   it from `list_curricula`.
/// - [SmartschoolGoalAccessDeniedError]: the selector refused the read.
/// - Any other [SmartschoolGoalError]: an answer the server cannot use. The
///   library's message can quote the answer, so it goes to the log only.
ToolError? goalToolError(Object error) {
  switch (error) {
    case SmartschoolCurriculumNotFoundError(:final curriculumId):
      log('goals: $error');
      return _noCurriculum(curriculumId);
    case ArgumentError(name: 'curriculumId', :final invalidValue)
        when error is! RangeError:
      log('goals: $error');
      return _noCurriculum('$invalidValue');
    case SmartschoolGoalAccessDeniedError():
      log('goals: $error');
      return const ToolError(
        'The goal selector of Smartschool refused the read to your account. '
        'The learning goals are only offered to accounts that may pick the '
        'goals of a lesfiche or a lesson.',
      );
    case SmartschoolGoalError(:final statusCode):
      log('goals: $error');
      return ToolError(
        'The goal selector gave an answer the server could not use'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}. Try again in a '
        'moment; the technical details are in the server log.',
      );
  }
  return null;
}

ToolError _noCurriculum(String id) => ToolError(
  'The goal selector has no curriculum with id $id. Take the id from '
  'list_curricula.',
);

/// The words of a `query` argument [value], in lower case; none when it is
/// absent or empty.
List<String> goalQueryWords(Object? value) => [
  if (value is String)
    for (final word in value.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
];

bool _holdsAll(String text, List<String> words) {
  final lower = text.toLowerCase();
  return words.every(lower.contains);
}

/// What `list_curricula` answers: the curricula of [groups], in the
/// selector's groups and order, one line each ([_curriculumLine]), only
/// those whose title holds every word of [query] when it is not empty.
String formatCurricula(List<CurriculumGroup> groups, String query) {
  final words = goalQueryWords(query);
  final all = groups.fold(0, (count, group) => count + group.curricula.length);
  if (all == 0) return 'The goal selector offers no curricula.';
  final shown = [
    for (final group in groups)
      (
        group,
        [
          for (final item in group.curricula)
            if (_holdsAll(item.title, words)) item,
        ],
      ),
  ];
  final count = shown.fold(0, (count, entry) => count + entry.$2.length);
  final of = 'of the $all curricula of the goal selector';
  if (count == 0) {
    return 'No curriculum whose title holds "${query.trim()}" ($of).';
  }
  return [
    if (words.isEmpty)
      'The $all curricula of the goal selector, in its groups:'
    else
      '$count ${count == 1 ? 'curriculum' : 'curricula'} whose title holds '
          '"${query.trim()}", $of, in its groups:',
    for (final (group, items) in shown)
      if (items.isNotEmpty) ...[
        '${group.name.trim().isEmpty ? '(no group name)' : group.name.trim()}:',
        for (final item in items) '- ${_curriculumLine(item)}',
      ],
    'read_curriculum reads the goals of one, by its id.',
  ].join('\n');
}

String _curriculumLine(CurriculumListItem item) => [
  if (item.title.trim() case final title when title.isNotEmpty)
    title
  else
    '(no title)',
  if (!item.isVisible) 'hidden in the selector',
  if (item.isFavourite) 'a favourite',
  'id ${item.id}',
].join(' | ');

/// [ref], the three fields a lesfiche or a planned lesson stores for a
/// goal, as every goal tool shows them: `id …, leerplanId …, type …`.
String formatGoalRef(LearningGoalRef ref) =>
    'id ${ref.id}, leerplanId ${ref.leerplanId}, type ${ref.type}';

/// [node] as a line shows it: its number ([CurriculumNode.prefix]) before
/// its text, as the selector shows it.
String _nodeText(CurriculumNode node) {
  final text = node.text;
  final shown = text.isEmpty ? '(no title)' : text;
  return node.prefix == null ? shown : '${node.prefix} $shown';
}

/// What a goal is, after its text, when it is not a plain goal: a goal of
/// basic literacy, an extension goal, deprecated.
String _goalNotes(CurriculumNode node) {
  final notes = [
    if (node.type == CurriculumNodeType.goalBasic) 'basic literacy',
    if (node.type == CurriculumNodeType.goalExtension) 'extension goal',
    if (node.isDeprecated) 'deprecated',
  ];
  return notes.isEmpty ? '' : ' (${notes.join(', ')})';
}

/// Whether [goal] holds every one of [words], in its number, its text or
/// the headings above it.
bool goalMatches(SelectableGoal goal, List<String> words) => _holdsAll(
  [
    for (final node in [...goal.path, goal.node]) ...[
      ?node.prefix,
      ?node.number,
      node.text,
    ],
  ].join(' '),
  words,
);

/// What `read_curriculum` answers: [curriculum]'s title and id, the
/// `leerplanId` and `type` that each of its goals is stored with, and its
/// goals that can be picked (only those that hold every word of [query]
/// when it is not empty), under their headings, indented by depth, each
/// with its number, text and id; at most [maxGoalLines] goals.
String formatCurriculum(Curriculum curriculum, String query) {
  final words = goalQueryWords(query);
  final title = curriculum.title.trim().isEmpty
      ? '(no title)'
      : curriculum.title.trim();
  final all = curriculum.goals;
  final matching = [
    for (final goal in all)
      if (goalMatches(goal, words)) goal,
  ];
  final head = [
    'Curriculum "$title" | id ${curriculum.id}'
        '${curriculum.isDeprecated ? ' | deprecated' : ''}',
    'Each goal of it is stored with its own id, leerplanId '
        '${curriculum.id} and type ${curriculum.leerplanType}.',
  ];
  if (all.isEmpty) {
    return [...head, 'It has no goals that can be picked.'].join('\n');
  }
  if (matching.isEmpty) {
    return [
      ...head,
      'None of its ${all.length} goals holds "${query.trim()}" in its number, '
          'its text or its headings.',
    ].join('\n');
  }
  final listed = matching.take(maxGoalLines).toList();
  final lines = <String>[];
  var above = <CurriculumNode>[];
  for (final goal in listed) {
    var same = 0;
    while (same < above.length &&
        same < goal.path.length &&
        above[same].id == goal.path[same].id) {
      same++;
    }
    for (var depth = same; depth < goal.path.length; depth++) {
      lines.add('${'  ' * depth}${_nodeText(goal.path[depth])}');
    }
    lines.add(
      '${'  ' * goal.path.length}- ${_nodeText(goal.node)}'
      '${_goalNotes(goal.node)} | id ${goal.node.id}',
    );
    above = goal.path;
  }
  return [
    ...head,
    if (words.isEmpty)
      'Its ${all.length} ${all.length == 1 ? 'goal' : 'goals'}, under their '
          'headings:'
    else
      '${matching.length} of its ${all.length} goals hold '
          '"${query.trim()}", under their headings:',
    ...lines,
    if (matching.length > listed.length)
      'Note: only the first ${listed.length} of the ${matching.length} are '
          'shown: narrow them with query.',
  ].join('\n');
}

/// The goals a lesfiche or a planned lesson stores ([refs]), named by the
/// goal selector ([curricula], the answer of [GoalService.resolve]), or the
/// selector's [error] when it could not name them.
typedef NamedGoals = ({
  List<LearningGoalRef> refs,
  List<Curriculum> curricula,
  SmartschoolGoalError? error,
});

/// No goals, as a lesfiche or a lesson without any has: [formatNamedGoals]
/// gives `Goals: none`.
const NamedGoals noGoals = (
  refs: <LearningGoalRef>[],
  curricula: <Curriculum>[],
  error: null,
);

/// Names the goals [refs] with [client] (`GoalService.resolve`, at
/// [location]: where the selector is opened). Without goals it sends
/// nothing. A [SmartschoolGoalError] does not lose the read the goals
/// belong to: the result then holds it, and the goals are shown by their
/// ids ([formatNamedGoals]). Any other error is passed on.
Future<NamedGoals> nameGoals(
  SmartschoolClient client,
  List<LearningGoalRef> refs, {
  GoalLocation location = GoalLocation.lessonContent,
}) async {
  if (refs.isEmpty) {
    return (refs: refs, curricula: const <Curriculum>[], error: null);
  }
  try {
    final curricula = await GoalService(
      client,
    ).resolve(refs, location: location);
    return (refs: refs, curricula: curricula, error: null);
  } on SmartschoolGoalError catch (error) {
    log('goals: $error');
    return (refs: refs, curricula: const <Curriculum>[], error: error);
  }
}

/// [goals] as the lines of a detail: `Goals: none`, or `Goals:` with one
/// line per goal, in the order stored: the curriculum's title, the headings
/// above the goal and the goal with its number, then its stored fields
/// ([formatGoalRef]). A goal the selector does not name is shown by its
/// fields and said to be unknown: the modules store any IDs without
/// complaint, and the selector does not read goals of every source (not
/// those of LLinkid, for instance). When the selector could not name the
/// goals at all, a note says so.
List<String> formatNamedGoals(NamedGoals goals) {
  final (:refs, :curricula, :error) = goals;
  if (refs.isEmpty) return const ['Goals: none'];
  return [
    'Goals:',
    for (final ref in refs)
      if (error != null)
        '- ${formatGoalRef(ref)}'
      else if (GoalService.findGoal(curricula, ref) case final goal?)
        '- ${_namedGoal(goal)} | ${formatGoalRef(ref)}'
      else
        '- unknown to the goal selector (an id it does not have, or a goal '
            'of a source it does not read, such as LLinkid) | '
            '${formatGoalRef(ref)}',
    if (error != null)
      'Note: the goal selector could not name the goals'
          '${error.statusCode == null ? '' : ' (HTTP ${error.statusCode})'}, '
          'so they are shown by their ids. The technical details are in the '
          'server log.',
  ];
}

String _namedGoal(SelectableGoal goal) {
  final title = goal.curriculum.title.trim();
  return [
    '${title.isEmpty ? '(no title)' : title}:',
    [
      for (final node in goal.path) _nodeText(node),
      '${_nodeText(goal.node)}${_goalNotes(goal.node)}',
    ].join(' > '),
  ].join(' ');
}
