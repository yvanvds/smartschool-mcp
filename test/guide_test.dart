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
import 'package:pub_semver/pub_semver.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/install.dart';
import 'package:smartschool_mcp/src/presence/presence_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:smartschool_mcp/src/tools/create_skore_evaluation_tool.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_feedback_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_feedback_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_grades_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import '../tool/release_notes.dart';
import 'support/fake_github.dart';

const _guidePath = 'docs/installatie.md';
const _chatGptGuidePath = 'docs/installatie-chatgpt.md';
const _repository = 'https://github.com/yvanvds/smartschool-mcp';
const _guideUrl = '$_repository/blob/main/$_guidePath';
const _chatGptGuideUrl = '$_repository/blob/main/$_chatGptGuidePath';
const _releases = '$_repository/releases';
const _latestRelease = '$_releases/latest';

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

  test('says under Bijwerken that the answer gives the download link of the '
      'extension and what is new, as the update notice does (#59)', () {
    final section = _section(text, '## 6. Bijwerken naar een nieuwe versie');
    expect(
      section,
      contains(
        'een downloadlink naar `${UpdateChecker.assetName}` en in een paar '
        'woorden wat er nieuw is.',
      ),
    );
    expect(
      section,
      contains('wat er nieuw is in elke versie die je overslaat'),
    );
    expect(section, contains('1. Klik op de downloadlink uit het antwoord'));
    expect(section, contains('`$_releases/`'));
    _expectNoticeGives(ClientApp.claudeDesktop, UpdateChecker.assetName);
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

  test('says that an account without 2FA, such as a student\'s, leaves the '
      '2FA key empty, as the install form allows, and what happens when '
      'Smartschool asks for a code anyway (#41)', () {
    expect(Setting.mfa.required, isFalse);
    expect(
      text,
      contains(
        '**Alleen als je tweestapsverificatie gebruikt.** Vraagt Smartschool '
        'na je wachtwoord geen code uit een app, zoals bij de meeste '
        'leerlingen? Sla deze stap dan over en laat de **2FA-sleutel** in '
        'stap 3 leeg.',
      ),
    );
    expect(
      text,
      contains(
        '| **2FA-sleutel** (alleen met tweestapsverificatie) | De sleutel uit '
        'stap 2',
      ),
    );
    expect(
      text,
      contains(
        '### Smartschool vraagt een 2FA-code, maar de 2FA-sleutel is leeg',
      ),
    );
    final chatGpt = _read(_chatGptGuidePath).replaceAll(RegExp(r'\s+'), ' ');
    expect(chatGpt, contains('laat `SMARTSCHOOL_MFA` in stap 3 weg.'));
    expect(
      chatGpt,
      contains(
        '| `SMARTSCHOOL_MFA` | Alleen met tweestapsverificatie: je '
        '2FA-sleutel',
      ),
    );
    expect(settingHints[Setting.mfa], startsWith('alleen met 2FA: '));
  });

  test('gives the time and size limits of the server', () {
    expect(text, contains('${DownloadFolder.defaultRetention.inDays} dagen'));
    expect(text, contains('${maxIntradeskFileBytes ~/ (1024 * 1024)} MB'));
    expect(text, contains('${maxSavedFileBytes ~/ (1024 * 1024)} MB'));
  });

  group('the gradebook (Puntenboek), as its tools are built (#145)', () {
    final chatGpt = _read(_chatGptGuidePath).replaceAll(RegExp(r'\s+'), ' ');
    // Without the quote marks of the note on published evaluations; read in
    // the first test that needs it, as _subsection expects.
    late final section = _subsection(
      text,
      '### Puntenboek',
    ).replaceAll(' > ', ' ');
    final session = SmartschoolSession(const ExtensionSettings());
    tearDownAll(session.close);
    final create = createSkoreEvaluationTool(session).definition;
    final grades = saveSkoreGradesTool(session).definition;
    final feedback = saveSkoreFeedbackTool(session).definition;

    test('is for every account, without a switch, unlike Skore-beheer', () {
      final behindSwitch = {
        for (final optIn in [
          skoreOptIn(session, SwitchState.on),
          presenceOptIn(session, SwitchState.on),
        ])
          for (final tool in optIn.tools) tool.definition.name,
      };
      for (final tool in [create, grades, feedback]) {
        expect(behindSwitch, isNot(contains(tool.name)));
      }
      for (final guide in [text, chatGpt]) {
        final summary = guide.substring(0, guide.indexOf('## Inhoud'));
        expect(
          summary,
          allOf(
            contains('- **Puntenboek:** je eigen puntenboeken in Skore'),
            contains(
              'Dit is er voor elke leerkracht: je hoeft er niets voor aan te '
              'zetten.',
            ),
          ),
        );
      }
      expect(
        section,
        contains(
          'Voor elke leerkracht: je hoeft er niets voor aan te zetten, ook '
          'niet **Skore-beheer**.',
        ),
      );
      expect(
        text,
        contains('### Skore-beheer Alleen met **Skore-beheer** aan'),
      );
    });

    test('says a new evaluation is always unpublished, as the tool, which '
        'cannot publish, creates it', () {
      expect(create.description, contains('It is always created unpublished'));
      expect(create.description, contains('this tool cannot publish'));
      expect(
        create.inputSchema.properties!.keys,
        isNot(anyElement(contains('publi'))),
      );
      for (final guide in [text, chatGpt]) {
        expect(
          guide,
          contains(
            'Een nieuwe evaluatie blijft ongepubliceerd: je publiceert ze '
            'zelf in Smartschool.',
          ),
        );
      }
      expect(
        section,
        contains(
          'Een nieuwe evaluatie is altijd ongepubliceerd: je leerlingen zien '
          'ze pas als je ze zelf publiceert in Smartschool.',
        ),
      );
    });

    test('says pupils see grades and feedback in a published or scheduled '
        'evaluation, and that Claude asks first, as allow_published '
        'needs', () {
      for (final tool in [grades, feedback]) {
        expect(
          tool.inputSchema.properties!.keys,
          contains('allow_published'),
          reason: tool.name,
        );
        expect(
          tool.description,
          allOf(
            contains('the school sends them a notification'),
            contains('from its publication time on'),
            contains(
              'Pass allow_published: true only after telling the user '
              'exactly that and getting their explicit yes for it.',
            ),
          ),
          reason: tool.name,
        );
      }
      expect(
        section,
        contains(
          'Vult Claude punten of feedback in bij een evaluatie die al '
          'gepubliceerd is, dan zien je leerlingen die meteen, en krijgen ze '
          'een melding. Is de publicatie gepland, dan zien ze die vanaf dat '
          'moment. Claude zegt je dat eerst uitdrukkelijk en vraagt of het '
          'toch mag.',
        ),
      );
    });

    test('says feedback goes to one pupil at a time, and that Claude never '
        'changes a colleague\'s but reads it', () {
      expect(feedback.description, contains('One pupil per call'));
      expect(feedback.inputSchema.properties!['pupil_id'], {
        'type': 'integer',
        'description': isA<String>(),
        'minimum': 1,
      });
      expect(
        feedback.description,
        contains('Feedback that others gave the pupil is never changed.'),
      );
      expect(
        readSkoreFeedbackTool(session).definition.description,
        contains('every feedback text on it, whoever wrote it'),
      );
      expect(
        section,
        allOf(
          contains('Claude geeft feedback aan één leerling per keer'),
          contains('De feedback van een collega verandert Claude nooit.'),
          contains('ook die van collega\'s.'),
        ),
      );
    });

    test('says Claude cannot publish, delete or move an evaluation: no tool '
        'does', () {
      final manifest =
          jsonDecode(_read('manifest.json')) as Map<String, Object?>;
      expect(
        [
          for (final tool in manifest['tools'] as List)
            if (((tool as Map)['name'] as String).contains('evaluation'))
              tool['name'],
        ],
        ['list_skore_evaluations', 'create_skore_evaluation'],
      );
      expect(
        section,
        contains(
          'Een evaluatie publiceren, verwijderen of verplaatsen, of haar '
          'titel of datum aanpassen, kan Claude niet: dat doe je zelf in '
          'Smartschool.',
        ),
      );
    });

    test('says under Veiligheid en privacy that the grades and feedback go '
        'to the AI provider', () {
      for (final (guide, assistant) in [
        (text, 'Claude'),
        (chatGpt, 'ChatGPT'),
      ]) {
        expect(
          _section(guide, '## 8. Veiligheid en privacy'),
          contains(
            'Vraag je $assistant iets over je puntenboek, dan gaan ook de '
            'punten van je leerlingen naar $assistant, en de feedback die '
            'jij of collega\'s hun gaven. Ook dat zijn gegevens over '
            'leerlingen',
          ),
          reason: assistant,
        );
      }
    });
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
    expect(installNotesFile, '.github/release-notes.md');
    expect(_read(installNotesFile), contains('($_guideUrl)'));
    expect(
      releaseNotesFor(Directory.current, 'v$packageVersion'),
      contains('($_guideUrl)'),
    );
    expect(
      _read('.github/workflows/release.yml'),
      contains('dart run tool/release_notes.dart'),
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

    test('says under Bijwerken that the answer gives the download link of '
        'the exe and what is new, as the update notice does (#59)', () {
      final section = _section(
        chatGpt,
        '## 6. Bijwerken naar een nieuwe versie',
      );
      expect(
        section,
        contains(
          'een downloadlink naar `${UpdateChecker.exeAssetName}` en in een '
          'paar woorden wat er nieuw is.',
        ),
      );
      expect(
        section,
        contains('wat er nieuw is in elke versie die je overslaat'),
      );
      expect(section, contains('1. Klik op de downloadlink uit het antwoord'));
      expect(section, contains('`$_releases/`'));
      _expectNoticeGives(ClientApp.codex, UpdateChecker.exeAssetName);
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

/// The part of [text] (a guide with every run of white space as one space)
/// from [heading] up to the next heading of level 2.
String _section(String text, String heading) {
  final start = text.indexOf(heading);
  expect(start, isNonNegative, reason: heading);
  final end = text.indexOf(' ## ', start + heading.length);
  return text.substring(start, end < 0 ? text.length : end);
}

/// The part of [text] (a guide with every run of white space as one space)
/// from [heading], of level 3, up to the next heading of level 2 or 3.
String _subsection(String text, String heading) {
  final start = text.indexOf(heading);
  expect(start, isNonNegative, reason: heading);
  final end = text.indexOf(RegExp(' #{2,3} '), start + heading.length);
  return text.substring(start, end < 0 ? text.length : end);
}

/// Checks that the update notice in [app] gives what the guides say: the
/// download link of [asset], on GitHub's release pages, and what is new.
void _expectNoticeGives(ClientApp app, String asset) {
  final link = downloadLink('v9.9.9', asset);
  expect(link, startsWith('$_releases/'));
  final release = Release(
    Version(9, 9, 9),
    tag: 'v9.9.9',
    url: Uri.parse(releasePage('v9.9.9')),
    assets: {asset: Uri.parse(link)},
    notes: '- Iets nieuws.',
  );
  expect(
    UpdateChecker.howToUpdate(release, app),
    startsWith('Give the user this download link: $link\n'),
  );
  expect(
    UpdateChecker.whatIsNew([release], Version(0, 1, 0)),
    allOf(contains('Summarise it for the user'), endsWith('- Iets nieuws.')),
  );
}

/// The anchor GitHub gives a heading: lower case, without punctuation, with
/// spaces as hyphens.
String _gitHubAnchor(String heading) => heading
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true), '')
    .replaceAll(' ', '-');
