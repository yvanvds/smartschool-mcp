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
/// to name what a half-day holds and to tell its [PresenceKind]; empty for a
/// class without a structure (a grouping class), whose half-days are named
/// by their code id.
final class PresenceCodes {
  PresenceCodes(this.codes);

  final List<PresenceCode> codes;

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
  /// "Te laat")`, or a code or alias id the codes do not hold.
  String statusOf(PresenceHalfDay? cell) {
    final (codeId, aliasId) = (cell?.codeId, cell?.aliasId);
    if (aliasId != null) {
      for (final code in codes) {
        for (final alias in code.aliases) {
          if (alias.aliasId == aliasId) {
            return '"${_name(alias.name)}" (under "${_name(code.name)}")';
          }
        }
      }
      return 'alias id $aliasId (not among the codes of the class)';
    }
    if (codeId == null) return 'nothing recorded';
    for (final code in codes) {
      if (code.codeId == codeId) return '"${_name(code.name)}"';
    }
    return 'code id $codeId (not among the codes of the class)';
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
/// account may record presences for it ([mayRecordHalfDays]), and whether
/// it is a grouping class without a school structure. For example
/// `1A | class id 298 | may record`.
String formatPresenceClass(PresenceClassRef presenceClass) => [
  _label(presenceClass.name),
  'class id ${presenceClass.groupId}',
  mayRecordHalfDays(presenceClass) ? 'may record' : 'view only',
  if (presenceClass.structId == null)
    'grouping class (no school structure): record in the official class',
].join(' | ');

/// One pupil of `list_class_presences` on the day [day] (`yyyy-MM-dd`):
/// name, pupil id, and what the morning and the afternoon hold, named with
/// [codes]. For example `- Peeters, Lotte (pupil id 1001) | morning:
/// "Aanwezig" | afternoon: "Te laat", motivation "bus"`.
String formatPresenceLine(
  PresencePupil pupil,
  String day,
  PresenceCodes codes,
) => [
  '- ${formatPresencePupil(pupil)}',
  for (final part in DayPart.values)
    '${formatDayPart(part)}: '
        '${codes.describe(pupil.halfDayFor(part, date: day))}',
].join(' | ');
