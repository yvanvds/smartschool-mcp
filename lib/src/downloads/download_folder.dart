import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../settings.dart';
import '../tools/server_tool.dart';
import 'file_names.dart';

/// Where the path of a [DownloadFolder] came from, and how the teacher
/// chooses another folder; for `smartschool_status` and error messages.
final class DownloadFolderOrigin {
  const DownloadFolderOrigin(this.label, {required this.fix});

  /// Such as `set in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)` or `the
  /// default`.
  final String label;

  /// What the teacher does to use another folder, such as `choose another
  /// folder in "Downloadmap" (...) in the Smartschool extension settings
  /// ..., then restart Claude Desktop`.
  final String fix;
}

/// The folder on this PC that `save_intradesk_file` and
/// `save_message_attachment` save files into, so that Claude can open them
/// with its own file tools (in a Cowork project whose folder holds it) or
/// the teacher can.
///
/// A saved file never replaces another: a name that is taken gets ` (2)`,
/// ` (3)`, ... ([save]). The files are temporary: the folder holds a list of
/// the files the server saved there, [manifestName], and [cleanUp] deletes
/// those saved more than [retention] ago. It never touches another file in
/// the folder, nor a saved file that was changed since (that is the
/// teacher's now). A file is written under a temporary name
/// ([reservedFilePrefix]...`.part`) and gets its name only once complete.
///
/// Two server processes may share the folder; each keeps the list up to
/// date, and a save that the other process's write of the list misses is
/// only never cleaned up.
final class DownloadFolder {
  DownloadFolder(
    this.path, {
    required this.origin,
    this.retention = defaultRetention,
    this.cleanupInterval = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The folder for [source], with [environment] (this process's by
  /// default): [Setting.downloadDir]'s environment variable when it is set,
  /// else (with a credentials file) the file's `download_dir`, else
  /// [defaultPath]. Null only when there is no home folder to put the
  /// default in.
  ///
  /// The environment variable comes first, so a test or a developer can
  /// point a server started with `--credentials` elsewhere without
  /// changing the file.
  static DownloadFolder? resolve(
    CredentialSource source, {
    Map<String, String>? environment,
    DateTime Function()? clock,
  }) {
    final variables = environment ?? Platform.environment;
    const setting = Setting.downloadDir;
    final fix = switch (source) {
      ExtensionSettings() =>
        'choose another folder in ${source.name(setting)} ${source.where}, '
            'then ${source.restart}',
      CredentialsFile(:final path) =>
        'set ${setting.envVar}, or ${setting.fileKey} in the credentials '
            'file $path, to another folder, then ${source.restart}',
    };
    DownloadFolder folder(String path, String label) => DownloadFolder(
      Directory(path).absolute.path,
      origin: DownloadFolderOrigin(label, fix: fix),
      clock: clock,
    );

    if (_clean(variables[setting.envVar]) case final path?) {
      return folder(path, switch (source) {
        ExtensionSettings() => 'set in ${source.name(setting)}',
        CredentialsFile() => 'set in ${setting.envVar}',
      });
    }
    if (source case CredentialsFile(:final path)) {
      if (_clean(source.downloadDirectory()) case final directory?) {
        return folder(
          directory,
          'set in ${setting.fileKey} in the credentials file $path',
        );
      }
    }
    if (defaultPath(variables) case final path?) {
      return folder(path, 'the default');
    }
    log(
      'downloads: no download folder (${setting.envVar} is not set and '
      'there is no home folder)',
    );
    return null;
  }

  /// `%USERPROFILE%\Downloads\Smartschool` on Windows (`$HOME` when
  /// `USERPROFILE` is not set), `$HOME/Downloads/Smartschool` elsewhere;
  /// null without either.
  static String? defaultPath(Map<String, String> environment) {
    final homes = Platform.isWindows
        ? ['USERPROFILE', 'HOME']
        : ['HOME', 'USERPROFILE'];
    for (final name in homes) {
      if (_clean(environment[name]) case final home?) {
        return [home, 'Downloads', 'Smartschool'].join(Platform.pathSeparator);
      }
    }
    return null;
  }

  /// How long a saved file is kept.
  static const defaultRetention = Duration(days: 7);

  /// The list of the files the server saved, in the folder.
  static const manifestName = '${reservedFilePrefix}downloads.json';

  /// The version of [manifestName]'s contents; a list of another version is
  /// ignored.
  static const manifestFormat = 1;

  /// A temporary file left behind (by a server that was stopped while
  /// writing) is deleted once it is this old.
  static const staleTemporaryAge = Duration(hours: 24);

  /// The absolute path of the folder.
  final String path;
  final DownloadFolderOrigin origin;

  /// How long a saved file is kept before [cleanUp] deletes it.
  final Duration retention;

  /// How often [cleanUp] looks for files to delete.
  final Duration cleanupInterval;
  final DateTime Function() _clock;

  final _random = Random.secure();
  Future<void> _lastChange = Future<void>.value();
  Future<void>? _background;

  /// Completes when no cleanup started by [cleanUpInBackground] is running.
  Future<void> get idle => _background ?? Future<void>.value();

  /// Starts [cleanUp] and returns at once; for startup.
  void cleanUpInBackground() {
    _background ??= cleanUp().then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) =>
          log('downloads: cleanup failed: $error\n$stackTrace'),
    );
  }

  /// Whether the folder can be saved into, for `smartschool_status`. Never
  /// throws.
  ///
  /// Tries it: creates and deletes a temporary file in the folder, or in the
  /// nearest folder above it when it does not exist yet (it is created on
  /// the first save).
  Future<DownloadFolderState> check() async {
    try {
      switch (await FileSystemEntity.type(path)) {
        case FileSystemEntityType.directory:
          final problem = await _tryWriting(Directory(path));
          return problem == null
              ? const DownloadFolderState(writable: true)
              : DownloadFolderState(writable: false, problem: problem);
        case FileSystemEntityType.notFound:
          var above = Directory(path).parent;
          var type = await FileSystemEntity.type(above.path);
          while (type == FileSystemEntityType.notFound) {
            if (above.parent.path == above.path) {
              return const DownloadFolderState(
                writable: false,
                problem: 'neither it nor a folder above it exists',
              );
            }
            above = above.parent;
            type = await FileSystemEntity.type(above.path);
          }
          if (type != FileSystemEntityType.directory) {
            return DownloadFolderState(
              writable: false,
              exists: false,
              problem:
                  'it cannot be created: ${above.path} is a file, not a '
                  'folder',
            );
          }
          final problem = await _tryWriting(above);
          return DownloadFolderState(
            writable: problem == null,
            exists: false,
            problem: problem == null
                ? null
                : 'it does not exist and cannot be created in '
                      '${above.path} ($problem)',
          );
        default:
          return const DownloadFolderState(
            writable: false,
            problem: 'it is a file, not a folder',
          );
      }
    } on FileSystemException catch (error) {
      return DownloadFolderState(writable: false, problem: _reason(error));
    }
  }

  /// Saves a file into the folder and returns where.
  ///
  /// Creates the folder if needed and a temporary file in it, and calls
  /// [write] with that file: it writes the content and returns the name
  /// Smartschool gives the file (null when it gives none: then
  /// [fallbackName], which must be a safe name). The file then gets that
  /// name, made safe ([safeFileName]), with ` (2)`, ` (3)`, ... when it is
  /// taken, and is added to the list of saved files. Runs a [cleanUp] first
  /// when one is due.
  ///
  /// When [write] throws, the temporary file is deleted and the error
  /// passed on. A folder that cannot be created or written to is a
  /// [ToolError] that says how to choose another.
  Future<SavedFile> save(
    Future<String?> Function(File temporary) write, {
    required String fallbackName,
  }) async {
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (error) {
      throw ToolError(
        'The download folder $path cannot be created (${_reason(error)}). '
        'To save files, ${origin.fix}.',
      );
    }
    try {
      await cleanUp();
    } catch (error, stackTrace) {
      log('downloads: cleanup failed: $error\n$stackTrace');
    }
    final temporary = _temporaryFile();
    try {
      await temporary.create(exclusive: true);
    } on FileSystemException catch (error) {
      throw _cannotWrite(error);
    }

    final SavedFile saved;
    try {
      final safe = safeFileName(await write(temporary), fallback: fallbackName);
      // Downloads run side by side; naming them one at a time: on Windows,
      // looking at a name while another save renames a file onto it can
      // make that rename fail.
      saved = await _locked(() async {
        final file = await _claim(safe.name);
        try {
          // Onto the empty file that holds the name.
          await temporary.rename(file.path);
        } on FileSystemException {
          await _deleteQuietly(file);
          rethrow;
        }
        final stat = await file.stat();
        final files = await _readManifest();
        await _writeManifest([
          ...?files,
          _Saved(
            name: _name(file),
            savedAt: _clock(),
            size: stat.size,
            modified: stat.modified.microsecondsSinceEpoch,
          ),
        ]);
        return SavedFile(
          file.path,
          name: _name(file),
          size: stat.size,
          safeName: safe,
        );
      });
    } on FileSystemException catch (error) {
      await _deleteQuietly(temporary);
      throw _cannotWrite(error);
    } catch (_) {
      await _deleteQuietly(temporary);
      rethrow;
    }
    return saved;
  }

  /// Deletes the files the server saved more than [retention] ago, when the
  /// last cleanup (in this process or another, as the list of saved files
  /// says) was more than [cleanupInterval] ago, or with [force]; returns how
  /// many files it deleted.
  ///
  /// Only files on the list are deleted, and only when they are as the
  /// server saved them (same size, not changed since): a file the teacher
  /// changed or replaced is left alone and taken off the list, like one
  /// that is gone. A file that cannot be deleted now (open in a program)
  /// stays on the list. Temporary files of the server
  /// ([reservedFilePrefix]...`.part`) left behind for
  /// [staleTemporaryAge] are deleted too. Failing to read or write the
  /// list is only logged.
  Future<int> cleanUp({bool force = false}) => _locked(() async {
    final files = await _readManifest();
    final now = _clock();
    if (!force && _recentlyCleaned(now)) return 0;
    if (!await Directory(path).exists()) return 0;
    var removed = 0;
    final kept = <_Saved>[];
    for (final saved in files ?? const <_Saved>[]) {
      if (now.difference(saved.savedAt) < retention) {
        kept.add(saved);
        continue;
      }
      switch (await _deleteSaved(saved)) {
        case _Deletion.deleted:
          removed++;
        case _Deletion.failed:
          kept.add(saved);
        case _Deletion.notOurs:
          break;
      }
    }
    removed += await _deleteStaleTemporaries(now);
    _cleanedAt = now;
    // Without a list, nothing was saved here: no list is made either.
    if (files != null) await _writeManifest(kept);
    log(
      'downloads: cleanup deleted $removed '
      'file${removed == 1 ? '' : 's'}, ${kept.length} still listed',
    );
    return removed;
  });

  /// When the last cleanup ran, in this process or as the list says.
  DateTime? _cleanedAt;

  bool _recentlyCleaned(DateTime now) {
    final cleanedAt = _cleanedAt;
    if (cleanedAt == null) return false;
    final age = now.difference(cleanedAt);
    return !age.isNegative && age < cleanupInterval;
  }

  /// Runs [action] once the changes to the list started before it are done:
  /// one at a time in this process.
  Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _lastChange;
    final done = Completer<void>();
    _lastChange = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  File get _manifest => File(_join(manifestName));

  /// The files on the list, or null when there is no list. Also takes the
  /// time of the last cleanup from it, when that is later than the one this
  /// process knows. A list that cannot be read counts as empty.
  Future<List<_Saved>?> _readManifest() async {
    final manifest = _manifest;
    try {
      final json = jsonDecode(await manifest.readAsString());
      if (json case {
        'format': manifestFormat,
        'files': final List<Object?> files,
      }) {
        if (json['cleaned_at'] case final String time) {
          final cleanedAt = DateTime.tryParse(time);
          if (cleanedAt != null &&
              (_cleanedAt == null || cleanedAt.isAfter(_cleanedAt!))) {
            _cleanedAt = cleanedAt;
          }
        }
        return [for (final file in files) ?_Saved.fromJson(file)];
      }
      log('downloads: ignoring ${manifest.path} (other format)');
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      log('downloads: cannot read ${manifest.path}: ${error.message}');
    } on FormatException {
      log('downloads: ignoring ${manifest.path} (damaged)');
    }
    return const [];
  }

  /// Writes the list into a temporary file and renames it, so another
  /// server process never reads half a list.
  Future<void> _writeManifest(List<_Saved> files) async {
    final manifest = _manifest;
    final temporary = _temporaryFile();
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'format': manifestFormat,
          'about':
              'The files the Smartschool extension saved in this folder. It '
              'deletes them ${retention.inDays} days after saving them, '
              'unless they were changed since; it never touches other files.',
          'cleaned_at': _cleanedAt?.toUtc().toIso8601String(),
          'files': [for (final file in files) file.toJson()],
        }),
        flush: true,
      );
      await temporary.rename(manifest.path);
    } on FileSystemException catch (error) {
      log('downloads: cannot save ${manifest.path}: ${error.message}');
      await _deleteQuietly(temporary);
    }
  }

  /// Deletes [saved] if it is still the file the server saved.
  Future<_Deletion> _deleteSaved(_Saved saved) async {
    final file = File(_join(saved.name));
    try {
      final stat = await FileStat.stat(file.path);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          stat.size != saved.size ||
          stat.modified.microsecondsSinceEpoch != saved.modified) {
        log('downloads: a saved file is gone or was changed; left alone');
        return _Deletion.notOurs;
      }
      await file.delete();
      return _Deletion.deleted;
    } on FileSystemException catch (error) {
      log('downloads: cannot delete a saved file now: ${_reason(error)}');
      return _Deletion.failed;
    }
  }

  /// Deletes the server's temporary files older than [staleTemporaryAge].
  Future<int> _deleteStaleTemporaries(DateTime now) async {
    var deleted = 0;
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        if (entity is! File || !_temporaryName.hasMatch(_name(entity))) {
          continue;
        }
        try {
          final changed = (await entity.stat()).modified;
          if (now.difference(changed) < staleTemporaryAge) continue;
          await entity.delete();
          deleted++;
        } on FileSystemException {
          // Being written, or gone.
        }
      }
    } on FileSystemException catch (error) {
      log('downloads: cannot list $path: ${error.message}');
    }
    return deleted;
  }

  /// Creates an empty file named [name], or ` (2)`, ` (3)`, ... when that
  /// is taken, and returns it.
  Future<File> _claim(String name) async {
    for (var number = 1; number <= 9999; number++) {
      final file = File(
        _join(number == 1 ? name : numberedFileName(name, number)),
      );
      try {
        await file.create(exclusive: true);
        return file;
      } on FileSystemException {
        // Taken (by a file, or a folder: Windows then refuses access);
        // anything else fails again on the temporary file's rename.
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          rethrow;
        }
      }
    }
    throw FileSystemException('every numbered name is taken', _join(name));
  }

  /// Creates and deletes a temporary file in [directory]; returns why that
  /// failed, or null.
  Future<String?> _tryWriting(Directory directory) async {
    final probe = File(
      [directory.path, _newTemporaryName(_random)].join(Platform.pathSeparator),
    );
    try {
      await probe.create(exclusive: true);
      await probe.delete();
      return null;
    } on FileSystemException catch (error) {
      return _reason(error);
    }
  }

  ToolError _cannotWrite(FileSystemException error) => ToolError(
    'The file could not be saved in the download folder $path '
    '(${_reason(error)}). To save files, ${origin.fix}.',
  );

  File _temporaryFile() => File(_join(_newTemporaryName(_random)));

  String _join(String name) => [path, name].join(Platform.pathSeparator);

  static String _name(File file) => file.uri.pathSegments.last;

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Not created, or gone.
    }
  }
}

/// What [DownloadFolder.check] found.
final class DownloadFolderState {
  const DownloadFolderState({
    required this.writable,
    this.exists = true,
    this.problem,
  });

  /// Whether files can be saved in it (created first when it does not
  /// exist).
  final bool writable;

  /// False when it does not exist yet; the first save creates it.
  final bool exists;

  /// Why it cannot be used, when not [writable].
  final String? problem;
}

/// A file [DownloadFolder.save] saved.
final class SavedFile {
  const SavedFile(
    this.path, {
    required this.name,
    required this.size,
    required this.safeName,
  });

  /// The full path of the file.
  final String path;

  /// Its name in the folder.
  final String name;

  /// Its size in bytes.
  final int size;

  /// The name it was meant to get, before a number was added.
  final SafeFileName safeName;

  /// What the teacher should know about the name: that Smartschool gave
  /// none, that it was changed, or that it was taken. Empty when the file
  /// has the name Smartschool gives it.
  List<String> get notes => [
    if (safeName.given == null)
      'Smartschool gave no file name, so it was saved as "${safeName.name}".'
    else if (safeName.changes.isNotEmpty)
      'The file name Smartschool gives, "${safeName.given!.trim()}", cannot '
          'be used as it is (${safeName.changes.join('; ')}), so it was '
          'saved as "${safeName.name}".',
    if (name != safeName.name)
      'A file named "${safeName.name}" was already in the download folder, '
          'so this one was saved as "$name"; the other file was not changed.',
  ];
}

/// A file on the list of saved files.
final class _Saved {
  const _Saved({
    required this.name,
    required this.savedAt,
    required this.size,
    required this.modified,
  });

  /// An entry of the list, or null when it is not one; a name that is not
  /// a plain file name (a path) never is, so nothing outside the folder is
  /// ever deleted.
  static _Saved? fromJson(Object? json) {
    if (json case {
      'name': final String name,
      'saved_at': final String savedAt,
      'size': final int size,
      'modified': final int modified,
    } when _isPlainName(name)) {
      if (DateTime.tryParse(savedAt) case final time?) {
        return _Saved(
          name: name,
          savedAt: time,
          size: size,
          modified: modified,
        );
      }
    }
    return null;
  }

  final String name;
  final DateTime savedAt;
  final int size;

  /// When it was last changed, in microseconds since the epoch.
  final int modified;

  Map<String, Object?> toJson() => {
    'name': name,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'size': size,
    'modified': modified,
  };

  static bool _isPlainName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains(RegExp(r'[/\\:]'));
}

enum _Deletion { deleted, failed, notOurs }

/// The names of the server's temporary files.
final _temporaryName = RegExp(
  '^${RegExp.escape(reservedFilePrefix)}[0-9a-f]{16}\\.part\$',
);

/// A new name for a temporary file: [reservedFilePrefix], 16 random hex
/// digits, `.part`.
String _newTemporaryName(Random random) {
  final digits = [
    for (var i = 0; i < 8; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  return '$reservedFilePrefix$digits.part';
}

/// [value] trimmed and without quotes around it, or null when empty.
String? _clean(String? value) {
  var text = value?.trim() ?? '';
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1).trim();
  }
  return text.isEmpty ? null : text;
}

/// Why [error] happened, from the operating system when it says.
String _reason(FileSystemException error) {
  final os = error.osError?.message.trim();
  return os == null || os.isEmpty ? error.message : os;
}

/// Writes [download]'s content into [file], replacing what is in it.
///
/// Completes with the download's error when its stream ends with one (it is
/// too large, or the connection failed), and the library then stops the
/// transfer; or with a [FileSystemException] when the file cannot be
/// written, and the transfer is stopped too.
Future<void> writeDownload(SmartschoolDownload download, File file) =>
    download.stream.pipe(file.openWrite());
