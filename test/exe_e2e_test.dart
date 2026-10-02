/// End-to-end test: compiles the server with `dart compile exe` and talks to
/// the executable over stdio the way Claude Desktop does.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/exe.dart';
import 'support/fake_github.dart';

void main() {
  late String exePath;

  setUpAll(() async => exePath = await compileServer());

  test('the compiled exe answers initialize and tools/list on stdout, '
      'logs only to stderr and exits when stdin closes', () async {
    final server = await ServerProcess.start(exePath);

    final initResult = await server.initialize();
    expect(initResult['protocolVersion'], '2025-06-18');
    expect(initResult['serverInfo'], {
      'name': 'smartschool',
      'version': packageVersion,
    });
    expect(
      (initResult['capabilities'] as Map<String, Object?>)['tools'],
      isA<Map<String, Object?>>(),
    );

    final tools = {
      for (final tool in (await server.request('tools/list'))['tools'] as List)
        (tool as Map)['name']: tool,
    };
    expect(tools.keys, [
      'smartschool_status',
      'list_messages',
      'read_message',
      'save_message_attachment',
      'search_messages',
      'archive_messages',
      'reply_to_message',
      'search_intradesk',
      'list_intradesk_folder',
      'read_intradesk_file',
      'save_intradesk_file',
    ]);
    final listSchema = tools['list_messages']!['inputSchema'] as Map;
    expect((listSchema['properties'] as Map)['box'], {
      'type': 'string',
      'description': isA<String>(),
      'default': 'inbox',
      'enum': ['inbox', 'sent', 'archive'],
    });
    final readSchema = tools['read_message']!['inputSchema'] as Map;
    expect(readSchema['required'], ['message_id']);
    for (final name in [
      'list_messages',
      'read_message',
      'search_messages',
      'search_intradesk',
      'list_intradesk_folder',
      'read_intradesk_file',
    ]) {
      expect(tools[name]!['annotations'], containsPair('readOnlyHint', true));
    }
    final searchSchema = tools['search_messages']!['inputSchema'] as Map;
    expect(searchSchema['required'], ['query']);
    expect((searchSchema['properties'] as Map)['boxes'], {
      'type': 'array',
      'description': isA<String>(),
      'default': ['inbox', 'archive'],
      'minItems': 1,
      'items': {
        'enum': ['inbox', 'sent', 'archive'],
        'type': 'string',
      },
    });
    final archive = tools['archive_messages'] as Map;
    expect(archive['annotations'], {
      'title': isA<String>(),
      'readOnlyHint': false,
      'destructiveHint': false,
      'idempotentHint': true,
      'openWorldHint': true,
    });
    final archiveSchema = archive['inputSchema'] as Map;
    expect(archiveSchema['required'], ['message_ids']);
    expect((archiveSchema['properties'] as Map)['message_ids'], {
      'type': 'array',
      'description': isA<String>(),
      'items': {'type': 'integer', 'minimum': 1},
      'minItems': 1,
      'maxItems': 100,
    });
    final reply = tools['reply_to_message'] as Map;
    expect(reply['annotations'], {
      'title': isA<String>(),
      'readOnlyHint': false,
      'destructiveHint': true,
      'idempotentHint': false,
      'openWorldHint': true,
    });
    final replySchema = reply['inputSchema'] as Map;
    expect(replySchema['required'], ['message_id', 'body']);
    expect((replySchema['properties'] as Map).keys, [
      'message_id',
      'body',
      'reply_all',
      'box',
    ]);
    final intradeskSearchSchema =
        tools['search_intradesk']!['inputSchema'] as Map;
    expect(intradeskSearchSchema['required'], ['query']);
    expect((intradeskSearchSchema['properties'] as Map).keys, [
      'query',
      'folder_id',
      'limit',
      'refresh',
    ]);
    final intradeskListSchema =
        tools['list_intradesk_folder']!['inputSchema'] as Map;
    expect(intradeskListSchema, isNot(contains('required')));
    expect((intradeskListSchema['properties'] as Map).keys, ['folder_id']);
    final readFileSchema = tools['read_intradesk_file']!['inputSchema'] as Map;
    expect(readFileSchema['required'], ['file_id']);
    expect((readFileSchema['properties'] as Map).keys, ['file_id']);
    for (final name in ['save_intradesk_file', 'save_message_attachment']) {
      expect(tools[name]!['annotations'], {
        'title': isA<String>(),
        'readOnlyHint': false,
        'destructiveHint': false,
        'idempotentHint': false,
        'openWorldHint': true,
      });
      expect(tools[name]!['description'], contains('200 MB'));
    }
    final saveFileSchema = tools['save_intradesk_file']!['inputSchema'] as Map;
    expect(saveFileSchema['required'], ['file_id']);
    expect((saveFileSchema['properties'] as Map).keys, ['file_id']);
    final saveAttachmentSchema =
        tools['save_message_attachment']!['inputSchema'] as Map;
    expect(saveAttachmentSchema['required'], ['message_id', 'attachment']);
    expect((saveAttachmentSchema['properties'] as Map)['attachment'], {
      'description': isA<String>(),
      'anyOf': [
        {'type': 'integer', 'minimum': 1},
        {'type': 'string', 'minLength': 1},
      ],
    });

    await server.stop();
    expect(await server.stderr, contains('serving MCP on stdio'));
  });

  test('no tool assumes a teacher: students sign in too, so titles and '
      'descriptions speak of the user (#62)', () async {
    final server = await ServerProcess.start(
      exePath,
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    final tools = (await server.request('tools/list'))['tools'] as List;
    expect(tools, hasLength(11));
    for (final tool in tools.cast<Map<String, Object?>>()) {
      // The whole definition: its title, description and the descriptions
      // of its arguments.
      expect(
        jsonEncode(tool).toLowerCase(),
        isNot(contains('teacher')),
        reason: '${tool['name']}',
      );
    }
    final readFile = tools.cast<Map<String, Object?>>().singleWhere(
      (tool) => tool['name'] == 'read_intradesk_file',
    );
    expect(readFile['description'], contains('what the user is looking for'));

    await server.stop();
  });

  test('smartschool_status without --credentials and without SMARTSCHOOL_* '
      'variables reports the missing settings', () async {
    final server = await ServerProcess.start(
      exePath,
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    final (isError, text) = await server.callTool('smartschool_status');

    expect(isError, isNot(true));
    expect(text, startsWith('Smartschool connection: NOT working\n'));
    // The 2FA key is optional: only an account with 2FA needs it (#41).
    expect(
      text,
      contains(
        'Missing: "Smartschool-adres" (SMARTSCHOOL_MAIN_URL), '
        '"Gebruikersnaam" (SMARTSCHOOL_USERNAME), '
        '"Wachtwoord" (SMARTSCHOOL_PASSWORD). Fill them in',
      ),
    );
    expect(
      text,
      contains(
        '\nSettings: extension settings (Smartschool-adres: missing, '
        'Gebruikersnaam: missing, Wachtwoord: missing, 2FA-sleutel: empty '
        '(only needed for an account with 2FA))\n',
      ),
    );
    expect(
      text,
      contains(
        '\nDownload folder: ${server.downloads} (set in "Downloadmap" '
        '(SMARTSCHOOL_DOWNLOAD_DIR); writable)\n',
      ),
    );
    expect(text, contains('Server version: $packageVersion'));
    expect(text, isNot(contains('#0')), reason: 'no stack trace');

    await server.stop();
    expect(
      await server.stderr,
      contains('Smartschool settings: extension settings'),
    );
  });

  test('smartschool_status without a download folder set: the default, '
      'Downloads\\Smartschool in the user\'s folder, created only when a '
      'file is saved', () async {
    final home = await Directory.systemTemp.createTemp('smartschool_mcp_home_');
    addTearDown(() => home.delete(recursive: true));
    final server = await ServerProcess.start(
      exePath,
      environment: {
        ...environmentWithoutSmartschool(),
        'USERPROFILE': home.path,
        'HOME': home.path,
        // Empty, as Claude Desktop passes a field left empty.
        'SMARTSCHOOL_DOWNLOAD_DIR': '',
      },
    );
    await server.initialize();

    final (_, text) = await server.callTool('smartschool_status');

    final folder = [
      home.path,
      'Downloads',
      'Smartschool',
    ].join(Platform.pathSeparator);
    expect(
      text,
      contains(
        '\nDownload folder: $folder (the default; does not exist yet: it is '
        'created when the first file is saved)\n',
      ),
    );
    await server.stop();
    expect(home.listSync(), isEmpty);
    expect(
      await server.stderr,
      contains('downloads: saving in $folder (the default)'),
    );
  });

  test('at startup, the files the server saved more than 7 days ago are '
      'deleted from the download folder, and no other file', () async {
    final folder = await Directory.systemTemp.createTemp(
      'smartschool_mcp_cleanup_',
    );
    addTearDown(() => folder.delete(recursive: true));
    File file(String name) =>
        File('${folder.path}${Platform.pathSeparator}$name');
    final old = file('rapport.pdf')..writeAsStringSync('oud');
    final recent = file('brief.docx')..writeAsStringSync('recent');
    final teachers = file('eigen bestand.pdf')..writeAsStringSync('van mij');
    teachers.setLastModifiedSync(DateTime(2020));
    final now = DateTime.now().toUtc();
    Map<String, Object?> entry(File file, Duration age) => {
      'name': file.uri.pathSegments.last,
      'saved_at': now.subtract(age).toIso8601String(),
      'size': file.lengthSync(),
      'modified': file.lastModifiedSync().microsecondsSinceEpoch,
    };
    file(DownloadFolder.manifestName).writeAsStringSync(
      jsonEncode({
        'format': DownloadFolder.manifestFormat,
        'cleaned_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'files': [
          entry(old, const Duration(days: 8)),
          entry(recent, const Duration(days: 1)),
        ],
      }),
    );

    final server = await ServerProcess.start(
      exePath,
      environment: {
        ...environmentWithoutSmartschool(),
        'SMARTSCHOOL_DOWNLOAD_DIR': folder.path,
      },
    );
    await server.initialize();
    await server.stop();

    expect(old.existsSync(), isFalse);
    expect(recent.readAsStringSync(), 'recent');
    expect(teachers.readAsStringSync(), 'van mij');
    final manifest =
        jsonDecode(file(DownloadFolder.manifestName).readAsStringSync())
            as Map<String, Object?>;
    expect(manifest['files'], [containsPair('name', 'brief.docx')]);
    expect(
      await server.stderr,
      contains('downloads: cleanup deleted 1 file, 1 still listed'),
    );
  });

  test('the message and Intradesk tools without settings: an error result '
      'that names the missing settings; invalid arguments: an error that '
      'says what to fix', () async {
    final server = await ServerProcess.start(
      exePath,
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    final (listError, listText) = await server.callTool(
      'list_messages',
      arguments: {'box': 'archive', 'unread_only': true},
    );
    final (readError, readText) = await server.callTool(
      'read_message',
      arguments: {'message_id': 123},
    );
    final (searchError, searchText) = await server.callTool(
      'search_messages',
      arguments: {
        'query': 'facultatieve verlofdag',
        'boxes': ['inbox', 'sent'],
      },
    );
    final (emptyQueryError, emptyQueryText) = await server.callTool(
      'search_messages',
      arguments: {'query': '  '},
    );
    final (archiveError, archiveText) = await server.callTool(
      'archive_messages',
      arguments: {
        'message_ids': [123, 456],
      },
    );
    final (replyError, replyText) = await server.callTool(
      'reply_to_message',
      arguments: {'message_id': 123, 'body': 'Donderdag kan ik.'},
    );
    final (emptyError, emptyText) = await server.callTool(
      'reply_to_message',
      arguments: {'message_id': 123, 'body': ' '},
    );
    final (intradeskError, intradeskText) = await server.callTool(
      'search_intradesk',
      arguments: {'query': 'formulier uitstap', 'refresh': true},
    );
    final (folderError, folderText) = await server.callTool(
      'list_intradesk_folder',
      arguments: {'folder_id': 'aaaa1111-1111-4111-b111-111111111111'},
    );
    final (badIdError, badIdText) = await server.callTool(
      'list_intradesk_folder',
      arguments: {'folder_id': '../messages'},
    );
    final (fileError, fileText) = await server.callTool(
      'read_intradesk_file',
      arguments: {'file_id': 'cccc1111-1111-4111-b111-111111111111'},
    );
    final (badFileIdError, badFileIdText) = await server.callTool(
      'read_intradesk_file',
      arguments: {'file_id': 'welkom.docx'},
    );
    final (saveFileError, saveFileText) = await server.callTool(
      'save_intradesk_file',
      arguments: {'file_id': 'cccc1111-1111-4111-b111-111111111111'},
    );
    final (badSaveIdError, badSaveIdText) = await server.callTool(
      'save_intradesk_file',
      arguments: {'file_id': 'C:\\Windows\\win.ini'},
    );
    final (saveAttachmentError, saveAttachmentText) = await server.callTool(
      'save_message_attachment',
      arguments: {'message_id': 123, 'attachment': 'planning.pdf'},
    );
    final (noAttachmentError, noAttachmentText) = await server.callTool(
      'save_message_attachment',
      arguments: {'message_id': 123, 'attachment': 0},
    );
    final (dateError, dateText) = await server.callTool(
      'list_messages',
      arguments: {'since': 'gisteren'},
    );
    final (tooManyError, tooManyText) = await server.callTool(
      'archive_messages',
      arguments: {
        'message_ids': [for (var id = 1; id <= 101; id++) id],
      },
    );

    for (final (isError, text) in [
      (listError, listText),
      (readError, readText),
      (searchError, searchText),
      (archiveError, archiveText),
      (replyError, replyText),
      (intradeskError, intradeskText),
      (folderError, folderText),
      (fileError, fileText),
      (saveFileError, saveFileText),
      (saveAttachmentError, saveAttachmentText),
    ]) {
      expect(isError, isTrue);
      expect(
        text,
        startsWith('Not all Smartschool settings are filled in. Missing: '),
      );
      expect(text, isNot(contains('#0')), reason: 'no stack trace');
    }
    expect(dateError, isTrue);
    expect(dateText, contains('"gisteren" is not'));
    expect(tooManyError, isTrue);
    expect(tooManyText, contains('List has 101 items'));
    expect(emptyError, isTrue);
    expect(emptyText, contains('body is empty'));
    expect(emptyQueryError, isTrue);
    expect(emptyQueryText, 'query is empty: pass the words to look for.');
    expect(badIdError, isTrue);
    expect(badIdText, startsWith('folder_id must be an Intradesk id like '));
    expect(badFileIdError, isTrue);
    expect(badFileIdText, startsWith('file_id must be an Intradesk id like '));
    expect(badSaveIdError, isTrue);
    expect(badSaveIdText, startsWith('file_id must be an Intradesk id like '));
    expect(noAttachmentError, isTrue);
    expect(noAttachmentText, isNot(startsWith('Not all Smartschool')));
    expect(Directory(server.downloads!).listSync(), isEmpty);

    await server.stop();
  });

  test('the tools accept a whole number written with a decimal part '
      '(123.0) and get as far as the missing settings', () async {
    final server = await ServerProcess.start(
      exePath,
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    for (final (tool, arguments) in <(String, Map<String, Object?>)>[
      ('read_message', {'message_id': 123.0}),
      ('list_messages', {'limit': 10.0}),
      ('search_messages', {'query': 'verlof', 'limit': 10.0}),
      (
        'archive_messages',
        {
          'message_ids': [123.0, 456],
        },
      ),
      ('reply_to_message', {'message_id': 123.0, 'body': 'Hallo'}),
      ('search_intradesk', {'query': 'uitstap', 'limit': 10.0}),
      ('save_message_attachment', {'message_id': 123.0, 'attachment': 2.0}),
    ]) {
      final (isError, text) = await server.callTool(tool, arguments: arguments);

      expect(isError, isTrue, reason: tool);
      expect(
        text,
        startsWith('Not all Smartschool settings are filled in. Missing: '),
        reason: tool,
      );
    }

    await server.stop();
    expect(await server.stderr, isNot(contains('is not a subtype')));
  });

  test('smartschool_status with --credentials naming a missing file says '
      'so, without looking for another credentials.yml', () async {
    final missing = File('does-not-exist.yml').absolute.path;
    final server = await ServerProcess.start(
      exePath,
      args: ['--credentials', 'does-not-exist.yml'],
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    final (_, text) = await server.callTool('smartschool_status');

    expect(text, startsWith('Smartschool connection: NOT working\n'));
    expect(text, contains('The credentials file $missing'));
    expect(text, contains('does not exist'));
    expect(text, contains('Settings: credentials file $missing'));

    await server.stop();
    expect(
      await server.stderr,
      contains('Smartschool settings: credentials file $missing'),
    );
  });

  group('the update check, against a fake GitHub', () {
    late FakeGitHub github;
    late Directory home;

    setUp(() async {
      github = await FakeGitHub.start();
      home = await Directory.systemTemp.createTemp('smartschool_mcp_home_');
      addTearDown(() => home.delete(recursive: true));
    });

    /// A colleague's install without settings, with [github] instead of
    /// GitHub and [home] as the home folder (for the cache folder).
    Future<ServerProcess> start({bool checkForUpdates = true}) =>
        ServerProcess.start(
          exePath,
          environment: {
            ...environmentWithoutSmartschool(),
            'HOME': home.path,
            UpdateChecker.endpointVariable: github.latestRelease.toString(),
          },
          checkForUpdates: checkForUpdates,
        );

    File stateFile() => File(
      [
        home.path,
        '.cache',
        'smartschool',
        UpdateChecker.stateFileName,
      ].join(Platform.pathSeparator),
    );

    test('a newer release: asked at startup in the background, shown by '
        'smartschool_status (without settings), saved in the cache folder; '
        'a restart within 24 hours does not ask again', () async {
      github.publish('v99.0.0');
      final server = await start();
      await server.initialize();
      await github.received(1).timeout(const Duration(seconds: 30));

      final (isError, text) = await server.callTool('smartschool_status');

      expect(isError, isNot(true));
      expect(text, startsWith('Smartschool connection: NOT working\n'));
      expect(
        text,
        endsWith(
          '\nServer version: $packageVersion\n'
          'Updates: version 99.0.0 is available. To update, download '
          'smartschool-mcp.mcpb from ${releasePage('v99.0.0')} and '
          'double-click it.',
        ),
      );
      expect(github.requests, hasLength(2), reason: 'startup and status');
      expect(
        github.requests.first.path,
        '/repos/yvanvds/smartschool-mcp/releases/latest',
      );
      expect(
        github.requests.first.userAgent,
        startsWith('smartschool-mcp/$packageVersion '),
      );
      await server.stop();
      expect(
        await server.stderr,
        contains('update check: version 99.0.0 is available'),
      );
      expect(jsonDecode(stateFile().readAsStringSync()), {
        'format': UpdateChecker.stateFormat,
        'endpoint': github.latestRelease.toString(),
        'checked_at': isA<String>(),
        'latest': {'tag': 'v99.0.0', 'url': releasePage('v99.0.0')},
      });

      final restarted = await start();
      await restarted.initialize();
      // An error result: stays a single text, without the notice.
      final (listError, listText) = await restarted.callTool('list_messages');
      expect(listError, isTrue);
      expect(
        listText,
        startsWith('Not all Smartschool settings are filled in.'),
      );
      await restarted.stop();

      expect(github.requests, hasLength(2));
      expect(
        await restarted.stderr,
        contains('update check: skipped, last checked at '),
      );
    });

    test('no release published yet (GitHub answers 404): up to date', () async {
      github.noReleases();
      final server = await start();
      await server.initialize();

      final (_, text) = await server.callTool('smartschool_status');

      expect(
        text,
        endsWith('\nUpdates: up to date (no release published yet)'),
      );
      await server.stop();
      expect(
        await server.stderr,
        contains('update check: up to date (no release published yet)'),
      );
    });

    test('while GitHub does not answer, startup and tool calls do not wait '
        'for it, smartschool_status gives up after 5 seconds, and the '
        'server still exits at once', () async {
      github
        ..publish('v99.0.0')
        ..hold();
      final server = await start();
      final watch = Stopwatch()..start();

      await server.initialize();
      await server.request('tools/list');
      await github.received(1).timeout(const Duration(seconds: 30));
      final (listError, _) = await server.callTool('list_messages');

      expect(listError, isTrue);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 4)),
        reason: 'the check waits up to 5 seconds for GitHub',
      );

      final (_, text) = await server.callTool('smartschool_status');

      expect(
        text,
        endsWith(
          '\nUpdates: could not check (no answer from 127.0.0.1 within '
          '5 seconds)',
        ),
      );
      await server.stop();
    });

    test('SMARTSCHOOL_MCP_UPDATE_CHECK=off: GitHub is not asked', () async {
      github.publish('v99.0.0');
      final server = await start(checkForUpdates: false);
      await server.initialize();

      final (_, text) = await server.callTool('smartschool_status');

      expect(
        text,
        endsWith('\nUpdates: not checked (the update check is turned off)'),
      );
      await server.stop();
      expect(github.requests, isEmpty);
      expect(stateFile().existsSync(), isFalse);
      expect(
        await server.stderr,
        contains('update check: turned off (SMARTSCHOOL_MCP_UPDATE_CHECK=off)'),
      );
    });
  });

  test(
    'an unknown argument prints the usage to stderr and exits with 64',
    () async {
      final process = await Process.start(exePath, ['--bogus']);
      addTearDown(process.kill);
      // Read while it runs: on Windows, the usage (longer since the download
      // folder) fills the stderr pipe when nobody reads it, and the server
      // waits for that forever instead of exiting.
      final stdoutChunks = process.stdout.toList();
      final stderrText = process.stderr
          .transform(systemEncoding.decoder)
          .join();
      await process.stdin.close();

      expect(await process.exitCode.timeout(const Duration(seconds: 30)), 64);
      expect(await stdoutChunks, isEmpty);
      expect(
        await stderrText,
        allOf(
          contains('unknown argument: --bogus'),
          contains('--credentials'),
          contains('SMARTSCHOOL_DOWNLOAD_DIR'),
        ),
      );
    },
  );
}
