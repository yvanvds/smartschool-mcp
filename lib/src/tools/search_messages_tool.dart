import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/html_to_text.dart';
import '../messages/message_box.dart';
import '../messages/message_cache.dart';
import '../messages/message_filter.dart';
import '../messages/message_format.dart';
import '../messages/message_search.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// At most this many message texts are downloaded per search: enough for
/// the newest [MessageBox.pageSize] messages of the inbox and of the
/// archive, the boxes searched by default.
const maxDownloadsPerSearch = 100;

/// How many message texts are downloaded at the same time, to be gentle on
/// Smartschool.
const downloadConcurrency = 4;

const defaultSearchLimit = 20;
const maxSearchLimit = 100;

/// The boxes searched when the call names none.
const defaultSearchBoxes = [MessageBox.inbox, MessageBox.archive];

/// `search_messages`: the messages whose text, subject or sender contains
/// some words, with a snippet around them.
///
/// The texts come from [cache] when they were downloaded before; the others
/// are downloaded, newest first, at most [maxDownloadsPerSearch] per call,
/// and saved there.
ServerTool searchMessagesTool(
  SmartschoolSession session,
  MessageTextCache cache,
) => ServerTool(
  definition: Tool(
    name: 'search_messages',
    title: 'Search Smartschool messages',
    description:
        'Searches the text of Smartschool messages, and their subject and '
        'sender, for words. Use it for questions about what a message said, '
        'like "In welk bericht stond de datum van de facultatieve '
        'verlofdag?". Every word must occur, in any order; case and accents '
        'do not matter, and a word also matches inside a longer word '
        '("verlof" finds "verlofdag"). Searches the inbox and the archive '
        'unless boxes says otherwise. Returns the matching messages newest '
        'first, each with its box, id, date, sender (recipients for sent '
        'messages) and subject, and a short snippet of the text around the '
        'words; to read one in full, call read_message with its id and box. '
        'The first search downloads the message texts and keeps them on this '
        'PC, so later searches are quick; at most $maxDownloadsPerSearch are '
        'downloaded per search, and the result says when messages were left '
        'unsearched because of that (search again to continue). Smartschool '
        'only returns the newest ${MessageBox.pageSize} messages of each box; '
        'older ones cannot be searched.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'The words to look for in the message text, subject and '
              'sender. Every word must occur, in any order.',
        ),
        'boxes': UntitledMultiSelectEnumSchema(
          description:
              'Which boxes to search: inbox, sent and/or archive. Default '
              'inbox and archive.',
          values: [for (final box in MessageBox.values) box.name],
          defaultValue: [for (final box in defaultSearchBoxes) box.name],
          minItems: 1,
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
              'At most this many matching messages, newest first. Default '
              '$defaultSearchLimit, at most $maxSearchLimit.',
          minimum: 1,
          maximum: maxSearchLimit,
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(
      title: 'Search Smartschool messages',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _search(session, cache, request.arguments ?? const {}),
);

/// A message to search: listed in [box], its text still to be found.
final class _Candidate {
  _Candidate(this.box, this.header);

  final MessageBox box;
  final ShortMessage header;

  /// The message text, once read from the cache or downloaded.
  String? text;

  /// Whether Smartschool no longer had the message when it was downloaded.
  bool vanished = false;
}

Future<CallToolResult> _search(
  SmartschoolSession session,
  MessageTextCache cache,
  Map<String, Object?> arguments,
) async {
  final query =
      SearchQuery.parse(arguments['query'] as String? ?? '') ??
      (throw const ToolError('query is empty: pass the words to look for.'));
  final boxes = _boxes(arguments);
  final (:since, :until) = dateRangeArguments(arguments);
  final inRange = MessageFilter(since: since, until: until);
  final limit = intArgument(arguments, 'limit') ?? defaultSearchLimit;

  final stopwatch = Stopwatch()..start();
  // Counted over both runs when the session expires halfway.
  var downloads = 0;
  // Like every session action, this may run twice. The second run lists the
  // boxes again and finds the texts the first one saved in the cache.
  final (:listed, :candidates, :fromCache, :notSearched) = await withMessages(
    session,
    (messages) async {
      final listed = <MessageBox, int>{};
      final candidates = <_Candidate>[];
      for (final box in boxes) {
        final headers = await box.headers(messages);
        listed[box] = headers.length;
        candidates.addAll([
          for (final header in headers)
            if (inRange.matches(header)) _Candidate(box, header),
        ]);
      }
      candidates.sort((a, b) {
        final byDate = b.header.date.compareTo(a.header.date);
        return byDate != 0 ? byDate : b.header.id.compareTo(a.header.id);
      });

      await Future.wait([
        for (final candidate in candidates)
          cache
              .read(candidate.box.boxType, candidate.header.id)
              .then((text) => candidate.text = text),
      ]);
      final missing = [
        for (final candidate in candidates)
          if (candidate.text == null) candidate,
      ];
      // The newest ones first; the rest is left for a next search.
      final download = missing.take(maxDownloadsPerSearch).toList();
      await _forEachConcurrently(download, downloadConcurrency, (
        candidate,
      ) async {
        final (box, id) = (candidate.box, candidate.header.id);
        final message = await box.message(messages, id, allRecipients: false);
        downloads++;
        if (message == null) {
          candidate.vanished = true;
          return;
        }
        final text = candidate.text = htmlToText(message.body);
        await cache.write(box.boxType, id, text);
      });
      return (
        listed: listed,
        candidates: candidates,
        fromCache: candidates.length - missing.length,
        notSearched: missing.length - download.length,
      );
    },
  );

  final hits = [
    for (final candidate in candidates)
      if (candidate.text case final text?
          when query.matches([
            candidate.header.subject,
            candidate.header.sender,
            text,
          ]))
        candidate,
  ];
  final searched = candidates.where((c) => c.text != null).length;
  final vanished = candidates.where((c) => c.vanished).length;
  // Counts only: the query and the texts are personal.
  log(
    'search_messages: ${candidates.length} messages to search, '
    '$fromCache texts from the cache, $downloads downloaded, $notSearched '
    'left for a next search, ${hits.length} matching, '
    '${stopwatch.elapsedMilliseconds} ms',
  );

  final where = _joinAnd([for (final box in boxes) box.label]);
  final listedTotal = listed.values.fold(0, (sum, count) => sum + count);
  final words = query.terms.join(', ');
  final shown = hits.take(limit).toList();
  final cut = shown.length < hits.length
      ? '; showing the newest ${shown.length} (raise limit to see the rest)'
      : '';
  final lines = [
    if (listedTotal == 0)
      '$where: no messages.'
    else if (candidates.isEmpty)
      '$where: no messages in the date range ($listedTotal checked).'
    else if (hits.isEmpty)
      '$where: none of the ${_count(searched, 'message')} searched '
          'contains all of: $words.'
    else
      '$where: ${hits.length} of the ${_count(searched, 'message')} searched '
          '${hits.length == 1 ? 'contains' : 'contain'} all of: '
          '$words$cut, newest first.',
    for (final hit in shown) ...[
      '- ${hit.box.name} | ${formatHeaderLine(hit.header, hit.box)}',
      '  ${hit.text!.isEmpty ? '(no text)' : query.snippet(hit.text!)}',
    ],
    if (notSearched > 0)
      'Not searched: the ${_count(notSearched, 'oldest message')}, because at '
          'most $maxDownloadsPerSearch message texts are downloaded per '
          'search. Search again to search '
          '${notSearched == 1 ? 'it' : 'them'} too: downloaded texts are '
          'kept, so the next search only downloads the rest.',
    if (vanished > 0)
      'Skipped: ${_count(vanished, 'listed message')} that Smartschool no '
          'longer returned (deleted in the meantime?).',
    // Smartschool only returns the newest messages of a box
    // (yvanvds/dartschool#15).
    if (_joinAnd([
          for (final box in boxes)
            if (listed[box]! >= MessageBox.pageSize) box.label,
        ])
        case final full when full.isNotEmpty)
      'Note: Smartschool only returns the newest ${MessageBox.pageSize} '
          'messages of a box, so older messages in $full were not searched.',
  ];
  return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
}

/// The boxes named in the `boxes` argument, in the order of
/// [MessageBox.values], or [defaultSearchBoxes].
List<MessageBox> _boxes(Map<String, Object?> arguments) {
  final value = arguments['boxes'];
  if (value == null) return defaultSearchBoxes;
  if (value is! List || value.isEmpty) {
    throw const ToolError(
      'boxes must be a list of one or more of inbox, sent and archive.',
    );
  }
  final named = {for (final name in value) MessageBox.parse(name)};
  return [
    for (final box in MessageBox.values)
      if (named.contains(box)) box,
  ];
}

/// Runs [action] on each of [items], at most [concurrency] at a time, in
/// the order of [items].
///
/// After an error no further item is started; the first error is thrown once
/// the running actions are done.
Future<void> _forEachConcurrently<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) action,
) async {
  var next = 0;
  var failed = false;
  Future<void> worker() async {
    while (!failed && next < items.length) {
      final item = items[next++];
      try {
        await action(item);
      } catch (_) {
        failed = true;
        rethrow;
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < concurrency && i < items.length; i++) worker(),
  ]);
}

/// [parts] as `A`, `A and B` or `A, B and C`.
String _joinAnd(List<String> parts) => parts.length <= 1
    ? parts.join()
    : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
