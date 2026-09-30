import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:smartschool_mcp/src/log.dart';
import 'package:smartschool_mcp/src/messages/message_cache.dart';
import 'package:smartschool_mcp/src/options.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/archive_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/reply_to_message_tool.dart';
import 'package:smartschool_mcp/src/tools/search_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/version.dart';

/// Serves MCP over stdin/stdout until the client closes stdin.
///
/// stdout is the protocol channel. Diagnostics go to stderr, and any stray
/// `print` (ours or a dependency's) is redirected there as well.
Future<void> main(List<String> args) async {
  await runZoned(
    () async {
      final ServerOptions options;
      try {
        options = ServerOptions.parse(args);
      } on FormatException catch (error) {
        log('${error.message}\n\n${ServerOptions.usage}');
        exitCode = 64; // EX_USAGE
        return;
      }

      final source = switch (options.credentialsPath) {
        final path? => CredentialsFile(path),
        null => const ExtensionSettings(),
      };
      final session = SmartschoolSession(source);
      final server = SmartschoolServer(
        stdioChannel(input: stdin, output: stdout),
        tools: [
          statusTool(session),
          listMessagesTool(session),
          readMessageTool(session),
          searchMessagesTool(session, MessageTextCache.of(session)),
          archiveMessagesTool(session),
          replyToMessageTool(session),
        ],
      );
      log('version $packageVersion serving MCP on stdio');
      log('Smartschool settings: ${source.logDescription}');
      await server.done;
      await session.close();
      log('client disconnected, shutting down');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => stderr.writeln(line),
    ),
  );
}
