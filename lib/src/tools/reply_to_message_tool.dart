import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/markdown_to_html.dart';
import '../messages/message_box.dart';
import '../messages/reply_recipients.dart';
import '../session.dart';
import 'arguments.dart';
import 'message_sending.dart';
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
    final summary = await session.run(
      (client) => _send(client, box, id, replyAll: replyAll, html: html),
    );
    return CallToolResult(
      content: [TextContent(text: 'Sent the reply to message $id.\n$summary')],
    );
  } on SendNotConfirmed catch (error) {
    return notConfirmedResult('The reply to message $id', error);
  }
}

/// Sends the reply with [client] and returns to whom and with which subject
/// ([sendSummary]).
///
/// Sends it once, with [submitOnce], which says why repeating this (as
/// [SmartschoolSession.run] does when Smartschool rejects the session)
/// cannot send it twice, and turns a send that Smartschool does not confirm
/// into a [SendNotConfirmed]. Everything else that goes wrong is a
/// [ToolError] or a login or connection problem, and nothing was sent.
Future<String> _send(
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

    final summary = sendSummary(
      to: recipients.toNames,
      cc: recipients.ccNames,
      subject: subject,
    );
    await submitOnce(
      () => messages.sendReply(
        id,
        SendMessageParams(
          to: recipients.to,
          cc: recipients.cc,
          subject: subject,
          bodyHtml: html,
        ),
        boxType: box.boxType,
        all: replyAll,
      ),
      tool: 'reply_to_message',
      what: 'the reply to message $id',
      summary: summary,
      // The reply form did not open, or Smartschool did not take a recipient
      // on or off it.
      composeRefused:
          'Smartschool did not open its reply form for message $id, or did '
          'not take the recipients of the reply on it, so nothing was sent. '
          'The account may not be allowed to send messages, or to send to '
          'one of the recipients; the details are in the server log.',
    );
    return summary;
  } finally {
    await messages.dispose();
  }
}
