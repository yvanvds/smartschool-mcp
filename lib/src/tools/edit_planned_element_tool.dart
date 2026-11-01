import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../goals/goals.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../problems.dart';
import '../session.dart';
import 'server_tool.dart';

/// `edit_planned_element`: changes the name, the public info and/or the
/// private info of a lesson or an assignment in the user's own planner, and
/// the learning goals of a lesson (`PlannerService.changeGoals`,
/// dartschool#226; #187): checked with the goal selector first
/// ([checkGoals]), and named in the result when they change.
///
/// Pupils see a new name and public info at once, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call).
/// Each change sets a value, so calling it again with the same values
/// changes nothing more: it is idempotent.
ServerTool editPlannedElementTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'edit_planned_element',
    title: 'Change a lesson or assignment in the Smartschool planner',
    description:
        'Changes the name, the public info (what pupils see) and/or the '
        'private info of a lesson or an assignment in the user\'s own '
        'Smartschool planner, and the learning goals of a lesson, by the id '
        'list_planner shows. Give only what changes, at least one of name, '
        'public_info, private_info and goals. Only '
        'the user\'s own planner can be changed: list_planner also shows '
        'colleagues\' lessons and assignments, and this tool refuses those. '
        'Pupils see a new name and public info at once. Before calling this '
        'tool, read the element with read_planned_element, show the user its '
        'date and time, class and course, and the new name or info, and only '
        'call it after the user has explicitly confirmed it. For several '
        'elements, one confirmation of the full list is enough; then call '
        'this tool once per element. Private info is hidden from pupils, but '
        'colleagues who can see the element read it too. Write the info as '
        'plain text, with a blank line between paragraphs; HTML in it is not '
        'interpreted, it shows as text. An info replaces the whole info: to '
        'add to it, pass the old text with the addition; an empty text '
        'empties it. goals are learning goals as read_curriculum shows them '
        '(find them with list_curricula and read_curriculum); pupils see '
        'them. $goalsReplaceNote A goal the goal selector does not know is '
        'refused, and nothing is sent. Of an assignment (a test or task, '
        'such as one planned with plan_assignment) only the name and the '
        'info change here, not its goals, date, type or classes. The changes '
        'are made in the order name, public info, private info, goals. The '
        'result gives the element as saved. '
        'If the result says a change may or may not have been saved, do not '
        'call this tool again for it: check the element with '
        'read_planned_element and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'id': Schema.string(
          description:
              'The id of a lesson or an assignment of your own planner, as '
              'list_planner shows it, like planned-lessons/4069/….',
          minLength: 1,
        ),
        'name': Schema.string(
          description: 'The new name, as the user confirmed it.',
          minLength: 1,
        ),
        'public_info': Schema.string(
          description:
              'The new info pupils see, as plain text; it replaces the whole '
              'public info. An empty text empties it.',
        ),
        'private_info': Schema.string(
          description:
              'The new private info, as plain text; it replaces the whole '
              'private info. An empty text empties it.',
        ),
        'goals': goalsSchema(
          description:
              'Only for a lesson: the learning goals it gets, in place of all '
              'its goals, each {id, leerplanId, type} as read_curriculum '
              'shows it; an empty list removes them. To add a goal, pass the '
              'goals read_planned_element shows plus the new one.',
        ),
      },
      required: ['id'],
    ),
    annotations: ToolAnnotations(
      title: 'Change a lesson or assignment in the Smartschool planner',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _edit(session, request.arguments ?? const {}),
);

/// A field the tool changes, in the order it changes them.
enum _Field {
  name('name', 'the name'),
  publicInfo('public_info', 'the public info'),
  privateInfo('private_info', 'the private info'),
  goals('goals', 'the goals');

  const _Field(this.argument, this.label);

  /// The tool's argument.
  final String argument;

  /// The field in a sentence.
  final String label;

  /// Whether this field of [element] has [value] already, as the library
  /// compares it.
  bool has(PlannedElementDetail element, Object value) => switch (this) {
    name => (element.name ?? '').trim() == value,
    publicInfo => element.publicInfo == value,
    privateInfo => element.privateInfo == value,
    goals => sameGoals(
      element.goals ?? const [],
      value as List<LearningGoalRef>,
    ),
  };

  /// Sets this field of [element] to [value] with the library's edit.
  Future<PlannedElementDetail> set(
    PlannerService planner,
    PlannedElementDetail element,
    Object value,
  ) => switch (this) {
    name => planner.renameElement(element, value as String),
    publicInfo => planner.changePublicInfo(element, value as String),
    privateInfo => planner.changePrivateInfo(element, value as String),
    goals => planner.changeGoals(element, value as List<LearningGoalRef>),
  };
}

Future<CallToolResult> _edit(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = PlannedElementRef.parse(arguments['id']);
  if (id.type != PlannedElementType.lesson &&
      id.type != PlannedElementType.assignment) {
    final what = id.type == PlannedElementType.placeholder
        ? 'an empty lesson hour, which has no name or info: fill it with '
              'plan_lesson'
        : 'a ${id.typeName}';
    throw ToolError(
      'id must be a lesson or an assignment of your own planner; $id is '
      '$what. Nothing was sent.',
    );
  }
  final changes = <_Field, Object>{
    for (final field in [_Field.name, _Field.publicInfo, _Field.privateInfo])
      if (arguments[field.argument] case final String text)
        field: field == _Field.name ? text.trim() : plainTextToHtml(text),
    _Field.goals: ?goalsArgument(arguments['goals']),
  };
  if (changes.isEmpty) {
    throw const ToolError(
      'Nothing to change: pass at least one of name, public_info, '
      'private_info and goals. Nothing was sent.',
    );
  }
  if (changes.containsKey(_Field.goals) &&
      id.type != PlannedElementType.lesson) {
    throw ToolError(
      'goals are for a lesson only; $id is an assignment, whose goals this '
      'server does not change. Nothing was sent.',
    );
  }
  if (changes[_Field.name] == '') {
    throw const ToolError(
      'name is empty: pass the new name, or leave name out to keep it. '
      'Nothing was sent.',
    );
  }

  // The element before the first change, and the fields changed so far:
  // kept over a repeat of the session's action, which reads the element
  // again (a field changed the first time then already has its value).
  PlannedElementDetail? before;
  final saved = <_Field>[];
  _Field? sending;
  var goalsChecked = false;
  try {
    final (after, goals) = await withPlannerClient(session, (client) async {
      final planner = PlannerService(client);
      var element = await id.read(planner);
      before ??= element;
      if (changes[_Field.goals] case final List<LearningGoalRef> goals
          when !goalsChecked) {
        await checkGoals(
          client,
          goals,
          location: GoalLocation.plannerLessonContent,
          stored: before!.goals ?? const [],
        );
        goalsChecked = true;
      }
      for (final MapEntry(key: field, :value) in changes.entries) {
        sending = field;
        element = await field.set(planner, element, value);
        if (!saved.contains(field)) saved.add(field);
        sending = null;
      }
      // The goals named as read_planned_element names them, when they
      // changed; the writes of the other fields do not show them.
      final goals = changes.containsKey(_Field.goals)
          ? await nameGoals(
              client,
              element.goals ?? const [],
              location: GoalLocation.plannerLessonContent,
            )
          : null;
      return (element, goals);
    });
    return CallToolResult(
      content: [
        TextContent(text: _savedText(before!, after, changes, saved, goals)),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    // Only the edits throw it, each with its field in [sending].
    final field =
        sending ?? changes.keys.firstWhere((field) => !saved.contains(field));
    final also = [
      if (saved.isNotEmpty) '${_sentence(_wasSaved(saved))}.',
      ?_notSent(changes, saved, field),
    ];
    return plannerWriteNotConfirmed(
      tool: 'edit_planned_element',
      what:
          'The change of ${field.label} of the '
          '${formatElementSummary(before!)}',
      also: also.isEmpty ? null : also.join(' '),
      check:
          'read the element with read_planned_element (id $id) and compare '
          '${field.label}',
      error: error,
    );
  } on ToolError catch (error) {
    if (saved.isEmpty) throw ToolError('${error.message} $nothingChanged');
    throw ToolError(_partly(before!, changes, saved, sending, error.message));
  } on SmartschoolProblem catch (problem) {
    if (saved.isEmpty) rethrow;
    throw ToolError(_partly(before!, changes, saved, sending, problem.message));
  }
}

/// The result of an edit that went through: what changed, what already had
/// its value, and the element as saved.
String _savedText(
  PlannedElementDetail before,
  PlannedElementDetail after,
  Map<_Field, Object> changes,
  List<_Field> saved,
  NamedGoals? goals,
) {
  final changed = [
    for (final field in saved)
      if (!field.has(before, changes[field]!)) field.label,
  ];
  final already = [
    for (final field in saved)
      if (field.has(before, changes[field]!)) field.label,
  ];
  return [
    if (changed.isNotEmpty)
      'Changed ${_list(changed)} of the ${formatElementSummary(before)}.'
    else
      'Nothing to change: the ${formatElementSummary(before)} already has '
          'what was given.',
    if (changed.isNotEmpty && already.isNotEmpty)
      '${_sentence(_list(already))} already had the value given.',
    if (changed.isNotEmpty) plannerListLagNote,
    '',
    formatElementDetail(after, goals: goals),
  ].join('\n');
}

/// The error of an edit that stopped after [saved] went through, with
/// [message]: what was saved, and what was not: [stopped], the change that
/// failed (null when the read before it did), and the changes after it.
String _partly(
  PlannedElementDetail before,
  Map<_Field, Object> changes,
  List<_Field> saved,
  _Field? stopped,
  String message,
) => [
  'Of the ${formatElementSummary(before)}, ${_wasSaved(saved)}.',
  if (stopped == null)
    'Then the planner could not be read again: $message'
  else
    '${_sentence(stopped.label)} was not changed: $message',
  ?_notSent(changes, saved, stopped),
].join(' ');

/// The changes of [changes] that were not sent: not [saved], and not
/// [stopped], the change that failed. Like `The private info was not
/// sent.`, or null when there are none.
String? _notSent(
  Map<_Field, Object> changes,
  List<_Field> saved,
  _Field? stopped,
) {
  final fields = [
    for (final field in changes.keys)
      if (field != stopped && !saved.contains(field)) field.label,
  ];
  if (fields.isEmpty) return null;
  return '${_sentence(_list(fields))} ${fields.length == 1 ? 'was' : 'were'} '
      'not sent.';
}

/// `the name was saved`, `the name and the public info were saved`.
String _wasSaved(List<_Field> fields) =>
    '${_list([for (final field in fields) field.label])} '
    '${fields.length == 1 ? 'was' : 'were'} saved';

/// `a`, `a and b`, `a, b and c`.
String _list(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

String _sentence(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
