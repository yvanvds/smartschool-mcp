/// The colleague guide `docs/installatie.md` against the server: it must use
/// the names colleagues see (the install form's field titles, the release
/// asset, the question that runs `smartschool_status`) and say what the server
/// keeps where, as the server does it; its links within the page must work;
/// and the README, the release notes and the extension manifest must link to
/// it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';

const _guidePath = 'docs/installatie.md';
const _repository = 'https://github.com/yvanvds/smartschool-mcp';
const _guideUrl = '$_repository/blob/main/$_guidePath';
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

  test('gives the time and size limits of the server', () {
    expect(text, contains('${DownloadFolder.defaultRetention.inDays} dagen'));
    expect(text, contains('${maxIntradeskFileBytes ~/ (1024 * 1024)} MB'));
    expect(text, contains('${maxSavedFileBytes ~/ (1024 * 1024)} MB'));
  });

  test('links only to headings on the page that exist', () {
    final anchors = {
      for (final match in RegExp(
        r'^#{1,6} (.+)$',
        multiLine: true,
      ).allMatches(guide))
        _gitHubAnchor(match.group(1)!),
    };
    final links = [
      for (final match in RegExp(r'\]\(#([^)]+)\)').allMatches(guide))
        match.group(1)!,
    ];
    expect(links, isNotEmpty);
    for (final link in links) {
      expect(anchors, contains(link), reason: '#$link');
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
}

/// The anchor GitHub gives a heading: lower case, without punctuation, with
/// spaces as hyphens.
String _gitHubAnchor(String heading) => heading
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true), '')
    .replaceAll(' ', '-');
