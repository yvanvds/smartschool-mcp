/// `tool/release_notes.dart`, which writes the notes of a release from
/// `CHANGELOG.md` and `.github/release-notes.md`, and the release workflow
/// that publishes them. The update check reads what is new from those notes.
library;

import 'dart:io';

import 'package:smartschool_mcp/src/update_check.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import '../tool/check_version.dart' show changelogFile, changelogSection;
import '../tool/release_notes.dart';
import 'support/fake_github.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// What [file] (a path from the project folder) imports or exports, and
/// what those imports import further on: the files of this project, as
/// paths from the project folder, and the other packages, as
/// `package:<name>` (not followed); `dart:` libraries are left out.
Set<String> _importGraph(String file) {
  final reached = <String>{};
  final todo = [file];
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!reached.add(path)) continue;
    for (final match in _directive.allMatches(_read(path))) {
      final uri = Uri.parse(match[1]!);
      if (uri.isScheme('dart')) continue;
      if (!uri.isScheme('package')) {
        todo.add(Uri.parse(path).resolveUri(uri).path);
      } else if (uri.pathSegments case ['smartschool_mcp', ...final rest]) {
        todo.add(['lib', ...rest].join('/'));
      } else {
        reached.add('package:${uri.pathSegments.first}');
      }
    }
  }
  return reached..remove(file);
}

/// An import or export directive, with its URI.
final _directive = RegExp(
  r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  test('the notes start with what is new in the version, from CHANGELOG.md, '
      'then how to install', () {
    final section = changelogSection(_read(changelogFile), packageVersion)!;

    final notes = releaseNotesFor(Directory.current, 'v$packageVersion');

    expect(
      notes,
      '${UpdateChecker.notesHeading}\n\n$section\n\n'
      '$installHeading\n\n${_read(installNotesFile).trim()}\n',
    );
    expect(
      releaseNotesFor(Directory.current, 'refs/tags/v$packageVersion'),
      notes,
    );
  });

  test('the update check takes exactly that section from the published '
      'notes (GitHub adds its own after them), as plain text', () {
    final section = changelogSection(_read(changelogFile), packageVersion)!;
    final body = releaseBody(
      'v$packageVersion',
      whatIsNew: section,
    ).replaceAll('\n', '\r\n');

    expect(body, contains("## What's Changed"));
    // The changelog quotes file names in backticks; plain text drops them.
    expect(UpdateChecker.notesSection(body), section.replaceAll('`', ''));
  });

  test('the tool compiles in seconds: of the server it imports only '
      'lib/src/release_notes.dart, which imports nothing, not '
      'update_check.dart and all of flutter_smartschool with it', () {
    final graph = _importGraph('tool/release_notes.dart');

    expect(graph.where((path) => path.startsWith('lib/')), [
      'lib/src/release_notes.dart',
    ]);
    expect(graph, isNot(contains('package:flutter_smartschool')));
    expect(_importGraph('lib/src/release_notes.dart'), isEmpty);
  });

  group('without a section for the version in CHANGELOG.md', () {
    late Directory project;

    setUp(() async {
      project = await Directory.systemTemp.createTemp('smartschool_mcp_rel_');
      addTearDown(() => project.delete(recursive: true));
      for (final file in [changelogFile, installNotesFile]) {
        final copy = File(
          [project.path, ...file.split('/')].join(Platform.pathSeparator),
        );
        copy.parent.createSync(recursive: true);
        File(file).copySync(copy.path);
      }
    });

    test('no notes: says what to write where', () {
      expect(
        () => releaseNotesFor(project, 'v99.0.0'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'CHANGELOG.md has no section "## 99.0.0": write what is new in '
                'this version there, in Dutch, for colleagues',
          ),
        ),
      );
    });

    // Each run JIT-compiles the tool: a few seconds, like check_version.dart,
    // now that it no longer compiles flutter_smartschool (#121, and the import
    // graph test above), which took 20 to 35 s a run on a loaded PC (#119).
    // The budget the e2e files get stays as a ceiling, not a need.
    test('run as a script: exits with 1 and writes nothing, so the release '
        'workflow stops; with a section it writes the notes', () async {
      final output = File(
        [project.path, 'notes.md'].join(Platform.pathSeparator),
      );
      Future<ProcessResult> run(String tag) =>
          Process.run(Platform.resolvedExecutable, [
            'run',
            'tool/release_notes.dart',
            '--root',
            project.path,
            '--tag',
            tag,
            '--output',
            output.path,
          ]);

      final missing = await run('v99.0.0');
      expect(missing.exitCode, 1);
      expect(
        missing.stderr,
        contains('CHANGELOG.md has no section "## 99.0.0"'),
      );
      expect(output.existsSync(), isFalse);

      final written = await run('v$packageVersion');
      expect(written.exitCode, 0, reason: '${written.stderr}');
      expect(
        output.readAsStringSync(),
        releaseNotesFor(Directory.current, 'v$packageVersion'),
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  test('the release workflow checks the changelog, writes the notes with '
      'the tool and publishes them, with the generated notes after them', () {
    final workflow = _read(
      '.github/workflows/release.yml',
    ).replaceAll(RegExp(r'\s+'), ' ');
    final check = workflow.indexOf(
      r'dart run tool/check_version.dart --tag "$env:TAG"',
    );
    final write = workflow.indexOf(
      r'dart run tool/release_notes.dart --tag "$env:TAG" --output '
      r'"$env:RUNNER_TEMP/release-notes.md"',
    );
    final publish = workflow.indexOf(
      r'--notes-file "$env:RUNNER_TEMP/release-notes.md" --generate-notes',
    );
    expect(check, isNonNegative);
    expect(write, greaterThan(check));
    expect(publish, greaterThan(write));
  });
}
