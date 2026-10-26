import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../lvs/lvs_access.dart';
import '../lvs/lvs_support_plan.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_lvs_support_plan`: the support plan of one pupil in Smartschool's
/// pupil tracking system (LVS), the "handelingsplannen" part of the pupil's
/// file: the individual plan with the pupil's support needs, goals and
/// approach, and the profile sketch, of the current period or another
/// ([LvsService.getSupportPlan] and the other reads of the support plans,
/// #156), with only the items for one course when asked.
ServerTool readLvsSupportPlanTool(SmartschoolSession session) => lvsTool(
  definition: Tool(
    name: 'read_lvs_support_plan',
    title: "Read a pupil's support plan in the pupil tracking system",
    description:
        "Reads one pupil's support plan (handelingsplan, individual plan) in "
        "Smartschool's pupil tracking system (leerlingvolgsysteem, LVS), for "
        "schools that use the LVS's support plans: the pupil's support needs "
        '(ondersteuningsnoden), main and work goals, and the approach '
        '(measures), each item with the courses it is for, its author and '
        'date; goals with their domain, objectives, approach and planning; '
        'an uploaded plan by its file name only (not opened); and the '
        'profile sketch (profielschets). Use it when the user asks what a '
        'pupil needs, in their lessons or in general. Of the current period '
        'of the support plans unless period is given (a period_id or name, '
        'as the answer lists them). course keeps only the items for that '
        'course (its name, or part of it) and those tied to no course. The '
        'server cannot tell which courses are the user\'s own: to see what '
        "concerns the user's course, pass it as course. A school without "
        'support plans, a pupil without a plan and a period without one '
        'each get a sentence; a school that keeps educational needs in note '
        'categories instead is read with read_lvs_notes. Not read yet: the '
        "plan's evaluation and its report, and the earlier versions of its "
        'items. Take pupil_id and class_id from one line of '
        'search_lvs_pupils. $lvsPrivacyRules Reading changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'pupil_id': lvsPupilIdSchema(),
        'class_id': lvsClassIdSchema(),
        'period': Schema.combined(
          description:
              'One period of the support plans: its period_id or its name, '
              'as this tool lists them at the end of its answer. Default: '
              'the current period.',
          anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
        ),
        'course': Schema.string(
          description:
              'Only the items for the course with this name (ignoring '
              'case), or else for those whose name holds it, and the items '
              'tied to no course. Default: all items.',
          minLength: 1,
        ),
      },
      required: ['pupil_id', 'class_id'],
    ),
    annotations: ToolAnnotations(
      title: "Read a pupil's support plan in the pupil tracking system",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final (:pupilId, :classId) = lvsPupilArguments(arguments);
  final period = lvsPlanPeriodArgument(arguments);
  final course = lvsPlanCourseArgument(arguments);
  final read = await withLvs(
    session,
    (lvs) => readLvsSupportPlan(
      lvs,
      pupilId: pupilId,
      classId: classId,
      period: period,
    ),
    part: lvsSupportPlanPart,
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatLvsSupportPlan(
          read,
          pupilId: pupilId,
          classId: classId,
          course: course,
        ),
      ),
    ],
  );
}
