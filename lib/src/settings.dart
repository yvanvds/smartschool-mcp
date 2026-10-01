import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:yaml/yaml.dart';

/// A setting of the server: the four values it needs to log in to
/// Smartschool ([login]), and the optional download folder.
///
/// [formTitle] is the field's title in the Claude Desktop extension's install
/// form. The extension manifest (`manifest.json`, its `user_config` keyed by
/// [fileKey]) must use exactly these titles, because the error messages tell
/// the teacher which field to fix by that name; `test/manifest_test.dart`
/// checks it.
enum Setting {
  mainUrl('Smartschool-adres', 'SMARTSCHOOL_MAIN_URL', 'main_url'),
  username('Gebruikersnaam', 'SMARTSCHOOL_USERNAME', 'username'),
  password('Wachtwoord', 'SMARTSCHOOL_PASSWORD', 'password'),
  mfa('2FA-sleutel', 'SMARTSCHOOL_MFA', 'mfa'),

  /// The folder `save_intradesk_file` and `save_message_attachment` save
  /// into; optional (see `DownloadFolder.resolve`). In the extension
  /// manifest a `directory` field, so the install form shows a folder
  /// picker.
  downloadDir(
    'Downloadmap',
    'SMARTSCHOOL_DOWNLOAD_DIR',
    'download_dir',
    required: false,
  );

  const Setting(
    this.formTitle,
    this.envVar,
    this.fileKey, {
    this.required = true,
  });

  /// The title of the field in the extension's install form.
  final String formTitle;

  /// The environment variable Claude Desktop fills from that field.
  final String envVar;

  /// The key in a `credentials.yml` file (the library's `PathCredentials`
  /// for the login settings).
  final String fileKey;

  /// Whether the server needs it to log in.
  final bool required;

  /// The settings the server needs to log in, in form order.
  static final List<Setting> login = [
    for (final setting in values)
      if (setting.required) setting,
  ];
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

  /// The download folder in the file ([Setting.downloadDir]'s key), or null
  /// when it has none, or when the file cannot be read: [read] reports
  /// that.
  String? downloadDirectory() {
    try {
      final yaml = loadYaml(File(path).readAsStringSync());
      if (yaml is! YamlMap) return null;
      final value = yaml[Setting.downloadDir.fileKey];
      return value is String ? value : null;
    } catch (_) {
      // Never the message: a YAML error quotes the file, which holds the
      // password.
      return null;
    }
  }
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
/// Smartschool address reduced to a host name and the 2FA key without white
/// space.
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
      mfa: normalizeTotpSecret(credentials.mfa ?? ''),
    );
  }

  final CredentialSource source;

  /// The Smartschool host name, e.g. `school.smartschool.be`.
  final String host;
  final String username;
  final String password;

  /// The TOTP secret (Base32), without white space: see
  /// [normalizeTotpSecret].
  final String mfa;

  /// Why [mfa] cannot be a TOTP secret, in a few words for the log (it never
  /// quotes the key); null when it can be one, or when it is empty (see
  /// [missing]).
  ///
  /// Checked before logging in: the library would post the password first
  /// and then fail on the key with a bare `FormatException`, on every
  /// attempt (yvanvds/dartschool#79). See [isTotpSecret].
  String? get mfaProblem => mfa.isEmpty || isTotpSecret(mfa)
      ? null
      : _base32.hasMatch(mfa)
      ? 'digits only, like a code of the authenticator app'
      : 'not Base32: a character other than the letters A to Z, the digits '
            '2 to 7 and "=" padding at the end';

  /// The login settings that are empty, in form order. All four are
  /// required: MFA is mandatory for teachers.
  List<Setting> get missing => [
    if (host.isEmpty) Setting.mainUrl,
    if (username.isEmpty) Setting.username,
    if (password.isEmpty) Setting.password,
    if (mfa.isEmpty) Setting.mfa,
  ];

  /// The credentials for the library. Only valid when [missing] is empty.
  Credentials toCredentials() => AppCredentials(
    username: username,
    password: password,
    mainUrl: host,
    mfa: mfa,
  );

  /// Removes all white space from a 2FA key, so that a key copied the way
  /// authenticator setup screens often show it, in groups
  /// (`JBSW Y3DP EHPK 3PXP`), works: authenticator apps ignore the spaces
  /// too.
  ///
  /// A workaround for yvanvds/dartschool#79: the library passes the key on
  /// unchanged, and the otp package rejects white space. Remove it, with
  /// [mfaProblem], once the library normalises and checks the key itself
  /// (yvanvds/smartschool-mcp#34).
  static String normalizeTotpSecret(String key) =>
      key.replaceAll(RegExp(r'\s'), '');

  /// Whether [key], without white space, can be a TOTP secret: RFC 4648
  /// Base32 in upper or lower case (the library upper-cases it, and
  /// authenticator apps take either), optionally with `=` padding at the end
  /// (which the library accepts), and not digits only.
  ///
  /// Digits only is a code of the authenticator app typed instead of its
  /// key: a 6-digit code made of the digits 2 to 7 is valid Base32, but a
  /// random 16-character key has no letter at all with a chance of less than
  /// 1 in 10^11.
  static bool isTotpSecret(String key) =>
      _base32.hasMatch(key) && key.contains(RegExp('[A-Za-z]'));

  static final _base32 = RegExp(r'^[A-Za-z2-7]+=*$');

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
