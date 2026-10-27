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
const _tool = 'save_skore_report_comment';

/// `save_skore_report_comment`: writes, changes or clears the course comment
/// ("vakcommentaar") of one pupil on a report period of one of the user's
/// gradebooks in Skore (#171), the text printed on the report the pupil and
/// their parents get, with the library's
/// [SkoreGradebookService.saveReportComment] and
/// [SkoreGradebookService.clearReportComment] (dartschool#195, #203).
///
/// One pupil per call, as `save_skore_feedback` takes one: each comment is a
/// personal text that goes on a report, and the user should read and confirm
/// each one; Claude Desktop's approval of every call is that confirmation.
/// A list would not save requests either: the library writes one comment
/// per call, and reads Skore again for each (its checks, the report before
/// and after), with no list of its own. And it would leave a list half
/// written when one pupil is refused in between (a colleague changed that
/// comment), which one pupil per call never does.
///
/// Skore keeps one course comment per pupil, course and report, which the
/// colleagues who give the course share, and it does not say who wrote it.
/// So the call names the comment it replaces (`current_comment`, as
/// `read_skore_report` gave it and the user saw it), and the tool refuses,
/// before anything is sent, when Skore holds another one by then: a
/// colleague's comment is never overwritten unseen. The library guards the
/// same (`replacing`) right before its save, for a change in between. A
/// comment that already is the new text is not sent again, which makes a
/// repeat of the call (after a refused session, or by Claude) harmless, so
/// the tool is marked idempotent.
///
/// The tool refuses, in its own words and before anything is sent: a
/// gradebook shared with the user to read only
/// ([checkSkoreGradebookChangeable]), an unknown report or pupil, a closed
/// report, a report without course comments, a comment Skore does not let
/// the user change (closed for the pupil), a text longer than the report
/// allows, and another comment than `current_comment`. The library refuses
/// all of these too, in words for its caller; its refusal is passed on for a
/// change between the tool's read and its own. A gradebook a colleague
/// shared with the user to read and write takes a comment as an own one
/// does, such as the behaviour gradebook of a class that its form teacher
/// shared with the co-titularis.
///
/// Offered to every account, without a switch, like the other gradebook
/// tools. Claude Desktop must ask for approval before every call: the tool
/// is marked destructive.
ServerTool saveSkoreReportCommentTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: _tool,
    title: 'Write a pupil\'s course comment on a report in Skore',
    description:
        'Writes the course comment (vakcommentaar) of one pupil on a '
        'report period (Skore\'s "Rapporten", such as R1D, Rapport 1) of '
        'one of the user\'s gradebooks in Skore, the Smartschool module '
        'for scores and reports (their own, or one a colleague shared '
        'with them to read and write), or changes or clears it. The '
        'course comment is printed on the report that the pupil and '
        'their parents get. One pupil per call: each text is personal. '
        'The text is plain text; line breaks are kept. Skore keeps one '
        'course comment per pupil and course on a report, which the '
        'colleagues who give the course share, and it does not say who '
        'wrote it. Before calling this tool, read the pupil\'s comment '
        'with read_skore_report (with the pupil_id). Show the user the '
        'pupil (class number and name), the report, the comment now (or '
        'that there is none) and the new text (or that the comment will '
        'be cleared), and tell the user that the comment goes on the '
        'report the pupil and their parents get; only call this tool '
        'after the user has explicitly confirmed it. In a gradebook a '
        'colleague shared with the user, also tell the user whose '
        'gradebook it is: its owner, as list_skore_gradebooks and '
        'read_skore_report name them. When the pupil has a comment, pass '
        'it as current_comment, as read_skore_report gave it: this tool '
        'replaces only that comment, and refuses when Skore holds another '
        'one by then (a colleague may have written it), showing the '
        'comment now. To clear the comment, pass clear: true and '
        'current_comment, without text. A closed report is refused, and '
        'so is a comment Skore does not let the user change (closed for '
        'the pupil) and a text longer than the report allows (the limit '
        'read_skore_report gives). A gradebook shared with the user to '
        'read only is refused: the user may read it, not change it. Only '
        'a gradebook of Skore\'s current school year can be changed. A '
        'comment that already is the new text is not sent again. The '
        'result gives the comment before and as Skore shows it after the '
        'save. If the result says the comment may or may not have been '
        'saved: read it with read_skore_report and tell the user what '
        'you found; saving it again is harmless.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description:
              'The gradebook id, from list_skore_gradebooks: a gradebook '
              'of Skore\'s current school year.',
          minimum: 1,
        ),
        'report_id': Schema.int(
          description:
              'The report period, by its report id from '
              'read_skore_gradebook or read_skore_report (not a period '
              'id).',
          minimum: 1,
        ),
        'pupil_id': Schema.int(
          description:
              'The pupil, by the pupil id read_skore_report or '
              'read_skore_gradebook gives.',
          minimum: 1,
        ),
        'text': Schema.string(
          description:
              'The course comment as the user confirmed it: plain text, '
              'line breaks kept, not blank, no longer than the report '
              'allows. It replaces the pupil\'s comment on the report. '
              'Leave it out with clear: true.',
        ),
        'current_comment': Schema.string(
          description:
              'The pupil\'s comment now, as read_skore_report gave it and '
              'the user saw it, which this call replaces or clears. Leave '
              'it out when the pupil has no comment.',
        ),
        'clear': Schema.bool(
          description:
              'true to clear the pupil\'s comment instead of writing one: '
              'pass current_comment, and no text. Only after the user '
              'explicitly confirmed it. Default false.',
        ),
      },
      required: ['gradebook_id', 'report_id', 'pupil_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Write a pupil\'s course comment on a report in Skore',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _save(session, request.arguments ?? const {}),
);

/// What the comment goes on: the gradebook as read, the report period, the
/// pupil, and the pupil's comment as the tool read it right before the save.
typedef _Target = ({
  SkoreGradebookSheet sheet,
  SkoreReportPeriod period,
  SkoreGradebookPupil pupil,
  SkoreReportComment comment,
});

/// What the tool did: [saved] is the comment as Skore shows it after the
/// save, or null when nothing was sent (the comment already was the text).
typedef _Outcome = ({_Target to, SkoreReportComment? saved});

Future<CallToolResult> _save(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final reportId = requiredIntArgument(arguments, 'report_id');
  final pupilId = requiredIntArgument(arguments, 'pupil_id');
  final clear = arguments['clear'] == true;
  final given = arguments['text'] as String? ?? '';
  // The comment the user saw, which the call replaces: "" for none.
  final current = (arguments['current_comment'] as String? ?? '').trim();
  // Refused before anything is sent: the library refuses a blank text too,
  // but after its reads.
  if (clear && given.trim().isNotEmpty) {
    throw const ToolError(
      'Pass either a text or clear: true, not both: clear: true clears the '
      'pupil\'s comment. Nothing was changed in Skore.',
    );
  }
  // The text as the library sends it (each line trimmed, no more than one
  // empty line in a row), so that its length is the one Skore checks.
  final text = clear ? '' : SkoreGradebookService.reportCommentText(given);
  if (!clear && text.isEmpty) {
    throw const ToolError(
      'text must not be blank: give the course comment the user confirmed, '
      'or pass clear: true to clear the pupil\'s comment. Nothing was changed '
      'in Skore.',
    );
  }

  final years = SkoreGradebookYears.of(session);
  // What the comment goes on, for a save Skore did not confirm: set before
  // the save is sent.
  _Target? target;
  try {
    final outcome = await withSkoreGradebookWrite<_Outcome>(
      session,
      reread: _reread(gradebookId, reportId, pupilId),
      (gradebooks) async {
        final found = await years.findInCurrentYear(gradebooks, gradebookId);
        // The library refuses it as well, before anything is sent; this
        // says it in the server's words, before the gradebook is read.
        checkSkoreGradebookChangeable(found.gradebook);
        final sheet = await gradebooks.getGradebook(found.gradebook);
        final period = skoreReportPeriod(sheet, reportId);
        final pupil = skoreGradebookPupil(sheet, pupilId);
        // The library refuses it as well, after reading Skore again.
        if (!period.isOpen) {
          final closed = period.closesAt;
          throw ToolError(
            '${_capitalized(_where(sheet, period))} is closed'
            '${closed == null ? '' : ' (closing time ${formatSkoreTime(closed)})'}: '
            'its course comments can no longer be written. Tell the user so.',
          );
        }
        final report = await readSkoreReport(gradebooks, sheet, period);
        final to = _target(sheet, period, pupil, report, text);
        final comment = to.comment;
        // Nothing to send: the comment already is the text (or empty, for a
        // clear). Also what a repeat of a call that saved finds.
        if (SkoreGradebookService.sameReportComment(comment.text, text)) {
          return (to: to, saved: null);
        }
        _checkCurrent(to, current, clear: clear);
        target = to;
        final saved = clear
            ? await gradebooks.clearReportComment(
                sheet.gradebook,
                reportId,
                pupilId,
                replacing: current,
              )
            : await gradebooks.saveReportComment(
                sheet.gradebook,
                reportId,
                pupilId,
                text,
                replacing: current.isEmpty ? null : current,
              );
        return (to: to, saved: saved);
      },
    );
    return CallToolResult(
      content: [
        TextContent(
          text: switch (outcome.saved) {
            null => _unchangedText(outcome.to, clear: clear),
            final saved => _savedText(outcome.to, saved, clear: clear),
          },
        ),
      ],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // Caught as the base type, so that a save Skore did not confirm is never
    // reported as an unexpected error; the library throws its subtype. Only
    // the save throws it, after target is set.
    final to = target;
    if (to == null) rethrow;
    return _notConfirmed(to, error, clear: clear);
  }
}

/// The target of a save of [text] (`""` for a clear) on [report] for
/// [pupil], after the checks of the report that need no argument but the
/// text: the report has course comments, the pupil has one on it, Skore lets
/// the user change it, and the text fits.
///
/// Throws a [ToolError] that says why and what to tell the user; nothing is
/// sent. The library refuses each of these as well, after reading Skore
/// again, in words for its caller.
_Target _target(
  SkoreGradebookSheet sheet,
  SkoreReportPeriod period,
  SkoreGradebookPupil pupil,
  SkoreReport report,
  String text,
) {
  final where = _where(sheet, period);
  if (!report.hasComments) {
    throw ToolError(
      '${_capitalized(where)} has no course comment for this course: there '
      'is nothing to write. Tell the user so.',
    );
  }
  final comment = report.pupil(pupil.id)?.comment;
  if (comment == null) {
    throw ToolError(
      '${_pupilName(pupil)} has no course comment on $where: Skore lists '
      'none for the pupil there, so the server cannot write one. Tell the '
      'user so; read_skore_report shows the report.',
    );
  }
  if (!comment.isEditable) {
    throw ToolError(
      'Skore does not let the user change the course comment of '
      '${_pupilName(pupil)} on $where: it is closed for this pupil. Tell the '
      'user so; read_skore_report shows the comment as it is.',
    );
  }
  final max = report.commentMaxLength;
  if (max != null && text.length > max) {
    throw ToolError(
      'The text has ${text.length} characters, more than the $max that '
      '$where allows for a course comment. Shorten it with the user, and '
      'call $_tool again with the text they confirm.',
    );
  }
  return (sheet: sheet, period: period, pupil: pupil, comment: comment);
}

/// Refuses the save in [to] when the pupil's comment, as the tool has just
/// read it, is not [current], the comment the call replaces (`""`: none):
/// the colleagues who give the course share the comment, so a comment
/// written or changed since the user read it is never overwritten unseen.
///
/// Throws a [ToolError] that shows the comment now and what to do: show it
/// to the user, and call again with it as `current_comment` after they
/// confirm. Nothing is sent. The library makes the same check right before
/// its save (`replacing`), for a change in between.
void _checkCurrent(_Target to, String current, {required bool clear}) {
  final now = to.comment;
  if (SkoreGradebookService.sameReportComment(now.text, current)) return;
  final pupil = _pupilName(to.pupil);
  final where = _where(to.sheet, to.period);
  if (now.isEmpty) {
    throw ToolError(
      '$pupil has no course comment on $where now, not the one passed as '
      'current_comment: it may have been cleared since it was read. Tell the '
      'user so; only after they confirm the new text again, call $_tool again '
      'without current_comment.',
    );
  }
  throw ToolError(
    [
      current.isEmpty
          ? '$pupil has a course comment on $where already, which this call '
                'would ${clear ? 'clear' : 'replace'}:'
          : 'The course comment of $pupil on $where is not the one passed as '
                'current_comment: the colleagues who give the course share it, '
                'and it may have been changed since it was read. It is now:',
      ...formatSkoreReportCommentText(now.text),
      'Show the user this comment${clear ? '' : ' and the new text'}, and '
          'only after they confirm, call $_tool again with this comment as '
          'current_comment.',
    ].join('\n'),
  );
}

/// What to read again after a change Skore refused, to correct the call.
String _reread(int gradebookId, int reportId, int pupilId) =>
    'Read the pupil\'s comment again with read_skore_report (gradebook_id '
    '$gradebookId, report_id $reportId, pupil_id $pupilId: the comment now, '
    'whether Skore lets the user change it and whether the report is open)';

/// [period] and the gradebook of [sheet]: `report R1D (Rapport 1, report id
/// 2762) of the gradebook of 6EWI for ... (gradebook id 32508)`.
String _where(SkoreGradebookSheet sheet, SkoreReportPeriod period) =>
    '${formatSkoreReportName(period)} of the '
    '${formatSkoreGradebookName(sheet.gradebook)}';

/// A pupil in a sentence: `Aerts, An (pupil id 1201)`.
String _pupilName(SkoreGradebookPupil pupil) =>
    '${skoreName(pupil.name)} (pupil id ${pupil.id})';

/// The pupil and the report of [to], for the first line of a result.
String _forPupilOn(_Target to) =>
    'for ${_pupilName(to.pupil)} on ${_where(to.sheet, to.period)}';

/// [comment] under [label]: `label: none.`, or the label and the text,
/// indented line by line.
List<String> _comment(String label, String comment) => comment.isEmpty
    ? ['$label: none.']
    : ['$label:', ...formatSkoreReportCommentText(comment)];

/// What the tool answers when the comment was saved or cleared: what it
/// did, the comment before (as the tool read it right before the save) and
/// [saved], as Skore shows it after the save.
String _savedText(_Target to, SkoreReportComment saved, {required bool clear}) {
  final before = to.comment.text;
  return [
    clear
        ? 'Cleared the course comment ${_forPupilOn(to)}.'
        : before.isEmpty
        ? 'Wrote the course comment ${_forPupilOn(to)}.'
        : 'Changed the course comment ${_forPupilOn(to)}.',
    clear
        ? 'The report the pupil and their parents get shows no course comment '
              'for this course now.'
        : 'It is printed on the report the pupil and their parents get.',
    ..._comment('The comment before', before),
    ..._comment('The comment as Skore shows it after the save', saved.text),
  ].join('\n');
}

/// What the tool answers when nothing was sent: the pupil's comment already
/// is the text, or there is none to clear.
String _unchangedText(_Target to, {required bool clear}) => [
  clear
      ? '${_capitalized(_pupilName(to.pupil))} has no course comment on '
            '${_where(to.sheet, to.period)}, so there is nothing to clear: '
            'nothing was sent, and nothing was changed in Skore.'
      : 'The course comment ${_forPupilOn(to)} already is this text, so '
            'nothing was sent, and nothing was changed in Skore.',
  if (!clear) ..._comment('The comment', to.comment.text),
].join('\n');

/// The result for a comment that went out to Skore without Skore confirming
/// it ([error]): it may or may not have been saved (or cleared). Claude
/// reads the pupil's comment and tells the user; saving it again is
/// harmless, as the library sends the whole text, and the tool sends
/// nothing when the comment already is the text.
///
/// The library's message can quote Skore's answer: it goes to the log only.
CallToolResult _notConfirmed(
  _Target to,
  SmartschoolSkoreSaveUnconfirmedError error, {
  required bool clear,
}) {
  log(
    '$_tool: Skore did not confirm the course comment, not retrying: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  final read =
      'First read the pupil\'s comment with read_skore_report (gradebook_id '
      '${to.sheet.gradebook.gradebookId}, report_id ${to.period.id}, '
      'pupil_id ${to.pupil.id}) and tell the user what you found.';
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: clear
            ? 'The clear of the course comment ${_forPupilOn(to)} was sent, '
                  'but Skore did not confirm it: it may or may not have been '
                  'cleared. $read If it still shows the comment, clearing it '
                  'again with $_tool is harmless: pass clear: true and the '
                  'comment it shows as current_comment.'
            : 'The course comment ${_forPupilOn(to)} was sent, but Skore did '
                  'not confirm it: it may or may not have been saved. $read If '
                  'it shows the text the user confirmed, it was saved. If it '
                  'still shows the comment as it was before, saving it again '
                  'with $_tool is harmless: pass the same text, with the '
                  'comment it shows (if any) as current_comment. If it shows '
                  'another text than either, show that to the user first.',
      ),
    ],
  );
}

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
