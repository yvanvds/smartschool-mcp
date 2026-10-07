/// `set_lesfiche_weblink`, `remove_lesfiche_weblink`,
/// `add_lesfiche_attachments`, `set_lesfiche_attachment_visibility` and
/// `remove_lesfiche_attachment` (#115), called over MCP on the real server,
/// session, library and local files, against a fake Smartschool whose
/// Lesfiches module writes the weblinks and attachments of a lesfiche as
/// dartschool's captures show them (`test/lesson_content_write_test.dart`
/// there, dartschool#129: a weblink write answered with the weblink only, a
/// removal with `204`, new attachments taken from the upload directory with
/// the visibility `always`, a lesfiche in the trash answered `404`), behind
/// the shared fake upload step (`test/support/fake_planner.dart`).
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/add_lesfiche_attachments_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/remove_lesfiche_attachment_tool.dart';
import 'package:smartschool_mcp/src/tools/remove_lesfiche_weblink_tool.dart';
import 'package:smartschool_mcp/src/tools/set_lesfiche_attachment_visibility_tool.dart';
import 'package:smartschool_mcp/src/tools/set_lesfiche_weblink_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The size limit of `add_lesfiche_attachments` here.
const _limit = 64;

/// The lesson lesfiche of dartschool's capture of the detail, with its
/// weblink `Oefeningen` and its attachment `lussen.txt`, and the assignment
/// lesfiche of the same capture.
final _lesson = fakeLesficheDetailLesson;
final _assignment = fakeLesficheDetailAssignment;
final _lessonPath = fakeLesficheDetailPath(_lesson);
final _weblink = _lesson.weblinks.single;
final _attachment = _lesson.attachments.single;

/// The id the fake gives the [n]th weblink or attachment it makes, with
/// [prefix] `e` for a weblink and `f` for an attachment.
String _partId(String prefix, int n) =>
    '${prefix}1000000-0000-4000-9000-${'$n'.padLeft(12, '0')}';

/// A visibility as the module takes it.
Map<String, Object?> _visibility(String option, [int? days]) => {
  'option': option,
  'daysAfterEnd': days,
};

/// How the result of a write starts to name the lesson lesfiche.
const _lussen = 'the lesson lesfiche "Lussen"';

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late Directory files;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner
      ..loadCaptures()
      ..loadLesfiches()
      ..loadLesficheDetails();
    files = await tempCache();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        readLesficheTool(session),
        setLesficheWeblinkTool(session),
        removeLesficheWeblinkTool(session),
        addLesficheAttachmentsTool(session, maxBytes: _limit),
        setLesficheAttachmentVisibilityTool(session),
        removeLesficheAttachmentTool(session),
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

  /// Calls [tool] for the lesson lesfiche, with [arguments].
  Future<String> onLesson(String tool, Map<String, Object?> arguments) =>
      ok(tool, {'lesfiche': _lesson.id, ...arguments});

  /// Calls [tool] for the lesson lesfiche, with [arguments], for an error.
  Future<String> refusedOnLesson(String tool, Map<String, Object?> arguments) =>
      error(tool, {'lesfiche': _lesson.id, ...arguments});

  /// Writes a file [name] with [content] into the test's folder, and
  /// returns its full path.
  String file(String name, [String content = 'dartschool test\n']) {
    final path = '${files.path}${Platform.pathSeparator}$name';
    File(path).writeAsStringSync(content);
    return path;
  }

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

  /// How many requests with [method] to [path] reached the fake
  /// Smartschool, also those it refused because the session was not
  /// accepted.
  int sentTo(String path, [String method = 'POST']) =>
      server.requests.where((request) => request == '$method $path').length;

  /// The lesson lesfiche of the fake, as it is now.
  FakeLesfiche lesson() =>
      planner.lesfiches.singleWhere((each) => each.id == _lesson.id);

  /// The lesfiche as `read_lesfiche` shows it: what a result ends with,
  /// after its own lines and a blank line.
  String inFull(String text) => text.substring(text.indexOf('\n\n') + 2);

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

    test('as writes Claude Desktop asks approval for; an add is not '
        'idempotent, a change of a visibility and a removal are', () {
      for (final (name, idempotent, required) in [
        ('set_lesfiche_weblink', false, ['lesfiche', 'name', 'url']),
        ('remove_lesfiche_weblink', true, ['lesfiche', 'weblink_id']),
        ('add_lesfiche_attachments', false, ['lesfiche', 'attachments']),
        (
          'set_lesfiche_attachment_visibility',
          true,
          ['lesfiche', 'attachment_id', 'visibility'],
        ),
        ('remove_lesfiche_attachment', true, ['lesfiche', 'attachment_id']),
      ]) {
        final tool = tools[name]!;
        expect(tool.toolAnnotations!.readOnlyHint, isFalse, reason: name);
        expect(tool.toolAnnotations!.destructiveHint, isTrue, reason: name);
        expect(tool.toolAnnotations!.idempotentHint, idempotent, reason: name);
        expect(tool.toolAnnotations!.openWorldHint, isTrue, reason: name);
        expect(tool.inputSchema.required, required, reason: name);
        expect(
          tool.description,
          allOf(
            contains('only call this tool after the user has explicitly'),
            contains(
              'Whether a lesson planned from the lesfiche earlier changes '
              'with it is not known.',
            ),
            contains('A lesfiche in the trash cannot be changed.'),
          ),
          reason: name,
        );
      }
      expect(tools['set_lesfiche_weblink']!.inputSchema.properties!.keys, [
        'lesfiche',
        'type',
        'weblink_id',
        'name',
        'url',
        'icon',
        'visibility',
      ]);
      expect(
        tools['add_lesfiche_attachments']!.description,
        contains('up to 10 files of 64 bytes each'),
      );
    });
  });

  group('set_lesfiche_weblink', () {
    test('adds a weblink: reads the lesfiche, sends the web client\'s body '
        'once, and gives the lesfiche back as read_lesfiche shows it, with '
        'the id of the weblink', () async {
      await openSession();

      final text = await onLesson('set_lesfiche_weblink', {
        'name': ' Quiz ',
        'url': 'example.com/quiz',
        'visibility': 'after_end:3',
      });

      expect(server.requests, [
        'GET $_lessonPath',
        'POST $_lessonPath/weblinks',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ]);
      expect(bodiesOf('$_lessonPath/weblinks'), [
        {
          'newName': 'Quiz',
          'newIcon': 'earth',
          'newUrl': 'http://example.com/quiz',
          'newVisibility': _visibility('days-after-end', 3),
        },
      ]);
      expect(
        text,
        startsWith(
          'Added the weblink "Quiz" to $_lussen, with id ${_partId('e', 1)}.\n'
          '\n'
          'Lesfiche ${_lesson.id}\n',
        ),
      );
      expect(
        text,
        contains(
          'Weblinks:\n'
          '- Oefeningen | https://example.com/oefeningen | icon earth | '
          'visible to pupils: from the end of the lesson it is planned in | '
          'id ${_weblink.id}\n'
          '- Quiz | http://example.com/quiz | icon earth | visible to pupils: '
          'from 3 days after the end of the lesson it is planned in | id '
          '${_partId('e', 1)}\n',
        ),
      );
      expect(inFull(text), await ok('read_lesfiche', {'lesfiche': _lesson.id}));
    });

    test('adds a weblink to an assignment lesfiche at assignments/, with the '
        'icon given', () async {
      await ok('set_lesfiche_weblink', {
        'lesfiche': _assignment.id,
        'type': 'assignment',
        'name': 'Opgave',
        'url': 'https://example.com/opgave',
        'icon': 'book',
      });

      final path = '${fakeLesficheDetailPath(_assignment)}/weblinks';
      expect(planner.writes, ['POST $path']);
      expect(bodiesOf(path), [
        {
          'newName': 'Opgave',
          'newIcon': 'book',
          'newUrl': 'https://example.com/opgave',
          'newVisibility': _visibility('always'),
        },
      ]);
    });

    test('changes a weblink by its id: every value is sent, and the icon and '
        'the visibility it has stay when they are not given', () async {
      final path = '$_lessonPath/weblinks/${_weblink.id}';

      expect(
        await onLesson('set_lesfiche_weblink', {
          'weblink_id': 'id ${_weblink.id.toUpperCase()}',
          'name': 'Oefeningen 2',
          'url': 'https://example.com/nieuw',
        }),
        startsWith(
          'Changed the weblink "Oefeningen" of $_lussen (id ${_weblink.id}).\n'
          '\n',
        ),
      );
      await onLesson('set_lesfiche_weblink', {
        'weblink_id': _weblink.id,
        'name': 'Oefeningen 3',
        'url': 'https://example.com/nieuw',
        'icon': 'book',
        'visibility': 'never',
      });

      expect(bodiesOf(path), [
        {
          'newName': 'Oefeningen 2',
          'newIcon': 'earth',
          'newUrl': 'https://example.com/nieuw',
          'newVisibility': _visibility('at-end'),
        },
        {
          'newName': 'Oefeningen 3',
          'newIcon': 'book',
          'newUrl': 'https://example.com/nieuw',
          'newVisibility': _visibility('never'),
        },
      ]);
      expect(planner.writes, ['POST $path', 'POST $path']);
      expect(lesson().weblinks.single.name, 'Oefeningen 3');
    });

    test('refuses, before anything is sent, a weblink without a name, with '
        'an address the web client refuses or a visibility it does not '
        'offer, and an empty weblink id', () async {
      await openSession();
      Future<String> refused(Map<String, Object?> arguments) => refusedOnLesson(
        'set_lesfiche_weblink',
        {'name': 'Quiz', 'url': 'https://example.com/quiz', ...arguments},
      );

      expect(
        await refused({'name': '  '}),
        'the weblink has no name: give it one. Nothing was sent.',
      );
      expect(
        await refused({'url': 'geen url'}),
        'the weblink ("Quiz") has the url "geen url", which is not a web '
        'address the Lesfiches web client takes: pass one like '
        'https://example.com/page. Nothing was sent.',
      );
      expect(
        await refused({'visibility': 'soms'}),
        startsWith(
          'the visibility of the weblink ("Quiz") is "soms", which is not a '
          'visibility: pass always (the default), never, at_start',
        ),
      );
      expect(
        await refused({'weblink_id': ' '}),
        'weblink_id is empty: pass the id of the weblink as read_lesfiche '
        'shows it at the end of its line, like '
        'e0000000-0000-4000-8000-000000000021. Nothing was sent.',
      );
      expect(server.requests, isEmpty, reason: 'nothing was sent');
    });

    test('refuses, after reading, a weblink id the lesfiche does not have, '
        'with its weblinks and their ids', () async {
      const unknown = 'e0000000-0000-4000-8000-0000000000ff';
      const listed =
          'The lesson lesfiche "Lussen" has no weblink with id $unknown. '
          'Nothing was sent. Its weblinks, each with its id at the end:\n'
          '- Oefeningen | https://example.com/oefeningen | icon earth | '
          'visible to pupils: from the end of the lesson it is planned in | '
          'id e0000000-0000-4000-8000-000000000021';

      expect(
        await refusedOnLesson('set_lesfiche_weblink', {
          'weblink_id': unknown,
          'name': 'Quiz',
          'url': 'https://example.com/quiz',
        }),
        listed,
      );
      expect(
        await refusedOnLesson('remove_lesfiche_weblink', {
          'weblink_id': unknown,
        }),
        listed,
      );
      expect(
        await error('remove_lesfiche_weblink', {
          'lesfiche': fakeLesficheFuncties.id,
          'weblink_id': unknown,
        }),
        'The lesson lesfiche "Functies" has no weblink with id $unknown. '
        'Nothing was sent. It has no weblinks.',
      );
      expect(planner.writes, isEmpty);
    });

    test('the module refuses an add with a bare 400: nothing was '
        'changed', () async {
      planner.failing['$_lessonPath/weblinks'] = 400;

      expect(
        await refusedOnLesson('set_lesfiche_weblink', {
          'name': 'Quiz',
          'url': 'https://example.com/quiz',
        }),
        'The Lesfiches module refused the weblink "Quiz" for $_lussen (HTTP '
        '400), without saying why. The lesfiche was not changed.',
      );
      expect(lesson().weblinks, hasLength(1));
    });

    test('an add the module does not confirm: maybe added, with how to '
        'check it, and not sent again; a change it does not confirm: maybe '
        'saved', () async {
      planner.lostAnswers.add('$_lessonPath/weblinks');

      expect(
        await refusedOnLesson('set_lesfiche_weblink', {
          'name': 'Quiz',
          'url': 'https://example.com/quiz',
        }),
        'The weblink "Quiz" may or may not have been added to $_lussen: it '
        'was sent, but the Lesfiches module did not confirm it. Do not call '
        'set_lesfiche_weblink again for it: a second call without '
        'weblink_id adds a second weblink. First read the lesfiche with '
        'read_lesfiche (lesfiche ${_lesson.id}) to see whether it is there. '
        'Then tell the user what you found.',
      );
      expect(sentTo('$_lessonPath/weblinks'), 1);
      expect(lesson().weblinks, hasLength(2), reason: 'it was added');

      planner.failing['$_lessonPath/weblinks/${_weblink.id}'] = 500;
      expect(
        await refusedOnLesson('set_lesfiche_weblink', {
          'weblink_id': _weblink.id,
          'name': 'Oefeningen 2',
          'url': 'https://example.com/oefeningen',
        }),
        'The change of the weblink "Oefeningen" of $_lussen may or may not '
        'have been saved: it was sent, but the Lesfiches module did not '
        'confirm it. Do not call set_lesfiche_weblink again for it. First '
        'read the lesfiche with read_lesfiche (lesfiche ${_lesson.id}) and '
        'compare the weblink. Then tell the user what you found.',
      );
    });

    test('Smartschool refuses the session for an add, which the library does '
        'not send again: the session repeats the call, which the library '
        'sends in a new session, logging in first, and adds the weblink '
        'once', () async {
      final path = '$_lessonPath/weblinks';
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' && request.uri.path == path,
      );

      expect(
        await onLesson('set_lesfiche_weblink', {
          'name': 'Quiz',
          'url': 'https://example.com/quiz',
        }),
        startsWith('Added the weblink "Quiz" to $_lussen, '),
      );
      expect(sentTo(path), 2, reason: 'the refused one and one');
      final first = server.requests.indexOf('POST $path');
      expect(
        server.requests[first + 1],
        'GET /login',
        reason:
            'after a refused session the library logs in before the next '
            'request (yvanvds/dartschool#134)',
      );
      expect(planner.writes, ['POST $path'], reason: 'added once');
      expect(server.logins, 2);
      expect(
        [for (final weblink in lesson().weblinks) weblink.name],
        ['Oefeningen', 'Quiz'],
      );
    });
  });

  group('remove_lesfiche_weblink', () {
    test('removes a weblink: a DELETE, answered with 204, and the lesfiche '
        'back without it', () async {
      await openSession();

      final text = await onLesson('remove_lesfiche_weblink', {
        'weblink_id': _weblink.id,
      });

      final path = '$_lessonPath/weblinks/${_weblink.id}';
      expect(server.requests, [
        'GET $_lessonPath',
        'DELETE $path',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ]);
      expect(planner.writes, ['DELETE $path']);
      expect(
        text,
        startsWith(
          'Removed the weblink "Oefeningen" (https://example.com/oefeningen) '
          'from $_lussen.\n\nLesfiche ${_lesson.id}\n',
        ),
      );
      expect(text, contains('\nWeblinks: none\n'));
      expect(lesson().weblinks, isEmpty);
    });

    test('a removal the module does not confirm (a 500): maybe removed, with '
        'how to check it', () async {
      planner.failing['$_lessonPath/weblinks/${_weblink.id}'] = 500;

      expect(
        await refusedOnLesson('remove_lesfiche_weblink', {
          'weblink_id': _weblink.id,
        }),
        'The weblink "Oefeningen" may or may not have been removed from '
        '$_lussen: it was sent, but the Lesfiches module did not confirm '
        'it. Do not call remove_lesfiche_weblink again for it. First read '
        'the lesfiche with read_lesfiche (lesfiche ${_lesson.id}) to see '
        'whether it is still there. Then tell the user what you found.',
      );
    });
  });

  group('a lesfiche in the trash', () {
    test('is still read, but its weblink and attachment writes are answered '
        '404: the error says it is most likely in the trash', () async {
      planner.trashedLesfiches.add(_lesson.id);
      const trash =
          'A lesfiche in the trash can still be read, but not changed, and '
          'list_lesfiches does not list it; the user restores it from the '
          'trash in the Lesfiches module itself. The lesfiche was not '
          'changed.';

      expect(
        await refusedOnLesson('set_lesfiche_weblink', {
          'name': 'Quiz',
          'url': 'https://example.com/quiz',
        }),
        'The Lesfiches module answered the weblink "Quiz" for $_lussen with '
        'HTTP 404: the lesfiche is in the trash or no longer exists. $trash',
      );
      expect(
        await refusedOnLesson('remove_lesfiche_weblink', {
          'weblink_id': _weblink.id,
        }),
        'The Lesfiches module answered the removal of the weblink '
        '"Oefeningen" from $_lussen with HTTP 404: the lesfiche is in the '
        'trash or no longer exists, or the weblink was removed meanwhile. '
        '$trash',
      );
      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _attachment.id,
          'visibility': 'always',
        }),
        'The Lesfiches module answered the change of the visibility of the '
        'attachment "lussen.txt" of $_lussen with HTTP 404: the lesfiche is '
        'in the trash or no longer exists, or the attachment was removed '
        'meanwhile. $trash',
      );
      expect(
        await refusedOnLesson('remove_lesfiche_attachment', {
          'attachment_id': _attachment.id,
        }),
        'The Lesfiches module answered the removal of the attachment '
        '"lussen.txt" from $_lussen with HTTP 404: the lesfiche is in the '
        'trash or no longer exists, or the attachment was removed '
        'meanwhile. $trash',
      );
      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('recursie.txt')},
          ],
        }),
        'The Lesfiches module answered the addition of the file '
        '"recursie.txt" to $_lussen with HTTP 404: the lesfiche is in the '
        'trash or no longer exists. $trash',
      );
      expect(lesson().weblinks, hasLength(1));
      expect(lesson().attachments, hasLength(1));
    });
  });

  group('add_lesfiche_attachments', () {
    test('adds files: reads the lesfiche, uploads them into a new directory, '
        'has the module take them once, then sets each visibility other than '
        'always (the module gives always), and gives the lesfiche back with '
        'the new attachments', () async {
      await openSession();
      final recursie = file('recursie.txt');
      final schema = file('schema.png', 'png');

      final text = await onLesson('add_lesfiche_attachments', {
        'attachments': [
          {'path': recursie, 'visibility': 'at_end'},
          {'path': schema},
        ],
      });

      final dir = server.uploads.directories.keys.single;
      expect(server.uploads.uploads, [
        (dir, 'recursie.txt'),
        (dir, 'schema.png'),
      ]);
      final visibility =
          '$_lessonPath/attachments/${_partId('f', 1)}/change-visibility';
      expect(server.requests, [
        'GET $_lessonPath',
        'GET $_lessonPath',
        'GET ${FakeUploads.directoryPath}',
        'POST ${FakeUploads.uploadPath}',
        'POST ${FakeUploads.uploadPath}',
        'POST $_lessonPath/attachments',
        'POST $visibility',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ], reason: 'the tool\'s read, the library\'s, upload, take, visibility');
      expect(bodiesOf('$_lessonPath/attachments'), [
        {'randomDir': dir},
      ]);
      expect(bodiesOf(visibility), [
        {'newVisibility': _visibility('at-end')},
      ]);
      expect(planner.writes, [
        'POST $_lessonPath/attachments',
        'POST $visibility',
      ], reason: 'taken once');
      expect(
        text,
        startsWith(
          'Added 2 attachments to $_lussen:\n'
          '- recursie.txt | 16 bytes | text/plain | visible to pupils: from '
          'the end of the lesson it is planned in | id ${_partId('f', 1)}\n'
          '- schema.png | 3 bytes | application/octet-stream | visible to '
          'pupils: always | id ${_partId('f', 2)}\n'
          '\n'
          'Lesfiche ${_lesson.id}\n',
        ),
      );
      expect(
        text,
        contains(
          'Attachments:\n'
          '1. lussen.txt | 16 bytes | text/plain | visible to pupils: never | '
          'id ${_attachment.id}\n'
          '2. recursie.txt | 16 bytes | text/plain | visible to pupils: from '
          'the end of the lesson it is planned in | id ${_partId('f', 1)}\n'
          '3. schema.png | 3 bytes | application/octet-stream | visible to '
          'pupils: always | id ${_partId('f', 2)}\n',
        ),
      );
      expect(inFull(text), await ok('read_lesfiche', {'lesfiche': _lesson.id}));
    });

    test('a file of a name the lesfiche has already: the module keeps both, '
        'and the result says so', () async {
      final text = await onLesson('add_lesfiche_attachments', {
        'attachments': [
          {'path': file('lussen.txt')},
        ],
      });

      expect(
        text,
        startsWith(
          'Added 1 attachment to $_lussen:\n'
          '- lussen.txt | 16 bytes | text/plain | visible to pupils: always | '
          'id ${_partId('f', 1)}\n'
          'Note: the lesfiche already had an attachment named "lussen.txt". '
          'The module keeps both; tell the user, and tell them apart by their '
          'ids below (remove_lesfiche_attachment removes one by its id).\n'
          '\n',
        ),
      );
      expect(planner.writes, ['POST $_lessonPath/attachments']);
      expect(
        [for (final attachment in lesson().attachments) attachment.fileName],
        ['lussen.txt', 'lussen.txt'],
      );
    });

    test('refuses, before anything is sent, no files, a path that is not '
        'full, a file that is too large, and a visibility the web client '
        'does not offer', () async {
      await openSession();
      final present = file('recursie.txt');
      final big = file('groot.pdf', 'x' * (_limit + 1));
      Future<String> refused(List<Object?> attachments) => refusedOnLesson(
        'add_lesfiche_attachments',
        {'attachments': attachments},
      );

      expect(
        await refused([]),
        'attachments is empty: pass 1 to 10 files, each with the full path '
        'of a file on this PC. Nothing was sent.',
      );
      expect(
        await refused([
          {'path': 'recursie.txt'},
        ]),
        startsWith('"recursie.txt" in attachments is not a full path'),
      );
      expect(
        await refused([
          {'path': big},
        ]),
        startsWith('The file "groot.pdf" ($big) is 65 bytes, too large'),
      );
      expect(
        await refused([
          {'path': present, 'visibility': 'after_end:15'},
        ]),
        'the visibility of attachment 1 of attachments ("$present") is '
        'after_end:15, but the web client offers 1 to 14 days after the end '
        'of the lesson. Nothing was sent.',
      );
      expect(server.requests, isEmpty, reason: 'nothing was sent');
      expect(server.uploads.uploads, isEmpty);
    });

    test('Smartschool\'s upload step refuses a file: Smartschool\'s words, '
        'and the module is not asked to take it', () async {
      server.uploads.nextRefusals.add((400, FakeUploads.badNameText));

      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('recursie.txt')},
          ],
        }),
        'Smartschool refused the file "recursie.txt" (HTTP 400): '
        '"${FakeUploads.badNameText}" Rename the file, or leave it out. The '
        'lesfiche was not changed.',
      );
      expect(planner.writes, isEmpty);
      expect(lesson().attachments, hasLength(1));
    });

    test('a take of the files the module does not confirm: maybe added, or '
        'added with always when another visibility was asked for, with how '
        'to check it, and not sent again', () async {
      const maybe =
          'The addition of the file "recursie.txt" to the lesson lesfiche '
          '"Lussen" may or may not have been carried out: it was sent, but '
          'the Lesfiches module did not confirm it. The module gives every '
          'new attachment the visibility always, and the server sets the '
          'visibility asked for after that: a file may also have been added '
          'with always. Do not call add_lesfiche_attachments again for it: a '
          'second call adds the files a second time. First read the lesfiche '
          'with read_lesfiche (lesfiche b0000000-0000-4000-8000-000000000011) '
          'and compare its attachments; set a visibility that is not as '
          'asked with set_lesfiche_attachment_visibility. Then tell the user '
          'what you found.';
      final attachments = [
        {'path': file('recursie.txt'), 'visibility': 'never'},
      ];
      planner.lostAnswers.add('$_lessonPath/attachments');

      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': attachments,
        }),
        maybe,
      );
      expect(sentTo('$_lessonPath/attachments'), 1);
      expect(lesson().attachments, hasLength(2), reason: 'taken');
      expect(lesson().attachments.last.option, 'always', reason: 'not set');

      // Without a visibility to set, nothing is said about it.
      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('schema.png')},
          ],
        }),
        allOf(
          startsWith(
            'The addition of the file "schema.png" to the lesson lesfiche '
            '"Lussen" may or may not have been carried out: it was sent, but '
            'the Lesfiches module did not confirm it. Do not call '
            'add_lesfiche_attachments again for it: ',
          ),
          isNot(contains('always')),
        ),
      );
      expect(sentTo('$_lessonPath/attachments'), 2, reason: 'one per call');
    });

    test('the module takes the files, but does not confirm a visibility (a '
        '500): the files were added, with their ids, and the visibility '
        'not set as a call that sets it, without a read; the call it gives '
        'sets it', () async {
      final path = fakeLesficheDetailPath(_assignment);
      final change = '$path/attachments/${_partId('f', 1)}/change-visibility';
      planner.failing[change] = 500;
      FakeLesfiche assignment() =>
          planner.lesfiches.singleWhere((each) => each.id == _assignment.id);

      final text = await error('add_lesfiche_attachments', {
        'lesfiche': _assignment.id,
        'type': 'assignment',
        'attachments': [
          {'path': file('recursie.txt'), 'visibility': 'never'},
        ],
      });

      expect(
        text,
        'Added 1 attachment to the assignment lesfiche "Lussen", but not '
        'every visibility asked for was set (each attachment with when '
        'pupils see it as far as the server knows):\n'
        '- recursie.txt | 16 bytes | text/plain | visible to pupils: always | '
        'id ${_partId('f', 1)}\n'
        'The module gives every new attachment the visibility always, and '
        'the server sets the visibility asked for after that. Setting the '
        'one of "recursie.txt" failed: it was sent, but the Lesfiches module '
        'did not confirm it, so it may or may not have been set.\n'
        'The file is on the lesfiche: do not call add_lesfiche_attachments '
        'again for it, as a second call adds it a second time. Set the '
        'visibility with set_lesfiche_attachment_visibility instead (setting '
        'one that went through again is harmless), and tell the user:\n'
        '- "recursie.txt": set_lesfiche_attachment_visibility (lesfiche '
        '${_assignment.id}, type assignment, attachment_id '
        '${_partId('f', 1)}, visibility never)',
      );
      expect(sentTo('$path/attachments'), 1, reason: 'taken once');
      expect(sentTo(change), 1, reason: 'not sent again');
      expect(server.requests.last, 'POST $change', reason: 'no read after it');
      expect(assignment().attachments.last.option, 'always');

      planner.failing.clear();
      expect(
        await ok('set_lesfiche_attachment_visibility', {
          'lesfiche': _assignment.id,
          'type': 'assignment',
          'attachment_id': _partId('f', 1),
          'visibility': 'never',
        }),
        startsWith(
          'Pupils now see the attachment "recursie.txt" of the assignment '
          'lesfiche "Lussen": never (before: always).\n',
        ),
      );
      expect(assignment().attachments.last.option, 'never');
      expect(sentTo('$path/attachments'), 1);
    });

    test('a visibility the module refuses (a bare 400): the attachments, '
        'each with when pupils see it as far as known, and the visibilities '
        'not set, that one and those after it, which were not tried, each as '
        'a call that sets it', () async {
      String change(int n) =>
          '$_lessonPath/attachments/${_partId('f', n)}/change-visibility';
      planner.failing[change(2)] = 400;

      final text = await refusedOnLesson('add_lesfiche_attachments', {
        'attachments': [
          {'path': file('a.txt'), 'visibility': 'at_end'},
          {'path': file('b.txt'), 'visibility': 'never'},
          {'path': file('c.txt'), 'visibility': 'after_end:3'},
        ],
      });

      expect(
        text,
        'Added 3 attachments to $_lussen, but not every visibility asked for '
        'was set (each attachment with when pupils see it as far as the '
        'server knows):\n'
        '- a.txt | 16 bytes | text/plain | visible to pupils: from the end of '
        'the lesson it is planned in | id ${_partId('f', 1)}\n'
        '- b.txt | 16 bytes | text/plain | visible to pupils: always | id '
        '${_partId('f', 2)}\n'
        '- c.txt | 16 bytes | text/plain | visible to pupils: always | id '
        '${_partId('f', 3)}\n'
        'The module gives every new attachment the visibility always, and '
        'the server sets the visibility asked for after that. Setting the '
        'one of "b.txt" failed: the Lesfiches module refused it (HTTP 400), '
        'without saying why, so it was not set. The server stopped there, '
        'without setting the one of "c.txt".\n'
        'The files are on the lesfiche: do not call add_lesfiche_attachments '
        'again for them, as a second call adds them a second time. Set each '
        'visibility with set_lesfiche_attachment_visibility instead (setting '
        'one that went through again is harmless), and tell the user:\n'
        '- "b.txt": set_lesfiche_attachment_visibility (lesfiche '
        '${_lesson.id}, attachment_id ${_partId('f', 2)}, visibility never)\n'
        '- "c.txt": set_lesfiche_attachment_visibility (lesfiche '
        '${_lesson.id}, attachment_id ${_partId('f', 3)}, visibility '
        'after_end:3)',
      );
      expect(planner.writes, [
        'POST $_lessonPath/attachments',
        'POST ${change(1)}',
        'POST ${change(2)}',
      ], reason: 'taken once, and the third visibility not tried');

      planner.failing.clear();
      for (final (n, visibility) in [(2, 'never'), (3, 'after_end:3')]) {
        await onLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _partId('f', n),
          'visibility': visibility,
        });
      }
      expect(
        [
          for (final attachment in lesson().attachments)
            (attachment.fileName, attachment.option),
        ],
        [
          ('lussen.txt', 'never'),
          ('a.txt', 'at-end'),
          ('b.txt', 'never'),
          ('c.txt', 'days-after-end'),
        ],
      );
    });

    test('a visibility the module answers with 404: not set, as the lesfiche '
        'went to the trash or the attachment was removed meanwhile', () async {
      planner.failing['$_lessonPath/attachments/${_partId('f', 1)}/'
              'change-visibility'] =
          404;

      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('recursie.txt'), 'visibility': 'at_end'},
          ],
        }),
        allOf(
          startsWith('Added 1 attachment to $_lussen, but not every '),
          contains(
            'Setting the one of "recursie.txt" failed: the Lesfiches module '
            'answered it with HTTP 404, so it was not set (the lesfiche was '
            'moved to the trash, or the attachment removed, meanwhile).\n',
          ),
          endsWith('attachment_id ${_partId('f', 1)}, visibility at_end)'),
        ),
      );
      expect(sentTo('$_lessonPath/attachments'), 1);
    });

    test('Smartschool refuses the session for a visibility, also after the '
        'library logged in again: the files were added and the visibility '
        'was not set; the session does not repeat the call', () async {
      final take = '$_lessonPath/attachments';
      final change = '$take/${_partId('f', 1)}/change-visibility';
      planner.beforeAnswer = (method, path) {
        if (method != 'POST' || path != take) return;
        server
          ..rejectsAfterLogin = 1
          ..expireSessionBefore(
            (RequestOptions request) =>
                request.method == 'POST' && request.uri.path == change,
          );
      };

      expect(
        await refusedOnLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('recursie.txt'), 'visibility': 'at_start'},
          ],
        }),
        allOf(
          startsWith('Added 1 attachment to $_lussen, but not every '),
          contains(
            'Setting the one of "recursie.txt" failed: Smartschool did not '
            'accept the session, so it was not set.\n',
          ),
          endsWith(
            '- "recursie.txt": set_lesfiche_attachment_visibility (lesfiche '
            '${_lesson.id}, attachment_id ${_partId('f', 1)}, visibility '
            'at_start)',
          ),
        ),
      );
      expect(sentTo(take), 1, reason: 'taken once');
      expect(planner.writes, ['POST $take'], reason: 'the change was refused');
      expect(server.logins, 2, reason: 'the library logged in again once');
      expect(lesson().attachments.last.option, 'always');
    });

    test('Smartschool refuses the session for the take of the files, which '
        'the library does not send again: the session repeats the call, '
        'which reads the lesfiche, uploads the files again into a new '
        'directory, and adds them once', () async {
      final path = '$_lessonPath/attachments';
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' && request.uri.path == path,
      );

      expect(
        await onLesson('add_lesfiche_attachments', {
          'attachments': [
            {'path': file('recursie.txt')},
          ],
        }),
        startsWith('Added 1 attachment to $_lussen:\n- recursie.txt | '),
      );
      expect(sentTo(path), 2, reason: 'the refused one and one');
      final first = server.requests.indexOf('POST $path');
      expect(
        server.requests[first + 1],
        'GET /login',
        reason:
            'after a refused session the library logs in before the next '
            'request (yvanvds/dartschool#134)',
      );
      expect(planner.writes, ['POST $path'], reason: 'taken once');
      expect(server.logins, 2);
      expect(server.uploads.directories, hasLength(2));
      expect(bodiesOf(path).single, {
        'randomDir': server.uploads.directories.keys.last,
      });
      expect(
        [for (final attachment in lesson().attachments) attachment.fileName],
        ['lussen.txt', 'recursie.txt'],
      );
    });
  });

  group('set_lesfiche_attachment_visibility', () {
    test('sets when pupils see an attachment, by its id, and says what it '
        'was', () async {
      await openSession();
      final path =
          '$_lessonPath/attachments/${_attachment.id}/change-visibility';

      final text = await onLesson('set_lesfiche_attachment_visibility', {
        'attachment_id': _attachment.id,
        'visibility': 'after_end:14',
      });

      expect(server.requests, [
        'GET $_lessonPath',
        'POST $path',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ]);
      expect(bodiesOf(path), [
        {'newVisibility': _visibility('days-after-end', 14)},
      ]);
      expect(
        text,
        startsWith(
          'Pupils now see the attachment "lussen.txt" of $_lussen: from 14 '
          'days after the end of the lesson it is planned in (before: '
          'never).\n\nLesfiche ${_lesson.id}\n',
        ),
      );
      expect(
        text,
        contains(
          '\n1. lussen.txt | 16 bytes | text/plain | visible to pupils: from '
          '14 days after the end of the lesson it is planned in | id '
          '${_attachment.id}\n',
        ),
      );

      expect(
        await onLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _attachment.id,
          'visibility': 'after_end:14',
        }),
        startsWith(
          'Pupils now see the attachment "lussen.txt" of $_lussen: from 14 '
          'days after the end of the lesson it is planned in (as before).\n',
        ),
      );
    });

    test('refuses, before anything is sent, a visibility that is empty or '
        'not one, and an empty id; after reading, an id the lesfiche does '
        'not have', () async {
      await openSession();

      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _attachment.id,
          'visibility': ' ',
        }),
        startsWith(
          'visibility is missing: pass when pupils see the file, always (the '
          'default), never, ',
        ),
      );
      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _attachment.id,
          'visibility': 'soms',
        }),
        startsWith('visibility is "soms", which is not a visibility: pass '),
      );
      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': ' id ',
          'visibility': 'never',
        }),
        startsWith('attachment_id is empty: pass the id of the attachment '),
      );
      expect(server.requests, isEmpty, reason: 'nothing was sent');

      const unknown = 'f0000000-0000-4000-8000-0000000000ff';
      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': unknown,
          'visibility': 'never',
        }),
        'The lesson lesfiche "Lussen" has no attachment with id $unknown. '
        'Nothing was sent. Its attachments, each with its id at the end:\n'
        '1. lussen.txt | 16 bytes | text/plain | visible to pupils: never | '
        'id ${_attachment.id}',
      );
      expect(planner.writes, isEmpty);
    });

    test('a change the module does not confirm (a 500): maybe saved, with '
        'how to check it', () async {
      planner.failing['$_lessonPath/attachments/${_attachment.id}/'
              'change-visibility'] =
          500;

      expect(
        await refusedOnLesson('set_lesfiche_attachment_visibility', {
          'attachment_id': _attachment.id,
          'visibility': 'always',
        }),
        'The change of the visibility of the attachment "lussen.txt" of '
        '$_lussen may or may not have been saved: it was sent, but the '
        'Lesfiches module did not confirm it. Do not call '
        'set_lesfiche_attachment_visibility again for it. First read the '
        'lesfiche with read_lesfiche (lesfiche ${_lesson.id}) and compare '
        'when pupils see it. Then tell the user what you found.',
      );
    });
  });

  group('remove_lesfiche_attachment', () {
    test('removes an attachment, by its id: a DELETE, answered with 204, and '
        'the lesfiche back without it', () async {
      await openSession();

      final text = await onLesson('remove_lesfiche_attachment', {
        'attachment_id': _attachment.id,
      });

      final path = '$_lessonPath/attachments/${_attachment.id}';
      expect(server.requests, [
        'GET $_lessonPath',
        'DELETE $path',
        'GET $_lessonPath',
        'GET $fakeCourseListPath',
      ]);
      expect(planner.writes, ['DELETE $path']);
      expect(
        text,
        startsWith(
          'Removed the attachment "lussen.txt" (16 bytes) from $_lussen.\n'
          '\n'
          'Lesfiche ${_lesson.id}\n',
        ),
      );
      expect(text, contains('\nAttachments: none\n'));
      expect(lesson().attachments, isEmpty);
    });

    test('a removal the module does not confirm (a 500): maybe removed; the '
        'lesfiche read back after a removal that went through fails: the '
        'result says so', () async {
      final path = '$_lessonPath/attachments/${_attachment.id}';
      planner.failing[path] = 500;
      expect(
        await refusedOnLesson('remove_lesfiche_attachment', {
          'attachment_id': _attachment.id,
        }),
        'The attachment "lussen.txt" may or may not have been removed from '
        '$_lussen: it was sent, but the Lesfiches module did not confirm '
        'it. Do not call remove_lesfiche_attachment again for it. First read '
        'the lesfiche with read_lesfiche (lesfiche ${_lesson.id}) to see '
        'whether it is still there. Then tell the user what you found.',
      );

      planner.failing.clear();
      planner.beforeAnswer = (method, path) {
        if (method == 'DELETE') planner.failing[_lessonPath] = 500;
      };
      expect(
        await onLesson('remove_lesfiche_attachment', {
          'attachment_id': _attachment.id,
        }),
        'Removed the attachment "lussen.txt" (16 bytes) from $_lussen.\n'
        '\n'
        'The change went through, but reading the lesfiche back failed: The '
        'Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log. Read it with read_lesfiche (lesfiche ${_lesson.id}) to '
        'see it.',
      );
      expect(lesson().attachments, isEmpty);
    });
  });
}
