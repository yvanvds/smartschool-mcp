import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../tools/server_tool.dart';

/// Where the message tools look for messages: one of the boxes a tool's
/// `box` argument names ([inbox], [sent] and [archive]), or a folder the
/// user made in Smartschool ("Map toevoegen") in the inbox or the sent box,
/// also inside another folder ([MessageBox.folder]), which a tool's `folder`
/// argument names ([BoxArgument]).
///
/// Smartschool's archive is not a [BoxType] of its own: it is a folder of
/// the inbox with its own box id, which [headers] looks up. A folder the
/// user made is a folder of its box in the same way, with the box id the
/// library's folder tree gives it ([MessagesService.getFolders]). Messages
/// in a folder are read with the [BoxType] of its box: Smartschool finds
/// them by their id.
final class MessageBox {
  const MessageBox._(this.name, this.label, this.phrase, this.boxType)
    : folder = null;

  /// [folder], a folder the user made, as [userFolders] lists them.
  ///
  /// Its [name] is its path from the box it is in, after that box's name,
  /// like `inbox/Projecten/2026`: the box to pass to the tools that read one
  /// message, then the folder.
  MessageBox.folder(MessageFolder this.folder)
    : boxType = folder.boxType,
      name = _pathName(folder),
      label = 'Folder ${_pathName(folder)}',
      phrase = 'the folder ${_pathName(folder)}';

  static const inbox = MessageBox._(
    'inbox',
    'Inbox',
    'the inbox',
    BoxType.inbox,
  );
  static const sent = MessageBox._(
    'sent',
    'Sent',
    'the sent box',
    BoxType.sent,
  );
  static const archive = MessageBox._(
    'archive',
    'Archive',
    'the archive',
    BoxType.inbox,
  );

  /// The boxes a tool's `box` argument names, in this order.
  static const values = [inbox, sent, archive];

  /// The box's name: the value of a tool's `box` argument (`inbox`, `sent`
  /// or `archive`), or a folder's path after the name of the box it is in,
  /// like `inbox/Projecten/2026`. Tool output names a message's box with it,
  /// and a tool's `folder` argument takes a folder's.
  final String name;

  /// The box's name at the start of a tool result, like `Inbox` or `Folder
  /// inbox/Projecten/2026`.
  final String label;

  /// The box in a sentence, like `the sent box` or `the folder
  /// inbox/Projecten/2026`.
  final String phrase;

  /// The [BoxType] to pass to [MessagesService] calls for a message in this
  /// box: that of the box a folder is in.
  final BoxType boxType;

  /// The folder the user made that this box is; null for [inbox], [sent]
  /// and [archive].
  final MessageFolder? folder;

  /// The argument of a tool that names this box, like `box sent` or
  /// `folder inbox/Projecten/2026`, for a note that says which box to list.
  String get argument => '${folder == null ? 'box' : 'folder'} $name';

  /// The folder of [boxType] this box is, for the [MessagesService] calls
  /// that name it (a `boxId`): the archive's box id, looked up once per
  /// service; a folder's own box id; 0 for the inbox and the sent box
  /// themselves.
  Future<int> folderId(MessagesService messages) async => switch (folder) {
    final folder? => folder.id,
    null => this == archive ? await messages.getArchiveBoxId() : 0,
  };

  /// The box named [value] (`inbox`, `sent` or `archive`); [inbox] when
  /// [value] is null.
  ///
  /// Throws an [ArgumentError] for another value; a tool's input schema
  /// ([schema]) rejects those before its handler runs.
  static MessageBox parse(Object? value) {
    if (value == null) return inbox;
    for (final box in values) {
      if (box.name == value) return box;
    }
    throw ArgumentError.value(value, 'box', 'not one of inbox, sent, archive');
  }

  /// The input schema of a tool's `box` argument: one of [boxes] (all boxes
  /// by default), [inbox] when absent.
  static Schema schema({
    required String description,
    List<MessageBox> boxes = values,
  }) => UntitledSingleSelectEnumSchema(
    description: description,
    values: [for (final box in boxes) box.name],
    defaultValue: inbox.name,
  );

  /// The folders the user made in the boxes of [boxTypes] (the inbox and
  /// the sent box by default), from the library's folder tree (one request,
  /// [MessagesService.getFolders]): every folder of those boxes but the
  /// archive, also those in another folder, each before the folders in it,
  /// in Smartschool's order.
  ///
  /// The tree is read again at every call: the user can add, rename or
  /// remove a folder in Smartschool at any time.
  static Future<List<MessageBox>> userFolders(
    MessagesService messages, {
    Set<BoxType> boxTypes = const {BoxType.inbox, BoxType.sent},
  }) async => [
    for (final folder in MessageFolder.flatten(await messages.getFolders()))
      if (!folder.isArchive && boxTypes.contains(folder.boxType))
        MessageBox.folder(folder),
  ];

  /// The folders of [folders] as a list for a sentence, each with its id:
  /// `inbox/A (id 1), sent/B (id 2)`.
  static String listFolders(Iterable<MessageBox> folders) => [
    for (final box in folders) '${box.name} (id ${box.folder?.id})',
  ].join(', ');

  /// The name of the box of [boxType], as a tool's `box` argument takes it.
  static String _boxName(BoxType boxType) =>
      boxType == BoxType.sent ? sent.name : inbox.name;

  /// [folder]'s [name]: its path after the name of its box.
  static String _pathName(MessageFolder folder) =>
      [_boxName(folder.boxType), ...folder.path].join('/');

  /// The message headers in this box, newest first.
  ///
  /// Smartschool lists a box 50 headers at a time. The pages are requested
  /// one after the other, and [stopAfter], when given, is called with each:
  /// when it returns true, no further page is requested. Without it, or
  /// when it never returns true, the whole box is listed, and a box can hold
  /// thousands of messages: stop as soon as the headers so far are enough.
  ///
  /// Smartschool keeps the paging position per user and box, not in the
  /// session (yvanvds/dartschool#76): a listing of the box anywhere on the
  /// account restarts it, also in another session (the web client, the
  /// Account Manager, another smartschool-mcp process). A listing that is
  /// still paging then fails with a [SmartschoolPagingRestartedError] after
  /// the pages it got, rather than return part of the box, and
  /// [SmartschoolSession.run] runs its action once more, which lists the box
  /// again (#28). So keep the state of [stopAfter] inside that action. A new
  /// login between two pages does not restart the paging: Smartschool goes
  /// on with the next page in the new session.
  ///
  /// Two pagings of the same box at the same time share the position and
  /// can skip each other's pages, without an error. So the box listings of
  /// this process run one at a time, also for different boxes: whether the
  /// inbox (box id 0) shares a position with a folder of it, such as the
  /// archive, is unknown (two folders do not, seen live by the library,
  /// yvanvds/dartschool#136). That keeps this server's own tool calls apart,
  /// but not a listing elsewhere on the account.
  Future<List<ShortMessage>> headers(
    MessagesService messages, {
    bool Function(List<ShortMessage> page)? stopAfter,
  }) => _oneListingAtATime(() async {
    final pages = switch (folder) {
      final folder? => messages.getHeaderPages(
        boxType: boxType,
        boxId: folder.id,
      ),
      null when this == archive => messages.getArchiveHeaderPages(),
      null => messages.getHeaderPages(boxType: boxType),
    };
    final headers = <ShortMessage>[];
    await for (final page in pages) {
      headers.addAll(page);
      if (stopAfter?.call(page) ?? false) break;
    }
    return headers;
  });

  /// The headers of the messages with [ids] in this box, by id.
  ///
  /// The box is listed newest first ([headers]) until all of [ids] are
  /// among the headers, or to its end: an id the box does not hold is
  /// missing from the map. The map holds the other headers listed as well.
  Future<Map<int, ShortMessage>> find(
    MessagesService messages,
    Iterable<int> ids,
  ) async {
    final missing = ids.toSet();
    final found = await headers(
      messages,
      stopAfter: (page) {
        missing.removeAll([for (final header in page) header.id]);
        return missing.isEmpty;
      },
    );
    return {for (final header in found) header.id: header};
  }

  /// Message [id] in this box, or null when the box has no such message.
  ///
  /// With [allRecipients] (the default) the message lists all its
  /// recipients; without, Smartschool names a few and counts the rest (a
  /// lighter request, for when the recipients do not matter).
  Future<FullMessage?> message(
    MessagesService messages,
    int id, {
    bool allRecipients = true,
  }) => messages.getMessage(
    id,
    boxType: boxType,
    includeAllRecipients: allRecipients,
  );
}

/// When the box listing that started last is done; the next one waits for
/// it.
Future<void> _lastListing = Future<void>.value();

/// Runs [listing] once the box listings started before it are done.
Future<T> _oneListingAtATime<T>(Future<T> Function() listing) {
  final previous = _lastListing;
  final done = Completer<void>();
  _lastListing = done.future;
  return previous.then((_) => listing()).whenComplete(done.complete);
}

/// Runs [action] with a [MessagesService] on the session's logged-in client.
///
/// The service is created inside [SmartschoolSession.run]'s callback and
/// disposed afterwards. Like every [SmartschoolSession.run] action, [action]
/// may run more than once (when Smartschool refuses the session, or
/// restarts a box listing of it, see [MessageBox.headers]), so it must be
/// safe to repeat.
Future<T> withMessages<T>(
  SmartschoolSession session,
  Future<T> Function(MessagesService messages) action,
) => session.run((client) async {
  final messages = MessagesService(client);
  try {
    return await action(messages);
  } finally {
    await messages.dispose();
  }
});

/// What the `box` argument of a tool that takes one message by its id says
/// about a message in a folder the user made: Smartschool finds it in its
/// box by its id.
const folderMessageBox =
    ' For a message in a folder the user made, the box that folder is in, '
    'which its path starts with (inbox for inbox/Projecten).';

/// The input schema of a tool's `folder` argument, next to its `box`.
Schema folderSchema({required String description}) =>
    Schema.string(description: description);

/// The description of a tool's `folder` argument, for the messages that
/// [verb] (like `list`), with what to add about the box ([box]).
String folderDescription(String verb, {String box = ''}) =>
    'A folder the user made in Smartschool, to $verb its messages instead '
    'of those of the box itself: its path as list_messages and '
    'search_messages show it (like inbox/Projecten/2026), its path from its '
    'box (Projecten/2026), its name or its id. An unknown folder is an error '
    'that names the folders the user has.$box';

/// A tool's `box` and `folder` arguments: a box ([MessageBox.parse]), or a
/// folder the user made, which [resolve] looks up in the folder tree.
///
/// `folder` takes a folder's path as tool output names it, after the name
/// of its box (`inbox/Projecten/2026`), its path from its box
/// (`Projecten/2026`), its name, ignoring case and the spaces around a `/`,
/// or its id. The folder is looked up in the box `box` names (inbox or
/// sent), or without `box` in all boxes whose folders the tool takes.
final class BoxArgument {
  BoxArgument._(this._box, this._folder, this._folderBoxTypes);

  /// The `box` and `folder` of [arguments]; a `folder` without `box` is
  /// looked up among the folders of the boxes of [folderBoxTypes].
  ///
  /// Throws a [ToolError] for `folder` with `box` archive: the folders the
  /// user made are in the inbox or the sent box. An empty `folder` counts as
  /// none.
  factory BoxArgument.parse(
    Map<String, Object?> arguments, {
    Set<BoxType> folderBoxTypes = const {BoxType.inbox, BoxType.sent},
  }) {
    final box = arguments['box'] == null
        ? null
        : MessageBox.parse(arguments['box']);
    final folder = switch (arguments['folder']) {
      final String folder when folder.trim().isNotEmpty => folder.trim(),
      _ => null,
    };
    if (folder != null && box == MessageBox.archive) {
      throw const ToolError(
        'folder names a folder the user made in the inbox or the sent box, '
        'not in the archive: pass box inbox or sent with it, or leave box '
        'out.',
      );
    }
    return BoxArgument._(
      box,
      folder,
      box == null ? folderBoxTypes : {box.boxType},
    );
  }

  final MessageBox? _box;
  final String? _folder;
  final Set<BoxType> _folderBoxTypes;

  /// The box the arguments name: the folder named, or else the box (the
  /// inbox by default).
  ///
  /// A folder is looked up in the folder tree ([MessageBox.userFolders]):
  /// first by its id, then by its path after the name of its box, then by
  /// its path from its box, then by its name. Throws a [ToolError] that
  /// names the user's folders when none matches, or more than one.
  Future<MessageBox> resolve(MessagesService messages) async {
    final named = _folder;
    if (named == null) return _box ?? MessageBox.inbox;
    final folders = await MessageBox.userFolders(messages);
    final matches = _matching([
      for (final folder in folders)
        if (_folderBoxTypes.contains(folder.boxType)) folder,
    ], named.replaceAll(_quotes, ''));
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) {
      throw ToolError(
        'There is more than one folder "$named": '
        '${MessageBox.listFolders(matches)}. Pass the one you mean as '
        'folder, by its path or its id.',
      );
    }
    if (folders.isEmpty) {
      throw ToolError(
        'There is no folder "$named": the user has made no folders in '
        "Smartschool's messages. Leave folder out and pass box (inbox, sent "
        'or archive).',
      );
    }
    final where = switch ((
      _folderBoxTypes.contains(BoxType.inbox),
      _folderBoxTypes.contains(BoxType.sent),
    )) {
      (true, true) => 'the inbox or the sent box',
      (false, true) => MessageBox.sent.phrase,
      _ => MessageBox.inbox.phrase,
    };
    throw ToolError(
      'There is no folder "$named" in $where. The folders the user made are: '
      '${MessageBox.listFolders(folders)}. Pass one of them as folder, by '
      'its path or its id.',
    );
  }

  /// Double quotes around a name.
  static final _quotes = RegExp(r'^"|"$');

  /// The folders of [folders] that [wanted] names: by id, else by path
  /// after the name of its box, else by path from its box, else by name.
  static List<MessageBox> _matching(List<MessageBox> folders, String wanted) {
    if (int.tryParse(wanted) case final id?) {
      final byId = [
        for (final box in folders)
          if (box.folder!.id == id) box,
      ];
      if (byId.isNotEmpty) return byId;
    }
    final key = _key(wanted);
    for (final name in <String Function(MessageBox box)>[
      (box) => box.name,
      (box) => box.folder!.path.join('/'),
      (box) => box.folder!.name,
    ]) {
      final matches = [
        for (final box in folders)
          if (_key(name(box)) == key) box,
      ];
      if (matches.isNotEmpty) return matches;
    }
    return const [];
  }

  /// [path] to compare: lowercase, without spaces around a `/`.
  static String _key(String path) =>
      path.split('/').map((part) => part.trim()).join('/').toLowerCase();
}
