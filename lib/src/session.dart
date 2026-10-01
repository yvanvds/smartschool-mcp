import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'log.dart';
import 'problems.dart';
import 'settings.dart';

/// Creates a [SmartschoolClient]; tests pass one that talks to a fake.
typedef ClientFactory =
    Future<SmartschoolClient> Function(Credentials credentials);

/// The one Smartschool login shared by all tools.
///
/// Nothing happens at startup, so the server starts even with incomplete
/// settings. The first [run] reads the settings, creates the client and logs
/// in; later calls reuse that client for the lifetime of the process. The
/// library keeps the session cookies in the user's cache folder
/// ([cacheDirectory], `~/.cache/smartschool/<username>`), so a new process
/// only goes through the password and 2FA steps when the saved session has
/// expired.
///
/// Every failure surfaces as a [SmartschoolProblem] whose message tells the
/// teacher what to fix. A failure that retrying cannot fix
/// ([ProblemKind.permanent]: wrong settings, such as an empty setting or a
/// 2FA key that is not valid, both found before logging in; a rejected
/// password or 2FA code) is
/// remembered and returned to later calls without contacting Smartschool
/// again, so a wrong password cannot lock the account through repeated
/// attempts.
final class SmartschoolSession {
  SmartschoolSession(this.source, {ClientFactory? createClient})
    : _createClient = createClient ?? SmartschoolClient.create;

  /// A GET that needs a valid session. Without one, Smartschool redirects it
  /// to `/login` and the library's auth interceptor logs in. The library's
  /// own session check (`ensureAuthenticated`) uses the same endpoint.
  static const sessionCheckPath = '/course-list/api/v1/courses';

  final CredentialSource source;
  final ClientFactory _createClient;

  SmartschoolSettings? _settings;
  SmartschoolProblem? _permanentProblem;
  SmartschoolClient? _client;
  Future<SmartschoolClient>? _connecting;
  String? _cacheDirectory;

  /// The folder the library keeps the logged-in user's data in, such as the
  /// saved session cookies: the client's [SmartschoolClient.cacheDir],
  /// `~/.cache/smartschool/<username>` unless the [ClientFactory] chose
  /// another one.
  ///
  /// The server keeps its own data for the user in subfolders of it (the
  /// message texts, the Intradesk index), so that it is found and removed
  /// together with the library's. Taken from the library rather than worked
  /// out here, so it cannot drift from the folder the library uses.
  ///
  /// Known once [run] has logged in, and still after [close]; before that,
  /// a [StateError]: use it only inside [run].
  String get cacheDirectory =>
      _cacheDirectory ??
      (throw StateError(
        'The Smartschool cache folder is only known once the session has '
        'logged in',
      ));

  /// The settings, read from [source] on first use.
  ///
  /// Throws a [SmartschoolProblem] when a credentials file is missing or
  /// unreadable. Empty settings are reported by [SmartschoolSettings.missing]
  /// and, on [run], as [ProblemKind.missingSettings].
  SmartschoolSettings get settings {
    if (_settings case final settings?) return settings;
    if (_permanentProblem case final problem?
        when problem.kind == ProblemKind.credentialsFileMissing ||
            problem.kind == ProblemKind.credentialsFileInvalid) {
      throw problem;
    }
    try {
      return _settings = SmartschoolSettings.read(source);
    } on CredentialsFileException catch (error) {
      log('Smartschool settings: $error');
      throw _permanentProblem = SmartschoolProblem.credentialsFile(error);
    }
  }

  /// Runs [action] with a logged-in client.
  ///
  /// Logs in first if needed. When the session expires later, the library
  /// logs in again for the first request that Smartschool refuses and
  /// retries that request; requests refused while that login runs wait for
  /// it instead of logging in themselves, so they share one login
  /// (yvanvds/dartschool#8, #36).
  ///
  /// When Smartschool still refuses the session for a request of [action]
  /// ([ProblemKind.sessionRejected]: also after the library logged in again,
  /// or the library did not send the request because a new login replaced
  /// the session it belongs to, like a step of a send), [action] runs once
  /// more, from the start; the library logs in again first if needed. A
  /// refused request did not take effect on the server, but [action] must be
  /// safe to repeat.
  ///
  /// Login and connection failures are thrown as [SmartschoolProblem]s; other
  /// errors from [action] are rethrown unchanged.
  Future<T> run<T>(Future<T> Function(SmartschoolClient client) action) async {
    final client = await _connectedClient();
    try {
      return await action(client);
    } catch (error, stackTrace) {
      final kind = classifyFailure(error);
      if (kind == null) rethrow;
      if (kind != ProblemKind.sessionRejected) {
        throw _problem(kind, error, stackTrace);
      }
      log(
        'Smartschool did not accept the session (${_describe(error)}); '
        'trying once more',
      );
    }
    try {
      // Through [_connectedClient], so that a login that another call found
      // rejected meanwhile is not tried again.
      return await action(await _connectedClient());
    } catch (error, stackTrace) {
      final kind = classifyFailure(error);
      if (kind == null) rethrow;
      throw _problem(kind, error, stackTrace);
    }
  }

  /// Releases the client this session created.
  Future<void> close() async {
    final client = _client;
    _client = null;
    await client?.dispose();
  }

  Future<SmartschoolClient> _connectedClient() async {
    if (_permanentProblem case final problem?) throw problem;
    if (_client case final client?) return client;
    // Concurrent first calls share one login: two parallel logins would send
    // the same one-time 2FA code twice.
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<SmartschoolClient> _connect() async {
    final settings = this.settings;
    if (settings.missing.isNotEmpty) {
      log(
        'Smartschool settings incomplete, missing: '
        '${settings.missing.map((s) => s.name).join(', ')}',
      );
      throw _permanentProblem = SmartschoolProblem.of(
        ProblemKind.missingSettings,
        settings,
      );
    }
    if (settings.mfaProblem case final problem?) {
      log('Smartschool settings: the 2FA key is not valid ($problem)');
      throw _permanentProblem = SmartschoolProblem.of(
        ProblemKind.twoFactorKeyInvalid,
        settings,
      );
    }
    final client = _client = await _open(settings);
    _cacheDirectory = client.cacheDir;
    return client;
  }

  /// Creates a client and checks its session, logging in if needed.
  Future<SmartschoolClient> _open(SmartschoolSettings settings) async {
    log('Smartschool: checking the session with ${settings.host}');
    final client = await _createClient(settings.toCredentials());
    final trace = SessionInterceptor(client);
    client.dio.interceptors.insert(0, trace);
    try {
      await client.ensureAuthenticated();
    } catch (error, stackTrace) {
      await client.dispose();
      throw _problem(
        classifyFailure(error) ?? ProblemKind.unexpected,
        error,
        stackTrace,
      );
    }
    log(
      trace.refusals == 0
          ? 'Smartschool: reused the saved session, no login needed'
          : 'Smartschool: logged in',
    );
    return client;
  }

  /// Builds the problem for [kind], logs [error] (with its stack trace when
  /// unexpected) and remembers the problem if it is permanent.
  SmartschoolProblem _problem(
    ProblemKind kind,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is SmartschoolProblem) return error;
    log(
      'Smartschool problem (${kind.name}): ${_describe(error)}'
      '${kind == ProblemKind.unexpected ? '\n$stackTrace' : ''}',
    );
    final problem = SmartschoolProblem.of(kind, settings);
    if (kind.permanent) _permanentProblem = problem;
    return problem;
  }
}

/// [error] on one line, for the log: a [DioException] shows the error it
/// wraps rather than its own multi-line description.
String _describe(Object error) => switch (error) {
  DioException(error: final Object inner) => '$inner',
  DioException(:final type, :final message) => 'DioException [$type]: $message',
  _ => '$error',
};

/// A Dio interceptor, installed first on the session's client, that logs
/// each step of the login chain to stderr (paths only, never bodies), so the
/// log shows whether a session was reused or a new login and 2FA round trip
/// happened.
///
/// It only watches: logging in again when Smartschool refuses the session
/// is up to the library's own auth interceptor, which comes after it.
final class SessionInterceptor extends Interceptor {
  SessionInterceptor(this._client);

  final SmartschoolClient _client;

  /// How many answers to a regular request refused its session (a `401`, or
  /// a page of the login chain); 0 means the saved session was valid.
  int refusals = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'POST') {
      final path = options.uri.path;
      if (path.endsWith('/login')) {
        log('Smartschool: sending username and password');
      } else if (path.endsWith('/account-verification')) {
        log('Smartschool: answering the account verification');
      } else if (path == '/2fa/api/v1/google-authenticator') {
        log('Smartschool: sending a 2FA code');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!_client.isAuthUri(response.requestOptions.uri)) {
      final page = response.realUri;
      final refused = _client.isAuthUri(page)
          ? 'sent to ${page.path}'
          : response.statusCode == 401
          ? 'answered 401'
          : null;
      if (refused != null) {
        refusals++;
        log('Smartschool: no valid session ($refused)');
      }
    }
    handler.next(response);
  }
}
