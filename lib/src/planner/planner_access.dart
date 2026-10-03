import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/message_filter.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'planner_format.dart';

// Reaching Smartschool's planner for the planner tools: the session runner,
// the planner and element ids the tools print and take, the classes and
// period arguments, the school's assignment types, and the planner's own
// errors as ToolErrors.

/// Runs [action] with a [PlannerService] on the session's logged-in client.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; reading
/// the planner is, and so are the library's writes (see
/// `planner_writes.dart`).
///
/// The planner's own errors, which [SmartschoolSession.run] passes on as
/// they are, become [ToolError]s ([plannerToolError]); login and connection
/// failures stay [SmartschoolProblem]s.
Future<T> withPlanner<T>(
  SmartschoolSession session,
  Future<T> Function(PlannerService planner) action,
) => withPlannerClient(session, (client) => action(PlannerService(client)));

/// Runs [action] with the session's logged-in client, for the planner tools
/// that need another service of the library next to the planner (the
/// Lesfiches module's `LessonContentService`), as [withPlanner] does: the
/// errors of the planner and of the Lesfiches module become [ToolError]s
/// ([plannerToolError]).
Future<T> withPlannerClient<T>(
  SmartschoolSession session,
  Future<T> Function(SmartschoolClient client) action,
) async {
  try {
    return await session.run(action);
  } catch (error) {
    final toolError = plannerToolError(error);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of the planner or of
/// [PlannerService]'s checks, or null for anything else.
///
/// - [SmartschoolPlannedElementNotFoundError]: the element is gone, or its
///   id changed (a lesson hour that was filled or cleared gets a new id,
///   dartschool#84).
/// - [SmartschoolPlannerWriteRefusedError]: a check of the library refused
///   a write before sending it (the element is not the user's own, the
///   planner does not allow the change, the lesson hour is no longer
///   empty, ...). The tools say why in their own words, from its reason
///   ([_refused]); the library's message, written for a developer, goes to
///   the log only.
/// - Any other [SmartschoolPlannerError]: an answer the server cannot use.
///   The library's message can quote the planner's answer, so it goes to
///   the log only.
/// - [SmartschoolLessonContentError]: the Lesfiches module, whose lesfiches
///   the planner plans (and reads before it plans one), gave an answer the
///   server cannot use. Likewise to the log only.
/// - [ArgumentError]: the library refused the request before sending it
///   (a malformed id, a reversed period). Not a [RangeError], which is a
///   bug rather than a refused request.
///
/// A write that went out without the planner confirming it
/// ([SmartschoolPlannerSaveUnconfirmedError]) is not a [ToolError]: the
/// write tools report it themselves (`plannerWriteNotConfirmed` in
/// `planner_writes.dart`).
ToolError? plannerToolError(Object error) {
  switch (error) {
    case SmartschoolPlannedElementNotFoundError(
      :final elementType,
      :final platformId,
      :final elementId,
    ):
      final id = PlannedElementRef(elementType, platformId, elementId);
      return ToolError(
        'The planner has no element $id (any more). It was removed, or its '
        'id changed: a lesson hour that is filled or cleared gets a new id. '
        'List the planner again with list_planner and take the id from '
        'there.',
      );
    case SmartschoolPlannerWriteRefusedError():
      log('planner: $error');
      return ToolError(_refused(error));
    case SmartschoolPlannerError(:final statusCode):
      log('planner: $error');
      return ToolError(
        'The planner gave an answer the server could not use'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}. Try again in a '
        'moment; the technical details are in the server log.',
      );
    case SmartschoolLessonContentError(:final statusCode):
      log('lesfiches: $error');
      return ToolError(
        'The Lesfiches module gave an answer the server could not use'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}. Try again in a '
        'moment; the technical details are in the server log.',
      );
    case ArgumentError(:final name, :final message) when error is! RangeError:
      log('planner: $error');
      return ToolError(
        'The planner request was refused before it was sent: '
        '${name == null ? '' : '$name '}$message.',
      );
  }
  return null;
}

/// How the tools start to say that a check of the library refused a write
/// before sending it (a [SmartschoolPlannerWriteRefusedError]), followed by
/// why.
const plannerRefused = 'The planner refused the change before it was sent';

/// Why a check of the library refused a write before sending it ([error]),
/// in the tools' own words: from the error's
/// [SmartschoolPlannerWriteRefusedError.reason] (dartschool#100), naming the
/// element the check read ([SmartschoolPlannerWriteRefusedError.element])
/// with [formatElementSummary], with what to do next.
///
/// The switch has a case for every [PlannerWriteRefusalReason] and no
/// default, so that a reason a later version of the library adds fails the
/// build here rather than reaching Claude unworded. A refusal without a
/// reason (an error made without one) only says that the details are in
/// the server log.
///
/// `plan_assignment` words [PlannerWriteRefusalReason.unknownAssignmentType]
/// itself, with the school's types as they are now, which the error does
/// not carry.
String _refused(SmartschoolPlannerWriteRefusedError error) {
  const lead = plannerRefused;
  const listAgain =
      'List the planner again with list_planner (planner me) to see how it '
      'is now.';
  final element = error.element;
  final the = element == null
      ? 'the element'
      : 'the ${formatElementSummary(element)}';
  final flags = error.capabilityFlags;
  return switch (error.reason) {
    PlannerWriteRefusalReason.notOwn =>
      '$lead: $the is not in your own planner: it is organised by '
          '${_organisers(element)}. Only the elements of your own planner can '
          'be changed, as list_planner (planner me) shows them.',
    PlannerWriteRefusalReason.notAllowed =>
      '$lead: the planner does not let you ${_capabilityVerbs(flags)} $the'
          '${flags.isEmpty ? '' : ': ${_capabilities(flags)} not set'}.',
    PlannerWriteRefusalReason.noLongerASlot =>
      '$lead: the lesson hour is not empty any more: the planner has $the in '
          'its place. $listAgain',
    PlannerWriteRefusalReason.periodChanged =>
      '$lead: the empty lesson hour moved since it was read: it is now $the. '
          '$listAgain',
    PlannerWriteRefusalReason.participantRoles =>
      '$lead: $the has participant roles or group filters, which this server '
          'does not know how to keep when it fills a lesson hour. Fill this '
          'hour in Smartschool itself.',
    PlannerWriteRefusalReason.trashable =>
      '$lead: $the is not a lesson in a lesson hour of the timetable, the '
          'only kind of lesson that is cleared: the planner lets you '
          '${_capabilityVerbs(flags, orElse: 'remove')} it instead'
          '${flags.isEmpty ? '' : ' (${_capabilities(flags)} set)'}. Remove '
          'it in Smartschool itself.',
    PlannerWriteRefusalReason.unknownLessonContent =>
      '$lead: you have no lesfiche with the id given (any more). List your '
          'lesfiches with list_lesfiches and take the id of a lesson lesfiche '
          'from there.',
    PlannerWriteRefusalReason.notALessonLessonContent =>
      '$lead: ${_lesficheKind(error.lessonContent)}, not a lesson lesfiche: '
          'only a lesson lesfiche can be planned into a lesson hour. List the '
          'lesson lesfiches with list_lesfiches and take the id of one from '
          'there.',
    PlannerWriteRefusalReason.unknownAssignmentType =>
      '$lead: the assignment type is no longer one of the school\'s '
          'assignment types: they changed since the server read them.',
    PlannerWriteRefusalReason.linkedEvaluation =>
      '$lead: $the is linked to a Skore evaluation, which has to be unlinked '
          'in Smartschool first: only then can it be moved to the trash.',
    null => '$lead. The technical details are in the server log.',
  };
}

/// Who organises [element]: the names of its organising users, or
/// `someone else` when it names none.
String _organisers(PlannedElement? element) {
  final names = element == null ? '' : elementOrganisers(element);
  return names.isEmpty ? 'someone else' : names;
}

/// What the planner's capability flags allow, by the flag's name.
const _capabilityVerb = {
  'canUserReplace': 'fill',
  'canUserEdit': 'change',
  'canUserRename': 'rename',
  'canUserChangePublicInfo': 'change the public info of',
  'canUserChangePrivateInfo': 'change the private info of',
  'canUserTrash': 'trash',
  'canUserDelete': 'delete',
};

/// What [flags], capability flags of the planner, allow: `fill`, `trash or
/// delete`; [orElse] when none of them is a flag the server knows.
String _capabilityVerbs(List<String> flags, {String orElse = 'change'}) {
  final verbs = [for (final flag in flags) ?_capabilityVerb[flag]];
  if (verbs.isEmpty) return orElse;
  return verbs.length == 1
      ? verbs.single
      : '${verbs.sublist(0, verbs.length - 1).join(', ')} or ${verbs.last}';
}

/// `its capability canUserReplace is`, `its capabilities canUserTrash and
/// canUserDelete are`: the planner's names of [flags], for a sentence that
/// says whether they are set.
String _capabilities(List<String> flags) => flags.length == 1
    ? 'its capability ${flags.single} is'
    : 'its capabilities ${flags.sublist(0, flags.length - 1).join(', ')} '
          'and ${flags.last} are';

/// What kind of lesfiche [item] is, a lesfiche that is not a lesson one:
/// `the lesfiche "Taak: een eigen spel" is an assignment lesfiche`.
String _lesficheKind(LessonContentItem? item) {
  if (item == null) return 'the lesfiche given is of another kind';
  final name = item.name.trim();
  final lesfiche = name.isEmpty
      ? 'the lesfiche ${item.id}'
      : 'the lesfiche "$name"';
  return item.type == LessonContentType.assignment
      ? '$lesfiche is an assignment lesfiche'
      : '$lesfiche is of the kind "${item.typeName}"';
}

/// A planner as the planner tools name it: `me`, the user's own planner, or
/// a [calendar] as `search_planners` prints it ([formatPlannerId]).
final class PlannerRef {
  /// The user's own planner.
  const PlannerRef.me() : calendar = null;

  /// The planner [calendar].
  const PlannerRef.of(PlannerCalendar this.calendar);

  /// The calendar named, or null for [PlannerRef.me].
  final PlannerCalendar? calendar;

  bool get isMe => calendar == null;

  /// The calendar to read: [calendar], or for [PlannerRef.me] the user's
  /// own ([PlannerService.ownCalendar]).
  Future<PlannerCalendar> resolve(PlannerService planner) async =>
      calendar ?? await planner.ownCalendar();

  /// [value], the argument [name] of a tool: `me` (also when absent or
  /// empty), or a planner id such as `group/4069_4256`.
  ///
  /// Throws a [ToolError] naming the expected forms for anything else, so
  /// that it never goes into a request.
  static PlannerRef parse(Object? value, {String name = 'planner'}) {
    final text = value is String ? value.trim() : null;
    if (value == null || text == '' || text?.toLowerCase() == 'me') {
      return const PlannerRef.me();
    }
    if (text != null) {
      final slash = text.indexOf('/');
      final kind = slash < 0 ? null : text.substring(0, slash).toLowerCase();
      for (final type in PlannerCalendarType.values) {
        if (type.wireName != kind) continue;
        try {
          return PlannerRef.of(
            PlannerCalendar(type, text.substring(slash + 1)),
          );
        } on ArgumentError {
          break;
        }
      }
    }
    throw ToolError(
      '$name must be me (your own planner) or a planner id as '
      'search_planners shows it, like user/4069_218_0 (a person), '
      'group/4069_4256 (a class) or location/4069_<id> (a room); '
      '${value is String ? '"$value"' : '$value'} is not.',
    );
  }

  @override
  String toString() => calendar == null ? 'me' : formatPlannerId(calendar!);
}

/// The planner id of [calendar] as the tools print and take it:
/// `user/4069_218_0`, `group/4069_4256`, `location/4069_<id>`.
String formatPlannerId(PlannerCalendar calendar) =>
    '${calendar.type.wireName}/${calendar.id}';

/// [value], the list argument [name] of a tool, as the planners of 1 to
/// [max] classes: planner ids as `search_planners` prints them, like
/// `group/4069_4256`. Without duplicates, in the order given.
///
/// Throws a [ToolError] that says what to fix for an empty list, more than
/// [max] classes, or an item that is not the planner id of a class (`me`, a
/// person's or a room's planner, a class name), so that it never goes into a
/// request.
List<PlannerCalendar> classPlannersArgument(
  Object? value, {
  required String name,
  required int max,
}) {
  final classes = <PlannerCalendar>[];
  final items = switch (value) {
    final List<Object?> items => items,
    null => const <Object?>[],
    _ => [value],
  };
  for (final item in items) {
    final calendar = _classPlanner(item);
    if (calendar == null) {
      throw ToolError(
        'each item of $name must be the planner id of a class as '
        'search_planners shows it, like group/4069_4256; '
        '${item is String ? '"$item"' : '$item'} is not.',
      );
    }
    if (!classes.contains(calendar)) classes.add(calendar);
  }
  if (classes.isEmpty) {
    throw ToolError(
      '$name is empty: pass the planner ids of the classes, as '
      'search_planners shows them (like group/4069_4256).',
    );
  }
  if (classes.length > max) {
    throw ToolError(
      '$name holds ${classes.length} classes, and at most $max fit in one '
      'call: ask for the others in another call.',
    );
  }
  return classes;
}

/// The class planner [item] names, or null when it names none.
PlannerCalendar? _classPlanner(Object? item) {
  // An empty text would be "me".
  if (item is! String || item.trim().isEmpty) return null;
  try {
    final calendar = PlannerRef.parse(item).calendar;
    return calendar?.type == PlannerCalendarType.group ? calendar : null;
  } on ToolError {
    return null;
  }
}

/// The school's assignment types (such as `KO Kleine Overhoring`), read once
/// per session: the planner tools name them, and the planning of an
/// assignment takes one.
final class AssignmentTypes {
  AssignmentTypes._();

  static final _ofSession = Expando<AssignmentTypes>();

  /// The assignment types of the school [session] logs in to, shared by
  /// every tool on that session.
  factory AssignmentTypes.of(SmartschoolSession session) =>
      _ofSession[session] ??= AssignmentTypes._();

  Future<List<PlannerAssignmentType>>? _types;

  /// The school's types ([PlannerService.getAssignmentTypes]), in the order
  /// the planner gives them: read with [planner] on the first call, and
  /// from memory after that. Calls at the same time share one read; a read
  /// that failed is tried again on the next call.
  Future<List<PlannerAssignmentType>> read(PlannerService planner) async {
    final pending = _types ??= planner.getAssignmentTypes();
    try {
      return await pending;
    } catch (_) {
      if (identical(_types, pending)) _types = null;
      rethrow;
    }
  }

  /// The school's types read again with [planner], for when they changed
  /// since [read] read them: the library refused a type as not one of the
  /// school's ([PlannerWriteRefusalReason.unknownAssignmentType]). Every
  /// tool on the session then gets the types as they are now.
  ///
  /// The library read the types itself for that check, but its error does
  /// not carry them (yvanvds/dartschool#119), so they are read once more: a
  /// workaround, whose removal is tracked in #89.
  Future<List<PlannerAssignmentType>> reread(PlannerService planner) {
    _types = null;
    return read(planner);
  }
}

/// An element of the planner as the tools name it: its type, platform and
/// id, which the library needs to read it, as one compound id
/// `<plannedElementType>/<platformId>/<id>`, such as
/// `planned-lessons/4069/225c0b54-…`.
final class PlannedElementRef {
  const PlannedElementRef(this.typeName, this.platformId, this.id);

  /// The id of [element].
  PlannedElementRef.of(PlannedElement element)
    : this(element.typeName, element.platformId, element.id);

  /// The planner's name of the element's type (`planned-lessons`).
  final String typeName;

  /// The platform (school) of the element.
  final int platformId;

  /// The element's own id (a UUID).
  final String id;

  static final _typeName = RegExp(r'^planned(?:-[a-z]+)+$');
  static final _platformId = RegExp(r'^\d{1,9}$');
  static final _id = RegExp(r'^[0-9A-Za-z][0-9A-Za-z_-]*$');

  /// [value], the argument [name] of a tool, as an element id like
  /// `planned-lessons/4069/225c0b54-…`. A leading `id `, as the tools print
  /// it, is allowed.
  ///
  /// Throws a [ToolError] naming the expected form for anything else, so
  /// that it never goes into a request.
  static PlannedElementRef parse(Object? value, {String name = 'id'}) {
    var text = value is String ? value.trim() : '';
    if (text.toLowerCase().startsWith('id ')) text = text.substring(3).trim();
    final parts = text.split('/');
    if (parts case [final type, final platform, final id]
        when _typeName.hasMatch(type) &&
            _platformId.hasMatch(platform) &&
            _id.hasMatch(id)) {
      return PlannedElementRef(type, int.parse(platform), id);
    }
    throw ToolError(
      '$name must be the id of a planner element as list_planner shows it: '
      'its type, platform and id, like '
      'planned-lessons/4069/225c0b54-0000-4000-8000-000000000000; '
      '${value is String ? '"$value"' : '$value'} is not.',
    );
  }

  /// The element's type; [PlannedElementType.other] for one the library
  /// does not know.
  PlannedElementType get type => PlannedElementType.fromWire(typeName);

  /// Reads the element's detail, by its [typeName]: also an element of a
  /// type the library does not know ([PlannedElementType.other]).
  Future<PlannedElementDetail> read(PlannerService planner) => planner
      .getPlannedElement(typeName: typeName, platformId: platformId, id: id);

  @override
  bool operator ==(Object other) =>
      other is PlannedElementRef &&
      other.typeName == typeName &&
      other.platformId == platformId &&
      other.id.toLowerCase() == id.toLowerCase();

  @override
  int get hashCode => Object.hash(typeName, platformId, id.toLowerCase());

  @override
  String toString() => '$typeName/$platformId/$id';
}

/// The `from` and `until` arguments of a planner tool: the period to read.
///
/// Each is a date like `2026-10-05` or a date and time like `2026-10-05
/// 14:30` ([parseDateArgument]): `from` a date from its start, `until` a
/// date to its end. `from` defaults to the start of today ([now]), `until`
/// to the end of the day [days] days after `from`.
///
/// Throws a [ToolError] for an invalid date, or when until is before from.
({DateTime from, DateTime until}) plannerPeriodArguments(
  Map<String, Object?> arguments, {
  required int days,
  DateTime Function() now = DateTime.now,
}) {
  final from = switch (arguments['from']) {
    final String from when from.trim().isNotEmpty => parseDateArgument(
      'from',
      from,
    ),
    _ => _startOfDay(now()),
  };
  final until = switch (arguments['until']) {
    final String until when until.trim().isNotEmpty => parseDateArgument(
      'until',
      until,
      endOfDay: true,
    ),
    _ => DateTime(from.year, from.month, from.day + days, 23, 59, 59),
  };
  if (until.isBefore(from)) {
    throw ToolError(
      'until must not be before from'
      '${arguments['from'] is String ? '' : ' (today when it is not given)'}.',
    );
  }
  return (from: from, until: until);
}

DateTime _startOfDay(DateTime time) =>
    DateTime(time.year, time.month, time.day);
