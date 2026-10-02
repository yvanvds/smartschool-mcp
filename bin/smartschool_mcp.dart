import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/install.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/log.dart';
import 'package:smartschool_mcp/src/messages/message_cache.dart';
import 'package:smartschool_mcp/src/options.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/archive_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/flag_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_class_assignments_tool.dart';
import 'package:smartschool_mcp/src/tools/list_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_planner_tool.dart';
import 'package:smartschool_mcp/src/tools/mark_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/read_planned_element_tool.dart';
import 'package:smartschool_mcp/src/tools/reply_to_message_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_message_attachment_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:smartschool_mcp/src/tools/search_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/search_planners_tool.dart';
import 'package:smartschool_mcp/src/tools/search_recipients_tool.dart';
import 'package:smartschool_mcp/src/tools/send_message_tool.dart';
import 'package:smartschool_mcp/src/tools/status_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_messages_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:smartschool_mcp/src/version.dart';

/// Serves MCP over stdin/stdout until the client closes stdin, or, started
/// with `--install` or by a double-click, installs the server for ChatGPT
/// and Codex (`lib/src/install.dart`).
///
/// When serving, stdout is the protocol channel. Diagnostics go to stderr,
/// and any stray `print` (ours or a dependency's) is redirected there as
/// well.
Future<void> main(List<String> args) async {
  final ServerOptions options;
  try {
    options = ServerOptions.parse(args);
  } on FormatException catch (error) {
    log('${error.message}\n\n${ServerOptions.usage}');
    exitCode = 64; // EX_USAGE
    return;
  }
  final interactive = stdin.hasTerminal;
  if (options.installs(interactive: interactive)) {
    exitCode = await runInstaller(
      out: stdout,
      interactive: interactive,
      clipboard: options.clipboard,
    );
    return;
  }
  await _serve(options);
}

Future<void> _serve(ServerOptions options) async {
  await runZoned(
    () async {
      final client = ClientContext();
      final source = switch (options.credentialsPath) {
        final path? => CredentialsFile(path),
        null => ExtensionSettings(client: client),
      };
      final session = SmartschoolSession(source);
      final intradeskIndex = IntradeskIndexCache.of(session);
      final downloads = DownloadFolder.resolve(source);
      final updates = UpdateChecker.fromEnvironment();
      final server = SmartschoolServer(
        stdioChannel(input: stdin, output: stdout),
        client: client,
        tools: [
          statusTool(
            session,
            updates: updates,
            downloads: () => downloads,
            client: client,
          ),
          listMessagesTool(session),
          readMessageTool(session),
          saveMessageAttachmentTool(session, downloads),
          searchMessagesTool(session, MessageTextCache.of(session)),
          archiveMessagesTool(session),
          markMessagesTool(session),
          flagMessagesTool(session),
          trashMessagesTool(session),
          replyToMessageTool(session),
          searchRecipientsTool(session),
          sendMessageTool(session),
          searchIntradeskTool(session, intradeskIndex),
          listIntradeskFolderTool(session, intradeskIndex),
          readIntradeskFileTool(session, intradeskIndex),
          saveIntradeskFileTool(session, intradeskIndex, downloads),
          searchPlannersTool(session),
          listPlannerTool(session),
          readPlannedElementTool(session),
          listClassAssignmentsTool(session),
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
      // old downloads, nor for deleting a copy an update moved aside.
      updates?.checkInBackground();
      downloads?.cleanUpInBackground();
      unawaited(
        deleteReplacedCopies(File(Platform.resolvedExecutable).parent.path),
      );
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
