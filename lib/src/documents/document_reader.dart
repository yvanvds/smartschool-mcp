import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../messages/html_to_text.dart';
import 'document_content.dart';
import 'docx_text.dart';
import 'image_content.dart';
import 'office_package.dart';
import 'pdf_text.dart';
import 'plain_text.dart';
import 'pptx_text.dart';
import 'xlsx_text.dart';

export 'document_content.dart';

/// Text longer than this many characters is cut off, with a note. Claude
/// Desktop accepts tool results of up to about 150,000 characters.
const defaultMaxDocumentChars = 100000;

/// How long [readDocument] may take; after that it gives up on the file.
const documentReadTimeout = Duration(seconds: 45);

/// How long the PDF reader goes on to the next page; it then returns the
/// pages it has, with a note.
const pdfTimeLimit = Duration(seconds: 30);

/// The formats [readDocument] reads, for messages.
const readableFormats =
    'Word (.docx), Excel (.xlsx), PowerPoint (.pptx), PDF, text (.txt, '
    '.csv, .md), web pages (.html) and images (.png, .jpg, .gif, .webp)';

/// The file extensions of the formats [readDocument] reads.
const readableExtensions = {
  ..._wordExtensions,
  ..._excelExtensions,
  ..._powerPointExtensions,
  'pdf',
  ..._textExtensions,
  ..._htmlExtensions,
  ..._imageExtensions,
};

const _wordExtensions = {'docx', 'docm', 'dotx', 'dotm'};
const _excelExtensions = {'xlsx', 'xlsm', 'xltx', 'xltm'};
const _powerPointExtensions = {'pptx', 'pptm', 'ppsx', 'ppsm', 'potx', 'potm'};
const _textExtensions = {'txt', 'csv', 'tsv', 'md'};
const _htmlExtensions = {'html', 'htm'};
const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

/// The extension of the file name [name] in lowercase, without the dot
/// (`docx`); empty when it has none. What follows the last dot counts only
/// when it looks like an extension (up to 5 letters and digits, at least
/// one letter), so `Info. Rapport` and `versie 3.1` have none.
String fileExtension(String? name) {
  if (name == null) return '';
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  final extension = name.substring(dot + 1).toLowerCase();
  return _extension.hasMatch(extension) ? extension : '';
}

final _extension = RegExp(r'^(?=.*[a-z])[a-z0-9]{1,5}$');

/// Why a file with [extension] (lowercase, without the dot) cannot be read;
/// null when it can, or when it has no extension (then its content
/// decides).
///
/// Lets a caller refuse a file before downloading it.
String? unreadableExtensionReason(String extension) {
  if (extension.isEmpty || readableExtensions.contains(extension)) return null;
  if (_legacyFormats[extension] case final format?) {
    return 'It is in the old $format format (.$extension), which cannot be '
        'read: only $readableFormats can. Saved in the new format '
        '(.${_newExtensions[format]}) it can be read.';
  }
  if (_openDocumentExtensions.contains(extension)) {
    return _openDocumentReason(extension);
  }
  return 'Files of type .$extension cannot be read: only $readableFormats '
      'can.';
}

const _openDocumentExtensions = {'odt', 'ods', 'odp', 'odg'};

String _openDocumentReason(String extension) =>
    'It is an OpenDocument file'
    '${_openDocumentExtensions.contains(extension) ? ' (.$extension)' : ''}, '
    'which cannot be read: only $readableFormats can.';

const _legacyFormats = {
  'doc': 'Word',
  'dot': 'Word',
  'xls': 'Excel',
  'xlt': 'Excel',
  'ppt': 'PowerPoint',
  'pps': 'PowerPoint',
  'pot': 'PowerPoint',
};
const _newExtensions = {'Word': 'docx', 'Excel': 'xlsx', 'PowerPoint': 'pptx'};

/// Reads [bytes], the content of a file called [name], as text or as an
/// image for Claude; see [readDocumentNow].
///
/// Runs in a separate isolate, so the server keeps answering other calls
/// meanwhile, and gives up after [timeout] (the isolate is stopped).
Future<DocumentContent> readDocument(
  Uint8List bytes, {
  String? name,
  int maxChars = defaultMaxDocumentChars,
  Duration timeout = documentReadTimeout,
}) async {
  final port = ReceivePort();
  try {
    final isolate = await Isolate.spawn(
      _readInIsolate,
      (port.sendPort, bytes, name, maxChars),
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'readDocument',
    );
    final Object? message;
    try {
      message = await port.first.timeout(timeout);
    } on TimeoutException {
      isolate.kill(priority: Isolate.immediate);
      return UnreadableDocument(
        'Reading it took too long (more than ${timeout.inSeconds} seconds).',
      );
    }
    return switch (message) {
      final DocumentContent content => content,
      [final error, final stack] => throw StateError(
        'reading the document failed: $error\n$stack',
      ),
      _ => throw StateError('reading the document stopped without a result'),
    };
  } finally {
    port.close();
  }
}

void _readInIsolate((SendPort, Uint8List, String?, int) message) {
  final (port, bytes, name, maxChars) = message;
  // stdout carries the MCP protocol; a stray print from a dependency must go
  // to stderr, as in the main isolate.
  final content = runZoned(
    () => readDocumentNow(bytes, name: name, maxChars: maxChars),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => stderr.writeln(line),
    ),
  );
  Isolate.exit(port, content);
}

/// Reads [bytes], the content of a file called [name], as text or as an
/// image for Claude.
///
/// The content decides the format, not the name: a PDF, a Word, Excel or
/// PowerPoint file (Office Open XML), or a PNG, JPEG, GIF or WebP image.
/// Only a text file is recognised by its extension (`.txt`, `.csv`, `.tsv`,
/// `.md`, `.html`, `.htm`, or none). Text longer than [maxChars] is cut
/// off. Anything else is an [UnreadableDocument] saying why.
DocumentContent readDocumentNow(
  Uint8List bytes, {
  String? name,
  int maxChars = defaultMaxDocumentChars,
  Duration pdfTimeLimit = pdfTimeLimit,
}) {
  final extension = fileExtension(name);
  try {
    return _read(bytes, extension, maxChars, pdfTimeLimit);
  } on UnreadableDocumentException catch (error) {
    return UnreadableDocument(error.reason);
  }
}

DocumentContent _read(
  Uint8List bytes,
  String extension,
  int maxChars,
  Duration pdfTimeLimit,
) {
  if (_isPdf(bytes)) {
    final pdf = _guard(
      'a PDF',
      () => pdfText(bytes, maxChars: maxChars, timeLimit: pdfTimeLimit),
    );
    return _text(
      DocumentFormat.pdf,
      pdf.text,
      maxChars,
      parts: _count(pdf.pages, 'page'),
      complete: pdf.complete,
      notes: pdf.notes,
    );
  }
  if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
    return _office(bytes, extension, maxChars);
  }
  if (_startsWith(bytes, const [0xD0, 0xCF, 0x11, 0xE0])) {
    // An OLE2 compound file: .doc, .xls, .ppt, or an Office file protected
    // by a password.
    throw UnreadableDocumentException(
      _legacyFormats.containsKey(extension)
          ? unreadableExtensionReason(extension)!
          : 'It is in an old Office format (.doc, .xls, .ppt) or protected '
                'by a password, which cannot be read: only $readableFormats '
                'can.',
    );
  }
  if (_imageType(bytes) case final mimeType?) {
    return imageContent(bytes, mimeType);
  }
  if (_textExtensions.contains(extension) ||
      (extension.isEmpty && looksLikeText(bytes))) {
    return _text(DocumentFormat.text, decodeText(bytes), maxChars);
  }
  if (_htmlExtensions.contains(extension)) {
    return _text(DocumentFormat.html, htmlToText(decodeText(bytes)), maxChars);
  }
  if (_expected(extension) case final what?) {
    throw UnreadableDocumentException(
      'It could not be read as $what: the file seems damaged.',
    );
  }
  throw UnreadableDocumentException(
    unreadableExtensionReason(extension) ??
        'Its content is not in a format that can be read: only '
            '$readableFormats can.',
  );
}

/// What a file with [extension] should have been, when that is a format
/// recognised by its content.
String? _expected(String extension) => switch (extension) {
  _ when _wordExtensions.contains(extension) => 'a Word document',
  _ when _excelExtensions.contains(extension) => 'an Excel workbook',
  _ when _powerPointExtensions.contains(extension) =>
    'a PowerPoint presentation',
  'pdf' => 'a PDF',
  _ when _imageExtensions.contains(extension) => 'an image',
  _ => null,
};

DocumentContent _office(Uint8List bytes, String extension, int maxChars) {
  final package = OfficePackage.open(
    bytes,
    what: _expected(extension) ?? 'an Office document',
  );
  var main = package.mainPart;
  if (main == null || !package.has(main)) {
    main = const [
      'word/document.xml',
      'xl/workbook.xml',
      'ppt/presentation.xml',
    ].where(package.has).firstOrNull;
  }
  switch (main?.split('/').first) {
    case 'word':
      final text = _guard('a Word document', () => docxText(package, main!));
      return _text(DocumentFormat.docx, text, maxChars);
    case 'xl':
      final workbook = _guard(
        'an Excel workbook',
        () => xlsxText(package, main!, maxChars: maxChars),
      );
      return _text(
        DocumentFormat.xlsx,
        workbook.text,
        maxChars,
        parts: _count(workbook.sheets, 'sheet'),
        complete: workbook.complete,
      );
    case 'ppt':
      final presentation = _guard(
        'a PowerPoint presentation',
        () => pptxText(package, main!),
      );
      return _text(
        DocumentFormat.pptx,
        presentation.text,
        maxChars,
        parts: _count(presentation.slides, 'slide'),
      );
  }
  if (package.has('mimetype') || _openDocumentExtensions.contains(extension)) {
    throw UnreadableDocumentException(_openDocumentReason(extension));
  }
  if (_expected(extension) case final what?) {
    throw UnreadableDocumentException(
      'It could not be read as $what: the file seems damaged.',
    );
  }
  throw UnreadableDocumentException(
    'It is a zip archive, which cannot be read: only $readableFormats can.',
  );
}

/// Runs [read], a reader for [what]; an error other than an
/// [UnreadableDocumentException] (a file the reader does not handle) is
/// logged and reported as a damaged file.
T _guard<T>(String what, T Function() read) {
  try {
    return read();
  } on UnreadableDocumentException {
    rethrow;
  } catch (error, stackTrace) {
    stderr.writeln(
      '[smartschool_mcp] reading $what failed: ${error.runtimeType}: '
      '$error\n$stackTrace',
    );
    throw UnreadableDocumentException(
      'It could not be read as $what: the file seems damaged, or uses '
      'something the reader does not handle.',
    );
  }
}

DocumentText _text(
  DocumentFormat format,
  String text,
  int maxChars, {
  String? parts,
  bool complete = true,
  List<String> notes = const [],
}) {
  final truncated = text.length > maxChars;
  return DocumentText(
    format: format,
    text: cutText(text, maxChars),
    parts: parts,
    truncated: truncated,
    fullLength: truncated && complete ? text.length : null,
    notes: notes,
  );
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

bool _isPdf(Uint8List bytes) {
  // The header may follow some junk, within the first kilobyte.
  final end = bytes.length < 1024 ? bytes.length : 1024;
  for (var i = 0; i + 5 <= end; i++) {
    if (bytes[i] == 0x25 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x44 &&
        bytes[i + 3] == 0x46 &&
        bytes[i + 4] == 0x2D) {
      return true;
    }
  }
  return false;
}

String? _imageType(Uint8List bytes) {
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) {
    return 'image/png';
  }
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
