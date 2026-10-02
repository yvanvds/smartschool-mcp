/// Checks that every file that carries the version carries the same one:
/// `version:` in `pubspec.yaml`, `packageVersion` in `lib/src/version.dart`
/// and `version` in `manifest.json`, and with `--tag` the release tag
/// (`vX.Y.Z`); and that `CHANGELOG.md` says what is new in that version.
///
/// ```
/// dart run tool/check_version.dart [--tag v1.2.3] [--root <folder>]
/// ```
///
/// Exits with 1 and says what differs when they disagree, or that the
/// section in `CHANGELOG.md` is missing, so the release workflow stops before
/// it builds anything. `test/version_test.dart` runs
/// the same check, so a pull request that bumps one file and not the others
/// fails CI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// The files that carry the version, relative to the project folder.
const versionFiles = ['pubspec.yaml', 'lib/src/version.dart', 'manifest.json'];

/// What is new in each version, in Dutch, for colleagues: a section under a
/// heading `## X.Y.Z` per version, relative to the project folder. The
/// release workflow puts the section of the released version at the top of
/// the release notes (`tool/release_notes.dart`), and the update notice of an
/// older server shows it.
const changelogFile = 'CHANGELOG.md';

/// The section of [version] in [changelog] (the text of [changelogFile]):
/// the lines under the heading `## <version>` up to the next heading of
/// level 1 or 2, without the blank lines around them; null when there is no
/// such heading or nothing under it.
String? changelogSection(String changelog, String version) {
  final lines = changelog.replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexWhere((line) => line.trim() == '## $version');
  if (start < 0) return null;
  final section = lines
      .skip(start + 1)
      .takeWhile((line) => !RegExp(r'^ {0,3}#{1,2}(\s|$)').hasMatch(line))
      .join('\n')
      .trim();
  return section.isEmpty ? null : section;
}

/// What is wrong with the versions in the project at [root]; empty when they
/// are valid and all the same (and equal to [tag], when given).
///
/// [tag] is a release tag (`v1.2.3`) or a full tag ref
/// (`refs/tags/v1.2.3`).
List<String> versionProblems(Directory root, {String? tag}) {
  final problems = <String>[];
  final versions = <String, String>{};
  for (final file in versionFiles) {
    try {
      final version = _readVersion(
        File([root.path, ...file.split('/')].join(Platform.pathSeparator)),
      );
      if (version == null) {
        problems.add('$file: no version found');
        continue;
      }
      versions[file] = version;
      try {
        Version.parse(version);
      } on FormatException {
        problems.add('$file: "$version" is not a version (X.Y.Z)');
      }
    } on Object catch (error) {
      problems.add('$file: cannot be read ($error)');
    }
  }
  if (versions.values.toSet().length > 1) {
    problems.add(
      'the versions differ: '
      '${versions.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
    );
  }
  // Only for a valid version that all files agree on: otherwise the problem
  // is in the files.
  final distinct = versions.values.toSet();
  if (problems.isEmpty && distinct.length == 1) {
    problems.addAll(_changelogProblems(root, distinct.single));
  }
  if (tag != null) {
    final name = tag.replaceFirst(RegExp('^refs/tags/'), '');
    if (!name.startsWith('v')) {
      problems.add('tag "$name" does not start with v (vX.Y.Z)');
    } else {
      final differing = [
        for (final MapEntry(key: file, value: version) in versions.entries)
          if (version != name.substring(1)) '$file $version',
      ];
      if (differing.isNotEmpty) {
        problems.add('tag "$name" does not match ${differing.join(', ')}');
      }
    }
  }
  return problems;
}

/// What is wrong with the section of [version] in [changelogFile] in [root].
List<String> _changelogProblems(Directory root, String version) {
  final file = File(
    [root.path, ...changelogFile.split('/')].join(Platform.pathSeparator),
  );
  try {
    if (changelogSection(file.readAsStringSync(), version) == null) {
      return [
        '$changelogFile: no section "## $version" with what is new in this '
            'version, in Dutch, for colleagues',
      ];
    }
    return const [];
  } on Object catch (error) {
    return ['$changelogFile: cannot be read ($error)'];
  }
}

String? _readVersion(File file) {
  final text = file.readAsStringSync();
  return switch (file.uri.pathSegments.last) {
    'pubspec.yaml' => switch (loadYaml(text)) {
      {'version': final Object version} => '$version',
      _ => null,
    },
    'manifest.json' => switch (jsonDecode(text)) {
      {'version': final String version} => version,
      _ => null,
    },
    _ => RegExp(
      r"""^const String packageVersion = ['"]([^'"]*)['"];""",
      multiLine: true,
    ).firstMatch(text)?.group(1),
  };
}

void main(List<String> args) {
  String? tag;
  var root = '.';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag' when i + 1 < args.length:
        tag = args[++i];
      case '--root' when i + 1 < args.length:
        root = args[++i];
      default:
        stderr.writeln(
          'unknown argument: ${args[i]}\n'
          'usage: dart run tool/check_version.dart [--tag vX.Y.Z] '
          '[--root <folder>]',
        );
        exit(64);
    }
  }
  final problems = versionProblems(Directory(root), tag: tag);
  if (problems.isNotEmpty) {
    stderr.writeln(
      'Version check failed. Keep the version the same in '
      '${versionFiles.join(', ')}${tag == null ? '' : ' and the tag'}, and '
      'say what is new in it in $changelogFile:',
    );
    for (final problem in problems) {
      stderr.writeln('- $problem');
    }
    exit(1);
  }
  stdout.writeln(
    'Version check passed: ${versionFiles.join(', ')}'
    '${tag == null ? '' : ' and tag $tag'} agree, and $changelogFile says '
    'what is new.',
  );
}
