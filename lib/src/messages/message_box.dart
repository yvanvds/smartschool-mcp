import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';

/// A mailbox as the message tools name it.
///
/// Smartschool's archive is not a [BoxType] of its own: it is a folder of
/// the inbox with its own box id, which [headers] looks up. Messages in the
/// archive are read with [BoxType.inbox].
enum MessageBox {
  inbox('Inbox'),
  sent('Sent'),
  archive('Archive');

  const MessageBox(this.label);

  /// The box's name in tool output.
  final String label;

  /// The [BoxType] to pass to [MessagesService] calls for a message in this
  /// box.
  BoxType get boxType => this == sent ? BoxType.sent : BoxType.inbox;

  /// The box named [value] (`inbox`, `sent` or `archive`); [inbox] when
  /// [value] is null.
  ///
  /// Throws an [ArgumentError] for another value; a tool's input schema
  /// ([schema]) rejects those before its handler runs.
  static MessageBox parse(Object? value) {
    if (value == null) return inbox;
    for (final box in values) {
      if (box.name == value) return box;
    }
    throw ArgumentError.value(value, 'box', 'not one of inbox, sent, archive');
  }

  /// The input schema of a tool's `box` argument.
  static Schema schema({required String description}) =>
      UntitledSingleSelectEnumSchema(
        description: description,
        values: [for (final box in values) box.name],
        defaultValue: inbox.name,
      );

  /// How many headers Smartschool returns for a box at most: the newest 50.
  ///
  /// Seen live for the inbox, the sent box and the archive. The library has
  /// no way to ask for older ones (yvanvds/dartschool#15), so a box that
  /// returns this many may hold older messages that cannot be listed.
  static const pageSize = 50;

  /// The message headers in this box as Smartschool returns them: the newest
  /// [pageSize] at most, in no guaranteed order.
  Future<List<ShortMessage>> headers(MessagesService messages) =>
      switch (this) {
        archive => messages.getArchiveHeaders(),
        _ => messages.getHeaders(boxType: boxType),
      };

  /// Message [id] in this box with all its recipients, or null when the box
  /// has no such message.
  ///
  /// For an unknown id Smartschool does not answer with nothing but with a
  /// placeholder message ("Niet beschikbaar", "* Bericht zonder onderwerp *",
  /// no text) whose date the library reads as 1970-01-01, so `getMessage`
  /// returns that instead of null (yvanvds/dartschool#16). A message dated
  /// before 1971 without text is taken to be that placeholder: no real
  /// message is that old, and the placeholder's texts presumably depend on
  /// the platform's language.
  Future<FullMessage?> message(MessagesService messages, int id) async {
    final message = await messages.getMessage(
      id,
      boxType: boxType,
      includeAllRecipients: true,
    );
    if (message == null) return null;
    if (message.date.isBefore(DateTime.utc(1971)) &&
        message.body.trim().isEmpty) {
      return null;
    }
    return message;
  }
}

/// Runs [action] with a [MessagesService] on the session's logged-in client.
///
/// The service is created inside [SmartschoolSession.run]'s callback, because
/// the session replaces its client after logging in again, and disposed
/// afterwards. Like every [SmartschoolSession.run] action, [action] may run
/// twice (after an expired session), so it must be safe to repeat.
Future<T> withMessages<T>(
  SmartschoolSession session,
  Future<T> Function(MessagesService messages) action,
) => session.run((client) async {
  final messages = MessagesService(client);
  try {
    return await action(messages);
  } finally {
    await messages.dispose();
  }
});
