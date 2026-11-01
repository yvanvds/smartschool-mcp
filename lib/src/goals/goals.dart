import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';

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

/// What the goal writes say about their list (#187): it replaces the goals,
/// so adding one means passing the current goals with it.
const goalsReplaceNote =
    'The list replaces all the goals: to add a goal, pass the goals it has '
    'now (as read_lesfiche or read_planned_element shows them) plus the new '
    'one; to remove one, pass the others; an empty list removes them all.';

/// The input schema of a `goals` argument ([goalsArgument]): goals as
/// `read_curriculum` shows them, each by its id with the leerplanId and the
/// type of its curriculum.
Schema goalsSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.object(
    properties: {
      'id': Schema.string(
        description:
            'The id of the goal, as read_curriculum shows it at the end of '
            'its line, like f0000000-0000-4000-8000-000000000011.',
        minLength: 1,
      ),
      'leerplanId': Schema.string(
        description:
            'The leerplanId of its curriculum, as read_curriculum shows it '
            'in its header (the curriculum\'s id).',
        minLength: 1,
      ),
      'type': Schema.string(
        description:
            'The type of its curriculum, as read_curriculum shows it in its '
            'header, like eindtermen-derde-graad-doorstroom or miniDB.',
        minLength: 1,
      ),
    },
    required: ['id', 'leerplanId', 'type'],
  ),
);

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

/// [value], the `goals` argument [name] of a goal write: goals, each
/// `{id, leerplanId, type}` as `read_curriculum` (or the read of the item)
/// shows them, without the white space around a field and each once, in
/// the order given; null when it is absent, empty to clear the goals.
///
/// Throws a [ToolError] that names the goal for one that is not an object
/// with the three fields, an id that is not a UUID (a goal's id always is;
/// the library refuses another), and two goals with the same id in another
/// curriculum or of another type, before anything is sent. Whether the
/// goals exist is checked by [checkGoals].
List<LearningGoalRef>? goalsArgument(Object? value, {String name = 'goals'}) {
  if (value == null) return null;
  final items = value is List ? value : [value];
  final goals = <LearningGoalRef>[];
  for (final (index, item) in items.indexed) {
    final where = 'Goal ${index + 1} of $name';
    String field(String key) => switch (item is Map ? item[key] : null) {
      final String text when text.trim().isNotEmpty => text.trim(),
      _ => throw ToolError(
        '$where has no $key: pass each goal as {id, leerplanId, type}, as '
        'read_curriculum shows them (the id at the end of the goal\'s line, '
        'the leerplanId and type in its header). $nothingSent',
      ),
    };
    if (item is! Map) {
      throw ToolError(
        '$where is not a goal: pass each goal as {id, leerplanId, type}, as '
        'read_curriculum shows them. $nothingSent',
      );
    }
    final goal = LearningGoalRef(
      id: field('id'),
      leerplanId: field('leerplanId'),
      type: field('type'),
    );
    if (!_uuid.hasMatch(goal.id)) {
      throw ToolError(
        '$where has the id "${goal.id}", which is not the id of a goal: take '
        'it from read_curriculum, where it ends the goal\'s line, like '
        'f0000000-0000-4000-8000-000000000011. $nothingSent',
      );
    }
    final earlier = goals
        .where((other) => other.id.toLowerCase() == goal.id.toLowerCase())
        .firstOrNull;
    if (earlier == null) {
      goals.add(goal);
    } else if (!sameGoals([earlier], [goal])) {
      throw ToolError(
        '$where has the id of another goal of the list, with another '
        'leerplanId or type: ${formatGoalRef(goal)} and '
        '${formatGoalRef(earlier)}. Take them from read_curriculum. '
        '$nothingSent',
      );
    }
  }
  return goals;
}

/// Whether [a] and [b] hold the same goals, in any order, the ids and the
/// leerplanIds in any case (as the library compares them).
bool sameGoals(Iterable<LearningGoalRef> a, Iterable<LearningGoalRef> b) {
  final left = {for (final goal in a) _goalKey(goal)};
  final right = {for (final goal in b) _goalKey(goal)};
  return left.length == right.length && left.containsAll(right);
}

(String, String, String) _goalKey(LearningGoalRef goal) =>
    (goal.id.toLowerCase(), goal.leerplanId.toLowerCase(), goal.type);

/// Checks with the goal selector (`GoalService.resolve` at [location], one
/// request) that [goals] are goals it knows, before a goal write sends them:
/// the lesfiche modules and the planner store any id without complaint, so
/// a made-up id would be stored. Goals the item already stores ([stored])
/// are kept without the check: they may be of a source the selector does
/// not read (LLinkid, for instance), and passing them is how a goal is
/// added. Returns the curricula of the answer, which name the goals checked
/// ([NamedGoals]).
///
/// Throws a [ToolError] that lists the goals the selector does not have in
/// that curriculum, or as a goal that can be picked (a heading), and those
/// given with another type than their curriculum's, with what to do; or
/// one for a selector that could not answer ([goalToolError]). Both say that
/// nothing was sent.
Future<List<Curriculum>> checkGoals(
  SmartschoolClient client,
  List<LearningGoalRef> goals, {
  required GoalLocation location,
  List<LearningGoalRef> stored = const [],
}) async {
  final storedKeys = {for (final goal in stored) _goalKey(goal)};
  final asked = [
    for (final goal in goals)
      if (!storedKeys.contains(_goalKey(goal))) goal,
  ];
  if (asked.isEmpty) return const [];
  final List<Curriculum> curricula;
  try {
    curricula = await GoalService(client).resolve(asked, location: location);
  } on SmartschoolGoalError catch (error) {
    final toolError = goalToolError(error)!;
    throw ToolError(
      'The goals could not be checked: ${toolError.message} $nothingSent',
    );
  } on ArgumentError catch (error) {
    if (error is RangeError) rethrow;
    log('goals: $error');
    throw ToolError(
      'The goals could not be checked: the goal selector refused '
      '${error.name ?? 'them'}: ${error.message}. $nothingSent',
    );
  }
  final problems = <String>[];
  for (final goal in asked) {
    final found = GoalService.findGoal(curricula, goal);
    if (found == null) {
      final known = curricula.any(
        (curriculum) =>
            curriculum.id.toLowerCase() == goal.leerplanId.toLowerCase(),
      );
      problems.add(
        '- ${formatGoalRef(goal)}: ${known ? 'its curriculum has no goal '
                  'with that id that can be picked' : 'the goal selector has '
                  'no such goal (no curriculum with that leerplanId has it)'}',
      );
    } else if (found.ref.type != goal.type) {
      problems.add(
        '- ${formatGoalRef(goal)}: its curriculum has the type '
        '${found.ref.type}, not ${goal.type}',
      );
    }
  }
  if (problems.isEmpty) return curricula;
  log('goals: ${problems.length} of ${asked.length} goals refused');
  throw ToolError(
    [
      '${problems.length == 1 ? 'A goal is' : '${problems.length} goals are'} '
          'not known to the goal selector as given, so ${problems.length == 1 ? 'it' : 'they'} would be '
          'stored as a goal without a name. $nothingSent',
      ...problems,
      'Find the goal with list_curricula and read_curriculum, and pass its '
          'id with the leerplanId and type of the curriculum\'s header.',
    ].join('\n'),
  );
}
