import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/markdown_to_html.dart';
import '../messages/recipient_search.dart';
import '../session.dart';
import 'message_sending.dart';
import 'server_tool.dart';

/// At most this many recipients in each of To, CC and BCC.
const maxRecipientsPerField = 50;

/// At most this many candidates are listed for a recipient that is not
/// clear; the rest are counted.
const _maxListedCandidates = 10;

/// `send_message`: sends a new message (not a reply) to the users and groups
/// named, found with the search of Smartschool's compose form.
///
/// Sending cannot be undone, so the tool is marked destructive (for Claude
/// Desktop to ask for approval before every call) and never sends a message
/// twice by itself ([submitOnce], as `reply_to_message`). It sends only to
/// recipients that each name exactly one user or group: a name that the
/// search does not find exactly, or finds more than once, stops the send
/// before anything is sent, with who the search does find, for the user to
/// choose from.
ServerTool sendMessageTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'send_message',
    title: 'Send a new Smartschool message',
    description:
        'Sends a new Smartschool message. Sending cannot be undone. To '
        'answer a message, use reply_to_message instead. Before calling this '
        'tool, look up every recipient with search_recipients, show the user '
        'exactly who will receive the message (the names as '
        'search_recipients lists them, with their class or group), the '
        'subject and the exact text, and only call it after the user has '
        'explicitly confirmed all of it. When search_recipients finds '
        'several users or groups for a name, or none, ask the user who they '
        'mean: never choose for them. A message to a group goes to all its '
        'members. Pass each recipient as search_recipients lists it before '
        'the "|", like "Sven Lamber (user 146)" or "5GZ (group 298)"; a name '
        'alone is enough when exactly one user or group has that name. The '
        'tool looks every recipient up again, and sends nothing when one '
        'does not name exactly one user or group: it then lists who '
        'Smartschool finds. Write body as plain text or simple Markdown: a '
        'blank line between paragraphs, lines starting with "- " or "1. " '
        'for lists, **bold**, *italic* and [text](https://...) links. HTML '
        'in body is not interpreted: it is sent as text. Attachments are not '
        'supported. The result says to whom the message was sent. If the '
        'result says the message may or may not have been sent, do not call '
        'this tool again for it: check the sent box with list_messages (box '
        'sent) and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'to': _recipientsSchema(
          'The recipients, as confirmed by the user: each as '
          'search_recipients lists it, like "Sven Lamber (user 146)".',
          minItems: 1,
        ),
        'cc': _recipientsSchema(
          'Recipients in CC, as confirmed by the user, written like those in '
          'to. Optional.',
        ),
        'bcc': _recipientsSchema(
          'Recipients in BCC (the other recipients do not see them), as '
          'confirmed by the user, written like those in to. Optional.',
        ),
        'subject': Schema.string(
          description: 'The subject, as confirmed by the user.',
          minLength: 1,
        ),
        'body': Schema.string(
          description:
              'The text of the message, as confirmed by the user: plain text '
              'or simple Markdown.',
          minLength: 1,
        ),
      },
      required: ['to', 'subject', 'body'],
    ),
    annotations: ToolAnnotations(
      title: 'Send a new Smartschool message',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _sendMessage(session, request.arguments ?? const {}),
);

Schema _recipientsSchema(String description, {int? minItems}) => Schema.list(
  description: description,
  items: Schema.string(minLength: 1),
  minItems: minItems,
  maxItems: maxRecipientsPerField,
);

/// The fields of a message, in the order they are looked up and shown.
enum _Field {
  to('to', 'To'),
  cc('cc', 'CC'),
  bcc('bcc', 'BCC');

  const _Field(this.argument, this.label);

  final String argument;
  final String label;
}

Future<CallToolResult> _sendMessage(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final requests = {
    for (final field in _Field.values) field: _requests(arguments, field),
  };
  if (requests[_Field.to]!.isEmpty) {
    throw const ToolError(
      'to is empty: pass at least one recipient. Nothing was sent.',
    );
  }
  final subject = (arguments['subject'] as String? ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (subject.isEmpty) {
    throw const ToolError(
      'subject is empty: pass the subject of the message. Nothing was sent.',
    );
  }
  final body = (arguments['body'] as String? ?? '').trim();
  if (body.isEmpty) {
    throw const ToolError(
      'body is empty: pass the text of the message. Nothing was sent.',
    );
  }
  final html = markdownToHtml(body);

  try {
    final summary = await session.run(
      (client) => _send(client, requests, subject: subject, html: html),
    );
    return CallToolResult(
      content: [TextContent(text: 'Sent the message.\n$summary')],
    );
  } on SendNotConfirmed catch (error) {
    return notConfirmedResult('The message', error);
  }
}

/// The recipients of [field] in [arguments], each once (ignoring case and
/// extra spaces).
List<RecipientRequest> _requests(Map<String, Object?> arguments, _Field field) {
  final name = field.argument;
  final values = switch (arguments[name]) {
    null => const <Object?>[],
    final List<Object?> values => values,
    _ => throw ToolError(
      '$name must be a list of recipients. Nothing was sent.',
    ),
  };
  final seen = <String>{};
  final requests = <RecipientRequest>[];
  for (final value in values) {
    if (value is! String || value.trim().isEmpty) {
      throw ToolError(
        'Each recipient in $name must be a name, like "Sven Lamber (user '
        '146)"; ${value is String ? 'an empty one' : '$value'} is not. '
        'Nothing was sent.',
      );
    }
    if (seen.add(normalName(value))) {
      requests.add(RecipientRequest.parse(value));
    }
  }
  return requests;
}

/// Looks up the recipients of [requests], sends the message with [client]
/// and returns to whom and with which subject ([sendSummary]).
///
/// Every recipient is looked up (each name searched once) before anything is
/// sent. When one does not name exactly one user or group, or one is in two
/// fields, it throws a [ToolError] and sends nothing. The message is sent
/// once, with [submitOnce], which says why repeating this (as
/// [SmartschoolSession.run] does when Smartschool rejects the session)
/// cannot send it twice, and turns a send that Smartschool does not confirm
/// into a [SendNotConfirmed].
Future<String> _send(
  SmartschoolClient client,
  Map<_Field, List<RecipientRequest>> requests, {
  required String subject,
  required String html,
}) async {
  final messages = MessagesService(client);
  try {
    final recipients = await _lookUp(messages, requests);
    List<MessageSearchUser> users(_Field field) => [
      for (final recipient in recipients[field]!)
        if (recipient case UserRecipient(:final user)) user,
    ];
    List<MessageSearchGroup> groups(_Field field) => [
      for (final recipient in recipients[field]!)
        if (recipient case GroupRecipient(:final group)) group,
    ];
    List<String> labels(_Field field) => [
      for (final recipient in recipients[field]!) recipient.label,
    ];

    final summary = sendSummary(
      to: labels(_Field.to),
      cc: labels(_Field.cc),
      bcc: labels(_Field.bcc),
      subject: subject,
    );
    await submitOnce(
      () => messages.sendMessage(
        SendMessageParams(
          to: users(_Field.to),
          cc: users(_Field.cc),
          bcc: users(_Field.bcc),
          toGroups: groups(_Field.to),
          ccGroups: groups(_Field.cc),
          bccGroups: groups(_Field.bcc),
          subject: subject,
          bodyHtml: html,
        ),
      ),
      tool: 'send_message',
      what: 'the message "$subject"',
      summary: summary,
      composeRefused:
          'Smartschool did not open its compose form, or did not take the '
          'recipients of the message on it, so nothing was sent. The account '
          'may not be allowed to send messages, or to send to one of the '
          'recipients; the details are in the server log.',
    );
    return summary;
  } finally {
    await messages.dispose();
  }
}

/// The recipient each of [requests] names, by field, each once.
///
/// Throws a [ToolError] that lists every request that names no user or
/// group, or several, with who the search does find, or that names a
/// recipient in two fields.
Future<Map<_Field, List<Recipient>>> _lookUp(
  MessagesService messages,
  Map<_Field, List<RecipientRequest>> requests,
) async {
  final searches = <String, List<Recipient>>{};
  final unclear = <String>[];
  final found = <_Field, List<Recipient>>{};
  for (final MapEntry(key: field, value: fieldRequests) in requests.entries) {
    final recipients = <Recipient>[];
    for (final request in fieldRequests) {
      final results = searches[normalName(request.name)] ??=
          await searchRecipients(messages, request.name);
      switch (request.matches(results)) {
        case [final recipient]:
          recipients.add(recipient);
        case []:
          unclear.add(
            '- "${request.text}": Smartschool finds no user or group with '
            '${request.id == null ? 'exactly that name' : 'that name and id'}'
            '${_candidates(results, 'It finds')}',
          );
        case final matches:
          unclear.add(
            '- "${request.text}": Smartschool finds '
            '${countRecipients(matches)} with that name'
            '${_candidates(matches, 'They are')}',
          );
      }
    }
    found[field] = withoutRepeats(recipients);
  }
  if (unclear.isNotEmpty) {
    throw ToolError(
      [
        'Nothing was sent: not every recipient names exactly one user or '
            'group.',
        ...unclear,
        'Show the user who Smartschool finds and let them choose: never '
            'choose for them. Then call send_message again with each '
            'recipient as listed before the "|", like "Sven Lamber (user '
            '146)".',
      ].join('\n'),
    );
  }

  // A recipient in two fields would get the message in both; rather ask.
  for (final (index, field) in _Field.values.indexed) {
    for (final earlier in _Field.values.take(index)) {
      for (final recipient in found[field]!) {
        if (found[earlier]!.any((other) => sameRecipient(other, recipient))) {
          throw ToolError(
            '${recipient.reference} is in both ${earlier.label} and '
            '${field.label}: name each recipient in one of them only. '
            'Nothing was sent.',
          );
        }
      }
    }
  }
  return found;
}

/// [recipients] as lines under an unclear recipient, introduced by [intro],
/// at most [_maxListedCandidates]; only the full stop when there are none.
String _candidates(List<Recipient> recipients, String intro) {
  if (recipients.isEmpty) return '.';
  final listed = recipients.take(_maxListedCandidates);
  final left = recipients.length - listed.length;
  return [
    '. $intro:',
    for (final recipient in listed) '  - ${recipient.listing}',
    if (left > 0)
      '  - and $left more: look them up with search_recipients and a longer '
          'part of the name.',
  ].join('\n');
}
