import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_writes.dart';
import '../log.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `add_intradesk_weblink`: adds a weblink (a named link to a web page) to a
/// folder on Intradesk, with the library's `IntradeskService.createWeblink`
/// (yvanvds/dartschool#128).
///
/// Marked destructive, and confirmed by the user first, as
/// `create_intradesk_folder`. The address is sent as Intradesk's web client
/// sends it ([IntradeskService.normalizeWeblinkUrl]: `http://` in front of an
/// address without a scheme), and the result shows it so. Before sending,
/// the tool reads the folder and refuses a name it holds already and a
/// folder the account may not add to. A create that Intradesk does not
/// confirm is reported as maybe made ([intradeskWriteNotConfirmed]). The new
/// weblink goes into the index in [cache], when one is loaded.
ServerTool addIntradeskWeblinkTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
) => ServerTool(
  definition: Tool(
    name: 'add_intradesk_weblink',
    title: 'Add a weblink on Intradesk',
    description:
        'Adds a weblink, a named link to a web page, to a folder on '
        'Intradesk, the school\'s shared document store in Smartschool. '
        'Everyone who can see the folder sees the weblink. Give the id of '
        'the folder, from search_intradesk or list_intradesk_folder (the '
        'top of Intradesk is not offered), the name the weblink shows and '
        'its address. An address without http:// or https:// is sent with '
        'http:// in front, as Intradesk itself does; the result shows the '
        'address as sent. Before calling this tool, show the user the name, '
        'the address and where it goes (the folder\'s path, as '
        'search_intradesk shows it), and only call this tool after the user '
        'has explicitly confirmed it. The tool refuses a name that a folder, '
        'file or weblink in the folder has already (Intradesk would not '
        'refuse it, but add the new weblink as "name (1)"), and a folder the '
        'user may not add to. If the result says the weblink may or may not '
        'have been added, do not call this tool again for it: list the '
        'folder with list_intradesk_folder and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'folder_id': Schema.string(
          description:
              'The id of the folder to add the weblink to, from '
              'search_intradesk or list_intradesk_folder.',
          minLength: 1,
        ),
        'name': Schema.string(
          description:
              'The name the weblink shows in the folder. Smartschool does not '
              'allow / : * ? " \\ < > |, nor a dot at the start or end.',
          minLength: 1,
        ),
        'url': Schema.string(
          description:
              'The address of the web page, like https://example.com/page.',
          minLength: 1,
        ),
        'icon': Schema.string(
          description:
              'The name of the Smartschool icon the weblink shows. Default '
              '${IntradeskService.defaultWeblinkIcon}, a globe: leave it out '
              'unless the user names an icon.',
          minLength: 1,
        ),
      },
      required: ['folder_id', 'name', 'url'],
    ),
    annotations: ToolAnnotations(
      title: 'Add a weblink on Intradesk',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, cache, request.arguments ?? const {}),
);

Future<CallToolResult> _add(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  Map<String, Object?> arguments,
) async {
  final folderId = intradeskFolderArgument(arguments);
  final name = intradeskNameArgument(arguments, what: 'the weblink');
  final url = (arguments['url'] as String? ?? '').trim();
  final address = IntradeskService.normalizeWeblinkUrl(url);
  if (address == null) {
    throw ToolError(
      'url "$url" is not a web address that Intradesk takes: give the '
      'address of a web page, like https://example.com/page. $nothingSent',
    );
  }
  final icon = (arguments['icon'] as String?)?.trim() ?? '';
  final iconName = icon.isEmpty ? IntradeskService.defaultWeblinkIcon : icon;

  IntradeskParent? parent;
  String where() => parent?.title ?? intradeskFolderTitle(folderId, null);
  String what() => 'the weblink "$name" ($address) in the ${where()}';
  final watch = Stopwatch()..start();
  try {
    final weblink = await withIntradeskWrite(session, (intradesk) async {
      final read = parent = await readIntradeskParent(
        intradesk,
        cache,
        folderId,
      );
      read.refuseWithoutAdd();
      read.refuseTakenNames([name], what: 'the new weblink');
      return intradesk.createWeblink(
        parentFolderId: folderId,
        name: name,
        url: address,
        icon: iconName,
      );
    }, what: what);
    final made = intradeskItems(
      IntradeskListing(folders: const [], files: const [], weblinks: [weblink]),
      folderId: folderId,
      path: parent!.path ?? '',
    );
    final index = await addToIntradeskIndex(cache, parent!, made);
    log(
      'add_intradesk_weblink: made in ${watch.elapsedMilliseconds} ms '
      '($index)',
    );
    final stored = weblink.url.trim().isEmpty ? address : weblink.url.trim();
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Added the weblink "${weblink.name}" to the ${where()}: it opens '
                '$stored.${weblink.id.isEmpty ? '' : ' Its id is ${weblink.id}.'}',
            ?_sentAsNote(url, address),
            ?renamedNote(name, weblink.name),
            for (final item in made)
              '- ${formatIntradeskItem(item, fullPath: parent!.path != null)}',
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolIntradeskSaveUnconfirmedError catch (error) {
    return intradeskWriteNotConfirmed(
      tool: 'add_intradesk_weblink',
      what: what(),
      folderId: folderId,
      error: error,
    );
  }
}

/// A note for the result when [address], the address sent, differs from
/// [url], the one given ([IntradeskService.normalizeWeblinkUrl]); null when
/// they are the same.
String? _sentAsNote(String url, String address) {
  if (address == url) return null;
  final changes = [
    if (url.contains(RegExp(r'\s'))) 'without white space',
    if (!RegExp(
      r'^https?://',
      caseSensitive: false,
    ).hasMatch(url.replaceAll(RegExp(r'\s'), '')))
      'with http:// in front',
  ];
  return 'Note: the address was sent as $address (${changes.join(' and ')}), '
      'as Intradesk\'s own web client sends it: Intradesk takes an address '
      'only with http:// or https:// in front.';
}
