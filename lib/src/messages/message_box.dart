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

  /// The box in a sentence, like `the sent box`.
  String get phrase => switch (this) {
    inbox => 'the inbox',
    sent => 'the sent box',
    archive => 'the archive',
  };

  /// The [BoxType] to pass to [MessagesService] calls for a message in this
  /// box.
  BoxType get boxType => this == sent ? BoxType.sent : BoxType.inbox;

  /// The folder of [boxType] this box is, for the [MessagesService] calls
  /// that name it (a `boxId`): the archive's box id, looked up once per
  /// service; 0 for the inbox and the sent box themselves.
  Future<int> folderId(MessagesService messages) async =>
      this == archive ? await messages.getArchiveBoxId() : 0;

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

  /// The input schema of a tool's `box` argument: one of [boxes] (all boxes
  /// by default), [inbox] when absent.
  static Schema schema({
    required String description,
    List<MessageBox> boxes = values,
  }) => UntitledSingleSelectEnumSchema(
    description: description,
    values: [for (final box in boxes) box.name],
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
  /// Smartschool keeps the paging position per user and box, not in the
  /// session (yvanvds/dartschool#76): a listing of the box anywhere on the
  /// account restarts it, also in another session (the web client, the
  /// Account Manager, another smartschool-mcp process). A listing that is
  /// still paging then fails with a [SmartschoolPagingRestartedError] after
  /// the pages it got, rather than return part of the box, and
  /// [SmartschoolSession.run] runs its action once more, which lists the box
  /// again (#28). So keep the state of [stopAfter] inside that action. A new
  /// login between two pages does not restart the paging: Smartschool goes
  /// on with the next page in the new session.
  ///
  /// Two pagings of the same box at the same time share the position and
  /// can skip each other's pages, without an error. So the box listings of
  /// this process run one at a time, also for different boxes: the inbox and
  /// the archive share a box type, and whether they share a position is
  /// unknown. That keeps this server's own tool calls apart, but not a
  /// listing elsewhere on the account.
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

  /// The headers of the messages with [ids] in this box, by id.
  ///
  /// The box is listed newest first ([headers]) until all of [ids] are
  /// among the headers, or to its end: an id the box does not hold is
  /// missing from the map. The map holds the other headers listed as well.
  Future<Map<int, ShortMessage>> find(
    MessagesService messages,
    Iterable<int> ids,
  ) async {
    final missing = ids.toSet();
    final found = await headers(
      messages,
      stopAfter: (page) {
        missing.removeAll([for (final header in page) header.id]);
        return missing.isEmpty;
      },
    );
    return {for (final header in found) header.id: header};
  }

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
/// may run more than once (when Smartschool refuses the session, or
/// restarts a box listing of it, see [MessageBox.headers]), so it must be
/// safe to repeat.
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
