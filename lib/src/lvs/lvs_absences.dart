import 'package:flutter_smartschool/flutter_smartschool.dart';

import 'lvs_format.dart';

// The absences of a pupil's file in the LVS, for `read_lvs_absences`
// (#157): the absences part of the file ("Afwezigheden"), the half-days the
// school registered with an absence code, grouped by school year. Read with
// the library's read of the absences (yvanvds/dartschool#164); the school
// year is chosen here, and the totals per code of each school year are the
// library's (LvsAbsences.totalsByCode).
//
// The library sends no school year: the LVS picks the school years it
// answers with, each a period of the answer. So `school_year` picks among
// them, and the others are summed up.
//
// A motivation can hold health information: it is shown only when asked
// for (`with_motivation`), and otherwise only counted.
//
// What the absences hold goes to Claude only: never to the log, never to
// disk (lvs_access.dart).

/// The part of the file `read_lvs_absences` reads, for the sentence of a
/// refusal with HTTP 403 ([withLvs]).
const lvsAbsencesPart = 'the absences (Afwezigheden)';

/// What `read_lvs_absences` read: the pupil's [absences], and whether the
/// pupil's file has a part of absences ([fileHasAbsences]; known only when
/// the file was read, see [readLvsAbsences], else `true`).
typedef LvsAbsencesRead = ({LvsAbsences absences, bool fileHasAbsences});

/// Reads the absences of the pupil [pupilId] in class [classId]
/// ([LvsService.getAbsences]), of every school year the LVS answers with.
///
/// The LVS answered a made-up pupil in a made-up class with HTTP 500 and
/// Smartschool's error page (seen live, yvanvds/dartschool#164), which the
/// library throws as a plain [SmartschoolLvsError], as it does any answer
/// it cannot read. So after such an error the pupil's file is read
/// ([LvsService.getPupilFile]): for a pupil the LVS does not know it throws
/// a [SmartschoolLvsPupilNotFoundError], which is thrown instead; else the
/// error of the absences stands (yvanvds/dartschool#190, tracked in #164).
/// The file is read too when the absences hold nothing, to tell an unknown
/// pupil apart there as well, and a file without a part of absences
/// ([LvsSectionType.absences]) from a pupil without absences. That read
/// takes today's attendance along, unused (yvanvds/dartschool#186, tracked
/// in #160).
///
/// A refusal ([SmartschoolLvsAccessDeniedError]) is thrown as it comes,
/// without reading the file.
Future<LvsAbsencesRead> readLvsAbsences(
  LvsService lvs, {
  required int pupilId,
  required int classId,
}) async {
  Future<LvsPupilFile> readFile() =>
      lvs.getPupilFile(pupilId: pupilId, classId: classId);

  final LvsAbsences absences;
  try {
    absences = await lvs.getAbsences(pupilId: pupilId, classId: classId);
  } on SmartschoolLvsError catch (error, stackTrace) {
    if (error is SmartschoolLvsAccessDeniedError ||
        error is SmartschoolLvsRequestNotAllowedError) {
      rethrow;
    }
    try {
      await readFile();
    } on SmartschoolLvsPupilNotFoundError {
      rethrow;
    } on SmartschoolLvsError {
      // The file cannot tell either: the error of the absences stands.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  if (!absences.isEmpty) return (absences: absences, fileHasAbsences: true);
  final file = await readFile();
  return (
    absences: absences,
    fileHasAbsences: file.allSections.any(
      (section) => section.type == LvsSectionType.absences,
    ),
  );
}

/// The periods of [absences] that are [schoolYear] ([chosen]: those whose
/// label names it, [LvsSchoolYear.tryParse]) and the [others], each in the
/// LVS's order.
typedef LvsAbsencePeriods = ({
  List<LvsAbsencePeriod> chosen,
  List<LvsAbsencePeriod> others,
});

/// The periods of [absences] in [schoolYear], and the others.
LvsAbsencePeriods selectLvsAbsencePeriods(
  LvsAbsences absences,
  LvsSchoolYear schoolYear,
) {
  final chosen = <LvsAbsencePeriod>[];
  final others = <LvsAbsencePeriod>[];
  for (final period in absences.periods) {
    (LvsSchoolYear.tryParse(period.label) == schoolYear ? chosen : others).add(
      period,
    );
  }
  return (chosen: chosen, others: others);
}

/// What `read_lvs_absences` answers for [read], of the pupil [pupilId] in
/// class [classId], for [schoolYear]:
///
/// - no absences at all: a sentence, which says so when the file has no
///   part of absences;
/// - none in [schoolYear]: a sentence;
/// - else: a line on whose absences, of which school year, how many
///   half-days; the totals per code; how many have a motivation (shown
///   under each absence only [withMotivation]); then each absence, day after
///   day in the LVS's order ([formatLvsAbsence]);
///
/// then the other school years the LVS gives, with their totals
/// ([_otherPeriodLine]).
String formatLvsAbsences(
  LvsAbsencesRead read, {
  required int pupilId,
  required int classId,
  required LvsSchoolYear schoolYear,
  required bool withMotivation,
}) {
  final pupil = 'the pupil with pupil_id $pupilId (class_id $classId)';
  if (read.absences.isEmpty) {
    return read.fileHasAbsences
        ? 'The LVS gives no absences for $pupil, in any school year.'
        : 'The file of $pupil in the LVS has no part of absences '
              '(Afwezigheden), and the LVS gives no absences for this pupil: '
              'the school may not keep absences in the LVS, or this account '
              'may not see them.';
  }
  final (:chosen, :others) = selectLvsAbsencePeriods(read.absences, schoolYear);
  final year = formatLvsSchoolYear(schoolYear);
  final inYear = LvsAbsences(periods: chosen);
  final absences = inYear.absences;
  return [
    if (absences.isEmpty)
      'The LVS gives no absences for $pupil in the school year $year.'
    else ...[
      'The absences of $pupil in the LVS in the school year $year: '
          '${_amount(absences.length, inYear.halfDays)}, day after day in the '
          "LVS's order. The codes are the school's own.",
      'Totals per code:',
      for (final total in inYear.totalsByCode)
        '- ${_codeLabel(total.code, total.codeDescription)}: '
            '${_amount(total.count, total.halfDays)}',
      _motivationLine(absences, withMotivation: withMotivation),
      for (final absence in absences)
        formatLvsAbsence(absence, withMotivation: withMotivation),
    ],
    if (others.isNotEmpty) ...[
      'Other school years the LVS gives (it picks them itself), with their '
          'totals; pass one as school_year for its absences:',
      for (final period in others) _otherPeriodLine(period),
    ],
  ].join('\n');
}

/// The line on the motivations of [absences]: how many have one, and
/// whether they are shown.
String _motivationLine(
  List<LvsAbsence> absences, {
  required bool withMotivation,
}) {
  final total = absences.length;
  final count = absences.where(_hasMotivation).length;
  if (count == 0) {
    return total == 1
        ? 'The absence has no motivation.'
        : 'None of the $total absences has a motivation.';
  }
  final has = total == 1
      ? 'The absence has a motivation'
      : count == total
      ? 'All $total absences have a motivation'
      : '$count of the $total absences ${count == 1 ? 'has' : 'have'} a '
            'motivation';
  return withMotivation
      ? '$has, shown under ${count == 1 ? 'it' : 'each'}, as asked '
            '(with_motivation).'
      : '$has, not shown, as a motivation can hold health information: '
            'pass with_motivation true only when the user asks why the pupil '
            'was absent.';
}

/// Whether [absence] has a motivation, as plain text.
bool _hasMotivation(LvsAbsence absence) => absence.motivation.trim().isNotEmpty;

/// One absence as `read_lvs_absences` lists it: its day (with the day of
/// the week), the part of the day and its code; with [withMotivation], its
/// motivation under it, a line for each of its lines.
///
/// ```text
/// - 2030-10-02 (Wednesday) | morning | Testcode 2 (TB)
///   Motivation: Testmotivatie in platte tekst.
/// ```
///
/// A day the library could not read ([LvsAbsence.date] `null`) is shown as
/// the LVS shows it, said so.
String formatLvsAbsence(LvsAbsence absence, {bool withMotivation = false}) {
  final date = absence.date;
  final shown = _oneLine(absence.formattedDate);
  final day = date != null
      ? '${_isoDay(date)} (${_weekdays[date.weekday - 1]})'
      : shown.isEmpty
      ? '(no day given)'
      : '"$shown" (the day as the LVS shows it; the server cannot read it)';
  final part = switch (absence.dayPart) {
    null => 'whole day',
    DayPart.morning => 'morning',
    DayPart.afternoon => 'afternoon',
  };
  final lines = [
    for (final line in absence.motivation.split('\n'))
      if (_oneLine(line).isNotEmpty) _oneLine(line),
  ];
  return [
    '- $day | $part | ${_codeLabel(absence.code, absence.codeDescription)}',
    if (withMotivation)
      if (lines case [final line])
        '  Motivation: $line'
      else if (lines.isNotEmpty) ...[
        '  Motivation:',
        for (final line in lines) '    $line',
      ],
  ].join('\n');
}

/// The line of a school year the answer does not list the absences of:
/// its label and its totals, per code.
///
/// ```text
/// - 2031-2032: 3 half-days (1 whole day and 1 half-day); Testcode 2 (TB):
///   1 half-day; Testcode (TA): 2 half-days (1 whole day)
/// ```
String _otherPeriodLine(LvsAbsencePeriod period) {
  final label = _oneLine(period.label);
  final name = LvsSchoolYear.tryParse(label) != null
      ? label
      : '"${label.isEmpty ? '(no name)' : label}", a period that is not a '
            'school year (school_year cannot name it)';
  if (period.absences.isEmpty) return '- $name: no absences';
  final totals = LvsAbsences(periods: [period]);
  return [
    '- $name: ${_amount(period.absences.length, period.halfDays)}',
    for (final total in totals.totalsByCode)
      '${_codeLabel(total.code, total.codeDescription)}: '
          '${_amount(total.count, total.halfDays)}',
  ].join('; ');
}

/// [count] absences of [halfDays] half-days in words: `1 half-day`,
/// `3 half-days (1 whole day and 1 half-day)`, `2 half-days (1 whole
/// day)`. A whole day counts two half-days.
String _amount(int count, int halfDays) {
  final wholeDays = halfDays - count;
  final halves = count - wholeDays;
  if (wholeDays <= 0) return _count(halfDays, 'half-day');
  return '${_count(halfDays, 'half-day')} (${[_count(wholeDays, 'whole day'), if (halves > 0) _count(halves, 'half-day')].join(' and ')})';
}

/// A code with its description, as the LVS shows it on the file:
/// `Testcode (TA)`; the code alone without a description.
String _codeLabel(String code, String description) {
  final short = _oneLine(code);
  final long = _oneLine(description);
  if (long.isEmpty) return short.isEmpty ? '(no code)' : short;
  return short.isEmpty ? long : '$long ($short)';
}

/// The days of the week, Monday first ([DateTime.weekday]).
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// [date] (its year, month and day: the library's day of an absence, at
/// midnight UTC) as `YYYY-MM-DD`.
String _isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// [count] [noun]s: `1 half-day`, `2 half-days`.
String _count(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';

/// [text] on one line: each run of white space one space, trimmed.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
