import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';

import '../../tool/release_notes.dart';

/// The release page GitHub gives for [tag].
String releasePage(String tag) =>
    'https://github.com/yvanvds/smartschool-mcp/releases/tag/$tag';

/// The direct download link GitHub gives for the file [asset] of the
/// release [tag].
String downloadLink(String tag, String asset) =>
    'https://github.com/yvanvds/smartschool-mcp/releases/download/$tag/$asset';

/// The notes of a release made by the release workflow, as GitHub keeps
/// them: what `tool/release_notes.dart` writes for [whatIsNew] (a section of
/// `CHANGELOG.md`), followed by GitHub's generated notes. Without
/// [whatIsNew], the notes of a release from before `CHANGELOG.md`: the
/// install instructions and the generated notes.
String releaseBody(String tag, {String? whatIsNew}) {
  final install = File(installNotesFile).readAsStringSync();
  final generated =
      "## What's Changed\n"
      '* Fix the clipboard path for ChatGPT, and ask for a paid plan with '
      'model training off by @yvanvds in '
      'https://github.com/yvanvds/smartschool-mcp/pull/56\n\n'
      '**Full Changelog**: '
      'https://github.com/yvanvds/smartschool-mcp/compare/v0.1.0...$tag';
  final written = whatIsNew == null
      ? install
      : releaseNotes(whatIsNew: whatIsNew, install: install);
  return '${written.trim()}\n\n$generated';
}

/// A request [FakeGitHub] received.
typedef GitHubRequest = ({String path, String? userAgent, String? accept});

/// GitHub's list of the releases of this server, faked on a local port, so
/// that no test ever asks the real GitHub. Stopped after the test.
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
  Uri get releases => Uri.parse(
    'http://127.0.0.1:${_server.port}/repos/yvanvds/smartschool-mcp/releases',
  );

  /// Every request so far.
  final List<GitHubRequest> requests = [];

  /// The releases, newest first, as GitHub lists them.
  final List<Map<String, Object?>> _releases = [];

  /// An answer that replaces the list, from [answer].
  (int, String)? _override;
  Completer<void>? _held;
  final List<Completer<void>> _waiters = [];

  /// Publishes the release [tag] (in front of the others, and instead of an
  /// earlier one with that tag), as GitHub describes it: with [assets]
  /// attached (both files by default) and [body] as its notes (by default
  /// [releaseBody] for [whatIsNew]).
  void publish(
    String tag, {
    String? whatIsNew,
    String? body,
    List<String> assets = const [
      UpdateChecker.assetName,
      UpdateChecker.exeAssetName,
    ],
    bool draft = false,
    bool prerelease = false,
  }) {
    _override = null;
    _releases
      ..removeWhere((release) => release['tag_name'] == tag)
      ..insert(0, {
        'url':
            'https://api.github.com/repos/yvanvds/smartschool-mcp/releases/'
            '${_releases.length + 1}',
        'html_url': releasePage(tag),
        'id': _releases.length + 1,
        'tag_name': tag,
        'name': tag,
        'draft': draft,
        'prerelease': prerelease,
        'assets': [
          for (final asset in assets)
            {
              'name': asset,
              'content_type': 'application/octet-stream',
              'browser_download_url': downloadLink(tag, asset),
            },
        ],
        'body': body ?? releaseBody(tag, whatIsNew: whatIsNew),
      });
  }

  /// From now on there is no release: GitHub answers with an empty list.
  void noReleases() {
    _override = null;
    _releases.clear();
  }

  /// From now on GitHub's rate limit is reached.
  void rateLimited() => answer(
    HttpStatus.forbidden,
    jsonEncode({'message': 'API rate limit exceeded for 127.0.0.1.'}),
  );

  /// From now on every request gets [status] and [body] (until [publish] or
  /// [noReleases]).
  void answer(int status, String body) => _override = (status, body);

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
    final (status, body) = _override ?? (HttpStatus.ok, jsonEncode(_releases));
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
  return Uri.parse('http://127.0.0.1:$port/releases');
}
