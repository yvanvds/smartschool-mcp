/// The gradebook tools on the gradebooks colleagues shared with the user
/// (#167, yvanvds/dartschool#191): Skore's tab "Gedeeld", such as the
/// behaviour gradebook of a class that its form teacher shared with the
/// co-titularis. Called over MCP on the real server, session and library,
/// against a fake Smartschool whose Skore gradebook lists them with
/// `accessableList` and answers every call about one only in the scope
/// Skore's web client opens it in: in the name of its owner, restricted to
/// it (`test/support/fake_skore_gradebook.dart`).
///
/// One gradebook is shared to read and write ([fakeSkoreSharedGedrag], of
/// [fakeSkoreGedragOwner]), one to read only ([fakeSkoreSharedLatijn], of
/// [fakeSkoreLatijnOwner]). "The user's own feedback" is the feedback of the
/// logged-in user ([fakeSkoreGradebookUser]), never that of the owner, who
/// is the shared gradebook's teacher.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_skore_evaluation_tool.dart';
import 'package:smartschool_mcp/src/tools/list_skore_evaluations_tool.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_feedback_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_gradebook_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_feedback_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_grades_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// [iso], a time with its offset as Skore gives it, as the tools show it:
/// `2026-12-18 20:00` in the time of this PC.
String _time(String iso) {
  final local = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

const _schoolYears =
    'School years in Skore: 2026-2027 (workyear id 24, listed here), '
    '2025-2026 (workyear id 22), 2024-2025 (workyear id 20).';

/// The user's own gradebooks of 2026-2027, as list_skore_gradebooks lists
/// them (see `FakeSkoreGradebook.loadSchool`).
const _ownList =
    'The user has 4 gradebooks of their own in Skore for school year '
    '2026-2027 (workyear id 24), in Skore\'s order:\n'
    '- 6EWI | Informaticawetenschappen (2 uur) (6e j DO) | gradebook id '
    '32508\n'
    '- 6WEWI2 | Informaticawetenschappen (2 uur) (6e j DO) | gradebook id '
    '32504\n'
    '- 5WW1 | Digitale vaardigheden | gradebook id 34826\n'
    '- 5WW1 | Project 1 (3e graad) | gradebook id 34582\n';

/// The gradebook shared to read and write, and the one shared to read only,
/// as list_skore_gradebooks lists them.
const _gedragLine =
    '- 5WW2 | Gedrag | gradebook id 34980 | owner Céline Dupré (user id 346) '
    '| shared to read and write';
const _latijnLine =
    '- 4LA | Latijn | gradebook id 34999 | owner Sofie Wouters (user id 347) '
    '| shared to read only';

/// The first line of a result about each shared gradebook.
const _gedragTitle =
    'Gradebook id 34980: Gedrag, class 5WW2, school year 2026-2027 (workyear '
    'id 24). Its owner, Céline Dupré (user id 346), shared it with the user '
    'to read and write.';
const _latijnTitle =
    'Gradebook id 34999: Latijn, class 4LA, school year 2026-2027 (workyear '
    'id 24). Its owner, Sofie Wouters (user id 347), shared it with the user '
    'to read only.';

/// The shared gradebooks as a sentence of a tool names them: with their
/// owner.
const _gedragName =
    'gradebook of 5WW2 for Gedrag (gradebook id 34980, owner Céline Dupré)';
const _latijnName =
    'gradebook of 4LA for Latijn (gradebook id 34999, owner Sofie Wouters)';

/// The evaluation on the scale of the behaviour gradebook, and where it is.
const _inzetName = 'evaluation "Inzet in de klas" (evaluation id 500021)';
const _inzet =
    'Inzet in de klas | evaluation id 500021 | column A | 2026-10-09 | max 10 '
    '| no component | a scale | not published: the pupils do not see it';
const _g1 = 'period G1 (period id 1758) of the $_gedragName';

/// The owner's feedback for Jonas and for Kato, and the user's for Kato, on
/// Inzet in de klas.
const _ownersForJonas = '00000000-0000-4000-8000-000000000021';
const _ownersForKato = '00000000-0000-4000-8000-000000000022';
const _usersForKato = '00000000-0000-4000-8000-000000000023';

/// The refusal of a change in the gradebook shared to read only.
const _readOnlyRefusal =
    'Skore lists the $_latijnName as shared with the user to read only: the '
    'user may read it, not change it. Tell the user so; its owner, Sofie '
    'Wouters, can make the change, or share the gradebook with the user to '
    'write. Nothing was changed in Skore.';

void main() {
  late FakeSmartschool server;
  late FakeSkoreGradebook skore;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skoreGradebook
      ..loadSchool()
      ..gradebooks.addAll([fakeSkoreSharedGedrag(), fakeSkoreSharedLatijn()]);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listSkoreGradebooksTool(session),
        readSkoreGradebookTool(session),
        listSkoreEvaluationsTool(session),
        readSkoreFeedbackTool(session),
        saveSkoreFeedbackTool(session),
        saveSkoreGradesTool(session),
        createSkoreEvaluationTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method off the library's list, and no evaluation created.
    expect([
      for (final request in skore.requests) request.rpc,
    ], everyElement(isIn(fakeSkoreGradebookRpcMethods)));
    expect(skore.evaluationSaves, isEmpty, reason: 'nothing is created');
    // Never another's feedback, the owner's included: every POST is a
    // create, or a change of the user's own.
    final others = {
      for (final book in skore.gradebooks)
        for (final list in book.evaluations.values)
          for (final evaluation in list)
            for (final feedback in evaluation.feedback.values.expand((f) => f))
              if (feedback.teacherId != fakeSkoreGradebookUser) feedback.id,
    };
    expect(others, containsAll([_ownersForJonas, _ownersForKato]));
    for (final save in skore.feedbackSaves) {
      expect(save.path.split('/').last, isNot(isIn(others)));
      expect(save.body['id'], isNot(isIn(others)));
    }
    // Nothing in the gradebook shared to read only.
    expect(skore.gradeSaves.where((params) => params[10] == '34999'), isEmpty);
    expect(
      skore.feedbackSaves.where(
        (save) =>
            (save.body['evaluation'] as Map)['evaluationId'] == '12_500031',
      ),
      isEmpty,
    );
  });

  Future<(bool, String)> call(String tool, Map<String, Object?> arguments) =>
      callTool(connection, tool, arguments).then((call) {
        final (result, text) = call;
        return (result.isError ?? false, text);
      });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (isError, text) = await call(tool, arguments);
    expect(isError, isFalse, reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (isError, text) = await call(tool, arguments);
    expect(isError, isTrue, reason: text);
    return text;
  }

  /// The RPC calls about [gradebookId]: those that name it in `owners`
  /// (`init`, `getGradebookContext`) or in their restriction.
  Iterable<({String rpc, List<Object?> params, Map<String, Object?> session})>
  callsAbout(int gradebookId) =>
      skore.requests.where((r) => r.session['restriction'] == gradebookId);

  /// Expects every call about the shared gradebook [gradebookId] of
  /// [owner] to have gone out as Skore's web client opens it: in the
  /// owner's name, restricted to the gradebook; and at least [methods].
  void expectOpenedAsShared(int gradebookId, int owner, List<String> methods) {
    final calls = callsAbout(gradebookId).toList();
    expect([for (final c in calls) c.rpc], containsAll(methods));
    for (final c in calls) {
      expect(c.session['teacher'], owner, reason: c.rpc);
    }
    // The calls of the user themselves stay in their own scope.
    for (final c in skore.requests) {
      if (c.rpc case 'getNavigation' || 'accessableList') {
        expect(c.session['teacher'], fakeSkoreGradebookUser);
        expect(c.session['restriction'], 0);
        expect(c.params.first, fakeSkoreGradebookUser);
      }
    }
  }

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

    test('list_skore_gradebooks says it lists the gradebooks colleagues '
        'shared with the user too, with their owner and the user\'s access, '
        'and what the other tools do with them', () {
      expect(
        tools['list_skore_gradebooks']!.description,
        allOf(
          contains(
            'Then, if any, the gradebooks colleagues shared with the user '
            '("Gedeeld" in Skore, such as the behaviour gradebook of a class '
            'shared with its co-titularis), each with its owner and whether '
            'it is shared to read and write or to read only.',
          ),
          contains(
            'one shared to read only can be read, not changed; in one shared '
            'to read and write, grades and feedback can be saved, but no '
            'evaluation created.',
          ),
        ),
      );
    });

    test('the writes tell Claude to name the owner of a shared gradebook '
        'when it asks the user to confirm, and that one shared to read only '
        'is refused; create_skore_evaluation keeps to the user\'s own', () {
      for (final name in ['save_skore_feedback', 'save_skore_grades']) {
        expect(
          tools[name]!.description,
          allOf(
            contains(
              'In a gradebook a colleague shared with the user, also tell the '
              'user whose gradebook it is: its owner',
            ),
            contains(
              'A gradebook shared with the user to read only is refused: the '
              'user may read it, not change it.',
            ),
          ),
          reason: name,
        );
      }
      expect(
        tools['save_skore_feedback']!.description,
        contains('Nor is the feedback of the owner of a shared gradebook.'),
      );
      expect(
        tools['create_skore_evaluation']!.description,
        contains(
          'one of the user\'s own gradebooks in Skore, the Smartschool module '
          'for scores and reports (not in one a colleague shared with them: '
          'that is refused)',
        ),
      );
    });
  });

  group('list_skore_gradebooks', () {
    test('lists the user\'s own gradebooks, then those shared with them in a '
        'section of their own, each with its owner and the user\'s access; '
        'getNavigation and accessableList, both as the user', () async {
      expect(
        await ok('list_skore_gradebooks', {}),
        '$_ownList'
        'Shared with the user by colleagues ("Gedeeld" in Skore): 2 '
        'gradebooks, in Skore\'s order, each with its owner and what the user '
        'may do in it:\n'
        '$_gedragLine\n'
        '$_latijnLine\n'
        '$_schoolYears',
      );
      expect(skore.calls, ['getNavigation', 'accessableList']);
      expectOpenedAsShared(34980, fakeSkoreColleague, []);
    });

    test('query looks in the shared gradebooks too', () async {
      expect(
        await ok('list_skore_gradebooks', {'query': 'gedrag'}),
        'Skore finds 1 for "gedrag" among the user\'s 4 gradebooks and the 2 '
        'shared with them for school year 2026-2027 (workyear id 24), in '
        'Skore\'s order:\n'
        'Shared with the user by colleagues ("Gedeeld" in Skore): 1 '
        'gradebook, in Skore\'s order, each with its owner and what the user '
        'may do in it:\n'
        '$_gedragLine\n'
        '$_schoolYears',
      );
      expect(
        await ok('list_skore_gradebooks', {'query': '5ww'}),
        'Skore finds 3 for "5ww" among the user\'s 4 gradebooks and the 2 '
        'shared with them for school year 2026-2027 (workyear id 24), in '
        'Skore\'s order:\n'
        '- 5WW1 | Digitale vaardigheden | gradebook id 34826\n'
        '- 5WW1 | Project 1 (3e graad) | gradebook id 34582\n'
        'Shared with the user by colleagues ("Gedeeld" in Skore): 1 '
        'gradebook, in Skore\'s order, each with its owner and what the user '
        'may do in it:\n'
        '$_gedragLine\n'
        '$_schoolYears',
      );
      expect(
        await ok('list_skore_gradebooks', {'query': 'wiskunde'}),
        startsWith(
          'None of the user\'s 4 gradebooks and the 2 shared with them in '
          'Skore for school year 2026-2027 (workyear id 24) has "wiskunde" in '
          'the name of its class or course.',
        ),
      );
    });

    test('a co-titularis without gradebooks of their own: the sentence that '
        'says so, then the gradebooks shared with them', () async {
      skore.gradebooks.removeWhere((g) => !g.isShared);
      expect(
        await ok('list_skore_gradebooks', {}),
        'The user has no gradebooks of their own in Skore for school year '
        '2026-2027 (workyear id 24).\n'
        'Shared with the user by colleagues ("Gedeeld" in Skore): 2 '
        'gradebooks, in Skore\'s order, each with its owner and what the user '
        'may do in it:\n'
        '$_gedragLine\n'
        '$_latijnLine\n'
        '$_schoolYears',
      );
      expect(
        await ok('list_skore_gradebooks', {'query': 'latijn'}),
        startsWith(
          'Skore finds 1 for "latijn" among the 2 gradebooks shared with the '
          'user for school year 2026-2027 (workyear id 24), in Skore\'s '
          'order:\n',
        ),
      );
    });

    test('a school year in which nothing is shared with the user: only the '
        'user\'s own, as before', () async {
      expect(
        await ok('list_skore_gradebooks', {'workyear_id': 22}),
        'The user has 1 gradebook of their own in Skore for school year '
        '2025-2026 (workyear id 22), in Skore\'s order:\n'
        '- 5BW | Informaticawetenschappen (2 uur) (5e j DG) | gradebook id '
        '28998\n'
        'School years in Skore: 2026-2027 (workyear id 24), 2025-2026 '
        '(workyear id 22, listed here), 2024-2025 (workyear id 20).',
      );
      expect(skore.calls, ['getNavigation wy=22', 'accessableList wy=22']);
    });
  });

  group('reading a shared gradebook', () {
    test('read_skore_gradebook: the gradebook with its owner, opened in the '
        'owner\'s name and restricted to it, as Skore\'s web client opens a '
        'gradebook of its tab "Gedeeld"', () async {
      expect(
        await ok('read_skore_gradebook', {'gradebook_id': 34980}),
        '$_gedragTitle\n'
        'Skore lets the user change it.\n'
        '1 period, in Skore\'s order; only an open period takes grades, and '
        'Skore opens the gradebook on G1 (active):\n'
        '- G1 | period id 1758 | open, closes '
        '${_time('2026-12-18T20:00:00+0100')} | active | note: Open van '
        '2026-09-01 08:00 tot en met 2026-12-18 20:00. Vul hier je '
        'waarderingen voor gedrag in.\n'
        '2 pupils, in Skore\'s order:\n'
        '- 1. Martens, Jonas | pupil id 1231\n'
        '- 2. Nys, Kato | pupil id 1232',
      );
      expect(skore.calls, [
        'getNavigation',
        'accessableList',
        'init wy=24',
        'getGradebookContext wy=24',
      ]);
      final [_, _, init, context] = skore.requests;
      expect(init.params, [
        ['1904'],
        ['34980'],
        fakeSkoreColleague,
        ['176', '492', '2518'],
        0,
        34980,
      ]);
      expect(context.params, [
        ['176', '492', '2518'],
        ['1904'],
        ['34980'],
        fakeSkoreColleague,
        1758,
        34980,
        24,
      ]);
      expectOpenedAsShared(34980, fakeSkoreColleague, [
        'init',
        'getGradebookContext',
      ]);
    });

    test('read_skore_gradebook: one shared to read only says the user may '
        'not change it', () async {
      expect(
        await ok('read_skore_gradebook', {'gradebook_id': 34999}),
        '$_latijnTitle\n'
        'The user may read it, not change it: it is shared with them to read '
        'only.\n'
        '1 period, in Skore\'s order; only an open period takes grades, and '
        'Skore opens the gradebook on DW1 (active):\n'
        '- DW1 | period id 1759 | open, closes '
        '${_time('2026-12-18T20:00:00+0100')} | active | note: Open van '
        '2026-09-18 15:30 tot en met 2026-12-18 20:00. Vul hier je punten '
        'voor Dagelijks werk in!\n'
        '1 pupil, in Skore\'s order:\n'
        '- 1. Smets, Lien | pupil id 1241',
      );
      expectOpenedAsShared(34999, fakeSkoreLatijnOwner.id, [
        'init',
        'getGradebookContext',
      ]);
    });

    test('list_skore_evaluations: the evaluations with the grades and the '
        'levels on the scale, read in the owner\'s name; no components, as '
        'no evaluation is created in a shared gradebook', () async {
      final text = await ok('list_skore_evaluations', {'gradebook_id': 34980});
      expect(
        text,
        startsWith(
          '$_gedragTitle\n'
          'Period G1 (period id 1758): open, closes '
          '${_time('2026-12-18T20:00:00+0100')}; Skore opens the gradebook on '
          'it (active).\n'
          '2 evaluations, in Skore\'s order, each with the grade of every '
          'pupil ("(feedback)": the pupil has feedback on it, which '
          'read_skore_feedback reads):\n'
          '- $_inzet\n'
          '  class average 7.5 | group average 7.5 | 2 of 2 pupils have a '
          'grade\n'
          '  grades: 1. Martens, Jonas: Zeer goed (ZG; stored as 10) '
          '(feedback); 2. Nys, Kato: Voldoende (V; stored as 5) (feedback)\n'
          '- Samenwerken | evaluation id 500022 | column B | 2026-10-12 | max '
          '20 | component DW | points | not published: the pupils do not see '
          'it\n'
          '  class average 14.0 | group average 14.0 | 1 of 2 pupils have a '
          'grade\n'
          '  grades: 1. Martens, Jonas: 14; 2. Nys, Kato: no grade\n',
        ),
      );
      expect(text, isNot(contains('Components')));
      expect(
        text,
        endsWith(
          'Pupils: 1. Martens, Jonas (pupil id 1231); '
          '2. Nys, Kato (pupil id 1232).',
        ),
      );
      expect(skore.calls, isNot(contains('getPosComponents wy=24')));
      final read = skore.requests.singleWhere((r) => r.rpc == 'getEvaluations');
      expect(read.params[1], fakeSkoreColleague);
      expectOpenedAsShared(34980, fakeSkoreColleague, ['getEvaluations']);
    });

    test('read_skore_feedback: the owner\'s feedback is the owner\'s, never '
        'the user\'s; only the logged-in user\'s is marked as the user\'s. '
        'Read at the path of the feedback panel, with the owner as its '
        'teacher', () async {
      expect(
        await ok('read_skore_feedback', {
          'gradebook_id': 34980,
          'evaluation_id': 500021,
          'pupil_id': 1232,
          'period_id': 1758,
        }),
        '$_gedragTitle\n'
        'Period: G1 (period id 1758).\n'
        'Evaluation: $_inzet\n'
        'Pupil: 2. Nys, Kato | pupil id 1232 | grade Voldoende (V; stored as '
        '5)\n'
        '2 feedback texts on it, in the order they were written:\n'
        '- by Céline Dupré (user id 346) | written '
        '${_time('2026-10-09T15:05:00+02:00')} | the user may not change it\n'
        '  Praat vaak door de les.\n'
        '- by the user, Jan Peeters (user id 345) | written '
        '${_time('2026-10-10T09:00:00+02:00')} | the user may change it\n'
        '  Let beter op in de les.',
      );
      expect(
        skore.feedbackReads.single.path,
        '/skore/api/v1/gradebook/feedback/12_500021/student/12_1232_0/class/'
        '12_2518/teacher/12_${fakeSkoreColleague}_0/context/176_492_2518',
      );
      expect(
        await ok('read_skore_feedback', {
          'gradebook_id': 34980,
          'evaluation_id': 500021,
          'pupil_id': 1231,
          'period_id': 1758,
        }),
        allOf(
          contains(
            '1 feedback text on it, in the order it was written:\n'
            '- by Céline Dupré (user id 346) | written',
          ),
          isNot(contains('by the user')),
        ),
      );
    });

    test('read_skore_feedback in one shared to read only: the owner\'s '
        'feedback, not marked as the user\'s', () async {
      final text = await ok('read_skore_feedback', {
        'gradebook_id': 34999,
        'evaluation_id': 500031,
        'pupil_id': 1241,
      });
      expect(text, startsWith('$_latijnTitle\n'));
      expect(
        text,
        contains(
          '\n- by Sofie Wouters (user id 347) | written '
          '${_time('2026-10-08T10:00:00+02:00')} | the user may not change '
          'it\n  Mooi werk.',
        ),
      );
      expect(text, isNot(contains('by the user')));
      expect(skore.feedbackReads.single.path, contains('/teacher/12_347_0/'));
    });
  });

  group('save_skore_feedback', () {
    Future<(bool, String)> save(int pupil, String text, {int book = 34980}) =>
        call('save_skore_feedback', {
          'gradebook_id': book,
          'evaluation_id': book == 34980 ? 500021 : 500031,
          'period_id': book == 34980 ? 1758 : 1759,
          'pupil_id': pupil,
          'text': text,
        });

    test('in a gradebook shared to write, for a pupil with only the owner\'s '
        'feedback (which Skore does not let the user change): creates the '
        'user\'s own, names the owner, and leaves the owner\'s as it '
        'was', () async {
      final (isError, text) = await save(1231, 'Blijf zo meedoen.');
      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Saved new feedback of the user for Martens, Jonas (pupil id 1231) on '
        'the $_inzetName in $_g1.\n'
        'Evaluation: $_inzet\n'
        'The feedback as Skore lists it after the save:\n'
        '- by the user, Jan Peeters (user id 345) | written '
        '${_time('2026-10-08T12:30:00+02:00')} | the user may change it\n'
        '  Blijf zo meedoen.',
      );
      final create = skore.feedbackSaves.single;
      expect(create.path, fakeSkoreFeedbackCreatePath);
      // The reference names the gradebook's teacher, its owner, as the
      // feedback panel does; the feedback is the user's.
      expect(create.body, {
        'evaluation': {
          'evaluationId': '12_500021',
          'classGroupId': '12_2518',
          'teacherId': '12_${fakeSkoreColleague}_0',
          'context': '176_492_2518',
        },
        'studentId': '12_1231_0',
        'text': 'Blijf zo meedoen.',
        'attachments': <Object?>[],
      });
      final feedback = skore.gradebooks
          .firstWhere((g) => g.id == 34980)
          .evaluationWithId(500021)!
          .feedback[1231]!;
      expect(
        [for (final f in feedback) (f.teacherId, f.text)],
        [
          (fakeSkoreColleague, 'Werkt goed mee in de klas.'),
          (fakeSkoreGradebookUser, 'Blijf zo meedoen.'),
        ],
      );
      // The tool's reads, then the library's checks, which read the
      // gradebooks shared with the user again.
      expect(skore.calls, [
        'getNavigation',
        'accessableList',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
        'getNavigation',
        'accessableList',
        'init wy=24',
        'getGradebookContext wy=24',
        'getEvaluations wy=24',
      ]);
      expectOpenedAsShared(34980, fakeSkoreColleague, [
        'init',
        'getGradebookContext',
        'getEvaluations',
      ]);
    });

    test('for a pupil with the owner\'s feedback and the user\'s: changes '
        'the user\'s, never the owner\'s', () async {
      final (isError, text) = await save(1232, 'Let beter op, en vraag hulp.');
      expect(isError, isFalse, reason: text);
      expect(
        text,
        startsWith(
          'Changed the text of the user\'s feedback for Nys, Kato (pupil id '
          '1232) on the $_inzetName in $_g1.\n',
        ),
      );
      final change = skore.feedbackSaves.single;
      expect(change.path, '$fakeSkoreFeedbackCreatePath/$_usersForKato');
      expect(change.body['id'], _usersForKato);
      final feedback = skore.gradebooks
          .firstWhere((g) => g.id == 34980)
          .evaluationWithId(500021)!
          .feedback[1232]!;
      expect(
        [for (final f in feedback) (f.id, f.text)],
        [
          (_ownersForKato, 'Praat vaak door de les.'),
          (_usersForKato, 'Let beter op, en vraag hulp.'),
        ],
      );
    });

    test('in a gradebook shared to read only: refused in the server\'s own '
        'words, naming the owner to ask, before the gradebook is read and '
        'nothing is sent', () async {
      final (isError, text) = await save(1241, 'Goed gedaan.', book: 34999);
      expect(isError, isTrue, reason: text);
      expect(text, _readOnlyRefusal);
      expect(skore.calls, ['getNavigation', 'accessableList']);
      expect(skore.feedbackReads, isEmpty);
      expect(skore.feedbackSaves, isEmpty);
    });

    test('shared to read only between the tool\'s read and the library\'s: '
        'the library refuses it before anything is sent, and the server says '
        'so in the same words', () async {
      final book = skore.gradebooks.firstWhere((g) => g.id == 34980);
      var lists = 0;
      skore.beforeAnswer = (rpc, _) {
        if (rpc == 'accessableList' && ++lists == 2) {
          book.sharedBy = const FakeSkoreSharer(
            fakeSkoreColleague,
            'Céline Dupré',
            writable: false,
          );
        }
      };
      final (isError, text) = await save(1231, 'Blijf zo meedoen.');
      expect(isError, isTrue, reason: text);
      expect(
        text,
        'Skore lists the $_gedragName as shared with the user to read only: '
        'the user may read it, not change it. Tell the user so; its owner, '
        'Céline Dupré, can make the change, or share the gradebook with the '
        'user to write. Nothing was changed in Skore.',
      );
      expect(lists, 2);
      expect(skore.calls.last, 'accessableList');
      expect(skore.feedbackSaves, isEmpty);
    });
  });

  group('save_skore_grades', () {
    test('in a gradebook shared to write: saved in the owner\'s name, as '
        'Skore\'s web client sends it, and the result names the '
        'owner', () async {
      final text = await ok('save_skore_grades', {
        'gradebook_id': 34980,
        'evaluation_id': 500022,
        'period_id': 1758,
        'grades': [
          {'pupil_id': 1232, 'grade': '12,5'},
        ],
      });
      expect(text, contains('period G1 (period id 1758) of the $_gedragName'));
      expect(text, contains('Nys, Kato'));
      expect(text, contains('12.5'));
      final [save] = skore.gradeSaves;
      expect(save[3], fakeSkoreColleague, reason: 'userID: the owner');
      expect(save[10], '34980');
      expect(
        skore.gradebooks
            .firstWhere((g) => g.id == 34980)
            .evaluationWithId(500022)!
            .grades,
        {1231: '14', 1232: '12.5'},
      );
      expectOpenedAsShared(34980, fakeSkoreColleague, [
        'init',
        'getGradebookContext',
        'getEvaluations',
        'saveGrade',
      ]);
    });

    test('in a gradebook shared to read only: refused in the server\'s own '
        'words before the gradebook is read; nothing is sent', () async {
      expect(
        await error('save_skore_grades', {
          'gradebook_id': 34999,
          'evaluation_id': 500031,
          'grades': [
            {'pupil_id': 1241, 'grade': '18'},
          ],
        }),
        _readOnlyRefusal,
      );
      expect(skore.calls, ['getNavigation', 'accessableList']);
      expect(skore.gradeSaves, isEmpty);
    });
  });

  group('create_skore_evaluation', () {
    test('refuses any shared gradebook, also one shared to write, before it '
        'is read: the server creates evaluations in the user\'s own '
        'gradebooks only', () async {
      for (final (id, name, owner) in [
        (34980, _gedragName, 'Céline Dupré'),
        (34999, _latijnName, 'Sofie Wouters'),
      ]) {
        expect(
          await error('create_skore_evaluation', {
            'gradebook_id': id,
            'title': 'Toets',
            'date': '2026-10-14',
            'max': 20,
          }),
          'The $name is not one of the user\'s own gradebooks: a colleague '
          'shared it with them. create_skore_evaluation creates an evaluation '
          'only in one of the user\'s own gradebooks. Tell the user so; its '
          'owner, $owner, can create the evaluation in it. Nothing was '
          'changed in Skore.',
          reason: '$id',
        );
      }
      expect(skore.calls, ['getNavigation', 'accessableList']);
    });
  });
}
