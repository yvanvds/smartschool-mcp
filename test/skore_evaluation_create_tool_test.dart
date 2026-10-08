/// `create_skore_evaluation` (#142), called over MCP on the real server,
/// session and library, against a fake Smartschool whose Skore gradebook
/// answers the "new evaluation" dialog (`getNewEvalDialogBox`,
/// `getPosComponents`) and carries out its save (`saveEvaluation`) in the
/// shape of dartschool's captures of #150
/// (`test/support/fake_skore_gradebook.dart`). Like the other gradebook
/// tools, it needs no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_skore_evaluation_tool.dart';
import 'package:smartschool_mcp/src/tools/list_skore_evaluations_tool.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// What no gradebook text may say: the gradebook is not behind the switch
/// "Skore-beheer", and needs no extra rights.
final _adminWords = RegExp(
  r'Skore-beheer|SMARTSCHOOL_SKORE|rights|administrator|score management',
  caseSensitive: false,
);

/// 5WW1's gradebook of Digitale vaardigheden: one open period, DW1, without
/// evaluations, and one pupil.
const _gradebookName =
    'gradebook of 5WW1 for Digitale vaardigheden (gradebook id 34826)';
const _gradebook = 'the $_gradebookName';
const _where = 'period DW1 (period id 1704) of $_gradebook';

/// What the tool says after a check of the library refused the change.
String _refused(String reason) =>
    'Skore refused the change before saving it: $reason Read the gradebook '
    'again with read_skore_gradebook (its periods, and whether the user may '
    'change it) and the period with list_skore_evaluations (its '
    'evaluations, and the components a new one can count for) to correct '
    'the call. Nothing was changed in Skore.';

/// The parameters of saveEvaluation for a new evaluation in 5WW1's DW1, as
/// Skore's dialog sends them (dartschool's `_saveParams`), with what may
/// change.
List<Object?> _saveParams({
  String title = 'Toets Python',
  String short = '',
  String date = '2026-10-14',
  String max = '20',
  String compName = 'DW',
  Object compId = '2',
}) => [
  0,
  '34826',
  fakeSkoreGradebookUser,
  '1588',
  'Digitale vaardigheden',
  title,
  short,
  1704,
  date,
  max,
  compName,
  compId,
  0, // public: not published
  <Object?>[],
  ['176', '492', '2516'],
  null,
  null,
  '', // publicdatetime: none
  null,
  1,
];

/// The calls of a create in 5WW1's DW1, after the tool's own reads: the
/// library's checks, the dialog, the save, and the period read again.
const _createCalls = [
  'getNavigation',
  'init wy=24',
  'getGradebookContext wy=24',
  'getNewEvalDialogBox wy=24',
  'getPosComponents wy=24',
  'saveEvaluation wy=24',
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
        createSkoreEvaluationTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method off the library's list, such as one that publishes.
    expect([
      for (final request in skore.requests) request.rpc,
    ], everyElement(isIn(fakeSkoreGradebookRpcMethods)));
    // Every save that reached Skore went out unpublished.
    for (final save in skore.evaluationSaves) {
      expect(save[12], 0, reason: 'public');
      expect(save[17], '', reason: 'publicdatetime');
    }
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

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (isError, text) = await call(tool, arguments);
    expect(isError, isTrue, reason: text);
    return text;
  }

  /// Creates "Toets Python" (2026-10-14, max 20) in 5WW1's gradebook of
  /// Digitale vaardigheden, or what is given, and returns the result.
  Future<(bool, String)> create([Map<String, Object?> arguments = const {}]) =>
      call('create_skore_evaluation', {
        'gradebook_id': 34826,
        'title': 'Toets Python',
        'date': '2026-10-14',
        'max': 20,
        ...arguments,
      });

  /// The period 5WW1's gradebook of Digitale vaardigheden opens on, as
  /// list_skore_evaluations lists it.
  Future<String> period([int gradebookId = 34826]) =>
      ok('list_skore_evaluations', {'gradebook_id': gradebookId});

  /// A gradebook of the fake by its id.
  FakeSkoreOwnGradebook book(int id) =>
      skore.gradebooks.firstWhere((g) => g.id == id);

  bool isSave(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path == fakeSkoreGradebookRpcPath &&
      (request.data as Map?)?['rpc_method'] == 'saveEvaluation';

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
      )).tools.singleWhere((tool) => tool.name == 'create_skore_evaluation');
    });

    test('as a write Claude Desktop asks approval for every time, not '
        'idempotent, without a word of "Skore-beheer", rights or teachers', () {
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isFalse);
      expect(annotations.openWorldHint, isTrue);
      final definition = jsonEncode(tool);
      expect(definition, isNot(matches(_adminWords)));
      expect(definition.toLowerCase(), isNot(contains('teacher')));
    });

    test('tells Claude to read the period first, to show what it creates '
        'and that it stays unpublished, and to wait for the user\'s '
        'confirmation', () {
      final description = tool.description!;
      for (final part in [
        'It is always created unpublished: the pupils do not see it until '
            'the user publishes it in Smartschool; this tool cannot publish.',
        'Before calling this tool, read the period with '
            'list_skore_evaluations: if it already has an evaluation with the '
            'same title and date, do not create it again.',
        'That list also gives the components a new evaluation in the period '
            'can count for, and the default.',
        'Show the user the gradebook (class and course), the period, the '
            'title, the short name if any, the date, the max and the '
            'component; say that it will be created unpublished and that the '
            'user publishes it in Smartschool; and only call this tool after '
            'the user has explicitly confirmed it.',
        'If the result says it may or may not have been created, do not call '
            'this tool again for it: read the period with '
            'list_skore_evaluations',
        'If the result says it was created but Skore shows it as published '
            'or scheduled, tell the user at once to check it in Smartschool, '
            'and do not create it again.',
      ]) {
        expect(description, contains(part));
      }
    });

    test('takes the gradebook, the title, the date and the max, and '
        'optionally the period, a short name and the component', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['gradebook_id', 'title', 'date', 'max']);
      expect(schema.properties!.keys, [
        'gradebook_id',
        'period_id',
        'title',
        'short_name',
        'date',
        'max',
        'component',
      ]);
      for (final name in ['gradebook_id', 'period_id', 'max']) {
        expect(schema.properties![name], {
          'type': 'integer',
          'description': isA<String>(),
          'minimum': 1,
        }, reason: name);
      }
      for (final name in ['title', 'short_name', 'date', 'component']) {
        expect(schema.properties![name], {
          'type': 'string',
          'description': isA<String>(),
        }, reason: name);
      }
    });
  });

  group('create_skore_evaluation', () {
    test('creates the evaluation with the exact save of Skore\'s dialog, '
        'once and unpublished, and reports it as Skore lists it after the '
        'save; the period lists it from then on', () async {
      final (isError, text) = await create();

      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Created evaluation "Toets Python" in $_where. It is not published: '
        'the pupils do not see it until the user publishes it in '
        'Smartschool.\n'
        'Created: Toets Python | evaluation id 500100 | column A | '
        '2026-10-14 | max 20 | component DW | points | not published: the '
        'pupils do not see it',
      );
      // The tool's own reads (the gradebook, its periods), then the
      // library's.
      expect(skore.calls, [
        'getNavigation',
        'init wy=24',
        'getGradebookContext wy=24',
        ..._createCalls,
      ]);
      // The exact parameters, strings and numbers as the dialog sends them:
      // DW, the second of the two components Skore offers.
      expect(skore.evaluationSaves, [_saveParams()]);
      final save = skore.requests.singleWhere((r) => r.rpc == 'saveEvaluation');
      expect(save.session['teacher'], fakeSkoreGradebookUser);
      expect(save.session['wy'], '24');

      expect(
        await period(),
        contains(
          '\n1 evaluation, in Skore\'s order, each with the grade of every '
          'pupil ("(feedback)": the pupil has feedback on it, which '
          'read_skore_feedback reads):\n'
          '- Toets Python | evaluation id 500100 | column A | 2026-10-14 | max '
          '20 | component DW | points | not published: the pupils do not see '
          'it\n',
        ),
      );
    });

    test('a short name, a period by period_id, a title and short name '
        'trimmed, a whole number written with a decimal part', () async {
      expect(
        await ok('create_skore_evaluation', {
          'gradebook_id': 34826.0,
          'period_id': 1704.0,
          'title': '  Toets 2 ',
          'short_name': ' T2 ',
          'date': ' 2026-09-01 ',
          'max': 100.0,
        }),
        endsWith(
          '\nCreated: Toets 2 (short name T2) | evaluation id 500100 | column '
          'A | 2026-09-01 | max 100 | component DW | points | not published: '
          'the pupils do not see it',
        ),
      );
      expect(skore.evaluationSaves, [
        _saveParams(
          title: 'Toets 2',
          short: 'T2',
          date: '2026-09-01',
          max: '100',
        ),
      ]);
    });

    test('the component by its name, ignoring case, or by its component '
        'id; geen for none', () async {
      final cases = <String, (String, Object, String)>{
        'dw': ('DW', '2', 'component DW'),
        ' DW ': ('DW', '2', 'component DW'),
        '2': ('DW', '2', 'component DW'),
        'geen': ('geen', 0, 'no component'),
        'GEEN': ('geen', 0, 'no component'),
        '0': ('geen', 0, 'no component'),
      };
      var count = 0;
      for (final MapEntry(key: component, value: (name, id, shown))
          in cases.entries) {
        final (isError, text) = await create({
          'title': 'Toets ${++count}',
          'component': component,
        });
        expect(isError, isFalse, reason: '$component: $text');
        expect(text, contains('| max 20 | $shown | points |'));
        expect(
          skore.evaluationSaves.last,
          _saveParams(title: 'Toets $count', compName: name, compId: id),
          reason: component,
        );
      }
      expect(skore.evaluationSaves, hasLength(cases.length));
    });

    test('without a component, the one Skore\'s dialog picks: geen when Skore '
        'offers more than two', () async {
      book(34826).components.add(['4', 'PW']);
      expect(
        (await create()).$2,
        contains('| max 20 | no component | points |'),
      );
      expect(skore.evaluationSaves, [_saveParams(compName: 'geen', compId: 0)]);
      expect(
        (await create({'title': 'Project', 'component': 'pw'})).$2,
        contains('| max 20 | component PW | points |'),
      );
      expect(
        skore.evaluationSaves.last,
        _saveParams(title: 'Project', compName: 'PW', compId: '4'),
      );
    });

    test('a component Skore does not offer: an error that lists those it '
        'offers and the default, before the save', () async {
      for (final component in ['PW', '4', 'Dagelijks werk']) {
        expect(
          await error('create_skore_evaluation', {
            'gradebook_id': 34826,
            'title': 'Toets Python',
            'date': '2026-10-14',
            'max': 20,
            'component': component,
          }),
          'Skore offers no component "$component" for a new evaluation in '
          '$_where. It offers geen (component id 0: none), DW (component id '
          '2). Pass one of these as component, by its name or component id, '
          'or leave out component for DW (the default). Nothing was changed '
          'in Skore.',
        );
      }
      expect(skore.evaluationSaves, isEmpty);
      expect(skore.calls.last, 'getPosComponents wy=24');
    });

    test('a blank title, a date that is not a day, or a max that is not '
        'positive: an error before anything is sent', () async {
      final cases = <Map<String, Object?>, String>{
        {'title': '  \n '}:
            'title must not be blank: give the title of the evaluation. '
            'Nothing was changed in Skore.',
        {'date': '14/10/2026'}:
            'date must be a day like 2026-10-14, without a time; '
            '"14/10/2026" is not. Nothing was changed in Skore.',
        {'date': '2026-02-30'}:
            'date must be a day like 2026-10-14, without a time; '
            '"2026-02-30" is not. Nothing was changed in Skore.',
        {'date': '2026-10-14 10:00'}:
            'date must be a day like 2026-10-14, without a time; '
            '"2026-10-14 10:00" is not. Nothing was changed in Skore.',
        // The input schema already refuses these.
        {'max': 0}: 'Value 0 is less than the minimum of 1 at path',
        {'max': 12.5}: '12.5',
        {'component': 2}: 'Value `2` is not of type `String`',
      };
      for (final MapEntry(key: arguments, value: message) in cases.entries) {
        final (isError, text) = await create(arguments);
        expect(isError, isTrue, reason: '$arguments');
        expect(text, contains(message), reason: '$arguments');
      }
      expect(skore.requests, isEmpty);
      expect(server.logins, 0);
    });

    group('passes on why Skore refused the change, with what to read again, '
        'saving nothing:', () {
      test('a gradebook Skore shows read-only', () async {
        book(34826).writable = false;
        expect(
          await error('create_skore_evaluation', {
            'gradebook_id': 34826,
            'title': 'Toets Python',
            'date': '2026-10-14',
            'max': 20,
          }),
          _refused(
            'Skore shows gradebook 34826 read-only to you in period DW1 (1704) '
            '(writable 0).',
          ),
        );
        expect(skore.calls.last, 'getGradebookContext wy=24');
      });

      test('a closed period', () async {
        final periods = book(34826).periods;
        final open = periods.single;
        periods[0] = FakeSkoreGradebookPeriod(
          open.id,
          open.name,
          open: false,
          timestamp: open.timestamp,
          note: open.note,
        );
        final (isError, text) = await create({'period_id': 1704});
        expect(isError, isTrue);
        expect(
          text,
          _refused('period DW1 (1704) of gradebook 34826 is closed.'),
        );
      });

      test('a date outside the current school year', () async {
        for (final date in ['2026-08-31', '2027-09-01']) {
          final (isError, text) = await create({'date': date});
          expect(isError, isTrue, reason: date);
          expect(
            text,
            _refused(
              'the date $date is not in school year 2026-2027 (2026-09-01 to '
              '2027-08-31).',
            ),
          );
        }
      });

      test('a course Skore does not offer for a new evaluation', () async {
        skore.answers['getNewEvalDialogBox'] = (
          status: 200,
          body: jsonEncode({
            'result': [
              ['2264', 'Informaticawetenschappen (2 uur)'],
            ],
            'session': 1,
            'method': 'getNewEvalDialogBox',
          }),
        );
        final (isError, text) = await create();
        expect(isError, isTrue);
        expect(
          text,
          _refused(
            'Skore does not offer course 1588 for a new evaluation in period '
            'DW1 (1704) of gradebook 34826 (it offers 2264).',
          ),
        );
      });

      tearDown(() {
        expect(skore.evaluationSaves, isEmpty);
      });
    });

    test('a gradebook of an earlier school year, or one that is not the '
        'user\'s: an error that says only one of the current school year '
        'can be changed', () async {
      // 5BW's gradebook of 2025-2026, once listed.
      await ok('list_skore_gradebooks', {'workyear_id': 22});
      expect(
        await error('create_skore_evaluation', {
          'gradebook_id': 28998,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        'Gradebook id 28998 is of school year 2025-2026 (workyear id 22), not '
        'of Skore\'s current school year, 2026-2027 (workyear id 24): only a '
        'gradebook of the current school year can be changed. Nothing was '
        'changed in Skore.',
      );
      expect(
        await error('create_skore_evaluation', {
          'gradebook_id': 99999,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        'None of the user\'s own gradebooks of Skore\'s current school year, '
        '2026-2027 (workyear id 24), has gradebook id 99999. Take the '
        'gradebook id from list_skore_gradebooks, without workyear_id: only a '
        'gradebook of the current school year can be changed. Nothing was '
        'changed in Skore.',
      );
      expect(skore.evaluationSaves, isEmpty);
      expect(
        skore.calls.where((call) => call.startsWith('init')),
        isEmpty,
        reason: 'no gradebook was read',
      );
    });

    test('a period_id that is not one of the gradebook\'s, or a gradebook '
        'without periods: an error before the library is asked', () async {
      expect(
        await error('create_skore_evaluation', {
          'gradebook_id': 34826,
          'period_id': 1446,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        allOf(
          startsWith(
            'The $_gradebookName has no period with period id 1446. Its '
            'periods, in Skore\'s order: DW1 (period id 1704, open, active).',
          ),
          endsWith(' Nothing was changed in Skore.'),
        ),
      );
      book(34582).periods.clear();
      expect(
        await error('create_skore_evaluation', {
          'gradebook_id': 34582,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        'The gradebook of 5WW1 for Project 1 (3e graad) (gradebook id 34582) '
        'has no periods yet, so no evaluation can be created in it. Nothing '
        'was changed in Skore.',
      );
      expect(skore.evaluationSaves, isEmpty);
      expect(skore.calls, isNot(contains('getNewEvalDialogBox wy=24')));
    });

    test('an answer the server cannot use before the save: says so, and '
        'that nothing was changed', () async {
      skore.answers['getPosComponents'] = (
        status: 200,
        body: '{"result":{"comps":"DW"},"session":1}',
      );
      final (isError, text) = await create();
      expect(isError, isTrue);
      expect(
        text,
        'Skore\'s gradebook gave an answer the server could not use. Try '
        'again in a moment; the technical details are in the server log. An '
        'account without gradebooks of its own in Skore, such as a pupil\'s, '
        'may get this answer too. Nothing was changed in Skore.',
      );
      expect(skore.evaluationSaves, isEmpty);
    });
  });

  group('a save Skore does not confirm is never sent again, and is not '
      'repeated as a refused session:', () {
    test('Skore answers it with an error page: Claude must check the period '
        'first, which shows nothing was created', () async {
      final logins = await loggedIn();
      skore.answers['saveEvaluation'] = (
        status: 500,
        body: '{"message":"Internal Server Error"}<!DOCTYPE html><html></html>',
      );

      expect(
        await error('create_skore_evaluation', {
          'gradebook_id': 34826,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        'The new evaluation "Toets Python" (2026-10-14, max 20) in $_where '
        'may or may not have been saved: the change was sent, but Skore did '
        'not confirm it. Do not call create_skore_evaluation again for it: '
        'first read the period with list_skore_evaluations (gradebook_id '
        '34826, period_id 1704) and look for that title on that day: when it '
        'is listed, it was created, unpublished; when it is not, nothing was '
        'created. Then tell the user what you found.',
      );
      expect(skore.evaluationSaves, [_saveParams()]);
      expect(skore.calls.last, 'saveEvaluation wy=24', reason: 'no check');
      expect(server.logins, logins);
      expect(await period(), contains('\nIt has no evaluations.\n'));
    });

    test('its answer is lost after Skore saved it: the check the result asks '
        'for finds it', () async {
      final logins = await loggedIn();
      skore.saveAnswerLost = true;

      final (isError, text) = await create();
      expect(isError, isTrue);
      expect(
        text,
        startsWith(
          'The new evaluation "Toets Python" (2026-10-14, max 20) in $_where '
          'may or may not have been saved',
        ),
      );
      expect(skore.evaluationSaves, hasLength(1));
      expect(skore.calls.last, 'saveEvaluation wy=24');
      expect(server.logins, logins);
      expect(
        await period(),
        contains(
          '\n- Toets Python | evaluation id 500100 | column A | 2026-10-14 | '
          'max 20 | component DW | points | not published: the pupils do not '
          'see it\n',
        ),
      );
    });

    test('Skore confirmed it, but the period read again does not list it: '
        'the result names the id Skore answered', () async {
      skore.onEvaluationSaved = (book, created) =>
          book.evaluations[1704]!.remove(created);

      final (isError, text) = await create();
      expect(isError, isTrue);
      expect(
        text,
        contains(
          'Do not call create_skore_evaluation again for it: first read the '
          'period with list_skore_evaluations (gradebook_id 34826, period_id '
          '1704) and look for evaluation id 500100, the id Skore answered for '
          'it: when it is listed, it was created, unpublished; when it is '
          'not, nothing was created.',
        ),
      );
      expect(skore.evaluationSaves, hasLength(1));
      expect(skore.calls.last, 'getEvaluations wy=24');
    });
  });

  test('created, but Skore shows it as public: says so plainly, to check in '
      'Smartschool now and not to create it again; nothing more is sent', () {
    final cases = {
      '': 'PUBLISHED: the pupils see it and its grades',
      fakeSkoreScheduledAt:
          'SCHEDULED for ${_time('2099-01-11T08:00:00+0100')}: from then on '
          'the pupils see it and its grades',
    };
    return Future.forEach(cases.entries, (entry) async {
      skore.onEvaluationSaved = (book, created) => created
        ..public = '1'
        ..publicDateTime = entry.key;
      final saves = skore.evaluationSaves.length;
      final title = 'Toets ${saves + 1}';

      final (isError, text) = await create({'title': title});

      expect(isError, isTrue);
      expect(
        text,
        'Evaluation "$title" was created in $_where, but Skore shows it as '
        'public, although the server sent it unpublished: ${entry.value}. '
        'Its pupils may see it. Tell the user now to check its publication '
        'in Smartschool and change it there: the server never changes a '
        'publication. Do not call create_skore_evaluation again for it: it '
        'exists, and a second call creates a second evaluation.\n'
        'Created: $title | evaluation id ${500100 + saves} | column A | '
        '2026-10-14 | max 20 | component DW | points | ${entry.value}',
      );
      expect(skore.evaluationSaves, hasLength(saves + 1));
      expect(skore.evaluationSaves.last, _saveParams(title: title));
      expect(skore.calls.last, 'getEvaluations wy=24');
    });
  });

  group('Smartschool refuses the session for the save', () {
    test('the library does not send it again: the session repeats the call, '
        'which reads the gradebook again and saves once', () async {
      final logins = await loggedIn();
      server.expireSessionBefore(isSave);

      expect(
        await ok('create_skore_evaluation', {
          'gradebook_id': 34826,
          'title': 'Toets Python',
          'date': '2026-10-14',
          'max': 20,
        }),
        endsWith(
          '\nCreated: Toets Python | evaluation id 500100 | column A | '
          '2026-10-14 | max 20 | component DW | points | not published: the '
          'pupils do not see it',
        ),
      );
      expect(server.logins, logins + 1);
      // The refused save never reached Skore; the repeat read the gradebook
      // again (its school year from memory) and saved once.
      final beforeSave = _createCalls.sublist(0, 5);
      expect(skore.calls, [
        'init wy=24',
        'getGradebookContext wy=24',
        ...beforeSave,
        'init wy=24',
        'getGradebookContext wy=24',
        ..._createCalls,
      ]);
      expect(skore.evaluationSaves, [_saveParams()]);
      expect(
        server.requests
            .where((request) => request == 'POST $fakeSkoreGradebookRpcPath')
            .length,
        skore.requests.length + 1,
        reason: 'the refused save and the one save',
      );
      expect(
        RegExp(r'Toets Python').allMatches(await period()),
        hasLength(1),
        reason: 'one evaluation',
      );
    });
  });

  test('the flow of the issue: read the period with its components, create '
      'the evaluation the user confirmed, read the period again', () async {
    expect(
      await period(),
      'Gradebook id 34826: Digitale vaardigheden, class 5WW1, school year '
      '2026-2027 (workyear id 24).\n'
      'Period DW1 (period id 1704): open, closes '
      '${_time('2026-12-18T20:00:00+0100')}; Skore opens the gradebook on it '
      '(active).\n'
      'It has no evaluations.\n'
      'Components a new evaluation in this period can count for '
      '(create_skore_evaluation\'s component): geen (component id 0: none), '
      'DW (component id 2). Default: DW.',
    );
    expect(
      await ok('create_skore_evaluation', {
        'gradebook_id': 34826,
        'period_id': 1704,
        'title': 'Toets Python',
        'date': '2026-10-14',
        'max': 20,
        'component': 'DW',
      }),
      startsWith('Created evaluation "Toets Python" in $_where.'),
    );
    expect(
      await period(),
      contains(
        '\n- Toets Python | evaluation id 500100 | column A | 2026-10-14 | max '
        '20 | component DW | points | not published: the pupils do not see '
        'it\n'
        '  no class average | no group average | 0 of 1 pupil has a grade\n'
        '  grades: 1. Jacobs, Gert: no grade\n',
      ),
    );
    expect(skore.evaluationSaves, hasLength(1));
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
