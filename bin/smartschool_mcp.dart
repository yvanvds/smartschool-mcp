import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:smartschool_mcp/src/log.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/version.dart';

/// Serves MCP over stdin/stdout until the client closes stdin.
///
/// stdout is the protocol channel. Diagnostics go to stderr, and any stray
/// `print` (ours or a dependency's) is redirected there as well.
Future<void> main() async {
  await runZoned(
    () async {
      final server = SmartschoolServer(
        stdioChannel(input: stdin, output: stdout),
      );
      log('version $packageVersion serving MCP on stdio');
      await server.done;
      log('client disconnected, shutting down');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => stderr.writeln(line),
    ),
  );
}
