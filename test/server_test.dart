import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/server.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Connects a dart_mcp client to a [SmartschoolServer] over an in-memory
/// channel and completes the initialize handshake.
Future<(ServerConnection, InitializeResult)> connect({
  Iterable<ServerTool> tools = const [],
}) async {
  final channel = StreamChannelController<String>();
  final server = SmartschoolServer(channel.local, tools: tools);
  final client = MCPClient(Implementation(name: 'test', version: '0.0.0'));
  final connection = client.connectServer(channel.foreign);
  addTearDown(() async {
    await connection.shutdown();
    await server.shutdown();
  });

  final result = await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  connection.notifyInitialized();
  return (connection, result);
}

void main() {
  test(
    'initialize reports the server name, version and tools capability',
    () async {
      final (_, result) = await connect();

      expect(result.serverInfo.name, 'smartschool');
      expect(result.serverInfo.version, packageVersion);
      expect(result.protocolVersion, ProtocolVersion.latestSupported);
      expect(result.capabilities.tools, isNotNull);
    },
  );

  test('tools/list is empty when no tools are registered', () async {
    final (connection, _) = await connect();

    final tools = await connection.listTools(ListToolsRequest());

    expect(tools.tools, isEmpty);
  });

  test('tools passed to the constructor are listed and callable', () async {
    final echo = ServerTool(
      definition: Tool(
        name: 'echo',
        description: 'Returns its input.',
        inputSchema: Schema.object(
          properties: {'text': Schema.string()},
          required: ['text'],
        ),
      ),
      handler: (request) => CallToolResult(
        content: [TextContent(text: request.arguments!['text'] as String)],
      ),
    );
    final (connection, _) = await connect(tools: [echo]);

    final tools = await connection.listTools(ListToolsRequest());
    expect(tools.tools.map((t) => t.name), ['echo']);

    final result = await connection.callTool(
      CallToolRequest(name: 'echo', arguments: {'text': 'hallo'}),
    );
    expect(result.isError, isNot(true));
    expect((result.content.single as TextContent).text, 'hallo');
  });
}
