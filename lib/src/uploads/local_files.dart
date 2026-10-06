import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../tools/server_tool.dart';

// Files on the user's computer that a tool sends to Smartschool: shared by
// the tools that upload (`upload_intradesk_files`, and the attachments of a
// lesfiche or a message). They take absolute paths ([localFilesArgument],
// [checkLocalFiles]), describe the files in their result ([LocalFile],
// [describeLocalFiles]), and report a file that the library or Smartschool
// refused ([uploadToolError]).
//
// The server reads any file the user's Windows account can read: the tools'
// descriptions say to show the user every file, with its name and size,
// before calling them.

/// Files larger than this are not sent: a sanity limit, as high as what
/// `save_intradesk_file` saves. The library reads a file into memory to
/// upload it.
const maxLocalFileBytes = 200 * 1024 * 1024;

/// The most files one call of a tool sends.
const maxLocalFiles = 10;

/// What a tool adds to an error about its files: it came before anything
/// was sent.
const nothingSent = 'Nothing was sent.';

/// A file on the user's computer, checked by [checkLocalFiles], that a tool
/// is about to send to Smartschool.
final class LocalFile {
  const LocalFile({required this.path, required this.name, required this.size});

  /// The absolute path, as the tool was given it (without white space
  /// around it).
  final String path;

  /// The name Smartschool gets: the last part of [path] ([localFileName]).
  final String name;

  /// The size in bytes when it was checked.
  final int size;

  /// `"toets 1.pdf" (12 KB)`.
  String get description => '"$name" (${formatFileSize(size)})';

  @override
  String toString() => description;
}

/// The name the library uploads the file at [path] under: the last part of
/// its path, read from its `file:` URI (`toets #1.pdf` for
/// `C:\Users\jan\toets #1.pdf`), as the library's services take it.
String localFileName(String path) => File(path).uri.pathSegments.last;

/// [value], the argument [argument] of a tool: a list of 1 to [maxCount]
/// absolute paths of files on this PC, checked with [checkLocalFiles].
///
/// Throws a [ToolError] that says what is wrong, before anything is sent.
List<LocalFile> localFilesArgument(
  Object? value, {
  required String argument,
  int maxCount = maxLocalFiles,
  int maxBytes = maxLocalFileBytes,
}) {
  final items = value is List ? value : [?value];
  final paths = <String>[];
  for (final item in items) {
    final path = item is String ? item.trim() : '';
    if (path.isEmpty) {
      throw ToolError(
        'each item of $argument must be the full path of a file on this PC, '
        'like C:\\Users\\jan\\Documents\\brief.docx; '
        '${item is String ? '"$item"' : '$item'} is not. $nothingSent',
      );
    }
    paths.add(path);
  }
  return checkLocalFiles(
    paths,
    argument: argument,
    maxCount: maxCount,
    maxBytes: maxBytes,
  );
}

/// The files at [paths], the argument [argument] of a tool, as they are now:
/// 1 to [maxCount] of them, each the absolute path of an existing file (not
/// a folder) of at most [maxBytes], with a name Smartschool takes
/// ([IntradeskService.isAllowedName]: Smartschool's upload step refuses any
/// other), and no two with the same name, ignoring case (Smartschool stores
/// a file under its name).
///
/// Throws a [ToolError] that names the path and says what is wrong, before
/// anything is sent.
List<LocalFile> checkLocalFiles(
  List<String> paths, {
  required String argument,
  int maxCount = maxLocalFiles,
  int maxBytes = maxLocalFileBytes,
}) {
  if (paths.isEmpty) {
    throw ToolError(
      '$argument is empty: give 1 to $maxCount full paths of files on this '
      'PC, like C:\\Users\\jan\\Documents\\brief.docx. $nothingSent',
    );
  }
  if (paths.length > maxCount) {
    throw ToolError(
      '$argument holds ${paths.length} files; at most $maxCount go in one '
      'call. $nothingSent',
    );
  }
  final files = <LocalFile>[];
  for (final path in paths) {
    if (!File(path).isAbsolute) {
      throw ToolError(
        '"$path" in $argument is not a full path: give the whole path of the '
        'file, starting with the drive, like '
        'C:\\Users\\jan\\Documents\\brief.docx. $nothingSent',
      );
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      throw ToolError(
        '"$path" in $argument is a folder, not a file: give the paths of the '
        'files in it. $nothingSent',
      );
    }
    if (type != FileSystemEntityType.file) {
      throw ToolError(
        'There is no file "$path" on this PC (any more): check the path. '
        '$nothingSent',
      );
    }
    final name = localFileName(path);
    if (!IntradeskService.isAllowedName(name)) {
      throw ToolError(
        'Smartschool does not take a file named "$name" ($path): no / : * ? '
        '" \\ < > |, and no dot at the start or end of the name or of the '
        'part before the extension. Rename the file first. $nothingSent',
      );
    }
    final int size;
    try {
      size = File(path).lengthSync();
    } on FileSystemException catch (error) {
      throw ToolError(
        'The file "$path" cannot be read: '
        '${error.osError?.message ?? error.message}. $nothingSent',
      );
    }
    if (size > maxBytes) {
      throw ToolError(
        'The file "$name" ($path) is ${formatFileSize(size)}, too large to '
        'send from here: files up to ${formatFileSize(maxBytes)} can be '
        'sent. The user can add it in Smartschool. $nothingSent',
      );
    }
    final same = files
        .where((file) => file.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (same != null) {
      throw ToolError(
        '$argument holds two files named "$name" (${same.path} and $path), '
        'which Smartschool would store under the same name: send one of '
        'them, or rename one first. $nothingSent',
      );
    }
    files.add(LocalFile(path: path, name: name, size: size));
  }
  return files;
}

/// [files] in a few words: `"brief.docx" (12 KB)`, `"a.pdf" (1 KB) and "b.pdf"
/// (2.0 MB)`.
String describeLocalFiles(Iterable<LocalFile> files) {
  final described = [for (final file in files) file.description];
  return described.length < 2
      ? described.join()
      : '${described.sublist(0, described.length - 1).join(', ')} and '
            '${described.last}';
}

/// The [ToolError] for [error], when it is about the [files] a tool sends,
/// or null for anything else:
///
/// - [SmartschoolAttachmentUploadError]: Smartschool's upload step did not
///   take a file ([SmartschoolAttachmentUploadError.fileName], with
///   Smartschool's own words when it gave them,
///   [SmartschoolAttachmentUploadError.serverMessage]), or gave no upload
///   directory. The library's message names the file, so it is not logged.
/// - An [ArgumentError] whose value is the path of one of [files]: the
///   library refused the file before sending anything (it no longer
///   exists, or Smartschool does not allow its name).
///
/// Both come before the module (Intradesk, Lesfiches, Messages) was told to
/// take the files: [nothingDone] says what that means for the call, like
/// `Nothing was added to Intradesk.`
ToolError? uploadToolError(
  Object error, {
  required Iterable<LocalFile> files,
  required String nothingDone,
}) {
  switch (error) {
    case SmartschoolAttachmentUploadError(
      :final fileName,
      :final statusCode,
      :final serverMessage,
    ):
      // Without the library's message, which names the file: the log never
      // shows a name or a path.
      log(
        'upload: the upload step failed (HTTP ${statusCode ?? '-'}, '
        '${serverMessage == null ? 'without' : 'with'} Smartschool\'s reason)',
      );
      final status = statusCode == null ? '' : ' (HTTP $statusCode)';
      final String what;
      if (fileName != null && serverMessage != null) {
        what =
            'Smartschool refused the file "$fileName"$status: '
            '"$serverMessage" Rename the file, or leave it out.';
      } else if (fileName != null) {
        what =
            'Smartschool did not take the file "$fileName"$status. Try again '
            'in a moment.';
      } else if (statusCode != null) {
        what =
            'Smartschool gave no upload directory$status, so no file was '
            'uploaded. Try again in a moment.';
      } else {
        what =
            'A file could not be uploaded: it was not found any more. Check '
            'the paths.';
      }
      return ToolError('$what $nothingDone');
    case ArgumentError(:final invalidValue, :final message)
        when error is! RangeError:
      final file = files.where((file) => file.path == invalidValue).firstOrNull;
      if (file == null) return null;
      log('upload: the library refused a file before sending it');
      return ToolError(
        'The file "${file.name}" (${file.path}) was refused before anything '
        'was sent: it $message. $nothingDone',
      );
  }
  return null;
}
