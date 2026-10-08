/// `list_skore_gradebooks` and `read_skore_gradebook` (#140), called over
/// MCP on the real server, session and library, against a fake Smartschool
/// whose Skore gradebook serves the calls `SkoreGradebookService` makes, in
/// the shape of dartschool's captures (`test/support/fake_skore_gradebook.dart`).
/// The tools need no switch: they are the user's own gradebooks, which need
/// no extra rights.
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/skore/skore_gradebook_access.dart';
import 'package:smartschool_mcp/src/tools/list_skore_gradebooks_tool.dart';
import 'package:smartschool_mcp/src/tools/read_skore_gradebook_tool.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
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

/// What no gradebook text may say: the gradebook is not behind the switch
/// "Skore-beheer", and needs no extra rights.
final _adminWords = RegExp(
  r'Skore-beheer|SMARTSCHOOL_SKORE|rights|administrator|score management',
  caseSensitive: false,
);

const _schoolYears =
    'School years in Skore: 2026-2027 (workyear id 24, listed here), '
    '2025-2026 (workyear id 22), 2024-2025 (workyear id 20).';

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
        readSkoreGradebookTool(session),
      ],
    );
  });

  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    expect(text, isNot(matches(_adminWords)));
    return text;
  }

  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    expect(text, isNot(matches(_adminWords)));
    return text;
  }

  Future<String> list([Map<String, Object?>? arguments]) =>
      ok('list_skore_gradebooks', arguments);

  Future<String> read(int gradebookId, {int? workyearId}) => ok(
    'read_skore_gradebook',
    {'gradebook_id': gradebookId, 'workyear_id': ?workyearId},
  );

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
        'rights, nor of the user as a teacher (pupils sign in too)', () {
      expect(tools.keys, ['list_skore_gradebooks', 'read_skore_gradebook']);
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

    test('list_skore_gradebooks takes an optional school year and query; '
        'read_skore_gradebook a gradebook id and an optional school year', () {
      final listSchema = tools['list_skore_gradebooks']!.inputSchema;
      expect(listSchema.required, isNull);
      expect(listSchema.properties!.keys, ['workyear_id', 'query']);
      final readSchema = tools['read_skore_gradebook']!.inputSchema;
      expect(readSchema.required, ['gradebook_id']);
      expect(readSchema.properties!.keys, ['gradebook_id', 'workyear_id']);
      expect(readSchema.properties!['gradebook_id'], {
        'type': 'integer',
        'description': 'The gradebook id, from list_skore_gradebooks.',
        'minimum': 1,
      });
      expect(
        tools['list_skore_gradebooks']!.description,
        contains('Pass the gradebook id to read_skore_gradebook'),
      );
    });
  });

  group('list_skore_gradebooks', () {
    test('lists the gradebooks of Skore\'s current school year in Skore\'s '
        'order, each once, with the school years Skore offers; one '
        'getNavigation as the user, without a school year', () async {
      expect(
        await list(),
        'The user has 4 gradebooks of their own in Skore for school year '
        '2026-2027 (workyear id 24), in Skore\'s order:\n'
        '- 6EWI | Informaticawetenschappen (2 uur) (6e j DO) | gradebook id '
        '32508\n'
        '- 6WEWI2 | Informaticawetenschappen (2 uur) (6e j DO) | gradebook '
        'id 32504\n'
        '- 5WW1 | Digitale vaardigheden | gradebook id 34826\n'
        '- 5WW1 | Project 1 (3e graad) | gradebook id 34582\n'
        '$_schoolYears',
      );
      expect(skore.calls, ['getNavigation']);
      final call = skore.requests.single;
      expect(call.params, [fakeSkoreGradebookUser, 0]);
      expect(call.session['teacher'], fakeSkoreGradebookUser);
      expect(call.session['restriction'], 0);
    });

    test('an earlier school year by its workyear_id', () async {
      expect(
        await list({'workyear_id': 22}),
        'The user has 1 gradebook of their own in Skore for school year '
        '2025-2026 (workyear id 22), in Skore\'s order:\n'
        '- 5BW | Informaticawetenschappen (2 uur) (5e j DG) | gradebook id '
        '28998\n'
        'School years in Skore: 2026-2027 (workyear id 24), 2025-2026 '
        '(workyear id 22, listed here), 2024-2025 (workyear id 20).',
      );
      expect(skore.calls, ['getNavigation wy=22']);
    });

    test('a school year without gradebooks: a sentence naming it, not an '
        'error', () async {
      expect(
        await list({'workyear_id': 20}),
        'The user has no gradebooks of their own in Skore for school year '
        '2024-2025 (workyear id 20).\n'
        'School years in Skore: 2026-2027 (workyear id 24), 2025-2026 '
        '(workyear id 22), 2024-2025 (workyear id 20, listed here).',
      );
    });

    test('an account without any gradebook of its own (a pupil, say): the '
        'same sentence', () async {
      skore.gradebooks.clear();
      expect(
        await list(),
        'The user has no gradebooks of their own in Skore for school year '
        '2026-2027 (workyear id 24).\n'
        '$_schoolYears',
      );
    });

    test('query keeps the gradebooks whose class or course holds every word, '
        'ignoring case and accents', () async {
      expect(
        await list({'query': '5ww'}),
        'Skore finds 2 for "5ww" among the user\'s 4 gradebooks for school '
        'year 2026-2027 (workyear id 24), in Skore\'s order:\n'
        '- 5WW1 | Digitale vaardigheden | gradebook id 34826\n'
        '- 5WW1 | Project 1 (3e graad) | gradebook id 34582\n'
        '$_schoolYears',
      );
      expect(
        await list({'query': 'informatica 6e'}),
        startsWith('Skore finds 2 for "informatica 6e" among'),
      );
      expect(
        await list({'query': 'wiskunde'}),
        'None of the user\'s 4 gradebooks in Skore for school year 2026-2027 '
        '(workyear id 24) has "wiskunde" in the name of its class or course. '
        'Look for a part of the name, such as 5WW or Wiskunde, or leave out '
        'query to list them all.\n'
        '$_schoolYears',
      );
    });

    test('the gradebooks are read once per school year for several calls in '
        'a session', () async {
      await list();
      await list({'query': '5ww'});
      await list({'workyear_id': 24});
      await list({'workyear_id': 22});
      await list({'workyear_id': 22, 'query': 'bw'});
      await read(32508);
      await read(28998, workyearId: 22);
      expect(skore.calls.where((c) => c.startsWith('getNavigation')), [
        'getNavigation',
        'getNavigation wy=22',
      ]);
    });

    test('a school year Skore does not offer: an error that names the ones it '
        'offers', () async {
      expect(
        await error('list_skore_gradebooks', {'workyear_id': 99}),
        'Skore\'s gradebook cannot take workyear_id 99: not a school year '
        'Skore offers (it offers 24 2026-2027, 22 2025-2026, 20 2024-2025). '
        'Take a workyear id from the school years list_skore_gradebooks '
        'lists, or leave out workyear_id for Skore\'s current school year.',
      );
      expect(skore.calls, ['getNavigation wy=99']);
    });

    test('a workyear_id that is not positive is refused before anything is '
        'sent', () async {
      final text = await error('list_skore_gradebooks', {'workyear_id': 0});
      expect(text, contains('workyear_id'));
      expect(skore.requests, isEmpty);
    });
  });

  group('read_skore_gradebook', () {
    test(
      'a gradebook with its periods (open, closing time, active, Skore\'s '
      'note), its pupils and whether the user may change it; init and '
      'getGradebookContext for its school year, after the gradebooks',
      () async {
        expect(
          await read(32508),
          'Gradebook id 32508: Informaticawetenschappen (2 uur) (6e j DO), '
          'class 6EWI, school year 2026-2027 (workyear id 24).\n'
          'Skore lets the user change it.\n'
          '1 period, in Skore\'s order; only an open period takes grades, and '
          'Skore opens the gradebook on DW1 (active):\n'
          '- DW1 | period id 1704 | open, closes '
          '${_time('2026-12-18T20:00:00+0100')} | active | note: Open van '
          '2026-09-18 15:30 tot en met 2026-12-18 20:00. Vul hier je punten '
          'voor Dagelijks werk (periode september- oktober) in!\n'
          '3 pupils, in Skore\'s order:\n'
          '- 1. Aerts, An | pupil id 1201\n'
          '- 2. Claes, Bart | pupil id 1202\n'
          '- 3. Dupont, Chloé | pupil id 1203',
        );
        expect(skore.calls, [
          'getNavigation',
          'init wy=24',
          'getGradebookContext wy=24',
        ]);
        expect(skore.requests[1].params, [
          ['2264'],
          ['32508'],
          fakeSkoreGradebookUser,
          ['176', '472', '2440'],
          0,
          0,
        ]);
        expect(skore.requests[2].params, [
          ['176', '472', '2440'],
          ['2264'],
          ['32508'],
          fakeSkoreGradebookUser,
          1704,
          0,
          24,
        ]);
      },
    );

    test('a gradebook of an earlier school year: closed periods, the last '
        'one active, pupils without a class number, one inactive', () async {
      expect(
        await read(28998, workyearId: 22),
        'Gradebook id 28998: Informaticawetenschappen (2 uur) (5e j DG), '
        'class 5BW, school year 2025-2026 (workyear id 22).\n'
        'Skore lets the user change it, but none of its periods is open, so '
        'it takes no grades now.\n'
        '3 periods, in Skore\'s order; only an open period takes grades, and '
        'Skore opens the gradebook on DW5 (active):\n'
        '- DW1 | period id 1446 | closed, closing time '
        '${_time('2025-12-18T20:00:00+0100')} | note: Vul hier je punten '
        'voor Dagelijks werk (periode september- oktober) in!\n'
        '- DW4 | period id 1608 | closed, closing time '
        '${_time('2026-04-02T23:00:00+0200')} | note: Vul hier je punten '
        'voor Dagelijks werk (periode maart) in!\n'
        '- DW5 | period id 1610 | closed, closing time '
        '${_time('2026-06-30T00:00:00+0200')} | active | note: Vul hier je '
        'punten voor Dagelijks werk (periode april - juni) in!\n'
        '2 pupils (1 inactive), in Skore\'s order:\n'
        '- Maes, Lotte | pupil id 1301\n'
        '- Verbeke, Fien | pupil id 1302 | inactive (greyed out in Skore)',
      );
      expect(skore.calls, [
        'getNavigation wy=22',
        'init wy=22',
        'getGradebookContext wy=22',
      ]);
      expect(skore.requests.last.params[4], 1610);
    });

    test('without workyear_id, a gradebook of a school year listed before is '
        'found in memory', () async {
      await list({'workyear_id': 22});
      expect(await read(28998), startsWith('Gradebook id 28998: '));
      expect(skore.calls, [
        'getNavigation wy=22',
        'init wy=22',
        'getGradebookContext wy=22',
      ]);
    });

    test('an id not in memory reads the gradebooks again, and finds one made '
        'since', () async {
      await list();
      skore.gradebooks.add(
        FakeSkoreOwnGradebook(
          workyear: FakeSkoreWorkyear.y2026,
          id: 35010,
          modelId: 176,
          modelName: '3gr D-D/A',
          groupId: 492,
          groupName: '5DG',
          classId: 2516,
          className: '5WW1',
          courseId: 1590,
          course: 'Wiskunde (4 uur)',
          periods: [...fakeSkoreGradebook6EWI().periods],
        ),
      );
      expect(
        await read(35010),
        startsWith(
          'Gradebook id 35010: Wiskunde (4 uur), class 5WW1, school year '
          '2026-2027 (workyear id 24).\n',
        ),
      );
      expect(skore.calls.where((c) => c.startsWith('getNavigation')), [
        'getNavigation',
        'getNavigation',
      ]);
      // Found from now on.
      await read(35010);
      expect(
        skore.calls.where((c) => c.startsWith('getNavigation')),
        hasLength(2),
      );
    });

    test('an unknown id, after the gradebooks were read again: an error that '
        'says to take it from list_skore_gradebooks', () async {
      await list();
      expect(
        await error('read_skore_gradebook', {'gradebook_id': 99999}),
        'None of the user\'s own gradebooks in Skore of school year 2026-2027 '
        '(workyear id 24) has gradebook id 99999. Take the gradebook id from '
        'list_skore_gradebooks; for a gradebook of an earlier school year, '
        'pass its workyear_id too, as list_skore_gradebooks lists the school '
        'years.',
      );
      expect(skore.calls, ['getNavigation', 'getNavigation']);
      expect(
        await error('read_skore_gradebook', {
          'gradebook_id': 32508,
          'workyear_id': 22,
        }),
        'None of the user\'s own gradebooks in Skore of school year 2025-2026 '
        '(workyear id 22) has gradebook id 32508. Take the gradebook id from '
        'list_skore_gradebooks with workyear_id 22.',
      );
    });

    test('a gradebook of an earlier school year, without its workyear_id and '
        'not listed before: the error says to pass it', () async {
      expect(
        await error('read_skore_gradebook', {'gradebook_id': 28998}),
        contains('pass its workyear_id too'),
      );
      // Nothing was in memory: one read of Skore's current school year.
      expect(skore.calls, ['getNavigation']);
    });

    test('read-only for the user, in coordinator mode, or without periods '
        '(then Skore is not asked)', () async {
      final book = skore.gradebooks.firstWhere((g) => g.id == 32504);
      book.writable = false;
      expect(
        await read(32504),
        contains(
          '\nSkore opens it read-only for the user: the user may not change '
          'it.\n',
        ),
      );
      book.coordinator = true;
      expect(
        await read(32504),
        contains(
          '\nSkore opens it read-only for the user, in coordinator '
          'mode.\n',
        ),
      );
      book.periods.clear();
      skore.requests.clear();
      expect(
        await read(32504),
        'Gradebook id 32504: Informaticawetenschappen (2 uur) (6e j DO), '
        'class 6WEWI2, school year 2026-2027 (workyear id 24).\n'
        'It has no periods yet, so it takes no grades; Skore was not asked '
        'whether the user may change it.\n'
        '2 pupils, in Skore\'s order:\n'
        '- 1. Goossens, Emma | pupil id 1211\n'
        '- 2. Hermans, Finn | pupil id 1212',
      );
      expect(skore.calls, ['init wy=24']);
    });

    test('a gradebook without pupils', () async {
      skore.gradebooks.firstWhere((g) => g.id == 34826).pupils.clear();
      expect(await read(34826), endsWith('\nNo pupils.'));
    });
  });

  group('an answer Skore\'s gradebook cannot use', () {
    test('an error page, from the gradebooks or from one gradebook: an error '
        'that says to try again and that a pupil\'s account may get it, '
        'without the page', () async {
      const expected =
          'Skore\'s gradebook gave an answer the server could not use. Try '
          'again in a moment; the technical details are in the server log. '
          'An account without gradebooks of its own in Skore, such as a '
          'pupil\'s, may get this answer too.';
      skore.answers['getNavigation'] = (
        status: 200,
        body: '<html><body>Lena Vermeulen heeft geen toegang.</body></html>',
      );
      expect(await error('list_skore_gradebooks'), expected);
      expect(
        await error('read_skore_gradebook', {'gradebook_id': 32508}),
        expected,
      );
      skore.answers.clear();
      for (final method in ['init', 'getGradebookContext']) {
        skore.answers[method] = (status: 500, body: 'Oeps');
        expect(
          await error('read_skore_gradebook', {'gradebook_id': 32508}),
          expected,
          reason: method,
        );
        skore.answers.clear();
      }
    });

    test('a redirect, as Skore sends a request it refuses elsewhere, and an '
        'answer in another shape: the same error', () async {
      skore.answers['getNavigation'] = (status: 302, body: '');
      expect(
        await error('list_skore_gradebooks'),
        startsWith(
          'Skore\'s gradebook gave an answer the server could not '
          'use.',
        ),
      );
      skore.answers['getNavigation'] = (
        status: 200,
        body:
            '{"result":{"navigation":null,"workyears":[["24","2026-2027"]],'
            '"currentWorkyear":"24"},"session":1}',
      );
      expect(
        await error('list_skore_gradebooks'),
        startsWith(
          'Skore\'s gradebook gave an answer the server could not '
          'use.',
        ),
      );
    });

    test('a read that failed is tried again on the next call', () async {
      skore.unusable = true;
      await error('list_skore_gradebooks');
      skore.unusable = false;
      expect(await list(), startsWith('The user has 4 gradebooks'));
      expect(skore.calls, ['getNavigation', 'getNavigation']);
    });
  });

  group('skoreGradebookToolError', () {
    test('a user id the gradebook calls cannot be built from: a short '
        'message', () {
      expect(
        skoreGradebookToolError(
          const SmartschoolParsingError(
            'Could not read the platform and the user ID from '
            'authenticatedUser.id "x".',
          ),
        )?.message,
        'Smartschool did not give the id of the signed-in user in the form '
        'Skore\'s gradebook needs, so the gradebook could not be read. Try '
        'again in a moment; the technical details are in the server log.',
      );
    });

    test('leaves alone what is not the library\'s answer about the '
        'gradebook: a ToolError, another ArgumentError, a save Skore did not '
        'confirm (for the write tools to report)', () {
      for (final error in <Object>[
        const ToolError('no such gradebook'),
        ArgumentError.value('x', 'method', 'not one the service calls'),
        ArgumentError('no name'),
        const SmartschoolSkoreSaveUnconfirmedError('not confirmed'),
        const SmartschoolSessionExpiredError('expired'),
      ]) {
        expect(skoreGradebookToolError(error), isNull, reason: '$error');
      }
    });
  });
}
