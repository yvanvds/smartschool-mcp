import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// The Intradesk module of a fake Smartschool: the directory listings of
/// the root and of each folder, and file downloads.
///
/// Listings have the shape of the dartschool fixtures under
/// `test/fixtures/smartschool/requests/get/intradesk/`, copied to
/// `test/fixtures/intradesk/` ([loadFixtures]). A folder is made with
/// [addFolder], a file with [addFile] and a weblink with [addWeblink]; each
/// shows up in its parent's listing. A file added with content can be
/// downloaded.
class FakeIntradesk {
  FakeIntradesk() {
    _listings[''] = _emptyListing();
  }

  static final _path = RegExp(
    r'^/intradesk/api/v1/(\d+)/directory-listing/forTreeOnlyFolders'
    r'(?:/([^/]+))?$',
  );
  static final _downloadPath = RegExp(
    r'^/intradesk/api/v1/(\d+)/files/([^/]+)/download$',
  );

  /// Listings by folder id; the root is ''.
  final Map<String, Map<String, List<Object?>>> _listings = {};

  /// The folder ids listed, in order; the root is ''.
  final List<String> listed = [];

  /// Folders whose listing is answered with this HTTP status instead. A
  /// folder id it does not know gets a 500, like the live platform.
  final Map<String, int> failing = {};

  /// The contents of the files that can be downloaded, by id.
  final Map<String, Uint8List> contents = {};
  final Map<String, String> _names = {};

  /// The file ids downloaded, in order.
  final List<String> downloaded = [];

  /// Whether downloads announce their size (`Content-Length`) and name
  /// (`Content-Disposition`).
  bool announceDownloads = true;

  /// How many bytes of downloads were sent: a download cancelled part of
  /// the way sends less than the file's size. Downloads come in chunks of
  /// 64 KB.
  int bytesSent = 0;

  /// How many downloads were cancelled before all of the file was sent.
  int stoppedDownloads = 0;

  int _folders = 0;
  int _files = 0;

  /// Serves the dartschool fixtures: the root with the folders `Documenten`
  /// (holding the folder `Archief` and the file `info.pdf`) and `Examens`
  /// (empty), and the file `welkom.docx`.
  void loadFixtures() {
    final folder = Directory('test/fixtures/intradesk');
    for (final file in folder.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last.replaceAll('.json', '');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      _listings[name == 'root' ? '' : name] = {
        for (final key in ['folders', 'files', 'weblinks'])
          key: [...json[key] as List],
      };
    }
    // Archief has no listing among the fixtures: it is empty.
    _listings.putIfAbsent(
      'bbbb1111-1111-4111-b111-111111111111',
      _emptyListing,
    );
  }

  /// Adds a folder [name] in [parent] (the root when empty) and returns its
  /// id.
  String addFolder(
    String name, {
    String parent = '',
    bool confidential = false,
    String changed = '2024-05-30T12:36:57+02:00',
  }) {
    final id = _id('aaaa', ++_folders);
    _listings[parent]!['folders']!.add({
      'id': id,
      'platform': {'id': 7, 'name': 'Testschool'},
      'name': name,
      'color': 'yellow',
      'state': 'active',
      'visible': true,
      'confidential': confidential,
      'officeTemplateFolder': false,
      'parentFolderId': parent,
      'dateStateChanged': changed,
      'dateCreated': changed,
      'dateChanged': changed,
      'isFavourite': false,
      'inConfidentialFolder': false,
      'capabilities': {
        'canManage': false,
        'canAdd': false,
        'canSeeHistory': false,
        'canSeeViewHistory': false,
      },
      'hasChildren': true,
    });
    _listings[id] = _emptyListing();
    return id;
  }

  /// Adds a file [name] of [size] bytes in [parent] (the root when empty)
  /// and returns its id. With [content], it can be downloaded, and its size
  /// is the content's unless [size] says otherwise.
  String addFile(
    String name, {
    String parent = '',
    int? size,
    Uint8List? content,
    bool confidential = false,
    String changed = '2024-08-29T17:01:56+02:00',
  }) {
    final id = _id('cccc', ++_files);
    if (content != null) {
      contents[id] = content;
      _names[id] = name;
    }
    size ??= content?.length ?? 1000;
    _listings[parent]!['files']!.add({
      'id': id,
      'platform': {'id': 7, 'name': 'Testschool'},
      'name': name,
      'state': 'active',
      'parentFolderId': parent,
      'dateCreated': changed,
      'dateStateChanged': changed,
      'dateChanged': changed,
      'currentRevision': {
        'id': _id('dddd', _files),
        'platform': {'id': 7, 'name': 'Testschool'},
        'fileId': id,
        'fileSize': size,
        'dateCreated': changed,
        'label': name,
        'owner': {
          'userIdentifier': '7_1001_0',
          'userPictureHash': 'initials_JJ',
          'userPictureUrl': 'https://userpicture.example.com/initials_JJ/128',
          'name': 'Jan Janssens',
          'nameReverse': 'Janssens Jan',
          'description': '',
          'descriptionReverse': '',
        },
      },
      'isFavourite': false,
      'confidential': confidential,
      'ownerId': '7_1001_0',
      'capabilities': {
        'canManage': false,
        'canMove': false,
        'canHandleRevisions': false,
        'canSeeHistory': false,
        'canSeeViewHistory': false,
      },
    });
    return id;
  }

  /// Adds a weblink to [parent] (the root when empty), with the keys every
  /// weblink of a live listing has; [raw] sets some of them, such as `id`,
  /// `name` and `url`.
  void addWeblink(Map<String, Object?> raw, {String parent = ''}) =>
      _listings[parent]!['weblinks']!.add({
        'id': '',
        'platform': {'id': 7, 'name': 'Testschool'},
        'name': '',
        'url': '',
        'icon': 'folder_orange',
        'state': 'active',
        'parentFolderId': parent,
        'dateCreated': '2024-08-29T17:01:56+02:00',
        'dateStateChanged': '2024-08-29T17:01:56+02:00',
        'dateChanged': '2024-08-29T17:01:56+02:00',
        'isFavourite': false,
        'confidential': false,
        'ownerId': '7_1001_0',
        'capabilities': {
          'canManage': false,
          'canMove': false,
          'canSeeHistory': false,
          'canSeeViewHistory': false,
        },
        ...raw,
      });

  /// Answers [options] if it is a request for an Intradesk listing or
  /// download.
  ResponseBody? respond(RequestOptions options) {
    if (options.method != 'GET') return null;
    if (_downloadPath.firstMatch(options.uri.path) case final download?) {
      return _download(download[2]!);
    }
    final match = _path.firstMatch(options.uri.path);
    if (match == null) return null;
    final id = match[2] ?? '';
    listed.add(id);
    if (failing[id] case final status?) {
      return _json('{"error":"forbidden"}', status: status);
    }
    final listing = _listings[id];
    // Seen live: an id that is not a folder (unknown, or a file) gets a 500.
    if (listing == null) return _json('{"error":"server error"}', status: 500);
    return _json(jsonEncode(listing));
  }

  ResponseBody _download(String id) {
    downloaded.add(id);
    final content = contents[id];
    // Seen live: an unknown file id gets a 404.
    if (content == null) return _json('{"error":"not found"}', status: 404);
    // Chunk by chunk, each in its own turn of the event loop, like data
    // arriving from a socket.
    Stream<Uint8List> chunks() async* {
      var complete = false;
      try {
        for (var start = 0; start < content.length; start += 64 * 1024) {
          await Future<void>.delayed(Duration.zero);
          final end = start + 64 * 1024 < content.length
              ? start + 64 * 1024
              : content.length;
          bytesSent += end - start;
          yield Uint8List.sublistView(content, start, end);
        }
        complete = true;
      } finally {
        if (!complete) stoppedDownloads++;
      }
    }

    return ResponseBody(
      chunks(),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
        if (announceDownloads) ...{
          Headers.contentLengthHeader: ['${content.length}'],
          'content-disposition': ['attachment; filename="${_names[id]}"'],
        },
      },
    );
  }

  static String _id(String prefix, int n) =>
      '$prefix${n.toString().padLeft(4, '0')}-0000-4000-8000-'
      '${n.toString().padLeft(12, '0')}';

  static Map<String, List<Object?>> _emptyListing() => {
    'folders': [],
    'files': [],
    'weblinks': [],
  };

  static ResponseBody _json(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}
