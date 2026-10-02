import 'dart:async';
import 'dart:collection';

import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../problems.dart';
import 'intradesk_access.dart';
import 'intradesk_index.dart';

/// How many folder listings [buildIntradeskIndex] requests at the same time,
/// to be gentle on Smartschool.
///
/// Seen live: a listing takes about 100 ms, so a walk of an Intradesk of
/// about 5900 folders and 22000 files took just under 3 minutes.
const intradeskWalkConcurrency = 4;

/// The most folders [buildIntradeskIndex] lists; the rest is left out of the
/// index, and the index says how many were skipped.
const maxIntradeskFolders = 20000;

/// How far a walk by [buildIntradeskIndex] is.
final class IntradeskWalkProgress {
  final Stopwatch _stopwatch = Stopwatch();

  /// The folders listed so far, the root included.
  int listed = 0;

  /// The folders found but not listed yet.
  int waiting = 0;

  /// The folders, files and weblinks found so far.
  int found = 0;

  /// How long the walk has been running.
  Duration get elapsed => _stopwatch.elapsed;

  void _start() {
    listed = waiting = found = 0;
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  String toString() =>
      '$listed folders listed, $waiting waiting, $found names found, '
      '${elapsed.inSeconds} s';
}

/// Walks the whole Intradesk tree breadth-first, listing at most
/// [concurrency] folders at a time and at most [maxFolders] in all, and
/// returns the index of everything found.
///
/// Every folder is listed: a folder's `hasChildren` only tells whether it
/// holds folders, not files (seen live).
///
/// A folder whose listing fails for another reason than a login or
/// connection problem or a disposed client (Smartschool answers some with a
/// 500) is counted in [IntradeskIndex.unlisted] and the walk goes on without
/// its contents. A login or connection problem, or the
/// [SmartschoolClientDisposedError] of a client disposed during the walk
/// (the server shuts down), stops the walk and is rethrown once the
/// listings in progress are done. A listing that finds the session expired
/// does not stop it: the library logs in again and retries the listing. Only
/// a session that Smartschool still refuses does, and then
/// `SmartschoolSession.run` walks once more.
///
/// Keeps [progress] up to date and logs it every [progressInterval]: counts
/// only, never names.
Future<IntradeskIndex> buildIntradeskIndex(
  IntradeskService intradesk, {
  IntradeskWalkProgress? progress,
  int concurrency = intradeskWalkConcurrency,
  int maxFolders = maxIntradeskFolders,
  Duration progressInterval = const Duration(seconds: 10),
}) async {
  final state = (progress ?? IntradeskWalkProgress()).._start();
  final items = <IntradeskItem>[];
  final queue = Queue<IntradeskItem?>()..add(null); // null: the root
  var unlisted = 0;
  var active = 0;
  Object? failure;
  StackTrace? failureTrace;
  final done = Completer<void>();

  Future<void> list(IntradeskItem? folder) async {
    final IntradeskListing listing;
    try {
      listing = folder == null
          ? await intradesk.getRootListing()
          : await intradesk.getFolderListing(folder.id);
    } catch (error) {
      // The root must work; for another folder only a login or connection
      // problem stops the walk, or the client being disposed (the server
      // shuts down; yvanvds/dartschool#73).
      if (folder == null ||
          error is SmartschoolClientDisposedError ||
          classifyFailure(error) != null) {
        rethrow;
      }
      unlisted++;
      log('intradesk index: a folder could not be listed (${_kind(error)})');
      return;
    }
    final found = intradeskItems(
      listing,
      folderId: folder?.id ?? '',
      path: folder?.path ?? '',
    );
    items.addAll(found);
    queue.addAll(found.where((item) => item.kind == IntradeskItemKind.folder));
    state
      ..found = items.length
      ..waiting = queue.length;
  }

  void pump() {
    while (failure == null &&
        active < concurrency &&
        queue.isNotEmpty &&
        state.listed < maxFolders) {
      final folder = queue.removeFirst();
      state
        ..listed += 1
        ..waiting = queue.length;
      active++;
      list(folder)
          .catchError((Object error, StackTrace stackTrace) {
            failure ??= error;
            failureTrace ??= stackTrace;
          })
          .whenComplete(() {
            active--;
            pump();
            if (active > 0 || done.isCompleted) return;
            if (failure case final error?) {
              done.completeError(error, failureTrace);
            } else {
              done.complete();
            }
          });
    }
  }

  final ticker = Timer.periodic(
    progressInterval,
    (_) => log('intradesk index: $state'),
  );
  try {
    pump();
    await done.future;
  } finally {
    ticker.cancel();
  }

  final index = IntradeskIndex(
    builtAt: DateTime.now(),
    items: items,
    unlisted: unlisted,
    skipped: queue.length,
    walkTime: state.elapsed,
  );
  log(
    'intradesk index: built in ${state.elapsed.inMilliseconds} ms: '
    '${state.listed} folders listed, '
    '${index.count(IntradeskItemKind.folder)} folders, '
    '${index.count(IntradeskItemKind.file)} files, '
    '${index.count(IntradeskItemKind.weblink)} weblinks, $unlisted failed, '
    '${index.skipped} skipped (limit $maxFolders)',
  );
  return index;
}

/// The kind of [error], without its message (which may quote a path or a
/// response).
String _kind(Object error) => switch (error) {
  SmartschoolDownloadError(:final statusCode) =>
    '${error.runtimeType}, status $statusCode',
  _ => '${error.runtimeType}',
};
