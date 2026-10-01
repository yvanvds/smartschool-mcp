import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'settings.dart';

/// Why logging in to or talking to Smartschool failed.
enum ProblemKind {
  /// One or more settings are empty.
  missingSettings(permanent: true),

  /// The file named with `--credentials` does not exist.
  credentialsFileMissing(permanent: true),

  /// The file named with `--credentials` is not a valid credentials file.
  credentialsFileInvalid(permanent: true),

  /// The 2FA key in the settings cannot be a TOTP secret (not Base32, or a
  /// code of the authenticator app): found before logging in, see
  /// [SmartschoolSettings.mfaProblem].
  twoFactorKeyInvalid(permanent: true),

  /// Smartschool rejected the username or password.
  wrongPassword(permanent: true),

  /// Smartschool rejected the 2FA code: wrong key, or a wrong PC clock.
  twoFactorRejected(permanent: true),

  /// The account uses a 2FA method other than an authenticator app.
  twoFactorUnsupported(permanent: true),

  /// Smartschool asks for account verification (date of birth) instead of
  /// a 2FA code.
  accountVerification(permanent: true),

  /// Smartschool could not be reached: no network, or a wrong address.
  unreachable(permanent: false),

  /// Smartschool did not accept the session (for example after it expired).
  sessionRejected(permanent: false),

  /// Anything else.
  unexpected(permanent: false);

  const ProblemKind({required this.permanent});

  /// Whether retrying in the same process is pointless: the settings can
  /// only change with a restart, and repeating a rejected login risks
  /// locking the account.
  final bool permanent;
}

/// A failure to log in to or talk to Smartschool, with a message for the
/// teacher.
///
/// The message names the setting to fix by its title in the install form (or
/// its key in the credentials file). It never contains a secret, a stack
/// trace or raw server output; those go to the log.
final class SmartschoolProblem implements Exception {
  const SmartschoolProblem(this.kind, this.message);

  /// The message for [kind], naming the settings of [settings].
  factory SmartschoolProblem.of(
    ProblemKind kind,
    SmartschoolSettings settings,
  ) {
    final source = settings.source;
    String name(Setting setting) => source.name(setting);
    final restart = source.restart;
    return SmartschoolProblem(kind, switch (kind) {
      ProblemKind.missingSettings => _missing(source, settings.missing),
      ProblemKind.credentialsFileMissing ||
      ProblemKind.credentialsFileInvalid => throw ArgumentError.value(
        kind,
        'kind',
        'use SmartschoolProblem.credentialsFile',
      ),
      ProblemKind.twoFactorKeyInvalid =>
        'The two-factor authentication (2FA) key is not valid, so Smartschool '
            'was not contacted. Check ${name(Setting.mfa)} ${source.where}: '
            'it must be the key Smartschool shows when you add an '
            'authenticator app, made of letters and the digits 2 to 7 (spaces '
            'do not matter), not the 6-digit code the app shows. Then '
            '$restart.',
      ProblemKind.wrongPassword =>
        'Smartschool did not accept the username or password. Check '
            '${name(Setting.username)} and ${name(Setting.password)} '
            '${source.where}, then $restart. Accounts that can only sign in '
            'through Microsoft or Google (single sign-on) are not supported.',
      ProblemKind.twoFactorRejected =>
        'Smartschool rejected the two-factor authentication (2FA) code. '
            'Check ${name(Setting.mfa)} ${source.where}: it must be the key '
            'Smartschool shows when you add an authenticator app, not a '
            '6-digit code. Also check that the clock of this PC is correct '
            '(Windows Settings → Time & language → Set time automatically): '
            'the codes depend on it. Then $restart.',
      ProblemKind.twoFactorUnsupported =>
        'Smartschool asks for a kind of two-factor authentication (2FA) this '
            'extension cannot handle. It only works with an authenticator '
            'app: set one up in your Smartschool profile, enter its key in '
            '${name(Setting.mfa)} ${source.where}, then $restart.',
      ProblemKind.accountVerification =>
        'Smartschool asks for account verification (a date of birth) '
            'instead of a two-factor authentication (2FA) code. That usually '
            'means 2FA with an authenticator app is not set up for this '
            'account. Set it up in your Smartschool profile, enter its key in '
            '${name(Setting.mfa)} ${source.where}, then $restart.',
      ProblemKind.unreachable =>
        'Could not reach Smartschool at ${settings.host}. Check the internet '
            'connection of this PC, and check that ${name(Setting.mainUrl)} '
            '${source.where} is the address of your school\'s Smartschool '
            '(like school.smartschool.be).',
      ProblemKind.sessionRejected =>
        'Smartschool did not accept the login session. Try again in a '
            'moment. If it keeps happening, $restart.',
      ProblemKind.unexpected =>
        'Talking to Smartschool failed with an unexpected error. Try again '
            'in a moment. If it keeps happening, $restart; the technical '
            'details are in the server log.',
    });
  }

  /// The message for a credentials file that is missing or unreadable.
  factory SmartschoolProblem.credentialsFile(CredentialsFileException error) =>
      error.exists
      ? SmartschoolProblem(
          ProblemKind.credentialsFileInvalid,
          'The credentials file ${error.path} (given with --credentials) '
          'could not be read. It must be YAML with the keys main_url, '
          'username, password and mfa. Fix it, then restart the server.',
        )
      : SmartschoolProblem(
          ProblemKind.credentialsFileMissing,
          'The credentials file ${error.path} (given with --credentials) '
          'does not exist. Fix the path or create the file with the keys '
          'main_url, username, password and mfa, then restart the server.',
        );

  final ProblemKind kind;

  /// What went wrong and how to fix it, for the teacher.
  final String message;

  @override
  String toString() => message;

  static String _missing(CredentialSource source, List<Setting> missing) {
    final names = missing.map(source.name).join(', ');
    return 'Not all Smartschool settings are filled in. Missing: $names. '
        'Fill ${missing.length == 1 ? 'it' : 'them'} in ${source.where}, '
        'then ${source.restart}.';
  }
}

/// Classifies [error] as a login or connection problem.
///
/// Returns null when [error] is something else (for example a tool-specific
/// failure), which the caller handles itself.
///
/// The library throws each login failure as its own subclass of
/// [SmartschoolAuthenticationError] (yvanvds/dartschool#11), an unreachable
/// Smartschool as a [SmartschoolConnectionError], and a session Smartschool
/// refused, also after the library logged in again where it could, as a
/// [SmartschoolSessionExpiredError]. Any other
/// [SmartschoolAuthenticationError] (an unknown step in the login chain, an
/// HTML page where data was expected) is [ProblemKind.unexpected].
/// `test/problems_test.dart` drives the library's real login chain against a
/// fake Smartschool, so a library update that throws another type fails a
/// test. A request made on `client.dio` directly still fails with the plain
/// [DioException], which carries the library's error.
ProblemKind? classifyFailure(Object error) {
  switch (error) {
    case SmartschoolProblem(:final kind):
      return kind;
    case DioException(error: final Object inner) when inner is! DioException:
      final kind = classifyFailure(inner);
      if (kind != null) return kind;
      return _classifyDio(error);
    case DioException():
      return _classifyDio(error);
    case SocketException() ||
        TlsException() ||
        HttpException() ||
        TimeoutException() ||
        SmartschoolConnectionError():
      return ProblemKind.unreachable;
    case SmartschoolSessionExpiredError():
      return ProblemKind.sessionRejected;
    case SmartschoolInvalidCredentialsError():
      return ProblemKind.wrongPassword;
    // A missing TOTP secret cannot happen: an empty key is caught as a
    // missing setting first. Nor can a key that is not Base32, which the
    // library reports as a bare FormatException (yvanvds/dartschool#79):
    // SmartschoolSettings.mfaProblem catches it first.
    case SmartschoolTwoFactorRejectedError() ||
        SmartschoolTwoFactorRequiredError():
      return ProblemKind.twoFactorRejected;
    case SmartschoolUnsupportedTwoFactorMethodError():
      return ProblemKind.twoFactorUnsupported;
    case SmartschoolAccountVerificationRequiredError() ||
        SmartschoolAccountVerificationRejectedError():
      return ProblemKind.accountVerification;
    case SmartschoolAuthenticationError():
      return ProblemKind.unexpected;
  }
  return null;
}

ProblemKind? _classifyDio(DioException error) => switch (error.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.connectionError ||
  DioExceptionType.badCertificate => ProblemKind.unreachable,
  _ => null,
};
