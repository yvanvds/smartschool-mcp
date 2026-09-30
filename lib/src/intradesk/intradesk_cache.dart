import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log.dart';
import '../session.dart';
import '../settings.dart';
import 'intradesk_index.dart';
import 'intradesk_walk.dart';

/// Where an index came from.
enum IntradeskIndexSource {
  /// Kept in memory since an earlier call in this process.
  memory,

  /// Read from the saved index file.
  disk,

  /// Built just now by walking Intradesk.
  walk,
}

/// Builds a new index, keeping [progress] up to date; see
/// `buildIntradeskIndex`.
typedef IntradeskIndexBuilder =
    Future<IntradeskIndex> Function(IntradeskWalkProgress progress);

/// What [IntradeskIndexCache.load] found.
final class IntradeskIndexLookup {
  const IntradeskIndexLookup(this.index, this.source, {this.building});

  /// The index to search: the newest there is, which is older than
  /// [IntradeskIndexCache.maxAge] only while [building] a new one. Null when
  /// there is none yet.
  final IntradeskIndex? index;

  /// Where [index] came from; null without one.
  final IntradeskIndexSource? source;

  /// The walk building a new index, while one runs (this lookup did not
  /// wait for it, or not long enough).
  final IntradeskWalkProgress? building;
}

/// The Intradesk index (see [IntradeskIndex]), kept in memory and on disk
/// for [maxAge], so that only the first search of the day walks the tree.
///
/// Walking a large Intradesk takes minutes (about 3 for 5900 folders, seen
/// live), longer than a client waits for a tool call. So the walk runs on its own: [load]
/// waits for it at most [buildWait], and meanwhile answers with the old
/// index when there is one, or with how far the walk is. A later [load]
/// finds the new index once the walk is done.
///
/// On disk it is one JSON file, `index.json`, in the user's own cache folder
/// (see [IntradeskIndexCache.of]). It holds the names and paths of the
/// folders and files the user can see on Intradesk; the log never shows
/// them.
///
/// Failing to read or write the file is never an error for the caller: an
/// index that cannot be read counts as not saved and is built again.
final class IntradeskIndexCache {
  /// A cache in [directory], created on the first write. [now] tells the
  /// time, for tests.
  IntradeskIndexCache(
    Directory directory, {
    this.maxAge = defaultMaxAge,
    this.buildWait = defaultBuildWait,
    DateTime Function()? now,
  }) : _resolve = (() => directory),
       _now = now ?? DateTime.now;

  /// The cache of the user [session] logs in as: the folder
  /// `intradesk/<host>` in the user's cache folder
  /// ([SmartschoolSettings.cacheDirectory]), next to the library's session
  /// cookies.
  ///
  /// The folder is worked out on first use, from the settings: use the cache
  /// only once the session has logged in.
  IntradeskIndexCache.of(
    SmartschoolSession session, {
    this.maxAge = defaultMaxAge,
    this.buildWait = defaultBuildWait,
    DateTime Function()? now,
  }) : _resolve = (() => directoryFor(session.settings)),
       _now = now ?? DateTime.now;

  /// The folder [IntradeskIndexCache.of] uses for [settings].
  static Directory directoryFor(SmartschoolSettings settings) => Directory(
    [
      settings.cacheDirectory,
      'intradesk',
      settings.host,
    ].join(Platform.pathSeparator),
  );

  /// How long an index is used before it is built again.
  static const defaultMaxAge = Duration(hours: 24);

  /// How long [load] waits for a walk: within the 60 seconds after which
  /// MCP clients such as Claude Desktop usually give up on a tool call.
  static const defaultBuildWait = Duration(seconds: 40);

  final Duration maxAge;
  final Duration buildWait;
  final Directory Function() _resolve;
  final DateTime Function() _now;
  Directory? _directory;
  IntradeskIndex? _index;
  Future<IntradeskIndex>? _building;
  IntradeskWalkProgress? _progress;
  int _writes = 0;

  /// The folder the index is saved in.
  Directory get directory {
    if (_directory case final directory?) return directory;
    final directory = _directory = _resolve();
    log('intradesk index cache: ${directory.path}');
    return directory;
  }

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}index.json');

  bool _fresh(IntradeskIndex index) {
    final age = _now().difference(index.builtAt);
    return !age.isNegative && age < maxAge;
  }

  /// The index to search.
  ///
  /// The one in memory or on disk when it is younger than [maxAge]. Else (or
  /// with [refresh]) a new one from [build], which is saved: when an old
  /// index exists and [refresh] is not set, that one is returned right away
  /// while [build] runs; otherwise [load] waits for [build] at most
  /// [buildWait], and then returns the old index or none, with the walk's
  /// progress. While a walk runs, every lookup that does not wait for it
  /// carries its progress, also one with a fresh index (a refresh is
  /// running).
  ///
  /// [build] runs once at a time: calls while it runs share it. An error
  /// from [build] is thrown to the calls waiting for it; when none is, it is
  /// logged, and the next call builds again.
  Future<IntradeskIndexLookup> load(
    IntradeskIndexBuilder build, {
    bool refresh = false,
  }) async {
    final saved = await _saved();
    if (saved != null && !refresh && _fresh(saved.index)) {
      return IntradeskIndexLookup(
        saved.index,
        saved.source,
        building: _progress,
      );
    }
    final building = _build(build);
    final progress = _progress;
    if (saved != null && !refresh) {
      return IntradeskIndexLookup(
        saved.index,
        saved.source,
        building: progress,
      );
    }
    try {
      return IntradeskIndexLookup(
        await building.timeout(buildWait),
        IntradeskIndexSource.walk,
      );
    } on TimeoutException {
      return IntradeskIndexLookup(
        saved?.index,
        saved?.source,
        building: progress,
      );
    }
  }

  /// Completes when the running walk, if any, is done and its index saved
  /// (also when it failed).
  Future<void> get walkDone async {
    try {
      await _building;
    } catch (_) {
      // Logged by [_build].
    }
  }

  /// The newest index in memory or on disk, whatever its age, without
  /// building one; null when there is none.
  Future<IntradeskIndex?> saved() async => (await _saved())?.index;

  /// The index in memory when it is fresh; else the newer of the ones in
  /// memory and on disk; null when there is neither.
  Future<({IntradeskIndex index, IntradeskIndexSource source})?>
  _saved() async {
    final memory = _index;
    if (memory != null && _fresh(memory)) {
      return (index: memory, source: IntradeskIndexSource.memory);
    }
    // Another server process may have saved a newer one.
    final disk = await read();
    if (disk != null &&
        (memory == null || disk.builtAt.isAfter(memory.builtAt))) {
      _index = disk;
      return (index: disk, source: IntradeskIndexSource.disk);
    }
    return memory == null
        ? null
        : (index: memory, source: IntradeskIndexSource.memory);
  }

  /// The running walk, or a new one.
  Future<IntradeskIndex> _build(IntradeskIndexBuilder build) {
    if (_building case final running?) return running;
    final progress = _progress = IntradeskWalkProgress();
    final running = _building = () async {
      final index = await build(progress);
      _index = index;
      await write(index);
      return index;
    }().whenComplete(() => _building = _progress = null);
    // Nobody may wait for it: the caller got the old index or stopped
    // waiting.
    unawaited(
      running.then<void>(
        (_) {},
        onError: (Object error) =>
            log('intradesk index: the walk failed (${error.runtimeType})'),
      ),
    );
    return running;
  }

  /// The saved index, or null when there is none (or it cannot be read).
  Future<IntradeskIndex?> read() async {
    final file = _file;
    try {
      return IntradeskIndex.fromJson(jsonDecode(await file.readAsString()));
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (error) {
      log('intradesk index cache: cannot read ${file.path}: ${error.message}');
    } on FormatException {
      log('intradesk index cache: ${file.path} is damaged or old, ignored');
    }
    return null;
  }

  /// Saves [index].
  ///
  /// Writes a temporary file and renames it, so a crash or a second server
  /// process never leaves a half-written file under the real name.
  Future<void> write(IntradeskIndex index) async {
    final file = _file;
    final temporary = File('${file.path}.$pid-${_writes++}.tmp');
    try {
      await directory.create(recursive: true);
      await temporary.writeAsString(jsonEncode(index.toJson()), flush: true);
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      log('intradesk index cache: cannot save ${file.path}: ${error.message}');
      try {
        await temporary.delete();
      } on FileSystemException {
        // It was not created.
      }
    }
  }
}
