import 'package:flutter_smartschool/flutter_smartschool.dart';

/// What an [IntradeskItem] is.
///
/// flutter_smartschool has an enum of the same name since 0.3.6, with the
/// kinds in another order (folder, weblink, file). This order is the one
/// the tools list and count in, so files that import both hide the
/// library's.
enum IntradeskItemKind { folder, file, weblink }

/// A folder, file or weblink on Intradesk, with the path of the folders
/// above it.
///
/// Made from a library listing ([IntradeskItem.folder], [IntradeskItem.file],
/// [IntradeskItem.weblink]) and kept in an [IntradeskIndex]. For a file,
/// [id] is what `IntradeskService.downloadFile` takes, [name] includes the
/// extension, and [size], [extension] and [mimeType] tell what a download
/// will bring.
final class IntradeskItem {
  const IntradeskItem({
    required this.kind,
    required this.id,
    required this.name,
    required this.parentId,
    required this.parentPath,
    this.changed,
    this.size,
    this.confidential = false,
    this.url,
  });

  /// [folder], listed in the folder [parentId] at [parentPath] (both
  /// empty at the root).
  factory IntradeskItem.folder(
    IntradeskFolder folder, {
    required String parentId,
    required String parentPath,
  }) => IntradeskItem(
    kind: IntradeskItemKind.folder,
    id: folder.id,
    name: folder.name.trim(),
    parentId: parentId,
    parentPath: parentPath,
    changed: folder.dateChanged,
    confidential: folder.confidential || folder.inConfidentialFolder,
  );

  /// [file], listed in the folder [parentId] at [parentPath] (both empty at
  /// the root).
  factory IntradeskItem.file(
    IntradeskFile file, {
    required String parentId,
    required String parentPath,
  }) => IntradeskItem(
    kind: IntradeskItemKind.file,
    id: file.id,
    name: file.name.trim(),
    parentId: parentId,
    parentPath: parentPath,
    changed: file.dateChanged,
    size: file.currentRevision?.fileSize,
    confidential: file.confidential,
  );

  /// The weblink [link], listed in the folder [parentId] at [parentPath]
  /// (both empty at the root); null when it has no name.
  static IntradeskItem? weblink(
    IntradeskWeblink link, {
    required String parentId,
    required String parentPath,
  }) {
    final name = link.name.trim();
    if (name.isEmpty) return null;
    final url = link.url.trim();
    return IntradeskItem(
      kind: IntradeskItemKind.weblink,
      id: link.id.trim(),
      name: name,
      parentId: parentId,
      parentPath: parentPath,
      changed: link.dateChanged,
      confidential: link.confidential,
      url: url.isEmpty ? null : url,
    );
  }

  final IntradeskItemKind kind;

  /// The folder or file id (a UUID). For a weblink, whatever id Smartschool
  /// gives it, possibly empty.
  final String id;

  /// The name as Smartschool shows it; for a file, with its extension.
  final String name;

  /// The id of the folder it was listed in; empty at the root.
  final String parentId;

  /// The names of the folders above it, from the root, joined with
  /// [separator]; empty at the root.
  final String parentPath;

  /// When it was last changed (UTC).
  final DateTime? changed;

  /// The size in bytes of a file's current version; null for folders and
  /// weblinks, and for a file without a current version.
  final int? size;

  /// Whether Smartschool marks it (or, for a folder, the folder it is in)
  /// confidential.
  final bool confidential;

  /// The address a weblink points to; null for folders and files.
  final String? url;

  /// Between the folder names of a path.
  static const separator = ' / ';

  /// The full path, like `Leerkrachten / Formulieren / uitstap.docx`.
  String get path => parentPath.isEmpty ? name : '$parentPath$separator$name';

  /// A file's extension in lowercase, without the dot (`docx`); empty when
  /// the name has none, and for folders and weblinks.
  String get extension {
    if (kind != IntradeskItemKind.file) return '';
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toLowerCase();
  }

  /// A file's MIME type, from its [extension]; null when the extension is
  /// not a common one.
  String? get mimeType => _mimeTypes[extension];

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    'parentId': parentId,
    'parentPath': parentPath,
    'changed': ?changed?.toUtc().toIso8601String(),
    'size': ?size,
    if (confidential) 'confidential': true,
    'url': ?url,
  };

  /// Reads what [toJson] wrote; throws a [FormatException] for anything
  /// else.
  factory IntradeskItem.fromJson(Object? json) {
    if (json case {
      'kind': final String kind,
      'id': final String id,
      'name': final String name,
      'parentId': final String parentId,
      'parentPath': final String parentPath,
    }) {
      final changed = json['changed'];
      final size = json['size'];
      final url = json['url'];
      return IntradeskItem(
        kind: IntradeskItemKind.values.firstWhere(
          (value) => value.name == kind,
          orElse: () => throw FormatException('unknown kind $kind'),
        ),
        id: id,
        name: name,
        parentId: parentId,
        parentPath: parentPath,
        changed: changed is String ? DateTime.parse(changed) : null,
        size: size is int ? size : null,
        confidential: json['confidential'] == true,
        url: url is String ? url : null,
      );
    }
    throw const FormatException('not an Intradesk item');
  }
}

/// MIME types by lowercase file extension, for the formats teachers keep on
/// Intradesk.
const _mimeTypes = {
  'pdf': 'application/pdf',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.'
      'presentation',
  'doc': 'application/msword',
  'xls': 'application/vnd.ms-excel',
  'ppt': 'application/vnd.ms-powerpoint',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'rtf': 'application/rtf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'md': 'text/markdown',
  'html': 'text/html',
  'htm': 'text/html',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'zip': 'application/zip',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
};

/// Every folder, file and weblink found on Intradesk by one walk of the tree
/// (see `buildIntradeskIndex`), for searching by name.
final class IntradeskIndex {
  IntradeskIndex({
    required this.builtAt,
    required List<IntradeskItem> items,
    this.unlisted = 0,
    this.skipped = 0,
    this.walkTime = Duration.zero,
  }) : items = List.unmodifiable(items);

  /// When the walk finished.
  final DateTime builtAt;

  /// In the order the walk found them: breadth-first, each folder's
  /// folders, then its files, then its weblinks.
  final List<IntradeskItem> items;

  /// Folders whose listing failed; their contents are missing.
  final int unlisted;

  /// Folders not listed because the walk reached its limit; their contents
  /// are missing.
  final int skipped;

  /// How long the walk took.
  final Duration walkTime;

  late final Map<String, IntradeskItem> _byId = {
    for (final item in items)
      if (item.id.isNotEmpty && item.kind != IntradeskItemKind.weblink)
        item.id: item,
  };

  late final Map<String, IntradeskItem> _weblinksById = {
    for (final item in items)
      if (item.id.isNotEmpty && item.kind == IntradeskItemKind.weblink)
        item.id: item,
  };

  /// The folder or file with [id], or null.
  IntradeskItem? find(String id) => _byId[id];

  /// The folder, file or weblink with [id], or null: [find], and a weblink
  /// that Smartschool gave an id.
  IntradeskItem? findItem(String id) => _byId[id] ?? _weblinksById[id];

  /// How many items there are of [kind].
  int count(IntradeskItemKind kind) =>
      items.where((item) => item.kind == kind).length;

  /// The items inside folder [folderId], at any depth.
  List<IntradeskItem> within(String folderId) {
    final folders = {folderId};
    final inside = <IntradeskItem>[];
    // Breadth-first order: a folder comes before what is in it.
    for (final item in items) {
      if (!folders.contains(item.parentId)) continue;
      inside.add(item);
      if (item.kind == IntradeskItemKind.folder) folders.add(item.id);
    }
    return inside;
  }

  /// This index after a write of the server's own (#111, #112), without
  /// walking: with [added], and without the items whose id is in [removed]
  /// and, for a folder, everything in it at any depth. Ids are compared
  /// ignoring case; an empty id removes nothing.
  ///
  /// An item of [added] whose id the index has already takes that item's
  /// place (a walk that ran meanwhile found it too); the others come last,
  /// after the folder they are in, so a folder still comes before what is in
  /// it. [builtAt], [unlisted], [skipped] and [walkTime] stay as they were:
  /// the next walk comes when it would have.
  IntradeskIndex patched({
    Iterable<IntradeskItem> added = const [],
    Iterable<String> removed = const [],
  }) {
    String key(String id) => id.toLowerCase();
    final gone = {
      for (final id in removed)
        if (id.isNotEmpty) key(id),
    };
    final replacing = {
      for (final item in added)
        if (item.id.isNotEmpty) key(item.id): item,
    };
    final goneFolders = <String>{};
    final placed = <IntradeskItem>{};
    final kept = <IntradeskItem>[];
    // Breadth-first: a folder comes before what is in it.
    for (final item in items) {
      final id = key(item.id);
      if ((item.id.isNotEmpty && gone.contains(id)) ||
          goneFolders.contains(key(item.parentId))) {
        if (item.kind == IntradeskItemKind.folder && item.id.isNotEmpty) {
          goneFolders.add(id);
        }
        continue;
      }
      final replacement = item.id.isEmpty ? null : replacing[id];
      if (replacement != null) placed.add(replacement);
      kept.add(replacement ?? item);
    }
    return IntradeskIndex(
      builtAt: builtAt,
      items: [
        ...kept,
        for (final item in added)
          if (!placed.contains(item) &&
              !gone.contains(key(item.id)) &&
              !goneFolders.contains(key(item.parentId)))
            item,
      ],
      unlisted: unlisted,
      skipped: skipped,
      walkTime: walkTime,
    );
  }

  /// The version of the saved index. Files of another version are ignored:
  /// raise it when what is saved changes.
  static const format = 1;

  Map<String, Object?> toJson() => {
    'format': format,
    'builtAt': builtAt.toUtc().toIso8601String(),
    'unlisted': unlisted,
    'skipped': skipped,
    'walkMs': walkTime.inMilliseconds,
    'items': [for (final item in items) item.toJson()],
  };

  /// Reads what [toJson] wrote; throws a [FormatException] for anything
  /// else, also for another [format].
  factory IntradeskIndex.fromJson(Object? json) {
    if (json case {
      'format': format,
      'builtAt': final String builtAt,
      'unlisted': final int unlisted,
      'skipped': final int skipped,
      'walkMs': final int walkMs,
      'items': final List<Object?> items,
    }) {
      return IntradeskIndex(
        builtAt: DateTime.parse(builtAt),
        items: [for (final item in items) IntradeskItem.fromJson(item)],
        unlisted: unlisted,
        skipped: skipped,
        walkTime: Duration(milliseconds: walkMs),
      );
    }
    throw const FormatException('not an Intradesk index of this format');
  }
}
