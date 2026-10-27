import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../lvs/lvs_access.dart';
import '../lvs/lvs_results.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_lvs_results`: the results of one pupil in Smartschool's pupil
/// tracking system (LVS), the "Resultaten" part of the pupil's file, in
/// every course: per course the evaluations with their scores as given, a
/// computed summary for many, then the feedback, the reports and the
/// periods, of one school year and by default its active period
/// ([LvsService.getAllEvaluations] and the other reads of the results app,
/// #155). [now] gives today, for the default school year.
ServerTool readLvsResultsTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => lvsTool(
  definition: Tool(
    name: 'read_lvs_results',
    title: "Read a pupil's results in the pupil tracking system",
    description:
        "Reads one pupil's results in Smartschool's pupil tracking system "
        '(leerlingvolgsysteem, LVS): the Resultaten part of the file, the '
        'results pupils and parents see, in every course, not only the '
        "user's gradebooks (read_skore_gradebook). Use it when the user "
        'asks how a pupil is doing in their courses. Of one school year, the '
        'current one unless school_year is given, and by default of its '
        'active period: period takes a period_id or a name, or all for every '
        'period. course keeps only the courses with that name (or whose name '
        'holds it, or with that course_id), with their parts. Per course, '
        'the evaluations, newest first, each with its day, name, score as '
        'given (points of a maximum with their percentage, a text or a '
        'symbol), whether it counts and whether it is published to the '
        'pupil; with $lvsResultsSummaryFrom or more, a summary line computed '
        'from the scores given (how many below half), which says so and how '
        'many scores could not be counted. Then the feedback (day, author, '
        'text), the reports by name and day (not opened), and the periods to '
        'ask for. Not read: the comments on reports, and the older Skore '
        'part some schools still show instead of Resultaten. Take pupil_id '
        'and class_id from one line of search_lvs_pupils. $lvsPrivacyRules '
        'Reading changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'pupil_id': lvsPupilIdSchema(),
        'class_id': lvsClassIdSchema(),
        'school_year': lvsSchoolYearSchema(),
        'period': Schema.combined(
          description:
              'One period of the results: its period_id or its name, as '
              'this tool lists them at the end of its answer, or all for '
              'every period of the school year. Default: the active period.',
          anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
        ),
        'course': Schema.combined(
          description:
              'Only the courses with this name (ignoring case), or else '
              'those whose name holds it, or the course with this '
              'course_id; with their parts. Default: all courses.',
          anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
        ),
      },
      required: ['pupil_id', 'class_id'],
    ),
    annotations: ToolAnnotations(
      title: "Read a pupil's results in the pupil tracking system",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}, now),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
  DateTime Function() now,
) async {
  final (:pupilId, :classId) = lvsPupilArguments(arguments);
  final today = now();
  final schoolYear = lvsSchoolYearArgument(arguments, now: today);
  final period = lvsResultsPeriodArgument(arguments);
  final course = lvsResultsCourseArgument(arguments);
  final read = await withLvs(
    session,
    (lvs) => readLvsResults(
      lvs,
      pupilId: pupilId,
      classId: classId,
      schoolYear: schoolYear,
      isCurrentSchoolYear: schoolYear == LvsSchoolYear.current(now: today),
      period: period,
      course: course,
    ),
    part: lvsResultsPart,
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatLvsResults(
          read,
          pupilId: pupilId,
          classId: classId,
          schoolYear: schoolYear,
        ),
      ),
    ],
  );
}
