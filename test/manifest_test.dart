/// The Claude Desktop extension's `manifest.json` against the server: its
/// settings, the environment variables they become, and its tool list; and
/// its long description against the summary of `docs/installatie.md`.
/// `test/bundle_e2e_test.dart` starts the server from it; the release
/// workflow validates it with `mcpb validate`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:smartschool_mcp/src/lvs/lvs_opt_in.dart';
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
        'lvs': 'boolean',
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

  test('describes a switch by the rights its tools need, or by the choice '
      'it is for the LVS, and each of its tools as one that needs it on '
      '(#42, #47, #153)', () {
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
    // Not rights but a choice: the most sensitive data about pupils, with
    // the privacy section of the guide and what is left out unless asked
    // (#153, #158).
    final lvs = fields[Setting.lvs.fileKey]!;
    expect(
      lvs['description'],
      allOf([
        startsWith('Alleen als jij en je school dat willen'),
        contains('leerlingvolgsysteem (LVS)'),
        contains('de gevoeligste gegevens over leerlingen'),
        contains(
          'de notities, de resultaten, het handelingsplan en de afwezigheden',
        ),
        contains('Alleen lezen, één leerling per keer'),
        contains(
          'vertrouwelijke notities en de motivering van afwezigheden alleen '
          'als je erom vraagt',
        ),
        contains(lvsPrivacyGuideUrl),
        contains('laat het dan uit'),
      ]),
    );
    final session = SmartschoolSession(const ExtensionSettings());
    final optIns = <OptInTools>[
      skoreOptIn(session, SwitchState.on),
      presenceOptIn(session, SwitchState.on),
      lvsOptIn(session, SwitchState.on),
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

  test('sums up in its long description the parts the Claude Desktop guide '
      'sums up, in its order, each part a switch turns on marked with that '
      'switch, and the gradebook and the pupil tracking system as the guide '
      'does (#150, #158)', () {
    final guide = File(
      'docs/installatie.md',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final guideSummary = guide.substring(0, guide.indexOf('\n## Inhoud'));
    final guideParts = [
      for (final match in RegExp(
        r'^- \*\*(.+?):?\*\*',
        multiLine: true,
      ).allMatches(guideSummary))
        match.group(1),
    ];
    expect(guideParts, contains('Puntenboek'));

    final longDescription = manifest['long_description'] as String;
    final parts = {
      for (final match in RegExp(
        r'^- \*\*(.+?)(?: \(alleen met (.+?) aan\))?:\*\* (.*)$',
        multiLine: true,
      ).allMatches(longDescription))
        match.group(1)!: (switchTitle: match.group(2), text: match.group(3)!),
    };
    expect(parts.keys, guideParts);
    final switchTitles = {
      for (final setting in Setting.switches) setting.formTitle,
    };
    expect(parts.keys, containsAll(switchTitles));
    for (final MapEntry(key: name, value: part) in parts.entries) {
      expect(
        part.switchTitle,
        switchTitles.contains(name) ? name : isNull,
        reason: name,
      );
    }

    // The guide's wrapped lines as one line, to find its sentences.
    final guideText = guideSummary.replaceAll(RegExp(r'\s+'), ' ');
    for (final (part, sentence) in [
      ('Puntenboek', 'je eigen puntenboeken in Skore bekijken'),
      (
        'Puntenboek',
        'Een nieuwe evaluatie blijft ongepubliceerd: je publiceert ze zelf '
            'in Smartschool.',
      ),
      (
        'Puntenboek',
        'Dit is er voor elke leerkracht: je hoeft er niets voor aan te '
            'zetten.',
      ),
      // The pupil tracking system (#158): read-only, one pupil at a time,
      // and what is left out unless asked.
      (
        'Leerlingvolgsysteem',
        'in het leerlingvolgsysteem (LVS) een leerling opzoeken en zijn '
            'dossier lezen: de notities, de resultaten in alle vakken, het '
            'handelingsplan en de afwezigheden.',
      ),
      (
        'Leerlingvolgsysteem',
        'Eén leerling per keer, en alleen lezen: Claude kan in het LVS niets '
            'veranderen.',
      ),
      (
        'Leerlingvolgsysteem',
        'Vertrouwelijke notities en de motivering van afwezigheden laat '
            'Claude weg, tenzij je erom vraagt.',
      ),
    ]) {
      expect(guideText, contains(sentence));
      expect(parts[part]!.text, contains(sentence), reason: part);
    }
    expect(
      guideText,
      contains('Voor je eigen puntenboek heb je het niet nodig.'),
    );
    expect(
      parts['Skore-beheer']!.text,
      contains('Voor je eigen puntenboek heb je Skore-beheer niet nodig.'),
    );
    expect(
      parts['Leerlingvolgsysteem']!.text,
      allOf(
        startsWith('alleen als jij en je school dat willen'),
        contains('het staat standaard uit'),
        contains('gaat naar Anthropic'),
        contains('Lees eerst Veiligheid en privacy in de gids.'),
      ),
    );
    expect(
      guideText,
      contains(
        '- **Leerlingvolgsysteem**, alleen als jij en je school dat willen',
      ),
    );
    expect(
      longDescription,
      contains('Uit het leerlingvolgsysteem bewaart ze niets.'),
    );
  });

  test('lists the tools of the tool pages, in the order the README links '
      'them', () {
    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final overview = RegExp(
      r'^## Tool areas\n(.*?)^## ',
      multiLine: true,
      dotAll: true,
    ).firstMatch(read('README.md'))!.group(1)!;
    final pages = [
      for (final match in RegExp(
        r'^\| \[[^\]]+\]\((docs/tools/[a-z_]+\.md)\) \|',
        multiLine: true,
      ).allMatches(overview))
        match.group(1)!,
    ];
    expect(pages, hasLength(pages.toSet().length));
    expect(
      Directory('docs/tools').listSync().whereType<File>().map(
        (file) => 'docs/tools/${file.uri.pathSegments.last}',
      ),
      unorderedEquals(pages),
      reason: 'the README links every tool page',
    );

    final documented = <String>[];
    for (final page in pages) {
      final text = read(page);
      // Each tool has a heading of its own under "## Tools", and a row in
      // the table the page opens with, in the same order.
      final section = RegExp(
        r'^## Tools\n(.*?)^## ',
        multiLine: true,
        dotAll: true,
      ).firstMatch(text)!.group(1)!;
      final headings = [
        for (final match in RegExp(
          r'^### `([a-z_]+)`$',
          multiLine: true,
        ).allMatches(section))
          match.group(1)!,
      ];
      final table = text.substring(0, text.indexOf('\n## Tools\n'));
      final rows = [
        for (final match in RegExp(
          r'^\| \[`([a-z_]+)`\]\(#([a-z_]+)\) \| [^|]+ \| (No|Yes)[^|]* \|$',
          multiLine: true,
        ).allMatches(table))
          if (match.group(1) == match.group(2)) match.group(1)!,
      ];
      expect(headings, isNotEmpty, reason: page);
      expect(rows, headings, reason: page);
      documented.addAll(headings);
    }

    expect(documented, hasLength(69));
    expect([
      for (final tool in manifest['tools'] as List) (tool as Map)['name'],
    ], documented);
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
