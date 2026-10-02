import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_shares.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `share_skore_gradebook`: shares a teacher's gradebook in Skore with one
/// or more other teachers, with read or write access, with the library's
/// [SkoreService.shareGradebook] (dartschool#74), one teacher after the
/// other ([changeSkoreShares]).
///
/// Sharing gives colleagues access to pupils' scores, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call).
/// It is idempotent: sharing again the same way saves nothing.
ServerTool shareSkoreGradebookTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'share_skore_gradebook',
    title: 'Share a gradebook with other teachers in Skore',
    description:
        'Shares a gradebook of a teacher in Skore, the Smartschool module '
        'for scores and reports, with one or more other teachers, as '
        'Skore\'s "share gradebooks" manager does (Puntenboeken): with read '
        'access (they may read it) or write access (they may read and change '
        'it). That gives those teachers access to the scores of the pupils '
        'in it. The gradebook id is the assignment id in list_skore_courses, '
        'and the owner is the teacher of that assignment. A typical flow: '
        'find the class with list_skore_classes, read its courses with '
        'list_skore_courses, take the assignment of the titularis on the '
        'course (its assignment id is the gradebook id, its teacher the '
        'owner), and share it with the other teachers of the class, whom '
        'list_skore_courses lists on the class\'s other courses. Before '
        'calling this tool, read the gradebook with '
        'list_skore_gradebook_shares; show the user the gradebook (its course '
        'and class), the teachers to share it with and the access, and only '
        'call this tool after the user has explicitly confirmed it. Pass all '
        'teachers of one confirmation in one call. The teachers it is already '
        'shared with keep their access; a teacher with the other access gets '
        'the access given instead. The server shares it with one teacher '
        'after the other and stops at the first that fails: the result says '
        'per teacher whether it was shared, already had that access (nothing '
        'saved), or was not shared or not tried, and gives the readers and '
        'writers of the gradebook afterwards. Before each change the server '
        'reads the gradebook and the teachers again, and refuses one that '
        'does not fit, saving nothing for that teacher: the owner among the '
        'teachers to share with, a gradebook that is not the owner\'s, a '
        'teacher Skore does not list. The result says why. If the result says '
        'a change may or may not have been saved, do not call this tool again '
        'for it: read the gradebook with list_skore_gradebook_shares and tell '
        'the user. To stop sharing a gradebook with someone, use '
        'unshare_skore_gradebook. Only for an account with the rights for '
        'score management in Skore; without them, the tool says so.',
    inputSchema: Schema.object(
      properties: {
        'owner_id': skoreOwnerIdSchema(),
        'gradebook_id': skoreGradebookIdSchema(),
        'teacher_ids': skoreShareTeachersSchema(
          description:
              'The teacher ids of the teachers to share it with, from '
              'list_skore_courses or list_skore_teachers: all those the user '
              'confirmed, at most $maxSkoreShareTeachers. Not the owner.',
        ),
        'access': UntitledSingleSelectEnumSchema(
          description:
              'read: they may read the gradebook; write: they may read and '
              'change it.',
          values: [for (final access in SkoreShareAccess.values) access.name],
        ),
      },
      required: ['owner_id', 'gradebook_id', 'teacher_ids', 'access'],
    ),
    annotations: ToolAnnotations(
      title: 'Share a gradebook with other teachers in Skore',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) {
    final arguments = request.arguments ?? const {};
    return changeSkoreShares(
      session,
      tool: 'share_skore_gradebook',
      ownerId: requiredIntArgument(arguments, 'owner_id'),
      gradebookId: requiredIntArgument(arguments, 'gradebook_id'),
      teacherIds: {...intListArgument(arguments, 'teacher_ids')}.toList(),
      // The input schema guarantees one of the names.
      access: SkoreShareAccess.values.byName(arguments['access'] as String),
    );
  },
);
