import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../downloads/download_folder.dart';
import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../log.dart';
import '../session.dart';
import 'saved_file_result.dart';
import 'server_tool.dart';

/// Files larger than this are not saved. Higher than what
/// `read_intradesk_file` reads: nothing goes through the tool result.
const maxSavedFileBytes = 200 * 1024 * 1024;

/// `save_intradesk_file`: saves one file on Intradesk into the download
/// folder ([downloads]), so that Claude can open it with its own file tools
/// (in a Cowork project) or the teacher can.
///
/// The file's path, size and kind come from the index in [cache] when there
/// is one: a folder, or a file larger than [maxBytes], is refused without
/// downloading. Saving never builds an index. Without a download folder
/// ([downloads] null), every call says how to set one.
ServerTool saveIntradeskFileTool(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  DownloadFolder? downloads, {
  int maxBytes = maxSavedFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'save_intradesk_file',
    title: 'Save an Intradesk file',
    description:
        'Saves one file from Intradesk, the school\'s shared document store '
        'in Smartschool, into the download folder on this PC, and returns '
        'its full path, file name and size. Use it to open a file '
        'read_intradesk_file cannot read (well), such as a scanned PDF, an '
        'old Office file (.doc, .xls, .ppt) or any other format, or when '
        'the user wants the file itself. After saving, open the file from '
        'the returned path with your own file tools when you can (for '
        'example in a Cowork project whose folder holds the download '
        'folder); otherwise tell the user where the file is, so they can '
        'open it or drag it into the chat. For a quick look at the text of '
        'a Word, Excel, PowerPoint, PDF or text file, read_intradesk_file is '
        'faster and works in every chat. Get the file id from '
        'search_intradesk or list_intradesk_folder. Files up to '
        '${formatFileSize(maxBytes)} are saved. An existing file is never '
        'replaced: the new one gets " (2)", " (3)", ... in its name. Files '
        'saved here are deleted after '
        '${DownloadFolder.defaultRetention.inDays} days; other files in the '
        'folder are never touched. Saving changes nothing on Intradesk.',
    inputSchema: Schema.object(
      properties: {
        'file_id': Schema.string(
          description:
              'The id of the file, from search_intradesk or '
              'list_intradesk_folder.',
        ),
      },
      required: ['file_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Save an Intradesk file',
      // It writes a file on this PC; it never replaces one.
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) =>
      _save(session, cache, downloads, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _save(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  DownloadFolder? downloads,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final id = intradeskIdArgument(arguments, 'file_id');
  if (id == null) {
    throw const ToolError(
      'file_id is empty: pass the id of a file, from search_intradesk or '
      'list_intradesk_folder.',
    );
  }

  final folder = downloads ?? (throw noDownloadFolder());

  // Inside the session, as the cache folder is the logged-in user's; also
  // reports missing settings before anything is written.
  final known = await session.run((_) async => (await cache.saved())?.find(id));
  _refuseBeforeDownload(id, known, maxBytes);

  final watch = Stopwatch()..start();
  final saved = await folder.save(
    (temporary) => session.run((client) async {
      try {
        // The library refuses a larger announced size before reading any of
        // the file, and otherwise stops the transfer once past the limit.
        final download = await writeDownload(
          temporary,
          () => IntradeskService(
            client,
          ).downloadFileStream(id, maxBytes: maxBytes),
        );
        return known?.name ?? download.fileName;
      } on SmartschoolDownloadError catch (error) {
        throw ToolError(
          'Smartschool could not download an Intradesk file with id $id '
          '(status ${error.statusCode}). Most likely it is not the id of a '
          'file you can open, for example a folder\'s id or a file that was '
          'removed: take the id of a file from search_intradesk or '
          'list_intradesk_folder. If the id is right, try again later.',
        );
      } on SmartschoolDownloadTooLargeError catch (error) {
        throw ToolError(
          '${intradeskFileTitle(id, known, size: tooLargeSize(error))} '
          '${tooLargeToSave(error)}',
        );
      }
    }),
    fallbackName: 'intradesk-$id',
  );
  log(
    'save_intradesk_file: ${saved.size} bytes saved in '
    '${watch.elapsedMilliseconds} ms '
    '(${known == null ? 'not in the index' : 'in the index'}, '
    '${describeNameForLog(saved)})',
  );
  return savedFileResult(
    intradeskFileTitle(id, known, name: saved.safeName.given, size: saved.size),
    saved,
    folder,
  );
}

/// Refuses, before downloading it, a file the index knows to be a folder or
/// too large.
void _refuseBeforeDownload(String id, IntradeskItem? known, int maxBytes) {
  if (known == null) return;
  if (known.kind == IntradeskItemKind.folder) {
    throw ToolError(
      '$id is the id of the Intradesk folder ${known.path}, not of a file: '
      'use list_intradesk_folder to see what is in it.',
    );
  }
  if (known.size case final size? when size > maxBytes) {
    throw ToolError(
      '${intradeskFileTitle(id, known, size: size)} is too large to save '
      'here: files up to ${formatFileSize(maxBytes)} can be saved. The '
      'teacher can download it in Smartschool.',
    );
  }
}
