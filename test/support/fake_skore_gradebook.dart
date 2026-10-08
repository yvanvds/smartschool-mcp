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
//   - getEvaluations(periodID, userID, courses, groupID, classID, pathIds)
//     (#141, dartschool#149): the evaluations of a period (`head`) and a
//     grade cell per pupil and evaluation (`details.stream`, HTML with the
//     grade as `raw` and a `gbc_message` marker for feedback), with the
//     class and group averages and the rows of another class of the group
//     that Skore sends along, as in dartschool's
//     `test/skore_gradebook_evaluations_test.dart`. A period without
//     evaluations gets an empty `head` and the stream `1`, as live.
//   - The "new evaluation" dialog and its save (#142, dartschool#150), as in
//     dartschool's `test/skore_gradebook_create_test.dart`:
//     getNewEvalDialogBox(0, owners, groupID, periodID), the course
//     (`[["2264", "Informaticawetenschappen (2 uur)"]]`);
//     getPosComponents(0, periodID, groupID, courseID, pathIds), the
//     components (`[[0, "geen"], ["2", "DW"]]`); and saveEvaluation with its
//     20 parameters, which it carries out as the live Skore did: the new
//     evaluation is listed from then on in column A of its period, with what
//     was sent (`public` as sent, `short` null for `""`), and the answer is
//     `{"state":1,"incumul":0,"evaluationID":<id>,"refID":<id>,
//     "importData":null}`.
// The school year goes as `wy` (a string) in the session object; without
// it, Skore answers for its current school year. Class, group, model,
// course, gradebook and period ids and names are those of the captures;
// pupils, teachers, evaluations and feedback are obvious fakes.
//
// Next to the RPC service, it serves the feedback of a pupil on an
// evaluation from Skore's REST API (#141), as the feedback panel reads it:
// `GET /skore/api/v1/gradebook/feedback/{ss}_{evaluationId}/student/
// {ss}_{pupilId}_0/class/{ss}_{classId}/teacher/{ss}_{userId}_0/context/
// {modelId}_{groupId}_{classId}`, a list in the shape of dartschool's
// captures (`test/skore_gradebook_feedback_test.dart`), `ss` being
// [fakeSkoreGradebookPlatform].
//
// It serves only [fakeSkoreGradebookRpcMethods] and answers any other with
// HTTP 501. The later gradebook tools add theirs (saveGrade, the feedback
// POST): a method of the library's allowlist
// (`SkoreGradebookService.rpcMethods`) and an answer in the shape of
// dartschool's capture for it.

/// Skore's gradebook RPC service, behind `/SkoreGradebook`.
const fakeSkoreGradebookRpcPath = '/modules/Skore/backend/gradebook/rpc.php';

/// The RPC methods of [fakeSkoreGradebookRpcPath] the fake serves.
const fakeSkoreGradebookRpcMethods = {
  'getNavigation',
  'init',
  'getGradebookContext',
  'getEvaluations',
  'getNewEvalDialogBox',
  'getPosComponents',
  'saveEvaluation',
};

/// Skore's REST API of the feedback of a pupil on an evaluation.
const fakeSkoreFeedbackPath = '/skore/api/v1/gradebook/feedback/';

/// The Smartschool user id of the fake's account (`12_345_0` on the fake
/// Smartschool's pages): the teacher of the gradebooks.
const fakeSkoreGradebookUser = 345;

/// The platform of the fake's account (`12` of `12_345_0`): Skore's `ss`
/// in the ids of its REST API.
const fakeSkoreGradebookPlatform = 12;

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

/// An evaluation (a column of grades) in a period of a gradebook, as
/// `getEvaluations` gives it (#141): its `head` entry and the cells of the
/// gradebook's pupils. Skore gives it the column letter of its place in the
/// period (`A` for the first).
class FakeSkoreEvaluation {
  FakeSkoreEvaluation(
    this.id,
    this.title, {
    required this.date,
    this.short,
    this.max = 20,
    this.componentId = 2,
    this.component = 'DW',
    this.evaltype = 1,
    this.planner = false,
    this.public = '0',
    this.publicDateTime = '',
    Map<int, String>? grades,
    Map<int, List<FakeSkoreFeedback>>? feedback,
    Set<int>? withoutCell,
  }) : grades = grades ?? {},
       feedback = feedback ?? {},
       withoutCell = withoutCell ?? {};

  /// Skore's `refID` and `evaluationID`.
  final int id;
  final String title;

  /// The short name, `null` for none (as Skore gives it).
  final String? short;

  /// The day, as Skore writes it (`2026-09-30`).
  final String date;

  /// The highest grade (`max`): a number, or null for none.
  final Object? max;

  /// The component: `componentID` 2 and `component` `DW` as captured, `0`
  /// and `''` for none.
  final int componentId;
  final String component;

  /// `evaltype`: 1 points, 2 a scale.
  final int evaltype;

  /// Whether it comes from the planner (`isPlannerEval` 1).
  final bool planner;

  /// Skore's `public` (`"1"` or `"0"`) and `publicdatetime` (a time in
  /// Belgium without an offset, `2026-10-09T08:00:00`, or `""`).
  String public;
  String publicDateTime;

  /// The grade of each pupil as Skore stores it (`79`, `15.5`), by pupil
  /// id; a pupil without one has an empty cell.
  final Map<int, String> grades;

  /// The feedback on it per pupil id, in the order written: the REST API's
  /// answer, and the cell's `gbc_message` marker when there is some.
  final Map<int, List<FakeSkoreFeedback>> feedback;

  /// The pupils of the gradebook whose cell Skore leaves out (not seen
  /// live).
  final Set<int> withoutCell;
}

/// A feedback text on an evaluation for a pupil, as Skore's REST API gives
/// it (#141).
class FakeSkoreFeedback {
  const FakeSkoreFeedback(
    this.id,
    this.text, {
    this.teacherId = fakeSkoreGradebookUser,
    this.teacherName = 'Jan Peeters',
    this.createdAt = '2026-10-08T09:49:36+02:00',
    this.changedAt,
    this.attachments = const [],
    this.canEdit = true,
  });

  /// A UUID.
  final String id;
  final String text;

  /// The Smartschool user id of the one who wrote it, and the name first
  /// name first.
  final int teacherId;
  final String teacherName;

  /// When it was written and last changed, with the offset
  /// (`2026-10-08T09:49:36+02:00`); [changedAt] is [createdAt] when null.
  final String createdAt;
  final String? changedAt;

  /// The file names of its attachments.
  final List<String> attachments;

  /// Skore's `capabilities.can_edit`.
  final bool canEdit;
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
    Map<int, List<FakeSkoreEvaluation>>? evaluations,
    List<List<Object>>? components,
  }) : periods = periods ?? [],
       pupils = pupils ?? [],
       evaluations = evaluations ?? {},
       components =
           components ??
           [
             [0, 'geen'],
             ['2', 'DW'],
           ];

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

  /// Pupils with a cell in `getEvaluations` but no row in `init` (not seen
  /// live).
  final List<FakeSkoreGradebookPupil> cellsOnly = [];

  /// Whether `getGradebookContext` answers `writable` 1.
  bool writable;

  /// Whether `getGradebookContext` answers `coordinator` 1.
  bool coordinator;

  /// The evaluations of each period, by period id, in Skore's order (column
  /// `A` first); a period without any has none here.
  final Map<int, List<FakeSkoreEvaluation>> evaluations;

  /// The components a new evaluation can count for, in every period, as
  /// `getPosComponents` gives them (and every evaluation's `posComps`): an
  /// id (`0` as a number, the others as strings) and a short name.
  final List<List<Object>> components;

  /// The evaluation with [id] in any period, or null.
  FakeSkoreEvaluation? evaluationWithId(int id) => [
    for (final list in evaluations.values) ...list,
  ].where((e) => e.id == id).firstOrNull;

  /// The course as the left panel names it, with the grade.
  String get courseName => grade.isEmpty ? course : '$course ($grade)';
}

/// When the scheduled evaluation of [fakeSkoreGradebook6EWI] is published:
/// a time in Belgium (CET) that stays to come, so that the library, which
/// compares it with the clock, finds it scheduled.
const fakeSkoreScheduledAt = '2099-01-11T08:00:00';

/// A colleague's Smartschool user id, who wrote feedback in
/// [fakeSkoreGradebook6EWI].
const fakeSkoreColleague = 346;

/// 6EWI's gradebook of 2026-2027 as captured: one open period, three
/// pupils with a class number, writable. Its period DW1 has three
/// evaluations, in the shape of dartschool's captures of #149: `Toets 1`
/// (column A, not published, no grades, feedback without a grade for Bart),
/// `Python scripts schrijven` (B, scheduled for [fakeSkoreScheduledAt],
/// grades 79, 15.5 and none; feedback for An, and for Bart from the user and
/// from a colleague with an attachment) and `Lussen` (C, without a
/// component, published since 2026-10-01 08:00, three grades).
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
  evaluations: {
    1704: [
      FakeSkoreEvaluation(
        500003,
        'Toets 1',
        date: '2026-10-08',
        feedback: {
          1202: [
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000003',
              'Feedback zonder cijfer.',
              createdAt: '2026-10-08T11:20:00+02:00',
            ),
          ],
        },
      ),
      FakeSkoreEvaluation(
        500001,
        'Python scripts schrijven',
        short: 'toets-python',
        date: '2026-09-30',
        max: 100,
        public: '1',
        publicDateTime: fakeSkoreScheduledAt,
        grades: {1201: '79', 1202: '15.5'},
        feedback: {
          1201: [
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000004',
              'Goed gewerkt, ga zo door.',
            ),
          ],
          1202: [
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000001',
              'Eerste opmerking.\nLet op de foutafhandeling.',
            ),
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000002',
              'Tweede opmerking.',
              teacherId: fakeSkoreColleague,
              teacherName: 'Céline Dupré',
              createdAt: '2026-10-08T10:02:11+02:00',
              changedAt: '2026-10-08T10:15:00+02:00',
              attachments: ['verbetering.pdf'],
              canEdit: false,
            ),
          ],
        },
      ),
      FakeSkoreEvaluation(
        500002,
        'Lussen',
        date: '2026-09-23',
        componentId: 0,
        component: '',
        public: '1',
        publicDateTime: '2026-10-01T08:00:00',
        grades: {1201: '14', 1202: '17', 1203: '12'},
      ),
    ],
  },
);

/// 5BW's gradebook of 2025-2026 as captured: three closed periods, the last
/// the active one, and two pupils without a class number, one inactive.
/// DW1 has a published evaluation, DW4 none (as live), DW5 a published one
/// from the planner.
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
  evaluations: {
    1446: [
      FakeSkoreEvaluation(
        400101,
        'Databanken',
        date: '2025-10-15',
        public: '1',
        publicDateTime: '2025-10-16T08:00:00',
        grades: {1301: '14'},
        feedback: {
          1301: [
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000101',
              'Sterk verbeterd.',
              createdAt: '2025-10-16T07:30:00+02:00',
            ),
          ],
        },
      ),
    ],
    1610: [
      FakeSkoreEvaluation(
        400201,
        'Eindproject',
        date: '2026-06-10',
        max: 50,
        planner: true,
        public: '1',
        publicDateTime: '2026-06-11T08:00:00',
        grades: {1301: '41', 1302: '30'},
      ),
    ],
  },
);

/// A fake of Skore's gradebook RPC service, served by `FakeSmartschool` to
/// logged-in requests: the user's gradebooks per school year ([gradebooks],
/// in the order of the left panel) and the school years Skore offers
/// ([workyears], [currentWorkyear]); and of the feedback of Skore's REST API
/// (`GET` [fakeSkoreFeedbackPath]...), from the evaluations of the
/// gradebooks.
///
/// Every RPC request is recorded in [requests] (the saves of a new
/// evaluation also in [evaluationSaves]), every feedback read in
/// [feedbackReads]. A method in [answers] gets that answer instead (a save
/// is then not carried out), and a feedback read [feedbackAnswer], for an
/// answer the library cannot use; with [unusable], every call gets
/// Smartschool's error page (with HTTP 200). A save of a new evaluation can
/// lose its answer after it was carried out ([saveAnswerLost]), and
/// [onEvaluationSaved] can change how Skore lists the new evaluation.
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

  /// The answer that replaces the fake's own to every feedback read: the
  /// HTTP status and the body.
  ({int status, String body})? feedbackAnswer;

  /// When true, every call is answered with Smartschool's error page (with
  /// HTTP 200) instead of data.
  bool unusable = false;

  /// The RPC calls that reached the fake, in order: the method, its
  /// parameters and the session object.
  final List<({String rpc, List<Object?> params, Map<String, Object?> session})>
  requests = [];

  /// The id the next new evaluation gets (Skore's `refID`).
  int nextEvaluationId = 500100;

  /// When true, a `saveEvaluation` is carried out, but answered with HTTP
  /// 500 and Smartschool's error page, as a save whose answer was lost.
  bool saveAnswerLost = false;

  /// Called with the gradebook and the new evaluation right after a
  /// `saveEvaluation` was carried out (it is listed from then on): to list
  /// it otherwise than sent, such as public, or not at all.
  void Function(FakeSkoreOwnGradebook book, FakeSkoreEvaluation created)?
  onEvaluationSaved;

  /// The parameters of every `saveEvaluation` that reached the fake, in
  /// order, also those [answers] answered (and that were not carried out).
  List<List<Object?>> get evaluationSaves => [
    for (final request in requests)
      if (request.rpc == 'saveEvaluation') request.params,
  ];

  /// The feedback reads of the REST API that reached the fake, in order:
  /// the evaluation and the pupil (from the path, null when it is not in the
  /// form the library sends), and the path.
  final List<({int? evaluationId, int? pupilId, String path})> feedbackReads =
      [];

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
    final path = options.uri.path;
    if (options.method == 'GET' && path.startsWith(fakeSkoreFeedbackPath)) {
      return _feedback(path);
    }
    if (options.method != 'POST' || path != fakeSkoreGradebookRpcPath) {
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
      'getEvaluations' => _evaluations(method, params, workyear),
      'getNewEvalDialogBox' => _newEvaluationCourses(method, params, workyear),
      'getPosComponents' => _components(method, params, workyear),
      'saveEvaluation' => _saveEvaluation(method, params, workyear),
      _ => _context(method, params, workyear),
    };
  }

  /// `getNewEvalDialogBox(0, owners, groupID, periodID)` for the gradebook
  /// in `owners` of [workyear]: its course, `[["2264",
  /// "Informaticawetenschappen (2 uur)"]]` as captured.
  ResponseBody _newEvaluationCourses(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final book = _owner(params, 1, workyear);
    if (book == null) {
      return _json('{"error":"the fake cannot answer $params"}', status: 400);
    }
    return _rpc(method, [
      ['${book.courseId}', book.course],
    ]);
  }

  /// `getPosComponents(0, periodID, groupID, courseID, pathIds)` for the
  /// period of the gradebook of [workyear] with that course and class (the
  /// last of `pathIds`): its [FakeSkoreOwnGradebook.components].
  ResponseBody _components(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final periodId = params.length > 1 ? int.tryParse('${params[1]}') : null;
    final courseId = params.length > 3 ? int.tryParse('${params[3]}') : null;
    final path = params.length > 4 ? params[4] : null;
    final classId = path is List && path.length == 3
        ? int.tryParse('${path.last}')
        : null;
    final book = gradebooks
        .where(
          (g) =>
              g.workyear.id == workyear.id &&
              g.courseId == courseId &&
              g.classId == classId &&
              g.periods.any((p) => p.id == periodId),
        )
        .firstOrNull;
    if (book == null) {
      return _json('{"error":"the fake cannot answer $params"}', status: 400);
    }
    return _rpc(method, book.components);
  }

  /// `saveEvaluation(evaluationID, ownerID, userID, courseID, coursename,
  /// title, short, periodID, date, max, compName, componentID, public,
  /// chain, pathIds, contentType, contentTypeName, publicdatetime,
  /// importParams, evalType)` for a new evaluation (`evaluationID` 0) in a
  /// period of the gradebook `ownerID` of [workyear]: carried out as the
  /// live Skore did, the new evaluation first in its period (column A). A
  /// save the fake cannot carry out (another gradebook or period, an
  /// evaluation that is not new) is answered with HTTP 400, which no test
  /// expects.
  ResponseBody _saveEvaluation(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final ownerId = params.length == 20 ? int.tryParse('${params[1]}') : null;
    final book = ownerId == null ? null : gradebookWithId(ownerId, workyear);
    final periodId = params.length == 20 ? params[7] : null;
    if (book == null ||
        params[0] != 0 ||
        periodId is! int ||
        !book.periods.any((p) => p.id == periodId)) {
      return _json('{"error":"the fake cannot save $params"}', status: 400);
    }
    final short = '${params[6]}';
    final componentId = params[11] == 0 ? 0 : int.parse('${params[11]}');
    final created = FakeSkoreEvaluation(
      nextEvaluationId++,
      '${params[5]}',
      short: short.isEmpty ? null : short,
      date: '${params[8]}',
      max: int.parse('${params[9]}'),
      componentId: componentId,
      // What Skore lists for "geen" was not seen; the fake lists no
      // component, as for an evaluation without one.
      component: componentId == 0 ? '' : '${params[10]}',
      public: '${params[12]}',
      publicDateTime: '${params[17]}',
    );
    (book.evaluations[periodId] ??= []).insert(0, created);
    onEvaluationSaved?.call(book, created);
    if (saveAnswerLost) {
      return ResponseBody.fromString(
        '{"message":"Internal Server Error"}$_errorPage',
        500,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
        },
      );
    }
    return _rpc(method, {
      'state': 1,
      'incumul': 0,
      'evaluationID': created.id,
      'refID': created.id,
      'importData': null,
    });
  }

  /// `getEvaluations(periodID, userID, courses, groupID, classID, pathIds)`
  /// for the period of the gradebook of [workyear] with that course and
  /// class: the evaluations of the period and the cells of its pupils, in
  /// the shape of dartschool's capture. A period of another gradebook is
  /// answered with HTTP 400, which no test expects: the tools send only a
  /// period of the gradebook's own.
  ResponseBody _evaluations(
    String method,
    List<Object?> params,
    FakeSkoreWorkyear workyear,
  ) {
    final periodId = params.isEmpty ? null : int.tryParse('${params[0]}');
    final courses = params.length > 2 ? params[2] : null;
    final courseId = courses is List && courses.length == 1
        ? int.tryParse('${courses.single}')
        : null;
    final classId = params.length > 4 ? int.tryParse('${params[4]}') : null;
    final book = gradebooks
        .where(
          (g) =>
              g.workyear.id == workyear.id &&
              g.courseId == courseId &&
              g.classId == classId &&
              g.periods.any((p) => p.id == periodId),
        )
        .firstOrNull;
    if (book == null) {
      return _json('{"error":"the fake cannot answer $params"}', status: 400);
    }
    final evaluations = book.evaluations[periodId] ?? const [];
    const table = {'orientation': 'byColumn'};
    if (evaluations.isEmpty) {
      // A period without evaluations, as live: an empty head, the stream 1.
      return _rpc(method, {
        'head': <Object?>[],
        'max': {
          ...table,
          'rowHeader': {
            'sort': [0],
          },
          'colHeader': {'sort': <Object?>[]},
          'stream': 1,
        },
        'details': {
          ...table,
          'rowHeader': {'sort': <Object?>[]},
          'colHeader': {'sort': <Object?>[]},
          'stream': 1,
        },
        'periodStatus': 1,
        'evalType': 1,
        'archive': <Object?>[],
      });
    }
    final columns = {
      for (final (index, evaluation) in evaluations.indexed)
        evaluation.id: String.fromCharCode('A'.codeUnitAt(0) + index),
    };
    // A pupil of another class of the group, whose row Skore sends along
    // with another gradebook, `p` [1, 0, 0, owner, -1] and no `raw`.
    final otherRow = 'pupil_1999_${book.classId + 2}';
    return _rpc(method, {
      'head': [
        for (final evaluation in evaluations)
          _head(evaluation, book, periodId!, columns[evaluation.id]!),
      ],
      'max': {
        ...table,
        'rowHeader': {
          'sort': [0],
        },
        'colHeader': {
          'sort': [for (final evaluation in evaluations) '${evaluation.id}'],
        },
        'stream': [
          for (final evaluation in evaluations)
            {
              'c': '${evaluation.id}',
              'r': 0,
              'v': [
                evaluation.max,
                '${evaluation.id}',
                columns[evaluation.id],
                evaluation.evaltype,
                '',
                '',
                '',
                evaluation.public,
              ],
              'w': 'maxcell',
            },
        ],
      },
      'details': {
        ...table,
        'rowHeader': {'sort': <Object?>[]},
        'colHeader': {'sort': <Object?>[]},
        'stream': [
          for (final evaluation in evaluations) ...[
            for (final pupil in [...book.pupils, ...book.cellsOnly])
              if (!evaluation.withoutCell.contains(pupil.id))
                {
                  'c': '${evaluation.id}',
                  'r': 'pupil_${pupil.id}_${book.classId}',
                  'v': _gradeCell(
                    evaluation.grades[pupil.id],
                    evaluation.feedback[pupil.id] ?? const [],
                  ),
                  'p': [1, 0, '${evaluation.id}', '${book.id}', evaluation.id],
                },
            {
              'c': '${evaluation.id}',
              'r': 'clavg_${book.classId}',
              'v': _gradeCell(_average(evaluation), const []),
              'p': [0],
            },
            {
              'c': '${evaluation.id}',
              'r': 'gravg_${book.groupId}',
              'v': _gradeCell(_average(evaluation), const []),
              'p': [0],
            },
          ],
          for (final evaluation in evaluations)
            {
              'c': '${evaluation.id}',
              'r': otherRow,
              'v':
                  '<div class="gbc" ></div><div class="gbc_cell_header">'
                  '$_noMessage</div>$_presence',
              'p': [1, 0, 0, '${book.id - 4}', -1],
            },
        ],
      },
      'periodStatus': 1,
      'evalType': 1,
      'archive': <Object?>[],
    });
  }

  /// The `head` entry of [evaluation] in period [periodId] of [book], in
  /// column [column].
  static Map<String, Object?> _head(
    FakeSkoreEvaluation evaluation,
    FakeSkoreOwnGradebook book,
    int periodId,
    String column,
  ) => {
    'formula': '',
    'title': evaluation.title,
    'short': evaluation.short,
    'date': evaluation.date,
    'componentID': evaluation.componentId,
    'component': evaluation.component,
    'periodID': periodId,
    'courseID': '${book.courseId}',
    'coursename': book.course,
    'public': evaluation.public,
    'publicdatetime': evaluation.publicDateTime,
    'max': evaluation.max,
    'catID': null,
    'catDescr': null,
    'etodID': '',
    'refID': '${evaluation.id}',
    'colID': column,
    'evaltype': evaluation.evaltype,
    'evaluationID': '${evaluation.id}',
    'cumulate': '',
    'cumulateGlobal': '',
    'projectID': '',
    'color': '#ffffff',
    'virtual': '0',
    'contentType': '',
    'contentTypeName': '',
    'ownerID': '${book.id}',
    'externeUuid': '',
    'isPlannerEval': evaluation.planner ? 1 : 0,
    'plaId': '',
    'pleType': '',
    'realCourseID': book.courseId,
    'posComps': book.components,
    'groupID': book.groupId,
  };

  /// The average of the numeric grades of [evaluation] with one decimal
  /// (`47.3`), or null without any.
  static String? _average(FakeSkoreEvaluation evaluation) {
    final values = [
      for (final grade in evaluation.grades.values) ?double.tryParse(grade),
    ];
    if (values.isEmpty) return null;
    final sum = values.reduce((a, b) => a + b);
    return (sum / values.length).toStringAsFixed(1);
  }

  /// A grade cell as Skore gives it: the grade as `raw` (with a decimal
  /// point) and as text (with a decimal comma), and, when the pupil has
  /// [feedback], the `gbc_message` marker whose tooltip joins the texts.
  static String _gradeCell(String? grade, List<FakeSkoreFeedback> feedback) {
    final raw = grade ?? '';
    final tooltip = base64.encode(
      utf8.encode(
        '<ul style="text-align:left;margin:0px;padding:12px;"><li>'
        '${_text.convert(feedback.map((f) => f.text).join(', '))}</li></ul>',
      ),
    );
    final marker = feedback.isEmpty
        ? _noMessage
        : '<span onmousedown="skore.gbc.onCellMessage();" '
              'class="gbc_message_place gbc_message" skoretooltip="true" '
              'tooltip="$tooltip" encoding="base64">&nbsp;&nbsp;</span>';
    return '<div class="gbc" raw="${_attribute.convert(raw)}">'
        '${_text.convert(raw.replaceAll('.', ','))}</div>'
        '<div class="gbc_cell_header">$marker</div>$_presence';
  }

  static const _noMessage =
      '<span onmousedown="skore.gbc.onCellMessage();" '
      'class="gbc_message_place" >&nbsp;&nbsp;</span>';

  static const _presence =
      '<div class="gbc_presence "><div></div><div></div></div>';

  static final _feedbackRead = RegExp(
    r'^/skore/api/v1/gradebook/feedback/(\d+)_(\d+)/student/(\d+)_(\d+)_0/'
    r'class/(\d+)_(\d+)/teacher/(\d+)_(\d+)_0/context/(\d+)_(\d+)_(\d+)$',
  );

  /// The answer to a feedback read at [path]: the feedback of the pupil on
  /// the evaluation, in the order written, as Skore's REST API lists it
  /// (`[]` for none). A path of another platform, user, class or context
  /// than the evaluation's is answered with HTTP 400, which no test
  /// expects.
  ResponseBody _feedback(String path) {
    final match = _feedbackRead.firstMatch(path);
    final ids = [
      for (var i = 1; i <= (match?.groupCount ?? 0); i++)
        int.parse(match!.group(i)!),
    ];
    feedbackReads.add((
      evaluationId: ids.isEmpty ? null : ids[1],
      pupilId: ids.isEmpty ? null : ids[3],
      path: path,
    ));
    if (feedbackAnswer case (:final status, :final body)) {
      return _json(body, status: status);
    }
    if (unusable) return _html(_errorPage);
    if (ids.isEmpty) return _problem(400, 'the fake cannot read $path');
    final [
      ss1,
      evaluationId,
      ss2,
      pupilId,
      ss3,
      classId,
      ss4,
      userId,
      modelId,
      groupId,
      contextClassId,
    ] = ids;
    final book = gradebooks
        .where(
          (g) =>
              g.classId == classId &&
              g.modelId == modelId &&
              g.groupId == groupId &&
              g.classId == contextClassId &&
              g.evaluationWithId(evaluationId) != null,
        )
        .firstOrNull;
    if ({ss1, ss2, ss3, ss4}.single != fakeSkoreGradebookPlatform ||
        userId != fakeSkoreGradebookUser ||
        book == null) {
      return _problem(400, 'the fake cannot read $path');
    }
    final evaluation = book.evaluationWithId(evaluationId)!;
    final pupil = book.pupils.where((p) => p.id == pupilId).firstOrNull;
    return _json(
      jsonEncode([
        for (final feedback in evaluation.feedback[pupilId] ?? const [])
          _feedbackJson(feedback, evaluationId, pupilId, pupil),
      ]),
    );
  }

  /// [feedback] as Skore's REST API gives it.
  static Map<String, Object?> _feedbackJson(
    FakeSkoreFeedback feedback,
    int evaluationId,
    int pupilId,
    FakeSkoreGradebookPupil? pupil,
  ) {
    const ss = fakeSkoreGradebookPlatform;
    Map<String, Object?> person(int id, String firstNameFirst) {
      final words = firstNameFirst.split(' ');
      final lastNameFirst = [...words.skip(1), words.first].join(' ');
      return {
        'id': '${ss}_${id}_0',
        'name': {
          'startingWithFirstName': firstNameFirst,
          'startingWithLastName': lastNameFirst,
        },
        'pictureHash': 'fake',
        'pictureUrl': '/smsc/img/fake/initials.png',
        'sort': lastNameFirst.toLowerCase(),
        'deleted': false,
      };
    }

    return {
      'id': feedback.id,
      'evaluationId': '${ss}_$evaluationId',
      'student': person(pupilId, pupil?.displayName ?? 'Onbekende Leerling'),
      'teacher': person(feedback.teacherId, feedback.teacherName),
      'text': feedback.text,
      'createdAt': feedback.createdAt,
      'changedAt': feedback.changedAt ?? feedback.createdAt,
      'attachments': [
        for (final (index, name) in feedback.attachments.indexed)
          {
            'id': 'att-${index + 1}',
            'name': name,
            'type': 'OTHER',
            'size': 1234,
            'downloadUrl': '/fake/download',
          },
      ],
      'capabilities': {'can_read': true, 'can_edit': feedback.canEdit},
    };
  }

  /// An error answer of Skore's REST API.
  static ResponseBody _problem(int status, String detail) => _json(
    jsonEncode({'title': 'Bad Request', 'detail': detail}),
    status: status,
  );

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
  static const _attribute = HtmlEscape(HtmlEscapeMode.attribute);

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
