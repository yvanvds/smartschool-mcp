import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../tools/server_tool.dart';

/// A user or a group that a new message can go to, as the search of
/// Smartschool's compose form finds it, with the ids its compose form needs.
///
/// Each has a [reference], the text that names exactly this recipient for
/// `send_message`: its name with what tells it apart from others with that
/// name, like `Sven Lamber (user 146)` or `5GZ (group 298)`, and for a
/// person of another school of the school group also that school's
/// platform, like `Ned Flanders (user 2231, platform 5810)`.
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

  /// For a person of another school of the school group, the platform of
  /// that school ([MessageSearchUser.ssId]); null for the own school, and
  /// for a group.
  int? get platform;

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
  String get reference {
    final ids = [
      'user ${user.userId}',
      if (user.userLt != 0) 'co-account ${user.userLt}',
      if (platform case final platform?) 'platform $platform',
    ];
    return '$name (${ids.join(', ')})';
  }

  /// A person of another school of the school group has their school's
  /// platform as [MessageSearchUser.ssId], and its name as
  /// [MessageSearchUser.platformName], which Smartschool leaves empty for
  /// the own school (yvanvds/dartschool#238, seen live on 2026-11-09).
  @override
  int? get platform => user.platformName == null ? null : user.ssId;

  @override
  String? get details {
    final parts = [
      if (platform != null)
        'school: ${_text(user.schoolName) ?? user.platformName}',
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
  int? get platform => null;

  @override
  Object get _key => ('group', group.groupId, group.ssId);
}

String? _text(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

/// The users and then the groups that the search of Smartschool's compose
/// form finds for [query], in Smartschool's order, each once:
/// [searchRecipientsAll] with one query, which makes the requests of the
/// library's [MessagesService.searchRecipientsForCompose] (one compose form
/// and one search). [includeOtherSchools] is as for [searchRecipientsAll].
Future<List<Recipient>> searchRecipients(
  MessagesService messages,
  String query, {
  bool? includeOtherSchools,
}) async => (await searchRecipientsAll(messages, [
  query,
], includeOtherSchools: includeOtherSchools))[query]!;

/// For each of [queries], the users and then the groups that the search of
/// Smartschool's compose form finds for it, in Smartschool's order, each
/// once, keyed by the query, in the order given. A query given twice is
/// searched once.
///
/// Searches them all on one compose form
/// ([MessagesService.searchRecipientsForComposeAll], yvanvds/dartschool#107),
/// one search per query, where a [searchRecipients] per query loads a form
/// for each. Only loads a compose form and searches: nothing is sent, and
/// the form is left unused, as when the user closes it in Smartschool.
///
/// Throws a [ToolError] when Smartschool does not open its compose form (a
/// [SmartschoolComposeError]), for instance for an account that may not send
/// messages.
///
/// With [includeOtherSchools] `true`, the searches also find the people of
/// the other schools of the school group, as the compose form's checkbox
/// "Toon personen van andere scholen" does; `false` finds the own school
/// only; `null` searches with the account's setting of that checkbox, as
/// before (yvanvds/dartschool#238). The setting belongs to the account, so
/// for `true` or `false` the library switches it only when it differs and
/// sets it back after the searches. Its [SmartschoolComposeError]s then
/// also say that Smartschool does not offer the option to the account, or
/// that the setting could not be set back; the [ToolError] passes the
/// library's message on, a workaround: the library does not tell them apart
/// by type (yvanvds/dartschool#241, removal tracked in
/// yvanvds/smartschool-mcp#213).
///
/// A search goes out only in the session of the compose form whose token it
/// sends (yvanvds/dartschool#97): when Smartschool refuses the session for
/// it, or the client logged in again since the form was loaded, the library
/// loads a new form, logging in first when Smartschool refuses the session
/// for that, and goes on with the searches on it. It does so once: when a
/// search on the new form cannot go out in its session either, it throws a
/// [SmartschoolSessionExpiredError], and no search went out with the token
/// of another session.
Future<Map<String, List<Recipient>>> searchRecipientsAll(
  MessagesService messages,
  Iterable<String> queries, {
  bool? includeOtherSchools,
}) async {
  final Map<String, (List<MessageSearchUser>, List<MessageSearchGroup>)>
  results;
  try {
    results = await messages.searchRecipientsForComposeAll(
      queries,
      includeOtherSchools: includeOtherSchools,
    );
  } on SmartschoolComposeError catch (error) {
    log('recipient search: compose form refused: $error');
    if (includeOtherSchools == null) {
      throw const ToolError(
        'Smartschool did not open its compose form, so recipients cannot be '
        'looked up, and nothing was sent. The account may not be allowed to '
        'send messages; the details are in the server log.',
      );
    }
    // Without the library's own markers: the method's name, the type of the
    // errors it names, and its issue numbers.
    final message = error.message.replaceAll(
      RegExp(
        r'SmartschoolComposeError: |searchRecipientsForCompose: | \(#\d+\)',
      ),
      '',
    );
    throw ToolError(
      'Smartschool could not look up recipients with its option "Toon '
      'personen van andere scholen" ${includeOtherSchools ? 'on' : 'off'}, '
      'and nothing was sent: $message',
    );
  }
  return {
    for (final MapEntry(key: query, value: (users, groups)) in results.entries)
      query: withoutRepeats(<Recipient>[
        for (final user in users) UserRecipient(user),
        for (final group in groups) GroupRecipient(group),
      ]),
  };
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
  /// Reads [text]: `Name (user 146)`, `Name (user 146, co-account 1)`,
  /// `Name (user 2231, platform 5810)` (a person of another school) and
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
      platform: match[5] == null ? null : int.parse(match[5]!),
    );
  }

  const RecipientRequest._(
    this.name, {
    required this.text,
    this.group = false,
    this.id,
    this.coaccount = 0,
    this.platform,
  });

  static final _reference = RegExp(
    r'^(.*\S)\s*\((user|group)\s+(\d+)(?:\s*,\s*co-account\s+(\d+))?'
    r'(?:\s*,\s*platform\s+(\d+))?\)$',
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

  /// The platform given with a user id: that of a person of another school
  /// of the school group ([Recipient.platform]). Null for the own school.
  final int? platform;

  /// Whether it names a person of another school, whom only a search with
  /// the people of the other schools finds.
  bool get otherSchool => platform != null;

  /// The recipients among [found] (what the search for [name] found) that
  /// this request names: those with exactly [name] (ignoring case and extra
  /// spaces) and, when it gives one, the kind and id in brackets, and the
  /// platform: a reference without one names someone of the own school.
  List<Recipient> matches(List<Recipient> found) => [
    for (final recipient in found)
      if (normalName(recipient.name) == normalName(name) && _sameId(recipient))
        recipient,
  ];

  bool _sameId(Recipient recipient) {
    if (id == null) return true;
    return switch (recipient) {
      UserRecipient(:final user) =>
        !group &&
            user.userId == id &&
            user.userLt == coaccount &&
            recipient.platform == platform,
      GroupRecipient(group: final g) =>
        group && g.groupId == id && platform == null,
    };
  }
}

/// [name] trimmed, with single spaces and in lower case: two names are the
/// same name when this makes them equal.
String normalName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
