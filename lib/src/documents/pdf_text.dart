import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'document_content.dart';

/// The text of the PDF [bytes], a `## Page n` line before the text of each
/// page that has text, in reading order.
///
/// Uses the pure-Dart text extraction of `pdf_graphics`, which reads the
/// fonts' encodings and Unicode maps. Stops once the text is longer than
/// [maxChars], and after [timeLimit] (between pages), so a large PDF cannot
/// keep the server busy for long.
///
/// Throws an [UnreadableDocumentException] for a PDF that cannot be opened
/// (damaged, or protected by a password) and for one without any text (a
/// scan).
({String text, int pages, bool complete, List<String> notes}) pdfText(
  Uint8List bytes, {
  required int maxChars,
  required Duration timeLimit,
}) {
  final PdfDocument document;
  final int pages;
  try {
    document = PdfDocument.open(bytes);
    pages = document.pageCount;
  } on CosPasswordException {
    throw const UnreadableDocumentException(
      'It is a PDF protected by a password, which cannot be read.',
    );
  } catch (_) {
    throw const UnreadableDocumentException(
      'It could not be read as a PDF: the file seems damaged.',
    );
  }

  final watch = Stopwatch()..start();
  final out = StringBuffer();
  final failed = <int>[];
  final notes = <String>[];
  var complete = true;
  for (var page = 1; page <= pages; page++) {
    if (out.length > maxChars) {
      complete = false;
      break;
    }
    if (page > 1 && watch.elapsed > timeLimit) {
      complete = false;
      notes.add(
        '${page == 2 ? 'Only page 1' : 'Only pages 1 to ${page - 1}'} of '
        '$pages ${page == 2 ? 'was' : 'were'} read: reading the rest took '
        'too long.',
      );
      break;
    }
    final String text;
    try {
      text = PdfTextExtractor.extract(document, page - 1).text.trim();
    } catch (_) {
      failed.add(page);
      continue;
    }
    if (text.isEmpty) continue;
    if (out.isNotEmpty) out.write('\n\n');
    out.write('## Page $page\n$text');
  }
  if (failed.isNotEmpty) {
    notes.add(
      failed.length == 1
          ? 'Page ${failed.single} could not be read.'
          : 'Pages ${failed.join(', ')} could not be read.',
    );
  }
  if (out.isEmpty && complete) {
    throw UnreadableDocumentException(
      failed.length == pages
          ? 'It could not be read as a PDF: the file seems damaged.'
          : 'The PDF has no text that can be read: it is probably a scan '
                '(pictures of pages).',
    );
  }
  return (text: out.toString(), pages: pages, complete: complete, notes: notes);
}
