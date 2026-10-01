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
/// library keeps the session cookies in `~/.cache/smartschool/<username>`,
/// so a new process only goes through the password and 2FA steps when the
/// saved session has expired.
///
/// Every failure surfaces as a [SmartschoolProblem] whose message tells the
/// teacher what to fix. A failure that retrying cannot fix
/// ([ProblemKind.permanent]: wrong settings, rejected password or 2FA code) is
/// remembered and returned to later calls without contacting Smartschool
/// again, so a wrong password cannot lock the account through repeated
/// attempts.
final class SmartschoolSession {
  SmartschoolSession(
    this.source, {
    ClientFactory? createClient,
    Duration recheckDelay = const Duration(seconds: 2),
  }) : _createClient = createClient ?? SmartschoolClient.create,
       _recheckDelay = recheckDelay;

  /// A GET that needs a valid session. Without one, Smartschool redirects it
  /// to `/login` and the library's auth interceptor logs in. The library's
  /// own session check (`ensureAuthenticated`) uses the same endpoint.
  static const sessionCheckPath = '/course-list/api/v1/courses';

  final CredentialSource source;
  final ClientFactory _createClient;

  /// How long to wait before checking a just-created session again (see
  /// [_open]).
  final Duration _recheckDelay;

  SmartschoolSettings? _settings;
  SmartschoolProblem? _permanentProblem;
  SmartschoolClient? _client;
  Future<SmartschoolClient>? _connecting;
  Future<SmartschoolClient>? _reconnecting;

  /// Clients replaced by [_reconnect], closed by [close].
  final List<SmartschoolClient> _retired = [];

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
  /// Logs in first if needed. When Smartschool rejects the session during
  /// [action] (it expired), logs in again and runs [action] once more. A
  /// rejected request did not take effect on the server, but [action] runs
  /// again from the start, so it must be safe to repeat.
  ///
  /// Calls that find the session expired at the same time, and concurrent
  /// requests within one [action], share one new login: several logins at
  /// once would send the same one-time 2FA code, and repeated logins count
  /// towards locking the account (#20). That is why the library itself
  /// never logs in on a client whose session worked (see
  /// [SessionInterceptor.allowLogin]).
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
        'logging in again',
      );
    }
    final fresh = await _reconnect(client);
    try {
      return await action(fresh);
    } catch (error, stackTrace) {
      final kind = classifyFailure(error);
      if (kind == null) rethrow;
      throw _problem(kind, error, stackTrace);
    }
  }

  /// Releases the clients this session created.
  Future<void> close() async {
    final clients = [?_client, ..._retired];
    _client = null;
    _retired.clear();
    for (final client in clients) {
      await client.dispose();
    }
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
    return _client = await _open(settings);
  }

  /// Replaces [rejected], whose session Smartschool no longer accepts, with a
  /// new client, logging in again if needed.
  ///
  /// A new client rather than a new login on [rejected]: its cookie jar may
  /// hold cookies that break the new session (see [_open]). Concurrent calls
  /// share one replacement, and [rejected] stays open until [close] because
  /// they may still be using it.
  Future<SmartschoolClient> _reconnect(SmartschoolClient rejected) {
    if (_permanentProblem case final problem?) return Future.error(problem);
    if (_client case final current? when !identical(current, rejected)) {
      return Future.value(current);
    }
    return _reconnecting ??= () async {
      final fresh = await _open(settings);
      _retired.add(rejected);
      return _client = fresh;
    }().whenComplete(() => _reconnecting = null);
  }

  /// Creates a client and checks its session, logging in if needed.
  ///
  /// Right after a successful login (password and 2FA accepted), Smartschool
  /// can still send the library's retry of the session check to `/login`.
  /// Seen live when logging in with an old cookie cache, while a new client
  /// got in with the cookies that login had saved. What differs is the
  /// cookie jar: the library's jar keeps expired cookies in memory
  /// (`ignoreExpires`) but drops them when it saves, and a new client
  /// reloads the saved cookies. So the check is repeated once with a new
  /// client, which never logs in: a second 2FA code within seconds could be
  /// refused as a replay. Belongs in the library: #13.
  Future<SmartschoolClient> _open(SmartschoolSettings settings) async {
    var loggedIn = false;

    Future<SmartschoolClient> attempt({required bool allowLogin}) async {
      final client = await _createClient(settings.toCredentials());
      final trace = SessionInterceptor(client, allowLogin: allowLogin);
      client.dio.interceptors.insert(0, trace);
      try {
        // What ensureAuthenticated() does. Before flutter_smartschool 0.3.0
        // it folded network errors into a SmartschoolAuthenticationError;
        // now both throw a SmartschoolConnectionError (#13).
        await client.platformId;
      } catch (_) {
        loggedIn = trace.loginPagesSeen > 0;
        await client.dispose();
        rethrow;
      }
      log(
        trace.loginPagesSeen == 0
            ? 'Smartschool: reused the saved session, no login needed'
            : 'Smartschool: logged in',
      );
      // From now on a request sent to the login chain fails, so that [run]
      // logs in again once for all requests that find the session expired.
      trace.allowLogin = false;
      return client;
    }

    log('Smartschool: checking the session with ${settings.host}');
    try {
      return await attempt(allowLogin: true);
    } catch (error, stackTrace) {
      final kind = classifyFailure(error) ?? ProblemKind.unexpected;
      if (kind != ProblemKind.sessionRejected || !loggedIn) {
        throw _problem(kind, error, stackTrace);
      }
      log(
        'Smartschool: logged in, but the session was not accepted yet '
        '(${_describe(error)}); checking again with the saved cookies',
      );
    }
    await Future<void>.delayed(_recheckDelay);
    try {
      return await attempt(allowLogin: false);
    } catch (error, stackTrace) {
      throw _problem(
        classifyFailure(error) ?? ProblemKind.unexpected,
        error,
        stackTrace,
      );
    }
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

/// A Dio interceptor, installed first on each of the session's clients,
/// that
///
/// - logs each step of the login chain to stderr (paths only, never bodies),
///   so the log shows whether a session was reused or a new login and 2FA
///   round trip happened;
/// - turns a `401` on a regular request into a [SessionExpiredError], so the
///   session logs in again, before the library's auth interceptor can (see
///   [SessionExpiredError]);
/// - unless [allowLogin], turns being sent to the login chain into a
///   [SessionExpiredError] as well, before the library's auth interceptor
///   can start a login.
final class SessionInterceptor extends Interceptor {
  SessionInterceptor(this._client, {this.allowLogin = true});

  final SmartschoolClient _client;

  /// Whether the library may log in when Smartschool asks for it.
  ///
  /// Only while [SmartschoolSession] checks a new client's session: once
  /// that works, the session turns it off. Up to flutter_smartschool 0.2.x
  /// the library logged in for every request that landed on the login
  /// chain, so requests in progress when the session expired each logged
  /// in, all with the same 2FA code (yvanvds/dartschool#36, fixed in 0.3.0;
  /// relying on that instead is #13). Instead they fail with a
  /// [SessionExpiredError], and [SmartschoolSession.run] logs in once for
  /// all of them with a new client and retries each call.
  bool allowLogin;

  /// How many responses landed on a page of the login chain; 0 means the
  /// saved session was valid.
  int loginPagesSeen = 0;

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
    final requested = response.requestOptions.uri;
    if (!_client.isAuthUri(requested)) {
      final page = response.realUri.path;
      if (_client.isAuthUri(response.realUri)) {
        loginPagesSeen++;
        if (!allowLogin) {
          log('Smartschool: the session is not valid (sent to $page)');
          return _reject(
            response,
            handler,
            const SessionExpiredError.sentToLogin(),
          );
        }
        log(
          page.endsWith('/login')
              ? 'Smartschool: no valid session, logging in'
              : 'Smartschool: login continues at $page',
        );
      } else if (response.statusCode == 401) {
        return _reject(
          response,
          handler,
          const SessionExpiredError.unauthorized(),
        );
      }
    }
    handler.next(response);
  }

  void _reject(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
    SessionExpiredError error,
  ) {
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: error,
      ),
    );
  }
}
