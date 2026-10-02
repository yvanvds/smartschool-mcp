import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_box.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// At most this many message ids per `archive_messages` call.
const maxArchiveIds = 100;

/// `archive_messages`: moves inbox messages to Smartschool's archive folder
/// and says per id what happened.
ServerTool archiveMessagesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'archive_messages',
    title: 'Archive Smartschool messages',
    description:
        'Archives Smartschool messages: moves them from the inbox to the '
        'archive folder. Archiving can be undone: archived messages stay in '
        'the archive (list_messages with box archive shows them), and the '
        'user can move them back to the inbox in Smartschool. Pass the ids '
        'of inbox messages from list_messages, at most $maxArchiveIds per '
        'call. When the user asks which messages they could archive ("Wat '
        'kan ik zeker archiveren?"), do not archive anything: use '
        'list_messages and read_message to propose a list and let the user '
        'choose. When the user asks you to archive messages, archive them '
        'with this tool. The result says per id whether it was archived, '
        'was already in the archive, or could not be archived and why.',
    inputSchema: Schema.object(
      properties: {
        'message_ids': Schema.list(
          description:
              'The ids of the inbox messages to archive, from list_messages. '
              'At most $maxArchiveIds.',
          items: Schema.int(minimum: 1),
          minItems: 1,
          maxItems: maxArchiveIds,
        ),
      },
      required: ['message_ids'],
    ),
    annotations: ToolAnnotations(
      title: 'Archive Smartschool messages',
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _archive(session, request.arguments ?? const {}),
);

Future<CallToolResult> _archive(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  // The input schema guarantees a list of 1 to maxArchiveIds whole numbers.
  // Duplicates (also 101 and 101.0) are dropped, keeping the order.
  final ids = {...intListArgument(arguments, 'message_ids')}.toList();
  final results = await withMessages(
    session,
    (messages) => _archiveIds(messages, ids),
  );
  return CallToolResult(
    // Only when nothing ended up in the archive.
    isError: results.every((r) => r.outcome.failed),
    content: [TextContent(text: _format(results))],
  );
}

/// What happened to one id.
enum _Outcome {
  archived('Archived', failed: false),
  alreadyArchived('Already in the archive', failed: false),
  notInInbox('Not archived, not in the inbox', failed: true),
  notConfirmed('Not archived, Smartschool did not confirm it', failed: true);

  const _Outcome(this.heading, {required this.failed});

  /// The heading of this outcome's list in the result.
  final String heading;
  final bool failed;
}

/// The outcome for one id, with the message's header when the inbox or the
/// archive listed it.
typedef _Result = ({int id, _Outcome outcome, ShortMessage? header});

/// Archives the inbox messages among [ids] and says what happened to each,
/// in the order of [ids].
///
/// Only ids found in the inbox are sent to Smartschool: what it does with
/// the id of a message elsewhere (sent, in the trash) is unknown. An id that
/// is not in the inbox is looked up in the archive: archiving is idempotent,
/// so one that is already there is not a failure (Claude repeating a call
/// whose answer got lost, for example).
///
/// Runs inside [withMessages], so it may run more than once. The archive
/// request comes last: when Smartschool rejects the session or restarts a
/// listing, nothing has been archived yet, and the repeat starts again from
/// the inbox listing.
Future<List<_Result>> _archiveIds(
  MessagesService messages,
  List<int> ids,
) async {
  final inbox = await _find(MessageBox.inbox, messages, ids);
  final archive = ids.every(inbox.containsKey)
      ? const <int, ShortMessage>{}
      : await _find(MessageBox.archive, messages, [
          for (final id in ids)
            if (!inbox.containsKey(id)) id,
        ]);
  final toArchive = [
    for (final id in ids)
      if (inbox.containsKey(id)) id,
  ];
  final confirmed = toArchive.isEmpty
      ? const <int>{}
      : {
          for (final change in await messages.moveToArchive(toArchive))
            if (change.newValue == 1) change.id,
        };
  _Result result(int id) => switch ((inbox[id], archive[id])) {
    (final header?, _) => (
      id: id,
      outcome: confirmed.contains(id)
          ? _Outcome.archived
          : _Outcome.notConfirmed,
      header: header,
    ),
    (null, final header?) => (
      id: id,
      outcome: _Outcome.alreadyArchived,
      header: header,
    ),
    (null, null) => (id: id, outcome: _Outcome.notInInbox, header: null),
  };
  return [for (final id in ids) result(id)];
}

/// The headers in [box] by id, listed newest first until all of [ids] are
/// among them (or to the end of the box).
Future<Map<int, ShortMessage>> _find(
  MessageBox box,
  MessagesService messages,
  List<int> ids,
) async {
  final missing = ids.toSet();
  final headers = await box.headers(
    messages,
    stopAfter: (page) {
      missing.removeAll([for (final header in page) header.id]);
      return missing.isEmpty;
    },
  );
  return {for (final header in headers) header.id: header};
}

/// [results] as text: a summary, a list per outcome, and notes on what to
/// do about failures.
String _format(List<_Result> results) {
  int count(_Outcome outcome) =>
      results.where((r) => r.outcome == outcome).length;
  final total = results.length;
  final archived = count(_Outcome.archived);
  final already = count(_Outcome.alreadyArchived);
  final failed = results.where((r) => r.outcome.failed).length;

  final String summary;
  if (archived == total) {
    summary = 'Archived ${_count(total, 'message')}.';
  } else {
    final rest = [
      if (already > 0)
        '$already ${already == 1 ? 'was' : 'were'} already in the archive',
      if (failed > 0) '$failed could not be archived',
    ];
    summary =
        'Archived $archived of ${_count(total, 'message')}; '
        '${rest.join(', ')}.';
  }

  final lines = [summary];
  for (final outcome in _Outcome.values) {
    final group = results.where((r) => r.outcome == outcome);
    if (group.isEmpty) continue;
    lines.add('${outcome.heading}:');
    for (final result in group) {
      lines.add(switch (result.header) {
        final header? => '- ${formatHeaderLine(header, MessageBox.inbox)}',
        null => '- id ${result.id}',
      });
    }
  }
  if (count(_Outcome.notInInbox) > 0) {
    lines.add(
      'Note: only messages in the inbox can be archived. Take the ids from '
      'list_messages on the inbox.',
    );
  }
  if (count(_Outcome.notConfirmed) > 0) {
    lines.add(
      'Note: Smartschool did not confirm that it archived the messages under '
      '"Not archived, Smartschool did not confirm it". Check with '
      'list_messages whether they are still in the inbox, then try again or '
      'let the user archive them in Smartschool.',
    );
  }
  return lines.join('\n');
}

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
