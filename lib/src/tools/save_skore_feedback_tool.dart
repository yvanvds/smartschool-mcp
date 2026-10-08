import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// The name of the tool, as its messages name it.
const _tool = 'save_skore_feedback';

/// `save_skore_feedback`: gives one pupil the user's written feedback on one
/// evaluation of one of the user's own gradebooks in Skore, or changes the
/// text of the feedback the user gave them there, with the library's
/// [SkoreGradebookService.saveFeedback] (dartschool#152). One pupil per
/// call: each text is personal, and the user should see each one.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools. Claude Desktop must ask for approval before every call, so the
/// tool is marked destructive; a first call creates the feedback, so it is
/// not marked idempotent, although a second call changes that feedback
/// rather than adding one (the library reads the pupil's feedback first),
/// which the description says.
///
/// An evaluation its pupils see (published or scheduled) is refused unless
/// `allow_published` is true ([checkSkoreWritePublication]). The tool reads
/// the pupil's feedback itself before the library is asked, and refuses in
/// its own words when the user has more than one feedback of their own
/// there or one Skore does not let them change ([_checkOwnFeedback]): the
/// library refuses both too, but with a refusal that cannot be told apart
/// from its others (yvanvds/dartschool#158, removal tracked in
/// yvanvds/smartschool-mcp#149). That read also tells whether the save
/// changed the user's feedback or created one, which the library's result
/// does not say. Feedback by others is never sent: the library keeps to the
/// user's own.
ServerTool saveSkoreFeedbackTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: _tool,
    title: 'Give a pupil feedback on an evaluation in Skore',
    description:
        'Gives one pupil the user\'s written feedback on one evaluation (a '
        'column of grades, such as a test) of one of the user\'s own '
        'gradebooks in Skore, the Smartschool module for scores and reports, '
        'or changes the feedback the user gave that pupil there before. One '
        'pupil per call: each text is personal. The text is plain text; line '
        'breaks are kept. Before calling this tool, read the pupil\'s '
        'feedback on the evaluation with read_skore_feedback. When the user '
        'already gave feedback there, this tool replaces its text: show the '
        'user the old text and the new one. Show the user the pupil (class '
        'number and name), the evaluation and the text, and only call this '
        'tool after the user has explicitly confirmed it. Feedback that '
        'others gave the pupil is never changed. Only a gradebook of Skore\'s '
        'current school year can be changed. An evaluation that is published '
        'or scheduled is refused unless allow_published is true: feedback '
        'there is visible to the pupil at once, and the school sends them a '
        'notification; in a scheduled one, from its publication time on. Pass '
        'allow_published: true only after telling the user exactly that and '
        'getting their explicit yes for it. The server reads the pupil\'s '
        'feedback again before it saves: it changes the user\'s feedback when '
        'there is one, and refuses when the user has more than one there or '
        'Skore does not let them change it. The result gives the feedback as '
        'Skore lists it after the save: whether it is new or changed, its '
        'text and its time. If the result says the feedback may or may not '
        'have been saved: read it with read_skore_feedback and tell the user '
        'what you found; calling this tool again is safe, as it changes the '
        'user\'s feedback rather than adding a second.',
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
        'pupil_id': Schema.int(
          description:
              'The pupil, by the pupil id list_skore_evaluations or '
              'read_skore_feedback gives.',
          minimum: 1,
        ),
        'text': Schema.string(
          description:
              'The feedback as the user confirmed it: plain text, line breaks '
              'kept, not blank. It replaces the text of the user\'s feedback '
              'for the pupil on the evaluation, when there is one.',
        ),
        'allow_published': Schema.bool(
          description:
              'true to save feedback on an evaluation that is published or '
              'scheduled: the pupil sees it at once, and the school sends '
              'them a notification (in a scheduled one, from its publication '
              'time on). Only after telling the user so and getting their '
              'explicit yes. Default false.',
        ),
      },
      required: ['gradebook_id', 'evaluation_id', 'pupil_id', 'text'],
    ),
    annotations: ToolAnnotations(
      title: 'Give a pupil feedback on an evaluation in Skore',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _save(session, request.arguments ?? const {}),
);

/// What the feedback goes into: the gradebook as read, the period and the
/// evaluation as read right before the save, the pupil, and the user's own
/// feedback for the pupil there as the tool read it (null for none).
typedef _Target = ({
  SkoreGradebookSheet sheet,
  SkoreGradebookPeriod period,
  SkoreEvaluation evaluation,
  SkoreGradebookPupil pupil,
  SkoreFeedback? existing,
});

Future<CallToolResult> _save(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final evaluationId = requiredIntArgument(arguments, 'evaluation_id');
  final periodId = intArgument(arguments, 'period_id');
  final pupilId = requiredIntArgument(arguments, 'pupil_id');
  final text = (arguments['text'] as String? ?? '').trim();
  final allowPublished = arguments['allow_published'] == true;
  // Refused before anything is sent: the library refuses it too, but after
  // the reads below.
  if (text.isEmpty) {
    throw const ToolError(
      'text must not be blank: give the feedback the user confirmed. Nothing '
      'was changed in Skore.',
    );
  }

  final years = SkoreGradebookYears.of(session);
  // What the feedback goes into, for a save Skore did not confirm: set
  // before the save is sent.
  _Target? target;
  try {
    final (to, saved) = await withSkoreGradebookWrite(
      session,
      reread: _reread(gradebookId, evaluationId, pupilId),
      (gradebooks) async {
        final found = await years.findInCurrentYear(gradebooks, gradebookId);
        final sheet = await gradebooks.getGradebook(found.gradebook);
        final pupil = skoreGradebookPupil(sheet, pupilId);
        final listed = await findSkoreEvaluation(
          gradebooks,
          sheet,
          evaluationId,
          periodId: periodId,
        );
        final evaluation = listed.evaluation;
        final where = _where(sheet, listed.period);
        // The library refuses it as well, but its refusal cannot be told
        // apart from the others (dartschool#157, #148).
        checkSkoreWritePublication(
          evaluation,
          where: where,
          what: 'the feedback',
          tool: _tool,
          allowPublished: allowPublished,
        );
        // The user's own feedback, as the library keeps to it: by the
        // gradebook's teacher, the user for every gradebook of their own.
        final own = [
          for (final feedback in await gradebooks.getFeedback(
            sheet.gradebook,
            evaluation,
            pupil.id,
          ))
            if (feedback.teacherId == sheet.gradebook.teacherId) feedback,
        ];
        final to = (
          sheet: sheet,
          period: listed.period,
          evaluation: evaluation,
          pupil: pupil,
          existing: own.firstOrNull,
        );
        // The library refuses these as well, but its refusals cannot be
        // told apart from the others (dartschool#158, #149).
        _checkOwnFeedback(to, own);
        target = to;
        try {
          final saved = await gradebooks.saveFeedback(
            sheet.gradebook,
            evaluation,
            pupil.id,
            text,
            allowPublished: allowPublished,
          );
          return (to, saved);
        } on SmartschoolSkoreChangeRefusedError {
          rethrow;
        } on SmartschoolSkoreError catch (error) {
          // Skore refused the save (a 4xx, whose title and detail can quote
          // the text), or a read before it gave an answer the library cannot
          // use: nothing was saved either way. The message to the log only.
          log(
            '$_tool: Skore did not save the feedback: '
            '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
          );
          throw ToolError(
            'Skore did not save the feedback for ${_pupilName(pupil)} on the '
            '${formatSkoreEvaluationName(evaluation)} in $where: it refused '
            'the save, or gave an answer the server could not use; the '
            'technical details are in the server log. Tell the user; trying '
            'again in a moment may help, else the user can give the feedback '
            'in Smartschool.',
          );
        }
      },
    );
    return CallToolResult(content: [TextContent(text: _savedText(to, saved))]);
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // Caught as the base type, so that a save Skore did not confirm is never
    // reported as an unexpected error; saveFeedback throws its subtype, with
    // whether it was a change. Only saveFeedback throws it, after target is
    // set.
    final to = target;
    if (to == null) rethrow;
    return _notConfirmed(to, error);
  }
}

/// Refuses the save in [to] when the user's own feedback for the pupil,
/// [own] as the tool has just read it, is more than one (the library
/// changes none of them, as it cannot tell which one is meant) or one that
/// Skore does not let the user change.
///
/// Throws a [ToolError] that says so and what to tell the user; nothing is
/// sent. The library refuses both as well, from the feedback as it reads
/// it right before the save, but with a `SmartschoolSkoreChangeRefusedError`
/// that cannot be told apart from its other refusals, worded for a caller
/// of the library (yvanvds/dartschool#158, removal tracked in
/// yvanvds/smartschool-mcp#149). When the feedback changes between the two
/// reads, the library's refusal is passed on as any other.
void _checkOwnFeedback(_Target to, List<SkoreFeedback> own) {
  final on =
      '${_pupilName(to.pupil)} on the '
      '${formatSkoreEvaluationName(to.evaluation)} in '
      '${_where(to.sheet, to.period)}';
  if (own.length > 1) {
    final written = [
      for (final feedback in own)
        if (feedback.createdAt case final at?) formatSkoreTime(at),
    ];
    throw ToolError(
      'The user has ${own.length} feedback texts of their own for $on'
      '${written.length == own.length ? ' (written ${written.join(', ')})' : ''}: '
      'the server changes none of them, as it cannot tell which one is '
      'meant. Show them to the user with read_skore_feedback, and tell the '
      'user to keep only one of them in Smartschool; then '
      '$_tool changes that one.',
    );
  }
  final existing = own.firstOrNull;
  if (existing != null && !existing.canEdit) {
    final at = existing.createdAt;
    throw ToolError(
      'Skore does not let the user change their feedback for $on'
      '${at == null ? '' : ' (written ${formatSkoreTime(at)})'}, so the '
      'server cannot save the new text, and it does not add a second '
      'feedback next to it. Tell the user so; read_skore_feedback shows the '
      'feedback as it is.',
    );
  }
}

/// What to read again after a change Skore refused, to correct the call.
String _reread(int gradebookId, int evaluationId, int pupilId) =>
    'Read the pupil\'s feedback again with read_skore_feedback (gradebook_id '
    '$gradebookId, evaluation_id $evaluationId, pupil_id $pupilId: the '
    'user\'s feedback and the evaluation\'s publication) and the gradebook '
    'with read_skore_gradebook (whether the period is open and the user may '
    'change it)';

/// [period] and the gradebook of [sheet]: `period DW1 (period id 1704) of
/// the gradebook of 6EWI for ... (gradebook id 32508)`.
String _where(SkoreGradebookSheet sheet, SkoreGradebookPeriod period) =>
    'period ${formatSkorePeriodName(period)} of the '
    '${formatSkoreGradebookName(sheet.gradebook)}';

/// A pupil in a sentence: `Aerts, An (pupil id 1201)`.
String _pupilName(SkoreGradebookPupil pupil) =>
    '${skoreName(pupil.name)} (pupil id ${pupil.id})';

/// The pupil and the evaluation of [to] and where it is, for the first line
/// of a result.
String _forPupilOn(_Target to) =>
    'for ${_pupilName(to.pupil)} on the '
    '${formatSkoreEvaluationName(to.evaluation)} in '
    '${_where(to.sheet, to.period)}';

/// What the tool answers when the feedback was saved: whether it changed
/// the user's feedback or is new, the evaluation with its publication, and
/// [saved] as Skore lists it after the save.
///
/// It is a change when the library saved the feedback the tool read as the
/// user's ([_Target.existing]); the library's result does not say it.
String _savedText(_Target to, SkoreFeedback saved) {
  final changed = to.existing?.id == saved.id;
  return [
    changed
        ? 'Changed the text of the user\'s feedback ${_forPupilOn(to)}.'
        : 'Saved new feedback of the user ${_forPupilOn(to)}.',
    'Evaluation: ${formatSkoreEvaluation(to.evaluation)}',
    'The feedback as Skore lists it after the save:',
    formatSkoreFeedback(saved, byUser: true),
  ].join('\n');
}

/// The result for feedback that went out to Skore without Skore confirming
/// it ([error]): it may or may not have been saved. Claude reads the pupil's
/// feedback and tells the user; calling the tool again is safe, as the
/// library reads first: a change sends the whole text again, and after a
/// create it changes the feedback that create made, rather than adding a
/// second. So the result says to read first, and to call again only when
/// the text is not there.
///
/// The library's message can quote Skore's answer: it goes to the log only.
CallToolResult _notConfirmed(
  _Target to,
  SmartschoolSkoreSaveUnconfirmedError error,
) {
  log(
    '$_tool: Skore did not confirm the feedback, not retrying: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  final (isUpdate, createdId) = switch (error) {
    SmartschoolSkoreFeedbackSaveUnconfirmedError(
      :final isUpdate,
      :final feedbackId,
    ) =>
      (isUpdate, isUpdate ? null : feedbackId),
    _ => (to.existing != null, null),
  };
  final read =
      'First read the pupil\'s feedback with read_skore_feedback '
      '(gradebook_id ${to.sheet.gradebook.gradebookId}, evaluation_id '
      '${to.evaluation.id}, pupil_id ${to.pupil.id}, period_id '
      '${to.period.id}) and tell the user what you found.';
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: isUpdate
            ? 'The new text of the user\'s feedback ${_forPupilOn(to)} was '
                  'sent, but Skore did not confirm it: it may or may not have '
                  'been changed. $read If its text is not the one the user '
                  'confirmed, saving it again with $_tool is harmless: it '
                  'sends the whole text again.'
            : 'The new feedback ${_forPupilOn(to)} was sent, but Skore did '
                  'not confirm it: it may or may not have been saved'
                  '${createdId == null ? '' : ' (Skore answered that it '
                            'created it, but reading the feedback again did '
                            'not confirm it)'}. $read If the user\'s '
                  'feedback is not there, or its text is not the one the '
                  'user confirmed, calling $_tool again with that text is '
                  'safe: it reads the pupil\'s feedback first, and changes '
                  'the user\'s feedback if this one was created, rather than '
                  'adding a second.',
      ),
    ],
  );
}
