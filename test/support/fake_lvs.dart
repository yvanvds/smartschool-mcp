import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

// A fake of Smartschool's pupil tracking system (LVS, "leerlingvolgsysteem",
// `/?module=LVS`): the reads of the library's `LvsService`, answered with
// the hand-written fixtures of `test/fixtures/lvs/` (#153).
//
// The LVS holds the most sensitive data Smartschool has. No answer of a live
// LVS is ever used here, also not trimmed: the fixtures are copies of the
// library's own (yvanvds/dartschool, `test/fixtures/lvs/`, written by hand
// in the shapes of #160) or written by hand in those shapes, with the fakes
// of `test/fixtures/lvs/FAKES.md` only. `test/lvs_fixtures_guard_test.dart`
// checks them. A new kind of answer (the results of #155, say) goes in a
// folder of its own under `test/fixtures/lvs/`, registered in that guard's
// `lvsFixtureKinds`, and gets a [FakeLvsRead] and a case in
// [FakeLvs.respond]; a command of the XML dispatcher gets an entry in
// `_commands` too (the notes of #154 are those). The results of #155 are
// GETs of the results app, answered only with its headers, as the LVS
// does. The support plans of #156 are form POSTs to the LVS's JSON
// dispatchers, answered with JSON as text, as the LVS does.

/// The folder of the fixtures the fake answers with.
const fakeLvsFixtures = 'test/fixtures/lvs';

/// A pupil of the fixtures: their pupil id and the id of their class.
typedef FakeLvsPupil = ({int pupilId, int classId});

/// Jan Janssens of class 1A: the one pupil a search for "janssens" finds,
/// with a file whose notes hold something (sub-categories, a heading, new
/// notes) and results, and attendance in the morning and the afternoon.
const fakeLvsJan = (pupilId: 900001, classId: 900101);

/// Marie Peeters of class 2B: found with Lars by "peeters", with a file
/// without form tutors whose support plans and absences hold something (the
/// absences something new), but not its note category, and attendance in
/// the morning only.
const fakeLvsMarie = (pupilId: 900002, classId: 900102);

/// Lars Peeters of class 3C: found by "peeters", but the LVS answers his
/// file with its placeholder pupil, as for a pupil it does not know.
const fakeLvsLars = (pupilId: 900005, classId: 900103);

/// Noor Van den Broeck of class 3C: found by no search, with a file without
/// a part of support plans, as at a school that keeps educational needs in
/// its note categories instead (#156).
const fakeLvsNoor = (pupilId: 900003, classId: 900103);

/// The reads of `LvsService` the fake answers.
enum FakeLvsRead {
  /// The root of the class tree (`checkAccess`):
  /// `POST /?module=LVS&file=treeBuilder` with `id`.
  tree,

  /// The pupil search (`searchPupils`): `GET /LVS/Spotlight?searchVal=`.
  search,

  /// A pupil's file (`getPupilFile`):
  /// `GET /LVS/Spotlight/<pupil id>?classID=<class id>`.
  pupilFile,

  /// A pupil's attendance today (`getPupilFile`, after the file):
  /// `POST /LVS/Pupilxhr/getStatusInfo` with `pupilID`.
  todayStatus,

  /// The notes of one category (`getNotes`, #154): the XML dispatcher,
  /// `POST /?module=LVS&file=dispatcher`, with the one command
  /// `lvs_cats/getUserCatItems` and its params.
  categoryNotes,

  /// All of a pupil's notes, the "all items" view (`getAllNotes`, #154):
  /// the XML dispatcher with the one command `lvs_pupils/getUserData`.
  allNotes,

  /// What the results app may show (`getResultsConfiguration`, #155):
  /// `GET /LVS/Results/getConfiguration?pupilId&groupId`.
  resultsConfiguration,

  /// The periods of a pupil's results (`getResultsPeriods`, #155):
  /// `GET /LVS/Results/getperiods?pupilId&groupId&startDate&endDate`.
  resultsPeriods,

  /// The courses of a pupil's results (`getResultsCourses`, #155):
  /// `GET /LVS/Results/getcourses`, with the same query.
  resultsCourses,

  /// A page of a pupil's evaluations (`getEvaluations`, #155):
  /// `GET /LVS/Results/getevaluationsofuser`, with `pageNumber`,
  /// `itemsOnPage` and, when given, `courseIds` and `periodIds` too.
  evaluations,

  /// The feedback on a pupil's results (`getFeedback`, #155):
  /// `GET /LVS/Results/getfeedback`.
  resultsFeedback,

  /// A pupil's reports (`getReports`, #155): `GET /LVS/Results/getreports`.
  reports,

  /// The periods of a pupil's support plans (`getSupportPlanPeriods`,
  /// #156): `POST /?module=LVS&file=jqDispatcher_settings&function=`
  /// `getLVSspecificTitles` with `groupID`, `pupilID`, `type`, `activeID`,
  /// `color` and `archiveID`.
  supportPlanPeriods,

  /// A pupil's support plan in a period (`getSupportPlan`, #156):
  /// `POST /?module=LVS&file=jqDispatcher_hp&function=getIHP` with
  /// `groupID`, `pupilID`, `periodID` and `exportID`.
  supportPlan,

  /// A pupil's profile sketch in a period (`getProfileSketch`, #156):
  /// `POST /?module=LVS&file=jqDispatcher_hp&function=getProfielSchets`
  /// with `pupilID`, `classID`, `periodID` and `exportID`.
  profileSketch,
}

/// The fixtures of a pupil's support plan in one period (#156): the plan
/// and the profile sketch, in `test/fixtures/lvs/supportplan/`.
typedef FakeLvsSupportPlan = ({String plan, String sketch});

/// The period menu of the support plans of a pupil the fake has none of:
/// none, as the LVS answered a made-up pupil in a made-up class (seen live,
/// yvanvds/dartschool#163).
const _noSupportPlanPeriods = 'supportplan/periods_none.json';

/// The support plan and profile sketch of a pupil the fake has none of: a
/// period error, as the LVS answered a made-up pupil in a made-up class
/// (seen live, yvanvds/dartschool#163).
const _noSupportPlan = (
  plan: 'supportplan/plan_no_period.json',
  sketch: 'supportplan/profile_no_period.json',
);

/// The fixtures of a pupil's results in one school year (#155), one per read
/// of the results app; all in `test/fixtures/lvs/results/`.
typedef FakeLvsResults = ({
  String periods,
  String courses,
  String evaluations,
  String feedback,
  String reports,
});

/// The results of a pupil the fake has none of, as the LVS answers a
/// made-up pupil (yvanvds/dartschool#162): empty lists.
const _noResults = (
  periods: 'results/empty.json',
  courses: 'results/empty.json',
  evaluations: 'results/empty.json',
  feedback: 'results/empty.json',
  reports: 'results/empty.json',
);

/// The command of a request to the LVS's XML dispatcher: its subsystem,
/// its action and its params with their values.
typedef FakeLvsCommand = ({
  String subsystem,
  String action,
  Map<String, String> params,
});

/// How the fake refuses or breaks a read ([FakeLvs.refusal]).
enum FakeLvsRefusal {
  /// HTTP 403, with a page that names a pupil: what the library takes for a
  /// refusal to the account. What the LVS answers an account without
  /// access was not captured (yvanvds/dartschool#168).
  forbidden,

  /// Sends the request on to Smartschool's start page, as Skore does for an
  /// account without its rights: the library's other refusal. A POST gets
  /// the `302` unfollowed; a GET the start page with the redirect it
  /// followed, as `dart:io`'s `HttpClient` gives them.
  startPage,

  /// HTTP 500 with Smartschool's error page, as the LVS answered reads of a
  /// made-up pupil (seen live, yvanvds/dartschool#168).
  serverError,

  /// HTTP 200 with an HTML page instead of data.
  htmlPage,
}

/// One request the fake LVS got, with the command of a request to the XML
/// dispatcher (`null` for any other, or a `command` that does not parse).
typedef FakeLvsRequest = ({
  String method,
  String path,
  Map<String, String> query,
  Map<String, String> form,
  FakeLvsCommand? command,
  FakeLvsRead? read,
});

/// The fake LVS, served by `FakeSmartschool` to logged-in requests.
class FakeLvs {
  FakeLvs({required this.startPage});

  /// The page Smartschool's start page answers, for [FakeLvsRefusal.startPage].
  final String startPage;

  /// Every request to the LVS, in order, with the read it is (`null` for a
  /// request that is none of [FakeLvsRead]: the LVS tools never send one).
  final List<FakeLvsRequest> requests = [];

  /// The reads, in order.
  List<FakeLvsRead?> get reads => [for (final r in requests) r.read];

  /// The requests, in order, each as one line: the method, the path with
  /// the query, and the form fields, such as
  /// `POST /LVS/Pupilxhr/getStatusInfo pupilID=900001`; for the XML
  /// dispatcher, its command and the command's params instead of the form,
  /// such as `POST /?module=LVS&file=dispatcher lvs_cats/getUserCatItems
  /// catID=900401 userID=900001 ...`.
  List<String> get calls => [
    for (final r in requests)
      [
        '${r.method} ${r.path}'
            '${r.query.isEmpty ? '' : '?${_fields(r.query, '&')}'}',
        if (r.command case final command?) ...[
          '${command.subsystem}/${command.action}',
          if (command.params.isNotEmpty) _fields(command.params, ' '),
        ] else if (r.form.isNotEmpty)
          _fields(r.form, ' '),
      ].join(' '),
  ];

  static String _fields(Map<String, String> fields, String separator) => [
    for (final MapEntry(:key, :value) in fields.entries) '$key=$value',
  ].join(separator);

  /// The fixture a search answers with, by a text the search text holds
  /// (any case); a search for anything else finds no one.
  final Map<String, String> searches = {
    'janssens': 'spotlight/search_one.json',
    'peeters': 'spotlight/search_several.json',
  };

  /// The fixture of each pupil's file, by pupil id. A pupil without one, or
  /// asked for in another class than the file's, gets the LVS's placeholder
  /// pupil (`spotlight/pupil_not_found.json`, with the pupil id asked for),
  /// as the LVS answers a made-up pupil id (yvanvds/dartschool#168).
  final Map<int, String> pupilFiles = {
    fakeLvsJan.pupilId: 'spotlight/pupil_file.json',
    fakeLvsMarie.pupilId: 'spotlight/pupil_file_parts.json',
    fakeLvsNoor.pupilId: 'spotlight/pupil_file_no_plans.json',
  };

  /// The fixture of each pupil's attendance today, by pupil id; none for
  /// any other pupil.
  final Map<int, String> statuses = {
    fakeLvsJan.pupilId: 'status/both.json',
    fakeLvsMarie.pupilId: 'status/am.json',
  };

  /// The fixture of the notes of a category, by pupil id and category id
  /// (#154): the category's own notes, of any school year, as the LVS
  /// answers them (the library keeps those of the school year asked for).
  /// A pupil asked for in another class than their file's gets the LVS's
  /// placeholder pupil (`notes/pupil_unknown.xml`); a category without a
  /// fixture the answer for a category the LVS does not know
  /// (`notes/category_unknown.xml`); both with the ids asked for.
  final Map<(int, int), String> categoryNotes = {
    (fakeLvsJan.pupilId, 900401): 'notes/category.xml',
    (fakeLvsJan.pupilId, 900402): 'notes/subcategory.xml',
    (fakeLvsJan.pupilId, 900404): 'notes/subcategory_deep.xml',
    (fakeLvsMarie.pupilId, 900401): 'notes/category_empty.xml',
  };

  /// The fixture of all of a pupil's notes, by pupil id (#154). A pupil
  /// without one, or asked for in another class than their file's, gets an
  /// answer without data (`notes/all_notes_empty.xml`, with the pupil id
  /// asked for), as the LVS answers a pupil it does not know.
  final Map<int, String> allNotes = {fakeLvsJan.pupilId: 'notes/all_notes.xml'};

  /// The fixtures of a pupil's results (#155), by pupil id and the first
  /// day of the school year asked for (`startDate`): Jan Janssens's in
  /// 2030-2031 (an active period, every kind of score and feedback) and in
  /// 2029-2030 (no active period, two periods of the same name). Any other
  /// pupil or school year, or a pupil asked for in another class than their
  /// file's, gets empty lists ([_noResults]), as the LVS answers a made-up
  /// pupil.
  final Map<(int, String), FakeLvsResults> results = {
    (fakeLvsJan.pupilId, '2030-09-01'): (
      periods: 'results/periods.json',
      courses: 'results/courses.json',
      evaluations: 'results/evaluations.json',
      feedback: 'results/feedback.json',
      reports: 'results/reports.json',
    ),
    (fakeLvsJan.pupilId, '2029-09-01'): (
      periods: 'results/periods_past.json',
      courses: 'results/courses.json',
      evaluations: 'results/evaluations_past.json',
      feedback: 'results/empty.json',
      reports: 'results/empty.json',
    ),
  };

  /// The fixture of what the results app may show, for every pupil.
  String resultsConfiguration = 'results/configuration.json';

  /// The fixture of the period menu of each pupil's support plans, by pupil
  /// id (#156). A pupil without one, or asked for in another class than
  /// their file's, gets no menu ([_noSupportPlanPeriods]).
  final Map<int, String> supportPlanPeriods = {
    fakeLvsJan.pupilId: 'supportplan/periods.json',
    fakeLvsMarie.pupilId: 'supportplan/periods.json',
  };

  /// The fixtures of each pupil's support plan, by pupil id and the
  /// `periodID` asked for (`0` for the current period) (#156): Marie
  /// Peeters has a plan in both periods (the current one with every kind of
  /// item; the second closed, with items for other courses, an item of an
  /// unknown kind and an empty one), each with a profile sketch; Jan
  /// Janssens has no plan and no sketch in the current period. Any other
  /// pupil or period, or a pupil asked for in another class than their
  /// file's, gets a period error ([_noSupportPlan]), as the LVS answered a
  /// made-up pupil.
  final Map<(int, int), FakeLvsSupportPlan> supportPlans = {
    for (final period in [0, 900501])
      (fakeLvsMarie.pupilId, period): (
        plan: 'supportplan/plan.json',
        sketch: 'supportplan/profile.json',
      ),
    (fakeLvsMarie.pupilId, 900502): (
      plan: 'supportplan/plan_other.json',
      sketch: 'supportplan/profile_lines.json',
    ),
    for (final period in [0, 900501])
      (fakeLvsJan.pupilId, period): (
        plan: 'supportplan/plan_none.json',
        sketch: 'supportplan/profile_none.json',
      ),
  };

  /// Whether the fake keeps the evaluations of the `courseIds` and
  /// `periodIds` asked for, as the results app expects; when false, it
  /// sends all of them, as the LVS might (not captured,
  /// yvanvds/dartschool#168).
  bool appliesResultFilters = true;

  /// How many evaluations the fake adds to a pupil's own, copies of the
  /// first with ids of their own, to fill more pages than the library
  /// reads.
  int extraEvaluations = 0;

  /// When set, the reads of [refusedReads] (all of them when that is null)
  /// are answered this way.
  FakeLvsRefusal? refusal;

  /// The reads [refusal] is for; null for all.
  Set<FakeLvsRead>? refusedReads;

  /// When set, every LVS request fails with it: thrown by the HTTP adapter,
  /// as a connection that breaks would, so that a test can feed the server
  /// an error of its choice (one whose message holds a name, say).
  Object? failure;

  /// Answers [options] when it is an LVS request; null otherwise.
  ResponseBody? respond(RequestOptions options) {
    final uri = options.uri;
    final path = uri.path;
    final query = uri.queryParameters;
    final isLvs =
        path.startsWith('/LVS/') || path == '/LVS' || query['module'] == 'LVS';
    if (!isLvs) return null;
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    final command = query['file'] == 'dispatcher'
        ? _commandOf(form['command'])
        : null;
    final read = _readOf(
      options.method,
      path,
      query,
      form,
      command,
      fromResultsApp: _fromResultsApp(options.headers),
    );
    requests.add((
      method: options.method,
      path: path,
      query: query,
      form: form,
      command: command,
      read: read,
    ));
    if (failure case final failure?) throw failure;
    if (read == null) return _html(_errorPage, status: 500);
    if (refusal case final refusal? when refusedReads?.contains(read) ?? true) {
      return _refuse(refusal, options);
    }
    return switch (read) {
      FakeLvsRead.tree => _fixture('tree/root.json', type: 'text/json'),
      FakeLvsRead.search => _search(query['searchVal'] ?? ''),
      FakeLvsRead.pupilFile => _pupilFile(path, query),
      FakeLvsRead.todayStatus => _fixture(
        statuses[int.tryParse(form['pupilID'] ?? '')] ?? 'status/none.json',
      ),
      FakeLvsRead.categoryNotes => _categoryNotes(command!.params),
      FakeLvsRead.allNotes => _allNotes(command!.params),
      FakeLvsRead.resultsConfiguration => _fixture(resultsConfiguration),
      FakeLvsRead.resultsPeriods => _fixture(_resultsOf(query).periods),
      FakeLvsRead.resultsCourses => _fixture(_resultsOf(query).courses),
      FakeLvsRead.evaluations => _evaluations(query),
      FakeLvsRead.resultsFeedback => _fixture(_resultsOf(query).feedback),
      FakeLvsRead.reports => _fixture(_resultsOf(query).reports),
      FakeLvsRead.supportPlanPeriods => _dispatcherJson(
        _isInClass(form['pupilID'], form['groupID'])
            ? supportPlanPeriods[int.parse(form['pupilID']!)] ??
                  _noSupportPlanPeriods
            : _noSupportPlanPeriods,
      ),
      FakeLvsRead.supportPlan => _dispatcherJson(
        _supportPlanOf(form['pupilID'], form['groupID'], form['periodID']).plan,
      ),
      FakeLvsRead.profileSketch => _dispatcherJson(
        _supportPlanOf(
          form['pupilID'],
          form['classID'],
          form['periodID'],
        ).sketch,
      ),
    };
  }

  /// Whether [headers] are those the results app sends
  /// (`X-Requested-With: XMLHttpRequest`, yvanvds/dartschool#175): without
  /// them, the LVS answers its reads with HTTP 500 (seen live).
  static bool _fromResultsApp(Map<String, Object?> headers) =>
      headers.entries.any(
        (header) =>
            header.key.toLowerCase() == 'x-requested-with' &&
            header.value == 'XMLHttpRequest',
      );

  /// Whether the pupil [pupilId] is in the class [classId] by their file's
  /// fixture (both form fields, as digits).
  bool _isInClass(String? pupilId, String? classId) {
    final pupil = int.tryParse(pupilId ?? '');
    return pupil != null && _classOf(pupil) == int.tryParse(classId ?? '');
  }

  /// The fixtures of the support plan that a read's form fields ask for:
  /// [pupilId] in [classId], in the period [periodId].
  FakeLvsSupportPlan _supportPlanOf(
    String? pupilId,
    String? classId,
    String? periodId,
  ) {
    final period = int.tryParse(periodId ?? '');
    if (!_isInClass(pupilId, classId) || period == null) return _noSupportPlan;
    return supportPlans[(int.parse(pupilId!), period)] ?? _noSupportPlan;
  }

  /// The fixtures of the results the [query] of a read asks for.
  FakeLvsResults _resultsOf(Map<String, String> query) {
    final pupilId = int.parse(query['pupilId']!);
    final classId = int.tryParse(query['groupId']!);
    if (_classOf(pupilId) != classId) return _noResults;
    return results[(pupilId, query['startDate']!)] ?? _noResults;
  }

  /// A page of evaluations: those of the pupil's fixture (with
  /// [extraEvaluations]), of the courses and periods asked for unless
  /// [appliesResultFilters] is off, page `pageNumber` of `itemsOnPage`.
  ResponseBody _evaluations(Map<String, String> query) {
    final all = (jsonDecode(_read(_resultsOf(query).evaluations)) as List)
        .cast<Map<String, Object?>>();
    if (all.isNotEmpty) {
      final first = all.first;
      for (var i = 0; i < extraEvaluations; i++) {
        all.add({
          ...first,
          'identifier': '900000_900001_0_normal_${910000 + i}',
        });
      }
    }
    Set<int> ids(String? list) => {
      for (final id in (list ?? '').split(',')) ?int.tryParse(id),
    };
    final courseIds = ids(query['courseIds']);
    final periodIds = ids(query['periodIds']);
    bool asked(Map<String, Object?> evaluation) {
      final courses = (evaluation['courses'] as List? ?? const []).map(
        (course) => (course as Map)['id'],
      );
      final period = (evaluation['period'] as Map?)?['id'];
      return (courseIds.isEmpty || courses.any(courseIds.contains)) &&
          (periodIds.isEmpty || periodIds.contains(period));
    }

    final kept = [
      for (final evaluation in all)
        if (!appliesResultFilters || asked(evaluation)) evaluation,
    ];
    final page = int.parse(query['pageNumber']!);
    final size = int.parse(query['itemsOnPage']!);
    return _json(jsonEncode(kept.skip((page - 1) * size).take(size).toList()));
  }

  /// The params of each command of the XML dispatcher the fake answers,
  /// with the read it is: exactly those the library sends (#154).
  static const _commands = {
    ('lvs_cats', 'getUserCatItems'): (
      FakeLvsRead.categoryNotes,
      {'catID', 'userID', 'toolbarType', 'syRange', 'groupID', 'toolbarSide'},
    ),
    ('lvs_pupils', 'getUserData'): (
      FakeLvsRead.allNotes,
      {
        'userID',
        'toolbarType',
        'groupID',
        'syRange',
        'viewAllFilter',
        'filterData',
      },
    ),
  };

  /// The command of the dispatcher's `command` form field [xml]: a
  /// `<request>` of one `<command>` with its `<subsystem>`, `<action>` and
  /// `<params>` of `<param name>`s; `null` for anything else.
  static FakeLvsCommand? _commandOf(String? xml) {
    if (xml == null) return null;
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      return null;
    }
    final request = document.rootElement;
    final commands = request.findElements('command').toList();
    if (request.name.local != 'request' || commands.length != 1) return null;
    final command = commands.single;
    final subsystem = command.getElement('subsystem')?.innerText.trim();
    final action = command.getElement('action')?.innerText.trim();
    final params = command.getElement('params');
    if (subsystem == null || action == null || params == null) return null;
    final values = <String, String>{};
    for (final param in params.childElements) {
      final name = param.getAttribute('name');
      if (param.name.local != 'param' || name == null) return null;
      if (values.containsKey(name)) return null;
      values[name] = param.innerText;
    }
    return (subsystem: subsystem, action: action, params: values);
  }

  static FakeLvsRead? _readOf(
    String method,
    String path,
    Map<String, String> query,
    Map<String, String> form,
    FakeLvsCommand? command, {
    required bool fromResultsApp,
  }) {
    bool only(Map<String, String> fields, Set<String> names) =>
        fields.keys.toSet().difference(names).isEmpty;
    bool exactly(Map<String, String> fields, Set<String> names) =>
        only(fields, names) && fields.keys.toSet().containsAll(names);
    // The reads of the results app (#155): GETs with its headers only, each
    // with its own query fields.
    const year = {'pupilId', 'groupId', 'startDate', 'endDate'};
    const page = {...year, 'pageNumber', 'itemsOnPage'};
    if (method == 'GET' && path.startsWith('/LVS/Results/')) {
      if (!fromResultsApp || form.isNotEmpty) return null;
      return switch (path.substring('/LVS/Results/'.length)) {
        'getConfiguration' when exactly(query, {'pupilId', 'groupId'}) =>
          FakeLvsRead.resultsConfiguration,
        'getperiods' when exactly(query, year) => FakeLvsRead.resultsPeriods,
        'getcourses' when exactly(query, year) => FakeLvsRead.resultsCourses,
        'getevaluationsofuser'
            when query.keys.toSet().containsAll(page) &&
                only(query, {...page, 'courseIds', 'periodIds'}) =>
          FakeLvsRead.evaluations,
        'getfeedback' when exactly(query, year) => FakeLvsRead.resultsFeedback,
        'getreports' when exactly(query, year) => FakeLvsRead.reports,
        _ => null,
      };
    }
    // The reads of the support plans (#156): form POSTs to the LVS's JSON
    // dispatchers, each with all of its own form fields and no other.
    if (method == 'POST' &&
        path == '/' &&
        query['module'] == 'LVS' &&
        exactly(query, {'module', 'file', 'function'})) {
      return switch ((query['file'], query['function'])) {
        ('jqDispatcher_settings', 'getLVSspecificTitles')
            when exactly(form, {
              'groupID',
              'pupilID',
              'type',
              'activeID',
              'color',
              'archiveID',
            }) =>
          FakeLvsRead.supportPlanPeriods,
        ('jqDispatcher_hp', 'getIHP')
            when exactly(form, {
              'groupID',
              'pupilID',
              'periodID',
              'exportID',
            }) =>
          FakeLvsRead.supportPlan,
        ('jqDispatcher_hp', 'getProfielSchets')
            when exactly(form, {
              'pupilID',
              'classID',
              'periodID',
              'exportID',
            }) =>
          FakeLvsRead.profileSketch,
        _ => null,
      };
    }
    return switch ((method, path)) {
      ('POST', '/')
          when query['module'] == 'LVS' &&
              query['file'] == 'dispatcher' &&
              only(query, {'module', 'file'}) &&
              only(form, {'command'}) &&
              command != null =>
        switch (_commands[(command.subsystem, command.action)]) {
          (final read, final params)
              when command.params.keys.toSet().containsAll(params) &&
                  only(command.params, params) =>
            read,
          _ => null,
        },
      ('POST', '/')
          when query['module'] == 'LVS' &&
              query['file'] == 'treeBuilder' &&
              only(query, {'module', 'file'}) &&
              only(form, {'id'}) =>
        FakeLvsRead.tree,
      ('GET', '/LVS/Spotlight')
          when query.containsKey('searchVal') &&
              only(query, {'searchVal'}) &&
              form.isEmpty =>
        FakeLvsRead.search,
      ('GET', _)
          when RegExp(r'^/LVS/Spotlight/\d+$').hasMatch(path) &&
              query.containsKey('classID') &&
              only(query, {'classID'}) &&
              form.isEmpty =>
        FakeLvsRead.pupilFile,
      ('POST', '/LVS/Pupilxhr/getStatusInfo')
          when query.isEmpty && only(form, {'pupilID'}) =>
        FakeLvsRead.todayStatus,
      _ => null,
    };
  }

  ResponseBody _search(String text) {
    final search = text.toLowerCase();
    for (final MapEntry(:key, :value) in searches.entries) {
      if (search.contains(key)) return _fixture(value);
    }
    return _fixture('spotlight/search_none.json');
  }

  ResponseBody _pupilFile(String path, Map<String, String> query) {
    final pupilId = int.parse(path.substring('/LVS/Spotlight/'.length));
    final classId = int.tryParse(query['classID'] ?? '');
    if (pupilFiles[pupilId] case final fixture?) {
      final file = jsonDecode(_read(fixture)) as Map<String, Object?>;
      final pupil = file['pupil'] as Map<String, Object?>;
      if (pupil['classID'] == classId) return _json(jsonEncode(file));
    }
    // The placeholder pupil, for the pupil id asked for.
    final placeholder =
        jsonDecode(_read('spotlight/pupil_not_found.json'))
            as Map<String, Object?>;
    (placeholder['pupil'] as Map<String, Object?>)['pupilID'] = pupilId;
    return _json(jsonEncode(placeholder));
  }

  /// The class of pupil [pupilId] by their file's fixture; `null` for a
  /// pupil without one.
  int? _classOf(int pupilId) {
    final fixture = pupilFiles[pupilId];
    if (fixture == null) return null;
    final file = jsonDecode(_read(fixture)) as Map<String, Object?>;
    return (file['pupil'] as Map<String, Object?>)['classID'] as int?;
  }

  /// The notes of a category ([categoryNotes]), for the command's [params].
  ResponseBody _categoryNotes(Map<String, String> params) {
    final pupilId = int.parse(params['userID']!);
    final classId = int.tryParse(params['groupID']!);
    final categoryId = int.parse(params['catID']!);
    if (_classOf(pupilId) != classId) {
      return _xml(
        _withIds(
          _read('notes/pupil_unknown.xml'),
          pupilId: pupilId,
          categoryId: categoryId,
        ),
      );
    }
    if (categoryNotes[(pupilId, categoryId)] case final fixture?) {
      return _xml(_read(fixture));
    }
    return _xml(
      _withIds(
        _read('notes/category_unknown.xml'),
        pupilId: pupilId,
        categoryId: categoryId,
      ),
    );
  }

  /// All of a pupil's notes ([allNotes]), for the command's [params].
  ResponseBody _allNotes(Map<String, String> params) {
    final pupilId = int.parse(params['userID']!);
    final classId = int.tryParse(params['groupID']!);
    if (allNotes[pupilId] case final fixture?
        when _classOf(pupilId) == classId) {
      return _xml(_read(fixture));
    }
    return _xml(_withIds(_read('notes/all_notes_empty.xml'), pupilId: pupilId));
  }

  /// [xml], an answer of the dispatcher, with [pupilId] as its pupil (the
  /// content's `pupilID` and that of its `pupilInfo`) and [categoryId] as
  /// its category (the content's `catID`).
  static String _withIds(String xml, {required int pupilId, int? categoryId}) {
    var result = xml
        .replaceFirst(
          RegExp(r'<pupilID>\d+</pupilID>'),
          '<pupilID>$pupilId</pupilID>',
        )
        .replaceFirst(RegExp(r'"pupilID":\d+'), '"pupilID":$pupilId');
    if (categoryId != null) {
      result = result.replaceFirst(
        RegExp(r'<catID>\d+</catID>'),
        '<catID>$categoryId</catID>',
      );
    }
    return result;
  }

  ResponseBody _refuse(FakeLvsRefusal refusal, RequestOptions options) =>
      switch ((refusal, options.method)) {
        (FakeLvsRefusal.forbidden, _) => _html(_noAccessPage, status: 403),
        (FakeLvsRefusal.startPage, 'GET') =>
          _html(startPage)
            ..redirects = [
              RedirectRecord(
                302,
                'GET',
                options.uri.resolve(_startPageLocation),
              ),
            ],
        (FakeLvsRefusal.startPage, _) => ResponseBody.fromString(
          '',
          302,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
            'location': [_startPageLocation],
          },
        ),
        (FakeLvsRefusal.serverError, _) => _html(_errorPage, status: 500),
        (FakeLvsRefusal.htmlPage, _) => _html(_errorPage),
      };

  static String _read(String fixture) =>
      File('$fakeLvsFixtures/$fixture').readAsStringSync();

  static ResponseBody _fixture(
    String fixture, {
    String type = Headers.jsonContentType,
  }) => _json(_read(fixture), type: type);

  static ResponseBody _json(
    String body, {
    String type = Headers.jsonContentType,
  }) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [type],
    },
  );

  /// An answer of the LVS's JSON dispatchers (#156): the JSON of [fixture]
  /// as text, `text/html`, as the LVS sends it (seen live,
  /// yvanvds/dartschool#163).
  static ResponseBody _dispatcherJson(String fixture) =>
      _json(_read(fixture), type: 'text/html; charset=UTF-8');

  /// An answer of the XML dispatcher.
  static ResponseBody _xml(String body) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: ['text/xml; charset=UTF-8'],
    },
  );

  static ResponseBody _html(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
        },
      );
}

/// Smartschool's error page, as the LVS answers a read it cannot carry out.
const _errorPage =
    '<!DOCTYPE html><html><head><title></title></head><body>'
    '<div id="#smscMain"><h1>Oeps, er ging iets mis</h1></div></body></html>';

/// Where Smartschool sends a request of an account without the rights.
const _startPageLocation = '/?module=Homepage';

/// A "no access" page that names a pupil, to check that no message quotes
/// it.
const fakeLvsNoAccessName = 'Janssens Jan';
const _noAccessPage =
    '<!DOCTYPE html><html><body><h1>Geen toegang</h1>'
    '<p>Testpagina: geen toegang tot $fakeLvsNoAccessName.</p></body></html>';
