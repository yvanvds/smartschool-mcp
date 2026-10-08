import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_evaluations`: the evaluations of one period of one of the
/// user's own gradebooks in Skore, with their publication and the pupils'
/// grades ([SkoreGradebookService.getEvaluations], dartschool#149); or one
/// evaluation, with a line per pupil.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools.
///
/// Without `evaluation_id`, every evaluation of the period comes with its
/// grades on one line, each grade next to its pupil's name: Claude never
/// has to line up a column of a grid with an evaluation (Skore's column
/// letters move when an evaluation is added), and a question about one
/// evaluation ("who has no grade yet?") is answered by one line. The pupil
/// ids are listed once. With `evaluation_id`, only that evaluation, one line
/// per pupil with the pupil id: the view to match names to pupil ids, as the
/// tools that save grades and feedback need.
ServerTool listSkoreEvaluationsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_evaluations',
    title: 'List the evaluations of a period in Skore',
    description:
        'Lists the evaluations (the columns of grades, such as tests and '
        'tasks) of one period of one of the user\'s own gradebooks in Skore, '
        'the Smartschool module for scores and reports, with the pupils\' '
        'grades. Without period_id, the period Skore opens the gradebook on '
        '(active); read_skore_gradebook lists the periods with their period '
        'ids. Per evaluation: its evaluation id (the id to use: Skore\'s '
        'column letter changes when an evaluation is added), title and short '
        'name, date, max, component, type (points or a scale), whether it '
        'comes from the planner, and its publication: not published, '
        'scheduled (with the time, Smartschool time, Belgium) or published. '
        'The pupils see a published evaluation and its grades, and a '
        'scheduled one from its time on: tell the user when that matters. '
        'Then the class and group averages and each pupil\'s grade as Skore '
        'stores it (with a decimal point), marked "feedback" when the pupil '
        'has feedback on it, which read_skore_feedback reads; the pupil ids '
        'are listed once, after the evaluations. With evaluation_id, only '
        'that evaluation, one line per pupil with the pupil id; without '
        'period_id, it is looked for in every period. A period without '
        'evaluations gets a sentence saying so. Reading changes nothing in '
        'Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'The period, by its period id from read_skore_gradebook. '
              'Default: the period Skore opens the gradebook on (active); '
              'with evaluation_id, the period that holds it.',
          minimum: 1,
        ),
        'evaluation_id': Schema.int(
          description:
              'Only this evaluation, by its evaluation id from this tool, '
              'with one line per pupil. Default: every evaluation of the '
              'period.',
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
      required: ['gradebook_id'],
    ),
    annotations: ToolAnnotations(
      title: 'List the evaluations of a period in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final periodId = intArgument(arguments, 'period_id');
  final evaluationId = intArgument(arguments, 'evaluation_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final text = await withSkoreGradebook(session, (gradebooks) async {
    final (:sheet, :workyear) = await readSkoreGradebook(
      gradebooks,
      years,
      gradebookId,
      workyearId: workyearId,
    );
    final title = '${formatSkoreGradebookTitle(sheet.gradebook, workyear)}.';
    if (evaluationId != null) {
      final found = await findSkoreEvaluation(
        gradebooks,
        sheet,
        evaluationId,
        periodId: periodId,
      );
      return formatSkoreEvaluationGrades(
        sheet,
        found.period,
        found.evaluation,
        title: title,
      );
    }
    final period = skoreGradebookPeriod(sheet, periodId);
    if (period == null) {
      return '$title\nIt has no periods yet, so it has no evaluations.';
    }
    return formatSkorePeriodEvaluations(
      sheet,
      period,
      await gradebooks.getEvaluations(sheet.gradebook, period.id),
      title: title,
    );
  });
  return CallToolResult(content: [TextContent(text: text)]);
}

/// What `list_skore_evaluations` answers for a period: [title], the period,
/// its [evaluations] in Skore's order, each with its averages and its
/// grades on one line, the pupils with their ids, and the gradebook's other
/// periods.
String formatSkorePeriodEvaluations(
  SkoreGradebookSheet sheet,
  SkoreGradebookPeriod period,
  List<SkoreEvaluation> evaluations, {
  required String title,
}) {
  final pupils = sheet.pupils;
  final count = evaluations.length;
  final others = [
    for (final other in sheet.periods)
      if (other.id != period.id)
        '${skoreName(other.name)} (period id ${other.id}'
            '${other.id == sheet.activePeriod?.id ? ', active' : ''})',
  ];
  return [
    title,
    _periodLine(sheet, period),
    if (evaluations.isEmpty)
      'It has no evaluations.'
    else ...[
      '$count ${count == 1 ? 'evaluation' : 'evaluations'}, in Skore\'s '
          'order, each with the grade of every pupil ("(feedback)": the pupil '
          'has feedback on it, which read_skore_feedback reads):',
      for (final evaluation in evaluations) ...[
        '- ${formatSkoreEvaluation(evaluation)}',
        '  ${formatSkoreEvaluationResults(evaluation.results)}',
        '  grades: ${_gradesLine(sheet, evaluation.results)}',
      ],
      if (pupils.isEmpty)
        'No pupils.'
      else
        'Pupils: ${[for (final pupil in pupils) _pupilWithId(pupil)].join('; ')}.',
    ],
    if (others.isNotEmpty)
      'Other periods of the gradebook: ${others.join(', ')}. Pass period_id '
          'for one of them.',
  ].join('\n');
}

/// What `list_skore_evaluations` answers for one evaluation: [title], its
/// period, the evaluation with its averages, and one line per pupil with
/// the pupil id, the grade and whether the pupil has feedback on it.
String formatSkoreEvaluationGrades(
  SkoreGradebookSheet sheet,
  SkoreGradebookPeriod period,
  SkoreEvaluation evaluation, {
  required String title,
}) {
  final results = evaluation.results;
  final max = evaluation.max;
  final rows = _rows(sheet, results);
  return [
    title,
    _periodLine(sheet, period),
    'Evaluation: ${formatSkoreEvaluation(evaluation)}',
    formatSkoreEvaluationResults(results),
    if (rows.isEmpty)
      'No pupils.'
    else ...[
      'Grades${max == null ? '' : ' out of ${formatSkoreNumber(max)}'}, one '
          'line per pupil in Skore\'s order ("feedback": the pupil has '
          'feedback on it, which read_skore_feedback reads):',
      for (final (pupil, grade) in rows)
        [
          '- ${pupil == null ? 'pupil id ${grade!.pupilId}' : formatSkoreGradebookPupil(pupil)}',
          formatSkoreGradeValue(grade),
          if (grade?.hasFeedback ?? false) 'feedback',
        ].join(' | '),
    ],
  ].join('\n');
}

/// The period of a result: its name and id, whether it is open, and whether
/// Skore opens the gradebook on it.
String _periodLine(SkoreGradebookSheet sheet, SkoreGradebookPeriod period) {
  final active = period.id == sheet.activePeriod?.id;
  return 'Period ${formatSkorePeriodName(period)}: '
      '${formatSkorePeriodState(period)}'
      '${active ? '; Skore opens the gradebook on it (active)' : ''}.';
}

/// The grades of an evaluation on one line, pupils in Skore's order:
/// `1. Aerts, An: 79 (feedback); 3. Dupont, Chloé: no grade`.
String _gradesLine(SkoreGradebookSheet sheet, SkoreEvaluationResults results) {
  final rows = _rows(sheet, results);
  if (rows.isEmpty) return 'no pupils';
  return [
    for (final (pupil, grade) in rows)
      '${switch (pupil) {
            null => 'pupil id ${grade!.pupilId}',
            SkoreGradebookPupil(isActive: true) => _pupilName(pupil),
            _ => '${_pupilName(pupil)} (inactive)',
          }}: ${formatSkoreGradeValue(grade)}'
          '${grade?.hasFeedback ?? false ? ' (feedback)' : ''}',
  ].join('; ');
}

/// The rows of an evaluation's grades: every pupil of the gradebook in
/// Skore's order with their cell (null when Skore gave none), then the
/// cells of pupils the gradebook does not list (without a pupil).
List<(SkoreGradebookPupil?, SkoreGrade?)> _rows(
  SkoreGradebookSheet sheet,
  SkoreEvaluationResults results,
) {
  final known = {for (final pupil in sheet.pupils) pupil.id};
  return [
    for (final pupil in sheet.pupils) (pupil, results.gradeOf(pupil.id)),
    for (final grade in results.grades)
      if (!known.contains(grade.pupilId)) (null, grade),
  ];
}

/// A pupil's class number (when Skore shows one) and name, last name
/// first: `1. Aerts, An`.
String _pupilName(SkoreGradebookPupil pupil) =>
    '${pupil.number == null ? '' : '${pupil.number}. '}'
    '${skoreName(pupil.name)}';

/// A pupil with their id: `1. Aerts, An (pupil id 1201)`.
String _pupilWithId(SkoreGradebookPupil pupil) =>
    '${_pupilName(pupil)} (pupil id ${pupil.id})';
