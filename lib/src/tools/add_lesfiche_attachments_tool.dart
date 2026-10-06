import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `add_lesfiche_attachments`: adds files from this PC as attachments to a
/// lesfiche in the user's own library of the Lesfiches module, each with
/// when pupils see it (the library's `LessonContentService.addAttachments`,
/// dartschool#129), and gives the lesfiche back as `read_lesfiche` shows it.
///
/// Marked destructive, as `create_lesfiche` is (its doc comment says why),
/// and not idempotent: a second call adds the files a second time (the
/// module keeps two attachments of the same name, seen live). The files are
/// checked before anything is sent (`lesficheAttachmentsArgument`). The
/// library reads the lesfiche, uploads the files into a new upload
/// directory, has the module take them once (never again after logging in
/// again), and then sets each visibility that is not `always`: the module
/// gives every new attachment `always`, and ignores the visibility sent
/// with them (seen live). The tool reads the lesfiche first, in the session
/// action of the add (the library takes it as read), so that a repeat of
/// the action logs in again with a read (yvanvds/dartschool#134).
///
/// An add the module does not confirm cannot be told from one whose files
/// went in but whose visibility could not be set: both are a
/// [SmartschoolLessonContentSaveUnconfirmedError] (yvanvds/dartschool#135;
/// telling them apart here is #126).
/// So the result of either says that the files may or may not have been
/// added, or added without the visibility asked for, and to read the
/// lesfiche before anything else.
ServerTool addLesficheAttachmentsTool(
  SmartschoolSession session, {
  int maxBytes = maxLocalFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'add_lesfiche_attachments',
    title: 'Add files to a Smartschool lesfiche',
    description:
        'Adds files from this PC as attachments to one lesfiche in the '
        'user\'s own library ("Mijn lesfiches") of the Smartschool Lesfiches '
        'module, by the id and kind list_lesfiches shows, each with when '
        'pupils see it. When pupils see a file counts from the lesson the '
        'lesfiche is planned in: $lesficheVisibilityValues. Before calling '
        'this tool, show the user the lesfiche (name and kind) and each file '
        '(name, size, when pupils see it), and only call this tool after the '
        'user has explicitly confirmed it; then call it once. The server '
        'reads any file the user\'s Windows account can read, up to '
        '$maxLocalFiles files of ${formatFileSize(maxBytes)} each: files you '
        'made for the user (for example in a Cowork project folder) or that '
        'the user names. Each file goes in under its own name; a name the '
        'lesfiche has already is kept twice, and the result says so. To '
        'swap a file, add the new one and remove the old one with '
        'remove_lesfiche_attachment. Whether a lesson planned from the '
        'lesfiche earlier changes with it is not known. A lesfiche in the '
        'trash cannot be changed. The result gives the lesfiche as changed, '
        'with the id of each attachment. If the result says the files may '
        'or may not have been added, do not call this tool again for them, '
        'as a second call adds them a second time: check the lesfiche with '
        'read_lesfiche and tell the user. For requests like "voeg dit '
        'werkblad toe aan mijn lesfiche Lussen".',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
        'attachments': lesficheAttachmentsSchema(
          description:
              'The files from this PC to add, 1 to $maxLocalFiles, each with '
              'the full path and when pupils see it; each goes in under its '
              'own name, and no two may have the same name.',
        ),
      },
      required: ['lesfiche', 'attachments'],
    ),
    annotations: ToolAnnotations(
      title: 'Add files to a Smartschool lesfiche',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _add(
  SmartschoolSession session,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final files = lesficheAttachmentsArgument(
    arguments['attachments'],
    maxBytes: maxBytes,
  );
  if (files.isEmpty) {
    throw const ToolError(
      'attachments is empty: pass 1 to $maxLocalFiles files, each with the '
      'full path of a file on this PC. $nothingSent',
    );
  }
  final localFiles = [for (final (:file, visibility: _) in files) file];
  final count = files.length == 1
      ? 'the file "${localFiles.single.name}"'
      : '${files.length} files';

  LessonContentDetail? lesfiche;
  String title() => lesfiche == null
      ? 'the ${lesficheKindName(type)} $id'
      : lesficheTitle(lesfiche!);

  final watch = Stopwatch()..start();
  final List<LessonContentAttachment> added;
  try {
    added = await withLesficheWrite(
      session,
      (client) async {
        // First, so that a repeat of the session logs in again with a read:
        // the take of the files is refused at once on an expired session,
        // without a login (yvanvds/dartschool#134). The library reads the
        // lesfiche again itself, to tell the new attachments by their ids.
        final read = lesfiche = (await readLesficheDetail(
          client,
          type,
          id,
          withCourseNames: false,
        )).detail;
        return LessonContentService(
          client,
        ).addAttachments(read, lesficheAttachments(files));
      },
      what: () => 'the addition of $count to ${title()}',
      nothingDone: lesficheUnchanged,
      files: localFiles,
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    final visibilities = files.any(
      (file) => file.visibility != LessonContentVisibility.always,
    );
    return lesficheWriteNotConfirmed(
      tool: 'add_lesfiche_attachments',
      what: 'The addition of $count to ${title()}',
      done: 'carried out',
      also: visibilities
          ? 'The module gives every new attachment the visibility always, '
                'and the server sets the visibility asked for after that: a '
                'file may also have been added with always.'
          : null,
      why: 'a second call adds the files a second time',
      check:
          'read the lesfiche with ${readLesficheCall(type, id)} and compare '
          'its attachments; set a visibility that is not as asked with '
          'set_lesfiche_attachment_visibility',
      error: error,
    );
  }
  log(
    'add_lesfiche_attachments: added ${added.length} files in '
    '${watch.elapsedMilliseconds} ms',
  );
  final before = lesfiche!;
  final namesakes = {
    for (final attachment in added)
      if (before.attachments.any(
        (old) =>
            old.fileName.trim().toLowerCase() ==
            attachment.fileName.trim().toLowerCase(),
      ))
        attachment.fileName.trim(),
  };
  return lesficheChangedResult(session, type, id, [
    'Added ${added.length == 1 ? '1 attachment' : '${added.length} attachments'} '
        'to ${title()}:',
    for (final attachment in added) '- ${formatLesficheAttachment(attachment)}',
    if (namesakes.isNotEmpty)
      'Note: the lesfiche already had an attachment named '
          '${namesakes.map((name) => '"$name"').join(', ')}. The module '
          'keeps both; tell the user, and tell them apart by their ids '
          'below (remove_lesfiche_attachment removes one by its id).',
  ]);
}
