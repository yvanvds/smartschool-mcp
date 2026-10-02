import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

final _sep = Platform.pathSeparator;

void main() {
  late Directory root;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('smartschool_downloads_');
    addTearDown(() => root.delete(recursive: true));
    now = DateTime.utc(2026, 3, 2, 9);
  });

  String inRoot(String name) => '${root.path}$_sep$name';

  DownloadFolder folderAt(String path) => DownloadFolder(
    path,
    origin: DownloadFolderOrigin('set in a test', fix: 'pick another'),
    clock: () => now,
  );

  /// Saves [content] as [name] in [folder].
  Future<SavedFile> save(DownloadFolder folder, String? name, String content) =>
      folder.save((temporary) async {
        await temporary.writeAsString(content);
        return name;
      }, fallbackName: 'bestand');

  /// The names in [directory], sorted.
  List<String> names(String directory) => [
    for (final entity in Directory(directory).listSync())
      entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
  ]..sort();

  Map<String, Object?> manifest(String directory) =>
      jsonDecode(
            File(
              '$directory$_sep${DownloadFolder.manifestName}',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  group('resolve', () {
    late File credentials;

    setUp(() {
      credentials = File(inRoot('credentials.yml'))
        ..writeAsStringSync(
          'username: jan.peeters\n'
          'password: $fakePassword\n'
          'main_url: $fakeHost\n'
          'mfa: $fakeTotpSecret\n'
          'download_dir: ${inRoot('uit het bestand')}\n',
        );
    });

    test('the extension setting, when filled in', () {
      final folder = DownloadFolder.resolve(
        const ExtensionSettings(),
        environment: {
          'SMARTSCHOOL_DOWNLOAD_DIR': ' ${inRoot('Cowork')} ',
          'USERPROFILE': root.path,
        },
      )!;

      expect(folder.path, inRoot('Cowork'));
      expect(
        folder.origin.label,
        'set in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)',
      );
      expect(
        folder.origin.fix,
        'choose another folder in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR) '
        'in the Smartschool extension settings in Claude Desktop (Settings → '
        'Extensions), then restart Claude Desktop',
      );
    });

    test('worded for the app the server runs in, which is known only after '
        'the folder was resolved', () {
      final client = ClientContext();
      final folder = DownloadFolder.resolve(
        ExtensionSettings(client: client),
        environment: {'SMARTSCHOOL_DOWNLOAD_DIR': inRoot('Cowork')},
      )!;

      client.app = ClientApp.codex;

      expect(
        folder.origin.label,
        'set in SMARTSCHOOL_DOWNLOAD_DIR ("Downloadmap")',
      );
      expect(
        folder.origin.fix,
        'choose another folder in SMARTSCHOOL_DOWNLOAD_DIR ("Downloadmap") '
        "in the ChatGPT app, under Instellingen (Settings) → Plug-ins → MCP's "
        '→ smartschool → Omgevingsvariabelen (Environment variables); in the '
        'Codex CLI or IDE extension, under [mcp_servers.smartschool.env] in '
        r'%USERPROFILE%\.codex\config.toml, then restart ChatGPT (or Codex)',
      );
    });

    test('empty, or without the setting: the default in Downloads', () {
      for (final value in [null, '', '   ']) {
        final folder = DownloadFolder.resolve(
          const ExtensionSettings(),
          environment: {
            'SMARTSCHOOL_DOWNLOAD_DIR': ?value,
            'USERPROFILE': root.path,
            'HOME': root.path,
          },
        )!;
        expect(folder.path, inRoot('Downloads${_sep}Smartschool'));
        expect(folder.origin.label, 'the default');
      }
    });

    test('a path in quotes, as Windows copies it, is the path', () {
      final folder = DownloadFolder.resolve(
        const ExtensionSettings(),
        environment: {'SMARTSCHOOL_DOWNLOAD_DIR': '"${inRoot('Map A')}"'},
      )!;
      expect(folder.path, inRoot('Map A'));
    });

    test('with a credentials file: its download_dir, unless the environment '
        'variable is set', () {
      final source = CredentialsFile(credentials.path);

      final fromFile = DownloadFolder.resolve(source, environment: {})!;
      expect(fromFile.path, inRoot('uit het bestand'));
      expect(
        fromFile.origin.label,
        'set in download_dir in the credentials file ${credentials.path}',
      );
      expect(
        fromFile.origin.fix,
        'set SMARTSCHOOL_DOWNLOAD_DIR, or download_dir in the credentials '
        'file ${credentials.path}, to another folder, then restart the server',
      );

      final fromVariable = DownloadFolder.resolve(
        source,
        environment: {'SMARTSCHOOL_DOWNLOAD_DIR': inRoot('test')},
      )!;
      expect(fromVariable.path, inRoot('test'));
      expect(fromVariable.origin.label, 'set in SMARTSCHOOL_DOWNLOAD_DIR');
    });

    test('a credentials file without download_dir, or one that cannot be '
        'read: the default', () {
      credentials.writeAsStringSync(
        'username: jan\npassword: [$fakePassword\n',
      );
      for (final source in [
        CredentialsFile(credentials.path),
        CredentialsFile(inRoot('missing.yml')),
      ]) {
        final folder = DownloadFolder.resolve(
          source,
          environment: {'USERPROFILE': root.path, 'HOME': root.path},
        )!;
        expect(folder.path, inRoot('Downloads${_sep}Smartschool'));
        expect(folder.origin.label, 'the default');
      }
    });

    test('without a setting or a home folder: none', () {
      expect(
        DownloadFolder.resolve(const ExtensionSettings(), environment: {}),
        isNull,
      );
    });

    test('downloadDir is an optional setting, not one to log in with', () {
      expect(Setting.downloadDir.required, isFalse);
      expect(Setting.login, [
        Setting.mainUrl,
        Setting.username,
        Setting.password,
        Setting.mfa,
      ]);
      expect(
        const ExtensionSettings().name(Setting.downloadDir),
        '"Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)',
      );
    });
  });

  group('check', () {
    test('an existing folder: writable, and nothing is left in it', () async {
      final state = await folderAt(root.path).check();

      expect(state.writable, isTrue);
      expect(state.exists, isTrue);
      expect(names(root.path), isEmpty);
    });

    test('a folder that does not exist yet: writable, as it can be created; '
        'it is not created', () async {
      final path = inRoot('a${_sep}b');
      final state = await folderAt(path).check();

      expect(state.writable, isTrue);
      expect(state.exists, isFalse);
      expect(Directory(inRoot('a')).existsSync(), isFalse);
    });

    test('a file, or a folder under a file: not writable, with why', () async {
      File(inRoot('bestand')).writeAsStringSync('x');

      final file = await folderAt(inRoot('bestand')).check();
      expect(file.writable, isFalse);
      expect(file.problem, 'it is a file, not a folder');

      final under = await folderAt(inRoot('bestand${_sep}map')).check();
      expect(under.writable, isFalse);
      expect(
        under.problem,
        'it cannot be created: ${inRoot('bestand')} is a file, not a folder',
      );
    });
  });

  group('save', () {
    test('creates the folder and saves the file under its name, listing it '
        'as saved', () async {
      final path = inRoot('Downloads${_sep}Smartschool');
      final folder = folderAt(path);

      final saved = await save(folder, 'uitstap.docx', 'inhoud');

      expect(saved.path, '$path${_sep}uitstap.docx');
      expect(saved.name, 'uitstap.docx');
      expect(saved.size, 6);
      expect(saved.notes, isEmpty);
      expect(File(saved.path).readAsStringSync(), 'inhoud');
      expect(names(path), [DownloadFolder.manifestName, 'uitstap.docx']);
      final stat = File(saved.path).statSync();
      expect(manifest(path), {
        'format': DownloadFolder.manifestFormat,
        'about': contains('never touches other files'),
        'cleaned_at': now.toIso8601String(),
        'files': [
          {
            'name': 'uitstap.docx',
            'saved_at': now.toIso8601String(),
            'size': 6,
            'modified': stat.modified.microsecondsSinceEpoch,
          },
        ],
      });
    });

    test('never replaces a file: a taken name gets (2), (3), ..., also when '
        'only the case differs or a folder has it', () async {
      final folder = folderAt(root.path);
      File(inRoot('uitstap.docx')).writeAsStringSync('van de leraar');
      Directory(inRoot('uitstap (3).docx')).createSync();

      final second = await save(folder, 'uitstap.docx', 'twee');
      final third = await save(folder, 'UITSTAP.docx', 'drie');

      expect(second.name, 'uitstap (2).docx');
      expect(second.notes, [
        'A file named "uitstap.docx" was already in the download folder, so '
            'this one was saved as "uitstap (2).docx"; the other file was not '
            'changed.',
      ]);
      expect(third.name, 'UITSTAP (4).docx');
      expect(File(inRoot('uitstap.docx')).readAsStringSync(), 'van de leraar');
      expect(File(second.path).readAsStringSync(), 'twee');
      expect(File(third.path).readAsStringSync(), 'drie');
      expect(
        [
          for (final file in manifest(root.path)['files'] as List)
            (file as Map)['name'],
        ],
        ['uitstap (2).docx', 'UITSTAP (4).docx'],
      );
    });

    test(
      'an unsafe name is made safe, with a note; no name: the fallback',
      () async {
        final folder = folderAt(inRoot('map'));

        final unsafe = await save(folder, r'..\..\evil:1.pdf', 'x');
        final none = await save(folder, null, 'y');

        expect(unsafe.name, '.._.._evil_1.pdf');
        expect(unsafe.path, inRoot('map$_sep.._.._evil_1.pdf'));
        expect(unsafe.notes, [
          r'The file name Smartschool gives, "..\..\evil:1.pdf", cannot be '
              'used as it is (it holds characters a file name cannot have), so '
              'it was saved as ".._.._evil_1.pdf".',
        ]);
        expect(none.name, 'bestand');
        expect(none.notes, [
          'Smartschool gave no file name, so it was saved as "bestand".',
        ]);
        expect(names(root.path), ['map']);
      },
    );

    test('when writing fails, the temporary file is deleted and the error '
        'passed on; nothing is listed', () async {
      final folder = folderAt(root.path);

      await expectLater(
        folder.save((temporary) async {
          await temporary.writeAsString('half');
          throw const ToolError('too large');
        }, fallbackName: 'bestand'),
        throwsA(
          isA<ToolError>().having((e) => e.message, 'message', 'too large'),
        ),
      );

      expect(names(root.path), isEmpty);
    });

    test('a folder that cannot be created: an error that says how to choose '
        'another, and no download', () async {
      File(inRoot('bestand')).writeAsStringSync('x');
      final path = inRoot('bestand${_sep}map');
      var written = false;

      await expectLater(
        folderAt(path).save((temporary) async {
          written = true;
          return 'a.pdf';
        }, fallbackName: 'bestand'),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('The download folder $path cannot be created ('),
              endsWith('). To save files, pick another.'),
            ),
          ),
        ),
      );
      expect(written, isFalse);
    });

    test('is written under a temporary name until complete', () async {
      final folder = folderAt(root.path);
      late List<String> whileWriting;

      await folder.save((temporary) async {
        await temporary.writeAsString('inhoud');
        whileWriting = names(root.path);
        return 'brief.pdf';
      }, fallbackName: 'bestand');

      expect(whileWriting, [
        matches(RegExp(r'^\.smartschool-mcp-[0-9a-f]{16}\.part$')),
      ]);
      expect(names(root.path), [DownloadFolder.manifestName, 'brief.pdf']);
    });

    test('saves at the same time all get a name of their own and are all '
        'listed', () async {
      final folder = folderAt(root.path);

      final saved = await Future.wait([
        for (var i = 0; i < 5; i++) save(folder, 'brief.pdf', '$i'),
      ]);

      expect(saved.map((s) => s.name).toSet(), hasLength(5));
      expect(manifest(root.path)['files'] as List, hasLength(5));
    });
  });

  group('cleanUp', () {
    late DownloadFolder folder;

    setUp(() => folder = folderAt(root.path));

    test('deletes the files it saved more than 7 days ago, and never touches '
        'another file in the folder', () async {
      File(inRoot('van de leraar.pdf')).writeAsStringSync('blijft');
      File(inRoot('oud.pdf')).writeAsStringSync('ook van de leraar');
      Directory(inRoot('submap')).createSync();
      File(inRoot('submap${_sep}oud.pdf')).writeAsStringSync('ook');
      final old = await save(folder, 'oud.pdf', 'oud');
      now = now.add(const Duration(days: 3));
      final recent = await save(folder, 'recent.pdf', 'recent');

      now = now.add(const Duration(days: 4, minutes: 1));
      expect(await folder.cleanUp(), 1);

      expect(old.name, 'oud (2).pdf');
      expect(File(old.path).existsSync(), isFalse);
      expect(File(recent.path).readAsStringSync(), 'recent');
      expect(names(root.path), [
        DownloadFolder.manifestName,
        'oud.pdf',
        'recent.pdf',
        'submap',
        'van de leraar.pdf',
      ]);
      expect(File(inRoot('oud.pdf')).readAsStringSync(), 'ook van de leraar');
      expect(File(inRoot('submap${_sep}oud.pdf')).readAsStringSync(), 'ook');
      expect(manifest(root.path)['files'], [
        containsPair('name', 'recent.pdf'),
      ]);
      expect(manifest(root.path)['cleaned_at'], now.toIso8601String());
    });

    test(
      'runs at most once a day, also as another process, unless forced',
      () async {
        final saved = await save(folder, 'a.pdf', 'a');
        now = now.add(const Duration(days: 6, hours: 12));
        // Runs, but nothing is old enough.
        expect(await folder.cleanUp(), 0);
        expect(File(saved.path).existsSync(), isTrue);

        // Old enough now, but the last cleanup is 13 hours ago.
        now = now.add(const Duration(hours: 13));
        expect(await folder.cleanUp(), 0);
        // Another process: the list says when the last cleanup was.
        expect(await folderAt(root.path).cleanUp(), 0);
        expect(File(saved.path).existsSync(), isTrue);
        expect(await folder.cleanUp(force: true), 1);
        expect(File(saved.path).existsSync(), isFalse);

        final next = await save(folder, 'b.pdf', 'b');
        now = now.add(const Duration(days: 7, hours: 1));
        expect(await folderAt(root.path).cleanUp(), 1);
        expect(File(next.path).existsSync(), isFalse);
      },
    );

    test('a saved file the teacher changed or replaced is left alone and '
        'taken off the list; one that is gone too', () async {
      final changed = await save(folder, 'gewijzigd.docx', 'eerst');
      final replaced = await save(folder, 'vervangen.docx', 'eerst');
      final gone = await save(folder, 'weg.docx', 'eerst');
      File(changed.path).writeAsStringSync('nieuw, langer');
      File(replaced.path)
        ..deleteSync()
        ..writeAsStringSync('ander');
      File(gone.path).deleteSync();
      // Same size, but changed later.
      File(
        replaced.path,
      ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

      now = now.add(const Duration(days: 8));
      expect(await folder.cleanUp(), 0);

      expect(File(changed.path).readAsStringSync(), 'nieuw, langer');
      expect(File(replaced.path).readAsStringSync(), 'ander');
      expect(manifest(root.path)['files'], isEmpty);
    });

    test('a file it cannot delete now stays on the list', () async {
      final saved = await save(folder, 'open.xlsx', 'x');
      final open = File(saved.path).openSync(mode: FileMode.append);
      addTearDown(open.closeSync);
      now = now.add(const Duration(days: 8));

      final removed = await folder.cleanUp();

      if (Platform.isWindows) {
        // Windows does not delete a file that a program has open.
        expect(removed, 0);
        expect(manifest(root.path)['files'], [
          containsPair('name', 'open.xlsx'),
        ]);
      } else {
        expect(removed, 1);
      }
    });

    test(
      'a list naming a path outside the folder deletes nothing there',
      () async {
        final outside = File(inRoot('buiten.txt'))..writeAsStringSync('x');
        final inside = Directory(inRoot('downloads'))..createSync();
        final stat = outside.statSync();
        File(
          '${inside.path}$_sep${DownloadFolder.manifestName}',
        ).writeAsStringSync(
          jsonEncode({
            'format': DownloadFolder.manifestFormat,
            'files': [
              for (final name in ['..${_sep}buiten.txt', '../buiten.txt', '..'])
                {
                  'name': name,
                  'saved_at': '2020-01-01T00:00:00.000Z',
                  'size': stat.size,
                  'modified': stat.modified.microsecondsSinceEpoch,
                },
            ],
          }),
        );

        expect(await folderAt(inside.path).cleanUp(), 0);
        expect(outside.existsSync(), isTrue);
      },
    );

    test('deletes its own temporary files left behind for a day, never '
        'others', () async {
      final stale = File(inRoot('.smartschool-mcp-0123456789abcdef.part'))
        ..writeAsStringSync('half');
      final fresh = File(inRoot('.smartschool-mcp-fedcba9876543210.part'))
        ..writeAsStringSync('half');
      final other = File(inRoot('.smartschool-mcp-iets.part'))
        ..writeAsStringSync('x');
      final download = File(inRoot('download.part'))..writeAsStringSync('x');
      for (final file in [stale, other, download]) {
        file.setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 2)),
        );
      }
      now = DateTime.now();

      expect(await folder.cleanUp(), 1);

      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
      expect(download.existsSync(), isTrue);
      expect(
        File(inRoot(DownloadFolder.manifestName)).existsSync(),
        isFalse,
        reason: 'nothing was saved here: no list is made',
      );
    });

    test(
      'a folder that does not exist, or a damaged list: nothing happens',
      () async {
        expect(await folderAt(inRoot('nergens')).cleanUp(), 0);
        expect(Directory(inRoot('nergens')).existsSync(), isFalse);

        File(inRoot(DownloadFolder.manifestName)).writeAsStringSync('{kapot');
        File(inRoot('a.pdf')).writeAsStringSync('x');
        now = now.add(const Duration(days: 30));
        expect(await folder.cleanUp(), 0);
        expect(File(inRoot('a.pdf')).existsSync(), isTrue);
      },
    );
  });
}
