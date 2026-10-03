import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/message_filter.dart';
import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/server_tool.dart';
import 'presence_format.dart';

// Reaching Smartschool's Presence module for the presence tools (#47): the
// session runner, the module's errors as ToolErrors, the arguments the tools
// share, and the access check of smartschool_status.

/// The rights the presence tools need, as `smartschool_status` and the
/// messages name them.
const presenceRights =
    "the right to record half-day presences for classes in Smartschool's "
    'Presence module, as an absence administrator has';

/// One [PresenceService] per client, for a tool call that runs several
/// session actions: the service keeps the module's configuration and the
/// codes of a school structure once read, so they are read once per call,
/// not once per action.
final class PresenceServices {
  SmartschoolClient? _client;
  PresenceService? _service;

  /// The service on [client]: the same one as before for the same client.
  PresenceService of(SmartschoolClient client) {
    if (identical(client, _client)) return _service!;
    _client = client;
    return _service = PresenceService(client);
  }
}

/// Runs [action] with a [PresenceService] on the session's logged-in client
/// (from [services], when given), and passes the module's errors on as they
/// are: for a tool that reports a [SmartschoolPresenceError] in its own words.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; the reads
/// are, and so are the library's writes: they save the same status again.
Future<T> runPresence<T>(
  SmartschoolSession session,
  Future<T> Function(PresenceService presence) action, {
  PresenceServices? services,
}) {
  final cache = services ?? PresenceServices();
  return session.run((client) => action(cache.of(client)));
}

/// [runPresence], with the module's errors as [ToolError]s
/// ([presenceToolError]); login and connection failures stay
/// `SmartschoolProblem`s.
Future<T> withPresence<T>(
  SmartschoolSession session,
  Future<T> Function(PresenceService presence) action, {
  PresenceServices? services,
}) async {
  try {
    return await runPresence(session, action, services: services);
  } on SmartschoolPresenceError catch (error) {
    throw presenceToolError(error, session.source);
  }
}

/// The [ToolError] for [error], an error of [PresenceService] from a read:
/// the Presence module refused the request (an error page instead of data),
/// or a class, code or pupil could not be found. Usually the account lacks
/// [presenceRights]; [source] is where the user turns "Aanwezigheden" off.
///
/// The library's message can quote what the module answered, which may hold
/// names, so it goes to the log only.
ToolError presenceToolError(
  SmartschoolPresenceError error,
  CredentialSource source,
) {
  log('presence: $error');
  return ToolError(
    "Smartschool's Presence module refused the request, or could not find "
    'what it was asked for; usually the account lacks $presenceRights. If '
    'so, ${presenceFix(source)}. Otherwise try again in a moment; the '
    'technical details are in the server log.',
  );
}

/// What the user does about missing rights, to end a sentence with.
String presenceFix(CredentialSource source) =>
    "ask the school's Smartschool administrator for them, or turn off "
    '${source.name(Setting.presence)} ${source.where}, then ${source.restart}';

/// Whether the account can use the presence tools, for
/// `smartschool_status`: one cheap read, the module's configuration
/// ([PresenceService.getConfig]), which lists the classes the account may
/// view and whether it may record presences for each.
///
/// Access when it may record presences for at least one class; no access
/// when it may record for none (also when the module lists no classes), or
/// when the module refuses the read.
///
/// Throws a `SmartschoolProblem` when it cannot log in or reach
/// Smartschool.
Future<AccessCheck> checkPresenceAccess(SmartschoolSession session) async {
  final List<PresenceClassRef> classes;
  try {
    classes = presenceClasses(
      await withPresence(session, (presence) => presence.getConfig()),
    );
  } on ToolError catch (error) {
    return AccessCheck.denied(error.message);
  }
  final recordable = classes.where((c) => c.userCanRecord).length;
  final listed =
      '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}';
  if (recordable == 0) {
    final seen = classes.isEmpty
        ? 'The Presence module lists no classes for this account'
        : 'The Presence module lists $listed for this account, but it may '
              'record presences for none of them';
    return AccessCheck.denied(
      '$seen, as for an account without $presenceRights. If so, '
      '${presenceFix(session.source)}.',
    );
  }
  return AccessCheck.granted(
    'the Presence module lets it record presences for $recordable of the '
    '$listed it lists',
  );
}

/// The classes of [config] the account may view: those the module allows,
/// and the class active in its web client when that is not among them, as
/// [PresenceConfig.classForGroup] finds them.
List<PresenceClassRef> presenceClasses(PresenceConfig config) => [
  ...config.allowedClasses,
  if (config.activeClass case final active?
      when !config.allowedClasses.any((c) => c.groupId == active.groupId))
    active,
];

/// The `class_id` argument of the presence tools.
Schema presenceClassIdSchema() => Schema.int(
  description: 'The class id, from list_presence_classes.',
  minimum: 1,
);

/// The day [value] names, like `2026-10-05`, at midnight in the time of this
/// PC (Smartschool time, Belgium).
///
/// Throws a [ToolError] for anything else, also a date with a time: the
/// presences are per half-day.
DateTime presenceDay(String value) {
  final text = value.trim();
  final invalid = ToolError(
    'date must be a day like 2026-10-05, without a time; "$value" is not.',
  );
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) throw invalid;
  try {
    return parseDateArgument('date', text);
  } on ToolError {
    // A day that does not exist, such as 2026-02-30.
    throw invalid;
  }
}

/// The day [now] falls on, at midnight.
DateTime presenceToday(DateTime now) => DateTime(now.year, now.month, now.day);

/// One day of a class in the Presence module, as [readPresenceDay] reads
/// it.
final class PresenceDay {
  const PresenceDay({
    required this.presenceClass,
    required this.day,
    required this.codes,
    required this.pupils,
  });

  /// The class, as the module's configuration lists it.
  final PresenceClassRef presenceClass;

  /// The day, at midnight.
  final DateTime day;

  /// The codes of the class's school structure: empty for a grouping class
  /// without one.
  final PresenceCodes codes;

  /// The pupils with their half-day cells for [day], in the module's order,
  /// with what the module said about the class on that day
  /// (yvanvds/dartschool#104).
  final PresenceClassPupils pupils;

  /// Whether the module refuses to record presences for the class on [day]
  /// (its `saveIsAllowed` is `false`), as it answers a class without pupils
  /// or a day in the future: then it lists no pupils, and gives its reason
  /// in [refusal].
  bool get refused => pupils.saveIsAllowed == false;

  /// The module's reason for listing no pupils, or for refusing to record
  /// presences for the class on [day] (its `errorMessage`, in Dutch), or
  /// null when it gave none.
  String? get refusal => pupils.errorMessage;

  /// [day] as the module writes it, `yyyy-MM-dd`.
  String get date => PresenceService.formatDate(day);

  /// The pupil with id [pupilId], or null when the class does not list one.
  PresencePupil? pupil(int pupilId) =>
      pupils.where((p) => p.userId == pupilId).firstOrNull;
}

/// Reads class [classId] on [day] with [presence]: the module's
/// configuration (which must list the class), the codes of the class's
/// school structure, and the pupils with their half-days, or the module's
/// reason for listing none.
///
/// Throws a [ToolError] when the configuration does not list the class.
Future<PresenceDay> readPresenceDay(
  PresenceService presence,
  int classId,
  DateTime day,
) async {
  final config = await presence.getConfig();
  final presenceClass = config.classForGroup(classId);
  if (presenceClass == null) {
    throw ToolError(
      'No class with class id $classId is among the classes this account '
      'may view in the Presence module. Take the class id from '
      'list_presence_classes.',
    );
  }
  final structId = presenceClass.structId;
  final codes = structId == null
      ? const <PresenceCode>[]
      : await presence.getAllCodes(structId);
  final pupils = await presence.getClassPupils(
    classGroupId: classId,
    date: day,
    schoolyearRefDate: config.schoolyearRefDate,
  );
  return PresenceDay(
    presenceClass: presenceClass,
    day: day,
    codes: PresenceCodes(codes),
    pupils: pupils,
  );
}
