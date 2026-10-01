/// The update check against a fake GitHub (never the real one), with a fake
/// clock for the 24 hour throttle.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:smartschool_mcp/src/cache_folder.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/fake_github.dart';
import 'support/fake_smartschool.dart';

void main() {
  late FakeGitHub github;
  late File stateFile;
  late DateTime now;

  setUp(() async {
    github = await FakeGitHub.start();
    final cache = await tempCache();
    stateFile = File(
      [cache.path, UpdateChecker.stateFileName].join(Platform.pathSeparator),
    );
    now = DateTime.utc(2026, 9, 30, 8);
  });

  /// A checker of this server at version [current] asking [github], as a
  /// server process would create it: each call is a new process sharing
  /// the state file.
  UpdateChecker checker({
    String current = '0.1.0',
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final updates = UpdateChecker(
      stateFile: stateFile,
      endpoint: endpoint ?? github.latestRelease,
      currentVersion: current,
      timeout: timeout,
      clock: () => now,
    );
    addTearDown(updates.close);
    return updates;
  }

  /// Starts a background check and waits for it.
  Future<void> backgroundCheck(UpdateChecker updates) async {
    updates.checkInBackground();
    await updates.idle;
  }

  Map<String, Object?> savedState() =>
      jsonDecode(stateFile.readAsStringSync()) as Map<String, Object?>;

  group('Release.parseTag', () {
    test('reads a semantic version with or without a v', () {
      for (final tag in ['v1.2.3', 'V1.2.3', '1.2.3', ' v1.2.3 ']) {
        expect(Release.parseTag(tag), Version(1, 2, 3), reason: tag);
      }
      expect(
        Release.parseTag('v1.0.0-beta.1'),
        Version(1, 0, 0, pre: 'beta.1'),
      );
    });

    test('ignores anything else', () {
      for (final tag in [
        '',
        'v',
        'latest',
        'release-2026',
        'v1.2',
        'v1.2.3.4',
        'vv1.2.3',
        'version 1.2.3',
      ]) {
        expect(Release.parseTag(tag), isNull, reason: tag);
      }
    });
  });

  group('compares the latest release with this version', () {
    for (final (current, tag, newer) in [
      ('0.1.0', 'v0.2.0', true),
      ('0.1.0', 'v0.1.1', true),
      ('0.1.0', 'v1.0.0', true),
      ('0.9.0', 'v0.10.0', true),
      ('0.9.0', 'v1.0.0-rc.1', true),
      ('0.1.0', 'v0.1.0', false),
      ('0.10.0', 'v0.9.0', false),
      ('1.0.0', 'v0.9.9', false),
      ('1.0.0', 'v1.0.0-rc.1', false),
    ]) {
      test('$current and $tag: ${newer ? '' : 'no '}update', () async {
        github.publish(tag);

        final result = await checker(current: current).checkNow();

        final release = switch (result) {
          UpdateAvailable(:final release) when newer => release,
          UpToDate(:final latest?) when !newer => latest,
          _ => fail('unexpected result: $result'),
        };
        expect(release.tag, tag);
        expect(release.version, Release.parseTag(tag));
        expect(release.url, Uri.parse(releasePage(tag)));
      });
    }
  });

  group('GitHub\'s answer', () {
    test(
      'asks the endpoint unauthenticated, as smartschool-mcp, for JSON',
      () async {
        github.publish('v0.2.0');

        await checker().checkNow();

        expect(github.requests, hasLength(1));
        final request = github.requests.single;
        expect(request.path, '/repos/yvanvds/smartschool-mcp/releases/latest');
        expect(request.userAgent, startsWith('smartschool-mcp/0.1.0 '));
        expect(request.accept, 'application/vnd.github+json');
      },
    );

    test('404 (no release published yet): up to date, and saved', () async {
      github.noReleases();

      final result = await checker().checkNow();

      expect(result, isA<UpToDate>().having((r) => r.latest, 'latest', null));
      expect(savedState(), {
        'format': UpdateChecker.stateFormat,
        'endpoint': github.latestRelease.toString(),
        'checked_at': now.toIso8601String(),
        'latest': null,
      });
    });

    test('a newer release is saved with its tag and page', () async {
      github.publish('v0.2.0');

      await checker().checkNow();

      expect(savedState(), {
        'format': UpdateChecker.stateFormat,
        'endpoint': github.latestRelease.toString(),
        'checked_at': now.toIso8601String(),
        'latest': {'tag': 'v0.2.0', 'url': releasePage('v0.2.0')},
      });
    });

    final failures = <String, (void Function(FakeGitHub), String)>{
      'rate limited (403)': (
        (github) => github.rateLimited(),
        'refused to answer (HTTP 403), probably its limit of 60 requests '
            'per hour',
      ),
      'too many requests (429)': (
        (github) => github.answer(429, '{}'),
        'refused to answer (HTTP 429)',
      ),
      'a server error': (
        (github) => github.answer(502, 'Bad gateway'),
        '127.0.0.1 answered HTTP 502',
      ),
      'not JSON': (
        (github) => github.answer(200, '<html>'),
        'not a release (not JSON)',
      ),
      'not a release': (
        (github) => github.answer(200, jsonEncode({'message': 'hello'})),
        'not a release (no tag_name or html_url)',
      ),
      'a tag that is not a version': (
        (github) => github.answer(
          200,
          jsonEncode({
            'tag_name': 'release-2026',
            'html_url': releasePage('release-2026'),
          }),
        ),
        'a tag that is not a version: "release-2026"',
      ),
      'a release page that is not https': (
        (github) => github.answer(
          200,
          jsonEncode({
            'tag_name': 'v0.2.0',
            'html_url': 'http://example.com/v0.2.0',
          }),
        ),
        'no https address',
      ),
    };
    for (final MapEntry(key: name, value: (setUpAnswer, reason))
        in failures.entries) {
      test('$name: the check failed, nothing saved, no notice', () async {
        setUpAnswer(github);
        final updates = checker();

        final result = await updates.checkNow();

        expect(
          result,
          isA<UpdateCheckFailed>().having(
            (r) => r.reason,
            'reason',
            contains(reason),
          ),
        );
        expect(stateFile.existsSync(), isFalse);
        expect(updates.takeNotice(), isNull);
      });
    }

    test('unreachable (offline): the check failed', () async {
      final result = await checker(
        endpoint: await unreachableAddress(),
      ).checkNow();

      expect(
        result,
        isA<UpdateCheckFailed>().having(
          (r) => r.reason,
          'reason',
          'could not reach 127.0.0.1',
        ),
      );
      expect(stateFile.existsSync(), isFalse);
    });

    test('no answer in time: the check gives up after the timeout', () async {
      github
        ..publish('v0.2.0')
        ..hold();
      final updates = checker(timeout: const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();

      final result = await updates.checkNow();

      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(
        result,
        isA<UpdateCheckFailed>().having(
          (r) => r.reason,
          'reason',
          'no answer from 127.0.0.1 within 300 ms',
        ),
      );
      expect(updates.takeNotice(), isNull);
    });
  });

  group('at most one check per 24 hours', () {
    test('a restart within 24 hours uses the saved check and does not ask; '
        'after 24 hours it asks again', () async {
      github.publish('v0.2.0');
      await backgroundCheck(checker());
      expect(github.requests, hasLength(1));

      now = now.add(const Duration(hours: 23, minutes: 59));
      final restarted = checker();
      await backgroundCheck(restarted);

      expect(github.requests, hasLength(1));
      expect(restarted.takeNotice(), contains('version 0.2.0'));

      now = now.add(const Duration(minutes: 1));
      github.publish('v0.3.0');
      final nextDay = checker();
      await backgroundCheck(nextDay);

      expect(github.requests, hasLength(2));
      expect(nextDay.takeNotice(), contains('version 0.3.0'));
    });

    test('"no release published yet" counts as a check', () async {
      github.noReleases();
      await backgroundCheck(checker());
      now = now.add(const Duration(hours: 12));

      await backgroundCheck(checker());

      expect(github.requests, hasLength(1));
    });

    test('a failed check is not saved: the next start asks again', () async {
      github.rateLimited();
      await backgroundCheck(checker());
      github.publish('v0.2.0');

      final restarted = checker();
      await backgroundCheck(restarted);

      expect(github.requests, hasLength(2));
      expect(restarted.takeNotice(), contains('version 0.2.0'));
    });

    test('a running server asks once a day, on a tool call, and not again '
        'after a failure the same day', () async {
      github.rateLimited();
      final updates = checker();
      await backgroundCheck(updates);
      github.publish('v0.2.0');

      now = now.add(const Duration(hours: 23));
      expect(updates.takeNotice(), isNull);
      await updates.idle;
      expect(github.requests, hasLength(1));

      now = now.add(const Duration(hours: 1));
      expect(updates.takeNotice(), isNull, reason: 'the answer is not in yet');
      await updates.idle;
      expect(github.requests, hasLength(2));
      expect(updates.takeNotice(), contains('version 0.2.0'));

      now = now.add(const Duration(hours: 23));
      github.publish('v0.3.0');
      expect(updates.takeNotice(), isNull);
      await updates.idle;
      expect(github.requests, hasLength(2));
    });

    test('checkNow asks every time', () async {
      github.noReleases();
      final updates = checker();

      await updates.checkNow();
      await updates.checkNow();

      expect(github.requests, hasLength(2));
    });

    test('a saved check of another address, a damaged file or a check '
        'dated in the future is not used', () async {
      for (final contents in [
        jsonEncode({
          'format': UpdateChecker.stateFormat,
          'endpoint': 'https://example.com/releases/latest',
          'checked_at': now.toIso8601String(),
          'latest': null,
        }),
        '{"format": 1, "endp',
        jsonEncode({
          'format': UpdateChecker.stateFormat,
          'endpoint': github.latestRelease.toString(),
          'checked_at': now.add(const Duration(days: 3)).toIso8601String(),
          'latest': null,
        }),
      ]) {
        stateFile
          ..createSync(recursive: true)
          ..writeAsStringSync(contents);
        github.publish('v0.2.0');
        final requests = github.requests.length;
        final updates = checker();

        await backgroundCheck(updates);

        expect(github.requests, hasLength(requests + 1), reason: contents);
        expect(updates.takeNotice(), contains('version 0.2.0'));
        expect(savedState()['checked_at'], now.toIso8601String());
      }
    });
  });

  group('the notice', () {
    test('says which version, which is installed, and how to update', () async {
      github.publish('v0.2.0');
      final updates = checker();
      await backgroundCheck(updates);

      expect(
        updates.takeNotice(),
        'Update available: version 0.2.0 of the Smartschool extension has '
        'been released (this is version 0.1.0). Please tell the user: to '
        'update, download smartschool-mcp.mcpb from ${releasePage('v0.2.0')} '
        'and double-click it.',
      );
    });

    test('is given once per process, and again for a later release', () async {
      github.publish('v0.2.0');
      final updates = checker();
      await updates.checkNow();

      expect(updates.takeNotice(), contains('version 0.2.0'));
      expect(updates.takeNotice(), isNull);

      github.publish('v0.3.0');
      await updates.checkNow();

      expect(updates.takeNotice(), contains('version 0.3.0'));
      expect(updates.takeNotice(), isNull);
    });

    test('is not given after smartschool_status showed the release', () async {
      github.publish('v0.2.0');
      final updates = checker();

      final result = await updates.checkNow();
      updates.announced((result as UpdateAvailable).release);

      expect(updates.takeNotice(), isNull);
    });

    test('is not given when up to date, without releases or before the '
        'check is in', () async {
      github
        ..publish('v0.2.0')
        ..hold();
      final pending = checker();
      pending.checkInBackground();
      await github.received(1);
      expect(pending.takeNotice(), isNull);
      github.release();
      await pending.idle;

      github.publish('v0.1.0');
      final upToDate = checker();
      await upToDate.checkNow();
      expect(upToDate.takeNotice(), isNull);

      github.noReleases();
      final noReleases = checker();
      await noReleases.checkNow();
      expect(noReleases.takeNotice(), isNull);
    });
  });

  group('fromEnvironment', () {
    test('asks GitHub by default and keeps its state in the shared cache '
        'folder, which needs no Smartschool settings', () {
      final updates = UpdateChecker.fromEnvironment(const {})!;
      addTearDown(updates.close);

      expect(updates.endpoint, UpdateChecker.defaultEndpoint);
      expect(
        UpdateChecker.defaultEndpoint.toString(),
        'https://api.github.com/repos/yvanvds/smartschool-mcp/releases/latest',
      );
      expect(
        updates.stateFile.path,
        [
          sharedCacheDirectory(),
          'smartschool-mcp-update-check.json',
        ].join(Platform.pathSeparator),
      );
      expect(updates.current, Version.parse(packageVersion));
    });

    test('SMARTSCHOOL_MCP_UPDATE_CHECK=off (or false, no, 0) turns it off', () {
      for (final value in ['off', 'OFF', ' false ', 'no', '0']) {
        expect(
          UpdateChecker.fromEnvironment({
            'SMARTSCHOOL_MCP_UPDATE_CHECK': value,
          }),
          isNull,
          reason: value,
        );
      }
      final on = UpdateChecker.fromEnvironment({
        'SMARTSCHOOL_MCP_UPDATE_CHECK': 'on',
      });
      expect(on, isNotNull);
    });

    test('SMARTSCHOOL_MCP_UPDATE_URL asks another address; one that is not '
        'http(s) turns the check off', () {
      final updates = UpdateChecker.fromEnvironment({
        'SMARTSCHOOL_MCP_UPDATE_URL': ' http://127.0.0.1:8080/latest ',
      })!;
      expect(updates.endpoint, Uri.parse('http://127.0.0.1:8080/latest'));

      for (final value in ['ftp://example.com/latest', 'not an address']) {
        expect(
          UpdateChecker.fromEnvironment({'SMARTSCHOOL_MCP_UPDATE_URL': value}),
          isNull,
          reason: value,
        );
      }
    });
  });
}
