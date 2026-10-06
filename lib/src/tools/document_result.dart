import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../documents/document_reader.dart';
import 'server_tool.dart';

// What the tools that read a file from Smartschool (`read_intradesk_file`,
// `read_lesfiche_attachment`) have in common: reading the download, the
// result for what `readDocument` made of it, and its log line.

/// All of [download]'s content. Its stream ends with a
/// [SmartschoolDownloadTooLargeError] once more than the allowed bytes came
/// in, or a [SmartschoolConnectionError] when the connection fails halfway;
/// the library then stops the transfer. Read inside the session's run, so
/// that a failed connection is reported like any other.
Future<Uint8List> readWholeDownload(SmartschoolDownload download) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in download.stream) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

/// The result for [content], what the file [title] holds: for text, a line
/// saying what it is, a blank line, the text, and notes; for an image, a
/// line and the image. A file that cannot be read is a [ToolError] with the
/// reason.
CallToolResult documentResult(String title, DocumentContent content) {
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
String describeDocumentForLog(DocumentContent content) => switch (content) {
  DocumentText(:final format, :final text, :final truncated, :final parts) =>
    '${format.name}${parts == null ? '' : ' ($parts)'}, ${text.length} '
        'characters${truncated ? ' (cut off)' : ''}',
  DocumentImage(:final bytes, :final mimeType, :final notes) =>
    'image $mimeType, ${bytes.length} bytes'
        '${notes.isEmpty ? '' : ' (scaled down)'}',
  UnreadableDocument() => 'unreadable',
};
