/// Writes the notes of a release, for the release workflow:
///
/// ```
/// dart run tool/release_notes.dart --tag v1.2.3 --output <file> [--root <folder>]
/// ```
///
/// The notes start with what is new in the version, for colleagues: its
/// section of `CHANGELOG.md` under [UpdateChecker.notesHeading], the section
/// the update notice of an older server shows. Then come the install
/// instructions of `.github/release-notes.md` under [installHeading].
/// `gh release create --generate-notes` adds GitHub's list of pull requests
/// after them.
///
/// Exits with 1 when `CHANGELOG.md` has no section for the version, and with
/// 64 on wrong arguments.
library;

import 'dart:io';

import 'package:smartschool_mcp/src/update_check.dart';

import 'check_version.dart';

/// The install instructions, the same for every release, relative to the
/// project folder.
const installNotesFile = '.github/release-notes.md';

/// The heading above [installNotesFile] in the notes. A heading of level 2,
/// so the update check takes nothing of it into what is new.
const installHeading = '## Installeren of bijwerken';

/// The notes of a release: [whatIsNew] (a section of `CHANGELOG.md`) under
/// [UpdateChecker.notesHeading], then [install] (the text of
/// [installNotesFile]) under [installHeading].
String releaseNotes({required String whatIsNew, required String install}) => [
  UpdateChecker.notesHeading,
  '',
  whatIsNew.trim(),
  '',
  installHeading,
  '',
  install.replaceAll('\r\n', '\n').trim(),
  '',
].join('\n');

/// The notes of the release of [tag] (`v1.2.3`, or `refs/tags/v1.2.3`) of
/// the project at [root]; throws a [StateError] that says what is missing
/// when `CHANGELOG.md` has no section for the version.
String releaseNotesFor(Directory root, String tag) {
  final version = tag.replaceFirst(RegExp('^refs/tags/'), '').substring(1);
  String read(String path) => File(
    [root.path, ...path.split('/')].join(Platform.pathSeparator),
  ).readAsStringSync();
  final section = changelogSection(read(changelogFile), version);
  if (section == null) {
    throw StateError(
      '$changelogFile has no section "## $version": write what is new in '
      'this version there, in Dutch, for colleagues',
    );
  }
  return releaseNotes(whatIsNew: section, install: read(installNotesFile));
}

void main(List<String> args) {
  const usage =
      'usage: dart run tool/release_notes.dart --tag vX.Y.Z --output <file> '
      '[--root <folder>]';
  String? tag;
  String? output;
  var root = '.';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag' when i + 1 < args.length:
        tag = args[++i];
      case '--output' when i + 1 < args.length:
        output = args[++i];
      case '--root' when i + 1 < args.length:
        root = args[++i];
      default:
        stderr.writeln('unknown argument: ${args[i]}\n$usage');
        exit(64);
    }
  }
  if (tag == null ||
      output == null ||
      !tag.replaceFirst(RegExp('^refs/tags/'), '').startsWith('v')) {
    stderr.writeln(usage);
    exit(64);
  }
  final String notes;
  try {
    notes = releaseNotesFor(Directory(root), tag);
  } on StateError catch (error) {
    stderr.writeln('Release notes not written: ${error.message}.');
    exit(1);
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Release notes not written: cannot read ${error.path}: '
      '${error.message}.',
    );
    exit(1);
  }
  File(output).writeAsStringSync(notes);
  stdout.writeln('Release notes of $tag written to $output.');
}
