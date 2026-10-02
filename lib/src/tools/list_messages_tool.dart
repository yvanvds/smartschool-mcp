import 'package:dart_mcp/server.dart';

import '../messages/message_box.dart';
import '../messages/message_filter.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'arguments.dart';
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
        'short; to see older messages, pass until (for example the date of '
        'the oldest message shown).',
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
  final (:since, :until) = dateRangeArguments(arguments);
  final filter = MessageFilter(
    query: query,
    unreadOnly: arguments['unread_only'] as bool? ?? false,
    since: since,
    until: until,
    limit: intArgument(arguments, 'limit') ?? MessageFilter.defaultLimit,
  );
  final filtered =
      (query?.isNotEmpty ?? false) ||
      filter.unreadOnly ||
      filter.since != null ||
      filter.until != null;

  // The box is listed newest first, page by page, until the pages listed
  // decide what to show. Like every session action, this may run more than
  // once.
  final (:headers, :stop) = await withMessages(session, (messages) async {
    var matching = 0;
    _Stop? stop;
    final headers = await box.headers(
      messages,
      stopAfter: (page) {
        matching += page.where(filter.matches).length;
        if (filter.reachesPastSince(page)) {
          stop = _Stop.pastSince;
        } else if (matching > filter.limit) {
          stop = _Stop.pastLimit;
        }
        return stop != null;
      },
    );
    return (headers: headers, stop: stop);
  });
  final (:shown, :matching) = filter.apply(headers);

  final total = _count(headers.length, 'message');
  final String summary;
  if (headers.isEmpty) {
    summary = '${box.label}: no messages.';
  } else if (matching == 0) {
    summary = '${box.label}: no messages match the filters ($total checked).';
  } else if (stop == _Stop.pastLimit) {
    // How many older messages match is unknown: they were not listed.
    final count = _count(shown.length, 'message');
    final verb = shown.length == 1 ? 'matches' : 'match';
    summary =
        '${box.label}: more than $count${filtered ? ' $verb the filters' : ''}'
        '; showing the newest ${shown.length} (raise limit, or pass until to '
        'see older ones), newest first.';
  } else if (filtered) {
    // A listing that stopped past since left out older messages, which
    // cannot match.
    final checked = stop == _Stop.pastSince ? 'the newest $total' : total;
    summary =
        '${box.label}: $matching of $checked '
        'match${matching == 1 ? 'es' : ''} the filters'
        '${_cut(shown.length, matching)}, newest first.';
  } else {
    summary =
        '${box.label}: $total${_cut(shown.length, matching)}, newest first.';
  }
  final lines = [
    summary,
    for (final message in shown) '- ${formatHeaderLine(message, box)}',
  ];
  return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
}

/// Why a box was not listed to the end.
enum _Stop {
  /// More messages matched than the limit: older ones would not be shown.
  pastLimit,

  /// The listing reached messages from before since: older ones cannot
  /// match.
  pastSince,
}

/// Notes that only [shown] of the [matching] messages are listed.
String _cut(int shown, int matching) => shown < matching
    ? '; showing the newest $shown (raise limit or narrow the filters to see '
          'the rest)'
    : '';

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
