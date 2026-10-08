import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';

// Reaching the user's own gradebooks in Skore ("Puntenboek",
// `/SkoreGradebook`) for the gradebook tools: the session runner, the
// library's errors as ToolErrors, and the gradebooks of a school year kept in
// memory per session, to find a gradebook by its id.
//
// Unlike the Skore tools of `skore_access.dart` (`SkoreService`, the admin
// side of Skore, behind the switch "Skore-beheer"), the gradebook needs no
// extra rights: every teacher has gradebooks of their own. So the gradebook
// tools are offered to every account, and nothing here speaks of rights or
// of that switch.

/// Runs [action] with a [SkoreGradebookService] on the session's logged-in
/// client.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat; the
/// reads are.
///
/// The library's errors, which [SmartschoolSession.run] passes on as they
/// are, become [ToolError]s ([skoreGradebookToolError]); login and
/// connection failures stay `SmartschoolProblem`s.
Future<T> withSkoreGradebook<T>(
  SmartschoolSession session,
  Future<T> Function(SkoreGradebookService gradebooks) action,
) async {
  try {
    return await session.run((client) => action(SkoreGradebookService(client)));
  } catch (error) {
    final toolError = skoreGradebookToolError(error);
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of [SkoreGradebookService], or null
/// for anything else (a [ToolError] of the action itself, a login or
/// connection failure), which the caller passes on as it is.
///
/// - [ArgumentError] for an argument of the library's methods
///   ([_arguments]): a value Skore does not offer, such as a school year it
///   does not list (Skore answers that with no gradebooks; the library refuses
///   it), or one that is not an id (refused before anything is sent). Its
///   message names only ids and school years, so it is passed on with the
///   tool's name of the argument and what to correct. Any other
///   [ArgumentError] is not taken for one of these: it stays an unexpected
///   error.
/// - [SmartschoolParsingError]: the session's user id (`authenticatedUser.id`)
///   is not in the form the gradebook calls are built from. Logged, with a
///   short message.
/// - [SmartschoolSkoreError]: an answer the server cannot use (an error page,
///   another HTTP status, data in an unknown shape). The library's message
///   can quote Skore's answer, which may hold names, so it goes to the log
///   only. What Skore answers an account without gradebooks of its own (a
///   pupil's) was not captured: this is the message such an account gets
///   when it is not an empty list, so it says so.
///
/// The writes of later tools add their own cases before the last one:
/// `SmartschoolSkoreChangeRefusedError` (a check refused the change, nothing
/// was saved; a [SmartschoolSkoreError], so it must come first). The save
/// that Skore did not confirm (`SmartschoolSkoreSaveUnconfirmedError` and its
/// subtypes) and a new evaluation that came back public
/// (`SmartschoolSkoreEvaluationPublicError`) are not [SmartschoolSkoreError]s:
/// they come out here as null, for the write tools to report themselves.
ToolError? skoreGradebookToolError(Object error) {
  switch (error) {
    case ArgumentError(:final String name, :final invalidValue)
        when _arguments.containsKey(name):
      log('skore gradebook: $error');
      final (argument, fix) = _arguments[name]!;
      return ToolError(
        'Skore\'s gradebook cannot take $argument $invalidValue: '
        '${_reason(error.message)} $fix',
      );
    case SmartschoolParsingError():
      log('skore gradebook: $error');
      return const ToolError(
        'Smartschool did not give the id of the signed-in user in the form '
        'Skore\'s gradebook needs, so the gradebook could not be read. Try '
        'again in a moment; the technical details are in the server log.',
      );
    case SmartschoolSkoreError():
      log('skore gradebook: $error');
      return const ToolError(
        'Skore\'s gradebook gave an answer the server could not use. Try '
        'again in a moment; the technical details are in the server log. An '
        'account without gradebooks of its own in Skore, such as a pupil\'s, '
        'may get this answer too.',
      );
  }
  return null;
}

/// The arguments of [SkoreGradebookService]'s methods whose [ArgumentError]
/// [skoreGradebookToolError] passes on, by the library's name: the tool's
/// name of the argument and what to correct. Later tools add theirs (a
/// period, a pupil, an evaluation).
const _arguments = <String, (String, String)>{
  'workyearId': (
    'workyear_id',
    'Take a workyear id from the school years list_skore_gradebooks lists, '
        'or leave out workyear_id for Skore\'s current school year.',
  ),
};

/// The library's [message] of an [ArgumentError] as a sentence.
String _reason(Object? message) {
  final text = '${message ?? 'not a value Skore offers'}'.trim();
  return text.endsWith('.') ? text : '$text.';
}

/// A gradebook of the user, with the school year it is of.
typedef FoundSkoreGradebook = ({
  SkoreGradebook gradebook,
  SkoreWorkyear workyear,
});

/// The user's own gradebooks per school year
/// ([SkoreGradebookService.getGradebookYear]), kept in memory for the
/// session, so that the gradebook tools find a gradebook by its id without
/// reading them for every call.
///
/// Skore's answer is big (some 270 KB for 22 gradebooks, 1.7 MB for 50, as
/// it sends the colleagues of every gradebook along): the library says to
/// read it once, not per gradebook. A gradebook id that is not in memory is
/// read again ([find]); gradebooks rarely change during a school year
/// (Skore's administrators make them).
final class SkoreGradebookYears {
  SkoreGradebookYears._();

  static final _ofSession = Expando<SkoreGradebookYears>();

  /// The gradebooks of the user [session] logs in as, shared by every tool
  /// on that session.
  factory SkoreGradebookYears.of(SmartschoolSession session) =>
      _ofSession[session] ??= SkoreGradebookYears._();

  /// The school years read, by the workyear id they were asked for: `null`
  /// for Skore's current school year, which is also kept under its own id.
  final Map<int?, Future<SkoreGradebookYear>> _years = {};

  /// The gradebooks of school year [workyearId] (Skore's current school
  /// year without it), with the school years Skore offers: from memory, or
  /// read with [gradebooks] on the first call for that year, and with
  /// [again]. Calls at the same time share one read; a read that failed is
  /// tried again on the next call.
  Future<SkoreGradebookYear> read(
    SkoreGradebookService gradebooks, {
    int? workyearId,
    bool again = false,
  }) async {
    final known = again ? null : _years[workyearId];
    final pending =
        known ?? gradebooks.getGradebookYear(workyearId: workyearId);
    _years[workyearId] = pending;
    try {
      final year = await pending;
      if (workyearId == null) _years[year.workyear.id] = pending;
      return year;
    } catch (_) {
      if (identical(_years[workyearId], pending)) _years.remove(workyearId);
      rethrow;
    }
  }

  /// The user's gradebook with [gradebookId], of school year [workyearId],
  /// or without it of any school year in memory, Skore's current one first.
  /// When it is not in memory, the school year is read again with
  /// [gradebooks] (Skore's current one without [workyearId]).
  ///
  /// Throws a [ToolError] that says to take the id from
  /// `list_skore_gradebooks` when that read does not hold it either.
  Future<FoundSkoreGradebook> find(
    SkoreGradebookService gradebooks,
    int gradebookId, {
    int? workyearId,
  }) async {
    for (final year in await _inMemory(workyearId)) {
      if (_found(year, gradebookId) case final found?) return found;
    }
    final year = await read(gradebooks, workyearId: workyearId, again: true);
    if (_found(year, gradebookId) case final found?) return found;
    final where =
        'school year ${year.workyear.name} (workyear id '
        '${year.workyear.id})';
    throw ToolError(
      'None of the user\'s own gradebooks in Skore of $where has gradebook '
      'id $gradebookId. Take the gradebook id from list_skore_gradebooks'
      '${workyearId == null ? '; for a gradebook of an earlier school year, '
                'pass its workyear_id too, as list_skore_gradebooks lists the '
                'school years' : ' with workyear_id $workyearId'}.',
    );
  }

  /// The school years in memory to look in for a gradebook of [workyearId]:
  /// that one, or without it every one, Skore's current school year first.
  /// A read that is still running is waited for; one that failed is left
  /// out.
  Future<List<SkoreGradebookYear>> _inMemory(int? workyearId) async {
    // A set: the current school year is kept under two keys.
    final pending = <Future<SkoreGradebookYear>>{
      if (workyearId != null)
        ?_years[workyearId]
      else ...[
        ?_years[null],
        for (final MapEntry(:key, :value) in _years.entries)
          if (key != null) value,
      ],
    };
    final years = <SkoreGradebookYear>[];
    for (final year in pending) {
      try {
        years.add(await year);
      } catch (_) {
        // read() forgets it; the caller reads the school year again.
      }
    }
    return years;
  }

  static FoundSkoreGradebook? _found(SkoreGradebookYear year, int id) =>
      switch (year.gradebooks.where((g) => g.gradebookId == id).firstOrNull) {
        final gradebook? => (gradebook: gradebook, workyear: year.workyear),
        null => null,
      };
}
