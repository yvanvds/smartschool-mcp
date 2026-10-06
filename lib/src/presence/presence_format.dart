import 'package:flutter_smartschool/flutter_smartschool.dart';

// How the presence tools name what a half-day holds and write their lines,
// in the style of the other tools: a line that sums up, then one line per
// item with its parts separated by ` | `.

/// What a half-day holds, as the presence tools tell it apart: the statuses
/// the writes may change, and anything else, which they never overwrite.
enum PresenceKind {
  /// Nothing recorded: no cell yet, or a cell without a code.
  empty,

  /// "Aanwezig" ([PresenceService.presentCodeName]).
  present,

  /// "Te laat" ([PresenceService.lateCodeName]), without an alias.
  late,

  /// "Te laat zonder geldige reden"
  /// ([PresenceService.lateWithoutReasonAliasName]), the alias of "Te laat".
  lateWithoutReason,

  /// Any other code or alias, such as an absence the secretariat recorded.
  other;

  /// Whether `set_pupils_late` and `set_pupils_present` may change a
  /// half-day that holds it.
  bool get changeable => this != other;
}

/// The statuses the writes may change, in a sentence.
const changeablePresences =
    'nothing recorded, "${PresenceService.presentCodeName}", '
    '"${PresenceService.lateCodeName}" or '
    '"${PresenceService.lateWithoutReasonAliasName}"';

/// The statuses the writes may change, by name, as the library's
/// `onlyReplacing` takes them: it refuses a half-day that holds any other
/// status, as it reads it right before the save (yvanvds/dartschool#105).
const changeablePresenceNames = {
  PresenceService.nothingRecorded,
  PresenceService.presentCodeName,
  PresenceService.lateCodeName,
  PresenceService.lateWithoutReasonAliasName,
};

/// The presence codes of a school structure ([PresenceService.getAllCodes]),
/// to name what a half-day holds and to tell its [PresenceKind]: those of
/// the class's structure, or, for a pupil of a grouping class, which has
/// none, those of the structure of the pupil's official class when
/// `readPresenceDay` read them (yvanvds/dartschool#126). A half-day whose
/// code or alias is not among them is named by the name the module gave
/// with its record ([PresenceHalfDay.statusName]), or else by its id, with
/// [unnamed].
final class PresenceCodes {
  PresenceCodes(
    this.codes, {
    this.unnamed = 'it is not among the codes of the class',
  });

  /// No codes, for a grouping class: its half-days are named by the name
  /// the module gave with each record, or else by their id, with [unnamed].
  PresenceCodes.none(String unnamed) : this(const [], unnamed: unnamed);

  final List<PresenceCode> codes;

  /// Why a half-day whose code or alias is not among [codes], and that the
  /// module gave no name with, stays named by its id: the end of `code id
  /// 70 (the module gave no name with the record, and ...)`. `it is not
  /// among the codes of the class`; for a pupil of a grouping class, `it is
  /// not among the codes of the pupil's official class`, or `this account
  /// does not see the pupil's official class, whose codes would name it`.
  final String unnamed;

  /// "Aanwezig", or null when the school has no such code.
  PresenceCode? get present => _named(PresenceService.presentCodeName);

  /// "Te laat", or null when the school has no such code.
  PresenceCode? get late => _named(PresenceService.lateCodeName);

  /// "Te laat zonder geldige reden" under "Te laat", or null.
  PresenceAlias? get lateWithoutReason =>
      late?.aliasByName(PresenceService.lateWithoutReasonAliasName);

  /// The code named [name] (ignoring case, as the library resolves it).
  PresenceCode? _named(String name) {
    final target = name.toLowerCase();
    return codes.where((c) => c.name.toLowerCase() == target).firstOrNull;
  }

  /// What [cell] holds (null: no cell yet).
  PresenceKind kindOf(PresenceHalfDay? cell) {
    final (codeId, aliasId) = (cell?.codeId, cell?.aliasId);
    if (aliasId != null) {
      final alias = lateWithoutReason;
      return alias != null && alias.aliasId == aliasId
          ? PresenceKind.lateWithoutReason
          : PresenceKind.other;
    }
    if (codeId == null) return PresenceKind.empty;
    if (codeId == present?.codeId) return PresenceKind.present;
    if (codeId == late?.codeId) return PresenceKind.late;
    return PresenceKind.other;
  }

  /// What [cell] holds, by name: `nothing recorded`, a code such as
  /// `"Te laat"`, an alias such as `"Te laat zonder geldige reden" (under
  /// "Te laat")`; for a code or alias [codes] do not hold, the name the
  /// module gave with the record ([PresenceHalfDay.statusName]: for an
  /// alias, its name alone), or else its id with why it stays unnamed, such
  /// as `code id 70 (the module gave no name with the record, and it is not
  /// among the codes of the class)`.
  String statusOf(PresenceHalfDay? cell) {
    if (cell == null) return 'nothing recorded';
    final (codeId, aliasId) = (cell.codeId, cell.aliasId);
    if (aliasId != null) {
      for (final code in codes) {
        for (final alias in code.aliases) {
          if (alias.aliasId == aliasId) {
            return '"${_name(alias.name)}" (under "${_name(code.name)}")';
          }
        }
      }
      return _unnamed(cell, 'alias id $aliasId');
    }
    if (codeId == null) return 'nothing recorded';
    for (final code in codes) {
      if (code.codeId == codeId) return '"${_name(code.name)}"';
    }
    return _unnamed(cell, 'code id $codeId');
  }

  /// [cell], whose code or alias [id] is not among [codes]: by the name the
  /// module gave with the record, or else by [id] and [unnamed].
  String _unnamed(PresenceHalfDay cell, String id) {
    final name = _name(cell.statusName ?? '');
    if (name.isNotEmpty) return '"$name"';
    return '$id (the module gave no name with the record, and $unnamed)';
  }

  /// What [cell] holds, with its motivation when it has one: for example
  /// `"Te laat", motivation "bus te laat"`.
  String describe(PresenceHalfDay? cell) {
    final motivation = _name(cell?.motivation ?? '');
    return [
      statusOf(cell),
      if (motivation.isNotEmpty) 'motivation "$motivation"',
    ].join(', ');
  }
}

/// [text] on one line, every run of white space as one space.
String _name(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The name [name] of a class or pupil on one line, or `(no name)`.
String _label(String name) => _name(name).isEmpty ? '(no name)' : _name(name);

/// A pupil as the presence tools name one: name and pupil id, such as
/// `Peeters, Lotte (pupil id 1001)`.
String formatPresencePupil(PresencePupil pupil) =>
    '${_label(pupil.name)} (pupil id ${pupil.userId})';

/// A class as the presence tools name one in a sentence: name and class id,
/// such as `class 1A (class id 298)`.
String formatPresenceClassName(PresenceClassRef presenceClass) =>
    'class ${_label(presenceClass.name)} (class id ${presenceClass.groupId})';

/// The class with class id [groupId], as the presence tools name a class
/// that [config] need not list, such as a pupil's official class
/// ([formatOfficialClass]) or a class a grouping class groups
/// ([PresenceClassRef.downStreamGroupIds]): name and class id, such as
/// `2A ECO (class id 1968)`, or, when the configuration does not list it,
/// `class id 1968 (not among the classes this account may view)`. Seen
/// live, an account without the absence-administrator rights is listed
/// fewer classes than the school has, without sub-groups such as "2A ECO"
/// (yvanvds/dartschool#121).
String formatPresenceClassId(int groupId, PresenceConfig config) =>
    switch (config.classForGroup(groupId)) {
      final listed? => '${_label(listed.name)} (class id $groupId)',
      null =>
        'class id $groupId (not among the classes this account may '
            'view)',
    };

/// The official class of [pupil] ([PresencePupil.officialClassId]), named
/// with [config] ([formatPresenceClassId]): for a pupil listed in a
/// grouping class, the class whose presences `set_pupils_late` and
/// `set_pupils_present` record. `none given by the module` when the module
/// gave none; not seen live, where it gave one with every pupil of all
/// seventeen grouping classes of the school (yvanvds/dartschool#126).
String formatOfficialClass(PresencePupil pupil, PresenceConfig config) =>
    switch (pupil.officialClassId) {
      final groupId? => formatPresenceClassId(groupId, config),
      null => 'none given by the module',
    };

/// What the Presence module said, [text] (in Dutch), quoted on one line and
/// ending a sentence: for example `"Deze klas bevat geen leerlingen."`.
String formatModuleReason(String text) {
  final reason = _name(text);
  return _endsSentence(reason) ? '"$reason"' : '"$reason".';
}

/// [text] on one line, ending a sentence: with a full stop added when it
/// does not end with `.`, `!` or `?`.
String formatSentence(String text) {
  final sentence = _name(text);
  return _endsSentence(sentence) ? sentence : '$sentence.';
}

bool _endsSentence(String text) => RegExp(r'[.!?]$').hasMatch(text);

/// [text] with its first letter in upper case, to start a sentence with.
String capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// [part] in words: `morning` or `afternoon`.
String formatDayPart(DayPart part) => switch (part) {
  DayPart.morning => 'morning',
  DayPart.afternoon => 'afternoon',
};

/// Whether the account may record the half-day presences of [presenceClass]
/// (its pupils' mornings and afternoons, as `set_pupils_late` and
/// `set_pupils_present` do): the module's `userCanConfirm` for the class.
///
/// Not its `userCanRecord`: the module gives a teacher without the
/// absence-administrator rights `userCanRecord` for every class, and refuses
/// that teacher's half-day save ("U heeft geen rechten om afwezigheden te
/// bevestigen voor deze leerling."), while `userCanConfirm` is false for
/// every class. An absence administrator has both (seen live, #95;
/// yvanvds/dartschool#121).
bool mayRecordHalfDays(PresenceClassRef presenceClass) =>
    presenceClass.userCanConfirm;

/// One class of `list_presence_classes`: name, class id, whether the
/// account may record presences for it ([mayRecordHalfDays]), whether it is
/// a grouping class without a school structure, and the classes it groups,
/// named with [config] ([formatPresenceClassId]). For example `1A | class
/// id 298 | may record`, or `2A | class id 1650 | may record | grouping
/// class (no school structure): record in the official class | groups 2A
/// MAW (class id 1652), 2A ECO (class id 1968)`.
///
/// The classes it groups are those the module names, in its order
/// ([PresenceClassRef.downStreamGroupIds]). Seen live: the official classes
/// of a year for six of the school's seventeen grouping classes (2A: 2A
/// MAW, 2A MOW, 2A STEMW and 2A ECO); none for every official class and for
/// the other grouping classes, such as "Taalatelier groep 1", whose pupils
/// come from official classes across the school. For those the line says
/// nothing of them, not "groups none": the list is not the official classes
/// of the pupils (the grouping class 2C listed a pupil of 2E ECO, which it
/// does not name, yvanvds/dartschool#126), which `list_class_presences`
/// gives per pupil.
String formatPresenceClass(
  PresenceClassRef presenceClass,
  PresenceConfig config,
) {
  final grouped = [
    for (final groupId in presenceClass.downStreamGroupIds)
      formatPresenceClassId(groupId, config),
  ];
  return [
    _label(presenceClass.name),
    'class id ${presenceClass.groupId}',
    mayRecordHalfDays(presenceClass) ? 'may record' : 'view only',
    if (presenceClass.structId == null)
      'grouping class (no school structure): record in the official class',
    if (grouped.isNotEmpty) 'groups ${grouped.join(', ')}',
  ].join(' | ');
}

/// One pupil of `list_class_presences` on the day [day] (`yyyy-MM-dd`):
/// name, pupil id, the pupil's [officialClass] when it is given (for a
/// pupil of a grouping class, [formatOfficialClass]), and what the morning
/// and the afternoon hold, named with [codes]. For example `- Peeters,
/// Lotte (pupil id 1001) | morning: "Aanwezig" | afternoon: "Te laat",
/// motivation "bus"`, or in a grouping class `- Maes, Finn (pupil id 1201)
/// | official class: 2A ECO (class id 1968) | morning: "Te laat" |
/// afternoon: "Aanwezig"`.
String formatPresenceLine(
  PresencePupil pupil,
  String day,
  PresenceCodes codes, {
  String? officialClass,
}) => [
  '- ${formatPresencePupil(pupil)}',
  if (officialClass != null) 'official class: $officialClass',
  for (final part in DayPart.values)
    '${formatDayPart(part)}: '
        '${codes.describe(pupil.halfDayFor(part, date: day))}',
].join(' | ');
