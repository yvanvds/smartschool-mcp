import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';

/// The release page GitHub gives for [tag].
String releasePage(String tag) =>
    'https://github.com/yvanvds/smartschool-mcp/releases/tag/$tag';

/// A request [FakeGitHub] received.
typedef GitHubRequest = ({String path, String? userAgent, String? accept});

/// GitHub's "latest release" endpoint, faked on a local port, so that no
/// test ever asks the real GitHub. Stopped after the test.
class FakeGitHub {
  FakeGitHub._(this._server) {
    _server.listen(_answer);
  }

  static Future<FakeGitHub> start() async {
    final github = FakeGitHub._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(github._stop);
    return github;
  }

  final HttpServer _server;

  /// The address to check, like [UpdateChecker.defaultEndpoint].
  Uri get latestRelease => Uri.parse(
    'http://127.0.0.1:${_server.port}'
    '/repos/yvanvds/smartschool-mcp/releases/latest',
  );

  /// Every request so far.
  final List<GitHubRequest> requests = [];

  int _status = HttpStatus.notFound;
  String _body = _notFound;
  Completer<void>? _held;
  final List<Completer<void>> _waiters = [];

  static final _notFound = jsonEncode({
    'message': 'Not Found',
    'documentation_url':
        'https://docs.github.com/rest/releases/releases#get-the-latest-release',
    'status': '404',
  });

  /// From now on the latest release is [tag], as GitHub describes it.
  void publish(String tag) => answer(
    HttpStatus.ok,
    jsonEncode({
      'url': 'https://api.github.com/repos/yvanvds/smartschool-mcp/releases/1',
      'html_url': releasePage(tag),
      'id': 1,
      'tag_name': tag,
      'name': tag,
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': UpdateChecker.assetName,
          'browser_download_url':
              'https://github.com/yvanvds/smartschool-mcp/releases/download/'
              '$tag/${UpdateChecker.assetName}',
        },
      ],
      'body': 'Release notes',
    }),
  );

  /// From now on there is no release: GitHub answers 404, as it does for a
  /// repository without releases.
  void noReleases() => answer(HttpStatus.notFound, _notFound);

  /// From now on GitHub's rate limit is reached.
  void rateLimited() => answer(
    HttpStatus.forbidden,
    jsonEncode({'message': 'API rate limit exceeded for 127.0.0.1.'}),
  );

  /// From now on every request gets [status] and [body].
  void answer(int status, String body) {
    _status = status;
    _body = body;
  }

  /// Holds every answer until [release] (or the end of the test).
  void hold() => _held ??= Completer<void>();

  /// Sends the held answers.
  void release() {
    _held?.complete();
    _held = null;
  }

  /// Completes once [count] requests have arrived.
  Future<void> received(int count) async {
    while (requests.length < count) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }

  Future<void> _answer(HttpRequest request) async {
    requests.add((
      path: request.uri.path,
      userAgent: request.headers.value(HttpHeaders.userAgentHeader),
      accept: request.headers.value(HttpHeaders.acceptHeader),
    ));
    for (final waiter in _waiters) {
      waiter.complete();
    }
    _waiters.clear();
    final status = _status;
    final body = _body;
    await _held?.future;
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(body);
      await request.response.close();
    } on Object {
      // The server gave up waiting.
    }
  }

  Future<void> _stop() async {
    release();
    await _server.close(force: true);
  }
}

/// An address where nothing answers: a port that was just freed.
Future<Uri> unreachableAddress() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return Uri.parse('http://127.0.0.1:$port/releases/latest');
}
