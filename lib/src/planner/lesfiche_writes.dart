import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'lesfiche_detail.dart';
import 'planner_access.dart';

// Making and changing lesfiches in the user's own library of the Lesfiches
// module (dartschool#129), shared by the tools that write there
// (`create_lesfiche`, and the edits after it): the name, the courses, the
// weblinks and the attachments a tool takes, checked before anything is
// sent; the write itself, with the library's errors as ToolErrors
// ([withLesficheWrite]); and a write the module did not confirm
// ([lesficheWriteNotConfirmed]). When pupils see a weblink or an attachment
// is parsed and worded in `lesfiche_detail.dart`
// (`lesficheVisibilityArgument`, `formatLesficheVisibility`).
//
// The library sends a create once, never again after logging in again, nor
// retried in any other way (the same for adding a weblink and the last step
// of adding attachments), and throws a
// [SmartschoolLessonContentSaveUnconfirmedError] when the module's answer
// does not confirm a write that went out. That is why repeating a write's
// action, as [SmartschoolSession.run] does when Smartschool refused the
// session, cannot make a lesfiche twice: a refused session means the write
// was not carried out, and an unconfirmed write is not a refused session, so
// it is not repeated. The repeat reads again what the action read before the
// write, and that read must come first: a request that goes out once only
// is refused at once on an expired session, without logging in, so it is a
// read of the repeat that logs in again (yvanvds/dartschool#134). The module
// keeps a name that is taken (seen live), so Claude is told never to call a
// create again that may or may not have been made.

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
/// The library's errors become [ToolError]s that end in [nothingDone]:
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
/// A [ToolError] of [write] itself (a check before sending), a
/// [SmartschoolLessonContentSaveUnconfirmedError] (the write may or may not
/// have been made: [lesficheWriteNotConfirmed]) and a login or connection
/// failure are thrown as they are.
Future<T> withLesficheWrite<T>(
  SmartschoolSession session,
  Future<T> Function(SmartschoolClient client) write, {
  required String Function() what,
  required String nothingDone,
  Iterable<LocalFile> files = const [],
}) async {
  try {
    return await session.run(write);
  } on SmartschoolLessonContentWriteRefusedError catch (error) {
    // The library's message names the lesfiche: the log never shows a name.
    log(
      'lesfiches write: refused (HTTP ${error.statusCode}, '
      '${error.violations.length} reasons)',
    );
    final violations = error.violations;
    throw ToolError(
      'The Lesfiches module refused ${what()} (HTTP ${error.statusCode})'
      '${violations.isEmpty ? ', without saying why' : ': ${violations.map((v) => '"$v"').join(' ')}'}. '
      '$nothingDone',
    );
  } on SmartschoolAttachmentUploadError catch (error) {
    throw uploadToolError(error, files: files, nothingDone: nothingDone)!;
  } on ArgumentError catch (error) {
    if (error is RangeError) rethrow;
    if (uploadToolError(error, files: files, nothingDone: nothingDone)
        case final toolError?) {
      throw toolError;
    }
    log('lesfiches write: refused before sending (${error.name})');
    final message = '${error.message}'.replaceFirst(
      RegExp(r'[.\s]*Nothing was sent\.?$'),
      '',
    );
    throw ToolError(
      '${_capitalised(what())} was refused before it was sent: '
      '${error.name == null ? '' : '${error.name} '}$message. $nothingSent',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError {
    rethrow;
  } catch (error) {
    final toolError = plannerToolError(error);
    if (toolError == null) rethrow;
    throw ToolError('${toolError.message} $nothingDone');
  }
}

/// The result of a Lesfiches write that went out without the module
/// confirming it ([error]): [what] (like `The lesson lesfiche "Lussen"`)
/// may or may not have been [done]. Claude must not call [tool] again for
/// it ([why] says what a second call could do), but first [check] (like
/// `list the lesfiches with list_lesfiches`) and tell the user.
CallToolResult lesficheWriteNotConfirmed({
  required String tool,
  required String what,
  required String check,
  required String why,
  required SmartschoolLessonContentSaveUnconfirmedError error,
  String done = 'made',
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
        text:
            '$what may or may not have been $done: it was sent, but the '
            'Lesfiches module did not confirm it. Do not call $tool again '
            'for it: $why. First $check. Then tell the user what you found.',
      ),
    ],
  );
}

String _capitalised(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
