import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import '../skore/skore_projects.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_skore_projects`: the projects of one of the user's project
/// gradebooks in Skore ("Projecten", #192, yvanvds/dartschool#204), per
/// project period and template, with the template's rating scale
/// ([SkoreGradebookService.getProjectPeriods], `getProjectTemplates`,
/// `getProjects`).
///
/// Offered to every account, without a switch, like the other gradebook
/// tools.
ServerTool listSkoreProjectsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_projects',
    title: 'List the projects of a project gradebook in Skore',
    description:
        'Lists the projects of one of the user\'s project gradebooks in '
        'Skore, the Smartschool module for scores and reports (Skore\'s '
        '"Projecten": a course whose pupils are rated per learning goal, '
        'such as "Digitale vaardigheden", instead of getting grades in '
        'evaluations; read_skore_gradebook says when a gradebook is one). '
        'By the gradebook id from list_skore_gradebooks: one of their own, '
        'or one a colleague shared with them. Per project period (with its '
        'period id, whether it is open and until when; only an open one '
        'takes ratings), each template (Skore\'s "Project:" selector) with '
        'its template id and its rating scale (its levels, such as Behaald '
        'and Niet behaald, by name and symbol), and under it each project '
        'with its project id, its day and whether its pupils see it '
        '(published or scheduled, in capitals). Pass the project id to '
        'read_skore_project for the learning goals and the pupils\' '
        'ratings. Projects are made and published in Skore in Smartschool '
        'itself, not here. For a gradebook of an earlier school year, pass '
        'its workyear_id too. Reading changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'One project period, by its period id from this tool or '
              'read_skore_gradebook. Default: every project period.',
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
      required: ['gradebook_id'],
    ),
    annotations: ToolAnnotations(
      title: 'List the projects of a project gradebook in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

/// A template of a project period with its projects.
typedef _Template = ({
  SkoreProjectTemplate template,
  List<SkoreProject> projects,
});

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final periodId = intArgument(arguments, 'period_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final text = await withSkoreGradebook(session, (gradebooks) async {
    final found = await years.find(
      gradebooks,
      gradebookId,
      workyearId: workyearId,
    );
    final periods = await readSkoreProjectPeriods(
      gradebooks,
      found.gradebook,
      periodId: periodId,
    );
    final read = <(SkoreGradebookPeriod, List<_Template>)>[];
    for (final period in periods) {
      final templates = <_Template>[];
      for (final template in await gradebooks.getProjectTemplates(
        found.gradebook,
        period.id,
      )) {
        templates.add((
          template: template,
          projects: await gradebooks.getProjects(
            found.gradebook,
            period.id,
            template,
          ),
        ));
      }
      read.add((period, templates));
    }
    return _formatProjects(found.gradebook, found.workyear, read);
  });
  return CallToolResult(content: [TextContent(text: text)]);
}

/// What `list_skore_projects` answers: the project gradebook [gradebook] of
/// school year [workyear], and per project period in [periods] its
/// templates, each with its scale and its projects.
String _formatProjects(
  SkoreGradebook gradebook,
  SkoreWorkyear workyear,
  List<(SkoreGradebookPeriod, List<_Template>)> periods,
) {
  final count = periods.fold(
    0,
    (sum, p) => sum + p.$2.fold(0, (sum, t) => sum + t.projects.length),
  );
  return [
    '${formatSkoreGradebookTitle(gradebook, workyear)}.',
    'A project gradebook (Skore\'s "Projecten"): its pupils are rated per '
        'learning goal in projects, on the scale of the project\'s template. '
        '${count == 0
            ? 'No projects'
            : count == 1
            ? '1 project'
            : '$count projects'} '
        'in ${periods.length == 1 ? 'this project period' : 'these ${periods.length} project periods'}, '
        'in Skore\'s order; read_skore_project reads one by its project id.',
    for (final (period, templates) in periods) ...[
      'Project period ${formatSkoreGradebookPeriod(period, active: false)}',
      if (templates.isEmpty) '  No templates: it has no projects.',
      for (final (:template, :projects) in templates) ...[
        '- ${formatSkoreProjectTemplateName(template)} | '
            '${formatSkoreProjectScale(template)}',
        if (projects.isEmpty)
          '  No projects made in it yet; projects are made in Skore in '
              'Smartschool itself.',
        for (final project in projects) '  - ${formatSkoreProject(project)}',
      ],
    ],
  ].join('\n');
}
