import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../tools/server_tool.dart';

/// A user or a group that a new message can go to, as the search of
/// Smartschool's compose form finds it, with the ids its compose form needs.
///
/// Each has a [reference], the text that names exactly this recipient for
/// `send_message`: its name with what tells it apart from others with that
/// name, like `Sven Lamber (user 146)` or `5GZ (group 298)`.
sealed class Recipient {
  const Recipient();

  /// The name Smartschool shows, trimmed.
  String get name;

  /// Names exactly this recipient: [name] and its kind and id, in brackets.
  String get reference;

  /// What tells it apart from others with the same name (a class, a
  /// co-account, a group's description), or null.
  String? get details;

  /// How a send's result names it: [name], with `(group)` for a group.
  String get label;

  /// [reference], with [details] after a `|` when there are any: a line of
  /// `search_recipients`, and how an unclear recipient's candidates are
  /// listed.
  String get listing => switch (details) {
    null => reference,
    final details => '$reference | $details',
  };

  /// What identifies the recipient on the compose form, for dropping a
  /// recipient found twice.
  Object get _key;
}

/// A user, such as a teacher or a student. A student's co-accounts (parents)
/// are users too, with the student's id and a co-account number
/// ([MessageSearchUser.userLt], 0 for the main account).
final class UserRecipient extends Recipient {
  const UserRecipient(this.user);

  final MessageSearchUser user;

  @override
  String get name => user.displayName.trim();

  @override
  String get reference => user.userLt == 0
      ? '$name (user ${user.userId})'
      : '$name (user ${user.userId}, co-account ${user.userLt})';

  @override
  String? get details {
    final parts = [
      ?_text(user.className),
      if (_text(user.coaccountName) case final coaccount?)
        'co-account: $coaccount',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  String get label => name;

  @override
  Object get _key => ('user', user.userId, user.ssId, user.userLt);
}

/// A group, such as a class: a message to it goes to all its members.
final class GroupRecipient extends Recipient {
  const GroupRecipient(this.group);

  final MessageSearchGroup group;

  @override
  String get name => group.displayName.trim();

  @override
  String get reference => '$name (group ${group.groupId})';

  @override
  String? get details => switch (_text(group.description)) {
    null => 'group',
    final description => 'group: $description',
  };

  @override
  String get label => '$name (group)';

  @override
  Object get _key => ('group', group.groupId, group.ssId);
}

String? _text(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

/// The users and then the groups that the search of Smartschool's compose
/// form ([MessagesService.searchRecipientsForCompose]) finds for [query], in
/// Smartschool's order, each once.
///
/// Only loads a compose form and searches: nothing is sent, and the form is
/// left unused, as when the user closes it in Smartschool.
///
/// Throws a [ToolError] when Smartschool does not open its compose form (a
/// [SmartschoolComposeError]), for instance for an account that may not send
/// messages.
///
/// When the session expires between loading the form and searching, the
/// library logs in again and sends the search with the old form's token
/// (yvanvds/dartschool#97); what Smartschool answers then has not been seen.
Future<List<Recipient>> searchRecipients(
  MessagesService messages,
  String query,
) async {
  final List<MessageSearchUser> users;
  final List<MessageSearchGroup> groups;
  try {
    (users, groups) = await messages.searchRecipientsForCompose(query);
  } on SmartschoolComposeError catch (error) {
    log('recipient search: compose form refused: $error');
    throw const ToolError(
      'Smartschool did not open its compose form, so recipients cannot be '
      'looked up, and nothing was sent. The account may not be allowed to '
      'send messages; the details are in the server log.',
    );
  }
  final seen = <Object>{};
  return [
    for (final recipient in <Recipient>[
      for (final user in users) UserRecipient(user),
      for (final group in groups) GroupRecipient(group),
    ])
      if (seen.add(recipient._key)) recipient,
  ];
}

/// How many users and groups [recipients] holds, like `2 users` or `1 user
/// and 1 group`.
String countRecipients(List<Recipient> recipients) {
  final users = recipients.whereType<UserRecipient>().length;
  final groups = recipients.length - users;
  String count(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';
  return [
    if (users > 0 || groups == 0) count(users, 'user'),
    if (groups > 0) count(groups, 'group'),
  ].join(' and ');
}

/// [recipients] without a recipient found earlier in the list.
List<Recipient> withoutRepeats(Iterable<Recipient> recipients) {
  final seen = <Object>{};
  return [
    for (final recipient in recipients)
      if (seen.add(recipient._key)) recipient,
  ];
}

/// Whether [a] and [b] are the same recipient.
bool sameRecipient(Recipient a, Recipient b) => a._key == b._key;

/// A recipient as `send_message` takes it: a name, or a [Recipient.reference]
/// (the name with its kind and id in brackets).
final class RecipientRequest {
  /// Reads [text]: `Name (user 146)`, `Name (user 146, co-account 1)` and
  /// `Name (group 298)` name one recipient; anything else is a name.
  factory RecipientRequest.parse(String text) {
    final trimmed = text.trim();
    final match = _reference.firstMatch(trimmed);
    if (match == null) return RecipientRequest._(trimmed, text: trimmed);
    return RecipientRequest._(
      match[1]!,
      text: trimmed,
      group: match[2]!.toLowerCase() == 'group',
      id: int.parse(match[3]!),
      coaccount: int.parse(match[4] ?? '0'),
    );
  }

  const RecipientRequest._(
    this.name, {
    required this.text,
    this.group = false,
    this.id,
    this.coaccount = 0,
  });

  static final _reference = RegExp(
    r'^(.*\S)\s*\((user|group)\s+(\d+)(?:\s*,\s*co-account\s+(\d+))?\)$',
    caseSensitive: false,
  );

  /// As given, trimmed.
  final String text;

  /// The name to search for.
  final String name;

  /// With an [id]: whether it names a group rather than a user.
  final bool group;

  /// The user or group id given in brackets, or null for a name alone.
  final int? id;

  /// The co-account number given with a user id (0: none, the main account).
  final int coaccount;

  /// The recipients among [found] (what the search for [name] found) that
  /// this request names: those with exactly [name] (ignoring case and extra
  /// spaces) and, when it gives one, the kind and id in brackets.
  List<Recipient> matches(List<Recipient> found) => [
    for (final recipient in found)
      if (normalName(recipient.name) == normalName(name) && _sameId(recipient))
        recipient,
  ];

  bool _sameId(Recipient recipient) {
    if (id == null) return true;
    return switch (recipient) {
      UserRecipient(:final user) =>
        !group && user.userId == id && user.userLt == coaccount,
      GroupRecipient(group: final g) => group && g.groupId == id,
    };
  }
}

/// [name] trimmed, with single spaces and in lower case: two names are the
/// same name when this makes them equal.
String normalName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
