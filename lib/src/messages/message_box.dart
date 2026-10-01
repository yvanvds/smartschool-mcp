import 'dart:async';

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

  /// The message headers in this box, newest first.
  ///
  /// Smartschool lists a box 50 headers at a time. The pages are requested
  /// one after the other, and [stopAfter], when given, is called with each:
  /// when it returns true, no further page is requested. Without it, or
  /// when it never returns true, the whole box is listed, and a box can hold
  /// thousands of messages: stop as soon as the headers so far are enough.
  ///
  /// Smartschool keeps one paging position per box in the session and
  /// restarts it whenever the box is listed (yvanvds/dartschool#15). The
  /// library then ends a listing that is still paging as if the box ended
  /// there (yvanvds/dartschool#76). So the box listings of this process (one
  /// session) run one at a time, also for different boxes: the inbox and the
  /// archive share a box type, and whether they share a position is
  /// unknown. A new login between two pages loses the position as well,
  /// which nothing here detects (#28).
  Future<List<ShortMessage>> headers(
    MessagesService messages, {
    bool Function(List<ShortMessage> page)? stopAfter,
  }) => _oneListingAtATime(() async {
    final pages = switch (this) {
      archive => messages.getArchiveHeaderPages(),
      _ => messages.getHeaderPages(boxType: boxType),
    };
    final headers = <ShortMessage>[];
    await for (final page in pages) {
      headers.addAll(page);
      if (stopAfter?.call(page) ?? false) break;
    }
    return headers;
  });

  /// Message [id] in this box, or null when the box has no such message.
  ///
  /// With [allRecipients] (the default) the message lists all its
  /// recipients; without, Smartschool names a few and counts the rest (a
  /// lighter request, for when the recipients do not matter).
  Future<FullMessage?> message(
    MessagesService messages,
    int id, {
    bool allRecipients = true,
  }) => messages.getMessage(
    id,
    boxType: boxType,
    includeAllRecipients: allRecipients,
  );
}

/// When the box listing that started last is done; the next one waits for
/// it.
Future<void> _lastListing = Future<void>.value();

/// Runs [listing] once the box listings started before it are done.
Future<T> _oneListingAtATime<T>(Future<T> Function() listing) {
  final previous = _lastListing;
  final done = Completer<void>();
  _lastListing = done.future;
  return previous.then((_) => listing()).whenComplete(done.complete);
}

/// Runs [action] with a [MessagesService] on the session's logged-in client.
///
/// The service is created inside [SmartschoolSession.run]'s callback and
/// disposed afterwards. Like every [SmartschoolSession.run] action, [action]
/// may run twice (when Smartschool refuses the session), so it must be safe
/// to repeat.
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
