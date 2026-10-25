import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';
import 'lvs_format.dart';

// The notes of a pupil's file in the LVS, for `read_lvs_notes` (#154): what
// schools keep on behaviour, care and educational needs, class council
// remarks and talks with parents, in note categories each school makes
// itself. Read with the library's getNotes and getAllNotes
// (yvanvds/dartschool#161), chosen (since, confidential, limit) and
// written here.
//
// The library returns confidential notes ("vertrouwelijk") marked, not
// left out: leaving them out unless the user asks, and counting them
// without showing what they hold, is this file's job.
//
// What these notes hold goes to Claude only: never to the log, never to
// disk (lvs_access.dart).

/// How many notes `read_lvs_notes` shows without a `limit`, newest first.
const lvsNotesDefaultLimit = 20;

/// The most notes `read_lvs_notes` shows in one call.
const lvsNotesMaxLimit = 100;

/// The notes `read_lvs_notes` read: of [category] and its sub-categories,
/// or of all categories when it is `null`; of any order.
typedef LvsNotesRead = ({LvsCategory? category, List<LvsNote> notes});

/// Reads the notes of the pupil [pupilId] in class [classId] in
/// [schoolYear]: of the note category [category] names (its id or its name,
/// [pickLvsCategory]) with its sub-categories, or of all categories when
/// it is `null`.
///
/// Of one category, the pupil's file is read first ([LvsService.getPupilFile])
/// for its categories, then each of the category and its sub-categories on
/// its own ([LvsService.getNotes]: a category's own notes, never those of
/// its sub-categories), but headings, which hold no notes of their own.
/// The file's read takes today's attendance along, which is not used: the
/// library has no read of the categories alone (yvanvds/dartschool#186,
/// tracked in #160).
/// Of all categories, the "all items" view ([LvsService.getAllNotes]); as
/// it answers a pupil it does not know with no notes at all, an empty
/// answer has the file read too, which tells the two apart (a
/// [SmartschoolLvsPupilNotFoundError]).
///
/// Throws a [ToolError] when [category] names no category of the file, or
/// more than one; the LVS's errors as the library throws them.
Future<LvsNotesRead> readLvsNotes(
  LvsService lvs, {
  required int pupilId,
  required int classId,
  required String? category,
  required LvsSchoolYear schoolYear,
}) async {
  if (category == null) {
    final notes = await lvs.getAllNotes(
      pupilId: pupilId,
      classId: classId,
      schoolYear: schoolYear,
    );
    if (notes.isEmpty) {
      await lvs.getPupilFile(pupilId: pupilId, classId: classId);
    }
    return (category: null, notes: notes);
  }
  final file = await lvs.getPupilFile(pupilId: pupilId, classId: classId);
  final picked = pickLvsCategory(file.noteCategories, category);
  final notes = <LvsNote>[];
  final seen = <int>{};
  for (final each in [picked, ...picked.descendants]) {
    if (each.isTitle) continue;
    for (final note in await lvs.getNotes(
      pupilId: pupilId,
      classId: classId,
      categoryId: each.id,
      schoolYear: schoolYear,
    )) {
      if (seen.add(note.id)) notes.add(note);
    }
  }
  return (category: picked, notes: notes);
}

/// The `category` argument as text: a name, or a `category_id` (also
/// written `category_id 900401`); `null` when it is absent or empty.
///
/// Throws a [ToolError] for a number that is not a whole number.
String? lvsCategoryArgument(Map<String, Object?> arguments) {
  switch (arguments['category']) {
    case null:
      return null;
    case final String text:
      final trimmed = text.trim().replaceAll(_quotes, '').trim();
      return trimmed.isEmpty ? null : trimmed;
    case final num number when number == number.truncate():
      return '${number.toInt()}';
    case final value:
      throw ToolError(
        'category must be a category_id or the name of a note category, as '
        'read_lvs_pupil lists them; $value is not.',
      );
  }
}

/// The note category of [categories] (the file's, with their
/// sub-categories) that [which] names: its `category_id` (digits, or
/// `category_id <digits>`), or else its name, ignoring case and runs of
/// white space.
///
/// Throws a [ToolError] that lists the file's categories when none has that
/// id or name, and the matching ones, with their ids, when several have
/// that name.
LvsCategory pickLvsCategory(List<LvsCategory> categories, String which) {
  final all = _withPaths(categories);
  if (all.isEmpty) {
    throw const ToolError(
      "This pupil's file has no note categories. Leave category out to "
      'read all notes of the pupil.',
    );
  }
  if (_idText.firstMatch(which) case final match?) {
    final id = int.parse(match[1]!);
    for (final (category, _) in all) {
      if (category.id == id) return category;
    }
  }
  final key = _key(which);
  final named = [
    for (final entry in all)
      if (_key(entry.$1.name) == key) entry,
  ];
  if (named.length == 1) return named.single.$1;
  if (named.length > 1) {
    throw ToolError(
      'Several note categories of this pupil\'s file are named "$which": '
      '${_list(named)}. Pass the one you mean as category, by its '
      'category_id.',
    );
  }
  throw ToolError(
    'This pupil\'s file has no note category "$which". Its note categories '
    'are: ${_list(all)}. Pass one of them as category, by its category_id '
    'or its name, or leave category out to read all notes.',
  );
}

/// A category id as `category` takes it: digits, or `category_id <digits>`
/// as the tools print it.
final _idText = RegExp(r'^(?:category_?id\s*)?(\d+)$', caseSensitive: false);

/// Double quotes around a name.
final _quotes = RegExp(r'^"|"$');

/// [name] to compare: in lower case, each run of white space one space.
String _key(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Every category of [categories], at any depth, depth first, with its path
/// from the top (`Testcategorie / Testsubcategorie`).
List<(LvsCategory, String)> _withPaths(
  List<LvsCategory> categories, [
  String parent = '',
]) => [
  for (final category in categories) ...[
    (category, '$parent${_label(category.name)}'),
    ..._withPaths(category.subcategories, '$parent${_label(category.name)} / '),
  ],
];

/// The categories of [entries] as an error lists them, by their path, with
/// their ids.
String _list(List<(LvsCategory, String)> entries) => [
  for (final (category, path) in entries)
    '$path (category_id ${category.id}'
        '${category.isTitle ? ', a heading' : ''})',
].join(', ');

/// The notes `read_lvs_notes` shows of all it read ([shown], newest first),
/// with how many it read ([total]) and how many it left out, and why:
/// dated before `since` ([older]), confidential ([confidential]), and
/// over the limit ([overLimit]).
typedef LvsNoteSelection = ({
  List<LvsNote> shown,
  int total,
  int older,
  int confidential,
  int overLimit,
});

/// The notes of [notes] to show, newest first (by their date; notes of the
/// same moment in their order): those of [since] on (a day, `YYYY-MM-DD`,
/// in Belgian time: [lvsDay]), but confidential ones unless
/// [includeConfidential], at most [limit].
///
/// Each note left out counts once, for the first reason in that order: a
/// confidential note dated before [since] is older, and [limit] counts the
/// notes the other two leave.
LvsNoteSelection selectLvsNotes(
  List<LvsNote> notes, {
  String? since,
  required bool includeConfidential,
  required int limit,
}) {
  final newestFirst = notes.indexed.toList()
    ..sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
  var older = 0;
  var confidential = 0;
  final kept = <LvsNote>[];
  for (final (_, note) in newestFirst) {
    if (since != null && lvsDay(note.date).compareTo(since) < 0) {
      older++;
    } else if (note.isConfidential && !includeConfidential) {
      confidential++;
    } else {
      kept.add(note);
    }
  }
  final shown = kept.take(limit).toList();
  return (
    shown: shown,
    total: notes.length,
    older: older,
    confidential: confidential,
    overLimit: kept.length - shown.length,
  );
}

/// What `read_lvs_notes` answers: a line on whose notes, which categories
/// and which school year; a block per note shown ([formatLvsNote]); and a
/// line on how many there are and how many were left out, and why.
///
/// A confidential note left out is counted only: nothing of it is shown,
/// not its date, category or title.
String formatLvsNotes({
  required int pupilId,
  required int classId,
  required LvsSchoolYear schoolYear,
  required LvsCategory? category,
  required LvsNoteSelection selection,
  required String? since,
  required int limit,
  required bool includeConfidential,
}) {
  final (:shown, :total, :older, :confidential, :overLimit) = selection;
  final pupil = 'the pupil with pupil_id $pupilId (class_id $classId)';
  final year = 'school year ${formatLvsSchoolYear(schoolYear)}';
  final which = category == null
      ? 'all note categories'
      : _categoryScope(category);
  if (total == 0) {
    return 'The LVS holds no notes of $pupil in $year, in $which. Pass '
        'school_year for the notes of another school year.';
  }
  final leftOut = [
    if (older > 0) '$older dated before $since (since)',
    if (confidential > 0)
      '$confidential confidential (vertrouwelijk), of which nothing is '
          'shown: pass include_confidential true only when the user '
          'explicitly asks for confidential notes',
    if (overLimit > 0)
      '$overLimit older than those shown, over the limit of $limit: pass a '
          'higher limit to see ${overLimit == 1 ? 'it' : 'them'}',
  ];
  final shownConfidential = shown.where((note) => note.isConfidential).length;
  return [
    'The notes of $pupil in the LVS, $year, in $which, newest first.',
    for (final note in shown) formatLvsNote(note),
    leftOut.isEmpty
        ? total == 1
              ? '1 note in total, shown.'
              : '$total notes in total, all shown.'
        : 'Shown: ${shown.length} of the $total '
              '${total == 1 ? 'note' : 'notes'}. Left out: '
              '${leftOut.join('; ')}.',
    if (includeConfidential && shownConfidential > 0)
      '$shownConfidential of the notes shown '
          '${shownConfidential == 1 ? 'is' : 'are'} confidential '
          '(vertrouwelijk), shown as the user asked for confidential notes.',
  ].join('\n');
}

/// Which categories a read of [category] covers, in words.
String _categoryScope(LvsCategory category) {
  final named = '${_label(category.name)} (category_id ${category.id})';
  if (category.subcategories.isEmpty) return named;
  return category.isTitle
      ? 'the sub-categories of the heading $named'
      : '$named and its sub-categories';
}

/// One note as `read_lvs_notes` shows it: a line with its day (Belgian
/// time), category, title and author, marked new or confidential, then a
/// line per field that holds something, `label: value`, indented.
///
/// ```text
/// - 2030-10-01 | Testcategorie (category_id 900401) | Testnotitie. | by Peeters Piet | new
///   Testveld tekst: Testtekst.
/// ```
String formatLvsNote(LvsNote note) {
  final title = _oneLine(note.title);
  final author = _oneLine(note.author);
  final head = [
    lvsDay(note.date),
    _noteCategory(note),
    title.isEmpty ? '(no title)' : title,
    if (author.isNotEmpty) 'by $author',
    if (note.isNew) 'new',
    if (note.isConfidential) 'vertrouwelijk (confidential)',
  ].join(' | ');
  final filled = note.fields.any(
    (field) => field.type != LvsNoteFieldType.heading && field.hasValue,
  );
  return [
    '- $head',
    for (final field in note.fields) ...formatLvsNoteField(field),
    if (!filled) '  (no field filled in)',
  ].join('\n');
}

/// The category of [note]: its name with its id, or the id alone when the
/// LVS names none (an older shape of the "all items" view).
String _noteCategory(LvsNote note) {
  final name = _oneLine(note.categoryName);
  return name.isEmpty
      ? 'category_id ${note.categoryId}'
      : '$name (category_id ${note.categoryId})';
}

/// The lines of [field] in a note, indented: none when it holds nothing; a
/// heading by its text; `label: value` for the others, a value of more lines
/// under its label. The text the library gives ([LvsNoteField.value]) is
/// already plain: a rich text with its lines, the chosen options, the day
/// of a date, the names of attachments (nothing is downloaded). A type the
/// library does not know shows its value as the LVS gives it, and says so.
List<String> formatLvsNoteField(LvsNoteField field) {
  final label = _oneLine(field.label).isEmpty
      ? '(no label)'
      : _oneLine(field.label);
  switch (field.type) {
    case LvsNoteFieldType.heading:
      return field.label.trim().isEmpty ? const [] : ['  $label (heading)'];
    case LvsNoteFieldType.attachment:
      if (field.attachments.isEmpty) return const [];
      final names = [
        for (final attachment in field.attachments) _oneLine(attachment.name),
      ];
      return ['  $label: ${names.join(', ')} (attachments, by name only)'];
    case LvsNoteFieldType.date when field.date == null && field.hasValue:
      return [
        '  $label: "${_oneLine(field.value)}" (as the LVS gives it, no day)',
      ];
    case LvsNoteFieldType.unknown:
      return _valueLines(
        '$label (a field of a type the server does not know, as the LVS '
        'gives it)',
        field.value,
      );
    case _:
      return _valueLines(label, field.value);
  }
}

/// `label: value` indented, or the label with each line of a value of more
/// lines under it; nothing for an empty value.
List<String> _valueLines(String label, String value) {
  final lines = [
    for (final line in value.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty) return const [];
  if (lines.length == 1) return ['  $label: ${lines.single}'];
  return ['  $label:', for (final line in lines) '    $line'];
}

/// [text] on one line: each run of white space one space, trimmed.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [text] on one line, or `(no name)` when it is empty.
String _label(String text) {
  final line = _oneLine(text);
  return line.isEmpty ? '(no name)' : line;
}
