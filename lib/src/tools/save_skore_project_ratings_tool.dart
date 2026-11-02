import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import '../skore/skore_projects.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// The name of the tool, as its messages name it.
const _tool = 'save_skore_project_ratings';

/// `save_skore_project_ratings`: saves or clears pupils' ratings of
/// learning goals in one project of one of the user's project gradebooks in
/// Skore, with the text Skore keeps with a rating (info), with the library's
/// [SkoreGradebookService.saveProjectRatings] (#192,
/// yvanvds/dartschool#204): the whole list in one call, so one approval for
/// a list the user saw.
///
/// In the style of `save_skore_grades`: a gradebook shared with the user to
/// read only is refused before it is read
/// ([checkSkoreGradebookChangeable]); pupils, learning goals and levels are
/// checked in the tool's own words before the library is asked (levels by
/// name or symbol, [skoreProjectLevel]); a published or scheduled project is
/// refused unless `allow_published` is true
/// ([checkSkoreProjectPublication]), also when the library refuses it with a
/// [SmartschoolSkoreProjectPublishedError]. The library reads Skore again,
/// refuses the whole list when one change does not fit, saving nothing,
/// and reads the ratings again to confirm them. Ratings it cannot confirm
/// are reported per change, with those it did confirm: saving a rating
/// again is harmless.
///
/// Offered to every account, without a switch. Marked destructive, so
/// Claude Desktop asks for approval before every call; saving the same
/// ratings again gives the same state, so it is idempotent.
ServerTool saveSkoreProjectRatingsTool(SmartschoolSession session) =>
    ServerTool(
      definition: Tool(
        name: _tool,
        title: 'Save ratings in a project in Skore',
        description:
            'Saves pupils\' ratings of learning goals in one project of one '
            'of the user\'s project gradebooks in Skore, the Smartschool '
            'module for scores and reports (Skore\'s "Projecten"; their own, '
            'or one a colleague shared with them to read and write), or '
            'clears them, as rating them in Skore\'s project sheet does: the '
            'whole list in one call. A rating is a level of the scale of the '
            'project\'s template, given by its name or symbol (such as '
            'Behaald or B); null or an empty level clears the rating. Each '
            'rating can also set the text Skore keeps with it (info): an '
            'empty text clears it, and leaving info out keeps it. Before '
            'calling this tool, read the project with read_skore_project and '
            'match each name and goal the user gave to a pupil id and a goal '
            'id there; never guess a pupil or a goal that matches none or '
            'more than one: ask the user. Show the user the full list, each '
            'pupil with class number and name, the goal, the current level '
            'and the new one, and only call this tool after the user has '
            'explicitly confirmed it. In a gradebook a colleague shared with '
            'the user, also tell the user whose gradebook it is. A gradebook '
            'shared with the user to read only is refused. Only a gradebook '
            'of Skore\'s current school year, in an open project period, can '
            'be changed. A project that is published or scheduled is refused '
            'unless allow_published is true: a rating there is visible to '
            'its pupils at once, or from its publication time on. Pass '
            'allow_published: true only after telling the user exactly that '
            'and getting their explicit yes for it. The server reads Skore '
            'again before it saves, and when one rating does not fit (a '
            'pupil not in the gradebook, a goal that takes no ratings, a '
            'level not on the scale, a rating to clear that is not there, a '
            'closed or read-only period), it saves none: the result says '
            'why. Projects are not made or published here. The result gives '
            'each rating as Skore lists it after the save. If the result '
            'says some ratings may or may not have been saved: saving a '
            'rating again is harmless, so read the project again with '
            'read_skore_project, tell the user what you found, and save only '
            'the ratings that differ.',
        inputSchema: Schema.object(
          properties: {
            'gradebook_id': Schema.int(
              description:
                  'The gradebook id, from list_skore_gradebooks: a gradebook '
                  'of Skore\'s current school year.',
              minimum: 1,
            ),
            'project_id': Schema.int(
              description:
                  'The project, by its project id from list_skore_projects.',
              minimum: 1,
            ),
            'period_id': Schema.int(
              description:
                  'The project period of the project, by its period id from '
                  'list_skore_projects, to find it with fewer reads. Default: '
                  'it is looked for in every project period.',
              minimum: 1,
            ),
            'ratings': Schema.list(
              description:
                  'The ratings to save, as the user confirmed them: each '
                  'pupil and goal once.',
              items: Schema.object(
                properties: {
                  'pupil_id': Schema.int(
                    description:
                        'The pupil, by the pupil id read_skore_project gives.',
                    minimum: 1,
                  ),
                  'goal_id': Schema.string(
                    description:
                        'The learning goal, by the goal id read_skore_project '
                        'gives (such as "9002").',
                  ),
                  'level': Schema.combined(
                    description:
                        'The new level, by its name or symbol on the scale '
                        'of the project\'s template, as read_skore_project '
                        'lists it (such as "Behaald" or "B"). Null or an '
                        'empty text clears the rating.',
                    anyOf: [Schema.string(), Schema.nil()],
                  ),
                  'info': Schema.string(
                    description:
                        'The text Skore keeps with the rating. An empty text '
                        'clears it. Default: the text it has is kept.',
                  ),
                },
                required: ['pupil_id', 'goal_id', 'level'],
              ),
              minItems: 1,
            ),
            'allow_published': Schema.bool(
              description:
                  'true to save in a project that is published or '
                  'scheduled: its pupils see the ratings at once (in a '
                  'scheduled one, from its publication time on). Only after '
                  'telling the user so and getting their explicit yes. '
                  'Default false.',
            ),
          },
          required: ['gradebook_id', 'project_id', 'ratings'],
        ),
        annotations: ToolAnnotations(
          title: 'Save ratings in a project in Skore',
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: true,
          openWorldHint: true,
        ),
      ),
      handler: (request) => _save(session, request.arguments ?? const {}),
    );

/// One rating of the call: the pupil, the goal, the level by name (null or
/// empty to clear it) and the info (null to keep it).
typedef _Rating = ({int pupilId, String goalId, String? level, String? info});

/// What the ratings go into: the gradebook as read (with its pupils), the
/// project as found, its learning goals by id, and the pupils of the call
/// by pupil id.
typedef _Target = ({
  SkoreGradebookSheet sheet,
  FoundSkoreProject found,
  Map<String, SkoreLearningGoal> goals,
  Map<int, SkoreGradebookPupil> pupils,
});

Future<CallToolResult> _save(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final projectId = requiredIntArgument(arguments, 'project_id');
  final periodId = intArgument(arguments, 'period_id');
  final ratings = _ratingsArgument(arguments);
  final allowPublished = arguments['allow_published'] == true;

  final years = SkoreGradebookYears.of(session);
  // What the ratings go into and the changes sent, for ratings Skore did
  // not confirm: set before the save is sent.
  ({_Target to, List<SkoreProjectRatingChange> changes})? sending;
  try {
    final (to, changes, saved) = await withSkoreGradebookWrite(
      session,
      reread: _reread(gradebookId, projectId),
      (gradebooks) async {
        final listed = await years.findInCurrentYear(gradebooks, gradebookId);
        // The library refuses it as well, before anything is sent.
        checkSkoreGradebookChangeable(listed.gradebook);
        final sheet = await gradebooks.getGradebook(listed.gradebook);
        final pupils = _pupils(sheet, ratings);
        final found = await findSkoreProject(
          gradebooks,
          sheet.gradebook,
          projectId,
          periodId: periodId,
        );
        final goals = {
          for (final goal in await gradebooks.getLearningGoals(
            sheet.gradebook,
            found.period.id,
            found.template,
          ))
            goal.id: goal,
        };
        final to = (sheet: sheet, found: found, goals: goals, pupils: pupils);
        _checkGoals(to, ratings);
        final changes = [
          for (final rating in ratings) _change(found.template, rating),
        ];
        checkSkoreProjectPublication(
          found.project,
          where: _where(to),
          tool: _tool,
          allowPublished: allowPublished,
        );
        sending = (to: to, changes: changes);
        try {
          final saved = await gradebooks.saveProjectRatings(
            sheet.gradebook,
            found.project,
            changes,
            allowPublished: allowPublished,
          );
          return (to, changes, saved);
        } on SmartschoolSkoreProjectPublishedError catch (error) {
          // Published between the two reads: said as the check above says
          // it, from the project as Skore listed it right before the save.
          log('$_tool: $error');
          checkSkoreProjectPublication(
            error.project,
            where: _where(to),
            tool: _tool,
            allowPublished: false,
          );
          rethrow;
        }
      },
    );
    return CallToolResult(
      content: [TextContent(text: _savedText(to, changes, saved))],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // Caught as the base type, so that a save Skore did not confirm is never
    // reported as an unexpected error; only saveProjectRatings throws it,
    // after sending is set.
    final sent = sending;
    if (sent == null) rethrow;
    return _notConfirmed(sent.to, sent.changes, error);
  }
}

/// The `ratings` argument, in the order given.
///
/// Throws a [ToolError] for a pupil and goal given twice, a blank goal id,
/// and an empty list (which the input schema refuses first), before
/// anything is sent.
List<_Rating> _ratingsArgument(Map<String, Object?> arguments) {
  final items = arguments['ratings'];
  if (items is! List || items.isEmpty) {
    throw const ToolError(
      'ratings must list at least one rating, each with a pupil_id, a '
      'goal_id and a level. Nothing was changed in Skore.',
    );
  }
  final ratings = <_Rating>[];
  final seen = <(int, String)>{};
  final twice = <String>[];
  for (final item in items) {
    final fields = (item as Map).cast<String, Object?>();
    final pupilId = requiredIntArgument(fields, 'pupil_id');
    final goalId = switch (fields['goal_id']) {
      final num id when id == id.roundToDouble() => '${id.toInt()}',
      final Object id => '$id'.trim(),
      null => '',
    };
    if (goalId.isEmpty) {
      throw ToolError(
        'The rating of pupil id $pupilId has no goal_id: give the goal id '
        'read_skore_project lists. Nothing was changed in Skore.',
      );
    }
    if (!seen.add((pupilId, goalId))) {
      twice.add('pupil id $pupilId with goal id $goalId');
    }
    ratings.add((
      pupilId: pupilId,
      goalId: goalId,
      level: (fields['level'] as String?)?.trim(),
      info: fields['info'] as String?,
    ));
  }
  if (twice.isNotEmpty) {
    throw ToolError(
      'ratings lists ${twice.join(', ')} more than once: give each pupil and '
      'goal once, with the level the user confirmed. Nothing was changed in '
      'Skore.',
    );
  }
  return ratings;
}

/// The pupils of [sheet] that [ratings] name, by pupil id.
///
/// Throws a [ToolError] that names every pupil id the gradebook has no
/// pupil with; nothing is sent.
Map<int, SkoreGradebookPupil> _pupils(
  SkoreGradebookSheet sheet,
  List<_Rating> ratings,
) {
  final byId = {for (final pupil in sheet.pupils) pupil.id: pupil};
  final unknown = {
    for (final rating in ratings)
      if (!byId.containsKey(rating.pupilId)) rating.pupilId,
  };
  if (unknown.isNotEmpty) {
    final which = unknown.length == 1
        ? 'pupil with pupil id'
        : 'pupils with pupil ids';
    throw ToolError(
      'The ${formatSkoreGradebookName(sheet.gradebook)} has no $which '
      '${unknown.join(', ')}${sheet.pupils.isEmpty ? ': it has no pupils' : ''}. '
      'Take the pupil ids from read_skore_project for this gradebook.',
    );
  }
  return {for (final rating in ratings) rating.pupilId: byId[rating.pupilId]!};
}

/// Refuses [ratings] of a goal that is not one of the template's of [to],
/// or that takes no rating (the course, a heading, a goal not enabled):
/// each such goal in one [ToolError]; nothing is sent.
void _checkGoals(_Target to, List<_Rating> ratings) {
  final wrong = <String>{};
  for (final rating in ratings) {
    final goal = to.goals[rating.goalId];
    if (goal == null) {
      wrong.add('goal id ${rating.goalId} is not one of its learning goals');
    } else if (!isSkoreRatableGoal(goal)) {
      final what = goal.isCourse
          ? 'the course itself'
          : goal.isTitle
          ? 'a heading'
          : 'not enabled in the template';
      wrong.add('${formatSkoreLearningGoalName(goal)} is $what');
    }
  }
  if (wrong.isEmpty) return;
  throw ToolError(
    'In the ${formatSkoreProjectName(to.found.project)}, '
    '${wrong.join('; ')}, so it takes no rating. Take the goal ids of the '
    'goals that take a rating from read_skore_project for this project.',
  );
}

/// The change of [rating]: its level of [template]'s scale by name
/// ([skoreProjectLevel], which throws a [ToolError] for one not on the
/// scale), or a clear for none.
SkoreProjectRatingChange _change(
  SkoreProjectTemplate template,
  _Rating rating,
) {
  final level = rating.level;
  if (level == null || level.isEmpty) {
    return SkoreProjectRatingChange.clear(
      pupilId: rating.pupilId,
      learningGoalId: rating.goalId,
      info: rating.info,
    );
  }
  return SkoreProjectRatingChange(
    pupilId: rating.pupilId,
    learningGoalId: rating.goalId,
    ratingId: skoreProjectLevel(template, level).id,
    info: rating.info,
  );
}

/// What to read again after a change Skore refused, to correct the call.
String _reread(int gradebookId, int projectId) =>
    'Read the project again with read_skore_project (gradebook_id '
    '$gradebookId, project_id $projectId: its publication, the goal ids, '
    'the levels and the pupils\' ratings) and list_skore_projects (whether '
    'the project period is open)';

/// The project period and gradebook of [to]: `project period PR1 (period
/// id 1710) of the gradebook of 5WW1 for ... (gradebook id 34990)`.
String _where(_Target to) =>
    'project period ${formatSkorePeriodName(to.found.period)} of the '
    '${formatSkoreGradebookName(to.sheet.gradebook)}';

/// The project of [to] and where it is, for the first line of a result.
String _projectIn(_Target to) =>
    '${formatSkoreProjectName(to.found.project)} in ${_where(to)}';

/// The pupil and goal of [change]: `1. Jacobs, Gert | pupil id 1221 | LPD
/// 16.1.1 Zoekt informatie op (goal id 9002)`.
String _pupilGoal(_Target to, SkoreProjectRatingChange change) {
  final goal = to.goals[change.learningGoalId];
  return '${formatSkoreGradebookPupil(to.pupils[change.pupilId]!)} | '
      '${goal == null ? 'goal id ${change.learningGoalId}' : formatSkoreLearningGoalName(goal)}';
}

/// One rating as Skore lists it: the pupil, the goal, the level by name and
/// the info, if any; `cleared` for one with neither (#206).
String _ratingLine(
  _Target to,
  SkoreProjectRatingChange change,
  SkoreProjectRating rating,
) {
  final info = rating.info?.trim() ?? '';
  if (rating.ratingId == null && info.isEmpty) {
    return '- ${_pupilGoal(to, change)}: cleared';
  }
  return [
    '- ${_pupilGoal(to, change)}: '
        '${formatSkoreProjectRatingLevel(to.found.template, rating.ratingId)}',
    if (info.isNotEmpty) 'info: ${skoreName(info)}',
  ].join(' | ');
}

/// The ratings: `1 rating`, `3 ratings`.
String _ratings(int count) => count == 1 ? '1 rating' : '$count ratings';

/// What the tool answers when every rating was saved: each (in the order of
/// [changes]) as Skore lists it after the save ([saved], in the same
/// order), under the project with its publication.
String _savedText(
  _Target to,
  List<SkoreProjectRatingChange> changes,
  List<SkoreProjectRating> saved,
) => [
  'Saved ${_ratings(changes.length)} in the ${_projectIn(to)}.',
  'Project: ${formatSkoreProject(to.found.project)}',
  'Ratings as Skore lists them after the save, in the order given:',
  for (final (i, change) in changes.indexed) _ratingLine(to, change, saved[i]),
].join('\n');

/// The result for [changes] that went out to Skore without Skore confirming
/// all of them ([error]): the ratings it confirmed, as read again, and the
/// others, as sent, which may or may not have been saved. Saving a rating
/// again is harmless. The library's message, which says per change why, goes
/// to the log only.
CallToolResult _notConfirmed(
  _Target to,
  List<SkoreProjectRatingChange> changes,
  SmartschoolSkoreSaveUnconfirmedError error,
) {
  log(
    '$_tool: Skore did not confirm every rating: '
    '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
  );
  final confirmed = switch (error) {
    SmartschoolSkoreProjectRatingSaveUnconfirmedError(:final confirmed) =>
      confirmed,
    _ => const <SkoreProjectRatingChange, SkoreProjectRating>{},
  };
  final count = changes.length;
  final unconfirmed = [
    for (final change in changes)
      if (!confirmed.containsKey(change)) change,
  ];
  final which = confirmed.isNotEmpty
      ? '${unconfirmed.length} of them'
      : count == 1
      ? 'it'
      : 'any of them';
  final template = to.found.template;
  String sent(SkoreProjectRatingChange change) {
    final info = change.info;
    return [
      change.clears
          ? 'no level, to clear the rating'
          : formatSkoreProjectRatingLevel(template, change.ratingId),
      if (info != null)
        info.trim().isEmpty ? 'info cleared' : 'info: ${skoreName(info)}',
    ].join(' | ');
  }

  final period = to.found.period.id;
  return CallToolResult(
    isError: true,
    content: [
      TextContent(
        text: [
          '${_capitalized(_ratings(count))} in the ${_projectIn(to)} '
              '${count == 1 ? 'was' : 'were'} sent, but Skore did not confirm '
              '$which.',
          if (confirmed.isNotEmpty) ...[
            'Saved, as Skore lists them after the save:',
            for (final change in changes)
              if (confirmed[change] case final rating?)
                _ratingLine(to, change, rating),
          ],
          'May or may not have been saved:',
          for (final change in unconfirmed)
            '- ${_pupilGoal(to, change)} | sent: ${sent(change)}',
          'Saving a rating again is harmless: read the project again with '
              'read_skore_project (gradebook_id '
              '${to.sheet.gradebook.gradebookId}, project_id '
              '${to.found.project.id}, period_id $period), tell the user what '
              'you found, and save only the ratings that differ from the ones '
              'the user confirmed again with $_tool.',
        ].join('\n'),
      ),
    ],
  );
}

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
