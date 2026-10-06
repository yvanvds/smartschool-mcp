import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_writes.dart';
import '../problems.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `edit_lesfiche`: changes the name, the icon, the public info, the
/// private info, the courses and/or whether it is visible in the module of
/// one lesfiche in the user's own library of the Lesfiches module, with the
/// library's edits (`LessonContentService.rename`, `changeIcon`,
/// `changePublicInfo`, `changePrivateInfo`, `changeCourses` and
/// `setVisible`, dartschool#129), one per field given, in that order, and
/// gives the lesfiche back as `read_lesfiche` shows it.
///
/// Marked destructive, as `create_lesfiche` is (its doc comment says why):
/// a write that Claude is told to show the user first and to make only
/// after the user's confirmation, and Claude Desktop and Codex ask approval
/// only for a tool marked destructive. Each edit sets a value, so calling it
/// again with the same values changes nothing more: it is idempotent.
///
/// The tool reads the lesfiche first, in the session action of the edits
/// (they take it as read, and a `404` of an edit then means that it is in
/// the trash), and the school's course list for the courses, before it
/// sends anything. It stops at the first edit that fails, and says which
/// were made and which were not sent, like `edit_planned_element`. The
/// edits answer with the lesfiche, but only `changeCourses` names its
/// courses, so the result reads it once more at the end
/// ([lesficheChangedResult]).
ServerTool editLesficheTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'edit_lesfiche',
    title: 'Change a Smartschool lesfiche',
    description:
        'Changes one lesfiche in the user\'s own library ("Mijn lesfiches") '
        'of the Smartschool Lesfiches module, by the id and kind '
        'list_lesfiches shows: its name, icon, public info (what pupils see '
        'once it is planned), private info, courses, and/or whether it is '
        'visible in the module. Give only what changes, at least one of '
        'them. The own library is private to the user: pupils only see what '
        'is planned from it. Before calling this tool, read the lesfiche '
        'with read_lesfiche, show the user its name and kind and what '
        'changes, and only call this tool after the user has explicitly '
        'confirmed it. Write the info as plain text, with a blank line '
        'between paragraphs; HTML in it is not interpreted, it shows as '
        'text. An info replaces the whole info: to add to it, pass the old '
        'text with the addition; an empty text empties it. courses replaces '
        'all its courses; an empty list removes them. visible false hides '
        'the lesfiche in the module, true shows it again; a hidden lesfiche '
        'is still listed and can still be planned. Its weblinks change with '
        'set_lesfiche_weblink and remove_lesfiche_weblink, its attachments '
        'with add_lesfiche_attachments, set_lesfiche_attachment_visibility '
        'and remove_lesfiche_attachment; labels are set in the Lesfiches '
        'module itself. Whether a lesson planned from the lesfiche earlier '
        'changes with it is not known: check such a lesson with '
        'read_planned_element, and change it with edit_planned_element. The '
        'changes are made one by one, in the order name, icon, public info, '
        'private info, courses, visible; when one fails, the result says '
        'which were made. A lesfiche in the trash cannot be changed. The '
        'result gives the lesfiche as changed. If the result says a change '
        'may or may not have been saved, do not call this tool again for '
        'it: check the lesfiche with read_lesfiche and tell the user. For '
        'requests like "geef mijn lesfiche Lussen ook het vak wiskunde".',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
        'name': Schema.string(
          description:
              'The new name, as the user confirmed it: at most '
              '${LessonContentService.maxNameLength} characters.',
          minLength: 1,
        ),
        'icon': Schema.string(
          description:
              'The new icon, a name from Smartschool\'s icon set as '
              'read_lesfiche shows it, like book. Leave it out unless the '
              'user asks for another icon.',
          minLength: 1,
        ),
        'public_info': Schema.string(
          description:
              'The new info pupils see with a lesson planned from the '
              'lesfiche, as plain text; it replaces the whole public info. '
              'An empty text empties it.',
        ),
        'private_info': Schema.string(
          description:
              'The new private info, as plain text; it replaces the whole '
              'private info. An empty text empties it.',
        ),
        'courses': lesficheCoursesSchema(
          description:
              'The courses the lesfiche gets, in place of all its courses; '
              'an empty list removes them.',
        ),
        'visible': Schema.bool(
          description:
              'false hides the lesfiche in the Lesfiches module, true shows '
              'it again. A hidden lesfiche is still listed and can still be '
              'planned.',
        ),
      },
      required: ['lesfiche'],
    ),
    annotations: ToolAnnotations(
      title: 'Change a Smartschool lesfiche',
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
  name('the name'),
  icon('the icon'),
  publicInfo('the public info'),
  privateInfo('the private info'),
  courses('the courses'),
  visible('the visibility in the module');

  const _Field(this.label);

  /// The field in a sentence.
  final String label;
}

/// The changes [arguments] ask for, in the order of [_Field]: a name, an
/// icon and the infos as the library sends them, the courses as the
/// argument names them ([lesficheCoursesArgument]), and whether it is
/// visible.
///
/// Throws a [ToolError] for a field it refuses, and when nothing changes,
/// before anything is sent.
Map<_Field, Object> _changes(Map<String, Object?> arguments) {
  final changes = <_Field, Object>{};
  if (arguments['name'] != null) {
    changes[_Field.name] = lesficheNameArgument(arguments['name']);
  }
  if (arguments['icon'] case final Object value) {
    final icon = value is String ? value.trim() : '';
    if (icon.isEmpty) {
      throw const ToolError(
        'icon is empty: pass the name of an icon from Smartschool\'s icon '
        'set, as read_lesfiche shows it, or leave icon out to keep it. '
        '$nothingSent',
      );
    }
    changes[_Field.icon] = icon;
  }
  if (arguments['public_info'] case final String text) {
    changes[_Field.publicInfo] = plainTextToHtml(text);
  }
  if (arguments['private_info'] case final String text) {
    changes[_Field.privateInfo] = plainTextToHtml(text);
  }
  if (lesficheCoursesArgument(arguments['courses']) case final courses?) {
    changes[_Field.courses] = courses;
  }
  if (arguments['visible'] case final Object value) {
    if (value is! bool) {
      throw const ToolError(
        'visible must be true (shown in the module) or false (hidden). '
        '$nothingSent',
      );
    }
    changes[_Field.visible] = value;
  }
  if (changes.isEmpty) {
    throw const ToolError(
      'Nothing to change: pass at least one of name, icon, public_info, '
      'private_info, courses and visible. $nothingSent',
    );
  }
  return changes;
}

Future<CallToolResult> _edit(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final changes = _changes(arguments);

  // The lesfiche before the first change, its courses as the school's course
  // list names them, and the fields changed so far: kept over a repeat of
  // the session's action, which reads the lesfiche again and sends only the
  // edits that were not made yet.
  LessonContentDetail? before;
  List<PlannerCourse>? courses;
  final saved = <_Field>[];
  _Field? sending;
  String title() => before == null
      ? 'the ${lesficheKindName(type)} $id'
      : lesficheTitle(before!);

  final watch = Stopwatch()..start();
  try {
    await session.run((client) async {
      final lesfiches = LessonContentService(client);
      var lesfiche = (await readLesficheDetail(
        client,
        type,
        id,
        withCourseNames: false,
      )).detail;
      before ??= lesfiche;
      if (changes[_Field.courses] case final List<String> wanted
          when courses == null) {
        courses = wanted.isEmpty
            ? const []
            : lesficheCourses(await lesfiches.getCourses(), wanted);
      }
      for (final MapEntry(key: field, :value) in changes.entries) {
        if (saved.contains(field)) continue;
        sending = field;
        lesfiche = await switch (field) {
          _Field.name => lesfiches.rename(lesfiche, value as String),
          _Field.icon => lesfiches.changeIcon(lesfiche, value as String),
          _Field.publicInfo => lesfiches.changePublicInfo(
            lesfiche,
            value as String,
          ),
          _Field.privateInfo => lesfiches.changePrivateInfo(
            lesfiche,
            value as String,
          ),
          _Field.courses => lesfiches.changeCourses(lesfiche, [
            for (final course in courses!) course.id,
          ]),
          _Field.visible => lesfiches.setVisible(lesfiche, value as bool),
        };
        saved.add(field);
        sending = null;
      }
    });
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    // Only the edits throw it, each with its field in [sending].
    final field =
        sending ?? changes.keys.firstWhere((field) => !saved.contains(field));
    final also = [
      if (saved.isNotEmpty) '${_sentence(_wasChanged(saved))}.',
      ?_notSent(changes, saved, field),
    ];
    return lesficheWriteNotConfirmed(
      tool: 'edit_lesfiche',
      what: 'The change of ${field.label} of ${title()}',
      done: 'saved',
      also: also.isEmpty ? null : also.join(' '),
      check:
          'read the lesfiche with ${readLesficheCall(type, id)} and compare '
          '${field.label}',
      error: error,
    );
  } on ToolError catch (error) {
    if (saved.isEmpty) rethrow;
    throw ToolError('${error.message} ${_stopped(changes, saved, sending)}');
  } on SmartschoolProblem catch (problem) {
    if (saved.isEmpty) rethrow;
    throw ToolError('${problem.message} ${_stopped(changes, saved, sending)}');
  } catch (error) {
    final toolError = lesficheWriteToolError(
      error,
      what: sending == null
          ? title()
          : 'the change of ${sending!.label} of ${title()}',
      nothingDone: _stopped(changes, saved, sending),
    );
    if (toolError == null) rethrow;
    throw toolError;
  }
  log(
    'edit_lesfiche: ${saved.length} edits in ${watch.elapsedMilliseconds} ms',
  );
  return lesficheChangedResult(
    session,
    type,
    id,
    _changedText(before!, changes, courses),
  );
}

/// Whether [lesfiche], as read before the edits, already had [value] (as
/// [_changes] gives it) for [field]; for the courses, [courses], the
/// courses found for the argument.
bool _had(
  LessonContentDetail lesfiche,
  _Field field,
  Object value,
  List<PlannerCourse>? courses,
) => switch (field) {
  _Field.name => lesfiche.name == value,
  _Field.icon => lesfiche.icon == value,
  _Field.publicInfo => lesfiche.publicInfo == value,
  _Field.privateInfo => lesfiche.privateInfo == value,
  _Field.courses => _sameIds(
    [for (final course in lesfiche.courses) course.id],
    [for (final course in courses ?? const <PlannerCourse>[]) course.id],
  ),
  _Field.visible => lesfiche.isVisible == value,
};

bool _sameIds(List<String> a, List<String> b) {
  final left = {for (final id in a) id.toLowerCase()};
  final right = {for (final id in b) id.toLowerCase()};
  return left.length == right.length && left.containsAll(right);
}

/// The lines of the result of the edits of [changes] that went through:
/// what changed of [before], the lesfiche as read before them, and what
/// already had the value given.
List<String> _changedText(
  LessonContentDetail before,
  Map<_Field, Object> changes,
  List<PlannerCourse>? courses,
) {
  final changed = <String>[];
  final already = <String>[];
  for (final MapEntry(key: field, :value) in changes.entries) {
    (_had(before, field, value, courses) ? already : changed).add(field.label);
  }
  return [
    if (changed.isNotEmpty)
      'Changed ${_list(changed)} of ${lesficheTitle(before)}.'
    else
      'Nothing to change: ${lesficheTitle(before)} already had what was '
          'given.',
    if (changed.isNotEmpty && already.isNotEmpty)
      '${_sentence(_list(already))} already had the value given.',
  ];
}

/// What an error of the edits of [changes] means for the call, after the
/// edits of [saved] went through and [stopped] failed (null when a read
/// failed): [lesficheUnchanged] when none went through, else what was
/// changed and what was not sent.
String _stopped(
  Map<_Field, Object> changes,
  List<_Field> saved,
  _Field? stopped,
) {
  if (saved.isEmpty) return lesficheUnchanged;
  return [
    '${_sentence(_wasChanged(saved))} before that.',
    ?_notSent(changes, saved, stopped),
  ].join(' ');
}

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

/// `the name was changed`, `the name and the icon were changed`.
String _wasChanged(List<_Field> fields) =>
    '${_list([for (final field in fields) field.label])} '
    '${fields.length == 1 ? 'was' : 'were'} changed';

/// `a`, `a and b`, `a, b and c`.
String _list(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

String _sentence(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
