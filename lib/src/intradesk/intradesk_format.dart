import 'intradesk_index.dart';

/// [bytes] for people: `812 bytes`, `178 KB`, `2.4 MB` (units of 1024).
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes ${bytes == 1 ? 'byte' : 'bytes'}';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final shown = value < 10 ? value.toStringAsFixed(1) : value.round();
  return '$shown ${units[unit]}';
}

/// [date] as `2024-03-15`, in the time of this PC (Belgium).
String formatIntradeskDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// [date] as `2024-03-15 14:30`, in the time of this PC (Belgium).
String formatIntradeskTime(DateTime date) {
  final local = date.toLocal();
  return '${formatIntradeskDate(local)} ${_two(local.hour)}:'
      '${_two(local.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `Intradesk file <path> (id …, 178 KB, changed 2024-08-29)`: the file
/// [id] with what is known about it, from the index ([known]) or the
/// download ([name], [size]).
String intradeskFileTitle(
  String id,
  IntradeskItem? known, {
  String? name,
  int? size,
}) {
  final what = known?.path ?? name;
  final details = [
    'id $id',
    if (size ?? known?.size case final size?) formatFileSize(size),
    if (known?.changed case final changed?)
      'changed ${formatIntradeskDate(changed)}',
    if (known?.confidential ?? false) 'confidential',
  ];
  return 'Intradesk file ${what == null ? '' : '$what '}'
      '(${details.join(', ')})';
}

/// One line describing [item]: kind, path (with [fullPath]) or name, id,
/// size, date changed and whether it is confidential.
///
/// For example `file | Leerkrachten / Formulieren / uitstap.docx | id
/// cccc1111-… | 178 KB | changed 2024-08-29`, or for a weblink
/// `weblink | Leerkrachten / Schoolsite | https://…`.
String formatIntradeskItem(IntradeskItem item, {bool fullPath = true}) {
  final name = fullPath ? item.path : item.name;
  if (item.kind == IntradeskItemKind.weblink) {
    return [
      'weblink',
      name,
      item.url ?? '(no address)',
      if (item.confidential) 'confidential',
    ].join(' | ');
  }
  return [
    item.kind.name,
    name,
    'id ${item.id}',
    if (item.size case final size?) formatFileSize(size),
    if (item.changed case final changed?)
      'changed ${formatIntradeskDate(changed)}',
    if (item.confidential) 'confidential',
  ].join(' | ');
}
