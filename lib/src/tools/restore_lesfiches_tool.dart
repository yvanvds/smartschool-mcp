import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_bulk.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `restore_lesfiches`: takes lesfiches out of the trash of the user's
/// Lesfiches module, back into the own library, in one write (the
/// library's `LessonContentService.restore`, dartschool#227).
///
/// The library takes each lesfiche as read, so the tool reads the trash
/// first (`getTrash`, without the course names), in the session action of
/// the write, and matches the ids given with it. An id it does not list is
/// looked up in the library (`getItems`): a lesfiche there is not in the
/// trash (nothing to restore); any other names no lesfiche. Both are
/// refused before anything is sent. A second call is refused so, and
/// changes nothing: idempotent. It changes the user's library, so it is
/// marked destructive (for Claude Desktop to ask for approval), as
/// `trash_lesfiches` is.
///
/// The library retries the restore after logging in again, as a read (it
/// names what it restores). When the module does not confirm it (an
/// exception for a lesfiche, such as the `404` of one that is no longer in
/// the trash, or no answer), the library throws a
/// [SmartschoolLessonContentSaveUnconfirmedError]: the tool reads the trash
/// again and says which lesfiches left it and which are still there
/// ([lesficheBulkPartialResult]).
ServerTool restoreLesfichesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'restore_lesfiches',
    title: 'Restore Smartschool lesfiches from the trash',
    description:
        'Takes lesfiches out of the trash of the user\'s Smartschool '
        'Lesfiches module, back into the user\'s own library, by the ids '
        'list_trashed_lesfiches shows: 1 to $maxLesficheBulkItems in one '
        'call, lessons and assignments together. Afterwards list_lesfiches '
        'lists them again, and they can be changed, copied and planned as '
        'before. Use it to undo trash_lesfiches, or to take an old lesfiche '
        'back. Before calling this tool, show the user each lesfiche by its '
        'name and kind as list_trashed_lesfiches shows it, and only call '
        'this tool after the user has explicitly confirmed it; then call it once, with all of '
        'them. An id that names no lesfiche in the trash is refused before '
        'anything is sent. If the result says the restore was not '
        'confirmed, it says which lesfiches left the trash and which not. '
        'For requests like "zet mijn lesfiche Lussen terug uit de '
        'prullenbak".',
    inputSchema: Schema.object(
      properties: {
        'lesfiches': lesficheIdsSchema(
          description:
              'The ids of the lesfiches to restore, as '
              'list_trashed_lesfiches shows them and as the user confirmed '
              'them, like b0000000-0000-4000-8000-000000000001: lessons and '
              'assignments together, at most $maxLesficheBulkItems.',
        ),
      },
      required: ['lesfiches'],
    ),
    annotations: ToolAnnotations(
      title: 'Restore Smartschool lesfiches from the trash',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _restore(session, request.arguments ?? const {}),
);

Future<CallToolResult> _restore(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = lesficheIdsArgument(arguments['lesfiches']);
  final nothingDone = ids.length == 1
      ? 'The lesfiche was not restored.'
      : 'None of the lesfiches was restored.';

  var chosen = const <LessonContentItem>[];
  final watch = Stopwatch()..start();
  try {
    await withLesficheWrite(
      session,
      (client) async {
        final lesfiches = LessonContentService(client);
        // First, in the action of the restore: the library takes each
        // lesfiche as read, with its kind and platform.
        final trash = await lesfiches.getTrash(withCourseNames: false);
        final (:found, :unknown) = findLesfiches(trash, ids);
        if (unknown.isNotEmpty) {
          final items = await lesfiches.getItems(withCourseNames: false);
          _refuseUnlisted(items, unknown, found);
        }
        refuseOtherLesficheKinds(found, action: 'restore');
        chosen = found;
        await lesfiches.restore(found);
      },
      what: () => chosen.isEmpty
          ? 'the restore of the lesfiches from the trash'
          : 'the restore of ${lesficheTitles(chosen)} from the trash',
      nothingDone: nothingDone,
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return _notConfirmed(session, chosen, error);
  }
  log(
    'restore_lesfiches: restored ${chosen.length} in '
    '${watch.elapsedMilliseconds} ms',
  );
  final them = chosen.length == 1 ? 'it' : 'them';
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Restored ${LesficheKind.all.count(chosen.length)} from the trash '
              'into the own library of the Lesfiches module:',
          for (final item in chosen)
            '- ${formatLesficheLine(item, withCourseNames: false)}',
          'list_lesfiches lists $them again, and '
              '${chosen.length == 1 ? 'it' : 'they'} can be changed, '
              'copied and planned as before.',
        ].join('\n'),
      ),
    ],
  );
}

/// Throws the [ToolError] for the ids [unknown], which the trash does not
/// list: those of [items] (the library) are not in the trash, the others
/// name no lesfiche. [found] are those the trash lists, for the note that
/// they were not restored either.
Never _refuseUnlisted(
  List<LessonContentItem> items,
  List<String> unknown,
  List<LessonContentItem> found,
) {
  final (found: listed, unknown: missing) = findLesfiches(items, unknown);
  final parts = [
    if (listed.isNotEmpty)
      '${capitalised(lesficheTitles(listed))} '
          '${listed.length == 1 ? 'is' : 'are'} not in the trash: '
          'list_lesfiches lists ${listed.length == 1 ? 'it' : 'them'} in '
          'the library, so there is nothing to restore.',
    if (missing.isNotEmpty)
      'The trash holds no ${missing.length == 1 ? 'lesfiche' : 'lesfiches'} '
          'with ${lesficheIdsPhrase(missing)}, and neither does the library. '
          'Take the ids from list_trashed_lesfiches.',
    if (found.isNotEmpty) 'The others were not restored either.',
  ];
  throw ToolError('${parts.join(' ')} $nothingSent');
}

/// The result when the module did not confirm the restore of [chosen]
/// ([error]): which of them left the trash, read again, and which not.
Future<CallToolResult> _notConfirmed(
  SmartschoolSession session,
  List<LessonContentItem> chosen,
  SmartschoolLessonContentSaveUnconfirmedError error,
) async {
  final one = chosen.length == 1;
  final trash = await readLesficheTrashAfter(session);
  if (trash == null) {
    return lesficheWriteNotConfirmed(
      tool: 'restore_lesfiches',
      what: lesficheSubject(chosen),
      done: 'restored',
      also: one ? null : 'Some of them may have been restored, and others not.',
      check:
          'list the trash with list_trashed_lesfiches to see '
          '${one ? 'whether it is still there' : 'which are still there'}',
      error: error,
    );
  }
  final inTrash = {for (final item in trash) item.id.toLowerCase()};
  bool restored(LessonContentItem item) =>
      !inTrash.contains(item.id.toLowerCase());
  return lesficheBulkPartialResult(
    tool: 'restore_lesfiches',
    sent: one
        ? 'The restore of ${lesficheTitle(chosen.single)}'
        : 'The restore of ${chosen.length} lesfiches',
    readFrom: 'the trash',
    doneHeader: 'Out of the trash, in the library now:',
    done: [
      for (final item in chosen)
        if (restored(item))
          '- ${formatLesficheLine(item, withCourseNames: false)}',
    ],
    notDoneHeader: 'Still in the trash:',
    notDone: [
      for (final item in chosen)
        if (!restored(item))
          '- ${formatLesficheLine(item, withCourseNames: false)}',
    ],
    advice:
        'Tell the user which were restored and which not, and ask before '
        'trying the others again.',
  );
}
