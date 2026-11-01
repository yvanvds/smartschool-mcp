import 'dart:convert';

import 'package:dio/dio.dart';

import 'fake_skore_gradebook.dart';

// A fake of Skore's project sheet (`/Gradebook`, "Projecten", #192), the
// part of a project gradebook flutter_smartschool 0.4.2 reads and writes
// (yvanvds/dartschool#204), in the shapes its `doc/skore.md` and its parsers
// describe (seen live 2026-11-01): form POSTs to `/Gradebook/Main/<method>`
// with the `context` of the period (the answer of `getGradebookContext`, as
// JSON), answered with JSON:
//   - getTemplateList {context}: the templates of the period, each with its
//     scale (`ratings`: the levels);
//   - getCategoriesList {context, template}: the learning goals
//     ("rubrieken"), from the course's root (`-<courseId>`) down;
//   - getProjectList {context, template}: the projects, each with its
//     `template`, `periodId` and `owners` (class and course);
//   - getCategoryGradesByProject {context, project}: the cells of the
//     project, each with its `pupil` as the pupil tree gives it;
//   - getGradebookConfig {context, template}: `rights.readonly`;
//   - getPupilTree {context}: the pupils of the gradebook's class;
//   - saveCategoryGrades {context, grades}: the cells to save (a new one
//     with the `id` null; `ratingId` -1 clears the level), answered with the
//     cells saved.
// The project periods themselves come from `init` with the page `1`
// (`FakeSkoreGradebook`).

/// The path of Skore's project sheet's API.
const fakeSkoreProjectPath = '/Gradebook/Main/';

/// The methods of [fakeSkoreProjectPath] the fake serves.
const fakeSkoreProjectMethods = {
  'getTemplateList',
  'getCategoriesList',
  'getProjectList',
  'getCategoryGradesByProject',
  'getGradebookConfig',
  'getPupilTree',
  'saveCategoryGrades',
};

/// A level of a template's scale.
class FakeSkoreProjectLevel {
  const FakeSkoreProjectLevel(this.id, this.description, this.symbol);

  final int id;
  final String description;
  final String symbol;

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'symbol': symbol,
    'min': 0,
    'max': 100,
    'scaleValue': 0,
    'color': '#00aa00',
    'iconName': '',
  };
}

/// A learning goal of a template ("rubriek").
class FakeSkoreLearningGoal {
  const FakeSkoreLearningGoal(
    this.id,
    this.description, {
    this.parentId,
    this.number = '',
    this.isTitle = false,
    this.isCourse = false,
    this.enabled = true,
  });

  final String id;
  final String description;
  final String? parentId;
  final String number;
  final bool isTitle;
  final bool isCourse;
  final bool enabled;

  Map<String, Object?> toJson(int courseId) => {
    'id': id,
    'parentId': parentId ?? '0',
    'description': description,
    'number': number,
    'level': 0,
    'isTitle': isTitle ? 1 : 0,
    'isCourse': isCourse ? 1 : 0,
    'enabled': enabled ? 1 : 0,
    'courseInstanceId': courseId,
  };
}

/// A cell of a project: a pupil's rating of a learning goal.
class FakeSkoreProjectCell {
  FakeSkoreProjectCell(
    this.id,
    this.pupilId,
    this.goalId, {
    this.ratingId,
    this.info,
  });

  final int id;
  final int pupilId;
  final String goalId;
  int? ratingId;
  String? info;
}

/// A project of a template.
class FakeSkoreProject {
  FakeSkoreProject(
    this.id,
    this.title, {
    this.short = '',
    this.date = '2026-10-30T00:00:00+0100',
    this.isPublic = false,
    this.publicDateTime,
    List<FakeSkoreProjectCell>? cells,
  }) : cells = cells ?? [];

  final int id;
  final String title;
  final String short;
  final String date;
  bool isPublic;
  String? publicDateTime;
  final List<FakeSkoreProjectCell> cells;
}

/// A template of a project period, with its scale, learning goals and
/// projects.
class FakeSkoreProjectTemplate {
  FakeSkoreProjectTemplate(
    this.id,
    this.title, {
    required this.scaleName,
    required this.levels,
    required this.goals,
    List<FakeSkoreProject>? projects,
    this.readonly = false,
  }) : projects = projects ?? [];

  final int id;
  final String title;
  final String scaleName;
  final List<FakeSkoreProjectLevel> levels;
  final List<FakeSkoreLearningGoal> goals;
  final List<FakeSkoreProject> projects;

  /// Whether `getGradebookConfig` answers `rights.readonly` true.
  bool readonly;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'descr': '',
    'info': '',
    'templateType': 1,
    'componentId': 0,
    'isRatingAllowed': 1,
    'isGradesAllowed': 0,
    'isRubricsEnabled': 1,
    'isComponentRequired': 0,
    'isComponentForbidden': 0,
    'creator': {'id': fakeSkoreGradebookUser},
    'scale': {
      'id': 7,
      'name': scaleName,
      'description': '',
      'ratings': [for (final level in levels) level.toJson()],
    },
  };
}

/// The project period of [fakeSkoreProjectGradebook]: `PR1`, open.
const fakeSkoreProjectPeriod = FakeSkoreGradebookPeriod(
  1710,
  'PR1',
  open: true,
  opens: '2026-09-01 08:00',
  timestamp: '2027-06-30T20:00:00+0200',
  note: 'Projecten van het schooljaar.',
);

/// A project gradebook of 2026-2027 in the shape seen live for "Digitale
/// vaardigheden" (dartschool#204): no evaluation periods, one open project
/// period PR1 with one template, "Digitale vaardigheden", on the scale
/// "Behaald" (B, level id 71) / "Niet behaald" (NB, 72), whose learning
/// goals are the course's root, a heading "Informatie verwerken" (9001) and
/// under it LPD 16.1.1 "Zoekt informatie op" (9002), LPD 16.1.2 "Beoordeelt
/// bronnen" (9003) and LPD 16.2.1 "Oud doel" (9004, not enabled). Two
/// projects: "Webquest" (8101, not published; Gert: 9002 Behaald with info
/// "Goed gezocht.", 9003 Niet behaald; Ilse: 9002 Niet behaald) and
/// "Presentatie" (8102, published since 2026-10-01 08:00, no ratings). Two
/// pupils, Gert and Ilse. Not in [FakeSkoreGradebook.loadSchool]: a test
/// adds it.
FakeSkoreOwnGradebook fakeSkoreProjectGradebook() => FakeSkoreOwnGradebook(
  workyear: FakeSkoreWorkyear.y2026,
  id: 34990,
  modelId: 176,
  modelName: '3gr D-D/A',
  groupId: 492,
  groupName: '5DG',
  classId: 2516,
  className: '5WW1',
  courseId: 1604,
  course: 'Digitale vaardigheden',
  grade: '3e graad',
  projectPeriods: [fakeSkoreProjectPeriod],
  projectTemplates: {
    1710: [
      FakeSkoreProjectTemplate(
        61,
        'Digitale vaardigheden',
        scaleName: 'Behaald / niet behaald',
        levels: const [
          FakeSkoreProjectLevel(71, 'Behaald', 'B'),
          FakeSkoreProjectLevel(72, 'Niet behaald', 'NB'),
        ],
        goals: const [
          FakeSkoreLearningGoal(
            '-1604',
            'Digitale vaardigheden',
            isCourse: true,
          ),
          FakeSkoreLearningGoal(
            '9001',
            'Informatie verwerken',
            parentId: '-1604',
            isTitle: true,
          ),
          FakeSkoreLearningGoal(
            '9002',
            'Zoekt informatie op',
            parentId: '9001',
            number: 'LPD 16.1.1',
          ),
          FakeSkoreLearningGoal(
            '9003',
            'Beoordeelt bronnen',
            parentId: '9001',
            number: 'LPD 16.1.2',
          ),
          FakeSkoreLearningGoal(
            '9004',
            'Oud doel',
            parentId: '9001',
            number: 'LPD 16.2.1',
            enabled: false,
          ),
        ],
        projects: [
          FakeSkoreProject(
            8101,
            'Webquest',
            short: 'WQ',
            cells: [
              FakeSkoreProjectCell(
                70001,
                1221,
                '9002',
                ratingId: 71,
                info: 'Goed gezocht.',
              ),
              FakeSkoreProjectCell(70002, 1221, '9003', ratingId: 72),
              FakeSkoreProjectCell(70003, 1222, '9002', ratingId: 72),
            ],
          ),
          FakeSkoreProject(
            8102,
            'Presentatie',
            date: '2026-11-20T00:00:00+0100',
            isPublic: true,
            publicDateTime: '2026-10-01T08:00:00+0200',
          ),
        ],
      ),
    ],
  },
  pupils: [
    const FakeSkoreGradebookPupil(
      1221,
      'Jacobs, Gert',
      'Gert Jacobs',
      number: 1,
    ),
    const FakeSkoreGradebookPupil(
      1222,
      'Lemmens, Ilse',
      'Ilse Lemmens',
      number: 2,
    ),
  ],
);

/// Skore's project sheet of the gradebooks of [gradebook]: answers the
/// form POSTs to [fakeSkoreProjectPath].
class FakeSkoreProjectSheet {
  FakeSkoreProjectSheet(this.gradebook);

  final FakeSkoreGradebook gradebook;

  /// The calls that reached the sheet, in order: the method and its form.
  final List<({String method, Map<String, String> form})> requests = [];

  /// The methods that reached the sheet, in order.
  List<String> get calls => [for (final r in requests) r.method];

  /// The cells of every `saveCategoryGrades`, in order.
  List<List<Object?>> get saves => [
    for (final r in requests)
      if (r.method == 'saveCategoryGrades')
        (jsonDecode(r.form['grades']!) as List).cast<Object?>(),
  ];

  /// When true, a `saveCategoryGrades` is answered with the cells sent, but
  /// not carried out: a save Skore did not keep.
  bool savesIgnored = false;

  /// Called with the method of every call, after it is recorded and before
  /// it is answered: to change a project between two calls.
  void Function(String method)? beforeAnswer;

  /// The id the next new cell gets.
  int nextCellId = 70100;

  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (options.method != 'POST' || !path.startsWith(fakeSkoreProjectPath)) {
      return null;
    }
    final method = path.substring(fakeSkoreProjectPath.length);
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    requests.add((method: method, form: form));
    beforeAnswer?.call(method);
    if (!fakeSkoreProjectMethods.contains(method)) {
      return _json({'message': 'the fake does not serve $method'}, 501);
    }
    final context = jsonDecode(form['context'] ?? 'null');
    final owners = context is Map ? context['owners'] : null;
    final bookId = owners is List && owners.length == 1
        ? int.tryParse('${owners.single}')
        : null;
    final book = bookId == null
        ? null
        : gradebook.gradebookWithId(bookId, gradebook.currentWorkyear);
    final periodId = context is Map
        ? int.tryParse('${context['periodId']}')
        : null;
    if (book == null || periodId == null) {
      return _json({
        'message': 'the fake cannot read the context $context',
      }, 400);
    }
    final templates = book.projectTemplates[periodId] ?? const [];
    FakeSkoreProjectTemplate? templateOf(String field) {
      final sent = jsonDecode(form[field] ?? 'null');
      final id = sent is Map ? int.tryParse('${sent['id']}') : null;
      return templates.where((t) => t.id == id).firstOrNull;
    }

    ({FakeSkoreProjectTemplate template, FakeSkoreProject project})? projectOf(
      Object? sent,
    ) {
      final id = sent is Map ? int.tryParse('${sent['id']}') : null;
      for (final template in templates) {
        for (final project in template.projects) {
          if (project.id == id) return (template: template, project: project);
        }
      }
      return null;
    }

    switch (method) {
      case 'getTemplateList':
        return _json([for (final t in templates) t.toJson()]);
      case 'getCategoriesList':
        final template = templateOf('template');
        if (template == null) return _json({'message': 'no template'}, 404);
        return _json([for (final g in template.goals) g.toJson(book.courseId)]);
      case 'getProjectList':
        final template = templateOf('template');
        if (template == null) return _json({'message': 'no template'}, 404);
        return _json([
          for (final p in template.projects)
            _projectJson(book, periodId, template, p),
        ]);
      case 'getGradebookConfig':
        final template = templateOf('template');
        if (template == null) return _json({'message': 'no template'}, 404);
        return _json({
          'rights': {'readonly': template.readonly},
        });
      case 'getPupilTree':
        return _json([
          {
            'id': book.groupId,
            'name': book.groupName,
            'icon': '',
            'classes': [
              {
                'id': book.classId,
                'name': book.className,
                'icon': '',
                'pupils': [for (final p in book.pupils) _pupil(book, p.id)],
              },
            ],
          },
        ]);
      case 'getCategoryGradesByProject':
        final found = projectOf(jsonDecode(form['project'] ?? 'null'));
        if (found == null) return _json({'message': 'no project'}, 404);
        return _json([
          for (final cell in found.project.cells)
            _cellJson(book, found.project, cell),
        ]);
      case 'saveCategoryGrades':
        final cells = (jsonDecode(form['grades'] ?? '[]') as List)
            .cast<Map<String, Object?>>();
        final saved = <Object?>[];
        for (final sent in cells) {
          final found = projectOf({'id': sent['projectId']});
          if (found == null) return _json({'message': 'no project'}, 404);
          final project = found.project;
          final ratingId = int.tryParse('${sent['ratingId']}');
          final info = sent['info'] as String?;
          final pupil = sent['pupil'] as Map;
          final pupilId = int.parse('${pupil['userId']}');
          final goalId = '${sent['categoryId']}';
          final id = sent['id'];
          FakeSkoreProjectCell cell;
          if (id == null) {
            cell = FakeSkoreProjectCell(nextCellId++, pupilId, goalId);
            if (!savesIgnored) project.cells.add(cell);
          } else {
            cell = project.cells.firstWhere((c) => c.id == id);
          }
          if (!savesIgnored) {
            cell
              ..ratingId = ratingId == null || ratingId == -1 ? null : ratingId
              ..info = info == null || info.isEmpty ? null : info;
          }
          saved.add(_cellJson(book, project, cell));
        }
        return _json(saved);
    }
    return null;
  }

  static Map<String, Object?> _projectJson(
    FakeSkoreOwnGradebook book,
    int periodId,
    FakeSkoreProjectTemplate template,
    FakeSkoreProject project,
  ) => {
    'id': project.id,
    'periodId': periodId,
    'template': template.toJson(),
    'title': project.title,
    'short': project.short,
    'date': project.date,
    'max': 0,
    'evalType': 'ratings',
    'isPublic': project.isPublic ? 1 : 0,
    'publicDateTime': project.publicDateTime,
    'inCount': 0,
    'componentId': 0,
    'groupContext': 0,
    'owners': [
      {'classId': book.classId, 'courseId': book.courseId},
    ],
  };

  static Map<String, Object?> _pupil(FakeSkoreOwnGradebook book, int id) => {
    'id': id + 50000,
    'userId': id,
    'classId': book.classId,
    'enabled': 1,
    'enabledCourses': <Object?>[],
  };

  static Map<String, Object?> _cellJson(
    FakeSkoreOwnGradebook book,
    FakeSkoreProject project,
    FakeSkoreProjectCell cell,
  ) => {
    'id': cell.id,
    'projectId': project.id,
    'categoryId': cell.goalId,
    'grade': null,
    'ratingId': cell.ratingId,
    'info': cell.info,
    'options': <Object?>[],
    'pupil': _pupil(book, cell.pupilId),
  };

  static ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
}
