import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pub_semver/pub_semver.dart';

import 'log.dart';
import 'settings.dart';
import 'version.dart';

/// A release of this server published on GitHub.
final class Release {
  const Release(this.version, {required this.tag, required this.url});

  final Version version;

  /// The release's tag, e.g. `v0.2.0`.
  final String tag;

  /// The release page (GitHub's `html_url`), where the `.mcpb` file is.
  final Uri url;

  /// The version in a release [tag] such as `v1.2.3` (the `v` is optional),
  /// or null when the tag is not a semantic version.
  static Version? parseTag(String tag) {
    var text = tag.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    try {
      return Version.parse(text);
    } on FormatException {
      return null;
    }
  }
}

/// What an update check found.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A release newer than this server.
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);

  final Release release;
}

/// No newer release. [latest] is the latest release, or null when none has
/// been published (GitHub answers 404).
final class UpToDate extends UpdateCheckResult {
  const UpToDate(this.latest);

  final Release? latest;
}

/// The check did not work: offline, rate limited, or an answer that is not
/// understood. [reason] is short, for `smartschool_status`; [detail] only
/// goes to the log.
final class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.reason, {this.detail});

  final String reason;
  final String? detail;
}

/// Asks GitHub whether a newer release of this server exists, and gives the
/// notice that tells the user about it.
///
/// Nothing ever waits for it: [checkInBackground] starts a check and
/// returns, a check gives up after [timeout], and a failure is only logged.
/// A successful check is saved with its time in [stateFile], so a restart
/// within [interval] (a day) does not ask GitHub again; a server that keeps
/// running asks again once a day, on a tool call. [checkNow] always asks.
///
/// A newer release is announced once per process: the first [takeNotice]
/// after it became known returns the notice, and the server adds it to that
/// tool result.
final class UpdateChecker {
  UpdateChecker({
    required this.stateFile,
    Uri? endpoint,
    String currentVersion = packageVersion,
    this.timeout = const Duration(seconds: 5),
    this.interval = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : endpoint = endpoint ?? defaultEndpoint,
       current = Version.parse(currentVersion),
       _clock = clock ?? DateTime.now;

  /// The checker the server uses, set up from [environment] (this process's
  /// environment by default).
  ///
  /// Null, so no check at all, when [disableVariable] is `off` (or `false`,
  /// `no`, `0`), or when [endpointVariable] is set but is not an http(s)
  /// address. The state file is [stateFileName] in
  /// [SmartschoolSettings.cacheRoot]: the check needs no Smartschool
  /// settings.
  static UpdateChecker? fromEnvironment([Map<String, String>? environment]) {
    final variables = environment ?? Platform.environment;
    final switchValue = variables[disableVariable];
    if (const {
      'off',
      'false',
      'no',
      '0',
    }.contains(switchValue?.trim().toLowerCase())) {
      log('update check: turned off ($disableVariable=$switchValue)');
      return null;
    }
    Uri? endpoint;
    final address = variables[endpointVariable]?.trim() ?? '';
    if (address.isNotEmpty) {
      endpoint = Uri.tryParse(address);
      if (endpoint == null || !_isWebAddress(endpoint, allowHttp: true)) {
        log(
          'update check: turned off, $endpointVariable is not an http(s) '
          'address: $address',
        );
        return null;
      }
      log('update check: asking $endpoint ($endpointVariable)');
    }
    return UpdateChecker(
      endpoint: endpoint,
      stateFile: File(
        [
          SmartschoolSettings.cacheRoot(variables),
          stateFileName,
        ].join(Platform.pathSeparator),
      ),
    );
  }

  /// GitHub's latest non-draft, non-prerelease release of this server.
  static final defaultEndpoint = Uri.parse(
    'https://api.github.com/repos/yvanvds/smartschool-mcp/releases/latest',
  );

  /// Set to `off` to turn the update check off (tests, development).
  static const disableVariable = 'SMARTSCHOOL_MCP_UPDATE_CHECK';

  /// Set to an address that answers like [defaultEndpoint] to ask it
  /// instead of GitHub (tests, development).
  static const endpointVariable = 'SMARTSCHOOL_MCP_UPDATE_URL';

  /// The file in [SmartschoolSettings.cacheRoot] with the last check.
  static const stateFileName = 'smartschool-mcp-update-check.json';

  /// The name of the extension file attached to every release.
  static const assetName = 'smartschool-mcp.mcpb';

  /// An answer larger than this is not a release (GitHub's is a few KB).
  static const maxAnswerBytes = 1024 * 1024;

  /// The version of [stateFile]'s contents; files of another version are
  /// ignored and overwritten.
  static const stateFormat = 1;

  /// What the user does to update to [release].
  static String howToUpdate(Release release) =>
      'download $assetName from ${release.url} and double-click it';

  final Uri endpoint;
  final File stateFile;

  /// The version of this server.
  final Version current;
  final Duration timeout;
  final Duration interval;
  final DateTime Function() _clock;

  /// The latest release known, from the last successful check (in this
  /// process or saved in [stateFile]); null when none is known.
  Release? _latest;

  /// When the check [_latest] comes from was made.
  DateTime? _checkedAt;

  /// When this process last asked, whether it worked or not.
  DateTime? _attemptedAt;

  /// The version the user was last told about in this process.
  Version? _announced;

  bool _stateRead = false;
  bool _closed = false;
  Future<void>? _background;
  final Set<HttpClient> _clients = {};
  int _writes = 0;

  /// Completes when no background check is running.
  Future<void> get idle => _background ?? Future.value();

  /// Starts a check in the background and returns at once, unless one is
  /// running or the last one is less than [interval] ago (in [stateFile],
  /// or asked by this process, successful or not). Never throws.
  void checkInBackground() {
    if (_closed || _background != null) return;
    final now = _clock();
    if (_isRecent(_checkedAt, now) || _isRecent(_attemptedAt, now)) return;
    _background = _checkInBackground().whenComplete(() => _background = null);
  }

  Future<void> _checkInBackground() async {
    try {
      if (!_stateRead) {
        _stateRead = true;
        // A check this process made meanwhile is more recent.
        if (await _readState() case (
          final checkedAt,
          final latest,
        ) when _checkedAt == null) {
          _latest = latest;
          _checkedAt = checkedAt;
        }
      }
      final checkedAt = _checkedAt;
      if (checkedAt != null && _isRecent(checkedAt, _clock())) {
        log(
          'update check: skipped, last checked at '
          '${checkedAt.toUtc().toIso8601String()} (${_describe(_latest)})',
        );
        return;
      }
      await _check();
    } catch (error, stackTrace) {
      log('update check: unexpected error: $error\n$stackTrace');
    }
  }

  /// Asks now, whenever the last check was, and returns what it found
  /// (within [timeout]). Never throws.
  Future<UpdateCheckResult> checkNow() async {
    if (_closed) return const UpdateCheckFailed('the server is shutting down');
    try {
      return await _check();
    } catch (error, stackTrace) {
      log('update check: unexpected error: $error\n$stackTrace');
      return const UpdateCheckFailed('unexpected error, see the server log');
    }
  }

  /// The notice to add to a tool result when a newer release is known and
  /// the user has not been told about it in this process (not by an earlier
  /// notice, nor by `smartschool_status`, see [announced]); null otherwise.
  ///
  /// Also starts a background check when the last one is a day old, so a
  /// server that keeps running learns about later releases. Never waits.
  String? takeNotice() {
    checkInBackground();
    final latest = _latest;
    if (latest == null ||
        latest.version <= current ||
        latest.version == _announced) {
      return null;
    }
    _announced = latest.version;
    return 'Update available: version ${latest.version} of the Smartschool '
        'extension has been released (this is version $current). Please tell '
        'the user: to update, ${howToUpdate(latest)}.';
  }

  /// Records that the user was told about [release] (by
  /// `smartschool_status`), so [takeNotice] does not repeat it.
  void announced(Release release) => _announced = release.version;

  /// Stops a running check; the server is shutting down.
  Future<void> close() async {
    _closed = true;
    for (final client in [..._clients]) {
      client.close(force: true);
    }
    await _background;
  }

  Future<UpdateCheckResult> _check() async {
    final startedAt = _attemptedAt = _clock();
    final result = await _ask();
    switch (result) {
      case UpdateAvailable(:final release):
        log(
          'update check: version ${release.version} is available (this is '
          '$current): ${release.url}',
        );
        _latest = release;
        _checkedAt = startedAt;
        await _writeState(startedAt, release);
      case UpToDate(:final latest):
        log('update check: up to date (${_describe(latest)})');
        _latest = latest;
        _checkedAt = startedAt;
        await _writeState(startedAt, latest);
      case UpdateCheckFailed(:final reason, :final detail):
        log('update check failed: $reason${detail == null ? '' : ': $detail'}');
    }
    return result;
  }

  bool _isRecent(DateTime? time, DateTime now) {
    if (time == null) return false;
    final age = now.difference(time);
    return !age.isNegative && age < interval;
  }

  String _describe(Release? latest) => latest == null
      ? 'no release published yet'
      : 'latest release ${latest.version}';

  Future<UpdateCheckResult> _ask() async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent =
          'smartschool-mcp/$current (+https://github.com/yvanvds/smartschool-mcp)';
    _clients.add(client);
    try {
      return await _request(client).timeout(timeout);
    } on TimeoutException {
      return UpdateCheckFailed(
        'no answer from ${endpoint.host} within ${_duration(timeout)}',
      );
    } on IOException catch (error) {
      return UpdateCheckFailed(
        'could not reach ${endpoint.host}',
        detail: '$error',
      );
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<UpdateCheckResult> _request(HttpClient client) async {
    final request = await client.getUrl(endpoint);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close();
    final status = response.statusCode;
    if (status != HttpStatus.ok) {
      await response.drain<void>();
      return switch (status) {
        // No release published (yet).
        HttpStatus.notFound => const UpToDate(null),
        HttpStatus.forbidden || HttpStatus.tooManyRequests => UpdateCheckFailed(
          '${endpoint.host} refused to answer (HTTP $status), probably its '
          'limit of 60 requests per hour',
        ),
        _ => UpdateCheckFailed('${endpoint.host} answered HTTP $status'),
      };
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      body.add(chunk);
      if (body.length > maxAnswerBytes) {
        return UpdateCheckFailed(
          'the answer from ${endpoint.host} is not a release (too large)',
        );
      }
    }
    return _parse(body.takeBytes());
  }

  UpdateCheckResult _parse(Uint8List body) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return UpdateCheckFailed(
        'the answer from ${endpoint.host} is not a release (not JSON)',
      );
    }
    if (json case {
      'tag_name': final String tag,
      'html_url': final String address,
    }) {
      final version = Release.parseTag(tag);
      if (version == null) {
        return UpdateCheckFailed(
          'the latest release has a tag that is not a version: '
          '"${tag.length > 40 ? '${tag.substring(0, 40)}...' : tag}"',
        );
      }
      final url = Uri.tryParse(address);
      if (url == null || !_isWebAddress(url)) {
        return const UpdateCheckFailed(
          'the latest release has no https address',
        );
      }
      final release = Release(version, tag: tag, url: url);
      return version > current ? UpdateAvailable(release) : UpToDate(release);
    }
    return UpdateCheckFailed(
      'the answer from ${endpoint.host} is not a release (no tag_name or '
      'html_url)',
    );
  }

  /// The last successful check saved in [stateFile], if it was of this
  /// [endpoint].
  Future<(DateTime, Release?)?> _readState() async {
    try {
      final json = jsonDecode(await stateFile.readAsString());
      if (json case {
        'format': stateFormat,
        'endpoint': final String savedEndpoint,
        'checked_at': final String checkedAt,
        'latest': final Object? latest,
      } when savedEndpoint == endpoint.toString()) {
        if (DateTime.tryParse(checkedAt) case final time?) {
          switch (latest) {
            case null:
              return (time, null);
            case {'tag': final String tag, 'url': final String address}:
              final version = Release.parseTag(tag);
              final url = Uri.tryParse(address);
              if (version != null && url != null && _isWebAddress(url)) {
                return (time, Release(version, tag: tag, url: url));
              }
          }
        }
      }
      log('update check: ignoring ${stateFile.path} (other format or address)');
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      log('update check: cannot read ${stateFile.path}: ${error.message}');
    } on FormatException {
      log('update check: ignoring ${stateFile.path} (damaged)');
    }
    return null;
  }

  /// Saves a successful check. Writes a temporary file and renames it, so a
  /// second server process never reads a half-written file.
  Future<void> _writeState(DateTime checkedAt, Release? latest) async {
    final temporary = File('${stateFile.path}.$pid-${_writes++}.tmp');
    try {
      await stateFile.parent.create(recursive: true);
      await temporary.writeAsString(
        jsonEncode({
          'format': stateFormat,
          'endpoint': endpoint.toString(),
          'checked_at': checkedAt.toUtc().toIso8601String(),
          'latest': latest == null
              ? null
              : {'tag': latest.tag, 'url': latest.url.toString()},
        }),
        flush: true,
      );
      await temporary.rename(stateFile.path);
    } on FileSystemException catch (error) {
      log('update check: cannot save ${stateFile.path}: ${error.message}');
      try {
        await temporary.delete();
      } on FileSystemException {
        // It was not created.
      }
    }
  }

  static bool _isWebAddress(Uri url, {bool allowHttp = false}) =>
      (url.isScheme('https') || allowHttp && url.isScheme('http')) &&
      url.host.isNotEmpty;

  static String _duration(Duration duration) =>
      duration.inMilliseconds % 1000 == 0
      ? '${duration.inSeconds} seconds'
      : '${duration.inMilliseconds} ms';
}
