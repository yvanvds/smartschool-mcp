/// `save_skore_grades` (#143), called over MCP on the real server, session
/// and library, against a fake Smartschool whose Skore gradebook carries out
/// `saveGrade` in the shape of dartschool's captures of #151
/// (`test/support/fake_skore_gradebook.dart`). Like the other gradebook
/// tools, it needs no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_skore_evaluations_tool.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_grades_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// What no gradebook text may say: the gradebook is not behind the switch
/// "Skore-beheer", and needs no extra rights.
final _adminWords = RegExp(
  r'Skore-beheer|SMARTSCHOOL_SKORE|rights|administrator|score management',
  caseSensitive: false,
);

/// 6EWI's gradebook (see `fakeSkoreGradebook6EWI`): one open period, DW1,
/// three pupils, and three evaluations: Toets 1 (not published, max 20, no
/// grades), Python scripts schrijven (scheduled, max 100) and Lussen
/// (published, max 20).
const _gradebookName =
    'gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
    '(gradebook id 32508)';
const _where = 'period DW1 (period id 1704) of the $_gradebookName';
const _toetsName = 'evaluation "Toets 1" (evaluation id 500003)';
const _toets =
    'Toets 1 | evaluation id 500003 | column A | 2026-10-08 | max 20 | '
    'component DW | points | not published: the pupils do not see it';

/// The pupils of 6EWI, as the result lists them.
const _an = '1. Aerts, An | pupil id 1201';
const _bart = '2. Claes, Bart | pupil id 1202';
const _chloe = '3. Dupont, Chloé | pupil id 1203';

/// What the tool says after a check of the library refused the change.
String _refused(String reason, {int evaluationId = 500003}) =>
    'Skore refused the change before saving it: $reason Read the evaluation '
    'again with list_skore_evaluations (gradebook_id 32508, evaluation_id '
    '$evaluationId: its max, its publication and the pupil ids) and the '
    'gradebook with read_skore_gradebook (whether the period is open and the '
    'user may change it) to correct the call. Nothing was changed in Skore.';

/// The parameters of saveGrade for [pupil] in an evaluation of 6EWI, as the
/// web client sends them for a cell (dartschool's `_saveParams`).
List<Object?> _saveParams(int pupil, String grade, {int evaluation = 500003}) =>
    [
      '$evaluation',
      'pupil_${pupil}_2440',
      grade,
      fakeSkoreGradebookUser,
      0,
      0,
      0,
      '0',
      ['176', '472', '2440'],
      '$evaluation',
      '32508',
    ];

/// The calls of the library's saveGrades for [count] pupils, after the
/// tool's own reads: its checks, a saveGrade per pupil, and the period read
/// again.
List<String> _saveCalls(int count) => [
  'getNavigation',
  'init wy=24',
  'getGradebookContext wy=24',
  'getEvaluations wy=24',
  for (var i = 0; i < count; i++) 'saveGrade wy=24',
  'getEvaluations wy=24',
];

/// The tool's own reads before the library is asked, the first time: the
/// gradebooks of the current school year, the gradebook, and the period
/// that holds the evaluation.
const _toolReads = [
  'getNavigation',
  'init wy=24',
  'getGradebookContext wy=24',
  'getEvaluations wy=24',
];

void main() {
  late FakeSmartschool server;
  late FakeSkoreGradebook skore;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skoreGradebook..loadSchool();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listSkoreGradebooksTool(session),
        listSkoreEvaluationsTool(session),
        saveSkoreGradesTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method off the library's list, such as one that publishes.
    expect([
      for (final request in skore.requests) request.rpc,
    ], everyElement(isIn(fakeSkoreGradebookRpcMethods)));
    expect(skore.evaluationSaves, isEmpty, reason: 'nothing is created');
  });

  Future<(bool, String)> call(String tool, Map<String, Object?> arguments) =>
      callTool(connection, tool, arguments).then((call) {
        final (result, text) = call;
        expect(text, isNot(matches(_adminWords)));
        return (result.isError ?? false, text);
      });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (isError, text) = await call(tool, arguments);
    expect(isError, isFalse, reason: text);
    return text;
  }

  /// Saves [grades] (pupil id to grade) in Toets 1 of 6EWI's gradebook, or
  /// what [arguments] give, and returns the result.
  Future<(bool, String)> save(
    Map<int, String?> grades, [
    Map<String, Object?> arguments = const {},
  ]) => call('save_skore_grades', {
    'gradebook_id': 32508,
    'evaluation_id': 500003,
    'grades': [
      for (final MapEntry(:key, :value) in grades.entries)
        {'pupil_id': key, 'grade': value},
    ],
    ...arguments,
  });

  Future<String> saved(
    Map<int, String?> grades, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, text) = await save(grades, arguments);
    expect(isError, isFalse, reason: text);
    return text;
  }

  Future<String> refused(
    Map<int, String?> grades, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, text) = await save(grades, arguments);
    expect(isError, isTrue, reason: text);
    return text;
  }

  /// One evaluation of 6EWI, one line per pupil, as list_skore_evaluations
  /// lists it.
  Future<String> grades([int evaluationId = 500003]) => ok(
    'list_skore_evaluations',
    {'gradebook_id': 32508, 'evaluation_id': evaluationId},
  );

  /// 6EWI's gradebook in the fake.
  FakeSkoreOwnGradebook book() =>
      skore.gradebooks.firstWhere((g) => g.id == 32508);

  /// An evaluation of 6EWI's DW1 in the fake.
  FakeSkoreEvaluation evaluation(int id) => book().evaluationWithId(id)!;

  bool isGradeSave(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path == fakeSkoreGradebookRpcPath &&
      (request.data as Map?)?['rpc_method'] == 'saveGrade';

  /// Logs in with a read, and forgets the requests it made.
  Future<int> loggedIn() async {
    await ok('list_skore_gradebooks', {});
    skore.requests.clear();
    server.requests.clear();
    return server.logins;
  }

  group('the tool is listed', () {
    late Tool tool;

    setUp(() async {
      tool = (await connection.listTools(
        ListToolsRequest(),
      )).tools.singleWhere((tool) => tool.name == 'save_skore_grades');
    });

    test('as a write Claude Desktop asks approval for every time, '
        'idempotent, without a word of "Skore-beheer", rights or '
        'teachers', () {
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.openWorldHint, isTrue);
      final definition = jsonEncode(tool);
      expect(definition, isNot(matches(_adminWords)));
      expect(definition.toLowerCase(), isNot(contains('teacher')));
    });

    test('tells Claude to read the evaluation first, to match names to '
        'pupil ids without guessing, to show the full list and wait for the '
        'user\'s confirmation, and when it may pass allow_published', () {
      final description = tool.description!;
      for (final part in [
        'the whole list in one call',
        'A grade is a number from 0 up to the evaluation\'s max, with a '
            'decimal point or comma (15, 15.5 or 15,5); an empty grade or '
            'null clears it.',
        'Before calling this tool, read the evaluation with '
            'list_skore_evaluations (with its evaluation_id) and match each '
            'name the user gave to a pupil id there; never guess a pupil for '
            'a name that matches no pupil or more than one: ask the user.',
        'Show the user the full list, each pupil with class number and name, '
            'the current grade and the new grade, out of the max, and only '
            'call this tool after the user has explicitly confirmed it.',
        'An evaluation that is published or scheduled is refused unless '
            'allow_published is true: a grade there is visible to its pupils '
            'at once, and the school sends them a notification; in a '
            'scheduled one, from its publication time on. Pass '
            'allow_published: true only after telling the user exactly that '
            'and getting their explicit yes for it.',
        'If the result says some grades may or may not have been saved: '
            'saving a grade again is harmless, so read the evaluation again '
            'with list_skore_evaluations, tell the user what you found, and '
            'save only the grades that differ.',
      ]) {
        expect(description, contains(part));
      }
    });

    test('takes the gradebook, the evaluation and the grades, each a pupil '
        'id with a text or null, and optionally the period and '
        'allow_published', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['gradebook_id', 'evaluation_id', 'grades']);
      final properties = schema.properties!;
      expect(properties.keys, [
        'gradebook_id',
        'evaluation_id',
        'period_id',
        'grades',
        'allow_published',
      ]);
      for (final name in ['gradebook_id', 'evaluation_id', 'period_id']) {
        expect(properties[name], {
          'type': 'integer',
          'description': isA<String>(),
          'minimum': 1,
        }, reason: name);
      }
      expect(jsonDecode(jsonEncode(properties['grades'])), {
        'type': 'array',
        'description': isA<String>(),
        'items': {
          'type': 'object',
          'properties': {
            'pupil_id': {
              'type': 'integer',
              'description': isA<String>(),
              'minimum': 1,
            },
            'grade': {
              'description': isA<String>(),
              'anyOf': [
                {'type': 'string'},
                {'type': 'null'},
              ],
            },
          },
          'required': ['pupil_id', 'grade'],
        },
        'minItems': 1,
      });
      expect(properties['allow_published'], {
        'type': 'boolean',
        'description': isA<String>(),
      });
    });
  });

  group('save_skore_grades', () {
    test('saves the list with one saveGrade per pupil, in the order given, '
        'with the library\'s value, and reports each grade as Skore lists '
        'it after the save; the evaluation lists them from then on', () async {
      final text = await saved({1203: '12.50', 1201: '15', 1202: '15,5'});

      expect(
        text,
        'Saved the grades of 3 pupils in the $_toetsName in $_where.\n'
        'Evaluation: $_toets\n'
        'Grades out of 20 as Skore lists them after the save, in the order '
        'given:\n'
        '- $_chloe | 12.5\n'
        '- $_an | 15\n'
        '- $_bart | 15.5',
      );
      expect(skore.calls, [..._toolReads, ..._saveCalls(3)]);
      // The exact parameters of the web client, with the grade as a plain
      // decimal with a point.
      expect(skore.gradeSaves, [
        _saveParams(1203, '12.5'),
        _saveParams(1201, '15'),
        _saveParams(1202, '15.5'),
      ]);
      final save = skore.requests.firstWhere((r) => r.rpc == 'saveGrade');
      expect(save.session['teacher'], fakeSkoreGradebookUser);
      expect(save.session['wy'], '24');

      expect(
        await grades(),
        endsWith(
          '\n- $_an | 15\n'
          '- $_bart | 15.5 | feedback\n'
          '- $_chloe | 12.5',
        ),
      );
    });

    test('an empty grade or null clears it; saving the same grade again '
        'sends it again and leaves it as it is', () async {
      evaluation(500003).grades.addAll({1201: '12', 1202: '9', 1203: '14'});

      expect(
        await saved({1201: '', 1202: null, 1203: '14'}),
        endsWith(
          '\n- $_an | no grade\n'
          '- $_bart | no grade\n'
          '- $_chloe | 14',
        ),
      );
      expect(skore.gradeSaves, [
        _saveParams(1201, ''),
        _saveParams(1202, ''),
        _saveParams(1203, '14'),
      ]);
      expect(evaluation(500003).grades, {1203: '14'});
    });

    test('one pupil, with period_id: the tool finds the evaluation with one '
        'read of that period; ids written with a decimal part', () async {
      expect(
        await ok('save_skore_grades', {
          'gradebook_id': 32508.0,
          'evaluation_id': 500003.0,
          'period_id': 1704.0,
          'grades': [
            {'pupil_id': 1202.0, 'grade': ' 7 '},
          ],
        }),
        'Saved the grade of 1 pupil in the $_toetsName in $_where.\n'
        'Evaluation: $_toets\n'
        'Grades out of 20 as Skore lists them after the save, in the order '
        'given:\n'
        '- $_bart | 7',
      );
      expect(skore.gradeSaves, [_saveParams(1202, '7')]);
      expect(skore.calls, [..._toolReads, ..._saveCalls(1)]);
    });

    group('a published or scheduled evaluation without allow_published: '
        'refused before the library is asked, saying what the pupils would '
        'see and that the user must say yes to it', () {
      test('published', () async {
        expect(
          await refused({1201: '15'}, {'evaluation_id': 500002}),
          'The evaluation "Lussen" (evaluation id 500002) in $_where is '
          'PUBLISHED since ${_time('2026-10-01T08:00:00+0200')}: its pupils '
          'would see the grades at once, and the school sends them a '
          'notification. Tell the user exactly that, and only if the user '
          'explicitly says yes to it, call save_skore_grades again with '
          'allow_published: true. Nothing was changed in Skore.',
        );
      });

      test('scheduled', () async {
        expect(
          await refused({1201: '15'}, {'evaluation_id': 500001}),
          'The evaluation "Python scripts schrijven" (evaluation id 500001) '
          'in $_where is SCHEDULED for '
          '${_time('2099-01-11T08:00:00+0100')}: its pupils would see the '
          'grades from then on. Tell the user exactly that, and only if the '
          'user explicitly says yes to it, call save_skore_grades again with '
          'allow_published: true. Nothing was changed in Skore.',
        );
      });

      test('allow_published false is the same', () async {
        expect(
          await refused(
            {1201: '15'},
            {'evaluation_id': 500002, 'allow_published': false},
          ),
          startsWith('The evaluation "Lussen" (evaluation id 500002) in '),
        );
      });

      tearDown(() {
        expect(skore.gradeSaves, isEmpty);
        expect(skore.calls, _toolReads, reason: 'the library was not asked');
      });
    });

    test('with allow_published: true, the grades are saved in a published '
        'evaluation, and the result says the pupils see them', () async {
      expect(
        await saved(
          {1203: '13'},
          {'evaluation_id': 500002, 'allow_published': true},
        ),
        'Saved the grade of 1 pupil in the evaluation "Lussen" (evaluation id '
        '500002) in $_where.\n'
        'Evaluation: Lussen | evaluation id 500002 | column C | 2026-09-23 | '
        'max 20 | no component | points | PUBLISHED since '
        '${_time('2026-10-01T08:00:00+0200')}: the pupils see it and its '
        'grades\n'
        'Grades out of 20 as Skore lists them after the save, in the order '
        'given:\n'
        '- $_chloe | 13',
      );
      expect(skore.gradeSaves, [_saveParams(1203, '13', evaluation: 500002)]);
    });

    test('published between the tool\'s read and the library\'s: the '
        'library refuses it, and its reason is passed on', () async {
      var reads = 0;
      skore.beforeAnswer = (rpc, params) {
        if (rpc == 'getEvaluations' && ++reads == 2) {
          evaluation(500003).public = '1';
        }
      };

      expect(
        await refused({1201: '15'}),
        _refused(
          'evaluation 500003 ("Toets 1") in period DW1 (1704) of gradebook '
          '32508 is published (public "1", publicdatetime ""): its pupils see '
          'what is written in it at once. Pass allowPublished: true to write '
          'in it anyway.',
        ),
      );
      expect(skore.gradeSaves, isEmpty);
      expect(skore.calls.last, 'getEvaluations wy=24');
    });

    group('passes on why Skore refused the change, with what to read again, '
        'saving none of the grades:', () {
      test('a grade that is not a number, or above the max', () async {
        expect(
          await refused({1201: '15', 1202: 'vijftien'}),
          _refused(
            'the grade "vijftien" of pupil 1202 is not a number of 0 or more '
            '(such as 15, 15.5 or 15,5), nor empty to clear it.',
          ),
        );
        expect(
          await refused({1201: '15', 1202: '-3', 1203: '12/20'}),
          _refused(
            'the grade "-3" of pupil 1202 is not a number of 0 or more (such '
            'as 15, 15.5 or 15,5), nor empty to clear it; the grade "12/20" '
            'of pupil 1203 is not a number of 0 or more (such as 15, 15.5 or '
            '15,5), nor empty to clear it.',
          ),
        );
        expect(
          await refused({1201: '15', 1202: '20,5'}),
          _refused(
            'in evaluation 500003 ("Toets 1") in period DW1 (1704) of '
            'gradebook 32508, the grade 20.5 of pupil 1202 is above the '
            'highest grade, 20.',
          ),
        );
      });

      test('a gradebook Skore shows read-only', () async {
        book().writable = false;
        expect(
          await refused({1201: '15'}),
          _refused(
            'Skore shows gradebook 32508 read-only to you in period DW1 (1704) '
            '(writable 0).',
          ),
        );
      });

      test('a closed period', () async {
        final periods = book().periods;
        final open = periods.single;
        periods[0] = FakeSkoreGradebookPeriod(
          open.id,
          open.name,
          open: false,
          timestamp: open.timestamp,
          note: open.note,
        );
        expect(
          await refused({1201: '15'}),
          _refused('period DW1 (1704) of gradebook 32508 is closed.'),
        );
      });

      test('an evaluation from the planner, or not in points', () async {
        book().evaluations[1704]!.addAll([
          FakeSkoreEvaluation(
            500004,
            'Taak uit de planner',
            date: '2026-10-08',
            planner: true,
          ),
          FakeSkoreEvaluation(
            500005,
            'Houding',
            date: '2026-10-08',
            evaltype: 2,
            max: null,
          ),
        ]);
        expect(
          await refused({1201: '15'}, {'evaluation_id': 500004}),
          _refused(
            'evaluation 500004 ("Taak uit de planner") in period DW1 (1704) '
            'of gradebook 32508 comes from the planner (isPlannerEval 1): '
            'Skore\'s web client leaves it to the planner.',
            evaluationId: 500004,
          ),
        );
        expect(
          await refused({1201: '15'}, {'evaluation_id': 500005}),
          _refused(
            'evaluation 500005 ("Houding") in period DW1 (1704) of gradebook '
            '32508 is not in points (evaltype 2): the library saves grades in '
            'points only.',
            evaluationId: 500005,
          ),
        );
      });

      tearDown(() {
        expect(skore.gradeSaves, isEmpty);
      });
    });

    test('an empty list or a pupil given twice: an error before anything is '
        'sent', () async {
      // The input schema refuses an empty list.
      expect(
        await refused({}),
        contains(
          'List has 0 items, but must have at least 1 at path '
          '#root["grades"]',
        ),
      );
      final (twice, message) = await call('save_skore_grades', {
        'gradebook_id': 32508,
        'evaluation_id': 500003,
        'grades': [
          {'pupil_id': 1201, 'grade': '15'},
          {'pupil_id': 1202, 'grade': '12'},
          {'pupil_id': 1201, 'grade': '16'},
          {'pupil_id': 1203, 'grade': '9'},
          {'pupil_id': 1203, 'grade': '9'},
        ],
      });
      expect(twice, isTrue);
      expect(
        message,
        'grades lists pupil ids 1201, 1203 more than once: give each pupil '
        'once, with the grade the user confirmed. Nothing was changed in '
        'Skore.',
      );
      // The input schema refuses a grade that is not a text or null (it is
      // required, also to clear one) and a pupil id that is not one.
      final cases = <Map<String, Object?>, String>{
        {'pupil_id': 1201, 'grade': 15}:
            'No sub-schema passed validation for 15 at path '
            '#root["grades"]["0"]["grade"]',
        {'pupil_id': 1201, 'grade': true}:
            'No sub-schema passed validation for true at path '
            '#root["grades"]["0"]["grade"]',
        {'pupil_id': 1201}:
            'Required property "grade" is missing at path #root["grades"]["0"]',
        {'pupil_id': 0, 'grade': '15'}:
            'Value 0 is less than the minimum of 1 at path '
            '#root["grades"]["0"]["pupil_id"]',
      };
      for (final MapEntry(key: item, value: message) in cases.entries) {
        final (isError, text) = await call('save_skore_grades', {
          'gradebook_id': 32508,
          'evaluation_id': 500003,
          'grades': [item],
        });
        expect(isError, isTrue, reason: '$item');
        expect(text, contains(message), reason: '$item');
      }
      expect(skore.requests, isEmpty);
      expect(server.logins, 0);
    });

    test('a pupil the gradebook does not have: an error that names every '
        'one, before the evaluations are read', () async {
      expect(
        await refused({1201: '15', 1999: '12', 1211: '9'}),
        'The $_gradebookName has no pupils with pupil ids 1999, 1211. Take '
        'the pupil ids from list_skore_evaluations with the evaluation_id, '
        'for this gradebook. Nothing was changed in Skore.',
      );
      expect(
        await refused({1999: '12'}),
        'The $_gradebookName has no pupil with pupil id 1999. Take the pupil '
        'ids from list_skore_evaluations with the evaluation_id, for this '
        'gradebook. Nothing was changed in Skore.',
      );
      expect(skore.calls, isNot(contains('getEvaluations wy=24')));
      expect(skore.gradeSaves, isEmpty);
    });

    test('an evaluation the gradebook does not have, or a gradebook of an '
        'earlier school year: an error, nothing saved', () async {
      expect(
        await refused({1201: '15'}, {'evaluation_id': 400101}),
        'The $_gradebookName has no evaluation with evaluation id 400101 in '
        'its only period, DW1 (period id 1704). Take the evaluation id from '
        'list_skore_evaluations, with the period_id of its period. Nothing '
        'was changed in Skore.',
      );
      // 5BW's gradebook of 2025-2026, once listed.
      await ok('list_skore_gradebooks', {'workyear_id': 22});
      expect(
        await refused(
          {1301: '15'},
          {'gradebook_id': 28998, 'evaluation_id': 400101},
        ),
        'Gradebook id 28998 is of school year 2025-2026 (workyear id 22), not '
        'of Skore\'s current school year, 2026-2027 (workyear id 24): only a '
        'gradebook of the current school year can be changed. Nothing was '
        'changed in Skore.',
      );
      expect(skore.gradeSaves, isEmpty);
    });
  });

  group('grades Skore does not confirm are reported per pupil, by name, '
      'with those it confirmed; the call is not repeated:', () {
    test('one pupil\'s save fails: the others are saved, and the result says '
        'to read the grades again and save the ones that differ', () async {
      final logins = await loggedIn();
      skore.gradeSaveFails.add(1202);

      final (isError, text) = await save({1201: '15', 1202: '16', 1203: ''});

      expect(isError, isTrue);
      expect(
        text,
        'The grades of 3 pupils in the $_toetsName in $_where were sent, but '
        'Skore did not confirm 1 of them.\n'
        'Saved, as Skore lists them after the save:\n'
        '- $_an | 15\n'
        '- $_chloe | no grade\n'
        'May or may not have been saved:\n'
        '- $_bart | sent: 16\n'
        'Saving a grade again is harmless: read the evaluation again with '
        'list_skore_evaluations (gradebook_id 32508, evaluation_id 500003, '
        'period_id 1704), tell the user what you found, and save only the '
        'grades that differ from the ones the user confirmed again with '
        'save_skore_grades.',
      );
      // A failed save does not stop the others; the period is read again
      // once, and nothing is sent again.
      expect(skore.gradeSaves, [
        _saveParams(1201, '15'),
        _saveParams(1202, '16'),
        _saveParams(1203, ''),
      ]);
      expect(skore.calls.last, 'getEvaluations wy=24');
      expect(server.logins, logins);

      // What the result asks for: read again, and save the one that
      // differs.
      expect(await grades(), contains('\n- $_bart | no grade | feedback\n'));
      skore.gradeSaveFails.clear();
      expect(await saved({1202: '16'}), endsWith('\n- $_bart | 16'));
      expect(evaluation(500003).grades, {1201: '15', 1202: '16'});
    });

    test('Skore answers every save, but reading again shows another grade '
        'for one pupil', () async {
      skore.onGradeSaved = (book, evaluation, pupilId) {
        if (pupilId == 1203) evaluation.grades[pupilId] = '1';
      };

      final (isError, text) = await save({1201: '15', 1203: '11'});

      expect(isError, isTrue);
      expect(
        text,
        allOf(
          startsWith(
            'The grades of 2 pupils in the $_toetsName in $_where were sent, '
            'but Skore did not confirm 1 of them.\n'
            'Saved, as Skore lists them after the save:\n'
            '- $_an | 15\n'
            'May or may not have been saved:\n'
            '- $_chloe | sent: 11\n',
          ),
          isNot(contains('"1"')),
        ),
      );
      expect(skore.gradeSaves, hasLength(2));
    });

    test('Skore confirms none: no list of saved grades; for one pupil, '
        '"it"', () async {
      skore.answers['saveGrade'] = (
        status: 200,
        body: jsonEncode({
          'result': {'savedState': -1},
          'session': 1,
          'method': 'saveGrade',
        }),
      );

      final (isError, text) = await save({1201: '15', 1202: ''});
      expect(isError, isTrue);
      expect(
        text,
        startsWith(
          'The grades of 2 pupils in the $_toetsName in $_where were sent, '
          'but Skore did not confirm any of them.\n'
          'May or may not have been saved:\n'
          '- $_an | sent: 15\n'
          '- $_bart | sent: empty, to clear the grade\n'
          'Saving a grade again is harmless: ',
        ),
      );
      expect(
        (await save({1203: '9,0'})).$2,
        startsWith(
          'The grade of 1 pupil in the $_toetsName in $_where was sent, but '
          'Skore did not confirm it.\n'
          'May or may not have been saved:\n'
          '- $_chloe | sent: 9\n',
        ),
      );
      expect(skore.gradeSaves, hasLength(3));
    });

    test('Smartschool refuses the session for a later save, also after the '
        'library logged in again: the earlier grades are saved, the rest is '
        'not sent, and the session does not repeat the call', () async {
      final logins = await loggedIn();
      var saves = 0;
      skore.beforeAnswer = (rpc, params) {
        if (rpc == 'saveGrade' && ++saves == 1) {
          server
            ..rejectsAfterLogin = 1
            ..expireSessionBefore(isGradeSave);
        }
      };

      final (isError, text) = await save({1201: '15', 1202: '16', 1203: '9'});

      expect(isError, isTrue);
      expect(
        text,
        startsWith(
          'The grades of 3 pupils in the $_toetsName in $_where were sent, '
          'but Skore did not confirm 2 of them.\n'
          'Saved, as Skore lists them after the save:\n'
          '- $_an | 15\n'
          'May or may not have been saved:\n'
          '- $_bart | sent: 16\n'
          '- $_chloe | sent: 9\n',
        ),
      );
      // Only An's save reached Skore: Bart's was refused twice, Chloé's not
      // sent.
      expect(skore.gradeSaves, [_saveParams(1201, '15')]);
      expect(server.logins, logins + 1);
      expect(evaluation(500003).grades, {1201: '15'});
    });
  });

  test('Smartschool refuses the session for the first save, also after the '
      'library logged in again: nothing was saved, so the session repeats '
      'the call once, which reads the gradebook again and saves each grade '
      'once, with the same value', () async {
    final logins = await loggedIn();
    server
      ..rejectsAfterLogin = 1
      ..expireSessionBefore(isGradeSave);

    expect(
      await saved({1201: '15', 1202: '16,5'}),
      endsWith(
        '\n- $_an | 15\n'
        '- $_bart | 16.5',
      ),
    );
    expect(server.logins, logins + 1);
    // The refused save (sent twice by the library, around its new login)
    // never reached Skore; the repeat read the gradebook again (its school
    // year from memory) and saved each grade once.
    final beforeSave = _saveCalls(0).sublist(0, 4);
    expect(skore.calls, [
      ..._toolReads.skip(1),
      ...beforeSave,
      ..._toolReads.skip(1),
      ..._saveCalls(2),
    ]);
    expect(skore.gradeSaves, [
      _saveParams(1201, '15'),
      _saveParams(1202, '16.5'),
    ]);
    expect(
      server.requests
          .where((request) => request == 'POST $fakeSkoreGradebookRpcPath')
          .length,
      skore.requests.length + 2,
      reason: 'the refused save, sent again after the login, and the rest',
    );
    expect(evaluation(500003).grades, {1201: '15', 1202: '16.5'});
  });

  test('the flow of the issue: read the evaluation, save the grades the '
      'user confirmed, read them back', () async {
    expect(
      await grades(),
      endsWith(
        'Grades out of 20, one line per pupil in Skore\'s order ("feedback": '
        'the pupil has feedback on it, which read_skore_feedback reads):\n'
        '- $_an | no grade\n'
        '- $_bart | no grade | feedback\n'
        '- $_chloe | no grade',
      ),
    );
    expect(
      await saved({1201: '15', 1202: '12,5', 1203: '17'}, {'period_id': 1704}),
      startsWith('Saved the grades of 3 pupils in the $_toetsName in $_where.'),
    );
    expect(
      await grades(),
      allOf(
        contains(
          '\nclass average 14.8 | group average 14.8 | 3 of 3 pupils have a '
          'grade\n',
        ),
        endsWith(
          '\n- $_an | 15\n'
          '- $_bart | 12.5 | feedback\n'
          '- $_chloe | 17',
        ),
      ),
    );
    expect(skore.gradeSaves, hasLength(3));
  });
}

/// [iso], a time with its offset, as the tools show it: `2026-12-18 20:00`
/// in the time of this PC.
String _time(String iso) {
  final local = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
