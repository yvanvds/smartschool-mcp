import 'package:dart_mcp/server.dart';

import '../lvs/lvs_access.dart';
import '../lvs/lvs_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// `read_lvs_pupil`: the overview of one pupil's file in Smartschool's
/// pupil tracking system (LVS): who, which class, the form tutors, today's
/// attendance, and which parts of the file hold something
/// ([LvsService.getPupilFile], #153). What the parts hold is read by the
/// tools of #154 to #157.
ServerTool readLvsPupilTool(SmartschoolSession session) => lvsTool(
  definition: Tool(
    name: 'read_lvs_pupil',
    title: "Read the overview of a pupil's file in the pupil tracking system",
    description:
        "Reads the overview of one pupil's file in Smartschool's pupil "
        'tracking system (leerlingvolgsysteem, LVS): name, class, the form '
        "tutors (titularissen) of the pupil's class, today's attendance, and "
        'the parts of the file that hold something: the note categories of '
        'the school, with their sub-categories and category_id, and the '
        "LVS's other parts, such as results, support plans and absences, "
        'marked "with new notes" or "with something new" where the LVS marks '
        'what this account has not seen. It lists the parts that hold nothing '
        'too. It does not show what a part holds. Take pupil_id and class_id '
        'from one line of search_lvs_pupils. $lvsPrivacyRules Reading '
        'changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'pupil_id': lvsPupilIdSchema(),
        'class_id': lvsClassIdSchema(),
      },
      required: ['pupil_id', 'class_id'],
    ),
    annotations: ToolAnnotations(
      title: "Read the overview of a pupil's file in the pupil tracking system",
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
  final file = await withLvs(
    session,
    (lvs) => lvs.getPupilFile(pupilId: pupilId, classId: classId),
  );
  return CallToolResult(content: [TextContent(text: formatLvsPupilFile(file))]);
}
