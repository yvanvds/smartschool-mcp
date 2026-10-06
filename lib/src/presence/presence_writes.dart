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
// A half-day is an official record, so every change is guarded:
//
// - Before anything is sent, the server reads the class once and refuses,
//   for the whole call: a date in the future, a class the account may not
//   record presences for ([mayRecordHalfDays]), a grouping class without a
//   school structure (naming the official class of each pupil asked for, to
//   call instead, #110), a class or day the module refuses to record
//   presences for (its `saveIsAllowed` and reason, yvanvds/dartschool#104),
//   and a pupil who is not listed or whose half-day holds another status
//   than nothing, "Aanwezig", "Te laat" or "Te laat zonder geldige reden". A
//   pupil who already has the status (and the motivation) is left alone:
//   nothing is saved for them.
// - The pupils are changed one after the other, and the change stops at the
//   first that fails. The library reads the class right before each save
//   and refuses a half-day that holds another status than those
//   ([changeablePresenceNames] as its `onlyReplacing`, dartschool#105): one
//   that changed meanwhile is not overwritten. It also refuses a pupil that
//   read no longer lists (dartschool#116), without sending anything.
// - The result says per pupil what the half-day holds now, as the module
//   answered the save (the library returns it, dartschool#105). The class is
//   read once more only when the change stopped, or when a save's answer
//   does not show the status.
//
// Repeating a session action, as [SmartschoolSession.run] does when
// Smartschool refused the session, makes the library read the class again
// and save the same status again: it cannot change a half-day twice, nor
// overwrite another status.

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

  /// Whether [cell] holds the status, named with [codes], and [motivation]
  /// when one is given (null: any motivation).
  bool heldBy(PresenceHalfDay? cell, PresenceCodes codes, String? motivation) =>
      codes.kindOf(cell) == kind &&
      (motivation == null || motivation == cell?.motivation.trim());
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
  const _Changed(this.saved, {required this.readBefore});

  /// The half-day as the module answered the save, with what it held right
  /// before ([PresenceSavedHalfDay.before]); null when the answer held no
  /// record of it.
  final PresenceSavedHalfDay? saved;

  /// What the half-day held when the server read the class before anything
  /// was sent.
  final PresenceHalfDay? readBefore;

  /// What the half-day held right before the save, as the library read it;
  /// [readBefore] when the save's answer held no record.
  PresenceHalfDay? get before => switch (saved) {
    final saved? => saved.before,
    null => readBefore,
  };
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
/// stops at the first that fails, and says per pupil what was done and what
/// the half-day holds now. The result is an error when the change stopped,
/// or when Smartschool does not show what was saved.
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
    // The class first: a class the account may only view is refused without
    // reading its pupils. A grouping class is read, for the official class
    // of each pupil asked for (_refuseGroupingClass).
    final config = await presence.getConfig();
    if (config.classForGroup(classId) case final presenceClass?) {
      _refuseViewOnly(presenceClass);
    }
    return readPresenceDay(presence, classId, day);
  }, services);
  _refuseGroupingClass(tool, read, pupilIds);
  _refuseBeforeSending(tool, read, pupilIds, part, target);

  final steps = <int, _Step>{};
  int? stoppedAt;
  for (final pupilId in pupilIds) {
    if (stoppedAt != null) {
      steps[pupilId] = const _NotTried();
      continue;
    }
    final readBefore = _cell(read.pupil(pupilId)!, part, read.date);
    if (target.heldBy(readBefore, read.codes, motivation)) {
      steps[pupilId] = const _Unchanged();
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
      readBefore: readBefore,
      codes: read.codes,
      name: formatPresencePupil(read.pupil(pupilId)!),
    );
    steps[pupilId] = step;
    if (step is _Refused || step is _Failed) stoppedAt = pupilId;
  }

  // The class is read once more only when the save answers do not tell
  // what every half-day holds now: one holds no record of the half-day, or
  // another status.
  final confirmed = steps.values.every(
    (step) => switch (step) {
      _Changed(:final saved?) => target.heldBy(saved, read.codes, motivation),
      _Changed() => false,
      _ => true,
    },
  );
  PresenceDay? after;
  String? afterProblem;
  if (stoppedAt != null || !confirmed) {
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

/// Refuses, with a [ToolError], a class whose presences the account may
/// only view ([mayRecordHalfDays]).
void _refuseViewOnly(PresenceClassRef presenceClass) {
  if (mayRecordHalfDays(presenceClass)) return;
  throw ToolError(
    'This account may not record presences for '
    '${formatPresenceClassName(presenceClass)}: the Presence module lets it '
    "view the class only. Ask the school's Smartschool administrator for the "
    'right to record presences for it.',
  );
}

/// Refuses the call of [tool] with a [ToolError] when [read] is a grouping
/// class without a school structure: presences are recorded in the pupils'
/// official classes, and the library's `setLate` and `setPresent` refuse a
/// grouping class too. The error names the official class of each of the
/// pupils [pupilIds] as the class read lists them
/// ([PresencePupil.officialClassId], [formatOfficialClass]), so that Claude
/// can call [tool] with it instead, without searching the school's classes
/// by name (#110).
void _refuseGroupingClass(String tool, PresenceDay read, List<int> pupilIds) {
  if (read.presenceClass.structId != null) return;
  throw ToolError(
    [
      '${capitalized(formatPresenceClassName(read.presenceClass))} is a '
          'grouping class without a school structure: presences are recorded '
          "in the pupils' official class, not here. Call $tool with the "
          'official class of the pupils instead, one call per class:',
      for (final pupilId in pupilIds)
        switch (read.pupil(pupilId)) {
          final pupil? =>
            '- ${formatPresencePupil(pupil)}: '
                '${formatOfficialClass(pupil, read.config)}',
          null => '- pupil id $pupilId: not listed in the class on that day',
        },
      nothingChangedInPresences,
    ].join('\n'),
  );
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
  if (read.refused) {
    // The module's own refusal of the class on that day
    // (yvanvds/dartschool#104), such as a class without pupils.
    final why = switch (read.refusal) {
      final reason? => ': ${formatModuleReason(reason)}',
      null => ', and gives no reason.',
    };
    throw ToolError(
      'The Presence module refuses to record presences for $named on '
      '${formatPlannerDay(read.day)}$why $nothingChangedInPresences',
    );
  }
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
/// action of its own, with the library's `setLate` or `setPresent`, which
/// read the class right before the save and refuse a half-day that holds
/// another status than [changeablePresenceNames], such as one that changed
/// since the read before anything was sent ([readBefore]), and a pupil the
/// class no longer lists on that day. [codes] name what it holds.
///
/// Their refusal of a class without `userCanConfirm`
/// (`SmartschoolPresenceNoConfirmRightError`) does not arise here: the
/// server refused such a class before anything was sent, and the library
/// goes by the configuration that read kept ([PresenceServices]).
Future<_Step> _changeOne(
  SmartschoolSession session,
  PresenceServices services, {
  required int classId,
  required int pupilId,
  required DateTime day,
  required DayPart part,
  required PresenceTarget target,
  required String? motivation,
  required PresenceHalfDay? readBefore,
  required PresenceCodes codes,
  required String name,
}) async {
  try {
    final saved = await runPresence(
      session,
      (presence) => switch (target) {
        PresenceTarget.present => presence.setPresent(
          userId: pupilId,
          classGroupId: classId,
          date: day,
          part: part,
          motivation: motivation ?? '',
          onlyReplacing: changeablePresenceNames,
        ),
        PresenceTarget.late ||
        PresenceTarget.lateWithoutReason => presence.setLate(
          userId: pupilId,
          classGroupId: classId,
          date: day,
          part: part,
          withoutValidReason: target == PresenceTarget.lateWithoutReason,
          motivation: motivation ?? '',
          onlyReplacing: changeablePresenceNames,
        ),
      },
      services: services,
    );
    return _Changed(saved, readBefore: readBefore);
  } on SmartschoolPresenceChangeRefusedError catch (refused) {
    return _Refused(
      'The ${formatDayPart(part)} of $name changed meanwhile: it now holds '
      '${codes.describe(refused.halfDay)}, which the server never '
      'overwrites.',
    );
  } on SmartschoolPresencePupilNotFoundError catch (missing) {
    return _Refused(_notListed(missing, name));
  } on SmartschoolPresenceError catch (error) {
    log('presence: $error');
    return _Failed(_refusedSave(error, name), maybeSaved: false);
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

/// Why the change for [name] stopped when the library's read right before
/// the save did not list the pupil ([missing], yvanvds/dartschool#116), such
/// as a pupil whose movement into the class ended: with the module's reason
/// when it listed no pupils at all.
String _notListed(SmartschoolPresencePupilNotFoundError missing, String name) {
  final listedNone = switch (missing.errorMessage) {
    final reason? =>
      ' The Presence module now lists no pupils for it: '
          '${formatModuleReason(reason)}',
    null => '',
  };
  return '$name is no longer listed in the class on that day.$listedNone';
}

/// Why the change for [name] failed with [error]: the module's reason when
/// it refused the save (the library gives it without the pupil's name,
/// yvanvds/dartschool#109), else a refusal of the save or of the library's
/// read right before it, whose details go to the log only.
///
/// The reason is not quoted: for an error without a reason of the module's
/// (or in a shape it does not recognise), the library gives a text of its
/// own instead, such as [PresenceSaveError.noReason].
String _refusedSave(SmartschoolPresenceError error, String name) {
  final reasons = {
    for (final saveError in error.saveErrors) formatSentence(saveError.message),
  };
  if (reasons.isEmpty) {
    return "Smartschool's Presence module refused the change for $name, or a "
        'read right before it; the technical details are in the server log.';
  }
  return "Smartschool's Presence module refused to save the change for "
      '$name: ${reasons.join(' ')}';
}

/// The result of a write: a heading, a line per pupil with what was done
/// and what the half-day holds now, and why the write stopped.
///
/// What it holds now comes from [after], the class read again, when it was
/// read; else from the save's answer for a pupil whose half-day was saved,
/// and from [read], the read before anything was sent, for a pupil left
/// alone. [afterProblem] says why [after] could not be read.
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
    // What the half-day holds now, when it is known: `listed` is false for
    // a pupil the class read again no longer lists.
    final ({bool listed, PresenceHalfDay? cell})? now;
    if (after != null) {
      final pupilNow = after.pupil(pupilId);
      now = (
        listed: pupilNow != null,
        cell: pupilNow == null ? null : _cell(pupilNow, part, after.date),
      );
    } else {
      now = switch (step) {
        _Changed(:final saved?) => (listed: true, cell: saved),
        _Unchanged() => (
          listed: true,
          cell: _cell(read.pupil(pupilId)!, part, read.date),
        ),
        _ => null,
      };
    }
    final done = switch (step) {
      _Changed(:final before) => 'set (was ${read.codes.describe(before)})',
      _Unchanged() => 'already had it; nothing saved',
      _Refused() => 'not changed (see below)',
      _Failed(maybeSaved: true) => 'may or may not have been saved (see below)',
      _Failed() => 'not changed (see below)',
      _NotTried() => 'not tried',
    };
    final holds = switch (now) {
      null => '',
      (listed: false, cell: _) => '; no longer listed in the class',
      (listed: true, :final cell) => '; now: ${read.codes.describe(cell)}',
    };
    final saved = step is _Changed || (step is _Failed && step.maybeSaved);
    final String mark;
    if (step is _Changed &&
        now != null &&
        !(now.listed && target.heldBy(now.cell, read.codes, motivation))) {
      unconfirmed = true;
      mark = ' (NOT what was saved)';
    } else {
      mark = saved && now == null ? ' (not confirmed)' : '';
    }
    lines.add('- ${name(pupilId)}: $done$holds$mark');
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
  final afterNote = switch (afterProblem) {
    final problem? =>
      'Reading the class again afterwards failed, so the result does not '
          'show what every half-day holds now: $problem Read the class with '
          'list_class_presences and tell the user what it shows.',
    null => null,
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
