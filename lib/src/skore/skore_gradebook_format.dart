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
  final closes = period.closesAt;
  final note = skorePeriodNote(period);
  return [
    fullName == name ? name : '$name ($fullName)',
    'period id ${period.id}',
    switch ((period.isOpen, closes)) {
      (true, final time?) => 'open, closes ${formatSkoreTime(time)}',
      (true, null) => 'open, no closing time',
      (false, final time?) => 'closed, closing time ${formatSkoreTime(time)}',
      (false, null) => 'closed',
    },
    if (active) 'active',
    if (note != null) 'note: $note',
  ].join(' | ');
}

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
