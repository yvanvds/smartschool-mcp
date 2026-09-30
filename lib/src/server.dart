import 'package:dart_mcp/server.dart';

import 'log.dart';
import 'problems.dart';
import 'tools/server_tool.dart';
import 'update_check.dart';
import 'version.dart';

/// The Smartschool MCP server.
///
/// Speaks MCP over the given channel (stdin/stdout in production) and exposes
/// the [ServerTool]s it is constructed with.
///
/// A tool may simply let a [SmartschoolProblem] (a login or connection
/// failure) propagate: the server turns it into an error result carrying the
/// problem's message, so every tool reports those the same way. A
/// [ToolError] (an invalid argument) likewise becomes an error result with
/// its message. Any other exception becomes a generic error result; its
/// details and stack trace go to the log only, never into tool output.
///
/// With [updates], the server adds the update notice
/// ([UpdateChecker.takeNotice]) to the first successful tool result after a
/// newer release became known.
base class SmartschoolServer extends MCPServer with ToolsSupport {
  SmartschoolServer(
    super.channel, {
    Iterable<ServerTool> tools = const [],
    UpdateChecker? updates,
  }) : _updates = updates,
       super.fromStreamChannel(
         implementation: Implementation(
           name: serverName,
           version: packageVersion,
         ),
         instructions:
             'Tools for working with Smartschool on behalf of the signed-in '
             'teacher.',
       ) {
    for (final tool in tools) {
      registerTool(tool.definition, (request) => _call(tool, request));
    }
  }

  /// The server name reported to MCP clients.
  static const String serverName = 'smartschool';

  final UpdateChecker? _updates;

  Future<CallToolResult> _call(
    ServerTool tool,
    CallToolRequest request,
  ) async => _withUpdateNotice(tool, await _run(tool, request));

  static Future<CallToolResult> _run(
    ServerTool tool,
    CallToolRequest request,
  ) async {
    try {
      return await tool.handler(request);
    } on SmartschoolProblem catch (problem) {
      return _error(problem.message);
    } on ToolError catch (error) {
      return _error(error.message);
    } catch (error, stackTrace) {
      final name = tool.definition.name;
      log('tool $name failed: $error\n$stackTrace');
      return _error(
        'The tool $name failed with an unexpected error. The technical '
        'details are in the server log.',
      );
    }
  }

  static CallToolResult _error(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);

  /// [result] with the update notice, if there is one, as a text of its own
  /// after the tool's content, which is kept as it is (an image stays an
  /// image). An error result gets no notice, which would read as part of the
  /// error: the notice waits for the next successful result.
  CallToolResult _withUpdateNotice(ServerTool tool, CallToolResult result) {
    final updates = _updates;
    if (updates == null || result.isError == true) return result;
    try {
      final notice = updates.takeNotice();
      if (notice == null) return result;
      log('update notice added to the ${tool.definition.name} result');
      return CallToolResult(
        meta: result.meta,
        content: [
          ...result.content,
          TextContent(text: notice),
        ],
        structuredContent: result.structuredContent,
        isError: result.isError,
      );
    } catch (error, stackTrace) {
      log('update notice failed: $error\n$stackTrace');
      return result;
    }
  }
}
