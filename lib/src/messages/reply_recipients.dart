import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'message_box.dart';

/// Who a reply goes to, with the ids Smartschool's compose form needs.
final class ReplyRecipients {
  const ReplyRecipients({required this.to, this.cc = const []});

  final List<MessageSearchUser> to;
  final List<MessageSearchUser> cc;

  bool get isEmpty => to.isEmpty && cc.isEmpty;

  /// The names in [to], for tool output.
  List<String> get toNames => _names(to);

  /// The names in [cc], for tool output.
  List<String> get ccNames => _names(cc);

  static List<String> _names(List<MessageSearchUser> users) => [
    for (final user in users) user.displayName.trim(),
  ];
}

/// The recipients of a reply to message [id] in [box], as Smartschool's own
/// reply forms fill them in.
///
/// - A message in the inbox or the archive: a plain reply goes to its
///   sender, the one recipient of Smartschool's reply form
///   ([MessagesService.getReplyRecipients]). A reply to all goes to the
///   recipients of Smartschool's reply-all form
///   ([MessagesService.getReplyAllRecipients]): the sender and the To
///   recipients in To, the CC recipients in CC, without the user (unless
///   the user sent the message).
/// - A message in the sent box: Smartschool's reply form for it names the
///   user, the sender. So, as in most mail programs, a plain reply goes to
///   the message's To recipients and a reply to all to its To and CC
///   recipients ([MessagesService.getSentMessageRecipients], which reads
///   the sent box's reply-all form and the message). The user is among them
///   only when the message went to the user too. The BCC recipients are
///   left out, so a reply never reveals them; a message sent to BCC
///   recipients only has no one to reply to.
///
/// These are the recipients to pass to [MessagesService.sendReply], with
/// `all: replyAll`: it takes whoever else its reply form names off the form.
///
/// Only loads compose pages and the message: nothing is sent.
Future<ReplyRecipients> loadReplyRecipients(
  MessagesService messages,
  MessageBox box,
  int id, {
  required bool replyAll,
}) async {
  // The reply forms of a received message name no BCC recipients.
  switch ((box, replyAll)) {
    case (MessageBox.sent, _):
      final (to, cc, _) = await messages.getSentMessageRecipients(id);
      return ReplyRecipients(to: to, cc: replyAll ? cc : const []);
    case (_, true):
      final (to, cc, _) = await messages.getReplyAllRecipients(
        id,
        boxType: box.boxType,
      );
      return ReplyRecipients(to: to, cc: cc);
    case (_, false):
      final (to, cc, _) = await messages.getReplyRecipients(
        id,
        boxType: box.boxType,
      );
      return ReplyRecipients(to: to, cc: cc);
  }
}
