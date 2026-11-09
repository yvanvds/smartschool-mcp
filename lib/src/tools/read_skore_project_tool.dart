import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import '../skore/skore_projects.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_skore_project`: one project of one of the user's project
/// gradebooks in Skore (#192, yvanvds/dartschool#204): its template's
/// scale, its learning goals as a tree ([SkoreGradebookService.
/// getLearningGoals]) and each pupil's ratings, the levels by name
/// ([SkoreGradebookService.getProjectRatings]).
///
/// Offered to every account, without a switch, like the other gradebook
/// tools.
ServerTool readSkoreProjectTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_skore_project',
    title: 'Read the ratings of a project in Skore',
    description:
        'Reads one project of one of the user\'s project gradebooks in '
        'Skore, the Smartschool module for scores and reports (Skore\'s '
        '"Projecten"; their own, or one a colleague shared with them), by '
        'the gradebook id and the project id from list_skore_projects. It '
        'gives the project (its day, and whether its pupils see it: '
        'published or scheduled, in capitals), the rating scale of its '
        'template with its levels by name and symbol, its learning goals '
        '(Skore\'s "rubrieken") as a tree under the course, each with its '
        'number, description and goal id, the headings and the goals that '
        'take no ratings marked; and per pupil (class number, name, pupil '
        'id) the rating of each goal that has one: the level by name, and '
        'the text Skore keeps with it (info), if any. Pass pupil_id for one '
        'pupil only. These are the goal ids, levels and pupil ids '
        'save_skore_project_ratings takes. For a gradebook of an earlier '
        'school year, pass its workyear_id too. Reading changes nothing in '
        'Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'project_id': Schema.int(
          description:
              'The project, by its project id from '
              'list_skore_projects.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'The project period of the project, by its period id from '
              'list_skore_projects, to find it with fewer reads. Default: it '
              'is looked for in every project period.',
          minimum: 1,
        ),
        'pupil_id': Schema.int(
          description:
              'One pupil, by the pupil id from read_skore_gradebook or this '
              'tool. Default: every pupil.',
          minimum: 1,
        ),
        'workyear_id': Schema.int(
          description:
              'The school year of the gradebook, by its workyear id from '
              'list_skore_gradebooks. Default: Skore\'s current school '
              'year.',
          minimum: 1,
        ),
      },
      required: ['gradebook_id', 'project_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read the ratings of a project in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final projectId = requiredIntArgument(arguments, 'project_id');
  final periodId = intArgument(arguments, 'period_id');
  final pupilId = intArgument(arguments, 'pupil_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final text = await withSkoreGradebook(session, (gradebooks) async {
    final (:sheet, :workyear) = await readSkoreGradebook(
      gradebooks,
      years,
      gradebookId,
      workyearId: workyearId,
    );
    final pupils = pupilId == null
        ? sheet.pupils
        : [skoreGradebookPupil(sheet, pupilId)];
    final found = await findSkoreProject(
      gradebooks,
      sheet.gradebook,
      projectId,
      periodId: periodId,
    );
    final goals = await gradebooks.getLearningGoals(
      sheet.gradebook,
      found.period.id,
      found.template,
    );
    final ratings = await gradebooks.getProjectRatings(
      sheet.gradebook,
      found.project,
    );
    return _format(
      sheet,
      workyear,
      found,
      goals,
      ratings,
      pupils,
      onePupil: pupilId != null,
    );
  });
  return CallToolResult(content: [TextContent(text: text)]);
}

/// What `read_skore_project` answers: the project of [found] in the
/// gradebook of [sheet] (of school year [workyear]), the scale, the
/// learning goals [goals] as a tree, and per pupil of [pupils] their
/// [ratings], in the order of the goals. Ratings of pupils the gradebook
/// does not list come last, by pupil id, unless [onePupil]. A rating with
/// no level, grade or info (one that was cleared) is left out.
String _format(
  SkoreGradebookSheet sheet,
  SkoreWorkyear workyear,
  FoundSkoreProject found,
  List<SkoreLearningGoal> goals,
  List<SkoreProjectRating> ratings,
  List<SkoreGradebookPupil> pupils, {
  required bool onePupil,
}) {
  final (:period, :template, :project) = found;
  final goalById = {for (final goal in goals) goal.id: goal};
  final order = {for (final (i, goal) in goals.indexed) goal.id: i};
  final byPupil = <int, List<SkoreProjectRating>>{};
  for (final rating in ratings) {
    // A cleared rating leaves a cell with nothing in it (seen live, #206):
    // left out.
    if (rating.ratingId == null &&
        (rating.grade?.trim() ?? '').isEmpty &&
        (rating.info?.trim() ?? '').isEmpty) {
      continue;
    }
    byPupil.putIfAbsent(rating.pupilId, () => []).add(rating);
  }
  for (final list in byPupil.values) {
    list.sort(
      (a, b) => (order[a.learningGoalId] ?? goals.length).compareTo(
        order[b.learningGoalId] ?? goals.length,
      ),
    );
  }
  String ratingLine(SkoreProjectRating rating) {
    final goal = goalById[rating.learningGoalId];
    final info = rating.info?.trim() ?? '';
    final grade = rating.grade?.trim() ?? '';
    return [
      '  - ${goal == null ? 'goal id ${rating.learningGoalId} (not one of the template\'s goals)' : formatSkoreLearningGoalName(goal)}: '
          '${formatSkoreProjectRatingLevel(template, rating.ratingId)}',
      if (grade.isNotEmpty) 'grade $grade',
      if (info.isNotEmpty) 'info: ${skoreName(info)}',
    ].join(' | ');
  }

  final listed = {for (final pupil in sheet.pupils) pupil.id};
  final others = [
    if (!onePupil)
      for (final id in byPupil.keys)
        if (!listed.contains(id)) id,
  ]..sort();
  final ratable = goals.where(isSkoreRatableGoal).length;
  return [
    '${formatSkoreGradebookTitle(sheet.gradebook, workyear)}.',
    'Project: ${formatSkoreProject(project)}',
    'In project period ${formatSkoreGradebookPeriod(period, active: false)}',
    'Template: ${formatSkoreProjectTemplateName(template)} | '
        '${formatSkoreProjectScale(template)}',
    if (goals.isEmpty)
      'The template has no learning goals.'
    else ...[
      '${goals.length} learning goals (rubrieken), in Skore\'s order, as a '
          'tree; $ratable of them take a rating (not the course, a heading '
          'or a goal that is not enabled):',
      ...formatSkoreLearningGoals(goals),
    ],
    if (pupils.isEmpty)
      'No pupils.'
    else ...[
      onePupil
          ? 'The pupil\'s ratings, in the order of the goals:'
          : 'Ratings of ${pupils.length} '
                '${pupils.length == 1 ? 'pupil' : 'pupils'}, in Skore\'s '
                'order, each with the goals rated, in the order of the goals:',
      for (final pupil in pupils) ...[
        '- ${formatSkoreGradebookPupil(pupil)}',
        if (byPupil[pupil.id] case final list? when list.isNotEmpty)
          for (final rating in list) ratingLine(rating)
        else
          '  no ratings',
      ],
    ],
    if (others.isNotEmpty) ...[
      'Ratings of pupils the gradebook does not list:',
      for (final id in others) ...[
        '- pupil id $id',
        for (final rating in byPupil[id]!) ratingLine(rating),
      ],
    ],
  ].join('\n');
}
