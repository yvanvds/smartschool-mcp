import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../documents/document_reader.dart';
import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../log.dart';
import '../session.dart';
import 'document_result.dart';
import 'server_tool.dart';

/// Files larger than this are not downloaded.
const maxIntradeskFileBytes = 25 * 1024 * 1024;

/// `read_intradesk_file`: what is in one file on Intradesk, as text (or as
/// an image), so Claude can check whether it holds what the user is
/// looking for.
///
/// The file's path, size and type come from the index in [cache] when there
/// is one: a file that is too large, or of a type that cannot be read, is
/// refused without downloading it. Reading never builds an index.
ServerTool readIntradeskFileTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'read_intradesk_file',
    title: 'Read an Intradesk file',
    description:
        'Opens one file on Intradesk, the school\'s shared document store in '
        'Smartschool, and returns what is in it: to check whether it holds '
        'what the user is looking for, to quote from it or to summarise '
        'it. Get the file id from search_intradesk or list_intradesk_folder. '
        'Word (.docx), Excel (.xlsx) and PowerPoint (.pptx) files, PDFs, '
        'text files (.txt, .csv, .md) and web pages (.html) come back as '
        'text: headings as # lines, table rows as one line with the cells '
        'separated by " | ", every sheet of a workbook under its name, every '
        'slide with its speaker notes, every page of a PDF under its '
        'number. Images (.png, .jpg, .gif, .webp) come back as an image. '
        'Files larger than ${maxIntradeskFileBytes ~/ (1024 * 1024)} MB are '
        'not opened, and text longer than $defaultMaxDocumentChars '
        'characters is cut off, with a note. Old Office files (.doc, .xls, '
        '.ppt) and other formats cannot be read, nor a scanned PDF (it has '
        'no text): save_intradesk_file saves any file for you to open '
        'with your own file tools. Reading a file changes nothing on '
        'Intradesk.',
    inputSchema: Schema.object(
      properties: {
        'file_id': Schema.string(
          description:
              'The id of the file, from search_intradesk or '
              'list_intradesk_folder.',
        ),
      },
      required: ['file_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read an Intradesk file',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, cache, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final id = intradeskIdArgument(arguments, 'file_id');
  if (id == null) {
    throw const ToolError(
      'file_id is empty: pass the id of a file, from search_intradesk or '
      'list_intradesk_folder.',
    );
  }

  final watch = Stopwatch()..start();
  final (known, download, bytes) = await session.run((client) async {
    // Inside the session, as the cache folder is the logged-in user's.
    final known = (await cache.saved())?.find(id);
    _refuseBeforeDownload(id, known);
    final intradesk = IntradeskService(client);
    try {
      // The library refuses a larger announced size before reading any of
      // the file, and otherwise stops the transfer once past the limit.
      final download = await intradesk.downloadFileStream(
        id,
        maxBytes: maxIntradeskFileBytes,
      );
      return (known, download, await readWholeDownload(download));
    } on SmartschoolDownloadError catch (error) {
      throw ToolError(
        'Smartschool could not download an Intradesk file with id $id '
        '(status ${error.statusCode}). Most likely it is not the id of a '
        'file you can open, for example a folder\'s id or a file that was '
        'removed: take the id of a file from search_intradesk or '
        'list_intradesk_folder. If the id is right, try again later.',
      );
    } on SmartschoolDownloadTooLargeError catch (error) {
      // The announced size, when it is what was too large; otherwise more
      // bytes came in than allowed, and how many more is unknown.
      final size = switch (error.contentLength) {
        final size? when size > error.maxBytes => size,
        _ => null,
      };
      throw ToolError(
        '${intradeskFileTitle(id, known, size: size)} is too large to open here'
        '${size == null ? ' (more than ${formatFileSize(error.maxBytes)})' : ''}: '
        '${_limit()} The user can open it in Smartschool.',
      );
    }
  });
  final downloaded = watch.elapsedMilliseconds;

  final name = known?.name ?? download.fileName;
  final title = intradeskFileTitle(id, known, name: name, size: bytes.length);
  final content = await readDocument(bytes, name: name);
  log(
    'read_intradesk_file: ${bytes.length} bytes '
    '(${known == null ? 'not in the index' : 'in the index'}, size '
    '${download.contentLength == null ? 'not announced' : 'announced'}, '
    'type ${download.contentType ?? 'none'}, file name '
    '${download.fileName == null ? 'not given' : 'given'}) downloaded in '
    '$downloaded ms; ${describeDocumentForLog(content)} in '
    '${watch.elapsedMilliseconds - downloaded} ms',
  );

  return documentResult(title, content);
}

/// Refuses, before downloading it, a file the index knows to be a folder,
/// too large, or of a type that cannot be read.
void _refuseBeforeDownload(String id, IntradeskItem? known) {
  if (known == null) return;
  if (known.kind == IntradeskItemKind.folder) {
    throw ToolError(
      '$id is the id of the Intradesk folder ${known.path}, not of a file: '
      'use list_intradesk_folder to see what is in it.',
    );
  }
  if (known.size case final size? when size > maxIntradeskFileBytes) {
    throw ToolError(
      '${intradeskFileTitle(id, known, size: size)} is too large to open here: '
      '${_limit()} The user can open it in Smartschool.',
    );
  }
  if (unreadableExtensionReason(fileExtension(known.name)) case final reason?) {
    throw ToolError(
      '${intradeskFileTitle(id, known, size: known.size)}: $reason',
    );
  }
}

String _limit() =>
    'files up to ${formatFileSize(maxIntradeskFileBytes)} can be read.';
