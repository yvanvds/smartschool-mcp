/// Builds the folder of the Claude Desktop extension, ready for
/// `mcpb validate` and `mcpb pack`:
///
/// ```
/// dart run tool/build_bundle.dart [<folder>]
/// ```
///
/// Run it from the project folder. The folder (default `bundle`,
/// git-ignored) gets `manifest.json`, its icon,
/// `LICENSE`, and the server compiled with `dart compile exe` to the
/// manifest's `server.entry_point` (`server/smartschool-mcp.exe`). A folder
/// from an earlier build is emptied first. Refuses to build when the versions
/// disagree (`tool/check_version.dart`).
///
/// The release workflow (`.github/workflows/release.yml`) builds the
/// extension with this script, and `test/bundle_e2e_test.dart` builds one
/// with it and starts it the way Claude Desktop does.
library;

import 'dart:convert';
import 'dart:io';

import 'check_version.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1 || args.any((arg) => arg.startsWith('-'))) {
    stderr.writeln('usage: dart run tool/build_bundle.dart [<folder>]');
    exit(64);
  }
  final problems = versionProblems(Directory.current);
  if (problems.isNotEmpty) {
    stderr.writeln('Not building: ${problems.join('; ')}');
    exit(1);
  }

  final manifest =
      jsonDecode(File('manifest.json').readAsStringSync())
          as Map<String, Object?>;
  final server = manifest['server'] as Map<String, Object?>;
  final entryPoint = server['entry_point'] as String;
  final icon = manifest['icon'] as String;
  final files = ['manifest.json', icon, 'LICENSE'];

  final bundle = Directory(args.isEmpty ? 'bundle' : args.single).absolute;
  if (bundle.existsSync()) {
    // Only ever delete an earlier build: a folder that holds nothing but
    // what a build puts in it (never this project, nor another one).
    final built = {...files, entryPoint}.map((path) => path.split('/').first);
    final others = [
      for (final entity in bundle.listSync())
        if (!built.contains(
          entity.uri.pathSegments.lastWhere((name) => name.isNotEmpty),
        ))
          entity.path,
    ];
    if (others.isNotEmpty) {
      stderr.writeln(
        'Not building: ${bundle.path} is not an earlier build to replace '
        '(it holds ${others.first}).',
      );
      exit(1);
    }
    bundle.deleteSync(recursive: true);
  }
  bundle.createSync(recursive: true);

  for (final file in files) {
    _copy(File(file), bundle, file);
  }

  final executable = _inBundle(bundle, entryPoint);
  // dart compile exe does not create the folder.
  executable.parent.createSync(recursive: true);
  final compile = await Process.start(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'bin/smartschool_mcp.dart',
    '-o',
    executable.path,
  ], mode: ProcessStartMode.inheritStdio);
  final exitCode = await compile.exitCode;
  if (exitCode != 0) {
    stderr.writeln('dart compile exe failed (exit code $exitCode)');
    exit(exitCode);
  }
  stdout.writeln('Built the extension in ${bundle.path}');
}

/// [relativePath] (with `/`) inside [bundle].
File _inBundle(Directory bundle, String relativePath) => File(
  [bundle.path, ...relativePath.split('/')].join(Platform.pathSeparator),
);

void _copy(File source, Directory bundle, String relativePath) {
  final target = _inBundle(bundle, relativePath);
  target.parent.createSync(recursive: true);
  source.copySync(target.path);
}
