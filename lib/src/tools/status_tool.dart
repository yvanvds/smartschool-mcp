import 'package:dart_mcp/server.dart';

import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../settings.dart';
import '../update_check.dart';
import '../version.dart';
import 'server_tool.dart';

/// `smartschool_status`: whether the Smartschool connection works, and if
/// not, what to fix; and whether a newer version of the server is available
/// ([updates] asks GitHub on every call; null when the update check is
/// turned off).
ServerTool statusTool(
  SmartschoolSession session, {
  UpdateChecker? updates,
}) => ServerTool(
  definition: Tool(
    name: 'smartschool_status',
    title: 'Smartschool connection status',
    description:
        'Checks whether the connection to Smartschool works: whether all '
        'settings are filled in, whether logging in succeeds, who is logged '
        'in, the Smartschool address, the version of this server and whether '
        'a newer version is available. Use it when the user asks whether '
        'their Smartschool connection works (for example "Werkt mijn '
        'Smartschool-verbinding?") or whether there is an update, or when '
        'another Smartschool tool reports a login problem. When the '
        'connection does not work, the result says what to fix; pass that on '
        'to the user. When a newer version is available, tell the user how '
        'to update.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'Smartschool connection status',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (_) => _status(session, updates),
);

Future<CallToolResult> _status(
  SmartschoolSession session,
  UpdateChecker? updates,
) async {
  // Asks GitHub while the connection is checked, so it adds no time.
  final updateCheck = updates?.checkNow();
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
  final update = await updateCheck;
  report.add(_describeUpdate(update));
  if (update case UpdateAvailable(:final release)) {
    // Shown here, so no tool result repeats it as a notice.
    updates?.announced(release);
  }
  return CallToolResult(content: [TextContent(text: report.join('\n'))]);
}

/// The `Updates:` line: what the update check found, or that it is off.
String _describeUpdate(UpdateCheckResult? result) => switch (result) {
  null => 'Updates: not checked (the update check is turned off)',
  UpdateAvailable(:final release) =>
    'Updates: version ${release.version} is available. To update, '
        '${UpdateChecker.howToUpdate(release)}.',
  UpToDate(latest: null) => 'Updates: up to date (no release published yet)',
  UpToDate(:final latest?) =>
    'Updates: up to date (latest release: ${latest.version})',
  UpdateCheckFailed(:final reason) => 'Updates: could not check ($reason)',
};

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
