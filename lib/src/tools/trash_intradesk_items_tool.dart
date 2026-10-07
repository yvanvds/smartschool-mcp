import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart'
    hide IntradeskItemKind;

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// At most this many items per call of `trash_intradesk_items`.
const maxIntradeskTrashItems = 20;

/// How many days Intradesk keeps what is in its trash (its
/// `daysTrashSaved`, yvanvds/dartschool#128).
const intradeskTrashDays = 30;

/// `trash_intradesk_items`: moves folders, files and weblinks on Intradesk to
/// Intradesk's trash, one at a time, with the library's
/// `IntradeskService.trashFolder`, `trashFile` and `trashWeblink`
/// (yvanvds/dartschool#128).
///
/// A move, not a deletion: Intradesk keeps its trash for
/// [intradeskTrashDays] days, and the user can restore from it in Intradesk
/// itself; the library neither reads nor restores the trash, and never
/// deletes for good. But colleagues no longer see what was moved, and a
/// folder takes everything in it along, so the tool is marked destructive
/// (for Claude Desktop to ask for approval before every call), and Claude is
/// told to show the user each item by name and path and wait for the user's
/// confirmation. Intradesk answers the move of an item that is in the trash
/// already as the first one (`204`, seen live), so a second call changes
/// nothing: the tool is marked idempotent.
///
/// The items are checked before anything is sent: each id is an Intradesk
/// id, no id comes twice with two kinds, and an id the index in [cache]
/// knows is of the kind passed. Then each item is moved in its own
/// [withIntradesk] call, in order, until one fails: the result says which
/// items were moved, which one failed and why, and which were not tried.
/// What was moved leaves the index at once, a folder with everything in it
/// ([IntradeskIndexCache.patch]); an item that may or may not have been
/// moved stays in it.
///
/// Intradesk answers the move of an id it has no item of that kind for with
/// `404`, and moves nothing (seen live, yvanvds/dartschool#133): a made-up
/// id, the id of an item of another kind (also one in the trash), or of an
/// item that does not exist any more. The library throws a
/// [SmartschoolIntradeskItemNotFoundError] for it, which is reported as
/// such for that item, as not moved (#124). Any other refusal (HTTP `400`
/// to `499`) is reported as not moved with Intradesk's reasons, and any
/// other failure as maybe moved.
ServerTool trashIntradeskItemsTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'trash_intradesk_items',
    title: 'Move Intradesk items to the trash',
    description:
        'Moves folders, files and weblinks on Intradesk, the school\'s shared '
        'document store in Smartschool, to Intradesk\'s trash. Colleagues no '
        'longer see them, and a folder goes to the trash with everything in '
        'it. It is a move, not a deletion: Intradesk keeps its trash for '
        '$intradeskTrashDays days, and until then the user can restore an '
        'item from the trash in Intradesk itself. This tool cannot restore '
        'anything, nor delete anything for good. Pass 1 to '
        '$maxIntradeskTrashItems items, each with its kind (folder, file or '
        'weblink) and its id, from list_intradesk_folder or '
        'search_intradesk. Before calling this tool, show the user each item '
        'by its name and path (as search_intradesk or list_intradesk_folder '
        'shows it), say that a folder goes with everything in it, that '
        'Intradesk keeps the trash for $intradeskTrashDays days and that the '
        'user restores from the trash in Intradesk itself, and only call '
        'this tool after the user has explicitly confirmed it. The items are '
        'moved one at a time, in order; when one fails, the tool stops, and '
        'the result says which items were moved and which were not tried. '
        'Moving an item to the trash again is harmless: if the result says '
        'an item may or may not have been moved, list its folder with '
        'list_intradesk_folder and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'items': Schema.list(
          description:
              'The folders, files and weblinks to move to the trash, as the '
              'user confirmed them, in order: each with its kind and its id. '
              'At most $maxIntradeskTrashItems.',
          items: Schema.object(
            properties: {
              'kind': UntitledSingleSelectEnumSchema(
                description:
                    'What the item is: folder, file or weblink, as '
                    'list_intradesk_folder and search_intradesk show it at '
                    'the start of its line.',
                values: [
                  for (final kind in IntradeskItemKind.values) kind.name,
                ],
              ),
              'id': Schema.string(
                description:
                    'The id of the item, from list_intradesk_folder or '
                    'search_intradesk.',
                minLength: 1,
              ),
            },
            required: ['kind', 'id'],
          ),
          minItems: 1,
          maxItems: maxIntradeskTrashItems,
        ),
      },
      required: ['items'],
    ),
    annotations: ToolAnnotations(
      title: 'Move Intradesk items to the trash',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _trash(session, cache, request.arguments ?? const {}),
);

/// An item to move to the trash, as the call names it: its [number] in
/// `items` (from 1), and its [id] in lowercase.
typedef _Item = ({int number, IntradeskItemKind kind, String id});

/// Where the moves stopped: at [item], which was not moved ([maybeMoved]
/// false) or may or may not have been, for [reason].
typedef _Stop = ({_Item item, bool maybeMoved, String reason});

Future<CallToolResult> _trash(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final (items, total) = _itemsArgument(arguments);
  // Inside the session, as the cache folder is the logged-in user's. A login
  // that fails is thrown as it is: nothing was sent.
  final index = await withIntradesk(session, (_) => cache.saved());
  final known = {for (final item in items) item.id: index?.findItem(item.id)};
  _refuseOtherKinds(items, known);

  final watch = Stopwatch()..start();
  final moved = <_Item>[];
  _Stop? stop;
  for (final item in items) {
    stop = await _move(session, item, known[item.id]);
    if (stop != null) break;
    moved.add(item);
  }
  final patched = moved.isEmpty
      ? 'nothing moved'
      : await cache.patch(removed: [for (final item in moved) item.id]) == null
      ? 'no index'
      : 'index patched';
  log(
    'trash_intradesk_items: moved ${moved.length} of ${items.length} in '
    '${watch.elapsedMilliseconds} ms ($patched)',
  );
  return _result(items, total, moved, stop, known, index);
}

/// The `items` argument of [arguments], each item once, in the order given,
/// and how many items it has (also those named twice).
///
/// Throws a [ToolError] for an id that is not an Intradesk id (it never goes
/// into a request path), and for an id passed with two kinds. The input
/// schema guarantees a list of 1 to [maxIntradeskTrashItems] objects with a
/// kind of [IntradeskItemKind] and a non-empty id.
(List<_Item>, int) _itemsArgument(Map<String, Object?> arguments) {
  final raw = arguments['items'] as List<Object?>;
  final items = <_Item>[];
  // The number of the item (from 1) that named each id first.
  final first = <String, int>{};
  for (final (index, entry) in raw.indexed) {
    final number = index + 1;
    final fields = entry! as Map<Object?, Object?>;
    final kind = IntradeskItemKind.values.byName(fields['kind']! as String);
    final value = fields['id'];
    final trimmed = value is String ? value.trim() : '';
    if (!isIntradeskId(trimmed)) {
      throw ToolError(
        'The id of item $number, ${value is String ? '"$value"' : '$value'}, '
        'is not an Intradesk id like 0a1b2c3d-1111-4222-8333-444455556666, '
        'as list_intradesk_folder and search_intradesk show them. '
        '$nothingSent',
      );
    }
    final id = trimmed.toLowerCase();
    if (first[id] case final earlier?) {
      final other = items.firstWhere((item) => item.id == id).kind;
      if (other == kind) continue;
      throw ToolError(
        'Items $earlier and $number have the same id $id, once as a '
        '${other.name} and once as a ${kind.name}: an id names one item. '
        'Check its kind with list_intradesk_folder or search_intradesk. '
        '$nothingSent',
      );
    }
    first[id] = number;
    items.add((number: number, kind: kind, id: id));
  }
  return (items, raw.length);
}

/// Throws a [ToolError] when the index knows the id of one of [items] as
/// another kind than passed ([known] by id): the move would go to the wrong
/// address, and the item may not be the one the user confirmed.
void _refuseOtherKinds(List<_Item> items, Map<String, IntradeskItem?> known) {
  for (final item in items) {
    final found = known[item.id];
    if (found == null || found.kind == item.kind) continue;
    throw ToolError(
      'Item ${item.number} is passed as a ${item.kind.name}, but the Intradesk '
      'index knows id ${item.id} as the ${found.kind.name} "${found.path}". '
      'Check with the user that this is the item they confirmed, and pass '
      'kind ${found.kind.name}. $nothingSent',
    );
  }
}

/// Moves [item] to the trash, in a session call of its own; null when
/// Intradesk confirmed it, else where and why it stopped. [known] is the
/// item as the index has it, if it does.
Future<_Stop?> _move(
  SmartschoolSession session,
  _Item item,
  IntradeskItem? known,
) async {
  final what = _phrase(item, known);
  try {
    // The library sends the move again after logging in again, and the
    // session repeats the call when Smartschool refused it: harmless, as
    // Intradesk answers a move of an item in the trash already with 204.
    await withIntradesk(session, (intradesk) {
      final id = item.id;
      return switch (item.kind) {
        IntradeskItemKind.folder => intradesk.trashFolder(id),
        IntradeskItemKind.file => intradesk.trashFile(id),
        IntradeskItemKind.weblink => intradesk.trashWeblink(id),
      };
    });
    return null;
  } on SmartschoolIntradeskItemNotFoundError {
    // Before its superclass, the refusal. The library's message names the
    // id: the log does not.
    log('trash_intradesk_items: no such item (HTTP 404)');
    final others = [
      for (final other in IntradeskItemKind.values)
        if (other != item.kind) 'a ${other.name}',
    ].join(' or ');
    return (
      item: item,
      maybeMoved: false,
      reason:
          'Intradesk has no ${item.kind.name} with id ${item.id}: it is the '
          'id of $others, or of an item that does not exist (any more). It '
          'was not moved. Check its kind and id with list_intradesk_folder '
          'or search_intradesk, and tell the user.',
    );
  } on SmartschoolIntradeskWriteRefusedError catch (error) {
    // The library's messages name the item: the log never shows a name.
    log(
      'trash_intradesk_items: refused (HTTP ${error.statusCode}, '
      '${error.violations.length} reasons)',
    );
    final violations = error.violations;
    return (
      item: item,
      maybeMoved: false,
      reason:
          'Intradesk refused the move of $what to the trash (HTTP '
          '${error.statusCode})'
          '${violations.isEmpty ? ', without saying why' : ': ${violations.map((v) => '"$v"').join(' ')}'}. '
          'It was not moved. Check its kind and id with list_intradesk_folder '
          'or search_intradesk, and tell the user.',
    );
  } on SmartschoolIntradeskSaveUnconfirmedError catch (error) {
    log(
      'trash_intradesk_items: Intradesk did not confirm a move '
      '(${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'}'
      '${error.cause == null ? '' : ', ${error.cause.runtimeType}'})',
    );
    return (
      item: item,
      maybeMoved: true,
      reason:
          '${_capitalised(what)} may or may not have been moved to the trash: '
          'it was sent, but Intradesk did not confirm it. Moving it to the '
          'trash again is harmless. First list ${_folderOf(known)} to see '
          'whether it is still there. Then tell the user what you found.',
    );
  } on SmartschoolProblem catch (problem) {
    // Smartschool refused the session, also after logging in again, or
    // could not be reached before the move was sent: it was not carried
    // out.
    return (
      item: item,
      maybeMoved: false,
      reason:
          '${problem.message} ${_capitalised(what)} was not moved to the '
          'trash.',
    );
  }
}

/// [items] (of [total] in `items`) moved up to [stop] as a tool result: what
/// was moved, where and why it stopped, what was not tried, how long
/// Intradesk keeps its trash, and what went along with each folder moved, as
/// [index] knew it. An error when the moves stopped.
CallToolResult _result(
  List<_Item> items,
  int total,
  List<_Item> moved,
  _Stop? stop,
  Map<String, IntradeskItem?> known,
  IntradeskIndex? index,
) {
  String line(_Item item) => '- ${_line(item, known[item.id])}';
  final untried = stop == null ? const <_Item>[] : items.skip(moved.length + 1);
  final lines = [
    if (stop == null) ...[
      'Moved ${_count(moved.length, 'item')} to Intradesk\'s trash.',
      for (final item in moved) line(item),
    ] else ...[
      'Moving to Intradesk\'s trash stopped at item ${stop.item.number} of '
          '$total: '
          '${switch (moved.length) {
            0 => 'nothing was moved',
            1 => '1 item was moved',
            final n => '$n items were moved',
          }}.',
      if (moved.isNotEmpty) ...[
        'Moved to the trash:',
        for (final item in moved) line(item),
      ],
      stop.maybeMoved ? 'Maybe moved:' : 'Not moved:',
      line(stop.item),
      if (untried.isNotEmpty) ...[
        'Not tried:',
        for (final item in untried) line(item),
      ],
      stop.reason,
    ],
    if (moved.isNotEmpty)
      'Intradesk keeps its trash for $intradeskTrashDays days: until then, '
          'the user can restore ${moved.length == 1 ? 'it' : 'them'} from the '
          'trash in Intradesk itself.',
    if (index != null)
      for (final item in moved)
        if (item.kind == IntradeskItemKind.folder)
          ?_contentsNote(item, known[item.id], index.within(item.id)),
  ];
  return CallToolResult(
    isError: stop != null,
    content: [TextContent(text: lines.join('\n'))],
  );
}

/// The note that the folder [item] took [inside] along to the trash, as the
/// index has it; null when the index has nothing in it.
String? _contentsNote(
  _Item item,
  IntradeskItem? known,
  List<IntradeskItem> inside,
) {
  if (inside.isEmpty) return null;
  final kinds = [
    for (final kind in IntradeskItemKind.values)
      if (inside.where((each) => each.kind == kind).length case final n
          when n > 0)
        _count(n, kind.name),
  ];
  final listed = kinds.length == 1
      ? kinds.single
      : '${kinds.take(kinds.length - 1).join(', ')} and ${kinds.last}';
  return 'Note: ${_phrase(item, known)} went to the trash with everything in '
      'it: the Intradesk index had ${_count(inside.length, 'item')} in it '
      '(${inside.length == 1 ? 'a ${inside.single.kind.name}' : listed}).';
}

/// [item] in a few words: `the file "Vakken / Verslag.docx" (id …)` when the
/// index knows it ([known]), else `the file with id …`.
String _phrase(_Item item, IntradeskItem? known) => known == null
    ? 'the ${item.kind.name} with id ${item.id}'
    : 'the ${item.kind.name} "${known.path}" (id ${item.id})';

/// [item] on one line, as list_intradesk_folder and search_intradesk show
/// it when the index knows it ([known]), else its kind and id.
String _line(_Item item, IntradeskItem? known) => known == null
    ? '${item.kind.name} | id ${item.id}'
    : formatIntradeskItem(known);

/// How to list the folder that holds [known]: by its id and path when the
/// index knows them, else the folder it was in.
String _folderOf(IntradeskItem? known) => switch (known) {
  null => 'the folder it was in with list_intradesk_folder',
  IntradeskItem(parentId: '') =>
    'the top of Intradesk with list_intradesk_folder (without folder_id)',
  final known =>
    'its folder, ${known.parentPath}, with list_intradesk_folder '
        '(folder_id ${known.parentId})',
};

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
