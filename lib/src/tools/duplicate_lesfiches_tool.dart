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

/// What the module puts behind the name of a copy (dartschool#227, seen
/// live).
const lesficheCopySuffix = ' - kopie';

/// `duplicate_lesfiches`: copies lesfiches of the user's Lesfiches module,
/// lessons and assignments, in the own library, in one write (the
/// library's `LessonContentService.duplicate`, dartschool#227).
///
/// Each copy gets a new id and the name of the lesfiche with " - kopie"
/// behind it, and the lesfiche's icon, info, visibility, courses, labels,
/// goals, weblinks and attachments. It changes no lesfiche, but it adds
/// lesfiches to the user's library, so it is marked destructive (for Claude
/// Desktop to ask for approval), as `create_lesfiche` is. Not idempotent: a
/// second call makes more copies, and the library sends it once, never
/// again after logging in again.
///
/// As `trash_lesfiches`, the tool reads the list first (`getItems`, without
/// the course names), in the session action of the write, and matches the
/// ids given with it. An id it does not list is looked up in the trash
/// (`getTrash`): a lesfiche there cannot be copied (the module answers it
/// with an exception `403`), so the tool says to restore it first; any
/// other is refused as unknown, before anything is sent. When the module
/// refuses anyway (the lesfiche went to the trash after the read), the
/// library throws a [SmartschoolLessonContentWriteRefusedError]: no copy
/// was made, and the tool says the same.
///
/// When some copies were made and others not, or the answer does not
/// arrive, the library throws a
/// [SmartschoolLessonContentSaveUnconfirmedError]: the tool reads the list
/// again and takes the lesfiches that are new since the read before the
/// write as the copies made, each matched with the lesfiche of its name
/// (with " - kopie" behind it) and kind ([lesficheBulkPartialResult]).
ServerTool duplicateLesfichesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'duplicate_lesfiches',
    title: 'Copy Smartschool lesfiches',
    description:
        'Copies lesfiches of the user\'s Smartschool Lesfiches module, lessons '
        'and assignments alike, in the user\'s own library, by the ids '
        'list_lesfiches shows: 1 to $maxLesficheBulkItems in one call. Each '
        'copy is a new lesfiche with a new id, named after the lesfiche with '
        '"$lesficheCopySuffix" behind it, with its icon, info for pupils and '
        'private info, visibility, courses, labels, learning goals, weblinks '
        'and attachments. The lesfiches themselves do not change. Use it to '
        'adapt a lesfiche for another class or year without making it again: '
        'copy it, then change the copy with edit_lesfiche (its name, say) '
        'and the other lesfiche tools, by the id this result gives. A '
        'lesfiche in the trash cannot be copied: restore it first with '
        'restore_lesfiches. Before calling this tool, show the user each '
        'lesfiche to copy by its name and kind, and only call this tool '
        'after the user has explicitly confirmed it; then call it once, with all of them. Every '
        'call makes new copies: never call it again for a lesfiche that was '
        'copied. If the result says the copy was not confirmed, it says '
        'which copies were made: do not copy those again. For requests like '
        '"maak een kopie van mijn lesfiche Lussen voor 5WEWI".',
    inputSchema: Schema.object(
      properties: {
        'lesfiches': lesficheIdsSchema(
          description:
              'The ids of the lesfiches to copy, as list_lesfiches shows '
              'them and as the user confirmed them, like '
              'b0000000-0000-4000-8000-000000000001: lessons and assignments '
              'together, at most $maxLesficheBulkItems. Each is copied once.',
        ),
      },
      required: ['lesfiches'],
    ),
    annotations: ToolAnnotations(
      title: 'Copy Smartschool lesfiches',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _duplicate(session, request.arguments ?? const {}),
);

Future<CallToolResult> _duplicate(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final ids = lesficheIdsArgument(arguments['lesfiches']);
  final nothingDone = ids.length == 1
      ? 'No copy was made.'
      : 'None of the lesfiches was copied.';

  var chosen = const <LessonContentItem>[];
  var before = const <LessonContentItem>[];
  final watch = Stopwatch()..start();
  late final List<LessonContentDetail> copies;
  try {
    copies = await withLesficheWrite(
      session,
      (client) async {
        final lesfiches = LessonContentService(client);
        // First, in the action of the write: the library takes each
        // lesfiche as listed, with its kind and platform.
        final items = before = await lesfiches.getItems(withCourseNames: false);
        final (:found, :unknown) = findLesfiches(items, ids);
        if (unknown.isNotEmpty) {
          final trash = await lesfiches.getTrash(withCourseNames: false);
          _refuseUnlisted(trash, unknown, found);
        }
        refuseOtherLesficheKinds(found, action: 'copy');
        chosen = found;
        try {
          return await lesfiches.duplicate(found);
        } on SmartschoolLessonContentWriteRefusedError catch (error) {
          if (error.statusCode != 403) rethrow;
          log('duplicate_lesfiches: refused with 403');
          throw ToolError(
            'The Lesfiches module refused to copy '
            '${lesficheTitles(found)} (HTTP 403): a lesfiche in the trash '
            'cannot be copied, so '
            '${found.length == 1 ? 'it' : 'one of them'} most likely went to '
            'the trash after this tool read the list. '
            'list_trashed_lesfiches lists the trash; restore it first with '
            'restore_lesfiches. $nothingDone',
          );
        }
      },
      what: () => chosen.isEmpty
          ? 'the copy of the lesfiches'
          : 'the copy of ${lesficheTitles(chosen)}',
      nothingDone: nothingDone,
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return _notConfirmed(session, chosen, before, error);
  }
  log(
    'duplicate_lesfiches: copied ${copies.length} in '
    '${watch.elapsedMilliseconds} ms',
  );
  final one = copies.length == 1;
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Made ${one ? '1 copy' : '${copies.length} copies'} in the own '
              'library of the Lesfiches module:',
          for (final (index, copy) in copies.indexed)
            '- ${formatLesficheLine(copy, withCourseNames: false)} '
                '(a copy of id ${chosen[index].id})',
          'Each copy has the icon, info, visibility, courses, labels, '
              'learning goals, weblinks and attachments of its lesfiche. '
              'Change ${one ? 'it' : 'a copy'} with edit_lesfiche (its name, '
              'say) and the other lesfiche tools by '
              '${one ? 'its' : 'the'} id; read_lesfiche shows '
              '${one ? 'it' : 'one'} in full. Do not call duplicate_lesfiches '
              'again for these lesfiches: it would make more copies.',
        ].join('\n'),
      ),
    ],
  );
}

/// Throws the [ToolError] for the ids [unknown], which the library does not
/// list: those of [trash] are in the trash (restore them first), the others
/// name no lesfiche. [found] are the ids that were listed, for the note
/// that they were not copied either.
Never _refuseUnlisted(
  List<LessonContentItem> trash,
  List<String> unknown,
  List<LessonContentItem> found,
) {
  final (found: trashed, unknown: missing) = findLesfiches(trash, unknown);
  final parts = [
    if (trashed.isNotEmpty)
      '${capitalised(lesficheTitles(trashed))} '
          '${trashed.length == 1 ? 'is' : 'are'} in the trash, and a '
          'lesfiche in the trash cannot be copied: restore '
          '${trashed.length == 1 ? 'it' : 'them'} first with '
          'restore_lesfiches (after the user confirms it), then copy '
          '${trashed.length == 1 ? 'it' : 'them'}.',
    if (missing.isNotEmpty)
      'You have no ${missing.length == 1 ? 'lesfiche' : 'lesfiches'} with '
          '${lesficheIdsPhrase(missing)}, in the library or in the trash. '
          'Take the ids from list_lesfiches (type all lists both kinds).',
    if (found.isNotEmpty) 'The others were not copied either.',
  ];
  throw ToolError('${parts.join(' ')} $nothingSent');
}

/// The result when the module did not confirm the copy of [chosen]
/// ([error]): the lesfiches new in the library since [before], read again,
/// as the copies made.
Future<CallToolResult> _notConfirmed(
  SmartschoolSession session,
  List<LessonContentItem> chosen,
  List<LessonContentItem> before,
  SmartschoolLessonContentSaveUnconfirmedError error,
) async {
  final one = chosen.length == 1;
  final after = await readLesfichesAfter(session);
  if (after == null) {
    return lesficheWriteNotConfirmed(
      tool: 'duplicate_lesfiches',
      what: one
          ? 'A copy of ${lesficheTitle(chosen.single)}'
          : 'Copies of the ${chosen.length} lesfiches '
                '(${lesficheTitles(chosen)})',
      done: 'made',
      also: one ? null : 'Some may have been made, and others not.',
      why: 'that would make more copies',
      check:
          'list the lesfiches with list_lesfiches (type all) to see which '
          'copies there are: a copy is named after its lesfiche with '
          '"$lesficheCopySuffix" behind it',
      error: error,
    );
  }
  final known = {for (final item in before) item.id.toLowerCase()};
  final fresh = [
    for (final item in after)
      if (!known.contains(item.id.toLowerCase())) item,
  ];
  final done = <String>[];
  final notDone = <String>[];
  for (final item in chosen) {
    final copy = fresh
        .where(
          (candidate) =>
              candidate.typeName == item.typeName &&
              candidate.name == '${item.name}$lesficheCopySuffix',
        )
        .firstOrNull;
    if (copy == null) {
      notDone.add('- ${formatLesficheLine(item, withCourseNames: false)}');
    } else {
      fresh.remove(copy);
      done.add(
        '- ${formatLesficheLine(copy, withCourseNames: false)} (a copy of '
        'id ${item.id})',
      );
    }
  }
  return lesficheBulkPartialResult(
    tool: 'duplicate_lesfiches',
    sent: one
        ? 'The copy of ${lesficheTitle(chosen.single)}'
        : 'The copy of ${chosen.length} lesfiches',
    readFrom: 'the list of lesfiches',
    doneHeader: 'Copies made:',
    done: done,
    notDoneHeader: 'No copy found of:',
    notDone: notDone,
    extra: [
      if (fresh.isNotEmpty) ...[
        'Also new in the library since the copy was sent:',
        for (final item in fresh)
          '- ${formatLesficheLine(item, withCourseNames: false)}',
      ],
    ],
    advice:
        'Do not call duplicate_lesfiches again for the lesfiches that were '
        'copied: it would make more copies. Tell the user which were copied '
        'and which not, and ask before copying the others again; one in the '
        'trash (list_trashed_lesfiches) cannot be copied.',
  );
}
