import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/message_search.dart';
import '../tools/server_tool.dart';
import 'skore_format.dart';
import 'skore_gradebook_access.dart';
import 'skore_gradebook_format.dart';

// The project gradebooks of Skore ("Projecten", #192, yvanvds/dartschool#204)
// for the project tools (`list_skore_projects`, `read_skore_project`,
// `save_skore_project_ratings`) and for `read_skore_gradebook`, which says
// that a gradebook is one: finding a project of a gradebook by its id, and
// the lines of a project, its scale and its learning goals.
//
// A project gradebook has project periods instead of evaluation periods
// (`getProjectPeriods`, Skore's `init` with the page `1`, which lists the
// evaluation periods too: `scope` 1, against 2 for a project period, by
// which the library gives only the project periods, flutter_smartschool
// 0.4.5, yvanvds/dartschool#236); a project period has templates
// (`getProjectTemplates`), each with its rating scale, its learning goals
// ("rubrieken", `getLearningGoals`) and its projects (`getProjects`). A
// pupil's rating of a learning goal in a project is a level of the
// template's scale (`getProjectRatings`). The library reads and writes them
// as Skore's project sheet (`/Gradebook`) does, and never makes, publishes
// or removes a project: that is done in Smartschool.

/// A project of a gradebook found by its id ([findSkoreProject]): its
/// project period, its template (with the scale) and the project as Skore
/// lists it.
typedef FoundSkoreProject = ({
  SkoreGradebookPeriod period,
  SkoreProjectTemplate template,
  SkoreProject project,
});

/// The project periods of [gradebook] ([SkoreGradebookService.
/// getProjectPeriods]), or only the one with [periodId].
///
/// Skore's answer lists the evaluation periods too; the library keeps only
/// the periods Skore marks as project periods (`scope` 2,
/// [SkoreGradebookPeriod.isProject], yvanvds/dartschool#236), so a normal
/// gradebook has none.
///
/// Throws a [ToolError] for a gradebook without project periods (it is not a
/// project gradebook: its evaluations are read with list_skore_evaluations),
/// and for a [periodId] that is not one of them, which lists them.
Future<List<SkoreGradebookPeriod>> readSkoreProjectPeriods(
  SkoreGradebooks gradebooks,
  SkoreGradebook gradebook, {
  int? periodId,
}) async {
  final periods = await gradebooks.getProjectPeriods(gradebook);
  final name = formatSkoreGradebookName(gradebook);
  if (periods.isEmpty) {
    throw ToolError(
      'The $name has no project periods (Skore\'s "Projecten"): it is not a '
      'project gradebook, so it has no projects. Its evaluations are read '
      'with list_skore_evaluations.',
    );
  }
  if (periodId == null) return periods;
  for (final period in periods) {
    if (period.id == periodId) return [period];
  }
  throw ToolError(
    'The $name has no project period with period id $periodId. Its project '
    'periods, in Skore\'s order: '
    '${[for (final p in periods) '${skoreName(p.name)} (period id ${p.id}, ${p.isOpen ? 'open' : 'closed'})'].join(', ')}. '
    'Take a period id from these, as list_skore_projects lists them, or '
    'leave out period_id to look in every project period.',
  );
}

/// Finds project [projectId] of [gradebook] (by its [SkoreProject.id]): in
/// project period [periodId], or without it in every project period, in
/// Skore's order, template by template.
///
/// Reads the project periods, then per period its templates and per
/// template its projects ([SkoreGradebookService.getProjects]) until it is
/// found. Throws a [ToolError] that says where to take the ids from for a
/// project that is not there ([readSkoreProjectPeriods] for the periods).
Future<FoundSkoreProject> findSkoreProject(
  SkoreGradebooks gradebooks,
  SkoreGradebook gradebook,
  int projectId, {
  int? periodId,
}) async {
  final periods = await readSkoreProjectPeriods(
    gradebooks,
    gradebook,
    periodId: periodId,
  );
  for (final period in periods) {
    final templates = await gradebooks.getProjectTemplates(
      gradebook,
      period.id,
    );
    for (final template in templates) {
      final projects = await gradebooks.getProjects(
        gradebook,
        period.id,
        template,
      );
      for (final project in projects) {
        if (project.id == projectId) {
          return (period: period, template: template, project: project);
        }
      }
    }
  }
  final where = periodId == null
      ? 'any of its project periods'
      : 'project period ${formatSkorePeriodName(periods.single)}';
  throw ToolError(
    'The ${formatSkoreGradebookName(gradebook)} has no project with project '
    'id $projectId in $where. Take the project id from list_skore_projects '
    'for this gradebook.',
  );
}

/// A project by its title and id: `project "Webquest" (project id 8101)`.
String formatSkoreProjectName(SkoreProject project) =>
    'project "${skoreName(project.title)}" (project id ${project.id})';

/// One project: its title (and short name), project id, day and whether
/// its pupils see it ([formatSkoreProjectPublication]), last.
///
/// For example `Webquest (short name WQ) | project id 8101 | 2026-10-30 |
/// not published: the pupils do not see it`.
String formatSkoreProject(SkoreProject project) {
  final short = project.shortName;
  final date = project.date;
  return [
    '${skoreName(project.title)}'
        '${short == null ? '' : ' (short name ${skoreName(short)})'}',
    'project id ${project.id}',
    if (date != null) formatSkoreDay(date),
    formatSkoreProjectPublication(project),
  ].join(' | ');
}

/// Whether the pupils see [project] and its ratings: `PUBLISHED since
/// 2026-10-01 08:00: the pupils see it and its ratings`, `SCHEDULED for
/// ...: from then on the pupils see it and its ratings`, or `not
/// published: the pupils do not see it`. In capitals when they do (or
/// will), so that it stands out.
String formatSkoreProjectPublication(SkoreProject project) {
  final at = project.publicAt;
  if (project.isPublic) {
    return 'PUBLISHED${at == null ? '' : ' since ${formatSkoreTime(at)}'}: '
        'the pupils see it and its ratings';
  }
  if (at != null) {
    return 'SCHEDULED for ${formatSkoreTime(at)}: from then on the pupils '
        'see it and its ratings';
  }
  return 'not published: the pupils do not see it';
}

/// A template by its title and id: `template "Digitale vaardigheden"
/// (template id 61)`.
String formatSkoreProjectTemplateName(SkoreProjectTemplate template) =>
    'template "${skoreName(template.title)}" (template id ${template.id})';

/// The scale of [template], for a line: its name and its levels in Skore's
/// order, each with its symbol: `scale "Behaald / niet behaald": Behaald
/// (B), Niet behaald (NB)`; or that it takes no ratings.
String formatSkoreProjectScale(SkoreProjectTemplate template) {
  final scale = template.scale;
  if (!template.isRatingAllowed || scale == null || scale.levels.isEmpty) {
    return 'no rating scale: it takes no ratings';
  }
  return 'scale "${skoreName(scale.name)}": '
      '${[for (final level in scale.levels) formatSkoreProjectLevel(level)].join(', ')}';
}

/// A level of a scale by its name and symbol: `Behaald (B)`, or the name
/// alone when the symbol is empty or the same.
String formatSkoreProjectLevel(SkoreProjectRatingLevel level) {
  final name = skoreName(level.description);
  final symbol = level.symbol.trim();
  return symbol.isEmpty || symbol == name ? name : '$name ($symbol)';
}

/// The level [ratingId] of [template]'s scale in words: [formatSkoreProjectLevel],
/// `no level` for none, or `level id N (not on the scale)`.
String formatSkoreProjectRatingLevel(
  SkoreProjectTemplate template,
  int? ratingId,
) {
  if (ratingId == null) return 'no level';
  final level = template.scale?.levelOf(ratingId);
  return level == null
      ? 'level id $ratingId (not on the scale)'
      : formatSkoreProjectLevel(level);
}

/// A learning goal by its number (when it has one) and description, with
/// its goal id: `LPD 16.1.1 Zoekt informatie op (goal id 9002)`.
String formatSkoreLearningGoalName(SkoreLearningGoal goal) {
  final number = goal.number.trim();
  final description = skoreName(goal.description);
  return '${number.isEmpty ? '' : '$number '}$description '
      '(goal id ${goal.id})';
}

/// Whether a pupil can be rated on [goal]: an enabled goal that is neither a
/// heading nor the course's root.
bool isSkoreRatableGoal(SkoreLearningGoal goal) =>
    goal.isEnabled && !goal.isTitle && !goal.isCourse;

/// The learning goals [goals] as a tree, one line each, indented two spaces
/// per level under its parent ([SkoreLearningGoal.parentId]), in Skore's
/// order: the course's root, the headings (`heading`) and the goals, a
/// goal Skore does not enable marked so.
List<String> formatSkoreLearningGoals(List<SkoreLearningGoal> goals) {
  final byId = {for (final goal in goals) goal.id: goal};
  int depth(SkoreLearningGoal goal) {
    var depth = 0;
    final seen = <String>{goal.id};
    for (
      var parent = byId[goal.parentId];
      parent != null && seen.add(parent.id);
      parent = byId[parent.parentId]
    ) {
      depth++;
    }
    return depth;
  }

  return [
    for (final goal in goals)
      '${'  ' * depth(goal)}- ${[formatSkoreLearningGoalName(goal), if (goal.isCourse) 'the course' else if (goal.isTitle) 'heading', if (!goal.isEnabled && !goal.isCourse && !goal.isTitle) 'not enabled: it takes no ratings'].join(' | ')}',
  ];
}

/// The level of [template]'s scale that [name] names: by its name or its
/// symbol, ignoring case, accents and spaces around it.
///
/// Throws a [ToolError] that lists the levels for a name that is none of
/// them, or a template that takes no ratings; nothing is sent.
SkoreProjectRatingLevel skoreProjectLevel(
  SkoreProjectTemplate template,
  String name,
) {
  final scale = template.scale;
  if (!template.isRatingAllowed || scale == null || scale.levels.isEmpty) {
    throw ToolError(
      'The ${formatSkoreProjectTemplateName(template)} has no rating scale: '
      'it takes no ratings, so "$name" cannot be saved in it.',
    );
  }
  final wanted = _folded(name);
  for (final level in scale.levels) {
    if (_folded(level.description) == wanted ||
        _folded(level.symbol) == wanted) {
      return level;
    }
  }
  throw ToolError(
    '"$name" is not a level of the scale of the '
    '${formatSkoreProjectTemplateName(template)}. Its levels, in Skore\'s '
    'order: ${[for (final level in scale.levels) formatSkoreProjectLevel(level)].join(', ')}. '
    'Give a level by its name or its symbol, or null to clear the rating.',
  );
}

/// [text] for comparing a level's name: lowercased, without accents, every
/// run of white space as one space, trimmed.
String _folded(String text) =>
    foldForSearch(text).trim().replaceAll(RegExp(r'\s+'), ' ');

/// Refuses ratings that [tool] would save in [project] of [where] (its
/// period and gradebook) when Skore lists the project as published or
/// scheduled, unless [allowPublished]: a rating there is visible to its
/// pupils at once, or from its publication time on.
///
/// Throws a [ToolError] that says so, and that [tool] takes
/// `allow_published: true` only after the user was told exactly that and
/// said yes to it; nothing is sent. The library refuses it too, as Skore
/// lists the project right before the save, with a
/// [SmartschoolSkoreProjectPublishedError], which the tool words the same
/// way from the project it carries.
void checkSkoreProjectPublication(
  SkoreProject project, {
  required String where,
  required String tool,
  required bool allowPublished,
}) {
  final at = project.publicAt;
  if ((!project.isPublic && at == null) || allowPublished) return;
  final time = at == null ? null : formatSkoreTime(at);
  final state = project.isPublic
      ? 'PUBLISHED${time == null ? '' : ' since $time'}: its pupils would see '
            'the ratings at once'
      : 'SCHEDULED for $time: its pupils would see the ratings from then on';
  throw ToolError(
    'The ${formatSkoreProjectName(project)} in $where is $state. Tell the '
    'user exactly that, and only if the user explicitly says yes to it, '
    'call $tool again with allow_published: true.',
  );
}
