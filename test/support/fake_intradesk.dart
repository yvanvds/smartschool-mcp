import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'fake_download.dart';
import 'fake_uploads.dart';

/// The Intradesk module of a fake Smartschool: the directory listings of
/// the root and of each folder, file downloads, and the writes of
/// yvanvds/dartschool#128.
///
/// Listings have the shape of the dartschool fixtures under
/// `test/fixtures/smartschool/requests/get/intradesk/`, copied to
/// `test/fixtures/intradesk/` ([loadFixtures]). A folder is made with
/// [addFolder], a file with [addFile] and a weblink with [addWeblink]; each
/// shows up in its parent's listing. A file added with content can be
/// downloaded. The parents of a folder are served as Smartschool does, which
/// the library asks for when a listing fails with a 500, and, with the
/// listings of the folders above, to read a folder's path and entry
/// (`getFolderPath`, `getFolder`, yvanvds/dartschool#132): the write tools
/// read the folder's path, and a create reads the folder it adds to before
/// sending it (yvanvds/dartschool#138).
///
/// The writes are carried out as the live Intradesk did on 2026-10-05, in
/// the shape of dartschool's trimmed captures (`intradesk_write_test.dart`);
/// the request bodies are recorded as sent ([writeRequests]):
/// - `POST /intradesk/api/v1/{platformId}/folders/` (and
///   `folders/as-confidential`) adds a folder and answers `201` with it,
///   without `hasChildren`; a confidential folder in an ordinary one gets
///   `400` with Intradesk's reason in `violations`;
/// - `POST .../weblinks/` adds a weblink and answers `201` with it; an
///   address without `http(s)://` or that is not one gets `400` with
///   `violations`;
/// - `POST .../files/upload` adds the files of an upload directory of
///   [uploads] and answers `201` with `files` as an object keyed by file id
///   and `exceptions` as an empty list (or the files of [refusedUploads]);
///   a directory without files gets a bare `400`. A directory is not used
///   up: taking it again adds its files again;
/// - `POST .../{folders|weblinks|files}/{id}/trash` with `{}` moves the item
///   to the trash ([trashed]) and answers an empty `204`: it no longer shows
///   in its folder's listing, and a folder takes everything in it along. An
///   item in the trash already (also one in a folder in the trash) gets
///   `204` again, as live. An id the fake has no item of that kind for (an
///   unknown id, or the id of an item of another kind, also one in the
///   trash) gets `404` with Intradesk's bare problem answer and moves
///   nothing, as the live one did on 2026-10-07 (yvanvds/dartschool#133).
///
/// A name that is taken is never refused: the new item is renamed to
/// `name (1)` (`name (1).ext` for a file). A parent that is not a folder, a
/// colour that Intradesk does not have, a missing icon and a name Smartschool
/// does not allow get a bare `500`. [nextWrites] answers the next writes
/// otherwise, and [beforeWrite] changes Intradesk between the tool's read and
/// its write.
class FakeIntradesk {
  FakeIntradesk({FakeUploads? uploads}) : uploads = uploads ?? FakeUploads() {
    _listings[''] = _emptyListing();
  }

  /// Smartschool's upload step, whose directories `files/upload` takes.
  final FakeUploads uploads;

  static final _write = RegExp(
    r'^/intradesk/api/v1/(\d+)/(folders/|folders/as-confidential|weblinks/|'
    r'files/upload|(folders|weblinks|files)/([^/]+)/trash)$',
  );

  /// The colours Intradesk has for a folder.
  static const _colors = [
    'red',
    'brown',
    'orange',
    'yellow',
    'green',
    'aqua',
    'blue',
    'purple',
    'pink',
    'white',
    'black',
  ];

  /// Intradesk's reason for a confidential folder in an ordinary one, as it
  /// gave it live.
  static const confidentialRefusal =
      'In een gewone map kan je enkel gewone mappen toevoegen. Vertrouwelijke '
      'mappen kan je hier niet toevoegen.';

  /// Intradesk's reason for an address it does not take, as it gave it
  /// live.
  static const urlRefusal = 'De URL die je hebt ingegeven is niet geldig.';

  static final _badName = RegExp(r'[/:*?"\\<>|]|^\.|\.$');

  static final _webAddress = RegExp(
    r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,63}\b'
    r'([-a-zA-Z0-9@:%_+.~#?&//=]*)$',
    caseSensitive: false,
  );

  /// The writes that reached Intradesk (with a session), in order, as `POST
  /// path` with the path after the platform (`folders/`, `weblinks/`,
  /// `files/upload`, `files/{id}/trash`, ...), whatever the answer.
  List<String> get writes => [
    for (final request in writeRequests) 'POST ${request.path}',
  ];

  /// The writes that reached Intradesk, with their JSON bodies as sent.
  final List<({String path, Map<String, Object?> body})> writeRequests = [];

  /// How the next writes are answered instead of being carried out as
  /// usual, in order.
  final List<FakeIntradeskWrite> nextWrites = [];

  /// Called with each write that is about to be carried out, after it is
  /// recorded: a test changes Intradesk there, as someone else in Smartschool
  /// between the tool's read and its write.
  void Function(String path, Map<String, Object?> body)? beforeWrite;

  /// The ids of the items moved to the trash, in order, each once.
  final List<String> trashed = [];

  /// The listing key (`folders`, `files` or `weblinks`) of each item in the
  /// trash, by id.
  final Map<String, String> _trash = {};

  /// File names that `files/upload` does not take, with Intradesk's reason:
  /// they are listed in the answer's `exceptions` (keyed per file, as the
  /// web client reads them) instead of being added.
  final Map<String, String> refusedUploads = {};

  int _made = 0;

  static final _path = RegExp(
    r'^/intradesk/api/v1/(\d+)/directory-listing/forTreeOnlyFolders'
    r'(?:/([^/]+))?$',
  );
  static final _downloadPath = RegExp(
    r'^/intradesk/api/v1/(\d+)/files/([^/]+)/download$',
  );
  static final _parentsPath = RegExp(
    r'^/intradesk/api/v1/(\d+)/folders/([^/]+)/parents$',
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

  /// The downloads cancelled before all of the file was sent; a test waits
  /// for them with `stops.reached`.
  final stops = StoppedDownloads();

  /// How many downloads were cancelled before all of the file was sent.
  int get stoppedDownloads => stops.count;

  /// When set, the connection of a download fails once this many bytes of
  /// it were sent, with the [HttpException] `dart:io` throws for a
  /// connection that closes early.
  int? failDownloadsAfter;

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
  /// id. With [canAdd], the account may add to it (its capabilities); a
  /// folder in a confidential folder is `inConfidentialFolder`.
  String addFolder(
    String name, {
    String parent = '',
    bool confidential = false,
    bool canAdd = false,
    String changed = '2024-05-30T12:36:57+02:00',
  }) {
    final id = _id('aaaa', ++_folders);
    _listings[parent]!['folders']!.add({
      ..._folderJson(
        id,
        name,
        parent,
        confidential: confidential,
        canAdd: canAdd,
        changed: changed,
      ),
      'hasChildren': true,
    });
    _listings[id] = _emptyListing();
    return id;
  }

  /// A folder as Intradesk answers its create, without `hasChildren`.
  Map<String, Object?> _folderJson(
    String id,
    String name,
    String parent, {
    String color = 'yellow',
    bool confidential = false,
    bool canAdd = false,
    String changed = '2024-05-30T12:36:57+02:00',
  }) => {
    'id': id,
    'platform': {'id': 7, 'name': 'Testschool'},
    'name': name,
    'color': color,
    'state': 'active',
    'visible': true,
    'confidential': confidential,
    'officeTemplateFolder': false,
    'parentFolderId': parent,
    'dateStateChanged': changed,
    'dateCreated': changed,
    'dateChanged': changed,
    'isFavourite': false,
    'inConfidentialFolder': isConfidential(parent),
    'capabilities': {
      'canManage': canAdd,
      'canAdd': canAdd,
      'canSeeHistory': false,
      'canSeeViewHistory': false,
    },
  };

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
    _listings[parent]!['files']!.add(
      _fileJson(
        id,
        name,
        parent,
        size: size ?? content?.length ?? 1000,
        confidential: confidential,
        changed: changed,
      ),
    );
    return id;
  }

  /// A file as a listing and Intradesk's answer to `files/upload` have it.
  Map<String, Object?> _fileJson(
    String id,
    String name,
    String parent, {
    required int size,
    bool confidential = false,
    String changed = '2024-08-29T17:01:56+02:00',
  }) => {
    'id': id,
    'platform': {'id': 7, 'name': 'Testschool'},
    'name': name,
    'state': 'active',
    'parentFolderId': parent,
    'dateCreated': changed,
    'dateStateChanged': changed,
    'dateChanged': changed,
    'currentRevision': {
      'id': 'dddd${id.substring(4)}',
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
  };

  /// Whether the folder [id] is confidential, or in a confidential folder;
  /// false for the root and an unknown id.
  bool isConfidential(String id) {
    for (final listing in _listings.values) {
      for (final folder in listing['folders']!.cast<Map<Object?, Object?>>()) {
        if (folder['id'] == id) {
          return folder['confidential'] == true ||
              folder['inConfidentialFolder'] == true;
        }
      }
    }
    return false;
  }

  /// The items of the folder [id] (the root when empty): its folders, files
  /// and weblinks as Intradesk lists them.
  List<Map<Object?, Object?>> itemsIn(String id) => [
    for (final key in ['folders', 'files', 'weblinks'])
      ...?_listings[id]?[key]?.cast<Map<Object?, Object?>>(),
  ];

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
  /// download; a download stops sending once [cancelled] completes (see
  /// [fakeDownload]).
  ResponseBody? respond(RequestOptions options, {Future<void>? cancelled}) {
    if (options.method == 'POST') return _respondToWrite(options);
    if (options.method != 'GET') return null;
    if (_downloadPath.firstMatch(options.uri.path) case final download?) {
      return _download(download[2]!, cancelled);
    }
    if (_parentsPath.firstMatch(options.uri.path) case final parents?) {
      return _parents(parents[2]!);
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

  /// The parents of folder [id] as Smartschool answers them (seen live,
  /// yvanvds/dartschool#37): a 404 for an id that is not a folder (unknown,
  /// a file or a weblink), and the folders above a folder, `[]` at the top.
  /// Here the folders above are their ids, from the top, as live: the
  /// library reads them to find a folder's entry (yvanvds/dartschool#132).
  ResponseBody _parents(String id) {
    if (id.isEmpty || !_listings.containsKey(id)) {
      return _json(
        '{"status":404,"title":"Not Found","detail":"","type":""}',
        status: 404,
      );
    }
    final parents = <String>[];
    var parent = _parentOf(id);
    while (parent != null && parent.isNotEmpty) {
      parents.insert(0, parent);
      parent = _parentOf(parent);
    }
    return _json(jsonEncode(parents));
  }

  /// The id of the folder whose listing holds the folder [id] ('' for the
  /// top), or null when no listing holds it.
  String? _parentOf(String id) {
    for (final MapEntry(:key, :value) in _listings.entries) {
      if (value['folders']!.any((folder) => (folder as Map)['id'] == id)) {
        return key;
      }
    }
    return null;
  }

  ResponseBody _download(String id, Future<void>? cancelled) {
    downloaded.add(id);
    final content = contents[id];
    // Seen live: an unknown file id gets a 404.
    if (content == null) return _json('{"error":"not found"}', status: 404);
    return fakeDownload(
      content,
      name: _names[id],
      announce: announceDownloads,
      failAfter: failDownloadsAfter,
      sent: (bytes) => bytesSent += bytes,
      stopped: stops.add,
      cancelled: cancelled,
    );
  }

  /// Answers a write, or null for a request that is not one.
  ResponseBody? _respondToWrite(RequestOptions options) {
    final match = _write.firstMatch(options.uri.path);
    if (match == null) return null;
    final path = match[2]!;
    final body = (options.data as Map).cast<String, Object?>();
    writeRequests.add((path: path, body: body));
    final override = nextWrites.isEmpty ? null : nextWrites.removeAt(0);
    switch (override) {
      case FakeIntradeskWrite(
        :final status,
        :final violations,
        carriedOut: false,
      ):
        return _problem(status, violations);
      default:
        beforeWrite?.call(path, body);
        final answer = switch (path) {
          'folders/' => _createFolder(body, confidential: false),
          'folders/as-confidential' => _createFolder(body, confidential: true),
          'weblinks/' => _createWeblink(body),
          'files/upload' => _takeFiles(body),
          _ => _moveToTrash(match[3]!, match[4]!),
        };
        if (override != null) {
          // Carried out, but the answer never arrives.
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection closed before full header was received',
            error: const SocketException('Connection reset by peer'),
          );
        }
        return answer;
    }
  }

  ResponseBody _createFolder(
    Map<String, Object?> body, {
    required bool confidential,
  }) {
    final parent = body['parentFolderId'];
    final name = body['name'];
    final color = body['color'];
    // Seen live: a bare 500 for each of these.
    if (parent is! String ||
        !_listings.containsKey(parent) ||
        color is! String ||
        !_colors.contains(color) ||
        name is! String ||
        name.trim().isEmpty ||
        _badName.hasMatch(name)) {
      return _problem(500);
    }
    if (confidential && !isConfidential(parent)) {
      return _problem(400, [confidentialRefusal]);
    }
    final id = _id('ffff', ++_made);
    final folder = _folderJson(
      id,
      _freeName(parent, name),
      parent,
      color: color,
      confidential: confidential,
      canAdd: true,
      changed: '2026-10-05T20:09:03+02:00',
    );
    _listings[parent]!['folders']!.add({...folder, 'hasChildren': false});
    _listings[id] = _emptyListing();
    return _json(jsonEncode(folder), status: 201);
  }

  ResponseBody _createWeblink(Map<String, Object?> body) {
    final parent = body['parentFolderId'];
    final name = body['name'];
    final url = body['url'];
    final icon = body['icon'];
    if (parent is! String ||
        !_listings.containsKey(parent) ||
        icon is! String ||
        icon.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        _badName.hasMatch(name)) {
      return _problem(500);
    }
    if (url is! String || !_webAddress.hasMatch(url)) {
      return _problem(400, [urlRefusal]);
    }
    const changed = '2026-10-05T20:09:03+02:00';
    final weblink = {
      'id': _id('eeee', ++_made),
      'platform': {'id': 7, 'name': 'Testschool'},
      'name': _freeName(parent, name),
      'state': 'active',
      'url': url,
      'icon': icon,
      'parentFolderId': parent,
      'dateCreated': changed,
      'dateStateChanged': changed,
      'dateChanged': changed,
      'isFavourite': false,
      'confidential': false,
      'ownerId': '7_1001_0',
      'capabilities': {
        'canManage': true,
        'canMove': true,
        'canSeeHistory': true,
        'canSeeViewHistory': true,
      },
    };
    _listings[parent]!['weblinks']!.add(weblink);
    return _json(jsonEncode(weblink), status: 201);
  }

  ResponseBody _takeFiles(Map<String, Object?> body) {
    final parent = body['parentFolderId'];
    if (parent is! String || !_listings.containsKey(parent)) {
      return _problem(500);
    }
    final files = uploads.directories[body['uploadDir']] ?? const [];
    // Seen live: a bare 400 for a directory without files.
    if (files.isEmpty) return _problem(400);
    final added = <String, Object?>{};
    final exceptions = <String, Object?>{};
    for (final file in files) {
      if (refusedUploads[file.name] case final reason?) {
        exceptions[file.name] = {
          'violations': {'file': reason},
        };
        continue;
      }
      final id = _id('cccc', ++_files);
      final json = _fileJson(
        id,
        _freeName(parent, file.name),
        parent,
        size: file.size,
        changed: '2026-10-05T20:09:04+02:00',
      );
      _listings[parent]!['files']!.add(json);
      added[id] = json;
    }
    return _json(
      jsonEncode({
        'files': added,
        'exceptions': exceptions.isEmpty ? <Object?>[] : exceptions,
      }),
      status: 201,
    );
  }

  /// Moves the item [id], listed under [key] (`folders`, `weblinks` or
  /// `files`), to the trash and answers `204`; see the class doc.
  ResponseBody _moveToTrash(String key, String id) {
    if (_inTrash(key, id)) return ResponseBody.fromString('', 204);
    for (final listing in _listings.values) {
      final items = listing[key]!;
      final index = items.indexWhere((item) => (item as Map)['id'] == id);
      if (index < 0) continue;
      items.removeAt(index);
      _trash[id] = key;
      trashed.add(id);
      return ResponseBody.fromString('', 204);
    }
    return _problem(404);
  }

  /// Whether the item [id], listed under [listing], is in the trash, or in a
  /// folder that is: an item of another kind with that id is not.
  bool _inTrash(String listing, String id) {
    if (_trash[id] case final trashed?) return trashed == listing;
    final folders = [
      for (final MapEntry(:key, :value) in _trash.entries)
        if (value == 'folders') key,
    ];
    while (folders.isNotEmpty) {
      final folder = folders.removeLast();
      final items = _listings[folder]?[listing] ?? const [];
      if (items.any((item) => (item as Map)['id'] == id)) return true;
      folders.addAll([
        for (final inside in _listings[folder]?['folders'] ?? const [])
          (inside as Map)['id']! as String,
      ]);
    }
    return false;
  }

  /// [name], or as Intradesk renames a new item when the folder [parent]
  /// holds an item of that name already (seen live): `name (1)`, `name
  /// (2)`, ..., before the extension of a name with one.
  String _freeName(String parent, String name) {
    final taken = {
      for (final item in itemsIn(parent))
        (item['name'] as String).trim().toLowerCase(),
    };
    if (!taken.contains(name.trim().toLowerCase())) return name;
    final dot = name.lastIndexOf('.');
    final (stem, extension) = dot > 0
        ? (name.substring(0, dot), name.substring(dot))
        : (name, '');
    for (var n = 1; ; n++) {
      final candidate = '$stem ($n)$extension';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
  }

  /// Intradesk's problem answer with [status], and [violations] when given:
  /// a bare 500 is `{"status":500,"title":"Internal Server Error",...}`.
  static ResponseBody _problem(int status, [List<String>? violations]) =>
      ResponseBody.fromString(
        jsonEncode({
          'status': status,
          'title': switch (status) {
            500 => 'Internal Server Error',
            404 => 'Not Found',
            403 => 'Forbidden',
            _ => 'Bad Request',
          },
          'detail': '',
          'type': '',
          'violations': ?violations,
        }),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/problem+json'],
        },
      );

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

/// How [FakeIntradesk] answers a write instead of carrying it out as usual
/// ([FakeIntradesk.nextWrites]).
final class FakeIntradeskWrite {
  /// Refused with HTTP [status] (`400` to `499`) and Intradesk's
  /// [violations], if any: nothing is made.
  const FakeIntradeskWrite.refused(this.status, [this.violations])
    : carriedOut = false;

  /// A bare `500`, as Intradesk answers a failure of its own: nothing is
  /// made, and the answer does not say so.
  const FakeIntradeskWrite.serverError()
    : status = 500,
      violations = null,
      carriedOut = false;

  /// Carried out, but the connection drops before the answer arrives.
  const FakeIntradeskWrite.lost()
    : status = 0,
      violations = null,
      carriedOut = true;

  final int status;
  final List<String>? violations;
  final bool carriedOut;
}
