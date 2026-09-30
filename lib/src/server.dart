import 'package:dart_mcp/server.dart';

import 'tools/server_tool.dart';
import 'version.dart';

/// The Smartschool MCP server.
///
/// Speaks MCP over the given channel (stdin/stdout in production) and exposes
/// the [ServerTool]s it is constructed with.
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
      registerTool(tool.definition, tool.handler);
    }
  }

  /// The server name reported to MCP clients.
  static const String serverName = 'smartschool';
}
