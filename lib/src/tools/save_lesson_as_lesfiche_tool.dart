import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/planner_access.dart';
import '../planner/planner_format.dart';
import '../planner/planner_writes.dart';
import '../session.dart';
import 'server_tool.dart';

/// `save_lesson_as_lesfiche`: saves a lesson of the user's own planner (one
/// typed in by hand, say) as a new lesson lesfiche in the user's Lesfiches
/// library, as the planner's "Opslaan in Lesfiches" does (the library's
/// `PlannerService.saveAsLessonContent`, dartschool#225, #190).
///
/// The lesson stays as it is, and keeps no link to the lesfiche. Pupils see
/// nothing new, but the tool adds a lesfiche, so it is marked destructive
/// (for Claude Desktop to ask for approval), as `create_lesfiche` is; not
/// idempotent: the module keeps two lesfiches of one name, so a second call
/// makes a second lesfiche. The library sends the save once, never again
/// after logging in again, and confirms it by reading the lesfiches before
/// and after; when that does not confirm it, the tool says to look in the
/// lesfiches before trying again ([plannerWriteNotConfirmed]).
ServerTool saveLessonAsLesficheTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'save_lesson_as_lesfiche',
    title: 'Save a Smartschool lesson as a lesfiche',
    description:
        'Saves a lesson of the user\'s own Smartschool planner (one typed in '
        'by hand, say) as a new lesson lesfiche in the user\'s own Lesfiches '
        'library, as the planner\'s "Opslaan in Lesfiches" does: to reuse it '
        'next year, or plan it into other hours with plan_lesfiche. The '
        'lesfiche gets the lesson\'s icon, public and private info and '
        'learning goals, and the lesson\'s name unless name gives another '
        'one. The lesson itself stays as it is, and keeps no link to the '
        'lesfiche: a later change to either does not reach the other. Only '
        'the user\'s own lessons can be saved: list_planner also shows '
        'colleagues\' lessons, and this tool refuses those. Take the '
        'lesson\'s id from list_planner (planner me). Before calling this '
        'tool, show the user the lesson (date and time, class, course and '
        'name) and the name the lesfiche gets, and only call it after the '
        'user has explicitly confirmed it. Every call makes a new lesfiche, '
        'also when one of that name exists: never call it again for a lesson '
        'that was saved. If the result says the lesfiche may or may not have '
        'been made, do not call this tool again: first look for it with '
        'list_lesfiches, and tell the user. The result gives the lesfiche '
        'as made, with its id. For requests like "bewaar mijn les van '
        'vrijdag als lesfiche".',
    inputSchema: Schema.object(
      properties: {
        'lesson': Schema.string(
          description:
              'The id of a lesson of your own planner, as list_planner '
              '(planner me) shows it, like planned-lessons/4069/….',
          minLength: 1,
        ),
        'name': Schema.string(
          description:
              'The name of the new lesfiche, at most '
              '${LessonContentService.maxNameLength} characters. Leave it '
              'out for the lesson\'s name.',
        ),
      },
      required: ['lesson'],
    ),
    annotations: ToolAnnotations(
      title: 'Save a Smartschool lesson as a lesfiche',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _save(session, request.arguments ?? const {}),
);

Future<CallToolResult> _save(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = PlannedElementRef.parse(arguments['lesson'], name: 'lesson');
  if (id.type != PlannedElementType.lesson) {
    throw ToolError(
      'lesson must be a lesson of your own planner, like '
      'planned-lessons/4069/…; $id is ${switch (id.type) {
        PlannedElementType.placeholder => 'an empty lesson hour, which has nothing to save',
        PlannedElementType.assignment => 'an assignment, which this server does not save as a lesfiche',
        _ => 'a ${id.typeName}, not a lesson',
      }}. Nothing was sent.',
    );
  }
  final name = arguments['name'] == null
      ? null
      : lesficheNameArgument(arguments['name']);

  PlannedElementDetail? lesson;
  try {
    final lesfiche = await withPlannerWrite(session, (planner) async {
      final read = lesson = await id.read(planner);
      if (name == null && (read.name ?? '').trim().isEmpty) {
        throw ToolError(
          'The ${formatElementSummary(read)} has no name: give the lesfiche '
          'one with name.',
        );
      }
      return planner.saveAsLessonContent(read, name: name);
    });
    final goals = await nameGoalsAfterWrite(
      session,
      lesfiche.goals,
      location: GoalLocation.lessonContent,
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Saved the ${formatElementSummary(lesson!)} as the lesson '
                'lesfiche "${lesfiche.name}" in your own library ("Mijn '
                'lesfiches") of the Lesfiches module. The lesson stays as it '
                'is, and keeps no link to the lesfiche.',
            'Its id is ${lesfiche.id}: plan it into other hours with '
                'plan_lesfiche, read it with read_lesfiche, and change it '
                'with edit_lesfiche.',
            '',
            formatLesficheDetail(lesfiche, goals: goals),
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolPlannerSaveUnconfirmedError catch (error) {
    final title = name ?? lesson?.name?.trim();
    return plannerWriteNotConfirmed(
      tool: 'save_lesson_as_lesfiche',
      what:
          'A lesfiche of the '
          '${lesson == null ? 'lesson $id' : formatElementSummary(lesson!)}',
      done: 'made',
      check:
          'look for it with list_lesfiches'
          '${title == null || title.isEmpty ? '' : ' (query "$title")'}: a '
          'second call makes a second lesfiche',
      error: error,
    );
  }
}
