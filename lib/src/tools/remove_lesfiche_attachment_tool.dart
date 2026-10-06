import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import 'server_tool.dart';

/// `remove_lesfiche_attachment`: removes one attachment from a lesfiche in
/// the user's own library of the Lesfiches module (the library's
/// `LessonContentService.removeAttachment`, dartschool#129), and gives the
/// lesfiche back as `read_lesfiche` shows it.
///
/// Marked destructive: the file is gone from the lesfiche, and the module
/// keeps no copy of it. A second call finds no attachment with that id and
/// changes nothing: it is idempotent. The tool reads the lesfiche first, in
/// the session action of the removal, and refuses an attachment id it does
/// not have before sending anything; the library retries the removal after
/// logging in again, as a read.
ServerTool removeLesficheAttachmentTool(SmartschoolSession session) =>
    ServerTool(
      definition: Tool(
        name: 'remove_lesfiche_attachment',
        title: 'Remove an attachment from a Smartschool lesfiche',
        description:
            'Removes one attachment from a lesfiche in the user\'s own '
            'library ("Mijn lesfiches") of the Smartschool Lesfiches module, '
            'by the id and kind list_lesfiches shows and the attachment\'s '
            'id as read_lesfiche shows it at the end of the attachment\'s '
            'line. The file is gone from the lesfiche: the module keeps no '
            'copy of it, and the lesfiche stays. To keep a copy, save it '
            'first with save_lesfiche_attachment. Before calling this tool, '
            'show the user the lesfiche (name and kind) and the file (name '
            'and size), and only call this tool after the user has '
            'explicitly confirmed it; then call it once per file. Whether a '
            'lesson planned from the lesfiche earlier changes with it is not '
            'known. A lesfiche in the trash cannot be changed. The result '
            'gives the lesfiche as changed. If the result says the '
            'attachment may or may not have been removed, check the lesfiche '
            'with read_lesfiche and tell the user.',
        inputSchema: Schema.object(
          properties: {
            'lesfiche': Schema.string(
              description:
                  'The id of the lesfiche, as list_lesfiches shows it, like '
                  'b0000000-0000-4000-8000-000000000001.',
              minLength: 1,
            ),
            'type': lesficheTypeSchema(),
            'attachment_id': Schema.string(
              description:
                  'The id of the attachment, as read_lesfiche shows it at '
                  'the end of the attachment\'s line.',
              minLength: 1,
            ),
          },
          required: ['lesfiche', 'attachment_id'],
        ),
        annotations: ToolAnnotations(
          title: 'Remove an attachment from a Smartschool lesfiche',
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: true,
          openWorldHint: true,
        ),
      ),
      handler: (request) => _remove(session, request.arguments ?? const {}),
    );

Future<CallToolResult> _remove(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final attachmentId = lesfichePartIdArgument(
    arguments['attachment_id'],
    name: 'attachment_id',
    what: 'attachment',
  );

  LessonContentDetail? lesfiche;
  LessonContentAttachment? attachment;
  String title() => lesfiche == null
      ? 'the ${lesficheKindName(type)} $id'
      : lesficheTitle(lesfiche!);
  String named() => attachment == null
      ? 'the attachment $attachmentId'
      : 'the attachment "${attachment!.fileName}"';

  try {
    await withLesficheWrite(
      session,
      (client) async {
        final read = lesfiche = (await readLesficheDetail(
          client,
          type,
          id,
          withCourseNames: false,
        )).detail;
        final (_, found) = lesficheAttachmentById(read, attachmentId);
        attachment = found;
        await LessonContentService(client).removeAttachment(read, found.id);
      },
      what: () => 'the removal of ${named()} from ${title()}',
      nothingDone: lesficheUnchanged,
      orGone: 'the attachment was removed meanwhile',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return lesficheWriteNotConfirmed(
      tool: 'remove_lesfiche_attachment',
      what: _capitalised(named()),
      done: 'removed from ${title()}',
      check:
          'read the lesfiche with ${readLesficheCall(type, id)} to see '
          'whether it is still there',
      error: error,
    );
  }
  log('remove_lesfiche_attachment: removed');
  final size = attachment!.fileSize;
  return lesficheChangedResult(session, type, id, [
    'Removed ${named()}${size == null ? '' : ' (${formatFileSize(size)})'} '
        'from ${title()}.',
  ]);
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
