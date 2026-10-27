import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'fake_intradesk.dart';
import 'fake_lvs.dart';
import 'fake_messages.dart';
import 'fake_planner.dart';
import 'fake_presence.dart';
import 'fake_skore.dart';
import 'fake_skore_gradebook.dart';
import 'fake_uploads.dart';

export 'fake_intradesk.dart';
export 'fake_lvs.dart';
export 'fake_messages.dart';
export 'fake_planner.dart';
export 'fake_presence.dart';
export 'fake_skore.dart';
export 'fake_skore_gradebook.dart';
export 'fake_uploads.dart';

const fakeHost = 'school.smartschool.be';
const fakeDisplayName = 'Jan Peeters';

/// The Smartschool user id of the fake's account by default
/// ([FakeSmartschool.userId]): `345` of the `authenticatedUser.id`
/// `12_345_0` on its pages.
const fakeUserId = 345;

/// A valid Base32 TOTP secret (not anyone's).
const fakeTotpSecret = 'JBSWY3DPEHPK3PXP';
const fakePassword = 'hunter2-not-real';

/// What Smartschool asks for after a correct password.
enum SecondStep {
  /// Nothing: an account without 2FA, such as a student's. The password
  /// alone logs in.
  none,

  /// The 2FA page, with an authenticator app configured.
  twoFactor,

  /// The 2FA page, but the account has no authenticator app configured.
  twoFactorWithoutApp,

  /// The account-verification page (date of birth).
  accountVerification,
}

/// A fake Smartschool that serves the login chain the way the live platform
/// does, for a [SmartschoolClient] whose `httpClientAdapter` it replaces.
///
/// Like `dart:io`'s `HttpClient`, it reports a followed redirect for a GET
/// through `redirects` and hands a POST's redirect back unfollowed.
class FakeSmartschool implements HttpClientAdapter {
  FakeSmartschool({
    this.passwordAccepted = true,
    this.secondStep = SecondStep.twoFactor,
    this.twoFactorAccepted = true,
    this.userId = fakeUserId,
  });

  /// The Smartschool user id of the account that logs in: the
  /// `authenticatedUser.id` of the fake's pages is `12_<userId>_0`. The LVS
  /// tests log in as a teacher of the LVS's fakes (`FAKES.md`), to be the
  /// author of items of a support plan (#163).
  final int userId;

  /// Smartschool's start page for the account [userId].
  late final String _homePage = _homePageOf(userId);

  bool passwordAccepted;
  SecondStep secondStep;
  bool twoFactorAccepted;

  /// When set, every request fails the way an unreachable host does.
  bool unreachable = false;

  /// How many requests right after a successful login Smartschool still
  /// refuses (a GET sent to `/login`, a POST answered with 401, or with
  /// `302 Location: /` for Skore's gradebook) although the login went
  /// through.
  ///
  /// Not seen live: the refusal seen live after a login with an old cookie
  /// cache was the library sending the refused session id along with the
  /// new one (yvanvds/dartschool#9), which [_hasSession] models.
  ///
  /// The start page the library opens right after the 2FA step, as a
  /// browser does with the 2FA answer's `redirectTo` (flutter_smartschool
  /// 0.4.0, yvanvds/dartschool#192), is part of the login: it is served,
  /// and does not count as one of these requests.
  int rejectsAfterLogin = 0;
  int _rejectsLeft = 0;

  /// Whether the 2FA step just completed a login, and the library's opening
  /// of the start page (`GET /`) that ends it has not come yet.
  bool _startPageAfterTwoFactor = false;

  /// The session id the server currently accepts, set by a completed login
  /// as the `PHPSESSID` cookie.
  String? _validSession;
  bool _passwordDone = false;

  /// How many logins completed: a correct password and 2FA code, or only a
  /// correct password with [SecondStep.none].
  int logins = 0;

  /// Every request, as `METHOD path`.
  final List<String> requests = [];

  /// Every POST refused for its session, as `STATUS path`: `401 /...`, or
  /// `302 /modules/Skore/backend/gradebook/rpc.php` ([_refusedPost]).
  final List<String> refusedPosts = [];

  /// The Messages module, served to logged-in requests. The attachments of
  /// a message go through the shared [uploads].
  late final FakeMailbox mailbox = FakeMailbox(
    owner: fakeDisplayName,
    uploads: uploads,
  );

  /// The Intradesk module, served to logged-in requests.
  late final FakeIntradesk intradesk = FakeIntradesk(uploads: uploads);

  /// Smartschool's upload step, shared by the modules that take files,
  /// served to logged-in requests.
  final FakeUploads uploads = FakeUploads();

  /// The planner, served to logged-in requests. Its own account is
  /// [fakePlannerMe], the user of the fake's pages.
  late final FakePlanner planner = FakePlanner(uploads: uploads);

  /// The Skore module, served to logged-in requests: empty until a test
  /// fills it (`FakeSkore.loadSchool`).
  late final FakeSkore skore = FakeSkore(startPage: _homePage);

  /// The user's own gradebooks in Skore (`/SkoreGradebook`), served to
  /// logged-in requests (its RPC POSTs, and the feedback GETs of Skore's
  /// REST API): empty until a test fills it
  /// (`FakeSkoreGradebook.loadSchool`).
  final FakeSkoreGradebook skoreGradebook = FakeSkoreGradebook();

  /// The Presence module, served to logged-in requests: empty until a test
  /// fills it (`FakePresence.loadSchool`).
  final FakePresence presence = FakePresence();

  /// The pupil tracking system (LVS), served to logged-in requests, with
  /// the hand-written fixtures of `test/fixtures/lvs/`.
  late final FakeLvs lvs = FakeLvs(startPage: _homePage);

  /// How long every request takes, so that concurrent requests overlap.
  Duration latency = Duration.zero;

  /// The most requests that were in progress at the same time.
  int maxInFlight = 0;
  int _inFlight = 0;

  /// Simulates the session expiring on the server.
  void expireSession() {
    _validSession = null;
    _passwordDone = false;
  }

  bool Function(RequestOptions request)? _expireBefore;

  /// Simulates the session expiring right before the first request that
  /// [matches] arrives, so that request is the first one without a session.
  void expireSessionBefore(bool Function(RequestOptions request) matches) =>
      _expireBefore = matches;

  /// Whether [options] carries the valid session.
  ///
  /// Like the live platform, only the first `PHPSESSID` in the `Cookie`
  /// header counts: a request that sends a refused session id before the
  /// new one is refused (yvanvds/dartschool#9).
  bool _hasSession(RequestOptions options) =>
      _validSession != null && sessionOf(options) == _validSession;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (++_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      return _respond(options, cancelFuture);
    } finally {
      _inFlight--;
    }
  }

  ResponseBody _respond(RequestOptions options, Future<void>? cancelled) {
    final path = options.uri.path;
    if (_expireBefore?.call(options) ?? false) {
      _expireBefore = null;
      expireSession();
    }
    final loggedIn = _hasSession(options);
    requests.add('${options.method} $path');
    if (unreachable) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: "Failed host lookup: '$fakeHost'",
        error: const SocketException("Failed host lookup: 'fake'"),
      );
    }
    if (FakeMailbox.isSubmit(options)) mailbox.submits++;

    if (options.method == 'POST' && path == '/login') {
      if (passwordAccepted && secondStep == SecondStep.none) {
        return _html(
          'Redirecting to /',
          status: 302,
          location: '/',
          cookie: _logIn(),
        );
      }
      _passwordDone = passwordAccepted;
      final target = !passwordAccepted
          ? '/login'
          : secondStep == SecondStep.accountVerification
          ? '/account-verification'
          : '/2fa';
      return _html('Redirecting to $target', status: 302, location: target);
    }
    if (path == '/login') return _html(_loginPage);
    if (path == '/account-verification') return _html(_accountVerificationPage);
    if (path == '/2fa') return _html('<html><body>2fa</body></html>');
    if (path == '/2fa/api/v1/config') {
      final mechanisms = secondStep == SecondStep.twoFactorWithoutApp
          ? '["sms"]'
          : '["googleAuthenticator"]';
      return _json('{"possibleAuthenticationMechanisms":$mechanisms}');
    }
    if (path == '/2fa/api/v1/google-authenticator') {
      if (!twoFactorAccepted) {
        return _json('{"success":false,"error":"invalid code"}');
      }
      final cookie = _logIn();
      _startPageAfterTwoFactor = true;
      return _json('{"success":true,"redirectTo":"/"}', cookie: cookie);
    }

    if (options.method == 'POST') {
      // An XML or form POST without a session gets a bare 401 (observed on
      // the live platform), not a redirect to /login; an RPC call of
      // Skore's gradebook gets `302 Location: /` ([_refusedPost]).
      if (!loggedIn || path == '/always-401') {
        return _refusedPost(path);
      }
      if (_rejectsLeft > 0) {
        _rejectsLeft--;
        return _refusedPost(path);
      }
      return lvs.respond(options) ??
          uploads.respond(options) ??
          mailbox.respond(options) ??
          intradesk.respond(options) ??
          planner.respond(options) ??
          skore.respond(options) ??
          skoreGradebook.respond(options) ??
          presence.respond(options) ??
          _html('<ok/>');
    }

    // A GET anywhere else needs a session; without one the server redirects
    // to the next step of the login chain.
    if (!loggedIn) {
      return _passwordDone
          ? _followedTo('/2fa', '<html><body>2fa</body></html>')
          : _followedTo('/login', _loginPage);
    }
    if (_startPageAfterTwoFactor && path == '/') {
      _startPageAfterTwoFactor = false;
      return _html(_homePage);
    }
    if (_rejectsLeft > 0) {
      _rejectsLeft--;
      return _followedTo('/login', _loginPage);
    }
    if (path == fakeCourseListPath) {
      return planner.courseListAnswer();
    }
    return lvs.respond(options) ??
        uploads.respond(options) ??
        mailbox.respond(options, cancelled: cancelled) ??
        intradesk.respond(options, cancelled: cancelled) ??
        planner.respond(options, cancelled: cancelled) ??
        skore.respond(options) ??
        skoreGradebook.respond(options) ??
        _html(_homePage);
  }

  @override
  void close({bool force = false}) {}

  /// Completes a login: starts a new session and returns the cookie that
  /// carries it.
  String _logIn() {
    logins++;
    _validSession = 'session$logins';
    _passwordDone = false;
    _rejectsLeft = rejectsAfterLogin;
    _startPageAfterTwoFactor = false;
    return 'PHPSESSID=$_validSession; path=/';
  }

  /// Smartschool's answer to a POST to [path] in a session it does not
  /// accept: a bare 401, or for an RPC call of Skore's gradebook
  /// ([fakeSkoreGradebookRpcPath]) `302 Location: /` with an empty body, as
  /// seen live (yvanvds/dartschool#192, the cause of #168), which
  /// flutter_smartschool 0.4.0 takes for a refused session too.
  ResponseBody _refusedPost(String path) {
    final gradebook = path == fakeSkoreGradebookRpcPath;
    refusedPosts.add('${gradebook ? 302 : 401} $path');
    return gradebook
        ? _html('', status: 302, location: '/')
        : ResponseBody.fromString('', 401);
  }

  ResponseBody _html(
    String body, {
    int status = 200,
    String? location,
    String? cookie,
  }) => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html'],
      if (location != null) 'location': [location],
      if (cookie != null) HttpHeaders.setCookieHeader: [cookie],
    },
  );

  ResponseBody _json(String body, {String? cookie}) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (cookie != null) HttpHeaders.setCookieHeader: [cookie],
    },
  );

  ResponseBody _followedTo(String path, String body) => _html(body)
    ..redirects = [
      RedirectRecord(302, 'GET', Uri.parse('https://$fakeHost$path')),
    ];
}

const _loginPage = '''
<html><body>
<form class="form" name="login_form" method="post">
<input type="text" name="login_form[_username]" />
<input type="password" name="login_form[_password]" />
<input type="hidden" name="login_form[_token]" value="csrf" />
<button type="submit">Aanmelden</button>
</form>
</body></html>
''';

const _accountVerificationPage = '''
<html><body>
<form name="account_verification_form" method="post">
<input type="date" name="account_verification_form[_security_question_answer]" />
<input type="hidden" name="account_verification_form[_token]" value="csrf" />
</form>
</body></html>
''';

/// Smartschool's start page, with the account [userId] as the
/// `authenticatedUser` the library reads at login.
String _homePageOf(int userId) =>
    '''
<html><head>
<script type="text/javascript">\$.extend(true, SMSC, JSON.parse('{"vars":{"authenticatedUser":{"id":"12_${userId}_0","name":{"startingWithFirstName":"$fakeDisplayName"}}}}'));</script>
</head><body>home</body></html>
''';

/// Credentials with fixed values, for [ExtensionSettings.new]'s `read`.
class FakeCredentials extends Credentials {
  FakeCredentials({
    this.mainUrl = fakeHost,
    this.username = 'jan.peeters',
    this.password = fakePassword,
    this.mfa = fakeTotpSecret,
  });

  @override
  final String mainUrl;
  @override
  final String username;
  @override
  final String password;
  @override
  final String? mfa;
}

/// Extension settings holding [credentials], in an environment with no
/// other variables (so no misnamed setting); worded for [client]'s app.
ExtensionSettings fakeExtensionSettings([
  Credentials? credentials,
  ClientContext? client,
]) => ExtensionSettings(
  client: client,
  read: () => credentials ?? FakeCredentials(),
  environment: () => const {},
);

/// A temporary cookie cache directory, deleted after the test.
Future<Directory> tempCache() async {
  final cache = await Directory.systemTemp.createTemp('smartschool_cache_');
  addTearDown(() => cache.delete(recursive: true));
  return cache;
}

/// A [ClientFactory] that creates real library clients talking to [server],
/// keeping their cookies in [cache] (like `~/.cache/smartschool/<username>`).
ClientFactory fakeClientFactory(FakeSmartschool server, Directory cache) {
  return (credentials) async {
    final client = await SmartschoolClient.create(
      credentials,
      cacheDir: cache.path,
    );
    client.dio.httpClientAdapter = server;
    addTearDown(client.dispose);
    return client;
  };
}
