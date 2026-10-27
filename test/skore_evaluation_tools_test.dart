/// `list_skore_evaluations` and `read_skore_feedback` (#141), called over
/// MCP on the real server, session and library, against a fake Smartschool
/// whose Skore gradebook answers `getEvaluations` and the feedback reads of
/// Skore's REST API in the shape of dartschool's captures of #149
/// (`test/support/fake_skore_gradebook.dart`). Like the other gradebook
/// tools, they need no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/skore/skore_gradebook_access.dart';
import 'package:smartschool_mcp/src/tools/list_skore_evaluations_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_feedback_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

/// [iso], a time with its offset, as the tools show it: `2026-12-18 20:00`
/// in the time of this PC.
String _time(String iso) {
  final local = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// What no gradebook text may say: the gradebook is not behind the switch
/// "Skore-beheer", and needs no extra rights.
final _adminWords = RegExp(
  r'Skore-beheer|SMARTSCHOOL_SKORE|rights|administrator|score management',
  caseSensitive: false,
);

const _ewiTitle =
    'Gradebook id 32508: Informaticawetenschappen (2 uur) (6e j DO), class '
    '6EWI, school year 2026-2027 (workyear id 24).';

const _bwTitle =
    'Gradebook id 28998: Informaticawetenschappen (2 uur) (5e j DG), class '
    '5BW, school year 2025-2026 (workyear id 22).';

/// 6EWI's period DW1, the active one.
final _dw1 =
    'Period DW1 (period id 1704): open, closes '
    '${_time('2026-12-18T20:00:00+0100')}; Skore opens the gradebook on it '
    '(active).';

/// The line before the evaluations of a period, for [count] of them.
String _evaluationsHeader(int count) =>
    '$count ${count == 1 ? 'evaluation' : 'evaluations'}, in Skore\'s order, '
    'each with the grade of every pupil ("(feedback)": the pupil has '
    'feedback on it, which read_skore_feedback reads):';

/// The three evaluations of 6EWI's DW1 (see `fakeSkoreGradebook6EWI`).
const _toets =
    'Toets 1 | evaluation id 500003 | column A | 2026-10-08 | max 20 | '
    'component DW | points | not published: the pupils do not see it';
final _python =
    'Python scripts schrijven (short name toets-python) | evaluation id '
    '500001 | column B | 2026-09-30 | max 100 | component DW | points | '
    'SCHEDULED for ${_time('2099-01-11T08:00:00+0100')}: from then on the '
    'pupils see it and its grades';
final _lussen =
    'Lussen | evaluation id 500002 | column C | 2026-09-23 | max 20 | no '
    'component | points | PUBLISHED since '
    '${_time('2026-10-01T08:00:00+0200')}: the pupils see it and its grades';

/// The line about the components of 6EWI's DW1, an open period: the two
/// Skore offers, and DW, the second of the two, by default.
const _components =
    'Components a new evaluation in this period can count for '
    '(create_skore_evaluation\'s component): geen (component id 0: none), DW '
    '(component id 2). Default: DW.';

/// The general error of an answer the server cannot use.
const _unusable = skoreGradebookUnusableAnswer;

/// The fake's scale (`fakeSkoreScale`), as the tools list it (#169).
const _scale =
    'The scale "Gedragsschaal" of the evaluations on a scale, from low to '
    'high: Onvoldoende (O) from 0% of the max, Voldoende (V) from 50%, Zeer '
    'goed (ZG) from 80%. Skore stores a value on it as a number out of the '
    'evaluation\'s max.';

/// The evaluations of a period that mixes points, a scale and a type the
/// library does not know (see `fakeSkoreMixedEvaluations`), as the tools
/// list them (#169).
const _toetsLussen =
    'Toets lussen | evaluation id 500011 | column A | 2026-10-05 | max 20 | '
    'component DW | points | not published: the pupils do not see it';
const _inzet =
    'Inzet in de les (short name inzet) | evaluation id 500012 | column B | '
    '2026-10-06 | max 10 | no component | a scale | not published: the '
    'pupils do not see it';
const _attitudes =
    'Attitudes | evaluation id 500013 | column C | 2026-10-07 | no max | no '
    'component | a type the server does not support (evaltype 3) | not '
    'published: the pupils do not see it';
const _attitudesNotRead =
    'The server cannot read the grades of this evaluation: it is of a type '
    'the server does not support yet (Skore\'s evaltype 3; the server reads '
    'evaluations in points and on a scale). The user sees them in Skore in '
    'Smartschool itself.';

void main() {
  late FakeSmartschool server;
  late FakeSkoreGradebook skore;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skoreGradebook..loadSchool();
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listSkoreEvaluationsTool(session),
        readSkoreFeedbackTool(session),
      ],
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

  Future<String> list(Map<String, Object?> arguments) =>
      ok('list_skore_evaluations', arguments);

  Future<String> feedback(Map<String, Object?> arguments) =>
      ok('read_skore_feedback', arguments);

  /// The periods `getEvaluations` was asked for, in order.
  List<Object?> evaluationReads() => [
    for (final request in skore.requests)
      if (request.rpc == 'getEvaluations') request.params.first,
  ];

  /// A gradebook of the fake by its id.
  FakeSkoreOwnGradebook book(int id) =>
      skore.gradebooks.firstWhere((g) => g.id == id);

  group('the tools are listed', () {
    late Map<String, Tool> tools;

    setUp(() async {
      tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
    });

    test('read-only and idempotent, without a word of "Skore-beheer" or '
        'rights, nor of teachers (pupils sign in too)', () {
      expect(tools.keys, ['list_skore_evaluations', 'read_skore_feedback']);
      for (final tool in tools.values) {
        final annotations = tool.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: tool.name);
        expect(annotations.idempotentHint, isTrue, reason: tool.name);
        expect(annotations.openWorldHint, isTrue, reason: tool.name);
        expect(annotations.destructiveHint, isNot(true), reason: tool.name);
        final definition = jsonEncode(tool);
        expect(definition, isNot(matches(_adminWords)), reason: tool.name);
        expect(
          definition.toLowerCase(),
          isNot(contains('teacher')),
          reason: tool.name,
        );
        expect(
          tool.description,
          contains('Reading changes nothing in Skore.'),
          reason: tool.name,
        );
      }
    });

    test('list_skore_evaluations takes a gradebook id and optionally a '
        'period, an evaluation and a school year; read_skore_feedback a '
        'gradebook, an evaluation and a pupil, and optionally a period and a '
        'school year', () {
      final listSchema = tools['list_skore_evaluations']!.inputSchema;
      expect(listSchema.required, ['gradebook_id']);
      expect(listSchema.properties!.keys, [
        'gradebook_id',
        'period_id',
        'evaluation_id',
        'workyear_id',
      ]);
      final readSchema = tools['read_skore_feedback']!.inputSchema;
      expect(readSchema.required, [
        'gradebook_id',
        'evaluation_id',
        'pupil_id',
      ]);
      expect(readSchema.properties!.keys, [
        'gradebook_id',
        'evaluation_id',
        'pupil_id',
        'period_id',
        'workyear_id',
      ]);
      for (final schema in [listSchema, readSchema]) {
        for (final property in schema.properties!.values) {
          expect((property as Map)['minimum'], 1);
        }
      }
      final listDescription = tools['list_skore_evaluations']!.description!;
      expect(
        listDescription,
        contains(
          'its evaluation id (the id to use: Skore\'s column letter changes '
          'when an evaluation is added)',
        ),
      );
      expect(
        listDescription,
        contains(
          'The pupils see a published evaluation and its grades, and a '
          'scheduled one from its time on',
        ),
      );
      expect(
        tools['read_skore_feedback']!.description,
        contains('pass the period_id of the evaluation too'),
      );
    });
  });

  group('list_skore_evaluations', () {
    test('the active period by default: each evaluation with its id, column, '
        'date, max, component, type and publication, its averages and the '
        'grade of every pupil by name, marked when the pupil has feedback; '
        'then the pupil ids and, for an open period, the components a new '
        'evaluation can count for. The gradebook, then one getEvaluations '
        'and one getPosComponents for the period, as the user, for its '
        'school year', () async {
      expect(
        await list({'gradebook_id': 32508}),
        '$_ewiTitle\n'
        '$_dw1\n'
        '${_evaluationsHeader(3)}\n'
        '- $_toets\n'
        '  no class average | no group average | 0 of 3 pupils have a grade\n'
        '  grades: 1. Aerts, An: no grade; 2. Claes, Bart: no grade '
        '(feedback); 3. Dupont, Chloé: no grade\n'
        '- $_python\n'
        '  class average 47.3 | group average 47.3 | 2 of 3 pupils have a '
        'grade\n'
        '  grades: 1. Aerts, An: 79 (feedback); 2. Claes, Bart: 15.5 '
        '(feedback); 3. Dupont, Chloé: no grade\n'
        '- $_lussen\n'
        '  class average 14.3 | group average 14.3 | 3 of 3 pupils have a '
        'grade\n'
        '  grades: 1. Aerts, An: 14; 2. Claes, Bart: 17; 3. Dupont, Chloé: '
        '12\n'
        'Pupils: 1. Aerts, An (pupil id 1201); 2. Claes, Bart (pupil id '
        '1202); 3. Dupont, Chloé (pupil id 1203).\n'
        '$_components',
      );
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
        'getPosComponents wy=24',
      ]);
      // As Skore's "new evaluation" dialog asks for them.
      expect(skore.requests.last.params, [
        0,
        1704,
        '472',
        '2264',
        ['176', '472', '2440'],
      ]);
      final read = skore.requests[3];
      expect(read.params, [
        1704,
        fakeSkoreGradebookUser,
        ['2264'],
        '472',
        '2440',
        ['176', '472', '2440'],
      ]);
      expect(read.session['teacher'], fakeSkoreGradebookUser);
      expect(skore.feedbackReads, isEmpty);
    });

    test('a period of an earlier school year by period_id: closed, pupils '
        'without a class number, one inactive, and the other periods of the '
        'gradebook', () async {
      expect(
        await list({
          'gradebook_id': 28998,
          'workyear_id': 22,
          'period_id': 1446,
        }),
        '$_bwTitle\n'
        'Period DW1 (period id 1446): closed, closing time '
        '${_time('2025-12-18T20:00:00+0100')}.\n'
        '${_evaluationsHeader(1)}\n'
        '- Databanken | evaluation id 400101 | column A | 2025-10-15 | max 20 '
        '| component DW | points | PUBLISHED since '
        '${_time('2025-10-16T08:00:00+0200')}: the pupils see it and its '
        'grades\n'
        '  class average 14.0 | group average 14.0 | 1 of 2 pupils have a '
        'grade\n'
        '  grades: Maes, Lotte: 14 (feedback); Verbeke, Fien (inactive): no '
        'grade\n'
        'Pupils: Maes, Lotte (pupil id 1301); Verbeke, Fien (pupil id 1302).\n'
        'Other periods of the gradebook: DW4 (period id 1608), DW5 (period id '
        '1610, active). Pass period_id for one of them.',
      );
      expect(skore.calls, [
        'getNavigation wy=22',
        'init wy=22',
        'getGradebookContext wy=22',
        'getEvaluations wy=22',
      ]);
      expect(evaluationReads(), [1446]);
      // Without period_id: the active period, with an evaluation from the
      // planner.
      expect(
        await list({'gradebook_id': 28998, 'workyear_id': 22}),
        contains(
          '\n- Eindproject | evaluation id 400201 | column A | 2026-06-10 | '
          'max 50 | component DW | points | from the planner | PUBLISHED '
          'since ${_time('2026-06-11T08:00:00+0200')}: the pupils see it and '
          'its grades\n',
        ),
      );
      expect(evaluationReads(), [1446, 1610]);
    });

    test('a period without evaluations: a sentence, not an error', () async {
      expect(
        await list({
          'gradebook_id': 28998,
          'workyear_id': 22,
          'period_id': 1608,
        }),
        '$_bwTitle\n'
        'Period DW4 (period id 1608): closed, closing time '
        '${_time('2026-04-02T23:00:00+0200')}.\n'
        'It has no evaluations.\n'
        'Other periods of the gradebook: DW1 (period id 1446), DW5 (period id '
        '1610, active). Pass period_id for one of them.',
      );
    });

    test('a gradebook without periods: a sentence, and no evaluations are '
        'asked for', () async {
      book(32504).periods.clear();
      expect(
        await list({'gradebook_id': 32504}),
        'Gradebook id 32504: Informaticawetenschappen (2 uur) (6e j DO), '
        'class 6WEWI2, school year 2026-2027 (workyear id 24).\n'
        'It has no evaluation periods yet, so it has no evaluations.',
      );
      expect(skore.calls, ['getNavigation', 'init wy=24']);
    });

    test('a gradebook with report periods only, as Skore shows the behaviour '
        'gradebook "Gedrag" (#168): no evaluation periods, so no '
        'evaluations, and its course comments are in its report periods; '
        'with a period_id or an evaluation_id, and for the feedback, an '
        'error that says the same; no evaluations are asked for', () async {
      skore.gradebooks.add(fakeSkoreGradebookGedrag());
      const gradebook =
          'gradebook of 5WW1 for Gedrag (A-stroom, D/A en D) (gradebook id '
          '34901)';
      expect(
        await list({'gradebook_id': 34901}),
        'Gradebook id 34901: Gedrag (A-stroom, D/A en D), class 5WW1, school '
        'year 2026-2027 (workyear id 24).\n'
        'It has no evaluation periods, only report periods, so it has no '
        'evaluations.\n'
        'Its course comments, one per pupil, are written in its report '
        'periods and go on the report.',
      );
      // The report's id is not a period id.
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 34901,
          'period_id': 2762,
        }),
        'The $gradebook has no period with period id 2762: it has no '
        'evaluation periods, only report periods, so it has no evaluations. '
        'Leave out period_id.',
      );
      const noEvaluation =
          'The $gradebook has no evaluation periods, only report periods, so '
          'it has no evaluation with evaluation id 500001.';
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 34901,
          'evaluation_id': 500001,
        }),
        noEvaluation,
      );
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 34901,
          'evaluation_id': 500001,
          'pupil_id': 1221,
        }),
        noEvaluation,
      );
      expect(evaluationReads(), isEmpty);
      expect(skore.calls, isNot(contains(startsWith('getGradebookContext'))));
    });

    test('a period_id that is not one of the gradebook\'s: an error that '
        'lists its periods, before any evaluations are read', () async {
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 28998,
          'workyear_id': 22,
          'period_id': 1704,
        }),
        'The gradebook of 5BW for Informaticawetenschappen (2 uur) (5e j DG) '
        '(gradebook id 28998) has no period with period id 1704. Its '
        'periods, in Skore\'s order: DW1 (period id 1446, closed), DW4 '
        '(period id 1608, closed), DW5 (period id 1610, closed, active). Take '
        'a period id from these, or leave out period_id for the period Skore '
        'opens the gradebook on (active).',
      );
      book(32504).periods.clear();
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 32504,
          'period_id': 1704,
        }),
        'The gradebook of 6WEWI2 for Informaticawetenschappen (2 uur) (6e j '
        'DO) (gradebook id 32504) has no period with period id 1704: it has '
        'no evaluation periods yet, so it has no evaluations. Leave out '
        'period_id.',
      );
      expect(evaluationReads(), isEmpty);
    });

    test('evaluation_id: that evaluation only, one line per pupil with the '
        'pupil id, the grade out of the max, and "feedback"; found in the '
        'active period with one getEvaluations', () async {
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500001}),
        '$_ewiTitle\n'
        '$_dw1\n'
        'Evaluation: $_python\n'
        'class average 47.3 | group average 47.3 | 2 of 3 pupils have a '
        'grade\n'
        'Grades out of 100, one line per pupil in Skore\'s order ("feedback": '
        'the pupil has feedback on it, which read_skore_feedback reads):\n'
        '- 1. Aerts, An | pupil id 1201 | 79 | feedback\n'
        '- 2. Claes, Bart | pupil id 1202 | 15.5 | feedback\n'
        '- 3. Dupont, Chloé | pupil id 1203 | no grade',
      );
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
      ]);
    });

    test('evaluation_id without period_id, in an earlier period: the active '
        'period is read first, then the others from the last to the first, '
        'until it is found; with period_id only that one', () async {
      expect(
        await list({
          'gradebook_id': 28998,
          'workyear_id': 22,
          'evaluation_id': 400101,
        }),
        '$_bwTitle\n'
        'Period DW1 (period id 1446): closed, closing time '
        '${_time('2025-12-18T20:00:00+0100')}.\n'
        'Evaluation: Databanken | evaluation id 400101 | column A | '
        '2025-10-15 | max 20 | component DW | points | PUBLISHED since '
        '${_time('2025-10-16T08:00:00+0200')}: the pupils see it and its '
        'grades\n'
        'class average 14.0 | group average 14.0 | 1 of 2 pupils have a '
        'grade\n'
        'Grades out of 20, one line per pupil in Skore\'s order ("feedback": '
        'the pupil has feedback on it, which read_skore_feedback reads):\n'
        '- Maes, Lotte | pupil id 1301 | 14 | feedback\n'
        '- Verbeke, Fien | pupil id 1302 | inactive (greyed out in Skore) | '
        'no grade',
      );
      expect(evaluationReads(), [1610, 1608, 1446]);
      skore.requests.clear();
      await list({
        'gradebook_id': 28998,
        'workyear_id': 22,
        'period_id': 1446,
        'evaluation_id': 400101,
      });
      expect(evaluationReads(), [1446]);
    });

    test('an evaluation_id the gradebook does not have: an error that says '
        'where it looked and where to take the id from', () async {
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 28998,
          'workyear_id': 22,
          'evaluation_id': 500001,
        }),
        'The gradebook of 5BW for Informaticawetenschappen (2 uur) (5e j DG) '
        '(gradebook id 28998) has no evaluation with evaluation id 500001 in '
        'any of its periods, read in this order: DW5 (period id 1610), DW4 '
        '(period id 1608), DW1 (period id 1446). Take the evaluation id from '
        'list_skore_evaluations, with the period_id of its period.',
      );
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 32508,
          'evaluation_id': 400101,
        }),
        'The gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
        '(gradebook id 32508) has no evaluation with evaluation id 400101 in '
        'its only period, DW1 (period id 1704). Take the evaluation id from '
        'list_skore_evaluations, with the period_id of its period.',
      );
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 28998,
          'workyear_id': 22,
          'period_id': 1610,
          'evaluation_id': 400101,
        }),
        'Period DW5 (period id 1610) of the gradebook of 5BW for '
        'Informaticawetenschappen (2 uur) (5e j DG) (gradebook id 28998) has '
        'no evaluation with evaluation id 400101. Take the evaluation id from '
        'list_skore_evaluations for that period, or leave out period_id to '
        'look in every period of the gradebook.',
      );
    });

    test('a scale without a max, published without a time, without a short '
        'name or component, from the planner, and a type Skore does not '
        'name, whose grades the library does not read: the evaluation with '
        'the reason, the rest of the period read (flutter_smartschool 0.4.0, '
        'yvanvds/dartschool#193; #170, #169)', () async {
      book(32508).evaluations[1704] = [
        FakeSkoreEvaluation(
          500005,
          'Houding',
          date: '2026-10-05',
          max: null,
          componentId: 0,
          component: '',
          evaltype: 2,
          planner: true,
          public: '1',
          grades: {1201: 'G'},
        ),
        FakeSkoreEvaluation(500006, 'Project', date: '2026-10-06', evaltype: 7),
      ];
      final text = await list({'gradebook_id': 32508});
      // A value of a scale without a max has no level.
      expect(
        text,
        contains(
          '\n- Houding | evaluation id 500005 | column A | 2026-10-05 | no max '
          '| no component | a scale | from the planner | PUBLISHED: the '
          'pupils see it and its grades\n'
          '  no class average | no group average | 1 of 3 pupils have a '
          'grade\n'
          '  grades: 1. Aerts, An: G (no level of the scale); 2. Claes, Bart: '
          'no grade; 3. Dupont, Chloé: no grade\n',
        ),
      );
      const project =
          'Project | evaluation id 500006 | column B | 2026-10-06 | max 20 | '
          'component DW | a type the server does not support (evaltype 7) | '
          'not published: the pupils do not see it';
      const notRead =
          'The server cannot read the grades of this evaluation: it is of a '
          'type the server does not support yet (Skore\'s evaltype 7; the '
          'server reads evaluations in points and on a scale). The user sees '
          'them in Skore in Smartschool itself.';
      expect(text, contains('\n- $project\n  $notRead\n$_scale\nPupils: '));
      skore.scaleReads.clear();
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500006}),
        endsWith('\nEvaluation: $project\n$notRead'),
      );
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500006,
          'pupil_id': 1201,
        }),
        endsWith(
          '\nEvaluation: $project\n'
          'Pupil: 1. Aerts, An | pupil id 1201 | grade not read\n'
          '$notRead\n'
          'The pupil has no feedback on this evaluation.',
        ),
      );
      // Not on a scale: the scale is not read.
      expect(skore.scaleReads, isEmpty);
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500005}),
        endsWith(
          '\n$_scale\n'
          'Values on the scale, one line per pupil in Skore\'s order: the '
          'level, with its abbreviation, and the value Skore stores '
          '("feedback": the pupil has feedback on it, which '
          'read_skore_feedback reads):\n'
          '- 1. Aerts, An | pupil id 1201 | G (no level of the scale)\n'
          '- 2. Claes, Bart | pupil id 1202 | no grade\n'
          '- 3. Dupont, Chloé | pupil id 1203 | no grade',
        ),
      );
    });

    test('a pupil without a cell, and a cell of a pupil the gradebook does '
        'not list: shown as such', () async {
      final ewi = book(32508);
      ewi.evaluations[1704]!.first.withoutCell.add(1203);
      ewi.cellsOnly.add(
        const FakeSkoreGradebookPupil(1209, 'Nieuw, Nina', 'Nina Nieuw'),
      );
      ewi.evaluations[1704]!.first.grades[1209] = '11';
      expect(
        await list({'gradebook_id': 32508}),
        contains(
          '\n  grades: 1. Aerts, An: no grade; 2. Claes, Bart: no grade '
          '(feedback); 3. Dupont, Chloé: no cell; pupil id 1209: 11\n',
        ),
      );
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500003}),
        endsWith(
          '\n- 3. Dupont, Chloé | pupil id 1203 | no cell\n'
          '- pupil id 1209 | 11',
        ),
      );
    });

    test('the evaluations are read again on every call, the gradebooks of the '
        'school year once', () async {
      await list({'gradebook_id': 32508});
      book(32508).evaluations[1704]!.first.grades[1201] = '18';
      expect(
        await list({'gradebook_id': 32508}),
        contains('\n  grades: 1. Aerts, An: 18; 2. Claes, Bart'),
      );
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
        'getPosComponents wy=24',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
        'getPosComponents wy=24',
      ]);
    });

    test('the components of an open period, with the default '
        'create_skore_evaluation takes: geen when Skore offers more than two, '
        'none without geen; a closed period gets no line, and they are not '
        'read', () async {
      final components = book(32508).components;
      components.add(['4', 'PW']);
      expect(
        await list({'gradebook_id': 32508}),
        endsWith(
          '\nComponents a new evaluation in this period can count for '
          '(create_skore_evaluation\'s component): geen (component id 0: '
          'none), DW (component id 2), PW (component id 4). Default: geen.',
        ),
      );
      components
        ..clear()
        ..add(['2', 'DW']);
      expect(
        await list({'gradebook_id': 32508}),
        endsWith(
          '\nComponents a new evaluation in this period can count for '
          '(create_skore_evaluation\'s component): DW (component id 2). No '
          'default: pass one as component.',
        ),
      );
      components.clear();
      expect(
        await list({'gradebook_id': 32508}),
        endsWith(
          '\nSkore offers no components for a new evaluation in this period.',
        ),
      );
      // A period without evaluations, open: the components after the
      // sentence.
      expect(
        await list({'gradebook_id': 34826}),
        endsWith('\nIt has no evaluations.\n$_components'),
      );
      // 5BW's periods are closed.
      skore.requests.clear();
      for (final periodId in [1446, 1608]) {
        expect(
          await list({
            'gradebook_id': 28998,
            'workyear_id': 22,
            'period_id': periodId,
          }),
          isNot(contains('omponents')),
        );
      }
      expect(skore.calls, isNot(contains(startsWith('getPosComponents'))));
    });

    test('components Skore\'s gradebook gives in a shape the library does '
        'not know: the evaluations are listed, with a line that says the '
        'components could not be read', () async {
      skore.answers['getPosComponents'] = (
        status: 200,
        body: '{"result":{"comps":"DW"},"session":1}',
      );
      expect(
        await list({'gradebook_id': 32508}),
        allOf(
          contains('\n- Lussen | evaluation id 500002 | column C |'),
          endsWith(
            '(pupil id 1203).\nThe components a new evaluation in this period '
            'can count for could not be read; the technical details are in '
            'the server log.',
          ),
        ),
      );
    });

    test('an unknown gradebook id: the error of the gradebook tools', () async {
      expect(
        await error('list_skore_evaluations', {'gradebook_id': 99999}),
        startsWith(
          'None of the user\'s own gradebooks in Skore of school year '
          '2026-2027 (workyear id 24) has gradebook id 99999. Take the '
          'gradebook id from list_skore_gradebooks',
        ),
      );
      expect(evaluationReads(), isEmpty);
    });
  });

  group('evaluations on a scale (#169, flutter_smartschool 0.4.0)', () {
    test('a period that mixes points, a scale and a type the server does '
        'not support: the points as Skore stores them, each value on the '
        'scale with its level\'s label and abbreviation, the scale once '
        '(read once per call: the page and the frame of Skore\'s '
        'gradebook), and the other type with why; a period in points only '
        'reads no scale', () async {
      await list({'gradebook_id': 32508});
      expect(skore.scaleReads, isEmpty);

      book(32508).evaluations[1704] = fakeSkoreMixedEvaluations();
      expect(
        await list({'gradebook_id': 32508}),
        '$_ewiTitle\n'
        '$_dw1\n'
        '${_evaluationsHeader(3)}\n'
        '- $_toetsLussen\n'
        '  class average 11.8 | group average 11.8 | 2 of 3 pupils have a '
        'grade\n'
        '  grades: 1. Aerts, An: 14; 2. Claes, Bart: 9.5; 3. Dupont, Chloé: '
        'no grade\n'
        '- $_inzet\n'
        '  class average 7.5 | group average 7.5 | 2 of 3 pupils have a '
        'grade\n'
        '  grades: 1. Aerts, An: Zeer goed (ZG; stored as 10) (feedback); '
        '2. Claes, Bart: Voldoende (V; stored as 5); 3. Dupont, Chloé: no '
        'grade (feedback)\n'
        '- $_attitudes\n'
        '  $_attitudesNotRead\n'
        '$_scale\n'
        'Pupils: 1. Aerts, An (pupil id 1201); 2. Claes, Bart (pupil id '
        '1202); 3. Dupont, Chloé (pupil id 1203).\n'
        '$_components',
      );
      // The frame answers `not good` to another secret than the page's.
      expect(skore.scaleReads, ['page', 'frame']);

      // One evaluation on the scale, one line per pupil.
      skore.scaleReads.clear();
      expect(
        await list({
          'gradebook_id': 32508,
          'evaluation_id': 500012,
          'period_id': 1704,
        }),
        '$_ewiTitle\n'
        '$_dw1\n'
        'Evaluation: $_inzet\n'
        'class average 7.5 | group average 7.5 | 2 of 3 pupils have a '
        'grade\n'
        '$_scale\n'
        'Values on the scale, one line per pupil in Skore\'s order: the '
        'level, with its abbreviation, and the value Skore stores out of 10 '
        '("feedback": the pupil has feedback on it, which '
        'read_skore_feedback reads):\n'
        '- 1. Aerts, An | pupil id 1201 | Zeer goed (ZG; stored as 10) | '
        'feedback\n'
        '- 2. Claes, Bart | pupil id 1202 | Voldoende (V; stored as 5)\n'
        '- 3. Dupont, Chloé | pupil id 1203 | no grade | feedback',
      );
      expect(skore.scaleReads, ['page', 'frame']);

      // The others of the period read no scale.
      skore.scaleReads.clear();
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500011}),
        endsWith(
          '\nGrades out of 20, one line per pupil in Skore\'s order '
          '("feedback": the pupil has feedback on it, which '
          'read_skore_feedback reads):\n'
          '- 1. Aerts, An | pupil id 1201 | 14\n'
          '- 2. Claes, Bart | pupil id 1202 | 9.5\n'
          '- 3. Dupont, Chloé | pupil id 1203 | no grade',
        ),
      );
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500013}),
        endsWith('\nEvaluation: $_attitudes\n$_attitudesNotRead'),
      );
      expect(skore.scaleReads, isEmpty);
    });

    test('read_skore_feedback on an evaluation on the scale: the pupil\'s '
        'level with its label, and every feedback, whoever wrote it; the '
        'scale is read once, and not for an evaluation in points', () async {
      book(32508).evaluations[1704] = fakeSkoreMixedEvaluations();
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500012,
          'pupil_id': 1201,
          'period_id': 1704,
        }),
        '$_ewiTitle\n'
        'Period: DW1 (period id 1704).\n'
        'Evaluation: $_inzet\n'
        'Pupil: 1. Aerts, An | pupil id 1201 | grade Zeer goed (ZG; stored '
        'as 10)\n'
        '1 feedback text on it, in the order it was written:\n'
        '- by the user, Jan Peeters (user id 345) | written '
        '${_time('2026-10-06T15:10:00+02:00')} | the user may change it\n'
        '  Werkt elke les goed mee.',
      );
      expect(skore.scaleReads, ['page', 'frame']);
      expect(
        skore.feedbackReads.single.path,
        '/skore/api/v1/gradebook/feedback/12_500012/student/12_1201_0/class/'
        '12_2440/teacher/12_345_0/context/176_472_2440',
      );
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500012,
          'pupil_id': 1203,
          'period_id': 1704,
        }),
        endsWith(
          '\nPupil: 3. Dupont, Chloé | pupil id 1203 | no grade\n'
          '1 feedback text on it, in the order it was written:\n'
          '- by Céline Dupré (user id 346) | written '
          '${_time('2026-10-06T16:00:00+02:00')} | the user may not change '
          'it\n'
          '  Komt vaak te laat in de les.',
        ),
      );
      skore.scaleReads.clear();
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500011,
          'pupil_id': 1202,
          'period_id': 1704,
        }),
        contains('\nPupil: 2. Claes, Bart | pupil id 1202 | grade 9.5\n'),
      );
      expect(skore.scaleReads, isEmpty);
    });

    test('a scale the library cannot read: the values as Skore stores '
        'them, with a sentence that the labels could not be read, and the '
        'reason in the server log only', () async {
      book(32508).evaluations[1704] = fakeSkoreMixedEvaluations();
      skore.frameAnswer =
          '<!DOCTYPE html><html><head><title>Skore</title></head><body>'
          '</body></html>';
      const notRead =
          'The scale of the evaluations on a scale could not be read, so '
          'their values are shown as Skore stores them (a number out of the '
          'max), without their labels; the technical details are in the '
          'server log.';
      // A connection of its own, so that the server's log is captured.
      final (texts, logged) = await captureLog(() async {
        final (connection, _) = await connect(
          tools: [
            listSkoreEvaluationsTool(session),
            readSkoreFeedbackTool(session),
          ],
        );
        return [
          for (final (tool, arguments) in [
            ('list_skore_evaluations', {'gradebook_id': 32508}),
            (
              'list_skore_evaluations',
              {'gradebook_id': 32508, 'evaluation_id': 500012},
            ),
            (
              'read_skore_feedback',
              {
                'gradebook_id': 32508,
                'evaluation_id': 500012,
                'pupil_id': 1201,
              },
            ),
          ])
            (await callTool(connection, tool, arguments)).$2,
        ];
      });
      expect(
        texts[0],
        contains(
          '\n  grades: 1. Aerts, An: 10 (feedback); 2. Claes, Bart: 5; 3. '
          'Dupont, Chloé: no grade (feedback)\n'
          '- $_attitudes\n'
          '  $_attitudesNotRead\n'
          '$notRead\n'
          'Pupils: ',
        ),
      );
      expect(
        texts[1],
        endsWith(
          '\n$notRead\n'
          'Values on the scale as Skore stores them out of 10, one line per '
          'pupil in Skore\'s order ("feedback": the pupil has feedback on '
          'it, which read_skore_feedback reads):\n'
          '- 1. Aerts, An | pupil id 1201 | 10 | feedback\n'
          '- 2. Claes, Bart | pupil id 1202 | 5\n'
          '- 3. Dupont, Chloé | pupil id 1203 | no grade | feedback',
        ),
      );
      expect(
        texts[2],
        contains(
          '\nPupil: 1. Aerts, An | pupil id 1201 | grade 10\n'
          '$notRead\n'
          '1 feedback text on it',
        ),
      );
      expect(
        logged,
        contains(
          'skore gradebook: the scale of the evaluations on a scale: '
          'SmartschoolSkoreError: The frame of Skore\'s gradebook '
          '($fakeSkoreGradebookFramePath) holds no defaultScale',
        ),
      );

      // Skore does not take the start-up secret: the library asks for the
      // page and the frame once more.
      skore
        ..frameAnswer = 'not good'
        ..scaleReads.clear();
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500012}),
        contains('\n$notRead\n'),
      );
      expect(skore.scaleReads, ['page', 'frame', 'page', 'frame']);
    });

    test('a cell of an evaluation on a scale in a shape the server does '
        'not know: that evaluation with why, the rest of the period read, '
        'and no scale read', () async {
      final evaluations = fakeSkoreMixedEvaluations();
      evaluations[1].cells[1202] = '<div class="gbc_scale">V</div>';
      book(32508).evaluations[1704] = evaluations;
      final text = await list({'gradebook_id': 32508});
      expect(
        text,
        contains(
          '\n  grades: 1. Aerts, An: 14; 2. Claes, Bart: 9.5; 3. Dupont, '
          'Chloé: no grade\n'
          '- $_inzet\n'
          '  The server cannot read the grades of this evaluation: Skore '
          'gave its grades in a shape the server does not know yet (the '
          'cell of row "pupil_1202_2440" has no value (a div.gbc with its '
          'raw)). The user sees them in Skore in Smartschool itself.\n'
          '- $_attitudes\n'
          '  $_attitudesNotRead\n'
          'Pupils: ',
        ),
      );
      expect(skore.scaleReads, isEmpty);
    });
  });

  group('read_skore_feedback', () {
    test('every feedback of the pupil on the evaluation, in the order '
        'written, from the user (marked) and a colleague: when written and '
        'changed, attachments, whether the user may change it, and the '
        'text line by line; with the evaluation and the pupil\'s grade. The '
        'gradebook, one getEvaluations and one feedback read, at the path '
        'of the feedback panel', () async {
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500001,
          'pupil_id': 1202,
        }),
        '$_ewiTitle\n'
        'Period: DW1 (period id 1704).\n'
        'Evaluation: $_python\n'
        'Pupil: 2. Claes, Bart | pupil id 1202 | grade 15.5\n'
        '2 feedback texts on it, in the order they were written:\n'
        '- by the user, Jan Peeters (user id 345) | written '
        '${_time('2026-10-08T09:49:36+02:00')} | the user may change it\n'
        '  Eerste opmerking.\n'
        '  Let op de foutafhandeling.\n'
        '- by Céline Dupré (user id 346) | written '
        '${_time('2026-10-08T10:02:11+02:00')}, changed '
        '${_time('2026-10-08T10:15:00+02:00')} | 1 attachment: '
        'verbetering.pdf | the user may not change it\n'
        '  Tweede opmerking.',
      );
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
      ]);
      expect(skore.feedbackReads, hasLength(1));
      expect(
        skore.feedbackReads.single.path,
        '/skore/api/v1/gradebook/feedback/12_500001/student/12_1202_0/class/'
        '12_2440/teacher/12_345_0/context/176_472_2440',
      );
    });

    test('feedback on an evaluation without a grade', () async {
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500003,
          'pupil_id': 1202,
        }),
        '$_ewiTitle\n'
        'Period: DW1 (period id 1704).\n'
        'Evaluation: $_toets\n'
        'Pupil: 2. Claes, Bart | pupil id 1202 | no grade\n'
        '1 feedback text on it, in the order it was written:\n'
        '- by the user, Jan Peeters (user id 345) | written '
        '${_time('2026-10-08T11:20:00+02:00')} | the user may change it\n'
        '  Feedback zonder cijfer.',
      );
    });

    test('a pupil without feedback: a sentence, not an error', () async {
      expect(
        await feedback({
          'gradebook_id': 32508,
          'evaluation_id': 500001,
          'pupil_id': 1203,
        }),
        endsWith(
          '\nPupil: 3. Dupont, Chloé | pupil id 1203 | no grade\n'
          'The pupil has no feedback on this evaluation.',
        ),
      );
      expect(skore.feedbackReads.single.pupilId, 1203);
    });

    test('an evaluation of an earlier period: without period_id, the active '
        'period first and then the others from the last; with period_id, '
        'only that one', () async {
      final expected =
          '$_bwTitle\n'
          'Period: DW1 (period id 1446).\n'
          'Evaluation: Databanken | evaluation id 400101 | column A | '
          '2025-10-15 | max 20 | component DW | points | PUBLISHED since '
          '${_time('2025-10-16T08:00:00+0200')}: the pupils see it and its '
          'grades\n'
          'Pupil: Maes, Lotte | pupil id 1301 | grade 14\n'
          '1 feedback text on it, in the order it was written:\n'
          '- by the user, Jan Peeters (user id 345) | written '
          '${_time('2025-10-16T07:30:00+02:00')} | the user may change it\n'
          '  Sterk verbeterd.';
      final arguments = {
        'gradebook_id': 28998,
        'workyear_id': 22,
        'evaluation_id': 400101,
        'pupil_id': 1301,
      };
      expect(await feedback(arguments), expected);
      expect(evaluationReads(), [1610, 1608, 1446]);
      skore.requests.clear();
      expect(await feedback({...arguments, 'period_id': 1446}), expected);
      expect(evaluationReads(), [1446]);
      expect(skore.feedbackReads, hasLength(2));
      expect(
        skore.feedbackReads.last.path,
        '/skore/api/v1/gradebook/feedback/12_400101/student/12_1301_0/class/'
        '12_2264/teacher/12_345_0/context/160_450_2264',
      );
    });

    test('a pupil the gradebook does not have: an error with where to take '
        'the id from, before any evaluation or feedback is read', () async {
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 32508,
          'evaluation_id': 500001,
          'pupil_id': 1301,
        }),
        'The gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
        '(gradebook id 32508) has no pupil with pupil id 1301. Take the pupil '
        'id from list_skore_evaluations or read_skore_gradebook for this '
        'gradebook.',
      );
      book(34826).pupils.clear();
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 34826,
          'evaluation_id': 500001,
          'pupil_id': 1221,
        }),
        contains('has no pupil with pupil id 1221: it has no pupils. Take'),
      );
      expect(evaluationReads(), isEmpty);
      expect(skore.feedbackReads, isEmpty);
    });

    test('an evaluation the gradebook does not have, or not in the period '
        'given, and a period it does not have: an error, and no feedback is '
        'read', () async {
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 32508,
          'evaluation_id': 400101,
          'pupil_id': 1201,
        }),
        contains('has no evaluation with evaluation id 400101 in its only '),
      );
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 28998,
          'workyear_id': 22,
          'period_id': 1610,
          'evaluation_id': 400101,
          'pupil_id': 1301,
        }),
        startsWith(
          'Period DW5 (period id 1610) of the gradebook of 5BW for '
          'Informaticawetenschappen (2 uur) (5e j DG) (gradebook id 28998) '
          'has no evaluation with evaluation id 400101.',
        ),
      );
      skore.requests.clear();
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 32508,
          'period_id': 1446,
          'evaluation_id': 500001,
          'pupil_id': 1201,
        }),
        startsWith(
          'The gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j '
          'DO) (gradebook id 32508) has no period with period id 1446. Its '
          'periods, in Skore\'s order: DW1 (period id 1704, open, active).',
        ),
      );
      expect(evaluationReads(), isEmpty);
      expect(skore.feedbackReads, isEmpty);
    });
  });

  group('an answer Skore\'s gradebook cannot use', () {
    test('a feedback read Skore refuses with a problem that quotes a name, an '
        'error page, or feedback about another pupil: the general error, '
        'without the name or the text', () async {
      const arguments = {
        'gradebook_id': 32508,
        'evaluation_id': 500001,
        'pupil_id': 1202,
      };
      skore.feedbackAnswer = (
        status: 403,
        body:
            '{"title":"Forbidden","detail":"Geen toegang tot de feedback van '
            'Bart Claes"}',
      );
      var text = await error('read_skore_feedback', arguments);
      expect(text, _unusable);
      expect(text, isNot(contains('Claes')));

      skore.feedbackAnswer = null;
      skore.unusable = true;
      expect(await error('read_skore_feedback', arguments), _unusable);
      skore.unusable = false;

      skore.feedbackAnswer = (
        status: 200,
        body: jsonEncode([
          {
            'id': '00000000-0000-4000-8000-000000000009',
            'evaluationId': '12_500001',
            'student': {'id': '12_1201_0'},
            'teacher': {'id': '12_345_0'},
            'text': 'Een tekst over An Aerts.',
          },
        ]),
      );
      text = await error('read_skore_feedback', arguments);
      expect(text, _unusable);
      expect(text, isNot(contains('Aerts')));
    });

    test('evaluations in a shape the library does not know, quoting a title, '
        'or an error page: the general error, without the title', () async {
      skore.answers['getEvaluations'] = (
        status: 200,
        body:
            '{"result":{"head":"Toets van Bart Claes","details":{}},'
            '"session":1,"method":"getEvaluations"}',
      );
      final text = await error('list_skore_evaluations', {
        'gradebook_id': 32508,
      });
      expect(text, _unusable);
      expect(text, isNot(contains('Claes')));
      expect(
        await error('read_skore_feedback', {
          'gradebook_id': 32508,
          'evaluation_id': 500001,
          'pupil_id': 1202,
        }),
        _unusable,
      );
      expect(skore.feedbackReads, isEmpty);
      skore.answers['getEvaluations'] = (status: 500, body: 'Oeps');
      expect(
        await error('list_skore_evaluations', {
          'gradebook_id': 32508,
          'evaluation_id': 500001,
        }),
        _unusable,
      );
    });
  });

  group('a session Smartschool refuses', () {
    test(
      'before the feedback read: the server logs in again and reads it',
      () async {
        // Log in first, so that the session expires during the tool call.
        await list({'gradebook_id': 32508});
        expect(server.logins, 1);
        server.expireSessionBefore(
          (request) => request.uri.path.startsWith(fakeSkoreFeedbackPath),
        );
        expect(
          await feedback({
            'gradebook_id': 32508,
            'evaluation_id': 500001,
            'pupil_id': 1202,
          }),
          contains(
            '\n2 feedback texts on it, in the order they were written:\n',
          ),
        );
        expect(server.logins, 2);
      },
    );

    test(
      'before getEvaluations: the server logs in again and reads them',
      () async {
        await list({'gradebook_id': 32508});
        server.expireSessionBefore(
          (request) =>
              request.uri.path == fakeSkoreGradebookRpcPath &&
              '${(request.data as Map)['rpc_method']}' == 'getEvaluations',
        );
        expect(
          await list({'gradebook_id': 32508, 'evaluation_id': 500002}),
          contains('\n- 3. Dupont, Chloé | pupil id 1203 | 12'),
        );
        expect(server.logins, 2);
      },
    );
  });

  group('skoreGradebookToolError', () {
    test('a change a check of a write refused: its reason, without the '
        'library\'s method and closing sentence, with what to read again; '
        'not taken for an answer the server cannot use', () {
      const refused = SmartschoolSkoreChangeRefusedError(
        'saveGrade: evaluation 500001 ("Python scripts schrijven") in period '
        'DW1 (1704) of gradebook 32508 is scheduled to be published. Nothing '
        'was saved.',
      );
      expect(
        skoreGradebookToolError(refused)?.message,
        'Skore refused the change before saving it: evaluation 500001 '
        '("Python scripts schrijven") in period DW1 (1704) of gradebook 32508 '
        'is scheduled to be published. Read the gradebook again with '
        'read_skore_gradebook (its periods) and list_skore_evaluations (a '
        'period\'s evaluations) to correct the call.',
      );
      expect(
        skoreGradebookToolError(
          refused,
          reread: 'Read the evaluation with list_skore_evaluations',
        )?.message,
        endsWith(
          'is scheduled to be published. Read the evaluation with '
          'list_skore_evaluations to correct the call.',
        ),
      );
      // A save Skore did not confirm, and a new evaluation that came back
      // public, are for the write tools to report.
      expect(
        skoreGradebookToolError(
          const SmartschoolSkoreEvaluationCreateUnconfirmedError(
            'createEvaluation: ...',
            gradebookId: 32508,
            periodId: 1704,
            title: 'Toets 1',
          ),
        ),
        isNull,
      );
    });

    test('a period id, a pupil id or an evaluation the library refuses: '
        'passed on with the tool\'s name of the argument and where to take '
        'it from', () {
      expect(
        skoreGradebookToolError(
          ArgumentError.value(
            0,
            'periodId',
            'not a period ID; nothing was sent',
          ),
        )?.message,
        'Skore\'s gradebook cannot take period_id 0: not a period ID; nothing '
        'was sent. Take a period id from read_skore_gradebook, or leave out '
        'period_id for the period Skore opens the gradebook on.',
      );
      expect(
        skoreGradebookToolError(
          ArgumentError.value(0, 'pupilId', 'not a pupil ID; nothing was sent'),
        )?.message,
        'Skore\'s gradebook cannot take pupil_id 0: not a pupil ID; nothing '
        'was sent. Take the pupil id from list_skore_evaluations or '
        'read_skore_gradebook.',
      );
      expect(
        skoreGradebookToolError(
          ArgumentError.value(
            500001,
            'evaluation',
            'an evaluation of gradebook 32508, not of gradebook 32504; nothing '
                'was sent',
          ),
        )?.message,
        'Skore\'s gradebook cannot take evaluation_id 500001: an evaluation of '
        'gradebook 32508, not of gradebook 32504; nothing was sent. Take the '
        'evaluation id from list_skore_evaluations for this gradebook.',
      );
    });
  });
}
