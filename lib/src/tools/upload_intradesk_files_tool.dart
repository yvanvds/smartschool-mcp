import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_access.dart';
import '../intradesk/intradesk_cache.dart';
import '../intradesk/intradesk_format.dart';
import '../intradesk/intradesk_index.dart';
import '../intradesk/intradesk_writes.dart';
import '../log.dart';
import '../session.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

/// `upload_intradesk_files`: uploads files from this PC to a folder on
/// Intradesk, each under its own name, with the library's
/// `IntradeskService.uploadFiles` (yvanvds/dartschool#128).
///
/// The files are checked first ([localFilesArgument]: absolute paths of
/// existing files, at most [maxBytes] each, no two with the same name), and
/// the folder is read and checked as for `create_intradesk_folder`: a file
/// whose name the folder holds already is refused, as is a folder the
/// account may not add to. The library asks for a new upload directory for
/// every call and has Intradesk take it once; a take that Intradesk does not
/// confirm is reported as maybe done ([intradeskWriteNotConfirmed]). The
/// files Intradesk added go into the index in [cache], when one is loaded.
ServerTool uploadIntradeskFilesTool(
  SmartschoolSession session,
  IntradeskIndexCache cache, {
  int maxBytes = maxLocalFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'upload_intradesk_files',
    title: 'Upload files to Intradesk',
    description:
        'Uploads 1 to $maxLocalFiles files from this PC to a folder on '
        'Intradesk, the school\'s shared document store in Smartschool, each '
        'under its own file name. Everyone who can see the folder sees the '
        'files. Give the id of the folder, from search_intradesk or '
        'list_intradesk_folder (the top of Intradesk is not offered), and '
        'the full paths of the files, like '
        'C:\\Users\\jan\\Documents\\brief.docx: files you made for the user '
        '(for example in a Cowork project folder) or that the user names. '
        'The server reads any file the user\'s Windows account can read, up '
        'to ${formatFileSize(maxBytes)} each. Before calling this tool, show '
        'the user every file with its name and size and where it goes (the '
        'folder\'s path, as search_intradesk shows it), and only call this '
        'tool after the user has explicitly confirmed it. The tool refuses a '
        'file whose name a folder, file or weblink in the folder has already '
        '(Intradesk would not refuse it, but add the new file as '
        '"name (1).ext"; a new version of a file on Intradesk is not '
        'offered), two files with the same name, and a folder the user may '
        'not add to. If the result says the files may or may not have been '
        'uploaded, do not call this tool again for them: list the folder '
        'with list_intradesk_folder and tell the user.',
    inputSchema: Schema.object(
      properties: {
        'folder_id': Schema.string(
          description:
              'The id of the folder to upload to, from search_intradesk or '
              'list_intradesk_folder.',
          minLength: 1,
        ),
        'paths': Schema.list(
          description:
              'The full paths of the files on this PC, like '
              'C:\\Users\\jan\\Documents\\brief.docx. Each file goes in under '
              'its own name.',
          items: Schema.string(minLength: 1),
          minItems: 1,
          maxItems: maxLocalFiles,
        ),
      },
      required: ['folder_id', 'paths'],
    ),
    annotations: ToolAnnotations(
      title: 'Upload files to Intradesk',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) =>
      _upload(session, cache, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _upload(
  SmartschoolSession session,
  IntradeskIndexCache cache,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final folderId = intradeskFolderArgument(arguments);
  final files = localFilesArgument(
    arguments['paths'],
    argument: 'paths',
    maxBytes: maxBytes,
  );
  final names = [for (final file in files) file.name];

  IntradeskParent? parent;
  String where() => parent?.title ?? intradeskFolderTitle(folderId, null);
  String what() =>
      '${files.length == 1 ? 'the file' : 'the files'} '
      '${describeLocalFiles(files)} for the ${where()}';
  final watch = Stopwatch()..start();
  try {
    final result = await withIntradeskWrite(
      session,
      (intradesk) async {
        final read = parent = await readIntradeskParent(
          intradesk,
          cache,
          folderId,
        );
        read.refuseWithoutAdd();
        read.refuseTakenNames(
          names,
          what: files.length == 1 ? 'the file' : 'some of the files',
        );
        return intradesk.uploadFiles(
          parentFolderId: folderId,
          filePaths: [for (final file in files) file.path],
        );
      },
      what: what,
      files: files,
    );
    final made = intradeskItems(
      IntradeskListing(
        folders: const [],
        files: result.files,
        weblinks: const [],
      ),
      folderId: folderId,
      path: parent!.path ?? '',
    );
    final index = made.isEmpty
        ? 'nothing made'
        : await addToIntradeskIndex(cache, parent!, made);
    log(
      'upload_intradesk_files: ${files.length} sent, ${made.length} made, '
      '${result.failures.length} failed in ${watch.elapsedMilliseconds} ms '
      '($index)',
    );
    return _result(names, made, result.failures, parent!);
  } on SmartschoolIntradeskSaveUnconfirmedError catch (error) {
    return intradeskWriteNotConfirmed(
      tool: 'upload_intradesk_files',
      what: what(),
      folderId: folderId,
      error: error,
    );
  }
}

/// The result of an upload of the files [names] to [parent]: the files
/// Intradesk added ([made]) and those it did not take ([failures]).
CallToolResult _result(
  List<String> names,
  List<IntradeskItem> made,
  List<IntradeskUploadFailure> failures,
  IntradeskParent parent,
) {
  final count = '${made.length} file${made.length == 1 ? '' : 's'}';
  final renamed = [
    for (final item in made)
      if (!names.contains(item.name)) '"${item.name}"',
  ];
  final lines = [
    if (made.isNotEmpty)
      'Uploaded $count to the ${parent.title}.'
    else if (failures.isNotEmpty)
      'Intradesk took none of the files for the ${parent.title}.'
    else
      'Intradesk answered the upload to the ${parent.title} without naming '
          'a file it added. Do not call upload_intradesk_files again for '
          'them: list the folder with list_intradesk_folder (folder_id '
          '${parent.id}) to see whether they are there, and tell the user.',
    for (final item in made)
      '- ${formatIntradeskItem(item, fullPath: parent.path != null)}',
    if (renamed.isNotEmpty)
      'Note: Intradesk stored ${renamed.join(', ')} under another name than '
          'any file sent: it renames a new file whose name is taken in the '
          'folder, so a file of that name was probably added there '
          'meanwhile. Tell the user.',
    if (failures.isNotEmpty) ...[
      'Intradesk did not take ${failures.length} '
          'file${failures.length == 1 ? '' : 's'}, which '
          '${failures.length == 1 ? 'was' : 'were'} not added:',
      for (final failure in failures)
        '- ${failure.key}: '
            '${failure.message.isEmpty ? 'no reason given' : '"${failure.message}"'}',
    ],
  ];
  return CallToolResult(
    isError: made.isEmpty ? true : null,
    content: [TextContent(text: lines.join('\n'))],
  );
}
