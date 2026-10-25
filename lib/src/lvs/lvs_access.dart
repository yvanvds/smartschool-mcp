import 'package:dart_mcp/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../opt_in.dart';
import '../problems.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/arguments.dart';
import '../tools/server_tool.dart';

// Reaching Smartschool's pupil tracking system (LVS, "leerlingvolgsysteem")
// for the LVS tools (#153), with the library's LvsService
// (yvanvds/dartschool#160): the session runner, the LVS's errors as
// ToolErrors, the arguments the tools share, and the access check of
// smartschool_status.
//
// The LVS holds the most sensitive data Smartschool has (care, behaviour,
// educational needs, sometimes health). Every LVS tool follows these rules
// (#153; the library's own are in its doc/lvs-privacy.md,
// yvanvds/dartschool#159):
//
// - Read-only. No LVS write tool, now or later, without an issue that
//   discusses it. The library sends only its reads, by an allowlist.
// - Nothing on disk: no cache folder, no downloads, nothing like the
//   message text cache. In memory only what one call needs.
// - Nothing in the log but an error's type and HTTP status
//   ([lvsLogDescription]): never its message, which may still hold a name.
//   Claude Desktop's MCP log is a file people attach to bug reports. Every
//   LVS tool is an [lvsTool], so no error of one reaches the server's own
//   log line, which prints the error; and [withLvs] has the session log a
//   refused session by type too, as its message names the request, with
//   the pupil's id.
// - Errors shown to the user say what to do, not what the answer held
//   ([lvsToolError]).
// - Descriptions end with [lvsPrivacyRules].
// - One pupil per call: no tool reads a whole class's notes or results.

/// What the LVS tools need, as `smartschool_status` names it.
const lvsRights =
    "access to Smartschool's pupil tracking system (leerlingvolgsysteem, "
    'LVS), as most teachers have';

/// The privacy section of the colleague guide, which the switch's
/// description and [lvsCaution] link to (#158 adds the LVS to it).
const lvsPrivacyGuideUrl =
    'https://github.com/yvanvds/smartschool-mcp/blob/main/docs/'
    'installatie.md#8-veiligheid-en-privacy';

/// What turning "Leerlingvolgsysteem" on means, for `smartschool_status`
/// ([OptInTools.caution]): it is a choice about pupils' data, not only a
/// matter of rights.
const lvsCaution =
    'Its tools read what the LVS holds about pupils, the most sensitive data '
    'in Smartschool (care, behaviour, educational needs, sometimes health): '
    'turn it on only when the user, and their school, choose to let the '
    'assistant read it. See the privacy section of the guide: '
    '$lvsPrivacyGuideUrl';

/// The sentences every LVS tool's description ends with, before "Reading
/// changes nothing": when to use it, and what not to do with the answer.
const lvsPrivacyRules =
    'What the LVS holds about pupils is confidential: use this tool only '
    'when the user asks about a particular pupil, one pupil at a time, and '
    'do not copy what it returns into files, artifacts, messages or other '
    'tools unless the user asks for it.';

/// An LVS tool: [definition] with [handler], which lets nothing of an
/// error reach the log but its type and HTTP status.
///
/// A [ToolError] (from [withLvs], an argument, ...) and a
/// [SmartschoolProblem] (a login or connection failure, worded by the
/// server) pass on as they are. Any other error would reach the server's
/// catch-all, which logs the error with its message (`tool ... failed:
/// $error`), and a message may quote the LVS. So it is logged here by
/// [lvsLogDescription], with its stack trace (the code's lines, no value),
/// and the call fails with a [ToolError] that says so.
ServerTool lvsTool({required Tool definition, required ToolHandler handler}) {
  final name = definition.name;
  return ServerTool(
    definition: definition,
    handler: (request) async {
      try {
        return await handler(request);
      } on SmartschoolProblem {
        rethrow;
      } on ToolError {
        rethrow;
      } catch (error, stackTrace) {
        log('tool $name failed: ${lvsLogDescription(error)}\n$stackTrace');
        throw ToolError(
          'The tool $name failed with an unexpected error. The server log '
          'names its type, and nothing of what the LVS answered.',
        );
      }
    },
  );
}

/// [error] for the log: its type, and the HTTP status when it has one, such
/// as `SmartschoolLvsError (HTTP 500)`. Never its message: the library
/// keeps names and texts out of the messages of its LVS errors, but an
/// error of another kind (one the HTTP client wraps, say) may quote what
/// the LVS answered.
String lvsLogDescription(Object error) {
  final status = switch (error) {
    SmartschoolLvsError(:final statusCode?) => statusCode,
    DioException(:final response?) => response.statusCode,
    _ => null,
  };
  final type = error.runtimeType;
  return status == null ? '$type' : '$type (HTTP $status)';
}

/// Runs [action] with an [LvsService] on the session's logged-in client,
/// and turns the LVS's errors into [ToolError]s ([lvsToolError]); login and
/// connection failures stay [SmartschoolProblem]s.
///
/// Like every [SmartschoolSession.run] action, [action] may run twice (when
/// Smartschool refuses the session), so it must be safe to repeat: the
/// LVS's reads are. What the session logs of a refused session or a
/// problem is the error's type ([lvsLogDescription]): its message names
/// the request, with the pupil's id.
///
/// [part] names the part of the pupil's file [action] reads, such as `the
/// results (Resultaten)` (#155), for a refusal with HTTP 403: the LVS's
/// apps answer that for an account without access to that part
/// ([lvsToolError]).
Future<T> withLvs<T>(
  SmartschoolSession session,
  Future<T> Function(LvsService lvs) action, {
  String? part,
}) async {
  try {
    return await session.run(
      (client) => action(LvsService(client)),
      describeError: lvsLogDescription,
    );
  } on SmartschoolLvsError catch (error) {
    throw lvsToolError(error, session.source, part: part);
  }
}

/// The [ToolError] for [error], an error of [LvsService]: what to do, in
/// the server's words; [source] is where the user turns
/// "Leerlingvolgsysteem" off. The error is logged by type and HTTP status
/// only ([lvsLogDescription]).
///
/// With [part] (the part of the file that was read, see [withLvs]), a
/// refusal with HTTP 403 says that the account has no access to that part:
/// what the results app takes a 403 for (yvanvds/dartschool#162). A
/// refusal by a redirect to the start page keeps the general sentence.
ToolError lvsToolError(
  SmartschoolLvsError error,
  CredentialSource source, {
  String? part,
}) {
  log('lvs: ${lvsLogDescription(error)}');
  return ToolError(switch (error) {
    SmartschoolLvsAccessDeniedError(statusCode: 403) when part != null =>
      "The account has no access to $part of this pupil's file: "
          "Smartschool's pupil tracking system (LVS) refused that read (HTTP "
          '403), as it does for an account without access to that part. '
          'Other parts of the file may still be readable: read_lvs_pupil '
          'lists them. If the account should have access, ask the '
          "school's Smartschool administrator.",
    // Not captured live: what the LVS answers an account without access,
    // or a pupil the account may not see (yvanvds/dartschool#168).
    SmartschoolLvsAccessDeniedError() =>
      "Smartschool's pupil tracking system (LVS) refused this read to the "
          'account: it may have no access to the LVS, or may not see this '
          'pupil. smartschool_status says whether the account can read the '
          'LVS. Without access, ${lvsFix(source)}.',
    SmartschoolLvsPupilNotFoundError(:final pupilId, :final classId) =>
      'The LVS knows no pupil with pupil_id $pupilId in the class with '
          'class_id $classId that this account may see. Take pupil_id and '
          'class_id from the same line of search_lvs_pupils.',
    SmartschoolLvsCategoryNotFoundError(:final categoryId) =>
      'The LVS knows no note category with category_id $categoryId in this '
          "pupil's file. Take it from the parts of the file that "
          'read_lvs_pupil lists.',
    SmartschoolLvsRequestNotAllowedError() =>
      'The server did not send this read to the LVS: the Smartschool '
          'library refused it as not one of its reads, which is a bug of the '
          'library. Nothing was sent, so nothing changed. The server log '
          'names the type of the error.',
    SmartschoolLvsError(:final statusCode) =>
      "Smartschool's pupil tracking system (LVS) answered with something "
          'the server could not read'
          '${statusCode == null || statusCode == 200 ? '' : ' (HTTP $statusCode)'}. '
          'Try again in a moment. If it keeps failing, the server log names '
          'the type of the error, and nothing of what the LVS answered.',
  });
}

/// What the user does about an account without access to the LVS, to end
/// a sentence with.
String lvsFix(CredentialSource source) =>
    "ask the school's Smartschool administrator for access to the LVS, or "
    'turn off ${source.name(Setting.lvs)} ${source.where}, then '
    '${source.restart}';

/// Whether the account can read the LVS, for `smartschool_status`: one
/// cheap read that holds no pupil, the root of the LVS's class tree
/// ([LvsService.checkAccess]).
///
/// Access when the LVS answers it; no access when it refuses it. The
/// library tells only that, not how many classes the root lists, so an
/// account that may see no class at all counts as having access
/// (yvanvds/dartschool#184). An answer the library cannot read is a
/// [ToolError]: access could not be checked.
///
/// Throws a `SmartschoolProblem` when it cannot log in or reach
/// Smartschool.
Future<AccessCheck> checkLvsAccess(SmartschoolSession session) async {
  final access = await withLvs(session, (lvs) => lvs.checkAccess());
  if (access) {
    return const AccessCheck.granted('the LVS answers its class tree');
  }
  return AccessCheck.denied(
    'The LVS refused its class tree to this account, as for an account '
    'without $lvsRights. If so, ${lvsFix(session.source)}.',
  );
}

/// The `pupil_id` argument of the LVS tools.
Schema lvsPupilIdSchema() => Schema.int(
  description: "The pupil's pupil_id, from search_lvs_pupils.",
  minimum: 1,
);

/// The `class_id` argument of the LVS tools.
Schema lvsClassIdSchema() => Schema.int(
  description:
      "The pupil's class_id, from the same line of search_lvs_pupils as "
      'pupil_id.',
  minimum: 1,
);

/// The pupil an LVS tool reads: the `pupil_id` and `class_id` arguments of
/// [arguments].
///
/// Throws a [ToolError] when one is absent, not a whole number, or not
/// positive (the library refuses those before anything is sent).
({int pupilId, int classId}) lvsPupilArguments(Map<String, Object?> arguments) {
  int positive(String name) {
    final value = requiredIntArgument(arguments, name);
    if (value < 1) {
      throw ToolError(
        '$name must be 1 or more; take it from search_lvs_pupils.',
      );
    }
    return value;
  }

  return (pupilId: positive('pupil_id'), classId: positive('class_id'));
}

/// An argument that names one thing of a pupil's file by its id or its
/// name, as text: a name, or an id (digits, or `<id name> <digits>` as the
/// tools print it, see [lvsIdIn]); `null` when it is absent or empty. Used
/// for a note category (#154), a period and a course of the results (#155),
/// and a period and a course of the support plans (#156).
///
/// Throws a [ToolError] for a number that is not a whole number, or a value
/// of another type, saying that [name] must be [what].
String? lvsIdOrNameArgument(
  Map<String, Object?> arguments,
  String name, {
  required String what,
}) {
  switch (arguments[name]) {
    case null:
      return null;
    case final String text:
      final trimmed = text.trim().replaceAll(_quotes, '').trim();
      return trimmed.isEmpty ? null : trimmed;
    case final num number when number == number.truncate():
      return '${number.toInt()}';
    case final value:
      throw ToolError('$name must be $what; $value is not.');
  }
}

/// Double quotes around a name.
final _quotes = RegExp(r'^"|"$');

/// The id that [which], the text of an [lvsIdOrNameArgument], names: its
/// digits, also written `<idName> <digits>` as the tools print an id
/// (`category_id 900401`, `period_id 900401`; with or without the
/// underscore, any case); `null` for any other text.
int? lvsIdIn(String which, String idName) {
  final prefix = RegExp.escape(idName).replaceAll('_', '_?');
  final match = RegExp(
    '^(?:$prefix\\s*)?(\\d+)\$',
    caseSensitive: false,
  ).firstMatch(which.trim());
  return match == null ? null : int.parse(match[1]!);
}

/// [name] to compare names by: in lower case, each run of white space one
/// space, trimmed.
String lvsNameKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// The items of [items] named [which] by [name] (ignoring case and runs of
/// white space, [lvsNameKey]), or, when none is, those whose name holds it.
/// Used for a period and a course of the results (#155) and of the support
/// plans (#156).
List<T> lvsNamed<T>(List<T> items, String which, String Function(T) name) {
  final key = lvsNameKey(which);
  final exact = [
    for (final item in items)
      if (lvsNameKey(name(item)) == key) item,
  ];
  if (exact.isNotEmpty) return exact;
  return [
    for (final item in items)
      if (lvsNameKey(name(item)).contains(key)) item,
  ];
}

/// The `school_year` argument of the LVS tools that read one school year
/// (#154): two years with a dash, as the LVS labels them.
Schema lvsSchoolYearSchema() => Schema.string(
  description:
      'The school year, like 2025-2026 (1 September to 31 August). Default: '
      'the current school year.',
);

/// The school year of the `school_year` argument of [arguments] (a label
/// like `2025-2026`, [LvsSchoolYear.tryParse]), or the current one in
/// Belgian time, of [now], when it is absent or empty.
///
/// Throws a [ToolError] for any other text, before anything is sent.
LvsSchoolYear lvsSchoolYearArgument(
  Map<String, Object?> arguments, {
  required DateTime now,
}) {
  final value = arguments['school_year'];
  final text = value is String ? value.trim() : null;
  if (value == null || text == '') return LvsSchoolYear.current(now: now);
  if (text != null) {
    if (LvsSchoolYear.tryParse(text) case final schoolYear?) return schoolYear;
  }
  throw ToolError(
    'school_year must be a school year like 2025-2026: two years, the '
    'second the one after the first; ${value is String ? '"$value"' : '$value'} '
    'is not. Leave it out for the current school year.',
  );
}
