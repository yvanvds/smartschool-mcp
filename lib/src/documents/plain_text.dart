import 'dart:convert';
import 'dart:typed_data';

/// The text in [bytes], a text file of unknown encoding.
///
/// Follows a byte order mark (UTF-8, UTF-16 LE or BE); without one, reads
/// UTF-8, and when that fails Windows-1252, what Excel on a Belgian PC
/// writes a CSV file in. Line breaks become `\n`.
String decodeText(Uint8List bytes) {
  final String text;
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    text = utf8.decode(bytes.sublist(3), allowMalformed: true);
  } else if (_startsWith(bytes, const [0xFF, 0xFE])) {
    text = _utf16(bytes, 2, littleEndian: true);
  } else if (_startsWith(bytes, const [0xFE, 0xFF])) {
    text = _utf16(bytes, 2, littleEndian: false);
  } else {
    text = _utf8OrWindows1252(bytes);
  }
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Whether [bytes] look like text rather than binary data: UTF-8 (or a
/// UTF-16 byte order mark) without control characters other than tabs,
/// line breaks and form feeds.
bool looksLikeText(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xFE]) ||
      _startsWith(bytes, const [0xFE, 0xFF])) {
    return true;
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return false;
  }
  return !text.codeUnits.any(
    (unit) =>
        unit < 0x20 &&
        unit != 0x09 &&
        unit != 0x0A &&
        unit != 0x0C &&
        unit != 0x0D,
  );
}

/// [text] cut to at most [maxChars] characters: at the last line break in
/// the final tenth when there is one, and never between the two halves of a
/// surrogate pair.
String cutText(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  var end = maxChars;
  final lineBreak = text.lastIndexOf('\n', end);
  if (lineBreak >= maxChars * 0.9) {
    end = lineBreak;
  } else if (end > 0 && _isHighSurrogate(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(0, end).trimRight();
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _utf16(Uint8List bytes, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

String _utf8OrWindows1252(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes([
      for (final byte in bytes) _windows1252[byte] ?? byte,
    ]);
  }
}

/// The characters Windows-1252 has where Latin-1 has control characters.
const _windows1252 = {
  0x80: 0x20AC, // €
  0x82: 0x201A,
  0x83: 0x0192,
  0x84: 0x201E,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02C6,
  0x89: 0x2030,
  0x8A: 0x0160,
  0x8B: 0x2039,
  0x8C: 0x0152,
  0x8E: 0x017D,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201C,
  0x94: 0x201D,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02DC,
  0x99: 0x2122,
  0x9A: 0x0161,
  0x9B: 0x203A,
  0x9C: 0x0153,
  0x9E: 0x017E,
  0x9F: 0x0178,
};
