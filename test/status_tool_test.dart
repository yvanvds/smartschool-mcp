import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/presence/presence_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

void main() {
  late FakeSmartschool server;

  setUp(() => server = FakeSmartschool());

  /// Calls `smartschool_status` over MCP on a server whose session reads
  /// [source] and talks to [server], with [downloads] when given.
  ///
  /// The client calls itself [clientName]; the server records the app in
  /// [client], which [source] should share.
  ///
  /// With [skore], the Skore tools are an opt-in group whose switch,
  /// "Skore-beheer", is set to it; with [presence], likewise the presence
  /// tools and "Aanwezigheden".
  Future<(CallToolResult, String)> status({
    CredentialSource? source,
    DownloadFolder? Function()? downloads,
    ClientContext? client,
    String clientName = 'test',
    SwitchState? skore,
    SwitchState? presence,
  }) async {
    final session = SmartschoolSession(
      source ?? fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(
      tools: [
        statusTool(
          session,
          downloads: downloads,
          client: client,
          optIns: [
            if (skore != null) skoreOptIn(session, skore),
            if (presence != null) presenceOptIn(session, presence),
          ],
        ),
      ],
      client: client,
      clientName: clientName,
    );
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

  group('with a download folder', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('smartschool_status_');
      addTearDown(() => root.delete(recursive: true));
    });

    DownloadFolder folderAt(String path) => DownloadFolder(
      path,
      origin: DownloadFolderOrigin(
        'set in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)',
        fix:
            'choose another folder in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR) '
            'in the Smartschool extension settings',
      ),
    );

    test('shows the folder, where it is set and that it is writable, after '
        'the settings', () async {
      final (result, text) = await status(downloads: () => folderAt(root.path));

      expect(result.isError, isNot(true));
      expect(
        text,
        'Smartschool connection: working\n'
        'Logged in as: $fakeDisplayName\n'
        'Smartschool address: $fakeHost\n'
        'Settings: extension settings (all filled in)\n'
        'Download folder: ${root.path} (set in "Downloadmap" '
        '(SMARTSCHOOL_DOWNLOAD_DIR); writable)\n'
        'Server version: $packageVersion\n'
        'Updates: not checked (the update check is turned off)',
      );
      expect(root.listSync(), isEmpty, reason: 'the check leaves nothing');
    });

    test('one that does not exist yet: created on the first save, not '
        'now', () async {
      final path = '${root.path}${Platform.pathSeparator}Smartschool';

      final (_, text) = await status(downloads: () => folderAt(path));

      expect(
        text,
        contains(
          '\nDownload folder: $path (set in "Downloadmap" '
          '(SMARTSCHOOL_DOWNLOAD_DIR); does not exist yet: it is created when '
          'the first file is saved)\n',
        ),
      );
      expect(Directory(path).existsSync(), isFalse);
    });

    test('one that cannot be used: NOT writable, why, and how to choose '
        'another', () async {
      final file = File('${root.path}${Platform.pathSeparator}bestand')
        ..writeAsStringSync('x');

      final (_, text) = await status(downloads: () => folderAt(file.path));

      expect(
        text,
        contains(
          '\nDownload folder: ${file.path} (set in "Downloadmap" '
          '(SMARTSCHOOL_DOWNLOAD_DIR); NOT writable: it is a file, not a '
          'folder). To save files, choose another folder in "Downloadmap" '
          '(SMARTSCHOOL_DOWNLOAD_DIR) in the Smartschool extension '
          'settings.\n',
        ),
      );
    });

    test('also when the connection does not work', () async {
      final (_, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(password: '')),
        downloads: () => folderAt(root.path),
      );

      expect(text, startsWith('Smartschool connection: NOT working\n'));
      expect(text, contains('\nDownload folder: ${root.path} ('));
    });

    test('none: says so and how to set one', () async {
      final (_, text) = await status(downloads: () => null);

      expect(
        text,
        contains(
          '\nDownload folder: none (there is no home folder for the '
          'default). To save files, set "Downloadmap" '
          '(SMARTSCHOOL_DOWNLOAD_DIR) in the Smartschool extension settings '
          'in Claude Desktop (Settings → Extensions), then restart Claude '
          'Desktop.\n',
        ),
      );
    });
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

  test('with missing settings: names them, not the empty 2FA key, and does not '
      'contact Smartschool', () async {
    final (result, text) = await status(
      source: fakeExtensionSettings(FakeCredentials(password: '', mfa: '')),
    );

    expect(result.isError, isNot(true));
    expect(text, startsWith('Smartschool connection: NOT working\n'));
    expect(
      text,
      contains(
        'Problem: Not all Smartschool settings are filled in. Missing: '
        '"Wachtwoord" (SMARTSCHOOL_PASSWORD). Fill it in in',
      ),
    );
    expect(
      text,
      contains(
        'Settings: extension settings (Smartschool-adres: filled in, '
        'Gebruikersnaam: filled in, Wachtwoord: missing, '
        '2FA-sleutel: empty (only needed for an account with 2FA))',
      ),
    );
    expect(text, contains('Server version: $packageVersion'));
    expect(server.requests, isEmpty);
  });

  group('without a 2FA key (#41)', () {
    test('for an account without 2FA, such as a student\'s: working, and '
        'the key is shown as empty, not missing', () async {
      server = FakeSmartschool(secondStep: SecondStep.none);

      final (result, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(mfa: '')),
      );

      expect(result.isError, isNot(true));
      expect(
        text,
        'Smartschool connection: working\n'
        'Logged in as: $fakeDisplayName\n'
        'Smartschool address: $fakeHost\n'
        'Settings: extension settings (Smartschool-adres: filled in, '
        'Gebruikersnaam: filled in, Wachtwoord: filled in, 2FA-sleutel: '
        'empty (only needed for an account with 2FA))\n'
        'Server version: $packageVersion\n'
        'Updates: not checked (the update check is turned off)',
      );
      expect(server.logins, 1);
      expect(server.requests, isNot(contains(startsWith('POST /2fa'))));
      expectNoSecretsOrTraces(text);
    });

    test('with a credentials file without the key mfa: working, and the '
        'key is named by its key in the file', () async {
      server = FakeSmartschool(secondStep: SecondStep.none);
      final dir = await Directory.systemTemp.createTemp('smartschool_status_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}credentials.yml')
        ..writeAsStringSync(
          'username: jan.peeters\n'
          'password: $fakePassword\n'
          'main_url: $fakeHost\n',
        );

      final (_, text) = await status(source: CredentialsFile(file.path));

      expect(text, startsWith('Smartschool connection: working\n'));
      expect(
        text,
        contains(
          'Settings: credentials file ${file.absolute.path} (main_url: '
          'filled in, username: filled in, password: filled in, mfa: empty '
          '(only needed for an account with 2FA))\n',
        ),
      );
      expect(server.logins, 1);
    });

    test('in ChatGPT, without the variable SMARTSCHOOL_MFA: working, and the '
        'key is named by its variable', () async {
      server = FakeSmartschool(secondStep: SecondStep.none);
      final client = ClientContext();

      final (_, text) = await status(
        source: ExtensionSettings(
          client: client,
          read: () => FakeCredentials(mfa: null),
          environment: () => {'SYSTEMROOT': r'C:\Windows'},
        ),
        client: client,
        clientName: ClientApp.codexClientName,
      );

      expect(text, startsWith('Smartschool connection: working\n'));
      expect(
        text,
        contains(
          '\nSettings: environment variables of the MCP server '
          '(SMARTSCHOOL_MAIN_URL: filled in, SMARTSCHOOL_USERNAME: filled '
          'in, SMARTSCHOOL_PASSWORD: filled in, SMARTSCHOOL_MFA: empty (only '
          'needed for an account with 2FA))\n',
        ),
      );
    });

    test('when Smartschool asks for a 2FA code: NOT working, says the '
        'account uses 2FA and names "2FA-sleutel"; a second call does not '
        'contact Smartschool', () async {
      final session = SmartschoolSession(
        fakeExtensionSettings(FakeCredentials(mfa: '')),
        createClient: fakeClientFactory(server, await tempCache()),
      );
      addTearDown(session.close);
      final (connection, _) = await connect(tools: [statusTool(session)]);

      final (result, text) = await callTool(connection, 'smartschool_status');
      final requests = server.requests.length;
      final (_, again) = await callTool(connection, 'smartschool_status');

      expect(result.isError, isNot(true));
      expect(
        text,
        startsWith(
          'Smartschool connection: NOT working\n'
          'Problem: This Smartschool account uses two-factor authentication '
          '(2FA): after the password, Smartschool asks for a code from an '
          'authenticator app, but "2FA-sleutel" (SMARTSCHOOL_MFA) is empty. '
          'Fill it in in the Smartschool extension settings in Claude Desktop '
          '(Settings → Extensions) with the key Smartschool shows when you '
          'add an authenticator app, not the 6-digit code the app shows. Then '
          'restart Claude Desktop.\n'
          'Smartschool address: $fakeHost\n'
          'Settings: extension settings (Smartschool-adres: filled in, '
          'Gebruikersnaam: filled in, Wachtwoord: filled in, 2FA-sleutel: '
          'empty (only needed for an account with 2FA))\n',
        ),
      );
      expectNoSecretsOrTraces(text);
      expect(again, text);
      expect(server.requests, hasLength(requests));
      expect(server.logins, 0);
    });
  });

  test('with the 2FA key copied in groups, with spaces or hyphens: '
      'working', () async {
    for (final key in ['JBSW Y3DP EHPK 3PXP', 'JBSW-Y3DP-EHPK-3PXP']) {
      server = FakeSmartschool();
      final (result, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(mfa: key)),
      );

      expect(result.isError, isNot(true), reason: key);
      expect(
        text,
        startsWith('Smartschool connection: working\n'),
        reason: key,
      );
      expect(server.logins, 1, reason: key);
    }
  });

  test('with a 6-digit code as 2FA key: names "2FA-sleutel", says it is not '
      'the code, and does not post the password; a second call does not '
      'contact Smartschool', () async {
    final session = SmartschoolSession(
      fakeExtensionSettings(FakeCredentials(mfa: '123456')),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(tools: [statusTool(session)]);

    final (result, text) = await callTool(connection, 'smartschool_status');
    final requests = server.requests.length;
    final (_, again) = await callTool(connection, 'smartschool_status');

    expect(result.isError, isNot(true));
    expect(
      text,
      startsWith(
        'Smartschool connection: NOT working\n'
        'Problem: The two-factor authentication (2FA) key is not valid, so '
        'the login to Smartschool was stopped. Check "2FA-sleutel" '
        '(SMARTSCHOOL_MFA) in the Smartschool extension settings in Claude '
        'Desktop (Settings → Extensions): it must be the key Smartschool shows '
        'when you add an authenticator app, made of letters and the digits 2 '
        'to 7 (spaces and hyphens do not matter), not the 6-digit code the '
        'app shows. Then restart Claude Desktop.\n'
        'Smartschool address: $fakeHost\n',
      ),
    );
    expect(text, isNot(contains('123456')));
    expectNoSecretsOrTraces(text);
    expect(again, text);
    expect(server.requests, isNot(contains('POST /login')));
    expect(server.requests, hasLength(requests));
  });

  group('with the opt-in switch "Skore-beheer" (#42)', () {
    const rights =
        'the rights for score management in Skore (Rapporten > Modellen and '
        'Puntenboeken), as a Skore administrator has';
    const fix =
        "ask the school's Smartschool administrator for them, or turn off "
        '"Skore-beheer" (SMARTSCHOOL_SKORE) in the Smartschool extension '
        'settings in Claude Desktop (Settings → Extensions), then restart '
        'Claude Desktop';

    setUp(() => server.skore.loadSchool());

    test('off: says so after the settings, how to turn it on and for whom, '
        'and does not ask Skore', () async {
      final (result, text) = await status(skore: SwitchState.off);

      expect(result.isError, isNot(true));
      expect(
        text,
        'Smartschool connection: working\n'
        'Logged in as: $fakeDisplayName\n'
        'Smartschool address: $fakeHost\n'
        'Settings: extension settings (all filled in)\n'
        'Skore-beheer: off: its tools are not offered. For an account with '
        '$rights: turn on "Skore-beheer" (SMARTSCHOOL_SKORE) in the '
        'Smartschool extension settings in Claude Desktop (Settings → '
        'Extensions), then restart Claude Desktop.\n'
        'Server version: $packageVersion\n'
        'Updates: not checked (the update check is turned off)',
      );
      expect(server.skore.requests, isEmpty);
    });

    test('set to something that is neither true nor false: off, and says '
        'so', () async {
      final (_, text) = await status(skore: SwitchState.unclear);

      expect(
        text,
        contains(
          '\nSkore-beheer: off, as "Skore-beheer" (SMARTSCHOOL_SKORE) is set '
          'to neither true nor false: its tools are not offered. For an '
          'account with $rights: set it to true in the Smartschool extension '
          'settings in Claude Desktop (Settings → Extensions), then restart '
          'Claude Desktop.\n',
        ),
      );
      expect(server.skore.requests, isEmpty);
    });

    test('on, with the rights: access, checked with one read of the '
        'teachers', () async {
      final (result, text) = await status(skore: SwitchState.on);

      expect(result.isError, isNot(true));
      expect(
        text,
        contains(
          '\nSettings: extension settings (all filled in)\n'
          'Skore-beheer: on; access: yes (Skore lists 6 teachers that can be '
          'assigned)\n'
          'Server version: ',
        ),
      );
      expect(server.skore.calls, ['POST $fakeSkoreOwnersRpcPath getTeachers']);
    });

    test('on, refused by Skore (HTTP 403): no access, with the rights it '
        'needs and what to do', () async {
      server.skore.refusal = SkoreRefusal.forbidden;

      final (result, text) = await status(skore: SwitchState.on);

      expect(result.isError, isNot(true));
      expect(text, startsWith('Smartschool connection: working\n'));
      expect(
        text,
        contains(
          '\nSkore-beheer: on; access: NO. This account has no rights for '
          'score management in Skore: Skore refused it its report management '
          '(Rapporten > Modellen). The Skore tools need $rights: $fix.\n',
        ),
      );
      expect(text, isNot(contains(fakeSkoreNoAccessName)));
      expectNoSecretsOrTraces(text);
    });

    test('on, answered with a page instead of data: no access, as the '
        'account usually lacks the rights (dartschool#91), without quoting '
        'the page', () async {
      server.skore.refusal = SkoreRefusal.page;

      final (_, text) = await status(skore: SwitchState.on);

      expect(
        text,
        contains(
          '\nSkore-beheer: on; access: NO. Skore gave an answer the server '
          'could not use; usually the account lacks $rights. If so, $fix. '
          'Otherwise try again in a moment; the technical details are in the '
          'server log.\n',
        ),
      );
      expect(text, isNot(contains(fakeSkoreNoAccessName)));
      expectNoSecretsOrTraces(text);
    });

    test('on, but Skore lists no teachers: no access, as an account without '
        'the rights may get an empty answer', () async {
      server.skore.teachers.clear();

      final (_, text) = await status(skore: SwitchState.on);

      expect(
        text,
        contains(
          '\nSkore-beheer: on; access: NO. Skore lists no teachers that can '
          'be assigned, as it may for an account without $rights. If so, '
          '$fix.\n',
        ),
      );
    });

    test('on, while the connection does not work: access not checked, and '
        'Skore not asked', () async {
      final (_, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(password: '')),
        skore: SwitchState.on,
      );

      expect(text, startsWith('Smartschool connection: NOT working\n'));
      expect(
        text,
        contains(
          '\nSkore-beheer: on; access not checked, as the connection does '
          'not work.\n',
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('in ChatGPT: names the variable first, and where to change it '
        'there', () async {
      final client = ClientContext();
      final (_, text) = await status(
        source: fakeExtensionSettings(null, client),
        client: client,
        clientName: ClientApp.codexClientName,
        skore: SwitchState.off,
      );

      expect(
        text,
        contains(
          '\nSkore-beheer: off: its tools are not offered. For an account '
          'with $rights: turn on SMARTSCHOOL_SKORE ("Skore-beheer") in the '
          "ChatGPT app, under Instellingen (Settings) → Plug-ins → MCP's → "
          'smartschool → Omgevingsvariabelen (Environment variables); in the '
          'Codex CLI or IDE extension, under [mcp_servers.smartschool.env] '
          r'in %USERPROFILE%\.codex\config.toml, then restart ChatGPT (or '
          'Codex).\n',
        ),
      );
    });
  });

  group('with the opt-in switch "Aanwezigheden" (#47)', () {
    const rights =
        "the right to record half-day presences for classes in Smartschool's "
        'Presence module, as an absence administrator has';
    const fix =
        "ask the school's Smartschool administrator for them, or turn off "
        '"Aanwezigheden" (SMARTSCHOOL_PRESENCE) in the Smartschool extension '
        'settings in Claude Desktop (Settings → Extensions), then restart '
        'Claude Desktop';

    setUp(() => server.presence.loadSchool('2026-06-01'));

    test('off: says so after the settings, and after Skore-beheer, how to '
        'turn it on and for whom, and does not ask the module', () async {
      final (result, text) = await status(
        skore: SwitchState.off,
        presence: SwitchState.off,
      );

      expect(result.isError, isNot(true));
      expect(
        text,
        contains(
          '\nSkore-beheer: off: its tools are not offered. For an account with '
          'the rights for score management in Skore (Rapporten > Modellen and '
          'Puntenboeken), as a Skore administrator has: turn on '
          '"Skore-beheer" (SMARTSCHOOL_SKORE) in the Smartschool extension '
          'settings in Claude Desktop (Settings → Extensions), then restart '
          'Claude Desktop.\n'
          'Aanwezigheden: off: its tools are not offered. For an account with '
          '$rights: turn on "Aanwezigheden" (SMARTSCHOOL_PRESENCE) in the '
          'Smartschool extension settings in Claude Desktop (Settings → '
          'Extensions), then restart Claude Desktop.\n'
          'Server version: ',
        ),
      );
      expect(server.presence.requests, isEmpty);
      expect(server.skore.requests, isEmpty);
    });

    test('on, with the right for some classes: access, checked with one read '
        'of the configuration', () async {
      final (result, text) = await status(presence: SwitchState.on);

      expect(result.isError, isNot(true));
      expect(
        text,
        contains(
          '\nSettings: extension settings (all filled in)\n'
          'Aanwezigheden: on; access: yes (the Presence module lets it record '
          'presences for 2 of the 3 classes it lists)\n'
          'Server version: ',
        ),
      );
      expect(server.presence.calls, ['POST $fakePresenceConfigPath']);
    });

    test('on, but the account may record presences for none of its classes: '
        'no access, with the right it needs and what to do', () async {
      server.presence.classes
        ..clear()
        ..add(fake1B);

      final (_, text) = await status(presence: SwitchState.on);

      expect(
        text,
        contains(
          '\nAanwezigheden: on; access: NO. The Presence module lists 1 class '
          'for this account, but it may record presences for none of them, as '
          'for an account without $rights. If so, $fix.\n',
        ),
      );
    });

    test('on, but the module lists no classes: no access', () async {
      server.presence.classes.clear();

      final (_, text) = await status(presence: SwitchState.on);

      expect(
        text,
        contains(
          '\nAanwezigheden: on; access: NO. The Presence module lists no '
          'classes for this account, as for an account without $rights. If '
          'so, $fix.\n',
        ),
      );
    });

    group('on, for a teacher without a lesson at the moment: the placeholder '
        '"Uit Planner" (class id -2) that the module gives as the active '
        'class is not counted (#84)', () {
      setUp(() => server.presence.noLesson = true);

      test('with classes: access', () async {
        final (_, text) = await status(presence: SwitchState.on);

        expect(
          text,
          contains(
            '\nAanwezigheden: on; access: yes (the Presence module lets it '
            'record presences for 2 of the 3 classes it lists)\n',
          ),
        );
      });

      test('without classes: no access, as the module lists none', () async {
        server.presence.classes.clear();

        final (_, text) = await status(presence: SwitchState.on);

        expect(
          text,
          contains(
            '\nAanwezigheden: on; access: NO. The Presence module lists no '
            'classes for this account, as for an account without $rights. If '
            'so, $fix.\n',
          ),
        );
      });
    });

    test('on, refused by the module with an error page: no access, without '
        'quoting the page', () async {
      server.presence.refused = true;

      final (result, text) = await status(presence: SwitchState.on);

      expect(result.isError, isNot(true));
      expect(
        text,
        contains(
          "\nAanwezigheden: on; access: NO. Smartschool's Presence module "
          'refused the request, or could not find what it was asked for; '
          'usually the account lacks $rights. If so, $fix. Otherwise try '
          'again in a moment; the technical details are in the server log.\n',
        ),
      );
      expect(text, isNot(contains('Oeps')));
      expectNoSecretsOrTraces(text);
    });

    test('on, while the connection does not work: access not checked, and '
        'the module not asked', () async {
      final (_, text) = await status(
        source: fakeExtensionSettings(FakeCredentials(password: '')),
        presence: SwitchState.on,
      );

      expect(
        text,
        contains(
          '\nAanwezigheden: on; access not checked, as the connection does '
          'not work.\n',
        ),
      );
      expect(server.requests, isEmpty);
    });
  });

  test('with a missing credentials file: says so', () async {
    final missing = File('does-not-exist.yml').absolute.path;

    final (_, text) = await status(source: CredentialsFile(missing));

    expect(text, startsWith('Smartschool connection: NOT working\n'));
    expect(text, contains('The credentials file $missing'));
    expect(text, contains('does not exist'));
    expect(text, contains('Settings: credentials file $missing'));
  });

  group('in ChatGPT or Codex', () {
    /// Settings read from [credentials], in an environment that also holds
    /// [variables], for a server Codex started.
    ExtensionSettings codexSettings(
      ClientContext client,
      FakeCredentials credentials, [
      Map<String, String> variables = const {},
    ]) => ExtensionSettings(
      client: client,
      read: () => credentials,
      environment: () => {'SYSTEMROOT': r'C:\Windows', ...variables},
    );

    test('a missing setting: names the variable, the form in ChatGPT and '
        'a variable under a mistyped name, never its value, and does not '
        'contact Smartschool', () async {
      final client = ClientContext();
      final (result, text) = await status(
        source: codexSettings(client, FakeCredentials(mainUrl: ''), {
          'SMARTSCHOOL_MAINURL': 'value-never-shown',
          'SMARTSCHOOL_USERNAME': 'jan.peeters',
        }),
        client: client,
        clientName: ClientApp.codexClientName,
      );

      expect(result.isError, isNot(true));
      const misnamed =
          '"SMARTSCHOOL_MAINURL" is set, but that is not the name of a '
          'setting: probably SMARTSCHOOL_MAIN_URL.';
      expect(
        text,
        startsWith(
          'Smartschool connection: NOT working\n'
          'Problem: Not all Smartschool settings are filled in. Missing: '
          'SMARTSCHOOL_MAIN_URL ("Smartschool-adres"). $misnamed Fill it in '
          "in the ChatGPT app, under Instellingen (Settings) → Plug-ins → MCP's "
          '→ smartschool → Omgevingsvariabelen (Environment variables); in the '
          'Codex CLI or IDE extension, under [mcp_servers.smartschool.env] in '
          r'%USERPROFILE%\.codex\config.toml, then restart ChatGPT (or '
          'Codex).\n',
        ),
      );
      expect(
        text,
        contains(
          '\nSettings: environment variables of the MCP server '
          '(SMARTSCHOOL_MAIN_URL: missing, SMARTSCHOOL_USERNAME: filled in, '
          'SMARTSCHOOL_PASSWORD: filled in, SMARTSCHOOL_MFA: filled in)\n'
          'Wrong setting names: $misnamed\n',
        ),
      );
      expect(text, isNot(contains('value-never-shown')));
      expectNoSecretsOrTraces(text);
      expect(server.requests, isEmpty);
    });

    test('valid settings: working', () async {
      final client = ClientContext();
      final (_, text) = await status(
        source: codexSettings(client, FakeCredentials()),
        client: client,
        clientName: ClientApp.codexClientName,
      );

      expect(
        text,
        'Smartschool connection: working\n'
        'Logged in as: $fakeDisplayName\n'
        'Smartschool address: $fakeHost\n'
        'Settings: environment variables of the MCP server (all filled in)\n'
        'Server version: $packageVersion\n'
        'Updates: not checked (the update check is turned off)',
      );
    });

    test('in Claude Desktop, the same settings are worded as '
        'before', () async {
      final client = ClientContext();
      final (_, text) = await status(
        source: codexSettings(client, FakeCredentials(mainUrl: '')),
        client: client,
        clientName: 'claude-ai',
      );

      expect(
        text,
        contains(
          'Missing: "Smartschool-adres" (SMARTSCHOOL_MAIN_URL). Fill it in in '
          'the Smartschool extension settings in Claude Desktop (Settings → '
          'Extensions), then restart Claude Desktop.\n',
        ),
      );
      expect(
        text,
        contains(
          '\nSettings: extension settings (Smartschool-adres: missing, ',
        ),
      );
      expect(text, isNot(contains('Wrong setting names')));
    });
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
      'no authenticator app': (
        FakeSmartschool(secondStep: SecondStep.twoFactorWithoutApp),
        'asks for a kind of two-factor authentication (2FA) this extension '
            'cannot handle',
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

  test('after a restart whose saved session expired: logs in once and '
      'works', () async {
    final cookies = await tempCache();
    Future<String> statusAfterStart() async {
      final session = SmartschoolSession(
        fakeExtensionSettings(),
        createClient: fakeClientFactory(server, cookies),
      );
      addTearDown(session.close);
      final (connection, _) = await connect(tools: [statusTool(session)]);
      final (_, text) = await callTool(connection, 'smartschool_status');
      return text;
    }

    await statusAfterStart();
    server.expireSession();
    server.requests.clear();
    final text = await statusAfterStart();

    expect(text, startsWith('Smartschool connection: working\n'));
    expect(server.logins, 2);
    expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
  });
}
