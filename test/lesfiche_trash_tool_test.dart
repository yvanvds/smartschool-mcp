/// `trash_lesfiches` (#116), called over MCP on the real server, session
/// and library, against a fake Smartschool whose Lesfiches module moves
/// lesfiches to its trash as dartschool's captures show it
/// (`test/lesson_content_write_test.dart` there, dartschool#129: one
/// `POST lesson-content/trash/bulk` with each lesfiche's id, kind and
/// platform, answered with `{"exceptions":[]}`, and a lesfiche in the trash
/// already with a bare `500`), after which the list leaves the lesfiches
/// out and their detail is still served (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_lesfiches_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The lesson lesfiche and the assignment lesfiche of dartschool's capture
/// of the detail, both named `Lussen`.
final _lesson = fakeLesficheDetailLesson;
final _assignment = fakeLesficheDetailAssignment;

/// Their lines in a result, as `list_lesfiches` shows them, with their
/// courses counted.
final _lessonLine =
    '- lesson | Lussen | no labels | 1 course | visible | changed '
    '2026-10-05 | id ${_lesson.id}';
final _assignmentLine =
    '- assignment KT Kleine Taak | Lussen | no labels | 1 course | visible | '
    'changed 2026-10-05 | id ${_assignment.id}';

/// The move of [lesfiches] as the web client sends it, each with its id,
/// kind and platform.
Map<String, Object?> _moveOf(List<FakeLesfiche> lesfiches) => {
  'lessonContent': [
    for (final lesfiche in lesfiches)
      {'id': lesfiche.id, 'type': lesfiche.type, 'platformId': 4069},
  ],
};

/// An id that names none of the fake's lesfiches.
const _unknown = 'b0000000-0000-4000-8000-000000000099';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner
      ..loadCaptures()
      ..loadLesfiches()
      ..loadLesficheDetails();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        readLesficheTool(session),
        createLesficheTool(session),
        trashLesfichesTool(session),
      ],
    );
  });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// Calls `trash_lesfiches` for the lesfiches [ids].
  Future<String> trash(List<String> ids) =>
      ok('trash_lesfiches', {'lesfiches': ids});

  /// Calls `trash_lesfiches` for the lesfiches [ids], for an error.
  Future<String> refused(List<String> ids) =>
      error('trash_lesfiches', {'lesfiches': ids});

  /// Opens the session (the session check reads the course list), and
  /// forgets the requests so far.
  Future<void> openSession() async {
    await ok('list_lesfiches', {});
    server.requests.clear();
    planner.requests.clear();
  }

  /// The bodies of the moves to the trash that reached the Lesfiches
  /// module.
  List<Object?> moves() => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == fakeLesficheTrashPath)
        request.data,
  ];

  /// How many moves to the trash reached the fake Smartschool, also those
  /// it refused because the session was not accepted.
  int sentMoves() => server.requests
      .where((request) => request == 'POST $fakeLesficheTrashPath')
      .length;

  /// The lesfiches `list_lesfiches` lists now, both kinds.
  Future<String> listed() => ok('list_lesfiches', {'type': 'all'});

  group('the tool is listed', () {
    late Map<String, Tool> tools;

    setUp(() async {
      tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
    });

    test('as a write Claude Desktop asks approval for, which a second call '
        'does not change: idempotent', () {
      final tool = tools['trash_lesfiches']!;
      expect(tool.toolAnnotations!.readOnlyHint, isFalse);
      expect(tool.toolAnnotations!.destructiveHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isTrue);
      expect(tool.toolAnnotations!.openWorldHint, isTrue);
      expect(tool.inputSchema.required, ['lesfiches']);
      expect(tool.inputSchema.properties!.keys, ['lesfiches']);
      expect(
        tool.description,
        allOf(
          contains('by the ids list_lesfiches shows: 1 to 20 in one call'),
          contains(
            'It is a move, not a deletion: the user can restore them from '
            'the trash in the Lesfiches module itself. This tool cannot '
            'restore anything, nor delete anything for good.',
          ),
          contains(
            'A lesson planned from one of them earlier stays in the '
            'planner: the planner copied the lesfiche when it was planned.',
          ),
          contains('show the user each lesfiche by its name and kind'),
          contains(
            'only call this tool after the user has explicitly confirmed '
            'it; then call it once, with all of them',
          ),
          contains('a lesfiche that is in the trash already is not listed'),
        ),
      );
    });

    test('create_lesfiche and read_lesfiche point to it', () {
      expect(
        tools['create_lesfiche']!.description,
        contains(
          'with its id for plan_lesfiche, read_lesfiche and edit_lesfiche, '
          'which changes it later (its weblinks and attachments change with '
          'set_lesfiche_weblink, add_lesfiche_attachments and the like), and '
          'trash_lesfiches, which moves it to the trash.',
        ),
      );
      expect(
        tools['read_lesfiche']!.description,
        contains(
          'by the ids shown here; trash_lesfiches moves it to the trash.',
        ),
      );
    });
  });

  group('trash_lesfiches', () {
    test('moves a lesson and an assignment lesfiche in one move: reads the '
        'list first, sends each once with its kind and platform, and the '
        'list leaves them out after; their detail is still read', () async {
      await openSession();

      final text = await trash([
        _lesson.id,
        _assignment.id.toUpperCase(),
        _lesson.id,
      ]);

      expect(server.requests, [
        'GET $fakeLesfichesPath',
        'POST $fakeLesficheTrashPath',
      ], reason: 'the list without the course names, then one move');
      expect(planner.writes, ['POST $fakeLesficheTrashPath']);
      expect(moves(), [
        _moveOf([_lesson, _assignment]),
      ]);
      expect(
        text,
        'Moved 2 lesfiches to the trash of the Lesfiches module:\n'
        '$_lessonLine\n'
        '$_assignmentLine\n'
        'list_lesfiches no longer lists them. The user can restore them from '
        'the trash in the Lesfiches module itself; this server cannot '
        'restore them, nor delete them for good. A lesson planned from one '
        'of them earlier stays in the planner.',
      );
      expect(planner.trashedLesfiches, {_lesson.id, _assignment.id});

      final list = await listed();
      expect(list, isNot(contains(_lesson.id)));
      expect(list, isNot(contains(_assignment.id)));
      expect(list, contains(fakeLesficheLussen.id));
      expect(
        await ok('read_lesfiche', {'lesfiche': _lesson.id}),
        contains('\nName: Lussen\n'),
      );
    });

    test('undoes a lesfiche made with create_lesfiche, by the id its result '
        'gives; a second call finds it no longer listed and sends '
        'nothing', () async {
      final made = await ok('create_lesfiche', {'name': 'Test: lussen'});
      final id = fakeNewLesficheId(1);
      expect(made, contains('Its id is $id: '));
      expect(made, contains('Move it to the trash with trash_lesfiches.'));

      expect(
        await trash([id]),
        'Moved 1 lesfiche to the trash of the Lesfiches module:\n'
        '- lesson | Test: lussen | no labels | no course | visible | changed '
        '2026-10-05 | id $id\n'
        'list_lesfiches no longer lists it. The user can restore it from the '
        'trash in the Lesfiches module itself; this server cannot restore '
        'it, nor delete it for good. A lesson planned from it earlier stays '
        'in the planner.',
      );
      expect(
        await ok('list_lesfiches', {'query': 'test'}),
        isNot(contains(id)),
      );

      expect(
        await refused([id]),
        'You have no lesfiche with id $id: list_lesfiches does not list it. '
        'A lesfiche that is in the trash already is not listed, nor is one '
        'that no longer exists. Take the ids from list_lesfiches (type all '
        'lists both kinds). Nothing was sent.',
      );
      expect(planner.writes, [
        'POST ${fakeLesficheCreatePath()}',
        'POST $fakeLesficheTrashPath',
      ]);
    });

    test('refuses, after reading the list but before anything is sent, ids '
        'that name no listed lesfiche: a lesfiche in the trash is not '
        'listed', () async {
      planner.trashedLesfiches.add(fakeLesficheGame.id);
      await openSession();

      expect(
        await refused([_lesson.id, fakeLesficheGame.id, _unknown]),
        'You have no lesfiches with the ids ${fakeLesficheGame.id}, '
        '$_unknown: list_lesfiches does not list them. A lesfiche that is in '
        'the trash already is not listed, nor is one that no longer exists. '
        'Take the ids from list_lesfiches (type all lists both kinds), and '
        'check with the user which lesfiches are meant: the others were not '
        'moved either. Nothing was sent.',
      );
      expect(server.requests, ['GET $fakeLesfichesPath']);
      expect(planner.writes, isEmpty);
      expect(planner.trashedLesfiches, {fakeLesficheGame.id});
    });

    test('refuses, before anything is sent, an item that is not the id of a '
        'lesfiche', () async {
      expect(
        await refused([_lesson.id, 'Lussen!']),
        'item 2 of lesfiches must be the id of a lesfiche as list_lesfiches '
        'shows it, like b0000000-0000-4000-8000-000000000001; "Lussen!" is '
        'not. Nothing was sent.',
      );
      expect(server.requests, isEmpty, reason: 'not even a login');
    });

    test('refuses, after reading the list, a lesfiche of a kind the library '
        'cannot move', () async {
      const id = 'b0000000-0000-4000-8000-000000000021';
      planner.lesfiches.add(
        const FakeLesfiche(
          id: id,
          name: 'Methode les 1',
          type: 'method-lessons',
        ),
      );

      expect(
        await refused([_lesson.id, id]),
        'The lesfiche "Methode les 1" (id $id) is of the kind '
        '"method-lessons", which this server cannot move to the trash: only '
        'lesson and assignment lesfiches. The user moves it to the trash in '
        'the Lesfiches module itself. Nothing was sent.',
      );
      expect(planner.writes, isEmpty);
    });

    test('exceptions in the answer: maybe moved, some or all, with '
        'list_lesfiches to check which are still listed', () async {
      planner.lesficheTrashExceptions[_lesson.id] = {
        'status': 403,
        'title': 'Forbidden',
        'detail': '',
      };

      expect(
        await refused([_lesson.id, _assignment.id]),
        'The 2 lesfiches (the lesson lesfiche "Lussen" and the assignment '
        'lesfiche "Lussen") may or may not have been moved to the trash: it '
        'was sent, but the Lesfiches module did not confirm it. Some of them '
        'may have been moved, and others not. Do not call trash_lesfiches '
        'again for it. First list the lesfiches with list_lesfiches (type '
        'all) to see which are still listed: a lesfiche in the trash is not '
        'listed. Then tell the user what you found.',
      );
      expect(planner.writes, ['POST $fakeLesficheTrashPath'], reason: 'once');

      final list = await listed();
      expect(list, contains(_lesson.id));
      expect(list, isNot(contains(_assignment.id)));
    });

    test('a bare 500 (the lesfiche was moved to the trash after the list was '
        'read, seen live) or a move whose answer does not arrive: maybe '
        'moved, with list_lesfiches to check it', () async {
      const notConfirmed =
          'may or may not have been moved to the trash: it was sent, but the '
          'Lesfiches module did not confirm it. Do not call trash_lesfiches '
          'again for it. First list the lesfiches with list_lesfiches (type '
          'all) to see whether it is still listed: a lesfiche in the trash is '
          'not listed. Then tell the user what you found.';
      planner.beforeAnswer = (method, path) {
        if (method == 'POST' && path == fakeLesficheTrashPath) {
          planner.trashedLesfiches.add(_lesson.id);
        }
      };

      expect(
        await refused([_lesson.id]),
        'The lesson lesfiche "Lussen" $notConfirmed',
      );

      planner
        ..beforeAnswer = null
        ..lostAnswers.add(fakeLesficheTrashPath);
      expect(
        await refused([_assignment.id]),
        'The assignment lesfiche "Lussen" $notConfirmed',
      );
      expect(planner.writes, [
        'POST $fakeLesficheTrashPath',
        'POST $fakeLesficheTrashPath',
      ], reason: 'each sent once');
      expect(planner.trashedLesfiches, {_lesson.id, _assignment.id});
    });

    test('the module refuses the move with a bare 400, or the list cannot be '
        'read: none was moved', () async {
      planner.failing[fakeLesficheTrashPath] = 400;

      expect(
        await refused([_lesson.id, _assignment.id]),
        'The Lesfiches module refused the move of the lesson lesfiche '
        '"Lussen" and the assignment lesfiche "Lussen" to the trash (HTTP '
        '400), without saying why. None of the lesfiches was moved to the '
        'trash.',
      );

      planner.failing[fakeLesfichesPath] = 500;
      expect(
        await refused([_lesson.id]),
        'The Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log. The lesfiche was not moved to the trash.',
      );
      expect(planner.writes, ['POST $fakeLesficheTrashPath']);
      expect(planner.trashedLesfiches, isEmpty);
    });

    test('Smartschool refuses the session for the move: the library logs in '
        'again and sends it once more, as a read, and the lesfiches are '
        'moved once', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' &&
            request.uri.path == fakeLesficheTrashPath,
      );

      expect(
        await trash([_lesson.id, _assignment.id]),
        startsWith('Moved 2 lesfiches to the trash of the Lesfiches module:\n'),
      );
      expect(sentMoves(), 2, reason: 'the refused one and one');
      expect(planner.writes, [
        'POST $fakeLesficheTrashPath',
      ], reason: 'moved once');
      expect(moves(), [
        _moveOf([_lesson, _assignment]),
      ]);
      expect(server.logins, 2);
      expect(planner.trashedLesfiches, {_lesson.id, _assignment.id});
    });
  });
}
