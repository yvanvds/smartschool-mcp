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

/// [gradebook] in a sentence, for the first line of a tool's result: its
/// id, course, class and school year. For example `Gradebook id 32508:
/// Informaticawetenschappen (2 uur) (6e j DO), class 6EWI, school year
/// 2026-2027 (workyear id 24)`.
String formatSkoreGradebookTitle(
  SkoreGradebook gradebook,
  SkoreWorkyear workyear,
) =>
    'Gradebook id ${gradebook.gradebookId}: '
    '${skoreName(gradebook.courseName)}, class '
    '${skoreName(gradebook.className)}, school year '
    '${formatSkoreWorkyear(workyear)}';

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

/// A gradebook by its class, course and id, as an error names it:
/// `gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO)
/// (gradebook id 32508)`.
String formatSkoreGradebookName(SkoreGradebook gradebook) =>
    'gradebook of ${skoreName(gradebook.className)} for '
    '${skoreName(gradebook.courseName)} (gradebook id '
    '${gradebook.gradebookId})';

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
      SkoreEvaluationType.unknown => 'type ${evaluation.typeCode}',
    },
    if (evaluation.isPlannerEvaluation) 'from the planner',
    formatSkorePublication(evaluation.publication),
  ].join(' | ');
}

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
