import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';

/// Compiles the server with `dart compile exe` into a temporary directory
/// (deleted after the tests) and returns the executable's path.
Future<String> compileServer() async {
  final tempDir = await Directory.systemTemp.createTemp('smartschool_mcp_e2e_');
  addTearDown(() => tempDir.delete(recursive: true));
  final exePath = [
    tempDir.path,
    Platform.isWindows ? 'smartschool_mcp.exe' : 'smartschool_mcp',
  ].join(Platform.pathSeparator);
  final compile = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'bin/smartschool_mcp.dart',
    '-o',
    exePath,
  ]);
  if (compile.exitCode != 0) {
    fail('dart compile exe failed:\n${compile.stdout}\n${compile.stderr}');
  }
  return exePath;
}

/// This process's environment without the `SMARTSCHOOL_*` variables, so the
/// server sees no extension settings.
Map<String, String> environmentWithoutSmartschool() => {
  for (final MapEntry(:key, :value) in Platform.environment.entries)
    if (!key.toUpperCase().startsWith('SMARTSCHOOL_')) key: value,
};

/// The compiled server, driven over stdio like Claude Desktop does.
class ServerProcess {
  ServerProcess._(this._process)
    : stderr = _process.stderr.transform(utf8.decoder).join(),
      _stdout = StreamQueue(
        _process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );

  /// Starts the server at [exePath]. With [environment], the server gets
  /// exactly that environment.
  static Future<ServerProcess> start(
    String exePath, {
    List<String> args = const [],
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      exePath,
      args,
      environment: environment,
      includeParentEnvironment: environment == null,
    );
    addTearDown(process.kill);
    return ServerProcess._(process);
  }

  final Process _process;
  final StreamQueue<String> _stdout;
  int _nextId = 1;

  /// Everything the server wrote to stderr, once it has exited.
  final Future<String> stderr;

  /// Sends `initialize` and `notifications/initialized`; returns the
  /// initialize result.
  Future<Map<String, Object?>> initialize() async {
    final result = await request('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'e2e-test', 'version': '0.0.0'},
    });
    _send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    return result;
  }

  /// Sends a request and returns its result; fails on a JSON-RPC error.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    final id = _nextId++;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    final line = await _stdout.next.timeout(timeout);
    final message = jsonDecode(line) as Map<String, Object?>;
    expect(message['jsonrpc'], '2.0', reason: 'not JSON-RPC 2.0: $line');
    expect(message['id'], id);
    expect(message, isNot(contains('error')), reason: line);
    return message['result'] as Map<String, Object?>;
  }

  /// Calls the tool [name] with [arguments]; returns `isError` and the text
  /// of its single content item.
  Future<(bool?, String)> callTool(
    String name, {
    Map<String, Object?> arguments = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    }, timeout);
    final content = result['content'] as List;
    expect(content, hasLength(1));
    final item = content.single as Map<String, Object?>;
    expect(item['type'], 'text');
    return (result['isError'] as bool?, item['text'] as String);
  }

  /// Closes stdin and expects a clean exit with nothing but protocol
  /// responses on stdout.
  Future<void> stop() async {
    await _process.stdin.close();
    expect(
      await _process.exitCode.timeout(const Duration(seconds: 30)),
      0,
      reason: 'server did not exit cleanly after stdin closed',
    );
    expect(
      await _stdout.rest.toList(),
      isEmpty,
      reason: 'stdout must carry nothing but protocol responses',
    );
  }

  void _send(Map<String, Object?> message) =>
      _process.stdin.writeln(jsonEncode(message));
}
