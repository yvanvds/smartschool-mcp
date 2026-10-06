import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../documents/document_reader.dart';
import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'document_result.dart';
import 'read_intradesk_file_tool.dart';
import 'server_tool.dart';

/// `read_lesfiche_attachment`: what is in one attachment of a lesfiche of
/// the user's Lesfiches module, as text (or as an image), as
/// `read_intradesk_file` reads a file
/// (`LessonContentService.downloadAttachmentStream`, dartschool#129;
/// [readDocument]).
///
/// The lesfiche gives the attachment's size and file name: one that is too
/// large, or of a type that cannot be read, is refused without downloading
/// it.
ServerTool readLesficheAttachmentTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_lesfiche_attachment',
    title: 'Read a lesfiche attachment',
    description:
        'Opens one attachment of a lesfiche of the user\'s Smartschool '
        'Lesfiches module and returns what is in it: to tell the user '
        'what it holds, to quote from it or to summarise it. Get the '
        'lesfiche id and kind from list_lesfiches; read_lesfiche lists '
        'the attachments, numbered. Pass the attachment by that number '
        '(1 for the first) or by its file name. Word (.docx), Excel '
        '(.xlsx) and PowerPoint (.pptx) files, PDFs, text files (.txt, '
        '.csv, .md) and web pages (.html) come back as text, as '
        'read_intradesk_file gives them; images (.png, .jpg, .gif, '
        '.webp) come back as an image. Files larger than '
        '${maxIntradeskFileBytes ~/ (1024 * 1024)} MB are not opened, '
        'and text longer than $defaultMaxDocumentChars characters is '
        'cut off, with a note. Old Office files (.doc, .xls, .ppt) and '
        'other formats cannot be read, nor a scanned PDF (it has no '
        'text): save_lesfiche_attachment saves any attachment for you to '
        'open with your own file tools. Reading an attachment changes '
        'nothing in Smartschool.',
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
      title: 'Read a lesfiche attachment',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final which = lesficheAttachmentArgument(arguments);

  final (:lesfiche, :number, :attachment) = await findLesficheAttachment(
    session,
    type,
    id,
    which,
  );
  final title = _capitalise(
    lesficheAttachmentTitle(lesfiche, number, attachment),
  );
  _refuseBeforeDownload(title, attachment);

  final watch = Stopwatch()..start();
  final (download, bytes) = await withPlannerClient(session, (client) async {
    try {
      // The library refuses a larger announced size before reading any of
      // the file, and otherwise stops the transfer once past the limit.
      final download = await LessonContentService(client)
          .downloadAttachmentStream(
            lesfiche,
            attachment.id,
            maxBytes: maxIntradeskFileBytes,
          );
      return (download, await readWholeDownload(download));
    } on SmartschoolDownloadError catch (error) {
      throw ToolError(
        'Smartschool could not download ${_lowercase(title)} (status '
        '${error.statusCode}). Try again later; the user can open it in '
        'Smartschool.',
      );
    } on SmartschoolDownloadTooLargeError catch (error) {
      // The announced size, when it is what was too large; otherwise more
      // bytes came in than allowed, and how many more is unknown.
      final size = switch (error.contentLength) {
        final size? when size > error.maxBytes => size,
        _ => null,
      };
      throw ToolError(
        '$title'
        '${size == null ? ' (more than ${formatFileSize(error.maxBytes)})' : ' (${formatFileSize(size)})'} '
        'is too large to open here: ${_limit()} The user can open it in '
        'Smartschool.',
      );
    }
  });
  final downloaded = watch.elapsedMilliseconds;

  final name = attachment.fileName.trim().isEmpty
      ? download.fileName
      : attachment.fileName.trim();
  final content = await readDocument(bytes, name: name);
  log(
    'read_lesfiche_attachment: ${bytes.length} bytes (size '
    '${download.contentLength == null ? 'not announced' : 'announced'}, '
    'type ${download.contentType ?? 'none'}, file name '
    '${download.fileName == null ? 'not given' : 'given'}) downloaded in '
    '$downloaded ms; ${describeDocumentForLog(content)} in '
    '${watch.elapsedMilliseconds - downloaded} ms',
  );
  return documentResult('$title (${formatFileSize(bytes.length)})', content);
}

/// Refuses, before downloading it, an attachment the lesfiche says is too
/// large, or whose name says it is of a type that cannot be read.
void _refuseBeforeDownload(String title, LessonContentAttachment attachment) {
  if (attachment.fileSize case final size? when size > maxIntradeskFileBytes) {
    throw ToolError(
      '$title (${formatFileSize(size)}) is too large to open here: '
      '${_limit()} The user can open it in Smartschool.',
    );
  }
  final extension = fileExtension(attachment.fileName.trim());
  if (unreadableExtensionReason(extension) case final reason?) {
    throw ToolError('$title: $reason');
  }
}

String _limit() =>
    'files up to ${formatFileSize(maxIntradeskFileBytes)} can be read.';

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String _lowercase(String text) =>
    text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
