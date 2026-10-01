/// `search_intradesk` and `list_intradesk_folder`, called over MCP on the
/// real server, session, library and index cache, against a fake Smartschool
/// serving the dartschool Intradesk fixtures; and the tree walk behind the
/// index.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_access.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_index.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_walk.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _documenten = 'aaaa1111-1111-4111-b111-111111111111';
const _examens = 'aaaa2222-2222-4222-b222-222222222222';
const _archief = 'bbbb1111-1111-4111-b111-111111111111';
const _welkom = 'cccc1111-1111-4111-b111-111111111111';
const _info = 'cccc2222-2222-4222-b222-222222222222';

/// The start of the line that ends a search result.
final _indexLine = RegExp(r'^Index of \d{4}-\d\d-\d\d \d\d:\d\d: ');

void main() {
  late FakeSmartschool server;
  late Directory cookies;
  late Directory cacheFolder;
  late Duration clockOffset;
  late Duration buildWait;
  late SmartschoolSession session;
  late IntradeskIndexCache cache;
  late ServerConnection connection;

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
      buildWait: buildWait,
      now: () => DateTime.now().add(clockOffset),
    );
    // Before the session closes: a walk may still run.
    addTearDown(() => current.walkDone);
    final (connection, _) = await connect(
      tools: [
        searchIntradeskTool(session, current),
        listIntradeskFolderTool(session, current),
      ],
    );
    return connection;
  }

  setUp(() async {
    server = FakeSmartschool()..intradesk.loadFixtures();
    cookies = await tempCache();
    cacheFolder = await tempCache();
    clockOffset = Duration.zero;
    buildWait = const Duration(seconds: 10);
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

  Future<String> search(
    Map<String, Object?> arguments, [
    ServerConnection? on,
  ]) => ok('search_intradesk', arguments, on);

  Future<String> list([String? folderId]) =>
      ok('list_intradesk_folder', {'folder_id': ?folderId});

  /// The lines of a search result before the index line.
  List<String> hits(String result) => [
    for (final line in result.split('\n').skip(1))
      if (line.startsWith('- ')) line,
  ];

  group('the tools', () {
    test('are listed as read-only, with their arguments', () async {
      final tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };

      expect(tools.keys, ['search_intradesk', 'list_intradesk_folder']);
      for (final tool in tools.values) {
        expect(tool.toolAnnotations?.readOnlyHint, isTrue);
        expect(tool.toolAnnotations?.destructiveHint, isNot(true));
      }
      final search = tools['search_intradesk']!;
      expect(search.inputSchema.required, ['query']);
      expect(search.inputSchema.properties!.keys, [
        'query',
        'folder_id',
        'limit',
        'refresh',
      ]);
      expect(search.description, contains('Only names are searched'));
      expect(search.description, contains('list_intradesk_folder'));
      expect(search.description, contains('refresh: true'));
      final list = tools['list_intradesk_folder']!;
      expect(list.inputSchema.required, isNull);
      expect(list.inputSchema.properties!.keys, ['folder_id']);
      expect(list.description, contains('search_intradesk'));
    });
  });

  group('list_intradesk_folder', () {
    test('lists the top of Intradesk: folders, then files, with ids, size '
        'and date changed', () async {
      expect(
        await list(),
        'Intradesk, top level: 2 folders, 1 file.\n'
        '- folder | Documenten | id $_documenten | changed 2024-08-29\n'
        '- folder | Examens | id $_examens | changed 2024-05-30\n'
        '- file | welkom.docx | id $_welkom | 178 KB | changed 2023-02-13',
      );
      expect(server.intradesk.listed, ['']);
    });

    test('lists a folder by id, named by its path once an index knows it; '
        'an empty folder says so', () async {
      const documenten =
          '1 folder, 1 file.\n'
          '- folder | Archief | id $_archief | changed 2023-05-30\n'
          '- file | info.pdf | id $_info | 50 KB | changed 2023-09-15';
      expect(
        await list(_documenten),
        'Intradesk folder $_documenten: $documenten',
      );
      expect(await list(_examens), 'Intradesk folder $_examens: empty.');

      await search({'query': 'welkom'});
      expect(
        await list(_documenten),
        'Intradesk folder Documenten (id $_documenten): $documenten',
      );
      expect(
        await list(_archief),
        'Intradesk folder Documenten / Archief (id $_archief): empty.',
      );
    });

    test('shows weblinks and confidential items', () async {
      server.intradesk
        ..addWeblink({
          'id': 'w1',
          'name': 'Schoolsite',
          'url': 'https://www.example.com',
        })
        ..addWeblink({'id': 'w2', 'url': 'https://unnamed.example.com'})
        ..addFile('verslag.docx', confidential: true, size: 2516582);

      final text = await list();

      expect(
        text,
        startsWith(
          'Intradesk, top level: 2 folders, 2 files, '
          '1 weblink.\n',
        ),
      );
      expect(
        text,
        contains(
          '\n- file | verslag.docx | id cccc0001-0000-4000-8000-000000000001 '
          '| 2.4 MB | changed 2024-08-29 | confidential\n',
        ),
      );
      expect(
        text,
        endsWith('\n- weblink | Schoolsite | https://www.example.com'),
      );
    });

    test('a folder with more than $maxIntradeskFolderItems items shows the '
        'first ones and says so', () async {
      for (var i = 1; i <= maxIntradeskFolderItems; i++) {
        server.intradesk.addFile('bijlage $i.pdf');
      }

      final lines = (await list()).split('\n');

      expect(lines.first, 'Intradesk, top level: 2 folders, 501 files.');
      expect(lines, hasLength(1 + maxIntradeskFolderItems + 1));
      expect(
        lines.last,
        'Note: only the first 500 of the 503 are shown. Use search_intradesk '
        'to find one by name.',
      );
    });

    test('an id that is not an Intradesk id is refused without asking '
        'Smartschool', () async {
      final text = await error('list_intradesk_folder', {
        'folder_id': '../../messages',
      });

      expect(text, startsWith('folder_id must be an Intradesk id like '));
      expect(text, endsWith('"../../messages" is not.'));
      expect(server.intradesk.listed, isEmpty);
    });

    test('an id that is not a folder (unknown, a file or a weblink) is an '
        'error that says so', () async {
      const unknown = '00000000-0000-4000-8000-000000000000';
      const weblink = 'eeee1111-1111-4111-b111-111111111111';
      server.intradesk.addWeblink({
        'id': weblink,
        'name': 'Schoolsite',
        'url': 'https://www.example.com',
      }, parent: _documenten);
      String notAFolder(String id) =>
          'Intradesk has no folder with id $id: it is the id of a file or a '
          'weblink, or of a folder that does not exist (any more). Take the '
          'id of a folder from list_intradesk_folder or search_intradesk; to '
          'read a file, use read_intradesk_file.';

      for (final id in [unknown, _welkom, weblink]) {
        expect(
          await error('list_intradesk_folder', {'folder_id': id}),
          notAFolder(id),
        );
      }
      expect(server.intradesk.listed, [unknown, _welkom, weblink]);
    });

    test('a folder Smartschool fails to list is an error, not a wrong '
        'id', () async {
      // The library asks for the parents of a folder whose listing fails
      // with a 500: Smartschool knows the folder, so the failure is its own.
      server.intradesk
        ..failing[_documenten] = 500
        ..failing[_archief] = 500
        ..failing[_examens] = 403;
      const failed =
          'The tool list_intradesk_folder failed with an unexpected error. '
          'The technical details are in the server log.';

      for (final id in [_documenten, _archief, _examens]) {
        expect(await error('list_intradesk_folder', {'folder_id': id}), failed);
      }
    });

    test('an id in capitals is the same folder', () async {
      await search({'query': 'welkom'});
      expect(
        await list(_documenten.toUpperCase()),
        startsWith('Intradesk folder Documenten (id $_documenten): '),
      );
      expect(server.intradesk.listed.last, _documenten);
    });
  });

  group('search_intradesk', () {
    test('finds files and folders by name with their full path, walking '
        'every folder once', () async {
      final text = await search({'query': 'INFO'});

      expect(text.split('\n'), [
        'Intradesk: 1 of the 5 names searched matches all of: info, best '
            'first.',
        '- file | Documenten / info.pdf | id $_info | 50 KB | changed '
            '2023-09-15',
        matches(_indexLine),
      ]);
      expect(
        text.split('\n').last,
        endsWith(
          ': 3 folders, 2 files, 0 weblinks. Names only, not what is in the '
          'files. For something added since, search again with refresh: '
          'true.',
        ),
      );
      expect(
        server.intradesk.listed,
        unorderedEquals(['', _documenten, _examens, _archief]),
      );
    });

    test('every word must occur in the path, one in the name; folders '
        'match too', () async {
      expect(hits(await search({'query': 'documenten archief'})), [
        '- folder | Documenten / Archief | id $_archief | changed 2023-05-30',
      ]);
      expect(hits(await search({'query': 'documenten'})), [
        '- folder | Documenten | id $_documenten | changed 2024-08-29',
      ]);
    });

    test('no match says what was searched', () async {
      final text = await search({'query': 'uitstap formulier'});

      expect(
        text.split('\n').first,
        'Intradesk: no name matches all of: uitstap, formulier (5 names '
        'searched).',
      );
      expect(hits(text), isEmpty);
    });

    test('a second search uses the index, also after a restart; refresh '
        'walks again', () async {
      final first = await search({'query': 'welkom'});
      server.intradesk.listed.clear();

      expect(await search({'query': 'welkom'}), first);
      final restarted = await start();
      expect(await search({'query': 'welkom'}, restarted), first);
      expect(server.intradesk.listed, isEmpty);
      expect(server.logins, 1, reason: 'the restart reuses the saved session');

      server.intradesk.addFile('welkom 2.docx');
      final refreshed = await search({'query': 'welkom', 'refresh': true});
      expect(server.intradesk.listed, hasLength(4));
      expect(hits(refreshed), hasLength(2));
    });

    test('wired like the server (IntradeskIndexCache.of): the index is saved '
        'in intradesk/<host> in the cache folder of the library\'s client, '
        'next to the session cookies, where a restart finds it', () async {
      Future<ServerConnection> startOfSession() async {
        final session = SmartschoolSession(
          fakeExtensionSettings(),
          createClient: fakeClientFactory(server, cookies),
        );
        addTearDown(session.close);
        final cache = IntradeskIndexCache.of(session, buildWait: buildWait);
        addTearDown(() => cache.walkDone);
        final (connection, _) = await connect(
          tools: [
            searchIntradeskTool(session, cache),
            listIntradeskFolderTool(session, cache),
          ],
        );
        return connection;
      }

      final first = await search({'query': 'welkom'}, await startOfSession());

      final index = File(
        [
          cookies.path,
          'intradesk',
          fakeHost,
          'index.json',
        ].join(Platform.pathSeparator),
      );
      expect(index.existsSync(), isTrue);
      expect(cacheFolder.listSync(), isEmpty);

      server.intradesk.listed.clear();
      expect(await search({'query': 'welkom'}, await startOfSession()), first);
      expect(server.intradesk.listed, isEmpty);
    });

    test('an index older than a day answers at once, with a note, while a '
        'new one is built; the next search uses the new one', () async {
      await search({'query': 'welkom'});
      server.intradesk
        ..listed.clear()
        ..addFile('welkom 2.docx');

      clockOffset = const Duration(hours: 23);
      expect(hits(await search({'query': 'welkom'})), hasLength(1));
      expect(server.intradesk.listed, isEmpty);

      clockOffset = const Duration(hours: 25);
      server.latency = const Duration(milliseconds: 20);
      final old = await search({'query': 'welkom'});
      expect(hits(old), hasLength(1));
      expect(
        old.split('\n').last,
        matches(
          RegExp(
            r'Names only, not what is in the files\. A new index is being '
            r'built \(\d+ folders? listed and \d+ waiting after \d+ seconds, '
            r'\d+ names? found so far\); search again in a few minutes for '
            r'up-to-date results\.$',
          ),
        ),
      );
      await cache.walkDone;
      clockOffset = Duration.zero; // the new index is from the real now
      final renewed = await search({'query': 'welkom'});
      expect(hits(renewed), hasLength(2));
      expect(renewed, contains('For something added since, search again'));
      expect(server.intradesk.listed, hasLength(4));
    });

    test('while the first index takes longer than buildWait, the result '
        'says it is being built; a later search has the results', () async {
      buildWait = const Duration(milliseconds: 30);
      final connection = await start();
      server.latency = const Duration(milliseconds: 40);

      final (result, text) = await callTool(connection, 'search_intradesk', {
        'query': 'info',
      });

      expect(result.isError, isNot(true));
      expect(
        text,
        matches(
          RegExp(
            r'^Intradesk is being indexed, so there are no search results '
            r'yet: \d+ folders? listed and \d+ waiting after \d+ seconds, '
            r'\d+ names? found so far\. Indexing a large Intradesk takes a '
            r'few minutes\. Search again in a minute; once the index is '
            r'ready, it is kept for 24 hours\.$',
          ),
        ),
      );
      await cache.walkDone;
      expect(hits(await search({'query': 'info'}, connection)), hasLength(1));
      expect(
        server.intradesk.listed,
        unorderedEquals(['', _documenten, _examens, _archief]),
        reason: 'one walk',
      );
    });

    test('folder_id limits the search to that folder at any depth', () async {
      expect(
        hits(await search({'query': 'archief', 'folder_id': _documenten})),
        ['- folder | Documenten / Archief | id $_archief | changed 2023-05-30'],
      );
      final outside = await search({
        'query': 'welkom',
        'folder_id': _documenten,
      });
      expect(
        outside.split('\n').first,
        'Intradesk folder Documenten: no name matches all of: welkom (2 names '
        'searched).',
      );
    });

    test('folder_id must be a folder in the index', () async {
      const unknown = '00000000-0000-4000-8000-000000000000';
      expect(
        await error('search_intradesk', {'query': 'x', 'folder_id': unknown}),
        allOf(
          startsWith('No folder with id $unknown in the Intradesk index of '),
          endsWith('search again with refresh: true.'),
        ),
      );
      expect(
        await error('search_intradesk', {'query': 'x', 'folder_id': _welkom}),
        '$_welkom is the file welkom.docx, not a folder.',
      );
      expect(
        await error('search_intradesk', {'query': 'x', 'folder_id': 'map'}),
        startsWith('folder_id must be an Intradesk id like '),
      );
    });

    test('an empty query is refused without walking', () async {
      expect(
        await error('search_intradesk', {'query': ' ?! '}),
        'query is empty: pass words from the name to look for.',
      );
      expect(server.intradesk.listed, isEmpty);
    });

    test('limit cuts the list and says so; weblinks and confidential items '
        'are found too', () async {
      final map = server.intradesk.addFolder('Uitstappen', confidential: true);
      for (var i = 1; i <= 3; i++) {
        server.intradesk.addFile('uitstap $i.pdf', parent: map);
      }
      server.intradesk.addWeblink({
        'id': 'w1',
        'name': 'Uitstap-info',
        'url': 'https://www.example.com/uitstap',
      }, parent: map);

      final text = await search({'query': 'uitstap', 'limit': 2.0});

      expect(text.split('\n').take(3), [
        'Intradesk: 5 of the 10 names searched match all of: uitstap; showing '
            'the best 2 (raise limit to see more), best first.',
        '- folder | Uitstappen | id $map | changed 2024-05-30 | confidential',
        '- file | Uitstappen / uitstap 1.pdf | id '
            'cccc0001-0000-4000-8000-000000000001 | 1000 bytes | changed '
            '2024-08-29',
      ]);
      expect(text, contains(': 4 folders, 5 files, 1 weblink.'));
      expect(hits(await search({'query': 'uitstappen'})), [
        '- folder | Uitstappen | id $map | changed 2024-05-30 | confidential',
      ]);
    });

    test('a folder Smartschool refuses to list is left out, and the result '
        'says so', () async {
      server.intradesk.failing[_documenten] = 403;

      final text = await search({'query': 'welkom'});

      expect(hits(text), hasLength(1));
      expect(text, contains(': 2 folders, 1 file, 0 weblinks.'));
      expect(
        text.split('\n').last,
        'Note: Smartschool did not list the contents of 1 folder, so it was '
        'not searched.',
      );
    });

    test('when the session expires during the walk, the listings in progress '
        'share one new login and are retried, without walking again', () async {
      for (var i = 1; i <= 6; i++) {
        server.intradesk.addFolder('Map $i');
      }
      await list(); // logs in
      server
        ..latency = const Duration(milliseconds: 20)
        ..maxInFlight = 0
        ..expireSessionBefore(
          (request) => request.uri.path.endsWith('/$_documenten'),
        );
      server.requests.clear();
      server.intradesk.listed.clear();

      final text = await search({'query': 'info'});

      expect(hits(text), hasLength(1));
      expect(text, contains(': 9 folders, 2 files, 0 weblinks.'));
      expect(
        server.maxInFlight,
        intradeskWalkConcurrency,
        reason: 'several listings were in progress when the session expired',
      );
      // One new login, not one per listing that found the session expired:
      // each would send the same 2FA code (yvanvds/dartschool#36, #20). The
      // library shares it and retries each refused listing.
      expect(server.logins, 2);
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
      expect(
        server.requests.where(
          (r) => r == 'POST /2fa/api/v1/google-authenticator',
        ),
        hasLength(1),
      );
      expect(
        server.intradesk.listed.where((id) => id == ''),
        hasLength(1),
        reason: 'the walk does not start again from the root',
      );
      expect(
        server.intradesk.listed.where((id) => id == _documenten),
        hasLength(1),
        reason: 'the refused listing is retried once, not listed twice',
      );
    });

    test('when the server shuts down during the walk, the walk stops and '
        'saves no partial index', () async {
      for (var i = 1; i <= 12; i++) {
        server.intradesk.addFolder('Map $i');
      }
      buildWait = const Duration(milliseconds: 30);
      final connection = await start();
      server.latency = const Duration(milliseconds: 40);

      final (_, text) = await callTool(connection, 'search_intradesk', {
        'query': 'info',
      });
      expect(text, startsWith('Intradesk is being indexed'));
      // What the server does when Claude Desktop disconnects; the library
      // then refuses every request of the walk.
      await session.close();
      await cache.walkDone;

      expect(await cache.read(), isNull);
      expect(server.intradesk.listed.length, lessThan(1 + 2 + 12 + 1));
    });

    test('without Smartschool settings: the missing settings, before the '
        'cache is touched', () async {
      final session = SmartschoolSession(
        fakeExtensionSettings(FakeCredentials(username: '', password: '')),
        createClient: fakeClientFactory(server, cookies),
      );
      addTearDown(session.close);
      final cache = IntradeskIndexCache.of(session);
      final (connection, _) = await connect(
        tools: [
          searchIntradeskTool(session, cache),
          listIntradeskFolderTool(session, cache),
        ],
      );

      for (final (tool, arguments) in [
        ('search_intradesk', {'query': 'welkom'}),
        ('list_intradesk_folder', <String, Object?>{}),
      ]) {
        final (result, text) = await callTool(connection, tool, arguments);
        expect(result.isError, isTrue);
        expect(
          text,
          startsWith('Not all Smartschool settings are filled in. Missing: '),
        );
      }
      expect(server.requests, isEmpty);
    });
  });

  group('buildIntradeskIndex', () {
    Future<IntradeskIndex> walk({int maxFolders = maxIntradeskFolders}) =>
        withIntradesk(
          session,
          (intradesk) => buildIntradeskIndex(intradesk, maxFolders: maxFolders),
        );

    test(
      'walks the fixture tree breadth-first into items with paths',
      () async {
        final index = await walk();

        expect(
          [for (final item in index.items) (item.kind.name, item.path)],
          [
            ('folder', 'Documenten'),
            ('folder', 'Examens'),
            ('file', 'welkom.docx'),
            ('folder', 'Documenten / Archief'),
            ('file', 'Documenten / info.pdf'),
          ],
        );
        final info = index.find(_info)!;
        expect(info.parentId, _documenten);
        expect(info.size, 51050);
        expect(info.extension, 'pdf');
        expect(info.mimeType, 'application/pdf');
        expect(info.changed, DateTime.utc(2023, 9, 15, 7));
        expect(index.unlisted, 0);
        expect(index.skipped, 0);
      },
    );

    test('lists at most 4 folders at a time', () async {
      for (var i = 1; i <= 12; i++) {
        final folder = server.intradesk.addFolder('Map $i');
        server.intradesk.addFolder('Sub $i', parent: folder);
      }
      await list(); // logs in first, one request at a time
      server
        ..latency = const Duration(milliseconds: 20)
        ..maxInFlight = 0;

      final index = await walk();

      expect(index.count(IntradeskItemKind.folder), 3 + 24);
      expect(server.intradesk.listed, hasLength(1 + 1 + 27));
      expect(server.maxInFlight, 4);
    });

    test('stops after maxFolders listings and counts the folders it '
        'skipped', () async {
      final index = await walk(maxFolders: 2);

      expect(server.intradesk.listed, ['', _documenten]);
      expect(index.skipped, 2); // Examens, and Archief found in Documenten
      expect(index.count(IntradeskItemKind.folder), 3);
    });

    test('a failing root listing fails the walk', () async {
      server.intradesk.failing[''] = 500;

      await expectLater(walk(), throwsA(isA<Exception>()));
    });
  });
}
