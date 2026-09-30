import 'package:xml/xml.dart';

import 'document_content.dart';
import 'office_package.dart';

/// The text of the PowerPoint presentation in [package], whose main part is
/// [mainPart] (usually `ppt/presentation.xml`), and how many slides it has.
///
/// Every slide in the presentation's order as a `## Slide n` line (with
/// `(hidden)` for a hidden slide), followed by the text of its shapes, one
/// paragraph per line, table rows as one line with the cells joined by
/// ` | `, and the speaker notes as a `Notes:` line.
({String text, int slides}) pptxText(OfficePackage package, String mainPart) {
  final presentation = package.xml(mainPart);
  if (presentation == null) {
    throw const UnreadableDocumentException(
      'It could not be read as a PowerPoint presentation: the file seems '
      'damaged.',
    );
  }
  final targets = package.relationshipTargets(mainPart);
  var slides = [
    for (final slide in presentation.findAllElements('sldId', namespace: '*'))
      if (_relationshipId(slide) case final id? when targets[id] != null)
        targets[id]!,
  ];
  if (slides.isEmpty) {
    // No slide list: the slide parts in the order of their numbers.
    int number(String path) =>
        int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(path)?[1] ?? '') ?? 0;
    slides = [
      for (final path in package.partsUnder('ppt/slides/'))
        if (RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(path)) path,
    ]..sort((a, b) => number(a).compareTo(number(b)));
  }

  final blocks = <String>[];
  for (final (index, path) in slides.indexed) {
    final slide = package.xml(path)?.rootElement;
    final hidden = slide != null && attribute(slide, 'show') == '0';
    blocks.add('## Slide ${index + 1}${hidden ? ' (hidden)' : ''}');
    if (slide == null) {
      blocks.add('(this slide could not be read)');
      continue;
    }
    final shapes = slide.getElement('cSld', namespace: '*');
    if (shapes != null) _drawingText(shapes, blocks);
    final notes = [
      for (final rel in package.relationships(path))
        if (rel.type.endsWith('/notesSlide')) rel.target,
    ];
    if (notes.isNotEmpty) {
      final text = _notesText(package.xml(notes.first));
      if (text.isNotEmpty) blocks.add('Notes: ${text.replaceAll('\n', ' ')}');
    }
  }
  return (text: joinBlocks(blocks), slides: slides.length);
}

/// The `r:id` of a slide list entry (which also has a plain `id`).
String? _relationshipId(XmlElement element) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == 'id' && attribute.name.prefix != null) {
      return attribute.value;
    }
  }
  return null;
}

/// The text of the body placeholder of a notes slide: the speaker notes,
/// without the slide image and slide number.
String _notesText(XmlDocument? notes) {
  if (notes == null) return '';
  final lines = <String>[];
  for (final shape in notes.findAllElements('sp', namespace: '*')) {
    final placeholder = shape.findAllElements('ph', namespace: '*').firstOrNull;
    if (placeholder == null || attribute(placeholder, 'type') != 'body') {
      continue;
    }
    if (shape.getElement('txBody', namespace: '*') case final body?) {
      _drawingText(body, lines);
    }
  }
  return lines.join('\n');
}

/// Adds the DrawingML text in [node] to [lines]: a line per paragraph, and a
/// line per table row with the cells joined by ` | `.
void _drawingText(XmlElement node, List<String> lines) {
  for (final element in node.childElements) {
    switch (element.name.local) {
      case 'p':
        final text = tidyText(_paragraphText(element));
        if (text.isNotEmpty) lines.add(text);
      case 'tbl':
        for (final row in element.findElements('tr', namespace: '*')) {
          final cells = [
            for (final cell in row.findElements('tc', namespace: '*'))
              _cellText(cell),
          ];
          if (cells.any((cell) => cell.isNotEmpty)) {
            lines.add(cells.join(' | '));
          }
        }
      // The fallback copy of content the Choice already has.
      case 'Fallback':
        break;
      default:
        _drawingText(element, lines);
    }
  }
}

/// The text of a DrawingML paragraph: its runs and fields, with line
/// breaks.
String _paragraphText(XmlElement paragraph) {
  final text = StringBuffer();
  for (final element in paragraph.childElements) {
    switch (element.name.local) {
      case 'r' || 'fld':
        text.write(element.getElement('t', namespace: '*')?.innerText ?? '');
      case 'br':
        text.write('\n');
    }
  }
  return text.toString();
}

/// The text of a table cell on one line.
String _cellText(XmlElement cell) {
  final lines = <String>[];
  _drawingText(cell, lines);
  return lines.join(' ');
}
