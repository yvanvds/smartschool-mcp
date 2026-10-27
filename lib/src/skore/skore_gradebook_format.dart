import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:html/parser.dart' as html_parser;

import 'skore_format.dart';

// The output lines of the gradebook tools, in the style of the other Skore
// tools: one line per item with its parts separated by ` | `, times in the
// time of this PC (Belgium), as the planner tools show them.

/// One of the user's gradebooks: its class, its course as Skore's gradebook
/// lists it (with the grade Skore adds) and its gradebook id.
///
/// For example `6EWI | Informaticawetenschappen (2 uur) (6e j DO) |
/// gradebook id 32508`.
String formatSkoreOwnGradebook(SkoreGradebook gradebook) => [
  skoreName(gradebook.className),
  skoreName(gradebook.courseName),
  'gradebook id ${gradebook.gradebookId}',
].join(' | ');

/// A gradebook a colleague shared with the user (#167): its class, its
/// course as Skore's list of shared gradebooks names it (without a grade),
/// its gradebook id, its owner by name and user id, and what the user may
/// do in it.
///
/// For example `5WW2 | Gedrag | gradebook id 34980 | owner Céline Dupré
/// (user id 346) | shared to read and write`, or `... | shared to read
/// only`.
String formatSkoreSharedGradebook(SkoreGradebook gradebook) => [
  skoreName(gradebook.className),
  skoreName(gradebook.courseName),
  'gradebook id ${gradebook.gradebookId}',
  'owner ${formatSkoreGradebookOwner(gradebook)} (user id '
      '${gradebook.teacherId})',
  'shared to ${_sharedTo(gradebook)}',
].join(' | ');

/// The owner of [gradebook], one a colleague shared with the user: the
/// colleague's name as Skore's list of shared gradebooks gives it (first
/// name first), or their user id when it gives none. For one of the user's
/// own gradebooks, `the user`.
String formatSkoreGradebookOwner(SkoreGradebook gradebook) {
  if (!gradebook.isShared) return 'the user';
  final name = gradebook.ownerName.trim();
  return name.isEmpty
      ? 'user id ${gradebook.teacherId}'
      : skoreName(gradebook.ownerName);
}

/// What the user may do in [gradebook], one a colleague shared with them,
/// after "shared to": `read and write`, or `read only`.
String _sharedTo(SkoreGradebook gradebook) =>
    gradebook.access == SkoreGradebookAccess.read
    ? 'read only'
    : 'read and write';

/// [gradebook] in a sentence, for the first line of a tool's result: its
/// id, course, class and school year. For example `Gradebook id 32508:
/// Informaticawetenschappen (2 uur) (6e j DO), class 6EWI, school year
/// 2026-2027 (workyear id 24)`.
///
/// For a gradebook a colleague shared with the user (#167), also its owner
/// and what the user may do in it, as a second sentence: `... (workyear id
/// 24). Its owner, Céline Dupré (user id 346), shared it with the user to
/// read and write`, or `to read only`.
String formatSkoreGradebookTitle(
  SkoreGradebook gradebook,
  SkoreWorkyear workyear,
) {
  final title =
      'Gradebook id ${gradebook.gradebookId}: '
      '${skoreName(gradebook.courseName)}, class '
      '${skoreName(gradebook.className)}, school year '
      '${formatSkoreWorkyear(workyear)}';
  if (!gradebook.isShared) return title;
  return '$title. Its owner, ${formatSkoreGradebookOwner(gradebook)} (user id '
      '${gradebook.teacherId}), shared it with the user to '
      '${_sharedTo(gradebook)}';
}

/// A school year: its name and workyear id, such as `2026-2027 (workyear
/// id 24)`.
String formatSkoreWorkyear(SkoreWorkyear workyear) =>
    '${skoreName(workyear.name)} (workyear id ${workyear.id})';

/// The school years Skore offers, in its order, the one [shown] marked:
/// `School years in Skore: 2026-2027 (workyear id 24, listed here),
/// 2025-2026 (workyear id 22).`
String formatSkoreWorkyears(
  List<SkoreWorkyear> workyears,
  SkoreWorkyear shown,
) {
  if (workyears.isEmpty) return 'Skore lists no school years.';
  final years = [
    for (final year in workyears)
      '${skoreName(year.name)} (workyear id ${year.id}'
          '${year.id == shown.id ? ', listed here' : ''})',
  ];
  return 'School years in Skore: ${years.join(', ')}.';
}

/// One period of a gradebook: its name (and full name when Skore gives
/// another), period id, whether it is open and when it closes, whether
/// Skore opens the gradebook on it ([active]), and Skore's note on it
/// ([skorePeriodNote]).
///
/// For example `DW1 | period id 1704 | open, closes 2026-12-18 20:00 |
/// active | note: Open van 2026-09-18 15:30 tot en met 2026-12-18 20:00. Vul
/// hier je punten voor Dagelijks werk (periode september- oktober) in!`.
String formatSkoreGradebookPeriod(
  SkoreGradebookPeriod period, {
  required bool active,
}) {
  final name = skoreName(period.name);
  final fullName = skoreName(period.fullName);
  final note = skorePeriodNote(period);
  return [
    fullName == name ? name : '$name ($fullName)',
    'period id ${period.id}',
    formatSkorePeriodState(period),
    if (active) 'active',
    if (note != null) 'note: $note',
  ].join(' | ');
}

/// Whether [period] is open, and when it closes (or closed), in the time of
/// this PC: `open, closes 2026-12-18 20:00`, `closed, closing time
/// 2026-06-30 00:00`.
String formatSkorePeriodState(SkoreGradebookPeriod period) =>
    switch ((period.isOpen, period.closesAt)) {
      (true, final time?) => 'open, closes ${formatSkoreTime(time)}',
      (true, null) => 'open, no closing time',
      (false, final time?) => 'closed, closing time ${formatSkoreTime(time)}',
      (false, null) => 'closed',
    };

/// A period by its name and id, as a sentence or an error names it:
/// `DW1 (period id 1704)`.
String formatSkorePeriodName(SkoreGradebookPeriod period) =>
    '${skoreName(period.name)} (period id ${period.id})';

/// What a gradebook without evaluation periods ([sheet], whose `periods`
/// are empty) has, after "has": `no evaluation periods yet`; or `no
/// evaluation periods, only report periods` for one with report periods
/// only, as Skore shows a behaviour gradebook such as "Gedrag (A-stroom,
/// D/A en D)" (#168, flutter_smartschool 0.4.0). Either way it has no
/// evaluations and takes no grades.
String formatSkoreMissingPeriods(SkoreGradebookSheet sheet) =>
    sheet.reports.isEmpty
    ? 'no evaluation periods yet'
    : 'no evaluation periods, only report periods';

/// For a gradebook with report periods only ([sheet], see
/// [formatSkoreMissingPeriods]), the sentence on where its course comments
/// are, for the tools that read it; null for any other gradebook.
String? skoreReportPeriodsOnlyNote(SkoreGradebookSheet sheet) =>
    sheet.periods.isEmpty && sheet.reports.isNotEmpty
    ? 'Its course comments, one per pupil, are written in its report '
          'periods and go on the report.'
    : null;

/// A gradebook by its class, course and id, as an error names it:
/// `gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO)
/// (gradebook id 32508)`. One a colleague shared with the user also by its
/// owner (#167), so that every result and refusal of a write names whose
/// gradebook it is: `gradebook of 5WW2 for Gedrag (gradebook id 34980,
/// owner Céline Dupré)`.
String formatSkoreGradebookName(SkoreGradebook gradebook) {
  final owner = gradebook.isShared
      ? ', owner ${formatSkoreGradebookOwner(gradebook)}'
      : '';
  return 'gradebook of ${skoreName(gradebook.className)} for '
      '${skoreName(gradebook.courseName)} (gradebook id '
      '${gradebook.gradebookId}$owner)';
}

/// One evaluation of a period (#141): its title (and short name), its
/// evaluation id, Skore's column, its day, its highest grade, its
/// component, its type, whether it comes from the planner, and its
/// publication ([formatSkorePublication]), last, so that it stands out.
///
/// For example `Python scripts schrijven (short name toets-python) |
/// evaluation id 500001 | column B | 2026-09-30 | max 100 | component DW |
/// points | SCHEDULED for 2026-10-09 08:00: from then on the pupils see it
/// and its grades`.
///
/// The column is the letter Skore shows the evaluation under, for the user
/// to find it; it changes when an evaluation is added, so the tools take
/// the evaluation id.
String formatSkoreEvaluation(SkoreEvaluation evaluation) {
  final title = skoreName(evaluation.title);
  final short = evaluation.shortName;
  final column = evaluation.column.trim();
  final max = evaluation.max;
  return [
    short == null ? title : '$title (short name ${skoreName(short)})',
    'evaluation id ${evaluation.id}',
    if (column.isNotEmpty) 'column $column',
    formatSkoreDay(evaluation.date),
    max == null ? 'no max' : 'max ${formatSkoreNumber(max)}',
    evaluation.componentId == 0
        ? 'no component'
        : 'component ${skoreName(evaluation.componentName)}',
    switch (evaluation.type) {
      SkoreEvaluationType.points => 'points',
      SkoreEvaluationType.scale => 'a scale',
      SkoreEvaluationType.unknown =>
        'a type the server does not support (evaltype ${evaluation.typeCode})',
    },
    if (evaluation.isPlannerEvaluation) 'from the planner',
    formatSkorePublication(evaluation.publication),
  ].join(' | ');
}

/// Why the server cannot read the grades of [evaluation], one the library
/// could not read (not [SkoreEvaluation.isReadable]), for after a colon: a
/// type it does not know, named by Skore's `evaltype`
/// ([SkoreEvaluation.typeCode]), in the server's words; or a cell in a
/// shape it does not recognise, with the library's reason
/// ([SkoreEvaluation.unreadableReason]), which names a cell by its row (a
/// pupil id) and quotes nothing of Skore's answer.
///
/// For example `it is of a type the server does not support yet (Skore's
/// evaltype 3; the server reads evaluations in points and on a scale)`.
String skoreUnreadableReason(SkoreEvaluation evaluation) =>
    switch (evaluation.type) {
      SkoreEvaluationType.unknown =>
        'it is of a type the server does not support yet (Skore\'s evaltype '
            '${evaluation.typeCode}; the server reads evaluations in points '
            'and on a scale)',
      _ =>
        'Skore gave its grades in a shape the server does not know yet '
            '(${evaluation.unreadableReason})',
    };

/// What the gradebook tools say instead of the grades of an [evaluation]
/// the library could not read (not [SkoreEvaluation.isReadable]), with why
/// ([skoreUnreadableReason]): `The server cannot read the grades of this
/// evaluation: it is of a type the server does not support yet (Skore's
/// evaltype 7; the server reads evaluations in points and on a scale). The
/// user sees them in Skore in Smartschool itself.`
///
/// Since flutter_smartschool 0.4.0 the library reads the rest of the period
/// around such an evaluation, and its `results` throw
/// (yvanvds/dartschool#193): the tools ask [SkoreEvaluation.isReadable]
/// first (#170).
String formatSkoreUnreadableGrades(SkoreEvaluation evaluation) =>
    'The server cannot read the grades of this evaluation: '
    '${skoreUnreadableReason(evaluation)}. The user sees them in Skore in '
    'Smartschool itself.';

/// Whether [evaluation] is one on a scale ("Waarderingen", Skore's
/// `evaltype` 2) whose grades the library read: the tools show its values
/// with the levels of the school's scale ([formatSkoreScaleValue]), read
/// once per call (`readSkoreScaleFor`, #169).
bool isSkoreScaleEvaluation(SkoreEvaluation evaluation) =>
    evaluation.type == SkoreEvaluationType.scale && evaluation.isReadable;

/// A pupil's [grade] in [evaluation], as the gradebook tools show it: for an
/// evaluation on a scale ([isSkoreScaleEvaluation]) with its level on
/// [scale] ([formatSkoreScaleValue]), else as Skore stores it
/// ([formatSkoreGradeValue]).
String formatSkoreGradeIn(
  SkoreEvaluation evaluation,
  SkoreGrade? grade,
  SkoreScale? scale,
) => isSkoreScaleEvaluation(evaluation)
    ? formatSkoreScaleValue(evaluation, grade, scale)
    : formatSkoreGradeValue(grade);

/// A pupil's [grade] in [evaluation], an evaluation on a scale (#169): the
/// level of [scale] it has ([SkoreScale.levelOf], as Skore's web client
/// finds it), by its description and abbreviation, and the value Skore
/// stores, out of the evaluation's max: `Zeer goed (ZG; stored as 10)`.
///
/// `no grade` for an empty cell and `no cell` when Skore gave none, as for
/// points; a value no level covers (not a number, or an evaluation without
/// a max) says so: `G (no level of the scale)`. Without [scale] (it could
/// not be read, which [formatSkoreScaleNote] says once), the value as Skore
/// stores it.
String formatSkoreScaleValue(
  SkoreEvaluation evaluation,
  SkoreGrade? grade,
  SkoreScale? scale,
) {
  final value = grade?.grade;
  if (grade == null || value == null || scale == null) {
    return formatSkoreGradeValue(grade);
  }
  final level = scale.levelOf(evaluation, grade);
  if (level == null) return '$value (no level of the scale)';
  final (label, short) = _scaleLabels(level);
  return short == null
      ? '$label (stored as $value)'
      : '$label ($short; stored as $value)';
}

/// A level of a scale by its description and abbreviation, `Zeer goed
/// (ZG)`; one of the two alone when Skore gives no other.
String formatSkoreScaleLevel(SkoreScaleLevel level) {
  final (label, short) = _scaleLabels(level);
  return short == null ? label : '$label ($short)';
}

/// The label of [level], its description (its abbreviation when it has
/// none), and its abbreviation next to it, or null when there is not both.
(String, String?) _scaleLabels(SkoreScaleLevel level) {
  final description = level.description.trim();
  final abbreviation = level.abbreviation.trim();
  if (description.isEmpty) return (skoreName(abbreviation), null);
  if (abbreviation.isEmpty) return (skoreName(description), null);
  return (skoreName(description), skoreName(abbreviation));
}

/// The school's [scale] in a sentence, for a result that shows values on
/// it (#169): its name and its levels from low to high, each with the
/// percentage of the max it starts at, and how Skore stores a value. For
/// example `The scale "Gedragsschaal" of the evaluations on a scale, from
/// low to high: Onvoldoende (O) from 0% of the max, Voldoende (V) from 50%,
/// Zeer goed (ZG) from 80%. Skore stores a value on it as a number out of
/// the evaluation's max.`
String formatSkoreScale(SkoreScale scale) {
  final name =
      'The scale "${skoreName(scale.name)}" of the evaluations on a '
      'scale';
  final levels = scale.levels;
  if (levels.isEmpty) return '$name has no levels.';
  return '$name, from low to high: '
      '${[for (final (index, level) in levels.indexed) '${formatSkoreScaleLevel(level)} from '
            '${formatSkoreNumber(level.lowerThreshold)}%'
            '${index == 0 ? ' of the max' : ''}'].join(', ')}. Skore stores a value on it as a number out of the '
      'evaluation\'s max.';
}

/// The line about the school's scale for a result that shows [evaluations]:
/// [formatSkoreScale] when one of them is on a scale
/// ([isSkoreScaleEvaluation]) and [scale] was read, a sentence that it
/// could not be read when it was not, and null when none is on a scale.
String? formatSkoreScaleNote(
  Iterable<SkoreEvaluation> evaluations,
  SkoreScale? scale,
) {
  if (!evaluations.any(isSkoreScaleEvaluation)) return null;
  if (scale != null) return formatSkoreScale(scale);
  return 'The scale of the evaluations on a scale could not be read, so '
      'their values are shown as Skore stores them (a number out of the '
      'max), without their labels; the technical details are in the server '
      'log.';
}

/// An evaluation by its title and id, as a sentence or an error names it:
/// `evaluation "Toets 1" (evaluation id 500003)`.
String formatSkoreEvaluationName(SkoreEvaluation evaluation) =>
    'evaluation "${skoreName(evaluation.title)}" (evaluation id '
    '${evaluation.id})';

/// Whether the pupils see an evaluation, and from when, in the time of this
/// PC (Belgium): `not published: the pupils do not see it`, `SCHEDULED for
/// 2026-10-09 08:00: from then on the pupils see it and its grades`,
/// `PUBLISHED since 2026-10-01 08:00: the pupils see it and its grades`.
/// Published and scheduled are in capitals: grades entered there reach the
/// pupils.
String formatSkorePublication(SkorePublication publication) {
  final at = publication.at;
  final time = at == null ? null : formatSkoreTime(at);
  return switch (publication.state) {
    SkorePublicationState.notPublished =>
      'not published: the pupils do not see it',
    SkorePublicationState.scheduled =>
      'SCHEDULED${time == null ? '' : ' for $time'}: from then on the pupils '
          'see it and its grades',
    SkorePublicationState.published =>
      'PUBLISHED${time == null ? '' : ' since $time'}: the pupils see it and '
          'its grades',
  };
}

/// The averages of an evaluation and how many of its pupils have a grade:
/// `class average 47.3 | group average 47.3 | 2 of 3 pupils have a grade`.
/// The averages are as Skore gives them (with a decimal point).
String formatSkoreEvaluationResults(SkoreEvaluationResults results) {
  final graded = results.grades.where((g) => g.grade != null).length;
  final total = results.grades.length;
  return [
    switch (results.classAverage) {
      final average? => 'class average $average',
      null => 'no class average',
    },
    switch (results.groupAverage) {
      final average? => 'group average $average',
      null => 'no group average',
    },
    '$graded of $total ${total == 1 ? 'pupil has' : 'pupils have'} a grade',
  ].join(' | ');
}

/// A pupil's grade as Skore stores it (`79`, `15.5`, with a decimal point),
/// `no grade` for an empty cell, and `no cell` when Skore gave none for the
/// pupil.
String formatSkoreGradeValue(SkoreGrade? grade) => switch (grade) {
  null => 'no cell',
  SkoreGrade(grade: final value?) => value,
  _ => 'no grade',
};

/// A day as `2026-09-30`.
String formatSkoreDay(DateTime day) =>
    '${day.year}-${_two(day.month)}-${_two(day.day)}';

/// [value] without a decimal part when it is whole: `20`, `15.5`.
String formatSkoreNumber(num value) =>
    value is double && value == value.truncateToDouble()
    ? '${value.toInt()}'
    : '$value';

/// One feedback of a pupil on an evaluation (#141): who wrote it (the user,
/// when [byUser]), when it was written and last changed, its attachments
/// and whether Skore lets the user change it; then its text, indented, line
/// by line.
///
/// For example `- by Céline Dupré (user id 346) | written 2026-10-08 10:02,
/// changed 2026-10-08 10:15 | 1 attachment: verbetering.pdf | the user may
/// not change it` and `  Tweede opmerking.`.
String formatSkoreFeedback(SkoreFeedback feedback, {required bool byUser}) {
  final author =
      '${skoreName(feedback.teacherName)} (user id '
      '${feedback.teacherId})';
  final created = feedback.createdAt;
  final changed = feedback.changedAt;
  final attachments = feedback.attachments;
  final text = feedback.text.trim();
  return [
    [
      byUser ? '- by the user, $author' : '- by $author',
      [
        if (created != null) 'written ${formatSkoreTime(created)}',
        if (changed != null && changed != created)
          'changed ${formatSkoreTime(changed)}',
      ].join(', '),
      if (attachments.isNotEmpty)
        '${attachments.length} '
            '${attachments.length == 1 ? 'attachment' : 'attachments'}: '
            '${[for (final a in attachments) skoreName(a.name)].join(', ')}',
      feedback.canEdit
          ? 'the user may change it'
          : 'the user may not change it',
    ].where((part) => part.isNotEmpty).join(' | '),
    if (text.isEmpty)
      '  (no text)'
    else
      for (final line in text.split(_newline)) '  ${line.trimRight()}',
  ].join('\n');
}

final _newline = RegExp(r'\r\n?|\n');

/// What Skore's description of [period] ([SkoreGradebookPeriod.info], HTML)
/// says that the rest of the period's line does not, as one line: the
/// school's note on the period and when it opens. The paragraphs that only
/// repeat its name or say that it is closed (`Gesloten!`) are left out; null
/// when nothing is left.
///
/// Skore gives `<p><u><b>DW1</b></u></p><p>Open van 2026-09-18 15:30<br/>
/// tot en met 2026-12-18 20:00</p><p>Vul hier je punten ... in!</p>`, and
/// for a closed period a lock and `Gesloten!` instead of the dates.
String? skorePeriodNote(SkoreGradebookPeriod period) {
  final fragment = html_parser.parseFragment(period.info);
  final paragraphs = fragment.querySelectorAll('p');
  final texts = [
    for (final text
        in paragraphs.isEmpty
            ? [fragment.text ?? '']
            : [for (final paragraph in paragraphs) paragraph.text])
      text.replaceAll(_whitespace, ' ').trim(),
  ];
  final kept = [
    for (final text in texts)
      if (text.isNotEmpty &&
          text != period.name.trim() &&
          text != period.fullName.trim() &&
          text != _closed)
        _sentence(text),
  ];
  return kept.isEmpty ? null : kept.join(' ');
}

/// What Skore's description of a closed period says instead of its dates.
const _closed = 'Gesloten!';

final _whitespace = RegExp(r'\s+');

/// [text] ending in a full stop, unless it ends in punctuation already.
String _sentence(String text) =>
    RegExp(r'[.!?:;]$').hasMatch(text) ? text : '$text.';

/// The components a new evaluation in a period can count for, in Skore's
/// order, each with its component id, `geen` marked as none: `geen
/// (component id 0: none), DW (component id 2)`.
String formatSkoreComponents(List<SkoreEvaluationComponent> components) => [
  for (final component in components)
    '${skoreName(component.name)} (component id ${component.id}'
        '${component.isNone ? ': none' : ''})',
].join(', ');

/// One pupil of a gradebook: the class number (when Skore shows one), the
/// name as the gradebook lists it (last name first), the pupil id, and
/// whether Skore greys the pupil out as inactive.
///
/// For example `1. Aerts, An | pupil id 1201`, or `Verbeke, Fien | pupil id
/// 1302 | inactive (greyed out in Skore)`.
String formatSkoreGradebookPupil(SkoreGradebookPupil pupil) => [
  '${pupil.number == null ? '' : '${pupil.number}. '}${skoreName(pupil.name)}',
  'pupil id ${pupil.id}',
  if (!pupil.isActive) 'inactive (greyed out in Skore)',
].join(' | ');

/// [time] as `2026-12-18 20:00`, in the time of this PC (Belgium), as the
/// other tools show times.
String formatSkoreTime(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
