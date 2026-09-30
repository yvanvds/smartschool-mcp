import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'document_content.dart';
import 'office_package.dart';

/// The text of the Excel workbook in [package], whose main part is
/// [mainPart] (usually `xl/workbook.xml`); how many sheets it has; and
/// whether all of them were read.
///
/// Every sheet in the workbook's order as a `## Sheet: name` line (with
/// `(hidden)` for a hidden sheet), followed by its rows that have a value,
/// one per line, with the cells joined by ` | ` (empty cells in between
/// kept, so columns line up; a run of more than 20 shown as one
/// `(n empty cells)` cell). A cell shows its value as last calculated:
/// text, a number, TRUE or FALSE, an error like `#N/A`, a date as
/// `2024-03-15` (with the time when it has one), and a percentage as `85%`.
///
/// Sheets are read as a stream of XML events, not as a tree, because they
/// can be large; reading stops once the text is longer than [maxChars].
({String text, int sheets, bool complete}) xlsxText(
  OfficePackage package,
  String mainPart, {
  required int maxChars,
}) {
  final workbook = package.xml(mainPart);
  if (workbook == null) {
    throw const UnreadableDocumentException(
      'It could not be read as an Excel workbook: the file seems damaged.',
    );
  }
  final properties = workbook.findAllElements('workbookPr', namespace: '*');
  final date1904 =
      properties.isNotEmpty &&
      {'1', 'true'}.contains(attribute(properties.first, 'date1904'));
  final targets = package.relationshipTargets(mainPart);
  final sheets = [
    for (final sheet in workbook.findAllElements('sheet', namespace: '*'))
      if (_relationshipId(sheet) case final id? when targets[id] != null)
        (
          name: attribute(sheet, 'name') ?? '',
          hidden: {'hidden', 'veryHidden'}.contains(attribute(sheet, 'state')),
          path: targets[id]!,
        ),
  ];
  String? part(String type) => [
    for (final rel in package.relationships(mainPart))
      if (rel.type.endsWith('/$type')) rel.target,
  ].firstOrNull;
  final strings = switch (part('sharedStrings')) {
    final path? => _sharedStrings(package.text(path) ?? ''),
    null => const <String>[],
  };
  final styles = switch (part('styles')) {
    final path? => _cellStyles(package.xml(path)),
    null => const <_NumberStyle>[],
  };

  final out = StringBuffer();
  var complete = true;
  for (final sheet in sheets) {
    if (out.length > maxChars) {
      complete = false;
      break;
    }
    if (out.isNotEmpty) out.write('\n\n');
    out.write('## Sheet: ${sheet.name}${sheet.hidden ? ' (hidden)' : ''}');
    final xml = package.text(sheet.path);
    if (xml == null) continue;
    final reader = _SheetReader(strings, styles, date1904: date1904);
    complete = reader.read(xml, out, maxChars: maxChars);
    if (!complete) break;
  }
  return (text: out.toString(), sheets: sheets.length, complete: complete);
}

/// The `r:id` of a sheet (which may also have a plain `id`).
String? _relationshipId(XmlElement element) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == 'id' && attribute.name.prefix != null) {
      return attribute.value;
    }
  }
  return null;
}

/// The strings of the shared string table, by index; phonetic hints left
/// out.
List<String> _sharedStrings(String xml) {
  final strings = <String>[];
  StringBuffer? item;
  var inText = false;
  var phonetic = false;
  for (final event in parseEvents(xml)) {
    switch (event) {
      case XmlStartElementEvent(localName: 'si', :final isSelfClosing):
        if (isSelfClosing) {
          strings.add('');
        } else {
          item = StringBuffer();
        }
      case XmlStartElementEvent(localName: 'rPh', :final isSelfClosing):
        phonetic = !isSelfClosing;
      case XmlStartElementEvent(localName: 't', :final isSelfClosing):
        inText = !isSelfClosing && !phonetic;
      case XmlTextEvent(:final value) || XmlCDATAEvent(:final value):
        if (inText) item?.write(value);
      case XmlEndElementEvent(localName: 't'):
        inText = false;
      case XmlEndElementEvent(localName: 'rPh'):
        phonetic = false;
      case XmlEndElementEvent(localName: 'si'):
        strings.add(item?.toString() ?? '');
        item = null;
      default:
        break;
    }
  }
  return strings;
}

/// How a number in a cell is shown.
enum _NumberStyle { general, date, percent }

/// The number style of each cell format (`cellXfs`), by index.
List<_NumberStyle> _cellStyles(XmlDocument? styles) {
  if (styles == null) return const [];
  final codes = {
    for (final format in styles.findAllElements('numFmt', namespace: '*'))
      ?int.tryParse(attribute(format, 'numFmtId') ?? ''):
          attribute(format, 'formatCode') ?? '',
  };
  final cellFormats = styles
      .findAllElements('cellXfs', namespace: '*')
      .firstOrNull;
  if (cellFormats == null) return const [];
  return [
    for (final format in cellFormats.findElements('xf', namespace: '*'))
      _numberStyle(
        int.tryParse(attribute(format, 'numFmtId') ?? '') ?? 0,
        codes,
      ),
  ];
}

_NumberStyle _numberStyle(int id, Map<int, String> codes) {
  // Built-in formats: 14-22 dates and times, 27-36 and 50-58 East Asian
  // dates, 45-47 times; 9 and 10 percentages.
  if ((id >= 14 && id <= 22) ||
      (id >= 27 && id <= 36) ||
      (id >= 45 && id <= 47) ||
      (id >= 50 && id <= 58)) {
    return _NumberStyle.date;
  }
  if (id == 9 || id == 10) return _NumberStyle.percent;
  final code = codes[id];
  if (code == null) return _NumberStyle.general;
  // Leave out quoted text, escaped characters and [colour], [$€-813] or
  // [h] parts; then date and time formats have y, m, d, h or s.
  final bare = code
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase();
  if (RegExp('[ymdhs]').hasMatch(bare) && bare != 'general') {
    return _NumberStyle.date;
  }
  if (bare.contains('%')) return _NumberStyle.percent;
  return _NumberStyle.general;
}

/// Reads one worksheet's rows.
final class _SheetReader {
  _SheetReader(this.strings, this.styles, {required this.date1904});

  final List<String> strings;
  final List<_NumberStyle> styles;
  final bool date1904;

  List<String> _row = [];
  String? _type;
  int _style = 0;
  int _column = 0;
  final _value = StringBuffer();
  final _inline = StringBuffer();
  var _inValue = false;
  var _inInline = false;
  var _inText = false;
  var _phonetic = false;

  /// Writes the rows of the sheet [xml] to [out], a line each; returns
  /// false when it stopped because [out] got longer than [maxChars].
  bool read(String xml, StringBuffer out, {required int maxChars}) {
    for (final event in parseEvents(xml)) {
      switch (event) {
        case XmlStartElementEvent(localName: 'row'):
          _row = [];
          _column = 0;
        case XmlStartElementEvent(
          localName: 'c',
          :final attributes,
          :final isSelfClosing,
        ):
          String? value(String name) => attributes
              .where((attribute) => attribute.localName == name)
              .firstOrNull
              ?.value;
          if (_columnIndex(value('r') ?? '') case final column
              when column >= 0) {
            _column = column;
          }
          _type = value('t');
          _style = int.tryParse(value('s') ?? '') ?? 0;
          _value.clear();
          _inline.clear();
          if (isSelfClosing) _endCell();
        case XmlStartElementEvent(localName: 'v', :final isSelfClosing):
          _inValue = !isSelfClosing;
        case XmlStartElementEvent(localName: 'is', :final isSelfClosing):
          _inInline = !isSelfClosing;
        case XmlStartElementEvent(localName: 'rPh', :final isSelfClosing):
          _phonetic = !isSelfClosing;
        case XmlStartElementEvent(localName: 't', :final isSelfClosing):
          _inText = _inInline && !_phonetic && !isSelfClosing;
        case XmlTextEvent(:final value) || XmlCDATAEvent(:final value):
          if (_inValue) _value.write(value);
          if (_inText) _inline.write(value);
        case XmlEndElementEvent(localName: 'v'):
          _inValue = false;
        case XmlEndElementEvent(localName: 't'):
          _inText = false;
        case XmlEndElementEvent(localName: 'rPh'):
          _phonetic = false;
        case XmlEndElementEvent(localName: 'is'):
          _inInline = false;
        case XmlEndElementEvent(localName: 'c'):
          _endCell();
        case XmlEndElementEvent(localName: 'row'):
          if (_rowText(_row) case final text?) out.write('\n$text');
          _row = [];
          if (out.length > maxChars) return false;
        case XmlEndElementEvent(localName: 'sheetData'):
          return true;
        default:
          break;
      }
    }
    return true;
  }

  void _endCell() {
    final shown = tidyText(_display().replaceAll('\n', ' '));
    while (_row.length < _column) {
      _row.add('');
    }
    _row.add(shown);
    _column++;
  }

  String _display() {
    final value = _value.toString().trim();
    switch (_type) {
      case 's':
        final index = int.tryParse(value);
        return index != null && index >= 0 && index < strings.length
            ? strings[index]
            : '';
      case 'inlineStr':
        return _inline.toString();
      case 'b':
        return value.isEmpty ? '' : (value == '1' ? 'TRUE' : 'FALSE');
      case 'e' || 'str' || 'd':
        return value;
    }
    final number = double.tryParse(value);
    if (number == null) return value;
    final style = _style < styles.length
        ? styles[_style]
        : _NumberStyle.general;
    return switch (style) {
      _NumberStyle.date => _date(number),
      _NumberStyle.percent => '${_number(number * 100)}%',
      _NumberStyle.general => _number(number),
    };
  }

  String _date(double serial) {
    if (serial < 0 || serial > 2958465) return _number(serial);
    final base = date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
    final time = base.add(
      Duration(milliseconds: (serial * Duration.millisecondsPerDay).round()),
    );
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${time.year}-${two(time.month)}-${two(time.day)}';
    final clock = '${two(time.hour)}:${two(time.minute)}';
    final hasTime = serial != serial.truncateToDouble();
    if (serial < 1 && hasTime) return clock;
    return hasTime ? '$date $clock' : date;
  }
}

/// More empty cells than this in a row between two values are shown as one
/// `(… empty cells)` cell, not as that many separators.
const _maxEmptyRun = 20;

/// [cells] as one line joined by ` | `, without the empty cells at the end;
/// null when all are empty.
String? _rowText(List<String> cells) {
  var end = cells.length;
  while (end > 0 && cells[end - 1].isEmpty) {
    end--;
  }
  if (end == 0) return null;
  final shown = <String>[];
  var empty = 0;
  void flushEmpty() {
    if (empty > _maxEmptyRun) {
      shown.add('($empty empty cells)');
    } else {
      shown.addAll(List.filled(empty, ''));
    }
    empty = 0;
  }

  for (final cell in cells.take(end)) {
    if (cell.isEmpty) {
      empty++;
      continue;
    }
    flushEmpty();
    shown.add(cell);
  }
  return shown.join(' | ');
}

/// [number] without floating-point noise: `12`, `0.3`, `1234.5678`.
String _number(double number) {
  if (number.isNaN || number.isInfinite) return '$number';
  if (number == number.truncateToDouble() && number.abs() < 1e15) {
    return number.toInt().toString();
  }
  final precise = number.toStringAsPrecision(12);
  if (precise.contains('e')) return '$number';
  return precise.contains('.')
      ? precise.replaceFirst(RegExp(r'\.?0+$'), '')
      : precise;
}

/// The zero-based column of a cell reference like `B3` (1) or `AA10` (26).
int _columnIndex(String reference) {
  var column = 0;
  for (final unit in reference.toUpperCase().codeUnits) {
    if (unit < 0x41 || unit > 0x5A) break;
    column = column * 26 + (unit - 0x40);
  }
  return column - 1;
}
