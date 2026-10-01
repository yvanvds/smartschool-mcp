import 'dart:io';

import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import '../tool/check_version.dart' show versionFiles, versionProblems;

void main() {
  test('packageVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(packageVersion, match!.group(1));
  });

  test('pubspec.yaml, version.dart and manifest.json carry the same '
      'version', () {
    expect(versionProblems(Directory.current), isEmpty);
  });

  group('tool/check_version.dart', () {
    late Directory project;

    /// [file] (one of [versionFiles]) in [project].
    File copied(String file) =>
        File([project.path, ...file.split('/')].join(Platform.pathSeparator));

    /// Replaces the version in the copy of [file] with [version].
    void setVersion(String file, String version) {
      final copy = copied(file);
      final pattern = switch (file) {
        'pubspec.yaml' => RegExp('^version: .*\$', multiLine: true),
        'manifest.json' => RegExp(r'"version": "[^"]*"'),
        _ => RegExp(r"packageVersion = '[^']*'"),
      };
      final replacement = switch (file) {
        'pubspec.yaml' => 'version: $version',
        'manifest.json' => '"version": "$version"',
        _ => "packageVersion = '$version'",
      };
      final text = copy.readAsStringSync();
      expect(text, contains(pattern), reason: file);
      copy.writeAsStringSync(text.replaceFirst(pattern, replacement));
    }

    setUp(() async {
      project = await Directory.systemTemp.createTemp('smartschool_mcp_ver_');
      addTearDown(() => project.delete(recursive: true));
      for (final file in versionFiles) {
        copied(file).parent.createSync(recursive: true);
        File(file).copySync(copied(file).path);
      }
    });

    test('accepts the release tag of the version, also as a tag ref', () {
      expect(versionProblems(project), isEmpty);
      expect(versionProblems(project, tag: 'v$packageVersion'), isEmpty);
      expect(
        versionProblems(project, tag: 'refs/tags/v$packageVersion'),
        isEmpty,
      );
    });

    test('a tag of another version, or without v: names the tag and what '
        'it should be', () {
      expect(versionProblems(project, tag: 'v99.0.0'), [
        'tag "v99.0.0" does not match pubspec.yaml $packageVersion, '
            'lib/src/version.dart $packageVersion, '
            'manifest.json $packageVersion',
      ]);
      expect(versionProblems(project, tag: packageVersion), [
        'tag "$packageVersion" does not start with v (vX.Y.Z)',
      ]);
    });

    for (final file in versionFiles) {
      test('$file with another version: names each file and its version', () {
        setVersion(file, '99.0.0');

        final problems = versionProblems(project, tag: 'v$packageVersion');

        expect(problems, hasLength(2));
        expect(problems.first, startsWith('the versions differ: '));
        expect(problems.first, contains('$file 99.0.0'));
        expect(
          problems.last,
          'tag "v$packageVersion" does not match $file 99.0.0',
        );
      });
    }

    test('a version that is not X.Y.Z, or a missing file', () {
      for (final file in versionFiles) {
        setVersion(file, 'next');
      }
      copied('manifest.json').deleteSync();

      final problems = versionProblems(project);

      expect(problems, [
        'pubspec.yaml: "next" is not a version (X.Y.Z)',
        'lib/src/version.dart: "next" is not a version (X.Y.Z)',
        startsWith('manifest.json: cannot be read ('),
      ]);
    });

    test('run as a script: exits with 1 and says what differs, so the '
        'release workflow stops; exits with 0 when all agree', () async {
      Future<ProcessResult> run(String tag) =>
          Process.run(Platform.resolvedExecutable, [
            'run',
            'tool/check_version.dart',
            '--root',
            project.path,
            '--tag',
            tag,
          ]);

      final wrong = await run('v99.0.0');
      expect(wrong.exitCode, 1);
      expect(wrong.stderr, contains('Version check failed.'));
      expect(wrong.stderr, contains('tag "v99.0.0" does not match'));

      final right = await run('v$packageVersion');
      expect(right.exitCode, 0, reason: '${right.stderr}');
      expect(right.stdout, contains('Version check passed'));
    });
  });
}
