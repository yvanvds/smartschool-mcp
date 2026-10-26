import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../lvs/lvs_absences.dart';
import '../lvs/lvs_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_lvs_absences`: the absences of one pupil in Smartschool's pupil
/// tracking system (LVS), the absences part of the pupil's file
/// ("Afwezigheden"): the totals per code and the half-days of one school
/// year, and the totals of the other school years the LVS gives
/// ([LvsService.getAbsences], #157); motivations left out and counted
/// unless asked for. [now] gives today, for the default school year.
ServerTool readLvsAbsencesTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => lvsTool(
  definition: Tool(
    name: 'read_lvs_absences',
    title: "Read a pupil's absences in the pupil tracking system",
    description:
        "Reads one pupil's absences in Smartschool's pupil tracking system "
        '(leerlingvolgsysteem, LVS): the absences part of the file '
        '(Afwezigheden), the half-days the school registered with an absence '
        'code. Use it when the user asks how often or when a pupil was '
        'absent, or to look for a pattern (Mondays, the day after a holiday, '
        'many half-days of one code). Of one school year, the current one '
        'unless school_year is given: the totals per code (its description '
        'and number of half-days; a whole day counts two), then each absence '
        'with its day and day of the week, morning, afternoon or whole day, '
        'and its code; then the totals of the other school years the LVS '
        "gives, which it picks itself. The codes are the school's own. A "
        'motivation can hold health information: motivations are left out '
        'and only counted, unless with_motivation is true; set it only when '
        'the user asks why the pupil was absent. No absences is a sentence, '
        'not an error. Take pupil_id and class_id from one line of '
        'search_lvs_pupils. $lvsPrivacyRules Reading changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'pupil_id': lvsPupilIdSchema(),
        'class_id': lvsClassIdSchema(),
        'school_year': lvsSchoolYearSchema(),
        'with_motivation': Schema.bool(
          description:
              "Also each absence's motivation (the reason given). Default "
              'false: motivations are left out and only counted, as they can '
              'hold health information. Set it to true only when the user '
              'asks why the pupil was absent.',
        ),
      },
      required: ['pupil_id', 'class_id'],
    ),
    annotations: ToolAnnotations(
      title: "Read a pupil's absences in the pupil tracking system",
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
  final schoolYear = lvsSchoolYearArgument(arguments, now: now());
  final withMotivation = arguments['with_motivation'] == true;
  final read = await withLvs(
    session,
    (lvs) => readLvsAbsences(lvs, pupilId: pupilId, classId: classId),
    part: lvsAbsencesPart,
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatLvsAbsences(
          read,
          pupilId: pupilId,
          classId: classId,
          schoolYear: schoolYear,
          withMotivation: withMotivation,
        ),
      ),
    ],
  );
}
