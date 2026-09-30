import 'package:dart_mcp/server.dart';

import '../messages/message_box.dart';
import '../messages/message_filter.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_messages`: the headers of the messages in a box, newest first,
/// optionally filtered.
ServerTool listMessagesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_messages',
    title: 'List Smartschool messages',
    description:
        'Lists the Smartschool messages in the inbox, the sent box or the '
        'archive, newest first: one line per message with its id, date, '
        'sender (recipients for sent messages), subject and whether it is '
        'unread, has attachments or has a colour flag. Only headers: to see '
        'what a message says, call read_message with its id and the same '
        'box. Use this first for questions like "Welke ongelezen berichten '
        'heb ik?" (unread_only) or "Wat kreeg ik gisteren over het '
        'oudercontact?" (query, since and until). query matches the subject '
        'and the sender name only, not the message text. The result says how '
        'many messages matched, so you can tell when the limit cut the list '
        'short. Smartschool only returns the newest '
        '${MessageBox.pageSize} messages of each box; older ones cannot be '
        'listed.',
    inputSchema: Schema.object(
      properties: {
        'box': MessageBox.schema(
          description:
              'Which box to list: inbox (default), sent or archive (messages '
              'the user archived).',
        ),
        'query': Schema.string(
          description:
              'Words to look for in the subject and the sender name, '
              'case-insensitive. Every word must occur, in any order.',
        ),
        'unread_only': Schema.bool(
          description: 'Only unread messages. Default false.',
        ),
        'since': Schema.string(
          description:
              'Only messages from this date on, like 2024-03-15 (the whole '
              'day counts) or 2024-03-15 14:30. Smartschool time (Belgium).',
        ),
        'until': Schema.string(
          description:
              'Only messages up to this date, like 2024-03-15 (the whole day '
              'counts) or 2024-03-15 14:30.',
        ),
        'limit': Schema.int(
          description:
              'At most this many messages, newest first. Default '
              '${MessageFilter.defaultLimit}, at most '
              '${MessageFilter.maxLimit}.',
          minimum: 1,
          maximum: MessageFilter.maxLimit,
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List Smartschool messages',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final box = MessageBox.parse(arguments['box']);
  final query = (arguments['query'] as String?)?.trim();
  final filter = MessageFilter(
    query: query,
    unreadOnly: arguments['unread_only'] as bool? ?? false,
    since: switch (arguments['since']) {
      final String since => parseDateArgument('since', since),
      _ => null,
    },
    until: switch (arguments['until']) {
      final String until => parseDateArgument('until', until, endOfDay: true),
      _ => null,
    },
    limit: arguments['limit'] as int? ?? MessageFilter.defaultLimit,
  );
  if ((filter.since, filter.until) case (
    final since?,
    final until?,
  ) when since.isAfter(until)) {
    throw const ToolError('since must not be later than until.');
  }
  final filtered =
      (query?.isNotEmpty ?? false) ||
      filter.unreadOnly ||
      filter.since != null ||
      filter.until != null;

  final headers = await withMessages(session, box.headers);
  final (:shown, :matching) = filter.apply(headers);

  final total = _count(headers.length, 'message');
  final String summary;
  if (headers.isEmpty) {
    summary = '${box.label}: no messages.';
  } else if (matching == 0) {
    summary = '${box.label}: no messages match the filters ($total checked).';
  } else if (filtered) {
    summary =
        '${box.label}: $matching of $total '
        'match${matching == 1 ? 'es' : ''} the filters'
        '${_cut(shown.length, matching)}, newest first.';
  } else {
    summary =
        '${box.label}: $total${_cut(shown.length, matching)}, newest first.';
  }
  final lines = [
    summary,
    for (final message in shown) '- ${formatHeaderLine(message, box)}',
    // Smartschool only returns the newest messages of a box
    // (yvanvds/dartschool#15).
    if (headers.length >= MessageBox.pageSize)
      'Note: Smartschool only returns the newest ${MessageBox.pageSize} '
          'messages of a box, so older messages are missing from this list '
          'and cannot be found with the filters.',
  ];
  return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
}

/// Notes that only [shown] of the [matching] messages are listed.
String _cut(int shown, int matching) => shown < matching
    ? '; showing the newest $shown (raise limit or narrow the filters to see '
          'the rest)'
    : '';

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
