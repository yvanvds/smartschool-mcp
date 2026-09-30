import 'package:xml/xml.dart';

import 'document_content.dart';
import 'office_package.dart';

/// The text of the Word document in [package], whose main part is
/// [mainPart] (usually `word/document.xml`).
///
/// Paragraphs in document order, one per line: headings (by their style's
/// name, `heading 1` to `heading 6`, or `Title`) as `#` lines, list items
/// as `- ` lines, table rows as one line with the cells joined by ` | `,
/// and the text of text boxes after the paragraph they are in. Deleted
/// tracked changes, field codes, headers, footers, footnotes and comments
/// are left out.
String docxText(OfficePackage package, String mainPart) {
  final body = package
      .xml(mainPart)
      ?.rootElement
      .getElement('body', namespace: '*');
  if (body == null) {
    throw const UnreadableDocumentException(
      'It could not be read as a Word document: the file seems damaged.',
    );
  }
  final styles = [
    for (final rel in package.relationships(mainPart))
      if (rel.type.endsWith('/styles')) rel.target,
  ];
  final writer = _DocxWriter(
    styles.isEmpty ? const {} : _headingLevels(package.xml(styles.first)),
  )..blocks(body);
  return joinBlocks(writer.out);
}

/// The heading level of each paragraph style that is a heading, by style
/// id. Word keeps the English names of its built-in styles (`heading 1`)
/// but translates the ids (`Kop1` in Dutch).
Map<String, int> _headingLevels(XmlDocument? styles) {
  if (styles == null) return const {};
  final levels = <String, int>{};
  for (final style in styles.findAllElements('style', namespace: '*')) {
    final id = attribute(style, 'styleId');
    final nameElement = child(style, 'name');
    final name = nameElement == null
        ? null
        : attribute(nameElement, 'val')?.toLowerCase();
    if (id == null || name == null) continue;
    if (name == 'title') {
      levels[id] = 1;
    } else if (RegExp(r'^heading ([1-6])$').firstMatch(name) case final m?) {
      levels[id] = int.parse(m[1]!);
    }
  }
  return levels;
}

final class _DocxWriter {
  _DocxWriter(this.headings, {this.plain = false});

  /// Heading levels by paragraph style id.
  final Map<String, int> headings;

  /// Without heading and list markers: for table cells.
  final bool plain;

  final List<String> out = [];

  /// The block-level content of [container]: paragraphs and tables.
  void blocks(XmlElement container) {
    for (final element in container.childElements) {
      switch (element.name.local) {
        case 'p':
          paragraph(element);
        case 'tbl':
          table(element);
        case 'sdt':
          if (child(element, 'sdtContent') case final content?) {
            blocks(content);
          }
        case 'customXml' || 'ins' || 'moveTo' || 'smartTag':
          blocks(element);
        case 'AlternateContent':
          if (child(element, 'Choice') case final choice?) blocks(choice);
      }
    }
  }

  void paragraph(XmlElement paragraph) {
    final text = StringBuffer();
    final boxes = <XmlElement>[];
    _inline(paragraph, text, boxes);
    final line = tidyText(text.toString());
    if (line.isNotEmpty) {
      final properties = child(paragraph, 'pPr');
      final style = properties == null ? null : child(properties, 'pStyle');
      final level = style == null ? null : headings[attribute(style, 'val')];
      final numbering = properties == null ? null : child(properties, 'numPr');
      final numberingId = numbering == null ? null : child(numbering, 'numId');
      final listItem =
          numbering != null &&
          (numberingId == null || attribute(numberingId, 'val') != '0');
      out.add(
        plain
            ? line
            : level != null
            ? '${'#' * level} $line'
            : listItem
            ? '- $line'
            : line,
      );
    }
    // Text boxes anchored in the paragraph, after it.
    for (final box in boxes) {
      blocks(box);
    }
  }

  void table(XmlElement table) {
    for (final row in table.childElements) {
      if (row.name.local != 'tr') continue;
      final cells = [
        for (final cell in row.childElements)
          if (cell.name.local == 'tc')
            (_DocxWriter(headings, plain: true)..blocks(cell)).out.join(' '),
      ];
      if (cells.any((cell) => cell.isNotEmpty)) {
        out.add(cells.map((cell) => cell.replaceAll('\n', ' ')).join(' | '));
      }
    }
  }

  /// Writes the text in the runs of [node] to [text], and collects the text
  /// boxes in it in [boxes].
  static void _inline(
    XmlElement node,
    StringBuffer text,
    List<XmlElement> boxes,
  ) {
    for (final element in node.childElements) {
      switch (element.name.local) {
        case 't':
          text.write(element.innerText);
        case 'tab' || 'ptab':
          text.write('\t');
        case 'br' || 'cr':
          text.write('\n');
        case 'noBreakHyphen':
          text.write('-');
        case 'txbxContent':
          boxes.add(element);
        // Properties, deleted text, field codes, and the VML copy of a
        // drawing that the DrawingML version (the Choice) already has.
        case 'pPr' ||
            'rPr' ||
            'del' ||
            'moveFrom' ||
            'delText' ||
            'instrText' ||
            'delInstrText' ||
            'Fallback':
          break;
        default:
          // Runs, hyperlinks, insertions, content controls, fields,
          // drawings.
          _inline(element, text, boxes);
      }
    }
  }
}
