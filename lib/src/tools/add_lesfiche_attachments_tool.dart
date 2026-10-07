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
/// When the module took the files and only setting a visibility failed,
/// the library says so with a [SmartschoolLessonContentVisibilityNotSetError]
/// (yvanvds/dartschool#135, #126): the result lists the attachments added,
/// with their ids, says why the visibility was not set, and gives each
/// visibility not set as a call of `set_lesfiche_attachment_visibility`
/// (setting one again is harmless), without a read of the lesfiche. Any
/// other [SmartschoolLessonContentSaveUnconfirmedError] means that the take
/// itself is unconfirmed: the result says that the files may or may not
/// have been added, or added without the visibility asked for, and to read
/// the lesfiche before anything else. Neither result is a reason to call
/// the tool again.
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
        'read_lesfiche and tell the user. If it says the files were added '
        'but a visibility was not set, do not call this tool again either: '
        'set it with set_lesfiche_attachment_visibility as the result says. '
        'For requests like "voeg dit werkblad toe aan mijn lesfiche '
        'Lussen".',
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
  } on SmartschoolLessonContentVisibilityNotSetError catch (error) {
    // Before the error it extends: the module took the files, after the
    // read of the lesfiche.
    return _visibilityNotSet(type, id, lesfiche!, error);
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
  return lesficheChangedResult(session, type, id, [
    '${_added(added)} to ${title()}:',
    for (final attachment in added) '- ${formatLesficheAttachment(attachment)}',
    ?_namesakes(lesfiche!, added, where: 'below'),
  ]);
}

/// `Added 1 attachment`, `Added 3 attachments`: how a result starts to say
/// that [added] went in.
String _added(List<LessonContentAttachment> added) =>
    'Added ${added.length == 1 ? '1 attachment' : '${added.length} attachments'}';

/// The note that [before], the lesfiche as read before the add, already
/// had an attachment named as one of [added] (ignoring case), which the
/// module keeps next to the new one; null when it had none. [where] says
/// where the result lists the ids, like `below`.
String? _namesakes(
  LessonContentDetail before,
  List<LessonContentAttachment> added, {
  required String where,
}) {
  final namesakes = {
    for (final attachment in added)
      if (before.attachments.any(
        (old) =>
            old.fileName.trim().toLowerCase() ==
            attachment.fileName.trim().toLowerCase(),
      ))
        attachment.fileName.trim(),
  };
  if (namesakes.isEmpty) return null;
  return 'Note: the lesfiche already had an attachment named '
      '${namesakes.map((name) => '"$name"').join(', ')}. The module keeps '
      'both; tell the user, and tell them apart by their ids $where '
      '(remove_lesfiche_attachment removes one by its id).';
}

/// The result of an add whose files the module took, when setting the
/// visibility of one of them failed ([error], yvanvds/dartschool#135): the
/// files are on the lesfiche [id] of the kind [type] ([before], as read
/// before the add).
///
/// An error, as the request was not carried out in full, that lists the
/// attachments added with their ids and their visibility as far as the
/// library knows (the one asked for up to the failed one, else the module's
/// `always`), says why the failed one was not set, and gives each
/// visibility not set (the failed one, and those after it, which the
/// library did not try) as a call of `set_lesfiche_attachment_visibility`.
/// No read: the error carries what the take made, and setting a visibility
/// again is harmless.
CallToolResult _visibilityNotSet(
  LessonContentType type,
  String id,
  LessonContentDetail before,
  SmartschoolLessonContentVisibilityNotSetError error,
) {
  final added = error.addedAttachments;
  final notSet = error.visibilitiesNotSet;
  // Without the library's message, which names the lesfiche and the files.
  log(
    'add_lesfiche_attachments: added ${added.length} files, but '
    '${notSet.length} visibilities were not set '
    '(${error.cause.runtimeType})',
  );
  String named(String attachmentId) {
    for (final attachment in added) {
      if (attachment.id.toLowerCase() == attachmentId.toLowerCase()) {
        final name = attachment.fileName.trim();
        return name.isEmpty ? 'the attachment $attachmentId' : '"$name"';
      }
    }
    return 'the attachment $attachmentId';
  }

  final untried = [
    for (final attachmentId in notSet.keys)
      if (attachmentId.toLowerCase() != error.attachment.id.toLowerCase())
        named(attachmentId),
  ];
  final where =
      'lesfiche $id'
      '${type == LessonContentType.assignment ? ', type assignment' : ''}';
  final them = added.length == 1 ? 'it' : 'them';
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '${_added(added)} to ${lesficheTitle(before)}, but not every '
              'visibility asked for was set (each attachment with when '
              'pupils see it as far as the server knows):',
          for (final attachment in added)
            '- ${formatLesficheAttachment(attachment)}',
          'The module gives every new attachment the visibility always, and '
              'the server sets the visibility asked for after that. Setting '
              'the one of ${named(error.attachment.id)} failed: '
              '${_visibilityFailure(error.cause)}.'
              '${untried.isEmpty ? '' : ' The server stopped there, without setting the one of ${untried.join(', ')}.'}',
          ?_namesakes(before, added, where: 'above'),
          '${added.length == 1 ? 'The file is' : 'The files are'} on the '
              'lesfiche: do not call add_lesfiche_attachments again for '
              '$them, as a second call adds $them a second time. Set '
              '${notSet.length == 1 ? 'the visibility' : 'each visibility'} '
              'with set_lesfiche_attachment_visibility instead (setting one '
              'that went through again is harmless), and tell the user:',
          for (final MapEntry(key: attachmentId, value: visibility)
              in notSet.entries)
            '- ${named(attachmentId)}: set_lesfiche_attachment_visibility '
                '($where, attachment_id $attachmentId, visibility '
                '${lesficheVisibilityValue(visibility) ?? formatLesficheVisibility(visibility)})',
        ].join('\n'),
      ),
    ],
  );
}

/// Why setting the visibility of an added attachment failed, and whether it
/// was set: [cause] is the failure of the library's
/// `changeAttachmentVisibility`
/// ([SmartschoolLessonContentVisibilityNotSetError.cause]).
String _visibilityFailure(Object? cause) => switch (cause) {
  SmartschoolLessonContentSaveUnconfirmedError() =>
    'it was sent, but the Lesfiches module did not confirm it, so it may or '
        'may not have been set',
  SmartschoolLessonContentWriteRefusedError(
    :final statusCode,
    :final violations,
  ) =>
    'the Lesfiches module refused it (HTTP $statusCode)'
        '${violations.isEmpty ? ', without saying why' : ': ${violations.map((v) => '"$v"').join(' ')}'}, '
        'so it was not set',
  SmartschoolLessonContentNotFoundError() =>
    'the Lesfiches module answered it with HTTP 404, so it was not set (the '
        'lesfiche was moved to the trash, or the attachment removed, '
        'meanwhile)',
  SmartschoolLessonContentError(:final statusCode) =>
    'the Lesfiches module refused it'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}, so it was not set',
  SmartschoolAuthenticationError() =>
    'Smartschool did not accept the session, so it was not set',
  _ => 'it may or may not have been set',
};
