/// `create_intradesk_folder`, `add_intradesk_weblink`,
/// `upload_intradesk_files` and `trash_intradesk_items`, called over MCP on
/// the real server, session, library, index cache and local files, against a
/// fake Smartschool whose Intradesk carries out the writes of
/// yvanvds/dartschool#128 as the live one did
/// (`test/support/fake_intradesk.dart`, with the request bodies and answers
/// of dartschool's `intradesk_write_test.dart`).
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart' show RequestOptions;
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/add_intradesk_weblink_tool.dart';
import 'package:smartschool_mcp/src/tools/create_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/list_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_intradesk_items_tool.dart';
import 'package:smartschool_mcp/src/tools/upload_intradesk_files_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _api = '/intradesk/api/v1/4069';

/// The id of the weblink Schoolsite in Vakken / Informatica.
const schoolsite = 'eeee9999-0000-4000-8000-000000009999';

/// The size limit of `upload_intradesk_files` here.
const _limit = 64;

void main() {
  late FakeSmartschool server;
  late FakeIntradesk intradesk;
  late Directory cookies;
  late Directory cacheFolder;
  late Directory files;
  late SmartschoolSession session;
  late IntradeskIndexCache cache;
  late ServerConnection connection;

  // The tree: Vakken (may add) / Informatica (may add) with Verslag.docx and
  // the weblink Schoolsite ([schoolsite]); Archief (may not add);
  // Leerlingendossiers (confidential, may add).
  late String vakken;
  late String informatica;
  late String verslag;
  late String archief;
  late String dossiers;

  /// Starts a server with its own session and index cache on the same
  /// cookie and cache folders, like a new server process.
  Future<ServerConnection> start() async {
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cookies),
    );
    addTearDown(session.close);
    final current = cache = IntradeskIndexCache(
      cacheFolder,
      buildWait: const Duration(seconds: 10),
    );
    addTearDown(() => current.walkDone);
    final (connection, _) = await connect(
      tools: [
        createIntradeskFolderTool(session, current),
        addIntradeskWeblinkTool(session, current),
        uploadIntradeskFilesTool(session, current, maxBytes: _limit),
        trashIntradeskItemsTool(session, current),
        searchIntradeskTool(session, current),
        listIntradeskFolderTool(session, current),
      ],
    );
    return connection;
  }

  setUp(() async {
    server = FakeSmartschool();
    intradesk = server.intradesk;
    vakken = intradesk.addFolder('Vakken', canAdd: true);
    informatica = intradesk.addFolder(
      'Informatica',
      parent: vakken,
      canAdd: true,
    );
    verslag = intradesk.addFile('Verslag.docx', parent: informatica);
    intradesk.addWeblink({
      'id': schoolsite,
      'name': 'Schoolsite',
      'url': 'https://www.example.com',
    }, parent: informatica);
    archief = intradesk.addFolder('Archief');
    dossiers = intradesk.addFolder(
      'Leerlingendossiers',
      confidential: true,
      canAdd: true,
    );
    cookies = await tempCache();
    cacheFolder = await tempCache();
    files = await tempCache();
    connection = await start();
  });

  Future<(CallToolResult, String)> call(
    String tool,
    Map<String, Object?> arguments, [
    ServerConnection? on,
  ]) => callTool(on ?? connection, tool, arguments);

  Future<String> ok(
    String tool,
    Map<String, Object?> arguments, [
    ServerConnection? on,
  ]) async {
    final (result, text) = await call(tool, arguments, on);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await call(tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// Builds the index, as the first search does.
  Future<void> buildIndex() async {
    await ok('search_intradesk', {'query': 'informatica'});
    intradesk.listed.clear();
  }

  /// The paths of what a search finds.
  Future<List<String>> found(String query, [ServerConnection? on]) async {
    final text = await ok('search_intradesk', {'query': query}, on);
    return [
      for (final line in text.split('\n'))
        if (line.startsWith('- ')) line.split(' | ')[1],
    ];
  }

  /// The names in the folder [id] on the fake Intradesk.
  List<String> namesIn(String id) => [
    for (final item in intradesk.itemsIn(id)) item['name']! as String,
  ];

  /// A file [name] with [content] on this PC; returns its full path.
  String file(String name, [String content = 'smartschool-mcp test\n']) {
    final path = '${files.path}${Platform.pathSeparator}$name';
    File(path).writeAsStringSync(content);
    return path;
  }

  bool isPostTo(RequestOptions request, String path) =>
      request.method == 'POST' && request.uri.path == '$_api/$path';

  int postsTo(String path) =>
      server.requests.where((r) => r == 'POST $_api/$path').length;

  group('the tools', () {
    test('are listed as writes Claude Desktop asks approval for, to be '
        'called only after the user confirmed, with their arguments', () async {
      final tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
      const writes = [
        'create_intradesk_folder',
        'add_intradesk_weblink',
        'upload_intradesk_files',
      ];
      for (final name in writes) {
        final tool = tools[name]!;
        expect(tool.toolAnnotations?.readOnlyHint, isFalse, reason: name);
        expect(tool.toolAnnotations?.destructiveHint, isTrue, reason: name);
        expect(tool.toolAnnotations?.idempotentHint, isFalse, reason: name);
        expect(tool.toolAnnotations?.openWorldHint, isTrue, reason: name);
        expect(
          tool.description,
          allOf(
            contains(
              'only call this tool after the user has explicitly '
              'confirmed it',
            ),
            contains('do not call this tool again for'),
            contains('list_intradesk_folder'),
            contains('the top of Intradesk is not offered'),
          ),
          reason: name,
        );
      }
      final folder = tools['create_intradesk_folder']!;
      expect(folder.inputSchema.required, ['folder_id', 'name']);
      expect(folder.inputSchema.properties!.keys, [
        'folder_id',
        'name',
        'color',
        'confidential',
      ]);
      expect((folder.inputSchema.properties!['color']! as Map)['enum'], [
        'red',
        'brown',
        'orange',
        'yellow',
        'green',
        'aqua',
        'blue',
        'purple',
        'pink',
        'white',
        'black',
      ]);
      final weblink = tools['add_intradesk_weblink']!;
      expect(weblink.inputSchema.required, ['folder_id', 'name', 'url']);
      expect(weblink.inputSchema.properties!.keys, [
        'folder_id',
        'name',
        'url',
        'icon',
      ]);
      final upload = tools['upload_intradesk_files']!;
      expect(upload.inputSchema.required, ['folder_id', 'paths']);
      expect(upload.inputSchema.properties!.keys, ['folder_id', 'paths']);
      expect(
        upload.description,
        allOf(
          contains('show the user every file with its name and size'),
          contains('up to 64 bytes each'),
        ),
      );
    });
  });

  group('create_intradesk_folder', () {
    test(
      'reads the folder, sends the create once with the name, the colour '
      '(yellow by default), the parent and the platform, and answers with '
      'the folder as Intradesk made it; without an index it builds none',
      () async {
        final text = await ok('create_intradesk_folder', {
          'folder_id': informatica,
          'name': ' Toetsen ',
        });

        expect(
          text,
          'Added the folder "Toetsen" to the Intradesk folder $informatica, '
          'with the colour yellow. Its id is '
          'ffff0001-0000-4000-8000-000000000001.\n'
          '- folder | Toetsen | id ffff0001-0000-4000-8000-000000000001 | '
          'changed 2026-10-05',
        );
        expect(intradesk.writeRequests, hasLength(1));
        expect(intradesk.writeRequests.single.path, 'folders/');
        expect(intradesk.writeRequests.single.body, {
          'name': 'Toetsen',
          'color': 'yellow',
          'parentFolderId': informatica,
          'platform': {'id': 4069},
        });
        // The folder above is the library's: it reads the folder's entry
        // before the create (yvanvds/dartschool#138).
        expect(intradesk.listed, [informatica, vakken], reason: 'no walk');
        expect(await cache.saved(), isNull);
        expect(namesIn(informatica), ['Toetsen', 'Verslag.docx', 'Schoolsite']);
        expect(
          await ok('list_intradesk_folder', {'folder_id': informatica}),
          contains(
            '- folder | Toetsen | id ffff0001-0000-4000-8000-000000000001',
          ),
        );
      },
    );

    test('with an index: names the parent by its path, reads its entry in the '
        'folder above, and patches the index, so that a search finds the new '
        'folder at once, also in a new server process', () async {
      await buildIndex();

      final text = await ok('create_intradesk_folder', {
        'folder_id': informatica,
        'name': 'Toetsen',
        'color': 'green',
      });

      expect(
        text,
        'Added the folder "Toetsen" to the Intradesk folder Vakken / '
        'Informatica (id $informatica), with the colour green. Its id is '
        'ffff0001-0000-4000-8000-000000000001.\n'
        '- folder | Vakken / Informatica / Toetsen | id '
        'ffff0001-0000-4000-8000-000000000001 | changed 2026-10-05',
      );
      expect(intradesk.writeRequests.single.body['color'], 'green');
      // The folder above twice: for the tool's read of the folder's entry and
      // for the library's (yvanvds/dartschool#138).
      final listed = [informatica, vakken, vakken];
      expect(intradesk.listed, listed);

      expect(await found('toetsen'), ['Vakken / Informatica / Toetsen']);
      expect(intradesk.listed, listed, reason: 'no walk');
      expect(await found('toetsen', await start()), [
        'Vakken / Informatica / Toetsen',
      ]);
      expect(intradesk.listed, listed, reason: 'no walk');
    });

    test('refuses a name the folder holds already, of any kind, ignoring case '
        'and spaces, and names the item; nothing is sent', () async {
      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': ' verslag.DOCX',
        }),
        'The Intradesk folder $informatica already holds an item with the '
        'name of the new folder: the file "Verslag.docx" (id $verslag). '
        'Intradesk does not refuse a second item with the same name, but adds '
        'the new one under another name (like "name (1)"). Choose another '
        'name, or ask the user what to do. Nothing was sent.',
      );
      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'schoolsite',
        }),
        contains('the weblink "Schoolsite" (id eeee9999-'),
      );
      expect(intradesk.writes, isEmpty);
    });

    test('refuses a folder the account may not add to before sending: with an '
        'index the tool does, without one the library, which reads the '
        'folder too', () async {
      expect(
        await error('create_intradesk_folder', {
          'folder_id': archief,
          'name': 'Oud',
        }),
        'The folder "Oud" in the Intradesk folder $archief was refused before '
        'it was sent: createFolder: the user may not add to folder $archief '
        '("Archief") (its canAdd is false), and Intradesk\'s web client '
        'offers no folder, weblink or file there. Nothing was sent.',
      );
      expect(intradesk.listed, [archief, ''], reason: 'the top: the library');
      expect(intradesk.writes, isEmpty);

      await buildIndex();

      expect(
        await error('create_intradesk_folder', {
          'folder_id': archief,
          'name': 'Nieuw',
        }),
        'Your account may not add anything to the Intradesk folder Archief '
        '(id $archief): Smartschool does not give you that right for this '
        'folder, and Intradesk\'s own web client offers no folder, weblink or '
        'file there. Choose another folder, or ask someone who manages it. '
        'Nothing was sent.',
      );
      expect(intradesk.writes, isEmpty);
    });

    test('a confidential folder goes to folders/as-confidential inside a '
        'confidential folder; the wrong kind is refused before sending: with '
        'an index the tool does, without one the library', () async {
      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Geheim',
          'confidential': true,
        }),
        'The confidential folder "Geheim" in the Intradesk folder '
        '$informatica was refused before it was sent: createFolder: folder '
        '$informatica ("Informatica") is an ordinary folder, which holds no '
        'confidential folder: Intradesk refuses one there (HTTP 400), and its '
        'web client offers none. Nothing was sent.',
      );
      expect(intradesk.writes, isEmpty);

      await buildIndex();
      intradesk.writeRequests.clear();
      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Geheim',
          'confidential': true,
        }),
        startsWith(
          'The Intradesk folder Vakken / Informatica (id $informatica) is not '
          'confidential: Intradesk adds a confidential folder only inside a '
          'confidential folder.',
        ),
      );
      expect(
        await error('create_intradesk_folder', {
          'folder_id': dossiers,
          'name': '2026',
        }),
        startsWith(
          'The Intradesk folder Leerlingendossiers (id $dossiers) is '
          'confidential: inside a confidential folder Intradesk adds only '
          'confidential folders. Pass confidential: true',
        ),
      );
      expect(intradesk.writes, isEmpty);

      expect(
        await ok('create_intradesk_folder', {
          'folder_id': dossiers,
          'name': '2026',
          'confidential': true,
        }),
        allOf(
          startsWith(
            'Added the confidential folder "2026" to the Intradesk folder '
            'Leerlingendossiers (id $dossiers)',
          ),
          endsWith('changed 2026-10-05 | confidential'),
        ),
      );
      expect(intradesk.writes, ['POST folders/as-confidential']);
      expect(await found('2026'), ['Leerlingendossiers / 2026']);
    });

    test('refuses an empty name, a name Smartschool does not allow, a '
        'folder_id that is not a folder id, the top of Intradesk and a '
        'colour Intradesk does not have before reading anything; a folder '
        'Intradesk does not have after reading it', () async {
      Future<String> refused(Map<String, Object?> arguments) => error(
        'create_intradesk_folder',
        {'folder_id': informatica, 'name': 'Toetsen', ...arguments},
      );

      expect(
        await refused({'name': '  '}),
        'name is empty: give the new folder a name. Nothing was sent.',
      );
      for (final name in ['a/b', '.verborgen', 'punt.']) {
        expect(
          await refused({'name': name}),
          'Smartschool does not allow the name "$name": no / : * ? " \\ < > '
          '|, and no dot at the start or end. Choose another name. Nothing '
          'was sent.',
        );
      }
      expect(
        await refused({'folder_id': 'Informatica'}),
        startsWith('folder_id must be an Intradesk id like '),
      );
      expect(
        await refused({'folder_id': ' '}),
        startsWith('folder_id is empty: pass the id of the folder to add to'),
      );
      expect(await refused({'color': 'mauve'}), contains('mauve'));
      expect(server.requests, isEmpty, reason: 'not even a login');

      const unknown = '00000000-0000-4000-8000-000000000000';
      expect(
        await refused({'folder_id': unknown}),
        startsWith(
          'Intradesk has no folder with id $unknown: it is the id of a file '
          'or a weblink, or of a folder that does not exist (any more).',
        ),
      );
      expect(
        await refused({'folder_id': verslag}),
        startsWith('Intradesk has no folder with id $verslag'),
      );
      expect(intradesk.writes, isEmpty);
    });

    test('a bare 500 is reported as maybe added, and the create is not sent '
        'again', () async {
      intradesk.nextWrites.add(const FakeIntradeskWrite.serverError());

      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Toetsen',
        }),
        'The folder "Toetsen" in the Intradesk folder $informatica may or may '
        'not have been added: it was sent, but Intradesk did not confirm it. '
        'Do not call create_intradesk_folder again for it: Intradesk does not '
        'refuse a name that is taken, so a second call could add it twice. '
        'First list the folder with list_intradesk_folder (folder_id '
        '$informatica) to see whether it is there. Then tell the user what '
        'you found.',
      );
      expect(intradesk.writes, ['POST folders/']);
      expect(postsTo('folders/'), 1);
      expect(server.logins, 1);
    });

    test('an answer lost after the create went through: maybe added, and the '
        'check the result asks for finds it', () async {
      intradesk.nextWrites.add(const FakeIntradeskWrite.lost());

      expect(
        await error('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Toetsen',
        }),
        contains('may or may not have been added'),
      );
      expect(intradesk.writes, ['POST folders/']);
      expect(
        await ok('list_intradesk_folder', {'folder_id': informatica}),
        contains('- folder | Toetsen | id '),
      );
    });

    test('Smartschool refuses the session for the create, which the library '
        'does not send again: the session repeats the call, which reads the '
        'folder again and makes the folder once', () async {
      server.expireSessionBefore((request) => isPostTo(request, 'folders/'));

      expect(
        await ok('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Toetsen',
        }),
        startsWith('Added the folder "Toetsen" '),
      );
      expect(postsTo('folders/'), 2, reason: 'the refused one and the create');
      expect(intradesk.writes, ['POST folders/'], reason: 'made once');
      // Each call lists the folder, and the library the folder above
      // (yvanvds/dartschool#138).
      expect(intradesk.listed, [informatica, vakken, informatica, vakken]);
      expect(server.logins, 2);
      expect(namesIn(informatica).where((n) => n.startsWith('Toetsen')), [
        'Toetsen',
      ]);
    });

    test('a name taken after the folder was read: Intradesk renames the new '
        'folder, and the result shows the name it stored', () async {
      intradesk.beforeWrite = (path, body) =>
          intradesk.addFolder('Toetsen', parent: informatica);

      expect(
        await ok('create_intradesk_folder', {
          'folder_id': informatica,
          'name': 'Toetsen',
        }),
        allOf(
          startsWith(
            'Added the folder "Toetsen (1)" to the Intradesk folder '
            '$informatica',
          ),
          contains(
            '\nNote: Intradesk stored it as "Toetsen (1)", not "Toetsen": it '
            'renames a new item whose name is taken in the folder, so an item '
            'named "Toetsen" was probably added there meanwhile. Tell the '
            'user.\n',
          ),
          contains('- folder | Toetsen (1) | id ffff'),
        ),
      );
    });
  });

  group('add_intradesk_weblink', () {
    test('sends the name, the address as Intradesk\'s web client sends it, the '
        'icon (earth by default), the parent and the platform once; the '
        'result shows the address as sent, and a search finds the weblink at '
        'once', () async {
      await buildIndex();

      final text = await ok('add_intradesk_weblink', {
        'folder_id': informatica,
        'name': 'Oefenplatform',
        'url': ' example.com/oefenen ',
      });

      expect(
        text,
        'Added the weblink "Oefenplatform" to the Intradesk folder Vakken / '
        'Informatica (id $informatica): it opens http://example.com/oefenen. '
        'Its id is eeee0001-0000-4000-8000-000000000001.\n'
        'Note: the address was sent as http://example.com/oefenen (with '
        'http:// in front), as Intradesk\'s own web client sends it: '
        'Intradesk takes an address only with http:// or https:// in front.\n'
        '- weblink | Vakken / Informatica / Oefenplatform | id '
        'eeee0001-0000-4000-8000-000000000001 | http://example.com/oefenen',
      );
      expect(intradesk.writeRequests.single.path, 'weblinks/');
      expect(intradesk.writeRequests.single.body, {
        'name': 'Oefenplatform',
        'url': 'http://example.com/oefenen',
        'icon': 'earth',
        'parentFolderId': informatica,
        'platform': {'id': 4069},
      });
      expect(await found('oefenplatform'), [
        'Vakken / Informatica / Oefenplatform',
      ]);
      // The folder above twice: the tool's read and the library's.
      expect(intradesk.listed, [
        informatica,
        vakken,
        vakken,
      ], reason: 'no walk');

      await ok('add_intradesk_weblink', {
        'folder_id': informatica,
        'name': 'Handboek',
        'url': 'https://example.com/handboek',
        'icon': 'book',
      });
      expect(intradesk.writeRequests.last.body['icon'], 'book');
    });

    test('refuses an address that is not a web address, and a name the folder '
        'holds already, before sending; Intradesk\'s own refusal is reported '
        'with its reason', () async {
      expect(
        await error('add_intradesk_weblink', {
          'folder_id': informatica,
          'name': 'Oefenplatform',
          'url': 'geen url',
        }),
        'url "geen url" is not a web address that Intradesk takes: give the '
        'address of a web page, like https://example.com/page. Nothing was '
        'sent.',
      );
      expect(
        await error('add_intradesk_weblink', {
          'folder_id': informatica,
          'name': 'SCHOOLSITE',
          'url': 'https://example.com',
        }),
        contains('the weblink "Schoolsite"'),
      );
      expect(intradesk.writes, isEmpty);

      intradesk.nextWrites.add(
        const FakeIntradeskWrite.refused(400, [FakeIntradesk.urlRefusal]),
      );
      expect(
        await error('add_intradesk_weblink', {
          'folder_id': informatica,
          'name': 'Oefenplatform',
          'url': 'https://example.com/oefenen',
        }),
        'Intradesk refused the weblink "Oefenplatform" '
        '(https://example.com/oefenen) in the Intradesk folder $informatica '
        '(HTTP 400): "${FakeIntradesk.urlRefusal}". Nothing was added to '
        'Intradesk.',
      );
      expect(intradesk.writes, ['POST weblinks/']);
      expect(namesIn(informatica), ['Verslag.docx', 'Schoolsite']);
    });

    test('a bare 500 is reported as maybe added, not sent again', () async {
      intradesk.nextWrites.add(const FakeIntradeskWrite.serverError());

      expect(
        await error('add_intradesk_weblink', {
          'folder_id': informatica,
          'name': 'Oefenplatform',
          'url': 'https://example.com/oefenen',
        }),
        startsWith(
          'The weblink "Oefenplatform" (https://example.com/oefenen) in the '
          'Intradesk folder $informatica may or may not have been added',
        ),
      );
      expect(postsTo('weblinks/'), 1);
    });
  });

  group('upload_intradesk_files', () {
    test('asks for a new upload directory, uploads each file into it, has '
        'Intradesk take it once, and lists the files as Intradesk added them; '
        'a search finds them at once', () async {
      await buildIndex();
      final brief = file('brief.docx', 'twenty bytes of text');
      final toets = file('toets #1.pdf', '%PDF');

      final text = await ok('upload_intradesk_files', {
        'folder_id': informatica,
        'paths': [brief, toets],
      });

      expect(
        text,
        'Uploaded 2 files to the Intradesk folder Vakken / Informatica (id '
        '$informatica).\n'
        '- file | Vakken / Informatica / brief.docx | id '
        'cccc0002-0000-4000-8000-000000000002 | 20 bytes | changed 2026-10-05\n'
        '- file | Vakken / Informatica / toets #1.pdf | id '
        'cccc0003-0000-4000-8000-000000000003 | 4 bytes | changed 2026-10-05',
      );
      final dir = server.uploads.directories.keys.single;
      expect(server.uploads.uploads, [
        (dir, 'brief.docx'),
        (dir, 'toets #1.pdf'),
      ]);
      expect(intradesk.writeRequests.single.path, 'files/upload');
      expect(intradesk.writeRequests.single.body, {
        'parentFolderId': informatica,
        'uploadDir': dir,
      });
      expect(await found('toets'), ['Vakken / Informatica / toets #1.pdf']);
      // The folder above twice: the tool's read and the library's.
      expect(intradesk.listed, [
        informatica,
        vakken,
        vakken,
      ], reason: 'no walk');
    });

    test('refuses, before anything is sent, a path that is not a full path, '
        'a file that does not exist, a folder, a file over the limit, two '
        'files with the same name, a name Smartschool does not allow, and a '
        'name the folder holds already', () async {
      Future<String> refused(List<Object?> paths) => error(
        'upload_intradesk_files',
        {'folder_id': informatica, 'paths': paths},
      );
      final brief = file('brief.docx');
      final missing = '${files.path}${Platform.pathSeparator}weg.pdf';

      expect(
        await refused(['brief.docx']),
        '"brief.docx" in paths is not a full path: give the whole path of the '
        'file, starting with the drive, like '
        'C:\\Users\\jan\\Documents\\brief.docx. Nothing was sent.',
      );
      expect(
        await refused([missing]),
        'There is no file "$missing" on this PC (any more): check the path. '
        'Nothing was sent.',
      );
      expect(
        await refused([files.path]),
        '"${files.path}" in paths is a folder, not a file: give the paths of '
        'the files in it. Nothing was sent.',
      );
      final big = file('groot.pdf', 'x' * (_limit + 1));
      expect(
        await refused([big]),
        'The file "groot.pdf" ($big) is 65 bytes, too large to send from '
        'here: files up to 64 bytes can be sent. The user can add it in '
        'Smartschool. Nothing was sent.',
      );
      final other = Directory('${files.path}${Platform.pathSeparator}andere')
        ..createSync();
      final copy = File('${other.path}${Platform.pathSeparator}BRIEF.docx')
        ..writeAsStringSync('copy');
      expect(
        await refused([brief, copy.path]),
        'paths holds two files named "BRIEF.docx" ($brief and ${copy.path}), '
        'which Smartschool would store under the same name: send one of '
        'them, or rename one first. Nothing was sent.',
      );
      final hidden = file('.verborgen');
      expect(
        await refused([hidden]),
        startsWith('Smartschool does not take a file named ".verborgen"'),
      );
      expect(server.uploads.directories, isEmpty);

      final taken = file('verslag.docx');
      expect(
        await refused([brief, taken]),
        'The Intradesk folder $informatica already holds an item with the '
        'name of some of the files: the file "Verslag.docx" (id $verslag). '
        'Intradesk does not refuse a second item with the same name, but adds '
        'the new one under another name (like "name (1)"). Choose another '
        'name, or ask the user what to do. Nothing was sent.',
      );
      expect(server.uploads.directories, isEmpty, reason: 'no upload step');
      expect(intradesk.writes, isEmpty);
    });

    test('a file Smartschool\'s upload step refuses: Smartschool\'s words, '
        'and Intradesk is not told to take the files', () async {
      server.uploads.nextRefusals.add((400, FakeUploads.badNameText));

      expect(
        await error('upload_intradesk_files', {
          'folder_id': informatica,
          'paths': [file('brief.docx')],
        }),
        'Smartschool refused the file "brief.docx" (HTTP 400): '
        '"${FakeUploads.badNameText}" Rename the file, or leave it out. '
        'Nothing was added to Intradesk.',
      );
      expect(server.uploads.uploads, hasLength(1));
      expect(intradesk.writes, isEmpty);
    });

    test('a file Intradesk did not take is reported with its reason, next to '
        'the files it added', () async {
      intradesk.refusedUploads['te groot.pdf'] = 'Het bestand is te groot.';

      final text = await ok('upload_intradesk_files', {
        'folder_id': informatica,
        'paths': [file('brief.docx'), file('te groot.pdf')],
      });

      expect(
        text,
        allOf(
          startsWith('Uploaded 1 file to the Intradesk folder $informatica.\n'),
          contains('\n- file | brief.docx | id cccc0002-'),
          endsWith(
            '\nIntradesk did not take 1 file, which was not added:\n'
            '- te groot.pdf: "Het bestand is te groot."',
          ),
        ),
      );
      expect(namesIn(informatica), [
        'Verslag.docx',
        'brief.docx',
        'Schoolsite',
      ]);
    });

    test('a name taken after the folder was read: Intradesk renames the new '
        'file, and the result says so', () async {
      intradesk.beforeWrite = (path, body) =>
          intradesk.addFile('brief.docx', parent: informatica);

      expect(
        await ok('upload_intradesk_files', {
          'folder_id': informatica,
          'paths': [file('brief.docx')],
        }),
        allOf(
          contains('\n- file | brief (1).docx | id '),
          contains(
            '\nNote: Intradesk stored "brief (1).docx" under another name '
            'than any file sent',
          ),
        ),
      );
    });

    test('Smartschool refuses the session for taking the files, which the '
        'library does not send again: the repeat asks for a new upload '
        'directory and adds the files once', () async {
      server.expireSessionBefore(
        (request) => isPostTo(request, 'files/upload'),
      );

      expect(
        await ok('upload_intradesk_files', {
          'folder_id': informatica,
          'paths': [file('brief.docx')],
        }),
        startsWith('Uploaded 1 file '),
      );
      expect(postsTo('files/upload'), 2, reason: 'the refused one and one');
      expect(intradesk.writes, ['POST files/upload'], reason: 'taken once');
      expect(server.uploads.directories, hasLength(2));
      expect(server.logins, 2);
      expect(namesIn(informatica).where((n) => n.startsWith('brief')), [
        'brief.docx',
      ]);
    });

    test(
      'a bare 500 for taking the files: maybe uploaded, not sent again',
      () async {
        intradesk.nextWrites.add(const FakeIntradeskWrite.serverError());
        final brief = file('brief.docx');

        expect(
          await error('upload_intradesk_files', {
            'folder_id': informatica,
            'paths': [brief],
          }),
          startsWith(
            'The file "brief.docx" (21 bytes) for the Intradesk folder '
            '$informatica may or may not have been added: it was sent, but '
            'Intradesk did not confirm it. Do not call upload_intradesk_files '
            'again for it',
          ),
        );
        expect(postsTo('files/upload'), 1);
      },
    );
  });

  group('trash_intradesk_items', () {
    /// The `items` argument for [items], each `(kind, id)`.
    Map<String, Object?> trash(List<(String, String)> items) => {
      'items': [
        for (final (kind, id) in items) {'kind': kind, 'id': id},
      ],
    };

    /// The line of Verslag.docx as the index has it.
    String verslagLine() =>
        'file | Vakken / Informatica / Verslag.docx | id $verslag | 1000 '
        'bytes | changed 2024-08-29';

    /// The line of the weblink Schoolsite as the index has it.
    const schoolsiteLine =
        'weblink | Vakken / Informatica / Schoolsite | id $schoolsite | '
        'https://www.example.com';

    test(
      'is listed as a write Claude Desktop asks approval for, that a '
      'second call does not change, to be called only after the user '
      'confirmed each item, with 1 to 20 items of a kind and an id',
      () async {
        final tool = (await connection.listTools(
          ListToolsRequest(),
        )).tools.singleWhere((tool) => tool.name == 'trash_intradesk_items');

        expect(tool.toolAnnotations?.readOnlyHint, isFalse);
        expect(tool.toolAnnotations?.destructiveHint, isTrue);
        expect(tool.toolAnnotations?.idempotentHint, isTrue);
        expect(tool.toolAnnotations?.openWorldHint, isTrue);
        expect(
          tool.description,
          allOf(
            contains(
              'only call this tool after the user has explicitly confirmed it',
            ),
            contains('show the user each item by its name and path'),
            contains('a folder goes to the trash with everything in it'),
            contains('Intradesk keeps its trash for 30 days'),
            contains('restore an item from the trash in Intradesk itself'),
            contains('cannot restore anything, nor delete anything for good'),
            contains('Moving an item to the trash again is harmless'),
          ),
        );
        expect(tool.inputSchema.required, ['items']);
        final items = tool.inputSchema.properties!['items']! as Map;
        expect(items['minItems'], 1);
        expect(items['maxItems'], maxIntradeskTrashItems);
        expect(maxIntradeskTrashItems, 20);
        final item = items['items'] as Map;
        expect(item['required'], ['kind', 'id']);
        expect(
          (item['properties'] as Map)['kind'],
          containsPair('enum', ['folder', 'file', 'weblink']),
        );
      },
    );

    test('with an index: moves each kind in order, sending {} to '
        '{kind}/{id}/trash, names each item by its path, says what went '
        'along with a folder, and patches the index, so that a search finds '
        'none of it at once, also in a new server process', () async {
      final oud = intradesk.addFolder('Oud 2025', parent: vakken);
      intradesk.addFile('planning 2025.xlsx', parent: oud);
      final toetsen = intradesk.addFolder('Toetsen 2025', parent: oud);
      intradesk.addWeblink({
        'id': 'eeee8888-0000-4000-8000-000000008888',
        'name': 'Oefensite 2025',
        'url': 'https://example.com/2025',
      }, parent: toetsen);
      await buildIndex();

      final text = await ok(
        'trash_intradesk_items',
        trash([
          ('file', verslag),
          ('weblink', schoolsite.toUpperCase()),
          ('folder', oud),
        ]),
      );

      expect(
        text,
        'Moved 3 items to Intradesk\'s trash.\n'
        '- ${verslagLine()}\n'
        '- $schoolsiteLine\n'
        '- folder | Vakken / Oud 2025 | id $oud | changed 2024-05-30\n'
        'Intradesk keeps its trash for 30 days: until then, the user can '
        'restore them from the trash in Intradesk itself.\n'
        'Note: the folder "Vakken / Oud 2025" (id $oud) went to the trash '
        'with everything in it: the Intradesk index had 3 items in it (1 '
        'folder, 1 file and 1 weblink).',
      );
      expect(
        [for (final request in intradesk.writeRequests) request.path],
        [
          'files/$verslag/trash',
          'weblinks/$schoolsite/trash',
          'folders/$oud/trash',
        ],
      );
      expect([
        for (final request in intradesk.writeRequests) request.body,
      ], everyElement(isEmpty));
      expect(intradesk.trashed, [verslag, schoolsite, oud]);
      expect(namesIn(informatica), isEmpty);
      expect(namesIn(vakken), ['Informatica']);
      expect(intradesk.listed, isEmpty, reason: 'nothing read before');

      for (final query in [
        'verslag',
        'schoolsite',
        'oud',
        'planning',
        'toetsen',
        'oefensite',
      ]) {
        expect(await found(query), isEmpty, reason: query);
      }
      expect(await found('informatica'), ['Vakken / Informatica']);
      final again = await start();
      expect(await found('planning', again), isEmpty);
      expect(await found('informatica', again), ['Vakken / Informatica']);
      expect(intradesk.listed, isEmpty, reason: 'no walk');
    });

    test('without an index: names each item by its kind and id and builds '
        'none; the folder no longer lists the item', () async {
      final text = await ok(
        'trash_intradesk_items',
        trash([('file', verslag)]),
      );

      expect(
        text,
        'Moved 1 item to Intradesk\'s trash.\n'
        '- file | id $verslag\n'
        'Intradesk keeps its trash for 30 days: until then, the user can '
        'restore it from the trash in Intradesk itself.',
      );
      expect(intradesk.writes, ['POST files/$verslag/trash']);
      expect(intradesk.listed, isEmpty, reason: 'no walk');
      expect(await cache.saved(), isNull);
      expect(
        await ok('list_intradesk_folder', {'folder_id': informatica}),
        allOf(contains('Schoolsite'), isNot(contains('Verslag.docx'))),
      );
    });

    test('an item in the trash already, by itself or in a folder in the '
        'trash: Intradesk answers 204 as the first time, so it is reported '
        'as moved', () async {
      await ok('trash_intradesk_items', trash([('folder', informatica)]));

      expect(
        await ok(
          'trash_intradesk_items',
          trash([('folder', informatica), ('file', verslag)]),
        ),
        startsWith(
          'Moved 2 items to Intradesk\'s trash.\n'
          '- folder | id $informatica\n'
          '- file | id $verslag\n',
        ),
      );
      expect(intradesk.writes, [
        'POST folders/$informatica/trash',
        'POST folders/$informatica/trash',
        'POST files/$verslag/trash',
      ]);
      expect(intradesk.trashed, [informatica]);
    });

    test('an id Intradesk has no item of that kind for: its refusal is '
        'reported for that item, and the moves stop there, with what was '
        'moved and what was not tried; the index loses only what was '
        'moved', () async {
      await buildIndex();
      const unknown = '00000000-0000-4000-8000-000000000000';

      final text = await error(
        'trash_intradesk_items',
        trash([
          ('file', verslag),
          ('folder', unknown),
          ('weblink', schoolsite),
        ]),
      );

      expect(
        text,
        'Moving to Intradesk\'s trash stopped at item 2 of 3: 1 item was '
        'moved.\n'
        'Moved to the trash:\n'
        '- ${verslagLine()}\n'
        'Not moved:\n'
        '- folder | id $unknown\n'
        'Not tried:\n'
        '- $schoolsiteLine\n'
        'Intradesk refused the move of the folder with id $unknown to the '
        'trash (HTTP 404), without saying why. It was not moved. Check its '
        'kind and id with list_intradesk_folder or search_intradesk, and '
        'tell the user.\n'
        'Intradesk keeps its trash for 30 days: until then, the user can '
        'restore it from the trash in Intradesk itself.',
      );
      expect(intradesk.writes, [
        'POST files/$verslag/trash',
        'POST folders/$unknown/trash',
      ]);
      expect(namesIn(informatica), ['Schoolsite']);
      expect(await found('verslag'), isEmpty);
      expect(await found('schoolsite'), ['Vakken / Informatica / Schoolsite']);

      // The id of a file the index does not know, passed as a folder's, is
      // sent, and refused the same way.
      final oud = intradesk.addFile('oud.pdf', parent: archief);
      expect(
        await error('trash_intradesk_items', trash([('folder', oud)])),
        allOf(
          startsWith(
            'Moving to Intradesk\'s trash stopped at item 1 of 1: nothing '
            'was moved.\n'
            'Not moved:\n'
            '- folder | id $oud\n',
          ),
          contains('(HTTP 404)'),
          isNot(contains('Intradesk keeps its trash')),
        ),
      );
      expect(namesIn(archief), ['oud.pdf']);
    });

    test('a refusal (HTTP 400 to 499) is reported with Intradesk\'s reasons, '
        'if any: nothing was moved', () async {
      intradesk.nextWrites
        ..add(const FakeIntradeskWrite.refused(403))
        // Made up: no refusal of a move to the trash was seen live.
        ..add(const FakeIntradeskWrite.refused(400, ['Dit kan niet.']));

      expect(
        await error('trash_intradesk_items', trash([('file', verslag)])),
        endsWith(
          '\nIntradesk refused the move of the file with id $verslag to the '
          'trash (HTTP 403), without saying why. It was not moved. Check its '
          'kind and id with list_intradesk_folder or search_intradesk, and '
          'tell the user.',
        ),
      );
      expect(
        await error('trash_intradesk_items', trash([('file', verslag)])),
        contains('to the trash (HTTP 400): "Dit kan niet.". It was not moved.'),
      );
      expect(intradesk.trashed, isEmpty);
      expect(namesIn(informatica), ['Verslag.docx', 'Schoolsite']);
    });

    test('a bare 500 is reported as maybe moved, with the folder to list, and '
        'not sent again; the index keeps the item, and the items after it '
        'are not tried', () async {
      await buildIndex();
      intradesk.nextWrites.add(const FakeIntradeskWrite.serverError());

      expect(
        await error(
          'trash_intradesk_items',
          trash([('file', verslag), ('folder', archief)]),
        ),
        'Moving to Intradesk\'s trash stopped at item 1 of 2: nothing was '
        'moved.\n'
        'Maybe moved:\n'
        '- ${verslagLine()}\n'
        'Not tried:\n'
        '- folder | Archief | id $archief | changed 2024-05-30\n'
        'The file "Vakken / Informatica / Verslag.docx" (id $verslag) may or '
        'may not have been moved to the trash: it was sent, but Intradesk '
        'did not confirm it. Moving it to the trash again is harmless. First '
        'list its folder, Vakken / Informatica, with list_intradesk_folder '
        '(folder_id $informatica) to see whether it is still there. Then '
        'tell the user what you found.',
      );
      expect(postsTo('files/$verslag/trash'), 1);
      expect(intradesk.writes, ['POST files/$verslag/trash']);
      expect(await found('verslag'), ['Vakken / Informatica / Verslag.docx']);

      // An item at the top of Intradesk is listed without folder_id.
      intradesk.nextWrites.add(const FakeIntradeskWrite.serverError());
      expect(
        await error('trash_intradesk_items', trash([('folder', archief)])),
        contains(
          'First list the top of Intradesk with list_intradesk_folder '
          '(without folder_id) to see whether it is still there.',
        ),
      );
    });

    test('an answer lost after the move went through: maybe moved; the '
        'listing the result asks for shows it gone, and moving it again is '
        'harmless', () async {
      intradesk.nextWrites.add(const FakeIntradeskWrite.lost());

      expect(
        await error('trash_intradesk_items', trash([('file', verslag)])),
        allOf(
          contains('\nMaybe moved:\n- file | id $verslag\n'),
          contains(
            'First list the folder it was in with list_intradesk_folder to '
            'see whether it is still there.',
          ),
        ),
      );
      expect(
        await ok('list_intradesk_folder', {'folder_id': informatica}),
        isNot(contains('Verslag.docx')),
      );
      expect(
        await ok('trash_intradesk_items', trash([('file', verslag)])),
        startsWith('Moved 1 item to Intradesk\'s trash.\n'),
      );
      expect(intradesk.trashed, [verslag]);
    });

    test('refuses, before anything is sent, an id that is not an Intradesk '
        'id, an id passed as two kinds, and what the input schema does not '
        'allow; with an index, an id it knows as another kind; the same item '
        'twice is moved once', () async {
      expect(
        await error(
          'trash_intradesk_items',
          trash([('file', verslag), ('folder', '../../messages')]),
        ),
        'The id of item 2, "../../messages", is not an Intradesk id like '
        '0a1b2c3d-1111-4222-8333-444455556666, as list_intradesk_folder and '
        'search_intradesk show them. Nothing was sent.',
      );
      expect(
        await error(
          'trash_intradesk_items',
          trash([('file', verslag), ('folder', verslag.toUpperCase())]),
        ),
        'Items 1 and 2 have the same id $verslag, once as a file and once as '
        'a folder: an id names one item. Check its kind with '
        'list_intradesk_folder or search_intradesk. Nothing was sent.',
      );
      await error('trash_intradesk_items', {'items': <Object?>[]});
      await error('trash_intradesk_items', trash([('map', verslag)]));
      await error('trash_intradesk_items', trash([('file', '')]));
      await error(
        'trash_intradesk_items',
        trash([
          for (var i = 0; i <= maxIntradeskTrashItems; i++) ('file', verslag),
        ]),
      );
      expect(server.requests, isEmpty, reason: 'not even a login');

      await buildIndex();
      expect(
        await error('trash_intradesk_items', trash([('folder', verslag)])),
        'Item 1 is passed as a folder, but the Intradesk index knows id '
        '$verslag as the file "Vakken / Informatica / Verslag.docx". Check '
        'with the user that this is the item they confirmed, and pass kind '
        'file. Nothing was sent.',
      );
      // Numbered as passed, also after an item named twice; the index knows
      // a weblink by its id too.
      expect(
        await error(
          'trash_intradesk_items',
          trash([('file', verslag), ('file', verslag), ('file', schoolsite)]),
        ),
        'Item 3 is passed as a file, but the Intradesk index knows id '
        '$schoolsite as the weblink "Vakken / Informatica / Schoolsite". '
        'Check with the user that this is the item they confirmed, and pass '
        'kind weblink. Nothing was sent.',
      );
      expect(intradesk.writes, isEmpty);

      expect(
        await ok(
          'trash_intradesk_items',
          trash([('file', verslag), ('file', ' ${verslag.toUpperCase()} ')]),
        ),
        startsWith('Moved 1 item to Intradesk\'s trash.\n- ${verslagLine()}\n'),
      );
      expect(intradesk.writes, ['POST files/$verslag/trash']);
    });

    test('Smartschool refuses the session for a move: the library logs in '
        'again and sends the move again, and the item is moved once', () async {
      server.expireSessionBefore(
        (request) => isPostTo(request, 'files/$verslag/trash'),
      );

      expect(
        await ok('trash_intradesk_items', trash([('file', verslag)])),
        startsWith('Moved 1 item to Intradesk\'s trash.\n'),
      );
      expect(postsTo('files/$verslag/trash'), 2, reason: 'refused, then sent');
      expect(intradesk.writes, ['POST files/$verslag/trash']);
      expect(intradesk.trashed, [verslag]);
      expect(server.logins, 2);
    });

    test('a login that fails before a move: that item is not moved, and the '
        'result says which were', () async {
      intradesk.beforeWrite = (path, body) {
        if (path != 'files/$verslag/trash') return;
        // The password changes, and the session ends, before the next move.
        server.passwordAccepted = false;
        server.expireSessionBefore(
          (request) => isPostTo(request, 'weblinks/$schoolsite/trash'),
        );
      };

      final text = await error(
        'trash_intradesk_items',
        trash([('file', verslag), ('weblink', schoolsite)]),
      );

      expect(
        text,
        allOf(
          startsWith(
            'Moving to Intradesk\'s trash stopped at item 2 of 2: 1 item was '
            'moved.\n'
            'Moved to the trash:\n'
            '- file | id $verslag\n'
            'Not moved:\n'
            '- weblink | id $schoolsite\n',
          ),
          contains(
            ' The weblink with id $schoolsite was not moved to the trash.\n'
            'Intradesk keeps its trash for 30 days',
          ),
        ),
      );
      expect(intradesk.trashed, [verslag]);
      expect(namesIn(informatica), ['Schoolsite']);
    });
  });
}
