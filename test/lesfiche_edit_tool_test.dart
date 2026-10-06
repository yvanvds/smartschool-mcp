/// `edit_lesfiche` (#115), called over MCP on the real server, session and
/// library, against a fake Smartschool whose Lesfiches module carries out
/// the edits of a lesfiche as dartschool's captures show them
/// (`test/lesson_content_write_test.dart` there, dartschool#129: each edit
/// answered `200` with the whole lesfiche, a bare `400`, a lesfiche in the
/// trash answered `404`), and whose course list names the school's courses
/// (`test/support/fake_planner.dart`).
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/edit_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The lesson lesfiche and the assignment lesfiche of dartschool's capture
/// of the detail, and where they are read and written.
final _lesson = fakeLesficheDetailLesson;
final _assignment = fakeLesficheDetailAssignment;
final _lessonPath = fakeLesficheDetailPath(_lesson);
final _assignmentPath = fakeLesficheDetailPath(_assignment);

/// The school's course wiskunde, as an edit sends it.
const _wiskunde = {
  'platformId': 4069,
  'id': 'c0000000-0000-4000-8000-000000000001',
};

/// The school's course informatica, as an edit sends it.
const _informatica = {
  'platformId': 4069,
  'id': 'c0000000-0000-4000-8000-000000000005',
};

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
        editLesficheTool(session),
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

  Future<String> edit(Map<String, Object?> arguments) =>
      ok('edit_lesfiche', {'lesfiche': _lesson.id, ...arguments});

  Future<String> refused(Map<String, Object?> arguments) =>
      error('edit_lesfiche', {'lesfiche': _lesson.id, ...arguments});

  /// Opens the session (the session check reads the course list), and
  /// forgets the requests so far.
  Future<void> openSession() async {
    await ok('list_lesfiches', {});
    server.requests.clear();
    planner.requests.clear();
  }

  /// The bodies of the requests with [method] to [path] that reached the
  /// Lesfiches module.
  List<Object?> bodiesOf(String path, [String method = 'POST']) => [
    for (final request in planner.requests)
      if (request.method == method && request.path == path) request.data,
  ];

  /// How many POSTs to [path] reached the fake Smartschool, also those it
  /// refused because the session was not accepted.
  int postsTo(String path) =>
      server.requests.where((request) => request == 'POST $path').length;

  /// The lesfiche of the fake with the id of [lesfiche], as it is now.
  FakeLesfiche now(FakeLesfiche lesfiche) =>
      planner.lesfiches.singleWhere((each) => each.id == lesfiche.id);

  /// The lesfiche as `read_lesfiche` shows it: what a result ends with,
  /// after its own lines and a blank line.
  String inFull(String text) => text.substring(text.indexOf('\n\n') + 2);

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

    test('as a write Claude Desktop asks approval for, which sets values: '
        'idempotent', () {
      final tool = tools['edit_lesfiche']!;
      expect(tool.toolAnnotations!.readOnlyHint, isFalse);
      expect(tool.toolAnnotations!.destructiveHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isTrue);
      expect(tool.toolAnnotations!.openWorldHint, isTrue);
      expect(tool.inputSchema.required, ['lesfiche']);
      expect(tool.inputSchema.properties!.keys, [
        'lesfiche',
        'type',
        'name',
        'icon',
        'public_info',
        'private_info',
        'courses',
        'visible',
      ]);
      expect(
        tool.description,
        allOf(
          contains(
            'only call this tool after the user has explicitly confirmed it',
          ),
          contains(
            'Whether a lesson planned from the lesfiche earlier changes with '
            'it is not known',
          ),
          contains('A lesfiche in the trash cannot be changed.'),
          contains('labels are set in the Lesfiches module itself'),
        ),
      );
    });

    test('read_lesfiche points to it and to the tools that change the '
        'weblinks and attachments', () {
      expect(
        tools['read_lesfiche']!.description,
        contains(
          'edit_lesfiche changes the lesfiche; set_lesfiche_weblink and '
          'remove_lesfiche_weblink change its weblinks, and '
          'add_lesfiche_attachments, set_lesfiche_attachment_visibility and '
          'remove_lesfiche_attachment its attachments, by the ids shown '
          'here;',
        ),
      );
    });
  });

  group('edit_lesfiche', () {
    test('changes every field, one edit each in the order name, icon, public '
        'info, private info, courses, visible, with the web client\'s '
        'bodies: reads the lesfiche and the course list first, and the '
        'lesfiche once more at the end, as read_lesfiche shows it', () async {
      await openSession();

      final text = await edit({
        'name': ' Lussen 2 ',
        'icon': 'book',
        'public_info': 'Hoofdstuk 4\n\nMet oefeningen.',
        'private_info': '',
        'courses': ['wiskunde', 'Informatica'],
        'visible': false,
      });

      expect(server.requests, [
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
        'POST $_lessonPath/rename',
        'POST $_lessonPath/change-icon',
        'POST $_lessonPath/change-public-info',
        'POST $_lessonPath/change-private-info',
        'GET $fakeCourseListPath',
        'POST $_lessonPath/change-courses',
        'POST $_lessonPath/mark-as-invisible',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ], reason: 'the library checks the courses again before sending');
      expect(
        [
          for (final request in planner.requests)
            if (request.method == 'POST') request.data,
        ],
        [
          {'newName': 'Lussen 2'},
          {'newIcon': 'book'},
          {'newPublicInfo': '<p>Hoofdstuk 4</p><p>Met oefeningen.</p>'},
          {'newPrivateInfo': ''},
          {
            'newCourses': [_wiskunde, _informatica],
          },
          <String, Object?>{},
        ],
      );
      expect(
        text,
        startsWith(
          'Changed the name, the icon, the public info, the private info, the '
          'courses and the visibility in the module of the lesson lesfiche '
          '"Lussen".\n'
          '\n'
          'Lesfiche ${_lesson.id}\n'
          'Kind: lesson\n'
          'Name: Lussen 2\n'
          'Icon: book\n'
          'Labels: none\n'
          'Courses: wiskunde, informatica\n'
          'In the module: hidden\n',
        ),
      );
      expect(
        text,
        endsWith(
          'Public info (what pupils see):\n'
          'Hoofdstuk 4\n'
          '\n'
          'Met oefeningen.\n'
          '\n'
          'Private info (hidden from pupils):\n'
          '(none)',
        ),
      );
      expect(
        inFull(text),
        await ok('read_lesfiche', {'lesfiche': _lesson.id}),
        reason: 'the lesfiche as read_lesfiche shows it',
      );
      final changed = now(_lesson);
      expect(changed.name, 'Lussen 2');
      expect(changed.isVisible, isFalse);
      expect(changed.weblinks, hasLength(1), reason: 'the weblinks stay');
      expect(changed.attachments, hasLength(1));
    });

    test('changes an assignment lesfiche at assignments/, and says which '
        'fields already had the value given (they are sent all the '
        'same)', () async {
      final text = await ok('edit_lesfiche', {
        'lesfiche': _assignment.id,
        'type': 'assignment',
        'name': 'Lussen',
        'icon': 'book',
        'visible': true,
      });

      expect(planner.writes, [
        'POST $_assignmentPath/rename',
        'POST $_assignmentPath/change-icon',
        'POST $_assignmentPath/mark-as-visible',
      ]);
      expect(
        text,
        startsWith(
          'Changed the icon of the assignment lesfiche "Lussen".\n'
          'The name and the visibility in the module already had the value '
          'given.\n'
          '\n'
          'Lesfiche ${_assignment.id}\n'
          'Kind: assignment KT Kleine Taak\n',
        ),
      );

      expect(
        await edit({
          'name': 'Lussen',
          'courses': [' Informatica'],
        }),
        startsWith(
          'Nothing to change: the lesson lesfiche "Lussen" already had what '
          'was given.\n\nLesfiche ${_lesson.id}\n',
        ),
      );
      expect(planner.writes.sublist(3), [
        'POST $_lessonPath/rename',
        'POST $_lessonPath/change-courses',
      ]);
    });

    test('an empty list of courses removes them, without reading the course '
        'list', () async {
      await openSession();

      final text = await edit({'courses': <String>[]});

      expect(server.requests, [
        'GET $_lessonPath',
        'POST $_lessonPath/change-courses',
        'GET $_lessonPath',
      ]);
      expect(bodiesOf('$_lessonPath/change-courses'), [
        {'newCourses': <Object?>[]},
      ]);
      expect(text, startsWith('Changed the courses of the lesson lesfiche '));
      expect(text, contains('\nCourses: none\n'));
    });

    test('refuses, before anything is sent, a call that changes nothing, a '
        'name that is empty or too long, an empty icon, and an id that is '
        'no lesfiche id', () async {
      await openSession();

      expect(
        await refused({}),
        'Nothing to change: pass at least one of name, icon, public_info, '
        'private_info, courses and visible. Nothing was sent.',
      );
      expect(
        await refused({'name': '  '}),
        'name is empty: give the lesfiche a name. Nothing was sent.',
      );
      expect(
        await refused({'name': 'x' * 256}),
        'name is 256 characters long, and the Lesfiches module takes at most '
        '255: shorten it. Nothing was sent.',
      );
      expect(
        await refused({'icon': ' '}),
        'icon is empty: pass the name of an icon from Smartschool\'s icon '
        'set, as read_lesfiche shows it, or leave icon out to keep it. '
        'Nothing was sent.',
      );
      expect(
        await error('edit_lesfiche', {
          'lesfiche': 'planned-lessons/4069/1',
          'name': 'Lussen 2',
        }),
        startsWith(
          'lesfiche must be the id of a lesfiche as list_lesfiches shows it',
        ),
      );
      expect(server.requests, isEmpty, reason: 'nothing was sent');
    });

    test('refuses, after reading but before any edit, a course the school '
        'does not have, and a lesfiche of another kind or that does not '
        'exist', () async {
      expect(
        await refused({
          'name': 'Lussen 2',
          'courses': ['informatica', 'geschiedenis'],
        }),
        startsWith(
          'courses holds "geschiedenis", which is not a course of the '
          'school\'s course list. Its courses are biologie, chemie, ',
        ),
      );
      expect(
        await error('edit_lesfiche', {
          'lesfiche': _lesson.id,
          'type': 'assignment',
          'name': 'Lussen 2',
        }),
        startsWith(
          'You have no assignment lesfiche with id ${_lesson.id}. Take the id '
          'and the kind from list_lesfiches',
        ),
      );
      expect(planner.writes, isEmpty);
      expect(now(_lesson).name, 'Lussen');
    });

    test('stops at the first edit that fails, and says what was changed '
        'before it and what was not sent', () async {
      planner.failing['$_lessonPath/rename'] = 400;
      expect(
        await refused({'name': 'Lussen 2', 'icon': 'book'}),
        'The Lesfiches module refused the change of the name of the lesson '
        'lesfiche "Lussen" (HTTP 400), without saying why. The lesfiche was '
        'not changed.',
      );
      expect(planner.writes, ['POST $_lessonPath/rename']);

      planner.failing
        ..clear()
        ..['$_lessonPath/change-icon'] = 400;
      expect(
        await refused({
          'name': 'Lussen 2',
          'icon': 'book',
          'courses': ['wiskunde'],
          'visible': false,
        }),
        'The Lesfiches module refused the change of the icon of the lesson '
        'lesfiche "Lussen" (HTTP 400), without saying why. The name was '
        'changed before that. The courses and the visibility in the module '
        'were not sent.',
      );
      expect(planner.writes.sublist(1), [
        'POST $_lessonPath/rename',
        'POST $_lessonPath/change-icon',
      ]);
      expect(now(_lesson).name, 'Lussen 2');
      expect(now(_lesson).icon, 'document_observation');
    });

    test('an edit the module does not confirm (a 500): maybe saved, with '
        'what was changed before it, and how to check it', () async {
      planner.failing['$_lessonPath/change-courses'] = 500;

      expect(
        await refused({
          'name': 'Lussen 2',
          'courses': ['wiskunde'],
          'visible': false,
        }),
        'The change of the courses of the lesson lesfiche "Lussen" may or may '
        'not have been saved: it was sent, but the Lesfiches module did not '
        'confirm it. The name was changed. The visibility in the module was '
        'not sent. Do not call edit_lesfiche again for it. First read the '
        'lesfiche with read_lesfiche (lesfiche ${_lesson.id}) and compare the '
        'courses. Then tell the user what you found.',
      );
      expect(postsTo('$_lessonPath/change-courses'), 1);
      expect(postsTo('$_lessonPath/mark-as-invisible'), 0);
    });

    test('a lesfiche in the trash is still read, but its edits are answered '
        '404: the error says it is most likely in the trash', () async {
      planner.trashedLesfiches.add(_lesson.id);

      expect(
        await refused({'name': 'Lussen 2', 'visible': false}),
        'The Lesfiches module answered the change of the name of the lesson '
        'lesfiche "Lussen" with HTTP 404: the lesfiche is in the trash or no '
        'longer exists. A lesfiche in the trash can still be read, but not '
        'changed, and list_lesfiches does not list it; the user restores it '
        'from the trash in the Lesfiches module itself. The lesfiche was not '
        'changed.',
      );
      expect(planner.writes, ['POST $_lessonPath/rename']);
      expect(
        await ok('read_lesfiche', {'lesfiche': _lesson.id}),
        contains('\nName: Lussen\n'),
      );
      expect(
        await ok('list_lesfiches', {'query': 'lussen'}),
        isNot(contains(_lesson.id)),
      );
    });

    test('Smartschool refuses the session for an edit: the library logs in '
        'again and sends it once more, as a read', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' &&
            request.uri.path == '$_lessonPath/rename',
      );

      expect(
        await edit({'name': 'Lussen 2'}),
        startsWith('Changed the name of the lesson lesfiche "Lussen".\n'),
      );
      expect(postsTo('$_lessonPath/rename'), 2);
      expect(planner.writes, ['POST $_lessonPath/rename']);
      expect(server.logins, 2);
    });

    test('the edits go through, but reading the lesfiche back fails: the '
        'result says what changed, and how to read it', () async {
      planner.beforeAnswer = (method, path) {
        if (method == 'POST') planner.failing[_lessonPath] = 500;
      };

      expect(
        await edit({'icon': 'book'}),
        'Changed the icon of the lesson lesfiche "Lussen".\n'
        '\n'
        'The change went through, but reading the lesfiche back failed: The '
        'Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log. Read it with read_lesfiche (lesfiche ${_lesson.id}) to '
        'see it.',
      );
      expect(now(_lesson).icon, 'book');
    });
  });
}
