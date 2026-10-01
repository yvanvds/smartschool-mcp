import 'package:dart_mcp/server.dart';

import '../downloads/download_folder.dart';
import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../settings.dart';
import '../update_check.dart';
import '../version.dart';
import 'server_tool.dart';

/// `smartschool_status`: whether the Smartschool connection works, and if
/// not, what to fix; whether a newer version of the server is available
/// ([updates] asks GitHub on every call; null when the update check is
/// turned off); and, with [downloads], which download folder the save tools
/// use and whether it is writable ([downloads] gives that folder, null when
/// there is none; without [downloads], the status says nothing about
/// downloads).
ServerTool statusTool(
  SmartschoolSession session, {
  UpdateChecker? updates,
  DownloadFolder? Function()? downloads,
}) => ServerTool(
  definition: Tool(
    name: 'smartschool_status',
    title: 'Smartschool connection status',
    description:
        'Checks whether the connection to Smartschool works: whether all '
        'settings are filled in, whether logging in succeeds, who is logged '
        'in, the Smartschool address, the download folder files are saved in '
        'and whether it is writable, the version of this server and whether '
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
  handler: (_) => _status(session, updates, downloads),
);

Future<CallToolResult> _status(
  SmartschoolSession session,
  UpdateChecker? updates,
  DownloadFolder? Function()? downloads,
) async {
  // Asks GitHub and tries the download folder while the connection is
  // checked, so they add no time.
  final updateCheck = updates?.checkNow();
  final folder = downloads?.call();
  final folderCheck = folder?.check();
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
    if (downloads != null)
      _describeDownloadFolder(folder, await folderCheck, session.source),
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

/// The `Download folder:` line: the folder, where its path comes from, and
/// whether files can be saved in it, or how to choose another.
String _describeDownloadFolder(
  DownloadFolder? folder,
  DownloadFolderState? state,
  CredentialSource source,
) {
  if (folder == null || state == null) {
    return 'Download folder: none (there is no home folder for the '
        'default). To save files, set ${source.name(Setting.downloadDir)} '
        '${source.where}, then ${source.restart}.';
  }
  final where = 'Download folder: ${folder.path} (${folder.origin.label}';
  if (!state.writable) {
    return '$where; NOT writable: ${state.problem}). To save files, '
        '${folder.origin.fix}.';
  }
  return state.exists
      ? '$where; writable)'
      : '$where; does not exist yet: it is created when the first file is '
            'saved)';
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
    for (final setting in Setting.login)
      '${_shortName(source, setting)}: '
          '${missing.contains(setting) ? 'missing' : 'filled in'}',
  ];
  return '$origin (${states.join(', ')})';
}

String _shortName(CredentialSource source, Setting setting) => switch (source) {
  ExtensionSettings() => setting.formTitle,
  CredentialsFile() => setting.fileKey,
};
