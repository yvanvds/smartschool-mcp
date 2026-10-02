import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/update_check.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Connects a dart_mcp client to a [SmartschoolServer] over an in-memory
/// channel and completes the initialize handshake.
///
/// Without [updates], the server has no update check. The client calls
/// itself [clientName] (`test`, an app the server does not know, by
/// default); the server records the app in [client], which the tools'
/// settings source should share.
Future<(ServerConnection, InitializeResult)> connect({
  Iterable<ServerTool> tools = const [],
  UpdateChecker? updates,
  ClientContext? client,
  String clientName = 'test',
}) async {
  final channel = StreamChannelController<String>();
  final server = SmartschoolServer(
    channel.local,
    tools: tools,
    updates: updates,
    client: client,
  );
  final mcpClient = MCPClient(
    Implementation(name: clientName, version: '0.0.0'),
  );
  final connection = mcpClient.connectServer(channel.foreign);
  addTearDown(() async {
    await connection.shutdown();
    await server.shutdown();
  });

  final result = await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: mcpClient.capabilities,
      clientInfo: mcpClient.implementation,
    ),
  );
  connection.notifyInitialized();
  return (connection, result);
}

/// Calls the tool [name] with [arguments] and returns the result and its
/// single text content.
Future<(CallToolResult, String)> callTool(
  ServerConnection connection,
  String name, [
  Map<String, Object?>? arguments,
]) async {
  final result = await connection.callTool(
    CallToolRequest(name: name, arguments: arguments),
  );
  return (result, (result.content.single as TextContent).text);
}
