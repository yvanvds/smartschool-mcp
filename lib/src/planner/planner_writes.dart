import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/markdown_to_html.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'planner_access.dart';
import 'planner_format.dart';

// Changing the user's own planner, shared by the planner tools that write
// (`plan_lesson`, `plan_lesfiche`, `edit_planned_element`, `clear_lesson`,
// `plan_assignment`, `trash_assignment`): the info texts Claude writes, as
// HTML; the empty lesson hour a fill takes; the lesson hour, the classes and
// the type of a new assignment; the fill of a lesson hour itself; and how a
// write the planner refused or did not confirm is reported.
//
// The library does the checks before each write (the element is the user's
// own and its capabilities allow the change, a lesson hour is still empty in
// the period it was read with, an assignment type is one of the school's),
// sends the fill of a lesson hour, the clear of a lesson, and the create and
// the trash of an assignment once, never again after logging in again, and
// throws a [SmartschoolPlannerSaveUnconfirmedError] when the planner's answer
// does not confirm a write that went out. That is why repeating a write's
// action, as [SmartschoolSession.run] does when Smartschool refused the
// session, cannot make a change twice: a refused session means the write was
// not carried out, the repeat reads the element again (a lesson hour that was
// filled meanwhile is gone), and an unconfirmed write is not a refused
// session, so it is not repeated.

/// What a write tool says after a change: the planner's list lags behind,
/// its detail does not (dartschool#84).
const plannerListLagNote =
    'For a few seconds after a change list_planner can still show the old '
    'state; read_planned_element shows the new state at once.';

/// [text], plain text that Claude writes for an info of the planner (what
/// pupils see, or the private info), as the simple HTML the planner's own
/// editor makes: one `<p>` per paragraph (a blank line between two), and
/// `<br />` for a single line break.
///
/// Every character is escaped ([escapeHtml]: `&`, `<`, `>` and quotes), so
/// HTML in [text] shows as text and never becomes markup. White space around
/// a paragraph or a line is left out. Text that is empty or white space only
/// is `""`: no info.
String plainTextToHtml(String text) {
  final paragraphs = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'\n[ \t]*\n'));
  return [
    for (final paragraph in paragraphs)
      if (paragraph.trim() case final lines when lines.isNotEmpty)
        '<p>${lines.split('\n').map(_line).join('<br />')}</p>',
  ].join();
}

String _line(String line) => escapeHtml(line.trim());

/// [value], the argument [name] of a tool, as the id of an empty lesson
/// hour as `list_planner` prints it: `planned-placeholders/4069/<id>`.
///
/// Throws a [ToolError] that says what to use instead for anything else (a
/// lesson, an assignment, an id that is not an element id), so that it
/// never goes into a request.
PlannedElementRef emptyHourArgument(Object? value, {String name = 'hour'}) {
  final hour = PlannedElementRef.parse(value, name: name);
  if (hour.type == PlannedElementType.placeholder) return hour;
  final what = switch (hour.type) {
    PlannedElementType.lesson =>
      'a lesson, not an empty lesson hour: change a lesson with '
          'edit_planned_element, or empty its hour first with clear_lesson',
    PlannedElementType.assignment => 'an assignment, not an empty lesson hour',
    _ => 'a ${hour.typeName}, not an empty lesson hour',
  };
  throw ToolError(
    '$name must be an empty lesson hour of your own planner, as list_planner '
    '(planner me) shows it, with an id like planned-placeholders/4069/…; '
    '$hour is $what. Nothing was sent.',
  );
}

/// [value], the argument [name] of a tool, as the id of a lesson hour as
/// `list_planner` prints it: an empty lesson hour
/// (`planned-placeholders/4069/<id>`) or a lesson
/// (`planned-lessons/4069/<id>`), which an assignment is planned in.
///
/// Throws a [ToolError] for anything else (an assignment, another kind of
/// element, an id that is not an element id), so that it never goes into a
/// request.
PlannedElementRef lessonHourArgument(Object? value, {String name = 'hour'}) {
  final hour = PlannedElementRef.parse(value, name: name);
  if (hour.type == PlannedElementType.placeholder ||
      hour.type == PlannedElementType.lesson) {
    return hour;
  }
  final what = hour.type == PlannedElementType.assignment
      ? 'an assignment'
      : 'a ${hour.typeName}';
  throw ToolError(
    '$name must be a lesson hour of your own planner, as list_planner '
    '(planner me) shows it: an empty lesson hour '
    '(planned-placeholders/4069/…) or a lesson (planned-lessons/4069/…); '
    '$hour is $what. Nothing was sent.',
  );
}

/// [value], the optional argument [name] of a tool: some of the classes of
/// a lesson hour, each by its name as `list_planner` shows it (`6A1`) or by
/// its planner id (`group/4069_2001`); null when it is absent. Without the
/// white space around an item, and without duplicates (ignoring case), in
/// the order given.
///
/// Throws a [ToolError] for an empty list, or an item that is not a text
/// with something in it, so that it never goes into a request.
/// [lessonHourClasses] matches the items with the hour's classes.
List<String>? lessonHourClassesArgument(
  Object? value, {
  String name = 'classes',
}) {
  if (value == null) return null;
  final items = value is List ? value : [value];
  final classes = <String>[];
  for (final item in items) {
    final text = item is String ? item.trim() : '';
    if (text.isEmpty) {
      throw ToolError(
        'each item of $name must be a class of the lesson hour, by its name '
        'as list_planner shows it (like 6A1) or its planner id (like '
        'group/4069_2001); ${item is String ? '"$item"' : '$item'} is not. '
        'Nothing was sent.',
      );
    }
    if (!classes.any((known) => known.toLowerCase() == text.toLowerCase())) {
      classes.add(text);
    }
  }
  if (classes.isEmpty) {
    throw ToolError(
      '$name is empty: name some of the classes of the lesson hour, or leave '
      '$name out for all of them. Nothing was sent.',
    );
  }
  return classes;
}

/// The classes of [hour], a lesson hour that an assignment is planned in:
/// all of them when [wanted] is null, else those that [wanted] names
/// ([lessonHourClassesArgument]), in that order. A class is named by its
/// name (ignoring case) or its planner id, `group/4069_2001` or `4069_2001`.
///
/// Throws a [ToolError] when [hour] has no classes, or when [wanted], the
/// argument [name], names a class that is not one of [hour]'s: an
/// assignment is only planned for the classes of its hour.
List<PlannerGroup> lessonHourClasses(
  PlannedElement hour,
  List<String>? wanted, {
  String name = 'classes',
}) {
  final classes = hour.participantGroups;
  if (classes.isEmpty) {
    throw ToolError(
      'The ${formatElementSummary(hour)} has no classes, so it cannot get an '
      'assignment: plan it in a lesson hour of the classes.',
    );
  }
  if (wanted == null) return classes;
  final chosen = <PlannerGroup>[];
  final others = <String>[];
  for (final item in wanted) {
    final text = item.toLowerCase();
    final match = classes
        .where(
          (group) =>
              group.name.trim().toLowerCase() == text ||
              group.id.toLowerCase() == text ||
              'group/${group.id}'.toLowerCase() == text,
        )
        .firstOrNull;
    if (match == null) {
      others.add('"$item"');
    } else if (!chosen.contains(match)) {
      chosen.add(match);
    }
  }
  if (others.isNotEmpty) {
    // The planner id as formatPlannerId writes it, without
    // PlannerCalendar's check of the id.
    final named = [
      for (final group in classes) '${group.name} (group/${group.id})',
    ];
    throw ToolError(
      '$name holds ${_and(others)}, which ${others.length == 1 ? 'is not a '
                'class' : 'are not classes'} of the '
      '${formatElementSummary(hour)}. Its classes are ${_and(named)}: name '
      'some of those, or leave $name out for all of them.',
    );
  }
  return chosen;
}

/// The assignment type of [types], the school's, that [value], the argument
/// [name] of a tool, names: by its abbreviation (`KO`), its name (`Kleine
/// Overhoring`) or both as the tools write them (`KO Kleine Overhoring`),
/// ignoring case and extra white space. An abbreviation is matched first,
/// then a name, then both.
///
/// Throws a [ToolError] that lists the school's types when [value] names
/// none of them, or more than one.
PlannerAssignmentType assignmentTypeArgument(
  Object? value,
  List<PlannerAssignmentType> types, {
  String name = 'type',
}) {
  String normal(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final wanted = value is String ? normal(value) : '';
  final schoolTypes = schoolAssignmentTypes(types);
  if (wanted.isNotEmpty) {
    for (final label in <String Function(PlannerAssignmentType type)>[
      (type) => type.abbreviation,
      (type) => type.name,
      formatAssignmentType,
    ]) {
      final matches = [
        for (final type in types)
          if (normal(label(type)) == wanted) type,
      ];
      if (matches.length == 1) return matches.single;
      if (matches.length > 1) {
        throw ToolError(
          '$name "$value" names ${matches.length} assignment types '
          '(${matches.map(formatAssignmentType).join(', ')}): pass its '
          'abbreviation and name together, as list_class_assignments lists '
          'it. $schoolTypes',
        );
      }
    }
  }
  throw ToolError(
    '$name ${value is String ? '"$value"' : '$value'} is not one of the '
    'school\'s assignment types: pass one by its abbreviation or its name. '
    '$schoolTypes',
  );
}

/// [types], the school's assignment types, in a sentence for an error about
/// a type: `The school's assignment types are GO Grote Overhoring, KO Kleine
/// Overhoring.`, or that the planner lists none.
String schoolAssignmentTypes(List<PlannerAssignmentType> types) => types.isEmpty
    ? 'The planner lists no assignment types for the school.'
    : 'The school\'s assignment types are '
          '${types.map(formatAssignmentType).join(', ')}.';

/// `a`, `a and b`, `a, b and c`.
String _and(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

/// Runs the planner write [write] with [withPlanner], for a tool that
/// changes the planner.
///
/// A [ToolError] (the planner refused the change before it was sent, the
/// element is gone, the read before the write failed) says that nothing
/// was changed. A [SmartschoolPlannerSaveUnconfirmedError] is thrown as it
/// is: the change may or may not have been made
/// ([plannerWriteNotConfirmed]).
Future<T> withPlannerWrite<T>(
  SmartschoolSession session,
  Future<T> Function(PlannerService planner) write,
) async {
  try {
    return await withPlanner(session, write);
  } on ToolError catch (error) {
    throw ToolError('${error.message} $nothingChanged');
  }
}

/// What a write tool adds to an error that came before anything changed.
const nothingChanged = 'Nothing was changed in the planner.';

/// The result of a planner write that went out without the planner
/// confirming it ([error]): [what] (like `The lesson "Lussen" in the empty
/// lesson hour on …`) may or may not have been [done]. Claude must not call
/// [tool] again for it, but first [check] (like `read the hour with
/// read_planned_element`) and tell the user. [also] comes in between (like
/// what else the call did save).
CallToolResult plannerWriteNotConfirmed({
  required String tool,
  required String what,
  required String check,
  required SmartschoolPlannerSaveUnconfirmedError error,
  String done = 'saved',
  String? also,
}) {
  log(
    '$tool: the planner did not confirm a write, not retrying: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '$what may or may not have been $done: the change was sent, but '
              'the planner did not confirm it.',
          ?also,
          'Do not call $tool again for it: first $check. Then tell the user '
              'what you found.',
        ].join(' '),
      ),
    ],
  );
}

/// Fills [hour], an empty lesson hour of the user's own planner
/// ([emptyHourArgument]), with [fill], and returns the result of the tool
/// [tool]: the lesson as saved, with its new id.
///
/// Reads the hour first (the library's fill takes the element as read, and
/// the result names the hour), then calls [fill] with it, such as
/// [PlannerService.planLesson] or [PlannerService.planLessonContent]; [what]
/// names what is planned (like `the lesson "Lussen"`). The library reads the hour again and refuses
/// one that is not the user's own or no longer empty, and sends the fill
/// once. A fill that the planner does not confirm is reported as maybe
/// saved ([plannerWriteNotConfirmed]), with how to check it.
Future<CallToolResult> fillLessonHour(
  SmartschoolSession session, {
  required String tool,
  required PlannedElementRef hour,
  required String what,
  required Future<PlannedElementDetail> Function(
    PlannerService planner,
    PlannedElementDetail slot,
  )
  fill,
}) async {
  PlannedElementDetail? slot;
  try {
    final lesson = await withPlannerWrite(session, (planner) async {
      final read = slot = await hour.read(planner);
      return fill(planner, read);
    });
    final classes = elementClasses(lesson);
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Planned $what in the ${formatElementSummary(slot!)}. Pupils'
                '${classes.isEmpty ? '' : ' of $classes'} see its name and '
                'public info now.',
            'The empty lesson hour $hour no longer exists: the lesson has '
                'the id ${PlannedElementRef.of(lesson)}.',
            plannerListLagNote,
            '',
            formatElementDetail(lesson),
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    final where = slot == null
        ? 'the empty lesson hour $hour'
        : 'the ${formatElementSummary(slot!)}';
    return plannerWriteNotConfirmed(
      tool: tool,
      what: '${_capitalised(what)} in $where',
      check:
          'read the hour with read_planned_element (id $hour): when the '
          'planner no longer has it, the hour was filled, and list_planner '
          '(planner me) shows the lesson in its place, possibly only after a '
          'few seconds; when the hour is still empty, nothing was saved',
      error: error,
    );
  }
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
