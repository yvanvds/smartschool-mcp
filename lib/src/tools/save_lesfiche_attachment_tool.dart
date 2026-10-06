import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../downloads/download_folder.dart';
import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'save_intradesk_file_tool.dart';
import 'saved_file_result.dart';
import 'server_tool.dart';

/// `save_lesfiche_attachment`: saves one attachment of a lesfiche of the
/// user's Lesfiches module into the download folder ([downloads]), so that
/// Claude can open it with its own file tools (in a Cowork project) or the
/// user can (`LessonContentService.downloadAttachmentStream`,
/// dartschool#129).
///
/// The attachment is named by its number as `read_lesfiche` lists it (1 for
/// the first) or by its file name. Attachments larger than [maxBytes] are
/// not saved: refused before downloading when the lesfiche gives the size.
/// Without a download folder ([downloads] null), every call says how to set
/// one.
ServerTool saveLesficheAttachmentTool(
  SmartschoolSession session,
  DownloadFolder? downloads, {
  int maxBytes = maxSavedFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'save_lesfiche_attachment',
    title: 'Save a lesfiche attachment',
    description:
        'Saves one attachment of a lesfiche of the user\'s Smartschool '
        'Lesfiches module into the download folder on this PC, and returns '
        'its full path, file name and size. Use it to open an attachment '
        'read_lesfiche_attachment cannot read (well), such as a scanned PDF, '
        'an old Office file (.doc, .xls, .ppt) or any other format, or when '
        'the user wants the file itself. After saving, open the file from '
        'the returned path with your own file tools when you can (for '
        'example in a Cowork project whose folder holds the download '
        'folder); otherwise tell the user where the file is, so they can '
        'open it or drag it into the chat. Get the lesfiche id and kind from '
        'list_lesfiches; read_lesfiche lists the attachments, numbered. Pass '
        'the attachment by that number (1 for the first) or by its file '
        'name. Attachments up to ${formatFileSize(maxBytes)} are saved. An '
        'existing file is never replaced: the new one gets " (2)", " (3)", '
        '... in its name. Files saved here are deleted after '
        '${DownloadFolder.defaultRetention.inDays} days; other files in the '
        'folder are never touched. Saving changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
        'attachment': lesficheAttachmentSchema(),
      },
      required: ['lesfiche', 'attachment'],
    ),
    annotations: ToolAnnotations(
      title: 'Save a lesfiche attachment',
      // It writes a file on this PC; it never replaces one.
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) =>
      _save(session, downloads, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _save(
  SmartschoolSession session,
  DownloadFolder? downloads,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final which = lesficheAttachmentArgument(arguments);
  final folder = downloads ?? (throw noDownloadFolder(session.source));

  final (:lesfiche, :number, :attachment) = await findLesficheAttachment(
    session,
    type,
    id,
    which,
  );
  final title = lesficheAttachmentTitle(lesfiche, number, attachment);
  if (attachment.fileSize case final size? when size > maxBytes) {
    throw ToolError(
      '${_capitalise(title)} (${formatFileSize(size)}) is too large to save '
      'here: files up to ${formatFileSize(maxBytes)} can be saved. The user '
      'can download it in Smartschool.',
    );
  }

  final watch = Stopwatch()..start();
  final saved = await folder.save(
    (temporary) => withPlannerClient(session, (client) async {
      try {
        // The library refuses a larger announced size before reading any of
        // the file, and otherwise stops the transfer once past the limit.
        final download = await writeDownload(
          temporary,
          () => LessonContentService(client).downloadAttachmentStream(
            lesfiche,
            attachment.id,
            maxBytes: maxBytes,
          ),
        );
        final name = attachment.fileName.trim();
        return name.isEmpty ? download.fileName : name;
      } on SmartschoolDownloadError catch (error) {
        throw ToolError(
          'Smartschool could not download $title (status '
          '${error.statusCode}). Try again later; the user can download it '
          'in Smartschool.',
        );
      } on SmartschoolDownloadTooLargeError catch (error) {
        final size = tooLargeSize(error);
        throw ToolError(
          '${_capitalise(title)}'
          '${size == null ? '' : ' (${formatFileSize(size)})'} '
          '${tooLargeToSave(error)}',
        );
      }
    }),
    fallbackName: 'lesfiche-attachment-$number',
  );
  log(
    'save_lesfiche_attachment: ${saved.size} bytes saved in '
    '${watch.elapsedMilliseconds} ms (${describeNameForLog(saved)})',
  );
  return savedFileResult(title, saved, folder);
}

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
