import 'dart:async';

import 'package:dart_mcp/server.dart';

/// Handles a call to a [ServerTool].
typedef ToolHandler =
    FutureOr<CallToolResult> Function(CallToolRequest request);

/// An MCP tool together with the code that runs when a client calls it.
///
/// Each tool lives in its own file under `lib/src/tools/` and exposes a
/// [ServerTool]; the entry point passes the list of tools to
/// `SmartschoolServer`, which registers them.
class ServerTool {
  const ServerTool({required this.definition, required this.handler});

  /// The name, description and input schema advertised in `tools/list`.
  final Tool definition;

  /// Runs the tool for a `tools/call` request.
  final ToolHandler handler;
}
