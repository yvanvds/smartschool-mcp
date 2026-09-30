/// The update notice in tool results and the `Updates:` line of
/// `smartschool_status`, over MCP on the real server, session, library and
/// tools, against a fake Smartschool and a fake GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:test/test.dart';

import 'support/fake_github.dart';
import 'support/fake_smartschool.dart';
import 'support/mcp.dart';
import 'support/sample_documents.dart';

void main() {
  late FakeSmartschool smartschool;
  late FakeGitHub github;
  late File stateFile;

  setUp(() async {
    smartschool = FakeSmartschool()..intradesk.loadFixtures();
    smartschool.mailbox.inbox.add(
      FakeMessage(
        id: 101,
        sender: 'Jan Peeters',
        subject: 'Oudercontact donderdag',
        date: '2024-03-14 16:05',
      ),
    );
    github = await FakeGitHub.start();
    stateFile = File(
      [
        (await tempCache()).path,
        UpdateChecker.stateFileName,
      ].join(Platform.pathSeparator),
    );
  });

  /// The update check of a server at version 0.1.0, asking [github].
  UpdateChecker checker({
    Duration timeout = const Duration(seconds: 5),
    Uri? endpoint,
  }) {
    final updates = UpdateChecker(
      stateFile: stateFile,
      endpoint: endpoint ?? github.latestRelease,
      currentVersion: '0.1.0',
      timeout: timeout,
    );
    addTearDown(updates.close);
    return updates;
  }

  /// A server with `smartschool_status`, `list_messages` and
  /// `read_intradesk_file` and the update check [updates], wired up as in
  /// `bin/smartschool_mcp.dart`.
  Future<ServerConnection> serve(
    UpdateChecker? updates, {
    CredentialSource? source,
  }) async {
    final session = SmartschoolSession(
      source ?? fakeExtensionSettings(),
      createClient: fakeClientFactory(smartschool, await tempCache()),
    );
    addTearDown(session.close);
    final index = IntradeskIndexCache(await tempCache());
    addTearDown(() => index.walkDone);
    final (connection, _) = await connect(
      tools: [
        statusTool(session, updates: updates),
        listMessagesTool(session),
        readIntradeskFileTool(session, index),
      ],
      updates: updates,
    );
    return connection;
  }

  Future<CallToolResult> call(
    ServerConnection connection,
    String name, [
    Map<String, Object?>? arguments,
  ]) => connection.callTool(CallToolRequest(name: name, arguments: arguments));

  /// The text of the single content item of [result].
  String text(CallToolResult result) {
    expect(result.content, hasLength(1));
    return (result.content.single as TextContent).text;
  }

  final notice =
      'Update available: version 0.2.0 of the Smartschool extension has been '
      'released (this is version 0.1.0). Please tell the user: to update, '
      'download smartschool-mcp.mcpb from ${releasePage('v0.2.0')} and '
      'double-click it.';
  final statusLine =
      'Updates: version 0.2.0 is available. To update, download '
      'smartschool-mcp.mcpb from ${releasePage('v0.2.0')} and double-click '
      'it.';

  test('a newer release: the notice comes once, as a text of its own after '
      'the content of the first successful result; an error result and an '
      'image stay as they are', () async {
    github.publish('v0.2.0');
    final updates = checker();
    final connection = await serve(updates);
    // As at startup.
    updates.checkInBackground();
    await updates.idle;

    final error = await call(connection, 'read_intradesk_file', {
      'file_id': 'welkom.docx',
    });
    expect(error.isError, isTrue);
    expect(text(error), startsWith('file_id must be an Intradesk id like '));

    final png = samplePng(40, 30);
    final id = smartschool.intradesk.addFile('logo.png', content: png);
    final image = await call(connection, 'read_intradesk_file', {
      'file_id': id,
    });
    expect(image.isError, isNot(true));
    expect(image.content, hasLength(3));
    expect(
      (image.content[0] as TextContent).text,
      startsWith('Intradesk file logo.png (id $id, '),
    );
    expect(image.content[1].isImage, isTrue);
    expect((image.content[1] as ImageContent).mimeType, 'image/png');
    expect(base64Decode((image.content[1] as ImageContent).data), png);
    expect(image.content[2].isText, isTrue);
    expect((image.content[2] as TextContent).text, notice);

    final messages = await call(connection, 'list_messages');
    expect(messages.isError, isNot(true));
    expect(text(messages), contains('Oudercontact donderdag'));
    expect(text(messages), isNot(contains('Update available')));

    final status = text(await call(connection, 'smartschool_status'));
    expect(status, startsWith('Smartschool connection: working\n'));
    expect(status, endsWith('\nServer version: 0.1.0\n$statusLine'));
    expect(github.requests, hasLength(2));
  });

  test('smartschool_status asks GitHub again although the last check is '
      'recent, shows the newer release, and no tool result repeats it as a '
      'notice', () async {
    github.noReleases();
    final updates = checker();
    final connection = await serve(updates);
    updates.checkInBackground();
    await updates.idle;
    github.publish('v0.2.0');

    final status = text(await call(connection, 'smartschool_status'));

    expect(github.requests, hasLength(2));
    expect(status, startsWith('Smartschool connection: working\n'));
    expect(status, endsWith('\n$statusLine'));
    final messages = await call(connection, 'list_messages');
    expect(text(messages), isNot(contains('Update available')));
  });

  test('smartschool_status checks for updates without Smartschool '
      'settings', () async {
    github.publish('v0.2.0');
    final connection = await serve(
      checker(),
      source: fakeExtensionSettings(
        FakeCredentials(mainUrl: '', username: '', password: '', mfa: ''),
      ),
    );

    final status = text(await call(connection, 'smartschool_status'));

    expect(status, startsWith('Smartschool connection: NOT working\n'));
    expect(status, endsWith('\n$statusLine'));
    expect(smartschool.requests, isEmpty);
  });

  for (final (name, answer, line) in [
    (
      'up to date',
      (FakeGitHub github) => github.publish('v0.1.0'),
      'Updates: up to date (latest release: 0.1.0)',
    ),
    (
      'no release published yet',
      (FakeGitHub github) => github.noReleases(),
      'Updates: up to date (no release published yet)',
    ),
    (
      'rate limited',
      (FakeGitHub github) => github.rateLimited(),
      'Updates: could not check (127.0.0.1 refused to answer (HTTP 403), '
          'probably its limit of 60 requests per hour)',
    ),
  ]) {
    test('$name: no notice, and smartschool_status says so', () async {
      answer(github);
      final updates = checker();
      final connection = await serve(updates);
      updates.checkInBackground();
      await updates.idle;

      final messages = await call(connection, 'list_messages');
      final status = text(await call(connection, 'smartschool_status'));

      expect(text(messages), isNot(contains('Update available')));
      expect(status, startsWith('Smartschool connection: working\n'));
      expect(status, endsWith('\nServer version: 0.1.0\n$line'));
    });
  }

  test('while GitHub does not answer, tool calls do not wait for it; the '
      'notice comes with the first result after the answer', () async {
    github
      ..publish('v0.2.0')
      ..hold();
    final updates = checker(timeout: const Duration(minutes: 5));
    final connection = await serve(updates);
    updates.checkInBackground();
    await github.received(1);

    final before = await call(connection, 'list_messages');
    expect(text(before), contains('Oudercontact donderdag'));
    expect(text(before), isNot(contains('Update available')));

    github.release();
    await updates.idle;
    final after = await call(connection, 'list_messages');

    expect(after.content, hasLength(2));
    expect((after.content.first as TextContent).text, text(before));
    expect((after.content.last as TextContent).text, notice);
  });

  test('smartschool_status when GitHub does not answer in time or cannot be '
      'reached: could not check, and the connection is still '
      'reported', () async {
    github
      ..publish('v0.2.0')
      ..hold();
    final slow = await serve(
      checker(timeout: const Duration(milliseconds: 300)),
    );
    final offline = await serve(checker(endpoint: await unreachableAddress()));

    final slowStatus = text(await call(slow, 'smartschool_status'));
    final offlineStatus = text(await call(offline, 'smartschool_status'));

    expect(slowStatus, startsWith('Smartschool connection: working\n'));
    expect(
      slowStatus,
      endsWith(
        '\nUpdates: could not check (no answer from 127.0.0.1 within '
        '300 ms)',
      ),
    );
    expect(offlineStatus, startsWith('Smartschool connection: working\n'));
    expect(
      offlineStatus,
      endsWith('\nUpdates: could not check (could not reach 127.0.0.1)'),
    );
  });

  test('without an update check (turned off): no notice, GitHub is not '
      'asked, and smartschool_status says it is off', () async {
    github.publish('v0.2.0');
    final connection = await serve(null);

    final messages = await call(connection, 'list_messages');
    final status = text(await call(connection, 'smartschool_status'));

    expect(text(messages), isNot(contains('Update available')));
    expect(
      status,
      endsWith('\nUpdates: not checked (the update check is turned off)'),
    );
    expect(github.requests, isEmpty);
  });
}
