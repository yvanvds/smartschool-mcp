import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/markdown_to_html.dart';
import '../messages/message_box.dart';
import '../messages/reply_recipients.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `reply_to_message`: sends a reply to a message, to its sender or to
/// everyone on it.
///
/// Sending cannot be undone, so the tool is marked destructive (for Claude
/// Desktop to ask for approval before every call) and never sends a reply
/// twice by itself: see [_send].
///
/// The reply is sent with the message's own reply form, so Smartschool links
/// it to the original, with the original subject after one `Re:`.
ServerTool replyToMessageTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'reply_to_message',
    title: 'Reply to a Smartschool message',
    description:
        'Sends a reply to a Smartschool message. Sending cannot be undone. '
        'Before calling this tool, read the message with read_message, '
        'show the user the exact text of the reply and who will receive '
        'it, and only call it after the user has explicitly confirmed '
        'both. Who receives it: a reply to a message in the inbox or the '
        'archive goes to its sender; with reply_all it goes to the sender '
        'and to everyone in To and CC except the user. A reply to a '
        'message in the sent box goes to its To recipients; with reply_all '
        'also to its CC recipients. Smartschool links the reply to the '
        'message. The subject is the original subject with one "Re:" in '
        'front. Write body as plain text or simple Markdown: a blank line '
        'between paragraphs, lines starting with "- " or "1. " for lists, '
        '**bold**, *italic* and [text](https://...) links. HTML in body is '
        'not interpreted: it is sent as text. Attachments, and messages that are not replies, '
        'are not supported. The result says to whom the reply was sent. '
        'If the result says the reply may or may not have been sent, do '
        'not call this tool again for it: check the sent box with '
        'list_messages (box sent) and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'message_id': Schema.int(
          description:
              'The id of the message to reply to, from '
              'list_messages.',
          minimum: 1,
        ),
        'body': Schema.string(
          description:
              'The text of the reply, as confirmed by the user: plain text '
              'or simple Markdown.',
          minLength: 1,
        ),
        'reply_all': Schema.bool(
          description:
              'Reply to everyone on the message instead of only the '
              'sender (for a sent message: also to its CC recipients). '
              'Default false.',
        ),
        'box': MessageBox.schema(
          description:
              'The box list_messages showed the message in: inbox '
              '(default), sent or archive.',
        ),
      },
      required: ['message_id', 'body'],
    ),
    annotations: ToolAnnotations(
      title: 'Reply to a Smartschool message',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _reply(session, request.arguments ?? const {}),
);

Future<CallToolResult> _reply(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'message_id');
  final box = MessageBox.parse(arguments['box']);
  final replyAll = arguments['reply_all'] as bool? ?? false;
  final body = (arguments['body'] as String? ?? '').trim();
  if (body.isEmpty) {
    throw const ToolError(
      'body is empty: pass the text of the reply. Nothing was sent.',
    );
  }
  final html = markdownToHtml(body);

  try {
    final (:recipients, :subject) = await session.run(
      (client) => _send(client, box, id, replyAll: replyAll, html: html),
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Sent the reply to message $id.\n'
              '${_summary(recipients, subject)}',
        ),
      ],
    );
  } on _NotConfirmed catch (error) {
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'The reply to message $id may or may not have been sent: '
              'sending started, but Smartschool did not confirm it. Do not '
              'send it again: first check the sent box (list_messages with '
              'box sent), or ask the user to check it in Smartschool.\n'
              '${_summary(error.recipients, error.subject)}',
        ),
      ],
    );
  }
}

/// Sends the reply with [client] and returns to whom and with which subject.
///
/// Runs inside [SmartschoolSession.run], which repeats it once when
/// Smartschool rejects the session (a [SmartschoolSessionExpiredError]).
/// That cannot send the reply twice: [MessagesService.sendReply] throws that
/// error only when Smartschool refused the session for a step of the send,
/// the submit included, before handling it, or when the step was not sent
/// because the client logged in again since it loaded the reply form. Either
/// way nothing was sent, and the repeat loads a new reply form.
///
/// Once the submit (the request that sends the reply) has gone out, the
/// library only returns normally when Smartschool answers it with its "sent"
/// page. Any other outcome is a [SmartschoolSendUnconfirmedError]: the reply
/// may have reached Smartschool, so it becomes a [_NotConfirmed], which the
/// session does not repeat, and the user must check the sent box.
///
/// Everything else that goes wrong is a [ToolError] or a login or connection
/// problem, and nothing was sent.
Future<({ReplyRecipients recipients, String subject})> _send(
  SmartschoolClient client,
  MessageBox box,
  int id, {
  required bool replyAll,
  required String html,
}) async {
  final messages = MessagesService(client);
  try {
    final message = await box.message(messages, id);
    if (message == null) {
      throw ToolError(
        'There is no message with id $id in the ${box.name} box. Take the '
        'id from list_messages and pass the box it was listed in. Nothing '
        'was sent.',
      );
    }
    if (!message.canReply) {
      throw ToolError(
        'Smartschool does not allow replies to message $id. Nothing was '
        'sent.',
      );
    }
    final recipients = await loadReplyRecipients(
      messages,
      box,
      id,
      replyAll: replyAll,
    );
    if (recipients.to.isEmpty) {
      throw ToolError(
        'Smartschool gives no one to send a reply to message $id to'
        '${box == MessageBox.sent ? ' (a reply to a sent message goes to its '
                  'To recipients, and it has none, for example when it only '
                  'went to BCC recipients)' : ''}. '
        'Nothing was sent. The user can reply in Smartschool itself.',
      );
    }
    if (box != MessageBox.sent &&
        !replyAll &&
        (recipients.to.length > 1 || recipients.cc.isNotEmpty)) {
      // Smartschool's reply form names only the sender. Anything else is
      // not a plain reply, so rather not send it.
      throw ToolError(
        "Smartschool's reply form for message $id does not name just the "
        'sender, so the reply was not sent. The user can reply in '
        'Smartschool itself.',
      );
    }
    final subject = MessagesService.ensureReplySubject(message.subject);

    try {
      await messages.sendReply(
        id,
        SendMessageParams(
          to: recipients.to,
          cc: recipients.cc,
          subject: subject,
          bodyHtml: html,
        ),
        boxType: box.boxType,
        all: replyAll,
      );
    } on SmartschoolSendUnconfirmedError catch (error) {
      log(
        'reply_to_message: Smartschool did not confirm the reply to message '
        '$id, not retrying: ${_oneLine(error)}',
      );
      throw _NotConfirmed(recipients, subject);
    } on SmartschoolComposeError catch (error) {
      // The reply form did not open, or Smartschool did not take a
      // recipient on or off it; either way the library stopped before the
      // submit.
      log('reply_to_message: reply form refused: ${_oneLine(error)}');
      throw ToolError(
        'Smartschool did not open its reply form for message $id, or did '
        'not take the recipients of the reply on it, so nothing was sent. '
        'The account may not be allowed to send messages, or to send to one '
        'of the recipients; the details are in the server log.',
      );
    }
    return (recipients: recipients, subject: subject);
  } finally {
    await messages.dispose();
  }
}

/// [error] on one line, for the log.
String _oneLine(Object error) => '$error'.replaceAll(RegExp(r'\s+'), ' ');

String _summary(ReplyRecipients recipients, String subject) => [
  'To: ${recipients.toNames}',
  if (recipients.cc.isNotEmpty) 'CC: ${recipients.ccNames}',
  'Subject: $subject',
].join('\n');

/// The reply's submit went out, but Smartschool did not confirm that it
/// sent the message: it may or may not have been sent.
final class _NotConfirmed implements Exception {
  const _NotConfirmed(this.recipients, this.subject);

  final ReplyRecipients recipients;
  final String subject;
}
