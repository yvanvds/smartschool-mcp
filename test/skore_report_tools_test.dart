/// The report periods of a gradebook (Skore's "Rapporten", #171,
/// yvanvds/dartschool#195): `read_skore_gradebook` lists them,
/// `read_skore_report` reads one (each pupil's results so far and course
/// comment), and `save_skore_report_comment` writes, changes or clears the
/// course comment of one pupil. Called over MCP on the real server, session
/// and library, against a fake Smartschool whose Skore gradebook answers
/// `getReportsResults` and carries out `saveType` in the shape of
/// dartschool's captures (`test/support/fake_skore_gradebook.dart`). Like
/// the other gradebook tools, they need no switch.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_gradebook_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_report_tool.dart';
import 'package:smartschool_mcp/src/tools/save_skore_report_comment_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

/// [iso], a time with its offset as Skore gives it, as the tools show it:
/// `2026-10-30 23:00` in the time of this PC.
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

/// 6EWI's gradebook (see `fakeSkoreGradebook6EWI`), given the open report
/// R1D ([fakeSkoreReportR1D], with [fakeSkoreReport6EWI]) and the closed
/// report R0 ([fakeSkoreReportR0]) in [main]'s setUp.
const _ewiTitle =
    'Gradebook id 32508: Informaticawetenschappen (2 uur) (6e j DO), class '
    '6EWI, school year 2026-2027 (workyear id 24).';
const _ewiName =
    'gradebook of 6EWI for Informaticawetenschappen (2 uur) (6e j DO) '
    '(gradebook id 32508)';
const _r1d = 'report R1D (Rapport 1, report id 2762)';
const _r1dOfEwi = '$_r1d of the $_ewiName';

/// R1D as the tools list it.
final _r1dLine =
    'R1D (Rapport 1) | report id 2762 | open, closes '
    '${_time('2026-10-30T23:00:00+0100')} | note: Open tot 2026-10-30 23:00. '
    'Schrijf hier je commentaar voor het rapport.';

/// R0 as the tools list it: closed, without a note.
final _r0Line =
    'R0 (Rapport 0) | report id 2570 | closed, closing time '
    '${_time('2026-09-30T23:00:00+0200')}';

/// What read_skore_report says of the course comment of a report that
/// allows 1600 characters, and of an open report.
const _commentNote =
    'The course comment of each pupil is printed on the report that the '
    'pupil and their parents get. Skore keeps one per pupil for this course, '
    'which the colleagues who give it share, and does not say who wrote it; '
    'it may have at most 1600 characters.';
const _openNote =
    'The report is open: save_skore_report_comment writes a comment where '
    'Skore lets the user change it.';

/// The pupils of 6EWI as a sentence of the tools names them.
const _an = 'Aerts, An (pupil id 1201)';
const _bart = 'Claes, Bart (pupil id 1202)';
const _chloe = 'Dupont, Chloé (pupil id 1203)';

/// An's comment on R1D, as Skore keeps it, and as a result shows it.
const _ansComment = 'Goed gewerkt dit trimester.\nBlijf zo verder werken.';
const _ansLines =
    '  Goed gewerkt dit trimester.\n'
    '  Blijf zo verder werken.';

/// The shared gradebooks (#167), as a sentence of the tools names them.
const _gedragName =
    'gradebook of 5WW2 for Gedrag (gradebook id 34980, owner Céline Dupré)';
const _latijnName =
    'gradebook of 4LA for Latijn (gradebook id 34999, owner Sofie Wouters)';

/// The tool's own reads of a save in 6EWI's gradebook, the school year in
/// memory: the gradebook (its report periods and pupils) and the report.
const _toolReads = [
  'init wy=24',
  'getGradebookContext wy=24',
  'getReportsResults wy=24',
];

/// The RPC calls of the library's saveReportComment or clearReportComment
/// in one of the user's own gradebooks: its checks (the user's gradebooks
/// of the current school year, the gradebook's report periods, the report),
/// the save, and the report read again.
const _libraryWrite = [
  'getNavigation',
  'init wy=24',
  'getReportsResults wy=24',
  'saveType wy=24',
  'getReportsResults wy=24',
];

/// What a write tool says after a check of the library refused the change,
/// for a pupil of 6EWI on R1D.
String _reread(int pupil) =>
    'Read the pupil\'s comment again with read_skore_report (gradebook_id '
    '32508, report_id 2762, pupil_id $pupil: the comment now, whether Skore '
    'lets the user change it and whether the report is open) to correct the '
    'call. Nothing was changed in Skore.';

void main() {
  late FakeSmartschool server;
  late FakeSkoreGradebook skore;
  late SmartschoolSession session;
  late ServerConnection connection;

  /// A gradebook of the fake.
  FakeSkoreOwnGradebook book(int id) =>
      skore.gradebooks.firstWhere((g) => g.id == id);

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skoreGradebook
      ..loadSchool()
      ..gradebooks.addAll([
        fakeSkoreGradebookGedrag(),
        fakeSkoreSharedGedrag(),
        fakeSkoreSharedLatijn(),
      ]);
    book(32508)
      ..reports.addAll([fakeSkoreReportR1D, fakeSkoreReportR0])
      ..reportContents[2762] = fakeSkoreReport6EWI()
      ..reportContents[2570] = FakeSkoreReport(
        components: const [
          FakeSkoreReportComponent(
            'DW',
            classAverage: '68',
            results: {1201: '75', 1202: '61'},
          ),
        ],
        comments: {1201: 'Een goede start.'},
      );
    book(34980).reports.add(fakeSkoreReportR1D);
    book(34999).reports.add(fakeSkoreReportR1D);
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listSkoreGradebooksTool(session),
        readSkoreGradebookTool(session),
        readSkoreReportTool(session),
        saveSkoreReportCommentTool(session),
      ],
    );
  });

  tearDown(() {
    // Never a method off the library's list, such as one that closes,
    // unlocks or calculates a report; nothing else is written.
    expect([
      for (final request in skore.requests) request.rpc,
    ], everyElement(isIn(fakeSkoreGradebookRpcMethods)));
    expect(skore.evaluationSaves, isEmpty, reason: 'nothing is created');
    expect(skore.gradeSaves, isEmpty, reason: 'no grade is saved');
    expect(skore.feedbackSaves, isEmpty, reason: 'no feedback is saved');
    // Never the comment closed for Chloé.
    for (final save in skore.reportCommentSaves) {
      expect(save[2], isNot('pupil_1203_2440'));
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

  /// Report [report] (R1D) of gradebook [gradebook] (6EWI), as
  /// read_skore_report reads it.
  Future<String> read({int gradebook = 32508, int report = 2762, int? pupil}) =>
      ok('read_skore_report', {
        'gradebook_id': gradebook,
        'report_id': report,
        'pupil_id': ?pupil,
      });

  /// Calls save_skore_report_comment for [pupil] on R1D of 6EWI, or what
  /// [arguments] give.
  Future<(bool, String)> save(
    int pupil, [
    Map<String, Object?> arguments = const {},
  ]) => call('save_skore_report_comment', {
    'gradebook_id': 32508,
    'report_id': 2762,
    'pupil_id': pupil,
    ...arguments,
  });

  Future<String> saved(
    int pupil, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, text) = await save(pupil, arguments);
    expect(isError, isFalse, reason: text);
    return text;
  }

  Future<String> refused(
    int pupil, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (isError, text) = await save(pupil, arguments);
    expect(isError, isTrue, reason: text);
    return text;
  }

  /// The comment of [pupil] on report [report] of gradebook [gradebook] in
  /// the fake.
  String? commentOf(int pupil, {int gradebook = 32508, int report = 2762}) =>
      book(gradebook).reportOf(report).comments[pupil];

  /// Logs in with a read, and forgets the requests it made.
  Future<void> loggedIn() async {
    await ok('list_skore_gradebooks', {});
    skore.requests.clear();
    server.requests.clear();
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

    test('read_skore_report is read-only and idempotent, and takes a '
        'gradebook, a report and optionally a pupil and a school year', () {
      final tool = tools['read_skore_report']!;
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.openWorldHint, isTrue);
      expect(annotations.destructiveHint, isNot(true));
      expect(tool.inputSchema.required, ['gradebook_id', 'report_id']);
      expect(tool.inputSchema.properties!.keys, [
        'gradebook_id',
        'report_id',
        'pupil_id',
        'workyear_id',
      ]);
      final definition = jsonEncode(tool);
      expect(definition, isNot(matches(_adminWords)));
      expect(definition.toLowerCase(), isNot(contains('teacher')));
      for (final part in [
        'by its report id from read_skore_gradebook',
        'the results so far per component of the course (such as DW)',
        'the text that is printed on the report the pupil and their parents '
            'get, with whether Skore lets the user change it.',
        'Skore keeps one course comment per pupil and course on a report, '
            'which the colleagues who give the course share, and it does not '
            'say who wrote it.',
        'A behaviour gradebook (such as Gedrag) has no results on the '
            'report, only the comment.',
        'Reading changes nothing in Skore.',
      ]) {
        expect(tool.description, contains(part));
      }
    });

    test('save_skore_report_comment is a write Claude Desktop asks approval '
        'for every time, idempotent (the same text is not sent again), '
        'without a word of "Skore-beheer", rights or teachers', () {
      final tool = tools['save_skore_report_comment']!;
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.openWorldHint, isTrue);
      final definition = jsonEncode(tool);
      expect(definition, isNot(matches(_adminWords)));
      expect(definition.toLowerCase(), isNot(contains('teacher')));
    });

    test('save_skore_report_comment tells Claude, as save_skore_feedback '
        'does, to read first, to show the pupil, the comment now and the new '
        'text, that the comment goes on the report, to wait for the user\'s '
        'confirmation, to name the owner of a shared gradebook, and what to '
        'do with a save that may not have gone through', () {
      final description = tools['save_skore_report_comment']!.description!;
      for (final part in [
        'The course comment is printed on the report that the pupil and '
            'their parents get.',
        'One pupil per call: each text is personal.',
        'The text is plain text; line breaks are kept.',
        'Before calling this tool, read the pupil\'s comment with '
            'read_skore_report (with the pupil_id).',
        'Show the user the pupil (class number and name), the report, the '
            'comment now (or that there is none) and the new text (or that '
            'the comment will be cleared), and tell the user that the comment '
            'goes on the report the pupil and their parents get; only call '
            'this tool after the user has explicitly confirmed it.',
        'In a gradebook a colleague shared with the user, also tell the user '
            'whose gradebook it is: its owner',
        'When the pupil has a comment, pass it as current_comment, as '
            'read_skore_report gave it: this tool replaces only that comment',
        'To clear the comment, pass clear: true and current_comment, without '
            'text.',
        'A closed report is refused',
        'A gradebook shared with the user to read only is refused: the user '
            'may read it, not change it.',
        'If the result says the comment may or may not have been saved: read '
            'it with read_skore_report and tell the user what you found; '
            'saving it again is harmless.',
      ]) {
        expect(description, contains(part));
      }
    });

    test('save_skore_report_comment takes the gradebook, the report and the '
        'pupil, and the text, the comment now, or clear', () {
      final schema = tools['save_skore_report_comment']!.inputSchema;
      expect(schema.required, ['gradebook_id', 'report_id', 'pupil_id']);
      final properties = schema.properties!;
      expect(properties.keys, [
        'gradebook_id',
        'report_id',
        'pupil_id',
        'text',
        'current_comment',
        'clear',
      ]);
      for (final name in ['gradebook_id', 'report_id', 'pupil_id']) {
        expect(properties[name], {
          'type': 'integer',
          'description': isA<String>(),
          'minimum': 1,
        }, reason: name);
      }
      for (final name in ['text', 'current_comment']) {
        expect(properties[name], {
          'type': 'string',
          'description': isA<String>(),
        }, reason: name);
      }
      expect(properties['clear'], {
        'type': 'boolean',
        'description': isA<String>(),
      });
    });
  });

  group('read_skore_gradebook', () {
    test('lists the report periods after the evaluation periods, each with '
        'its report id, whether it is open and until when, and Skore\'s '
        'note', () async {
      final text = await ok('read_skore_gradebook', {'gradebook_id': 32508});
      expect(
        text,
        contains(
          '\n2 report periods (Rapporten), in Skore\'s order, where each '
          'pupil\'s course comment is written that goes on the report, while '
          'the report is open; read_skore_report reads one by its report '
          'id:\n'
          '- $_r1dLine\n'
          '- $_r0Line\n'
          '3 pupils, in Skore\'s order:\n',
        ),
      );
      expect(text.indexOf('report periods'), greaterThan(text.indexOf('DW1')));
    });

    test('says nothing of report periods for a gradebook without', () async {
      expect(
        await ok('read_skore_gradebook', {'gradebook_id': 32504}),
        isNot(contains('report')),
      );
    });
  });

  group('read_skore_report', () {
    test(
      'per pupil the results per component and the course comment: the '
      'one the user may change, none yet, and one closed for the pupil; '
      'with the report, the components\' class averages and the limit',
      () async {
        await loggedIn();
        expect(
          await read(),
          '$_ewiTitle\n'
          'Report: $_r1dLine\n'
          'The report shows the course "Informaticawetenschappen (2 uur)" with '
          'the results so far per component, as Skore calculates them from the '
          'evaluations (read-only): DW (class average 71).\n'
          '$_commentNote\n'
          '$_openNote\n'
          '3 pupils, in Skore\'s order:\n'
          '- 1. Aerts, An | pupil id 1201 | DW 79 | comment the user may '
          'change\n'
          '$_ansLines\n'
          '- 2. Claes, Bart | pupil id 1202 | DW 38 (low) | no comment yet, the '
          'user may write one\n'
          '- 3. Dupont, Chloé | pupil id 1203 | DW no result | comment Skore '
          'does not let the user change (closed for this pupil)\n'
          '  Vaak afwezig bij de toetsen.',
        );
        // The gradebook (its report periods and pupils), then the report, as
        // Skore's web client opens it: the report's id as a string, the
        // user's id, in the user's own scope.
        expect(skore.calls, _toolReads);
        final request = skore.requests.last;
        expect(request.params, [
          ['176', '472', '2440'],
          ['2264'],
          '2762',
          fakeSkoreGradebookUser,
        ]);
        expect(request.session['teacher'], fakeSkoreGradebookUser);
        expect(request.session['restriction'], 0);
        expect(skore.reportCommentSaves, isEmpty);
      },
    );

    test('with pupil_id, that pupil only', () async {
      expect(
        await read(pupil: 1201),
        '$_ewiTitle\n'
        'Report: $_r1dLine\n'
        'The report shows the course "Informaticawetenschappen (2 uur)" with '
        'the results so far per component, as Skore calculates them from the '
        'evaluations (read-only): DW (class average 71).\n'
        '$_commentNote\n'
        '$_openNote\n'
        '- 1. Aerts, An | pupil id 1201 | DW 79 | comment the user may '
        'change\n'
        '$_ansLines',
      );
    });

    test('a closed report: its comments as they are, none of them for the '
        'user to change', () async {
      expect(
        await read(report: 2570),
        '$_ewiTitle\n'
        'Report: $_r0Line\n'
        'The report shows the course "Informaticawetenschappen (2 uur)" with '
        'the results so far per component, as Skore calculates them from the '
        'evaluations (read-only): DW (class average 68).\n'
        '$_commentNote\n'
        'The report is closed: its course comments can no longer be '
        'written.\n'
        '3 pupils, in Skore\'s order:\n'
        '- 1. Aerts, An | pupil id 1201 | DW 75 | comment (the report is '
        'closed)\n'
        '  Een goede start.\n'
        '- 2. Claes, Bart | pupil id 1202 | DW 61 | no comment (the report is '
        'closed)\n'
        '- 3. Dupont, Chloé | pupil id 1203 | DW no result | no comment (the '
        'report is closed)',
      );
    });

    test('the behaviour gradebook "Gedrag" (#168): no results, only the '
        'comment', () async {
      expect(
        await read(gradebook: 34901),
        'Gradebook id 34901: Gedrag (A-stroom, D/A en D), class 5WW1, school '
        'year 2026-2027 (workyear id 24).\n'
        'Report: $_r1dLine\n'
        'The report shows no results for the course "Gedrag (A-stroom, D/A en '
        'D)" (a course without components, such as behaviour): only its '
        'course comment.\n'
        '$_commentNote\n'
        '$_openNote\n'
        '2 pupils, in Skore\'s order:\n'
        '- 1. Jacobs, Gert | pupil id 1221 | no comment yet, the user may '
        'write one\n'
        '- 2. Lemmens, Ilse | pupil id 1222 | no comment yet, the user may '
        'write one',
      );
    });

    test('a gradebook a colleague shared with the user: read in the owner\'s '
        'name, restricted to it, its owner named', () async {
      book(34980).reportOf(2762).comments[1231] = 'Een fijne leerling.';
      final text = await read(gradebook: 34980);
      expect(
        text,
        startsWith(
          'Gradebook id 34980: Gedrag, class 5WW2, school year 2026-2027 '
          '(workyear id 24). Its owner, Céline Dupré (user id 346), shared it '
          'with the user to read and write.\n'
          'Report: $_r1dLine\n',
        ),
      );
      expect(
        text,
        endsWith(
          '- 1. Martens, Jonas | pupil id 1231 | comment the user may change\n'
          '  Een fijne leerling.\n'
          '- 2. Nys, Kato | pupil id 1232 | no comment yet, the user may '
          'write one',
        ),
      );
      final request = skore.requests.last;
      expect(request.rpc, 'getReportsResults');
      expect(request.params.last, fakeSkoreGedragOwner.id);
      expect(request.session['teacher'], fakeSkoreGedragOwner.id);
      expect(request.session['restriction'], 34980);
    });

    test('a gradebook shared with the user to read only: its comments are '
        'read, none of them for the user to change, whatever Skore marks in '
        'the owner\'s name', () async {
      book(34999).reportOf(2762).comments[1241] = 'Mooi werk dit trimester.';
      expect(
        await read(gradebook: 34999),
        'Gradebook id 34999: Latijn, class 4LA, school year 2026-2027 '
        '(workyear id 24). Its owner, Sofie Wouters (user id 347), shared it '
        'with the user to read only.\n'
        'Report: $_r1dLine\n'
        'The report shows no results for the course "Latijn" (a course '
        'without components, such as behaviour): only its course comment.\n'
        '$_commentNote\n'
        'The report is open, but the user may read these comments, not '
        'change them: the gradebook is shared with them to read only.\n'
        '1 pupil, in Skore\'s order:\n'
        '- 1. Smets, Lien | pupil id 1241 | comment (shared to read only)\n'
        '  Mooi werk dit trimester.',
      );
      expect(skore.requests.last.session['teacher'], fakeSkoreLatijnOwner.id);
    });

    test(
      'a report id that is not one of the gradebook\'s (such as a period '
      'id): an error that lists its report periods; nothing more is read',
      () async {
        await loggedIn();
        expect(
          await error('read_skore_report', {
            'gradebook_id': 32508,
            'report_id': 1704,
          }),
          'The $_ewiName has no report with report id 1704. Its report periods, '
          'in Skore\'s order: R1D (report id 2762, open), R0 (report id 2570, '
          'closed). Take a report id from these, as read_skore_gradebook lists '
          'them; a period id is not a report id.',
        );
        expect(
          await error('read_skore_report', {
            'gradebook_id': 32504,
            'report_id': 2762,
          }),
          'The gradebook of 6WEWI2 for Informaticawetenschappen (2 uur) (6e j '
          'DO) (gradebook id 32504) has no report with report id 2762: it has '
          'no report periods, so it has no course comments to read or write.',
        );
        expect(skore.calls, isNot(contains('getReportsResults wy=24')));
      },
    );

    test('a pupil the gradebook does not list: an error, before the report '
        'is read', () async {
      await loggedIn();
      expect(
        await error('read_skore_report', {
          'gradebook_id': 32508,
          'report_id': 2762,
          'pupil_id': 9999,
        }),
        'The $_ewiName has no pupil with pupil id 9999. Take the pupil id from '
        'list_skore_evaluations or read_skore_gradebook for this gradebook.',
      );
      expect(skore.calls, isNot(contains('getReportsResults wy=24')));
    });

    test('a course that is not on the report (Skore\'s 404 "Course not found '
        'in source!"): says so, and that trying again does not help; the '
        'library\'s message in the log only', () async {
      book(32508).reportOf(2762).courseOnReport = false;
      final ((result, text), logged) = await captureLog(() async {
        final (connection, _) = await connect(
          tools: [readSkoreReportTool(session)],
        );
        return callTool(connection, 'read_skore_report', {
          'gradebook_id': 32508,
          'report_id': 2762,
        });
      });
      expect(result.isError, isTrue, reason: text);
      expect(
        text,
        'Skore answers that the course of the $_ewiName is not on $_r1d, so '
        'the server cannot read its results or its course comment there. '
        'Skore answers so for a course that is on the report through a '
        'project (Skore\'s "Projecten"), which the server does not read yet. '
        'Tell the user so; trying again does not help. The user sees the '
        'report in Skore in Smartschool itself.',
      );
      expect(text, isNot(contains('Course not found')));
      expect(logged, contains('HTTP 404: "Course not found in source!"'));
    });

    test('another answer Skore\'s gradebook cannot use: the general '
        'message, not the one of a course that is not on the report', () async {
      skore.answers['getReportsResults'] = (
        status: 404,
        body: '{"message":"Not found"}',
      );
      final text = await error('read_skore_report', {
        'gradebook_id': 32508,
        'report_id': 2762,
      });
      expect(text, startsWith('Skore\'s gradebook gave an answer the server '));
    });
  });

  group('save_skore_report_comment', () {
    test('writes a comment for a pupil without one with saveType, as the '
        'web client sends it, once; read_skore_report shows it', () async {
      await loggedIn();
      expect(
        await saved(1202, {
          'text': '  Werkt goed mee in de les.\n\n\n Let op bij de toetsen. ',
        }),
        'Wrote the course comment for $_bart on $_r1dOfEwi.\n'
        'It is printed on the report the pupil and their parents get.\n'
        'The comment before: none.\n'
        'The comment as Skore shows it after the save:\n'
        '  Werkt goed mee in de les.\n'
        '  \n'
        '  Let op bij de toetsen.',
      );
      // The tool's reads, then the library's checks, the save and the
      // report read again.
      expect(skore.calls, [..._toolReads, ..._libraryWrite]);
      expect(skore.reportCommentSaves, [
        [
          'info',
          '2264_info',
          'pupil_1202_2440',
          // Trimmed, each line trimmed, no more than one empty line in a row.
          'Werkt goed mee in de les.\n\nLet op bij de toetsen.',
          ['1', '2762'],
          ['176', '472', '2440'],
        ],
      ]);
      final save = skore.requests.firstWhere((r) => r.rpc == 'saveType');
      expect(save.session['teacher'], fakeSkoreGradebookUser);
      expect(save.session['restriction'], 0);
      expect(
        commentOf(1202),
        'Werkt goed mee in de les.\n\nLet op bij de toetsen.',
      );
      expect(
        await read(pupil: 1202),
        endsWith(
          '- 2. Claes, Bart | pupil id 1202 | DW 38 (low) | comment the user '
          'may change\n'
          '  Werkt goed mee in de les.\n'
          '  \n'
          '  Let op bij de toetsen.',
        ),
      );
    });

    test('changes a comment passed as current_comment (white space aside), '
        'and shows it before and after', () async {
      expect(
        await saved(1201, {
          'text': 'Goed gewerkt, ga zo door.',
          'current_comment':
              'Goed gewerkt dit trimester. Blijf zo verder werken.',
        }),
        'Changed the course comment for $_an on $_r1dOfEwi.\n'
        'It is printed on the report the pupil and their parents get.\n'
        'The comment before:\n'
        '$_ansLines\n'
        'The comment as Skore shows it after the save:\n'
        '  Goed gewerkt, ga zo door.',
      );
      expect(skore.reportCommentSaves, hasLength(1));
      expect(commentOf(1201), 'Goed gewerkt, ga zo door.');
    });

    test('a pupil with a comment, without current_comment: refused, with '
        'the comment now, to show the user; nothing is sent', () async {
      expect(
        await refused(1201, {'text': 'Goed gewerkt, ga zo door.'}),
        '$_an has a course comment on $_r1dOfEwi already, which this call '
        'would replace:\n'
        '$_ansLines\n'
        'Show the user this comment and the new text, and only after they '
        'confirm, call save_skore_report_comment again with this comment as '
        'current_comment. Nothing was changed in Skore.',
      );
      expect(skore.reportCommentSaves, isEmpty);
      expect(commentOf(1201), _ansComment);
    });

    test('another comment than current_comment (a colleague changed it): '
        'refused, with the comment now; nothing is sent', () async {
      expect(
        await refused(1201, {
          'text': 'Goed gewerkt, ga zo door.',
          'current_comment': 'Goed gewerkt.',
        }),
        'The course comment of $_an on $_r1dOfEwi is not the one passed as '
        'current_comment: the colleagues who give the course share it, and '
        'it may have been changed since it was read. It is now:\n'
        '$_ansLines\n'
        'Show the user this comment and the new text, and only after they '
        'confirm, call save_skore_report_comment again with this comment as '
        'current_comment. Nothing was changed in Skore.',
      );
      // A comment passed for a pupil who has none (cleared meanwhile).
      expect(
        await refused(1202, {
          'text': 'Werkt goed mee.',
          'current_comment': 'Een oude tekst.',
        }),
        '$_bart has no course comment on $_r1dOfEwi now, not the one passed '
        'as current_comment: it may have been cleared since it was read. '
        'Tell the user so; only after they confirm the new text again, call '
        'save_skore_report_comment again without current_comment. Nothing '
        'was changed in Skore.',
      );
      expect(skore.reportCommentSaves, isEmpty);
    });

    test('clears a comment with clear: true and current_comment: saveType '
        'with an empty text; read_skore_report shows none', () async {
      await loggedIn();
      expect(
        await saved(1201, {'clear': true, 'current_comment': _ansComment}),
        'Cleared the course comment for $_an on $_r1dOfEwi.\n'
        'The report the pupil and their parents get shows no course comment '
        'for this course now.\n'
        'The comment before:\n'
        '$_ansLines\n'
        'The comment as Skore shows it after the save: none.',
      );
      expect(skore.calls, [..._toolReads, ..._libraryWrite]);
      expect(skore.reportCommentSaves.single[3], '');
      expect(commentOf(1201), isNull);
      expect(
        await read(pupil: 1201),
        endsWith(
          '- 1. Aerts, An | pupil id 1201 | DW 79 | no comment yet, the user '
          'may write one',
        ),
      );
    });

    test('a clear without current_comment: refused, with the comment; and a '
        'clear with a text: refused before anything is sent', () async {
      expect(
        await refused(1201, {'clear': true}),
        '$_an has a course comment on $_r1dOfEwi already, which this call '
        'would clear:\n'
        '$_ansLines\n'
        'Show the user this comment, and only after they confirm, call '
        'save_skore_report_comment again with this comment as '
        'current_comment. Nothing was changed in Skore.',
      );
      await loggedIn();
      expect(
        await refused(1201, {'clear': true, 'text': 'Iets.'}),
        'Pass either a text or clear: true, not both: clear: true clears the '
        'pupil\'s comment. Nothing was changed in Skore.',
      );
      expect(skore.requests, isEmpty);
      expect(commentOf(1201), _ansComment);
    });

    test('nothing to send: a comment that already is the text (white space '
        'aside), or none to clear', () async {
      await loggedIn();
      expect(
        await saved(1201, {
          'text': 'Goed gewerkt dit trimester.\n  Blijf zo verder werken. ',
          'current_comment': 'Iets anders.',
        }),
        'The course comment for $_an on $_r1dOfEwi already is this text, so '
        'nothing was sent, and nothing was changed in Skore.\n'
        'The comment:\n'
        '$_ansLines',
      );
      expect(
        await saved(1202, {'clear': true}),
        '$_bart has no course comment on $_r1dOfEwi, so there is nothing to '
        'clear: nothing was sent, and nothing was changed in Skore.',
      );
      expect(skore.calls, [..._toolReads, ..._toolReads]);
    });

    test(
      'refused before anything is sent: a blank text, an unknown report '
      'or pupil, a closed report, a comment closed for the pupil, a text '
      'longer than the report allows, a report without course comments',
      () async {
        await loggedIn();
        expect(
          await refused(1202, {'text': ' \n '}),
          'text must not be blank: give the course comment the user confirmed, '
          'or pass clear: true to clear the pupil\'s comment. Nothing was '
          'changed in Skore.',
        );
        expect(await refused(1202), startsWith('text must not be blank'));
        expect(skore.requests, isEmpty);

        expect(
          await refused(1202, {'text': 'Iets.', 'report_id': 1704}),
          startsWith('The $_ewiName has no report with report id 1704. '),
        );
        expect(
          await refused(9999, {'text': 'Iets.'}),
          'The $_ewiName has no pupil with pupil id 9999. Take the pupil id from '
          'list_skore_evaluations or read_skore_gradebook for this gradebook. '
          'Nothing was changed in Skore.',
        );
        expect(
          await refused(1201, {
            'text': 'Iets.',
            'report_id': 2570,
            'current_comment': 'Een goede start.',
          }),
          'Report R0 (Rapport 0, report id 2570) of the $_ewiName is closed '
          '(closing time ${_time('2026-09-30T23:00:00+0200')}): its course '
          'comments can no longer be written. Tell the user so. Nothing was '
          'changed in Skore.',
        );
        // None of these read the report.
        expect(skore.calls, isNot(contains('getReportsResults wy=24')));

        expect(
          await refused(1203, {
            'text': 'Iets.',
            'current_comment': 'Vaak afwezig bij de toetsen.',
          }),
          'Skore does not let the user change the course comment of $_chloe on '
          '$_r1dOfEwi: it is closed for this pupil. Tell the user so; '
          'read_skore_report shows the comment as it is. Nothing was changed in '
          'Skore.',
        );
        book(32508).reportOf(2762).length = '20';
        expect(
          await refused(1202, {
            'text': 'Een tekst van meer dan twintig tekens.',
          }),
          'The text has 38 characters, more than the 20 that $_r1dOfEwi allows '
          'for a course comment. Shorten it with the user, and call '
          'save_skore_report_comment again with the text they confirm. Nothing '
          'was changed in Skore.',
        );
        book(32508).reportOf(2762).hasComments = false;
        expect(
          await refused(1202, {'text': 'Iets.'}),
          'Report R1D (Rapport 1, report id 2762) of the $_ewiName has no '
          'course comment for this course: there is nothing to write. Tell the '
          'user so. Nothing was changed in Skore.',
        );
        book(32508).reportOf(2762).courseOnReport = false;
        expect(
          await refused(1202, {'text': 'Iets.'}),
          allOf(
            startsWith(
              'Skore answers that the course of the $_ewiName is not ',
            ),
            endsWith('Nothing was changed in Skore.'),
          ),
        );
        expect(skore.reportCommentSaves, isEmpty);
        expect(skore.calls, isNot(contains('getNavigation')));
      },
    );

    test('the behaviour gradebook "Gedrag" (#168), without evaluation '
        'periods: written as any other', () async {
      await loggedIn();
      expect(
        await saved(1221, {
          'gradebook_id': 34901,
          'text': 'Is beleefd en behulpzaam.',
        }),
        'Wrote the course comment for Jacobs, Gert (pupil id 1221) on $_r1d '
        'of the gradebook of 5WW1 for Gedrag (A-stroom, D/A en D) (gradebook '
        'id 34901).\n'
        'It is printed on the report the pupil and their parents get.\n'
        'The comment before: none.\n'
        'The comment as Skore shows it after the save:\n'
        '  Is beleefd en behulpzaam.',
      );
      // No getGradebookContext: the gradebook has no evaluation periods,
      // and the library does not ask it for a report.
      expect(skore.calls, [
        'init wy=24',
        'getReportsResults wy=24',
        ..._libraryWrite,
      ]);
      expect(skore.reportCommentSaves.single.sublist(0, 3), [
        'info',
        '1902_info',
        'pupil_1221_2516',
      ]);
      expect(commentOf(1221, gradebook: 34901), 'Is beleefd en behulpzaam.');
    });

    test('a gradebook a colleague shared with the user to read and write, '
        'as the co-titularis has their class\'s "Gedrag": written in the '
        'owner\'s name, restricted to it, the owner named', () async {
      await loggedIn();
      expect(
        await saved(1232, {
          'gradebook_id': 34980,
          'text': 'Let beter op in de les.',
        }),
        'Wrote the course comment for Nys, Kato (pupil id 1232) on $_r1d of '
        'the $_gedragName.\n'
        'It is printed on the report the pupil and their parents get.\n'
        'The comment before: none.\n'
        'The comment as Skore shows it after the save:\n'
        '  Let beter op in de les.',
      );
      expect(skore.calls, [
        'init wy=24',
        'getGradebookContext wy=24',
        'getReportsResults wy=24',
        'getNavigation',
        'accessableList',
        'init wy=24',
        'getReportsResults wy=24',
        'saveType wy=24',
        'getReportsResults wy=24',
      ]);
      final save = skore.requests.firstWhere((r) => r.rpc == 'saveType');
      expect(save.session['teacher'], fakeSkoreGedragOwner.id);
      expect(save.session['restriction'], 34980);
      expect(save.params.sublist(0, 3), [
        'info',
        '1904_info',
        'pupil_1232_2518',
      ]);
      expect(commentOf(1232, gradebook: 34980), 'Let beter op in de les.');
    });

    test('a gradebook shared with the user to read only: refused in the '
        'server\'s words, with its owner, before it is read', () async {
      await loggedIn();
      expect(
        await refused(1241, {'gradebook_id': 34999, 'text': 'Mooi werk.'}),
        'Skore lists the $_latijnName as shared with the user to read only: '
        'the user may read it, not change it. Tell the user so; its owner, '
        'Sofie Wouters, can make the change, or share the gradebook with the '
        'user to write. Nothing was changed in Skore.',
      );
      expect(skore.requests, isEmpty);
    });

    test(
      'a comment written between the tool\'s read and the library\'s: '
      'the library\'s refusal, with what to read again; nothing is sent',
      () async {
        var reads = 0;
        skore.beforeAnswer = (rpc, params) {
          if (rpc == 'getReportsResults' && ++reads == 2) {
            book(32508).reportOf(2762).comments[1202] = 'Een collega schreef.';
          }
        };
        final text = await refused(1202, {'text': 'Werkt goed mee.'});
        expect(text, startsWith('Skore refused the change before saving it: '));
        expect(text, endsWith(_reread(1202)));
        expect(skore.reportCommentSaves, isEmpty);
        expect(commentOf(1202), 'Een collega schreef.');
      },
    );

    test('a session Smartschool refuses for the save: the library logs in '
        'again and sends it once more; saved once', () async {
      await loggedIn();
      bool isSave(RequestOptions request) =>
          request.uri.path == fakeSkoreGradebookRpcPath &&
          '${(request.data as Map)['rpc_method']}' == 'saveType';
      server.expireSessionBefore(isSave);
      expect(
        await saved(1202, {'text': 'Werkt goed mee.'}),
        startsWith('Wrote the course comment for $_bart on $_r1dOfEwi.\n'),
      );
      expect(server.refusedPosts, ['302 $fakeSkoreGradebookRpcPath']);
      expect(skore.reportCommentSaves, hasLength(1));
      expect(commentOf(1202), 'Werkt goed mee.');
    });
  });

  group('a comment Skore does not confirm is reported with how to check '
      'it, and not sent again', () {
    test('a save answered without savedState 1', () async {
      skore.answers['saveType'] = (
        status: 200,
        body: jsonEncode({
          'result': {'savedState': 0},
          'session': 1,
          'method': 'saveType',
        }),
      );
      final text = await refused(1202, {'text': 'Werkt goed mee.'});
      expect(
        text,
        'The course comment for $_bart on $_r1dOfEwi was sent, but Skore did '
        'not confirm it: it may or may not have been saved. First read the '
        'pupil\'s comment with read_skore_report (gradebook_id 32508, '
        'report_id 2762, pupil_id 1202) and tell the user what you found. If '
        'it shows the text the user confirmed, it was saved. If it still '
        'shows the comment as it was before, saving it again with '
        'save_skore_report_comment is harmless: pass the same text, with the '
        'comment it shows (if any) as current_comment. If it shows another '
        'text than either, show that to the user first.',
      );
      expect(skore.reportCommentSaves, hasLength(1));
    });

    test('a clear answered with HTTP 500', () async {
      skore.answers['saveType'] = (
        status: 500,
        body: '{"message":"Internal Server Error"}',
      );
      expect(
        await refused(1201, {'clear': true, 'current_comment': _ansComment}),
        'The clear of the course comment for $_an on $_r1dOfEwi was sent, but '
        'Skore did not confirm it: it may or may not have been cleared. First '
        'read the pupil\'s comment with read_skore_report (gradebook_id '
        '32508, report_id 2762, pupil_id 1201) and tell the user what you '
        'found. If it still shows the comment, clearing it again with '
        'save_skore_report_comment is harmless: pass clear: true and the '
        'comment it shows as current_comment.',
      );
      expect(skore.reportCommentSaves, hasLength(1));
      expect(commentOf(1201), _ansComment);
    });

    test('a save Skore answered, whose comment the report read again does '
        'not show', () async {
      skore.onReportCommentSaved = (book, report, pupil) =>
          book.reportOf(report).comments.remove(pupil);
      expect(
        await refused(1202, {'text': 'Werkt goed mee.'}),
        startsWith(
          'The course comment for $_bart on $_r1dOfEwi was sent, but Skore '
          'did not confirm it: it may or may not have been saved.',
        ),
      );
      expect(skore.reportCommentSaves, hasLength(1));
    });
  });
}
