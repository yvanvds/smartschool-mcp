import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_box.dart';
import '../messages/message_format.dart';
import 'arguments.dart';

// The tools that change messages named by id: their `message_ids`
// argument, and, for a change Smartschool makes one message at a time
// (mark_messages, flag_messages), making it and saying per id what
// happened.

/// At most this many message ids per call of a tool that changes messages.
const maxMessageIds = 100;

/// The input schema of a tool's `message_ids` argument: 1 to
/// [maxMessageIds] ids.
Schema messageIdsSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.int(minimum: 1),
  minItems: 1,
  maxItems: maxMessageIds,
);

/// The `message_ids` argument of [arguments] without duplicates (also 101
/// and 101.0), in the order given.
///
/// The input schema ([messageIdsSchema]) guarantees a list of 1 to
/// [maxMessageIds] whole numbers.
List<int> messageIdsArgument(Map<String, Object?> arguments) =>
    {...intListArgument(arguments, 'message_ids')}.toList();

/// What happened to one message id of a change.
enum ChangeOutcome {
  /// Smartschool confirmed the change.
  changed(failed: false),

  /// The box does not hold the message, so nothing was sent for it.
  notInBox(failed: true),

  /// Smartschool did not confirm the change: its answer gave no new state,
  /// or another one than asked.
  notConfirmed(failed: true);

  const ChangeOutcome({required this.failed});

  final bool failed;
}

/// The outcome of a change for one id, with the message's header as the box
/// listed it, before the change (none for [ChangeOutcome.notInBox]).
typedef ChangeResult = ({int id, ChangeOutcome outcome, ShortMessage? header});

/// Makes a change to each message of [ids] in [box], one message at a
/// time, and says what happened to each, in the order of [ids].
///
/// [box] is listed until all of [ids] are found ([MessageBox.find]). Only
/// ids found there are passed to [change]: what Smartschool does with the
/// id of a message in another box is unknown. [change] makes the change to
/// one message and returns whether Smartschool confirmed it.
///
/// Meant to run inside [withMessages], so it may run more than once, also
/// after some messages were changed: [change] must set a state, not toggle
/// it. A repeat lists the box again and changes each message again.
Future<List<ChangeResult>> changeEach(
  MessagesService messages,
  MessageBox box,
  List<int> ids,
  Future<bool> Function(int id) change,
) async {
  final headers = await box.find(messages, ids);
  return [
    for (final id in ids)
      switch (headers[id]) {
        null => (id: id, outcome: ChangeOutcome.notInBox, header: null),
        final header => (
          id: id,
          outcome: await change(id)
              ? ChangeOutcome.changed
              : ChangeOutcome.notConfirmed,
          header: header,
        ),
      },
  ];
}

/// How a change is worded in its result.
class ChangeWording {
  const ChangeWording({
    required this.done,
    required this.heading,
    required this.verb,
  });

  /// The summary for the [messages] changed, like `Marked 2 messages as
  /// read` or `Marked 1 of 3 messages as read`.
  final String Function(String messages) done;

  /// The heading of the list of messages changed, like `Marked as read`.
  final String heading;

  /// The change as a past participle, like `marked`, for `could not be
  /// marked` and `Not marked`.
  final String verb;
}

/// [results] of a change of messages in [box] as a tool result: a summary,
/// a list per outcome and notes on what to do about failures. An error only
/// when no message was changed.
///
/// A message changed is shown by [changedLine]: its header line with the
/// new state. The others are shown as the box listed them.
CallToolResult changesResult(
  List<ChangeResult> results, {
  required MessageBox box,
  required ChangeWording wording,
  required String Function(ShortMessage header) changedLine,
}) {
  final total = _count(results.length, 'message');
  final changed = results.where((r) => !r.outcome.failed).length;
  final failed = results.length - changed;
  final verb = wording.verb;
  String heading(ChangeOutcome outcome) => switch (outcome) {
    ChangeOutcome.changed => wording.heading,
    ChangeOutcome.notInBox => 'Not $verb, not in ${box.phrase}',
    ChangeOutcome.notConfirmed => 'Not $verb, Smartschool did not confirm it',
  };

  final lines = [
    failed == 0
        ? '${wording.done(total)}.'
        : '${wording.done('$changed of $total')}; $failed could not be '
              '$verb.',
  ];
  for (final outcome in ChangeOutcome.values) {
    final group = results.where((r) => r.outcome == outcome);
    if (group.isEmpty) continue;
    lines.add('${heading(outcome)}:');
    for (final result in group) {
      lines.add(switch ((outcome, result.header)) {
        (ChangeOutcome.changed, final header?) => '- ${changedLine(header)}',
        (_, final header?) => '- ${formatHeaderLine(header, box)}',
        (_, null) => '- id ${result.id}',
      });
    }
  }
  bool any(ChangeOutcome outcome) => results.any((r) => r.outcome == outcome);
  if (any(ChangeOutcome.notInBox)) {
    lines.add(
      'Note: the messages under "${heading(ChangeOutcome.notInBox)}" are '
      'not in ${box.phrase}. Take the ids from list_messages on the box the '
      'messages are in, and pass that box.',
    );
  }
  if (any(ChangeOutcome.notConfirmed)) {
    lines.add(
      'Note: Smartschool did not confirm the change of the messages under '
      '"${heading(ChangeOutcome.notConfirmed)}"; they are shown as they '
      'were before. Check with list_messages (box ${box.name}) whether they '
      'changed, then try again or let the user change them in Smartschool.',
    );
  }
  return CallToolResult(
    isError: changed == 0,
    content: [TextContent(text: lines.join('\n'))],
  );
}

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
