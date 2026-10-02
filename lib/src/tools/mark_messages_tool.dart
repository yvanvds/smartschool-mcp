import 'package:dart_mcp/server.dart';

import '../messages/message_box.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'message_changes.dart';
import 'server_tool.dart';

/// The boxes whose messages `mark_messages` marks. A sent message has no
/// read state for the user.
const _boxes = [MessageBox.inbox, MessageBox.archive];

/// `mark_messages`: marks messages in the inbox or the archive as read or
/// unread, and says per id what happened.
ServerTool markMessagesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'mark_messages',
    title: 'Mark Smartschool messages read or unread',
    description:
        'Marks Smartschool messages as read or unread, as the user can in '
        'Smartschool. Reading a message with read_message does not mark it '
        'as read; this tool does. Pass the ids from list_messages and the '
        'box the messages are in (inbox or archive; sent messages have no '
        'read state for the user), at most $maxMessageIds per call. Marking '
        'can be undone: mark the messages the other way. When the user asks '
        'you to mark messages ("Markeer alles van de directie van vorige '
        'week als gelezen"), mark them with this tool. Do not mark messages '
        'the user did not ask about, also not after reading them for the '
        'user. When the user only asks which messages they could mark, do '
        'not mark anything: propose a list and let the user choose. The '
        'result says per id whether it was marked, or could not be marked '
        'and why.',
    inputSchema: Schema.object(
      properties: {
        'message_ids': messageIdsSchema(
          description:
              'The ids of the messages to mark, from list_messages. At most '
              '$maxMessageIds.',
        ),
        'read': Schema.bool(
          description: 'true marks the messages as read, false as unread.',
        ),
        'box': MessageBox.schema(
          description:
              'The box the messages are in: inbox (default) or archive.',
          boxes: _boxes,
        ),
      },
      required: ['message_ids', 'read'],
    ),
    annotations: ToolAnnotations(
      title: 'Mark Smartschool messages read or unread',
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _mark(session, request.arguments ?? const {}),
);

Future<CallToolResult> _mark(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = messageIdsArgument(arguments);
  // The input schema guarantees a bool, and a box of _boxes.
  final read = arguments['read'] as bool;
  final box = MessageBox.parse(arguments['box']);
  final results = await withMessages(
    session,
    (messages) => changeEach(messages, box, ids, (id) async {
      // Marking unread names the folder of a message in the archive, as the
      // library asks; marking read cannot (yvanvds/dartschool#94).
      // Smartschool answers with the message's id and read state, 1 read or
      // 0 unread. The library reads an answer without a state as 0 as well
      // (yvanvds/dartschool#95); one without the message's id is caught.
      final change = read
          ? await messages.markRead(id, boxType: box.boxType)
          : await messages.markUnread(
              id,
              boxType: box.boxType,
              boxId: box == MessageBox.archive
                  ? await messages.getArchiveBoxId()
                  : 0,
            );
      return change != null &&
          change.id == id &&
          change.newValue == (read ? 1 : 0);
    }),
  );
  final state = read ? 'read' : 'unread';
  return changesResult(
    results,
    box: box,
    wording: ChangeWording(
      done: (messages) => 'Marked $messages as $state',
      heading: 'Marked as $state',
      verb: 'marked',
    ),
    changedLine: (header) => formatHeaderLine(header, box, unread: !read),
  );
}
