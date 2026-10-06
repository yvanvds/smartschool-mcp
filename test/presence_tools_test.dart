/// `list_presence_classes`, `list_class_presences`, `set_pupils_late` and
/// `set_pupils_present` (#47), called over MCP on the real server, session
/// and library, against a fake Smartschool whose Presence module serves the
/// endpoints `PresenceService` reads, in the shape of dartschool's trimmed
/// captures with fake names, and carries out the save of a half-day as the
/// live module did (`test/support/fake_presence.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/presence/presence_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The day of the fake school, and the time the tools take as now.
const _day = '2026-06-01';
final _now = DateTime(2026, 6, 1, 10, 30);

const _getConfig = 'POST $fakePresenceConfigPath';
const _getCodes = 'POST $fakePresenceCodesPath';
const _getClass = 'POST $fakePresenceClassPath';
const _save = 'POST $fakePresenceSavePath';

/// The reads of a write before anything is sent.
const _readFirst = [_getConfig, _getCodes, _getClass];

/// The requests for one pupil whose half-day is saved: the library reads the
/// class, checks the half-day against the statuses the server lets it
/// replace (dartschool#105), and saves. The server reads nothing more.
const _savePupil = [_getClass, _save];

/// What the tools say to an account without the rights, after the reason.
const _rights =
    "the right to record half-day presences for classes in Smartschool's "
    'Presence module, as an absence administrator has';
const _fix =
    "ask the school's Smartschool administrator for them, or turn off "
    '"Aanwezigheden" (SMARTSCHOOL_PRESENCE) in the Smartschool extension '
    'settings in Claude Desktop (Settings → Extensions), then restart Claude '
    'Desktop';

/// Class 1A of the fake school in a sentence, and the morning in it.
const _class1A = 'class 1A (class id 298)';
const _morning = 'the morning of Monday 2026-06-01 in $_class1A';

void main() {
  late FakeSmartschool server;
  late FakePresence presence;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    presence = server.presence..loadSchool(_day);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: presenceOptIn(session, SwitchState.on, now: () => _now).offered,
    );
  });

  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// The arguments of a write for the morning of [_day] in 1A.
  Map<String, Object?> write(
    List<int> pupilIds, {
    String part = 'morning',
    String date = _day,
    int classId = 298,
    Map<String, Object?> more = const {},
  }) => {
    'class_id': classId,
    'pupil_ids': pupilIds,
    'date': date,
    'part': part,
    ...more,
  };

  /// What pupil [userId]'s half-day [part] of [_day] holds in the fake, as
  /// (code id, alias id, motivation).
  (int?, int?, String?)? stored(int userId, [String part = 'am']) {
    final cell = presence.halfDay(userId, _day, part);
    return cell == null ? null : (cell.codeId, cell.aliasId, cell.motivation);
  }

  group('the switch', () {
    test('off or unclear: no presence tool is offered', () {
      final session = SmartschoolSession(fakeExtensionSettings());
      for (final state in [SwitchState.off, SwitchState.unclear]) {
        final optIn = presenceOptIn(session, state);
        expect(optIn.setting, Setting.presence);
        expect(optIn.offered, isEmpty, reason: state.name);
        expect(optIn.tools, hasLength(4));
      }
    });
  });

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

    test('the reads first, read-only, then the writes, destructive and '
        'idempotent, so Claude Desktop asks approval before every write', () {
      expect(tools.keys, [
        'list_presence_classes',
        'list_class_presences',
        'set_pupils_late',
        'set_pupils_present',
      ]);
      for (final name in ['list_presence_classes', 'list_class_presences']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isTrue, reason: name);
        expect(annotations.destructiveHint, isNot(true), reason: name);
        expect(
          tools[name]!.description,
          contains('Reading changes nothing.'),
          reason: name,
        );
      }
      for (final name in ['set_pupils_late', 'set_pupils_present']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isFalse, reason: name);
        expect(annotations.destructiveHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isTrue, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
        expect(
          tools[name]!.description,
          allOf(
            contains(
              'show the user the class, the pupils by name, the day and the '
              'half-day',
            ),
            contains(
              'only call this tool after the user has explicitly confirmed '
              'it. Pass all pupils of one confirmation in one call.',
            ),
            contains(
              'The server only changes a half-day that holds nothing '
              'recorded, "Aanwezig", "Te laat" or "Te laat zonder geldige '
              'reden".',
            ),
          ),
          reason: name,
        );
      }
    });

    test('the writes take the class, the pupils, the day and the half-day, '
        'and optionally a motivation (and, to mark late, without a valid '
        'reason)', () {
      expect(tools['set_pupils_late']!.inputSchema.required, [
        'class_id',
        'pupil_ids',
        'date',
        'part',
      ]);
      expect(tools['set_pupils_late']!.inputSchema.properties!.keys, [
        'class_id',
        'pupil_ids',
        'date',
        'part',
        'without_valid_reason',
        'motivation',
      ]);
      expect(tools['set_pupils_present']!.inputSchema.properties!.keys, [
        'class_id',
        'pupil_ids',
        'date',
        'part',
        'motivation',
      ]);
      final properties = tools['set_pupils_late']!.inputSchema.properties!;
      expect(properties['pupil_ids'], {
        'type': 'array',
        'description': isA<String>(),
        'items': {'type': 'integer', 'minimum': 1},
        'minItems': 1,
        'maxItems': 50,
      });
      expect(properties['part'], {
        'type': 'string',
        'description': isA<String>(),
        'enum': ['morning', 'afternoon'],
      });
      expect(tools['list_class_presences']!.inputSchema.required, ['class_id']);
    });
  });

  group('list_presence_classes', () {
    test('lists the classes of the configuration, and whether the account '
        'may record presences for each', () async {
      final text = await ok('list_presence_classes');

      expect(
        text,
        'The Presence module lists 3 classes for this account, in its order; '
        'it may record presences for 2 of them.\n'
        '1A | class id 298 | may record\n'
        '1B | class id 312 | view only\n'
        '2A | class id 1650 | may record | grouping class (no school '
        'structure): record in the official class',
      );
      expect(presence.calls, [_getConfig]);
    });

    test(
      'a teacher without the absence-administrator rights: every class '
      'view only, although the module gives userCanRecord for each (#95)',
      () async {
        presence.dropConfirmRight();

        final text = await ok('list_presence_classes');

        expect(
          text,
          'The Presence module lists 3 classes for this account, in its order; '
          'it may record presences for 0 of them.\n'
          '1A | class id 298 | view only\n'
          '1B | class id 312 | view only\n'
          '2A | class id 1650 | view only | grouping class (no school '
          'structure): record in the official class',
        );
      },
    );

    test('no classes: says the account most likely lacks the rights', () async {
      presence.classes.clear();

      final text = await ok('list_presence_classes');

      expect(
        text,
        'The Presence module lists no classes for this account, as for an '
        'account without $_rights. If so, $_fix.',
      );
    });

    group('a teacher without a lesson at the moment: the placeholder "Uit '
        'Planner" (class id -2) that the module gives as the active class is '
        'no class, and is neither listed nor counted (#84)', () {
      setUp(() => presence.noLesson = true);

      test('with classes', () async {
        final text = await ok('list_presence_classes');

        expect(
          text,
          'The Presence module lists 3 classes for this account, in its '
          'order; it may record presences for 2 of them.\n'
          '1A | class id 298 | may record\n'
          '1B | class id 312 | view only\n'
          '2A | class id 1650 | may record | grouping class (no school '
          'structure): record in the official class',
        );
      });

      test(
        'without classes: none, as for an account without the rights',
        () async {
          presence.classes.clear();

          final text = await ok('list_presence_classes');

          expect(
            text,
            'The Presence module lists no classes for this account, as for an '
            'account without $_rights. If so, $_fix.',
          );
        },
      );
    });
  });

  group('list_class_presences', () {
    test('lists a day of a class with the names of the codes and their '
        'motivation; the registrations per lesson are left out', () async {
      final text = await ok('list_class_presences', {
        'class_id': 298,
        'date': _day,
      });

      expect(
        text,
        'Class 1A (class id 298), Monday 2026-06-01: 4 pupils, in the '
        "module's order. This account may record presences for this class.\n"
        '- Peeters, Lotte (pupil id 1001) | morning: "Aanwezig" | afternoon: '
        '"Aanwezig"\n'
        '- Janssens, Emma (pupil id 1002) | morning: nothing recorded | '
        'afternoon: nothing recorded\n'
        '- Dupont, Noah (pupil id 1003) | morning: "Doktersattest", '
        'motivation "attest huisarts" | afternoon: nothing recorded\n'
        '- Claes, Mila (pupil id 1004) | morning: "Te laat", motivation "bus '
        'te laat" | afternoon: "Te laat zonder geldige reden" (under "Te '
        'laat")',
      );
      expect(presence.calls, _readFirst);
      expect(presence.requests[1].form, {
        'structID': '$fakePresenceStruct',
        'ofschoolage': 'of_school_age',
      });
      expect(presence.requests[2].form, {
        'classID': '298',
        'startDate': _day,
        'endDate': _day,
        'schoolyearRefDate': '2025-11-05',
        'includePupils': '1',
        'includePresences': '1',
      });
    });

    test('a half-day whose code or alias is not among the codes of the '
        'class: as the module names it with the record, or by its id, and '
        'why', () async {
      // Not seen live. "Ziek" is a code of another structure, which the
      // module names with the record as any; the alias 99 is one the module
      // gives no name with.
      presence.halfDay(fakeDupont.userId, _day, 'am')!.codeId =
          fakePresenceZiek;
      presence.halfDay(fakeClaes.userId, _day, 'pm')!.aliasId = 99;

      final text = await ok('list_class_presences', {
        'class_id': 298,
        'date': _day,
      });

      expect(
        text,
        endsWith(
          '- Dupont, Noah (pupil id 1003) | morning: "Ziek", motivation '
          '"attest huisarts" | afternoon: nothing recorded\n'
          '- Claes, Mila (pupil id 1004) | morning: "Te laat", motivation '
          '"bus te laat" | afternoon: alias id 99 (the module gave no name '
          'with the record, and it is not among the codes of the class)',
        ),
      );
    });

    test('without a date: today', () async {
      final text = await ok('list_class_presences', {'class_id': 298});

      expect(text, startsWith('Class 1A (class id 298), Monday 2026-06-01: '));
    });

    test('a class the account may only view: its pupils, and that the writes '
        'refuse it', () async {
      final text = await ok('list_class_presences', {
        'class_id': 312,
        'date': _day,
      });

      expect(
        text,
        'Class 1B (class id 312), Monday 2026-06-01: 1 pupil, in the '
        "module's order. This account may only view this class: "
        'set_pupils_late and set_pupils_present refuse it.\n'
        '- Wouters, Lars (pupil id 1101) | morning: "Te laat" | afternoon: '
        'nothing recorded',
      );
    });

    test('a teacher without the absence-administrator rights: the pupils, '
        'and that the writes refuse the class (#95)', () async {
      presence.dropConfirmRight();

      final text = await ok('list_class_presences', {
        'class_id': 298,
        'date': _day,
      });

      expect(
        text,
        startsWith(
          'Class 1A (class id 298), Monday 2026-06-01: 4 pupils, in the '
          "module's order. This account may only view this class: "
          'set_pupils_late and set_pupils_present refuse it.\n'
          '- Peeters, Lotte (pupil id 1001) | ',
        ),
      );
    });

    test('no pupils: the reason the module gives, for a class without pupils '
        'and for a day in the future (dartschool#104)', () async {
      presence.classes.add(const FakePresenceClass(4882, '2F ECO '));

      expect(
        await ok('list_class_presences', {'class_id': 4882, 'date': _day}),
        'The Presence module lists no pupils for class 2F ECO (class id 4882) '
        'on Monday 2026-06-01: "Deze klas bevat geen leerlingen." This '
        'account may record presences for this class.',
      );
      expect(
        await ok('list_class_presences', {
          'class_id': 298,
          'date': '2026-06-02',
        }),
        'The Presence module lists no pupils for class 1A (class id 298) on '
        'Tuesday 2026-06-02: "Het is niet mogelijk om in de toekomst '
        'afwezigheden op te nemen." This account may record presences for '
        'this class.',
      );
    });

    group('a grouping class: the module gives no codes for it; its statuses '
        'as the module names them with the records, or with the codes of '
        "the pupil's official class (#99, #101)", () {
      /// The heading of 2A, with [count] pupils.
      String heading(String count) =>
          'Class 2A (class id 1650), Monday 2026-06-01: $count, in the '
          "module's order. This account may record presences for this class. "
          'The class is a grouping class without a school structure: '
          "presences are recorded in the pupils' official class.";

      test('"Te laat" and "Aanwezig", as the module names them with the '
          'records; no codes read', () async {
        final text = await ok('list_class_presences', {
          'class_id': 1650,
          'date': _day,
        });

        expect(
          text,
          '${heading('1 pupil')}\n'
          '- Maes, Finn (pupil id 1201) | morning: "Te laat" | afternoon: '
          '"Aanwezig"',
        );
        expect(presence.calls, [_getConfig, _getClass]);
      });

      test('a half-day the module gives no name with: the codes of the '
          "structure of the pupil's official class, read once per structure "
          'after the pupils, not those of every class', () async {
        // 2A ECO, the official class of Maes, in a second structure, and
        // Peeters of 1A in 2A too. Maes holds "Ziek", a code of 2A ECO's
        // structure, and "Te laat", a code of 1A's.
        presence.classes
          ..add(fake2AEco)
          ..[presence.classes.indexOf(fake2A)] = const FakePresenceClass(
            1650,
            '2A  ',
            structId: null,
            pupils: [fakeMaes, fakePeeters],
          );
        presence.halfDay(fakeMaes.userId, _day, 'am')!
          ..codeId = fakePresenceZiek
          ..unnamed = true;
        presence.halfDay(fakeMaes.userId, _day, 'pm')!
          ..codeId = fakePresenceTeLaat
          ..unnamed = true;
        presence.halfDay(fakePeeters.userId, _day, 'am')!.unnamed = true;

        final text = await ok('list_class_presences', {
          'class_id': 1650,
          'date': _day,
        });

        expect(
          text,
          '${heading('2 pupils')}\n'
          '- Maes, Finn (pupil id 1201) | morning: "Ziek" | afternoon: code '
          'id 497 (the module gave no name with the record, and it is not '
          "among the codes of the pupil's official class)\n"
          '- Peeters, Lotte (pupil id 1001) | morning: "Aanwezig" | '
          'afternoon: "Aanwezig"',
        );
        expect(presence.calls, [_getConfig, _getClass, _getCodes, _getCodes]);
        expect(
          [
            for (final request in presence.requests)
              if (request.path == fakePresenceCodesPath)
                request.form['structID'],
          ],
          ['$fakePresenceOtherStruct', '$fakePresenceStruct'],
        );
      });

      test('a half-day the module gives no name with, of a pupil whose '
          'official class this account does not see: by code id, and why; '
          'no codes read', () async {
        presence.halfDay(fakeMaes.userId, _day, 'am')!.unnamed = true;

        final text = await ok('list_class_presences', {
          'class_id': 1650,
          'date': _day,
        });

        expect(
          text,
          '${heading('1 pupil')}\n'
          '- Maes, Finn (pupil id 1201) | morning: code id 497 (the module '
          'gave no name with the record, and this account does not see the '
          "pupil's official class, whose codes would name it) | afternoon: "
          '"Aanwezig"',
        );
        expect(presence.calls, [_getConfig, _getClass]);
      });
    });

    test('an unknown class id, or a date that is not a day: says what to '
        'pass', () async {
      expect(
        await error('list_class_presences', {'class_id': 4242}),
        'No class with class id 4242 is among the classes this account may '
        'view in the Presence module. Take the class id from '
        'list_presence_classes.',
      );
      for (final date in ['2026-06-01 08:30', '1 juni', '2026-02-30']) {
        expect(
          await error('list_class_presences', {'class_id': 298, 'date': date}),
          startsWith('date must be a day like 2026-10-05'),
          reason: date,
        );
      }
    });
  });

  group('set_pupils_late', () {
    test('marks several pupils late with a motivation, one after the other, '
        'and says what is stored as the module answered the saves, without '
        'reading the class again (dartschool#105)', () async {
      final text = await ok(
        'set_pupils_late',
        write([1001, 1002], more: {'motivation': 'bus lijn 5 te laat'}),
      );

      expect(
        text,
        'Set "Te laat" with motivation "bus lijn 5 te laat" for $_morning:\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig"); now: "Te '
        'laat", motivation "bus lijn 5 te laat"\n'
        '- Janssens, Emma (pupil id 1002): set (was nothing recorded); now: '
        '"Te laat", motivation "bus lijn 5 te laat"',
      );
      expect(presence.calls, [..._readFirst, ..._savePupil, ..._savePupil]);
      // An update of Peeters's half-day, a new one for Janssens.
      expect(presence.saves, [
        {
          'userID': 1001,
          'movementID': 5001,
          'presenceID': 90001,
          'presenceDate': _day,
          'studentID': 1001,
          'hourID': null,
          'partOfDay': 'am',
          'codeID': fakePresenceTeLaat,
          'aliasID': null,
          'motivation': 'bus lijn 5 te laat',
          'deleteStatus': 0,
        },
        {
          'userID': 1002,
          'movementID': 5002,
          'presenceID': null,
          'presenceDate': _day,
          'studentID': 1002,
          'hourID': null,
          'partOfDay': 'am',
          'codeID': fakePresenceTeLaat,
          'aliasID': null,
          'motivation': 'bus lijn 5 te laat',
          'deleteStatus': 0,
        },
      ]);
      expect(stored(1001), (fakePresenceTeLaat, null, 'bus lijn 5 te laat'));
      expect(stored(1002), (fakePresenceTeLaat, null, 'bus lijn 5 te laat'));
      expect(stored(1001, 'pm'), (fakePresenceAanwezig, null, null));
    });

    test('without a valid reason: the alias, also over a "Te laat"', () async {
      final text = await ok(
        'set_pupils_late',
        write([1002, 1004], more: {'without_valid_reason': true}),
      );

      expect(
        text,
        'Set "Te laat zonder geldige reden" for $_morning:\n'
        '- Janssens, Emma (pupil id 1002): set (was nothing recorded); now: '
        '"Te laat zonder geldige reden" (under "Te laat")\n'
        '- Claes, Mila (pupil id 1004): set (was "Te laat", motivation "bus '
        'te laat"); now: "Te laat zonder geldige reden" (under "Te laat")',
      );
      expect(
        [
          for (final save in presence.saves)
            (save['codeID'], save['aliasID'], save['motivation']),
        ],
        [
          (null, fakePresenceZonderReden, ''),
          (null, fakePresenceZonderReden, ''),
        ],
      );
      expect(stored(1002), (null, fakePresenceZonderReden, null));
      expect(stored(1004), (null, fakePresenceZonderReden, null));
    });

    test('a pupil who already has the status keeps it and its motivation: '
        'nothing is saved for them', () async {
      final text = await ok('set_pupils_late', write([1004]));

      expect(
        text,
        'Nothing changed in Smartschool: these pupils already had "Te laat" '
        'for $_morning, so nothing was saved:\n'
        '- Claes, Mila (pupil id 1004): already had it; nothing saved; now: '
        '"Te laat", motivation "bus te laat"',
      );
      expect(presence.saves, isEmpty);
      expect(presence.calls, _readFirst, reason: 'nothing more is read');

      // With another motivation, the half-day changes.
      final changed = await ok(
        'set_pupils_late',
        write([1004], more: {'motivation': 'trein'}),
      );
      expect(
        changed,
        contains(
          '- Claes, Mila (pupil id 1004): set (was "Te laat", motivation "bus '
          'te laat"); now: "Te laat", motivation "trein"',
        ),
      );
      expect(presence.saves, hasLength(1));
    });

    test('the afternoon', () async {
      final text = await ok(
        'set_pupils_late',
        write([1001], part: 'afternoon'),
      );

      expect(
        text,
        startsWith('Set "Te laat" for the afternoon of Monday 2026-06-01 in '),
      );
      expect(presence.saves.single['partOfDay'], 'pm');
      expect(presence.saves.single['presenceID'], 90002);
      expect(stored(1001, 'pm'), (fakePresenceTeLaat, null, null));
      expect(stored(1001), (fakePresenceAanwezig, null, null));
    });
  });

  group('set_pupils_present', () {
    test('sets pupils marked late present again, and saves nothing for a '
        'pupil who is present', () async {
      await ok('set_pupils_late', write([1001, 1002]));

      final text = await ok('set_pupils_present', write([1001, 1002, 1004]));

      expect(
        text,
        'Set "Aanwezig" for $_morning:\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Te laat"); now: '
        '"Aanwezig"\n'
        '- Janssens, Emma (pupil id 1002): set (was "Te laat"); now: '
        '"Aanwezig"\n'
        '- Claes, Mila (pupil id 1004): set (was "Te laat", motivation "bus '
        'te laat"); now: "Aanwezig"',
      );
      expect(stored(1001), (fakePresenceAanwezig, null, null));
      expect(stored(1002), (fakePresenceAanwezig, null, null));
      expect(stored(1004), (fakePresenceAanwezig, null, null));

      final again = await ok('set_pupils_present', write([1001]));
      expect(again, startsWith('Nothing changed in Smartschool: '));
      expect(presence.saves, hasLength(5));
    });
  });

  group('refused before anything is sent', () {
    test('a class the account may only view, after reading only the '
        'configuration', () async {
      final text = await error('set_pupils_late', write([1101], classId: 312));

      expect(
        text,
        'This account may not record presences for class 1B (class id 312): '
        "the Presence module lets it view the class only. Ask the school's "
        'Smartschool administrator for the right to record presences for it. '
        'Nothing was changed in Smartschool.',
      );
      expect(presence.calls, [_getConfig]);
    });

    test('a teacher without the absence-administrator rights, whom the module '
        'gives userCanRecord but not userCanConfirm: refused after reading '
        'only the configuration, so the save the module would refuse is never '
        'sent (#95)', () async {
      presence.dropConfirmRight();

      for (final tool in ['set_pupils_late', 'set_pupils_present']) {
        final text = await error(tool, write([1002]));

        expect(
          text,
          'This account may not record presences for class 1A (class id '
          "298): the Presence module lets it view the class only. Ask the "
          "school's Smartschool administrator for the right to record "
          'presences for it. Nothing was changed in Smartschool.',
        );
      }
      expect(presence.calls, [_getConfig, _getConfig]);
      expect(presence.saves, isEmpty);
    });

    test('a class or day the module refuses, with its reason, after reading '
        'the class (dartschool#104)', () async {
      presence.classes.add(const FakePresenceClass(4882, '2F ECO '));

      final text = await error('set_pupils_late', write([1001], classId: 4882));

      expect(
        text,
        'The Presence module refuses to record presences for class 2F ECO '
        '(class id 4882) on Monday 2026-06-01: "Deze klas bevat geen '
        'leerlingen." Nothing was changed in Smartschool.',
      );
      expect(presence.calls, _readFirst);
    });

    test('a grouping class, and an unknown class', () async {
      expect(
        await error('set_pupils_present', write([1201], classId: 1650)),
        'Class 2A (class id 1650) is a grouping class without a school '
        "structure: presences are recorded in the pupils' official class. "
        'Find it with list_presence_classes. Nothing was changed in '
        'Smartschool.',
      );
      expect(
        await error('set_pupils_late', write([1001], classId: 4242)),
        endsWith(
          'Take the class id from list_presence_classes. Nothing was changed '
          'in Smartschool.',
        ),
      );
      expect(presence.calls, everyElement(isNot(_save)));
    });

    test('a pupil with another status, or not listed: the whole call, and '
        'the pupils that could be changed are not changed either', () async {
      final text = await error('set_pupils_late', write([1001, 1003, 4242]));

      expect(
        text,
        'Nothing was changed in Smartschool. set_pupils_late only changes a '
        'half-day that holds nothing recorded, "Aanwezig", "Te laat" or "Te '
        'laat zonder geldige reden", and never overwrites another status, '
        'such as an absence the secretariat recorded. In $_class1A, on the '
        'morning of Monday 2026-06-01:\n'
        '- Dupont, Noah (pupil id 1003): the morning holds "Doktersattest", '
        'motivation "attest huisarts".\n'
        '- pupil id 4242 is not listed in the class on that day.\n'
        'Read the class with list_class_presences. Leave those pupils out '
        '(and call again with the others, as the user confirmed), or let the '
        'user change their half-day in Smartschool.',
      );
      expect(presence.calls, _readFirst);
      expect(stored(1001), (fakePresenceAanwezig, null, null));
      expect(stored(1003), (
        fakePresenceDoktersattest,
        null,
        'attest huisarts',
      ));

      // The afternoon of the same pupil holds nothing: that may change.
      await ok('set_pupils_present', write([1003], part: 'afternoon'));
      expect(stored(1003, 'pm'), (fakePresenceAanwezig, null, null));
    });

    test('a day in the future, without asking Smartschool', () async {
      final text = await error(
        'set_pupils_late',
        write([1001], date: '2026-06-02'),
      );

      expect(
        text,
        'The date Tuesday 2026-06-02 is in the future: presences are recorded '
        'for today or an earlier day. Nothing was changed in Smartschool.',
      );
      expect(presence.requests, isEmpty);

      // An earlier day may change.
      presence.halfDays[(1001, '2026-05-29', 'am')] = FakeHalfDay(
        80001,
        codeId: fakePresenceAanwezig,
      );
      await ok('set_pupils_late', write([1001], date: '2026-05-29'));
      expect(
        presence.halfDay(1001, '2026-05-29', 'am')!.codeId,
        fakePresenceTeLaat,
      );
    });
  });

  group('the check afterwards', () {
    test('a save answered without the half-day as stored: the class is read '
        'once more, and shows it', () async {
      presence.save = PresenceSave.withoutRecords;

      final text = await ok('set_pupils_late', write([1001, 1002]));

      expect(
        text,
        'Set "Te laat" for $_morning:\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig"); now: "Te '
        'laat"\n'
        '- Janssens, Emma (pupil id 1002): set (was nothing recorded); now: '
        '"Te laat"',
      );
      expect(presence.calls, [
        ..._readFirst,
        ..._savePupil,
        ..._savePupil,
        _getClass,
      ]);
    });

    test('a save answered as done but not carried out: the class is read '
        'once more; NOT what was saved, and an error', () async {
      presence.save = PresenceSave.unapplied;

      final text = await error('set_pupils_late', write([1001]));

      expect(
        text,
        'Set "Te laat" for $_morning:\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig"); now: '
        '"Aanwezig" (NOT what was saved)\n'
        'Smartschool does not show what was saved for the pupils marked "NOT '
        'what was saved": read the class with list_class_presences and tell '
        'the user what it shows.',
      );
      expect(presence.calls, [..._readFirst, ..._savePupil, _getClass]);
    });

    test('a read afterwards that fails: the saves it was needed for are not '
        'confirmed, and Claude is told to read the class', () async {
      presence.save = PresenceSave.withoutRecords;
      // The 3rd read of the class is the one after the save.
      presence.onGetClass = (count) {
        if (count == 3) presence.refused = true;
      };

      final text = await error('set_pupils_late', write([1001]));

      expect(
        text,
        'Set "Te laat" for $_morning:\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig") (not '
        'confirmed)\n'
        'Reading the class again afterwards failed, so the result does not '
        "show what every half-day holds now: Smartschool's Presence module "
        'refused the request, or could not find what it was asked for; '
        'usually the account lacks $_rights. If so, $_fix. Otherwise try '
        'again in a moment; the technical details are in the server log. '
        'Read the class with list_class_presences and tell the user what it '
        'shows.',
      );
      expect(presence.calls, [..._readFirst, ..._savePupil, _getClass]);
      expect(stored(1001), (fakePresenceTeLaat, null, null));
    });
  });

  group('a failure halfway stops the change, reported per pupil', () {
    test('the module refuses the second save: its reason, without what else '
        'its answer holds (dartschool#109)', () async {
      presence.nextSaves.addAll([
        PresenceSave.confirmed,
        PresenceSave.rejected,
      ]);

      final text = await error('set_pupils_late', write([1001, 1002, 1004]));

      expect(
        text,
        'Setting "Te laat" for $_morning stopped at Janssens, Emma (pupil id '
        '1002):\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig"); now: "Te '
        'laat"\n'
        '- Janssens, Emma (pupil id 1002): not changed (see below); now: '
        'nothing recorded\n'
        '- Claes, Mila (pupil id 1004): not tried; now: "Te laat", motivation '
        '"bus te laat"\n'
        "Smartschool's Presence module refused to save the change for "
        'Janssens, Emma (pupil id 1002): De afwezigheid kon niet worden '
        'opgeslagen.\n'
        'The pupils listed after them were not tried.',
      );
      expect(presence.calls, [
        ..._readFirst,
        ..._savePupil,
        ..._savePupil,
        _getClass,
      ]);
      expect(stored(1001), (fakePresenceTeLaat, null, null));
      expect(stored(1002), isNull);
    });

    test('the module answers the save with an error page', () async {
      presence.save = PresenceSave.errorPage;

      final text = await error('set_pupils_present', write([1004, 1001]));

      expect(
        text,
        contains(
          '- Claes, Mila (pupil id 1004): not changed (see below); now: "Te '
          'laat", motivation "bus te laat"\n'
          '- Peeters, Lotte (pupil id 1001): not tried; now: "Aanwezig"\n',
        ),
      );
      expect(text, isNot(contains('Oeps')));
    });

    test('the answer to the second save is lost: may or may not have been '
        'saved, and the class read afterwards shows it was', () async {
      presence.nextSaves.addAll([
        PresenceSave.confirmed,
        PresenceSave.answerLost,
      ]);

      final text = await error('set_pupils_late', write([1001, 1002, 1004]));

      expect(
        text,
        contains(
          '- Janssens, Emma (pupil id 1002): may or may not have been saved '
          '(see below); now: "Te laat"\n'
          '- Claes, Mila (pupil id 1004): not tried; now: "Te laat", '
          'motivation "bus te laat"\n',
        ),
      );
      expect(
        text,
        contains(
          'The half-day of Janssens, Emma (pupil id 1002) may or may not have '
          'been saved: see what it holds now.',
        ),
      );
      expect(presence.saves, hasLength(2), reason: 'not sent again');
    });

    test('a half-day that changed to another status after the first read is '
        'refused by the library right before its save, and nothing is sent '
        'for it (dartschool#105)', () async {
      // The 3rd read of the class is the library's, right before the second
      // pupil's save.
      presence.onGetClass = (count) {
        if (count == 3) {
          presence.halfDays[(1002, _day, 'am')] = FakeHalfDay(
            93001,
            codeId: fakePresenceDoktersattest,
          );
        }
      };

      final text = await error('set_pupils_late', write([1001, 1002]));

      expect(
        text,
        'Setting "Te laat" for $_morning stopped at Janssens, Emma (pupil id '
        '1002):\n'
        '- Peeters, Lotte (pupil id 1001): set (was "Aanwezig"); now: "Te '
        'laat"\n'
        '- Janssens, Emma (pupil id 1002): not changed (see below); now: '
        '"Doktersattest"\n'
        'The morning of Janssens, Emma (pupil id 1002) changed meanwhile: it '
        'now holds "Doktersattest", which the server never overwrites. '
        'Nothing was saved for them.',
      );
      // The library's read, without a save, then the read afterwards.
      expect(presence.calls, [
        ..._readFirst,
        ..._savePupil,
        _getClass,
        _getClass,
      ]);
      expect(presence.saves, hasLength(1));
      expect(stored(1002), (fakePresenceDoktersattest, null, null));
    });
  });

  group('a pupil the library no longer finds in the class right before the '
      'save: the change stops there, says so, and the class read afterwards '
      'shows it (dartschool#116)', () {
    test('the class lists the other pupils', () async {
      // The 2nd read of the class is the library's, right before the first
      // pupil's save.
      presence.onGetClass = (count) {
        if (count == 2) {
          presence.classes[0] = const FakePresenceClass(
            298,
            '1A  ',
            pupils: [fakeJanssens, fakeDupont, fakeClaes],
          );
        }
      };

      final text = await error('set_pupils_late', write([1001, 1002]));

      expect(
        text,
        'Setting "Te laat" for $_morning stopped at Peeters, Lotte (pupil id '
        '1001):\n'
        '- Peeters, Lotte (pupil id 1001): not changed (see below); no longer '
        'listed in the class\n'
        '- Janssens, Emma (pupil id 1002): not tried; now: nothing recorded\n'
        'Peeters, Lotte (pupil id 1001) is no longer listed in the class on '
        'that day. Nothing was saved for them.\n'
        'The pupils listed after them were not tried.',
      );
      expect(presence.calls, [..._readFirst, _getClass, _getClass]);
      expect(presence.saves, isEmpty);
    });

    test("the class lists no pupils at all: with the module's reason", () async {
      // The 2nd read of the class is the library's, right before the first
      // pupil's save.
      presence.onGetClass = (count) {
        if (count == 2) {
          presence.classes[0] = const FakePresenceClass(298, '1A  ');
        }
      };

      final text = await error('set_pupils_present', write([1002, 1004]));

      expect(
        text,
        'Setting "Aanwezig" for $_morning stopped at Janssens, Emma (pupil id '
        '1002):\n'
        '- Janssens, Emma (pupil id 1002): not changed (see below); no longer '
        'listed in the class\n'
        '- Claes, Mila (pupil id 1004): not tried; no longer listed in the '
        'class\n'
        'Janssens, Emma (pupil id 1002) is no longer listed in the class on '
        'that day. The Presence module now lists no pupils for it: "Deze klas '
        'bevat geen leerlingen." Nothing was saved for them.\n'
        'The pupils listed after them were not tried.',
      );
      expect(presence.calls, [..._readFirst, _getClass, _getClass]);
      expect(presence.saves, isEmpty);
    });
  });

  test('a session Smartschool refuses for the save: the library logs in '
      'again and saves once', () async {
    await ok('list_class_presences', {'class_id': 298, 'date': _day});
    server.expireSessionBefore(
      (request) => request.uri.path == fakePresenceSavePath,
    );

    final text = await ok('set_pupils_late', write([1002]));

    expect(text, contains('set (was nothing recorded); now: "Te laat"'));
    expect(presence.saves, hasLength(1));
    expect(server.logins, 2);
  });

  test('an account the module refuses: usually no rights, with what to do, '
      'without quoting the page', () async {
    presence.refused = true;

    for (final (tool, arguments) in <(String, Map<String, Object?>)>[
      ('list_presence_classes', {}),
      ('list_class_presences', {'class_id': 298}),
    ]) {
      expect(
        await error(tool, arguments),
        "Smartschool's Presence module refused the request, or could not "
        'find what it was asked for; usually the account lacks $_rights. If '
        'so, $_fix. Otherwise try again in a moment; the technical details '
        'are in the server log.',
        reason: tool,
      );
    }
    final text = await error('set_pupils_late', write([1001]));
    expect(text, endsWith('Nothing was changed in Smartschool.'));
    expect(text, isNot(contains('Oeps')));
    expect(presence.calls, everyElement(isNot(_save)));
  });
}
