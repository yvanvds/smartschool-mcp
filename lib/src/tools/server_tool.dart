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

/// A tool call that cannot be carried out as asked: an invalid argument, or
/// something the arguments name that does not exist.
///
/// A handler throws it with a [message] for Claude that says what to change;
/// the server turns it into an error result with that message.
final class ToolError implements Exception {
  const ToolError(this.message);

  final String message;

  @override
  String toString() => message;
}
