import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// At most this many lesfiches per call of `trash_lesfiches`.
const maxLesficheTrashItems = 20;

/// `trash_lesfiches`: moves lesfiches of the user's Lesfiches module,
/// lessons and assignments, to the module's trash in one move (the
/// library's `LessonContentService.trash`, dartschool#129).
///
/// A move, not a deletion: the lesfiches leave the list, and the user
/// restores them from the trash in the module itself; the library neither
/// restores a lesfiche nor deletes one for good. A lesson planned from one
/// of them earlier stays in the planner, which copied the lesfiche (its
/// info, attachments and weblinks, #117). Still the lesfiches leave the
/// user's library,
/// so the tool is marked destructive (for Claude Desktop to ask for
/// approval), and Claude is told to show the user each lesfiche by name and
/// kind and to call once after the user's confirmation. A second call
/// changes nothing: the lesfiches are no longer listed, so it is refused
/// before anything is sent. So it is marked idempotent, as
/// `remove_lesfiche_attachment` is.
///
/// The library takes each lesfiche as listed (its kind and platform go
/// into the move), so the tool reads the list first (`getItems`, without
/// the course names), in the session action of the move, and matches the
/// ids given with it (ignoring case). An id that names no listed lesfiche
/// is refused before anything is sent, with a note that a lesfiche in the
/// trash is not listed; so is a lesfiche of a kind the library cannot
/// write. Then all of them go in one move, which the library retries after
/// logging in again, as a read; a refused session repeats the action from
/// the read (`SmartschoolSession.run`), so a move is never sent with a
/// list read in an earlier session.
///
/// The module answers the move of a lesfiche that is in the trash already
/// with a bare `500`, and the library throws a
/// [SmartschoolLessonContentSaveUnconfirmedError] for it, and for an answer
/// whose `exceptions` are not empty: the result says that some or all of
/// them may or may not have been moved, and to check with
/// `list_lesfiches`.
ServerTool trashLesfichesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'trash_lesfiches',
    title: 'Move Smartschool lesfiches to the trash',
    description:
        'Moves lesfiches of the user\'s Smartschool Lesfiches module, lessons '
        'and assignments alike, to the module\'s trash, by the ids '
        'list_lesfiches shows: 1 to $maxLesficheTrashItems in one call. The '
        'lesfiches leave the user\'s library: list_lesfiches no longer lists '
        'them, and they can no longer be planned. It is a move, not a '
        'deletion: the user can restore them from the trash in the Lesfiches '
        'module itself. This tool cannot restore anything, nor delete '
        'anything for good. A lesson planned from one of them earlier stays '
        'in the planner: the planner copied the lesfiche when it was '
        'planned. Use it to clear out old lesfiches, or to undo a lesfiche '
        'made with create_lesfiche. Before calling this tool, show the user '
        'each lesfiche by its name and kind (lesson or assignment, as '
        'list_lesfiches shows it; two lesfiches can have the same name), say '
        'that the user can restore them from the trash in the Lesfiches '
        'module, and only call this tool after the user has explicitly '
        'confirmed it; then call it once, with all of them. An id that names '
        'none of the user\'s lesfiches is refused before anything is sent: a '
        'lesfiche that is in the trash already is not listed. If the result '
        'says the lesfiches may or may not have been moved, do not call this '
        'tool again for them: check with list_lesfiches which are still '
        'listed, and tell the user. For requests like "ruim mijn '
        'testlesfiches op".',
    inputSchema: Schema.object(
      properties: {
        'lesfiches': Schema.list(
          description:
              'The ids of the lesfiches to move to the trash, as '
              'list_lesfiches shows them and as the user confirmed them, '
              'like b0000000-0000-4000-8000-000000000001: lessons and '
              'assignments together, at most $maxLesficheTrashItems. The '
              'kind of each is taken from list_lesfiches.',
          items: Schema.string(minLength: 1),
          minItems: 1,
          maxItems: maxLesficheTrashItems,
        ),
      },
      required: ['lesfiches'],
    ),
    annotations: ToolAnnotations(
      title: 'Move Smartschool lesfiches to the trash',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _trash(session, request.arguments ?? const {}),
);

Future<CallToolResult> _trash(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = _idsArgument(arguments['lesfiches']);
  final nothingDone = ids.length == 1
      ? 'The lesfiche was not moved to the trash.'
      : 'None of the lesfiches was moved to the trash.';

  var chosen = const <LessonContentItem>[];
  final watch = Stopwatch()..start();
  try {
    await withLesficheWrite(
      session,
      (client) async {
        final lesfiches = LessonContentService(client);
        // First, in the action of the move: the library takes each
        // lesfiche as listed, with its kind and platform.
        final items = await lesfiches.getItems(withCourseNames: false);
        final found = chosen = _chosen(items, ids);
        await lesfiches.trash(found);
      },
      what: () => chosen.isEmpty
          ? 'the move of the lesfiches to the trash'
          : 'the move of ${_titles(chosen)} to the trash',
      nothingDone: nothingDone,
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    final one = chosen.length == 1;
    return lesficheWriteNotConfirmed(
      tool: 'trash_lesfiches',
      what: one
          ? _capitalised(lesficheTitle(chosen.single))
          : 'The ${chosen.length} lesfiches (${_titles(chosen)})',
      done: 'moved to the trash',
      also: one ? null : 'Some of them may have been moved, and others not.',
      check:
          'list the lesfiches with list_lesfiches (type all) to see '
          '${one ? 'whether it is still listed' : 'which are still listed'}: '
          'a lesfiche in the trash is not listed',
      error: error,
    );
  }
  log(
    'trash_lesfiches: moved ${chosen.length} in '
    '${watch.elapsedMilliseconds} ms',
  );
  final them = chosen.length == 1 ? 'it' : 'them';
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Moved ${LesficheKind.all.count(chosen.length)} to the trash of the '
              'Lesfiches module:',
          for (final item in chosen)
            '- ${formatLesficheLine(item, withCourseNames: false)}',
          'list_lesfiches no longer lists $them. The user can restore $them '
              'from the trash in the Lesfiches module itself; this server '
              'cannot restore $them, nor delete $them for good. A lesson '
              'planned from ${chosen.length == 1 ? 'it' : 'one of them'} '
              'earlier stays in the planner.',
        ].join('\n'),
      ),
    ],
  );
}

/// The `lesfiches` argument [value]: ids of lesfiches as `list_lesfiches`
/// shows them ([lesficheArgument]), each once (ignoring case), in the order
/// given. The input schema guarantees a list of 1 to
/// [maxLesficheTrashItems] texts.
///
/// Throws a [ToolError] that names the item for anything that is not such
/// an id, before anything is sent.
List<String> _idsArgument(Object? value) {
  final items = value is List ? value : [value];
  final ids = <String>[];
  for (final (index, item) in items.indexed) {
    final id = lesficheArgument(item, name: 'item ${index + 1} of lesfiches');
    if (!ids.any((known) => known.toLowerCase() == id.toLowerCase())) {
      ids.add(id);
    }
  }
  return ids;
}

/// The lesfiches of [items] (the user's, as listed) with the ids [ids], in
/// that order (ignoring case).
///
/// Throws a [ToolError] when an id names no listed lesfiche (one in the
/// trash is not listed), or a lesfiche of a kind the library cannot move,
/// before anything is sent.
List<LessonContentItem> _chosen(
  List<LessonContentItem> items,
  List<String> ids,
) {
  final chosen = <LessonContentItem>[];
  final unknown = <String>[];
  for (final id in ids) {
    final matches = [
      for (final item in items)
        if (item.id.toLowerCase() == id.toLowerCase()) item,
    ];
    if (matches.isEmpty) unknown.add(id);
    chosen.addAll(matches);
  }
  if (unknown.isNotEmpty) {
    final one = unknown.length == 1;
    throw ToolError(
      'You have no ${one ? 'lesfiche with id' : 'lesfiches with the ids'} '
      '${unknown.join(', ')}: list_lesfiches does not list '
      '${one ? 'it' : 'them'}. A lesfiche that is in the trash already is '
      'not listed, nor is one that no longer exists. Take the ids from '
      'list_lesfiches (type all lists both kinds)'
      '${chosen.isEmpty ? '' : ', and check with the user which lesfiches are meant: the others were not moved either'}. '
      '$nothingSent',
    );
  }
  for (final item in chosen) {
    if (item.type != LessonContentType.other) continue;
    throw ToolError(
      '${_capitalised(lesficheTitle(item))} (id ${item.id}) is of the kind '
      '"${item.typeName}", which this server cannot move to the trash: only '
      'lesson and assignment lesfiches. The user moves it to the trash in '
      'the Lesfiches module itself. $nothingSent',
    );
  }
  return chosen;
}

/// The lesfiches [items] in a few words each ([lesficheTitle]): `the
/// lesson lesfiche "Lussen" and the assignment lesfiche "Taak"`.
String _titles(List<LessonContentItem> items) {
  final titles = [for (final item in items) lesficheTitle(item)];
  return titles.length < 2
      ? titles.join()
      : '${titles.sublist(0, titles.length - 1).join(', ')} and '
            '${titles.last}';
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
