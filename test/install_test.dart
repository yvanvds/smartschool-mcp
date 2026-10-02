/// The installer for ChatGPT and Codex, on files standing in for the
/// executable. `test/install_e2e_test.dart` runs the compiled one.
@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smartschool_mcp/src/install.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

final _sep = Platform.pathSeparator;

void main() {
  late Directory root;
  late String directory;
  late File source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('smartschool_install_');
    addTearDown(() => root.delete(recursive: true));
    directory = '${root.path}${_sep}Programs${_sep}smartschool-mcp';
    source = File('${root.path}${_sep}Downloads${_sep}smartschool-mcp.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('version 2');
  });

  String target() => '$directory$_sep$installedName';

  List<String> namesIn(String path) => [
    for (final entity in Directory(path).listSync())
      entity.uri.pathSegments.last,
  ]..sort();

  test('the folder is Programs\\smartschool-mcp in LOCALAPPDATA', () {
    expect(
      installDirectory({'LOCALAPPDATA': r'C:\Users\jan\AppData\Local'}),
      r'C:\Users\jan\AppData\Local\Programs\smartschool-mcp',
    );
    expect(installDirectory({}), isNull);
    expect(installDirectory({'LOCALAPPDATA': '  '}), isNull);
  });

  group('installExecutable', () {
    test('copies the executable into a new folder', () async {
      final installation = await installExecutable(source.path, directory);

      expect(installation.path, target());
      expect(installation.copied, isTrue);
      expect(installation.replaced, isFalse);
      expect(File(target()).readAsStringSync(), 'version 2');
      expect(namesIn(directory), [installedName]);
    });

    test('replaces an earlier copy and leaves nothing else', () async {
      File(target())
        ..createSync(recursive: true)
        ..writeAsStringSync('version 1');

      final installation = await installExecutable(source.path, directory);

      expect(installation.replaced, isTrue);
      expect(File(target()).readAsStringSync(), 'version 2');
      expect(namesIn(directory), [installedName]);
    });

    test('run from the installed copy: nothing to copy', () async {
      await installExecutable(source.path, directory);

      final again = await installExecutable(target(), directory);

      expect(again.path, target());
      expect(again.copied, isFalse);
      expect(again.replaced, isFalse);
      expect(namesIn(directory), [installedName]);
    });

    test('a copy that cannot be made leaves the earlier one in place, and '
        'no half-written file', () async {
      File(target())
        ..createSync(recursive: true)
        ..writeAsStringSync('version 1');

      await expectLater(
        installExecutable('${root.path}${_sep}missing.exe', directory),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(target()).readAsStringSync(), 'version 1');
      expect(namesIn(directory), [installedName]);
    });
  });

  test('deleteReplacedCopies deletes only the copies an update moved '
      'aside', () async {
    Directory(directory).createSync(recursive: true);
    const others = [
      installedName,
      '$installedName.0123456789abcdef.new',
      '$installedName.old',
      'notes.txt',
    ];
    for (final name in [...others, '$installedName.0123456789abcdef.old']) {
      File('$directory$_sep$name').writeAsStringSync(name);
    }

    await deleteReplacedCopies(directory);

    expect(namesIn(directory), [...others]..sort());
    await deleteReplacedCopies('${root.path}${_sep}nothing-here');
  });

  group('installInstructions', () {
    const path =
        r'C:\Users\jan\AppData\Local\Programs\smartschool-mcp'
        r'\smartschool-mcp.exe';

    test('say, in Dutch, how to add the server in ChatGPT: its name, the '
        'command, no arguments and every setting with what goes in '
        'it', () {
      final text = installInstructions(
        const Installation(path, copied: true, replaced: false),
        onClipboard: true,
      );

      expect(text, startsWith('Smartschool voor ChatGPT, versie '));
      expect(text, contains(packageVersion));
      expect(text, contains('Geïnstalleerd in: $path\n'));
      expect(text, contains('Dat pad staat ook op je klembord.'));
      expect(text, contains('Voeg Smartschool nu zo toe in de ChatGPT-app:'));
      expect(text, contains('Aangepaste MCP-server maken'));
      expect(text, contains('Naam: smartschool.'));
      expect(text, contains('plak het pad (Ctrl+V)\n   $path\n'));
      expect(text, contains('Argumenten: geen.'));
      for (final setting in Setting.values) {
        expect(
          text,
          matches(
            RegExp(
              '\n   ${setting.envVar} +${RegExp.escape(settingHints[setting]!)}'
              '\n',
            ),
          ),
          reason: setting.name,
        );
      }
      expect(text, contains('Werkt mijn Smartschool-verbinding?'));
      expect(text, endsWith(chatGptGuideUrl));
    });

    test('ask, before the steps, for a paid plan and for model training to '
        'be off (#50)', () {
      for (final installation in const [
        Installation(path, copied: true, replaced: false),
        Installation(path, copied: true, replaced: true),
        Installation(path, copied: false, replaced: false),
      ]) {
        final text = installInstructions(installation, onClipboard: false);
        final warning = privacyWarning.join('\n');
        expect(text, contains('\n$warning\n'));
        expect(text.indexOf(warning), lessThan(text.indexOf('1. Open')));
      }
      final warning = privacyWarning.join(' ');
      expect(warning, contains('gevoelige gegevens over leerlingen'));
      expect(warning, contains('betalend ChatGPT-abonnement'));
      expect(warning, contains('(Improve the model for everyone) uit'));
    });

    test('an update says the settings in ChatGPT stay; a second run that '
        'the server is already installed', () {
      final update = installInstructions(
        const Installation(path, copied: true, replaced: true),
        onClipboard: false,
      );
      expect(update, contains('Je instellingen in ChatGPT blijven bewaard.'));
      expect(update, isNot(contains('klembord')));
      expect(update, isNot(contains('Ctrl+V')));

      final again = installInstructions(
        const Installation(path, copied: false, replaced: false),
        onClipboard: false,
      );
      expect(again, contains('Smartschool is al geïnstalleerd in: $path'));
      expect(again, contains('Staat Smartschool nog niet in ChatGPT?'));
    });
  });

  group('runInstaller', () {
    /// Runs the installer with [environment] as if it were [source]; returns
    /// the exit code and what it wrote.
    Future<(int, String)> run(
      String source,
      Map<String, String> environment,
    ) async {
      final output = _Output();
      final sink = IOSink(output);
      final code = await runInstaller(
        out: sink,
        interactive: false,
        clipboard: false,
        environment: environment,
        source: source,
      );
      await sink.close();
      return (code, output.text);
    }

    test('installs into LOCALAPPDATA and shows the instructions', () async {
      final (code, text) = await run(source.path, {'LOCALAPPDATA': root.path});

      final installed =
          '${root.path}${_sep}Programs${_sep}smartschool-mcp$_sep'
          '$installedName';
      expect(code, 0);
      expect(File(installed).readAsStringSync(), 'version 2');
      expect(text, contains('Geïnstalleerd in: $installed\n'));
    });

    test('refuses without LOCALAPPDATA, or when run with dart run', () async {
      final (noFolder, why) = await run(source.path, {});
      expect(noFolder, 1);
      expect(why, contains('LOCALAPPDATA ontbreekt'));

      final (fromDart, how) = await run(r'C:\tools\dart-sdk\bin\dart.exe', {
        'LOCALAPPDATA': root.path,
      });
      expect(fromDart, 1);
      expect(how, contains('alleen vanuit het gecompileerde'));
      expect(Directory('${root.path}${_sep}Programs').existsSync(), isFalse);
    });

    test('reports a copy that fails, without a stack trace', () async {
      final (code, text) = await run('${root.path}${_sep}missing.exe', {
        'LOCALAPPDATA': root.path,
      });

      expect(code, 1);
      expect(text, startsWith('Installeren lukte niet: $installedName kon'));
      expect(text, isNot(contains('#0')));
    });
  });
}

/// Collects what is written to an [IOSink].
final class _Output implements StreamConsumer<List<int>> {
  final _bytes = BytesBuilder();

  String get text => utf8.decode(_bytes.toBytes()).replaceAll('\r\n', '\n');

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.add);

  @override
  Future<void> close() async {}
}
