import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_writes.dart';
import '../log.dart';
import '../session.dart';
import 'server_tool.dart';

/// `create_intradesk_folder`: adds a folder to a folder on Intradesk, with
/// the library's `IntradeskService.createFolder` (yvanvds/dartschool#128).
///
/// Colleagues who see the parent folder see the new one, so the tool is
/// marked destructive (for Claude Desktop to ask for approval before every
/// call), and Claude is told to show the user the name and the parent's path
/// and wait for the user's confirmation. Before sending, the tool reads the
/// parent and its path ([readIntradeskParent]) and refuses a name the parent
/// holds already; the library reads the parent too and refuses a parent the
/// account may not add to, and a folder of the wrong kind for the parent
/// (only a confidential folder goes in a confidential one), which
/// [withIntradeskWrite] words. A create that Intradesk does not confirm is
/// reported as maybe made ([intradeskWriteNotConfirmed]). The new folder
/// goes into the index in [cache], when one is loaded
/// ([addToIntradeskIndex]).
ServerTool createIntradeskFolderTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'create_intradesk_folder',
    title: 'Add a folder on Intradesk',
    description:
        'Adds a new folder to a folder on Intradesk, the school\'s shared '
        'document store in Smartschool. Everyone who can see the parent '
        'folder sees the new one. Give the id of the parent folder, from '
        'search_intradesk or list_intradesk_folder (a folder at the top of '
        'Intradesk is not offered), and the name. Before calling this tool, '
        'show the user the name of the new folder and where it goes (the '
        'parent folder\'s path, as search_intradesk shows it), and only call '
        'this tool after the user has explicitly confirmed it. The tool '
        'refuses a name that a folder, file or weblink in the parent folder '
        'has already (Intradesk would not refuse it, but add the new folder '
        'as "name (1)"), and a parent folder the user may not add to. Inside '
        'a confidential folder, pass confidential: true: Intradesk adds only '
        'confidential folders there. To put files in the new folder, use '
        'upload_intradesk_files with its id. If the result says the folder '
        'may or may not have been added, do not call this tool again for '
        'it: list the parent folder with list_intradesk_folder and tell the '
        'user.',
    inputSchema: Schema.object(
      properties: {
        'folder_id': Schema.string(
          description:
              'The id of the folder to add the new folder to, from '
              'search_intradesk or list_intradesk_folder.',
          minLength: 1,
        ),
        'name': Schema.string(
          description:
              'The name of the new folder. Smartschool does not allow / : * '
              '? " \\ < > |, nor a dot at the start or end.',
          minLength: 1,
        ),
        'color': UntitledSingleSelectEnumSchema(
          description:
              'The colour of the folder in Intradesk. Default '
              '${IntradeskService.defaultFolderColor}, the colour of nearly '
              'every folder: leave it out unless the user asks for a colour.',
          values: IntradeskService.folderColors,
        ),
        'confidential': Schema.bool(
          description:
              'Only inside a confidential folder: true adds a confidential '
              'folder, the only kind Intradesk adds there. Default false.',
        ),
      },
      required: ['folder_id', 'name'],
    ),
    annotations: ToolAnnotations(
      title: 'Add a folder on Intradesk',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _create(session, cache, request.arguments ?? const {}),
);

Future<CallToolResult> _create(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final folderId = intradeskFolderArgument(arguments);
  final name = intradeskNameArgument(arguments, what: 'the new folder');
  final color =
      arguments['color'] as String? ?? IntradeskService.defaultFolderColor;
  final confidential = arguments['confidential'] as bool? ?? false;
  final kind = confidential ? 'confidential folder' : 'folder';

  IntradeskParent? parent;
  String where() => parent?.title ?? intradeskFolderTitle(folderId, null);
  final watch = Stopwatch()..start();
  try {
    final folder = await withIntradeskWrite(
      session,
      (intradesk) async {
        final read = parent = await readIntradeskParent(intradesk, folderId);
        read.refuseTakenNames([name], what: 'the new folder');
        return intradesk.createFolder(
          parentFolderId: folderId,
          name: name,
          color: color,
          confidential: confidential,
        );
      },
      what: () => 'the $kind "$name" in the ${where()}',
      where: where,
    );
    final made = intradeskItems(
      IntradeskListing(folders: [folder], files: const [], weblinks: const []),
      folderId: folderId,
      path: parent!.path,
    );
    final index = await addToIntradeskIndex(cache, made);
    log(
      'create_intradesk_folder: made in ${watch.elapsedMilliseconds} ms '
      '($index)',
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Added the $kind "${folder.name}" to the ${where()}, with the '
                'colour ${folder.color.isEmpty ? color : folder.color}. Its '
                'id is ${folder.id}.',
            ?renamedNote(name, folder.name),
            for (final item in made) '- ${formatIntradeskItem(item)}',
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolIntradeskSaveUnconfirmedError catch (error) {
    return intradeskWriteNotConfirmed(
      tool: 'create_intradesk_folder',
      what: 'the $kind "$name" in the ${where()}',
      folderId: folderId,
      error: error,
    );
  }
}
