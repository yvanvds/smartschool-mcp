import 'package:dart_mcp/server.dart';

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../intradesk/intradesk_search.dart';
import '../intradesk/intradesk_walk.dart';
import '../log.dart';
import '../messages/message_search.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

const defaultIntradeskSearchLimit = 20;
const maxIntradeskSearchLimit = 100;

/// `search_intradesk`: the folders, files and weblinks on Intradesk whose
/// name contains some words.
///
/// Searches an index of the whole tree from [cache], built by walking
/// Intradesk when there is none younger than [IntradeskIndexCache.maxAge]
/// or when the call asks for `refresh`.
ServerTool searchIntradeskTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'search_intradesk',
    title: 'Search Intradesk',
    description:
        'Searches the names of the folders, files and weblinks on Intradesk, '
        'the school\'s shared document store in Smartschool, for words. Use '
        'it to find a document, like "Waar staat het formulier voor de '
        'uitstap?". Only names are searched, not what is in the files. Every '
        'word must occur in the full path (the folder names and the name), '
        'at least one in the name itself; case and accents do not matter, '
        'and a word also matches inside a longer word ("formulier" finds '
        '"Formulieren"). Returns the matches best first, each with its '
        'full path, like "Leerkrachten / Formulieren / uitstap.docx", its '
        'id, and for a file its size and the date it was changed. To see '
        'what is in a folder, call list_intradesk_folder with its id. '
        'Searches an index of all of Intradesk that is kept for '
        '${IntradeskIndexCache.defaultMaxAge.inHours} hours. Building it '
        'walks every folder and takes a few minutes on a large Intradesk: '
        'until the first index is ready the result says so (search again '
        'after a minute), and while a newer one is built the old one is '
        'searched. Pass refresh: true when something added in the meantime '
        'is not found.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words from the name of the folder, file or weblink. Every '
              'word must occur, in any order.',
        ),
        'folder_id': Schema.string(
          description:
              'Only search inside this folder (at any depth): a folder id '
              'from list_intradesk_folder or an earlier search. Default: all '
              'of Intradesk.',
        ),
        'limit': Schema.int(
          description:
              'At most this many matches, best first. Default '
              '$defaultIntradeskSearchLimit, at most '
              '$maxIntradeskSearchLimit.',
          minimum: 1,
          maximum: maxIntradeskSearchLimit,
        ),
        'refresh': Schema.bool(
          description:
              'Walk Intradesk again to rebuild the index before searching, '
              'for something added or renamed since the index was built. '
              'Slow; default false.',
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(
      title: 'Search Intradesk',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _search(session, cache, request.arguments ?? const {}),
);

Future<CallToolResult> _search(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final query =
      SearchQuery.parse(arguments['query'] as String? ?? '') ??
      (throw const ToolError(
        'query is empty: pass words from the name to look for.',
      ));
  final folderId = intradeskIdArgument(arguments, 'folder_id');
  final limit = intArgument(arguments, 'limit') ?? defaultIntradeskSearchLimit;
  final refresh = arguments['refresh'] as bool? ?? false;

  final stopwatch = Stopwatch()..start();
  // Logs in first: the index cache folder is the logged-in user's, and a
  // missing setting is reported before the cache is used.
  await session.run((_) async {});
  final lookup = await cache.load(
    (progress) => withIntradesk(
      session,
      (intradesk) => buildIntradeskIndex(intradesk, progress: progress),
    ),
    refresh: refresh,
  );
  final building = lookup.building;
  final index = lookup.index;
  if (index == null) {
    log(
      'search_intradesk: no index yet, the walk is running '
      '(${building ?? 'just finished'}), ${stopwatch.elapsedMilliseconds} ms',
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Intradesk is being indexed, so there are no search results '
              'yet${building == null ? '' : ': ${_progress(building)}'}. '
              'Indexing a large Intradesk takes a few minutes. Search again '
              'in a minute; once the index is ready, it is kept for '
              '${cache.maxAge.inHours} hours.',
        ),
      ],
    );
  }

  var scope = index.items;
  var where = 'Intradesk';
  if (folderId != null) {
    final folder = index.find(folderId);
    if (folder == null) {
      throw ToolError(
        'No folder with id $folderId in the Intradesk index of '
        '${formatIntradeskTime(index.builtAt)}. Take the id from '
        'list_intradesk_folder or an earlier search; for a folder added '
        'since, search again with refresh: true.',
      );
    }
    if (folder.kind != IntradeskItemKind.folder) {
      throw ToolError(
        '$folderId is the ${folder.kind.name} ${folder.path}, not a folder.',
      );
    }
    scope = index.within(folderId);
    where = 'Intradesk folder ${folder.path}';
  }
  final hits = matchIntradeskItems(scope, query);
  final folders = index.count(IntradeskItemKind.folder);
  final files = index.count(IntradeskItemKind.file);
  final weblinks = index.count(IntradeskItemKind.weblink);
  // Counts only: the query and the names may be personal.
  log(
    'search_intradesk: index from the ${lookup.source!.name}'
    '${building == null ? '' : ' (old; a new one is being built)'} (built '
    '${formatIntradeskTime(index.builtAt)}: $folders folders, $files files, '
    '$weblinks weblinks, ${index.unlisted} failed, ${index.skipped} '
    'skipped), ${scope.length} names searched, ${hits.length} matching, '
    '${stopwatch.elapsedMilliseconds} ms',
  );

  final words = query.terms.join(', ');
  final update = building == null
      ? 'For something added since, search again with refresh: true.'
      : 'A new index is being built (${_progress(building)}); search again '
            'in a few minutes for up-to-date results.';
  final shown = hits.take(limit).toList();
  final cut = shown.length < hits.length
      ? '; showing the best ${shown.length} (raise limit to see more)'
      : '';
  final lines = [
    if (hits.isEmpty)
      '$where: no name matches all of: $words '
          '(${_count(scope.length, 'name')} searched).'
    else
      '$where: ${hits.length} of the ${_count(scope.length, 'name')} '
          'searched ${hits.length == 1 ? 'matches' : 'match'} all of: '
          '$words$cut, best first.',
    for (final hit in shown) '- ${formatIntradeskItem(hit)}',
    'Index of ${formatIntradeskTime(index.builtAt)}: '
        '${_count(folders, 'folder')}, ${_count(files, 'file')}, '
        '${_count(weblinks, 'weblink')}. Names only, not what is in the '
        'files. $update',
    if (index.unlisted > 0)
      'Note: Smartschool did not list the contents of '
          '${_count(index.unlisted, 'folder')}, so '
          '${index.unlisted == 1 ? 'it was' : 'they were'} not searched.',
    if (index.skipped > 0)
      'Note: the index holds at most $maxIntradeskFolders listed folders, '
          'so ${_count(index.skipped, 'folder')} deeper in Intradesk '
          '${index.skipped == 1 ? 'was' : 'were'} not searched. Browse '
          'there with list_intradesk_folder.',
  ];
  return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
}

/// How far the walk [progress] is, for the teacher.
String _progress(IntradeskWalkProgress progress) =>
    '${_count(progress.listed, 'folder')} listed and ${progress.waiting} '
    'waiting after ${progress.elapsed.inSeconds} seconds, '
    '${_count(progress.found, 'name')} found so far';

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
