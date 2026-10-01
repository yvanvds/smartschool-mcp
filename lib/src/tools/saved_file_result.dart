import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../downloads/download_folder.dart';
import '../intradesk/intradesk_format.dart';
import '../settings.dart';
import 'server_tool.dart';

// What `save_intradesk_file` and `save_message_attachment` have in common:
// their result, their messages and their log line.

/// The result of saving [saved] (what it is: [title]) in [folder]: the full
/// path, the file name, the size, notes about the name, and what Claude
/// does next.
CallToolResult savedFileResult(
  String title,
  SavedFile saved,
  DownloadFolder folder,
) => CallToolResult(
  content: [
    TextContent(
      text: [
        'Saved $title in the download folder.',
        'Path: ${saved.path}',
        'File name: ${saved.name}',
        'Size: ${formatFileSize(saved.size)}'
            '${saved.size < 1024 ? '' : ' (${saved.size} bytes)'}',
        for (final note in saved.notes) 'Note: $note',
        'Open the file from this path with your own file tools if you can; '
            'otherwise tell the user where it is, so they can open it or '
            'drag it into the chat. It is deleted from the download folder '
            'after ${folder.retention.inDays} days.',
      ].join('\n'),
    ),
  ],
);

/// The size Smartschool announced for a download that was too large, when
/// that is what was too large; null when more bytes came in than allowed
/// (how many more is unknown).
int? tooLargeSize(SmartschoolDownloadTooLargeError error) =>
    switch (error.contentLength) {
      final size? when size > error.maxBytes => size,
      _ => null,
    };

/// `is too large to save here ...`, for after what the file is.
String tooLargeToSave(SmartschoolDownloadTooLargeError error) {
  final limit = formatFileSize(error.maxBytes);
  return 'is too large to save here'
      '${tooLargeSize(error) == null ? ' (more than $limit)' : ''}: files up '
      'to $limit can be saved. The teacher can download it in Smartschool.';
}

/// The error when there is no download folder (no setting and no home
/// folder for the default).
ToolError noDownloadFolder() => ToolError(
  'There is no download folder to save files in. Set '
  '"${Setting.downloadDir.formTitle}" (${Setting.downloadDir.envVar}) in the '
  'Smartschool extension settings to a folder, then restart Claude Desktop.',
);

/// What happened to the name of [saved], for the log; never the name.
String describeNameForLog(SavedFile saved) => [
  if (saved.safeName.given == null)
    'no name given'
  else if (saved.safeName.changes.isEmpty)
    'name as given'
  else
    'name changed',
  if (saved.name != saved.safeName.name) 'numbered',
].join(', ');
