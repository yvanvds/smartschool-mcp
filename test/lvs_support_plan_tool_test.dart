/// `read_lvs_support_plan` (#156), called over MCP on the real server,
/// session and library (`LvsService.getSupportPlanPeriods`, `getSupportPlan`
/// and `getProfileSketch`), against a fake Smartschool whose pupil tracking
/// system (LVS) answers with the hand-written fixtures of
/// `test/fixtures/lvs/supportplan/` (the fakes of `FAKES.md` only, checked
/// by `test/lvs_fixtures_guard_test.dart`): the plan of the current period
/// and of a chosen one, the items the user wrote first (#163), a course,
/// by its name and by its id, the three cases without a plan (a school
/// without support plans, a pupil without a plan, no period), "no access to
/// the support plans", and the privacy rules every LVS tool follows (#153):
/// only reads, nothing on disk, nothing of an answer or an error's message
/// in the log.
///
/// The account is Céline Dupré ([fakeLvsCelineUserId]), a teacher of the
/// fixtures who wrote some of the items, unless a test logs in as another.
///
/// No real pupil's plan was captured (yvanvds/dartschool#168): the fixtures
/// are in the shapes of the LVS's JavaScript, the library's own and some
/// written here (an item of a kind the library does not know, an empty one).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:smartschool_mcp/src/lvs/lvs_support_plan.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/lvs_tool_harness.dart';

/// The requests of the three reads of [pupil]'s support plan, of the period
/// [period] (`0` for the current one).
List<String> _calls({FakeLvsPupil pupil = fakeLvsMarie, int period = 0}) => [
  'POST /?module=LVS&file=jqDispatcher_settings&function=getLVSspecificTitles '
      'groupID=${pupil.classId} pupilID=${pupil.pupilId} type=hp_ihp '
      'activeID=0 color=#418b09 archiveID=0',
  'POST /?module=LVS&file=jqDispatcher_hp&function=getIHP '
      'groupID=${pupil.classId} pupilID=${pupil.pupilId} periodID=$period '
      'exportID=0',
  'POST /?module=LVS&file=jqDispatcher_hp&function=getProfielSchets '
      'pupilID=${pupil.pupilId} classID=${pupil.classId} periodID=$period '
      'exportID=0',
];

/// The request of [pupil]'s file: the file only, without today's
/// attendance (`getStatusInfo`), which the tool does not show.
String _fileCall(FakeLvsPupil pupil) =>
    'GET /LVS/Spotlight/${pupil.pupilId}?classID=${pupil.classId}';

/// The line on what the tool does not read.
const _notRead =
    "Not read: the plan's evaluation and its report, and the earlier versions "
    'of its items; the server cannot read them yet.';

/// The periods of the support plans, to ask for.
const _periods =
    'Periods of the support plans, to pass as period (its period_id or name): '
    'Testperiode (period_id 900501, in Testschooljaar), Testperiode 2 '
    '(period_id 900502, in Testschooljaar).';

/// The items of the current period of Marie's plan, in the LVS's order: for
/// Testvak; for Testvak and, by its course id only, Testvak 2 (by Céline,
/// [_groupPlanItemByUser]); and two tied to no course.
const _needsItem =
    '- Support needs and approach | by Piet Peeters | 14/10/2030 | for '
    'Testvak\n'
    '  Support needs (ondersteuningsnoden):\n'
    '    - Testondersteuningsnood\n'
    '    - Tweede testnood & meer\n'
    '  Main goals (hoofddoelen): Testhoofddoel\n'
    '  Work goals (werkdoelen):\n'
    '    - Testwerkdoel\n'
    '    - Tweede testwerkdoel\n'
    '  Approach (aanpak): Testaanpak\n'
    '  Comment on the approach: Testcommentaar bij de aanpak.';

const _groupPlanItemRest =
    '21/10/2030 | for Testvak, Testvak 2 | theme Testthema\n'
    '  Start situation (beginsituatie): Testbeginsituatie van de leerling.\n'
    '  - Goal: Testdoel | domain Testdomein > Testsubdomein\n'
    '    Objectives (doelstellingen): Testdoelstelling\n'
    '    Approach (aanpak): Testaanpak bij het doel\n'
    '    Planning: Testvak\n'
    '  - Goal: Testdoel uit het leerplan | no longer in its curriculum';

const _groupPlanItemByUser =
    "- Goals taken over from the class's group plan (groepswerkplan) | by "
    'the user, Céline Dupré | $_groupPlanItemRest';

const _groupPlanItem =
    "- Goals taken over from the class's group plan (groepswerkplan) | by "
    'Céline Dupré | $_groupPlanItemRest';

const _ownGoalsItem =
    '- Goals chosen for the pupil | by Piet Peeters | 28/10/2030 | the '
    "school's own goals\n"
    '  - Goal: Testdoel van de school | domain Testdomein';

const _documentItem =
    '- An uploaded plan | by Piet Peeters | 02/11/2030 | '
    'Testhandelingsplan.pdf (PDF), by name only: not opened';

const _sketch =
    'Profile sketch (profielschets; last change: Testversie van 01/10/2030):\n'
    '  Testprofielschets van de leerling: sterk in testen.';

/// The line on whose plan, of the current period, up to how many items.
const _currentPeriodHead =
    'The support plan (handelingsplan) of the pupil with pupil_id 900002 '
    '(class_id 900102) in the LVS, the current period Testperiode (period_id '
    '900501, in Testschooljaar): 4 items';

/// The answer for the current period of Marie's plan, for Céline: the item
/// she wrote first.
const _currentAnswer =
    '$_currentPeriodHead: first the item the user wrote, marked "by the '
    'user", then the others, each in the LVS\'s order.\n'
    '$_notRead\n'
    '$_groupPlanItemByUser\n'
    '$_needsItem\n'
    '$_ownGoalsItem\n'
    '$_documentItem\n'
    '$_sketch\n'
    '$_periods';

/// The items of the second period of Marie's plan, in the LVS's order: for
/// two courses, for Testvak and goals planned in Testvak 2 (both by
/// Céline), a kind the library does not know, and one with nothing filled
/// in.
const _twoCoursesItem =
    '- Support needs and approach | by Piet Peeters | 03/02/2031 | for '
    'Testvak, Testvak 2\n'
    '  Support needs (ondersteuningsnoden):\n'
    '    - Testnood op\n'
    '      twee regels\n'
    '  Work goals (werkdoelen): Testwerkdoel voor twee vakken\n'
    '  Approach (aanpak):\n'
    '    - Testaanpak een\n'
    '      Testaanpak twee\n'
    '  Comment on the approach:\n'
    '    Testcommentaar met\n'
    '    twee regels';

const _vakItem =
    '- Support needs and approach | by the user, Céline Dupré | 10/02/2031 | '
    'for Testvak\n'
    '  Support needs (ondersteuningsnoden): Testnood voor het vak\n'
    '  Approach (aanpak): Testaanpak voor het vak';

const _vak2GoalsItem =
    '- Goals chosen for the pupil | by the user, Céline Dupré | 17/02/2031 | '
    'goals of special primary education (BuBaO)\n'
    '  - Goal: Testdoel voor het tweede vak\n'
    '    Objectives (doelstellingen):\n'
    '      - Testdoelstelling een.\n'
    '        Testdoelstelling twee.\n'
    '    Planning: Testvak 2';

const _unknownItem =
    '- An item of a type the server does not know ("testsoort") | by Piet '
    'Peeters | its content is not read';

const _emptyItem =
    '- Support needs and approach | tied to no course\n'
    '  (nothing filled in)';

const _sketchLines =
    'Profile sketch (profielschets; last change: Testversie van 01/10/2030):\n'
    '  Testprofielschets\n'
    '  Testtekst met\n'
    '  twee regels\n'
    '  Tweede testalinea.\n'
    '  Sterk in testen\n'
    '  Test graag';

/// The line on whose plan, of the second period, closed, for Céline: the
/// items she wrote first.
const _secondPeriodHead =
    'The support plan (handelingsplan) of the pupil with pupil_id 900002 '
    '(class_id 900102) in the LVS, the period Testperiode 2 (period_id 900502, '
    'in Testschooljaar), closed (read only in Smartschool): 5 items: first the '
    '2 items the user wrote, marked "by the user", then the others, each in '
    "the LVS's order.";

/// The answer for the second period of Marie's plan, for Céline.
const _secondAnswer =
    '$_secondPeriodHead\n'
    '$_notRead\n'
    '$_vakItem\n'
    '$_vak2GoalsItem\n'
    '$_twoCoursesItem\n'
    '$_unknownItem\n'
    '$_emptyItem\n'
    '$_sketchLines\n'
    '$_periods';

/// The issue's "a school without support plans": what a file without a part
/// of them gets.
const _noSupportPlans =
    'The file of the pupil with pupil_id 900003 (class_id 900103) in the LVS '
    'has no part of support plans (handelingsplannen): the school does not '
    "use the LVS's support plans, or this account may not see them. A school "
    'without them keeps educational needs (onderwijsbehoeften) and measures in '
    'its note categories instead: read_lvs_pupil lists the categories of the '
    'file, and read_lvs_notes reads them.';

/// What a refusal with HTTP 403 says.
const _noAccess =
    'The account has no access to the support plans (handelingsplannen) of '
    "this pupil's file: Smartschool's pupil tracking system (LVS) refused that "
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
    h = await LvsToolHarness.start(userId: fakeLvsCelineUserId);
    lvs = h.lvs;
  });

  Map<String, Object?> marie([Map<String, Object?> more = const {}]) => {
    ...fakeLvsPupilArguments(fakeLvsMarie),
    ...more,
  };

  Map<String, Object?> jan([Map<String, Object?> more = const {}]) => {
    ...fakeLvsPupilArguments(fakeLvsJan),
    ...more,
  };

  Future<String> read(Map<String, Object?> arguments) =>
      h.ok('read_lvs_support_plan', arguments);

  Future<String> refused(Map<String, Object?> arguments) =>
      h.error('read_lvs_support_plan', arguments);

  /// Jan's support plans as the LVS answered a class without a structure of
  /// them: no period menu, and a period error.
  void janWithoutPeriods() {
    lvs.supportPlanPeriods.remove(fakeLvsJan.pupilId);
    lvs.supportPlans.removeWhere((key, _) => key.$1 == fakeLvsJan.pupilId);
  }

  group('the tool is listed', () {
    late Tool tool;
    late List<String> names;

    setUp(() async {
      final tools = await h.listTools();
      names = tools.keys.toList();
      tool = tools['read_lvs_support_plan']!;
    });

    test('after the results, read-only and idempotent', () {
      expect(names.take(5), [
        'search_lvs_pupils',
        'read_lvs_pupil',
        'read_lvs_notes',
        'read_lvs_results',
        'read_lvs_support_plan',
      ]);
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.destructiveHint, isNot(true));
    });

    test('its description: the privacy rules of every LVS tool, what it does '
        'not read (the evaluation), the items the user wrote first, the '
        "user's course as course, and the note categories of schools without "
        'support plans', () {
      final description = tool.description!;
      expect(
        description,
        endsWith('$lvsPrivacyRules Reading changes nothing.'),
      );
      for (final part in [
        "Not read yet: the plan's evaluation and its report, and the earlier "
            'versions of its items.',
        'The items the user wrote come first, marked "by the user".',
        'to see what concerns the user\'s lessons, pass the user\'s course as '
            'course.',
        'a school that keeps educational needs in note categories instead is '
            'read with read_lvs_notes',
        'an uploaded plan by its file name only (not opened)',
      ]) {
        expect(description, contains(part));
      }
      // The sentence of #156 is gone: the user's own items come first.
      expect(description, isNot(contains('cannot tell')));
      // Students sign in too: the LVS tools speak of the user, and of an
      // item's author (an exe e2e test checks every tool).
      expect(jsonEncode(tool).toLowerCase(), isNot(contains('teacher')));
    });

    test('takes pupil_id and class_id, and optionally a period (id or name) '
        'and a course (a name)', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['pupil_id', 'class_id']);
      expect(schema.properties!.keys, [
        'pupil_id',
        'class_id',
        'period',
        'course',
      ]);
      expect((schema.properties!['course']! as Map)['type'], 'string');
    });
  });

  group('a plan', () {
    test('of the current period: the item the user wrote first, marked, then '
        "the others in the LVS's order, each with what it holds, then the "
        'profile sketch and the periods; three reads, of period 0 and the '
        'live plan (exportID 0)', () async {
      final text = await read(marie());

      expect(text, _currentAnswer);
      expect(lvs.calls, _calls());
      expect(lvs.reads, [
        FakeLvsRead.supportPlanPeriods,
        FakeLvsRead.supportPlan,
        FakeLvsRead.profileSketch,
      ]);
    });

    test('for another author, Piet Peeters: his three items first, the '
        'uploaded plan too (its author by id), then the one by Céline; the '
        'reads are the same', () async {
      final piet = await LvsToolHarness.start(userId: fakeLvsPietUserId);

      final text = await piet.ok('read_lvs_support_plan', marie());

      expect(
        text,
        '$_currentPeriodHead: first the 3 items the user wrote, marked "by '
        'the user", then the others, each in the LVS\'s order.\n'
        '$_notRead\n'
        '${_needsItem.replaceFirst('by Piet', 'by the user, Piet')}\n'
        '${_ownGoalsItem.replaceFirst('by Piet', 'by the user, Piet')}\n'
        '${_documentItem.replaceFirst('by Piet', 'by the user, Piet')}\n'
        '$_groupPlanItem\n'
        '$_sketch\n'
        '$_periods',
      );
      expect(piet.lvs.calls, _calls());
    });

    test('for an account that wrote none of the items: all in the LVS\'s '
        'order, said so, none marked', () async {
      final other = await LvsToolHarness.start();

      final text = await other.ok('read_lvs_support_plan', marie());

      expect(
        text,
        "$_currentPeriodHead, in the LVS's order; the user wrote none of "
        'them.\n'
        '$_notRead\n'
        '$_needsItem\n'
        '$_groupPlanItem\n'
        '$_ownGoalsItem\n'
        '$_documentItem\n'
        '$_sketch\n'
        '$_periods',
      );
      expect(text, isNot(contains('by the user')));
    });

    for (final period in <Object>[
      'testperiode 2',
      ' Testperiode  2 ',
      900502,
      '900502',
      'period_id 900502',
    ]) {
      test('of a period chosen by its name, ignoring case, or by its '
          'period_id ("$period"): items of more lines, for several courses, '
          'of a kind the server does not know, and with nothing filled in, in '
          'a closed period', () async {
        final text = await read(marie({'period': period}));

        expect(text, _secondAnswer);
        expect(lvs.calls, _calls(period: 900502));
      });
    }

    test('a period by part of its name, when no name is that', () async {
      final text = await read(marie({'period': 'periode 2'}));

      expect(text, startsWith(_secondPeriodHead));
    });

    test('a name several periods hold: an error that lists them with their '
        'ids, after the menu only', () async {
      final text = await refused(marie({'period': 'periode'}));

      expect(
        text,
        'Several periods of the support plans match "periode": Testperiode '
        '(period_id 900501, in Testschooljaar), Testperiode 2 (period_id '
        '900502, in Testschooljaar). Pass the one you mean as period, by its '
        'period_id.',
      );
      expect(lvs.reads, [FakeLvsRead.supportPlanPeriods]);
    });

    for (final period in <Object>['Testperiode 3', 900503]) {
      test('a period the menu does not have ($period): an error that lists '
          'them, after the menu only', () async {
        final text = await refused(marie({'period': period}));

        expect(
          text,
          'The support plans have no period "$period". Their periods are: '
          'Testperiode (period_id 900501, in Testschooljaar), Testperiode 2 '
          '(period_id 900502, in Testschooljaar). Pass one of them as period, '
          'by its period_id or its name, or leave period out for the current '
          'period.',
        );
        expect(lvs.reads, [FakeLvsRead.supportPlanPeriods]);
      });
    }
  });

  group('a course', () {
    test('by its name, ignoring case: the items for it and those tied to no '
        'course, the one the user wrote first, with the items for other '
        'courses counted', () async {
      final text = await read(marie({'period': 900502, 'course': 'testvak'}));

      expect(
        text,
        '$_secondPeriodHead\n'
        'Only the items for the course Testvak, and those tied to no course, '
        'which may concern every course: 4 of the 5. Not shown: 1 item for '
        'other courses only; leave course out to see it.\n'
        '$_notRead\n'
        '$_vakItem\n'
        '$_twoCoursesItem\n'
        '$_unknownItem\n'
        '$_emptyItem\n'
        '$_sketchLines\n'
        '$_periods',
      );
      // The course is not sent to the LVS: the items are kept here, as the
      // LVS's web client filters them.
      expect(lvs.calls, _calls(period: 900502));
    });

    test('by its id: an item planned in the course by its course id only, '
        'which names no course of that name, is kept; the plan names the '
        'course', () async {
      final text = await read(marie({'course': 'Testvak 2'}));

      expect(
        text,
        '$_currentPeriodHead: first the item the user wrote, marked "by the '
        'user", then the others, each in the LVS\'s order.\n'
        'Only the items for the course Testvak 2, and those tied to no '
        'course, which may concern every course: 3 of the 4. Not shown: 1 '
        'item for other courses only; leave course out to see it.\n'
        '$_notRead\n'
        '$_groupPlanItemByUser\n'
        '$_ownGoalsItem\n'
        '$_documentItem\n'
        '$_sketch\n'
        '$_periods',
      );
      // Its goal is planned in Testvak only: by name, it would not be kept.
      expect(_groupPlanItemByUser, contains('Planning: Testvak\n'));
    });

    test('by part of its name, when no course is named that: also the items '
        'whose goals are planned in it', () async {
      final text = await read(marie({'period': 900502, 'course': 'VAK 2'}));

      expect(
        text,
        '$_secondPeriodHead\n'
        'Only the items for the course Testvak 2, and those tied to no '
        'course, which may concern every course: 4 of the 5. Not shown: 1 '
        'item for other courses only; leave course out to see it.\n'
        '$_notRead\n'
        '$_vak2GoalsItem\n'
        '$_twoCoursesItem\n'
        '$_unknownItem\n'
        '$_emptyItem\n'
        '$_sketchLines\n'
        '$_periods',
      );
    });

    test('a part of a name several courses hold: the items for each of '
        'them', () async {
      final text = await read(marie({'period': 900502, 'course': 'vak'}));

      expect(
        text,
        contains(
          '\nOnly the items for the courses Testvak, Testvak 2, and those '
          'tied to no course, which may concern every course: 5 of the 5.\n',
        ),
      );
    });

    test('a course no item names: only the items tied to no course, with the '
        'courses the items name', () async {
      final text = await read(marie({'course': 'Testvak 3'}));

      expect(
        text,
        '$_currentPeriodHead: first the item the user wrote, marked "by the '
        'user", then the others, each in the LVS\'s order.\n'
        'No item of this plan names a course "Testvak 3"; its items name: '
        'Testvak, Testvak 2. Shown: only the 2 items tied to no course, which '
        'may concern every course; leave course out to see all 4.\n'
        '$_notRead\n'
        '$_ownGoalsItem\n'
        '$_documentItem\n'
        '$_sketch\n'
        '$_periods',
      );
    });
  });

  group('no plan: a sentence for each case', () {
    test('a pupil without a plan in the period: a sentence, after the file '
        'says the pupil is known; the sketch and the periods', () async {
      final text = await read(jan());

      expect(
        text,
        'The pupil with pupil_id 900001 (class_id 900101) has no support plan '
        '(handelingsplan) in the LVS in the current period Testperiode '
        '(period_id 900501, in Testschooljaar).\n'
        'Profile sketch (profielschets): none in this period.\n'
        '$_periods',
      );
      expect(lvs.calls, [..._calls(pupil: fakeLvsJan), _fileCall(fakeLvsJan)]);
    });

    test('a pupil without a plan, but with a profile sketch: the sketch, '
        'and the file is not read', () async {
      lvs.supportPlans[(fakeLvsJan.pupilId, 0)] = (
        plan: 'supportplan/plan_none.json',
        sketch: 'supportplan/profile.json',
      );

      final text = await read(jan());

      expect(
        text,
        'The pupil with pupil_id 900001 (class_id 900101) has no support plan '
        '(handelingsplan) in the LVS in the current period Testperiode '
        '(period_id 900501, in Testschooljaar).\n'
        '$_sketch\n'
        '$_periods',
      );
      expect(lvs.calls, _calls(pupil: fakeLvsJan));
    });

    test('no period of support plans (a class without a structure of them): '
        "a sentence with the LVS's message, after the file says the pupil is "
        'known and has a part of support plans', () async {
      janWithoutPeriods();

      final text = await read(jan());

      expect(
        text,
        'The LVS gives no period of support plans for the pupil with pupil_id '
        '900001 (class_id 900101): their class may have no structure of '
        'support plans (the LVS says: "Testfout: maak eerst een structuur aan '
        'voor deze klas"). There is no plan to read.\n'
        'The LVS lists no periods of the support plans to choose from.',
      );
      expect(lvs.calls, [..._calls(pupil: fakeLvsJan), _fileCall(fakeLvsJan)]);
    });

    test('no period for a period chosen from the menu: the sentence names '
        'it', () async {
      lvs.supportPlans.remove((fakeLvsMarie.pupilId, 900502));

      final text = await read(marie({'period': 'Testperiode 2'}));

      expect(
        text,
        startsWith(
          'The LVS gives no period of support plans for the pupil with '
          'pupil_id 900002 (class_id 900102) in the period Testperiode 2 '
          '(period_id 900502, in Testschooljaar): their class may have no '
          'structure of support plans (the LVS says: "Testfout: ',
        ),
      );
    });

    for (final more in <Map<String, Object?>>[
      {},
      {'period': 'Testperiode'},
      {'course': 'Testvak'},
    ]) {
      test('a school without support plans (no part of them in the file) '
          '$more: a sentence that points to the note categories, '
          'read_lvs_notes', () async {
        final text = await read({
          ...fakeLvsPupilArguments(fakeLvsNoor),
          ...more,
        });

        expect(text, _noSupportPlans);
        expect(lvs.reads.last, FakeLvsRead.pupilFile);
        if (more.containsKey('period')) {
          // No period to pick from: the plan is not read.
          expect(lvs.reads, [
            FakeLvsRead.supportPlanPeriods,
            FakeLvsRead.pupilFile,
          ]);
        }
      });
    }

    test('a known pupil with a part of support plans but no periods, with a '
        'period: there are none to pick from', () async {
      janWithoutPeriods();

      final text = await refused(jan({'period': 'Testperiode'}));

      expect(
        text,
        "The LVS lists no periods of this pupil's support plans to choose "
        'from. Leave period out for the current period.',
      );
      expect(lvs.reads, [
        FakeLvsRead.supportPlanPeriods,
        FakeLvsRead.pupilFile,
      ]);
    });

    for (final (what, arguments) in [
      ('a pupil the LVS does not know', fakeLvsPupilArguments(fakeLvsLars)),
      (
        'a pupil in another class than theirs',
        {'pupil_id': fakeLvsMarie.pupilId, 'class_id': fakeLvsJan.classId},
      ),
      (
        'a pupil the LVS does not know, with a period',
        {...fakeLvsPupilArguments(fakeLvsLars), 'period': 'Testperiode'},
      ),
    ]) {
      test('$what: the support plans answer nothing, and the file says the '
          'LVS does not know the pupil', () async {
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
  });

  group('arguments that cannot be read: an error that says what to pass, '
      'before logging in', () {
    for (final (arguments, error) in <(Map<String, Object?>, String)>[
      // Not a whole number, or not a text: refused by the schema.
      ({'period': 2.5}, 'period'),
      ({'period': true}, 'period'),
      ({'course': 900301}, 'course'),
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

    test('an empty period or course counts as none', () async {
      expect(
        await read(marie({'period': ' ', 'course': '""'})),
        _currentAnswer,
      );
    });
  });

  group('a refusal or an answer the server cannot read: an error that says '
      'what to do, and quotes nothing of the answer', () {
    for (final reads in [
      {FakeLvsRead.supportPlanPeriods},
      {FakeLvsRead.supportPlan},
      {FakeLvsRead.profileSketch},
    ]) {
      test('HTTP 403 (${reads.single.name}): no access to the support plans, '
          'in a sentence', () async {
        lvs
          ..refusal = FakeLvsRefusal.forbidden
          ..refusedReads = reads;

        final text = await refused(marie());

        expect(text, _noAccess);
        expect(text, isNot(contains(fakeLvsNoAccessName)));
      });
    }

    test('sent on to the start page: the refusal of the LVS', () async {
      lvs
        ..refusal = FakeLvsRefusal.startPage
        ..refusedReads = {FakeLvsRead.supportPlan};

      expect(await refused(marie()), startsWith(_refused));
    });

    for (final (refusal, status) in [
      (FakeLvsRefusal.serverError, ' (HTTP 500)'),
      (FakeLvsRefusal.htmlPage, ''),
    ]) {
      test('${refusal.name}: could not read', () async {
        lvs
          ..refusal = refusal
          ..refusedReads = {FakeLvsRead.profileSketch};

        final text = await refused(marie());

        expect(text, startsWith('$_unreadable$status. Try again in a moment.'));
        expect(text, isNot(contains('Oeps')));
      });
    }
  });

  group('privacy', () {
    test('only the three reads of the support plans, and the file when there '
        'is no plan: no other POST, no PUT', () async {
      await read(marie());
      await read(marie({'period': 900502, 'course': 'Testvak'}));
      await read(jan());
      await read(fakeLvsPupilArguments(fakeLvsNoor));

      expect(lvs.reads, everyElement(isNotNull));
      expect(lvs.reads.toSet(), {
        FakeLvsRead.supportPlanPeriods,
        FakeLvsRead.supportPlan,
        FakeLvsRead.profileSketch,
        FakeLvsRead.pupilFile,
      });
      String post(FakeLvsRequest r) =>
          [r.method, r.path, ?r.query['file'], ?r.query['function']].join(' ');
      expect(
        {
          for (final r in lvs.requests)
            if (r.method != 'GET') post(r),
        },
        {
          'POST / jqDispatcher_settings getLVSspecificTitles',
          'POST / jqDispatcher_hp getIHP',
          'POST / jqDispatcher_hp getProfielSchets',
        },
      );
      // Only the live plan, never an archived export.
      expect([
        for (final r in lvs.requests)
          if (r.form.containsKey('exportID')) r.form['exportID'],
      ], everyElement('0'));
    });

    test('nothing is kept on disk: the cache folder holds the same files '
        'before and after, none with a plan', () async {
      // The first call logs in, which saves the session there.
      await read(marie());
      final before = h.cacheFiles();

      await read(marie({'period': 900502}));
      await read(jan());

      expect(h.cacheFiles(), before);
      for (final path in h.cacheFiles()) {
        final content = File(path).readAsStringSync().toLowerCase();
        for (final word in ['testnood', 'testondersteuningsnood', 'testdoel']) {
          expect(content, isNot(contains(word)), reason: path);
        }
      }
    });

    test('the log of a call that succeeds holds nothing of the plan, nor the '
        "pupil's id", () async {
      final (_, text, log) = await h.logged(
        'read_lvs_support_plan',
        marie({'course': 'Testvak'}),
      );

      expect(text, contains('Testondersteuningsnood'));
      // The log is captured: the login shows in it.
      expect(log, contains('Smartschool: checking the session'));
      final logged = log.toLowerCase();
      for (final word in [
        'testondersteuningsnood',
        'testnood',
        'testdoel',
        'testaanpak',
        'testprofielschets',
        'testhandelingsplan',
        'testvak',
        'testperiode',
        'peeters',
        'dupré',
        '${fakeLvsMarie.pupilId}',
      ]) {
        expect(logged, isNot(contains(word)));
      }
    });

    test('a session Smartschool refuses during the plan: the log names the '
        "error's type, not the request, which holds the pupil's id", () async {
      await read(marie());
      h.server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      final (isError, text, log) = await h.logged(
        'read_lvs_support_plan',
        marie({'period': 900502}),
      );

      expect(isError, isNot(true), reason: text);
      expect(
        log,
        contains(
          'Smartschool did not accept the session '
          '(SmartschoolSessionExpiredError); trying once more',
        ),
      );
      expect(log, isNot(contains('${fakeLvsMarie.pupilId}')));
      expect(log, isNot(contains('900502')));
      expect(log, isNot(contains('jqDispatcher')));
    });

    test('an error whose message holds a name: the log has its type and '
        'HTTP status only, the result neither', () async {
      lvs.failure = const SmartschoolLvsError(
        'Testfout over Peeters Marie.',
        statusCode: 500,
      );

      final (isError, text, log) = await h.logged(
        'read_lvs_support_plan',
        marie(),
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
        ..refusedReads = {FakeLvsRead.supportPlan};

      final (_, _, log) = await h.logged('read_lvs_support_plan', marie());

      expect(log, contains('lvs: SmartschoolLvsAccessDeniedError (HTTP 403)'));
      expect(log, isNot(contains(fakeLvsNoAccessName)));
      expect(log, isNot(contains('${fakeLvsMarie.pupilId}')));
    });
  });

  group('the parts, worded', () {
    LvsPlanItem item(
      LvsPlanItemKind kind, {
      String type = 'ihp',
      String author = '',
      int? authorId,
      String date = '',
      String versionType = '',
      List<String> courses = const [],
      List<int> courseIds = const [],
      List<String> supportNeeds = const [],
      List<LvsPlanGoal> goals = const [],
      String fileName = '',
      String mimeType = '',
    }) => LvsPlanItem(
      id: 900601,
      type: type,
      kind: kind,
      author: author,
      authorId: authorId,
      date: date,
      versionType: versionType,
      courses: courses,
      courseIds: courseIds,
      supportNeeds: supportNeeds,
      goals: goals,
      fileName: fileName,
      mimeType: mimeType,
    );

    /// A plan of [items], with [courses] as the plan's courses.
    LvsSupportPlan planOf(
      List<LvsPlanItem> items, {
      List<LvsPlanCourse> courses = const [],
    }) => LvsSupportPlan(
      period: const LvsPlanPeriodInfo(id: 900501, hasError: false),
      items: items,
      courses: courses,
    );

    test('empty fields left out; an item without anything, a document '
        'without a name or kind of file, goals of a kind the server does not '
        'know', () {
      expect(
        formatLvsPlanItem(
          item(
            LvsPlanItemKind.needs,
            courses: [' ', ''],
            supportNeeds: ['', ' \n '],
          ),
        ),
        '- Support needs and approach | tied to no course\n'
        '  (nothing filled in)',
      );
      expect(
        formatLvsPlanItem(item(LvsPlanItemKind.document, type: 'document')),
        '- An uploaded plan | (no file name), by name only: not opened',
      );
      expect(
        formatLvsPlanItem(
          item(
            LvsPlanItemKind.goals,
            type: 'from_gwp',
            versionType: 'testdoelen',
            goals: const [LvsPlanGoal(name: '')],
          ),
        ),
        '- Goals chosen for the pupil | goals of kind "testdoelen"\n'
        '  - Goal: (no name)',
      );
      expect(
        formatLvsPlanItem(
          item(LvsPlanItemKind.goals, type: 'from_gwp', versionType: 'normal'),
        ),
        '- Goals chosen for the pupil\n'
        '  (nothing filled in)',
      );
    });

    test('a profile sketch: its lines, its last change; there but empty; '
        'none', () {
      const period = LvsPlanPeriodInfo(hasError: false);
      expect(
        formatLvsProfileSketch(
          const LvsProfileSketch(
            period: period,
            hasSketch: true,
            text: 'Testregel een\n\n  Testregel twee  ',
          ),
        ),
        'Profile sketch (profielschets):\n'
        '  Testregel een\n'
        '  Testregel twee',
      );
      expect(
        formatLvsProfileSketch(
          const LvsProfileSketch(
            period: period,
            hasSketch: true,
            lastRevision: 'Testversie',
          ),
        ),
        'Profile sketch (profielschets; last change: Testversie): there, but '
        'empty.',
      );
      expect(
        formatLvsProfileSketch(
          const LvsProfileSketch(period: period, hasSketch: false),
        ),
        'Profile sketch (profielschets): none in this period.',
      );
    });

    test('a course keeps the items that name it, among their courses or the '
        'planning of their goals, and those that name none', () {
      final items = [
        item(LvsPlanItemKind.needs, courses: ['Testvak']),
        item(
          LvsPlanItemKind.goals,
          goals: const [
            LvsPlanGoal(name: 'Testdoel', planning: ['Testvak 2']),
          ],
        ),
        item(LvsPlanItemKind.document),
        item(LvsPlanItemKind.unknown, type: 'testsoort'),
      ];

      final plan = planOf(items);

      final all = selectLvsPlanItems(plan, null, userId: null);
      expect(all.shown, items);
      expect(all.otherCourses, 0);

      final vak2 = selectLvsPlanItems(plan, 'testvak  2', userId: null);
      expect(vak2.matched, ['Testvak 2']);
      expect(vak2.shown, [items[1], items[2], items[3]]);
      expect(vak2.otherCourses, 1);

      final none = selectLvsPlanItems(plan, 'Testvak 9', userId: null);
      expect(none.matched, isEmpty);
      expect(none.shown, [items[2], items[3]]);
      expect(none.otherCourses, 2);
    });

    test('a course keeps the items planned in it by its id: their own course '
        "ids, named by the plan's courses or by a goal's planning, and the "
        "courses of their goals' planning; a course id the plan does not name "
        'ties an item to a course all the same', () {
      final items = [
        // By its own course id, which the plan's courses name.
        item(LvsPlanItemKind.goals, courseIds: [900302]),
        // By the course id of its goal's planning, under another name.
        item(
          LvsPlanItemKind.goals,
          goals: const [
            LvsPlanGoal(
              name: 'Testdoel',
              planning: ['TV2'],
              moments: [LvsPlanMoment(type: 'course', id: 900302, name: 'TV2')],
            ),
          ],
        ),
        // By the id of a course only a goal's planning names.
        item(LvsPlanItemKind.needs, courseIds: [900303]),
        // A course id nothing names: tied to a course, but not this one.
        item(LvsPlanItemKind.needs, courseIds: [900309]),
        // Another moment of the planning with an id: not a course id.
        item(
          LvsPlanItemKind.goals,
          goals: const [
            LvsPlanGoal(
              name: 'Testdoel',
              planning: ['Testmoment'],
              moments: [
                LvsPlanMoment(type: 'other', id: 900302, name: 'Testmoment'),
              ],
            ),
          ],
        ),
        item(LvsPlanItemKind.needs, courseIds: [900301]),
        item(
          LvsPlanItemKind.goals,
          goals: const [
            LvsPlanGoal(
              name: 'Testdoel',
              planning: ['Testvak 3'],
              moments: [
                LvsPlanMoment(type: 'course', id: 900303, name: 'Testvak 3'),
              ],
            ),
          ],
        ),
      ];
      final plan = planOf(
        items,
        courses: const [
          LvsPlanCourse(id: 900301, name: 'Testvak'),
          LvsPlanCourse(id: 900302, name: 'Testvak 2'),
        ],
      );

      final vak2 = selectLvsPlanItems(plan, 'Testvak 2', userId: null);
      expect(vak2.matched, ['Testvak 2']);
      expect(vak2.shown, [items[0], items[1]]);
      expect(vak2.otherCourses, 5);

      final vak3 = selectLvsPlanItems(plan, 'testvak 3', userId: null);
      expect(vak3.matched, ['Testvak 3']);
      expect(vak3.shown, [items[2], items[6]]);

      // Testvak itself, not the courses whose name holds it.
      final vak = selectLvsPlanItems(plan, 'Testvak', userId: null);
      expect(vak.matched, ['Testvak']);
      expect(vak.shown, [items[5]]);
    });

    test('the items the user wrote first, each part in the LVS\'s order, also '
        'among the items of a course; none for an unknown user', () {
      final items = [
        item(LvsPlanItemKind.needs, authorId: 900201, courses: ['Testvak']),
        item(LvsPlanItemKind.needs, authorId: 900202, courses: ['Testvak']),
        item(LvsPlanItemKind.document, authorId: 900202),
        item(LvsPlanItemKind.needs, courses: ['Testvak 2']),
        item(LvsPlanItemKind.needs, authorId: 900202, courses: ['Testvak 2']),
      ];
      final plan = planOf(items);

      expect(selectLvsPlanItems(plan, null, userId: 900202).shown, [
        items[1],
        items[2],
        items[4],
        items[0],
        items[3],
      ]);
      expect(selectLvsPlanItems(plan, 'Testvak', userId: 900202).shown, [
        items[1],
        items[2],
        items[0],
      ]);
      expect(selectLvsPlanItems(plan, null, userId: null).shown, items);
      expect(lvsPlanItemByUser(items[3], null), isFalse);
    });

    test('an item by the user, with its author or without; the courses of '
        'its course ids by name, a course id the plan does not name '
        'counted', () {
      const names = {900301: 'Testvak', 900302: 'Testvak 2'};
      expect(
        formatLvsPlanItem(
          item(LvsPlanItemKind.needs, author: 'Céline Dupré', authorId: 900202),
          byUser: true,
        ),
        startsWith(
          '- Support needs and approach | by the user, Céline Dupré | tied to '
          'no course',
        ),
      );
      expect(
        formatLvsPlanItem(item(LvsPlanItemKind.document), byUser: true),
        startsWith('- An uploaded plan | by the user | '),
      );
      // The names the LVS gives, then those of its other course ids.
      expect(
        formatLvsPlanItem(
          item(
            LvsPlanItemKind.needs,
            courses: ['Testvak'],
            courseIds: [900301, 900302, 900309],
          ),
          courseNames: names,
        ),
        startsWith('- Support needs and approach | for Testvak, Testvak 2\n'),
      );
      expect(
        formatLvsPlanItem(
          item(LvsPlanItemKind.goals, courseIds: [900302]),
          courseNames: names,
        ),
        startsWith('- Goals chosen for the pupil | for Testvak 2\n'),
      );
      expect(
        formatLvsPlanItem(
          item(LvsPlanItemKind.needs, courseIds: [900308, 900309]),
          courseNames: names,
        ),
        startsWith(
          '- Support needs and approach | for 2 courses the plan does not '
          'name\n',
        ),
      );
      expect(
        formatLvsPlanItem(
          item(LvsPlanItemKind.goals, courseIds: [900309]),
          courseNames: names,
        ),
        startsWith(
          '- Goals chosen for the pupil | for 1 course the plan does ',
        ),
      );
    });

    test('the first line says how many items the user wrote: some, none, all '
        'of them, one that is all; and only the order for an unknown '
        'user', () {
      String head(List<int?> authors, int? userId) => formatLvsSupportPlan(
        (
          periods: const [],
          period: null,
          plan: planOf([
            for (final author in authors)
              item(LvsPlanItemKind.document, authorId: author),
          ]),
          sketch: null,
          fileHasSupportPlans: true,
          userId: userId,
        ),
        pupilId: 900002,
        classId: 900102,
        course: null,
      ).split('\n').first;

      const lead =
          'The support plan (handelingsplan) of the pupil with pupil_id 900002 '
          '(class_id 900102) in the LVS, the current period (period_id '
          '900501): ';
      expect(
        head([900201, 900202, 900202], 900202),
        '${lead}3 items: first the 2 items the user wrote, marked "by the '
        'user", then the others, each in the LVS\'s order.',
      );
      expect(
        head([900201, null], 900202),
        "${lead}2 items, in the LVS's order; the user wrote none of them.",
      );
      expect(
        head([900202, 900202], 900202),
        "${lead}2 items, in the LVS's order; the user wrote all of them.",
      );
      expect(
        head([900202], 900202),
        "${lead}1 item, in the LVS's order; the user wrote it.",
      );
      expect(head([900202], null), "${lead}1 item, in the LVS's order.");
    });

    test('a course no item names, in a plan whose items all name a course: '
        'nothing is shown, which the answer says', () {
      final text = formatLvsSupportPlan(
        (
          periods: const [],
          period: null,
          plan: planOf([
            item(LvsPlanItemKind.needs, courses: ['Testvak']),
          ]),
          sketch: const LvsProfileSketch(
            period: LvsPlanPeriodInfo(hasError: false),
            hasSketch: false,
          ),
          fileHasSupportPlans: true,
          userId: null,
        ),
        pupilId: 900002,
        classId: 900102,
        course: 'Testvak 3',
      );

      expect(
        text,
        'The support plan (handelingsplan) of the pupil with pupil_id 900002 '
        '(class_id 900102) in the LVS, the current period (period_id '
        "900501): 1 item, in the LVS's order.\n"
        'No item of this plan names a course "Testvak 3"; its items name: '
        'Testvak. Nothing is shown; leave course out to see all 1.\n'
        '$_notRead\n'
        'Profile sketch (profielschets): none in this period.\n'
        'The LVS lists no periods of the support plans to choose from.',
      );
    });

    test('a period by its id as the tool prints it, or its name', () {
      const periods = [
        LvsPlanPeriod(id: 900501, name: 'Testperiode'),
        LvsPlanPeriod(id: 900502, name: 'Testperiode 2', heading: 'Test'),
      ];
      expect(pickLvsPlanPeriod(periods, 'Period_ID 900502'), periods[1]);
      expect(pickLvsPlanPeriod(periods, 'TESTPERIODE'), periods[0]);
      expect(
        () => pickLvsPlanPeriod(const [], 'Testperiode'),
        throwsA(isA<ToolError>()),
      );
    });
  });
}
