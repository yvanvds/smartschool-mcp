import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../tools/server_tool.dart';
import 'intradesk_index.dart';

/// Runs [action] with an [IntradeskService] on the session's logged-in
/// client.
///
/// The service is created inside [SmartschoolSession.run]'s callback, because
/// the session replaces its client after logging in again. Like every
/// [SmartschoolSession.run] action, [action] may run twice (after an expired
/// session), so it must be safe to repeat; reading Intradesk is.
Future<T> withIntradesk<T>(
  SmartschoolSession session,
  Future<T> Function(IntradeskService intradesk) action,
) => session.run((client) => action(IntradeskService(client)));

/// Matches an Intradesk folder or file id: a UUID.
final _id = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Whether [id] looks like an Intradesk folder or file id.
///
/// Checked before an id goes into a request path.
bool isIntradeskId(String id) => _id.hasMatch(id);

/// The items of [listing], the listing of the folder [folderId] (empty for
/// the root) at [path] (empty for the root): its folders, then its files,
/// then its named weblinks.
List<IntradeskItem> intradeskItems(
  IntradeskListing listing, {
  String folderId = '',
  String path = '',
}) => [
  for (final folder in listing.folders)
    IntradeskItem.folder(folder, parentId: folderId, parentPath: path),
  for (final file in listing.files)
    IntradeskItem.file(file, parentId: folderId, parentPath: path),
  for (final raw in listing.weblinks)
    ?IntradeskItem.weblink(raw, parentId: folderId, parentPath: path),
];

/// The Intradesk folder or file id argument [name] of [arguments], in
/// lowercase like Smartschool writes ids, or null when it is absent or
/// empty.
///
/// Throws a [ToolError] when it is not an Intradesk id, so that it never
/// goes into a request path.
String? intradeskIdArgument(Map<String, Object?> arguments, String name) {
  final value = arguments[name];
  if (value == null) return null;
  final id = value is String ? value.trim() : null;
  if (id != null && id.isEmpty) return null;
  if (id == null || !isIntradeskId(id)) {
    throw ToolError(
      '$name must be an Intradesk id like '
      '0a1b2c3d-1111-4222-8333-444455556666, as list_intradesk_folder and '
      'search_intradesk show them; ${value is String ? '"$value"' : '$value'} '
      'is not.',
    );
  }
  return id.toLowerCase();
}
