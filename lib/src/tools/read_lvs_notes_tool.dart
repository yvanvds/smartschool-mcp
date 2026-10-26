import 'package:dart_mcp/server.dart';

import '../lvs/lvs_access.dart';
import '../lvs/lvs_notes.dart';
import '../messages/message_filter.dart' show parseDateArgument;
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_lvs_notes`: the notes of one pupil's file in Smartschool's pupil
/// tracking system (LVS), of one note category with its sub-categories or
/// of all, in one school year, newest first; confidential notes left out
/// and counted unless asked for ([LvsService.getNotes],
/// [LvsService.getAllNotes], #154). [now] gives today, for the default
/// school year.
ServerTool readLvsNotesTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => lvsTool(
  definition: Tool(
    name: 'read_lvs_notes',
    title: "Read the notes in a pupil's file in the pupil tracking system",
    description:
        "Reads the notes in one pupil's file in Smartschool's pupil tracking "
        'system (leerlingvolgsysteem, LVS): what the school keeps on '
        'behaviour, care and educational needs, class council remarks, talks '
        'with parents and the like, in note categories the school makes '
        'itself. Use it when the user asks how a pupil is doing, or which '
        'measures or agreements a pupil has. With category (a category_id or '
        "a name from read_lvs_pupil), the notes of that category and its "
        'sub-categories; without it, of all categories. Of one school year, '
        'the current one unless school_year is given; since and limit keep '
        'the answer short. Newest first, each note with its day, category, '
        'title, author and fields as label: value (attachments by name only, '
        'not opened). Confidential notes (vertrouwelijk) are left out and '
        'only counted, unless include_confidential is true: set it only when '
        'the user explicitly asks for confidential notes. The answer ends '
        'with how many notes there are and how many were left out, and why. '
        'Only notes: results, support plans and absences are not read here. '
        'Take pupil_id and class_id from one line of search_lvs_pupils. '
        '$lvsPrivacyRules This tool only reads, and the server sends nothing '
        "that marks a note as seen; whether Smartschool takes notes as seen "
        'by this account when they are read (their "new" mark) is not known '
        'yet.',
    inputSchema: Schema.object(
      properties: {
        'pupil_id': lvsPupilIdSchema(),
        'class_id': lvsClassIdSchema(),
        'category': Schema.combined(
          description:
              'One note category, as read_lvs_pupil lists them: its '
              'category_id, or its name (ignoring case). Its sub-categories '
              'are read with it. Default: all categories.',
          anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
        ),
        'school_year': lvsSchoolYearSchema(),
        'since': Schema.string(
          description:
              'Only notes from this day on, like 2025-10-01 (Belgian time). '
              'Default: the whole school year.',
        ),
        'limit': Schema.int(
          description:
              'At most this many notes, newest first. Default '
              '$lvsNotesDefaultLimit, at most $lvsNotesMaxLimit.',
          minimum: 1,
          maximum: lvsNotesMaxLimit,
        ),
        'include_confidential': Schema.bool(
          description:
              'Also the confidential notes (vertrouwelijk). Default false: '
              'they are left out and only counted. Set it to true only when '
              'the user explicitly asks for confidential notes.',
        ),
      },
      required: ['pupil_id', 'class_id'],
    ),
    annotations: ToolAnnotations(
      title: "Read the notes in a pupil's file in the pupil tracking system",
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
  final category = lvsCategoryArgument(arguments);
  final schoolYear = lvsSchoolYearArgument(arguments, now: now());
  final since = switch (arguments['since']) {
    final String text when text.trim().isNotEmpty => _day(
      parseDateArgument('since', text),
    ),
    _ => null,
  };
  final limit = intArgument(arguments, 'limit') ?? lvsNotesDefaultLimit;
  if (limit < 1 || limit > lvsNotesMaxLimit) {
    throw ToolError(
      'limit must be from 1 to $lvsNotesMaxLimit; $limit is not.',
    );
  }
  final includeConfidential = arguments['include_confidential'] == true;
  final read = await withLvs(
    session,
    (lvs) => readLvsNotes(
      lvs,
      pupilId: pupilId,
      classId: classId,
      category: category,
      schoolYear: schoolYear,
    ),
  );
  final selection = selectLvsNotes(
    read.notes,
    since: since,
    includeConfidential: includeConfidential,
    limit: limit,
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatLvsNotes(
          pupilId: pupilId,
          classId: classId,
          schoolYear: schoolYear,
          category: read.category,
          selection: selection,
          since: since,
          limit: limit,
          includeConfidential: includeConfidential,
        ),
      ),
    ],
  );
}

/// The day of [date] (its year, month and day) as `YYYY-MM-DD`; a time is
/// not used, as notes are compared by day.
String _day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
