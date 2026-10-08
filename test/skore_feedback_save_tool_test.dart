/// `save_skore_feedback` (#144), called over MCP on the real server, session
/// and library, against a fake Smartschool whose Skore gradebook carries out
/// the feedback POSTs of Skore's REST API in the shape of dartschool's
/// captures of #152 (`test/support/fake_skore_gradebook.dart`). Like the
/// other gradebook tools, it needs no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_feedback_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_feedback_tool.dart';
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
/// three pupils, and three evaluations: Toets 1 (not published; Bart has
/// feedback of the user), Python scripts schrijven (scheduled; An has
/// feedback of the user, Bart of the user and of a colleague) and Lussen
/// (published, no feedback).
const _gradebookName =
    'gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
    '(gradebook id 32508)';
const _where = 'period DW1 (period id 1704) of the $_gradebookName';
const _toetsName = 'evaluation "Toets 1" (evaluation id 500003)';
const _toets =
    'Toets 1 | evaluation id 500003 | column A | 2026-10-08 | max 20 | '
    'component DW | points | not published: the pupils do not see it';

/// The pupils of 6EWI, as a sentence of the tool names them.
const _an = 'Aerts, An (pupil id 1201)';
const _bart = 'Claes, Bart (pupil id 1202)';
const _chloe = 'Dupont, Chloé (pupil id 1203)';

/// The user's feedback as the result lists it: by the fake account.
const _byUser = '- by the user, Jan Peeters (user id 345)';

/// The fake UUID of the first feedback the fake creates.
const _created = '00000000-0000-4000-8000-000000000201';

/// The colleague's feedback for Bart on Python scripts schrijven.
const _colleagues = '00000000-0000-4000-8000-000000000002';

/// The reference of an evaluation of 6EWI in a feedback POST, as the
/// feedback panel sends it.
Map<String, Object?> _reference(int evaluation) => {
  'evaluationId': '12_$evaluation',
  'classGroupId': '12_2440',
  'teacherId': '12_${fakeSkoreGradebookUser}_0',
  'context': '176_472_2440',
};

/// The body of a create, as the feedback panel sends it.
Map<String, Object?> _createBody(
  String text, {
  int pupil = 1201,
  int evaluation = 500003,
}) => {
  'evaluation': _reference(evaluation),
  'studentId': '12_${pupil}_0',
  'text': text,
  'attachments': <Object?>[],
};

/// The body of a change of feedback [id], as the feedback panel sends it.
Map<String, Object?> _changeBody(
  String id,
  String text, {
  int pupil = 1201,
  int evaluation = 500003,
  List<Object?> attachments = const [],
}) => {
  'id': id,
  'evaluation': _reference(evaluation),
  'studentId': '12_${pupil}_0',
  'text': text,
  'attachments': attachments,
};

/// What the tool says after a check of the library refused the change.
String _refused(String reason, {int pupil = 1201}) =>
    'Skore refused the change before saving it: $reason Read the pupil\'s '
    'feedback again with read_skore_feedback (gradebook_id 32508, '
    'evaluation_id 500003, pupil_id $pupil: the user\'s feedback and the '
    'evaluation\'s publication) and the gradebook with read_skore_gradebook '
    '(whether the period is open and the user may change it) to correct the '
    'call. Nothing was changed in Skore.';

/// The tool's own reads before the library is asked, the first time: the
/// gradebooks of the current school year, the gradebook, and the period
/// that holds the evaluation (the pupil's feedback is a GET).
const _toolReads = [
  'getNavigation',
  'init wy=24',
  'getGradebookContext wy=24',
  'getEvaluations wy=24',
];

/// The RPC calls of the library's saveFeedback: its checks.
const _libraryReads = [
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
        readSkoreFeedbackTool(session),
        saveSkoreFeedbackTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method off the library's list, such as one that publishes.
    expect([
      for (final request in skore.requests) request.rpc,
    ], everyElement(isIn(fakeSkoreGradebookRpcMethods)));
    expect(skore.evaluationSaves, isEmpty, reason: 'nothing is created');
    expect(skore.gradeSaves, isEmpty, reason: 'no grade is saved');
    // Never another teacher's feedback: every POST is the user's, a create
    // or a change of the user's own.
    final others = {
      for (final book in skore.gradebooks)
        for (final list in book.evaluations.values)
          for (final evaluation in list)
            for (final feedback in evaluation.feedback.values.expand((f) => f))
              if (feedback.teacherId != fakeSkoreGradebookUser) feedback.id,
    };
    expect(others, contains(_colleagues));
    for (final save in skore.feedbackSaves) {
      expect(
        (save.body['evaluation'] as Map)['teacherId'],
        '12_${fakeSkoreGradebookUser}_0',
      );
      expect(save.path.split('/').last, isNot(isIn(others)));
      expect(save.body['id'], isNot(isIn(others)));
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

  /// Gives An feedback [text] on Toets 1 of 6EWI's gradebook, or what
  /// [arguments] give, and returns the result.
  Future<(bool, String)> save(
    String text, [
    Map<String, Object?> arguments = const {},
  ]) => call('save_skore_feedback', {
    'gradebook_id': 32508,
    'evaluation_id': 500003,
    'pupil_id': 1201,
    'text': text,
    ...arguments,
  });

  Future<String> saved(
    String text, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, result) = await save(text, arguments);
    expect(isError, isFalse, reason: result);
    return result;
  }

  Future<String> refused(
    String text, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, result) = await save(text, arguments);
    expect(isError, isTrue, reason: result);
    return result;
  }

  /// A pupil's feedback on an evaluation of 6EWI, as read_skore_feedback
  /// reads it.
  Future<String> feedback({int pupil = 1201, int evaluation = 500003}) =>
      ok('read_skore_feedback', {
        'gradebook_id': 32508,
        'evaluation_id': evaluation,
        'pupil_id': pupil,
        'period_id': 1704,
      });

  /// 6EWI's gradebook in the fake.
  FakeSkoreOwnGradebook book() =>
      skore.gradebooks.firstWhere((g) => g.id == 32508);

  /// An evaluation of 6EWI's DW1 in the fake.
  FakeSkoreEvaluation evaluation(int id) => book().evaluationWithId(id)!;

  /// The feedback of [pupil] on evaluation [id] in the fake.
  List<FakeSkoreFeedback> feedbackOf(int pupil, [int id = 500003]) =>
      evaluation(id).feedback[pupil] ?? const [];

  bool isFeedbackCreate(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path == fakeSkoreFeedbackCreatePath;

  bool isFeedbackChange(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path.startsWith(fakeSkoreFeedbackPath);

  /// The feedback POSTs that reached the fake Smartschool, before its
  /// session check: also those it refused.
  List<String> postsSent() => [
    for (final request in server.requests)
      if (request.startsWith('POST $fakeSkoreFeedbackCreatePath')) request,
  ];

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
      )).tools.singleWhere((tool) => tool.name == 'save_skore_feedback');
    });

    test('as a write Claude Desktop asks approval for every time, not '
        'idempotent (a first call creates), without a word of '
        '"Skore-beheer", rights or teachers', () {
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isFalse);
      expect(annotations.openWorldHint, isTrue);
      final definition = jsonEncode(tool);
      expect(definition, isNot(matches(_adminWords)));
      expect(definition.toLowerCase(), isNot(contains('teacher')));
    });

    test('tells Claude to read the feedback first, to show the old and the '
        'new text, the pupil and the evaluation, to wait for the user\'s '
        'confirmation, when it may pass allow_published, and what to do '
        'with a save that may not have gone through', () {
      final description = tool.description!;
      for (final part in [
        'One pupil per call: each text is personal.',
        'The text is plain text; line breaks are kept.',
        'Before calling this tool, read the pupil\'s feedback on the '
            'evaluation with read_skore_feedback. When the user already gave '
            'feedback there, this tool replaces its text: show the user the '
            'old text and the new one.',
        'Show the user the pupil (class number and name), the evaluation and '
            'the text, and only call this tool after the user has explicitly '
            'confirmed it.',
        'Feedback that others gave the pupil is never changed.',
        'An evaluation that is published or scheduled is refused unless '
            'allow_published is true: feedback there is visible to the pupil '
            'at once, and the school sends them a notification; in a '
            'scheduled one, from its publication time on. Pass '
            'allow_published: true only after telling the user exactly that '
            'and getting their explicit yes for it.',
        'it changes the user\'s feedback when there is one, and refuses when '
            'the user has more than one there or Skore does not let them '
            'change it.',
        'whether it is new or changed, its text and its time.',
        'If the result says the feedback may or may not have been saved: '
            'read it with read_skore_feedback and tell the user what you '
            'found; calling this tool again is safe, as it changes the '
            'user\'s feedback rather than adding a second.',
      ]) {
        expect(description, contains(part));
      }
    });

    test('takes the gradebook, the evaluation, the pupil and the text, and '
        'optionally the period and allow_published', () {
      final schema = tool.inputSchema;
      expect(schema.required, [
        'gradebook_id',
        'evaluation_id',
        'pupil_id',
        'text',
      ]);
      final properties = schema.properties!;
      expect(properties.keys, [
        'gradebook_id',
        'evaluation_id',
        'period_id',
        'pupil_id',
        'text',
        'allow_published',
      ]);
      for (final name in [
        'gradebook_id',
        'evaluation_id',
        'period_id',
        'pupil_id',
      ]) {
        expect(properties[name], {
          'type': 'integer',
          'description': isA<String>(),
          'minimum': 1,
        }, reason: name);
      }
      expect(properties['text'], {
        'type': 'string',
        'description': isA<String>(),
      });
      expect(properties['allow_published'], {
        'type': 'boolean',
        'description': isA<String>(),
      });
    });
  });

  group('save_skore_feedback', () {
    test('a first save creates the user\'s feedback with the POST of the '
        'feedback panel, sent once; a second changes the same one; '
        'read_skore_feedback shows it', () async {
      expect(
        await feedback(),
        endsWith('\nThe pupil has no feedback on this evaluation.'),
      );
      skore.requests.clear();
      skore.feedbackReads.clear();

      expect(
        await saved('Goed gewerkt.'),
        'Saved new feedback of the user for $_an on the $_toetsName in '
        '$_where.\n'
        'Evaluation: $_toets\n'
        'The feedback as Skore lists it after the save:\n'
        '$_byUser | written ${_time('2026-10-08T12:30:00+02:00')} | the user '
        'may change it\n'
        '  Goed gewerkt.',
      );
      // The tool's reads (the school year from memory) and its read of the
      // pupil's feedback; then the library's checks, its read of the
      // feedback, the create, and the feedback read again to check it.
      expect(skore.calls, [..._toolReads.skip(1), ..._libraryReads]);
      expect([
        for (final read in skore.feedbackReads)
          (read.evaluationId, read.pupilId),
      ], List.filled(3, (500003, 1201)));
      final create = skore.feedbackSaves.single;
      expect(create.path, fakeSkoreFeedbackCreatePath);
      expect(create.body, _createBody('Goed gewerkt.'));
      expect(create.contentType, startsWith('application/json'));
      expect(create.xRequestedWith, 'XMLHttpRequest');
      expect(postsSent(), ['POST $fakeSkoreFeedbackCreatePath']);
      expect([for (final f in feedbackOf(1201)) f.id], [_created]);

      // The second call changes it: the same feedback, the new text.
      skore.feedbackSavedAt = '2026-10-08T12:45:00+02:00';
      expect(
        await saved('Goed gewerkt, let op de lussen.'),
        'Changed the text of the user\'s feedback for $_an on the $_toetsName '
        'in $_where.\n'
        'Evaluation: $_toets\n'
        'The feedback as Skore lists it after the save:\n'
        '$_byUser | written ${_time('2026-10-08T12:30:00+02:00')}, changed '
        '${_time('2026-10-08T12:45:00+02:00')} | the user may change it\n'
        '  Goed gewerkt, let op de lussen.',
      );
      final change = skore.feedbackSaves.last;
      expect(change.path, '$fakeSkoreFeedbackCreatePath/$_created');
      expect(
        change.body,
        _changeBody(_created, 'Goed gewerkt, let op de lussen.'),
      );
      expect(change.xRequestedWith, 'XMLHttpRequest');
      expect(skore.feedbackSaves, hasLength(2));
      expect(
        [for (final f in feedbackOf(1201)) f.text],
        ['Goed gewerkt, let op de lussen.'],
      );

      expect(
        await feedback(),
        endsWith(
          '\n1 feedback text on it, in the order it was written:\n'
          '$_byUser | written ${_time('2026-10-08T12:30:00+02:00')}, changed '
          '${_time('2026-10-08T12:45:00+02:00')} | the user may change it\n'
          '  Goed gewerkt, let op de lussen.',
        ),
      );
    });

    test('changes the user\'s feedback next to a colleague\'s, on a scheduled '
        'evaluation with allow_published: true, sending its attachments back '
        'as they are; the colleague\'s feedback is never sent', () async {
      final list = evaluation(500001).feedback[1202]!;
      final colleague = list[1];
      list[0] = const FakeSkoreFeedback(
        '00000000-0000-4000-8000-000000000001',
        'Eerste opmerking.\nLet op de foutafhandeling.',
        attachments: ['opgave.pdf'],
      );

      final text = await saved('Sterk verbeterd.', {
        'evaluation_id': 500001,
        'pupil_id': 1202,
        'allow_published': true,
      });

      expect(
        text,
        allOf(
          startsWith(
            'Changed the text of the user\'s feedback for $_bart on the '
            'evaluation "Python scripts schrijven" (evaluation id 500001) in '
            '$_where.\n'
            'Evaluation: Python scripts schrijven (short name toets-python) | '
            'evaluation id 500001 | column B | 2026-09-30 | max 100 | '
            'component DW | points | SCHEDULED for '
            '${_time('2099-01-11T08:00:00+01:00')}: from then on the pupils '
            'see it and its grades\n',
          ),
          endsWith(
            '\n$_byUser | written ${_time('2026-10-08T09:49:36+02:00')}, '
            'changed ${_time('2026-10-08T12:30:00+02:00')} | 1 attachment: '
            'opgave.pdf | the user may change it\n'
            '  Sterk verbeterd.',
          ),
        ),
      );
      expect(
        skore.feedbackSaves.single.path,
        '$fakeSkoreFeedbackCreatePath/00000000-0000-4000-8000-000000000001',
      );
      expect(
        skore.feedbackSaves.single.body,
        _changeBody(
          '00000000-0000-4000-8000-000000000001',
          'Sterk verbeterd.',
          pupil: 1202,
          evaluation: 500001,
          attachments: [
            {
              'id': 'att-1',
              'name': 'opgave.pdf',
              'type': 'OTHER',
              'size': 1234,
              'downloadUrl': '/fake/download',
            },
          ],
        ),
      );
      // The colleague's feedback is as it was, still second.
      expect(feedbackOf(1202, 500001), hasLength(2));
      expect(feedbackOf(1202, 500001)[1], same(colleague));
    });

    test('a pupil with only a colleague\'s feedback gets the user\'s own, '
        'created next to it', () async {
      evaluation(500003).feedback[1203] = [
        const FakeSkoreFeedback(
          '00000000-0000-4000-8000-000000000009',
          'Van een collega.',
          teacherId: fakeSkoreColleague,
          teacherName: 'Céline Dupré',
          canEdit: false,
        ),
      ];

      expect(
        await saved('Netjes.', {'pupil_id': 1203}),
        startsWith(
          'Saved new feedback of the user for $_chloe on the $_toetsName in '
          '$_where.\n',
        ),
      );
      expect(
        skore.feedbackSaves.single.body,
        _createBody('Netjes.', pupil: 1203),
      );
      expect(
        [for (final f in feedbackOf(1203)) f.text],
        ['Van een collega.', 'Netjes.'],
      );
    });

    test('sends the text trimmed, keeping the lines within it, and lists it '
        'line by line', () async {
      expect(
        await saved('  \nGoed gewerkt.\n\nLet op de lussen.  \n'),
        endsWith('\n  Goed gewerkt.\n  \n  Let op de lussen.'),
      );
      expect(
        skore.feedbackSaves.single.body['text'],
        'Goed gewerkt.\n\nLet op de lussen.',
      );
    });

    test('a blank text, or none: an error before anything is sent', () async {
      for (final text in ['', '   ', '\n\t ']) {
        expect(
          await refused(text),
          'text must not be blank: give the feedback the user confirmed. '
          'Nothing was changed in Skore.',
          reason: jsonEncode(text),
        );
      }
      final (isError, missing) = await call('save_skore_feedback', {
        'gradebook_id': 32508,
        'evaluation_id': 500003,
        'pupil_id': 1201,
      });
      expect(isError, isTrue);
      expect(missing, contains('Required property "text" is missing'));
      expect(skore.requests, isEmpty);
      expect(skore.feedbackReads, isEmpty);
      expect(server.logins, 0);
    });

    test('a pupil the gradebook does not have: an error before the '
        'evaluations are read; an evaluation it does not have, or a '
        'gradebook of an earlier school year: an error, nothing sent', () async {
      expect(
        await refused('Goed gewerkt.', {'pupil_id': 1999}),
        'The $_gradebookName has no pupil with pupil id 1999. Take the pupil '
        'id from list_skore_evaluations or read_skore_gradebook for this '
        'gradebook. Nothing was changed in Skore.',
      );
      expect(skore.calls, isNot(contains('getEvaluations wy=24')));
      expect(
        await refused('Goed gewerkt.', {'evaluation_id': 400101}),
        'The $_gradebookName has no evaluation with evaluation id 400101 in '
        'its only period, DW1 (period id 1704). Take the evaluation id from '
        'list_skore_evaluations, with the period_id of its period. Nothing '
        'was changed in Skore.',
      );
      await ok('list_skore_gradebooks', {'workyear_id': 22});
      expect(
        await refused('Goed gewerkt.', {
          'gradebook_id': 28998,
          'evaluation_id': 400101,
          'pupil_id': 1301,
        }),
        'Gradebook id 28998 is of school year 2025-2026 (workyear id 22), not '
        'of Skore\'s current school year, 2026-2027 (workyear id 24): only a '
        'gradebook of the current school year can be changed. Nothing was '
        'changed in Skore.',
      );
      expect(skore.feedbackReads, isEmpty);
      expect(skore.feedbackSaves, isEmpty);
    });

    group('a published or scheduled evaluation without allow_published: '
        'refused before the feedback is read, saying what the pupil would '
        'see and that the user must say yes to it', () {
      test('published', () async {
        expect(
          await refused('Goed gewerkt.', {'evaluation_id': 500002}),
          'The evaluation "Lussen" (evaluation id 500002) in $_where is '
          'PUBLISHED since ${_time('2026-10-01T08:00:00+02:00')}: its pupils '
          'would see the feedback at once, and the school sends them a '
          'notification. Tell the user exactly that, and only if the user '
          'explicitly says yes to it, call save_skore_feedback again with '
          'allow_published: true. Nothing was changed in Skore.',
        );
      });

      test('scheduled, also with allow_published false', () async {
        expect(
          await refused('Goed gewerkt.', {
            'evaluation_id': 500001,
            'allow_published': false,
          }),
          'The evaluation "Python scripts schrijven" (evaluation id 500001) '
          'in $_where is SCHEDULED for '
          '${_time('2099-01-11T08:00:00+01:00')}: its pupils would see the '
          'feedback from then on. Tell the user exactly that, and only if the '
          'user explicitly says yes to it, call save_skore_feedback again '
          'with allow_published: true. Nothing was changed in Skore.',
        );
      });

      tearDown(() {
        expect(skore.feedbackSaves, isEmpty);
        expect(skore.feedbackReads, isEmpty);
        expect(skore.calls, _toolReads, reason: 'the library was not asked');
      });
    });

    test('with allow_published: true, feedback is saved on a published '
        'evaluation, and the result says the pupils see it', () async {
      expect(
        await saved('Goed gewerkt.', {
          'evaluation_id': 500002,
          'allow_published': true,
        }),
        startsWith(
          'Saved new feedback of the user for $_an on the evaluation "Lussen" '
          '(evaluation id 500002) in $_where.\n'
          'Evaluation: Lussen | evaluation id 500002 | column C | 2026-09-23 | '
          'max 20 | no component | points | PUBLISHED since '
          '${_time('2026-10-01T08:00:00+02:00')}: the pupils see it and its '
          'grades\n',
        ),
      );
      expect(
        skore.feedbackSaves.single.body,
        _createBody('Goed gewerkt.', evaluation: 500002),
      );
    });

    group('refused in its own words, with what to tell the user, before the '
        'library is asked:', () {
      test('the user has more than one feedback of their own for the pupil '
          'there', () async {
        evaluation(500003).feedback[1202]!.add(
          const FakeSkoreFeedback(
            '00000000-0000-4000-8000-000000000005',
            'Nog een opmerking.',
            createdAt: '2026-10-08T11:25:00+02:00',
          ),
        );

        expect(
          await refused('Goed gewerkt.', {'pupil_id': 1202}),
          'The user has 2 feedback texts of their own for $_bart on the '
          '$_toetsName in $_where (written '
          '${_time('2026-10-08T11:20:00+02:00')}, '
          '${_time('2026-10-08T11:25:00+02:00')}): the server changes none '
          'of them, as it cannot tell which one is meant. Show them to the '
          'user with read_skore_feedback, and tell the user to keep only one '
          'of them in Smartschool; then save_skore_feedback changes that one. '
          'Nothing was changed in Skore.',
        );
      });

      test('Skore does not let the user change their feedback', () async {
        evaluation(500003).feedback[1202] = [
          const FakeSkoreFeedback(
            '00000000-0000-4000-8000-000000000003',
            'Feedback zonder cijfer.',
            createdAt: '2026-10-08T11:20:00+02:00',
            canEdit: false,
          ),
        ];

        expect(
          await refused('Goed gewerkt.', {'pupil_id': 1202}),
          'Skore does not let the user change their feedback for $_bart on '
          'the $_toetsName in $_where (written '
          '${_time('2026-10-08T11:20:00+02:00')}), so the server cannot save '
          'the new text, and it does not add a second feedback next to it. '
          'Tell the user so; read_skore_feedback shows the feedback as it '
          'is. Nothing was changed in Skore.',
        );
      });

      tearDown(() {
        expect(skore.feedbackSaves, isEmpty);
        expect(skore.calls, _toolReads, reason: 'the library was not asked');
        expect(skore.feedbackReads, hasLength(1));
      });
    });

    test('the feedback changes between the tool\'s read and the library\'s: '
        'the library refuses it, and its reason is passed on', () async {
      var reads = 0;
      skore.beforeAnswer = (rpc, params) {
        if (rpc == 'getEvaluations' && ++reads == 2) {
          evaluation(500003).feedback[1201] = [
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000007',
              'A',
            ),
            const FakeSkoreFeedback(
              '00000000-0000-4000-8000-000000000008',
              'B',
            ),
          ];
        }
      };

      expect(
        await refused('Goed gewerkt.'),
        _refused(
          'you gave pupil 1201 2 feedbacks on evaluation 500003 ("Toets 1") '
          'in period DW1 (1704) of gradebook 32508 already '
          '(00000000-0000-4000-8000-000000000007, '
          '00000000-0000-4000-8000-000000000008): the library changes none of '
          'them, as it cannot tell which one is meant. Keep one in '
          'Smartschool.',
        ),
      );
      expect(skore.feedbackSaves, isEmpty);
      expect(skore.calls, [..._toolReads, ..._libraryReads]);
    });

    test('Skore refuses the save (HTTP 4xx): nothing was saved, and the '
        'answer, which can quote the text, goes to the log only', () async {
      skore.feedbackSaveAnswer = (
        status: 422,
        body: jsonEncode({
          'title': 'Unprocessable Entity',
          'detail': 'De tekst "Geheime opmerking." is niet toegestaan',
        }),
      );

      final text = await refused('Geheime opmerking.');
      expect(
        text,
        'Skore did not save the feedback for $_an on the $_toetsName in '
        '$_where: it refused the save, or gave an answer the server could not '
        'use; the technical details are in the server log. Tell the user; '
        'trying again in a moment may help, else the user can give the '
        'feedback in Smartschool. Nothing was changed in Skore.',
      );
      expect(text, isNot(contains('Geheime')));
      expect(skore.feedbackSaves, hasLength(1));
      expect(feedbackOf(1201), isEmpty);
    });
  });

  group('feedback Skore does not confirm is reported with how to check it; '
      'the call is not repeated:', () {
    test(
      'a new feedback whose answer was lost: read it, and calling again '
      'changes the one the create made rather than adding a second',
      () async {
        skore.feedbackSaveAnswerLost = true;

        final (isError, text) = await save('Goed gewerkt.');

        expect(isError, isTrue);
        expect(
          text,
          'The new feedback for $_an on the $_toetsName in $_where was sent, '
          'but Skore did not confirm it: it may or may not have been saved. '
          'First read the pupil\'s feedback with read_skore_feedback '
          '(gradebook_id 32508, evaluation_id 500003, pupil_id 1201, period_id '
          '1704) and tell the user what you found. If the user\'s feedback is '
          'not there, or its text is not the one the user confirmed, calling '
          'save_skore_feedback again with that text is safe: it reads the '
          'pupil\'s feedback first, and changes the user\'s feedback if this '
          'one was created, rather than adding a second.',
        );
        expect(postsSent(), hasLength(1), reason: 'sent once');

        // What the result asks for: read it, and call again if needed.
        expect(await feedback(), endsWith('\n  Goed gewerkt.'));
        skore.feedbackSaveAnswerLost = false;
        expect(
          await saved('Goed gewerkt.'),
          startsWith(
            'Changed the text of the user\'s feedback for $_an on the '
            '$_toetsName in $_where.\n',
          ),
        );
        expect(
          skore.feedbackSaves.last.path,
          '$fakeSkoreFeedbackCreatePath/$_created',
        );
        expect([for (final f in feedbackOf(1201)) f.id], [_created]);
      },
    );

    test('a new feedback Skore answered, but reading again does not list '
        'it', () async {
      skore.onFeedbackSaved = (evaluation, pupilId, saved) =>
          evaluation.feedback[pupilId]!.remove(saved);

      final (isError, text) = await save('Goed gewerkt.');

      expect(isError, isTrue);
      expect(
        text,
        startsWith(
          'The new feedback for $_an on the $_toetsName in $_where was sent, '
          'but Skore did not confirm it: it may or may not have been saved '
          '(Skore answered that it created it, but reading the feedback '
          'again did not confirm it). First read the pupil\'s feedback with '
          'read_skore_feedback ',
        ),
      );
      expect(skore.feedbackSaves, hasLength(1));
    });

    test('a change reading again shows with another text: saving it again '
        'is harmless', () async {
      skore.onFeedbackSaved = (evaluation, pupilId, saved) =>
          evaluation.feedback[pupilId]![0] = saved.changed(
            'Feedback zonder cijfer.',
            at: '2026-10-08T12:30:00+02:00',
          );

      final (isError, text) = await save('Goed gewerkt.', {'pupil_id': 1202});

      expect(isError, isTrue);
      expect(
        text,
        'The new text of the user\'s feedback for $_bart on the $_toetsName in '
        '$_where was sent, but Skore did not confirm it: it may or may not '
        'have been changed. First read the pupil\'s feedback with '
        'read_skore_feedback (gradebook_id 32508, evaluation_id 500003, '
        'pupil_id 1202, period_id 1704) and tell the user what you found. If '
        'its text is not the one the user confirmed, saving it again with '
        'save_skore_feedback is harmless: it sends the whole text again.',
      );
      expect(
        skore.feedbackSaves.single.path,
        '$fakeSkoreFeedbackCreatePath/00000000-0000-4000-8000-000000000003',
      );
    });
  });

  test('Smartschool refuses the session for a create: the library does not '
      'send it again, so the session repeats the call once, which reads the '
      'pupil\'s feedback again first and creates it once', () async {
    final logins = await loggedIn();
    server.expireSessionBefore(isFeedbackCreate);

    expect(
      await saved('Goed gewerkt.'),
      startsWith('Saved new feedback of the user for $_an on the $_toetsName'),
    );
    // The refused create never reached Skore, and the library did not log
    // in again for it: the login is the repeat's, for its first read.
    expect(skore.feedbackSaves, hasLength(1));
    expect(skore.feedbackSaves.single.path, fakeSkoreFeedbackCreatePath);
    expect(postsSent(), hasLength(2));
    expect(server.logins, logins + 1);
    final first = server.requests.indexOf('POST $fakeSkoreFeedbackCreatePath');
    final second = server.requests.lastIndexOf(
      'POST $fakeSkoreFeedbackCreatePath',
    );
    final between = server.requests.sublist(first + 1, second);
    expect(between, contains('POST /login'));
    expect(
      between.where((r) => r.startsWith('GET $fakeSkoreFeedbackPath')),
      hasLength(2),
      reason: 'the tool and the library read the feedback again',
    );
    expect([for (final f in feedbackOf(1201)) f.text], ['Goed gewerkt.']);
  });

  test('Smartschool refuses the session for a change: the library logs in '
      'again and sends the whole text again, once', () async {
    final logins = await loggedIn();
    server.expireSessionBefore(isFeedbackChange);

    expect(
      await saved('Goed gewerkt.', {'pupil_id': 1202}),
      startsWith('Changed the text of the user\'s feedback for $_bart on'),
    );
    expect(skore.feedbackSaves, hasLength(1));
    expect(
      server.requests.where(
        (r) =>
            r ==
            'POST $fakeSkoreFeedbackCreatePath/'
                '00000000-0000-4000-8000-000000000003',
      ),
      hasLength(2),
    );
    expect(server.logins, logins + 1);
    expect([for (final f in feedbackOf(1202)) f.text], ['Goed gewerkt.']);
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
