import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// Small sample files of every format `readDocument` reads, made up for the
/// tests (no real school documents), with the text each should give.

/// A zip of [parts] (path to text).
Uint8List zipOf(Map<String, String> parts) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in parts.entries) {
    archive.add(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  return ZipEncoder().encodeBytes(archive);
}

const _xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _relsNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _officeRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _s = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _mc = 'http://schemas.openxmlformats.org/markup-compatibility/2006';

String _rels(List<(String id, String type, String target)> rels) =>
    '$_xml<Relationships xmlns="$_relsNs">'
    '${[for (final (id, type, target) in rels) '<Relationship Id="$id" Type="$_officeRel/$type" Target="$target"${target.startsWith('http') ? ' TargetMode="External"' : ''}/>'].join()}'
    '</Relationships>';

String _contentTypes(String mainPart, String mainType) =>
    '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
    'content-types"><Default Extension="rels" ContentType="application/'
    'vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" '
    'ContentType="application/xml"/><Override PartName="/$mainPart" '
    'ContentType="$mainType"/></Types>';

/// A Word document with a title, a heading, list items, a tracked change, a
/// field, a hyperlink, a table, a text box (with its VML fallback copy) and
/// a content control; it reads as [sampleDocxText].
Uint8List sampleDocx() => zipOf({
  '[Content_Types].xml': _contentTypes(
    'word/document.xml',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.'
        'document.main+xml',
  ),
  '_rels/.rels': _rels([('rId1', 'officeDocument', 'word/document.xml')]),
  'word/_rels/document.xml.rels': _rels([
    ('rId1', 'styles', 'styles.xml'),
    ('rId2', 'hyperlink', 'https://www.example.com/uitstap'),
  ]),
  'word/styles.xml':
      '$_xml<w:styles xmlns:w="$_w">'
      '<w:style w:type="paragraph" w:styleId="Titel"><w:name w:val="Title"/>'
      '</w:style>'
      '<w:style w:type="paragraph" w:styleId="Kop1">'
      '<w:name w:val="heading 1"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Kop2">'
      '<w:name w:val="heading 2"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Lijstalinea">'
      '<w:name w:val="List Paragraph"/></w:style>'
      '</w:styles>',
  'word/document.xml':
      '$_xml<w:document xmlns:w="$_w" xmlns:mc="$_mc" '
      'xmlns:r="$_officeRel" '
      'xmlns:wps="http://schemas.microsoft.com/office/word/2010/'
      'wordprocessingShape" xmlns:v="urn:schemas-microsoft-com:vml">'
      '<w:body>'
      '<w:p><w:pPr><w:pStyle w:val="Titel"/></w:pPr>'
      '<w:r><w:t>Uitstap naar Brugge</w:t></w:r></w:p>'
      '<w:p><w:r><w:t xml:space="preserve">Vertrek om </w:t></w:r>'
      '<w:r><w:rPr><w:b/></w:rPr><w:t>8.30 uur</w:t></w:r>'
      '<w:r><w:tab/><w:t>aan de schoolpoort.</w:t></w:r></w:p>'
      '<w:p/>'
      '<w:p><w:pPr><w:pStyle w:val="Kop1"/><w:tabs><w:tab w:val="left" '
      'w:pos="720"/></w:tabs></w:pPr><w:r><w:t>Programma</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Lijstalinea"/><w:numPr>'
      '<w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>'
      '<w:r><w:t>Begijnhof</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/>'
      '</w:numPr></w:pPr><w:r><w:t>Belfort &amp; Markt</w:t></w:r></w:p>'
      '<w:p><w:r><w:t xml:space="preserve">Kostprijs: </w:t></w:r>'
      '<w:del w:id="1" w:author="x"><w:r><w:delText>10</w:delText></w:r>'
      '</w:del><w:ins w:id="2" w:author="x"><w:r><w:t>12</w:t></w:r></w:ins>'
      '<w:r><w:t xml:space="preserve"> euro</w:t></w:r>'
      '<w:r><w:br/><w:t>Betalen via de schoolrekening.</w:t></w:r></w:p>'
      '<w:p><w:r><w:t xml:space="preserve">Meer info op </w:t></w:r>'
      '<w:hyperlink r:id="rId2"><w:r><w:t>de website</w:t></w:r>'
      '</w:hyperlink><w:r><w:t xml:space="preserve"> (pagina </w:t></w:r>'
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>'
      '<w:r><w:t>).</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Kop2"/></w:pPr>'
      '<w:r><w:t>Groepen</w:t></w:r></w:p>'
      '<w:tbl><w:tblPr/>'
      '<w:tr><w:tc><w:p><w:r><w:t>Klas</w:t></w:r></w:p></w:tc>'
      '<w:tc><w:p><w:r><w:t>Begeleider</w:t></w:r></w:p></w:tc></w:tr>'
      '<w:tr><w:tc><w:p><w:r><w:t>3A</w:t></w:r></w:p></w:tc>'
      '<w:tc><w:p><w:r><w:t>Mevr. Peeters</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>Dhr. Janssens</w:t></w:r></w:p></w:tc></w:tr>'
      '<w:tr><w:tc><w:p/></w:tc><w:tc><w:p/></w:tc></w:tr>'
      '</w:tbl>'
      '<w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps">'
      '<w:drawing><wps:wsp><wps:txbx><w:txbxContent><w:p><w:r>'
      '<w:t>Vergeet je lunchpakket niet!</w:t></w:r></w:p></w:txbxContent>'
      '</wps:txbx></wps:wsp></w:drawing></mc:Choice><mc:Fallback><w:pict>'
      '<v:shape><v:textbox><w:txbxContent><w:p><w:r>'
      '<w:t>Vergeet je lunchpakket niet!</w:t></w:r></w:p></w:txbxContent>'
      '</v:textbox></v:shape></w:pict></mc:Fallback></mc:AlternateContent>'
      '</w:r><w:r><w:t>Tot dan.</w:t></w:r></w:p>'
      '<w:sdt><w:sdtPr/><w:sdtContent><w:p><w:r>'
      '<w:t>Handtekening ouder:</w:t></w:r></w:p></w:sdtContent></w:sdt>'
      '<w:sectPr/>'
      '</w:body></w:document>',
});

const sampleDocxText =
    '# Uitstap naar Brugge\n'
    'Vertrek om 8.30 uur aan de schoolpoort.\n'
    '\n'
    '# Programma\n'
    '- Begijnhof\n'
    '- Belfort & Markt\n'
    'Kostprijs: 12 euro\n'
    'Betalen via de schoolrekening.\n'
    'Meer info op de website (pagina 1).\n'
    '\n'
    '## Groepen\n'
    'Klas | Begeleider\n'
    '3A | Mevr. Peeters Dhr. Janssens\n'
    'Tot dan.\n'
    'Vergeet je lunchpakket niet!\n'
    'Handtekening ouder:';

/// A Word document with just [paragraphs].
Uint8List docxWithParagraphs(Iterable<String> paragraphs) => zipOf({
  '_rels/.rels': _rels([('rId1', 'officeDocument', 'word/document.xml')]),
  'word/document.xml':
      '$_xml<w:document xmlns:w="$_w"><w:body>'
      '${[for (final text in paragraphs) '<w:p><w:r><w:t>${const HtmlEscape().convert(text)}</w:t></w:r></w:p>'].join()}'
      '</w:body></w:document>',
});

/// An Excel workbook with three sheets (listed out of their file order, one
/// hidden), shared and inline strings (rich text, a phonetic hint), numbers
/// with floating-point noise, percentages, booleans, a formula, an error,
/// dates and a time, and cells far apart; it reads as [sampleXlsxText].
Uint8List sampleXlsx() => zipOf({
  '[Content_Types].xml': _contentTypes(
    'xl/workbook.xml',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.'
        'main+xml',
  ),
  '_rels/.rels': _rels([('rId1', 'officeDocument', 'xl/workbook.xml')]),
  'xl/workbook.xml':
      '$_xml<workbook xmlns="$_s" xmlns:r="$_officeRel"><workbookPr/>'
      '<sheets>'
      '<sheet name="Punten" sheetId="1" r:id="rId2"/>'
      '<sheet name="Planning" sheetId="2" r:id="rId1"/>'
      '<sheet name="Oud" sheetId="3" state="hidden" r:id="rId3"/>'
      '</sheets></workbook>',
  'xl/_rels/workbook.xml.rels': _rels([
    ('rId1', 'worksheet', 'worksheets/sheet2.xml'),
    ('rId2', 'worksheet', 'worksheets/sheet1.xml'),
    ('rId3', 'worksheet', '/xl/worksheets/sheet3.xml'),
    ('rId4', 'sharedStrings', 'sharedStrings.xml'),
    ('rId5', 'styles', 'styles.xml'),
  ]),
  'xl/sharedStrings.xml':
      '$_xml<sst xmlns="$_s" count="7" uniqueCount="7">'
      '<si><t>Naam</t></si>'
      '<si><t>Wiskunde</t></si>'
      '<si><r><rPr><b/></rPr><t>An</t></r><r><t xml:space="preserve"> '
      'Peeters</t></r></si>'
      '<si><t>Bert</t><rPh sb="0" eb="1"><t>ベ</t></rPh></si>'
      '<si><t>Datum</t></si>'
      '<si><t>Activiteit</t></si>'
      '<si><t>Oude gegevens</t></si>'
      '</sst>',
  'xl/styles.xml':
      '$_xml<styleSheet xmlns="$_s"><numFmts count="2">'
      '<numFmt numFmtId="164" formatCode="dd/mm/yyyy;@"/>'
      '<numFmt numFmtId="165" formatCode="0.0&quot; punten&quot;"/>'
      '</numFmts><cellXfs count="6">'
      '<xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/>'
      '<xf numFmtId="9"/><xf numFmtId="20"/><xf numFmtId="165"/>'
      '</cellXfs></styleSheet>',
  'xl/worksheets/sheet1.xml':
      '$_xml<worksheet xmlns="$_s"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>'
      '<c r="C1" t="inlineStr"><is><t>Geslaagd</t></is></c></row>'
      '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" s="3"><v>0.85</v>'
      '</c><c r="C2" t="b"><v>1</v></c></row>'
      '<row r="3"><c r="A3" t="s"><v>3</v></c><c r="B3" s="3">'
      '<v>0.47999999999999998</v></c><c r="C3" t="b"><v>0</v></c></row>'
      '<row r="4"/>'
      '<row r="5"><c r="A5" t="str"><f>"Gemiddelde"</f><v>Gemiddelde</v>'
      '</c><c r="B5" s="5"><f>AVERAGE(B2:B3)</f><v>0.66500000000000004</v>'
      '</c></row>'
      '<row r="6"><c r="B6" t="e"><v>#DIV/0!</v></c><c r="D6"><v>12</v></c>'
      '</row>'
      '<row r="7"><c r="A7"><v>1</v></c><c r="AB7" t="s"><v>0</v></c></row>'
      '</sheetData></worksheet>',
  'xl/worksheets/sheet2.xml':
      '$_xml<worksheet xmlns="$_s"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>4</v></c><c r="B1" t="s"><v>5</v></c>'
      '</row>'
      '<row r="2"><c r="A2" s="1"><v>45565</v></c><c r="B2" t="inlineStr">'
      '<is><t>Uitstap</t></is></c><c r="C2" s="4"><v>0.35416666666666669</v>'
      '</c></row>'
      '<row r="3"><c r="A3" s="2"><v>45580.5</v></c><c r="B3" '
      't="inlineStr"><is><t>Oudercontact</t></is></c></row>'
      '</sheetData></worksheet>',
  'xl/worksheets/sheet3.xml':
      '$_xml<worksheet xmlns="$_s"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>6</v></c></row>'
      '</sheetData></worksheet>',
});

const sampleXlsxText =
    '## Sheet: Punten\n'
    'Naam | Wiskunde | Geslaagd\n'
    'An Peeters | 85% | TRUE\n'
    'Bert | 48% | FALSE\n'
    'Gemiddelde | 0.665\n'
    ' | #DIV/0! |  | 12\n'
    '1 | (26 empty cells) | Naam\n'
    '\n'
    '## Sheet: Planning\n'
    'Datum | Activiteit\n'
    '2024-09-30 | Uitstap | 08:30\n'
    '2024-10-15 12:00 | Oudercontact\n'
    '\n'
    '## Sheet: Oud (hidden)\n'
    'Oude gegevens';

/// An Excel workbook with one sheet of [rows] rows of [columns] numbers.
Uint8List xlsxWithRows(int rows, {int columns = 5}) => zipOf({
  '_rels/.rels': _rels([('rId1', 'officeDocument', 'xl/workbook.xml')]),
  'xl/workbook.xml':
      '$_xml<workbook xmlns="$_s" xmlns:r="$_officeRel"><sheets>'
      '<sheet name="Blad1" sheetId="1" r:id="rId1"/></sheets></workbook>',
  'xl/_rels/workbook.xml.rels': _rels([
    ('rId1', 'worksheet', 'worksheets/sheet1.xml'),
  ]),
  'xl/worksheets/sheet1.xml':
      '$_xml<worksheet xmlns="$_s"><sheetData>'
      '${[
        for (var r = 1; r <= rows; r++) '<row r="$r">${[for (var c = 0; c < columns; c++) '<c><v>${r * 10 + c}</v></c>'].join()}</row>',
      ].join()}'
      '</sheetData></worksheet>',
});

/// A PowerPoint presentation of three slides (listed out of their file
/// order, the last hidden) with a title, a line break, speaker notes, a
/// table and a shape with a fallback copy; it reads as [samplePptxText].
Uint8List samplePptx() {
  String shape(String body, {String? placeholder}) =>
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Vorm"/><p:cNvSpPr/><p:nvPr>'
      '${placeholder == null ? '' : '<p:ph type="$placeholder"/>'}'
      '</p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>'
      '$body</p:txBody></p:sp>';
  String slide(String shapes, {bool hidden = false}) =>
      '$_xml<p:sld xmlns:p="$_p" xmlns:a="$_a" xmlns:r="$_officeRel" '
      'xmlns:mc="$_mc"${hidden ? ' show="0"' : ''}><p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
      '</p:nvGrpSpPr><p:grpSpPr/>$shapes</p:spTree></p:cSld></p:sld>';
  String cell(String text) =>
      '<a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:t>$text</a:t></a:r></a:p>'
      '</a:txBody><a:tcPr/></a:tc>';

  return zipOf({
    '[Content_Types].xml': _contentTypes(
      'ppt/presentation.xml',
      'application/vnd.openxmlformats-officedocument.presentationml.'
          'presentation.main+xml',
    ),
    '_rels/.rels': _rels([('rId1', 'officeDocument', 'ppt/presentation.xml')]),
    'ppt/presentation.xml':
        '$_xml<p:presentation xmlns:p="$_p" xmlns:r="$_officeRel">'
        '<p:sldIdLst><p:sldId id="256" r:id="rId3"/>'
        '<p:sldId id="257" r:id="rId2"/><p:sldId id="258" r:id="rId4"/>'
        '</p:sldIdLst></p:presentation>',
    'ppt/_rels/presentation.xml.rels': _rels([
      ('rId1', 'slideMaster', 'slideMasters/slideMaster1.xml'),
      ('rId2', 'slide', 'slides/slide1.xml'),
      ('rId3', 'slide', 'slides/slide2.xml'),
      ('rId4', 'slide', 'slides/slide3.xml'),
    ]),
    'ppt/slides/slide2.xml': slide(
      shape('<a:p><a:r><a:t>Welkom</a:t></a:r></a:p>', placeholder: 'title') +
          shape(
            '<a:p><a:r><a:t xml:space="preserve">Infoavond </a:t></a:r>'
            '<a:r><a:t>3de jaar</a:t></a:r><a:br/><a:r><a:t>Dinsdag 19u'
            '</a:t></a:r></a:p><a:p><a:endParaRPr/></a:p>',
          ),
    ),
    'ppt/slides/_rels/slide2.xml.rels': _rels([
      ('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml'),
      ('rId2', 'notesSlide', '../notesSlides/notesSlide1.xml'),
    ]),
    'ppt/notesSlides/notesSlide1.xml':
        '$_xml<p:notes xmlns:p="$_p" xmlns:a="$_a"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Dia"/><p:cNvSpPr/><p:nvPr>'
        '<p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>'
        '${shape('<a:p><a:r><a:t>Stoelen klaarzetten.</a:t></a:r></a:p>', placeholder: 'body')}'
        '${shape('<a:p><a:fld id="1" type="slidenum"><a:t>1</a:t></a:fld></a:p>', placeholder: 'sldNum')}'
        '</p:spTree></p:cSld></p:notes>',
    'ppt/slides/slide1.xml': slide(
      '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="3" name="Tabel"/>'
      '<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm/>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/'
      'drawingml/2006/table"><a:tbl><a:tblGrid/>'
      '<a:tr h="370840">${cell('Vak')}${cell('Lokaal')}</a:tr>'
      '<a:tr h="370840">${cell('Frans')}${cell('B204')}</a:tr>'
      '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>'
      '<mc:AlternateContent><mc:Choice Requires="p14">'
      '${shape('<a:p><a:r><a:t>Nieuw</a:t></a:r></a:p>')}'
      '</mc:Choice><mc:Fallback>'
      '${shape('<a:p><a:r><a:t>Nieuw</a:t></a:r></a:p>')}'
      '</mc:Fallback></mc:AlternateContent>',
    ),
    'ppt/slides/slide3.xml': slide(
      shape('<a:p><a:r><a:t>Reserve</a:t></a:r></a:p>'),
      hidden: true,
    ),
  });
}

const samplePptxText =
    '## Slide 1\n'
    'Welkom\n'
    'Infoavond 3de jaar\n'
    'Dinsdag 19u\n'
    'Notes: Stoelen klaarzetten.\n'
    '\n'
    '## Slide 2\n'
    'Vak | Lokaal\n'
    'Frans | B204\n'
    'Nieuw\n'
    '\n'
    '## Slide 3 (hidden)\n'
    'Reserve';

/// A PDF with a page per entry of [pages], each line of it written with the
/// standard Helvetica font (WinAnsi encoding: Latin-1 text only). A page
/// without lines has only a drawing, like a scan has only a picture.
Uint8List samplePdf(List<List<String>> pages) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[for (var i = 0; i < pages.length; i++) '${4 + 2 * i} 0 R'].join(' ')}] /Count ${pages.length} >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
  ];
  for (final (i, lines) in pages.indexed) {
    final String content;
    if (lines.isEmpty) {
      content = '0.5 g 72 72 451 698 re f';
    } else {
      final text = StringBuffer('BT /F1 12 Tf 72 770 Td 16 TL');
      for (final line in lines) {
        final escaped = line
            .replaceAll(r'\', r'\\')
            .replaceAll('(', r'\(')
            .replaceAll(')', r'\)');
        text.write(' ($escaped) Tj T*');
      }
      text.write(' ET');
      content = text.toString();
    }
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources '
        '<< /Font << /F1 3 0 R >> >> /Contents ${5 + 2 * i} 0 R >>',
      )
      ..add(
        '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\n'
        'endstream',
      );
  }
  final out = BytesBuilder();
  void write(String text) => out.add(latin1.encode(text));
  write('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, object) in objects.indexed) {
    offsets.add(out.length);
    write('${i + 1} 0 obj\n$object\nendobj\n');
  }
  final xref = out.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n'
    '$xref\n%%EOF\n',
  );
  return out.toBytes();
}

/// A PNG of [width] by [height] pixels: a colour gradient, with an alpha
/// channel when [alpha]. With [compress] false it is stored uncompressed,
/// which makes a large file of a simple picture.
Uint8List samplePng(
  int width,
  int height, {
  bool alpha = false,
  bool compress = true,
}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: alpha ? 4 : 3,
  );
  for (final pixel in image) {
    pixel
      ..r = pixel.x * 255 ~/ width
      ..g = pixel.y * 255 ~/ height
      ..b = 128;
    if (alpha) pixel.a = pixel.x < width ~/ 2 ? 0 : 255;
  }
  return img.encodePng(image, level: compress ? 6 : 0);
}

/// The first bytes of an OLE2 compound file, like a `.doc`.
Uint8List sampleOle2() => Uint8List.fromList([
  0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
  ...List.filled(504, 0),
]);
