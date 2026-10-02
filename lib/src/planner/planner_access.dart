import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/message_filter.dart';
import '../session.dart';
import '../tools/server_tool.dart';

// Reaching Smartschool's planner for the planner tools: the session runner,
// the planner and element ids the tools print and take, the period
// arguments, and the planner's own errors as ToolErrors.

/// Runs [action] with a [PlannerService] on the session's logged-in client.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; reading
/// the planner is.
///
/// The planner's own errors, which [SmartschoolSession.run] passes on as
/// they are, become [ToolError]s ([plannerToolError]); login and connection
/// failures stay [SmartschoolProblem]s.
Future<T> withPlanner<T>(
  SmartschoolSession session,
  Future<T> Function(PlannerService planner) action,
) async {
  try {
    return await session.run((client) => action(PlannerService(client)));
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
/// - Any other [SmartschoolPlannerError]: an answer the server cannot use.
///   The library's message can quote the planner's answer, so it goes to
///   the log only.
/// - [ArgumentError]: the library refused the request before sending it
///   (a malformed id, a reversed period). Not a [RangeError], which is a
///   bug rather than a refused request.
///
/// The planner writes (#53, #55) add their own cases in front of the
/// [SmartschoolPlannerError] one: a refused write is one too.
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
    case SmartschoolPlannerError(:final statusCode):
      log('planner: $error');
      return ToolError(
        'The planner gave an answer the server could not use'
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

  /// Reads the element's detail.
  ///
  /// An element of a type the library does not know is read with
  /// [PlannerService.getDetail], which takes an element: one with only the
  /// type, platform and id that the request needs. A workaround until the
  /// library reads an element by its type name (yvanvds/dartschool#99); its
  /// removal is #70.
  Future<PlannedElementDetail> read(PlannerService planner) {
    final type = this.type;
    if (type != PlannedElementType.other) {
      return planner.getPlannedElement(
        type: type,
        platformId: platformId,
        id: id,
      );
    }
    final unknown = DateTime.fromMillisecondsSinceEpoch(0);
    return planner.getDetail(
      PlannedElement(
        id: id,
        platformId: platformId,
        type: type,
        typeName: typeName,
        period: PlannerPeriod(from: unknown, to: unknown),
      ),
    );
  }

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
