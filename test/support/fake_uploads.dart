import 'dart:convert';

import 'package:dio/dio.dart';

/// A file uploaded into an upload directory of [FakeUploads].
typedef FakeUploadedFile = ({String name, int size});

/// Smartschool's upload step, which every module that takes files goes
/// through first (yvanvds/dartschool#128): the files are uploaded one by one
/// into an upload directory, and the module (Intradesk, see
/// `FakeIntradesk`) is then told to take the files of that directory.
///
/// As the live platform answered it on 2026-10-05 (dartschool's
/// `intradesk_write_test.dart`):
/// - `GET /upload/api/v1/get-upload-directory` answers
///   `{"uploadDir": "<30 hex characters>"}`, a new directory every time;
/// - `POST /Upload/Upload/Index`, multipart with the fields `file` and
///   `uploadDir`, answers `true`, or HTTP `400` with the rule in plain text
///   (as `text/html`) for a file name with one of `/ : * ? " \ < > |` or a
///   dot at its start or end.
///
/// A directory is not used up by the module that takes its files: it keeps
/// them.
class FakeUploads {
  static const directoryPath = '/upload/api/v1/get-upload-directory';
  static const uploadPath = '/Upload/Upload/Index';

  /// Smartschool's answer to a file name it does not allow, as it gave it
  /// live.
  static const badNameText =
      'De karakters: / : * ? " \\ < > | zijn niet toegestaan in de naam van '
      'een map of bestand. Een punt voor of achter de naam van een map of '
      'bestand is ook niet toegestaan.';

  static final _badName = RegExp(r'[/:*?"\\<>|]|^\.|\.$');

  /// The upload directories handed out, each with the files uploaded into
  /// it, in order.
  final Map<String, List<FakeUploadedFile>> directories = {};

  /// Every file uploaded (or refused), as `(directory, file name)`, in
  /// order.
  final List<(String?, String?)> uploads = [];

  /// Answers for the next uploads instead of taking the file: an HTTP status
  /// and a plain-text body, such as `(400, badNameText)`.
  final List<(int, String)> nextRefusals = [];

  /// When set, the request for an upload directory is answered with this
  /// HTTP status and an empty object.
  int? directoryStatus;

  int _directories = 0;

  /// Answers [options] if it is a request of the upload step.
  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (options.method == 'GET' && path == directoryPath) {
      if (directoryStatus case final status?) return _json('{}', status);
      final dir = (++_directories).toRadixString(16).padLeft(30, 'a');
      directories[dir] = [];
      return _json(jsonEncode({'uploadDir': dir}));
    }
    if (options.method != 'POST' || path != uploadPath) return null;
    final form = options.data as FormData;
    final dir = form.fields
        .where((field) => field.key == 'uploadDir')
        .firstOrNull
        ?.value;
    final file = form.files.where((file) => file.key == 'file').firstOrNull;
    final name = file?.value.filename;
    uploads.add((dir, name));
    if (nextRefusals.isNotEmpty) {
      final (status, body) = nextRefusals.removeAt(0);
      return _text(body, status);
    }
    if (name == null || _badName.hasMatch(name)) {
      return _text(badNameText, 400);
    }
    final files = directories[dir];
    if (files == null) return _json('false');
    files.add((name: name, size: file!.value.length));
    return _json('true');
  }

  static ResponseBody _json(String body, [int status = 200]) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  static ResponseBody _text(String body, int status) => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
    },
  );
}
