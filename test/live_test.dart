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
/// for a word of a read message, twice (the second time from the message
/// text cache, `~/.cache/smartschool/<username>/messages/<host>`), and for a
/// word that occurs nowhere. Run it on its own with
/// `--name search_messages`. It prints counts and timings, never the word or
/// any message text.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
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
      int? wordId;
      for (final header in inbox.where((h) => !h.unread).take(5)) {
        final text = await call('read_message', {'message_id': header.id});
        final body = text.substring(text.indexOf('\n\n') + 2);
        if (body.startsWith('(The message has no text.)')) continue;
        word = RegExp(r'\p{L}{7,}', unicode: true).firstMatch(body)?[0];
        if (word != null) {
          wordId = header.id;
          break;
        }
      }
      expect(word, isNotNull, reason: 'no read inbox message with a word');
      final query = {'query': word!.toUpperCase(), 'limit': 100};

      final watch = Stopwatch()..start();
      final first = await call('search_messages', query);
      final firstTime = watch.elapsedMilliseconds;
      watch.reset();
      final second = await call('search_messages', query);
      final secondTime = watch.elapsedMilliseconds;
      final nothing = await call('search_messages', {
        'query': 'qzxj${DateTime.now().microsecondsSinceEpoch}',
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
      expect(hits, contains(wordId), reason: _mask(first));
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
}

/// [text] with every letter and digit replaced, to show its shape without
/// its (personal) content.
String _mask(String text) => text
    .replaceAll(RegExp(r'\p{L}', unicode: true), 'x')
    .replaceAll(RegExp(r'\d'), '9');

typedef _Header = ({int id, String who, String subject, bool unread});

final _headerLine = RegExp(
  r'^- id (\d+) \| \d{4}-\d\d-\d\d \d\d:\d\d \| (?:from|to) (.*?) \| '
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
    if (line.startsWith('Note: ')) continue;
    final match = _headerLine.firstMatch(line);
    expect(match, isNotNull, reason: 'line: ${_mask(line)}');
    headers.add((
      id: int.parse(match![1]!),
      who: match[2]!,
      subject: match[3]!,
      unread: match[4]?.contains('unread') ?? false,
    ));
  }
  return headers;
}
