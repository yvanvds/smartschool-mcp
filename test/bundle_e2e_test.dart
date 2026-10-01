/// End-to-end test of the Claude Desktop extension: builds its folder with
/// `tool/build_bundle.dart`, the script the release workflow packs, and
/// starts the server in it the way Claude Desktop does from `manifest.json`.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/claude_desktop.dart';
import 'support/exe.dart';

void main() {
  late Directory bundle;
  late Map<String, Object?> manifest;

  setUpAll(() async {
    final temp = await Directory.systemTemp.createTemp(
      'smartschool_mcp_bundle_',
    );
    addTearDown(() => temp.delete(recursive: true));
    bundle = Directory(_join(temp.path, 'smartschool-mcp'));
    final build = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/build_bundle.dart',
      bundle.path,
    ]);
    if (build.exitCode != 0) {
      fail('tool/build_bundle.dart failed:\n${build.stdout}\n${build.stderr}');
    }
    manifest =
        jsonDecode(File(_join(bundle.path, 'manifest.json')).readAsStringSync())
            as Map<String, Object?>;
  });

  /// The `user_config` fields of the manifest, by key.
  Map<String, Map<String, Object?>> fields() =>
      (manifest['user_config'] as Map).cast<String, Map<String, Object?>>();

  /// Starts the server the way Claude Desktop does after the install form
  /// was filled in with [userConfig], with [home] as the user's folder.
  Future<ServerProcess> startInstalled(
    Map<String, String> userConfig,
    Directory home,
  ) {
    final config = claudeDesktopConfig(
      manifest,
      extensionPath: bundle.path,
      userConfig: userConfig,
      home: home.path,
    );
    expect(config, isNotNull, reason: 'Claude Desktop would not start it');
    expect(
      config!.env.values,
      everyElement(isNot(contains(r'${'))),
      reason: 'every setting must reach the server, also one left empty',
    );
    expect(File(config.command).existsSync(), isTrue, reason: config.command);
    return ServerProcess.start(
      config.command,
      args: config.args,
      environment: {
        ...environmentWithoutSmartschool(),
        'HOME': home.path,
        'USERPROFILE': home.path,
        ...config.env,
      },
    );
  }

  Future<Directory> tempHome() async {
    final home = await Directory.systemTemp.createTemp('smartschool_mcp_home_');
    addTearDown(() => home.delete(recursive: true));
    return home;
  }

  test('the extension folder holds the manifest, its icon, the license and '
      'the server at the entry point, and nothing else', () {
    final files = {
      for (final file in bundle.listSync(recursive: true).whereType<File>())
        file.path
            .substring(bundle.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
    };

    expect(files, {
      'manifest.json',
      'icon.png',
      'LICENSE',
      'server/smartschool-mcp.exe',
    });
    expect(manifest['icon'], 'icon.png');
    expect(
      (manifest['server'] as Map)['entry_point'],
      'server/smartschool-mcp.exe',
    );
    expect(
      File(_join(bundle.path, 'manifest.json')).readAsStringSync(),
      File('manifest.json').readAsStringSync(),
    );
  });

  test('the build refuses to replace a folder that is not an earlier build, '
      'and leaves it as it was', () async {
    final folder = await Directory.systemTemp.createTemp(
      'smartschool_mcp_not_a_bundle_',
    );
    addTearDown(() => folder.delete(recursive: true));
    final own = File(_join(folder.path, 'manifest.json'))
      ..writeAsStringSync('{}');
    final other = File(_join(folder.path, 'package.json'))
      ..writeAsStringSync('{}');

    final build = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/build_bundle.dart',
      folder.path,
    ]);

    expect(build.exitCode, 1);
    expect(build.stderr, contains('is not an earlier build to replace'));
    expect(own.readAsStringSync(), '{}');
    expect(other.existsSync(), isTrue);
    expect(folder.listSync(), hasLength(2));
  });

  test('installed with the required settings and "Downloadmap" left empty: '
      'the server reports the manifest\'s version and tools, names the '
      'settings to fix by their titles in the install form, and saves in '
      'the default download folder', () async {
    final home = await tempHome();
    // Only spaces: Claude Desktop takes them as filled in, the server as
    // empty, so it reports them without logging in anywhere.
    final server = await startInstalled({
      for (final MapEntry(:key, :value) in fields().entries)
        if (value['required'] == true) key: ' ',
    }, home);

    final init = await server.initialize();
    expect((init['serverInfo'] as Map)['version'], manifest['version']);
    final tools = (await server.request('tools/list'))['tools'] as List;
    expect(
      [for (final tool in tools) (tool as Map)['name']],
      [for (final tool in manifest['tools'] as List) (tool as Map)['name']],
    );

    final (isError, text) = await server.callTool('smartschool_status');

    expect(isError, isNot(true));
    expect(text, startsWith('Smartschool connection: NOT working\n'));
    final env =
        ((manifest['server'] as Map)['mcp_config'] as Map)['env'] as Map;
    String envVar(String key) =>
        env.keys.singleWhere((name) => env[name] == '\${user_config.$key}')
            as String;
    final required = [
      for (final MapEntry(:key, :value) in fields().entries)
        if (value['required'] == true) '"${value['title']}" (${envVar(key)})',
    ];
    expect(text, contains('Missing: ${required.join(', ')}.'));
    expect(text, contains('Settings: extension settings'));
    final folder = _join(_join(home.path, 'Downloads'), 'Smartschool');
    expect(
      text,
      contains(
        '\nDownload folder: $folder (the default; does not exist yet: it is '
        'created when the first file is saved)\n',
      ),
    );
    expect(text, contains('Server version: ${manifest['version']}'));

    await server.stop();
    expect(home.listSync(), isEmpty);
  });

  test('installed with a folder picked for "Downloadmap": '
      'smartschool_status shows it under that title, writable', () async {
    final home = await tempHome();
    final downloads = await Directory.systemTemp.createTemp(
      'smartschool_mcp_picked_',
    );
    addTearDown(() => downloads.delete(recursive: true));
    final server = await startInstalled({
      for (final MapEntry(:key, :value) in fields().entries)
        if (value['required'] == true) key: ' ',
      'download_dir': downloads.path,
    }, home);
    await server.initialize();

    final (_, text) = await server.callTool('smartschool_status');

    final title = fields()['download_dir']!['title'];
    expect(
      text,
      contains(
        '\nDownload folder: ${downloads.path} (set in "$title" '
        '(SMARTSCHOOL_DOWNLOAD_DIR); writable)\n',
      ),
    );
    await server.stop();
  });
}

String _join(String folder, String name) =>
    '$folder${Platform.pathSeparator}$name';
