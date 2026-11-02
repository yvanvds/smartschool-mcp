/// The project gradebooks of Skore ("Projecten", #192): `read_skore_gradebook`
/// saying a gradebook is one, `list_skore_projects`, `read_skore_project`
/// and `save_skore_project_ratings`, called over MCP on the real server,
/// session and library (flutter_smartschool 0.4.2, yvanvds/dartschool#204),
/// against a fake Smartschool whose Skore gradebook serves the project
/// sheet (`test/support/fake_skore_projects.dart`). Like the other gradebook
/// tools, they need no switch.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_skore_projects_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_gradebook_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_project_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_report_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_project_ratings_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// What no gradebook text may say: the gradebook is not behind the switch
/// "Skore-beheer", and needs no extra rights.
final _adminWords = RegExp(
  r'Skore-beheer|SMARTSCHOOL_SKORE|rights|administrator|score management',
  caseSensitive: false,
);

/// [iso], a time with its offset as Skore gives it, as the tools show it.
String _time(String iso) {
  final local = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

const _title =
    'Gradebook id 34990: Digitale vaardigheden (3e graad), class 5WW1, '
    'school year 2026-2027 (workyear id 24).';
const _gradebookName =
    'gradebook of 5WW1 for Digitale vaardigheden (3e graad) (gradebook id '
    '34990)';
const _where = 'project period PR1 (period id 1710) of the $_gradebookName';
final _period =
    'PR1 | period id 1710 | open, closes '
    '${_time('2027-06-30T20:00:00+0200')} | note: Open van 2026-09-01 08:00 '
    'tot en met 2027-06-30 20:00. Projecten van het schooljaar.';
const _template =
    'template "Digitale vaardigheden" (template id 61) | scale "Behaald / '
    'niet behaald": Behaald (B), Niet behaald (NB)';
const _webquest =
    'Webquest (short name WQ) | project id 8101 | 2026-10-30 | not '
    'published: the pupils do not see it';
final _presentatie =
    'Presentatie | project id 8102 | 2026-11-20 | PUBLISHED since '
    '${_time('2026-10-01T08:00:00+0200')}: the pupils see it and its ratings';
const _gert = '1. Jacobs, Gert | pupil id 1221';
const _ilse = '2. Lemmens, Ilse | pupil id 1222';
const _zoekt = 'LPD 16.1.1 Zoekt informatie op (goal id 9002)';
const _bronnen = 'LPD 16.1.2 Beoordeelt bronnen (goal id 9003)';

const _goals =
    '5 learning goals (rubrieken), in Skore\'s order, as a tree; 2 of them '
    'take a rating (not the course, a heading or a goal that is not '
    'enabled):\n'
    '- Digitale vaardigheden (goal id -1604) | the course\n'
    '  - Informatie verwerken (goal id 9001) | heading\n'
    '    - $_zoekt\n'
    '    - $_bronnen\n'
    '    - LPD 16.2.1 Oud doel (goal id 9004) | not enabled: it takes no '
    'ratings';

/// What the tool says after a check of the library refused the change.
String _refused(String reason) =>
    'Skore refused the change before saving it: $reason Read the project '
    'again with read_skore_project (gradebook_id 34990, project_id 8101: its '
    'publication, the goal ids, the levels and the pupils\' ratings) and '
    'list_skore_projects (whether the project period is open) to correct the '
    'call. Nothing was changed in Skore.';

void main() {
  late FakeSmartschool server;
  late FakeSkoreGradebook skore;
  late FakeSkoreOwnGradebook book;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skoreGradebook..loadSchool();
    book = fakeSkoreProjectGradebook();
    skore.gradebooks.add(book);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        readSkoreGradebookTool(session),
        readSkoreReportTool(session),
        listSkoreProjectsTool(session),
        readSkoreProjectTool(session),
        saveSkoreProjectRatingsTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method of the project sheet off the library's list, such as
    // one that makes, publishes or removes a project.
    expect(
      skore.projects.calls,
      everyElement(isIn(fakeSkoreProjectMethods.toList())),
    );
  });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    expect(text, isNot(matches(_adminWords)));
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    expect(text, isNot(matches(_adminWords)));
    return text;
  }

  /// The cell of [pupil] and [goal] in project [project] of the fake.
  FakeSkoreProjectCell? cell(int project, int pupil, String goal) => book
      .projectTemplates[1710]!
      .single
      .projects
      .singleWhere((p) => p.id == project)
      .cells
      .where((c) => c.pupilId == pupil && c.goalId == goal)
      .firstOrNull;

  group('read_skore_gradebook', () {
    test('says a gradebook is a project gradebook when Skore\'s init lists '
        'its project period among its periods, as live (#205): lists its '
        'project periods, not as evaluation periods, and points to the '
        'project tools; its report periods are left out; no second '
        'init', () async {
      book.reports.add(fakeSkoreReportR1D);
      expect(
        await ok('read_skore_gradebook', {'gradebook_id': 34990}),
        '$_title\n'
        'It is a project gradebook (Skore\'s "Projecten"): it has no '
        'evaluation periods, so no evaluations and no grades; its pupils are '
        'rated per learning goal in projects, on the scale of the project\'s '
        'template. list_skore_projects lists its projects, read_skore_project '
        'reads their ratings, and save_skore_project_ratings saves them. A '
        'project course is not on the gradebook\'s reports, so it has no '
        'course comments there.\n'
        '1 project period, in Skore\'s order; only an open one takes '
        'ratings:\n'
        '- $_period\n'
        '2 pupils, in Skore\'s order:\n'
        '- $_gert\n'
        '- $_ilse',
      );
      expect(skore.calls, [
        'getNavigation',
        'accessableList',
        'init wy=24',
        'getGradebookContext wy=24',
      ]);
    });

    test('a gradebook with evaluation periods only is not a project '
        'gradebook, and costs no extra request', () async {
      final text = await ok('read_skore_gradebook', {'gradebook_id': 32508});
      expect(text, isNot(contains('project')));
      expect(text, contains('\nSkore lets the user change it.\n'));
      expect(skore.calls.where((c) => c.startsWith('init')), ['init wy=24']);
    });

    test('a gradebook with evaluation and project periods (not seen live) '
        'lists both apart, and Skore opens it on an evaluation '
        'period', () async {
      book.periods.add(
        const FakeSkoreGradebookPeriod(
          1704,
          'DW1',
          open: true,
          opens: '2026-09-01 08:00',
          timestamp: '2026-12-18T20:00:00+0100',
          note: 'Eerste dagelijks werk.',
        ),
      );
      final text = await ok('read_skore_gradebook', {'gradebook_id': 34990});
      expect(
        text,
        contains(
          '\nIt is a project gradebook (Skore\'s "Projecten"): besides the '
          'evaluation periods listed below, its pupils are rated per '
          'learning goal in projects',
        ),
      );
      expect(
        text,
        contains(
          '\n1 project period, in Skore\'s order; only an open one takes '
          'ratings:\n- $_period\n',
        ),
      );
      expect(
        text,
        contains(
          '\n1 period, in Skore\'s order; only an open period takes grades, '
          'and Skore opens the gradebook on DW1 (active):\n- DW1 | period id '
          '1704 |',
        ),
      );
    });
  });

  test('read_skore_report of a project course: Skore\'s 404 says so and '
      'points to the project tools (#184)', () async {
    book.reports.add(fakeSkoreReportR1D);
    book.reportOf(2762).courseOnReport = false;
    final text = await error('read_skore_report', {
      'gradebook_id': 34990,
      'report_id': 2762,
    });
    expect(
      text,
      contains(
        'Skore answers so for a project course (Skore\'s "Projecten"), which '
        'is not on the gradebook\'s reports: read_skore_gradebook says '
        'whether the gradebook is one, and read_skore_project reads the '
        'ratings of its projects.',
      ),
    );
  });

  group('list_skore_projects', () {
    test('per project period, each template with its scale and its '
        'projects, the published one in capitals', () async {
      expect(
        await ok('list_skore_projects', {'gradebook_id': 34990}),
        '$_title\n'
        'A project gradebook (Skore\'s "Projecten"): its pupils are rated per '
        'learning goal in projects, on the scale of the project\'s template. '
        '2 projects in this project period, in Skore\'s order; '
        'read_skore_project reads one by its project id.\n'
        'Project period $_period\n'
        '- $_template\n'
        '  - $_webquest\n'
        '  - $_presentatie',
      );
      expect(skore.projects.calls, ['getTemplateList', 'getProjectList']);
    });

    test(
      'a template without projects says they are made in Smartschool',
      () async {
        book.projectTemplates[1710]!.single.projects.clear();
        expect(
          await ok('list_skore_projects', {
            'gradebook_id': 34990,
            'period_id': 1710,
          }),
          endsWith(
            '- $_template\n'
            '  No projects made in it yet; projects are made in Skore in '
            'Smartschool itself.',
          ),
        );
      },
    );

    test('an unknown project period lists them; a gradebook without project '
        'periods is not a project gradebook', () async {
      expect(
        await error('list_skore_projects', {
          'gradebook_id': 34990,
          'period_id': 1704,
        }),
        'The $_gradebookName has no project period with period id 1704. Its '
        'project periods, in Skore\'s order: PR1 (period id 1710, open). Take '
        'a period id from these, as list_skore_projects lists them, or leave '
        'out period_id to look in every project period.',
      );
      expect(
        await error('list_skore_projects', {'gradebook_id': 32508}),
        'The gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
        '(gradebook id 32508) has no project periods (Skore\'s "Projecten"): '
        'it is not a project gradebook, so it has no projects. Its '
        'evaluations are read with list_skore_evaluations.',
      );
      expect(skore.projects.calls, isEmpty);
    });
  });

  group('read_skore_project', () {
    test('the project, the scale, the goals as a tree and each pupil\'s '
        'ratings by level name, with the info', () async {
      expect(
        await ok('read_skore_project', {
          'gradebook_id': 34990,
          'project_id': 8101,
        }),
        '$_title\n'
        'Project: $_webquest\n'
        'In project period $_period\n'
        'Template: $_template\n'
        '$_goals\n'
        'Ratings of 2 pupils, in Skore\'s order, each with the goals rated, '
        'in the order of the goals:\n'
        '- $_gert\n'
        '  - $_zoekt: Behaald (B) | info: Goed gezocht.\n'
        '  - $_bronnen: Niet behaald (NB)\n'
        '- $_ilse\n'
        '  - $_zoekt: Niet behaald (NB)',
      );
    });

    test('pupil_id gives one pupil; a pupil without ratings says so', () async {
      book.projectTemplates[1710]!.single.projects.first.cells.removeWhere(
        (c) => c.pupilId == 1222,
      );
      expect(
        await ok('read_skore_project', {
          'gradebook_id': 34990,
          'project_id': 8101,
          'period_id': 1710,
          'pupil_id': 1222,
        }),
        endsWith(
          'The pupil\'s ratings, in the order of the goals:\n'
          '- $_ilse\n'
          '  no ratings',
        ),
      );
    });

    test('an unknown project says where to take the id from', () async {
      expect(
        await error('read_skore_project', {
          'gradebook_id': 34990,
          'project_id': 9999,
        }),
        'The $_gradebookName has no project with project id 9999 in any of '
        'its project periods. Take the project id from list_skore_projects '
        'for this gradebook.',
      );
    });
  });

  group('save_skore_project_ratings', () {
    test('saves a level by symbol (any case), clears a rating, and gives a '
        'pupil a first rating with info, in one save; the result lists them '
        'as Skore does after the save', () async {
      final text = await ok('save_skore_project_ratings', {
        'gradebook_id': 34990,
        'project_id': 8101,
        'ratings': [
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'nb', 'info': ''},
          {'pupil_id': 1221, 'goal_id': '9003', 'level': null},
          {
            'pupil_id': 1222,
            'goal_id': '9003',
            'level': ' behaald ',
            'info': 'Mooie bronnen.',
          },
        ],
      });
      expect(
        text,
        'Saved 3 ratings in the project "Webquest" (project id 8101) in '
        '$_where.\n'
        'Project: $_webquest\n'
        'Ratings as Skore lists them after the save, in the order given:\n'
        '- $_gert | $_zoekt: Niet behaald (NB)\n'
        '- $_gert | $_bronnen: no level\n'
        '- $_ilse | $_bronnen: Behaald (B) | info: Mooie bronnen.',
      );
      expect(skore.projects.saves, hasLength(1));
      final sent = skore.projects.saves.single.cast<Map>();
      expect(
        [for (final c in sent) (c['id'], c['ratingId'], c['info'])],
        [(70001, 72, ''), (70002, -1, null), (null, 71, 'Mooie bronnen.')],
      );
      expect(cell(8101, 1221, '9002')!.info, isNull);
      expect(cell(8101, 1222, '9003')!.ratingId, 71);
    });

    test('a published project is refused without allow_published, nothing '
        'sent; with it, the rating is saved', () async {
      final arguments = {
        'gradebook_id': 34990,
        'project_id': 8102,
        'period_id': 1710,
        'ratings': [
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'B'},
        ],
      };
      expect(
        await error('save_skore_project_ratings', arguments),
        'The project "Presentatie" (project id 8102) in $_where is PUBLISHED '
        'since ${_time('2026-10-01T08:00:00+0200')}: its pupils would see '
        'the ratings at once. Tell the user exactly that, and only if the '
        'user explicitly says yes to it, call save_skore_project_ratings '
        'again with allow_published: true. Nothing was changed in Skore.',
      );
      expect(skore.projects.saves, isEmpty);
      expect(
        await ok('save_skore_project_ratings', {
          ...arguments,
          'allow_published': true,
        }),
        startsWith('Saved 1 rating in the project "Presentatie"'),
      );
      expect(cell(8102, 1221, '9002')!.ratingId, 71);
    });

    test('a project published between the tool\'s read and the library\'s: '
        'the library\'s refusal is said the same way', () async {
      final webquest = book.projectTemplates[1710]!.single.projects.first;
      var lists = 0;
      skore.projects.beforeAnswer = (method) {
        if (method == 'getProjectList' && ++lists == 2) {
          webquest
            ..isPublic = false
            ..publicDateTime = '2099-01-11T08:00:00+0100';
        }
      };
      final text = await error('save_skore_project_ratings', {
        'gradebook_id': 34990,
        'project_id': 8101,
        'ratings': [
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'B'},
        ],
      });
      expect(
        text,
        'The project "Webquest" (project id 8101) in $_where is SCHEDULED '
        'for ${_time('2099-01-11T08:00:00+0100')}: its pupils would see the '
        'ratings from then on. Tell the user exactly that, and only if the '
        'user explicitly says yes to it, call save_skore_project_ratings '
        'again with allow_published: true. Nothing was changed in Skore.',
      );
      expect(skore.projects.saves, isEmpty);
    });

    test('a level not on the scale, a goal that takes no rating, an unknown '
        'pupil and a pupil and goal given twice are refused before anything '
        'is sent', () async {
      Future<String> refused(List<Map<String, Object?>> ratings) => error(
        'save_skore_project_ratings',
        {'gradebook_id': 34990, 'project_id': 8101, 'ratings': ratings},
      );
      expect(
        await refused([
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'Goed'},
        ]),
        '"Goed" is not a level of the scale of the template "Digitale '
        'vaardigheden" (template id 61). Its levels, in Skore\'s order: '
        'Behaald (B), Niet behaald (NB). Give a level by its name or its '
        'symbol, or null to clear the rating. Nothing was changed in Skore.',
      );
      expect(
        await refused([
          {'pupil_id': 1221, 'goal_id': '9001', 'level': 'B'},
          {'pupil_id': 1221, 'goal_id': '9004', 'level': 'B'},
          {'pupil_id': 1221, 'goal_id': '1', 'level': 'B'},
        ]),
        'In the project "Webquest" (project id 8101), Informatie verwerken '
        '(goal id 9001) is a heading; LPD 16.2.1 Oud doel (goal id 9004) is '
        'not enabled in the template; goal id 1 is not one of its learning '
        'goals, so it takes no rating. Take the goal ids of the goals that '
        'take a rating from read_skore_project for this project. Nothing was '
        'changed in Skore.',
      );
      expect(
        await refused([
          {'pupil_id': 1299, 'goal_id': '9002', 'level': 'B'},
        ]),
        'The $_gradebookName has no pupil with pupil id 1299. Take the pupil '
        'ids from read_skore_project for this gradebook. Nothing was changed '
        'in Skore.',
      );
      expect(
        await refused([
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'B'},
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'NB'},
        ]),
        'ratings lists pupil id 1221 with goal id 9002 more than once: give '
        'each pupil and goal once, with the level the user confirmed. '
        'Nothing was changed in Skore.',
      );
      expect(skore.projects.saves, isEmpty);
    });

    test('the library\'s refusals are passed on with what to read again: a '
        'clear of a rating that is not there, a gradebook Skore shows '
        'read-only', () async {
      expect(
        await error('save_skore_project_ratings', {
          'gradebook_id': 34990,
          'project_id': 8101,
          'ratings': [
            {'pupil_id': 1222, 'goal_id': '9003', 'level': null},
          ],
        }),
        _refused(
          'in project 8101 ("Webquest") in project period PR1 (1710) of '
          'gradebook 34990, pupil 1222 has no rating of goal 9003 to clear.',
        ),
      );
      book.writable = false;
      expect(
        await error('save_skore_project_ratings', {
          'gradebook_id': 34990,
          'project_id': 8101,
          'ratings': [
            {'pupil_id': 1221, 'goal_id': '9002', 'level': 'B'},
          ],
        }),
        _refused(
          'Skore shows gradebook 34990 read-only to you in project period '
          'PR1 (1710) (writable 0).',
        ),
      );
      expect(skore.projects.saves, isEmpty);
    });

    test('a save Skore does not keep: the result says the ratings may or may '
        'not have been saved, and that saving again is harmless', () async {
      skore.projects.savesIgnored = true;
      final text = await error('save_skore_project_ratings', {
        'gradebook_id': 34990,
        'project_id': 8101,
        'ratings': [
          {'pupil_id': 1221, 'goal_id': '9002', 'level': 'B'},
          {'pupil_id': 1222, 'goal_id': '9002', 'level': 'B', 'info': 'Ok'},
        ],
      });
      expect(
        text,
        '2 ratings in the project "Webquest" (project id 8101) in $_where '
        'were sent, but Skore did not confirm 1 of them.\n'
        'Saved, as Skore lists them after the save:\n'
        '- $_gert | $_zoekt: Behaald (B) | info: Goed gezocht.\n'
        'May or may not have been saved:\n'
        '- $_ilse | $_zoekt | sent: Behaald (B) | info: Ok\n'
        'Saving a rating again is harmless: read the project again with '
        'read_skore_project (gradebook_id 34990, project_id 8101, period_id '
        '1710), tell the user what you found, and save only the ratings that '
        'differ from the ones the user confirmed again with '
        'save_skore_project_ratings.',
      );
    });
  });
}
