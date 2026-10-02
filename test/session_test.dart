import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/problems.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

/// A form POST, like the ones the message tools make.
Future<String> _post(SmartschoolClient client) =>
    client.postFormRaw('/some/form', {'a': 'b'});

TypeMatcher<SmartschoolProblem> _problem(ProblemKind kind) =>
    isA<SmartschoolProblem>().having((p) => p.kind, 'kind', kind);

/// Runs [body] and returns the lines it logged to stderr, without their
/// `[smartschool_mcp] ` prefix.
Future<List<String>> _logOf(Future<void> Function() body) async {
  final stderr = _CapturedStderr();
  await IOOverrides.runZoned(body, stderr: () => stderr);
  return [
    for (final line in stderr.lines)
      line.replaceFirst('[smartschool_mcp] ', ''),
  ];
}

/// A stderr that keeps the lines written to it.
final class _CapturedStderr implements Stdout {
  final List<String> lines = [];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSmartschool server;
  late Directory cache;
  late int clientsCreated;

  setUp(() async {
    server = FakeSmartschool();
    cache = await tempCache();
    clientsCreated = 0;
  });

  SmartschoolSession newSession({CredentialSource? source}) {
    final create = fakeClientFactory(server, cache);
    final session = SmartschoolSession(
      source ?? fakeExtensionSettings(),
      createClient: (credentials) {
        clientsCreated++;
        return create(credentials);
      },
    );
    addTearDown(session.close);
    return session;
  }

  test('nothing is read or created until the first call', () {
    var settingsRead = 0;
    newSession(
      source: ExtensionSettings(
        read: () {
          settingsRead++;
          return FakeCredentials();
        },
      ),
    );

    expect(settingsRead, 0);
    expect(clientsCreated, 0);
    expect(server.requests, isEmpty);
  });

  test('the first call logs in with password and 2FA; later calls reuse the '
      'client without logging in again', () async {
    final session = newSession();

    expect(await session.run(_post), '<ok/>');
    expect(server.logins, 1);
    expect(server.requests, contains('POST /2fa/api/v1/google-authenticator'));

    server.requests.clear();
    expect(await session.run(_post), '<ok/>');
    expect(server.logins, 1);
    expect(clientsCreated, 1);
    expect(server.requests, ['POST /some/form']);
  });

  test('concurrent first calls share a single login', () async {
    final session = newSession();

    await Future.wait([session.run(_post), session.run(_post)]);

    expect(server.logins, 1);
    expect(clientsCreated, 1);
  });

  test('a new process reuses the saved session cookies: no password or 2FA '
      'step while the session is valid', () async {
    await newSession().run(_post);
    expect(server.logins, 1);
    server.requests.clear();

    // A second session on the same cookie cache, like a restarted server.
    expect(await newSession().run(_post), '<ok/>');

    expect(server.logins, 1);
    expect(server.requests, isNot(contains('POST /login')));
    expect(server.requests, isNot(contains(startsWith('POST /2fa'))));
  });

  test('the cache folder is the one the library\'s client uses: unknown '
      'before the login, still known after closing', () async {
    final session = newSession();
    expect(() => session.cacheDirectory, throwsStateError);

    await session.run(_post);
    expect(session.cacheDirectory, cache.path);

    await session.close();
    expect(session.cacheDirectory, cache.path);
  });

  test('the log tells a new login from a reused session, and shows a '
      'session that expired', () async {
    final first = await _logOf(() => newSession().run(_post));
    final reused = await _logOf(() => newSession().run(_post));
    server.expireSession();
    final expired = await _logOf(() => newSession().run(_post));

    expect(
      first,
      containsAllInOrder([
        'Smartschool: no valid session (sent to /login)',
        'Smartschool: sending username and password',
        'Smartschool: sending a 2FA code',
        'Smartschool: logged in',
      ]),
    );
    expect(
      reused,
      contains(endsWith('reused the saved session, no login needed')),
    );
    expect(reused, isNot(contains(startsWith('Smartschool: sending'))));
    expect(
      expired,
      containsAllInOrder([
        'Smartschool: no valid session (sent to /login)',
        'Smartschool: sending username and password',
        'Smartschool: logged in',
      ]),
    );
    for (final line in [...first, ...reused, ...expired]) {
      expect(line, isNot(contains(fakePassword)));
      expect(line, isNot(contains(fakeTotpSecret)));
    }
  });

  test('the log shows a POST that Smartschool answers with 401', () async {
    final session = newSession();
    await session.run(_post);
    server.expireSession();

    final log = await _logOf(() => session.run(_post));

    expect(
      log,
      containsAllInOrder([
        'Smartschool: no valid session (answered 401)',
        'Smartschool: sending username and password',
        'Smartschool: sending a 2FA code',
      ]),
    );
  });

  group('when the session expires mid-process', () {
    // The library logs in again on the same client and retries the refused
    // request itself (yvanvds/dartschool#8, #36), so the action runs once.

    test(
      'a POST answered with 401 logs in again and is retried once',
      () async {
        final session = newSession();
        await session.run(_post);
        server.expireSession();
        server.requests.clear();

        expect(await session.run(_post), '<ok/>');

        expect(server.logins, 2);
        expect(server.requests.first, 'POST /some/form');
        expect(server.requests.last, 'POST /some/form');
        expect(
          server.requests.where((r) => r == 'POST /some/form'),
          hasLength(2),
        );
        expect(server.requests, contains('POST /login'));
        expect(
          clientsCreated,
          1,
          reason: 'the new login is on the same client',
        );
      },
    );

    test('a GET sent to /login logs in again and is retried once', () async {
      final session = newSession();
      await session.run(_post);
      server.expireSession();
      server.requests.clear();
      var attempts = 0;

      await session.run((client) {
        attempts++;
        return client.getRaw('/some/page');
      });

      expect(server.logins, 2);
      expect(attempts, 1, reason: 'the library retries the request');
      expect(clientsCreated, 1);
      expect(server.requests.first, 'GET /some/page');
      expect(server.requests.last, 'GET /some/page');
      expect(server.requests.where((r) => r == 'GET /some/page'), hasLength(2));
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
    });

    test('concurrent calls that find it expired share one new login, and '
        'each is retried once', () async {
      final session = newSession();
      await session.run(_post);
      server
        ..expireSession()
        ..latency = const Duration(milliseconds: 20);
      server.requests.clear();
      final attempts = <String, int>{};
      Future<String> call(
        String name,
        Future<String> Function(SmartschoolClient client) request,
      ) => session.run((client) {
        attempts.update(name, (n) => n + 1, ifAbsent: () => 1);
        return request(client);
      });

      await Future.wait([
        call('GET a', (client) => client.getRaw('/a')),
        call('GET b', (client) => client.getRaw('/b')),
        call('GET c', (client) => client.getRaw('/c')),
        call('POST', _post),
      ]);

      expect(server.logins, 2);
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
      expect(clientsCreated, 1);
      expect(attempts, {'GET a': 1, 'GET b': 1, 'GET c': 1, 'POST': 1});
      for (final request in ['GET /a', 'GET /b', 'GET /c', 'POST /some/form']) {
        expect(
          server.requests.where((r) => r == request),
          hasLength(2),
          reason: '$request: refused, then retried once',
        );
      }
    });

    test('requests of one call that find it expired at the same time share '
        'one new login, and each is retried once', () async {
      final session = newSession();
      await session.run(_post);
      server
        ..expireSession()
        ..latency = const Duration(milliseconds: 20)
        ..maxInFlight = 0;
      var attempts = 0;

      await session.run((client) {
        attempts++;
        return Future.wait([
          for (final path in ['/a', '/b', '/c', '/d']) client.getRaw(path),
        ]);
      });

      expect(server.maxInFlight, 4);
      expect(server.logins, 2);
      expect(attempts, 1);
      expect(clientsCreated, 1);
    });

    test('a call that starts after the new login uses the client without '
        'logging in again', () async {
      final session = newSession();
      await session.run(_post);
      server.expireSession();
      await session.run((client) => client.getRaw('/a'));
      server.requests.clear();

      await session.run((client) => client.getRaw('/b'));

      expect(server.logins, 2);
      expect(clientsCreated, 1);
      expect(server.requests, ['GET /b']);
    });

    test('when Smartschool refuses the retry after logging in again, the call '
        'runs once more, without another login', () async {
      final session = newSession();
      await session.run(_post);
      server
        ..expireSession()
        ..rejectsAfterLogin = 1;
      var attempts = 0;

      expect(
        await session.run((client) {
          attempts++;
          return client.getRaw('/a');
        }),
        contains('home'),
      );

      expect(attempts, 2);
      expect(server.logins, 2);
    });

    test('a request that is still refused after logging in again is not '
        'retried a second time', () async {
      final session = newSession();
      await session.run(_post);
      server.requests.clear();
      var attempts = 0;

      await expectLater(
        session.run((client) {
          attempts++;
          return client.postFormRaw('/always-401', {});
        }),
        throwsA(_problem(ProblemKind.sessionRejected)),
      );
      // Each attempt: the library logs in again and retries the request
      // once; then the session runs the call once more, and stops.
      expect(attempts, 2);
      expect(
        server.requests.where((r) => r == 'POST /always-401'),
        hasLength(4),
      );
      expect(server.logins, 3);
    });
  });

  group('when Smartschool restarts the paging of a box the call lists '
      '(yvanvds/dartschool#76)', () {
    const restarted = SmartschoolPagingRestartedError(
      'Smartschool restarted the paging of the box',
    );

    test('the call runs once more, on the same client, and says so in the '
        'log', () async {
      final session = newSession();
      var attempts = 0;
      late String result;

      final lines = await _logOf(() async {
        result = await session.run((client) async {
          if (++attempts == 1) throw restarted;
          return 'listed';
        });
      });

      expect(result, 'listed');
      expect(attempts, 2);
      expect(server.logins, 1);
      expect(clientsCreated, 1);
      expect(
        lines,
        contains(
          'Smartschool restarted the listing of a message box '
          '($restarted); listing it again',
        ),
      );
    });

    test('restarted again: reported, and not run a third time', () async {
      final session = newSession();
      var attempts = 0;

      await expectLater(
        session.run((client) async {
          attempts++;
          throw restarted;
        }),
        throwsA(_problem(ProblemKind.listingRestarted)),
      );
      expect(attempts, 2);
    });

    test('a refused session and a restarted listing are each repeated '
        'once', () async {
      final session = newSession();
      var attempts = 0;

      expect(
        await session.run((client) async {
          switch (++attempts) {
            case 1:
              throw restarted;
            case 2:
              throw const SmartschoolSessionExpiredError();
          }
          return 'listed';
        }),
        'listed',
      );
      expect(attempts, 3);

      attempts = 0;
      await expectLater(
        session.run((client) async {
          attempts++;
          throw attempts == 2
              ? const SmartschoolSessionExpiredError()
              : restarted;
        }),
        throwsA(_problem(ProblemKind.listingRestarted)),
      );
      expect(attempts, 3);
    });
  });

  group('with a saved session that expired (an old cookie cache)', () {
    test('a new process logs in once, and its first call succeeds on that '
        'client', () async {
      await newSession().run(_post);
      server.expireSession();
      server.requests.clear();
      clientsCreated = 0;

      // A second session on the same cookie cache, like a restarted server.
      // The library's retry after the login must not send the refused
      // session id along (yvanvds/dartschool#9).
      expect(await newSession().run(_post), '<ok/>');

      expect(server.logins, 2);
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
      expect(server.requests.last, 'POST /some/form');
      expect(clientsCreated, 1);
    });

    test('a session Smartschool still refuses after the login is reported, '
        'without a second login', () async {
      server.rejectsAfterLogin = 1;
      final session = newSession();

      await expectLater(
        session.run(_post),
        throwsA(_problem(ProblemKind.sessionRejected)),
      );

      expect(server.logins, 1);
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
      expect(server.requests, isNot(contains('POST /some/form')));
    });
  });

  test(
    'missing settings are reported without contacting Smartschool',
    () async {
      final session = newSession(
        source: fakeExtensionSettings(FakeCredentials(mainUrl: '', mfa: ' ')),
      );

      await expectLater(
        session.run(_post),
        throwsA(
          _problem(ProblemKind.missingSettings).having(
            (p) => p.message,
            'message',
            contains(
              '"Smartschool-adres" (SMARTSCHOOL_MAIN_URL), "2FA-sleutel"',
            ),
          ),
        ),
      );
      expect(clientsCreated, 0);
      expect(server.requests, isEmpty);
    },
  );

  test('a 2FA key that is not valid is reported without posting the '
      'password, also on later calls, which do not contact Smartschool, and '
      'the log does not quote it', () async {
    // The 6-digit code of the app, typed with a space, and a key with a "1":
    // the library refuses both before it posts the password
    // (yvanvds/dartschool#79).
    for (final code in ['123 456', 'JBSW Y3DP EHPK 3PX1']) {
      server = FakeSmartschool();
      cache = await tempCache();
      clientsCreated = 0;
      final session = newSession(
        source: fakeExtensionSettings(FakeCredentials(mfa: code)),
      );
      final key = _problem(ProblemKind.twoFactorKeyInvalid).having(
        (p) => p.message,
        'message',
        allOf(
          startsWith(
            'The two-factor authentication (2FA) key is not valid, so the '
            'login to Smartschool was stopped. Check "2FA-sleutel" '
            '(SMARTSCHOOL_MFA) in the Smartschool',
          ),
          isNot(contains(code)),
        ),
      );

      late int requests;
      final log = await _logOf(() async {
        await expectLater(session.run(_post), throwsA(key), reason: code);
        requests = server.requests.length;
        await expectLater(session.run(_post), throwsA(key), reason: code);
      });

      expect(server.requests, isNot(contains('POST /login')), reason: code);
      expect(server.requests, hasLength(requests), reason: code);
      expect(server.logins, 0, reason: code);
      expect(clientsCreated, 1, reason: code);
      expect(
        log,
        contains(startsWith('Smartschool problem (twoFactorKeyInvalid)')),
        reason: code,
      );
      expect(log, everyElement(isNot(contains(code))), reason: code);
    }
  });

  test('a date as 2FA key, where Smartschool asks for a 2FA code: reported '
      'as not valid after the password, and not tried again', () async {
    // The library keeps a date for an account verification, so it posts the
    // password first, and refuses the date as a key at the 2FA step.
    const date = '2010-05-15';
    final session = newSession(
      source: fakeExtensionSettings(FakeCredentials(mfa: date)),
    );

    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.twoFactorKeyInvalid)),
    );
    final requests = server.requests.length;
    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.twoFactorKeyInvalid)),
    );

    expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
    expect(
      server.requests,
      isNot(contains('POST /2fa/api/v1/google-authenticator')),
    );
    expect(server.requests, hasLength(requests));
    expect(server.logins, 0);
  });

  test('a 2FA key copied in groups (with spaces or hyphens), in lower case '
      'or with "=" padding: the library logs in with it', () async {
    for (final key in [
      'JBSW Y3DP EHPK 3PXP',
      'JBSW-Y3DP-EHPK-3PXP',
      'jbswy3dpehpk3pxp',
      'JBSWY3DPEHPK3PXPJBSWY3DPEH======',
    ]) {
      server = FakeSmartschool();
      cache = await tempCache();
      final session = newSession(
        source: fakeExtensionSettings(FakeCredentials(mfa: key)),
      );

      expect(await session.run(_post), '<ok/>', reason: key);
      expect(server.logins, 1, reason: key);
    }
  });

  test('a missing credentials file is reported', () async {
    final session = newSession(
      source: CredentialsFile('${cache.path}/missing.yml'),
    );

    expect(
      () => session.settings,
      throwsA(_problem(ProblemKind.credentialsFileMissing)),
    );
    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.credentialsFileMissing)),
    );
    expect(clientsCreated, 0);
  });

  test('a rejected password is reported and not retried: later calls do not '
      'contact Smartschool again', () async {
    server.passwordAccepted = false;
    final session = newSession();

    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.wrongPassword)),
    );
    final requests = server.requests.length;

    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.wrongPassword)),
    );
    expect(server.requests, hasLength(requests));
  });

  test('each login failure yields its own problem', () async {
    Future<SmartschoolProblem> failure(FakeSmartschool fake) async {
      server = fake;
      cache = await tempCache();
      try {
        await newSession().run(_post);
      } on SmartschoolProblem catch (problem) {
        return problem;
      }
      fail('no problem');
    }

    final problems = [
      await failure(FakeSmartschool(passwordAccepted: false)),
      await failure(FakeSmartschool(twoFactorAccepted: false)),
      await failure(
        FakeSmartschool(secondStep: SecondStep.twoFactorWithoutApp),
      ),
      await failure(
        FakeSmartschool(secondStep: SecondStep.accountVerification),
      ),
      await failure(FakeSmartschool()..unreachable = true),
    ];

    expect(problems.map((p) => p.kind), [
      ProblemKind.wrongPassword,
      ProblemKind.twoFactorRejected,
      ProblemKind.twoFactorUnsupported,
      ProblemKind.accountVerification,
      ProblemKind.unreachable,
    ]);
    expect(problems.map((p) => p.message).toSet(), hasLength(5));
  });

  test('an unreachable Smartschool is retried on the next call', () async {
    server.unreachable = true;
    final session = newSession();

    await expectLater(
      session.run(_post),
      throwsA(_problem(ProblemKind.unreachable)),
    );

    server.unreachable = false;
    expect(await session.run(_post), '<ok/>');
    expect(server.logins, 1);
  });

  test(
    'a network failure during an action is reported as unreachable',
    () async {
      final session = newSession();
      await session.run(_post);
      server.unreachable = true;

      await expectLater(
        session.run(_post),
        throwsA(_problem(ProblemKind.unreachable)),
      );
    },
  );

  test('other errors from the action are passed through unchanged', () async {
    final session = newSession();

    await expectLater(
      session.run<void>((_) async => throw const FormatException('tool bug')),
      throwsFormatException,
    );
  });
}
