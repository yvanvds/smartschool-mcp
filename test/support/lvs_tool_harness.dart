import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/lvs/lvs_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'fake_smartschool.dart';
import 'log_capture.dart';
import 'mcp.dart';

/// The LVS tools (#153) called over MCP on the real server, session and
/// library (`LvsService`), against a fake Smartschool whose pupil tracking
/// system answers with the hand-written fixtures of `test/fixtures/lvs/`
/// (`fake_lvs.dart`). Made in a `setUp` ([start]), for the tests of each
/// LVS tool (#154 and on): the calls, the requests the fake LVS got, the
/// log of a call, and the cache folder.
final class LvsToolHarness {
  LvsToolHarness._(this.server, this.cache, this.session, this._now);

  /// Connects the LVS tools, with the switch on and [now] as today (for the
  /// tools' default school year); closed at the end of the test.
  static Future<LvsToolHarness> start({
    DateTime Function() now = DateTime.now,
  }) async {
    final server = FakeSmartschool();
    final cache = await tempCache();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cache),
    );
    addTearDown(session.close);
    final harness = LvsToolHarness._(server, cache, session, now);
    final (connection, _) = await connect(tools: harness._tools());
    harness._connection = connection;
    return harness;
  }

  /// The fake Smartschool.
  final FakeSmartschool server;

  /// The session's cache folder, where only the login keeps something.
  final Directory cache;

  /// The session the tools share.
  final SmartschoolSession session;

  final DateTime Function() _now;
  late final ServerConnection _connection;

  /// The fake LVS.
  FakeLvs get lvs => server.lvs;

  List<ServerTool> _tools() =>
      lvsOptIn(session, SwitchState.on, now: _now).offered;

  /// The tools as the server lists them, by name, in its order.
  Future<Map<String, Tool>> listTools() async => {
    for (final tool in (await _connection.listTools(ListToolsRequest())).tools)
      tool.name: tool,
  };

  /// Calls [tool] with [arguments] and returns its text, which must not be
  /// an error.
  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(_connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  /// Calls [tool] with [arguments] and returns its text, which must be an
  /// error.
  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(_connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// Calls [tool] with [arguments] on a server connected with the log
  /// captured, over the same session; returns whether it failed, its text
  /// and the log.
  Future<(bool?, String, String)> logged(
    String tool,
    Map<String, Object?> arguments,
  ) async {
    final ((result, text), log) = await captureLog(() async {
      final (connection, _) = await connect(tools: _tools());
      return callTool(connection, tool, arguments);
    });
    return (result.isError, text, log);
  }

  /// The files in [cache], sorted.
  List<String> cacheFiles() => [
    for (final file in cache.listSync(recursive: true))
      if (file is File) file.path,
  ]..sort();
}

/// The `pupil_id` and `class_id` arguments of [pupil].
Map<String, Object?> fakeLvsPupilArguments(FakeLvsPupil pupil) => {
  'pupil_id': pupil.pupilId,
  'class_id': pupil.classId,
};
