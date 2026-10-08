/// `list_skore_evaluations` and `read_skore_feedback` (#141), called over
/// MCP on the real server, session and library, against a fake Smartschool
/// whose Skore gradebook answers `getEvaluations` and the feedback reads of
/// Skore's REST API in the shape of dartschool's captures of #149
/// (`test/support/fake_skore_gradebook.dart`). Like the other gradebook
/// tools, they need no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/skore/skore_gradebook_access.dart';
import 'package:smartschool_mcp/src/tools/list_skore_evaluations_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_feedback_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
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

/// The general error of an answer the server cannot use.
const _unusable =
    'Skore\'s gradebook gave an answer the server could not use. Try again '
    'in a moment; the technical details are in the server log. An account '
    'without gradebooks of its own in Skore, such as a pupil\'s, may get '
    'this answer too.';

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
        'then the pupil ids. The gradebook, then one getEvaluations for the '
        'period, as the user, for its school year', () async {
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
        '1202); 3. Dupont, Chloé (pupil id 1203).',
      );
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
      ]);
      final read = skore.requests.last;
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
        'It has no periods yet, so it has no evaluations.',
      );
      expect(skore.calls, ['getNavigation', 'init wy=24']);
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
        'no periods yet, so it has no evaluations. Leave out period_id.',
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
        'name', () async {
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
      expect(
        text,
        contains(
          '\n- Houding | evaluation id 500005 | column A | 2026-10-05 | no max '
          '| no component | a scale | from the planner | PUBLISHED: the '
          'pupils see it and its grades\n'
          '  no class average | no group average | 1 of 3 pupils have a '
          'grade\n'
          '  grades: 1. Aerts, An: G; 2. Claes, Bart: no grade; 3. Dupont, '
          'Chloé: no grade\n',
        ),
      );
      expect(
        text,
        contains(
          '\n- Project | evaluation id 500006 | column B | 2026-10-06 | max 20 '
          '| component DW | type 7 | not published: the pupils do not see '
          'it\n',
        ),
      );
      expect(
        await list({'gradebook_id': 32508, 'evaluation_id': 500005}),
        contains(
          '\nGrades, one line per pupil in Skore\'s order ("feedback": the '
          'pupil has feedback on it, which read_skore_feedback reads):\n'
          '- 1. Aerts, An | pupil id 1201 | G\n',
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
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
      ]);
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
