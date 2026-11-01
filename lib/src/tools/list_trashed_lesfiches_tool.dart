import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiches.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'list_lesfiches_tool.dart';
import 'server_tool.dart';

/// How long the Lesfiches module keeps a lesfiche in its trash, as its web
/// client's trash dialog says ("binnen 100 dagen", dartschool#227).
const lesficheTrashDays = 100;

/// `list_trashed_lesfiches`: the lesfiches in the trash of the user's
/// Lesfiches module (the library's `LessonContentService.getTrash`,
/// dartschool#227), with the day each went there, most recent first: what
/// `restore_lesfiches` takes back out.
///
/// The courses are named as `list_lesfiches` names them; when only the
/// course list that names them fails, the lesfiches are listed with the
/// number of their courses.
ServerTool listTrashedLesfichesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_trashed_lesfiches',
    title: 'List the Smartschool lesfiches in the trash',
    description:
        'Lists the lesfiches in the trash of the user\'s Smartschool '
        'Lesfiches module, lessons and assignments alike: those moved there '
        'with trash_lesfiches or in Smartschool itself. One line per '
        'lesfiche, most recently moved first: its kind, name, labels, '
        'courses, whether it is visible or hidden, the day it went to the '
        'trash, and its id for restore_lesfiches, which takes it back into '
        'the user\'s library. The Lesfiches module says a lesfiche in its '
        'trash can be restored within $lesficheTrashDays days. A lesfiche in the trash cannot '
        'be changed, copied or planned until it is restored. Filter with '
        'query (words in the name). Listing changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the name of the lesfiche, '
              'case-insensitive, in any order. Default: any name.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the Smartschool lesfiches in the trash',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final query = (arguments['query'] as String? ?? '').trim();
  final words = [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  final (all, courseError) = await withPlannerClient(session, (client) async {
    try {
      return (await LessonContentService(client).getTrash(), null);
    } on SmartschoolLessonContentCourseListError catch (error) {
      // Only the course list that names the courses failed: its error
      // carries the lesfiches as read, without the names.
      log('lesfiches trash: $error');
      return (error.items, error);
    }
  });
  final shown =
      all
          .where(
            (item) => lesficheMatches(item, labels: const {}, words: words),
          )
          .toList()
        ..sort((a, b) {
          final at = a.dateStateChanged, bt = b.dateStateChanged;
          if (at != null && bt != null && at != bt) return bt.compareTo(at);
          if (at != bt) return at == null ? 1 : -1;
          final byName = compareLesficheNames(a.name, b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });

  final String text;
  if (all.isEmpty) {
    text = 'The trash of the Lesfiches module is empty.';
  } else if (shown.isEmpty) {
    text =
        'No lesfiches whose name holds "$query" (of the '
        '${LesficheKind.all.count(all.length)} in the trash of the Lesfiches '
        'module).';
  } else {
    final listed = shown.take(maxLesficheLines).toList();
    final withCourseNames = courseError == null;
    final unnamed =
        withCourseNames &&
        listed.any((item) => item.courses.any((course) => course.name == null));
    text = [
      '${LesficheKind.all.count(shown.length)}'
          '${query.isEmpty ? '' : ' whose name holds "$query"'}'
          '${query.isEmpty ? '' : ', of the ${all.length}'} in the trash of '
          'the Lesfiches module, most recently moved first:',
      for (final item in listed)
        formatLesficheLine(
          item,
          withCourseNames: withCourseNames,
          inTrash: true,
        ),
      if (shown.length > listed.length)
        'Note: only the first ${listed.length} of the ${shown.length} are '
            'shown: narrow the list with query.',
      if (courseError != null && listed.any((item) => item.courses.isNotEmpty))
        lesficheCourseListNote(courseError),
      if (unnamed) unnamedLesficheCourseNote,
      'The Lesfiches module says a lesfiche in its trash can be restored '
          'within $lesficheTrashDays days. restore_lesfiches takes one back '
          'into the library, by its id.',
    ].join('\n');
  }
  return CallToolResult(content: [TextContent(text: text)]);
}
