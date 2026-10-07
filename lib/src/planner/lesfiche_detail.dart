import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../session.dart';
import '../tools/arguments.dart';
import '../tools/server_tool.dart';
import 'lesfiches.dart';
import 'planner_access.dart';
import 'planner_format.dart';

// One lesfiche of the Lesfiches module in full (dartschool#129), as
// `read_lesfiche` shows it and the tools that make or change a lesfiche
// (#114, #115) give it back: the `type` argument of a tool
// that takes one lesfiche, reading its detail, how it is written (with its
// weblinks and attachments and when pupils see them), the `visibility` a
// tool that makes or changes a weblink or an attachment takes, and the
// `attachment` argument of the tools that save or read one of its
// attachments. The tools reach the module with `withPlannerClient`
// (`planner_access.dart`), which turns its other errors into ToolErrors; the
// writes share `lesfiche_writes.dart`.

/// The `type` argument of a tool that takes one lesfiche, by the kind of
/// lesfiche each value names: `lesson` (the default) or `assignment`, the
/// kind `list_lesfiches` shows first on the lesfiche's line.
const lesficheTypes = {
  'lesson': LessonContentType.lesson,
  'assignment': LessonContentType.assignment,
};

/// The input schema of the `type` argument ([lesficheTypes]).
Schema lesficheTypeSchema() => UntitledSingleSelectEnumSchema(
  description:
      'The kind of the lesfiche, as list_lesfiches shows it first on its '
      'line: lesson (the default) or assignment.',
  values: lesficheTypes.keys.toList(),
);

/// The kind of lesfiche the `type` argument [value] names
/// ([lesficheTypes]); a lesson when it is absent. The input schema allows
/// only those values.
LessonContentType lesficheTypeArgument(Object? value) =>
    lesficheTypes[value] ?? LessonContentType.lesson;

/// [type] in words: `lesson lesfiche`, `assignment lesfiche`, or `lesfiche`
/// for a kind the library does not know.
String lesficheKindName(LessonContentType type) => switch (type) {
  LessonContentType.lesson => 'lesson lesfiche',
  LessonContentType.assignment => 'assignment lesfiche',
  LessonContentType.other => 'lesfiche',
};

/// [item] in a few words, for a sentence: `the lesson lesfiche "Lussen"`, or
/// with its id when it has no name.
String lesficheTitle(LessonContentItem item) {
  final name = item.name.trim();
  return 'the ${lesficheKindName(item.type)} '
      '${name.isEmpty ? item.id : '"$name"'}';
}

/// A lesfiche as a tool read it ([readLesficheDetail]): its [detail], and,
/// when the school's course list that names its courses could not be read,
/// that error ([courseError]; the detail's courses then have no names).
typedef LesficheRead = ({
  LessonContentDetail detail,
  SmartschoolLessonContentCourseListError? courseError,
});

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Reads the detail of the lesfiche [id] of the kind [type] with [client]
/// (`LessonContentService.getDetailById`): with its courses named after the
/// school's course list unless not [withCourseNames] (one request less).
///
/// A course list that cannot be read does not lose the lesfiche: the result
/// then holds the detail as read, with the error ([LesficheRead]). The
/// module's `404` (it has no lesfiche of that kind with that id: a made-up
/// id, or the id of the other kind; a lesfiche in the trash is still
/// answered) is a [ToolError] that says to take the id and the kind from
/// `list_lesfiches` ([lesficheNotFound]); so is an [id] that is not a UUID,
/// without a request. Any other error is passed on, for
/// `withPlannerClient`.
Future<LesficheRead> readLesficheDetail(
  SmartschoolClient client,
  LessonContentType type,
  String id, {
  bool withCourseNames = true,
}) async {
  if (!_uuid.hasMatch(id)) throw lesficheNotFound(type, id);
  try {
    final detail = await LessonContentService(
      client,
    ).getDetailById(type, id, withCourseNames: withCourseNames);
    return (detail: detail, courseError: null);
  } on SmartschoolLessonContentNotFoundError catch (error) {
    log('lesfiches: $error');
    throw lesficheNotFound(type, id);
  } on SmartschoolLessonContentCourseListError catch (error) {
    // Only the course list that names the courses failed: its error
    // carries the lesfiche as read, without the names.
    log('lesfiches: $error');
    if (error.items case [final LessonContentDetail detail]) {
      return (detail: detail, courseError: error);
    }
    rethrow;
  }
}

/// The [ToolError] for a lesfiche [id] of the kind [type] that the module
/// does not have: what to take from `list_lesfiches`.
ToolError lesficheNotFound(LessonContentType type, String id) {
  final other = type == LessonContentType.assignment
      ? 'a lesson lesfiche is read with type lesson'
      : 'an assignment lesfiche is read with type assignment';
  return ToolError(
    'You have no ${lesficheKindName(type)} with id $id. Take the id and the '
    'kind from list_lesfiches (type all lists both kinds): $other, and a '
    'lesfiche asked for as the other kind is not found.',
  );
}

/// When pupils see a weblink or an attachment of a lesfiche ([visibility]),
/// counted from the lesson the lesfiche is planned in: `always`, `never`,
/// `from the start of the lesson it is planned in`, `from the end of the
/// lesson it is planned in`, `from 3 days after the end of the lesson it is
/// planned in`; an option the library does not know by the module's name
/// for it.
String formatLesficheVisibility(LessonContentVisibility visibility) {
  const lesson = 'the lesson it is planned in';
  final days = visibility.daysAfterEnd;
  return switch (visibility.option) {
    LessonContentVisibilityOption.always => 'always',
    LessonContentVisibilityOption.never => 'never',
    LessonContentVisibilityOption.atStart => 'from the start of $lesson',
    LessonContentVisibilityOption.atEnd => 'from the end of $lesson',
    LessonContentVisibilityOption.daysAfterEnd => switch (days) {
      null => 'some days after the end of $lesson (the module gave no number)',
      1 => 'from 1 day after the end of $lesson',
      _ => 'from $days days after the end of $lesson',
    },
    LessonContentVisibilityOption.other =>
      'as the module\'s option "${visibility.optionName}"'
          '${days == null ? '' : ' with $days days'}, which this server does '
          'not know',
  };
}

/// The values of a `visibility` argument ([lesficheVisibilityArgument]), as
/// a tool's description and errors list them.
const lesficheVisibilityValues =
    'always (the default), never, at_start (from the start of the lesson it '
    'is planned in), at_end (from its end) or after_end:N (from N days after '
    'its end, N from 1 to ${LessonContentVisibility.maxDaysAfterEnd})';

/// The input schema of a `visibility` argument of a weblink or an attachment
/// of a lesfiche ([lesficheVisibilityArgument]), with [description] (what
/// it is the visibility of) in front of the values.
///
/// A plain string, not an enum: `after_end:N` takes a number, and the tool
/// words a wrong value itself.
Schema lesficheVisibilitySchema({String description = 'When pupils see it'}) =>
    Schema.string(
      description:
          '$description, counted from the lesson the lesfiche is planned in: '
          '$lesficheVisibilityValues.',
    );

final _afterEnd = RegExp(r'^after[_-]end\s*:\s*(\d{1,4})$');

/// [value], the visibility of a weblink or an attachment that a tool takes
/// ([where] names it in an error, like `the visibility of weblink 1`):
/// `always`, `never`, `at_start`, `at_end` or `after_end:N` with N from 1 to
/// [LessonContentVisibility.maxDaysAfterEnd], the options the web client
/// offers; [LessonContentVisibility.always] when it is absent or empty.
/// Case and the white space around it do not matter, and a hyphen does for
/// an underscore (`at-start`, the module's own name).
///
/// Throws a [ToolError] that lists the values for anything else, so that it
/// never goes into a request. [formatLesficheVisibility] words the result.
LessonContentVisibility lesficheVisibilityArgument(
  Object? value, {
  required String where,
}) {
  final text = value is String ? value.trim().toLowerCase() : null;
  if (value == null || text == '') return LessonContentVisibility.always;
  switch (text?.replaceAll('-', '_')) {
    case 'always':
      return LessonContentVisibility.always;
    case 'never':
      return LessonContentVisibility.never;
    case 'at_start':
      return LessonContentVisibility.atStart;
    case 'at_end':
      return LessonContentVisibility.atEnd;
  }
  if (_afterEnd.firstMatch(text ?? '') case final match?) {
    final days = int.parse(match[1]!);
    if (days >= 1 && days <= LessonContentVisibility.maxDaysAfterEnd) {
      return LessonContentVisibility.afterEnd(days);
    }
    throw ToolError(
      '$where is after_end:$days, but the web client offers 1 to '
      '${LessonContentVisibility.maxDaysAfterEnd} days after the end of the '
      'lesson. Nothing was sent.',
    );
  }
  throw ToolError(
    '$where is ${value is String ? '"$value"' : '$value'}, which is not a '
    'visibility: pass $lesficheVisibilityValues. Nothing was sent.',
  );
}

/// [visibility] as a `visibility` argument gives it
/// ([lesficheVisibilityArgument]): `always`, `never`, `at_start`, `at_end`
/// or `after_end:N`; null for one that no argument gives (an option the
/// library does not know, or days after the end without a number).
///
/// How a result tells Claude what to pass to set a visibility, like
/// `add_lesfiche_attachments` when one was not set.
String? lesficheVisibilityValue(LessonContentVisibility visibility) {
  final days = visibility.daysAfterEnd;
  return switch (visibility.option) {
    LessonContentVisibilityOption.always => 'always',
    LessonContentVisibilityOption.never => 'never',
    LessonContentVisibilityOption.atStart => 'at_start',
    LessonContentVisibilityOption.atEnd => 'at_end',
    LessonContentVisibilityOption.daysAfterEnd =>
      days == null ? null : 'after_end:$days',
    LessonContentVisibilityOption.other => null,
  };
}

/// One line describing [weblink]: its name, address, icon, when pupils see
/// it ([formatLesficheVisibility]) and its id, like `Oefeningen |
/// https://example.com/oefeningen | icon earth | visible to pupils: from
/// the end of the lesson it is planned in | id e0000000-…`.
String formatLesficheWeblink(LessonContentWeblink weblink) => [
  if (weblink.name.trim() case final name when name.isNotEmpty)
    name
  else
    '(no name)',
  if (weblink.url.trim() case final url when url.isNotEmpty)
    url
  else
    '(no address)',
  if (weblink.icon.trim() case final icon when icon.isNotEmpty) 'icon $icon',
  'visible to pupils: ${formatLesficheVisibility(weblink.visibility)}',
  'id ${weblink.id}',
].join(' | ');

/// One line describing [attachment]: its file name, size, type, when pupils
/// see it ([formatLesficheVisibility]) and its id, like `lussen.txt | 16
/// bytes | text/plain | visible to pupils: never | id f0000000-…`.
String formatLesficheAttachment(LessonContentAttachment attachment) => [
  _fileName(attachment),
  if (attachment.fileSize case final size?) formatFileSize(size),
  if (attachment.mimeType?.trim() case final type? when type.isNotEmpty) type,
  'visible to pupils: ${formatLesficheVisibility(attachment.visibility)}',
  'id ${attachment.id}',
].join(' | ');

String _fileName(LessonContentAttachment attachment) {
  final name = attachment.fileName.trim();
  return name.isEmpty ? '(no name)' : name;
}

/// [detail] as text, one field per line: its id, kind (an assignment with
/// its type), name, icon, labels, courses (by name, unless [courseError]
/// says the school's course list could not be read: then how many), visible
/// or hidden in the module, its weblinks ([formatLesficheWeblink]) and its
/// attachments, numbered from 1 ([formatLesficheAttachment]); notes on what
/// is not shown and on the courses; then its public info and private info
/// as plain text ([plannerInfoText]).
///
/// What `read_lesfiche` answers, and what the tools that make or change a
/// lesfiche give back after their own lines.
String formatLesficheDetail(
  LessonContentDetail detail, {
  SmartschoolLessonContentError? courseError,
}) {
  final withCourseNames = courseError == null;
  final labels = [
    for (final label in detail.labels)
      if (label.text.trim() case final text when text.isNotEmpty) text,
  ];
  final unnamed =
      withCourseNames && detail.courses.any((course) => course.name == null);
  final notShown = [
    if (detail.partnerWeblinkCount > 0)
      _count(
        detail.partnerWeblinkCount,
        'weblink of a publisher',
        'weblinks of publishers',
      ),
    if (detail.deeplinkCount > 0)
      _count(detail.deeplinkCount, 'deeplink', 'deeplinks'),
  ];
  String info(String html) {
    final text = plannerInfoText(html);
    return text.isEmpty ? '(none)' : text;
  }

  return [
    'Lesfiche ${detail.id}',
    'Kind: ${formatLesficheKind(detail)}',
    'Name: ${detail.name.isEmpty ? '(no name)' : detail.name}',
    if (detail.icon?.trim() case final icon? when icon.isNotEmpty)
      'Icon: $icon',
    'Labels: ${labels.isEmpty ? 'none' : labels.join(', ')}',
    'Courses: '
        '${detail.courses.isEmpty ? 'none' : formatLesficheCourses(detail, withCourseNames: withCourseNames)}',
    'In the module: ${detail.isVisible ? 'visible' : 'hidden'}',
    if (detail.weblinks.isEmpty)
      'Weblinks: none'
    else ...[
      'Weblinks:',
      for (final weblink in detail.weblinks)
        '- ${formatLesficheWeblink(weblink)}',
    ],
    if (detail.attachments.isEmpty)
      'Attachments: none'
    else ...[
      'Attachments:',
      for (final (index, attachment) in detail.attachments.indexed)
        '${index + 1}. ${formatLesficheAttachment(attachment)}',
    ],
    if (notShown.isNotEmpty)
      'Note: it also has ${notShown.join(' and ')}, which are not shown '
          'here.',
    if (courseError != null && detail.courses.isNotEmpty)
      lesficheCourseListNote(courseError),
    if (unnamed) unnamedLesficheCourseNote,
    '',
    'Public info (what pupils see):',
    info(detail.publicInfo),
    '',
    'Private info (hidden from pupils):',
    info(detail.privateInfo),
  ].join('\n');
}

String _count(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

/// The input schema of the `attachment` argument: an attachment of a
/// lesfiche by its number or its file name.
Schema lesficheAttachmentSchema() => Schema.combined(
  description:
      'Which attachment: its number as read_lesfiche lists it (1 for the '
      'first), or its file name.',
  anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
);

/// The `attachment` argument of [arguments]: a number from 1, or a file
/// name (without white space around it). Throws a [ToolError] when it is
/// absent or empty.
Object lesficheAttachmentArgument(Map<String, Object?> arguments) {
  final value = arguments['attachment'];
  if (value is String) {
    final name = value.trim();
    if (name.isEmpty) {
      throw const ToolError(
        'attachment is empty: pass its number as read_lesfiche lists it (1 '
        'for the first), or its file name.',
      );
    }
    return name;
  }
  return requiredIntArgument(arguments, 'attachment');
}

/// The attachment of [lesfiche] that [which] names (a number from 1, as
/// [formatLesficheDetail] numbers them, or a file name, exactly or else
/// ignoring case), with its number.
///
/// Throws a [ToolError] that lists the attachments for a lesfiche without
/// attachments, a number it does not have, a name it does not have, or a
/// name that two of its attachments have (the module keeps both): then the
/// number tells them apart. A number written as text names the attachment
/// with that number, unless an attachment has it as its name.
(int, LessonContentAttachment) pickLesficheAttachment(
  LessonContentDetail lesfiche,
  Object which,
) {
  final attachments = lesfiche.attachments;
  final what = _capitalise(lesficheTitle(lesfiche));
  if (attachments.isEmpty) throw ToolError('$what has no attachments.');
  final numbered = [
    for (final (index, attachment) in attachments.indexed)
      (index + 1, attachment),
  ];
  String list([Iterable<(int, LessonContentAttachment)>? only]) => [
    for (final (number, attachment) in only ?? numbered)
      '$number. ${_fileName(attachment)}'
          '${attachment.fileSize == null ? '' : ' (${formatFileSize(attachment.fileSize!)})'}',
  ].join('\n');
  final count = _count(attachments.length, 'attachment', 'attachments');

  if (which is String) {
    for (final matches in [
      (String name) => name == which,
      (String name) => name.toLowerCase() == which.toLowerCase(),
    ]) {
      final found = [
        for (final entry in numbered)
          if (matches(entry.$2.fileName.trim())) entry,
      ];
      if (found.length == 1) return found.single;
      if (found.length > 1) {
        throw ToolError(
          '$what has more than one attachment named "$which": pass its '
          'number instead.\n${list(found)}',
        );
      }
    }
    if (int.tryParse(which) case final number?) {
      return pickLesficheAttachment(lesfiche, number);
    }
    throw ToolError(
      '$what has no attachment named "$which". Its $count:\n${list()}',
    );
  }
  final number = which as int;
  if (number < 1 || number > attachments.length) {
    throw ToolError(
      '$what has $count, so there is no attachment $number: pass a number '
      'from 1 to ${attachments.length}, or the file name.\n${list()}',
    );
  }
  return numbered[number - 1];
}

/// An attachment of a lesfiche as `save_lesfiche_attachment` and
/// `read_lesfiche_attachment` find it ([findLesficheAttachment]).
typedef LesficheAttachment = ({
  LessonContentDetail lesfiche,
  int number,
  LessonContentAttachment attachment,
});

/// Reads the lesfiche [id] of the kind [type] with [session]
/// ([readLesficheDetail], without the course names, which are not needed)
/// and picks its attachment [which] ([pickLesficheAttachment]): the
/// lesfiche, the attachment and its number. The errors of the module become
/// [ToolError]s (`withPlannerClient`).
Future<LesficheAttachment> findLesficheAttachment(
  SmartschoolSession session,
  LessonContentType type,
  String id,
  Object which,
) async {
  final (:detail, courseError: _) = await withPlannerClient(
    session,
    (client) => readLesficheDetail(client, type, id, withCourseNames: false),
  );
  final (number, attachment) = pickLesficheAttachment(detail, which);
  return (lesfiche: detail, number: number, attachment: attachment);
}

/// [attachment], the attachment [number] of [lesfiche], in a few words:
/// `attachment 1 of the lesson lesfiche "Lussen", "lussen.txt"`.
String lesficheAttachmentTitle(
  LessonContentDetail lesfiche,
  int number,
  LessonContentAttachment attachment,
) =>
    'attachment $number of ${lesficheTitle(lesfiche)}, '
    '"${_fileName(attachment)}"';

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
