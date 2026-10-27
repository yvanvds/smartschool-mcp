/// `read_lvs_absences` (#157), called over MCP on the real server, session
/// and library (`LvsService.getAbsences`), against a fake Smartschool whose
/// pupil tracking system (LVS) answers with the hand-written fixtures of
/// `test/fixtures/lvs/absences/` (the fakes of `FAKES.md` only, checked by
/// `test/lvs_fixtures_guard_test.dart`): the totals per code and the
/// half-days of the current school year and of another, the other school
/// years summed up, motivations only with `with_motivation`, no absences as
/// a sentence, an unknown pupil told apart by the file, "no access to the
/// absences", and the privacy rules every LVS tool follows (#153): only
/// reads, nothing on disk, nothing of an answer or an error's message in the
/// log.
///
/// The fixtures are in the shape of a real pupil's answer as the developer
/// captured it in a browser (yvanvds/dartschool#176, shapes only): the
/// library's own, and one written here (days the library cannot date, a
/// period that is not a school year, an empty school year).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/lvs/lvs_absences.dart';
import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/lvs_tool_harness.dart';

/// Today in the tests: in the school year 2031-2032, the one the library's
/// fixture names (`year_label`).
final _now = DateTime.utc(2031, 10, 25, 9);

/// The request of [pupil]'s absences.
String _call([FakeLvsPupil pupil = fakeLvsMarie]) =>
    'POST /LVS/Pupilpresences pupilID=${pupil.pupilId} '
    'groupID=${pupil.classId}';

/// The two requests of [pupil]'s file.
List<String> _fileCalls(FakeLvsPupil pupil) => [
  'GET /LVS/Spotlight/${pupil.pupilId}?classID=${pupil.classId}',
  'POST /LVS/Pupilxhr/getStatusInfo pupilID=${pupil.pupilId}',
];

/// Marie's absences in 2031-2032, the current school year, as listed.
const _currentList =
    '- 2031-09-18 (Thursday) | afternoon | Testcode 2 (TB)\n'
    '- 2032-01-20 (Tuesday) | whole day | Testcode (TA)';

/// Marie's other school year, 2030-2031, summed up.
const _otherPast =
    'Other school years the LVS gives (it picks them itself), with their '
    'totals; pass one as school_year for its absences:\n'
    '- 2030-2031: 4 half-days (1 whole day and 2 half-days); Testcode (TA): 3 '
    'half-days (1 whole day and 1 half-day); Testcode 2 (TB): 1 half-day';

/// Marie's other school year, 2031-2032, summed up.
const _otherCurrent =
    'Other school years the LVS gives (it picks them itself), with their '
    'totals; pass one as school_year for its absences:\n'
    '- 2031-2032: 3 half-days (1 whole day and 1 half-day); Testcode 2 (TB): '
    '1 half-day; Testcode (TA): 2 half-days (1 whole day)';

/// The answer for Marie, of the current school year.
const _currentAnswer =
    'The absences of the pupil with pupil_id 900002 (class_id 900102) in the '
    'LVS in the school year 2031-2032: 3 half-days (1 whole day and 1 '
    "half-day), day after day in the LVS's order. The codes are the school's "
    'own.\n'
    'Totals per code:\n'
    '- Testcode 2 (TB): 1 half-day\n'
    '- Testcode (TA): 2 half-days (1 whole day)\n'
    '1 of the 2 absences has a motivation, not shown, as a motivation can hold '
    'health information: pass with_motivation true only when the user asks '
    'why the pupil was absent.\n'
    '$_currentList\n'
    '$_otherPast';

/// The head of the answer for Marie, of the school year 2030-2031.
const _pastHead =
    'The absences of the pupil with pupil_id 900002 (class_id 900102) in the '
    'LVS in the school year 2030-2031: 4 half-days (1 whole day and 2 '
    "half-days), day after day in the LVS's order. The codes are the school's "
    'own.\n'
    'Totals per code:\n'
    '- Testcode (TA): 3 half-days (1 whole day and 1 half-day)\n'
    '- Testcode 2 (TB): 1 half-day';

/// The answer for Marie, of the school year 2030-2031, without motivations.
const _pastAnswer =
    '$_pastHead\n'
    '2 of the 3 absences have a motivation, not shown, as a motivation can '
    'hold health information: pass with_motivation true only when the user '
    'asks why the pupil was absent.\n'
    '- 2030-09-16 (Monday) | whole day | Testcode (TA)\n'
    '- 2030-10-02 (Wednesday) | morning | Testcode 2 (TB)\n'
    '- 2030-10-02 (Wednesday) | afternoon | Testcode (TA)\n'
    '$_otherCurrent';

/// The answer for Marie, of the school year 2030-2031, with motivations.
const _pastAnswerWithMotivation =
    '$_pastHead\n'
    '2 of the 3 absences have a motivation, shown under each, as asked '
    '(with_motivation).\n'
    '- 2030-09-16 (Monday) | whole day | Testcode (TA)\n'
    '  Motivation: Testmotivatie: thuis gebleven.\n'
    '- 2030-10-02 (Wednesday) | morning | Testcode 2 (TB)\n'
    '- 2030-10-02 (Wednesday) | afternoon | Testcode (TA)\n'
    '  Motivation: Testmotivatie in platte tekst.\n'
    '$_otherCurrent';

/// What a refusal with HTTP 403 says.
const _noAccess =
    'The account has no access to the absences (Afwezigheden) of this '
    "pupil's file: Smartschool's pupil tracking system (LVS) refused that "
    'read (HTTP 403), as it does for an account without access to that part. '
    'Other parts of the file may still be readable: read_lvs_pupil lists '
    "them. If the account should have access, ask the school's Smartschool "
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

  Map<String, Object?> marie([Map<String, Object?> more = const {}]) => {
    ...fakeLvsPupilArguments(fakeLvsMarie),
    ...more,
  };

  Future<String> read(Map<String, Object?> arguments) =>
      h.ok('read_lvs_absences', arguments);

  Future<String> refused(Map<String, Object?> arguments) =>
      h.error('read_lvs_absences', arguments);

  group('the tool is listed', () {
    late Tool tool;
    late List<String> names;

    setUp(() async {
      final tools = await h.listTools();
      names = tools.keys.toList();
      tool = tools['read_lvs_absences']!;
    });

    test('last, after the support plan, read-only and idempotent', () {
      expect(names, [
        'search_lvs_pupils',
        'read_lvs_pupil',
        'read_lvs_notes',
        'read_lvs_results',
        'read_lvs_support_plan',
        'read_lvs_absences',
      ]);
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.destructiveHint, isNot(true));
    });

    test('its description: the privacy rules of every LVS tool, the '
        'current school year by default, and motivations only when the user '
        'asks why the pupil was absent', () {
      final description = tool.description!;
      expect(
        description,
        endsWith('$lvsPrivacyRules Reading changes nothing.'),
      );
      for (final part in [
        'Of one school year, the current one unless school_year is given',
        'the totals of the other school years the LVS gives, which it picks '
            'itself',
        'A motivation can hold health information: motivations are left out '
            'and only counted, unless with_motivation is true; set it only '
            'when the user asks why the pupil was absent.',
        'No absences is a sentence, not an error.',
      ]) {
        expect(description, contains(part));
      }
      // Students sign in too: the LVS tools speak of the user (an exe e2e
      // test checks every tool).
      expect(jsonEncode(tool).toLowerCase(), isNot(contains('teacher')));
    });

    test('takes pupil_id and class_id, and optionally a school year and '
        'with_motivation (a boolean)', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['pupil_id', 'class_id']);
      expect(schema.properties!.keys, [
        'pupil_id',
        'class_id',
        'school_year',
        'with_motivation',
      ]);
      expect(
        (schema.properties!['with_motivation']! as Map)['type'],
        'boolean',
      );
      expect(
        (schema.properties!['with_motivation']! as Map)['description'],
        contains(
          'Set it to true only when the user asks why the pupil was '
          'absent.',
        ),
      );
    });
  });

  group('absences', () {
    test('of the current school year: the totals per code, how many have a '
        'motivation (not what it says), each half-day with its day, day of '
        'the week, part of the day and code, then the other school years '
        'summed up; one read', () async {
      final text = await read(marie());

      expect(text, _currentAnswer);
      expect(lvs.calls, [_call()]);
      expect(lvs.reads, [FakeLvsRead.absences]);
      expect(text, isNot(contains('Testmotivatie')));
    });

    for (final year in ['2030-2031', ' 2030 - 2031 ']) {
      test('of another school year the LVS gives ("$year"): its absences, '
          'and the current one summed up; the same read, as the library '
          'sends no school year', () async {
        final text = await read(marie({'school_year': year}));

        expect(text, _pastAnswer);
        expect(lvs.calls, [_call()]);
      });
    }

    test('with_motivation: each motivation under its absence, as plain '
        'text', () async {
      final text = await read(
        marie({'school_year': '2030-2031', 'with_motivation': true}),
      );

      expect(text, _pastAnswerWithMotivation);
    });

    test('with_motivation false is the default', () async {
      expect(
        await read(
          marie({'school_year': '2030-2031', 'with_motivation': false}),
        ),
        _pastAnswer,
      );
    });

    test('a motivation of more lines keeps its lines', () async {
      lvs.absences[fakeLvsMarie.pupilId] = 'absences/absences_lines.json';

      final text = await read(
        marie({'school_year': '2030-2031', 'with_motivation': true}),
      );

      expect(
        text,
        endsWith(
          'The absence has a motivation, shown under it, as asked '
          '(with_motivation).\n'
          '- 2030-09-16 (Monday) | whole day | Testcode (TA)\n'
          '  Motivation:\n'
          '    Testmotivatie met\n'
          '    twee regels\n'
          '    Tweede testalinea.',
        ),
      );
    });

    test('days the LVS shows without a year are dated by their school '
        'year', () async {
      lvs.absences[fakeLvsMarie.pupilId] = 'absences/absences_no_year.json';

      final text = await read(marie({'school_year': '2030-2031'}));

      expect(
        text,
        endsWith(
          '- 2030-09-02 (Monday) | whole day | Testcode (TA)\n'
          '- 2030-10-23 (Wednesday) | morning | Testcode (TA)\n'
          '- 2030-12-03 (Tuesday) | afternoon | Testcode 2 (TB)\n'
          '- 2031-02-03 (Monday) | whole day | Testcode (TA)\n'
          '- 2031-08-29 (Friday) | morning | Testcode 2 (TB)',
        ),
      );
      expect(
        text,
        contains(': 7 half-days (2 whole days and 3 half-days), day after day'),
      );
      expect(text, isNot(contains('Other school years')));
    });

    test('a day the library cannot read, as the LVS shows it; a code without '
        'a description; a period that is not a school year, and a school '
        'year without absences, summed up', () async {
      lvs.absences[fakeLvsMarie.pupilId] = 'absences/absences_undated.json';

      final text = await read(marie());

      expect(
        text,
        'The absences of the pupil with pupil_id 900002 (class_id 900102) in '
        'the LVS in the school year 2031-2032: 3 half-days (1 whole day and 1 '
        "half-day), day after day in the LVS's order. The codes are the "
        "school's own.\n"
        'Totals per code:\n'
        '- Testcode (TA): 1 half-day\n'
        '- TB: 2 half-days (1 whole day)\n'
        'None of the 2 absences has a motivation.\n'
        '- "Testdag" (the day as the LVS shows it; the server cannot read it) '
        '| morning | Testcode (TA)\n'
        '- (no day given) | whole day | TB\n'
        'Other school years the LVS gives (it picks them itself), with their '
        'totals; pass one as school_year for its absences:\n'
        '- "Testperiode", a period that is not a school year (school_year '
        'cannot name it): 1 half-day; Testcode 2 (TB): 1 half-day\n'
        '- 2029-2030: no absences',
      );
    });

    test('a school year the LVS does not give: a sentence, and the school '
        'years it gives; the file is not read, as the pupil has '
        'absences', () async {
      final text = await read(marie({'school_year': '2029-2030'}));

      expect(
        text,
        'The LVS gives no absences for the pupil with pupil_id 900002 '
        '(class_id 900102) in the school year 2029-2030.\n'
        'Other school years the LVS gives (it picks them itself), with their '
        'totals; pass one as school_year for its absences:\n'
        '- 2030-2031: 4 half-days (1 whole day and 2 half-days); Testcode '
        '(TA): 3 half-days (1 whole day and 1 half-day); Testcode 2 (TB): 1 '
        'half-day\n'
        '- 2031-2032: 3 half-days (1 whole day and 1 half-day); Testcode 2 '
        '(TB): 1 half-day; Testcode (TA): 2 half-days (1 whole day)',
      );
      expect(lvs.reads, [FakeLvsRead.absences]);
    });
  });

  group('no absences: a sentence', () {
    test('a pupil whose file has a part of absences: none in any school '
        'year, after the file says the pupil is known', () async {
      lvs.absences[fakeLvsMarie.pupilId] = 'absences/none.json';

      final text = await read(marie({'with_motivation': true}));

      expect(
        text,
        'The LVS gives no absences for the pupil with pupil_id 900002 '
        '(class_id 900102), in any school year.',
      );
      expect(lvs.calls, [_call(), ..._fileCalls(fakeLvsMarie)]);
    });

    test('a pupil whose file has no part of absences: a sentence that says '
        'so', () async {
      final text = await read(fakeLvsPupilArguments(fakeLvsJan));

      expect(
        text,
        'The file of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS has no part of absences (Afwezigheden), and the LVS gives no '
        'absences for this pupil: the school may not keep absences in the '
        'LVS, or this account may not see them.',
      );
      expect(lvs.calls, [_call(fakeLvsJan), ..._fileCalls(fakeLvsJan)]);
    });

    for (final (what, arguments) in [
      ('a pupil the LVS does not know', fakeLvsPupilArguments(fakeLvsLars)),
      (
        'a pupil in another class than theirs',
        {'pupil_id': fakeLvsMarie.pupilId, 'class_id': fakeLvsJan.classId},
      ),
    ]) {
      test('$what: the LVS answers the absences with HTTP 500, and the file '
          'says the LVS does not know the pupil', () async {
        final text = await refused(arguments);

        expect(
          text,
          'The LVS knows no pupil with pupil_id ${arguments['pupil_id']} in '
          'the class with class_id ${arguments['class_id']} that this account '
          'may see. Take pupil_id and class_id from the same line of '
          'search_lvs_pupils.',
        );
        expect(lvs.reads, [
          FakeLvsRead.absences,
          // The library's own read of the file after the 500, without
          // today's status (yvanvds/dartschool#190), and no other (#164).
          FakeLvsRead.pupilFile,
        ]);
      });
    }

    test('a known pupil whose absences the LVS answers with HTTP 500: could '
        'not read, after the file says the pupil is known', () async {
      final text = await refused(fakeLvsPupilArguments(fakeLvsNoor));

      expect(
        text,
        startsWith('$_unreadable (HTTP 500). Try again in a moment.'),
      );
      expect(text, isNot(contains('Oeps')));
      expect(lvs.reads, [
        FakeLvsRead.absences,
        // The library's read of the file after the 500, without today's
        // status (yvanvds/dartschool#190), and no other (#164).
        FakeLvsRead.pupilFile,
      ]);
    });
  });

  group('arguments that cannot be read: an error that says what to pass, '
      'before logging in', () {
    for (final (arguments, error) in <(Map<String, Object?>, String)>[
      ({'school_year': '2030'}, 'school_year must be a school year'),
      ({'school_year': '2030-2032'}, 'school_year must be a school year'),
      // Not a boolean, or not a whole number: refused by the schema.
      ({'with_motivation': 'true'}, 'with_motivation'),
      ({'school_year': 2030}, 'school_year'),
      ({'class_id': null}, 'class_id'),
      ({'pupil_id': 0}, 'pupil_id'),
    ]) {
      test('$arguments', () async {
        final text = await refused(
          marie(arguments)..removeWhere((_, v) => v == null),
        );

        expect(text, contains(error));
        expect(h.server.requests, isEmpty);
      });
    }

    test('an empty school_year counts as none', () async {
      expect(await read(marie({'school_year': ' '})), _currentAnswer);
    });
  });

  group('a refusal or an answer the server cannot read: an error that says '
      'what to do, and quotes nothing of the answer', () {
    test('HTTP 403: no access to the absences, in a sentence; the file is '
        'not read', () async {
      lvs
        ..refusal = FakeLvsRefusal.forbidden
        ..refusedReads = {FakeLvsRead.absences};

      final text = await refused(marie());

      expect(text, _noAccess);
      expect(text, isNot(contains(fakeLvsNoAccessName)));
      expect(lvs.reads, [FakeLvsRead.absences]);
    });

    test('sent on to the start page: the refusal of the LVS', () async {
      lvs
        ..refusal = FakeLvsRefusal.startPage
        ..refusedReads = {FakeLvsRead.absences};

      expect(await refused(marie()), startsWith(_refused));
      expect(lvs.reads, [FakeLvsRead.absences]);
    });

    for (final (refusal, status) in [
      (FakeLvsRefusal.serverError, ' (HTTP 500)'),
      (FakeLvsRefusal.htmlPage, ''),
    ]) {
      test('${refusal.name}: could not read; only after HTTP 500 is the file '
          'read, by the library', () async {
        lvs
          ..refusal = refusal
          ..refusedReads = {FakeLvsRead.absences};

        final text = await refused(marie());

        expect(text, startsWith('$_unreadable$status. Try again in a moment.'));
        expect(text, isNot(contains('Oeps')));
        expect(lvs.reads, [
          FakeLvsRead.absences,
          // After a 500 only, the library reads the file, without today's
          // status (yvanvds/dartschool#190); the server reads nothing more
          // (#164).
          if (refusal == FakeLvsRefusal.serverError) FakeLvsRead.pupilFile,
        ]);
      });
    }
  });

  group('privacy', () {
    test('only the read of the absences, and the file when there are none '
        'or after HTTP 500: no other POST, no PUT', () async {
      await read(marie());
      await read(marie({'school_year': '2030-2031', 'with_motivation': true}));
      await read(fakeLvsPupilArguments(fakeLvsJan));
      await refused(fakeLvsPupilArguments(fakeLvsNoor));

      expect(lvs.reads, everyElement(isNotNull));
      expect(lvs.reads.toSet(), {
        FakeLvsRead.absences,
        FakeLvsRead.pupilFile,
        FakeLvsRead.todayStatus,
      });
      expect(
        {
          for (final r in lvs.requests)
            if (r.method != 'GET') '${r.method} ${r.path}',
        },
        {'POST /LVS/Pupilpresences', 'POST /LVS/Pupilxhr/getStatusInfo'},
      );
    });

    test('nothing is kept on disk: the cache folder holds the same files '
        'before and after, none with an absence', () async {
      // The first call logs in, which saves the session there.
      await read(marie());
      final before = h.cacheFiles();

      await read(marie({'school_year': '2030-2031', 'with_motivation': true}));
      await read(fakeLvsPupilArguments(fakeLvsJan));

      expect(h.cacheFiles(), before);
      for (final path in h.cacheFiles()) {
        final content = File(path).readAsStringSync().toLowerCase();
        for (final word in ['testcode', 'testmotivatie', 'pupilpresences']) {
          expect(content, isNot(contains(word)), reason: path);
        }
      }
    });

    test('the log of a call that succeeds holds nothing of the absences, '
        "their motivations, nor the pupil's id", () async {
      final (_, text, log) = await h.logged(
        'read_lvs_absences',
        marie({'school_year': '2030-2031', 'with_motivation': true}),
      );

      expect(text, contains('Testmotivatie in platte tekst.'));
      // The log is captured: the login shows in it.
      expect(log, contains('Smartschool: checking the session'));
      final logged = log.toLowerCase();
      for (final word in [
        'testcode',
        'testmotivatie',
        'thuis',
        'afternoon',
        '2030-09-16',
        '2030-2031',
        'peeters',
        'pupilpresences',
        '${fakeLvsMarie.pupilId}',
      ]) {
        expect(logged, isNot(contains(word)));
      }
    });

    test('a session Smartschool refuses during the absences: the log names '
        "the error's type, not the request, which holds the pupil's "
        'id', () async {
      await read(marie());
      h.server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      final (isError, text, log) = await h.logged('read_lvs_absences', marie());

      expect(isError, isNot(true), reason: text);
      expect(
        log,
        contains(
          'Smartschool did not accept the session '
          '(SmartschoolSessionExpiredError); trying once more',
        ),
      );
      expect(log, isNot(contains('${fakeLvsMarie.pupilId}')));
      expect(log, isNot(contains('Pupilpresences')));
    });

    test('an error whose message holds a name: the log has its type and '
        'HTTP status only, the result neither', () async {
      lvs.failure = const SmartschoolLvsError(
        'Testfout over Peeters Marie.',
        statusCode: 500,
      );

      final (isError, text, log) = await h.logged(
        'read_lvs_absences',
        marie({'with_motivation': true}),
      );

      expect(isError, isTrue);
      expect(text, startsWith('$_unreadable (HTTP 500).'));
      expect(log, contains('lvs: SmartschoolLvsError (HTTP 500)\n'));
      for (final shown in [text, log]) {
        expect(shown, isNot(contains('Peeters')));
        expect(shown, isNot(contains('Testfout')));
      }
    });

    test('a refusal with HTTP 403: the log has its type and status '
        'only', () async {
      lvs
        ..refusal = FakeLvsRefusal.forbidden
        ..refusedReads = {FakeLvsRead.absences};

      final (_, _, log) = await h.logged('read_lvs_absences', marie());

      expect(log, contains('lvs: SmartschoolLvsAccessDeniedError (HTTP 403)'));
      expect(log, isNot(contains(fakeLvsNoAccessName)));
      expect(log, isNot(contains('${fakeLvsMarie.pupilId}')));
    });
  });

  group('the parts, worded', () {
    LvsAbsence absence({
      DateTime? date,
      String formattedDate = '',
      DayPart? dayPart,
      String code = 'TA',
      String codeDescription = 'Testcode',
      String motivation = '',
    }) => LvsAbsence(
      date: date,
      formattedDate: formattedDate,
      dayPart: dayPart,
      code: code,
      codeDescription: codeDescription,
      motivation: motivation,
    );

    final read = LvsSchoolYear.starting(2030);

    String format(
      List<LvsAbsencePeriod> periods, {
      bool withMotivation = false,
      bool fileHasAbsences = true,
    }) => formatLvsAbsences(
      (
        absences: LvsAbsences(periods: periods),
        fileHasAbsences: fileHasAbsences,
      ),
      pupilId: 900001,
      classId: 900101,
      schoolYear: read,
      withMotivation: withMotivation,
    );

    test('an absence: its day and day of the week, part of the day and '
        'code; a day shown as the LVS shows it when it cannot be read', () {
      expect(
        formatLvsAbsence(
          absence(date: DateTime.utc(2030, 9, 16), dayPart: DayPart.morning),
        ),
        '- 2030-09-16 (Monday) | morning | Testcode (TA)',
      );
      expect(
        formatLvsAbsence(
          absence(formattedDate: ' Test   dag ', codeDescription: ''),
        ),
        '- "Test dag" (the day as the LVS shows it; the server cannot read '
        'it) | whole day | TA',
      );
      expect(
        formatLvsAbsence(absence(code: '', codeDescription: '')),
        '- (no day given) | whole day | (no code)',
      );
      expect(
        formatLvsAbsence(absence(code: ' ', codeDescription: 'Testcode')),
        '- (no day given) | whole day | Testcode',
      );
    });

    test('a motivation only with withMotivation: one line, or its lines '
        'under its label, without empty ones', () {
      final one = absence(motivation: 'Testmotivatie.');
      final lines = absence(motivation: 'Testregel een\n \n  Testregel  twee ');
      expect(formatLvsAbsence(one), isNot(contains('Testmotivatie')));
      expect(
        formatLvsAbsence(one, withMotivation: true),
        '- (no day given) | whole day | Testcode (TA)\n'
        '  Motivation: Testmotivatie.',
      );
      expect(
        formatLvsAbsence(lines, withMotivation: true),
        '- (no day given) | whole day | Testcode (TA)\n'
        '  Motivation:\n'
        '    Testregel een\n'
        '    Testregel twee',
      );
      expect(
        formatLvsAbsence(absence(motivation: ' \n '), withMotivation: true),
        '- (no day given) | whole day | Testcode (TA)',
      );
    });

    test('the periods of a school year, however the LVS writes its label, '
        'are read together; another label is summed up', () {
      final absences = LvsAbsences(
        periods: [
          LvsAbsencePeriod(
            label: '2030-2031',
            absences: [absence(date: DateTime.utc(2030, 9, 16))],
          ),
          LvsAbsencePeriod(label: 'Testperiode', absences: [absence()]),
          LvsAbsencePeriod(
            label: '2030 - 2031',
            absences: [
              absence(
                date: DateTime.utc(2031, 1, 6),
                dayPart: DayPart.afternoon,
              ),
            ],
          ),
        ],
      );

      final (:chosen, :others) = selectLvsAbsencePeriods(absences, read);

      expect([for (final p in chosen) p.label], ['2030-2031', '2030 - 2031']);
      expect([for (final p in others) p.label], ['Testperiode']);
      expect(
        format(absences.periods),
        'The absences of the pupil with pupil_id 900001 (class_id 900101) in '
        'the LVS in the school year 2030-2031: 3 half-days (1 whole day and 1 '
        "half-day), day after day in the LVS's order. The codes are the "
        "school's own.\n"
        'Totals per code:\n'
        '- Testcode (TA): 3 half-days (1 whole day and 1 half-day)\n'
        'None of the 2 absences has a motivation.\n'
        '- 2030-09-16 (Monday) | whole day | Testcode (TA)\n'
        '- 2031-01-06 (Monday) | afternoon | Testcode (TA)\n'
        'Other school years the LVS gives (it picks them itself), with their '
        'totals; pass one as school_year for its absences:\n'
        '- "Testperiode", a period that is not a school year (school_year '
        'cannot name it): 2 half-days (1 whole day); Testcode (TA): 2 '
        'half-days (1 whole day)',
      );
    });

    test('the half-days in words: whole days count two', () {
      String totals(List<LvsAbsence> absences) => format([
        LvsAbsencePeriod(label: '2030-2031', absences: absences),
      ]).split('\n').first;

      expect(
        totals([absence(dayPart: DayPart.morning)]),
        endsWith(
          ': 1 half-day, day after day in the LVS\'s order. The codes '
          "are the school's own.",
        ),
      );
      expect(
        totals([absence(), absence()]),
        contains(': 4 half-days (2 whole days), day after day'),
      );
      expect(
        totals([
          absence(),
          absence(dayPart: DayPart.morning),
          absence(dayPart: DayPart.afternoon),
        ]),
        contains(': 4 half-days (1 whole day and 2 half-days), day after day'),
      );
    });

    test('a motivation counted, in the singular and the plural', () {
      String counted(List<LvsAbsence> absences, {bool shown = false}) => format(
        [LvsAbsencePeriod(label: '2030-2031', absences: absences)],
        withMotivation: shown,
      ).split('\n')[3];
      final withOne = absence(motivation: 'Testmotivatie.');

      expect(
        counted([withOne, absence()]),
        startsWith('1 of the 2 absences has a motivation, not shown,'),
      );
      expect(
        counted([withOne, withOne, absence()]),
        startsWith('2 of the 3 absences have a motivation, not shown,'),
      );
      expect(
        counted([withOne, withOne]),
        startsWith('All 2 absences have a motivation, not shown,'),
      );
      expect(
        counted([withOne, withOne, absence()], shown: true),
        '2 of the 3 absences have a motivation, shown under each, as asked '
        '(with_motivation).',
      );
      expect(
        counted([withOne], shown: true),
        'The absence has a motivation, shown under it, as asked '
        '(with_motivation).',
      );
      expect(counted([absence()]), 'The absence has no motivation.');
      expect(
        counted([absence(), absence()], shown: true),
        'None of the 2 absences has a motivation.',
      );
    });

    test('no absences at all: a sentence, which says when the file has no '
        'part of them', () {
      expect(
        format(const []),
        'The LVS gives no absences for the pupil with pupil_id 900001 '
        '(class_id 900101), in any school year.',
      );
      expect(
        format(const [
          LvsAbsencePeriod(label: '2030-2031', absences: []),
        ], fileHasAbsences: false),
        startsWith(
          'The file of the pupil with pupil_id 900001 (class_id 900101) in '
          'the LVS has no part of absences (Afwezigheden)',
        ),
      );
    });
  });
}
