import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/log.dart';
import 'package:smartschool_mcp/src/messages/message_cache.dart';
import 'package:smartschool_mcp/src/options.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/archive_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/reply_to_message_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_message_attachment_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:smartschool_mcp/src/tools/search_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
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
      final intradeskIndex = IntradeskIndexCache.of(session);
      final downloads = DownloadFolder.resolve(source);
      final updates = UpdateChecker.fromEnvironment();
      final server = SmartschoolServer(
        stdioChannel(input: stdin, output: stdout),
        tools: [
          statusTool(session, updates: updates, downloads: () => downloads),
          listMessagesTool(session),
          readMessageTool(session),
          saveMessageAttachmentTool(session, downloads),
          searchMessagesTool(session, MessageTextCache.of(session)),
          archiveMessagesTool(session),
          replyToMessageTool(session),
          searchIntradeskTool(session, intradeskIndex),
          listIntradeskFolderTool(session, intradeskIndex),
          readIntradeskFileTool(session, intradeskIndex),
          saveIntradeskFileTool(session, intradeskIndex, downloads),
        ],
        updates: updates,
      );
      log('version $packageVersion serving MCP on stdio');
      log('Smartschool settings: ${source.logDescription}');
      log(
        downloads == null
            ? 'downloads: no download folder'
            : 'downloads: saving in ${downloads.path} '
                  '(${downloads.origin.label})',
      );
      // In the background: startup never waits for GitHub, nor for deleting
      // old downloads.
      updates?.checkInBackground();
      downloads?.cleanUpInBackground();
      await server.done;
      await updates?.close();
      await downloads?.idle;
      await session.close();
      log('client disconnected, shutting down');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => stderr.writeln(line),
    ),
  );
}
