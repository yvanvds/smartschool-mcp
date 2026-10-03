import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/planner_format.dart';
import '../problems.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import 'presence_access.dart';
import 'presence_format.dart';

// Recording half-day presences, for `set_pupils_late` and
// `set_pupils_present` (#47), on the library's `setLate` and `setPresent`.
//
// A half-day is an official record, so the server guards every change
// itself; the library saves over whatever the half-day holds and returns
// nothing (yvanvds/dartschool#105, a workaround; its removal is #76):
//
// - Before anything is sent: a date in the future, a class the account may
//   not record presences for (`userCanRecord`), a grouping class without a
//   school structure, and a pupil who is not listed or whose half-day holds
//   another status than nothing, "Aanwezig", "Te laat" or "Te laat zonder
//   geldige reden" are refused, for the whole call.
// - Before each pupil's save, in the same session action: the class is read
//   again, and a half-day that changed to another status meanwhile is
//   refused ([_stillChangeable]). A pupil who already has the status (and
//   the motivation) is left alone: nothing is saved for them.
// - The pupils are changed one after the other, and the change stops at the
//   first that fails.
// - After the saves, the class is read once more, and the result says per
//   pupil what the half-day holds now.
//
// Repeating a session action, as [SmartschoolSession.run] does when
// Smartschool refused the session, reads the class again and saves the same
// status again: it cannot change a half-day twice, nor overwrite another
// status.

/// At most this many pupils per call: more than a class has.
const maxPresencePupils = 50;

/// What a Presence write tool adds to an error that came before anything
/// was saved.
const nothingChangedInPresences = 'Nothing was changed in Smartschool.';

/// The status a write sets.
enum PresenceTarget {
  /// "Te laat" ([PresenceService.setLate]).
  late(PresenceKind.late, PresenceService.lateCodeName),

  /// "Te laat zonder geldige reden" ([PresenceService.setLate] with
  /// `withoutValidReason`).
  lateWithoutReason(
    PresenceKind.lateWithoutReason,
    PresenceService.lateWithoutReasonAliasName,
  ),

  /// "Aanwezig" ([PresenceService.setPresent]).
  present(PresenceKind.present, PresenceService.presentCodeName);

  const PresenceTarget(this.kind, this.status);

  /// What a half-day holds once it is set.
  final PresenceKind kind;

  /// The name of the status, as the school's codes have it.
  final String status;

  /// Whether the codes of a class hold the status.
  bool among(PresenceCodes codes) => switch (this) {
    late => codes.late != null,
    lateWithoutReason => codes.lateWithoutReason != null,
    present => codes.present != null,
  };
}

/// The `pupil_ids` argument of the write tools.
Schema presencePupilIdsSchema() => Schema.list(
  description:
      'The pupil ids, from list_class_presences: all pupils the user '
      'confirmed, at most $maxPresencePupils.',
  items: Schema.int(minimum: 1),
  minItems: 1,
  maxItems: maxPresencePupils,
);

/// The `date` argument of the write tools.
Schema presenceWriteDateSchema() => Schema.string(
  description:
      'The day, like 2026-10-05: today or an earlier day, never a day in the '
      'future. Smartschool time (Belgium).',
);

/// The `part` argument of the write tools.
Schema presencePartSchema() => UntitledSingleSelectEnumSchema(
  description: 'The half-day: morning or afternoon.',
  values: [for (final part in DayPart.values) part.name],
);

/// The `motivation` argument of the write tools.
Schema presenceMotivationSchema() => Schema.string(
  description:
      'Optional: a short note stored with the status, as confirmed by the '
      'user. It replaces the motivation the half-day has. Without it, a '
      'half-day that changes gets none, and a pupil who already has the '
      'status keeps theirs.',
  maxLength: 500,
);

/// The half-day the `part` argument names; the input schema guarantees one
/// of the names.
DayPart presencePartArgument(Map<String, Object?> arguments) =>
    DayPart.values.byName(arguments['part'] as String);

/// The `motivation` argument, trimmed; null when it is not given.
String? presenceMotivationArgument(Map<String, Object?> arguments) =>
    (arguments['motivation'] as String?)?.trim();

/// What happened to one pupil of a write.
sealed class _Step {
  const _Step();
}

/// Saved.
final class _Changed extends _Step {
  const _Changed(this.before);

  /// What the half-day held when the server read it right before the save.
  final PresenceHalfDay? before;
}

/// The pupil already had the status (and the motivation): nothing saved.
final class _Unchanged extends _Step {
  const _Unchanged();
}

/// Refused right before the save: nothing saved, and the write stops.
final class _Refused extends _Step {
  const _Refused(this.reason);

  final String reason;
}

/// Failed: refused by the module, or a login or connection failure. The
/// write stops.
final class _Failed extends _Step {
  const _Failed(this.reason, {required this.maybeSaved});

  final String reason;

  /// Whether the save may have gone out (a login or connection failure).
  final bool maybeSaved;
}

/// After the pupil that stopped the write.
final class _NotTried extends _Step {
  const _NotTried();
}

/// Sets [target] for the [part] of [day] for the pupils [pupilIds] of class
/// [classId], with [motivation] (null: not given), and returns the result of
/// [tool]. [today] is the day it is now, in the time of this PC.
///
/// Refuses the whole call, before anything is sent, with a [ToolError] that
/// says nothing was changed: see the comment at the top of this file. Then
/// changes one pupil after the other, each in a session action of its own,
/// stops at the first that fails, reads the class again, and says per pupil
/// what was done and what the half-day holds now. The result is an error
/// when the change stopped, or when the class read afterwards does not show
/// what was saved.
Future<CallToolResult> changePresences(
  SmartschoolSession session, {
  required String tool,
  required int classId,
  required List<int> pupilIds,
  required DateTime day,
  required DayPart part,
  required PresenceTarget target,
  required String? motivation,
  required DateTime today,
}) async {
  if (day.isAfter(today)) {
    throw ToolError(
      'The date ${formatPlannerDay(day)} is in the future: presences are '
      'recorded for today or an earlier day. $nothingChangedInPresences',
    );
  }
  final services = PresenceServices();
  final read = await _withPresenceWrite(session, (presence) async {
    // The class first: a class the account may not record for is refused
    // without reading its pupils.
    final config = await presence.getConfig();
    if (config.classForGroup(classId) case final presenceClass?) {
      _refuseClass(presenceClass);
    }
    return readPresenceDay(presence, classId, day);
  }, services);
  _refuseBeforeSending(tool, read, pupilIds, part, target);

  final steps = <int, _Step>{};
  int? stoppedAt;
  for (final pupilId in pupilIds) {
    if (stoppedAt != null) {
      steps[pupilId] = const _NotTried();
      continue;
    }
    final step = await _changeOne(
      session,
      services,
      classId: classId,
      pupilId: pupilId,
      day: day,
      part: part,
      target: target,
      motivation: motivation,
      name: formatPresencePupil(read.pupil(pupilId)!),
    );
    steps[pupilId] = step;
    if (step is _Refused || step is _Failed) stoppedAt = pupilId;
  }

  // What the half-days hold now: the library does not read a save back.
  PresenceDay? after;
  String? afterProblem;
  try {
    after = await withPresence(
      session,
      (presence) => readPresenceDay(presence, classId, day),
      services: services,
    );
  } on ToolError catch (error) {
    afterProblem = error.message;
  } on SmartschoolProblem catch (problem) {
    afterProblem = problem.message;
  }

  return _result(
    read: read,
    after: after,
    afterProblem: afterProblem,
    steps: steps,
    stoppedAt: stoppedAt,
    part: part,
    target: target,
    motivation: motivation,
  );
}

/// [withPresence] for a read before anything is sent: a [ToolError] says
/// that nothing was changed.
Future<T> _withPresenceWrite<T>(
  SmartschoolSession session,
  Future<T> Function(PresenceService presence) action,
  PresenceServices services,
) async {
  try {
    return await withPresence(session, action, services: services);
  } on ToolError catch (error) {
    throw ToolError('${error.message} $nothingChangedInPresences');
  }
}

/// Refuses, with a [ToolError], a class whose presences the account may not
/// record: one it may only view (`userCanRecord`), and a grouping class
/// without a school structure.
void _refuseClass(PresenceClassRef presenceClass) {
  final named = formatPresenceClassName(presenceClass);
  if (!presenceClass.userCanRecord) {
    throw ToolError(
      'This account may not record presences for $named: the Presence '
      'module lets it view the class only. Ask the school\'s Smartschool '
      'administrator for the right to record presences for it.',
    );
  }
  if (presenceClass.structId == null) {
    throw ToolError(
      '${capitalized(named)} is a grouping class without a school '
      "structure: presences are recorded in the pupils' official class. Find "
      'it with list_presence_classes.',
    );
  }
}

/// Refuses the call of [tool] with a [ToolError] when [read], the class
/// before anything was sent, does not allow setting [target] for the [part]
/// of the pupils [pupilIds].
void _refuseBeforeSending(
  String tool,
  PresenceDay read,
  List<int> pupilIds,
  DayPart part,
  PresenceTarget target,
) {
  final named = formatPresenceClassName(read.presenceClass);
  if (!target.among(read.codes)) {
    throw ToolError(
      'The presence codes of $named have no "${target.status}", so $tool '
      'cannot set it there. $nothingChangedInPresences',
    );
  }
  final problems = <String>[];
  for (final pupilId in pupilIds) {
    final pupil = read.pupil(pupilId);
    if (pupil == null) {
      problems.add(
        '- pupil id $pupilId is not listed in the class on that day.',
      );
      continue;
    }
    final cell = _cell(pupil, part, read.date);
    if (!read.codes.kindOf(cell).changeable) {
      problems.add(
        '- ${formatPresencePupil(pupil)}: the ${formatDayPart(part)} holds '
        '${read.codes.describe(cell)}.',
      );
    }
  }
  if (problems.isEmpty) return;
  throw ToolError(
    [
      '$nothingChangedInPresences $tool only changes a half-day that holds '
          '$changeablePresences, and never overwrites another status, such as '
          'an absence the secretariat recorded. In $named, on the '
          '${formatDayPart(part)} of ${formatPlannerDay(read.day)}:',
      ...problems,
      'Read the class with list_class_presences. Leave those pupils out (and '
          'call again with the others, as the user confirmed), or let the '
          'user change their half-day in Smartschool.',
    ].join('\n'),
  );
}

/// The half-day [part] of [pupil] on [date] (`yyyy-MM-dd`), or null.
PresenceHalfDay? _cell(PresencePupil pupil, DayPart part, String date) =>
    pupil.halfDayFor(part, date: date);

/// Sets [target] for pupil [pupilId] ([name], for the messages) in a session
/// action of its own: reads the class again, refuses a half-day that changed
/// meanwhile ([_stillChangeable]), leaves a pupil who already has the status
/// alone, and saves.
Future<_Step> _changeOne(
  SmartschoolSession session,
  PresenceServices services, {
  required int classId,
  required int pupilId,
  required DateTime day,
  required DayPart part,
  required PresenceTarget target,
  required String? motivation,
  required String name,
}) async {
  try {
    return await runPresence(session, (presence) async {
      final now = await readPresenceDay(presence, classId, day);
      final pupil = now.pupil(pupilId);
      if (_stillChangeable(now, pupil, part, name) case final reason?) {
        return _Refused(reason);
      }
      final before = _cell(pupil!, part, now.date);
      if (now.codes.kindOf(before) == target.kind &&
          (motivation == null || motivation == before?.motivation.trim())) {
        return const _Unchanged();
      }
      switch (target) {
        case PresenceTarget.present:
          await presence.setPresent(
            userId: pupilId,
            classGroupId: classId,
            date: day,
            part: part,
            motivation: motivation ?? '',
          );
        case PresenceTarget.late || PresenceTarget.lateWithoutReason:
          await presence.setLate(
            userId: pupilId,
            classGroupId: classId,
            date: day,
            part: part,
            withoutValidReason: target == PresenceTarget.lateWithoutReason,
            motivation: motivation ?? '',
          );
      }
      return _Changed(before);
    }, services: services);
  } on SmartschoolPresenceError catch (error) {
    log('presence: $error');
    return _Failed(
      "Smartschool's Presence module refused the change for $name, or a "
      'read right before it; the technical details are in the server log.',
      maybeSaved: false,
    );
  } on ToolError catch (error) {
    return _Failed(error.message, maybeSaved: false);
  } on SmartschoolProblem catch (problem) {
    return _Failed(
      '${problem.message} The half-day of $name may or may not have been '
      'saved: see what it holds now.',
      maybeSaved: true,
    );
  }
}

/// Why the half-day [part] of [pupil] ([name]), as read right before its
/// save in [now], may no longer be changed: the pupil is no longer listed,
/// or the half-day changed to another status since the read before anything
/// was sent. Null when it may be changed.
///
/// The library saves over whatever the half-day holds
/// (yvanvds/dartschool#105, a workaround; its removal is #76).
String? _stillChangeable(
  PresenceDay now,
  PresencePupil? pupil,
  DayPart part,
  String name,
) {
  if (pupil == null) {
    return '$name is no longer listed in the class on that day.';
  }
  final cell = _cell(pupil, part, now.date);
  if (now.codes.kindOf(cell).changeable) return null;
  return 'The ${formatDayPart(part)} of $name changed meanwhile: it now '
      'holds ${now.codes.describe(cell)}, which the server never overwrites.';
}

/// The result of a write: a heading, a line per pupil with what was done
/// and what the half-day holds now ([after], null when [afterProblem] kept
/// it from being read), and why the write stopped.
CallToolResult _result({
  required PresenceDay read,
  required PresenceDay? after,
  required String? afterProblem,
  required Map<int, _Step> steps,
  required int? stoppedAt,
  required DayPart part,
  required PresenceTarget target,
  required String? motivation,
}) {
  final status = '"${target.status}"';
  final withMotivation = switch (motivation) {
    null => '',
    '' => ' without a motivation',
    final text => ' with motivation "$text"',
  };
  final where =
      'the ${formatDayPart(part)} of ${formatPlannerDay(read.day)} in '
      '${formatPresenceClassName(read.presenceClass)}';
  final changed = steps.values.whereType<_Changed>().isNotEmpty;
  String name(int pupilId) => formatPresencePupil(read.pupil(pupilId)!);

  var unconfirmed = false;
  final lines = <String>[];
  for (final MapEntry(key: pupilId, value: step) in steps.entries) {
    final pupilNow = after?.pupil(pupilId);
    final cell = pupilNow == null ? null : _cell(pupilNow, part, after!.date);
    final done = switch (step) {
      _Changed(:final before) => 'set (was ${read.codes.describe(before)})',
      _Unchanged() => 'already had it; nothing saved',
      _Refused() => 'not changed (see below)',
      _Failed(maybeSaved: true) => 'may or may not have been saved (see below)',
      _Failed() => 'not changed (see below)',
      _NotTried() => 'not tried',
    };
    final now = switch ((after, pupilNow)) {
      (null, _) => '',
      (_?, null) => '; no longer listed in the class',
      (final after?, _?) => '; now: ${after.codes.describe(cell)}',
    };
    final saved = step is _Changed || (step is _Failed && step.maybeSaved);
    final asSaved =
        pupilNow != null &&
        after!.codes.kindOf(cell) == target.kind &&
        (motivation == null || motivation == cell?.motivation.trim());
    final String mark;
    if (step is _Changed && after != null && !asSaved) {
      unconfirmed = true;
      mark = ' (NOT what was saved)';
    } else {
      mark = saved && after == null ? ' (not confirmed)' : '';
    }
    lines.add('- ${name(pupilId)}: $done$now$mark');
  }

  final heading = switch (stoppedAt) {
    final pupilId? =>
      'Setting $status$withMotivation for $where stopped at ${name(pupilId)}:',
    null when changed => 'Set $status$withMotivation for $where:',
    null =>
      'Nothing changed in Smartschool: these pupils already had $status for '
          '$where${motivation == null ? '' : ' with that motivation'}, so '
          'nothing was saved:',
  };
  final why = switch (stoppedAt == null ? null : steps[stoppedAt]) {
    _Refused(:final reason) => '$reason Nothing was saved for them.',
    _Failed(:final reason) => reason,
    _ => null,
  };
  final untried = steps.values.whereType<_NotTried>().isNotEmpty;
  final afterNote = switch ((after, afterProblem)) {
    (null, final problem?) when changed || stoppedAt != null =>
      'Reading the class again afterwards failed, so what the half-days hold '
          'now is not confirmed: $problem Read the class with '
          'list_class_presences and tell the user what it shows.',
    _ => null,
  };
  return CallToolResult(
    isError: stoppedAt != null || unconfirmed || afterNote != null,
    content: [
      TextContent(
        text: [
          heading,
          ...lines,
          ?why,
          if (untried) 'The pupils listed after them were not tried.',
          if (unconfirmed)
            'Smartschool does not show what was saved for the pupils marked '
                '"NOT what was saved": read the class with '
                'list_class_presences and tell the user what it shows.',
          ?afterNote,
        ].join('\n'),
      ),
    ],
  );
}
