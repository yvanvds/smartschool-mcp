import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_box.dart';
import '../messages/message_format.dart';
import '../session.dart';
import 'message_changes.dart';
import 'server_tool.dart';

/// `trash_messages`: moves messages of the inbox, the sent box or the
/// archive to Smartschool's trash, and says per id what happened.
///
/// A move, not a deletion: the user can restore a message from the trash in
/// Smartschool, until the trash is emptied. But this server cannot take a
/// message out of the trash again (the library has no such move), and the
/// trash can be emptied. So, unlike archiving, the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call),
/// and Claude is told to show the list and wait for the user's confirmation
/// first.
///
/// Each message is moved with `moveToTrashFrom`, which names the box of the
/// copy it moves (yvanvds/dartschool#60, #64), never with `moveToTrash`: its
/// `quick delete` names the id only, and deletes a copy in the trash for
/// good (yvanvds/dartschool#19, #61).
ServerTool trashMessagesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'trash_messages',
    title: 'Move Smartschool messages to the trash',
    description:
        "Moves Smartschool messages to the user's trash in Smartschool. It "
        'is a move, not a deletion: the user can restore a message from the '
        'trash in Smartschool itself, as long as the trash has not been '
        'emptied. This tool cannot take a message out of the trash again, '
        'nor empty the trash. Pass the ids from list_messages and the box '
        'the messages are in (inbox, sent or archive), at most '
        '$maxMessageIds per call. When the user asks you to throw messages '
        'away or delete them ("Gooi die nieuwsbrieven weg"), first show the '
        'user the messages you will move to the trash (date, sender or '
        'recipients, subject), and only call this tool, with exactly those '
        'ids, after the user has explicitly confirmed that list. When the '
        'user only asks which messages they could throw away, do not move '
        'anything: propose a list and let the user choose. To get a message '
        'out of the inbox without throwing it away, use archive_messages. A '
        'message the user sent to themselves has the same id in the inbox '
        'and in the sent box: this tool moves only the copy in the box '
        'passed, and the other copy stays in its box. The result says per '
        'id whether it was moved to the trash, was not in the box (also a '
        'message that is in the trash already), or was still in the box '
        'after the move.',
    inputSchema: Schema.object(
      properties: {
        'message_ids': messageIdsSchema(
          description:
              'The ids of the messages to move to the trash, from '
              'list_messages, as the user confirmed them. At most '
              '$maxMessageIds.',
        ),
        'box': MessageBox.schema(
          description:
              'The box the messages are in: inbox (default), sent or '
              'archive.',
        ),
      },
      required: ['message_ids'],
    ),
    annotations: ToolAnnotations(
      title: 'Move Smartschool messages to the trash',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _trash(session, request.arguments ?? const {}),
);

Future<CallToolResult> _trash(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = messageIdsArgument(arguments);
  final box = MessageBox.parse(arguments['box']);
  // Kept across the runs of the action, which withMessages may repeat after
  // some messages were moved (see changeEach): the messages passed to the
  // move, and those whose move went out. withMessages repeats the action
  // when moveToTrashFrom throws a SmartschoolSessionExpiredError, which it
  // throws only when Smartschool refused the session for the move itself
  // (since flutter_smartschool 0.3.4, yvanvds/dartschool#115): that move
  // was not made, so it is sent again.
  final started = <int, ShortMessage>{};
  final moved = <int>{};
  final results = await withMessages(
    session,
    (messages) => changeEach(messages, box, ids, started: started, (id) async {
      if (!moved.contains(id)) {
        try {
          // Returns what its own check after the move found: whether the
          // box no longer holds the message, or null when Smartschool's
          // answer said neither.
          final left = await messages.moveToTrashFrom(
            id,
            boxType: box.boxType,
            boxId: await box.folderId(messages),
          );
          moved.add(id);
          if (left != null) return left;
        } on SmartschoolMoveUncheckedError {
          // The move went out and only the library's check after it failed:
          // checked below, never moved again.
          moved.add(id);
        }
      }
      // A move that went out in an earlier run, or whose check failed or
      // said neither: getMessage returns null once the box no longer holds
      // the message, also for a message just moved to the trash, as the
      // library's docs of getMessage and SmartschoolMoveUncheckedError say.
      return await box.message(messages, id, allRecipients: false) == null;
    }),
  );
  return changesResult(
    results,
    box: box,
    wording: ChangeWording(
      done: (messages) => 'Moved $messages from ${box.phrase} to the trash',
      heading: 'Moved to the trash',
      verb: 'moved',
      unconfirmed: (
        reason: 'still in ${box.phrase}',
        note: (heading) =>
            'the messages under "$heading" were still in ${box.phrase} '
            'after the move to the trash. Check with list_messages (box '
            '${box.name}) whether they are still there, then try again or '
            'let the user move them to the trash in Smartschool.',
      ),
    ),
    changedLine: (header) => formatHeaderLine(header, box),
  );
}
