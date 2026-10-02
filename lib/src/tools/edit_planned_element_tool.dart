import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../problems.dart';
import '../session.dart';
import 'server_tool.dart';

/// `edit_planned_element`: changes the name, the public info and/or the
/// private info of a lesson or an assignment in the user's own planner.
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
        'Smartschool planner, by the id list_planner shows. Give only what '
        'changes, at least one of name, public_info and private_info. Only '
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
        'empties it. The result gives the element as saved. If the result '
        'says a change may or may not have been saved, do not call this tool '
        'again for it: check the element with read_planned_element and tell '
        'the user.',
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
  privateInfo('private_info', 'the private info');

  const _Field(this.argument, this.label);

  /// The tool's argument.
  final String argument;

  /// The field in a sentence.
  final String label;

  /// The value of this field of [element], as the library compares it.
  String of(PlannedElementDetail element) => switch (this) {
    name => (element.name ?? '').trim(),
    publicInfo => element.publicInfo,
    privateInfo => element.privateInfo,
  };

  /// Sets this field of [element] to [value] with the library's edit.
  Future<PlannedElementDetail> set(
    PlannerService planner,
    PlannedElementDetail element,
    String value,
  ) => switch (this) {
    name => planner.renameElement(element, value),
    publicInfo => planner.changePublicInfo(element, value),
    privateInfo => planner.changePrivateInfo(element, value),
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
  final changes = <_Field, String>{
    for (final field in _Field.values)
      if (arguments[field.argument] case final String text)
        field: field == _Field.name ? text.trim() : plainTextToHtml(text),
  };
  if (changes.isEmpty) {
    throw const ToolError(
      'Nothing to change: pass at least one of name, public_info and '
      'private_info. Nothing was sent.',
    );
  }
  if (changes[_Field.name]?.isEmpty ?? false) {
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
  try {
    final after = await withPlanner(session, (planner) async {
      var element = await id.read(planner);
      before ??= element;
      for (final MapEntry(key: field, :value) in changes.entries) {
        sending = field;
        element = await field.set(planner, element, value);
        if (!saved.contains(field)) saved.add(field);
        sending = null;
      }
      return element;
    });
    return CallToolResult(
      content: [TextContent(text: _savedText(before!, after, changes, saved))],
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
  Map<_Field, String> changes,
  List<_Field> saved,
) {
  final changed = [
    for (final field in saved)
      if (field.of(before) != changes[field]) field.label,
  ];
  final already = [
    for (final field in saved)
      if (field.of(before) == changes[field]) field.label,
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
    formatElementDetail(after),
  ].join('\n');
}

/// The error of an edit that stopped after [saved] went through, with
/// [message]: what was saved, and what was not: [stopped], the change that
/// failed (null when the read before it did), and the changes after it.
String _partly(
  PlannedElementDetail before,
  Map<_Field, String> changes,
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
  Map<_Field, String> changes,
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
