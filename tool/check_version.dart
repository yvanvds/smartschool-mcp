/// Checks that every file that carries the version carries the same one:
/// `version:` in `pubspec.yaml`, `packageVersion` in `lib/src/version.dart`
/// and `version` in `manifest.json`, and with `--tag` the release tag
/// (`vX.Y.Z`).
///
/// ```
/// dart run tool/check_version.dart [--tag v1.2.3] [--root <folder>]
/// ```
///
/// Exits with 1 and says what differs when they disagree, so the release
/// workflow stops before it builds anything. `test/version_test.dart` runs
/// the same check, so a pull request that bumps one file and not the others
/// fails CI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// The files that carry the version, relative to the project folder.
const versionFiles = ['pubspec.yaml', 'lib/src/version.dart', 'manifest.json'];

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
      '${versionFiles.join(', ')}${tag == null ? '' : ' and the tag'}:',
    );
    for (final problem in problems) {
      stderr.writeln('- $problem');
    }
    exit(1);
  }
  stdout.writeln(
    'Version check passed: ${versionFiles.join(', ')}'
    '${tag == null ? '' : ' and tag $tag'} agree.',
  );
}
