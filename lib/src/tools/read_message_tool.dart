import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/html_to_text.dart';
import '../messages/message_box.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// Message text longer than this is cut off, with a note.
const maxBodyLength = 20000;

/// `read_message`: one message in full, with its body as plain text.
ServerTool readMessageTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_message',
    title: 'Read a Smartschool message',
    description:
        'Reads one Smartschool message: sender, date, recipients (To and '
        'CC), subject, the attachments (numbered, with name and size) and '
        'the message text as plain text. Get the id from list_messages '
        'first and pass the same box. Use it to summarise a message or '
        'answer questions about it. To open an attachment, save it with '
        'save_message_attachment. Reading a message here does not mark it '
        'as read in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'message_id': Schema.int(
          description: 'The id of the message, from list_messages.',
          minimum: 1,
        ),
        'box': MessageBox.schema(
          description:
              'The box list_messages showed the message in: inbox (default), '
              'sent or archive.',
        ),
      },
      required: ['message_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a Smartschool message',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'message_id');
  final box = MessageBox.parse(arguments['box']);

  // Neither call changes the read state: getMessage does not mark the
  // message as read (Claude reading it is not the teacher reading it).
  final (message, attachments) = await withMessages(session, (messages) async {
    final message = await box.message(messages, id);
    if (message == null || message.attachment <= 0) {
      return (message, const <MessageAttachment>[]);
    }
    return (message, await messages.getAttachments(id, boxType: box.boxType));
  });
  if (message == null) {
    throw ToolError(
      'There is no message with id $id in the ${box.name} box. Take the id '
      'from list_messages and pass the box it was listed in.',
    );
  }
  return CallToolResult(
    content: [TextContent(text: formatMessage(message, attachments, box))],
  );
}

/// [message] as text: a header block, then the body as plain text.
String formatMessage(
  FullMessage message,
  List<MessageAttachment> attachments,
  MessageBox box,
) {
  final body = htmlToText(message.body);
  final shown = _truncate(body, maxBodyLength);
  final flag = flagName(message.coloredFlag);
  final lines = [
    'Message ${message.id} (${box.label})',
    'From: ${message.sender.trim()}',
    'Date: ${formatMessageDate(message.date)}',
    'To: ${_recipients(message.receivers, message.totalNrOtherToReceivers)}',
    if (message.ccReceivers.isNotEmpty || message.totalNrOtherCcReceivers > 0)
      'CC: ${_recipients(message.ccReceivers, message.totalNrOtherCcReceivers)}',
    if (message.bccReceivers.isNotEmpty || message.totalNrOtherBccReceivers > 0)
      'BCC: '
          '${_recipients(message.bccReceivers, message.totalNrOtherBccReceivers)}',
    'Subject: ${displaySubject(message.subject)}',
    if (box != MessageBox.sent && message.unread) 'Status: unread',
    if (flag != null) 'Flag: $flag',
    if (attachments.isEmpty)
      'Attachments: none'
    else ...[
      'Attachments (${attachments.length}):',
      // Numbered: save_message_attachment takes the number.
      for (final (index, attachment) in attachments.indexed)
        '${index + 1}. ${attachment.name.trim()}'
            '${attachment.size.trim().isEmpty ? '' : ' (${attachment.size.trim()})'}',
    ],
    '',
    if (body.isEmpty) '(The message has no text.)' else shown,
    if (shown.length < body.length)
      '\n[Message text cut off: showing the first ${shown.length} of '
          '${body.length} characters.]',
  ];
  return lines.join('\n');
}

String _recipients(List<String> names, int others) {
  final listed = names.map((n) => n.trim()).where((n) => n.isNotEmpty);
  final parts = [
    ...listed,
    if (others > 0) '$others other${others == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? '(none)' : parts.join(', ');
}

/// [text] cut to at most [max] characters, at a line or word boundary when
/// one is near the end.
String _truncate(String text, int max) {
  if (text.length <= max) return text;
  var cut = text.lastIndexOf('\n', max);
  if (cut < max * 0.9) cut = text.lastIndexOf(' ', max);
  if (cut < max * 0.9) cut = max;
  return text.substring(0, cut).trimRight();
}
