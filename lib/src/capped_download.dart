import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

/// A file downloaded by [downloadCapped].
final class DownloadedFile {
  const DownloadedFile(
    this.bytes, {
    this.fileName,
    this.contentType,
    this.announcedSize,
  });

  final Uint8List bytes;

  /// The file name from the `Content-Disposition` header, if any.
  final String? fileName;

  /// The `Content-Type` header, if any.
  final String? contentType;

  /// The size from the `Content-Length` header, if any.
  final int? announcedSize;
}

/// A download stopped because the file is larger than allowed.
final class FileTooLargeError implements Exception {
  const FileTooLargeError({required this.maxBytes, this.size});

  final int maxBytes;

  /// The size Smartschool announced; null when the download itself went
  /// past [maxBytes] (the file is larger, by how much is unknown).
  final int? size;

  @override
  String toString() =>
      'FileTooLargeError: ${size ?? 'more than $maxBytes'} bytes, '
      'allowed $maxBytes';
}

/// Downloads [path] with [client]'s session, like
/// `SmartschoolClient.download`, but stops with a [FileTooLargeError] as
/// soon as it is clear the file is larger than [maxBytes]: from the
/// `Content-Length` header before reading any of it, otherwise while
/// reading. A status other than 200 is a [SmartschoolDownloadError], like
/// the library's.
///
/// Workaround: the library's download reads the whole file into memory,
/// whatever its size, and cannot be limited (yvanvds/dartschool#41, #22).
Future<DownloadedFile> downloadCapped(
  SmartschoolClient client,
  String path, {
  required int maxBytes,
}) async {
  // Dio reads the body from the connection as soon as the response starts,
  // whether anyone listens or not; only cancelling the request stops it.
  final cancel = CancelToken();
  void stop(ResponseBody body) {
    body.stream.listen(null, onError: (_) {}, cancelOnError: true);
    cancel.cancel('download stopped');
  }

  final Response<ResponseBody> response;
  try {
    response = await client.dio.get<ResponseBody>(
      path,
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancel,
    );
  } on DioException catch (error) {
    // For example the session interceptor refusing a page of the login
    // chain.
    if (error.response?.data case final ResponseBody body) stop(body);
    rethrow;
  }
  final body = response.data!;
  final status = response.statusCode ?? 0;
  if (status != 200) {
    stop(body);
    throw SmartschoolDownloadError('Download failed: $path', status);
  }
  final announced = int.tryParse(
    response.headers.value(Headers.contentLengthHeader) ?? '',
  );
  if (announced != null && announced > maxBytes) {
    stop(body);
    throw FileTooLargeError(maxBytes: maxBytes, size: announced);
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in body.stream) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) {
      cancel.cancel('download stopped');
      throw FileTooLargeError(maxBytes: maxBytes);
    }
  }
  return DownloadedFile(
    bytes.takeBytes(),
    fileName: contentDispositionFileName(
      response.headers.value('content-disposition'),
    ),
    contentType: response.headers.value(Headers.contentTypeHeader),
    announcedSize: announced,
  );
}

/// The file name in a `Content-Disposition` header: its `filename*`
/// (RFC 5987, `UTF-8''na%C3%AFef.docx`) or else its `filename`; null when
/// it has neither.
String? contentDispositionFileName(String? header) {
  if (header == null) return null;
  final extended = RegExp(
    r"""filename\*\s*=\s*([\w-]+)'[^']*'([^;]+)""",
    caseSensitive: false,
  ).firstMatch(header);
  if (extended != null) {
    final encoding = extended[1]!.toLowerCase() == 'utf-8' ? utf8 : latin1;
    try {
      final name = encoding.decode(_percentDecode(extended[2]!.trim()));
      if (name.isNotEmpty) return name;
    } on FormatException {
      // Fall back to the plain filename.
    }
  }
  final plain = RegExp(
    r'''filename\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]+))''',
    caseSensitive: false,
  ).firstMatch(header);
  if (plain == null) return null;
  final quoted = plain[1]?.replaceAllMapped(
    RegExp(r'\\(.)'),
    (match) => match[1]!,
  );
  final name = (quoted ?? plain[2]!).trim();
  return name.isEmpty ? null : name;
}

/// The bytes of [text] with its `%XX` escapes decoded.
List<int> _percentDecode(String text) {
  final bytes = <int>[];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x25 && i + 2 < text.length) {
      final byte = int.tryParse(text.substring(i + 1, i + 3), radix: 16);
      if (byte != null) {
        bytes.add(byte);
        i += 2;
        continue;
      }
    }
    bytes.addAll(utf8.encode(text[i]));
  }
  return bytes;
}
