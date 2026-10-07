import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart'
    hide IntradeskItemKind;

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../session.dart';
import 'server_tool.dart';

/// A folder with more items than this shows only the first ones, with a
/// note.
const maxIntradeskFolderItems = 500;

/// `list_intradesk_folder`: what is in one Intradesk folder, or at the top
/// of Intradesk, as Smartschool has it now.
///
/// The folder's path comes from the index in [cache] when there is one; the
/// listing itself never builds an index.
ServerTool listIntradeskFolderTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'list_intradesk_folder',
    title: 'List an Intradesk folder',
    description:
        'Lists what is in one folder on Intradesk, the school\'s shared '
        'document store in Smartschool: its folders, then its files, then '
        'its weblinks, one line each with the name, the id, and for a file '
        'its size and the date it was changed. Without folder_id it lists '
        'the top of Intradesk. To go into a folder, call it again with that '
        'folder\'s id. To find a document by name anywhere on Intradesk, '
        'use search_intradesk instead.',
    inputSchema: Schema.object(
      properties: {
        'folder_id': Schema.string(
          description:
              'The id of the folder to list, from an earlier '
              'list_intradesk_folder or search_intradesk. Default: the top of '
              'Intradesk.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List an Intradesk folder',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, cache, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final folderId = intradeskIdArgument(arguments, 'folder_id');

  final (listing, known) = await withIntradesk(session, (intradesk) async {
    if (folderId == null) return (await intradesk.getRootListing(), null);
    final IntradeskListing listing;
    try {
      listing = await intradesk.getFolderListing(folderId);
    } on SmartschoolIntradeskFolderNotFoundError {
      // Any other failure is Smartschool's, not the id's: the server reports
      // it as an unexpected error.
      throw ToolError(
        'Intradesk has no folder with id $folderId: it is the id of a file '
        'or a weblink, or of a folder that does not exist (any more). Take '
        'the id of a folder from list_intradesk_folder or search_intradesk; '
        'to read a file, use read_intradesk_file.',
      );
    }
    // The folder's path, when the index knows it; inside the session, as
    // the cache folder is the logged-in user's.
    final known = (await cache.saved())?.find(folderId);
    return (listing, known?.kind == IntradeskItemKind.folder ? known : null);
  });

  final path = known?.path ?? '';
  final items = intradeskItems(listing, folderId: folderId ?? '', path: path);
  final where = folderId == null
      ? 'Intradesk, top level'
      : known == null
      ? 'Intradesk folder $folderId'
      : 'Intradesk folder ${known.path} (id $folderId)';
  final counts = [
    for (final kind in IntradeskItemKind.values)
      if (items.where((item) => item.kind == kind).length case final count
          when count > 0)
        '$count ${kind.name}${count == 1 ? '' : 's'}',
  ];
  final shown = items.take(maxIntradeskFolderItems).toList();
  final lines = [
    '$where: ${counts.isEmpty ? 'empty' : counts.join(', ')}.',
    for (final item in shown) '- ${formatIntradeskItem(item, fullPath: false)}',
    if (shown.length < items.length)
      'Note: only the first ${shown.length} of the ${items.length} are '
          'shown. Use search_intradesk to find one by name.',
  ];
  return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
}
