import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_shares.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `unshare_skore_gradebook`: stops sharing a teacher's gradebook in Skore
/// with one or more teachers, with the library's
/// [SkoreService.unshareGradebook] (dartschool#74), one teacher after the
/// other ([changeSkoreShares]).
///
/// It changes who has access to pupils' scores, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call).
/// It is idempotent: unsharing again saves nothing.
ServerTool unshareSkoreGradebookTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'unshare_skore_gradebook',
    title: 'Stop sharing a gradebook with teachers in Skore',
    description:
        'Stops sharing a gradebook of a teacher in Skore, the Smartschool '
        'module for scores and reports, with one or more teachers, as '
        'Skore\'s "share gradebooks" manager does (Puntenboeken): they lose '
        'their read or write access to it. The other teachers it is shared '
        'with keep theirs. The gradebook id is the assignment id in '
        'list_skore_courses, and the owner is the teacher of that '
        'assignment. Before calling this tool, read the gradebook with '
        'list_skore_gradebook_shares; show the user the gradebook (its course '
        'and class) and the teachers who lose their access, and only call '
        'this tool after the user has explicitly confirmed it. Pass all '
        'teachers of one confirmation in one call. The server unshares it '
        'with one teacher after the other and stops at the first that fails: '
        'the result says per teacher whether it was unshared, was not shared '
        'with them (nothing saved), or was not unshared or not tried, and '
        'gives the readers and writers of the gradebook afterwards. Before '
        'each change the server reads the gradebook again, and refuses one '
        'that does not fit, saving nothing for that teacher: the owner among '
        'the teachers, a gradebook that is not the owner\'s. The result says '
        'why. A teacher Skore no longer lists (such as one who left the '
        'school) can still be taken off. If the result says a change may or '
        'may not have been saved, do not call this tool again for it: read '
        'the gradebook with list_skore_gradebook_shares and tell the user. To '
        'share a gradebook, use share_skore_gradebook. Only for an account '
        'with the rights for score management in Skore; without them, the '
        'tool says so.',
    inputSchema: Schema.object(
      properties: {
        'owner_id': skoreOwnerIdSchema(),
        'gradebook_id': skoreGradebookIdSchema(),
        'teacher_ids': skoreShareTeachersSchema(
          description:
              'The teacher ids of the teachers who lose their access, from '
              'list_skore_gradebook_shares: all those the user confirmed, at '
              'most $maxSkoreShareTeachers. Not the owner.',
        ),
      },
      required: ['owner_id', 'gradebook_id', 'teacher_ids'],
    ),
    annotations: ToolAnnotations(
      title: 'Stop sharing a gradebook with teachers in Skore',
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
      tool: 'unshare_skore_gradebook',
      ownerId: requiredIntArgument(arguments, 'owner_id'),
      gradebookId: requiredIntArgument(arguments, 'gradebook_id'),
      teacherIds: {...intListArgument(arguments, 'teacher_ids')}.toList(),
      access: null,
    );
  },
);
