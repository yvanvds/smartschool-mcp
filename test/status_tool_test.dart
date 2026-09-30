import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

void main() {
  late FakeSmartschool server;

  setUp(() => server = FakeSmartschool());

  /// Calls `smartschool_status` over MCP on a server whose session reads
  /// [source] and talks to [server].
  Future<(CallToolResult, String)> status({CredentialSource? source}) async {
    final session = SmartschoolSession(
      source ?? fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(tools: [statusTool(session)]);
    return callTool(connection, 'smartschool_status');
  }

  void expectNoSecretsOrTraces(String text) {
    expect(text.contains(fakePassword), isFalse, reason: 'password shown');
    expect(text.contains(fakeTotpSecret), isFalse, reason: '2FA key shown');
    expect(text, isNot(contains('#0')), reason: 'stack trace shown');
    expect(text, isNot(contains('Exception')), reason: 'raw error shown');
    expect(text, isNot(contains('Error:')), reason: 'raw error shown');
  }

  test('is listed as a read-only tool', () async {
    final session = SmartschoolSession(fakeExtensionSettings());
    final (connection, _) = await connect(tools: [statusTool(session)]);

    final tools = (await connection.listTools(ListToolsRequest())).tools;

    expect(tools.map((t) => t.name), ['smartschool_status']);
    expect(tools.single.toolAnnotations?.readOnlyHint, isTrue);
    expect(tools.single.description, contains('Werkt mijn Smartschool'));
  });

  test('with valid settings: logs in and shows who is logged in', () async {
    final (result, text) = await status();

    expect(result.isError, isNot(true));
    expect(
      text,
      'Smartschool connection: working\n'
      'Logged in as: $fakeDisplayName\n'
      'Smartschool address: $fakeHost\n'
      'Settings: extension settings (all filled in)\n'
      'Server version: $packageVersion\n'
      'Updates: not checked (the update check is turned off)',
    );
    expect(server.logins, 1);
    expectNoSecretsOrTraces(text);
  });

  test('with a credentials file: shows the file, never its values', () async {
    final dir = await Directory.systemTemp.createTemp('smartschool_status_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}credentials.yml')
      ..writeAsStringSync(
        'username: jan.peeters\n'
        'password: $fakePassword\n'
        'main_url: $fakeHost\n'
        'mfa: $fakeTotpSecret\n',
      );

    final (_, text) = await status(source: CredentialsFile(file.path));

    expect(text, contains('Smartschool connection: working'));
    expect(
      text,
      contains(
        'Settings: credentials file ${file.absolute.path} '
        '(all filled in)',
      ),
    );
    expectNoSecretsOrTraces(text);
  });

  test(
    'with missing settings: names them and does not contact Smartschool',
    () async {
      final (result, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(password: '', mfa: '')),
      );

      expect(result.isError, isNot(true));
      expect(text, startsWith('Smartschool connection: NOT working\n'));
      expect(
        text,
        contains(
          'Problem: Not all Smartschool settings are filled in. Missing: '
          '"Wachtwoord" (SMARTSCHOOL_PASSWORD), "2FA-sleutel" (SMARTSCHOOL_MFA).',
        ),
      );
      expect(
        text,
        contains(
          'Settings: extension settings (Smartschool-adres: filled in, '
          'Gebruikersnaam: filled in, Wachtwoord: missing, '
          '2FA-sleutel: missing)',
        ),
      );
      expect(text, contains('Server version: $packageVersion'));
      expect(server.requests, isEmpty);
    },
  );

  test('with a missing credentials file: says so', () async {
    final missing = File('does-not-exist.yml').absolute.path;

    final (_, text) = await status(source: CredentialsFile(missing));

    expect(text, startsWith('Smartschool connection: NOT working\n'));
    expect(text, contains('The credentials file $missing'));
    expect(text, contains('does not exist'));
    expect(text, contains('Settings: credentials file $missing'));
  });

  group('each login failure has its own message', () {
    final cases = {
      'wrong password': (
        FakeSmartschool(passwordAccepted: false),
        'did not accept the username or password',
      ),
      '2FA code rejected': (
        FakeSmartschool(twoFactorAccepted: false),
        'rejected the two-factor authentication (2FA) code',
      ),
      'account verification': (
        FakeSmartschool(secondStep: SecondStep.accountVerification),
        'asks for account verification (a date of birth)',
      ),
      'unreachable': (
        FakeSmartschool()..unreachable = true,
        'Could not reach Smartschool at $fakeHost',
      ),
    };
    for (final MapEntry(key: name, value: (fake, expected)) in cases.entries) {
      test(name, () async {
        server = fake;

        final (result, text) = await status();

        expect(result.isError, isNot(true));
        expect(text, startsWith('Smartschool connection: NOT working\n'));
        expect(text, contains('Problem: '));
        expect(text, contains(expected));
        expect(text, contains('Smartschool address: $fakeHost'));
        expectNoSecretsOrTraces(text);
      });
    }
  });

  test('checks the connection live on every call: logs in again when the '
      'session expired in the meantime', () async {
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(tools: [statusTool(session)]);

    await callTool(connection, 'smartschool_status');
    server.expireSession();
    final (_, text) = await callTool(connection, 'smartschool_status');

    expect(text, startsWith('Smartschool connection: working\n'));
    expect(server.logins, 2);
  });
}
