import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../problems.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'lesfiche_detail.dart';
import 'planner_access.dart';

// Making and changing lesfiches in the user's own library of the Lesfiches
// module (dartschool#129), shared by the tools that write there
// (`create_lesfiche`, and the edits after it: `edit_lesfiche`,
// `set_lesfiche_weblink`, `remove_lesfiche_weblink`,
// `add_lesfiche_attachments`, `set_lesfiche_attachment_visibility`,
// `remove_lesfiche_attachment`): the name, the courses, the weblinks and the
// attachments a tool takes, and the weblink or attachment it names by its
// id, checked before anything is sent; the write itself, with the library's
// errors as ToolErrors ([withLesficheWrite], [lesficheWriteToolError]); a
// write the module did not confirm ([lesficheWriteNotConfirmed]); and the
// result of a change, with the lesfiche read back
// ([lesficheChangedResult]). When pupils see a weblink or an attachment is
// parsed and worded in `lesfiche_detail.dart`
// (`lesficheVisibilityArgument`, `formatLesficheVisibility`).
//
// The tools that change a lesfiche read it first, in the session action of
// the write: the library's writes take the lesfiche as read, the tools check
// the weblink or attachment they name against it, and a write's `404` then
// means that the lesfiche is in the trash (a lesfiche in the trash is still
// read, but its writes are answered `404`, seen live), not that the id or
// the kind is wrong (`readLesficheDetail` says that).
//
// The library sends a create once, never again after logging in again, nor
// retried in any other way (the same for adding a weblink and the last step
// of adding attachments), and throws a
// [SmartschoolLessonContentSaveUnconfirmedError] when the module's answer
// does not confirm a write that went out. That is why repeating a write's
// action, as [SmartschoolSession.run] does when Smartschool refused the
// session, cannot make a lesfiche, a weblink or an attachment twice: a
// refused session means the write was not carried out, and an unconfirmed
// write is not a refused session, so it is not repeated. The repeat reads
// again what the action read before the write, and that read must come
// first: a request that goes out once only is refused at once on an expired
// session, without logging in, so it is a read of the repeat that logs in
// again (yvanvds/dartschool#134). The module keeps a name that is taken
// (seen live), and adds a second weblink or attachment for a second add, so
// Claude is told never to call a create or an add again that may or may not
// have been made. The edits and the removals set or name what they act on:
// the library retries them after logging in again, as a read.

/// What a tool that makes a lesfiche adds to an error that came before the
/// module made it (after the arguments were checked and sent on).
const noLesficheMade = 'No lesfiche was made.';

/// [value], the `name` argument of a tool that names a lesfiche, without the
/// white space around it.
///
/// Throws a [ToolError] for an empty name, and for one longer than the
/// [LessonContentService.maxNameLength] characters the web client's name
/// field takes (the library refuses it, and the module answers an empty one
/// with a bare `400`), so that it never goes into a request.
String lesficheNameArgument(Object? value) {
  final name = value is String ? value.trim() : '';
  if (name.isEmpty) {
    throw const ToolError(
      'name is empty: give the lesfiche a name. $nothingSent',
    );
  }
  if (name.length > LessonContentService.maxNameLength) {
    throw ToolError(
      'name is ${name.length} characters long, and the Lesfiches module takes '
      'at most ${LessonContentService.maxNameLength}: shorten it. '
      '$nothingSent',
    );
  }
  return name;
}

/// The input schema of a `courses` argument ([lesficheCoursesArgument]).
Schema lesficheCoursesSchema({required String description}) => Schema.list(
  description:
      '$description Each course by its name as list_lesfiches, '
      'read_lesfiche and list_planner show it (like informatica), from the '
      'school\'s course list; a name that two courses have is told apart by '
      'the id the error gives.',
  items: Schema.string(minLength: 1),
);

/// [value], the `courses` argument [name] of a tool: courses of the school,
/// each by its name as the tools show it (`informatica`) or by its id; null
/// when it is absent. Without the white space around an item, and without
/// duplicates (ignoring case), in the order given; an empty list is no
/// courses.
///
/// Throws a [ToolError] for an item that is not a text with something in
/// it, so that it never goes into a request. [lesficheCourses] matches the
/// items with the school's courses.
List<String>? lesficheCoursesArgument(
  Object? value, {
  String name = 'courses',
}) {
  if (value == null) return null;
  final items = value is List ? value : [value];
  final courses = <String>[];
  for (final item in items) {
    final text = item is String ? item.trim() : '';
    if (text.isEmpty) {
      throw ToolError(
        'each item of $name must be a course by its name as list_lesfiches '
        'or list_planner show it (like informatica); '
        '${item is String ? '"$item"' : '$item'} is not. $nothingSent',
      );
    }
    if (!courses.any((known) => known.toLowerCase() == text.toLowerCase())) {
      courses.add(text);
    }
  }
  return courses;
}

/// The courses of [school], the school's course list
/// (`LessonContentService.getCourses`), that [wanted] names
/// ([lesficheCoursesArgument]), in that order and each once: by its id
/// (ignoring case), else by its name (ignoring case and extra white space).
///
/// Throws a [ToolError] when an item of [wanted], the argument [name], names
/// no course of the list (the module would store an unknown course without
/// complaint, and the library refuses one), with the names of the school's
/// courses; or a name that several courses have, with their ids, which tell
/// them apart.
List<PlannerCourse> lesficheCourses(
  List<PlannerCourse> school,
  List<String> wanted, {
  String name = 'courses',
}) {
  String normal(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final chosen = <PlannerCourse>[];
  final unknown = <String>[];
  for (final item in wanted) {
    final byId = school
        .where((course) => course.id.toLowerCase() == item.toLowerCase())
        .toList();
    final matches = byId.isNotEmpty
        ? byId
        : [
            for (final course in school)
              if (normal(course.name) == normal(item)) course,
          ];
    if (matches.isEmpty) {
      unknown.add('"$item"');
    } else if (matches.length > 1) {
      final listed = [
        for (final course in matches) '${course.name} (id ${course.id})',
      ];
      throw ToolError(
        '$name holds "$item", which names ${matches.length} of the school\'s '
        'courses: ${listed.join(', ')}. Ask the user which one is meant, and '
        'pass its id instead. $nothingSent',
      );
    } else if (!chosen.any((course) => course.id == matches.single.id)) {
      chosen.add(matches.single);
    }
  }
  if (unknown.isNotEmpty) {
    final names =
        {
          for (final course in school)
            if (course.name.trim().isNotEmpty) course.name.trim(),
        }.toList()..sort((a, b) {
          final order = a.toLowerCase().compareTo(b.toLowerCase());
          return order != 0 ? order : a.compareTo(b);
        });
    throw ToolError(
      '$name holds ${unknown.join(', ')}, which '
      '${unknown.length == 1 ? 'is not a course' : 'are not courses'} of the '
      'school\'s course list. '
      '${names.isEmpty ? 'The course list names no courses.' : 'Its courses are ${names.join(', ')}.'} '
      'Pass a course by its name as list_lesfiches or list_planner show it. '
      '$nothingSent',
    );
  }
  return chosen;
}

/// The input schema of a `weblinks` argument ([lesficheWeblinksArgument]).
Schema lesficheWeblinksSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.object(
    properties: {
      'name': Schema.string(
        description: 'The name the weblink shows.',
        minLength: 1,
      ),
      'url': Schema.string(
        description:
            'The address it opens, like https://example.com/oefeningen. One '
            'without http:// or https:// in front gets http://, as the web '
            'client sends it.',
        minLength: 1,
      ),
      'visibility': lesficheVisibilitySchema(
        description: 'When pupils see the weblink',
      ),
    },
    required: ['name', 'url'],
  ),
);

/// [value], the `weblinks` argument [name] of a tool: weblinks for a
/// lesfiche, each `{name, url, visibility?}` ([lesficheWeblinkArgument]), in
/// the order given; empty when it is absent.
///
/// Throws a [ToolError] that names the weblink for anything it refuses.
List<NewLessonContentWeblink> lesficheWeblinksArgument(
  Object? value, {
  String name = 'weblinks',
}) {
  if (value == null) return const [];
  final items = value is List ? value : [value];
  return [
    for (final (index, item) in items.indexed)
      lesficheWeblinkArgument(item, where: 'weblink ${index + 1} of $name'),
  ];
}

/// [item], one weblink for a lesfiche (`{name, url, visibility?}`; [where]
/// names it in an error, like `weblink 1 of weblinks`): its name without the
/// white space around it, its address as the library sends it
/// ([LessonContentService.normalizeWeblinkUrl]: without white space, with
/// `http://` in front when it has no scheme), and when pupils see it
/// ([lesficheVisibilityArgument], always by default), with the web client's
/// icon.
///
/// Throws a [ToolError] for a weblink without a name or an address, and an
/// address the web client refuses (the module answers it with a bare `400`),
/// so that it never goes into a request.
NewLessonContentWeblink lesficheWeblinkArgument(
  Object? item, {
  required String where,
}) {
  if (item is! Map) {
    throw ToolError(
      '$where must be an object with the name and the url of the weblink, '
      'and optionally its visibility. $nothingSent',
    );
  }
  final name = item['name'] is String ? (item['name'] as String).trim() : '';
  if (name.isEmpty) {
    throw ToolError('$where has no name: give it one. $nothingSent');
  }
  final url = item['url'] is String ? (item['url'] as String).trim() : '';
  if (url.isEmpty) {
    throw ToolError('$where ("$name") has no url. $nothingSent');
  }
  final address = LessonContentService.normalizeWeblinkUrl(url);
  if (address == null) {
    throw ToolError(
      '$where ("$name") has the url "$url", which is not a web address the '
      'Lesfiches web client takes: pass one like https://example.com/page. '
      '$nothingSent',
    );
  }
  return NewLessonContentWeblink(
    name: name,
    url: address,
    visibility: lesficheVisibilityArgument(
      item['visibility'],
      where: 'the visibility of $where ("$name")',
    ),
  );
}

/// A file on this PC that a tool attaches to a lesfiche ([file], checked by
/// [checkLocalFiles]), with when pupils see it ([visibility]).
typedef LesficheFile = ({LocalFile file, LessonContentVisibility visibility});

/// [files] as the library takes them.
List<NewLessonContentAttachment> lesficheAttachments(
  Iterable<LesficheFile> files,
) => [
  for (final (:file, :visibility) in files)
    NewLessonContentAttachment(file.path, visibility: visibility),
];

/// The input schema of an `attachments` argument
/// ([lesficheAttachmentsArgument]).
Schema lesficheAttachmentsSchema({required String description}) => Schema.list(
  description: description,
  items: Schema.object(
    properties: {
      'path': Schema.string(
        description:
            'The full path of the file on this PC, like '
            'C:\\Users\\jan\\Documents\\werkblad.docx. It goes in under '
            'its own name.',
        minLength: 1,
      ),
      'visibility': lesficheVisibilitySchema(
        description: 'When pupils see the file',
      ),
    },
    required: ['path'],
  ),
  maxItems: maxLocalFiles,
);

/// [value], the `attachments` argument [name] of a tool: files on this PC
/// for a lesfiche, each `{path, visibility?}`, in the order given; empty
/// when it is absent or an empty list.
///
/// The paths are checked with [checkLocalFiles] (1 to [maxLocalFiles]
/// absolute paths of existing files of at most [maxBytes], each with a name
/// Smartschool takes, no two with the same name ignoring case: the module
/// sends the visibility of an attachment by its name), and the visibilities
/// with [lesficheVisibilityArgument]. Throws a [ToolError] that names the
/// path or the item, before anything is sent.
List<LesficheFile> lesficheAttachmentsArgument(
  Object? value, {
  String name = 'attachments',
  int maxBytes = maxLocalFileBytes,
}) {
  if (value == null) return const [];
  final items = value is List ? value : [value];
  if (items.isEmpty) return const [];
  final paths = <String>[];
  final visibilities = <LessonContentVisibility>[];
  for (final (index, item) in items.indexed) {
    final where = 'attachment ${index + 1} of $name';
    final path = item is Map && item['path'] is String
        ? (item['path'] as String).trim()
        : '';
    if (path.isEmpty) {
      throw ToolError(
        '$where must be an object with the full path of a file on this PC '
        '(path, like C:\\Users\\jan\\Documents\\werkblad.docx), and '
        'optionally its visibility. $nothingSent',
      );
    }
    paths.add(path);
    visibilities.add(
      lesficheVisibilityArgument(
        (item as Map)['visibility'],
        where: 'the visibility of $where ("$path")',
      ),
    );
  }
  final files = checkLocalFiles(paths, argument: name, maxBytes: maxBytes);
  return [
    for (final (index, file) in files.indexed)
      (file: file, visibility: visibilities[index]),
  ];
}

/// Runs the Lesfiches write [write] on the session, for a tool that makes
/// or changes a lesfiche; [what] names what is written (like `the lesson
/// lesfiche "Lussen"`), for the errors, and [nothingDone] says what an
/// error means for the call (like [noLesficheMade]).
///
/// The library's errors become [ToolError]s that end in [nothingDone]
/// ([lesficheWriteToolError], with [files] and [orGone]). A [ToolError] of
/// [write] itself (a check before sending), a
/// [SmartschoolLessonContentSaveUnconfirmedError] (the write may or may not
/// have been made: [lesficheWriteNotConfirmed]) and a login or connection
/// failure are thrown as they are.
Future<T> withLesficheWrite<T>(
  SmartschoolSession session,
  Future<T> Function(SmartschoolClient client) write, {
  required String Function() what,
  required String nothingDone,
  Iterable<LocalFile> files = const [],
  String? orGone,
}) async {
  try {
    return await session.run(write);
  } on SmartschoolLessonContentSaveUnconfirmedError {
    rethrow;
  } catch (error) {
    final toolError = lesficheWriteToolError(
      error,
      what: what(),
      nothingDone: nothingDone,
      files: files,
      orGone: orGone,
    );
    if (toolError == null) rethrow;
    throw toolError;
  }
}

/// The [ToolError] for [error], an error of a Lesfiches write that came
/// before the module made or changed anything, ending in [nothingDone];
/// null for anything else. [what] names what is written, like `the change
/// of the name of the lesson lesfiche "Lussen"`.
///
/// - [SmartschoolLessonContentNotFoundError]: the module answered the write
///   of a lesfiche that the tool read just before with `404`. A lesfiche in
///   the trash is still read, but its writes are answered so (seen live,
///   dartschool#129), so it is most likely there; [orGone] says what else
///   may be gone (like `the weblink was removed meanwhile`);
/// - [SmartschoolLessonContentWriteRefusedError]: the module refused the
///   write (HTTP `400` to `499`, a bare `400` seen live), with its reasons
///   in its own words when it gave any;
/// - [SmartschoolAttachmentUploadError], and an [ArgumentError] about one of
///   [files]: a file was not uploaded ([uploadToolError]);
/// - any other [ArgumentError]: the library refused the write before
///   sending it (the courses or the assignment type changed since the tool
///   read them, say);
/// - the other errors of the module and the planner ([plannerToolError]),
///   which come from a read before the write.
///
/// Not a [SmartschoolLessonContentSaveUnconfirmedError] (the write may or
/// may not have been made: [lesficheWriteNotConfirmed]), a [ToolError], a
/// login or connection failure, or a [RangeError] (a bug).
ToolError? lesficheWriteToolError(
  Object error, {
  required String what,
  required String nothingDone,
  Iterable<LocalFile> files = const [],
  String? orGone,
}) {
  switch (error) {
    case SmartschoolLessonContentNotFoundError():
      // The library's message names the lesfiche by its id only, but the
      // log keeps to the same words as the other writes.
      log('lesfiches write: the module answered 404');
      return ToolError(
        'The Lesfiches module answered $what with HTTP 404: the lesfiche is '
        'in the trash or no longer exists'
        '${orGone == null ? '' : ', or $orGone'}. A lesfiche in the trash '
        'can still be read, but not changed, and list_lesfiches does not '
        'list it; the user restores it from the trash in the Lesfiches '
        'module itself. $nothingDone',
      );
    case SmartschoolLessonContentWriteRefusedError(
      :final statusCode,
      :final violations,
    ):
      // The library's message names the lesfiche: the log never shows a
      // name.
      log(
        'lesfiches write: refused (HTTP $statusCode, '
        '${violations.length} reasons)',
      );
      return ToolError(
        'The Lesfiches module refused $what (HTTP $statusCode)'
        '${violations.isEmpty ? ', without saying why' : ': ${violations.map((v) => '"$v"').join(' ')}'}. '
        '$nothingDone',
      );
    case SmartschoolAttachmentUploadError():
      return uploadToolError(error, files: files, nothingDone: nothingDone);
    case ArgumentError(:final name, :final message) when error is! RangeError:
      if (uploadToolError(error, files: files, nothingDone: nothingDone)
          case final toolError?) {
        return toolError;
      }
      log('lesfiches write: refused before sending ($name)');
      final reason = '$message'.replaceFirst(
        RegExp(r'[.\s]*Nothing was sent\.?$'),
        '',
      );
      return ToolError(
        '${_capitalised(what)} was refused before it was sent: '
        '${name == null ? '' : '$name '}$reason. $nothingDone',
      );
  }
  final toolError = plannerToolError(error);
  if (toolError == null) return null;
  return ToolError('${toolError.message} $nothingDone');
}

/// The result of a Lesfiches write that went out without the module
/// confirming it ([error]): [what] (like `The lesson lesfiche "Lussen"`)
/// may or may not have been [done]. [also] comes after that (like what else
/// the call did). Claude must not call [tool] again for it ([why], when
/// given, says what a second call could do), but first [check] (like `list
/// the lesfiches with list_lesfiches`) and tell the user.
CallToolResult lesficheWriteNotConfirmed({
  required String tool,
  required String what,
  required String check,
  required SmartschoolLessonContentSaveUnconfirmedError error,
  String? why,
  String done = 'made',
  String? also,
}) {
  // Without the library's message, which names the lesfiche.
  log(
    '$tool: the Lesfiches module did not confirm a write, not retrying '
    '(${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'}'
    '${error.cause == null ? '' : ', ${error.cause.runtimeType}'})',
  );
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '$what may or may not have been $done: it was sent, but the '
              'Lesfiches module did not confirm it.',
          ?also,
          'Do not call $tool again for it${why == null ? '' : ': $why'}. '
              'First $check. Then tell the user what you found.',
        ].join(' '),
      ),
    ],
  );
}

/// What a tool that changes a lesfiche adds to an error that came before
/// the module changed anything.
const lesficheUnchanged = 'The lesfiche was not changed.';

/// `read_lesfiche (lesfiche <id>)`, with `type assignment` for an
/// assignment lesfiche: how Claude reads the lesfiche [id] of the kind
/// [type].
String readLesficheCall(LessonContentType type, String id) =>
    'read_lesfiche (lesfiche $id'
    '${type == LessonContentType.assignment ? ', type assignment' : ''})';

/// The result of a write that changed the lesfiche [id] of the kind [type]:
/// [done] (what changed, a line each), a blank line, and the lesfiche read
/// back with its courses named, as `read_lesfiche` shows it
/// ([formatLesficheDetail]). The edits answer without the course names,
/// and the weblink writes and the removals without the lesfiche.
///
/// The read is a session action of its own, after the write's, so that a
/// repeat of the session for it never sends the write again. When it
/// fails, the write still went through: the result says what changed, why
/// the lesfiche is not shown, and how to read it.
Future<CallToolResult> lesficheChangedResult(
  SmartschoolSession session,
  LessonContentType type,
  String id,
  List<String> done,
) async {
  String shown;
  try {
    final (:detail, :courseError) = await withPlannerClient(
      session,
      (client) => readLesficheDetail(client, type, id),
    );
    shown = formatLesficheDetail(detail, courseError: courseError);
  } on Object catch (error) {
    final message = switch (error) {
      ToolError(:final message) => message,
      SmartschoolProblem(:final message) => message,
      _ => null,
    };
    if (message == null) rethrow;
    log('lesfiches: reading the lesfiche back after a write failed');
    shown =
        'The change went through, but reading the lesfiche back failed: '
        '$message Read it with ${readLesficheCall(type, id)} to see it.';
  }
  return CallToolResult(
    content: [
      TextContent(text: [...done, '', shown].join('\n')),
    ],
  );
}

/// [value], the argument [name] of a tool that names a weblink or an
/// attachment of a lesfiche ([what], like `weblink`) by its id, as
/// `read_lesfiche` prints it: without the white space around it, and
/// without a leading `id `.
///
/// Throws a [ToolError] when that is empty, before anything is sent.
/// [lesficheWeblinkById] and [lesficheAttachmentById] find it in the
/// lesfiche.
String lesfichePartIdArgument(
  Object? value, {
  required String name,
  required String what,
}) {
  final text = (value is String ? value.trim() : '')
      .replaceFirst(RegExp(r'^id(\s+|$)', caseSensitive: false), '')
      .trim();
  if (text.isNotEmpty) return text;
  throw ToolError(
    '$name is empty: pass the id of the $what as read_lesfiche shows it at '
    'the end of its line, like e0000000-0000-4000-8000-000000000021. '
    '$nothingSent',
  );
}

/// The weblink of [lesfiche] with the id [id] (ignoring case).
///
/// Throws a [ToolError] that lists the weblinks of [lesfiche] with their
/// ids when it has none with that id, before anything is sent.
LessonContentWeblink lesficheWeblinkById(
  LessonContentDetail lesfiche,
  String id,
) {
  final weblinks = lesfiche.weblinks;
  for (final weblink in weblinks) {
    if (weblink.id.toLowerCase() == id.toLowerCase()) return weblink;
  }
  final listed = [
    for (final weblink in weblinks) '- ${formatLesficheWeblink(weblink)}',
  ];
  throw ToolError(
    '${_capitalised(lesficheTitle(lesfiche))} has no weblink with id $id. '
    '$nothingSent '
    '${weblinks.isEmpty ? 'It has no weblinks.' : 'Its weblinks, each with its id at the end:\n${listed.join('\n')}'}',
  );
}

/// The attachment of [lesfiche] with the id [id] (ignoring case), with its
/// number as `read_lesfiche` numbers them.
///
/// Throws a [ToolError] that lists the attachments of [lesfiche] with their
/// ids when it has none with that id, before anything is sent.
(int, LessonContentAttachment) lesficheAttachmentById(
  LessonContentDetail lesfiche,
  String id,
) {
  final attachments = lesfiche.attachments;
  for (final (index, attachment) in attachments.indexed) {
    if (attachment.id.toLowerCase() == id.toLowerCase()) {
      return (index + 1, attachment);
    }
  }
  final listed = [
    for (final (index, attachment) in attachments.indexed)
      '${index + 1}. ${formatLesficheAttachment(attachment)}',
  ];
  throw ToolError(
    '${_capitalised(lesficheTitle(lesfiche))} has no attachment with id '
    '$id. $nothingSent '
    '${attachments.isEmpty ? 'It has no attachments.' : 'Its attachments, each with its id at the end:\n${listed.join('\n')}'}',
  );
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
