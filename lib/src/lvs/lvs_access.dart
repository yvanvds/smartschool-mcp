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
Future<T> withLvs<T>(
  SmartschoolSession session,
  Future<T> Function(LvsService lvs) action,
) async {
  try {
    return await session.run(
      (client) => action(LvsService(client)),
      describeError: lvsLogDescription,
    );
  } on SmartschoolLvsError catch (error) {
    throw lvsToolError(error, session.source);
  }
}

/// The [ToolError] for [error], an error of [LvsService]: what to do, in
/// the server's words; [source] is where the user turns
/// "Leerlingvolgsysteem" off. The error is logged by type and HTTP status
/// only ([lvsLogDescription]).
ToolError lvsToolError(SmartschoolLvsError error, CredentialSource source) {
  log('lvs: ${lvsLogDescription(error)}');
  return ToolError(switch (error) {
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
