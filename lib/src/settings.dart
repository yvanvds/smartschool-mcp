import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:yaml/yaml.dart';

import 'client_app.dart';

/// A setting of the server: the four values it logs in to Smartschool with
/// ([login]), the optional download folder, and the opt-in switches
/// ([switches]) that turn on tools only some accounts can use.
///
/// Of the four, the 2FA key is optional: only an account with two-factor
/// authentication (2FA), such as a teacher's, needs it. Students sign in
/// with only their password.
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

  /// The TOTP secret of the authenticator app, for an account with 2FA; an
  /// account without it leaves it empty. When Smartschool asks for a 2FA
  /// code and it is empty, the login fails with
  /// `ProblemKind.twoFactorKeyMissing`.
  mfa('2FA-sleutel', 'SMARTSCHOOL_MFA', 'mfa', required: false),

  /// The folder `save_intradesk_file` and `save_message_attachment` save
  /// into; optional (see `DownloadFolder.resolve`). In the extension
  /// manifest a `directory` field, so the install form shows a folder
  /// picker.
  downloadDir(
    'Downloadmap',
    'SMARTSCHOOL_DOWNLOAD_DIR',
    'download_dir',
    required: false,
    forLogin: false,
  ),

  /// The switch for the Skore tools (`lib/src/skore/`), for an account with
  /// the rights for score management in Skore, as a Skore administrator
  /// has. Off by default (#42).
  skore(
    'Skore-beheer',
    'SMARTSCHOOL_SKORE',
    'skore',
    required: false,
    forLogin: false,
    isSwitch: true,
  );

  const Setting(
    this.formTitle,
    this.envVar,
    this.fileKey, {
    this.required = true,
    this.forLogin = true,
    this.isSwitch = false,
  });

  /// The title of the field in the extension's install form.
  final String formTitle;

  /// The environment variable Claude Desktop fills from that field, and the
  /// key the teacher enters in ChatGPT's form for the MCP server.
  final String envVar;

  /// The key in a `credentials.yml` file (the library's `PathCredentials`
  /// for the login settings).
  final String fileKey;

  /// Whether it must be filled in: the server does not log in without it
  /// ([SmartschoolSettings.missing]).
  final bool required;

  /// Whether the server logs in with it ([login]).
  final bool forLogin;

  /// Whether it is an opt-in switch: on or off, off by default, and only
  /// when it is on does the server offer a group of tools that only some
  /// accounts can use (`OptInTools` in `opt_in.dart`). In the extension
  /// manifest a `boolean` field with the default `false`, which Claude
  /// Desktop passes as `true` or `false`; read with [Switches.read].
  final bool isSwitch;

  /// The settings the server logs in with, in form order: the required
  /// ones and the optional 2FA key.
  static final List<Setting> login = [
    for (final setting in values)
      if (setting.forLogin) setting,
  ];

  /// The opt-in switches ([isSwitch]), in form order.
  static final List<Setting> switches = [
    for (final setting in values)
      if (setting.isSwitch) setting,
  ];
}

/// What an opt-in switch ([Setting.isSwitch]) is set to.
enum SwitchState {
  /// Turned on: `true` (also `1`, `yes`, `on`, and in Dutch `ja`, `aan`).
  on,

  /// Turned off: not set, empty, or `false` (also `0`, `no`, `off`, `nee`,
  /// `uit`).
  off,

  /// Set to something that is neither on nor off: taken as off, and
  /// `smartschool_status` says so.
  unclear;

  bool get isOn => this == on;

  /// The state [value] sets: a value as typed or passed in an environment
  /// variable (any case, spaces around it ignored), or as YAML reads it
  /// from a credentials file (a `bool`, a number or a string); null is not
  /// set, so [off].
  static SwitchState parse(Object? value) {
    if (value == null) return off;
    final text = '$value'.trim().toLowerCase();
    if (_on.contains(text)) return on;
    if (text.isEmpty || _off.contains(text)) return off;
    return unclear;
  }

  static const _on = {'true', '1', 'yes', 'on', 'ja', 'aan'};
  static const _off = {'false', '0', 'no', 'off', 'nee', 'uit'};
}

/// The opt-in switches ([Setting.switches]) as set when the server starts:
/// it decides then which tools it offers.
final class Switches {
  /// Switches in [states]; every other switch is off.
  const Switches([this._states = const {}]);

  /// The switches set for [source], with [environment] (this process's by
  /// default): each switch's environment variable when it is set and not
  /// empty, else (with a credentials file) the file's key, else off. The
  /// environment variable comes first, as for the download folder, so a
  /// developer can turn a switch on for a server started with
  /// `--credentials` without changing the file.
  factory Switches.read(
    CredentialSource source, {
    Map<String, String>? environment,
  }) {
    final variables = environment ?? Platform.environment;
    return Switches({
      for (final setting in Setting.switches)
        setting: switch (variables[setting.envVar]) {
          final value? when value.trim().isNotEmpty => SwitchState.parse(value),
          _ => switch (source) {
            CredentialsFile() => SwitchState.parse(source.value(setting)),
            ExtensionSettings() => SwitchState.off,
          },
        },
    });
  }

  final Map<Setting, SwitchState> _states;

  /// What [setting], a switch, is set to.
  SwitchState operator [](Setting setting) =>
      _states[setting] ?? SwitchState.off;

  /// Whether [setting], a switch, is on.
  bool isOn(Setting setting) => this[setting].isOn;
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

  /// Settings given under a name that is not a setting's, such as a key
  /// mistyped in ChatGPT's form; none for most sources.
  List<MisnamedSetting> get misnamed => const [];
}

/// The settings as `SMARTSCHOOL_*` environment variables (the library's
/// [EnvCredentials]).
///
/// Claude Desktop fills them from the extension's install form. In ChatGPT
/// and Codex the teacher enters them as the environment variables of the
/// MCP server. The messages say where to fix them in the app [client] names.
final class ExtensionSettings extends CredentialSource {
  /// [read] defaults to [EnvCredentials] and [environment] to this process's
  /// environment; tests pass their own. Without [client], the messages are
  /// for Claude Desktop.
  const ExtensionSettings({
    this.client,
    Credentials Function()? read,
    Map<String, String> Function()? environment,
  }) : _read = read,
       _environment = environment;

  /// The app the server runs in.
  final ClientContext? client;

  final Credentials Function()? _read;
  final Map<String, String> Function()? _environment;

  ClientApp get _app => client?.app ?? ClientApp.claudeDesktop;

  @override
  Credentials read() => (_read ?? EnvCredentials.new)();

  @override
  String get label => switch (_app) {
    ClientApp.claudeDesktop => 'extension settings',
    ClientApp.codex => 'environment variables of the MCP server',
  };

  @override
  String name(Setting setting) => switch (_app) {
    ClientApp.claudeDesktop => '"${setting.formTitle}" (${setting.envVar})',
    // ChatGPT's form shows the variable, which the teacher typed.
    ClientApp.codex => '${setting.envVar} ("${setting.formTitle}")',
  };

  @override
  String get where => switch (_app) {
    ClientApp.claudeDesktop =>
      'in the Smartschool extension settings in Claude Desktop '
          '(Settings → Extensions)',
    ClientApp.codex =>
      'in the ChatGPT app, under Instellingen (Settings) → Plug-ins → '
          "MCP's → ${ClientApp.codexServerName} → Omgevingsvariabelen "
          '(Environment variables); in the Codex CLI or IDE extension, under '
          '[mcp_servers.${ClientApp.codexServerName}.env] in '
          r'%USERPROFILE%\.codex\config.toml',
  };

  @override
  String get restart => switch (_app) {
    ClientApp.claudeDesktop => 'restart Claude Desktop',
    ClientApp.codex => 'restart ChatGPT (or Codex)',
  };

  @override
  String get logDescription =>
      'extension settings (SMARTSCHOOL_* environment variables)';

  @override
  List<MisnamedSetting> get misnamed =>
      MisnamedSetting.find((_environment ?? () => Platform.environment)().keys);
}

/// An environment variable that looks like a setting but is not one, such
/// as `SMARTSCHOOL_MAINURL`, or `SMARTSCHOOL_MFA ` with a space: a key
/// mistyped in ChatGPT's form, where the teacher types the names.
///
/// Codex starts the server with a cleared environment (a fixed list of
/// Windows variables, `WINDOWS_CORE_ENV_VARS` in
/// `codex-rs/protocol/src/shell_environment.rs`, plus the server's own), so
/// there such a variable comes from the form.
final class MisnamedSetting {
  const MisnamedSetting(this.name, this.meant);

  /// The variable's name as set.
  final String name;

  /// The setting it most likely means, or null when none is close.
  final Setting? meant;

  /// The variables in [names] that are not a setting but look like one:
  /// the name without case, spaces and punctuation is close to a setting's
  /// (at most [_maxDistance] edits), or starts with `SMARTSCHOOL`. Names
  /// are compared without case, as Windows does. The server's own
  /// variables (`SMARTSCHOOL_MCP_*`) and the tests' (`SMARTSCHOOL_LIVE_*`)
  /// are not settings to begin with.
  static List<MisnamedSetting> find(Iterable<String> names) =>
      [for (final name in names) ?_misnamed(name)]
        ..sort((a, b) => a.name.compareTo(b.name));

  /// How many letters a name may differ from a setting's to be taken as
  /// that setting.
  static const _maxDistance = 3;

  static MisnamedSetting? _misnamed(String name) {
    final upper = name.toUpperCase();
    if (Setting.values.any((setting) => setting.envVar == upper) ||
        upper.startsWith('SMARTSCHOOL_MCP_') ||
        upper.startsWith('SMARTSCHOOL_LIVE_')) {
      return null;
    }
    final compact = _compact(upper);
    Setting? closest;
    var distance = _maxDistance + 1;
    for (final setting in Setting.values) {
      final d = _distance(compact, _compact(setting.envVar));
      if (d < distance) (closest, distance) = (setting, d);
    }
    if (closest != null) return MisnamedSetting(name, closest);
    return compact.startsWith('SMARTSCHOOL')
        ? MisnamedSetting(name, null)
        : null;
  }

  static String _compact(String name) =>
      name.replaceAll(RegExp('[^A-Z0-9]'), '');

  /// The Levenshtein distance between [a] and [b].
  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, i);
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          substitution,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  /// A sentence about [misnamed], for messages to the teacher, e.g.
  /// `"SMARTSCHOOL_MAINURL" is set, but that is not the name of a setting:
  /// probably SMARTSCHOOL_MAIN_URL.`; null when [misnamed] is empty. Names
  /// only, never a value.
  static String? describe(List<MisnamedSetting> misnamed) {
    if (misnamed.isEmpty) return null;
    final names = [for (final variable in misnamed) '"${variable.name}"'];
    final meant = {
      for (final variable in misnamed)
        if (variable.meant case final setting?) setting.envVar,
    };
    final isAre = misnamed.length == 1
        ? 'is set, but that is not the name of a setting'
        : 'are set, but those are not names of settings';
    final fix = meant.isEmpty
        ? 'the names are ${_list([for (final s in Setting.values) s.envVar])}'
        : 'probably ${_list([...meant])}';
    return '${_list(names)} $isAre: $fix.';
  }

  static String _list(List<String> items) => items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
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
  String? downloadDirectory() => switch (value(Setting.downloadDir)) {
    final String directory => directory,
    _ => null,
  };

  /// The value of [setting]'s key in the file, as YAML reads it (a string,
  /// a `bool`, a number), for a setting the library's [PathCredentials]
  /// does not read, such as the download folder or a switch; null when the
  /// file has no such key, or cannot be read: [read] reports that.
  Object? value(Setting setting) {
    try {
      final yaml = loadYaml(File(path).readAsStringSync());
      return yaml is YamlMap ? yaml[setting.fileKey] : null;
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

  /// The 2FA key: the TOTP secret (Base32) of the authenticator app, as
  /// typed, only trimmed; empty for an account without two-factor
  /// authentication (2FA), such as a student's.
  ///
  /// The library checks it: it ignores white space and hyphens in it (a key
  /// copied in groups, `JBSW Y3DP EHPK 3PXP`), and refuses a value that
  /// cannot be a TOTP secret, such as the 6-digit code of the app, with a
  /// [SmartschoolInvalidTotpSecretError] when it logs in (see
  /// `ProblemKind.twoFactorKeyInvalid`). It takes an empty key as no key:
  /// it logs in with only the password, and fails with a
  /// [SmartschoolTwoFactorRequiredError] when Smartschool asks for a 2FA
  /// code (see `ProblemKind.twoFactorKeyMissing`).
  final String mfa;

  /// The login settings ([Setting.login]) that are empty, in form order,
  /// also the optional 2FA key.
  List<Setting> get empty => [
    if (host.isEmpty) Setting.mainUrl,
    if (username.isEmpty) Setting.username,
    if (password.isEmpty) Setting.password,
    if (mfa.isEmpty) Setting.mfa,
  ];

  /// The required settings that are empty, in form order: the server does
  /// not log in while there are any. The 2FA key is not one of them, as
  /// only an account with 2FA needs it.
  List<Setting> get missing => [
    for (final setting in empty)
      if (setting.required) setting,
  ];

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
