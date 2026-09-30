import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/problems.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

/// Logs in with the library's real login chain against [server] and returns
/// what the login threw.
Future<Object> _loginError(FakeSmartschool server) async {
  final client = await fakeClientFactory(server, await tempCache())(
    FakeCredentials(),
  );
  try {
    await client.platformId;
  } catch (error) {
    return error;
  }
  fail('the login succeeded');
}

void main() {
  group('classifyFailure of what the library throws when logging in', () {
    // These go through the library's real auth interceptor, so they break
    // when a library update changes how it reports a failure.
    test('a rejected password', () async {
      final error = await _loginError(FakeSmartschool(passwordAccepted: false));
      expect(classifyFailure(error), ProblemKind.wrongPassword);
    });

    test('a rejected 2FA code', () async {
      final error = await _loginError(
        FakeSmartschool(twoFactorAccepted: false),
      );
      expect(classifyFailure(error), ProblemKind.twoFactorRejected);
    });

    test('2FA without an authenticator app', () async {
      final error = await _loginError(
        FakeSmartschool(secondStep: SecondStep.twoFactorWithoutApp),
      );
      expect(classifyFailure(error), ProblemKind.twoFactorUnsupported);
    });

    test('account verification instead of 2FA', () async {
      final error = await _loginError(
        FakeSmartschool(secondStep: SecondStep.accountVerification),
      );
      expect(classifyFailure(error), ProblemKind.accountVerification);
    });

    test('an unreachable host', () async {
      final error = await _loginError(FakeSmartschool()..unreachable = true);
      expect(classifyFailure(error), ProblemKind.unreachable);
    });
  });

  group('classifyFailure of other errors', () {
    test('network failures are "unreachable"', () {
      final request = RequestOptions(path: '/');
      for (final error in [
        const SocketException('Failed host lookup'),
        const HandshakeException('bad certificate'),
        TimeoutException('slow'),
        DioException.connectionTimeout(
          requestOptions: request,
          timeout: const Duration(seconds: 30),
        ),
        DioException(
          requestOptions: request,
          error: const SocketException('Connection refused'),
        ),
      ]) {
        expect(
          classifyFailure(error),
          ProblemKind.unreachable,
          reason: '$error',
        );
      }
    });

    test('a rejected session: a 401, or HTML where data was expected', () {
      expect(
        classifyFailure(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            error: const SessionExpiredError(),
          ),
        ),
        ProblemKind.sessionRejected,
      );
      expect(
        classifyFailure(
          const SmartschoolAuthenticationError(
            'Smartschool returned HTML instead of XML for "message list". '
            'Login may have failed or expired.',
          ),
        ),
        ProblemKind.sessionRejected,
      );
      expect(
        classifyFailure(
          const SmartschoolAuthenticationError(
            'Expected JSON but received HTML from https://x/y. Session may be '
            'unauthenticated or login flow did not complete.',
          ),
        ),
        ProblemKind.sessionRejected,
      );
    });

    test('other authentication errors are "unexpected"', () {
      expect(
        classifyFailure(
          const SmartschoolAuthenticationError(
            'Maximum login attempts reached',
          ),
        ),
        ProblemKind.unexpected,
      );
    });

    test('a SmartschoolProblem keeps its kind', () {
      expect(
        classifyFailure(
          const SmartschoolProblem(ProblemKind.unreachable, 'offline'),
        ),
        ProblemKind.unreachable,
      );
    });

    test('anything else is not a login or connection problem', () {
      final request = RequestOptions(path: '/');
      for (final error in [
        const SmartschoolParsingError('bad XML'),
        StateError('bug'),
        DioException(requestOptions: request, error: StateError('bug')),
        DioException.badResponse(
          statusCode: 500,
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 500),
        ),
      ]) {
        expect(classifyFailure(error), isNull, reason: '$error');
      }
    });
  });

  group('SmartschoolProblem messages', () {
    final fromExtension = SmartschoolSettings.read(fakeExtensionSettings());
    late SmartschoolSettings fromFile;
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('smartschool_msg_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}credentials.yml')
        ..writeAsStringSync(
          'username: jan.peeters\n'
          'password: $fakePassword\n'
          'main_url: $fakeHost\n'
          'mfa: $fakeTotpSecret\n',
        );
      fromFile = SmartschoolSettings.read(CredentialsFile(file.path));
    });

    String message(ProblemKind kind, [SmartschoolSettings? settings]) =>
        SmartschoolProblem.of(kind, settings ?? fromExtension).message;

    final loginKinds = [
      for (final kind in ProblemKind.values)
        if (kind != ProblemKind.credentialsFileMissing &&
            kind != ProblemKind.credentialsFileInvalid &&
            kind != ProblemKind.missingSettings)
          kind,
    ];

    test('each kind has its own message', () {
      final messages = loginKinds.map(message).toSet();
      expect(messages, hasLength(loginKinds.length));
    });

    test('never contain the password or the 2FA key', () {
      for (final settings in [fromExtension, fromFile]) {
        for (final kind in loginKinds) {
          final text = message(kind, settings);
          expect(text.contains(fakePassword), isFalse, reason: kind.name);
          expect(text.contains(fakeTotpSecret), isFalse, reason: kind.name);
        }
      }
    });

    test('name the settings to fix by their install-form title', () {
      expect(
        message(ProblemKind.wrongPassword),
        allOf(
          contains('"Gebruikersnaam" (SMARTSCHOOL_USERNAME)'),
          contains('"Wachtwoord" (SMARTSCHOOL_PASSWORD)'),
          contains('extension settings in Claude Desktop'),
          contains('restart Claude Desktop'),
        ),
      );
      for (final kind in [
        ProblemKind.twoFactorRejected,
        ProblemKind.twoFactorUnsupported,
        ProblemKind.accountVerification,
      ]) {
        expect(
          message(kind),
          contains('"2FA-sleutel" (SMARTSCHOOL_MFA)'),
          reason: kind.name,
        );
      }
      expect(
        message(ProblemKind.unreachable),
        allOf(
          contains(fakeHost),
          contains('"Smartschool-adres" (SMARTSCHOOL_MAIN_URL)'),
        ),
      );
    });

    test('a rejected 2FA code points at the PC clock', () {
      expect(message(ProblemKind.twoFactorRejected), contains('clock'));
    });

    test('account verification says what Smartschool asks for', () {
      expect(
        message(ProblemKind.accountVerification),
        contains('account verification (a date of birth)'),
      );
    });

    test('name the settings by their key in a credentials file', () {
      expect(
        message(ProblemKind.wrongPassword, fromFile),
        allOf(
          contains('username and password'),
          contains(
            'in the credentials file '
            '${(fromFile.source as CredentialsFile).path}',
          ),
          contains('restart the server'),
        ),
      );
    });

    test('missing settings lists exactly the empty ones', () {
      final settings = SmartschoolSettings.read(
        fakeExtensionSettings(FakeCredentials(password: '', mfa: '')),
      );

      final text = message(ProblemKind.missingSettings, settings);

      expect(
        text,
        contains(
          'Missing: "Wachtwoord" (SMARTSCHOOL_PASSWORD), '
          '"2FA-sleutel" (SMARTSCHOOL_MFA)',
        ),
      );
      expect(text, isNot(contains('Gebruikersnaam')));
      expect(text, isNot(contains('Smartschool-adres')));
    });

    test('a missing or unreadable credentials file names the file', () {
      final missing = SmartschoolProblem.credentialsFile(
        const CredentialsFileException(r'C:\dev\x.yml', exists: false),
      );
      final invalid = SmartschoolProblem.credentialsFile(
        const CredentialsFileException(
          r'C:\dev\x.yml',
          exists: true,
          cause: 'YamlException',
        ),
      );

      expect(missing.kind, ProblemKind.credentialsFileMissing);
      expect(missing.message, contains(r'C:\dev\x.yml'));
      expect(missing.message, contains('does not exist'));
      expect(invalid.kind, ProblemKind.credentialsFileInvalid);
      expect(invalid.message, contains('could not be read'));
      expect(invalid.message, isNot(equals(missing.message)));
    });
  });
}
