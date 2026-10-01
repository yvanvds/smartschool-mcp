import 'dart:convert';
import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';

/// The plain text of messages (from `htmlToText`), kept on disk so a message
/// is downloaded once and later searches read it from here.
///
/// A Smartschool message does not change once sent, so a saved text never
/// goes stale. Each message is a small JSON file, `<box>-<id>.json`, where
/// `<box>` is the [BoxType]'s value: `inbox` (also for the archive, a folder
/// of the inbox, so a text saved before a message was archived is still
/// found) or `outbox` for the sent box.
///
/// The texts are personal: the cache lives in the user's own profile folder
/// (see [MessageTextCache.of]), and the log never shows a text.
///
/// Failing to read or write the cache is never an error for the caller: a
/// text that cannot be read counts as not saved and is downloaded again.
final class MessageTextCache {
  /// A cache in [directory], created on the first write.
  MessageTextCache(Directory directory) : _resolve = (() => directory);

  /// The cache of the user [session] logs in as: the folder
  /// `messages/<host>` in the user's cache folder
  /// ([SmartschoolSession.cacheDirectory]), next to the library's session
  /// cookies. The host keeps the message ids of two schools apart.
  ///
  /// The folder is worked out on first use: use the cache only once the
  /// session has logged in.
  MessageTextCache.of(SmartschoolSession session)
    : _resolve = (() => directoryFor(session));

  /// The folder [MessageTextCache.of] uses for [session].
  static Directory directoryFor(SmartschoolSession session) => Directory(
    [
      session.cacheDirectory,
      'messages',
      session.settings.host,
    ].join(Platform.pathSeparator),
  );

  /// The version of the file contents. Files of another version are ignored
  /// (and overwritten): raise it when the saved text changes, for example
  /// when `htmlToText` writes something else for the same message.
  static const format = 1;

  final Directory Function() _resolve;
  Directory? _directory;
  int _writes = 0;

  /// The folder the texts are saved in.
  Directory get directory {
    if (_directory case final directory?) return directory;
    final directory = _directory = _resolve();
    log('message text cache: ${directory.path}');
    return directory;
  }

  File _file(BoxType boxType, int id) => File(
    '${directory.path}${Platform.pathSeparator}${boxType.value}-$id.json',
  );

  /// The saved text of message [id] in [boxType], or null when it is not
  /// saved (or cannot be read).
  Future<String?> read(BoxType boxType, int id) async {
    final file = _file(boxType, id);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json case {
        'format': format,
        'id': final int savedId,
        'text': final String text,
      } when savedId == id) {
        return text;
      }
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      log('message text cache: cannot read ${file.path}: ${error.message}');
    } on FormatException {
      log('message text cache: ${file.path} is damaged, downloading again');
    }
    return null;
  }

  /// Saves [text] as the text of message [id] in [boxType].
  ///
  /// Writes a temporary file and renames it, so a crash or a second server
  /// process never leaves a half-written file under the real name.
  Future<void> write(BoxType boxType, int id, String text) async {
    final file = _file(boxType, id);
    final temporary = File('${file.path}.$pid-${_writes++}.tmp');
    try {
      await directory.create(recursive: true);
      await temporary.writeAsString(
        jsonEncode({'format': format, 'id': id, 'text': text}),
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      log('message text cache: cannot save ${file.path}: ${error.message}');
      try {
        await temporary.delete();
      } on FileSystemException {
        // It was not created.
      }
    }
  }
}
