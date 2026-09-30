/// End-to-end test: compiles the server with `dart compile exe` and talks to
/// the executable over stdio the way Claude Desktop does.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String exePath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('smartschool_mcp_e2e_');
    exePath = [
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
  });

  tearDownAll(() => tempDir.delete(recursive: true));

  test('the compiled exe answers initialize and tools/list on stdout, '
      'logs only to stderr and exits when stdin closes', () async {
    final process = await Process.start(exePath, const []);
    addTearDown(process.kill);
    final stderrText = process.stderr.transform(utf8.decoder).join();
    final stdoutLines = StreamQueue(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );

    void send(Map<String, Object?> message) =>
        process.stdin.writeln(jsonEncode(message));

    /// Reads the next stdout line, which must be a JSON-RPC 2.0 message.
    Future<Map<String, Object?>> receive() async {
      final line = await stdoutLines.next.timeout(const Duration(seconds: 30));
      final message = jsonDecode(line) as Map<String, Object?>;
      expect(message['jsonrpc'], '2.0', reason: 'not JSON-RPC 2.0: $line');
      return message;
    }

    send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'e2e-test', 'version': '0.0.0'},
      },
    });
    final initialize = await receive();
    expect(initialize['id'], 1);
    expect(initialize, isNot(contains('error')));
    final initResult = initialize['result'] as Map<String, Object?>;
    expect(initResult['protocolVersion'], '2025-06-18');
    expect(initResult['serverInfo'], {
      'name': 'smartschool',
      'version': packageVersion,
    });
    expect(
      (initResult['capabilities'] as Map<String, Object?>)['tools'],
      isA<Map<String, Object?>>(),
    );

    send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    final toolsList = await receive();
    expect(toolsList['id'], 2);
    expect(toolsList, isNot(contains('error')));
    expect((toolsList['result'] as Map<String, Object?>)['tools'], isEmpty);

    await process.stdin.close();
    expect(
      await process.exitCode.timeout(const Duration(seconds: 30)),
      0,
      reason: 'server did not exit cleanly after stdin closed',
    );
    expect(
      await stdoutLines.rest.toList(),
      isEmpty,
      reason: 'stdout must carry nothing but protocol responses',
    );
    expect(await stderrText, contains('serving MCP on stdio'));
  });
}
