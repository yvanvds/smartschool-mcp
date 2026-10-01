import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// The answer to a file download as Smartschool sends it: [content] in
/// chunks of 64 KB, each in its own turn of the event loop like data
/// arriving from a socket, with its size (`Content-Length`) and [name]
/// (`Content-Disposition`) when [announce].
///
/// [sent] is called with the size of each chunk sent, [stopped] when the
/// download is cancelled (or fails) before all of [content] was sent. With
/// [failAfter], the connection fails once that many bytes were sent, with
/// the [HttpException] `dart:io` throws for a connection that closes early.
ResponseBody fakeDownload(
  Uint8List content, {
  String? name,
  bool announce = true,
  int? failAfter,
  void Function(int bytes)? sent,
  void Function()? stopped,
}) {
  Stream<Uint8List> chunks() async* {
    var complete = false;
    try {
      for (var start = 0; start < content.length; start += 64 * 1024) {
        await Future<void>.delayed(Duration.zero);
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
