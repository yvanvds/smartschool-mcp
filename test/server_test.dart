import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/problems.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

import 'support/mcp.dart';

/// A tool without arguments whose handler is [handler].
ServerTool _tool(String name, ToolHandler handler) => ServerTool(
  definition: Tool(name: name, inputSchema: Schema.object()),
  handler: handler,
);

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

  test('the instructions do not assume a teacher: students sign in too '
      '(#41)', () async {
    final (_, result) = await connect();

    expect(
      result.instructions,
      'Tools for working with Smartschool on behalf of the signed-in user, a '
      'teacher or a student.',
    );
  });

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

  group('a tool that throws', () {
    test('a SmartschoolProblem becomes an error result with exactly its '
        'message', () async {
      const problem = SmartschoolProblem(
        ProblemKind.wrongPassword,
        'Smartschool did not accept the username or password.',
      );
      final (connection, _) = await connect(
        tools: [_tool('login_fails', (_) => throw problem)],
      );

      final (result, text) = await callTool(connection, 'login_fails');

      expect(result.isError, isTrue);
      expect(text, problem.message);
    });

    test('anything else becomes a generic error result without the '
        'exception or its stack trace', () async {
      final (connection, _) = await connect(
        tools: [
          _tool('crashes', (_) async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('internal detail');
          }),
        ],
      );

      final (result, text) = await callTool(connection, 'crashes');

      expect(result.isError, isTrue);
      expect(text, contains('crashes failed with an unexpected error'));
      expect(text, isNot(contains('internal detail')));
      expect(text, isNot(contains('#0')), reason: 'no stack trace');
      expect(text, isNot(contains('.dart')), reason: 'no stack trace');
    });
  });
}
