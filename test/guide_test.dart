/// The colleague guides against the server.
///
/// `docs/installatie.md` (Claude Desktop) must use the names colleagues see
/// (the install form's field titles, the release asset, the question that
/// runs `smartschool_status`) and say what the server keeps where, as the
/// server does it. `docs/installatie-chatgpt.md` must name the release exe,
/// the folder the installer uses, the keys and the server name the
/// installer shows, and where ChatGPT keeps the settings, as the server's
/// messages say. The links within and between the guides must work, and
/// the README, the release notes and the extension manifest must link to
/// them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/install.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';

const _guidePath = 'docs/installatie.md';
const _chatGptGuidePath = 'docs/installatie-chatgpt.md';
const _repository = 'https://github.com/yvanvds/smartschool-mcp';
const _guideUrl = '$_repository/blob/main/$_guidePath';
const _chatGptGuideUrl = '$_repository/blob/main/$_chatGptGuidePath';
const _latestRelease = '$_repository/releases/latest';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final guide = _read(_guidePath);
  // The guide wraps its lines: compare with every run of white space as one
  // space.
  final text = guide.replaceAll(RegExp(r'\s+'), ' ');

  test('names every field of the install form by its title', () {
    for (final setting in Setting.values) {
      expect(text, contains('**${setting.formTitle}**'), reason: setting.name);
    }
  });

  test('tests the connection with the question smartschool_status is '
      'described with', () async {
    const question = 'Werkt mijn Smartschool-verbinding?';
    expect(text, contains('> $question'));
    final session = SmartschoolSession(const ExtensionSettings());
    addTearDown(session.close);
    expect(statusTool(session).definition.description, contains(question));
  });

  test('downloads the asset the update notice names, from the latest '
      'release', () {
    const asset = UpdateChecker.assetName;
    expect(text, contains('($_latestRelease/download/$asset)'));
    expect(text, contains('($_latestRelease)'));
    expect(text, contains('`$asset`'));
  });

  test('names the files and folders the server keeps', () {
    expect(text, contains(r'`%USERPROFILE%\.cache\smartschool`'));
    expect(
      text,
      contains(
        r'`%USERPROFILE%\.cache\smartschool\' + UpdateChecker.stateFileName,
      ),
    );
    expect(text, contains('`${DownloadFolder.manifestName}`'));
    final home = DownloadFolder.defaultPath({'USERPROFILE': 'H', 'HOME': 'H'});
    final downloads = home!.substring('H'.length + 1).replaceAll('/', r'\');
    expect(downloads, r'Downloads\Smartschool');
    expect(text, contains('`$downloads`'));
  });

  test('says that spaces in the 2FA key do not matter and which characters '
      'it has, as the library checks it', () {
    expect(text, isNot(contains('zonder spaties')));
    expect(text, contains('Spaties in de sleutel zijn geen probleem.'));
    expect(text, contains('letters en de cijfers 2 tot 7; spaties mogen.'));
    // The check the library runs on the key when it logs in.
    expect(
      Credentials.normalizeTotpSecret('JBSW Y3DP EHPK 3PXP'),
      'JBSWY3DPEHPK3PXP',
    );
    for (final typed in ['123456', '234567', 'JBSWY3DPEHPK3PX8']) {
      expect(
        () => Credentials.normalizeTotpSecret(typed),
        throwsA(isA<SmartschoolInvalidTotpSecretError>()),
        reason: typed,
      );
    }
  });

  test('gives the time and size limits of the server', () {
    expect(text, contains('${DownloadFolder.defaultRetention.inDays} dagen'));
    expect(text, contains('${maxIntradeskFileBytes ~/ (1024 * 1024)} MB'));
    expect(text, contains('${maxSavedFileBytes ~/ (1024 * 1024)} MB'));
  });

  test('links only to headings on the page, or in the other guide, that '
      'exist', () {
    final guides = {
      'installatie.md': guide,
      'installatie-chatgpt.md': _read(_chatGptGuidePath),
    };
    final anchors = {
      for (final MapEntry(:key, :value) in guides.entries)
        key: {
          for (final match in RegExp(
            r'^#{1,6} (.+)$',
            multiLine: true,
          ).allMatches(value))
            _gitHubAnchor(match.group(1)!),
        },
    };
    final link = RegExp(r'\]\(((?:installatie(?:-chatgpt)?\.md)?)#([^)]+)\)');
    for (final MapEntry(key: name, value: text) in guides.entries) {
      final links = [
        for (final match in link.allMatches(text))
          (match.group(1)!.isEmpty ? name : match.group(1)!, match.group(2)!),
      ];
      expect(links, isNotEmpty, reason: name);
      for (final (page, anchor) in links) {
        expect(anchors[page], contains(anchor), reason: '$name: $page#$anchor');
      }
    }
  });

  test('is linked from the README, the release notes and the extension '
      'manifest', () {
    expect(_read('README.md'), contains('](docs/installatie.md)'));
    expect(_read('.github/release-notes.md'), contains('($_guideUrl)'));
    expect(
      _read('.github/workflows/release.yml'),
      contains('--notes-file .github/release-notes.md'),
    );
    final manifest = jsonDecode(_read('manifest.json')) as Map<String, Object?>;
    expect(manifest['documentation'], _guideUrl);
  });

  group('the ChatGPT guide', () {
    final chatGpt = _read(_chatGptGuidePath).replaceAll(RegExp(r'\s+'), ' ');

    test('downloads the exe the update notice names, from the latest '
        'release, and the release publishes it', () {
      const asset = UpdateChecker.exeAssetName;
      expect(chatGpt, contains('($_latestRelease/download/$asset)'));
      expect(chatGpt, contains('`$asset`'));
      expect(asset, installedName);
      expect(
        _read('.github/workflows/release.yml'),
        contains('bundle/server/$asset'),
      );
    });

    test('names the folder the installer copies the server to', () {
      final folder = installDirectory({'LOCALAPPDATA': '%LOCALAPPDATA%'})!;
      expect(chatGpt, contains('`$folder\\$installedName`'));
    });

    test('has the form the installer describes: the server name the '
        'messages use, no arguments, and every key', () {
      expect(
        chatGpt,
        contains('| **Naam** | `${ClientApp.codexServerName}` |'),
      );
      expect(chatGpt, contains('| **Argumenten** | Niets.'));
      for (final setting in Setting.values) {
        expect(
          chatGpt,
          contains('| `${setting.envVar}` |'),
          reason: setting.name,
        );
        expect(
          chatGpt,
          contains('| **${setting.formTitle}** | `${setting.envVar}` |'),
          reason: '${setting.name}: the table for the other guide',
        );
      }
      final instructions = installInstructions(
        const Installation(r'C:\x.exe', copied: true, replaced: false),
        onClipboard: false,
      );
      for (final words in ["MCP's", 'Aangepaste MCP-server maken']) {
        expect(chatGpt, contains(words));
        expect(instructions, contains(words));
      }
    });

    test('says where ChatGPT keeps the settings, as the messages do', () {
      const config = r'%USERPROFILE%\.codex\config.toml';
      expect(chatGpt, contains('`$config`'));
      final where = ExtensionSettings(
        client: ClientContext(ClientApp.codex),
      ).where;
      expect(where, contains(config));
      const path = "Instellingen → Plug-ins → MCP's → smartschool";
      expect(chatGpt, contains('**$path**'));
      expect(where.replaceAll(' (Settings)', ''), contains(path));
    });

    test('asks for a paid plan and for model training to be off, with the '
        'English name of the setting the installer gives (#50)', () {
      const english = 'Improve the model for everyone';
      expect(chatGpt, contains('**Een betalend ChatGPT-abonnement:**'));
      expect(chatGpt, contains('(*$english*) uit.'));
      expect(privacyWarning.join(' '), contains(english));
      expect(chatGpt, contains('### Eerst: OpenAI niet laten trainen'));
    });

    test('quotes the message about a mistyped key as the server words '
        'it', () {
      final message = MisnamedSetting.describe(
        MisnamedSetting.find(['SMARTSCHOOL_MAINURL']),
      )!;
      // Quoted without the full stop at the end.
      expect(
        chatGpt,
        contains('`${message.substring(0, message.length - 1)}`'),
      );
    });

    test('tests with the same question, and is linked from the other guide, '
        'the README, the release notes and the installer', () {
      expect(chatGpt, contains('> Werkt mijn Smartschool-verbinding?'));
      expect(guide, contains('](installatie-chatgpt.md)'));
      expect(_read('README.md'), contains('](docs/installatie-chatgpt.md)'));
      expect(
        _read('.github/release-notes.md'),
        contains('($_chatGptGuideUrl)'),
      );
      expect(chatGptGuideUrl, _chatGptGuideUrl);
    });
  });
}

/// The anchor GitHub gives a heading: lower case, without punctuation, with
/// spaces as hyphens.
String _gitHubAnchor(String heading) => heading
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true), '')
    .replaceAll(' ', '-');
