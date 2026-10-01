/// The document reader behind `read_intradesk_file`: every format it reads,
/// from small sample files made in `support/sample_documents.dart`, and the
/// ones it refuses.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:smartschool_mcp/src/documents/document_reader.dart';
import 'package:smartschool_mcp/src/documents/image_content.dart';
import 'package:smartschool_mcp/src/documents/plain_text.dart';
import 'package:test/test.dart';

import 'support/sample_documents.dart';

void main() {
  DocumentText text(
    Uint8List bytes, {
    String? name,
    int maxChars = defaultMaxDocumentChars,
    Duration pdfTimeLimit = pdfTimeLimit,
  }) {
    final content = readDocumentNow(
      bytes,
      name: name,
      maxChars: maxChars,
      pdfTimeLimit: pdfTimeLimit,
    );
    if (content is UnreadableDocument) fail('unreadable: ${content.reason}');
    return content as DocumentText;
  }

  String unreadable(Uint8List bytes, {String? name}) {
    final content = readDocumentNow(bytes, name: name);
    expect(content, isA<UnreadableDocument>());
    return (content as UnreadableDocument).reason;
  }

  group('Word', () {
    test('headings, paragraphs, list items, a table and a text box, without '
        'deleted text, field codes or the fallback copy', () {
      final document = text(sampleDocx(), name: 'uitstap.docx');

      expect(document.format, DocumentFormat.docx);
      expect(document.text, sampleDocxText);
      expect(document.parts, isNull);
      expect(document.truncated, isFalse);
    });

    test('the content decides, not the name', () {
      expect(text(sampleDocx()).text, sampleDocxText);
      expect(text(sampleDocx(), name: 'verslag.pdf').text, sampleDocxText);
    });

    test('a document without text says so', () {
      expect(text(docxWithParagraphs(['', ' '])).text, isEmpty);
    });

    test('text over the budget is cut off at a line break, with the full '
        'length', () {
      final paragraphs = [
        for (var i = 1; i <= 100; i++) 'Paragraaf $i met wat tekst erin.',
      ];
      final full = paragraphs.join('\n');

      final document = text(docxWithParagraphs(paragraphs), maxChars: 1000);

      expect(document.truncated, isTrue);
      expect(document.fullLength, full.length);
      expect(document.text.length, lessThanOrEqualTo(1000));
      expect(document.text.length, greaterThan(900));
      expect(full, startsWith('${document.text}\n'));
    });
  });

  group('Excel', () {
    test('every sheet in the workbook order under its name, with shared and '
        'inline strings, numbers, percentages, booleans, errors, dates and '
        'times', () {
      final workbook = text(sampleXlsx(), name: 'punten.xlsx');

      expect(workbook.format, DocumentFormat.xlsx);
      expect(workbook.text, sampleXlsxText);
      expect(workbook.parts, '3 sheets');
      expect(workbook.truncated, isFalse);
    });

    test('a large sheet stops being read at the budget; the full length is '
        'not known', () {
      final workbook = text(xlsxWithRows(5000), maxChars: 2000);

      expect(workbook.truncated, isTrue);
      expect(workbook.fullLength, isNull);
      expect(workbook.text, startsWith('## Sheet: Blad1\n10 | 11 | 12 | 13 |'));
      expect(workbook.text.length, lessThanOrEqualTo(2000));
    });
  });

  group('PowerPoint', () {
    test('every slide in the presentation order, with its notes, tables and '
        'hidden mark', () {
      final presentation = text(samplePptx(), name: 'infoavond.pptx');

      expect(presentation.format, DocumentFormat.pptx);
      expect(presentation.text, samplePptxText);
      expect(presentation.parts, '3 slides');
    });
  });

  group('PDF', () {
    test('the text of every page under its number', () {
      final pdf = text(
        samplePdf([
          ['Uitstap naar Brugge', 'Vertrek om 8.30 uur, café aan de markt.'],
          [],
          ['Kostprijs: 12 euro (inclusief bus)'],
        ]),
        name: 'uitstap.pdf',
      );

      expect(pdf.format, DocumentFormat.pdf);
      expect(
        pdf.text,
        '## Page 1\n'
        'Uitstap naar Brugge\n'
        'Vertrek om 8.30 uur, café aan de markt.\n'
        '\n'
        '## Page 3\n'
        'Kostprijs: 12 euro (inclusief bus)',
      );
      expect(pdf.parts, '3 pages');
      expect(pdf.notes, isEmpty);
    });

    test('a PDF without text is a scan', () {
      expect(
        unreadable(samplePdf([[], []]), name: 'scan.pdf'),
        'The PDF has no text that can be read: it is probably a scan '
        '(pictures of pages).',
      );
    });

    test('a damaged PDF says so', () {
      expect(
        unreadable(
          Uint8List.fromList(latin1.encode('%PDF-1.4\nnot really a pdf')),
          name: 'kapot.pdf',
        ),
        'It could not be read as a PDF: the file seems damaged.',
      );
    });

    test('stops at the budget, and after the time limit with a note', () {
      final pages = [
        for (var i = 1; i <= 20; i++)
          [for (var line = 1; line <= 10; line++) 'Pagina $i, regel $line'],
      ];

      final cut = text(samplePdf(pages), maxChars: 500);
      expect(cut.truncated, isTrue);
      expect(cut.fullLength, isNull);
      expect(cut.text, startsWith('## Page 1\nPagina 1, regel 1\n'));

      final slow = text(samplePdf(pages), pdfTimeLimit: Duration.zero);
      expect(slow.truncated, isFalse);
      expect(slow.text, startsWith('## Page 1\n'));
      expect(slow.text, isNot(contains('## Page 2')));
      expect(slow.notes, [
        'Only page 1 of 20 was read: reading the rest took too long.',
      ]);
    });
  });

  group('text', () {
    test('UTF-8 with or without a byte order mark, UTF-16, and Windows-1252 '
        'from Excel', () {
      final expected = 'Naam;Bedrag\nAn;€ 12,50\nBéatrice;7';
      final crlf = expected.replaceAll('\n', '\r\n');
      for (final bytes in [
        utf8.encode(crlf),
        [0xEF, 0xBB, 0xBF, ...utf8.encode(crlf)],
        [
          0xFF,
          0xFE,
          for (final unit in crlf.codeUnits) ...[unit & 0xFF, unit >> 8],
        ],
        [for (final unit in crlf.codeUnits) unit == 0x20AC ? 0x80 : unit],
      ]) {
        final document = text(Uint8List.fromList(bytes), name: 'lijst.csv');
        expect(document.format, DocumentFormat.text);
        expect(document.text, expected);
      }
    });

    test('.txt and .md as they are, .html through the HTML converter', () {
      final notes = utf8.encode('# Notities\n\n- punt 1\n- punt 2\n');
      expect(
        text(Uint8List.fromList(notes), name: 'notities.md').text,
        '# Notities\n\n- punt 1\n- punt 2\n',
      );
      expect(
        text(Uint8List.fromList(notes), name: 'a.TXT').format,
        DocumentFormat.text,
      );

      final page = text(
        Uint8List.fromList(
          utf8.encode(
            '<html><head><title>x</title></head><body><h1>Reglement</h1>'
            '<p>Artikel&nbsp;1: <b>stipt</b> zijn.</p></body></html>',
          ),
        ),
        name: 'reglement.html',
      );
      expect(page.format, DocumentFormat.html);
      expect(page.text, '# Reglement\n\nArtikel 1: stipt zijn.');
    });

    test('a file without an extension is text when it looks like text', () {
      expect(
        text(Uint8List.fromList(utf8.encode('Gewoon tekst.\n'))).text,
        'Gewoon tekst.\n',
      );
      expect(
        unreadable(Uint8List.fromList([0, 1, 2, 3, 4, 250, 251])),
        startsWith(
          'Its content is not in a format that can be read: only '
          'Word (.docx), ',
        ),
      );
    });

    test('cutText cuts at a line break near the end, never inside a '
        'surrogate pair', () {
      expect(cutText('abc', 5), 'abc');
      expect(cutText('${'a' * 95}\n${'b' * 20}', 100), 'a' * 95);
      expect(
        cutText('${'a' * 50}\n${'b' * 60}', 100),
        '${'a' * 50}\n${'b' * 49}',
      );
      expect(cutText('${'a' * 99}😀', 100), 'a' * 99);
    });
  });

  group('images', () {
    test('a small image is passed on as it is', () {
      final png = samplePng(8, 6);
      final content = readDocumentNow(png, name: 'logo.png');

      expect(content, isA<DocumentImage>());
      final image = content as DocumentImage;
      expect(image.mimeType, 'image/png');
      expect(image.bytes, png);
      expect(image.notes, isEmpty);
    });

    test('a large image is scaled down to a JPEG under the limit, '
        'transparency on white', () {
      final png = samplePng(3000, 2000, alpha: true, compress: false);
      expect(png.length, greaterThan(maxImageBytes));

      final content = readDocumentNow(png, name: 'foto.png');

      expect(content, isA<DocumentImage>());
      final image = content as DocumentImage;
      expect(image.mimeType, 'image/jpeg');
      expect(image.bytes.length, lessThanOrEqualTo(maxImageBytes));
      final decoded = img.decodeJpg(image.bytes)!;
      expect((decoded.width, decoded.height), (1568, 1045));
      // The transparent left half is white now.
      final pixel = decoded.getPixel(10, 10);
      expect([pixel.r, pixel.g, pixel.b], everyElement(greaterThan(240)));
      expect(image.notes, [
        'The image (3000×2000 pixels) was scaled down to 1568×1045 pixels '
            'to fit.',
      ]);
    });

    test('a damaged image says so', () {
      final png = samplePng(3000, 2000, compress: false);
      expect(
        unreadable(Uint8List.sublistView(png, 0, 800 * 1024), name: 'x.png'),
        'It could not be read as an image: the file seems damaged.',
      );
    });
  });

  test('fileExtension takes only what looks like an extension', () {
    expect(fileExtension('Uitstap.DOCX'), 'docx');
    expect(fileExtension('verslag.v2'), 'v2');
    expect(fileExtension('Info. Rapport'), '');
    expect(fileExtension('versie 3.1'), '');
    expect(fileExtension('.gitignore'), '');
    expect(fileExtension('geen extensie'), '');
    expect(fileExtension('punt.'), '');
    expect(fileExtension(null), '');
  });

  group('refused', () {
    test('old Office files, by their extension, before or after '
        'downloading', () {
      expect(
        unreadableExtensionReason('doc'),
        'It is in the old Word format (.doc), which cannot be read: only '
        'Word (.docx), Excel (.xlsx), PowerPoint (.pptx), PDF, text (.txt, '
        '.csv, .md), web pages (.html) and images (.png, .jpg, .gif, .webp) '
        'can. Saved in the new format (.docx) it can be read.',
      );
      expect(
        unreadable(sampleOle2(), name: 'oud.xls'),
        contains('the old Excel format (.xls)'),
      );
      expect(
        unreadable(sampleOle2(), name: 'beveiligd.docx'),
        startsWith(
          'It is in an old Office format (.doc, .xls, .ppt) or '
          'protected by a password, which cannot be read: only ',
        ),
      );
    });

    test('other formats', () {
      expect(unreadableExtensionReason('docx'), isNull);
      expect(unreadableExtensionReason('JPG'.toLowerCase()), isNull);
      expect(unreadableExtensionReason(''), isNull);
      expect(
        unreadableExtensionReason('mp4'),
        startsWith('Files of type .mp4 cannot be read: only Word'),
      );
      expect(
        unreadableExtensionReason('odt'),
        startsWith('It is an OpenDocument file (.odt), which cannot be'),
      );
      expect(
        unreadable(
          zipOf({'mimetype': 'application/vnd.oasis.opendocument.text'}),
        ),
        startsWith('It is an OpenDocument file, which cannot be read'),
      );
      expect(
        unreadable(zipOf({'foto1.jpg': 'x'}), name: 'fotos.zip'),
        startsWith('It is a zip archive, which cannot be read: only '),
      );
      expect(
        unreadable(
          Uint8List.fromList(utf8.encode('<html>login</html>')),
          name: 'verslag.docx',
        ),
        'It could not be read as a Word document: the file seems damaged.',
      );
      expect(
        unreadable(
          zipOf({'word/document.xml': '<w:document'}),
          name: 'verslag.docx',
        ),
        'It could not be read as a Word document: the file seems damaged.',
      );
    });
  });

  group('readDocument', () {
    test('reads in a separate isolate', () async {
      final content = await readDocument(sampleDocx(), name: 'uitstap.docx');

      expect((content as DocumentText).text, sampleDocxText);
    });

    test('gives up after the timeout', () async {
      final content = await readDocument(
        samplePdf([
          ['Pagina 1'],
        ]),
        timeout: Duration.zero,
      );

      expect(
        (content as UnreadableDocument).reason,
        'Reading it took too long (more than 0 seconds).',
      );
    });
  });
}
