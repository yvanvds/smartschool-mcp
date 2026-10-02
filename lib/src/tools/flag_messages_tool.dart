import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_box.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'message_changes.dart';
import 'server_tool.dart';

/// The flags `flag_messages` sets by name: the names list_messages shows
/// ([flagName]), and `none`, which clears the flag.
final Map<String, MessageLabel> flagLabels = {
  for (final label in MessageLabel.values)
    flagName(label.value) ?? 'none': label,
};

/// `flag_messages`: sets or clears the colour flag of messages in a box,
/// and says per id what happened.
ServerTool flagMessagesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'flag_messages',
    title: 'Flag Smartschool messages',
    description:
        'Sets or clears the colour flag of Smartschool messages, the flag '
        'list_messages and read_message show: green, yellow, red or blue, '
        'or none to clear it. Pass the ids from list_messages and the box '
        'the messages are in (inbox, sent or archive), at most '
        '$maxMessageIds per call. A flag can be changed or cleared again at '
        'any time. When the user asks you to flag messages ("Zet een rode '
        'vlag op de berichten waar ik nog op moet antwoorden"), flag them '
        'with this tool. When the user only asks which messages they could '
        'flag, do not flag anything: propose a list and let the user choose. '
        'The result says per id whether its flag was set, or could not be '
        'set and why.',
    inputSchema: Schema.object(
      properties: {
        'message_ids': messageIdsSchema(
          description:
              'The ids of the messages to flag, from list_messages. At most '
              '$maxMessageIds.',
        ),
        'flag': UntitledSingleSelectEnumSchema(
          description:
              'The flag to set: green, yellow, red or blue; none '
              'clears the flag.',
          values: flagLabels.keys.toList(),
        ),
        'box': MessageBox.schema(
          description:
              'The box the messages are in: inbox (default), sent or '
              'archive.',
        ),
      },
      required: ['message_ids', 'flag'],
    ),
    annotations: ToolAnnotations(
      title: 'Flag Smartschool messages',
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _flag(session, request.arguments ?? const {}),
);

Future<CallToolResult> _flag(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = messageIdsArgument(arguments);
  // The input schema guarantees one of the names.
  final name = arguments['flag'] as String;
  final label = flagLabels[name]!;
  final box = MessageBox.parse(arguments['box']);
  final results = await withMessages(
    session,
    (messages) => changeEach(messages, box, ids, (id) async {
      // The request cannot name the folder of a message in the archive
      // (yvanvds/dartschool#94). Smartschool answers with the message's id
      // and flag. The library reads an answer without a flag as 0, no flag
      // (yvanvds/dartschool#95); one without the message's id is caught.
      final change = await messages.setLabel(id, label, boxType: box.boxType);
      return change != null &&
          change.id == id &&
          change.newValue == label.value;
    }),
  );
  final clear = label == MessageLabel.noFlag;
  return changesResult(
    results,
    box: box,
    wording: clear
        ? ChangeWording(
            done: (messages) => 'Cleared the flag of $messages',
            heading: 'Flag cleared',
            verb: 'cleared',
          )
        : ChangeWording(
            done: (messages) => 'Flagged $messages $name',
            heading: 'Flagged $name',
            verb: 'flagged',
          ),
    changedLine: (header) => formatHeaderLine(header, box, flag: label.value),
  );
}
