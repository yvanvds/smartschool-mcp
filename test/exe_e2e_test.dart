/// End-to-end test: compiles the server with `dart compile exe` and talks to
/// the executable over stdio the way Claude Desktop does.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/exe.dart';

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
      'search_messages',
      'archive_messages',
      'reply_to_message',
      'search_intradesk',
      'list_intradesk_folder',
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

    await server.stop();
    expect(await server.stderr, contains('serving MCP on stdio'));
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
    expect(
      text,
      contains(
        'Missing: "Smartschool-adres" (SMARTSCHOOL_MAIN_URL), '
        '"Gebruikersnaam" (SMARTSCHOOL_USERNAME), '
        '"Wachtwoord" (SMARTSCHOOL_PASSWORD), "2FA-sleutel" (SMARTSCHOOL_MFA).',
      ),
    );
    expect(text, contains('Settings: extension settings'));
    expect(text, contains('Server version: $packageVersion'));
    expect(text, isNot(contains('#0')), reason: 'no stack trace');

    await server.stop();
    expect(
      await server.stderr,
      contains('Smartschool settings: extension settings'),
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

  test(
    'an unknown argument prints the usage to stderr and exits with 64',
    () async {
      final process = await Process.start(exePath, ['--bogus']);
      await process.stdin.close();

      expect(await process.exitCode.timeout(const Duration(seconds: 30)), 64);
      expect(await process.stdout.toList(), isEmpty);
      expect(
        await process.stderr.transform(systemEncoding.decoder).join(),
        allOf(contains('unknown argument: --bogus'), contains('--credentials')),
      );
    },
  );
}
