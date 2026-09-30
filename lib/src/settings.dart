import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';

/// One of the four values the server needs to log in to Smartschool.
///
/// [formTitle] is the field's title in the Claude Desktop extension's install
/// form. The extension manifest must use exactly these titles, because the
/// error messages tell the teacher which field to fix by that name.
enum Setting {
  mainUrl('Smartschool-adres', 'SMARTSCHOOL_MAIN_URL', 'main_url'),
  username('Gebruikersnaam', 'SMARTSCHOOL_USERNAME', 'username'),
  password('Wachtwoord', 'SMARTSCHOOL_PASSWORD', 'password'),
  mfa('2FA-sleutel', 'SMARTSCHOOL_MFA', 'mfa');

  const Setting(this.formTitle, this.envVar, this.fileKey);

  /// The title of the field in the extension's install form.
  final String formTitle;

  /// The environment variable Claude Desktop fills from that field.
  final String envVar;

  /// The key in a `credentials.yml` file (the library's `PathCredentials`).
  final String fileKey;
}

/// Where the Smartschool settings come from.
sealed class CredentialSource {
  const CredentialSource();

  /// Reads the credentials.
  ///
  /// Throws a [CredentialsFileException] when a credentials file is missing
  /// or unreadable.
  Credentials read();

  /// Short name of the source, e.g. `extension settings`.
  String get label;

  /// How [setting] is called in this source, for messages to the teacher.
  String name(Setting setting);

  /// Where the teacher fixes a setting, e.g. `in the credentials file X`.
  String get where;

  /// What the teacher restarts after fixing a setting.
  String get restart;

  /// One line for the startup log saying which source is used.
  String get logDescription;
}

/// The settings of the Claude Desktop extension, which Claude Desktop passes
/// as `SMARTSCHOOL_*` environment variables (the library's
/// [EnvCredentials]).
final class ExtensionSettings extends CredentialSource {
  /// [read] defaults to [EnvCredentials]; tests pass their own.
  const ExtensionSettings({Credentials Function()? read}) : _read = read;

  final Credentials Function()? _read;

  @override
  Credentials read() => (_read ?? EnvCredentials.new)();

  @override
  String get label => 'extension settings';

  @override
  String name(Setting setting) => '"${setting.formTitle}" (${setting.envVar})';

  @override
  String get where =>
      'in the Smartschool extension settings in Claude Desktop '
      '(Settings → Extensions)';

  @override
  String get restart => 'restart Claude Desktop';

  @override
  String get logDescription =>
      'extension settings (SMARTSCHOOL_* environment variables)';
}

/// A `credentials.yml` file named with `--credentials`, for development.
///
/// Only the given file is read. The library's [PathCredentials] would fall
/// back to searching the working directory, its parents and the home
/// directory, so the file's existence is checked first.
final class CredentialsFile extends CredentialSource {
  /// [path] is resolved against the current directory.
  CredentialsFile(String path) : path = File(path).absolute.path;

  /// The absolute path of the file.
  final String path;

  @override
  Credentials read() {
    if (!File(path).existsSync()) {
      throw CredentialsFileException(path, exists: false);
    }
    try {
      return PathCredentials(filename: path);
    } catch (error) {
      // Only the type: a YAML error message quotes the offending line, which
      // may hold the password.
      throw CredentialsFileException(
        path,
        exists: true,
        cause: error.runtimeType.toString(),
      );
    }
  }

  @override
  String get label => 'credentials file';

  @override
  String name(Setting setting) => setting.fileKey;

  @override
  String get where => 'in the credentials file $path';

  @override
  String get restart => 'restart the server';

  @override
  String get logDescription => 'credentials file $path (--credentials)';
}

/// A credentials file named with `--credentials` could not be used.
final class CredentialsFileException implements Exception {
  const CredentialsFileException(this.path, {required this.exists, this.cause});

  final String path;

  /// False when the file does not exist, true when it could not be parsed.
  final bool exists;

  /// The type of the parse error, never its message (see
  /// [CredentialsFile.read]).
  final String? cause;

  @override
  String toString() => exists
      ? 'CredentialsFileException: cannot parse $path ($cause)'
      : 'CredentialsFileException: $path does not exist';
}

/// The settings as read from a [CredentialSource]: trimmed, with the
/// Smartschool address reduced to a host name.
final class SmartschoolSettings {
  SmartschoolSettings._(
    this.source, {
    required this.host,
    required this.username,
    required this.password,
    required this.mfa,
  });

  /// Reads the settings from [source].
  ///
  /// Throws a [CredentialsFileException] when a credentials file is missing
  /// or unreadable. Empty settings are not an error here: see [missing].
  factory SmartschoolSettings.read(CredentialSource source) {
    final credentials = source.read();
    return SmartschoolSettings._(
      source,
      host: normalizeHost(credentials.mainUrl),
      username: credentials.username.trim(),
      password: credentials.password.trim(),
      mfa: (credentials.mfa ?? '').trim(),
    );
  }

  final CredentialSource source;

  /// The Smartschool host name, e.g. `school.smartschool.be`.
  final String host;
  final String username;
  final String password;

  /// The TOTP secret (Base32).
  final String mfa;

  /// The settings that are empty, in form order. All four are required: MFA
  /// is mandatory for teachers.
  List<Setting> get missing => [
    for (final setting in Setting.values)
      if (_value(setting).isEmpty) setting,
  ];

  String _value(Setting setting) => switch (setting) {
    Setting.mainUrl => host,
    Setting.username => username,
    Setting.password => password,
    Setting.mfa => mfa,
  };

  /// The credentials for the library. Only valid when [missing] is empty.
  Credentials toCredentials() => AppCredentials(
    username: username,
    password: password,
    mainUrl: host,
    mfa: mfa,
  );

  /// Reduces what a teacher may type as the Smartschool address
  /// (`https://school.smartschool.be/`, with spaces, ...) to the host name
  /// the library expects.
  static String normalizeHost(String address) {
    var host = address.trim().replaceFirst(
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'),
      '',
    );
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    return host.trim();
  }
}
