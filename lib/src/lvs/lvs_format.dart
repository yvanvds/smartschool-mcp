import 'package:flutter_smartschool/flutter_smartschool.dart';

// How the LVS tools write their answers, in the style of the other tools: a
// line that sums up, then one line per item with its parts separated by
// ` | ` (or, for the parts of a pupil's file, a list indented by depth).
//
// What these lines hold goes to Claude only: never to the log, never to
// disk (lvs_access.dart).

/// The tools that read a part of a pupil's file, by the part's type
/// ([LvsSection.type]): `read_lvs_pupil` names the tool on the part's line,
/// so that Claude knows which tool reads it. The LVS tools that read the
/// parts (#154 to #157) add theirs here.
const lvsSectionReaders = <String, String>{
  // The note categories, and their headings (#154).
  LvsSectionType.items: 'read_lvs_notes',
};

/// [schoolYear] as the LVS labels a school year, `2030-2031`; another range
/// of days as `2030-09-01 to 2030-12-31`.
String formatLvsSchoolYear(LvsSchoolYear schoolYear) {
  final first = schoolYear.from.year;
  return schoolYear == LvsSchoolYear.starting(first)
      ? '$first-${first + 1}'
      : '${schoolYear.firstDay} to ${schoolYear.lastDay}';
}

/// The day of [instant] in Belgian time, the LVS's, as `YYYY-MM-DD`: the
/// day the LVS shows a note on, also on a computer in another time zone.
///
/// The library has the Belgian day of a note but does not export it
/// (yvanvds/dartschool#185), so this asks its [LvsSchoolYear.includesDay],
/// which tells the Belgian day: Belgian time is one or two hours ahead of
/// UTC, so the day there is the day in UTC or the one after. Tracked for
/// removal in #160.
String lvsDay(DateTime instant) {
  final utc = instant.toUtc();
  final next = DateTime.utc(utc.year, utc.month, utc.day + 1);
  final day = LvsSchoolYear(from: next, until: next).includesDay(instant)
      ? next
      : DateTime.utc(utc.year, utc.month, utc.day);
  return LvsSchoolYear(from: day, until: day).firstDay;
}

/// What a part of a pupil's file is, in a few words, by its type.
const _sectionKinds = {
  LvsSectionType.items: 'note category',
  LvsSectionType.supportPlans: 'support plans',
  LvsSectionType.skore: 'reports in Skore',
  LvsSectionType.results: 'results',
  LvsSectionType.deliberation: 'deliberations of the class council',
  LvsSectionType.forms: 'forms',
  LvsSectionType.contactMoments: 'contact moments',
  LvsSectionType.absences: 'absences',
  LvsSectionType.career: 'school career',
  LvsSectionType.messages: 'messages kept in the LVS',
  LvsSectionType.smartSignal: 'Smartsignal',
};

/// What [section] is: its kind ([_sectionKinds]), or its type as the LVS
/// names it for a type the LVS's web client does not know.
String formatLvsSectionKind(LvsSection section) =>
    _sectionKinds[section.type] ?? 'a part of type "${section.type}"';

/// One pupil a search found, as `search_lvs_pupils` lists it:
/// `- Janssens Jan | class 1A | pupil_id 900001 | class_id 900101`.
String formatLvsMatch(LvsPupilMatch match) => [
  '- ${_label(match.name)}',
  'class ${_label(match.className)}',
  'pupil_id ${match.pupilId}',
  'class_id ${match.classId}',
].join(' | ');

/// What `search_lvs_pupils` answers for [query]: no pupil, one, or several,
/// in the LVS's order.
String formatLvsMatches(String query, List<LvsPupilMatch> found) {
  if (found.isEmpty) {
    return 'The pupil tracking system (LVS) finds no pupil whose name '
        'matches "$query" among the pupils this account may see. Check the '
        'spelling, or search for part of the name, such as the last name.';
  }
  final summary = found.length == 1
      ? 'finds 1 pupil whose name matches "$query". Pass its pupil_id and '
            'class_id to read_lvs_pupil.'
      : 'finds ${found.length} pupils whose name matches "$query", in its '
            'order. Several pupils match: ask the user which one they mean, by '
            'name and class, before reading a file. Do not pick one yourself.';
  return [
    'The pupil tracking system (LVS) $summary',
    for (final match in found) formatLvsMatch(match),
  ].join('\n');
}

/// What `read_lvs_pupil` answers: who, which class, the form tutors,
/// today's attendance, the parts of the file that hold something (with
/// their sub-parts, indented), and those that hold nothing.
///
/// [readers] names the tool that reads a part, by its type
/// ([lvsSectionReaders]).
String formatLvsPupilFile(
  LvsPupilFile file, {
  Map<String, String> readers = lvsSectionReaders,
}) {
  final description = file.classDescription.isEmpty
      ? ''
      : ' (${file.classDescription})';
  final tutors = [for (final teacher in file.teachers) _label(teacher.name)];
  final filled = <String>[];
  final empty = <LvsSection>[];
  void add(LvsSection section, int depth) {
    if (!_holdsSomething(section)) {
      empty.add(section);
      empty.addAll(section.descendants);
      return;
    }
    filled.add('${'  ' * depth}- ${_sectionLine(section, readers)}');
    for (final child in section.children) {
      add(child, depth + 1);
    }
  }

  for (final section in file.sections) {
    add(section, 0);
  }
  return [
    "${_label(file.name)}, class ${_label(file.className)}$description: the "
        "overview of the pupil's file in the LVS (pupil_id ${file.pupilId}, "
        'class_id ${file.classId}).',
    tutors.isEmpty
        ? 'Form tutors (titularissen): none given.'
        : 'Form tutors (titularissen): ${tutors.join(', ')}.',
    formatLvsToday(file.todayStatus),
    if (filled.isEmpty)
      'No part of the file holds anything for this pupil.'
    else ...[
      'The parts of the file that hold something, in the LVS\'s order '
          '(${filled.length}). What they hold is not shown here.',
      ...filled,
    ],
    if (empty.isNotEmpty)
      'Parts that hold nothing for this pupil: '
          '${[for (final section in empty) '${_label(section.name)} (${formatLvsSectionKind(section)})'].join(', ')}.',
  ].join('\n');
}

/// Whether [section] holds something for the pupil, itself or in a part
/// under it.
bool _holdsSomething(LvsSection section) =>
    section.hasItems || section.descendants.any((child) => child.hasItems);

/// The line of [section] in the list of parts, without its indent:
/// `Testcategorie: note category (category_id 900401), with new notes`.
String _sectionLine(LvsSection section, Map<String, String> readers) {
  final isNotes = section.type == LvsSectionType.items;
  final kind = section.isTitle
      ? 'heading of ${isNotes ? 'note categories' : formatLvsSectionKind(section)}'
      : formatLvsSectionKind(section);
  final parts = [
    '${_label(section.name)}: $kind',
    if (isNotes) '(category_id ${section.id})',
  ];
  final details = [
    if (section.hasNewItems) isNotes ? 'with new notes' : 'with something new',
    if (readers[section.type] case final tool?) 'read it with $tool',
  ];
  return [parts.join(' '), ...details].join(', ');
}

/// The line on today's attendance: the code of each half-day that has one,
/// as the LVS shows them on the pupil's file.
String formatLvsToday(LvsTodayStatus today) {
  if (today.halfDays.isEmpty) {
    return "Today's attendance: nothing registered (no school today, or "
        'nothing registered yet).';
  }
  final halfDays = [
    for (final halfDay in today.halfDays)
      '${_partOfDay(halfDay.partOfDay)}: '
          '${halfDay.name.isEmpty ? halfDay.code : '${halfDay.name} (${halfDay.code})'}',
  ];
  return "Today's attendance: ${halfDays.join('; ')}.";
}

/// A half-day as the LVS names it (`am`, `pm`), in words. Another value is
/// kept as it comes: on a school day the LVS was seen to answer three
/// half-days, in a shape not captured yet (yvanvds/dartschool#168).
String _partOfDay(String partOfDay) => switch (partOfDay) {
  'am' => 'morning',
  'pm' => 'afternoon',
  _ => 'part of the day "$partOfDay"',
};

/// [text], or `(no name)` when it is empty.
String _label(String text) => text.trim().isEmpty ? '(no name)' : text.trim();
