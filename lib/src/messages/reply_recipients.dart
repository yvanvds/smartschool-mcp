import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'message_box.dart';

/// Who a reply goes to, with the ids Smartschool's compose form needs.
final class ReplyRecipients {
  const ReplyRecipients({required this.to, this.cc = const []});

  final List<MessageSearchUser> to;
  final List<MessageSearchUser> cc;

  bool get isEmpty => to.isEmpty && cc.isEmpty;

  /// The names in [to], for tool output.
  String get toNames => _names(to);

  /// The names in [cc], for tool output.
  String get ccNames => _names(cc);

  static String _names(List<MessageSearchUser> users) =>
      users.map((u) => u.displayName.trim()).join(', ');
}

/// The recipients of a reply to message [id] in [box], as Smartschool's own
/// reply forms fill them in.
///
/// - A message in the inbox or the archive: a plain reply goes to its
///   sender, from Smartschool's reply form (`composeType=1`), which names
///   only the sender. The reply-all form does contain the sender too, but
///   without marking which entry it is (it was the last one when checked
///   live), so it cannot be picked from there reliably. The library has no
///   call for the reply form yet (yvanvds/dartschool#24), so its page is
///   loaded here and parsed with the library's parser. A reply to all goes
///   to the recipients of Smartschool's reply-all form: the sender and the
///   To recipients in To, the CC recipients in CC, without the user (unless
///   the user sent the message).
/// - A message in the sent box: Smartschool's reply form for it names the
///   user, the sender. So, as in most mail programs, a plain reply goes to
///   the message's To recipients and a reply to all to its To and CC
///   recipients, from the sent box's reply-all form without the user
///   ([MessagesService.getSentMessageRecipients]). For some sent messages
///   that form names no one but the user (seen live); then the result is
///   empty (yvanvds/dartschool#27).
///
/// Only loads compose pages: nothing is sent.
Future<ReplyRecipients> loadReplyRecipients(
  SmartschoolClient client,
  MessagesService messages,
  MessageBox box,
  int id, {
  required bool replyAll,
}) async {
  switch ((box, replyAll)) {
    case (MessageBox.sent, _):
      final (to, cc) = await messages.getSentMessageRecipients(id);
      return ReplyRecipients(to: to, cc: replyAll ? cc : const []);
    case (_, true):
      final (to, cc) = await messages.getReplyAllRecipients(
        id,
        boxType: box.boxType,
      );
      return ReplyRecipients(to: to, cc: cc);
    case (_, false):
      final (to, cc) = MessagesService.parseReplyAllRecipients(
        await client.getRaw(replyFormPath(box, id)),
      );
      return ReplyRecipients(to: to, cc: cc);
  }
}

/// The path of Smartschool's form for a plain reply to message [id] in
/// [box], which it fills in with the sender.
String replyFormPath(MessageBox box, int id) =>
    '/?module=Messages&file=composeMessage&boxType=${box.boxType.value}'
    '&composeType=1&msgID=$id';
