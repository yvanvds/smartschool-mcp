/// End-to-end test of the installer for ChatGPT and Codex, and of the server
/// started the way Codex starts it: compiles the server, installs it with
/// `--install` into a temporary `LOCALAPPDATA`, starts the installed copy
/// with Codex's environment and client name, installs again while that copy
/// runs, and checks that the copy moved aside is deleted later.
@TestOn('windows')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/install.dart';
import 'package:test/test.dart';

import 'support/exe.dart';

/// The variables Codex passes on to an MCP server on Windows, next to the
/// server's own: `WINDOWS_CORE_ENV_VARS` in
/// `codex-rs/protocol/src/shell_environment.rs` (openai/codex). It starts
/// the server with a cleared environment (`env_clear` in
/// `codex-rs/utils/pty/src/child_command.rs`).
const _codexWindowsVariables = [
  'PATH',
  'PATHEXT',
  'SHELL',
  'COMSPEC',
  'SYSTEMROOT',
  'WINDIR',
  'SYSTEMDRIVE',
  'USERNAME',
  'USERDOMAIN',
  'USERPROFILE',
  'HOMEDRIVE',
  'HOMEPATH',
  'PROGRAMFILES',
  'PROGRAMFILES(X86)',
  'PROGRAMW6432',
  'PROGRAMDATA',
  'LOCALAPPDATA',
  'APPDATA',
  'TEMP',
  'TMP',
  'TMPDIR',
  'POWERSHELL',
  'PWSH',
];

/// The environment Codex gives a server whose form holds [variables].
Map<String, String> _codexEnvironment(Map<String, String> variables) => {
  for (final name in _codexWindowsVariables) name: ?Platform.environment[name],
  ...variables,
};

void main() {
  late String exePath;
  late Directory local;
  late String installed;

  setUpAll(() async => exePath = await compileServer());

  setUp(() async {
    local = await Directory.systemTemp.createTemp('smartschool_local_');
    addTearDown(() async {
      try {
        await local.delete(recursive: true);
      } on FileSystemException {
        // A server was still running from it; it is in the temp folder.
      }
    });
    installed = [
      local.path,
      'Programs',
      'smartschool-mcp',
      installedName,
    ].join(Platform.pathSeparator);
  });

  /// Runs the compiled installer with `LOCALAPPDATA` set to [local].
  Future<ProcessResult> install() => Process.run(
    exePath,
    ['--install', '--no-clipboard'],
    environment: {
      ...environmentWithoutSmartschool(),
      'LOCALAPPDATA': local.path,
    },
    includeParentEnvironment: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  /// The copies an update moved aside in the install folder.
  List<String> replacedCopies() => [
    for (final entity in File(installed).parent.listSync())
      if (replacedCopy.hasMatch(entity.uri.pathSegments.last)) entity.path,
  ];

  test('installs into LOCALAPPDATA; the installed copy serves Codex, says '
      'where to fix a setting in ChatGPT and names a mistyped key; a second '
      'install replaces the running copy, which a later start '
      'deletes', () async {
    final first = await install();
    expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
    final output = (first.stdout as String).replaceAll('\r\n', '\n');
    expect(output, contains('Geïnstalleerd in: $installed\n'));
    expect(output, contains('SMARTSCHOOL_MAIN_URL'));
    expect(output, isNot(contains('klembord')));
    expect(File(installed).readAsBytesSync(), File(exePath).readAsBytesSync());

    // As ChatGPT starts it, with a key mistyped in its form.
    final form = {
      'SMARTSCHOOL_MAINURL': 'school.smartschool.be',
      'SMARTSCHOOL_USERNAME': 'jan.peeters',
      'SMARTSCHOOL_PASSWORD': 'password-never-shown',
      'SMARTSCHOOL_MFA': 'JBSWY3DPEHPK3PXP',
    };
    final server = await ServerProcess.start(
      installed,
      environment: _codexEnvironment(form),
    );
    await server.initialize(clientName: ClientApp.codexClientName);
    final (isError, status) = await server.callTool('smartschool_status');

    expect(isError, isNot(true));
    expect(
      status,
      startsWith(
        'Smartschool connection: NOT working\n'
        'Problem: Not all Smartschool settings are filled in. Missing: '
        'SMARTSCHOOL_MAIN_URL ("Smartschool-adres"). "SMARTSCHOOL_MAINURL" is '
        'set, but that is not the name of a setting: probably '
        'SMARTSCHOOL_MAIN_URL. Fill it in in the ChatGPT app, under '
        "Instellingen (Settings) → Plug-ins → MCP's → smartschool → "
        'Omgevingsvariabelen',
      ),
    );
    expect(status, contains('then restart ChatGPT (or Codex).\n'));
    expect(status, contains('\nSettings: environment variables of the MCP '));
    expect(status, isNot(contains('password-never-shown')));
    expect(status, isNot(contains('JBSWY3DPEHPK3PXP')));

    // An update while ChatGPT runs the installed copy.
    final second = await install();
    expect(second.exitCode, 0, reason: '${second.stdout}${second.stderr}');
    expect(
      second.stdout,
      contains('Je instellingen in ChatGPT blijven bewaard.'),
    );
    expect(replacedCopies(), hasLength(1), reason: 'the running copy');

    await server.stop();
    expect(await server.stderr, contains('client: codex-mcp-client'));

    final restarted = await ServerProcess.start(
      installed,
      environment: _codexEnvironment(form),
    );
    await restarted.initialize(clientName: ClientApp.codexClientName);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (replacedCopies().isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(replacedCopies(), isEmpty, reason: 'deleted at the next start');
    await restarted.stop();
  });

  test('the compiled server words its messages for the app that started '
      'it, by the name it gives in initialize', () async {
    for (final (clientName, expected) in [
      (ClientApp.codexClientName, 'restart ChatGPT (or Codex)'),
      ('claude-ai', 'restart Claude Desktop'),
    ]) {
      final server = await ServerProcess.start(
        exePath,
        environment: environmentWithoutSmartschool(),
      );
      await server.initialize(clientName: clientName);
      final (_, status) = await server.callTool('smartschool_status');
      expect(status, contains(expected), reason: clientName);
      await server.stop();
    }
  });
}
