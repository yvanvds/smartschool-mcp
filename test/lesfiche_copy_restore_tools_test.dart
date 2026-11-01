/// `duplicate_lesfiches`, `list_trashed_lesfiches` and `restore_lesfiches`
/// (#189), called over MCP on the real server, session and library, against
/// a fake Smartschool whose Lesfiches module copies lesfiches, lists its
/// trash and restores from it as dartschool's captures show it
/// (dartschool#227: `POST lesson-content/duplicate/bulk` and
/// `restore/bulk` with the body of the trash, answered keyed by each
/// lesfiche as sent, and `GET lesson-content/trashed`; a lesfiche in the
/// trash gets a `403` for a copy, one not in it a `404` for a restore;
/// `test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/duplicate_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/list_trashed_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/restore_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/trash_lesfiches_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The lesson lesfiche and the assignment lesfiche of dartschool's capture
/// of the detail, both named `Lussen`, with a weblink and an attachment.
final _lesson = fakeLesficheDetailLesson;
final _assignment = fakeLesficheDetailAssignment;

/// The ids of the first and second copy the fake makes.
final _copy1 = fakeNewLesficheId(1);
final _copy2 = fakeNewLesficheId(2);

/// The lines of the lesfiches in a result of a bulk write (no course
/// names).
final _lessonLine =
    '- lesson | Lussen | no labels | 1 course | visible | changed '
    '2026-10-05 | id ${_lesson.id}';
final _assignmentLine =
    '- assignment KT Kleine Taak | Lussen | no labels | 1 course | visible | '
    'changed 2026-10-05 | id ${_assignment.id}';

/// The body of a bulk write of [lesfiches], each with its id, kind and
/// platform, as the web client sends it.
Map<String, Object?> _bulkOf(List<FakeLesfiche> lesfiches) => {
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
        duplicateLesfichesTool(session),
        trashLesfichesTool(session),
        listTrashedLesfichesTool(session),
        restoreLesfichesTool(session),
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

  /// Opens the session (the session check reads the course list), and
  /// forgets the requests so far.
  Future<void> openSession() async {
    await ok('list_lesfiches', {});
    server.requests.clear();
    planner.requests.clear();
  }

  /// The bodies of the writes to [path] that reached the Lesfiches module.
  List<Object?> bodies(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
  ];

  /// The lesfiches `list_lesfiches` lists now, both kinds.
  Future<String> listed() => ok('list_lesfiches', {'type': 'all'});

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

    test('duplicate_lesfiches: a write Claude Desktop asks approval for, '
        'that a second call repeats (more copies), for 1 to 20 ids', () {
      final tool = tools['duplicate_lesfiches']!;
      expect(tool.toolAnnotations!.readOnlyHint, isFalse);
      expect(tool.toolAnnotations!.destructiveHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isFalse);
      expect(tool.toolAnnotations!.openWorldHint, isTrue);
      expect(tool.inputSchema.required, ['lesfiches']);
      expect(tool.inputSchema.properties!.keys, ['lesfiches']);
      expect(
        tool.description,
        allOf(
          contains('by the ids list_lesfiches shows: 1 to 20 in one call'),
          contains('named after the lesfiche with " - kopie" behind it'),
          contains(
            'A lesfiche in the trash cannot be copied: restore it first with '
            'restore_lesfiches.',
          ),
          contains('never call it again for a lesfiche that was copied'),
        ),
      );
    });

    test('list_trashed_lesfiches: a read', () {
      final tool = tools['list_trashed_lesfiches']!;
      expect(tool.toolAnnotations!.readOnlyHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isTrue);
      expect(tool.inputSchema.properties!.keys, ['query']);
      expect(
        tool.description,
        allOf(
          contains('its id for restore_lesfiches'),
          contains('can be restored within 100 days'),
        ),
      );
    });

    test('restore_lesfiches: a write Claude Desktop asks approval for, that '
        'a second call does not change', () {
      final tool = tools['restore_lesfiches']!;
      expect(tool.toolAnnotations!.readOnlyHint, isFalse);
      expect(tool.toolAnnotations!.destructiveHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isTrue);
      expect(tool.inputSchema.required, ['lesfiches']);
      expect(
        tool.description,
        allOf(
          contains('by the ids list_trashed_lesfiches shows: 1 to 20'),
          contains('Use it to undo trash_lesfiches'),
        ),
      );
    });
  });

  test('a lesfiche is copied, the copy moved to the trash, found there and '
      'restored, with Claude seeing each step', () async {
    final copied = await ok('duplicate_lesfiches', {
      'lesfiches': [_lesson.id],
    });
    expect(
      copied,
      'Made 1 copy in the own library of the Lesfiches module:\n'
      '- lesson | Lussen - kopie | no labels | 1 course | visible | id '
      '$_copy1 (a copy of id ${_lesson.id})\n'
      'Each copy has the icon, info, visibility, courses, labels, learning '
      'goals, weblinks and attachments of its lesfiche. Change it with '
      'edit_lesfiche (its name, say) and the other lesfiche tools by its id; '
      'read_lesfiche shows it in full. Do not call duplicate_lesfiches again '
      'for these lesfiches: it would make more copies.',
    );
    expect(await listed(), contains('| Lussen - kopie |'));
    final read = await ok('read_lesfiche', {'lesfiche': _copy1});
    expect(read, contains('\nName: Lussen - kopie\n'));
    expect(read, contains('Oefeningen'));
    expect(read, contains('lussen.txt'));

    await ok('trash_lesfiches', {
      'lesfiches': [_copy1],
    });
    expect(
      await ok('list_trashed_lesfiches', {}),
      '1 lesfiche in the trash of the Lesfiches module, most recently moved '
      'first:\n'
      'lesson | Lussen - kopie | no labels | informatica | visible | in the '
      'trash since 2026-11-01 | id $_copy1\n'
      'The Lesfiches module says a lesfiche in its trash can be restored '
      'within 100 days. restore_lesfiches takes one back into the library, '
      'by its id.',
    );

    expect(
      await ok('restore_lesfiches', {
        'lesfiches': [_copy1],
      }),
      'Restored 1 lesfiche from the trash into the own library of the '
      'Lesfiches module:\n'
      '- lesson | Lussen - kopie | no labels | 1 course | visible | changed '
      '2026-11-01 | id $_copy1\n'
      'list_lesfiches lists it again, and it can be changed, copied and '
      'planned as before.',
    );
    expect(await listed(), contains(_copy1));
    expect(
      await ok('list_trashed_lesfiches', {}),
      'The trash of the Lesfiches module is empty.',
    );
    expect(planner.writes, [
      'POST $fakeLesficheDuplicatePath',
      'POST $fakeLesficheTrashPath',
      'POST $fakeLesficheRestorePath',
    ]);
  });

  group('duplicate_lesfiches', () {
    test('copies a lesson and an assignment in one write, each once, with '
        'the labels, goals, weblinks and attachments of the '
        'lesfiche', () async {
      final labelled = _lesson.withChanges(
        labels: ['JAAR 6'],
        ownLabels: ['Lussen'],
        goals: [
          {'id': 'g1', 'leerplanId': 'l1', 'type': 'eindtermen'},
        ],
      );
      planner.lesfiches[planner.lesfiches.indexWhere(
            (lesfiche) => lesfiche.id == _lesson.id,
          )] =
          labelled;
      await openSession();

      final text = await ok('duplicate_lesfiches', {
        'lesfiches': [_lesson.id, _assignment.id.toUpperCase(), _lesson.id],
      });

      expect(server.requests, [
        'GET $fakeLesfichesPath',
        'POST $fakeLesficheDuplicatePath',
      ], reason: 'the list without the course names, then one write');
      expect(bodies(fakeLesficheDuplicatePath), [
        _bulkOf([_lesson, _assignment]),
      ]);
      expect(
        text,
        startsWith(
          'Made 2 copies in the own library of the Lesfiches module:\n'
          '- lesson | Lussen - kopie | labels JAAR 6, Lussen | 1 course | '
          'visible | id $_copy1 (a copy of id ${_lesson.id})\n'
          '- assignment KT Kleine Taak | Lussen - kopie | no labels | 1 '
          'course | visible | id $_copy2 (a copy of id ${_assignment.id})\n'
          'Each copy has',
        ),
      );
      expect(text, contains('Change a copy with edit_lesfiche'));
      final copy = planner.lesfiches.firstWhere((l) => l.id == _copy1);
      expect(copy.labels, ['JAAR 6']);
      expect(copy.ownLabels, ['Lussen']);
      expect(copy.goals, labelled.goals);
      expect(copy.attachments, _lesson.attachments);
      expect(copy.weblinks.single.url, _lesson.weblinks.single.url);
      expect(copy.weblinks.single.id, isNot(_lesson.weblinks.single.id));
    });

    test('refuses, before anything is sent, a lesfiche in the trash (restore '
        'it first) and an id that names no lesfiche', () async {
      planner.trashedLesfiches.add(_assignment.id);
      await openSession();

      expect(
        await error('duplicate_lesfiches', {
          'lesfiches': [_lesson.id, _assignment.id, _unknown],
        }),
        'The assignment lesfiche "Lussen" is in the trash, and a lesfiche in '
        'the trash cannot be copied: restore it first with restore_lesfiches '
        '(after the user confirms it), then copy it. You have no lesfiche '
        'with id $_unknown, in the library or in the trash. Take the ids from '
        'list_lesfiches (type all lists both kinds). The others were not '
        'copied either. Nothing was sent.',
      );
      expect(server.requests, [
        'GET $fakeLesfichesPath',
        'GET $fakeLesficheTrashedPath',
      ]);
      expect(planner.writes, isEmpty);
    });

    test('a lesfiche that went to the trash after the list was read: the '
        'module refuses it (403), no copy was made', () async {
      planner.beforeAnswer = (method, path) {
        if (path == fakeLesficheDuplicatePath) {
          planner.trashedLesfiches.add(_lesson.id);
        }
      };

      expect(
        await error('duplicate_lesfiches', {
          'lesfiches': [_lesson.id],
        }),
        'The Lesfiches module refused to copy the lesson lesfiche "Lussen" '
        '(HTTP 403): a lesfiche in the trash cannot be copied, so it most '
        'likely went to the trash after this tool read the list. '
        'list_trashed_lesfiches lists the trash; restore it first with '
        'restore_lesfiches. No copy was made.',
      );
      expect(planner.writes, ['POST $fakeLesficheDuplicatePath']);
    });

    test('some copies made and others not: the list, read again, says which '
        'were copied and which not', () async {
      planner.beforeAnswer = (method, path) {
        if (path == fakeLesficheDuplicatePath) {
          planner.trashedLesfiches.add(_assignment.id);
        }
      };
      await openSession();

      expect(
        await error('duplicate_lesfiches', {
          'lesfiches': [_lesson.id, _assignment.id],
        }),
        'The copy of 2 lesfiches was sent, but the Lesfiches module did not '
        'confirm all of it. Read again after it, the list of lesfiches shows '
        'what was done.\n'
        'Copies made:\n'
        '- lesson | Lussen - kopie | no labels | 1 course | visible | changed '
        '2026-11-01 | id $_copy1 (a copy of id ${_lesson.id})\n'
        'No copy found of:\n'
        '$_assignmentLine\n'
        'Do not call duplicate_lesfiches again for the lesfiches that were '
        'copied: it would make more copies. Tell the user which were copied '
        'and which not, and ask before copying the others again; one in the '
        'trash (list_trashed_lesfiches) cannot be copied.',
      );
      expect(server.requests, [
        'GET $fakeLesfichesPath',
        'POST $fakeLesficheDuplicatePath',
        'GET $fakeLesfichesPath',
      ], reason: 'sent once, then the list again');
    });

    test('an answer that does not arrive: the list, read again, finds the '
        'copies; when it cannot be read, maybe made, with list_lesfiches to '
        'check', () async {
      planner.lostAnswers.add(fakeLesficheDuplicatePath);

      final found = await ok('duplicate_lesfiches', {
        'lesfiches': [_lesson.id],
      });
      expect(
        found,
        contains(
          'Copies made:\n'
          '- lesson | Lussen - kopie | no labels | 1 course | visible | '
          'changed 2026-11-01 | id $_copy1 (a copy of id ${_lesson.id})\n',
        ),
      );
      expect(found, isNot(contains('No copy found')));

      planner.beforeAnswer = (method, path) {
        if (path == fakeLesficheDuplicatePath) {
          planner.failing[fakeLesfichesPath] = 500;
        }
      };
      expect(
        await error('duplicate_lesfiches', {
          'lesfiches': [_lesson.id],
        }),
        'A copy of the lesson lesfiche "Lussen" may or may not have been '
        'made: it was sent, but the Lesfiches module did not confirm it. Do '
        'not call duplicate_lesfiches again for it: that would make more '
        'copies. First list the lesfiches with list_lesfiches (type all) to '
        'see which copies there are: a copy is named after its lesfiche with '
        '" - kopie" behind it. Then tell the user what you found.',
      );
      expect(planner.writes, [
        'POST $fakeLesficheDuplicatePath',
        'POST $fakeLesficheDuplicatePath',
      ], reason: 'each sent once');
    });

    test('Smartschool refuses the session for the copy: the library does '
        'not send it again by itself; the action is repeated in a new '
        'session, and one copy is made', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' &&
            request.uri.path == fakeLesficheDuplicatePath,
      );

      expect(
        await ok('duplicate_lesfiches', {
          'lesfiches': [_lesson.id],
        }),
        startsWith('Made 1 copy'),
      );
      expect(planner.writes, ['POST $fakeLesficheDuplicatePath']);
      expect(
        planner.lesfiches.where((l) => l.name == 'Lussen - kopie'),
        hasLength(1),
      );
    });
  });

  group('list_trashed_lesfiches', () {
    test('lists the trash most recently moved first, with the course names, '
        'filtered by words in the name', () async {
      planner
        ..trashedLesfiches.addAll([fakeLesficheGame.id, _lesson.id])
        ..lesficheTrashDates[fakeLesficheGame.id] = '2026-10-20 08:00:00';

      expect(
        await ok('list_trashed_lesfiches', {}),
        '2 lesfiches in the trash of the Lesfiches module, most recently '
        'moved first:\n'
        'lesson | Lussen | no labels | informatica | visible | in the trash '
        'since 2026-11-01 | id ${_lesson.id}\n'
        'assignment KT Kleine Taak | Taak: een eigen spel | labels Lussen | '
        'informatica | visible | in the trash since 2026-10-20 | id '
        '${fakeLesficheGame.id}\n'
        'The Lesfiches module says a lesfiche in its trash can be restored '
        'within 100 days. restore_lesfiches takes one back into the library, '
        'by its id.',
      );
      expect(
        await ok('list_trashed_lesfiches', {'query': 'SPEL'}),
        startsWith(
          '1 lesfiche whose name holds "SPEL", of the 2 in the trash of the '
          'Lesfiches module, most recently moved first:\n'
          'assignment KT Kleine Taak | Taak: een eigen spel |',
        ),
      );
      expect(
        await ok('list_trashed_lesfiches', {'query': 'recursie'}),
        'No lesfiches whose name holds "recursie" (of the 2 lesfiches in the '
        'trash of the Lesfiches module).',
      );
      expect(planner.writes, isEmpty);
    });
  });

  group('restore_lesfiches', () {
    test(
      'restores a lesson and an assignment in one write, each once',
      () async {
        planner.trashedLesfiches.addAll([_lesson.id, _assignment.id]);
        await openSession();

        expect(
          await ok('restore_lesfiches', {
            'lesfiches': [_assignment.id, _lesson.id.toUpperCase(), _lesson.id],
          }),
          'Restored 2 lesfiches from the trash into the own library of the '
          'Lesfiches module:\n'
          '$_assignmentLine\n'
          '$_lessonLine\n'
          'list_lesfiches lists them again, and they can be changed, copied '
          'and planned as before.',
        );
        expect(server.requests, [
          'GET $fakeLesficheTrashedPath',
          'POST $fakeLesficheRestorePath',
        ]);
        expect(bodies(fakeLesficheRestorePath), [
          _bulkOf([_assignment, _lesson]),
        ]);
        expect(planner.trashedLesfiches, isEmpty);
      },
    );

    test('refuses, before anything is sent, a lesfiche that is not in the '
        'trash and an id that names no lesfiche; a second call finds it no '
        'longer in the trash', () async {
      planner.trashedLesfiches.add(_assignment.id);
      await openSession();

      expect(
        await error('restore_lesfiches', {
          'lesfiches': [_assignment.id, _lesson.id, _unknown],
        }),
        'The lesson lesfiche "Lussen" is not in the trash: list_lesfiches '
        'lists it in the library, so there is nothing to restore. The trash '
        'holds no lesfiche with id $_unknown, and neither does the library. '
        'Take the ids from list_trashed_lesfiches. The others were not '
        'restored either. Nothing was sent.',
      );
      expect(server.requests, [
        'GET $fakeLesficheTrashedPath',
        'GET $fakeLesfichesPath',
      ]);

      await ok('restore_lesfiches', {
        'lesfiches': [_assignment.id],
      });
      expect(
        await error('restore_lesfiches', {
          'lesfiches': [_assignment.id],
        }),
        startsWith('The assignment lesfiche "Lussen" is not in the trash'),
      );
      expect(planner.writes, ['POST $fakeLesficheRestorePath']);
    });

    test('an exception for one of them: the trash, read again, says which '
        'were restored and which not', () async {
      planner
        ..trashedLesfiches.addAll([_lesson.id, _assignment.id])
        ..lesficheRestoreExceptions[_lesson.id] = {
          'status': 409,
          'title': 'Conflict',
          'detail': '',
        };
      await openSession();

      expect(
        await error('restore_lesfiches', {
          'lesfiches': [_lesson.id, _assignment.id],
        }),
        'The restore of 2 lesfiches was sent, but the Lesfiches module did '
        'not confirm all of it. Read again after it, the trash shows what '
        'was done.\n'
        'Out of the trash, in the library now:\n'
        '$_assignmentLine\n'
        'Still in the trash:\n'
        '$_lessonLine\n'
        'Tell the user which were restored and which not, and ask before '
        'trying the others again.',
      );
      expect(server.requests, [
        'GET $fakeLesficheTrashedPath',
        'POST $fakeLesficheRestorePath',
        'GET $fakeLesficheTrashedPath',
      ]);
      expect(await listed(), contains(_assignment.id));
    });

    test('an answer that does not arrive, and the trash cannot be read '
        'after it: maybe restored, with list_trashed_lesfiches to '
        'check', () async {
      planner
        ..trashedLesfiches.add(_lesson.id)
        ..lostAnswers.add(fakeLesficheRestorePath)
        ..beforeAnswer = (method, path) {
          if (path == fakeLesficheRestorePath) {
            planner.failing[fakeLesficheTrashedPath] = 500;
          }
        };

      expect(
        await error('restore_lesfiches', {
          'lesfiches': [_lesson.id],
        }),
        'The lesson lesfiche "Lussen" may or may not have been restored: it '
        'was sent, but the Lesfiches module did not confirm it. Do not call '
        'restore_lesfiches again for it. First list the trash with '
        'list_trashed_lesfiches to see whether it is still there. Then tell '
        'the user what you found.',
      );
      expect(planner.writes, ['POST $fakeLesficheRestorePath']);
    });

    test('Smartschool refuses the session for the restore: the library logs '
        'in again and sends it once more, as a read', () async {
      planner.trashedLesfiches.add(_lesson.id);
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' &&
            request.uri.path == fakeLesficheRestorePath,
      );

      expect(
        await ok('restore_lesfiches', {
          'lesfiches': [_lesson.id],
        }),
        startsWith('Restored 1 lesfiche from the trash'),
      );
      expect(planner.writes, ['POST $fakeLesficheRestorePath']);
      expect(planner.trashedLesfiches, isEmpty);
    });
  });
}
