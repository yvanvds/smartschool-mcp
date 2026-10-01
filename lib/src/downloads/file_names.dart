/// Turning the name Smartschool gives a file into one it can be saved under
/// in the download folder, on Windows and elsewhere.
library;

/// The longest name [safeFileName] gives, in UTF-16 code units, before a
/// number is added for a name that is taken (` (2)`). Windows allows 255
/// per name, but many programs still stop at 260 for the whole path.
const maxFileNameLength = 120;

/// Names starting with this are the server's own files in the download
/// folder (its list of saved files, files being written); a saved file never
/// gets one.
const reservedFilePrefix = '.smartschool-mcp-';

/// A name [safeFileName] made, and what it changed.
final class SafeFileName {
  const SafeFileName(this.name, {this.changes = const [], this.given});

  /// The name to save the file under: no folder, nothing Windows refuses.
  final String name;

  /// Why the name differs from [given], for the teacher, such as `it holds
  /// characters a file name cannot have`; empty when it does not (apart
  /// from spaces around it).
  final List<String> changes;

  /// The name Smartschool gave, or null when it gave none (and [name] is
  /// the fallback).
  final String? given;
}

/// Characters Windows does not allow in a name, and control characters.
final _forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]');

/// Device names Windows keeps for itself, also with an extension (`nul.txt`).
final _reserved = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  for (var i = 0; i <= 9; i++) ...['COM$i', 'LPT$i'],
  for (final digit in ['¹', '²', '³']) ...['COM$digit', 'LPT$digit'],
};

/// A name to save a file under for [given], the name Smartschool gives it,
/// or [fallback] when it gives none.
///
/// Characters Windows does not allow (`<>:"/\|?*` and control characters,
/// so also every folder separator) become `_`; dots and spaces at the end,
/// which Windows drops, are left out; a device name Windows keeps for itself
/// (`CON`, `nul.txt`, `COM1`, ...) and a name like the server's own files
/// ([reservedFilePrefix]) get a `_` in front; and a name longer than
/// [maxFileNameLength] is cut short, keeping its extension. [fallback] must
/// be safe itself.
SafeFileName safeFileName(String? given, {required String fallback}) {
  final changes = <String>[];
  var name = (given ?? '').trim();
  if (name.contains(_forbidden)) {
    name = name.replaceAll(_forbidden, '_');
    changes.add('it holds characters a file name cannot have');
  }
  final withoutEnd = name.replaceFirst(RegExp(r'[. ]+$'), '');
  if (withoutEnd != name) {
    name = withoutEnd;
    if (name.isNotEmpty) changes.add('it ends in a dot or a space');
  }
  name = name.trimLeft();
  if (name.isEmpty) {
    return SafeFileName(
      fallback,
      given: (given ?? '').trim().isEmpty ? null : given,
      changes: [if ((given ?? '').trim().isNotEmpty) 'it is not a file name'],
    );
  }
  if (_reserved.contains(name.split('.').first.trimRight().toUpperCase())) {
    name = '_$name';
    changes.add('Windows keeps it for a device');
  }
  if (name.toLowerCase().startsWith(reservedFilePrefix)) {
    name = '_$name';
    changes.add('it looks like the name of a file of this server');
  }
  if (name.length > maxFileNameLength) {
    name = _shorten(name, maxFileNameLength);
    changes.add('it is longer than $maxFileNameLength characters');
  }
  return SafeFileName(name, changes: changes, given: given);
}

/// [name] with ` (number)` before its extension: `uitstap (2).docx`.
String numberedFileName(String name, int number) {
  final (stem, extension) = _split(name);
  return '$stem ($number)$extension';
}

/// [name] cut to [max] code units, keeping a short extension, without
/// splitting a character made of two code units.
String _shorten(String name, int max) {
  var (stem, extension) = _split(name);
  if (extension.length > 16) {
    stem = name;
    extension = '';
  }
  var end = max - extension.length;
  if (_isHighSurrogate(stem.codeUnitAt(end - 1))) end--;
  stem = stem.substring(0, end).replaceFirst(RegExp(r'[. ]+$'), '');
  return '$stem$extension';
}

/// [name] split before its last dot (`.docx`), unless that is the first
/// character; the extension is empty without one.
(String, String) _split(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? (name, '') : (name.substring(0, dot), name.substring(dot));
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
