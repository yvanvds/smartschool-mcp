import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_access.dart';
import '../skore/skore_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_gradebook_shares`: the gradebooks of one teacher in Skore,
/// each with the teachers it is shared with, by name
/// ([SkoreService.getGradebookShares], dartschool#74, joined with
/// [SkoreService.getTeachers]).
ServerTool listSkoreGradebookSharesTool(SmartschoolSession session) =>
    ServerTool(
      definition: Tool(
        name: 'list_skore_gradebook_shares',
        title: 'List the gradebooks of a teacher in Skore, with their shares',
        description:
            'Lists the gradebooks of one teacher in Skore, the Smartschool '
            'module for scores and reports, each with the teachers it is '
            'shared with, as Skore\'s "share gradebooks" manager shows them '
            '(Puntenboeken). One line per gradebook, in Skore\'s order: its '
            'course, its class, its gradebook id, its readers (teachers who '
            'may read it) and its writers (teachers who may read and change '
            'it), each by name and teacher id; a teacher Skore no longer '
            'lists (such as one who left the school) shows by teacher id '
            'only. A gradebook belongs to an assignment (Skore\'s '
            '"lesopdracht"): its gradebook id is the assignment id in '
            'list_skore_courses, and its owner is the teacher of that '
            'assignment. Take teacher_id from list_skore_courses (the '
            'teacher of an assignment) or list_skore_teachers. An empty list '
            'means that no gradebook belongs to that teacher id, or that no '
            'teacher has that id. To change whom a gradebook is shared with, '
            'use share_skore_gradebook or unshare_skore_gradebook. Only for '
            'an account with the rights for score management in Skore; '
            'without them, the tool says so. Reading changes nothing in '
            'Skore.',
        inputSchema: Schema.object(
          properties: {
            'teacher_id': Schema.int(
              description:
                  'The teacher id of the owner of the gradebooks: the '
                  'teacher of an assignment in list_skore_courses, or from '
                  'list_skore_teachers.',
              minimum: 1,
            ),
          },
          required: ['teacher_id'],
        ),
        annotations: ToolAnnotations(
          title: 'List the gradebooks of a teacher in Skore, with their shares',
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
  final teacherId = requiredIntArgument(arguments, 'teacher_id');
  final (gradebooks, teachers) = await withSkore(
    session,
    (skore) async =>
        (await skore.getGradebookShares(teacherId), await skore.getTeachers()),
  );
  return CallToolResult(
    content: [
      TextContent(
        text: formatSkoreGradebookShares(
          teacherId,
          gradebooks,
          skoreTeacherNames(teachers),
        ),
      ),
    ],
  );
}

/// What `list_skore_gradebook_shares` answers: the [gradebooks] of teacher
/// [teacherId] in Skore's order, after a line that counts them, the
/// teachers named from [names].
String formatSkoreGradebookShares(
  int teacherId,
  List<SkoreGradebookShares> gradebooks,
  Map<int, String> names,
) {
  final owner = formatSkoreTeacherId(teacherId, names);
  if (gradebooks.isEmpty) {
    return 'Skore lists no gradebooks for $owner: no gradebook belongs to '
        'that teacher id, or no teacher has that id. Take the teacher id of '
        'an assignment from list_skore_courses.';
  }
  final count = gradebooks.length;
  return [
    'Skore lists $count ${count == 1 ? 'gradebook' : 'gradebooks'} of '
        '$owner, in Skore\'s order, each with the teachers it is shared with: '
        'readers may read it, writers may read and change it. A gradebook id '
        'is the id of its assignment in list_skore_courses.',
    for (final gradebook in gradebooks)
      '- ${formatSkoreGradebook(gradebook, names)}',
  ].join('\n');
}
