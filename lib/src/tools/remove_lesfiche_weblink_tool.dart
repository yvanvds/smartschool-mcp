import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import 'server_tool.dart';

/// `remove_lesfiche_weblink`: removes one weblink from a lesfiche in the
/// user's own library of the Lesfiches module (the library's
/// `LessonContentService.removeWeblink`, dartschool#129), and gives the
/// lesfiche back as `read_lesfiche` shows it.
///
/// Marked destructive: the weblink is gone, and the module keeps no copy of
/// it. A second call finds no weblink with that id and changes nothing: it
/// is idempotent. The tool reads the lesfiche first, in the session action
/// of the removal, and refuses a weblink id it does not have before sending
/// anything; the library retries the removal after logging in again, as a
/// read.
ServerTool removeLesficheWeblinkTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'remove_lesfiche_weblink',
    title: 'Remove a weblink from a Smartschool lesfiche',
    description:
        'Removes one weblink from a lesfiche in the user\'s own library '
        '("Mijn lesfiches") of the Smartschool Lesfiches module, by the id '
        'and kind list_lesfiches shows and the weblink\'s id as '
        'read_lesfiche shows it at the end of the weblink\'s line. The '
        'weblink is gone: the module keeps no copy of it, and the lesfiche '
        'stays. Before calling this tool, show the user the lesfiche (name '
        'and kind) and the weblink (name and address), and only call this '
        'tool after the user has explicitly confirmed it; then call it once '
        'per weblink. To replace a dead link, change it with '
        'set_lesfiche_weblink instead. Whether a lesson planned from the '
        'lesfiche earlier changes with it is not known. A lesfiche in the '
        'trash cannot be changed. The result gives the lesfiche as changed. '
        'If the result says the weblink may or may not have been removed, '
        'check the lesfiche with read_lesfiche and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
        'weblink_id': Schema.string(
          description:
              'The id of the weblink, as read_lesfiche shows it at the end '
              'of the weblink\'s line.',
          minLength: 1,
        ),
      },
      required: ['lesfiche', 'weblink_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Remove a weblink from a Smartschool lesfiche',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _remove(session, request.arguments ?? const {}),
);

Future<CallToolResult> _remove(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final weblinkId = lesfichePartIdArgument(
    arguments['weblink_id'],
    name: 'weblink_id',
    what: 'weblink',
  );

  LessonContentDetail? lesfiche;
  LessonContentWeblink? weblink;
  String title() => lesfiche == null
      ? 'the ${lesficheKindName(type)} $id'
      : lesficheTitle(lesfiche!);
  String named() => weblink == null
      ? 'the weblink $weblinkId'
      : 'the weblink "${weblink!.name}"';

  try {
    await withLesficheWrite(
      session,
      (client) async {
        final read = lesfiche = (await readLesficheDetail(
          client,
          type,
          id,
          withCourseNames: false,
        )).detail;
        final found = weblink = lesficheWeblinkById(read, weblinkId);
        await LessonContentService(client).removeWeblink(read, found.id);
      },
      what: () => 'the removal of ${named()} from ${title()}',
      nothingDone: lesficheUnchanged,
      orGone: 'the weblink was removed meanwhile',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return lesficheWriteNotConfirmed(
      tool: 'remove_lesfiche_weblink',
      what: _capitalised(named()),
      done: 'removed from ${title()}',
      check:
          'read the lesfiche with ${readLesficheCall(type, id)} to see '
          'whether it is still there',
      error: error,
    );
  }
  log('remove_lesfiche_weblink: removed');
  return lesficheChangedResult(session, type, id, [
    'Removed ${named()} (${weblink!.url}) from ${title()}.',
  ]);
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
