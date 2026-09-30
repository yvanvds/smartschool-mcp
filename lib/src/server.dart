import 'package:dart_mcp/server.dart';

import 'log.dart';
import 'problems.dart';
import 'tools/server_tool.dart';
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
base class SmartschoolServer extends MCPServer with ToolsSupport {
  SmartschoolServer(super.channel, {Iterable<ServerTool> tools = const []})
    : super.fromStreamChannel(
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

  static Future<CallToolResult> _call(
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
}
