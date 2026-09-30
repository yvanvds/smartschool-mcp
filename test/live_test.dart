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
}
