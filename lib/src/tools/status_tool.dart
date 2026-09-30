import 'package:dart_mcp/server.dart';

import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../settings.dart';
import '../version.dart';
import 'server_tool.dart';

/// `smartschool_status`: whether the Smartschool connection works, and if
/// not, what to fix.
ServerTool statusTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'smartschool_status',
    title: 'Smartschool connection status',
    description:
        'Checks whether the connection to Smartschool works: whether all '
        'settings are filled in, whether logging in succeeds, who is logged '
        'in, the Smartschool address and the version of this server. Use it '
        'when the user asks whether their Smartschool connection works (for '
        'example "Werkt mijn Smartschool-verbinding?"), or when another '
        'Smartschool tool reports a login problem. When the connection does '
        'not work, the result says what to fix; pass that on to the user.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'Smartschool connection status',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (_) => _status(session),
);

Future<CallToolResult> _status(SmartschoolSession session) async {
  SmartschoolSettings? settings;
  String? displayName;
  String? problem;
  try {
    settings = session.settings;
    displayName = await session.run((client) async {
      // A live request, so a check hours after the first login still tests
      // the connection now (and logs in again if the session expired).
      await client.getJson(SmartschoolSession.sessionCheckPath);
      return (await client.getCurrentUser()).displayName;
    });
  } on SmartschoolProblem catch (error) {
    problem = error.message;
  } catch (error, stackTrace) {
    log('smartschool_status: unexpected error: $error\n$stackTrace');
    problem = settings == null
        ? 'Reading the Smartschool settings failed with an unexpected error. '
              'The technical details are in the server log.'
        : SmartschoolProblem.of(ProblemKind.unexpected, settings).message;
  }

  final source = session.source;
  final report = [
    if (problem == null) ...[
      'Smartschool connection: working',
      'Logged in as: $displayName',
    ] else ...[
      'Smartschool connection: NOT working',
      'Problem: $problem',
    ],
    if (settings != null)
      'Smartschool address: '
          '${settings.host.isEmpty ? '(not filled in)' : settings.host}',
    'Settings: ${_describeSettings(source, settings)}',
    'Server version: $packageVersion',
  ];
  return CallToolResult(content: [TextContent(text: report.join('\n'))]);
}

/// Where the settings come from and which are filled in, without values.
String _describeSettings(
  CredentialSource source,
  SmartschoolSettings? settings,
) {
  final origin = switch (source) {
    ExtensionSettings() => source.label,
    CredentialsFile(:final path) => '${source.label} $path',
  };
  if (settings == null) return origin;
  final missing = settings.missing;
  if (missing.isEmpty) return '$origin (all filled in)';
  final states = [
    for (final setting in Setting.values)
      '${_shortName(source, setting)}: '
          '${missing.contains(setting) ? 'missing' : 'filled in'}',
  ];
  return '$origin (${states.join(', ')})';
}

String _shortName(CredentialSource source, Setting setting) => switch (source) {
  ExtensionSettings() => setting.formTitle,
  CredentialsFile() => setting.fileKey,
};
