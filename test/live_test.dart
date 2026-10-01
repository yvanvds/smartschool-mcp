/// Live test against the real Smartschool, driving the compiled server over
/// stdio with `--credentials`.
///
/// Opt-in, because it needs real credentials and every run logs in with a
/// real 2FA code: set `SMARTSCHOOL_LIVE_CREDENTIALS` to the path of a
/// `credentials.yml` (keys `main_url`, `username`, `password`, `mfa`):
///
/// ```
/// SMARTSCHOOL_LIVE_CREDENTIALS=credentials.yml dart test test/live_test.dart
/// ```
///
/// The server's stderr is copied to this process's stderr as evidence of
/// which login steps ran. It never contains secrets.
///
/// The message test only reads: it lists the inbox and the archive and reads
/// a few messages that are already read, and it uses your own cookie cache,
/// so it needs no new login while the saved session is valid. Run it on its
/// own with `--name list_messages`. Its failures show message text masked.
///
/// The search test only reads as well: it searches the inbox and the archive
/// for a word of a read message, from that message's date on, twice (the
/// second time from the message text cache,
/// `~/.cache/smartschool/<username>/messages/<host>`), and for a word that
/// occurs nowhere. Run it on its own with
/// `--name search_messages`. It prints counts and timings, never the word or
/// any message text.
///
/// The Intradesk test only reads as well (it downloads no file): it lists the
/// top of Intradesk and a folder, and searches for a word of a name there
/// with `refresh: true`, which walks all of Intradesk (minutes on a large
/// one; the test waits for the walk by searching again every 20 s), then
/// again from the index in memory, after a restart from the index on disk
/// (`~/.cache/smartschool/<username>/intradesk/<host>`), and for a word that
/// occurs nowhere. Run it on its own with `--name list_intradesk_folder`.
/// It prints counts and timings, never a name.
///
/// The file test only reads as well: it searches Intradesk for files of
/// each format `read_intradesk_file` reads (with the index on disk, or a
/// walk when there is none), opens the two smallest of each (above 5 KB)
/// and one above the size limit, which must be refused without downloading.
/// Run it on its own with `--name read_intradesk_file`. It prints formats,
/// sizes, character counts and timings, never a name or any text.
///
/// The save test only reads as well: it saves the smallest PDF and Word file
/// above 5 KB on Intradesk (from the index, or a walk when there is none)
/// and the first attachment of a read message in the inbox or the archive
/// (twice) into a temporary download folder, which is deleted afterwards,
/// and checks their sizes and first bytes. Run it on its own with
/// `--name save_intradesk_file`. It prints extensions, sizes and timings,
/// never a name or any content.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:test/test.dart';

import 'support/exe.dart';

final _credentialsPath = Platform.environment['SMARTSCHOOL_LIVE_CREDENTIALS'];

void main() {
  final credentialsPath = _credentialsPath;
  if (credentialsPath == null || credentialsPath.isEmpty) {
    test(
      'live Smartschool login',
      () {},
      skip:
          'Set SMARTSCHOOL_LIVE_CREDENTIALS to a credentials.yml to run '
          'the live test.',
    );
    return;
  }

  late String exePath;
  setUpAll(() async => exePath = await compileServer());

  test(
    'logs in with the credentials file (password and 2FA) and shows the '
    'display name; a second process start reuses the saved session',
    () async {
      // A fresh home directory, so the cookie cache
      // (~/.cache/smartschool/<username>) starts empty and the first start
      // must go through the whole login.
      final home = await Directory.systemTemp.createTemp('smartschool_live_');
      addTearDown(() => home.delete(recursive: true));
      final environment = {
        for (final MapEntry(:key, :value)
            in environmentWithoutSmartschool().entries)
          if (!{'HOME', 'USERPROFILE'}.contains(key.toUpperCase())) key: value,
        'HOME': home.path,
        'USERPROFILE': home.path,
      };
      final secrets = PathCredentials(filename: credentialsPath);

      void expectNoSecrets(String text, String what) {
        expect(
          text.contains(secrets.password),
          isFalse,
          reason: '$what contains the password',
        );
        expect(
          text.contains(secrets.mfa!),
          isFalse,
          reason: '$what contains the 2FA key',
        );
      }

      Future<(String, String)> startAndCheckStatus(String label) async {
        final server = await ServerProcess.start(
          exePath,
          args: ['--credentials', credentialsPath],
          environment: environment,
        );
        await server.initialize();
        final (isError, text) = await server.callTool(
          'smartschool_status',
          timeout: const Duration(minutes: 2),
        );
        await server.stop();
        final log = await server.stderr;
        expectNoSecrets(text, '$label tool output');
        expectNoSecrets(log, '$label stderr');
        stderr.writeln('--- $label: server stderr ---\n$log');
        expect(isError, isNot(true));
        expect(text, isNot(contains('#0')), reason: 'stack trace in output');
        return (text, log);
      }

      final (first, firstLog) = await startAndCheckStatus('first start');
      expect(first, startsWith('Smartschool connection: working\n'));
      expect(first, matches(RegExp(r'^Logged in as: \S', multiLine: true)));
      expect(firstLog, contains('Smartschool settings: credentials file'));
      expect(firstLog, contains('Smartschool: sending username and password'));
      expect(firstLog, contains('Smartschool: sending a 2FA code'));
      expect(firstLog, contains('Smartschool: logged in'));

      final (second, secondLog) = await startAndCheckStatus('second start');
      expect(second, startsWith('Smartschool connection: working\n'));
      expect(secondLog, contains('reused the saved session'));
      expect(secondLog, isNot(contains('sending username and password')));
      expect(secondLog, isNot(contains('sending a 2FA code')));
    },
  );

  test(
    'list_messages and read_message work on the real account, read-only',
    () async {
      // The user's own cookie cache, so this reuses the saved session when
      // it is still valid. Only messages that are already read are read, so
      // nothing changes on the account whatever getMessage does. Message
      // content is personal: failures show masked text only.
      final server = await ServerProcess.start(
        exePath,
        args: ['--credentials', credentialsPath],
        environment: environmentWithoutSmartschool(),
      );
      await server.initialize();
      Future<String> call(String tool, Map<String, Object?> arguments) async {
        final (isError, text) = await server.callTool(
          tool,
          arguments: arguments,
          timeout: const Duration(minutes: 2),
        );
        expect(isError, isNot(true), reason: '$tool: ${_mask(text)}');
        return text;
      }

      final inbox = await call('list_messages', {'limit': 200});
      final inboxHeaders = _expectListShape(inbox, 'Inbox');

      final archive = await call('list_messages', {'box': 'archive'});
      final archiveHeaders = _expectListShape(archive, 'Archive');

      // A word from an archived subject, searched for in upper case.
      final word = archiveHeaders
          .expand((h) => h.subject.toLowerCase().split(RegExp(r'\W+')))
          .firstWhere((w) => w.length >= 5, orElse: () => '');
      if (word.isNotEmpty) {
        final found = _expectListShape(
          await call('list_messages', {
            'box': 'archive',
            'query': word.toUpperCase(),
          }),
          'Archive',
        );
        expect(found, isNotEmpty);
        expect(
          found.every(
            (h) => '${h.subject} ${h.who}'.toLowerCase().contains(word),
          ),
          isTrue,
          reason: 'a listed message does not contain the query word',
        );
      }

      final read = inboxHeaders.where((h) => !h.unread).take(3).toList();
      expect(read, isNotEmpty, reason: 'no read message in the inbox');
      for (final header in read) {
        final text = await call('read_message', {'message_id': header.id});
        expect(
          text.startsWith('Message ${header.id} (Inbox)\nFrom: '),
          isTrue,
          reason: _mask(text),
        );
        for (final field in ['\nDate: ', '\nTo: ', '\nSubject: ']) {
          expect(text.contains(field), isTrue, reason: 'no $field line');
        }
        expect(
          RegExp(
            r'<(p|div|br|span|table|a)\b',
            caseSensitive: false,
          ).hasMatch(text),
          isFalse,
          reason: 'HTML left in the text: ${_mask(text)}',
        );
      }

      await server.stop();
      // Only the login steps: on an unexpected error the log could quote a
      // Smartschool response.
      final steps = (await server.stderr)
          .split('\n')
          .where((line) => line.contains('] Smartschool: '));
      stderr.writeln('--- messages: login steps ---\n${steps.join('\n')}');
    },
  );

  test(
    'search_messages works on the real account, read-only: it finds a word '
    'of a message, and a second search is served from the text cache',
    () async {
      // The user's own cookie cache and message text cache
      // (~/.cache/smartschool/<username>/messages/<host>). Only messages
      // that are already read are read. Failures show masked text only.
      final server = await ServerProcess.start(
        exePath,
        args: ['--credentials', credentialsPath],
        environment: environmentWithoutSmartschool(),
      );
      await server.initialize();
      Future<String> call(String tool, Map<String, Object?> arguments) async {
        final (isError, text) = await server.callTool(
          tool,
          arguments: arguments,
          timeout: const Duration(minutes: 2),
        );
        expect(isError, isNot(true), reason: '$tool: ${_mask(text)}');
        return text;
      }

      // A long word from the text of a read inbox message.
      final inbox = _expectListShape(await call('list_messages', {}), 'Inbox');
      String? word;
      _Header? wordMessage;
      for (final header in inbox.where((h) => !h.unread).take(5)) {
        final text = await call('read_message', {'message_id': header.id});
        final body = text.substring(text.indexOf('\n\n') + 2);
        if (body.startsWith('(The message has no text.)')) continue;
        word = RegExp(r'\p{L}{7,}', unicode: true).firstMatch(body)?[0];
        if (word != null) {
          wordMessage = header;
          break;
        }
      }
      expect(word, isNotNull, reason: 'no read inbox message with a word');
      // From the date of that message on: the whole inbox and archive can be
      // more than the 100 texts a search downloads, and then the second
      // search would download the next 100 instead of reading the cache.
      final since = wordMessage!.date;
      final query = {
        'query': word!.toUpperCase(),
        'since': since,
        'limit': 100,
      };

      final watch = Stopwatch()..start();
      final first = await call('search_messages', query);
      final firstTime = watch.elapsedMilliseconds;
      watch.reset();
      final second = await call('search_messages', query);
      final secondTime = watch.elapsedMilliseconds;
      final nothing = await call('search_messages', {
        'query': 'qzxj${DateTime.now().microsecondsSinceEpoch}',
        'since': since,
      });

      final hits = [
        for (final match in RegExp(
          r'^- (inbox|archive) \| id (\d+) \| \d{4}-\d\d-\d\d \d\d:\d\d \| '
          r'from ',
          multiLine: true,
        ).allMatches(first))
          int.parse(match[2]!),
      ];
      expect(
        RegExp(
          r'^Inbox and Archive: \d+ of the \d+ messages? searched contains? '
          r'all of: ',
        ).hasMatch(first),
        isTrue,
        reason: _mask(first),
      );
      expect(hits, contains(wordMessage.id), reason: _mask(first));
      expect(second == first, isTrue, reason: 'second: ${_mask(second)}');
      expect(
        RegExp(
          r'^Inbox and Archive: none of the \d+ messages searched contains '
          r'all of: qzxj\d+\.',
        ).hasMatch(nothing),
        isTrue,
        reason: _mask(nothing),
      );

      await server.stop();
      // Counts and timings only: the query and the texts are personal.
      final searches = (await server.stderr)
          .split('\n')
          .where((line) => line.contains('] search_messages: '))
          .toList();
      stderr.writeln(
        '--- search_messages: counts ---\n${searches.join('\n')}\n'
        'first search $firstTime ms, second $secondTime ms',
      );
      expect(searches, hasLength(3));
      expect(searches[1], contains(', 0 downloaded,'));
      expect(searches[2], contains(', 0 downloaded,'));
    },
  );

  test('list_intradesk_folder and search_intradesk work on the real account, '
      'read-only: a refresh walks Intradesk in the background, later '
      'searches use the index, also after a restart', () async {
    // The user's own cookie cache and Intradesk index
    // (~/.cache/smartschool/<username>/intradesk/<host>). Nothing is
    // downloaded or changed. The names are the school's: failures show
    // masked text only, and only counts and timings are printed.
    Future<ServerProcess> start() async {
      final server = await ServerProcess.start(
        exePath,
        args: ['--credentials', credentialsPath],
        environment: environmentWithoutSmartschool(),
      );
      await server.initialize();
      return server;
    }

    final timings = <String>[];
    Future<(bool?, String)> call(
      ServerProcess server,
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final watch = Stopwatch()..start();
      final result = await server.callTool(
        tool,
        arguments: arguments,
        timeout: const Duration(minutes: 2),
      );
      timings.add('$tool ${watch.elapsedMilliseconds} ms');
      // Every call answers well within the minute Claude Desktop waits.
      expect(watch.elapsed, lessThan(const Duration(seconds: 50)));
      return result;
    }

    Future<String> ok(
      ServerProcess server,
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final (isError, text) = await call(server, tool, arguments);
      expect(isError, isNot(true), reason: '$tool: ${_mask(text)}');
      return text;
    }

    bool walking(String text) =>
        text.startsWith('Intradesk is being indexed') ||
        text.contains('A new index is being built');

    final server = await start();
    final root = await ok(server, 'list_intradesk_folder', {});
    expect(root, startsWith('Intradesk, top level: '), reason: _mask(root));
    final rootItems = _intradeskLines(root);
    expect(rootItems, isNotEmpty, reason: _mask(root));

    final (bogusError, bogus) = await call(server, 'list_intradesk_folder', {
      'folder_id': '00000000-0000-4000-8000-000000000000',
    });
    expect(bogusError, isTrue);
    expect(
      bogus,
      startsWith(
        'Intradesk has no folder with id '
        '00000000-0000-4000-8000-000000000000: ',
      ),
    );

    // A word from a name at the top level, never printed.
    final word = rootItems
        .expand(
          (item) => RegExp(
            r'\p{L}{4,}',
            unicode: true,
          ).allMatches(item.name).map((m) => m[0]!),
        )
        .first;
    final query = {'query': word.toUpperCase(), 'limit': 100};

    // The refresh walks Intradesk; the call answers after at most 40 s,
    // from the old index or with how far the walk is.
    var first = await ok(server, 'search_intradesk', {
      ...query,
      'refresh': true,
    });
    final walk = Stopwatch()..start();
    while (walking(first)) {
      expect(walk.elapsed, lessThan(const Duration(minutes: 12)));
      await Future<void>.delayed(const Duration(seconds: 20));
      first = await ok(server, 'search_intradesk', query);
    }
    final second = await ok(server, 'search_intradesk', query);
    final nothing = await ok(server, 'search_intradesk', {
      'query': 'qzxj${DateTime.now().microsecondsSinceEpoch}',
    });
    final folder = rootItems.firstWhere((item) => item.kind == 'folder');
    final sub = await ok(server, 'list_intradesk_folder', {
      'folder_id': folder.id,
    });
    await server.stop();
    final log = await server.stderr;

    final restarted = await start();
    final third = await ok(restarted, 'search_intradesk', query);
    await restarted.stop();
    final restartedLog = await restarted.stderr;

    final hits = RegExp(
      r'^- (folder|file|weblink) \| ',
      multiLine: true,
    ).allMatches(first).length;
    expect(
      RegExp(
        r'^Intradesk: \d+ of the \d+ names searched match(es)? all of: ',
      ).hasMatch(first),
      isTrue,
      reason: _mask(first),
    );
    expect(hits, greaterThan(0));
    expect(
      RegExp(
        r'^Index of \d{4}-\d\d-\d\d \d\d:\d\d: \d+ folders, \d+ files, '
        r'\d+ weblinks?\. ',
        multiLine: true,
      ).hasMatch(first),
      isTrue,
      reason: _mask(first),
    );
    expect(second == first, isTrue, reason: 'second: ${_mask(second)}');
    expect(third == first, isTrue, reason: 'third: ${_mask(third)}');
    expect(
      RegExp(
        r'^Intradesk: no name matches all of: qzxj\d+ \(\d+ names searched\)',
      ).hasMatch(nothing),
      isTrue,
      reason: _mask(nothing),
    );
    expect(
      sub,
      startsWith('Intradesk folder ${folder.name} (id ${folder.id}): '),
      reason: 'the index names the folder: ${_mask(sub)}',
    );

    // Counts and timings only: names and the query are the school's.
    final lines = [
      for (final line in '$log\n$restartedLog'.split('\n'))
        if (line.contains('] search_intradesk: ') ||
            line.contains('] intradesk index: '))
          line,
    ];
    stderr.writeln(
      '--- intradesk: counts ---\n${lines.join('\n')}\n'
      '${timings.join('\n')}\nwalk waited ${walk.elapsed.inSeconds} s',
    );
    final searches = [
      for (final line in lines)
        if (line.contains('] search_intradesk: ')) line,
    ];
    expect(lines, contains(contains('] intradesk index: built in ')));
    expect(searches.last, contains('index from the disk ('));
    expect(searches[searches.length - 2], contains('index from the memory ('));
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('read_intradesk_file opens real Word, Excel, PowerPoint, PDF and '
      'image files, read-only, and refuses one above the size limit '
      'without downloading it', () async {
    // The user's own cookie cache and Intradesk index. Files are only
    // downloaded, never changed. Names and contents are the school's:
    // failures show masked text only, and only formats, sizes, counts and
    // timings are printed.
    final server = await ServerProcess.start(
      exePath,
      args: ['--credentials', credentialsPath],
      environment: environmentWithoutSmartschool(),
    );
    await server.initialize();

    Future<(bool?, String, int)> call(
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final watch = Stopwatch()..start();
      final result = await server.request('tools/call', {
        'name': tool,
        'arguments': arguments,
      }, const Duration(minutes: 2));
      final content = result['content'] as List;
      final text = (content.first as Map)['text'] as String;
      return (result['isError'] as bool?, text, watch.elapsedMilliseconds);
    }

    Future<String> search(String extension) async {
      var (isError, text, _) = await call('search_intradesk', {
        'query': extension,
        'limit': 100,
      });
      final walk = Stopwatch()..start();
      while (text.startsWith('Intradesk is being indexed')) {
        expect(walk.elapsed, lessThan(const Duration(minutes: 12)));
        await Future<void>.delayed(const Duration(seconds: 20));
        (isError, text, _) = await call('search_intradesk', {
          'query': extension,
          'limit': 100,
        });
      }
      expect(isError, isNot(true), reason: _mask(text));
      return text;
    }

    final report = <String>[];
    final tooLarge = <({String id, String extension, int size})>[];
    const labels = {
      'docx': 'Word document',
      'xlsx': 'Excel workbook',
      'pptx': 'PowerPoint presentation',
      'pdf': 'PDF',
      'png': 'image',
      'jpg': 'image',
    };
    for (final MapEntry(key: extension, value: label) in labels.entries) {
      final files = [
        for (final file in _intradeskFiles(await search(extension)))
          if (file.extension == extension) file,
      ]..sort((a, b) => a.size.compareTo(b.size));
      tooLarge.addAll(files.where((file) => file.size > 25 * 1024 * 1024));
      final small = files.where((file) => file.size > 5 * 1024).take(2);
      if (small.isEmpty) {
        report.add('$extension: no file found');
        continue;
      }
      for (final file in small) {
        final (isError, text, ms) = await call('read_intradesk_file', {
          'file_id': file.id,
        });
        expect(isError, isNot(true), reason: _mask(text));
        final header = text.split('\n').first;
        expect(
          RegExp(
            r'^Intradesk file .+ \(id '
            '${file.id}'
            r', .+\): '
            '${RegExp.escape(label)}[,.( ]',
          ).hasMatch(header),
          isTrue,
          reason: _mask(header),
        );
        expect(ms, lessThan(50000), reason: 'within Claude Desktop\'s wait');
        report.add(
          '$extension: ${file.size} bytes -> ${text.length} characters of '
          'output in $ms ms',
        );
      }
    }
    if (tooLarge.isNotEmpty) {
      final file = tooLarge.first;
      final (isError, text, ms) = await call('read_intradesk_file', {
        'file_id': file.id,
      });
      expect(isError, isTrue);
      expect(text, contains(' is too large to open here: files up to 25 MB'));
      report.add('refused ${file.extension} of ${file.size} bytes in $ms ms');
    } else {
      report.add('no file above the size limit found');
    }
    await server.stop();
    final log = await server.stderr;

    final downloads = [
      for (final line in log.split('\n'))
        if (line.contains('] read_intradesk_file: ')) line,
    ];
    stderr.writeln(
      '--- read_intradesk_file: formats, sizes, counts ---\n'
      '${report.join('\n')}\n${downloads.join('\n')}',
    );
    // The refused file was never downloaded.
    expect(downloads, hasLength(report.where((r) => r.contains('->')).length));
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('save_intradesk_file and save_message_attachment save real files into '
      'a temporary download folder, read-only, with the right bytes', () async {
    // The user's own cookie cache and Intradesk index. Files are only
    // downloaded, never changed, into a temporary download folder that
    // ServerProcess.start deletes after the test. Names and contents are
    // the user's: failures show masked text only, and only extensions,
    // sizes and timings are printed.
    final server = await ServerProcess.start(
      exePath,
      args: ['--credentials', credentialsPath],
      environment: environmentWithoutSmartschool(),
    );
    final downloads = server.downloads!;
    await server.initialize();

    Future<(bool?, String, int)> call(
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final watch = Stopwatch()..start();
      final result = await server.request('tools/call', {
        'name': tool,
        'arguments': arguments,
      }, const Duration(minutes: 2));
      final content = result['content'] as List;
      final text = (content.first as Map)['text'] as String;
      return (result['isError'] as bool?, text, watch.elapsedMilliseconds);
    }

    Future<String> ok(String tool, Map<String, Object?> arguments) async {
      final (isError, text, _) = await call(tool, arguments);
      expect(isError, isNot(true), reason: '$tool: ${_mask(text)}');
      return text;
    }

    final report = <String>[];

    /// Checks the result of a save: the file is in [downloads], has the
    /// size the result gives, about [expectedSize], and starts like a file
    /// of its extension. Returns the file.
    File checkSaved(String text, {int? expectedSize, String? what}) {
      final path = RegExp(r'^Path: (.+)$', multiLine: true).firstMatch(text);
      final size = RegExp(
        r'^Size: .*?(?:\((\d+) bytes\)|(\d+) bytes?)$',
        multiLine: true,
      ).firstMatch(text);
      expect(path, isNotNull, reason: _mask(text));
      expect(size, isNotNull, reason: _mask(text));
      final file = File(path![1]!);
      expect(file.parent.path, downloads, reason: 'saved outside the folder');
      expect(file.existsSync(), isTrue);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, int.parse(size![1] ?? size[2]!));
      // Smartschool and the index give sizes rounded.
      if (expectedSize != null) {
        expect(
          (bytes.length - expectedSize).abs(),
          lessThanOrEqualTo(max(1024, expectedSize ~/ 20)),
          reason: '${bytes.length} bytes saved, about $expectedSize expected',
        );
      }
      // Only a short extension is printed, never more of the name.
      final name = file.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final extension = dot < 0 || name.length - dot > 6
          ? '(other)'
          : name.substring(dot + 1).toLowerCase();
      final magic = switch (extension) {
        'pdf' => '%PDF',
        'docx' || 'xlsx' || 'pptx' => 'PK\x03\x04',
        'png' => '\x89PNG',
        _ => null,
      };
      if (magic != null) {
        expect(
          String.fromCharCodes(bytes.take(magic.length)),
          magic,
          reason: 'not a .$extension file',
        );
      }
      report.add(
        '${what ?? 'file'} .$extension: ${bytes.length} bytes saved'
        '${magic == null ? '' : ', starts like a .$extension file'}',
      );
      return file;
    }

    // Intradesk: the smallest PDF and Word file above 5 KB the index has.
    for (final extension in ['pdf', 'docx']) {
      var text = await ok('search_intradesk', {
        'query': extension,
        'limit': 100,
      });
      final walk = Stopwatch()..start();
      while (text.startsWith('Intradesk is being indexed')) {
        expect(walk.elapsed, lessThan(const Duration(minutes: 12)));
        await Future<void>.delayed(const Duration(seconds: 20));
        text = await ok('search_intradesk', {'query': extension, 'limit': 100});
      }
      final files = [
        for (final file in _intradeskFiles(text))
          if (file.extension == extension && file.size > 5 * 1024) file,
      ]..sort((a, b) => a.size.compareTo(b.size));
      if (files.isEmpty) {
        report.add('intradesk .$extension: no file found');
        continue;
      }
      final (isError, saved, ms) = await call('save_intradesk_file', {
        'file_id': files.first.id,
      });
      expect(isError, isNot(true), reason: _mask(saved));
      checkSaved(saved, expectedSize: files.first.size, what: 'intradesk');
      report.add('  in $ms ms');
    }

    // An attachment of a read message in the inbox or the archive, saved
    // twice: the second copy gets a name of its own, with the same bytes.
    _Header? withAttachment;
    var box = 'inbox';
    for (final candidate in ['inbox', 'archive']) {
      final headers = _expectListShape(
        await ok('list_messages', {'box': candidate, 'limit': 200}),
        candidate == 'inbox' ? 'Inbox' : 'Archive',
      );
      withAttachment = headers
          .where((h) => !h.unread && h.attachments)
          .firstOrNull;
      if (withAttachment != null) {
        box = candidate;
        break;
      }
    }
    expect(withAttachment, isNotNull, reason: 'no read message with files');
    final message = await ok('read_message', {
      'message_id': withAttachment!.id,
      'box': box,
    });
    expect(
      RegExp(r'^1\. ', multiLine: true).hasMatch(message),
      isTrue,
      reason: _mask(message),
    );
    // The size as Smartschool gives it, such as `3.87 KiB`, when it reads
    // like that.
    final first = RegExp(
      r'^1\. .+ \(([\d.]+) (bytes?|B|KiB|KB|MiB|MB)\)$',
      multiLine: true,
    ).firstMatch(message);
    const units = {
      'B': 1,
      'byte': 1,
      'bytes': 1,
      'KiB': 1024,
      'KB': 1024,
      'MiB': 1024 * 1024,
      'MB': 1024 * 1024,
    };
    final listedSize = first == null
        ? null
        : (double.parse(first[1]!) * units[first[2]]!).round();
    if (listedSize == null) report.add('attachment size not in a known form');
    final arguments = {
      'message_id': withAttachment.id,
      'attachment': 1,
      'box': box,
    };
    final (isError, once, ms) = await call(
      'save_message_attachment',
      arguments,
    );
    expect(isError, isNot(true), reason: _mask(once));
    final saved = checkSaved(
      once,
      expectedSize: listedSize,
      what: 'attachment',
    );
    report.add('  in $ms ms');
    final twice = await ok('save_message_attachment', arguments);
    final again = checkSaved(twice, expectedSize: listedSize, what: 'again');
    // Booleans only: a failing matcher would print the names or bytes.
    expect(again.path == saved.path, isFalse, reason: 'saved over the first');
    expect(
      twice.contains('was already in the download folder'),
      isTrue,
      reason: _mask(twice),
    );
    final (one, two) = (saved.readAsBytesSync(), again.readAsBytesSync());
    expect(
      one.length == two.length &&
          Iterable.generate(one.length).every((i) => one[i] == two[i]),
      isTrue,
      reason: 'the second copy has other bytes',
    );

    final status = await ok('smartschool_status', {});
    expect(
      status.contains(
        '\nDownload folder: $downloads (set in SMARTSCHOOL_DOWNLOAD_DIR; '
        'writable)\n',
      ),
      isTrue,
      reason: _mask(status),
    );
    await server.stop();
    final log = await server.stderr;

    final manifest =
        jsonDecode(
              File(
                '$downloads${Platform.pathSeparator}'
                '${DownloadFolder.manifestName}',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final saves = [
      for (final line in log.split('\n'))
        if (line.contains('] save_')) line,
    ];
    expect(manifest['files'], hasLength(saves.length));
    stderr.writeln(
      '--- save tools: extensions, sizes, timings ---\n'
      '${report.join('\n')}\n${saves.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

typedef _IntradeskLine = ({String kind, String name, String id});

/// The files of a `search_intradesk` result: id, extension and size.
List<({String id, String extension, int size})> _intradeskFiles(String text) {
  const units = {'byte': 1, 'bytes': 1, 'KB': 1024, 'MB': 1024 * 1024};
  return [
    for (final line in text.split('\n'))
      if (RegExp(
            r'^- file \| .*\.(\w+) \| id ([0-9a-f-]{36}) \| ([\d.]+) '
            r'(bytes?|KB|MB)(?: \||$)',
          ).firstMatch(line)
          case final match?)
        (
          id: match[2]!,
          extension: match[1]!.toLowerCase(),
          size: (double.parse(match[3]!) * units[match[4]]!).round(),
        ),
  ];
}

/// The folders and files of a `list_intradesk_folder` result.
List<_IntradeskLine> _intradeskLines(String text) => [
  for (final line in text.split('\n').skip(1))
    if (RegExp(
          r'^- (folder|file) \| (.+?) \| id ([0-9a-f-]{36})(?: \| |$)',
        ).firstMatch(line)
        case final match?)
      (kind: match[1]!, name: match[2]!, id: match[3]!),
];

/// [text] with every letter and digit replaced, to show its shape without
/// its (personal) content.
String _mask(String text) => text
    .replaceAll(RegExp(r'\p{L}', unicode: true), 'x')
    .replaceAll(RegExp(r'\d'), '9');

typedef _Header = ({
  int id,
  String date,
  String who,
  String subject,
  bool unread,
  bool attachments,
});

final _headerLine = RegExp(
  r'^- id (\d+) \| (\d{4}-\d\d-\d\d \d\d:\d\d) \| (?:from|to) (.*?) \| '
  r'(.+?)(?: \| ((?:unread|attachments|flag \w+)(?:, (?:attachments|flag \w+))*))?$',
);

/// Checks the shape of a `list_messages` result for [label] and returns its
/// headers.
List<_Header> _expectListShape(String text, String label) {
  final lines = text.split('\n');
  expect(
    RegExp('^$label: ').hasMatch(lines.first),
    isTrue,
    reason: 'summary: ${_mask(lines.first)}',
  );
  final headers = <_Header>[];
  for (final line in lines.skip(1)) {
    final match = _headerLine.firstMatch(line);
    expect(match, isNotNull, reason: 'line: ${_mask(line)}');
    headers.add((
      id: int.parse(match![1]!),
      date: match[2]!,
      who: match[3]!,
      subject: match[4]!,
      unread: match[5]?.contains('unread') ?? false,
      attachments: match[5]?.contains('attachments') ?? false,
    ));
  }
  return headers;
}
