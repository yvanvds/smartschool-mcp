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
      recheckDelay: Duration.zero,
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

  group('when the session expires mid-process', () {
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
        expect(server.requests, contains('POST /login'));
        expect(clientsCreated, 2, reason: 'a new client for the new login');
      },
    );

    test('a GET sent to /login logs in again with a new client and is '
        'retried once', () async {
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
      expect(attempts, 2);
      expect(clientsCreated, 2, reason: 'a new client for the new login');
      expect(server.requests.first, 'GET /some/page');
      expect(server.requests.last, 'GET /some/page');
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
    });

    test('concurrent calls that find it expired share one new login, and '
        'each is retried once', () async {
      final session = newSession();
      await session.run(_post);
      server
        ..expireSession()
        ..latency = const Duration(milliseconds: 20);
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
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(2));
      expect(clientsCreated, 2);
      expect(attempts, {'GET a': 2, 'GET b': 2, 'GET c': 2, 'POST': 2});
    });

    test('requests of one call that find it expired at the same time share '
        'one new login, and the call is retried once', () async {
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
      expect(attempts, 2);
      expect(clientsCreated, 2);
    });

    test('a call that starts after the new login uses the new client without '
        'logging in again', () async {
      final session = newSession();
      await session.run(_post);
      server.expireSession();
      await session.run((client) => client.getRaw('/a'));
      server.requests.clear();

      await session.run((client) => client.getRaw('/b'));

      expect(server.logins, 2);
      expect(clientsCreated, 2);
      expect(server.requests, ['GET /b']);
    });

    test('a request that is still refused after logging in again is not '
        'retried a second time', () async {
      final session = newSession();
      var attempts = 0;

      await expectLater(
        session.run((client) {
          attempts++;
          return client.postFormRaw('/always-401', {});
        }),
        throwsA(_problem(ProblemKind.sessionRejected)),
      );
      expect(attempts, 2);
    });
  });

  group('when Smartschool still sends the first request after a successful '
      'login to /login', () {
    test(
      'checks once more with a new client, without logging in again',
      () async {
        server.rejectsAfterLogin = 1;
        final session = newSession();

        expect(await session.run(_post), '<ok/>');

        expect(server.logins, 1);
        expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
        expect(clientsCreated, 2);
      },
    );

    test('gives up when the new client is refused too, still without a '
        'second login', () async {
      server.rejectsAfterLogin = 2;
      final session = newSession();

      await expectLater(
        session.run(_post),
        throwsA(_problem(ProblemKind.sessionRejected)),
      );

      expect(server.logins, 1);
      expect(server.requests.where((r) => r == 'POST /login'), hasLength(1));
      expect(server.requests, isNot(contains('POST /some/form')));
    });

    test('also when logging in again after the session expired', () async {
      final session = newSession();
      await session.run(_post);
      server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      expect(await session.run(_post), '<ok/>');

      expect(server.logins, 2);
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
