import 'dart:convert';

import 'package:dio/dio.dart';

// A fake of Skore's gradebook as a teacher sees it at `/SkoreGradebook`
// ("Puntenboek"): the RPC service `SkoreGradebookService` of
// flutter_smartschool calls (dartschool#148), answered in the shape of
// dartschool's trimmed live captures (read-only, 2026-10-08) in
// `test/skore_gradebook_service_test.dart` there:
//   - getNavigation(userID, 0): the tree of the left panel with the
//     gradebooks of a school year, and the school years (`workyears`,
//     `currentWorkyear` as a string). A group node repeats gradebooks of its
//     classes. A school year Skore does not offer (`wy` "99" live) gets an
//     empty tree with `currentWorkyear` the year asked for.
//   - init(courses, owners, userID, pathIds, 0, 0): the periods and the rows
//     of a gradebook (`left_0`, ...: `1.  Last, First`, or `- Last, First`
//     without a class number, a `gbc_hidden` span for an inactive pupil).
//   - getGradebookContext(pathIds, courses, owners, userID, periodId, 0, wy):
//     whether the user may change the gradebook.
// The school year goes as `wy` (a string) in the session object; without
// it, Skore answers for its current school year. Class, group, model,
// course, gradebook and period ids and names are those of the captures;
// pupils and teachers are obvious fakes.
//
// It serves only [fakeSkoreGradebookRpcMethods] and answers any other with
// HTTP 501. The later gradebook tools add theirs (getEvaluations, the
// feedback REST API, getPosComponents, getNewEvalDialogBox, saveEvaluation,
// saveGrade): a method of the library's allowlist
// (`SkoreGradebookService.rpcMethods`) and an answer in the shape of
// dartschool's capture for it.

/// Skore's gradebook RPC service, behind `/SkoreGradebook`.
const fakeSkoreGradebookRpcPath = '/modules/Skore/backend/gradebook/rpc.php';

/// The RPC methods of [fakeSkoreGradebookRpcPath] the fake serves.
const fakeSkoreGradebookRpcMethods = {
  'getNavigation',
  'init',
  'getGradebookContext',
};

/// The Smartschool user id of the fake's account (`12_345_0` on the fake
/// Smartschool's pages): the teacher of the gradebooks.
const fakeSkoreGradebookUser = 345;

/// A school year of Skore: `["24", "2026-2027"]`.
class FakeSkoreWorkyear {
  const FakeSkoreWorkyear(this.id, this.name);

  static const y2026 = FakeSkoreWorkyear(24, '2026-2027');
  static const y2025 = FakeSkoreWorkyear(22, '2025-2026');
  static const y2024 = FakeSkoreWorkyear(20, '2024-2025');

  final int id;
  final String name;
}

/// A period of a gradebook, as `init` gives it.
class FakeSkoreGradebookPeriod {
  const FakeSkoreGradebookPeriod(
    this.id,
    this.name, {
    required this.open,
    required this.timestamp,
    required this.note,
    this.opens,
  });

  final int id;
  final String name;

  /// Whether the period takes grades (`open` 1).
  final bool open;

  /// When it closes, as Skore writes it (`2026-12-18T20:00:00+0100`); empty
  /// for none.
  final String timestamp;

  /// When it opens, as Skore's description says it of an open period
  /// (`2026-09-18 15:30`).
  final String? opens;

  /// The school's note in Skore's description.
  final String note;

  /// Skore's description (`info`): the name, the dates (or `Gesloten!`
  /// with a lock for a closed period) and the note, as captured.
  String get info {
    final closes = timestamp.isEmpty
        ? ''
        : timestamp.substring(0, 16).replaceFirst('T', ' ');
    final state = open
        ? 'Open van ${opens ?? ''}<br/> tot en met $closes'
        : '<img src="/turbowidgets_dev/skore/mvc/templates/images/lock.png" '
              'align="absmiddle"/><span style="margin-left:5px;">'
              'Gesloten!</span>';
    return '<p><u><b>$name</b></u></p><p>$state</p><p>$note</p>';
  }
}

/// A pupil of a gradebook's class: a row `pupil_<id>_<classId>`.
class FakeSkoreGradebookPupil {
  const FakeSkoreGradebookPupil(
    this.id,
    this.name,
    this.displayName, {
    this.number,
    this.active = true,
  });

  final int id;

  /// Last name first, as the row shows it (`Aerts, An`).
  final String name;

  /// First name first, as the row's `alternate` carries it (`An Aerts`).
  final String displayName;

  /// The class number, or null for a row without (`- Maes, Lotte`).
  final int? number;

  /// False for a row Skore greys out (`gbc_hidden`).
  final bool active;
}

/// One of the user's gradebooks: a course of a class in a school year.
class FakeSkoreOwnGradebook {
  FakeSkoreOwnGradebook({
    required this.workyear,
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.groupId,
    required this.groupName,
    required this.classId,
    required this.className,
    required this.courseId,
    required this.course,
    this.grade = '',
    this.teachers = const ['Peeters Jan'],
    List<FakeSkoreGradebookPeriod>? periods,
    this.activePeriod = 0,
    List<FakeSkoreGradebookPupil>? pupils,
    this.writable = true,
    this.coordinator = false,
  }) : periods = periods ?? [],
       pupils = pupils ?? [];

  final FakeSkoreWorkyear workyear;

  /// The gradebook id (Skore's `ownerID`).
  final int id;
  final int modelId;
  final String modelName;
  final int groupId;
  final String groupName;
  final int classId;
  final String className;
  final int courseId;

  /// The course name without the grade (`init`'s `ownerMap`).
  final String course;

  /// The grade the left panel adds to the course (`6e j DO`); empty for
  /// none.
  final String grade;

  /// The names of the course's teachers (Skore's `part`).
  final List<String> teachers;

  final List<FakeSkoreGradebookPeriod> periods;

  /// The index in [periods] of the period Skore opens the gradebook on
  /// (`activePeriodE`).
  int activePeriod;

  final List<FakeSkoreGradebookPupil> pupils;

  /// Whether `getGradebookContext` answers `writable` 1.
  bool writable;

  /// Whether `getGradebookContext` answers `coordinator` 1.
  bool coordinator;

  /// The course as the left panel names it, with the grade.
  String get courseName => grade.isEmpty ? course : '$course ($grade)';
}

/// 6EWI's gradebook of 2026-2027 as captured: one open period, three
/// pupils with a class number, writable.
FakeSkoreOwnGradebook fakeSkoreGradebook6EWI() => FakeSkoreOwnGradebook(
  workyear: FakeSkoreWorkyear.y2026,
  id: 32508,
  modelId: 176,
  modelName: '3gr D-D/A',
  groupId: 472,
  groupName: '6DO',
  classId: 2440,
  className: '6EWI',
  courseId: 2264,
  course: 'Informaticawetenschappen (2 uur)',
  grade: '6e j DO',
  periods: [
    const FakeSkoreGradebookPeriod(
      1704,
      'DW1',
      open: true,
      opens: '2026-09-18 15:30',
      timestamp: '2026-12-18T20:00:00+0100',
      note:
          'Vul hier je punten voor Dagelijks werk (periode september- '
          'oktober) in!',
    ),
  ],
  pupils: [
    const FakeSkoreGradebookPupil(1201, 'Aerts, An', 'An Aerts', number: 1),
    const FakeSkoreGradebookPupil(1202, 'Claes, Bart', 'Bart Claes', number: 2),
    const FakeSkoreGradebookPupil(
      1203,
      'Dupont, Chloé',
      'Chloé Dupont',
      number: 3,
    ),
  ],
);

/// 5BW's gradebook of 2025-2026 as captured: three closed periods, the last
/// the active one, and two pupils without a class number, one inactive.
FakeSkoreOwnGradebook fakeSkoreGradebook5BW() => FakeSkoreOwnGradebook(
  workyear: FakeSkoreWorkyear.y2025,
  id: 28998,
  modelId: 160,
  modelName: '3grD-D/A (ASOTSO)',
  groupId: 450,
  groupName: '5DG',
  classId: 2264,
  className: '5BW',
  courseId: 1766,
  course: 'Informaticawetenschappen (2 uur)',
  grade: '5e j DG',
  periods: [
    const FakeSkoreGradebookPeriod(
      1446,
      'DW1',
      open: false,
      timestamp: '2025-12-18T20:00:00+0100',
      note:
          'Vul hier je punten voor Dagelijks werk (periode september- '
          'oktober) in!',
    ),
    const FakeSkoreGradebookPeriod(
      1608,
      'DW4',
      open: false,
      timestamp: '2026-04-02T23:00:00+0200',
      note: 'Vul hier je punten voor Dagelijks werk (periode maart) in!',
    ),
    const FakeSkoreGradebookPeriod(
      1610,
      'DW5',
      open: false,
      timestamp: '2026-06-30T00:00:00+0200',
      note: 'Vul hier je punten voor Dagelijks werk (periode april - juni) in!',
    ),
  ],
  activePeriod: 2,
  pupils: [
    const FakeSkoreGradebookPupil(1301, 'Maes, Lotte', 'Lotte Maes'),
    const FakeSkoreGradebookPupil(
      1302,
      'Verbeke, Fien',
      'Fien Verbeke',
      active: false,
    ),
  ],
);

/// A fake of Skore's gradebook RPC service, served by `FakeSmartschool` to
/// logged-in requests: the user's gradebooks per school year ([gradebooks],
/// in the order of the left panel) and the school years Skore offers
/// ([workyears], [currentWorkyear]).
///
/// Every request is recorded in [requests]. A method in [answers] gets that
/// answer instead, for an answer the library cannot use; with [unusable],
/// every call gets Smartschool's error page (with HTTP 200).
class FakeSkoreGradebook {
  /// The school years Skore offers, in its order (newest first).
  final List<FakeSkoreWorkyear> workyears = [];

  /// Skore's current school year: the one of a call without `wy`.
  FakeSkoreWorkyear currentWorkyear = FakeSkoreWorkyear.y2026;

  /// The user's gradebooks of every school year, in the order of the left
  /// panel (per model, group and class).
  final List<FakeSkoreOwnGradebook> gradebooks = [];

  /// Answers that replace the fake's own, by RPC method: the HTTP status and
  /// the body.
  final Map<String, ({int status, String body})> answers = {};

  /// When true, every call is answered with Smartschool's error page (with
  /// HTTP 200) instead of data.
  bool unusable = false;

  /// The RPC calls that reached the fake, in order: the method, its
  /// parameters and the session object.
  final List<({String rpc, List<Object?> params, Map<String, Object?> session})>
  requests = [];

  /// The calls, as `method` or, with a school year, `method wy=22`.
  List<String> get calls => [
    for (final request in requests)
      [
        request.rpc,
        if (request.session['wy'] case final wy?) 'wy=$wy',
      ].join(' '),
  ];

  /// The school years and gradebooks of dartschool's captures: 2026-2027
  /// (current) with 6EWI (as captured), 6WEWI2, and two gradebooks of 5WW1
  /// (one of a course with three teachers), 2025-2026 with 5BW (as
  /// captured), and 2024-2025 without gradebooks.
  void loadSchool() {
    workyears.addAll(const [
      FakeSkoreWorkyear.y2026,
      FakeSkoreWorkyear.y2025,
      FakeSkoreWorkyear.y2024,
    ]);
    currentWorkyear = FakeSkoreWorkyear.y2026;
    gradebooks.addAll([
      fakeSkoreGradebook6EWI(),
      FakeSkoreOwnGradebook(
        workyear: FakeSkoreWorkyear.y2026,
        id: 32504,
        modelId: 176,
        modelName: '3gr D-D/A',
        groupId: 472,
        groupName: '6DO',
        classId: 2444,
        className: '6WEWI2',
        courseId: 2264,
        course: 'Informaticawetenschappen (2 uur)',
        grade: '6e j DO',
        periods: [...fakeSkoreGradebook6EWI().periods],
        pupils: [
          const FakeSkoreGradebookPupil(
            1211,
            'Goossens, Emma',
            'Emma Goossens',
            number: 1,
          ),
          const FakeSkoreGradebookPupil(
            1212,
            'Hermans, Finn',
            'Finn Hermans',
            number: 2,
          ),
        ],
      ),
      FakeSkoreOwnGradebook(
        workyear: FakeSkoreWorkyear.y2026,
        id: 34826,
        modelId: 176,
        modelName: '3gr D-D/A',
        groupId: 492,
        groupName: '5DG',
        classId: 2516,
        className: '5WW1',
        courseId: 1588,
        course: 'Digitale vaardigheden',
        periods: [...fakeSkoreGradebook6EWI().periods],
        pupils: [
          const FakeSkoreGradebookPupil(
            1221,
            'Jacobs, Gert',
            'Gert Jacobs',
            number: 1,
          ),
        ],
      ),
      FakeSkoreOwnGradebook(
        workyear: FakeSkoreWorkyear.y2026,
        id: 34582,
        modelId: 176,
        modelName: '3gr D-D/A',
        groupId: 492,
        groupName: '5DG',
        classId: 2516,
        className: '5WW1',
        courseId: 1840,
        course: 'Project 1',
        grade: '3e graad',
        teachers: const ['Dupré Céline', 'Peeters Jan', "D'Hondt Karel"],
        periods: [...fakeSkoreGradebook6EWI().periods],
        pupils: [
          const FakeSkoreGradebookPupil(
            1221,
            'Jacobs, Gert',
            'Gert Jacobs',
            number: 1,
          ),
        ],
      ),
      fakeSkoreGradebook5BW(),
    ]);
  }

  /// The gradebook with [id] of school year [workyear], or null.
  FakeSkoreOwnGradebook? gradebookWithId(int id, FakeSkoreWorkyear workyear) =>
      gradebooks
          .where((g) => g.id == id && g.workyear.id == workyear.id)
          .firstOrNull;

  ResponseBody? respond(RequestOptions options) {
    if (options.method != 'POST' ||
        options.uri.path != fakeSkoreGradebookRpcPath) {
      return null;
    }
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    final method = form['rpc_method'] ?? '';
    final params = (jsonDecode(form['rpc_params'] ?? '[]') as List)
        .cast<Object?>();
    final session = (jsonDecode(form['rpc_sessionobj'] ?? '{}') as Map)
        .cast<String, Object?>();
    requests.add((rpc: method, params: params, session: session));
    if (answers[method] case (:final status, :final body)) {
      return _json(body, status: status);
    }
    if (unusable) return _html(_errorPage);
    if (!fakeSkoreGradebookRpcMethods.contains(method)) {
      return _json('{"error":"the fake does not serve $method"}', status: 501);
    }
    // The school year of the call: `wy`, a string, else Skore's current one.
    final wy = session['wy'];
    final workyearId = wy == null ? currentWorkyear.id : int.parse('$wy');
    final workyear =
        workyears.where((y) => y.id == workyearId).firstOrNull ??
        FakeSkoreWorkyear(workyearId, '');
    return switch (method) {
      'getNavigation' => _rpc(method, _navigation(workyear)),
      'init' => _init(method, params, workyear),
      _ => _context(method, params, workyear),
    };
  }

  /// `getNavigation`'s result for [workyear]: the tree of its gradebooks, or
  /// an empty one for a school year Skore does not offer (as live for `wy`
  /// "99").
  Map<String, Object?> _navigation(FakeSkoreWorkyear workyear) {
    final offered = workyears.any((y) => y.id == workyear.id);
    final books = [
      if (offered)
        for (final gradebook in gradebooks)
          if (gradebook.workyear.id == workyear.id) gradebook,
    ];
    // Models, their groups and their classes, in the order of the books.
    final models = <int, Map<int, Map<int, List<FakeSkoreOwnGradebook>>>>{};
    for (final book in books) {
      (((models[book.modelId] ??= {})[book.groupId] ??= {})[book.classId] ??=
              [])
          .add(book);
    }
    return {
      'navigation': [
        for (final MapEntry(key: modelId, value: groups) in models.entries)
          _modelNode(
            books.firstWhere((b) => b.modelId == modelId),
            groups.values,
          ),
      ],
      'workyears': [
        for (final year in workyears) ['${year.id}', year.name],
      ],
      'currentWorkyear': '${workyear.id}',
    };
  }

  /// A model at the top of the tree: no `crum`, no `data`.
  static Map<String, Object?> _modelNode(
    FakeSkoreOwnGradebook first,
    Iterable<Map<int, List<FakeSkoreOwnGradebook>>> groups,
  ) => {
    'children': [
      for (final classes in groups)
        _groupNode(classes.values.first.first, classes.values),
    ],
    'content': _nodeContent('modellen16.gif', 'rootimg', first.modelName),
    'raw': first.modelName,
    'icon': '$_icons/modellen16.gif',
  };

  /// A group of classes, which repeats the gradebooks of its classes in its
  /// `data`, as live (the library takes them from the class nodes only).
  static Map<String, Object?> _groupNode(
    FakeSkoreOwnGradebook first,
    Iterable<List<FakeSkoreOwnGradebook>> classes,
  ) => {
    'children': [for (final books in classes) _classNode(books)],
    'content': _nodeContent('groep.gif', 'mimg', first.groupName),
    'raw': first.groupName,
    'icon': '$_icons/groep.gif',
    'crum': {
      'path': '${first.modelName}&#187;${first.groupName}',
      'ids': ['${first.modelId}', '${first.groupId}'],
    },
    'data': [
      for (final books in classes.toList().reversed)
        for (final book in books) _gradebookEntry(book),
    ],
  };

  /// A class with its gradebooks.
  static Map<String, Object?> _classNode(List<FakeSkoreOwnGradebook> books) {
    final first = books.first;
    return {
      'content': _nodeContent('klas.gif', 'clsimg', first.className),
      'raw': first.className,
      'icon': '$_icons/klas.gif',
      'crum': {
        'path':
            '${first.modelName}&#187;${first.groupName}&#187;'
            '${first.className}',
        'ids': ['${first.modelId}', '${first.groupId}', '${first.classId}'],
      },
      'data': [for (final book in books) _gradebookEntry(book)],
      'structure': [
        '${first.classId}',
        jsonEncode([
          for (final book in books)
            {
              'children': <Object?>[],
              'courseID': book.courseId,
              'extra': book.grade,
              'behaviour': '',
              'settings': {
                'visibility': 'visible',
                'count': 'count',
                'type': 'course',
              },
              'coursename': book.course,
            },
        ]),
      ],
    };
  }

  /// A gradebook in the `data` of a node.
  static Map<String, Object?> _gradebookEntry(FakeSkoreOwnGradebook book) {
    final tooltip = base64.encode(
      utf8.encode(
        '<div style="text-align:left">Dit vak wordt gegeven door:</div>'
        '<div style="text-align:left"><ul>'
        '${book.teachers.map((t) => '<li>${_text.convert(t)}</li>').join()}'
        '</ul></div>',
      ),
    );
    return {
      'content':
          '<span><img course="${book.courseId}" src="" selected="false"/>'
          '</span><span class="navigator_course" skoretooltip="true" '
          'tooltip="$tooltip" encoding="base64">'
          '${_text.convert(book.courseName)}</span>',
      'data': {
        'ownerID': '${book.id}',
        'userID': '$fakeSkoreGradebookUser',
        'classID': '${book.classId}',
        'groupID': '${book.groupId}',
        'modelID': '${book.modelId}',
        'courseID': '${book.courseId}',
        'structureID': '1564',
      },
      'coursename': book.courseName,
      'icon': 'PHN2Zy8+',
      'iconType': 'svg',
      'part': book.teachers,
      'colleagues': [
        {
          'id': '$fakeSkoreGradebookUser',
          'userPictureUrl': '/smsc/img/fake/initials_JP.png',
          'name': 'Peeters Jan',
          'shared': [
            {
              'userId': '0',
              'ownerId': '0',
              'classcourse': '${book.className}/${book.course}',
            },
          ],
        },
      ],
    };
  }

  /// `init(courses, owners, userID, pathIds, 0, 0)` for the gradebook in
  /// `owners` of [workyear]. One the fake does not have is answered with
  /// HTTP 400, which no test expects: the library sends only gradebooks of
  /// `getNavigation`.
  ResponseBody _init(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final book = _owner(params, 1, workyear);
    if (book == null) {
      return _json('{"error":"the fake cannot init $params"}', status: 400);
    }
    final rows = {
      'orientation': 'byColumn',
      'rowHeader': {
        'sort': [
          'clavg_${book.classId}',
          for (final pupil in book.pupils) 'pupil_${pupil.id}_${book.classId}',
        ],
      },
      'colHeader': {
        'sort': [0],
      },
      'stream': [
        {
          'c': 0,
          'r': 'clavg_${book.classId}',
          'v': '${book.className} : Klasgemiddelde',
        },
        for (final pupil in book.pupils)
          {
            'c': 0,
            'r': 'pupil_${pupil.id}_${book.classId}',
            'v': _pupilCell(pupil),
          },
      ],
    };
    return _rpc(method, {
      'left_0': rows,
      'left_1': rows,
      'left_2': rows,
      'periods': [
        for (final period in book.periods)
          {
            'name': period.name,
            'fullname': period.name,
            'id': '${period.id}',
            'info': period.info,
            'virtual': '0',
            'scope': '1',
            'open': period.open ? 1 : 0,
            'timestamp': period.timestamp,
            'lockIcon': period.open ? 0 : 1,
            'categoryMode': 1,
          },
      ],
      'reports': <Object?>[],
      'activePeriodE': book.activePeriod,
      'activePeriodP': -1,
      'activeReport': 0,
      'projectAdmin': 1,
      'classesMap': {
        '_${book.groupId}': ['${book.classId}'],
      },
      'skoreClasses': {'_${book.classId}': book.className},
      'virtualClasses': null,
      'coursesMap': {'_${book.courseId}': book.course},
      'ownerMap': [
        {
          'courseID': '${book.courseId}',
          'groupID': '${book.groupId}',
          'coursename': book.course,
          'ownerID': '${book.id}',
          'classID': '${book.classId}',
        },
      ],
      'allowEvaluationTypes': null,
      'wystring': workyear.name.replaceFirst('-', ' - '),
      'isRestrictedAccess': 0,
    });
  }

  /// `getGradebookContext(pathIds, courses, owners, userID, periodId, 0,
  /// wy)` for the gradebook in `owners` of [workyear].
  ResponseBody _context(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final book = _owner(params, 2, workyear);
    if (book == null) {
      return _json('{"error":"the fake cannot answer $params"}', status: 400);
    }
    return _rpc(method, {
      'writable': book.writable ? 1 : 0,
      'coordinator': book.coordinator ? 1 : 0,
      'modelId': book.modelId,
      'groupId': book.groupId,
      'classId': book.classId,
      'periodId': params[4],
      'courses': [book.courseId],
      'owners': [book.id],
      'teacherId': fakeSkoreGradebookUser,
      'virtualId': 0,
      'restriction': 0,
    });
  }

  /// The gradebook of [workyear] whose id is the only item of the list at
  /// [index] of [params] (`owners`, ids as strings), or null.
  FakeSkoreOwnGradebook? _owner(
    List<Object?> params,
    int index,
    FakeSkoreWorkyear workyear,
  ) {
    final owners = params.length > index ? params[index] : null;
    if (owners is! List || owners.length != 1) return null;
    final id = int.tryParse('${owners.single}');
    return id == null ? null : gradebookWithId(id, workyear);
  }

  /// The cell of [pupil]'s row: a span with the name in its text (after the
  /// class number, or `-`) and first name first in base64 as its
  /// `alternate`, greyed out (`gbc_hidden`) for an inactive pupil.
  static String _pupilCell(FakeSkoreGradebookPupil pupil) {
    final hidden = pupil.active ? '' : 'class="gbc_hidden"  ';
    final tooltip = base64.encode(
      utf8.encode(
        '<div style="text-align:center;"><img class="pupil_picture" '
        'src="/smsc/img/fake/initials.png" /><div style="margin-top:10px;">'
        '${_text.convert(pupil.displayName)}</div></div>',
      ),
    );
    final alternate = base64.encode(utf8.encode(pupil.displayName));
    final number = pupil.number == null ? '-' : '${pupil.number}. ';
    return '<span ${hidden}tooltip="$tooltip" encoding="base64"  '
        'skoretooltip="true" avatarhash="4069_00000000-0000-0000-0000-'
        '${pupil.id.toString().padLeft(12, '0')}" alternate="$alternate">'
        '$number ${_text.convert(pupil.name)}</span><span '
        'style="position:absolute; right:20px;top:2px;"></span>';
  }

  static const _icons = '/modules/Skore/themes/default/images/skoreicons';

  /// A tree node's content: an icon, `&nbsp;` and the name.
  static String _nodeContent(String icon, String alt, String name) =>
      '<img src="$_icons/$icon" border="0" alt="$alt" height="16" '
      'width="16" align="absmidle"/>&nbsp;${_text.convert(name)}';

  static const _text = HtmlEscape(HtmlEscapeMode.element);

  /// An RPC answer of Skore to [method] with [result], as in the captures.
  static ResponseBody _rpc(String method, Object? result) => _json(
    jsonEncode({
      'result': result,
      'session': 1,
      'method': method,
      'timelimit': 0,
      'limitInfo': null,
    }),
  );

  static ResponseBody _json(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );

  static ResponseBody _html(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
    },
  );
}

/// Smartschool's generic error page.
const _errorPage =
    '<!DOCTYPE html><html><head><title></title></head><body>'
    '<div id="#smscMain"><h1>Oeps, er ging iets mis</h1></div></body></html>';
