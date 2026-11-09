import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_skore_report`: one report period (Skore's "Rapporten", such as
/// `R1D: Rapport 1`) of one of the user's gradebooks in Skore, their own or
/// one a colleague shared with them (#167), as Skore's gradebook shows it
/// (#171, [SkoreGradebookService.getReport], dartschool#195): per pupil of
/// the class the results so far per component of the course, and the
/// course comment ("vakcommentaar") that is printed on the report.
///
/// Skore keeps one course comment per pupil, course and report, which the
/// colleagues who give the course share, and it does not say who wrote it:
/// so the result marks a comment by whether Skore lets the user change it
/// ([SkoreReportComment.isEditable], and the report open), not by its
/// author.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools. The gradebook is read first ([readSkoreGradebook]: its report
/// periods and pupils), to refuse an unknown report or pupil before the
/// report is asked for, and to name the pupils, whom the report gives by
/// id only.
ServerTool readSkoreReportTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_skore_report',
    title: 'Read a report in a gradebook in Skore',
    description:
        'Reads one report period (Skore\'s "Rapporten", such as R1D, Rapport '
        '1) of one of the user\'s gradebooks in Skore, the Smartschool module '
        'for scores and reports (their own, or one a colleague shared with '
        'them, whose owner it names), by its report id from '
        'read_skore_gradebook. Per pupil of the class, in Skore\'s order: '
        'the results so far per component of the course (such as DW), as '
        'Skore calculates them from the evaluations and shows them on the '
        'report (read-only), and the pupil\'s course comment (vakcommentaar): '
        'the text that is printed on the report the pupil and their parents '
        'get, with whether Skore lets the user change it. Skore keeps one '
        'course comment per pupil and course on a report, which the '
        'colleagues who give the course share, and it does not say who wrote '
        'it. It also gives the report (open or closed, until when: only '
        'while it is open can comments be written, with '
        'save_skore_report_comment), the class average per component, and '
        'how long a comment may be. A behaviour gradebook (such as Gedrag) '
        'has no results on the report, only the comment. Pass pupil_id for '
        'one pupil: read that pupil\'s comment right before changing it. For '
        'a gradebook of an earlier school year, pass its workyear_id too. '
        'Reading changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'report_id': Schema.int(
          description:
              'The report period, by its report id from '
              'read_skore_gradebook (not a period id).',
          minimum: 1,
        ),
        'pupil_id': Schema.int(
          description:
              'Only this pupil, by the pupil id read_skore_gradebook gives. '
              'Default: every pupil of the class.',
          minimum: 1,
        ),
        'workyear_id': Schema.int(
          description:
              'The school year of the gradebook, by its workyear id from '
              'list_skore_gradebooks. Default: Skore\'s current school '
              'year.',
          minimum: 1,
        ),
      },
      required: ['gradebook_id', 'report_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a report in a gradebook in Skore',
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
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final reportId = requiredIntArgument(arguments, 'report_id');
  final pupilId = intArgument(arguments, 'pupil_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final text = await withSkoreGradebook(session, (gradebooks) async {
    final (:sheet, :workyear) = await readSkoreGradebook(
      gradebooks,
      years,
      gradebookId,
      workyearId: workyearId,
    );
    final period = skoreReportPeriod(sheet, reportId);
    // The pupil is looked up in the gradebook first, so that an unknown one
    // is refused before the report is asked for.
    final pupil = pupilId == null ? null : skoreGradebookPupil(sheet, pupilId);
    final report = await readSkoreReport(gradebooks, sheet, period);
    return formatSkoreReport(sheet, workyear, period, report, pupil: pupil);
  });
  return CallToolResult(content: [TextContent(text: text)]);
}

/// What `read_skore_report` answers: the gradebook of [sheet] (of school
/// year [workyear]), the report period [period], how the report shows the
/// course (its name, its components with their class average), what the
/// course comment is, and per pupil of [report] (or only [pupil]) the
/// results and the comment ([formatSkoreReportPupil]).
String formatSkoreReport(
  SkoreGradebookSheet sheet,
  SkoreWorkyear workyear,
  SkoreReportPeriod period,
  SkoreReport report, {
  SkoreGradebookPupil? pupil,
}) {
  final components = report.components;
  final max = report.commentMaxLength;
  final rows = pupil == null ? report.pupils : [?report.pupil(pupil.id)];
  final names = {for (final p in sheet.pupils) p.id: p};
  // A gradebook shared with the user to read only (#167): Skore may show its
  // comments as editable, in its owner's name, but the user may not change
  // them, and save_skore_report_comment refuses it.
  final readOnly = sheet.gradebook.access == SkoreGradebookAccess.read;
  return [
    '${formatSkoreGradebookTitle(sheet.gradebook, workyear)}.',
    'Report: ${formatSkoreReportPeriod(period)}',
    if (components.isEmpty)
      'The report shows no results for the course "'
          '${skoreName(report.courseName)}" (a course without components, '
          'such as behaviour): only its course comment.'
    else
      'The report shows the course "${skoreName(report.courseName)}" with '
          'the results so far per component, as Skore calculates them from '
          'the evaluations (read-only): '
          '${[for (final c in components) '${skoreName(c.name)} (class average ${c.classAverage ?? 'none'})'].join(', ')}.',
    if (!report.hasComments)
      'The report has no course comment for this course.'
    else ...[
      'The course comment of each pupil is printed on the report that the '
          'pupil and their parents get. Skore keeps one per pupil for this '
          'course, which the colleagues who give it share, and does not say '
          'who wrote it'
          '${max == null ? '' : '; it may have at most $max characters'}.',
      if (!period.isOpen)
        'The report is closed: its course comments can no longer be written.'
      else if (readOnly)
        'The report is open, but the user may read these comments, not change '
            'them: the gradebook is shared with them to read only.'
      else
        'The report is open: save_skore_report_comment writes a comment '
            'where Skore lets the user change it.',
    ],
    if (pupil != null && rows.isEmpty)
      '${formatSkoreGradebookPupil(pupil)} has no row on this report.'
    else if (rows.isEmpty)
      'The report lists no pupils of the class.'
    else ...[
      if (pupil == null)
        '${rows.length} ${rows.length == 1 ? 'pupil' : 'pupils'}, in '
            'Skore\'s order:',
      for (final row in rows)
        formatSkoreReportPupil(
          row,
          names[row.pupilId],
          report: report,
          isOpen: period.isOpen,
          readOnly: readOnly,
        ),
    ],
  ].join('\n');
}

/// One pupil's row of [report] (#171): the pupil (as [pupil] of the
/// gradebook names them, or by id when the gradebook does not list them),
/// the result per component, and the course comment: whether Skore lets the
/// user change it (only while the report is open, [isOpen], and not in a
/// gradebook shared with the user to read only, [readOnly]), then its text,
/// indented line by line.
///
/// For example `- 1. Aerts, An | pupil id 1201 | DW 79 | comment the user may
/// change` and `  Goed gewerkt.`; `- 2. Claes, Bart | pupil id 1202 | DW 38
/// (low) | no comment yet, the user may write one`.
String formatSkoreReportPupil(
  SkoreReportPupil row,
  SkoreGradebookPupil? pupil, {
  required SkoreReport report,
  required bool isOpen,
  bool readOnly = false,
}) {
  final comment = row.comment;
  final results = [
    for (final component in report.components)
      switch (row.resultOf(component.column)) {
        null => '${skoreName(component.name)} no cell',
        SkoreReportResult(value: null) =>
          '${skoreName(component.name)} no result',
        SkoreReportResult(:final value?, :final isLow) =>
          '${skoreName(component.name)} $value${isLow ? ' (low)' : ''}',
      },
  ];
  final state = switch (comment) {
    _ when !report.hasComments => null,
    null => 'no comment on the report',
    SkoreReportComment(isEditable: false) =>
      comment.isEmpty
          ? 'no comment, and Skore does not let the user write one (closed '
                'for this pupil)'
          : 'comment Skore does not let the user change (closed for this '
                'pupil)',
    _ when !isOpen =>
      comment.isEmpty
          ? 'no comment (the report is closed)'
          : 'comment (the report is closed)',
    _ when readOnly =>
      comment.isEmpty
          ? 'no comment (shared to read only)'
          : 'comment (shared to read only)',
    _ =>
      comment.isEmpty
          ? 'no comment yet, the user may write one'
          : 'comment the user may change',
  };
  return [
    [
      '- ${pupil == null ? 'pupil id ${row.pupilId} (not in the gradebook\'s list of pupils)' : formatSkoreGradebookPupil(pupil)}',
      ...results,
      ?state,
    ].join(' | '),
    if (comment != null && !comment.isEmpty)
      ...formatSkoreReportCommentText(comment.text),
  ].join('\n');
}
