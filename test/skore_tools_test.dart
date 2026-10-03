/// `list_skore_classes`, `list_skore_courses` and `list_skore_teachers`
/// (#42), called over MCP on the real server, session and library, against
/// a fake Smartschool whose Skore serves the endpoints `SkoreService` reads,
/// in the shape of dartschool's anonymised captures, with fake names
/// (`test/support/fake_skore.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// What the tools say to an account without the rights, after the reason:
/// what it needs, and what to do, in the words of Claude Desktop.
const _rightsAndFix =
    'the rights for score management in Skore (Rapporten > Modellen and '
    'Puntenboeken), as a Skore administrator has';
const _fix =
    "ask the school's Smartschool administrator for them, or turn off "
    '"Skore-beheer" (SMARTSCHOOL_SKORE) in the Smartschool extension '
    'settings in Claude Desktop (Settings → Extensions), then restart Claude '
    'Desktop';

void main() {
  late FakeSmartschool server;
  late FakeSkore skore;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skore..loadSchool();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: skoreOptIn(session, SwitchState.on).offered,
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

  Future<String> courses(int classId) =>
      ok('list_skore_courses', {'class_id': classId});

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

    test('the reads in order, read-only and idempotent, before the writes '
        '(#43, #44)', () {
      expect(tools.keys, [
        'list_skore_classes',
        'list_skore_courses',
        'list_skore_teachers',
        'list_skore_gradebook_shares',
        'add_skore_teacher',
        'replace_skore_teacher',
        'share_skore_gradebook',
        'unshare_skore_gradebook',
      ]);
      for (final tool in tools.values.take(4)) {
        final annotations = tool.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: tool.name);
        expect(annotations.idempotentHint, isTrue, reason: tool.name);
        expect(annotations.openWorldHint, isTrue, reason: tool.name);
        expect(annotations.destructiveHint, isNot(true), reason: tool.name);
        expect(
          tool.description,
          contains(
            'Only for an account with the rights for score management in '
            'Skore; without them, the tool says so.',
          ),
          reason: tool.name,
        );
        expect(
          tool.description,
          contains('Reading changes nothing in Skore.'),
          reason: tool.name,
        );
      }
    });

    test('list_skore_classes and list_skore_teachers take an optional '
        'query', () {
      for (final name in ['list_skore_classes', 'list_skore_teachers']) {
        final schema = tools[name]!.inputSchema;
        expect(schema.required, isNull, reason: name);
        expect(schema.properties!.keys, ['query'], reason: name);
      }
      expect(
        tools['list_skore_classes']!.description,
        contains('Pass the class id to list_skore_courses'),
      );
    });

    test('list_skore_courses takes the class id from list_skore_classes, and '
        'says to name a course by its id, as codes are not unique', () {
      final tool = tools['list_skore_courses']!;
      expect(tool.inputSchema.required, ['class_id']);
      expect(tool.inputSchema.properties!['class_id'], {
        'type': 'integer',
        'description': 'The Skore class id, from list_skore_classes.',
        'minimum': 1,
      });
      expect(
        tool.description,
        contains(
          'Course codes are not unique within a class (a course and its '
          'sub-course can share one), so name a course by its course id.',
        ),
      );
      expect(
        tool.description,
        contains('the assignment id is also the id of its gradebook'),
      );
      expect(
        tool.description,
        contains(
          'An empty list means that the class has no course structure in '
          'Skore yet, or that no class has that id.',
        ),
      );
      expect(tool.description, contains('wie geeft wiskunde in 3B1?'));
    });
  });

  group('list_skore_classes', () {
    test('lists every class with its id, group and report model, in '
        'Skore\'s order; a class outside a group has none', () async {
      expect(
        await ok('list_skore_classes'),
        'Skore lists 6 classes in 3 report models:\n'
        '- 1B1 | class id 2376 | group 1B | model 1gr B-str.\n'
        '- 1B2 | class id 2378 | group 1B | model 1gr B-str.\n'
        '- 2B1 | class id 2368 | group 2B | model 1gr B-str.\n'
        '- 3B1 | class id 2450 | group 3B | model 2gr A-str.\n'
        '- 5WW1 | class id 2516 | group 5DG | model 3gr D-D/A\n'
        '- OKAN | class id 2600 | no group | model 3gr D-D/A',
      );
      expect(skore.calls, ['GET $fakeSkoreModelsPath']);
    });

    test('finds classes by part of their name or of their group\'s, '
        'ignoring case', () async {
      expect(
        await ok('list_skore_classes', {'query': '5ww'}),
        'Skore finds 1 of its 6 classes in 3 report models for "5ww":\n'
        '- 5WW1 | class id 2516 | group 5DG | model 3gr D-D/A',
      );
      // 5DG is the group of 5WW1.
      expect(
        await ok('list_skore_classes', {'query': '5DG'}),
        contains('- 5WW1 | class id 2516'),
      );
      final b1 = await ok('list_skore_classes', {'query': ' 1B '});
      expect(b1, startsWith('Skore finds 2 of its 6 classes'));
      expect(b1, contains('- 1B1 |'));
      expect(b1, contains('- 1B2 |'));
    });

    test('says when no class matches, and how to look', () async {
      expect(
        await ok('list_skore_classes', {'query': '7XY'}),
        'None of the 6 classes in 3 report models in Skore has "7XY" in the '
        'name of the class or its group. Look for a part of the name, such '
        'as 5WW, or leave out query to list them all.',
      );
    });

    test('says when Skore lists no classes at all', () async {
      skore.models.clear();
      expect(
        await ok('list_skore_classes'),
        'Skore lists no classes in its report models. A school without '
        'report models in Skore has none; an account without the rights for '
        'score management in Skore may also get an empty list.',
      );
    });
  });

  group('list_skore_courses', () {
    test('lists the rows of a class nested by depth: group headers, a '
        'course with several teachers, and two courses with the same code '
        'told apart by id', () async {
      expect(
        await courses(2516),
        'Skore class id 2516: 6 courses (3 without a teacher) and 2 group '
        'headers, in Skore\'s order; each row belongs to the nearest row '
        'above it with a smaller depth.\n'
        '- Vakken [Vak] | course id 1966 | code Vak | depth 0 | group header, '
        'cannot get a teacher\n'
        '  - Aardrijkskunde (1 uur) (5e j DG) [AARDR] | course id 2164 | code '
        'AARDR | depth 1 | teacher: Janssens, Jan (teacher id 1001, '
        'assignment 31882)\n'
        '  - Eye4Skills (2 uur) (3e graad) [PROJE] | course id 2142 | code '
        'PROJE | depth 1 | no teacher\n'
        '    - Project 1 (3e graad) [PROJE1] | course id 1840 | code PROJE1 | '
        'depth 2 | 3 teachers: Peeters, Piet (teacher id 1002, assignment '
        '34580); Dupré, Céline (teacher id 1003, assignment 34582); '
        "D'Hondt, Karel (teacher id 1004, assignment 34584)\n"
        '  - Toegepaste sociale- en gedragswetenschappen (6 uur) (5e j DG '
        '(5WW)) [T.SOGEWE] | course id 1776 | code T.SOGEWE | depth 1 | no '
        'teacher\n'
        '    - Toegepaste sociale- en gedragswetenschappen (/90) (5e j DG '
        '(5WW)) [T.SOGEWE] | course id 2676 | code T.SOGEWE | depth 2 | no '
        'teacher\n'
        '- Extra rapporten [Extra rapporten] | course id 1590 | code Extra '
        'rapporten | depth 0 | group header, cannot get a teacher\n'
        '  - Digitale vaardigheden [Digitale vaardigheden] | course id 1588 | '
        'code Digitale vaardigheden | depth 1 | teacher: Willems, Wim '
        '(teacher id 1005, assignment 34826)',
      );
      expect(skore.calls, ['GET $fakeSkoreOwnersPagePath']);
      expect(skore.requests.single.query, {'classID': '2516'});
    });

    test('answers "wie geeft wiskunde in 3B1?": the class by name, then its '
        'courses', () async {
      final classes = await ok('list_skore_classes', {'query': '3B1'});
      expect(classes, contains('- 3B1 | class id 2450 |'));

      final text = await courses(2450);

      expect(
        text,
        contains(
          '\n  - Wiskunde (5 uur) (3e j A) [WISK] | course id 3010 | code WISK '
          '| depth 1 | teacher: Maes, Mira (teacher id 1006, assignment '
          '40010)\n',
        ),
      );
      expect(text, startsWith('Skore class id 2450: 2 courses and 1 group '));
    });

    test('an empty class, and a class id Skore does not know: says that the '
        'class has no course structure, or that no class has the id', () async {
      const empty =
          'the class has no course structure in Skore yet (Skore links one '
          'under Koppeling), or no class has that id. Take the class id from '
          'list_skore_classes.';
      expect(
        await courses(2378),
        'Skore lists no courses for class id 2378: $empty',
      );
      expect(
        await courses(999999),
        'Skore lists no courses for class id 999999: $empty',
      );
    });

    test('accepts a whole number written with a decimal part, and refuses '
        'another number without asking Skore', () async {
      expect(
        await ok('list_skore_courses', {'class_id': 2516.0}),
        startsWith('Skore class id 2516:'),
      );
      skore.requests.clear();
      await error('list_skore_courses', {'class_id': 2516.5});
      await error('list_skore_courses', {'class_id': 0});
      expect(skore.requests, isEmpty);
    });
  });

  group('list_skore_teachers', () {
    test('lists the teachers Skore lets assign, with their ids, with only '
        'the read of getTeachers', () async {
      expect(
        await ok('list_skore_teachers'),
        'Skore lists 6 teachers that can be assigned:\n'
        "- D'Hondt, Karel | teacher id 1004\n"
        '- Dupré, Céline | teacher id 1003\n'
        '- Janssens, Jan | teacher id 1001\n'
        '- Maes, Mira | teacher id 1006\n'
        '- Peeters, Piet | teacher id 1002\n'
        '- Willems, Wim | teacher id 1005',
      );
      expect(skore.calls, ['POST $fakeSkoreOwnersRpcPath getTeachers']);
    });

    test('finds a teacher by name in any order, ignoring case and '
        'accents', () async {
      expect(
        await ok('list_skore_teachers', {'query': 'celine dupre'}),
        'Skore finds 1 of its 6 teachers for "celine dupre":\n'
        '- Dupré, Céline | teacher id 1003',
      );
      expect(
        await ok('list_skore_teachers', {'query': 'Vermeulen'}),
        'None of the 6 teachers that Skore can assign has "Vermeulen" in the '
        'name. Look for a part of the name, or leave out query to list them '
        'all.',
      );
    });
  });

  group('an account without the rights', () {
    final calls = {
      'list_skore_classes': <String, Object?>{},
      'list_skore_courses': <String, Object?>{'class_id': 2516},
      'list_skore_teachers': <String, Object?>{},
    };

    test('refused by Skore (HTTP 403): every tool says that the account has '
        'no rights for score management, which rights it needs and what to '
        'do, without quoting the page', () async {
      skore.refusal = SkoreRefusal.forbidden;

      for (final MapEntry(key: tool, value: arguments) in calls.entries) {
        expect(
          await error(tool, arguments),
          'This account has no rights for score management in Skore: Skore '
          'refused it its report management (Rapporten > Modellen). The '
          'Skore tools need $_rightsAndFix: $_fix.',
          reason: tool,
        );
      }
      expect(skore.calls, hasLength(3));
    });

    test('answered with a page instead of data, as such an account most '
        'likely is (dartschool#91): every tool says that the account usually '
        'lacks the rights, without quoting the page or calling it '
        'unexpected', () async {
      skore.refusal = SkoreRefusal.page;

      for (final MapEntry(key: tool, value: arguments) in calls.entries) {
        final text = await error(tool, arguments);
        expect(
          text,
          'Skore gave an answer the server could not use; usually the '
          'account lacks $_rightsAndFix. If so, $_fix. Otherwise try again '
          'in a moment; the technical details are in the server log.',
          reason: tool,
        );
        expect(text, isNot(contains(fakeSkoreNoAccessName)), reason: tool);
        expect(text, isNot(contains('Geen toegang')), reason: tool);
        expect(text, isNot(contains('unexpected')), reason: tool);
      }
    });
  });

  test('logs in again when the session expired, for a page and an RPC '
      'call', () async {
    await ok('list_skore_teachers');
    final logins = server.logins;

    server.expireSessionBefore(
      (request) => request.uri.path == fakeSkoreOwnersPagePath,
    );
    expect(await courses(2516), startsWith('Skore class id 2516:'));
    expect(server.logins, logins + 1);

    server.expireSessionBefore(
      (request) => request.uri.path == fakeSkoreOwnersRpcPath,
    );
    expect(await ok('list_skore_teachers'), contains('Willems, Wim'));
    expect(server.logins, logins + 2);
  });

  test('the tools only read: no other RPC method reaches Skore', () async {
    await ok('list_skore_classes');
    await courses(2516);
    await ok('list_skore_teachers', {'query': 'Peeters'});

    expect(
      [for (final request in skore.requests) ?request.rpc],
      ['getTeachers'],
    );
    expect(
      skore.requests.where((request) => request.method == 'POST'),
      hasLength(1),
    );
  });

  test('skoreOptIn offers its tools only when "Skore-beheer" is on', () {
    final session = SmartschoolSession(fakeExtensionSettings());
    final on = skoreOptIn(session, SwitchState.on);
    expect(on.setting, Setting.skore);
    expect(
      [for (final tool in on.offered) tool.definition.name],
      [
        'list_skore_classes',
        'list_skore_courses',
        'list_skore_teachers',
        'list_skore_gradebook_shares',
        'add_skore_teacher',
        'replace_skore_teacher',
        'share_skore_gradebook',
        'unshare_skore_gradebook',
      ],
    );
    for (final state in [SwitchState.off, SwitchState.unclear]) {
      final optIn = skoreOptIn(session, state);
      expect(optIn.offered, isEmpty, reason: state.name);
      expect(optIn.tools, hasLength(8), reason: state.name);
    }
  });
}
