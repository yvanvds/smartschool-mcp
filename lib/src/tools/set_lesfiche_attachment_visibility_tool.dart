import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `set_lesfiche_attachment_visibility`: sets when pupils see one
/// attachment of a lesfiche in the user's own library of the Lesfiches
/// module (the library's `LessonContentService.changeAttachmentVisibility`,
/// dartschool#129), and gives the lesfiche back as `read_lesfiche` shows it.
///
/// Marked destructive, as `create_lesfiche` is (its doc comment says why):
/// it changes what pupils see of a lesson planned from the lesfiche later.
/// It sets a value, so it is idempotent; the library retries it after
/// logging in again, as a read. The tool reads the lesfiche first, in the
/// session action of the change, and refuses an attachment id it does not
/// have before sending anything.
ServerTool setLesficheAttachmentVisibilityTool(SmartschoolSession session) =>
    ServerTool(
      definition: Tool(
        name: 'set_lesfiche_attachment_visibility',
        title: 'Set when pupils see an attachment of a Smartschool lesfiche',
        description:
            'Sets when pupils see one attachment of a lesfiche in the '
            'user\'s own library ("Mijn lesfiches") of the Smartschool '
            'Lesfiches module, by the id and kind list_lesfiches shows and '
            'the attachment\'s id as read_lesfiche shows it at the end of '
            'the attachment\'s line. It counts from the lesson the lesfiche '
            'is planned in: $lesficheVisibilityValues. Before calling this '
            'tool, show the user the lesfiche (name and kind), the file and '
            'the new visibility, and only call this tool after the user has '
            'explicitly confirmed it. Whether a lesson planned from the '
            'lesfiche earlier changes with it is not known. A lesfiche in '
            'the trash cannot be changed. The result gives the lesfiche as '
            'changed. If the result says the visibility may or may not have '
            'been changed, check the lesfiche with read_lesfiche and tell '
            'the user. For requests like "laat de oplossingen pas na de les '
            'zien".',
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
            'visibility': lesficheVisibilitySchema(
              description: 'When pupils see the file',
            ),
          },
          required: ['lesfiche', 'attachment_id', 'visibility'],
        ),
        annotations: ToolAnnotations(
          title: 'Set when pupils see an attachment of a Smartschool lesfiche',
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: true,
          openWorldHint: true,
        ),
      ),
      handler: (request) => _set(session, request.arguments ?? const {}),
    );

Future<CallToolResult> _set(
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
  if (arguments['visibility'] case final value
      when value is! String || value.trim().isEmpty) {
    throw const ToolError(
      'visibility is missing: pass when pupils see the file, '
      '$lesficheVisibilityValues. $nothingSent',
    );
  }
  final visibility = lesficheVisibilityArgument(
    arguments['visibility'],
    where: 'visibility',
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
        return LessonContentService(
          client,
        ).changeAttachmentVisibility(read, found.id, visibility);
      },
      what: () => 'the change of the visibility of ${named()} of ${title()}',
      nothingDone: lesficheUnchanged,
      orGone: 'the attachment was removed meanwhile',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return lesficheWriteNotConfirmed(
      tool: 'set_lesfiche_attachment_visibility',
      what: 'The change of the visibility of ${named()} of ${title()}',
      done: 'saved',
      check:
          'read the lesfiche with ${readLesficheCall(type, id)} and compare '
          'when pupils see it',
      error: error,
    );
  }
  log('set_lesfiche_attachment_visibility: changed');
  final was = attachment!.visibility;
  return lesficheChangedResult(session, type, id, [
    'Pupils now see ${named()} of ${title()}: '
        '${formatLesficheVisibility(visibility)}'
        '${was == visibility ? ' (as before)' : ' (before: ${formatLesficheVisibility(was)})'}.',
  ]);
}
