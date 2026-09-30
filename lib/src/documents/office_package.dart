import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_content.dart';

/// An XML part larger than this (uncompressed) is not read: parsing it
/// would take too much memory. Real documents stay far below it; a zip bomb
/// does not.
const maxOfficePartBytes = 48 * 1024 * 1024;

/// An Office Open XML file (`.docx`, `.xlsx`, `.pptx`): a zip of XML parts
/// linked by relationships.
final class OfficePackage {
  OfficePackage._(this._archive);

  /// Opens [bytes] as a zip; throws an [UnreadableDocumentException] when it
  /// is not one.
  factory OfficePackage.open(Uint8List bytes, {required String what}) {
    try {
      return OfficePackage._(ZipDecoder().decodeBytes(bytes));
    } catch (_) {
      throw UnreadableDocumentException(
        'It could not be read as $what: the file seems damaged.',
      );
    }
  }

  final Archive _archive;

  /// Whether the package has a part at [path].
  bool has(String path) => _archive.findFile(path) != null;

  /// The part names that start with [prefix].
  Iterable<String> partsUnder(String prefix) => [
    for (final file in _archive.files)
      if (file.isFile && file.name.startsWith(prefix)) file.name,
  ];

  /// The path of the main part (`word/document.xml`, `xl/workbook.xml`,
  /// `ppt/presentation.xml`), from the package relationships; null when
  /// there is none.
  String? get mainPart {
    for (final rel in relationships('')) {
      if (rel.type.endsWith('/officeDocument')) return rel.target;
    }
    return null;
  }

  /// The text of the part at [path]; null when there is none.
  ///
  /// Throws an [UnreadableDocumentException] when the part is larger than
  /// [maxOfficePartBytes].
  String? text(String path) {
    final file = _archive.findFile(path);
    if (file == null || !file.isFile) return null;
    if (file.size > maxOfficePartBytes) {
      throw const UnreadableDocumentException(
        'It is too large to read: one of its parts is larger than '
        '${maxOfficePartBytes ~/ (1024 * 1024)} MB unpacked.',
      );
    }
    final text = utf8.decode(file.content, allowMalformed: true);
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

  /// The part at [path], parsed; null when there is none or it is not XML.
  XmlDocument? xml(String path) {
    final text = this.text(path);
    if (text == null) return null;
    try {
      return XmlDocument.parse(text);
    } on XmlException {
      return null;
    }
  }

  /// The relationships of the part at [source] (the package itself when
  /// empty) to other parts, in document order: links to outside the
  /// package are left out.
  List<({String id, String type, String target})> relationships(String source) {
    final slash = source.lastIndexOf('/');
    final folder = slash < 0 ? '' : source.substring(0, slash + 1);
    final name = source.substring(slash + 1);
    final rels = xml('${folder}_rels/$name.rels');
    if (rels == null) return const [];
    return [
      for (final rel in rels.findAllElements('Relationship', namespace: '*'))
        if (rel.getAttribute('TargetMode') != 'External')
          if ((
                rel.getAttribute('Id'),
                rel.getAttribute('Type'),
                rel.getAttribute('Target'),
              )
              case (final String id, final String type, final String target))
            (id: id, type: type, target: resolvePartPath(folder, target)),
    ];
  }

  /// The targets of the relationships of the part at [source], by id.
  Map<String, String> relationshipTargets(String source) => {
    for (final rel in relationships(source)) rel.id: rel.target,
  };
}

/// The part path [target] points to from a part in [folder] (ending in `/`,
/// or empty for the package root): absolute when it starts with `/`,
/// otherwise relative, with `..` resolved.
String resolvePartPath(String folder, String target) {
  final segments = <String>[];
  final path = target.startsWith('/') ? target : '$folder$target';
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  return segments.join('/');
}

/// The attribute [local] of [element], whatever its namespace prefix; null
/// when it has none.
String? attribute(XmlElement element, String local) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}

/// The first child element of [element] named [local], whatever its
/// namespace prefix.
XmlElement? child(XmlElement element, String local) =>
    element.getElement(local, namespace: '*');

/// Joins text blocks into a document: one block per line, with a blank line
/// before a heading (a block starting with `#`) that is not the first.
String joinBlocks(Iterable<String> blocks) {
  final out = StringBuffer();
  for (final block in blocks) {
    if (block.trim().isEmpty) continue;
    if (out.isNotEmpty) out.write(block.startsWith('#') ? '\n\n' : '\n');
    out.write(block);
  }
  return out.toString();
}

/// [text] with runs of spaces and tabs collapsed to one space, each line
/// trimmed, and empty lines left out.
String tidyText(String text) => text
    .split('\n')
    .map((line) => line.replaceAll(_spaces, ' ').trim())
    .where((line) => line.isNotEmpty)
    .join('\n');

final _spaces = RegExp(r'[ \t ]+');
