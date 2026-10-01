import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// The answer to a file download as Smartschool sends it: [content] in
/// chunks of 64 KB, each in its own turn of the event loop like data
/// arriving from a socket, with its size (`Content-Length`) and [name]
/// (`Content-Disposition`) when [announce].
///
/// [sent] is called with the size of each chunk sent, [stopped] when the
/// download is cancelled (or fails) before all of [content] was sent. With
/// [failAfter], the connection fails once that many bytes were sent, with
/// the [HttpException] `dart:io` throws for a connection that closes early.
///
/// [cancelled] is the `cancelFuture` Dio passes to its adapter for the
/// request's `CancelToken`. When it completes, no more is sent, like Dio's
/// `IOHttpClientAdapter`, which aborts the request and so closes the
/// connection. Without that, whether the rest is sent would depend on
/// timing: Dio may read a response to its end after its reader stopped
/// listening.
ResponseBody fakeDownload(
  Uint8List content, {
  String? name,
  bool announce = true,
  int? failAfter,
  void Function(int bytes)? sent,
  void Function()? stopped,
  Future<void>? cancelled,
}) {
  var aborted = false;
  cancelled?.then<void>(
    (_) => aborted = true,
    onError: (Object _) => aborted = true,
  );
  Stream<Uint8List> chunks() async* {
    var complete = false;
    try {
      for (var start = 0; start < content.length; start += 64 * 1024) {
        await Future<void>.delayed(Duration.zero);
        if (aborted) return;
        if (failAfter case final limit? when start >= limit) {
          throw const HttpException('Connection closed while receiving data');
        }
        final end = start + 64 * 1024 < content.length
            ? start + 64 * 1024
            : content.length;
        sent?.call(end - start);
        yield Uint8List.sublistView(content, start, end);
      }
      complete = true;
    } finally {
      if (!complete) stopped?.call();
    }
  }

  return ResponseBody(
    chunks(),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/octet-stream'],
      if (announce) ...{
        Headers.contentLengthHeader: ['${content.length}'],
        if (name != null)
          'content-disposition': [
            'attachment; filename="${name.replaceAll(RegExp(r'["\\]'), '_')}"; '
                "filename*=UTF-8''${Uri.encodeComponent(name)}",
          ],
      },
    },
  );
}

/// Counts the downloads of a fake that were stopped before all of the file
/// was sent, and lets a test wait for them.
///
/// A download is stopped some time after the tool call that stopped it has
/// returned: the client cancels the transfer, and [fakeDownload] stops at
/// its next chunk. How long that takes depends on the machine (seen: more
/// than 100 ms on a slow CI runner), so a test waits for the count with
/// [reached] rather than for a fixed time.
class StoppedDownloads {
  int _count = 0;
  final _counts = StreamController<int>.broadcast(sync: true);

  /// How many downloads were stopped so far.
  int get count => _count;

  /// Counts one more stopped download.
  void add() => _counts.add(++_count);

  /// Completes once [count] downloads were stopped; fails the test when
  /// that takes longer than [timeout].
  Future<void> reached(
    int count, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    // Checked and listened to in the same turn of the event loop, so no
    // stop is missed in between.
    if (_count >= count) return;
    await _counts.stream
        .firstWhere((stopped) => stopped >= count)
        .timeout(
          timeout,
          onTimeout: () => fail(
            'expected $count stopped downloads within ${timeout.inSeconds} '
            'seconds, saw $_count',
          ),
        );
  }
}
