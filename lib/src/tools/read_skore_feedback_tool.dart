import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_skore_feedback`: the written feedback of one pupil on one
/// evaluation of one of the user's gradebooks in Skore, their own or one a
/// colleague shared with them (#167), from everyone who gave some
/// ([SkoreGradebookService.getFeedback], dartschool#149). The user's own
/// feedback is marked by the logged-in user's id, never by the gradebook's
/// teacher, who is the owner of a shared gradebook.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools.
///
/// The library takes the evaluation as `getEvaluations` lists it, so the
/// evaluation is looked up in its period first ([findSkoreEvaluation]):
/// with `period_id`, one read of that period; without it, the active period
/// first, then the others. The gradebook's pupils and periods come from
/// `getGradebook`, to refuse an unknown pupil or period before anything
/// else is sent, and to name the pupil.
ServerTool readSkoreFeedbackTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_skore_feedback',
    title: 'Read a pupil\'s feedback on an evaluation in Skore',
    description:
        'Reads the written feedback a pupil has on one evaluation of one of '
        'the user\'s gradebooks in Skore, the Smartschool module for scores '
        'and reports (their own, or one a colleague shared with them, whose '
        'owner it names): every feedback text on it, whoever wrote it, in '
        'the order they were written, each with who wrote it (marked when it '
        'is the user), when it was written and last changed (Smartschool '
        'time, Belgium), the names of its attachments, whether Skore lets '
        'the user change it, and its text. It also gives the evaluation (with '
        'its publication: the pupils see the feedback on a published '
        'evaluation) and the pupil\'s grade: on an evaluation on a scale, its '
        'level with its label and abbreviation. It reads the feedback on an '
        'evaluation in points or on a scale, also on one whose grades the '
        'server cannot read. Take the gradebook id, the '
        'evaluation id and the pupil id from list_skore_evaluations, which '
        'marks with "feedback" the pupils who have some; pass the period_id '
        'of the evaluation too, so that the other periods need not be read. '
        'A pupil without feedback on it gets a sentence saying so. Reading '
        'changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'evaluation_id': Schema.int(
          description: 'The evaluation id, from list_skore_evaluations.',
          minimum: 1,
        ),
        'pupil_id': Schema.int(
          description:
              'The pupil id, from list_skore_evaluations or '
              'read_skore_gradebook.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'The period of the evaluation, by its period id. Default: the '
              'evaluation is looked for in the period Skore opens the '
              'gradebook on, then in the other periods.',
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
      required: ['gradebook_id', 'evaluation_id', 'pupil_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a pupil\'s feedback on an evaluation in Skore',
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
  final evaluationId = requiredIntArgument(arguments, 'evaluation_id');
  final pupilId = requiredIntArgument(arguments, 'pupil_id');
  final periodId = intArgument(arguments, 'period_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final text = await withSkoreGradebook(session, (gradebooks) async {
    final userId = await gradebooks.userId();
    final (:sheet, :workyear) = await readSkoreGradebook(
      gradebooks,
      years,
      gradebookId,
      workyearId: workyearId,
    );
    final pupil = skoreGradebookPupil(sheet, pupilId);
    final found = await findSkoreEvaluation(
      gradebooks,
      sheet,
      evaluationId,
      periodId: periodId,
    );
    final feedback = await gradebooks.getFeedback(
      sheet.gradebook,
      found.evaluation,
      pupil.id,
    );
    return formatSkorePupilFeedback(
      sheet,
      workyear,
      found,
      pupil,
      feedback,
      userId: userId,
      scale: await readSkoreScaleFor(gradebooks, [found.evaluation]),
    );
  });
  return CallToolResult(content: [TextContent(text: text)]);
}

/// What `read_skore_feedback` answers: the gradebook, the evaluation (of
/// [found]) and its period, [pupil] with their grade (on a scale, with its
/// level on [scale], #169), and [feedback] in Skore's order (the order
/// written), or a sentence that there is none.
///
/// The user's own feedback is the one by the logged-in user, [userId]
/// ([SkoreGradebooks.userId]), as the library keeps it: not the one by the
/// gradebook's teacher ([SkoreGradebook.teacherId]), which is the user for
/// their own gradebooks, but the colleague who owns a gradebook shared with
/// them (#167), whose feedback is never the user's.
String formatSkorePupilFeedback(
  SkoreGradebookSheet sheet,
  SkoreWorkyear workyear,
  FoundSkoreEvaluation found,
  SkoreGradebookPupil pupil,
  List<SkoreFeedback> feedback, {
  required int userId,
  SkoreScale? scale,
}) {
  final evaluation = found.evaluation;
  // An evaluation the library could not read has no grades to give
  // (yvanvds/dartschool#193); its feedback is read all the same.
  final readable = evaluation.isReadable;
  final grade = readable ? evaluation.results.gradeOf(pupil.id) : null;
  final count = feedback.length;
  return [
    '${formatSkoreGradebookTitle(sheet.gradebook, workyear)}.',
    'Period: ${formatSkorePeriodName(found.period)}.',
    'Evaluation: ${formatSkoreEvaluation(evaluation)}',
    'Pupil: ${formatSkoreGradebookPupil(pupil)} | '
        '${!readable
            ? 'grade not read'
            : grade?.grade == null
            ? formatSkoreGradeValue(grade)
            : 'grade ${formatSkoreGradeIn(evaluation, grade, scale)}'}',
    if (!readable) formatSkoreUnreadableGrades(evaluation),
    if (scale == null) ?formatSkoreScaleNote([evaluation], scale),
    if (feedback.isEmpty)
      'The pupil has no feedback on this evaluation.'
    else ...[
      '$count feedback ${count == 1 ? 'text' : 'texts'} on it, in the order '
          '${count == 1 ? 'it was' : 'they were'} written:',
      for (final item in feedback)
        formatSkoreFeedback(item, byUser: item.teacherId == userId),
    ],
  ].join('\n');
}
