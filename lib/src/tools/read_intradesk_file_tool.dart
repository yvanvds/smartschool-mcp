import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../capped_download.dart';
import '../documents/document_reader.dart';
import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_download.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../log.dart';
import '../session.dart';
import 'server_tool.dart';

/// Files larger than this are not downloaded.
const maxIntradeskFileBytes = 25 * 1024 * 1024;

/// `read_intradesk_file`: what is in one file on Intradesk, as text (or as
/// an image), so Claude can check whether it holds what the teacher is
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
        'what the teacher is looking for, to quote from it or to summarise '
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
        'no text). Reading a file changes nothing on Intradesk.',
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
  final (known, file) = await session.run((client) async {
    // Inside the session, as the cache folder is the logged-in user's.
    final known = (await cache.saved())?.find(id);
    _refuseBeforeDownload(id, known);
    try {
      return (
        known,
        await downloadIntradeskFile(
          client,
          id,
          maxBytes: maxIntradeskFileBytes,
        ),
      );
    } on SmartschoolDownloadError catch (error) {
      throw ToolError(
        'Smartschool could not download an Intradesk file with id $id '
        '(status ${error.statusCode}). Most likely it is not the id of a '
        'file you can open, for example a folder\'s id or a file that was '
        'removed: take the id of a file from search_intradesk or '
        'list_intradesk_folder. If the id is right, try again later.',
      );
    } on FileTooLargeError catch (error) {
      throw ToolError(
        '${_title(id, known, size: error.size)} is too large to open here'
        '${error.size == null ? ' (more than ${formatFileSize(error.maxBytes)})' : ''}: '
        '${_limit()} The teacher can open it in Smartschool.',
      );
    }
  });
  final downloaded = watch.elapsedMilliseconds;

  final name = known?.name ?? file.fileName;
  final title = _title(id, known, name: name, size: file.bytes.length);
  final content = await readDocument(file.bytes, name: name);
  log(
    'read_intradesk_file: ${file.bytes.length} bytes '
    '(${known == null ? 'not in the index' : 'in the index'}, size '
    '${file.announcedSize == null ? 'not announced' : 'announced'}, '
    'type ${file.contentType ?? 'none'}, file name '
    '${file.fileName == null ? 'not given' : 'given'}) downloaded in '
    '$downloaded ms; ${_describeForLog(content)} in '
    '${watch.elapsedMilliseconds - downloaded} ms',
  );

  switch (content) {
    case DocumentText():
      return CallToolResult(
        content: [TextContent(text: _text(title, content))],
      );
    case DocumentImage(:final bytes, :final mimeType, :final notes):
      return CallToolResult(
        content: [
          TextContent(
            text: [
              '$title: image ($mimeType).',
              for (final note in notes) 'Note: $note',
            ].join('\n'),
          ),
          ImageContent(data: base64Encode(bytes), mimeType: mimeType),
        ],
      );
    case UnreadableDocument(:final reason):
      throw ToolError('$title: $reason');
  }
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
      '${_title(id, known, size: size)} is too large to open here: '
      '${_limit()} The teacher can open it in Smartschool.',
    );
  }
  if (unreadableExtensionReason(fileExtension(known.name)) case final reason?) {
    throw ToolError('${_title(id, known, size: known.size)}: $reason');
  }
}

String _limit() =>
    'files up to ${formatFileSize(maxIntradeskFileBytes)} can be read.';

/// `Intradesk file <path> (id …, 178 KB, changed 2024-08-29)`, with what is
/// known about the file.
String _title(String id, IntradeskItem? known, {String? name, int? size}) {
  final what = known?.path ?? name;
  final details = [
    'id $id',
    if (size ?? known?.size case final size?) formatFileSize(size),
    if (known?.changed case final changed?)
      'changed ${formatIntradeskDate(changed)}',
    if (known?.confidential ?? false) 'confidential',
  ];
  return 'Intradesk file ${what == null ? '' : '$what '}'
      '(${details.join(', ')})';
}

/// The result for [document]: a line saying what it is, a blank line, the
/// text, and notes.
String _text(String title, DocumentText document) {
  final length = document.text.length;
  final summary = [
    document.format.label,
    ?document.parts,
    if (length == 0)
      'no text'
    else if (!document.truncated)
      '$length characters'
    else if (document.fullLength case final full?)
      'the first $length of $full characters'
    else
      'the first $length characters',
  ].join(', ');
  final notes = [
    if (document.truncated)
      'the text is cut off here, after $length '
          '${document.fullLength == null ? 'characters; the rest of the file was not read' : 'of ${document.fullLength} characters'}.',
    if (length == 0) 'it has no text: it may hold only pictures.',
    ...document.notes,
  ];
  return [
    '$title: $summary.',
    if (length > 0) '\n${document.text}',
    if (notes.isNotEmpty) '',
    for (final note in notes) 'Note: ${_capitalise(note)}',
  ].join('\n');
}

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// [content] for the log: format, sizes and counts, never text or names.
String _describeForLog(DocumentContent content) => switch (content) {
  DocumentText(:final format, :final text, :final truncated, :final parts) =>
    '${format.name}${parts == null ? '' : ' ($parts)'}, ${text.length} '
        'characters${truncated ? ' (cut off)' : ''}',
  DocumentImage(:final bytes, :final mimeType, :final notes) =>
    'image $mimeType, ${bytes.length} bytes'
        '${notes.isEmpty ? '' : ' (scaled down)'}',
  UnreadableDocument() => 'unreadable',
};
