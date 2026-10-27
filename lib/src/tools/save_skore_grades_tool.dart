import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// The name of the tool, as its messages name it.
const _tool = 'save_skore_grades';

/// `save_skore_grades`: saves the grades of pupils in one evaluation of one
/// of the user's gradebooks in Skore, or clears them, with the library's
/// [SkoreGradebookService.saveGrades] (dartschool#151): the whole list in
/// one call, so one approval for a list the user saw.
///
/// A gradebook a colleague shared with the user to read and write takes
/// grades as an own one does (#167, dartschool#191); one shared to read only
/// is refused in the tool's own words before it is read
/// ([checkSkoreGradebookChangeable]), and the library refuses it too.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools. Claude Desktop must ask for approval before every call, so the
/// tool is marked destructive; saving the same grades again gives the same
/// state, so it is idempotent. The pupils are taken by their pupil ids,
/// which Claude matches to the names the user gave with
/// `list_skore_evaluations`: names are ambiguous.
///
/// Only an evaluation in points takes grades: one on a scale, whose values
/// the library does not save, and one the library could not read, are
/// refused in the tool's own words before the library is asked
/// ([_checkInPoints], #169). An evaluation its pupils see (published or
/// scheduled) is refused unless `allow_published` is true
/// ([checkSkoreWritePublication]). The library
/// reads the gradebook again and refuses the whole list when one grade does
/// not fit, saving nothing; it saves one pupil at a time and reads the
/// period again to confirm them. Grades it cannot confirm are reported per
/// pupil, with those it did confirm: saving a grade again is harmless, so
/// Claude may read them again and save the ones that differ.
ServerTool saveSkoreGradesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: _tool,
    title: 'Save the grades of an evaluation in Skore',
    description:
        'Saves the grades of pupils in one evaluation (a column of grades, '
        'such as a test) of one of the user\'s gradebooks in Skore, the '
        'Smartschool module for scores and reports (their own, or one a '
        'colleague shared with them to read and write), as typing them into '
        'the gradebook does: the whole list in one call, such as the grades '
        'of a test the user gives as names with grades or as a pasted table. A '
        'grade is a number from 0 up to the evaluation\'s max, with a '
        'decimal point or comma (15, 15.5 or 15,5); an empty grade or null '
        'clears it. Before calling this tool, read the evaluation with '
        'list_skore_evaluations (with its evaluation_id) and match each name '
        'the user gave to a pupil id there; never guess a pupil for a name '
        'that matches no pupil or more than one: ask the user. Show the user '
        'the full list, each pupil with class number and name, the current '
        'grade and the new grade, out of the max, and only call this tool '
        'after the user has explicitly confirmed it. In a gradebook a '
        'colleague shared with the user, also tell the user whose gradebook '
        'it is: its owner, as list_skore_gradebooks and '
        'list_skore_evaluations name them. A gradebook shared with the user '
        'to read only is refused: the user may read it, not change it. Only '
        'a gradebook of '
        'Skore\'s current school year can be changed. An evaluation that is '
        'published or scheduled is refused unless allow_published is true: '
        'a grade there is visible to its pupils at once, and the school '
        'sends them a notification; in a scheduled one, from its publication '
        'time on. Pass allow_published: true only after telling the user '
        'exactly that and getting their explicit yes for it. The server '
        'reads the gradebook again before it saves, and when one grade does '
        'not fit (not a number, above the max, a pupil not in the gradebook, '
        'a closed or read-only period, an evaluation from the planner), it '
        'saves none: the result says why. Only an evaluation in points takes '
        'grades: one on a scale (Skore\'s "Waarderingen", such as for '
        'behaviour; its type in list_skore_evaluations) is refused, as the '
        'server cannot save a value on a scale, and so is one of a type the '
        'server does not support; the user enters those in Smartschool. The '
        'result gives '
        'each pupil\'s grade as Skore lists it after the save, and the '
        'evaluation\'s publication. If the result says some grades may or '
        'may not have been saved: saving a grade again is harmless, so read '
        'the evaluation again with list_skore_evaluations, tell the user what '
        'you found, and save only the grades that differ.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description:
              'The gradebook id, from list_skore_gradebooks: a gradebook of '
              'Skore\'s current school year.',
          minimum: 1,
        ),
        'evaluation_id': Schema.int(
          description:
              'The evaluation, by its evaluation id from '
              'list_skore_evaluations.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'The period of the evaluation, by its period id from '
              'list_skore_evaluations, to find the evaluation with one read. '
              'Default: it is looked for in every period of the gradebook.',
          minimum: 1,
        ),
        'grades': Schema.list(
          description:
              'The grades to save, as the user confirmed them: each pupil '
              'once, with the new grade.',
          items: Schema.object(
            properties: {
              'pupil_id': Schema.int(
                description:
                    'The pupil, by the pupil id list_skore_evaluations gives '
                    'for the evaluation.',
                minimum: 1,
              ),
              'grade': Schema.combined(
                description:
                    'The new grade as text: a number from 0 up to the '
                    'evaluation\'s max, such as "15", "15.5" or "15,5". An '
                    'empty text or null clears the pupil\'s grade.',
                anyOf: [Schema.string(), Schema.nil()],
              ),
            },
            required: ['pupil_id', 'grade'],
          ),
          minItems: 1,
        ),
        'allow_published': Schema.bool(
          description:
              'true to save in an evaluation that is published or '
              'scheduled: its pupils see the grades at once, and the school '
              'sends them a notification (in a scheduled one, from its '
              'publication time on). Only after telling the user so and '
              'getting their explicit yes. Default false.',
        ),
      },
      required: ['gradebook_id', 'evaluation_id', 'grades'],
    ),
    annotations: ToolAnnotations(
      title: 'Save the grades of an evaluation in Skore',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _save(session, request.arguments ?? const {}),
);

/// What the grades go into: the gradebook as read (with its pupils), the
/// period and the evaluation as read right before the save, and the pupils
/// of the call by pupil id.
typedef _Target = ({
  SkoreGradebookSheet sheet,
  SkoreGradebookPeriod period,
  SkoreEvaluation evaluation,
  Map<int, SkoreGradebookPupil> pupils,
});

Future<CallToolResult> _save(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final evaluationId = requiredIntArgument(arguments, 'evaluation_id');
  final periodId = intArgument(arguments, 'period_id');
  final grades = _gradesArgument(arguments);
  final allowPublished = arguments['allow_published'] == true;

  final years = SkoreGradebookYears.of(session);
  // What the grades go into, for grades Skore did not confirm: set before
  // the saves are sent.
  _Target? target;
  try {
    final (to, saved) = await withSkoreGradebookWrite(
      session,
      reread: _reread(gradebookId, evaluationId),
      (gradebooks) async {
        final found = await years.findInCurrentYear(gradebooks, gradebookId);
        // The library refuses it as well, before anything is sent; this
        // says it in the server's words, before the gradebook is read.
        checkSkoreGradebookChangeable(found.gradebook);
        final sheet = await gradebooks.getGradebook(found.gradebook);
        final pupils = _pupils(sheet, grades.keys);
        final listed = await findSkoreEvaluation(
          gradebooks,
          sheet,
          evaluationId,
          periodId: periodId,
        );
        final evaluation = listed.evaluation;
        final to = (
          sheet: sheet,
          period: listed.period,
          evaluation: evaluation,
          pupils: pupils,
        );
        // The library refuses both as well, after reading Skore again, in
        // words for a caller of the library (#169).
        _checkInPoints(to);
        // The library refuses it as well, but its refusal cannot be told
        // apart from the others (dartschool#157, #148).
        checkSkoreWritePublication(
          evaluation,
          where: _where(to),
          what: 'the grades',
          tool: _tool,
          allowPublished: allowPublished,
        );
        target = to;
        final saved = await gradebooks.saveGrades(
          sheet.gradebook,
          evaluation,
          grades,
          allowPublished: allowPublished,
        );
        return (to, saved);
      },
    );
    return CallToolResult(
      content: [TextContent(text: _savedText(to, grades.keys, saved))],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // Caught as the base type, so that a save Skore did not confirm is never
    // reported as an unexpected error; saveGrades throws its subtype, with
    // the pupils it confirmed. Only saveGrades throws it, after target is
    // set.
    final to = target;
    if (to == null) rethrow;
    return _notConfirmed(to, grades, error);
  }
}

/// The `grades` argument: each pupil's grade (a text, or null to clear it)
/// by pupil id, in the order given.
///
/// Throws a [ToolError] for a pupil given twice, and for an empty list
/// (which the input schema refuses first), before anything is sent.
Map<int, String?> _gradesArgument(Map<String, Object?> arguments) {
  final items = arguments['grades'];
  if (items is! List || items.isEmpty) {
    throw const ToolError(
      'grades must list at least one pupil, each with a pupil_id and a '
      'grade. Nothing was changed in Skore.',
    );
  }
  final grades = <int, String?>{};
  final twice = <int>{};
  for (final item in items) {
    final fields = (item as Map).cast<String, Object?>();
    final pupilId = requiredIntArgument(fields, 'pupil_id');
    if (grades.containsKey(pupilId)) {
      twice.add(pupilId);
    } else {
      grades[pupilId] = fields['grade'] as String?;
    }
  }
  if (twice.isNotEmpty) {
    throw ToolError(
      'grades lists ${twice.length == 1 ? 'pupil id' : 'pupil ids'} '
      '${twice.join(', ')} more than once: give each pupil once, with the '
      'grade the user confirmed. Nothing was changed in Skore.',
    );
  }
  return grades;
}

/// The pupils of [sheet] with the pupil ids [ids], by pupil id.
///
/// Throws a [ToolError] that names every id the gradebook has no pupil
/// with, and where to take the ids from; nothing is saved.
Map<int, SkoreGradebookPupil> _pupils(
  SkoreGradebookSheet sheet,
  Iterable<int> ids,
) {
  final byId = {for (final pupil in sheet.pupils) pupil.id: pupil};
  final unknown = [
    for (final id in ids)
      if (!byId.containsKey(id)) id,
  ];
  if (unknown.isNotEmpty) {
    final which = unknown.length == 1
        ? 'pupil with pupil id'
        : 'pupils with pupil ids';
    final none = sheet.pupils.isEmpty ? ': it has no pupils' : '';
    throw ToolError(
      'The ${formatSkoreGradebookName(sheet.gradebook)} has no $which '
      '${unknown.join(', ')}$none. Take the pupil ids from '
      'list_skore_evaluations with the evaluation_id, for this gradebook.',
    );
  }
  return {for (final id in ids) id: byId[id]!};
}

/// Refuses the grades for the evaluation of [to] when it is not one in
/// points whose grades the server reads (#169): one on a scale
/// ([SkoreEvaluationType.scale], "Waarderingen"), whose values the library
/// does not save (it saves grades in points only, flutter_smartschool
/// 0.4.0), or one the library could not read (not
/// [SkoreEvaluation.isReadable]: a type it does not know, or a cell in a
/// shape it does not recognise), which it refuses to write in.
///
/// Throws a [ToolError] that says which and what to tell the user, before
/// the library is asked: nothing is sent. The library refuses both too,
/// after reading Skore again, with a `SmartschoolSkoreChangeRefusedError`
/// worded for its caller ("not in points (evaltype 2)"), which would come
/// out as a refusal of Skore's.
void _checkInPoints(_Target to) {
  final evaluation = to.evaluation;
  final name = '${formatSkoreEvaluationName(evaluation)} in ${_where(to)}';
  if (!evaluation.isReadable) {
    throw ToolError(
      'The server cannot read the $name: '
      '${skoreUnreadableReason(evaluation)}, so $_tool saves no grades in '
      'it. Tell the user so; they can enter its grades in Skore in '
      'Smartschool itself.',
    );
  }
  if (evaluation.type != SkoreEvaluationType.points) {
    throw ToolError(
      'The $name is an evaluation on a scale: its values are levels of the '
      'school\'s scale, which list_skore_evaluations shows, not points. '
      '$_tool saves grades in points only, and the server cannot save a '
      'value on a scale yet. Tell the user so; they can enter its values in '
      'Skore in Smartschool itself. Feedback on it can be given with '
      'save_skore_feedback.',
    );
  }
}

/// What to read again after a change Skore refused, to correct the call.
String _reread(int gradebookId, int evaluationId) =>
    'Read the evaluation again with list_skore_evaluations (gradebook_id '
    '$gradebookId, evaluation_id $evaluationId: its max, its publication and '
    'the pupil ids) and the gradebook with read_skore_gradebook (whether the '
    'period is open and the user may change it)';

/// The period and gradebook of [to]: `period DW1 (period id 1704) of the
/// gradebook of 6EWI for ... (gradebook id 32508)`.
String _where(_Target to) =>
    'period ${formatSkorePeriodName(to.period)} of the '
    '${formatSkoreGradebookName(to.sheet.gradebook)}';

/// The evaluation of [to] and where it is, for the first line of a result.
String _evaluationIn(_Target to) =>
    '${formatSkoreEvaluationName(to.evaluation)} in ${_where(to)}';

/// One pupil of [to] with [grade], their cell as Skore lists it.
String _gradeLine(_Target to, int pupilId, SkoreGrade? grade) =>
    '- ${formatSkoreGradebookPupil(to.pupils[pupilId]!)} | '
    '${formatSkoreGradeValue(grade)}';

/// The pupils: `the grade of 1 pupil`, `the grades of 3 pupils`.
String _gradesOf(int count) =>
    count == 1 ? 'the grade of 1 pupil' : 'the grades of $count pupils';

/// What the tool answers when every grade was saved: each pupil (in the
/// order of [pupilIds]) with the grade as Skore lists it after the save
/// ([saved]), and the evaluation with its publication.
String _savedText(
  _Target to,
  Iterable<int> pupilIds,
  Map<int, SkoreGrade> saved,
) {
  final max = to.evaluation.max;
  return [
    'Saved ${_gradesOf(pupilIds.length)} in the ${_evaluationIn(to)}.',
    'Evaluation: ${formatSkoreEvaluation(to.evaluation)}',
    'Grades${max == null ? '' : ' out of ${formatSkoreNumber(max)}'} as '
        'Skore lists them after the save, in the order given:',
    for (final id in pupilIds) _gradeLine(to, id, saved[id]),
  ].join('\n');
}

/// The result for [grades] that went out to Skore without Skore confirming
/// all of them ([error]): the pupils whose grade it confirmed, with the
/// grade as read again, and the others, with the grade sent, which may or
/// may not have been saved. Saving a grade again is harmless, so Claude may
/// read the grades again and save the ones that differ, after telling the
/// user.
///
/// The library's message says per pupil why a grade is not confirmed, and
/// can quote Skore's answers: it goes to the log only.
CallToolResult _notConfirmed(
  _Target to,
  Map<int, String?> grades,
  SmartschoolSkoreSaveUnconfirmedError error,
) {
  log(
    '$_tool: Skore did not confirm every grade: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  final (confirmed, sent) = switch (error) {
    SmartschoolSkoreGradeSaveUnconfirmedError(
      :final confirmed,
      :final grades,
    ) =>
      (confirmed, grades),
    _ => (const <int, SkoreGrade>{}, const <int, String>{}),
  };
  final count = grades.length;
  final unconfirmed = [
    for (final id in grades.keys)
      if (!confirmed.containsKey(id)) id,
  ];
  final which = confirmed.isNotEmpty
      ? '${unconfirmed.length} of them'
      : count == 1
      ? 'it'
      : 'any of them';
  final period = to.period.id;
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '${_capitalized(_gradesOf(count))} in the ${_evaluationIn(to)} '
              '${count == 1 ? 'was' : 'were'} sent, but Skore did not confirm '
              '$which.',
          if (confirmed.isNotEmpty) ...[
            'Saved, as Skore lists them after the save:',
            for (final id in grades.keys)
              if (confirmed[id] case final cell?) _gradeLine(to, id, cell),
          ],
          'May or may not have been saved:',
          for (final id in unconfirmed)
            '- ${formatSkoreGradebookPupil(to.pupils[id]!)} | sent: '
                '${_sent(sent[id] ?? grades[id]?.trim() ?? '')}',
          'Saving a grade again is harmless: read the evaluation again with '
              'list_skore_evaluations (gradebook_id '
              '${to.sheet.gradebook.gradebookId}, evaluation_id '
              '${to.evaluation.id}, period_id $period), tell the user what you '
              'found, and save only the grades that differ from the ones the '
              'user confirmed again with $_tool.',
        ].join('\n'),
      ),
    ],
  );
}

/// A grade as it was sent: `15.5`, or `empty, to clear the grade`.
String _sent(String grade) =>
    grade.isEmpty ? 'empty, to clear the grade' : grade;

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
