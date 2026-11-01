import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'lesfiche_detail.dart';
import 'lesfiches.dart';
import 'planner_access.dart';

// The bulk writes of the Lesfiches module (dartschool#129, #227), shared by
// the tools that take several lesfiches by their ids: `trash_lesfiches`
// (to the trash), `restore_lesfiches` (out of it) and `duplicate_lesfiches`
// (copies in the own library). Each reads the lesfiches first, in the
// session action of the write (the library takes each lesfiche as read,
// with its kind and platform), and matches the ids given with them
// ([findLesfiches]); and each, when the module does not confirm the write,
// reads again where the lesfiches are now (the library or the trash), in
// a session action of its own, and says which were done and which were not
// ([lesficheBulkPartialResult]).
//
// The library names the lesfiches of an unconfirmed bulk write only in the
// message of its `SmartschoolLessonContentSaveUnconfirmedError`
// (yvanvds/dartschool#235, #195), which the server never shows or logs (it
// holds names); so the tools read where the lesfiches are instead.

/// At most this many lesfiches per call of a bulk write.
const maxLesficheBulkItems = 20;

/// The input schema of the `lesfiches` argument of a bulk write
/// ([lesficheIdsArgument]); [description] says what they are.
Schema lesficheIdsSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.string(minLength: 1),
  minItems: 1,
  maxItems: maxLesficheBulkItems,
);

/// The `lesfiches` argument [value]: ids of lesfiches as `list_lesfiches`
/// shows them ([lesficheArgument]), each once (ignoring case), in the order
/// given. The input schema guarantees a list of 1 to
/// [maxLesficheBulkItems] texts.
///
/// Throws a [ToolError] that names the item for anything that is not such
/// an id, before anything is sent.
List<String> lesficheIdsArgument(Object? value) {
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

/// The lesfiches of [items] with the ids [ids], in that order (ignoring
/// case), and the ids that name none of them ([unknown]).
({List<LessonContentItem> found, List<String> unknown}) findLesfiches(
  List<LessonContentItem> items,
  List<String> ids,
) {
  final found = <LessonContentItem>[];
  final unknown = <String>[];
  for (final id in ids) {
    final matches = [
      for (final item in items)
        if (item.id.toLowerCase() == id.toLowerCase()) item,
    ];
    if (matches.isEmpty) unknown.add(id);
    found.addAll(matches);
  }
  return (found: found, unknown: unknown);
}

/// Throws a [ToolError] for the first lesfiche of [items] of a kind the
/// library cannot write ([LessonContentType.other]): this server cannot
/// [action] it (like `move to the trash`), and the user does that in the
/// Lesfiches module itself.
void refuseOtherLesficheKinds(
  List<LessonContentItem> items, {
  required String action,
}) {
  for (final item in items) {
    if (item.type != LessonContentType.other) continue;
    throw ToolError(
      '${capitalised(lesficheTitle(item))} (id ${item.id}) is of the kind '
      '"${item.typeName}", which this server cannot $action: only lesson '
      'and assignment lesfiches. The user does that in the Lesfiches module '
      'itself. $nothingSent',
    );
  }
}

/// The ids [ids] in a sentence: `id x` or `the ids x, y`.
String lesficheIdsPhrase(List<String> ids) =>
    ids.length == 1 ? 'id ${ids.single}' : 'the ids ${ids.join(', ')}';

/// The lesfiches [items] in a few words each ([lesficheTitle]): `the
/// lesson lesfiche "Lussen" and the assignment lesfiche "Taak"`.
String lesficheTitles(List<LessonContentItem> items) {
  final titles = [for (final item in items) lesficheTitle(item)];
  return titles.length < 2
      ? titles.join()
      : '${titles.sublist(0, titles.length - 1).join(', ')} and '
            '${titles.last}';
}

/// [items] as the subject of a sentence: `The lesson lesfiche "Lussen"`,
/// or `The 2 lesfiches (the lesson lesfiche "Lussen" and ...)`.
String lesficheSubject(List<LessonContentItem> items) => items.length == 1
    ? capitalised(lesficheTitle(items.single))
    : 'The ${items.length} lesfiches (${lesficheTitles(items)})';

String capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// The lesfiches in the module's trash, read again after a bulk write the
/// module did not confirm, in a session action of its own; null when they
/// cannot be read (the tool then says to check with a tool).
Future<List<LessonContentItem>?> readLesficheTrashAfter(
  SmartschoolSession session,
) => _readAfter(
  session,
  (lesfiches) => lesfiches.getTrash(withCourseNames: false),
);

/// The lesfiches in the own library ([LessonContentService.getItems]),
/// read again after a bulk write the module did not confirm, as
/// [readLesficheTrashAfter] reads the trash.
Future<List<LessonContentItem>?> readLesfichesAfter(
  SmartschoolSession session,
) => _readAfter(
  session,
  (lesfiches) => lesfiches.getItems(withCourseNames: false),
);

Future<List<LessonContentItem>?> _readAfter(
  SmartschoolSession session,
  Future<List<LessonContentItem>> Function(LessonContentService) read,
) async {
  try {
    return await withPlannerClient(
      session,
      (client) => read(LessonContentService(client)),
    );
  } on Object catch (error) {
    if (error is! ToolError && error is! SmartschoolProblem) rethrow;
    log('lesfiches: reading them again after an unconfirmed write failed');
    return null;
  }
}

/// The result of a bulk write of [tool] that the module did not confirm,
/// with where the lesfiches are now, read again after it ([readFrom], like
/// `the trash`): [sent] says what was sent (like `The move of 2 lesfiches
/// to the trash`), [done] lists those that were done under [doneHeader]
/// (like `Moved to the trash:`), and [notDone] those that were not under
/// [notDoneHeader]; [extra] lines come after them. An error result when
/// some were not done, with [advice] (what Claude does next); else it says
/// all were done.
CallToolResult lesficheBulkPartialResult({
  required String tool,
  required String sent,
  required String readFrom,
  required String doneHeader,
  required List<String> done,
  required String notDoneHeader,
  required List<String> notDone,
  required String advice,
  List<String> extra = const [],
}) {
  log(
    '$tool: the Lesfiches module did not confirm a write; read again: '
    '${done.length} done, ${notDone.length} not',
  );
  return CallToolResult(
    isError: notDone.isNotEmpty,
    content: [
      TextContent(
        text: [
          '$sent was sent, but the Lesfiches module did not confirm '
              '${done.length + notDone.length == 1 ? 'it' : 'all of it'}. '
              'Read again after it, $readFrom shows what was done.',
          if (done.isNotEmpty) ...[doneHeader, ...done],
          if (notDone.isNotEmpty) ...[notDoneHeader, ...notDone],
          ...extra,
          advice,
        ].join('\n'),
      ),
    ],
  );
}
