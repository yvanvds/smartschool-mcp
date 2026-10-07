import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart'
    hide IntradeskItemKind;

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'intradesk_access.dart';
import 'intradesk_cache.dart';
import 'intradesk_index.dart';

// Adding to Intradesk, shared by the tools that write there
// (`create_intradesk_folder`, `add_intradesk_weblink`,
// `upload_intradesk_files`): the folder a write adds to, read before sending
// ([readIntradeskParent]) and checked for the names it holds
// ([IntradeskParent.refuseTakenNames]); the write itself, with the library's
// errors as ToolErrors ([withIntradeskWrite]), among them its refusal of a
// folder the account may not add to, or of the wrong kind; a write Intradesk
// did not confirm ([intradeskWriteNotConfirmed]); and the index patched with
// what was made ([addToIntradeskIndex]).
//
// The library sends a create, and the last step of an upload, once: never
// again after logging in again (yvanvds/dartschool#128), and throws a
// [SmartschoolIntradeskSaveUnconfirmedError] when Intradesk's answer does not
// confirm a write that went out. That is why repeating a write's action, as
// [SmartschoolSession.run] does when Smartschool refused the session, cannot
// add anything twice: a refused session means the write was not carried out,
// the repeat reads the folder again (a name taken meanwhile is refused, and
// an upload asks for a new upload directory), and an unconfirmed write is not
// a refused session, so it is not repeated. Intradesk itself never refuses a
// name that is taken but renames the new item (`name (1)`, seen live): so a
// name the folder holds already is refused before sending, and Claude is told
// never to call a write again that may or may not have been made.

/// What a write tool adds to an error that came after the folder was read
/// but before anything was made.
const nothingAdded = 'Nothing was added to Intradesk.';

/// The `folder_id` argument of a tool that adds to an Intradesk folder: the
/// folder's id, in lowercase ([intradeskIdArgument]).
///
/// Throws a [ToolError] when it is empty: the top of Intradesk is not
/// offered (the library adds no weblink or file there, and a folder there
/// was not tried live).
String intradeskFolderArgument(Map<String, Object?> arguments) =>
    intradeskIdArgument(arguments, 'folder_id') ??
    (throw const ToolError(
      'folder_id is empty: pass the id of the folder to add to, from '
      'search_intradesk or list_intradesk_folder. Adding at the top of '
      'Intradesk is not offered. $nothingSent',
    ));

/// The `name` argument of a tool that adds a folder or a weblink to
/// Intradesk ([what], like `the new folder`), without the white space around
/// it.
///
/// Throws a [ToolError] for an empty name or one Smartschool does not allow
/// ([IntradeskService.isAllowedName]), which Intradesk answers with a bare
/// HTTP `500`.
String intradeskNameArgument(
  Map<String, Object?> arguments, {
  required String what,
}) {
  final name = (arguments['name'] as String? ?? '').trim();
  if (name.isEmpty) {
    throw ToolError('name is empty: give $what a name. $nothingSent');
  }
  if (!IntradeskService.isAllowedName(name)) {
    throw ToolError(
      'Smartschool does not allow the name "$name": no / : * ? " \\ < > |, '
      'and no dot at the start or end. Choose another name. $nothingSent',
    );
  }
  return name;
}

/// A note for a result when Intradesk stored a new item as [stored] instead
/// of [asked]: it renames a new item whose name is taken (`name (1)`), which
/// happens when the folder got an item of that name after the tool read it.
/// Null when the names are the same.
String? renamedNote(String asked, String stored) => asked == stored
    ? null
    : 'Note: Intradesk stored it as "$stored", not "$asked": it renames a '
          'new item whose name is taken in the folder, so an item named '
          '"$asked" was probably added there meanwhile. Tell the user.';

/// The folder an Intradesk write adds to, as [readIntradeskParent] read it
/// right before the write.
final class IntradeskParent {
  const IntradeskParent({
    required this.id,
    required this.path,
    required this.listing,
  });

  /// The folder's id, in lowercase.
  final String id;

  /// The folder's path, like `Vakken / Informatica`: the names of the
  /// folders from the top of Intradesk down to it, as Intradesk lists them
  /// now.
  final String path;

  /// What the folder holds now.
  final IntradeskListing listing;

  /// `Intradesk folder Vakken / Informatica (id …)`.
  String get title => intradeskFolderTitle(id, path);

  /// The items of [listing], named with the folder's path.
  List<IntradeskItem> get items =>
      intradeskItems(listing, folderId: id, path: path);

  /// The item in the folder whose name is [name], ignoring case and the
  /// white space around it, or null.
  IntradeskItem? holding(String name) {
    final wanted = name.trim().toLowerCase();
    return items
        .where((item) => item.name.trim().toLowerCase() == wanted)
        .firstOrNull;
  }

  /// Throws a [ToolError] when the folder holds an item (a folder, a file or
  /// a weblink) named like one of [names] already, ignoring case and the
  /// white space around it: Intradesk would not refuse the new item but
  /// rename it (`name (1)`, `name (1).ext`), which is not what the user
  /// asked for. [what] names the new items (like `the folder`, `a file`).
  void refuseTakenNames(Iterable<String> names, {required String what}) {
    final taken = [for (final name in names) ?holding(name)];
    if (taken.isEmpty) return;
    final listed = taken.map(describeIntradeskItem).join(', ');
    throw ToolError(
      'The $title already holds ${taken.length == 1 ? 'an item' : 'items'} '
      'with the name of $what: $listed. Intradesk does not refuse a second '
      'item with the same name, but adds the new one under another name '
      '(like "name (1)"). Choose another name, or ask the user what to do. '
      '$nothingSent',
    );
  }
}

/// `Intradesk folder Vakken / Informatica (id …)` for the folder [id] at
/// [path], or `Intradesk folder <id>` without a path.
String intradeskFolderTitle(String id, String? path) =>
    path == null ? 'Intradesk folder $id' : 'Intradesk folder $path (id $id)';

/// `the file "verslag.docx" (id …)`, `the weblink "Schoolsite"`: [item] in
/// a few words.
String describeIntradeskItem(IntradeskItem item) =>
    'the ${item.kind.name} "${item.name}"'
    '${item.id.isEmpty ? '' : ' (id ${item.id})'}';

/// Reads the folder [id] that a write is about to add to: its path, from
/// the library's `getFolderPath` (its parents, then the listing of the top
/// of Intradesk and of each folder above it, yvanvds/dartschool#132), and
/// its listing, for the names it holds.
///
/// Whether the account may add to the folder, and what kind of folder goes
/// in it, is not checked here: the library's create reads the folder again
/// and refuses those before sending (yvanvds/dartschool#138), which
/// [withIntradeskWrite] words.
///
/// Throws a [ToolError] when Intradesk has no folder [id] (an unknown id, or
/// that of a file or a weblink), or does not list it where its parents put
/// it (a folder in Intradesk's trash, or one the account does not see).
Future<IntradeskParent> readIntradeskParent(
  IntradeskService intradesk,
  String id,
) async {
  try {
    final folders = await intradesk.getFolderPath(id);
    return IntradeskParent(
      id: id,
      path: [
        for (final folder in folders) folder.name.trim(),
      ].join(IntradeskItem.separator),
      listing: await intradesk.getFolderListing(id),
    );
  } on SmartschoolIntradeskFolderNotFoundError catch (error) {
    // 200: the listing of the folder above does not hold it.
    throw ToolError(
      error.statusCode == 200
          ? 'Intradesk does not list the folder with id $id where it is: it '
                'is in Intradesk\'s trash, or your account does not see it. '
                'Take the id of a folder from list_intradesk_folder or '
                'search_intradesk. $nothingSent'
          : 'Intradesk has no folder with id $id: it is the id of a file or '
                'a weblink, or of a folder that does not exist (any more). '
                'Take the id of a folder from list_intradesk_folder or '
                'search_intradesk. $nothingSent',
    );
  }
}

/// Runs the Intradesk write [write] on the session, for a tool that adds
/// to Intradesk; [what] names what is added, where (like `the folder
/// "Toetsen" in the Intradesk folder …`), and [where] the folder it is
/// added to (like `Intradesk folder Vakken / Informatica (id …)`,
/// [IntradeskParent.title]), for the errors.
///
/// The library's errors become [ToolError]s that say nothing was added:
/// - [SmartschoolIntradeskAddRefusedError]: the library read the folder and
///   refused the write before sending it (yvanvds/dartschool#138), worded by
///   its reason ([_addRefusal]): the account may not add there, or the
///   folder takes another kind of folder;
/// - [SmartschoolIntradeskWriteRefusedError]: Intradesk refused the write
///   (HTTP `400` to `499`), with its reasons in its own words (Dutch) when
///   it gave any;
/// - [SmartschoolIntradeskFolderNotFoundError]: the folder is gone;
/// - [SmartschoolAttachmentUploadError], and an [ArgumentError] about one of
///   [files]: a file was not uploaded ([uploadToolError]);
/// - any other [ArgumentError]: the library refused the write before
///   sending it.
///
/// A [ToolError] of [write] itself (a check before sending) is thrown as it
/// is. A [SmartschoolIntradeskSaveUnconfirmedError] is thrown as it is too:
/// the write may or may not have been made ([intradeskWriteNotConfirmed]).
Future<T> withIntradeskWrite<T>(
  SmartschoolSession session,
  Future<T> Function(IntradeskService intradesk) write, {
  required String Function() what,
  required String Function() where,
  Iterable<LocalFile> files = const [],
}) async {
  try {
    return await withIntradesk(session, write);
  } on SmartschoolIntradeskAddRefusedError catch (error) {
    log('intradesk write: refused before sending (${error.reason.name})');
    throw ToolError(_addRefusal(error.reason, where()));
  } on SmartschoolIntradeskWriteRefusedError catch (error) {
    // The library's messages name the item: the log never shows a name.
    log(
      'intradesk write: refused (HTTP ${error.statusCode}, '
      '${error.violations.length} reasons)',
    );
    final violations = error.violations;
    throw ToolError(
      'Intradesk refused ${what()} (HTTP ${error.statusCode})'
      '${violations.isEmpty ? ', without saying why' : ': ${violations.map((v) => '"$v"').join(' ')}'}. '
      '$nothingAdded',
    );
  } on SmartschoolIntradeskFolderNotFoundError catch (error) {
    throw ToolError(
      'Intradesk has no folder with id ${error.folderId} (any more): it was '
      'removed or moved while ${what()} was being sent. Take the id of a '
      'folder from list_intradesk_folder or search_intradesk. $nothingAdded',
    );
  } on SmartschoolAttachmentUploadError catch (error) {
    throw uploadToolError(error, files: files, nothingDone: nothingAdded)!;
  } on ArgumentError catch (error) {
    if (error is RangeError) rethrow;
    if (uploadToolError(error, files: files, nothingDone: nothingAdded)
        case final toolError?) {
      throw toolError;
    }
    log('intradesk write: refused before sending (${error.name})');
    throw ToolError(
      '${_capitalised(what())} was refused before it was sent: '
      '${error.name == null ? '' : '${error.name} '}${error.message}. '
      '$nothingSent',
    );
  }
}

/// What a tool says when the library refused to add to [folder] (like
/// `Intradesk folder Vakken / Informatica (id …)`) for [reason], after
/// reading it and before sending anything (yvanvds/dartschool#138). These
/// are the rules of Intradesk's web client, which offers nothing else.
String _addRefusal(IntradeskAddRefusalReason reason, String folder) {
  final why = switch (reason) {
    IntradeskAddRefusalReason.cannotAdd =>
      'Your account may not add anything to the $folder: Smartschool does '
          'not give you that right for this folder, and Intradesk\'s own web '
          'client offers no folder, weblink or file there. Choose another '
          'folder, or ask someone who manages it.',
    // Only at the top of Intradesk, which the tools do not offer.
    IntradeskAddRefusalReason.cannotAddConfidentialFolder =>
      'Your account may not add a confidential folder to the $folder: '
          'Smartschool does not give you that right there. Leave confidential '
          'out to add an ordinary folder.',
    IntradeskAddRefusalReason.ordinaryParent =>
      'The $folder is not confidential: Intradesk adds a confidential folder '
          'only inside a confidential folder. Leave confidential out to add '
          'an ordinary folder.',
    IntradeskAddRefusalReason.confidentialParent =>
      'The $folder is confidential: inside a confidential folder Intradesk '
          'adds only confidential folders. Pass confidential: true, and tell '
          'the user that the new folder will be confidential.',
  };
  return '$why $nothingSent';
}

/// The result of an Intradesk write that went out without Intradesk
/// confirming it ([error]): [what] (like `The folder "Toetsen" in Intradesk
/// folder …`) may or may not have been added to the folder [folderId].
/// Claude must not call [tool] again for it, but list the folder first and
/// tell the user.
CallToolResult intradeskWriteNotConfirmed({
  required String tool,
  required String what,
  required String folderId,
  required SmartschoolIntradeskSaveUnconfirmedError error,
}) {
  log(
    '$tool: Intradesk did not confirm a write, not retrying '
    '(${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'}'
    '${error.cause == null ? '' : ', ${error.cause.runtimeType}'})',
  );
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text:
            '${_capitalised(what)} may or may not have been added: it was '
            'sent, but Intradesk did not confirm it. Do not call $tool again '
            'for it: Intradesk does not refuse a name that is taken, so a '
            'second call could add it twice. First list the folder with '
            'list_intradesk_folder (folder_id $folderId) to see whether it is '
            'there. Then tell the user what you found.',
      ),
    ],
  );
}

/// Adds [made], the items a write just made, named with the path of the
/// folder they were added to ([IntradeskParent.items] does the same for its
/// listing), to the index in [cache], so that `search_intradesk` finds them
/// at once instead of after the next walk: when an index is loaded
/// ([IntradeskIndexCache.patch]).
///
/// Returns how it went, for the log: `index patched` or `no index`.
Future<String> addToIntradeskIndex(
  IntradeskIndexCache cache,
  List<IntradeskItem> made,
) async =>
    await cache.patch(added: made) == null ? 'no index' : 'index patched';

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
