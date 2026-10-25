/// `read_lvs_results` (#155), called over MCP on the real server, session and
/// library (`LvsService.getResultsPeriods`, `getAllEvaluations` and the other
/// reads of the results app), against a fake Smartschool whose pupil
/// tracking system (LVS) answers with the hand-written fixtures of
/// `test/fixtures/lvs/results/` (the fakes of `FAKES.md` only, checked by
/// `test/lvs_fixtures_guard_test.dart`), and only to the results app's
/// headers, as the LVS does: the active period, a chosen period, a course,
/// the school year, a summary computed from the scores, feedback, reports,
/// "no access to results", and the privacy rules every LVS tool follows
/// (#153): only reads, nothing on disk, nothing of an answer or an error's
/// message in the log.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:smartschool_mcp/src/lvs/lvs_results.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/lvs_tool_harness.dart';

/// Today for the tests: in school year 2030-2031, that of the fixtures.
final _now = DateTime.utc(2030, 10, 25, 9);

/// The query of school year 2030-2031, as the library sends it.
const _year2030 = 'startDate=2030-09-01&endDate=2031-08-31';

/// The request of the results app's read [read] (`getperiods`, ...) for
/// [pupil] in the school year of [year].
String _resultsCall(
  String read, {
  String year = _year2030,
  FakeLvsPupil pupil = fakeLvsJan,
}) =>
    'GET /LVS/Results/$read?pupilId=${pupil.pupilId}&groupId=${pupil.classId}'
    '&$year';

/// The request of page [page] of the evaluations of [pupil], with
/// [filters] (`&courseIds=...&periodIds=...`).
String _evaluationsCall({
  String filters = '',
  String year = _year2030,
  int page = 1,
  FakeLvsPupil pupil = fakeLvsJan,
}) =>
    'GET /LVS/Results/getevaluationsofuser?pupilId=${pupil.pupilId}'
    '&groupId=${pupil.classId}&pageNumber=$page&itemsOnPage=100$filters'
    '&$year';

/// The requests of a read of the results: the periods, courses, evaluations
/// ([filters]), feedback and reports.
List<String> _calls({
  String filters = '&periodIds=900401',
  String year = _year2030,
  FakeLvsPupil pupil = fakeLvsJan,
}) => [
  _resultsCall('getperiods', year: year, pupil: pupil),
  _resultsCall('getcourses', year: year, pupil: pupil),
  _evaluationsCall(filters: filters, year: year, pupil: pupil),
  _resultsCall('getfeedback', year: year, pupil: pupil),
  _resultsCall('getreports', year: year, pupil: pupil),
];

/// The read of what the results app may show, for a school year that is not
/// the current one.
String _configurationCall({FakeLvsPupil pupil = fakeLvsJan}) =>
    'GET /LVS/Results/getConfiguration?pupilId=${pupil.pupilId}'
    '&groupId=${pupil.classId}';

/// The two requests of [pupil]'s file.
List<String> _fileCalls(FakeLvsPupil pupil) => [
  'GET /LVS/Spotlight/${pupil.pupilId}?classID=${pupil.classId}',
  'POST /LVS/Pupilxhr/getStatusInfo pupilID=${pupil.pupilId}',
];

/// The feedback of the active period, of all courses.
const _feedback =
    'Feedback (5), newest first:\n'
    '- 2030-12-20 | the class council, on the report Testrapport, in its part '
    'Testcomponent\n'
    '  Testopmerking van de klassenraad.\n'
    '  Testregel twee.\n'
    '- 2030-12-20 | on the report Testrapport, for Testvak | Testopmerking '
    'voor het vak.\n'
    '- 2030-12-20 | on the report Testrapport, for Testvak 2 | Testopmerking '
    'voor het tweede vak.\n'
    '- 2030-10-15 | by Piet Peeters | on the evaluation Testevaluatie '
    '(Testvak) | Testfeedback bij de evaluatie.\n'
    '  Attachments, by name only (not opened): Testbijlage.pdf\n'
    '- (no date) | feedback of a kind the server does not know | '
    'Testfeedback van een onbekende soort.\n'
    'Not shown: 1 feedback on other periods or courses.';

/// The feedback on the goal of the project of the second period.
const _goalFeedback =
    '- 2031-03-09 | by Céline Dupré | on a goal of the evaluation '
    'Testevaluatie (Testvak) | Testfeedback bij een doel.';

/// The reports of school year 2030-2031.
const _reports =
    'Reports of school year 2030-2031 (2), newest first, by name and day '
    'only: the server does not open them.\n'
    '- 2031-06-30 | Testrapport\n'
    '- 2030-12-20 | Testrapport';

/// The periods of school year 2030-2031, to ask for.
const _periods =
    'Periods of the results in school year 2030-2031, to pass as period (its '
    'period_id or name, or all for every period): Testperiode (period_id '
    '900401, active), Testperiode 2 (period_id 900402).';

/// The evaluations of Testvak in the active period, newest first: the one
/// at 00:30 Belgian time (23:30 UTC the day before) on its Belgian day.
const _activeEvaluations =
    '  - 2030-11-26 | Testevaluatie | 10/10 (100%) | counts\n'
    '  - 2030-11-19 | Testevaluatie | a symbol, icon "target_lpd_steel"\n'
    '  - 2030-11-12 | Testevaluatie | 9/20 (45%) | counts\n'
    '  - 2030-11-05 | Testevaluatie | A (Testbeoordeling) | does not count | '
    'not published to the pupil\n'
    '  - 2030-10-22 | Testevaluatie | 4/10 (40%) | counts\n'
    '  - 2030-10-15 | Testevaluatie | 7/10 (70%) | counts | Testcomponent '
    '(TEST) | with feedback';

/// The answer for the active period, of all courses.
const _activeAnswer =
    'The results of the pupil with pupil_id 900001 (class_id 900101) in the '
    'LVS, school year 2030-2031, the active period Testperiode (period_id '
    '900401), all courses: 6 evaluations, per course, newest first.\n'
    'Testvak (course_id 900301), teacher Piet Peeters: 6 evaluations.\n'
    '  Computed from the scores given (not by the LVS): 6 evaluations; of '
    'the 4 with a score as a number, 2 below half (under 50%); 2 could not be '
    'counted (a text, a symbol or no score).\n'
    '$_activeEvaluations\n'
    'Courses without evaluations here: Testvak 2 (course_id 900302, a part of '
    'Testvak).\n'
    '$_feedback\n'
    '$_reports\n'
    '$_periods';

/// The evaluations of Testvak 2 in the second period, under its own course.
const _secondPeriodVak2 =
    'Testvak 2 (course_id 900302, a part of Testvak), teacher Céline Dupré: '
    '3 evaluations.\n'
    '  - 2031-03-16 | Testevaluatie | a score of type "testgrafiek", which '
    'the server does not know: "Testwaarde" | counts | also for Testvak\n'
    '  - 2031-03-02 | Testevaluatie | 12,5/20 (62.5%) | counts\n'
    '  - (no date) | Testevaluatie | no score';

/// The answer for the second period and the course Testvak 2.
const _vak2Answer =
    'The results of the pupil with pupil_id 900001 (class_id 900101) in the '
    'LVS, school year 2030-2031, the period Testperiode 2 (period_id 900402), '
    'the course Testvak 2 (course_id 900302, a part of Testvak): 3 '
    'evaluations, per course, newest first.\n'
    '$_secondPeriodVak2\n'
    'Feedback (1), newest first:\n'
    '- 2030-12-20 | on the report Testrapport, for Testvak 2 | Testopmerking '
    'voor het tweede vak.\n'
    'Not shown: 3 feedback on other periods or courses.\n'
    'Not shown: 2 remarks about no one course (of the class council, or the '
    'like); leave course out to see them.\n'
    '$_reports\n'
    '$_periods';

/// The issue's "no access to results": what a refusal with HTTP 403 says.
const _noAccess =
    "The account has no access to the results (Resultaten) of this pupil's "
    "file: Smartschool's pupil tracking system (LVS) refused that read (HTTP "
    '403), as it does for an account without access to that part. Other '
    'parts of the file may still be readable: read_lvs_pupil lists them. If '
    "the account should have access, ask the school's Smartschool "
    'administrator.';

const _refused =
    "Smartschool's pupil tracking system (LVS) refused this read to the "
    'account: it may have no access to the LVS, or may not see this pupil.';

const _unreadable =
    "Smartschool's pupil tracking system (LVS) answered with something the "
    'server could not read';

void main() {
  late LvsToolHarness h;
  late FakeLvs lvs;

  setUp(() async {
    h = await LvsToolHarness.start(now: () => _now);
    lvs = h.lvs;
  });

  Map<String, Object?> jan([Map<String, Object?> more = const {}]) => {
    ...fakeLvsPupilArguments(fakeLvsJan),
    ...more,
  };

  Future<String> read(Map<String, Object?> arguments) =>
      h.ok('read_lvs_results', arguments);

  Future<String> refused(Map<String, Object?> arguments) =>
      h.error('read_lvs_results', arguments);

  group('the tool is listed', () {
    late Tool tool;
    late List<String> names;

    setUp(() async {
      final tools = await h.listTools();
      names = tools.keys.toList();
      tool = tools['read_lvs_results']!;
    });

    test('after the notes, read-only and idempotent', () {
      expect(names.take(4), [
        'search_lvs_pupils',
        'read_lvs_pupil',
        'read_lvs_notes',
        'read_lvs_results',
      ]);
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.destructiveHint, isNot(true));
    });

    test('its description: the privacy rules of every LVS tool, that the '
        'summary is computed, and what it does not read (the comments on '
        'reports, the older Skore part)', () {
      final description = tool.description!;
      expect(
        description,
        endsWith('$lvsPrivacyRules Reading changes nothing.'),
      );
      expect(
        description,
        contains(
          'with 5 or more, a summary line computed from the scores given (how '
          'many below half), which says so and how many scores could not be '
          'counted',
        ),
      );
      expect(
        description,
        contains(
          'Not read: the comments on reports, and the older Skore part some '
          'schools still show instead of Resultaten.',
        ),
      );
    });

    test('takes pupil_id and class_id, and optionally a school year, a '
        'period (id or name) and a course (id or name)', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['pupil_id', 'class_id']);
      expect(schema.properties!.keys, [
        'pupil_id',
        'class_id',
        'school_year',
        'period',
        'course',
      ]);
      for (final name in ['period', 'course']) {
        expect(schema.properties![name], {
          'description': isA<String>(),
          'anyOf': [
            {'type': 'integer', 'minimum': 1},
            {'type': 'string', 'minLength': 1},
          ],
        }, reason: name);
      }
      expect(
        (schema.properties!['period']! as Map)['description'],
        contains('all for every period'),
      );
    });
  });

  group('the active period by default', () {
    test('per course, newest first by their Belgian day, each score as '
        'given; a summary line computed from the scores, which says how many '
        'it could not count; the courses without evaluations; the feedback, '
        'the reports and the periods to ask for', () async {
      final text = await read(jan());

      expect(text, _activeAnswer);
      // The current school year needs no configuration; the evaluations
      // are those of the active period.
      expect(lvs.calls, _calls());
    });

    test('a course with fewer than 5 evaluations gets no summary', () async {
      final text = await read(jan({'period': 'Testperiode 2'}));

      expect(
        text,
        contains(
          'Testvak (course_id 900301), teacher Piet Peeters: 2 evaluations.\n'
          '  - 2031-03-16 |',
        ),
      );
      expect(text, isNot(contains('Computed')));
    });

    test('the school year without an active period: all its periods, each '
        "evaluation's period named; another school year than today's reads "
        'what the results app may show first', () async {
      final text = await read(jan({'school_year': '2029-2030'}));

      expect(
        text,
        'The results of the pupil with pupil_id 900001 (class_id 900101) in '
        'the LVS, school year 2029-2030, all periods (none is marked active), '
        'all courses: 2 evaluations, per course, newest first.\n'
        'Testvak (course_id 900301), teacher Piet Peeters: 2 evaluations.\n'
        '  - 2030-03-10 | Testevaluatie | B | counts | Testperiode\n'
        '  - 2029-10-15 | Testevaluatie | 6/10 (60%) | counts | Testperiode\n'
        'Courses without evaluations here: Testvak 2 (course_id 900302, a part '
        'of Testvak).\n'
        'Feedback: none in school year 2029-2030.\n'
        'Reports: none in school year 2029-2030.\n'
        'Periods of the results in school year 2029-2030, to pass as period '
        '(its period_id or name, or all for every period): Testperiode '
        '(period_id 900403), Testperiode (period_id 900404).',
      );
      const year = 'startDate=2029-09-01&endDate=2030-08-31';
      expect(lvs.calls, [
        _configurationCall(),
        ..._calls(filters: '', year: year),
      ]);
    });

    test('the current school year is that of today: in an earlier one the '
        'LVS holds nothing, and the file is read to tell that from a pupil it '
        'does not know', () async {
      final h = await LvsToolHarness.start(
        now: () => DateTime.utc(2031, 8, 31, 22, 30), // 00:30, 1 September
        // in Belgium
      );

      final text = await h.ok('read_lvs_results', jan());

      expect(
        text,
        'The LVS holds no evaluations of the pupil with pupil_id 900001 '
        '(class_id 900101) in school year 2031-2032, all periods (the LVS '
        'lists none), all courses.\n'
        'Feedback: none in school year 2031-2032.\n'
        'Reports: none in school year 2031-2032.\n'
        'The LVS lists no periods of the results in school year 2031-2032.',
      );
      expect(h.lvs.calls, [
        ..._calls(filters: '', year: 'startDate=2031-09-01&endDate=2032-08-31'),
        ..._fileCalls(fakeLvsJan),
      ]);
    });

    test('an account the results app lets see the current school year only: '
        'another school year is an error, after the configuration '
        'alone', () async {
      lvs.resultsConfiguration = 'results/configuration_current_only.json';

      final text = await refused(jan({'school_year': '2029-2030'}));

      expect(
        text,
        'The results app lets this account see the results of the current '
        'school year only, not those of school year 2029-2030. Leave '
        'school_year out for the current school year.',
      );
      expect(lvs.calls, [_configurationCall()]);

      // The current school year needs no configuration.
      expect(await read(jan({'school_year': '2030-2031'})), _activeAnswer);
    });
  });

  group('a period', () {
    test('by its name, ignoring case, or its period_id: that period only, '
        'asked of the LVS by its id', () async {
      for (final period in [
        ' testperiode   2 ',
        '"Testperiode 2"',
        900402,
        '900402',
        'period_id 900402',
        'periode 2',
      ]) {
        lvs.requests.clear();

        final text = await read(jan({'period': period, 'course': 'Testvak 2'}));

        expect(text, _vak2Answer, reason: '$period');
        expect(
          lvs.calls,
          _calls(filters: '&courseIds=900302&periodIds=900402'),
          reason: '$period',
        );
      }
    });

    test('all: every period, without ids sent, each evaluation\'s period '
        'named, and the feedback of every period', () async {
      final text = await read(jan({'period': 'ALL'}));

      expect(
        text,
        startsWith(
          'The results of the pupil with pupil_id 900001 (class_id 900101) in '
          'the LVS, school year 2030-2031, all periods, all courses: 10 '
          'evaluations, per course, newest first.\n'
          'Testvak (course_id 900301), teacher Piet Peeters: 8 evaluations.\n'
          '  Computed from the scores given (not by the LVS): 8 evaluations; '
          'of the 4 with a score as a number, 2 below half (under 50%); 4 '
          'could not be counted (a text, a symbol or no score).\n'
          '  - 2031-03-16 | Testevaluatie | a score of type "testgrafiek", '
          'which the server does not know: "Testwaarde" | counts | Testperiode '
          '2 | also for Testvak 2\n'
          '  - 2031-03-09 | Testevaluatie | a rubric (Testbeoordeling) | counts '
          '| Testperiode 2 | with feedback\n'
          '  - 2030-11-26 | Testevaluatie | 10/10 (100%) | counts | '
          'Testperiode\n',
        ),
      );
      expect(
        text,
        contains(
          'Testvak 2 (course_id 900302, a part of Testvak), teacher Céline '
          'Dupré: 2 evaluations.\n'
          '  - 2031-03-02 | Testevaluatie | 12,5/20 (62.5%) | counts | '
          'Testperiode 2\n'
          '  - (no date) | Testevaluatie | no score | Testperiode 2\n'
          'Feedback (6), newest first:\n'
          '$_goalFeedback\n',
        ),
      );
      expect(text, isNot(contains('Not shown')));
      expect(text, isNot(contains('Courses without evaluations')));
      expect(lvs.calls, _calls(filters: ''));
    });

    test('a name several periods match: an error that lists them with their '
        'ids, before the evaluations are read', () async {
      final text = await refused(
        jan({'school_year': '2029-2030', 'period': 'testperiode'}),
      );

      expect(
        text,
        "Several periods of this pupil's results in school year 2029-2030 "
        'match "testperiode": Testperiode (period_id 900403), Testperiode '
        '(period_id 900404). Pass the one you mean as period, by its '
        'period_id.',
      );
      expect(lvs.calls, [
        _configurationCall(),
        _resultsCall(
          'getperiods',
          year: 'startDate=2029-09-01&endDate=2030-08-31',
        ),
      ]);

      // Their ids tell them apart.
      final one = await read(
        jan({'school_year': '2029-2030', 'period': 900404}),
      );
      expect(one, contains('the period Testperiode (period_id 900404)'));
      expect(one, contains('  - 2030-03-10 | Testevaluatie | B | counts\n'));
      expect(one, isNot(contains('2029-10-15')));
    });

    for (final period in ['Testtrimester', 900499]) {
      test('a period the results do not have ($period): an error that lists '
          'them', () async {
        final text = await refused(jan({'period': period}));

        expect(
          text,
          "This pupil's results in school year 2030-2031 have no period "
          '"$period". Their periods are: Testperiode (period_id 900401, '
          'active), Testperiode 2 (period_id 900402). Pass one of them as '
          'period, by its period_id or its name, or all for every period; '
          'leave period out for the active period.',
        );
        expect(lvs.calls, [_resultsCall('getperiods')]);
      });
    }
  });

  group('a course', () {
    test('by its name, ignoring case: that course with its parts, asked of '
        'the LVS by their ids', () async {
      final text = await read(jan({'course': 'TESTVAK', 'period': 'all'}));

      expect(
        text,
        startsWith(
          'The results of the pupil with pupil_id 900001 (class_id 900101) in '
          'the LVS, school year 2030-2031, all periods, the courses Testvak '
          '(course_id 900301), Testvak 2 (course_id 900302, a part of '
          'Testvak): 10 evaluations, per course, newest first.\n'
          'Testvak (course_id 900301), teacher Piet Peeters: 8 evaluations.\n',
        ),
      );
      // The class council's remarks are about no one course.
      expect(
        text,
        contains(
          'Not shown: 2 remarks about no one course (of the class council, or '
          'the like); leave course out to see them.\n',
        ),
      );
      expect(lvs.calls, _calls(filters: '&courseIds=900301,900302'));
    });

    test('by its course_id, or part of its name: that course only; an '
        'evaluation for two courses under the one asked for, which names the '
        'other', () async {
      for (final course in [900302, 'course_id 900302', 'vak 2']) {
        lvs.requests.clear();

        final text = await read(
          jan({'course': course, 'period': 'Testperiode 2'}),
        );

        expect(text, _vak2Answer, reason: '$course');
      }
    });

    test('a course without evaluations in the period: a sentence, with the '
        'feedback, reports and periods', () async {
      final text = await read(jan({'course': 'Testvak 2'}));

      expect(
        text,
        startsWith(
          'The LVS holds no evaluations of the pupil with pupil_id 900001 '
          '(class_id 900101) in school year 2030-2031, the active period '
          'Testperiode (period_id 900401), the course Testvak 2 (course_id '
          '900302, a part of Testvak).\n'
          'Feedback (1), newest first:\n',
        ),
      );
      expect(text, endsWith('$_reports\n$_periods'));
      // Feedback, reports: no reason to read the file.
      expect(lvs.calls, _calls(filters: '&courseIds=900302&periodIds=900401'));
    });

    test('a course the results do not have: an error that lists them, '
        'before the evaluations are read', () async {
      final text = await refused(jan({'course': 'Testgeschiedenis'}));

      expect(
        text,
        "This pupil's results in school year 2030-2031 have no course "
        '"Testgeschiedenis". Their courses are: Testvak (course_id 900301), '
        'Testvak 2 (course_id 900302, a part of Testvak). Pass one of them as '
        'course, by its course_id or (part of) its name, or leave course out '
        'for all courses.',
      );
      expect(lvs.calls, [
        _resultsCall('getperiods'),
        _resultsCall('getcourses'),
      ]);
    });

    test('an LVS that sends evaluations of other periods and courses than '
        'those asked for: they are left out all the same', () async {
      lvs.appliesResultFilters = false;

      expect(
        await read(jan({'period': 900402, 'course': 900302})),
        _vak2Answer,
      );
      expect(await read(jan()), _activeAnswer);
    });
  });

  group('nothing to show, or no such pupil', () {
    test('a school year without results: a sentence, after the file says the '
        'pupil is known', () async {
      final text = await read(jan({'school_year': '2028-2029'}));

      expect(
        text,
        startsWith(
          'The LVS holds no evaluations of the pupil with pupil_id 900001 '
          '(class_id 900101) in school year 2028-2029, all periods (the LVS '
          'lists none), all courses.\n'
          'Feedback: none in school year 2028-2029.\n',
        ),
      );
      expect(text, isNot(contains('Skore')));
      expect(lvs.calls.skip(lvs.calls.length - 2), _fileCalls(fakeLvsJan));
    });

    test('a file that shows the older Skore part instead of Resultaten: the '
        'answer says this tool does not read it', () async {
      final text = await read(fakeLvsPupilArguments(fakeLvsMarie));

      expect(
        text,
        'The LVS holds no evaluations of the pupil with pupil_id 900002 '
        '(class_id 900102) in school year 2030-2031, all periods (the LVS '
        'lists none), all courses.\n'
        "This pupil's file shows its results in the older Skore part (reports "
        'in Skore), which this tool does not read: it reads the Resultaten '
        'part only.\n'
        'Feedback: none in school year 2030-2031.\n'
        'Reports: none in school year 2030-2031.\n'
        'The LVS lists no periods of the results in school year 2030-2031.',
      );
      expect(lvs.calls, [
        ..._calls(filters: '', pupil: fakeLvsMarie),
        ..._fileCalls(fakeLvsMarie),
      ]);
    });

    for (final (what, arguments) in [
      ('a pupil the LVS does not know', fakeLvsPupilArguments(fakeLvsLars)),
      (
        'a pupil in another class than theirs',
        {'pupil_id': fakeLvsJan.pupilId, 'class_id': fakeLvsMarie.classId},
      ),
    ]) {
      test('$what: the results app answers nothing, and the file says the LVS '
          'does not know the pupil', () async {
        final text = await refused(arguments);

        expect(
          text,
          'The LVS knows no pupil with pupil_id ${arguments['pupil_id']} in '
          'the class with class_id ${arguments['class_id']} that this account '
          'may see. Take pupil_id and class_id from the same line of '
          'search_lvs_pupils.',
        );
        expect(lvs.reads.last, FakeLvsRead.pupilFile);
      });
    }

    test('a pupil the LVS does not know, with a course or a period: the file '
        'says so, not that there is no course or period', () async {
      final unknown = fakeLvsPupilArguments(fakeLvsLars);
      for (final more in [
        {'course': 'Testvak'},
        {'period': 'Testperiode'},
      ]) {
        lvs.requests.clear();

        final text = await refused({...unknown, ...more});

        expect(text, startsWith('The LVS knows no pupil with pupil_id 900005'));
        expect(lvs.reads.last, FakeLvsRead.pupilFile, reason: '$more');
      }
    });

    test('a known pupil without courses, with a course: there are none to '
        'pick from', () async {
      final text = await refused(
        jan({'school_year': '2028-2029', 'course': 'Testvak'}),
      );

      expect(
        text,
        "The LVS lists no courses of this pupil's results in school year "
        '2028-2029. Leave course out.',
      );
    });
  });

  group('many evaluations', () {
    test('read page by page until a page is not full', () async {
      lvs.extraEvaluations = 150;

      final text = await read(jan());

      expect(text, contains('all courses: 156 evaluations, per course'));
      expect(text, isNot(contains('Only the first')));
      expect(
        [
          for (final call in lvs.calls)
            if (call.contains('getevaluationsofuser')) call,
        ],
        [
          _evaluationsCall(filters: '&periodIds=900401'),
          _evaluationsCall(filters: '&periodIds=900401', page: 2),
        ],
      );
    });

    test('more than the library reads: the answer says the LVS may have '
        'more, and how to read fewer', () async {
      lvs.extraEvaluations = 1000;

      final text = await read(jan());

      expect(
        text,
        startsWith(
          'The results of the pupil with pupil_id 900001 (class_id 900101) in '
          'the LVS, school year 2030-2031, the active period Testperiode '
          '(period_id 900401), all courses: 1000 evaluations, per course, '
          'newest first.\n'
          'Only the first 1000 evaluations were read (10 pages of 100): the '
          'LVS may have more. Pass a period or a course to read fewer at a '
          'time.\n',
        ),
      );
      expect(
        lvs.calls.where((call) => call.contains('getevaluationsofuser')),
        hasLength(lvsEvaluationsMaxPages),
      );
    });
  });

  group('arguments that cannot be read: an error that says what to pass, '
      'before logging in', () {
    for (final (arguments, error) in <(Map<String, Object?>, String)>[
      ({'school_year': '2030'}, 'school_year must be a school year like'),
      // Not a whole number, or not a text: refused by the schema.
      ({'period': 2.5}, 'period'),
      ({'course': 2.5}, 'course'),
      ({'period': true}, 'period'),
      ({'class_id': null}, 'class_id'),
      ({'pupil_id': 0}, 'pupil_id'),
    ]) {
      test('$arguments', () async {
        final text = await refused(
          jan(arguments)..removeWhere((_, v) => v == null),
        );

        expect(text, contains(error));
        expect(h.server.requests, isEmpty);
      });
    }

    test('an empty period, course or school year counts as none', () async {
      final text = await read(
        jan({'period': ' ', 'course': '""', 'school_year': ''}),
      );

      expect(text, _activeAnswer);
    });
  });

  group('a refusal or an answer the server cannot read: an error that says '
      'what to do, and quotes nothing of the answer', () {
    for (final reads in [
      {FakeLvsRead.resultsPeriods},
      {FakeLvsRead.evaluations},
      {FakeLvsRead.reports},
    ]) {
      test('HTTP 403 (${reads.single.name}): no access to the results, in a '
          'sentence', () async {
        lvs
          ..refusal = FakeLvsRefusal.forbidden
          ..refusedReads = reads;

        final text = await refused(jan());

        expect(text, _noAccess);
        expect(text, isNot(contains(fakeLvsNoAccessName)));
      });
    }

    test('sent on to the start page: the refusal of the LVS', () async {
      lvs
        ..refusal = FakeLvsRefusal.startPage
        ..refusedReads = {FakeLvsRead.resultsCourses};

      final text = await refused(jan());

      expect(text, startsWith(_refused));
    });

    test('a refused configuration, for another school year: no access to '
        'the results', () async {
      lvs
        ..refusal = FakeLvsRefusal.forbidden
        ..refusedReads = {FakeLvsRead.resultsConfiguration};

      expect(await refused(jan({'school_year': '2029-2030'})), _noAccess);
    });

    for (final (refusal, status) in [
      (FakeLvsRefusal.serverError, ' (HTTP 500)'),
      (FakeLvsRefusal.htmlPage, ''),
    ]) {
      test('${refusal.name}: could not read', () async {
        lvs
          ..refusal = refusal
          ..refusedReads = {FakeLvsRead.resultsFeedback};

        final text = await refused(jan());

        expect(text, startsWith('$_unreadable$status. Try again in a moment.'));
        expect(text, isNot(contains('Oeps')));
      });
    }
  });

  group('privacy', () {
    test("only the reads of the results app, with the app's headers, and the "
        'file when the results hold nothing: no PUT, no other POST', () async {
      await read(jan());
      await read(jan({'school_year': '2029-2030', 'course': 'Testvak'}));
      await read(fakeLvsPupilArguments(fakeLvsMarie));

      // Without the app's headers the fake answers a read of the results
      // with HTTP 500, as the LVS does, and counts it as no read.
      expect(lvs.reads, everyElement(isNotNull));
      expect(lvs.reads.toSet(), {
        FakeLvsRead.resultsConfiguration,
        FakeLvsRead.resultsPeriods,
        FakeLvsRead.resultsCourses,
        FakeLvsRead.evaluations,
        FakeLvsRead.resultsFeedback,
        FakeLvsRead.reports,
        FakeLvsRead.pupilFile,
        FakeLvsRead.todayStatus,
      });
      expect(
        {
          for (final r in lvs.requests)
            if (r.method != 'GET') '${r.method} ${r.path}',
        },
        {'POST /LVS/Pupilxhr/getStatusInfo'},
      );
    });

    test('nothing is kept on disk: the cache folder holds the same files '
        'before and after, none with a result', () async {
      // The first call logs in, which saves the session there.
      await read(jan());
      final before = h.cacheFiles();

      await read(jan({'period': 'all'}));
      await read(jan({'school_year': '2029-2030'}));

      expect(h.cacheFiles(), before);
      for (final path in h.cacheFiles()) {
        final content = File(path).readAsStringSync().toLowerCase();
        for (final word in ['testevaluatie', 'testfeedback', 'testvak']) {
          expect(content, isNot(contains(word)), reason: path);
        }
      }
    });

    test('the log of a call that succeeds holds nothing of the results, nor '
        "the pupil's id", () async {
      final (_, text, log) = await h.logged(
        'read_lvs_results',
        jan({'period': 'all'}),
      );

      expect(text, contains('Testfeedback bij een doel.'));
      // The log is captured: the login shows in it.
      expect(log, contains('Smartschool: checking the session'));
      final logged = log.toLowerCase();
      for (final word in [
        'testevaluatie',
        'testvak',
        'testfeedback',
        'testopmerking',
        'testrapport',
        'testperiode',
        'testbijlage',
        'peeters',
        'dupré',
        '${fakeLvsJan.pupilId}',
      ]) {
        expect(logged, isNot(contains(word)));
      }
    });

    test('a session Smartschool refuses during the results: the log names '
        "the error's type, not the request, which holds the pupil's "
        'id', () async {
      await read(jan());
      h.server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      final (isError, text, log) = await h.logged('read_lvs_results', jan());

      expect(isError, isNot(true), reason: text);
      expect(
        log,
        contains(
          'Smartschool did not accept the session '
          '(SmartschoolSessionExpiredError); trying once more',
        ),
      );
      expect(log, isNot(contains('${fakeLvsJan.pupilId}')));
      expect(log, isNot(contains('Results')));
    });

    test('an error whose message holds a name: the log has its type and '
        'HTTP status only, the result neither', () async {
      lvs.failure = const SmartschoolLvsError(
        'Testfout over Janssens Jan.',
        statusCode: 500,
      );

      final (isError, text, log) = await h.logged('read_lvs_results', jan());

      expect(isError, isTrue);
      expect(text, startsWith('$_unreadable (HTTP 500).'));
      expect(log, contains('lvs: SmartschoolLvsError (HTTP 500)\n'));
      for (final shown in [text, log]) {
        expect(shown, isNot(contains('Janssens')));
        expect(shown, isNot(contains('Testfout')));
      }
    });

    test('a refusal with HTTP 403: the log has its type and status '
        'only', () async {
      lvs
        ..refusal = FakeLvsRefusal.forbidden
        ..refusedReads = {FakeLvsRead.evaluations};

      final (_, _, log) = await h.logged('read_lvs_results', jan());

      expect(log, contains('lvs: SmartschoolLvsAccessDeniedError (HTTP 403)'));
      expect(log, isNot(contains(fakeLvsNoAccessName)));
      expect(log, isNot(contains('${fakeLvsJan.pupilId}')));
    });
  });

  group('the parts, worded', () {
    LvsScore score(
      String type, {
      String value = '',
      num? percentage,
      String description = '',
    }) => LvsScore(
      type: type,
      value: value,
      percentage: percentage,
      description: description,
    );

    test('a score as the LVS gives it, nothing computed', () {
      for (final (given, shown) in [
        (score('percentage', value: '70', percentage: 70), '70%'),
        (score('percentage', value: '66.666', percentage: 66.666), '66.7%'),
        (
          score(
            'percentage',
            value: '62.5',
            percentage: 62.5,
            description: '12,5/20',
          ),
          '12,5/20 (62.5%)',
        ),
        (score('percentage', value: '70'), '70%'),
        (
          score('percentage', description: 'Testbeoordeling'),
          'Testbeoordeling',
        ),
        (score('percentage'), 'no score'),
        (score('text', value: 'A'), 'A'),
        (score('text', description: 'Testbeoordeling'), 'Testbeoordeling'),
        (score('text'), 'no score'),
        (score('icon'), 'a symbol'),
        (
          score(
            'icon',
            value: 'target_lpd_steel',
            description: 'Testbeoordeling',
          ),
          'a symbol, icon "target_lpd_steel" (Testbeoordeling)',
        ),
        (score('image', value: '/skore/api/v1/assets/900901'), 'an image'),
        (score('rubrics', value: 'Testwaarde'), 'a rubric, "Testwaarde"'),
        (LvsScore.none, 'no score'),
        (
          score('', value: 'Testwaarde'),
          'a score without a type: "Testwaarde"',
        ),
        (
          score('testgrafiek'),
          'a score of type "testgrafiek", which the server does not know',
        ),
      ]) {
        expect(formatLvsScore(given), shown, reason: '$given');
      }
    });

    test('the summary: from 5 evaluations on, computed from the scores that '
        'are a number, saying how many could not be counted', () {
      LvsEvaluation evaluation(LvsScore score) => LvsEvaluation(
        identifier: '900000_900001_0_normal_900601',
        name: 'Testevaluatie',
        score: score,
      );
      final number = [
        for (final percentage in [49.9, 50, 20, 90, 100])
          evaluation(score('percentage', percentage: percentage)),
      ];

      expect(formatLvsResultsSummary(number.take(4).toList()), isNull);
      expect(
        formatLvsResultsSummary(number),
        'Computed from the scores given (not by the LVS): 5 evaluations, all '
        'with a score as a number: 2 below half (under 50%).',
      );
      expect(
        formatLvsResultsSummary([
          for (var i = 0; i < 5; i++) evaluation(score('text', value: 'A')),
        ]),
        'Computed from the scores given (not by the LVS): 5 evaluations, none '
        'with a score as a number: none could be counted (texts, symbols or '
        'no score).',
      );
      expect(
        formatLvsResultsSummary([
          ...number,
          evaluation(LvsScore.none),
          evaluation(score('percentage', value: 'Testwaarde')),
        ]),
        'Computed from the scores given (not by the LVS): 7 evaluations; of '
        'the 5 with a score as a number, 2 below half (under 50%); 2 could not '
        'be counted (a text, a symbol or no score).',
      );
    });

    test('feedback without text, author or date, and a text of one line '
        'given as HTML', () {
      expect(
        formatLvsFeedback(
          const LvsFeedback(
            identifier: '00000000-0000-0000-0000-000000901001',
            kind: LvsFeedbackKind.course,
            text: ' ',
          ),
        ),
        '- (no date) | on a report | (no text)',
      );
      expect(
        formatLvsFeedback(
          LvsFeedback(
            identifier: '00000000-0000-0000-0000-000000901003',
            kind: LvsFeedbackKind.evaluation,
            text: '<p>Testfeedback &amp; meer.</p>',
            evaluation: LvsFeedbackEvaluation(
              identifier: '900000_900001_0_normal_900601',
              name: 'Testevaluatie',
              date: DateTime.utc(2030, 10, 14, 22),
            ),
          ),
        ),
        '- 2030-10-15 | on the evaluation Testevaluatie | Testfeedback & meer.',
      );
    });

    test('a course with parts at any depth comes with all of them, in the '
        "LVS's order", () {
      const courses = [
        LvsResultsCourse(id: 900303, name: 'Testvak', parentCourseId: 900302),
        LvsResultsCourse(id: 900301, name: 'Testvak 2'),
        LvsResultsCourse(id: 900302, name: 'Testvak', parentCourseId: 900301),
        LvsResultsCourse(id: 900304, name: 'Testvak'),
      ];
      final year = LvsSchoolYear.starting(2030);

      expect(
        [
          for (final course in pickLvsResultsCourses(
            courses,
            'course_id 900301',
            schoolYear: year,
          ))
            course.id,
        ],
        [900303, 900301, 900302],
      );
      // A name several courses have: a filter, so all of them.
      expect(
        [
          for (final course in pickLvsResultsCourses(
            courses,
            'testvak',
            schoolYear: year,
          ))
            course.id,
        ],
        [900303, 900302, 900304],
      );
    });

    test('an id as the tools print it, and names compared without case or '
        'runs of white space', () {
      expect(lvsIdIn('900401', 'period_id'), 900401);
      expect(lvsIdIn(' Period_ID 900401 ', 'period_id'), 900401);
      expect(lvsIdIn('periodid900401', 'period_id'), 900401);
      expect(lvsIdIn('category_id 900401', 'period_id'), isNull);
      expect(lvsIdIn('Testperiode 2', 'period_id'), isNull);
      expect(lvsNameKey('  Testperiode \t 2 '), 'testperiode 2');
      expect(
        () => lvsIdOrNameArgument(
          {'period': 2.5},
          'period',
          what: 'a period_id or a name',
        ),
        throwsA(
          isA<ToolError>().having(
            (error) => error.message,
            'message',
            'period must be a period_id or a name; 2.5 is not.',
          ),
        ),
      );
    });
  });
}
