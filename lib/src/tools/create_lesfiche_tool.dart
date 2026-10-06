import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `create_lesfiche`: makes a lesfiche in the user's own library ("Mijn
/// lesfiches") of the Lesfiches module, a lesson or an assignment, with its
/// name, icon, public and private info, courses, weblinks and attachments
/// (files from this PC) in one create, as the web client makes one (the
/// library's `LessonContentService.createLesson` and `createAssignment`,
/// dartschool#129), and gives it back as `read_lesfiche` shows it.
///
/// Marked destructive, though the own library is private to the user
/// until a lesson is planned from the lesfiche: it is a write that Claude is
/// told to show the user first (the name, the courses, the info, the
/// weblinks and the files) and to make only after the user's confirmation;
/// a second call makes a second lesfiche (the module keeps a name that is
/// taken), so it is not idempotent either; and it sends files from this PC
/// to Smartschool. Claude Desktop, and Codex too, ask for approval only for
/// a tool marked destructive (README, "ChatGPT and Codex"), and that
/// approval is what holds Claude to the confirmation.
///
/// The arguments are checked before anything is sent
/// (`lesfiche_writes.dart`, the visibilities in `lesfiche_detail.dart`).
/// The tool then reads the user's lesfiches, for the note on lesfiches of
/// the same name and kind (that read also logs in again when the session
/// repeats the call: the create goes out once only), the school's course
/// list to find the courses by name, and for an assignment the school's
/// assignment types. The library checks the courses and the type again,
/// uploads the files, sends the create once and reads the new lesfiche
/// back; a create it cannot confirm is reported as maybe made, or as made
/// with its id when the module answered with one.
ServerTool createLesficheTool(
  SmartschoolSession session, {
  int maxBytes = maxLocalFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'create_lesfiche',
    title: 'Make a Smartschool lesfiche',
    description:
        'Makes a new lesfiche in the user\'s own library ("Mijn lesfiches") '
        'of the Smartschool Lesfiches module, in one call: a lesson lesfiche '
        '(the default) or an assignment lesfiche (type assignment, with '
        'assignment_type), with its name, public info (what pupils see once '
        'it is planned), private info, courses, weblinks and attachments '
        '(files from this PC). The own library is private to the user: '
        'pupils see nothing of a lesfiche until a lesson is planned from it. '
        'Use it to turn a lesson prepared with the user (in the chat, or '
        'from documents) into a lesfiche, which plan_lesfiche then plans '
        'into the user\'s lesson hours as often as needed. Before calling '
        'this tool, show the user the kind, the name, the courses, the info, '
        'each weblink (name, address, when pupils see it) and each file '
        '(name, size, when pupils see it), and only call this tool after the '
        'user has explicitly confirmed it; then call it once per lesfiche. '
        'The server reads any file the user\'s Windows account can read, up '
        'to $maxLocalFiles files of ${formatFileSize(maxBytes)} each: files '
        'you made for the user (for example in a Cowork project folder) or '
        'that the user names. A name that is taken is not refused: the '
        'module makes a second lesfiche of that name, and the result names '
        'the others. Labels are not offered: the user sets them in the '
        'Lesfiches module itself. Write the info as plain text, with a blank '
        'line between paragraphs; HTML in it is not interpreted, it shows as '
        'text. When pupils see a weblink or a file counts from the lesson '
        'the lesfiche is planned in: $lesficheVisibilityValues. The result '
        'gives the lesfiche as made, with its id for plan_lesfiche and '
        'read_lesfiche. If the result says the lesfiche may or may not have '
        'been made, or that it was made without confirming everything, do '
        'not call this tool again for it, as a second call makes a second '
        'lesfiche: check it with list_lesfiches or read_lesfiche as the '
        'result says, and tell the user. For requests like "maak een '
        'lesfiche Lussen voor informatica met dit werkblad".',
    inputSchema: Schema.object(
      properties: {
        'name': Schema.string(
          description:
              'The name of the lesfiche, as the user confirmed it: at most '
              '${LessonContentService.maxNameLength} characters. Pupils see '
              'it once it is planned.',
          minLength: 1,
        ),
        'type': UntitledSingleSelectEnumSchema(
          description:
              'The kind of lesfiche: lesson (the default) or assignment (a '
              'test or task, with assignment_type).',
          values: lesficheTypes.keys.toList(),
        ),
        'assignment_type': Schema.string(
          description:
              'Only for type assignment, and then required: one of the '
              'school\'s assignment types, by its abbreviation or name, such '
              'as KT or Kleine Taak (list_class_assignments lists them), as '
              'the user confirmed it.',
          minLength: 1,
        ),
        'public_info': Schema.string(
          description:
              'What pupils see with a lesson planned from the lesfiche, as '
              'plain text: a blank line between paragraphs. Default: none.',
        ),
        'private_info': Schema.string(
          description: 'Notes pupils do not see, as plain text. Default: none.',
        ),
        'courses': lesficheCoursesSchema(
          description: 'The courses of the lesfiche. Default: none.',
        ),
        'weblinks': lesficheWeblinksSchema(
          description:
              'Weblinks pupils open from the lesfiche, each with its name, '
              'its address and when pupils see it. Default: none.',
        ),
        'attachments': lesficheAttachmentsSchema(
          description:
              'Files from this PC to attach, 1 to $maxLocalFiles, each with '
              'the full path and when pupils see it; each goes in under its '
              'own name, and no two may have the same name. Default: none.',
        ),
        'icon': Schema.string(
          description:
              'The icon of the lesfiche, a name from Smartschool\'s icon set '
              'as read_lesfiche shows it. Default: the web client\'s, '
              '${LessonContentService.defaultLessonIcon} for a lesson and '
              '${LessonContentService.defaultAssignmentIcon} for an '
              'assignment. Leave it out unless the user asks for an icon.',
        ),
      },
      required: ['name'],
    ),
    annotations: ToolAnnotations(
      title: 'Make a Smartschool lesfiche',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) =>
      _create(session, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _create(
  SmartschoolSession session,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final type = lesficheTypeArgument(arguments['type']);
  final name = lesficheNameArgument(arguments['name']);
  final typeName = _assignmentTypeArgument(type, arguments['assignment_type']);
  final icon = switch (arguments['icon']) {
    final String icon when icon.trim().isNotEmpty => icon.trim(),
    _ =>
      type == LessonContentType.assignment
          ? LessonContentService.defaultAssignmentIcon
          : LessonContentService.defaultLessonIcon,
  };
  final publicInfo = plainTextToHtml(arguments['public_info'] as String? ?? '');
  final privateInfo = plainTextToHtml(
    arguments['private_info'] as String? ?? '',
  );
  final wanted = lesficheCoursesArgument(arguments['courses']) ?? const [];
  final weblinks = lesficheWeblinksArgument(arguments['weblinks']);
  final files = lesficheAttachmentsArgument(
    arguments['attachments'],
    maxBytes: maxBytes,
  );
  final kind = lesficheKindName(type);
  final assignmentTypes = AssignmentTypes.of(session);

  final watch = Stopwatch()..start();
  try {
    final (lesfiche, namesakes) = await withLesficheWrite(
      session,
      (client) async {
        final lesfiches = LessonContentService(client);
        // First, so that a repeat of the session logs in again with it:
        // the create is refused at once on an expired session, without a
        // login (yvanvds/dartschool#134).
        final items = await lesfiches.getItems(withCourseNames: false);
        final courses = wanted.isEmpty
            ? const <PlannerCourse>[]
            : lesficheCourses(await lesfiches.getCourses(), wanted);
        final courseIds = [for (final course in courses) course.id];
        final LessonContentDetail made;
        if (typeName == null) {
          made = await lesfiches.createLesson(
            name: name,
            icon: icon,
            publicInfo: publicInfo,
            privateInfo: privateInfo,
            courseIds: courseIds,
            weblinks: weblinks,
            attachments: lesficheAttachments(files),
          );
        } else {
          final planner = PlannerService(client);
          final PlannerAssignmentType assignmentType;
          try {
            assignmentType = assignmentTypeArgument(
              typeName,
              await assignmentTypes.read(planner),
              name: 'assignment_type',
            );
          } on ToolError catch (error) {
            throw ToolError('${error.message} $nothingSent');
          }
          try {
            made = await lesfiches.createAssignment(
              name: name,
              assignmentTypeId: assignmentType.id,
              icon: icon,
              publicInfo: publicInfo,
              privateInfo: privateInfo,
              courseIds: courseIds,
              weblinks: weblinks,
              attachments: lesficheAttachments(files),
            );
          } on ArgumentError catch (error) {
            // The school's types changed since the session read them: the
            // library's check read them again before sending.
            if (error.name != 'assignmentTypeId') rethrow;
            throw await _typeGone(
              planner,
              assignmentTypes,
              typeName,
              assignmentType,
            );
          }
        }
        return (made, _namesakes(items, made));
      },
      what: () => 'the $kind "$name"',
      nothingDone: noLesficheMade,
      files: [for (final (:file, visibility: _) in files) file],
    );
    log(
      'create_lesfiche: made the $kind in ${watch.elapsedMilliseconds} ms '
      '(courses ${lesfiche.courses.length}, weblinks '
      '${lesfiche.weblinks.length}, attachments '
      '${lesfiche.attachments.length}, of the same name ${namesakes.length})',
    );
    return _result(lesfiche, namesakes);
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return _notConfirmed(type, name, error);
  }
}

/// The `assignment_type` argument [value] for a lesfiche of the kind
/// [type]: the name or abbreviation of an assignment type, without the
/// white space around it, for an assignment; null for a lesson.
///
/// Throws a [ToolError] when an assignment lacks it, or a lesson has it.
String? _assignmentTypeArgument(LessonContentType type, Object? value) {
  final text = value is String ? value.trim() : '';
  if (type == LessonContentType.assignment) {
    if (text.isNotEmpty) return text;
    throw const ToolError(
      'assignment_type is missing: an assignment lesfiche has one of the '
      'school\'s assignment types. Pass it by its abbreviation or name, such '
      'as KT or Kleine Taak (list_class_assignments lists them). '
      '$nothingSent',
    );
  }
  if (text.isEmpty) return null;
  throw const ToolError(
    'assignment_type is for an assignment lesfiche only: pass type '
    'assignment with it, or leave it out for a lesson lesfiche. $nothingSent',
  );
}

/// The error for the assignment type [sent] that [typeName] named, which
/// the library refused as no longer one of the school's: the school's types
/// as they are now, read with [planner], which every tool on the session
/// takes from now on ([AssignmentTypes.replace]).
Future<ToolError> _typeGone(
  PlannerService planner,
  AssignmentTypes assignmentTypes,
  String typeName,
  PlannerAssignmentType sent,
) async {
  log('lesfiches: the library refused the assignment type before sending');
  final types = await planner.getAssignmentTypes();
  assignmentTypes.replace(types);
  return ToolError(
    'assignment_type "$typeName" named the assignment type '
    '${formatAssignmentType(sent)}, which is no longer one of the '
    'school\'s assignment types: they changed since the server read them. '
    '${schoolAssignmentTypes(types)} Ask the user which one to use instead. '
    '$nothingSent',
  );
}

/// The lesfiches of [items] (the user's, as read before the create) with
/// the name and the kind of [made], ignoring case and extra white space,
/// but [made] itself: the module keeps a name that is taken.
List<LessonContentItem> _namesakes(
  List<LessonContentItem> items,
  LessonContentDetail made,
) {
  String normal(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return sortedByName([
    for (final item in items)
      if (item.type == made.type &&
          item.id.toLowerCase() != made.id.toLowerCase() &&
          normal(item.name) == normal(made.name))
        item,
  ]);
}

/// The result of a create: [lesfiche] as read back, with what to do with
/// it, and the [namesakes] it has.
CallToolResult _result(
  LessonContentDetail lesfiche,
  List<LessonContentItem> namesakes,
) {
  final kind = lesficheKindName(lesfiche.type);
  final isLesson = lesfiche.type == LessonContentType.lesson;
  final readIt =
      'read_lesfiche (lesfiche ${lesfiche.id}'
      '${isLesson ? '' : ', type assignment'})';
  final others = namesakes.length == 1
      ? '1 other $kind'
      : '${namesakes.length} other ${kind}s';
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Made the $kind "${lesfiche.name}" in your own library ("Mijn '
              'lesfiches") of the Lesfiches module. Pupils see nothing of it '
              'until it is planned.',
          if (isLesson)
            'Its id is ${lesfiche.id}: plan it into an empty lesson hour of '
                'your own planner with plan_lesfiche, and read it with '
                '$readIt.'
          else
            'Its id is ${lesfiche.id}: read it with $readIt. This server '
                'plans lesson lesfiches only; an assignment lesfiche is '
                'planned in Smartschool itself.',
          'Labels are set in the Lesfiches module itself.',
          if (namesakes.isNotEmpty) ...[
            'Note: you already had $others named "${lesfiche.name}". The '
                'module keeps both; tell the user, who can tell them apart '
                'by their labels in the module:',
            for (final item in namesakes)
              '- ${formatLesficheLine(item, withCourseNames: false)}',
          ],
          '',
          formatLesficheDetail(lesfiche),
        ].join('\n'),
      ),
    ],
  );
}

/// The result of a create of the lesfiche [name] of the kind [type] that
/// the library could not confirm ([error]): made, when the module answered
/// with its id ([SmartschoolLessonContentSaveUnconfirmedError.lessonContentId])
/// but reading it back failed or did not show everything sent; else maybe
/// made.
CallToolResult _notConfirmed(
  LessonContentType type,
  String name,
  SmartschoolLessonContentSaveUnconfirmedError error,
) {
  final kind = lesficheKindName(type);
  final id = error.lessonContentId;
  if (id == null) {
    return lesficheWriteNotConfirmed(
      tool: 'create_lesfiche',
      what: 'The $kind "$name"',
      check:
          'list the lesfiches with list_lesfiches (type '
          '${type == LessonContentType.assignment ? 'assignments' : 'lessons'}'
          ', query "$name") to see whether it is there',
      why:
          'the module does not refuse a name that is taken, so a second '
          'call could make it twice',
      error: error,
    );
  }
  log(
    'create_lesfiche: the lesfiche was made, but '
    '${error.cause == null ? 'its detail does not show everything sent' : 'reading it back failed (${error.cause.runtimeType})'}',
  );
  final readIt =
      'read_lesfiche (lesfiche $id'
      '${type == LessonContentType.assignment ? ', type assignment' : ''})';
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            'The $kind "$name" was made, with id $id, but '
            '${error.cause == null ? 'what the Lesfiches module shows of it does not match everything that was sent' : 'reading it back failed'}. '
            'Do not call create_lesfiche again for it: it exists, and a '
            'second call would make a second lesfiche. First read it with '
            '$readIt to see what it holds; then tell the user what you '
            'found. What is missing can be added in the Lesfiches module.',
      ),
    ],
  );
}
