/// The Claude Desktop extension's `manifest.json` against the server: its
/// settings, the environment variables they become, and its tool list.
/// `test/bundle_e2e_test.dart` starts the server from it; the release
/// workflow validates it with `mcpb validate`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smartschool_mcp/src/opt_in.dart';
import 'package:smartschool_mcp/src/presence/presence_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final manifest =
      jsonDecode(File('manifest.json').readAsStringSync())
          as Map<String, Object?>;
  final server = manifest['server'] as Map<String, Object?>;
  final mcpConfig = server['mcp_config'] as Map<String, Object?>;
  final fields = (manifest['user_config'] as Map)
      .cast<String, Map<String, Object?>>();

  test('runs the compiled server from the extension folder, on Windows '
      'only', () {
    expect(manifest['manifest_version'], '0.3');
    expect(server['type'], 'binary');
    expect(server['entry_point'], 'server/smartschool-mcp.exe');
    expect(mcpConfig['command'], '\${__dirname}/${server['entry_point']}');
    expect(mcpConfig['args'], isEmpty);
    expect(manifest['compatibility'], {
      'platforms': ['win32'],
    });
  });

  test('has a field per setting, in form order, titled as the server names '
      'it in its messages', () {
    expect(fields.keys, [
      for (final setting in Setting.values) setting.fileKey,
    ]);
    for (final setting in Setting.values) {
      final field = fields[setting.fileKey]!;
      expect(field['title'], setting.formTitle, reason: setting.name);
      expect(field['required'], setting.required, reason: setting.name);
      expect(field['description'], isNotEmpty, reason: setting.name);
    }
    expect(
      {for (final MapEntry(:key, :value) in fields.entries) key: value['type']},
      {
        'main_url': 'string',
        'username': 'string',
        'password': 'string',
        'mfa': 'string',
        'download_dir': 'directory',
        'skore': 'boolean',
        'presence': 'boolean',
      },
    );
    // A switch, and only a switch, is a boolean field (#42).
    for (final setting in Setting.values) {
      expect(
        fields[setting.fileKey]!['type'] == 'boolean',
        setting.isSwitch,
        reason: setting.name,
      );
    }
    expect(
      [
        for (final MapEntry(:key, :value) in fields.entries)
          if (value['sensitive'] == true) key,
      ],
      ['password', 'mfa'],
    );
  });

  test('passes every setting in its SMARTSCHOOL_* variable and nothing else '
      '(no update-check override)', () {
    expect(mcpConfig['env'], {
      for (final setting in Setting.values)
        setting.envVar: '\${user_config.${setting.fileKey}}',
    });
    expect(
      (mcpConfig['env'] as Map).keys,
      isNot(
        anyElement(
          isIn([UpdateChecker.disableVariable, UpdateChecker.endpointVariable]),
        ),
      ),
    );
  });

  test('gives an optional field a default without variables, empty for '
      'text and off for a switch: Claude Desktop passes an unset field as '
      '"\${user_config.KEY}" and does not replace \${HOME} in a '
      'default', () {
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value['required'] == true) {
        expect(value, isNot(contains('default')), reason: key);
      } else if (value['type'] == 'boolean') {
        expect(value['default'], isFalse, reason: key);
      } else {
        expect(value['default'], '', reason: key);
      }
    }
  });

  test('describes a switch by the rights its tools need, and each of its '
      'tools as one that needs it on (#42, #47)', () {
    final skore = fields[Setting.skore.fileKey]!;
    expect(
      skore['description'],
      allOf(
        contains('Rapporten > Modellen en Puntenboeken'),
        contains('laat het dan uit'),
      ),
    );
    final presence = fields[Setting.presence.fileKey]!;
    expect(
      presence['description'],
      allOf(
        contains('halve-dagaanwezigheden van klassen registreert'),
        contains('afwezigheidsbeheerder'),
        contains('laat het dan uit'),
      ),
    );
    final session = SmartschoolSession(const ExtensionSettings());
    final optIns = <OptInTools>[
      skoreOptIn(session, SwitchState.on),
      presenceOptIn(session, SwitchState.on),
    ];
    expect(
      {for (final optIn in optIns) optIn.setting},
      Setting.switches.toSet(),
      reason: 'a group of tools for every switch',
    );
    final descriptions = {
      for (final tool in manifest['tools'] as List)
        (tool as Map)['name']: tool['description'] as String,
    };
    for (final optIn in optIns) {
      for (final tool in optIn.tools) {
        final name = tool.definition.name;
        expect(
          descriptions[name],
          startsWith('Alleen met ${optIn.setting.formTitle} aan: '),
          reason: name,
        );
      }
    }
  });

  test('lists the tools of the README, in its order', () {
    final readme = File(
      'README.md',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final section = RegExp(
      r'^### Tools\n(.*?)^#',
      multiLine: true,
      dotAll: true,
    ).firstMatch(readme)!.group(1)!;
    final readmeTools = [
      for (final match in RegExp(
        r'^- `([a-z_]+)`:',
        multiLine: true,
      ).allMatches(section))
        match.group(1),
    ];

    expect(readmeTools, hasLength(59));
    expect([
      for (final tool in manifest['tools'] as List) (tool as Map)['name'],
    ], readmeTools);
    for (final tool in manifest['tools'] as List) {
      expect((tool as Map)['description'], isNotEmpty, reason: tool['name']);
    }
  });

  test('names the project as pubspec.yaml does, under GPL-3.0', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(manifest['name'], 'smartschool-mcp');
    expect(manifest['display_name'], 'Smartschool');
    expect(manifest['repository'], {
      'type': 'git',
      'url': '${pubspec['repository']}.git',
    });
    expect(manifest['license'], 'GPL-3.0');
    expect(manifest['description'], isNotEmpty);
    expect(manifest['author'], containsPair('name', isNotEmpty));
  });

  test('has a 512 x 512 PNG icon', () {
    final bytes = File(manifest['icon'] as String).readAsBytesSync();
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData.sublistView(bytes, 16, 24);
    expect((header.getUint32(0), header.getUint32(4)), (512, 512));
  });
}
