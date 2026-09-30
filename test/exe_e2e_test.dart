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
    expect(tools.keys, ['smartschool_status', 'list_messages', 'read_message']);
    final listSchema = tools['list_messages']!['inputSchema'] as Map;
    expect((listSchema['properties'] as Map)['box'], {
      'type': 'string',
      'description': isA<String>(),
      'default': 'inbox',
      'enum': ['inbox', 'sent', 'archive'],
    });
    final readSchema = tools['read_message']!['inputSchema'] as Map;
    expect(readSchema['required'], ['message_id']);
    for (final name in ['list_messages', 'read_message']) {
      expect(tools[name]!['annotations'], containsPair('readOnlyHint', true));
    }

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

  test('the message tools without settings: an error result that names the '
      'missing settings; invalid arguments: an error that says what to '
      'fix', () async {
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
    final (dateError, dateText) = await server.callTool(
      'list_messages',
      arguments: {'since': 'gisteren'},
    );

    for (final (isError, text) in [
      (listError, listText),
      (readError, readText),
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

    await server.stop();
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
