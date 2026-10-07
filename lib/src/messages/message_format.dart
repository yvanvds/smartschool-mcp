import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'message_box.dart';

/// [date] as `2024-03-15 14:30`, in Smartschool's (local) time.
String formatMessageDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// The name of Smartschool's colour flag [flag] (1-4), or null for no flag.
String? flagName(int flag) => switch (flag) {
  1 => 'green',
  2 => 'yellow',
  3 => 'red',
  4 => 'blue',
  _ => null,
};

/// [subject], or a placeholder when it is empty.
String displaySubject(String subject) =>
    subject.trim().isEmpty ? '(no subject)' : subject.trim();

/// One compact line describing [message] in [box]: id, date, sender (the
/// recipients in the sent box and its folders), subject and markers.
///
/// For example `id 123 | 2024-03-15 14:30 | from Jan Peeters | Oudercontact |
/// unread, attachments, flag red`.
///
/// [unread] and [flag], when given, replace the message's own read state and
/// colour flag: for a line that shows the message after a change.
String formatHeaderLine(
  ShortMessage message,
  MessageBox box, {
  bool? unread,
  int? flag,
}) {
  final markers = [
    if ((unread ?? message.unread) && box.boxType != BoxType.sent) 'unread',
    if (message.attachment > 0) 'attachments',
    if (flagName(flag ?? message.coloredFlag) case final name?) 'flag $name',
  ];
  return [
    'id ${message.id}',
    formatMessageDate(message.date),
    '${box.boxType == BoxType.sent ? 'to' : 'from'} ${message.sender.trim()}',
    displaySubject(message.subject),
    if (markers.isNotEmpty) markers.join(', '),
  ].join(' | ');
}
