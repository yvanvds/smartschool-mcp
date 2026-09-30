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
/// recipients for [MessageBox.sent]), subject and markers.
///
/// For example `id 123 | 2024-03-15 14:30 | from Jan Peeters | Oudercontact |
/// unread, attachments, flag red`.
String formatHeaderLine(ShortMessage message, MessageBox box) {
  final markers = [
    if (message.unread && box != MessageBox.sent) 'unread',
    if (message.attachment > 0) 'attachments',
    if (flagName(message.coloredFlag) case final flag?) 'flag $flag',
  ];
  return [
    'id ${message.id}',
    formatMessageDate(message.date),
    '${box == MessageBox.sent ? 'to' : 'from'} ${message.sender.trim()}',
    displaySubject(message.subject),
    if (markers.isNotEmpty) markers.join(', '),
  ].join(' | ');
}
