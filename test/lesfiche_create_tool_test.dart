/// `create_lesfiche` (#114), called over MCP on the real server, session,
/// library and local files, against a fake Smartschool whose Lesfiches
/// module makes a lesfiche from the web client's body as dartschool's
/// captures of the create show it (`test/lesson_content_write_test.dart`
/// there, dartschool#129: `201` with `{"id"}` only, a bare `400`), behind
/// the shared fake upload step, and serves the detail it reads back; whose
/// course list names the school's courses; and whose planner plans a
/// lesfiche into an empty lesson hour (`test/support/fake_planner.dart`).
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/plan_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// The size limit of `create_lesfiche`'s attachments here.
const _limit = 64;

const _api = '/lesson-content/api/v1';

/// The create of a lesson lesfiche, and of an assignment lesfiche.
final _createLesson = fakeLesficheCreatePath();
final _createAssignment = fakeLesficheCreatePath('assignments');

/// The detail of the [n]th lesfiche the fake makes, of the kind [type].
String _detailPath(int n, [String type = 'lessons']) =>
    '$_api/$type/${fakeNewLesficheId(n)}';

/// The id the fake gives the [n]th weblink or attachment its creates make,
/// with [prefix] `e` for a weblink and `f` for an attachment.
String _partId(String prefix, int n) =>
    '${prefix}1000000-0000-4000-9000-${'$n'.padLeft(12, '0')}';

/// The web client's body for a lesfiche named [name] (dartschool#129), with
/// every list it sends.
Map<String, Object?> _body({
  required String name,
  String icon = 'document_observation',
  String? assignmentType,
  String publicInfo = '',
  String privateInfo = '',
  List<Object?> courses = const [],
  List<Object?> weblinks = const [],
  String? randomDir,
  Map<String, Object?> visibilityOptions = const {},
}) => {
  'name': name,
  'assignmentType': ?assignmentType,
  'icon': icon,
  'publicInfo': publicInfo,
  'privateInfo': privateInfo,
  'courses': courses,
  'goals': <Object?>[],
  'labels': <Object?>[],
  'weblinks': weblinks,
  'partnerWeblinks': <Object?>[],
  'miniDBItems': <Object?>[],
  'deeplinks': <Object?>[],
  'randomDir': randomDir,
  'previousLessonContent': null,
  'visibilityOptions': visibilityOptions,
};

/// A visibility as the module takes it.
Map<String, Object?> _visibility(String option, [int? days]) => {
  'option': option,
  'daysAfterEnd': days,
};

/// The course informatica as a create sends it.
const _informatica = {
  'platformId': 4069,
  'id': 'c0000000-0000-4000-8000-000000000005',
};

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
    planner.assignmentTypes.addAll(FakeAssignmentType.school);
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
        createLesficheTool(session, maxBytes: _limit),
        planLesficheTool(session),
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

  /// The bodies of the creates that reached the Lesfiches module at [path].
  List<Object?> bodiesOf(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
  ];

  /// How many POSTs to [path] reached the fake Smartschool, also those it
  /// refused because the session was not accepted.
  int postsTo(String path) =>
      server.requests.where((request) => request == 'POST $path').length;

  /// The lesfiches of the fake named [name], of the kind [type].
  List<FakeLesfiche> named(String name, [String type = 'lessons']) => [
    for (final lesfiche in planner.lesfiches)
      if (lesfiche.name == name && lesfiche.type == type) lesfiche,
  ];

  /// The lesfiche as `read_lesfiche` shows it: what a create's result ends
  /// with, after its own lines and a blank line.
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

    test('as a write Claude Desktop asks approval for every time, not '
        'idempotent: a second call makes a second lesfiche', () {
      final tool = tools['create_lesfiche']!;
      expect(tool.toolAnnotations!.readOnlyHint, isFalse);
      expect(tool.toolAnnotations!.destructiveHint, isTrue);
      expect(tool.toolAnnotations!.idempotentHint, isFalse);
      expect(tool.toolAnnotations!.openWorldHint, isTrue);
      expect(tool.inputSchema.required, ['name']);
      expect(tool.inputSchema.properties!.keys, [
        'name',
        'type',
        'assignment_type',
        'public_info',
        'private_info',
        'courses',
        'weblinks',
        'attachments',
        'icon',
      ]);
      expect(
        tool.description,
        allOf(
          contains(
            'only call this tool after the user has explicitly '
            'confirmed it; then call it once per lesfiche',
          ),
          contains(
            'pupils see nothing of a lesfiche until a lesson is '
            'planned from it',
          ),
          contains('Labels are not offered'),
          contains('up to 10 files of 64 bytes each'),
          contains('always (the default), never, at_start'),
          contains(
            'with its id for plan_lesfiche, read_lesfiche and '
            'edit_lesfiche, which changes it later',
          ),
        ),
      );
    });

    test('plan_lesfiche points to it for a lesfiche that does not exist '
        'yet', () {
      expect(
        tools['plan_lesfiche']!.description,
        endsWith(
          'For a lesfiche that does not exist yet, make it first with '
          'create_lesfiche.',
        ),
      );
    });
  });

  group('create_lesfiche', () {
    test('makes a lesson lesfiche with its info, a course, weblinks and '
        'attachments: reads the lesfiches and the course list, uploads the '
        'files into a new directory, sends the web client\'s body once, and '
        'gives the lesfiche back as read_lesfiche shows it', () async {
      await openSession();
      final recursie = file('recursie.txt');
      final schema = file('schema.png', 'png');

      final text = await ok('create_lesfiche', {
        'name': '  Recursie ',
        'public_info':
            'Hoofdstuk 5\n\nLees eerst de inleiding.\nMaak dan oefening 1.',
        'private_info': 'Voor mij: <b>niet</b> vergeten',
        'courses': ['Informatica'],
        'weblinks': [
          {
            'name': 'Oefeningen',
            'url': 'https://example.com/oefeningen',
            'visibility': 'at_end',
          },
          {
            'name': 'Quiz',
            'url': 'example.com/quiz',
            'visibility': 'after_end:3',
          },
        ],
        'attachments': [
          {'path': recursie, 'visibility': 'never'},
          {'path': schema},
        ],
      });

      final id = fakeNewLesficheId(1);
      final dir = server.uploads.directories.keys.single;
      expect(server.uploads.uploads, [
        (dir, 'recursie.txt'),
        (dir, 'schema.png'),
      ]);
      expect(
        server.requests,
        [
          'GET $fakeLesfichesPath',
          'GET $fakeCourseListPath',
          'GET $fakeCourseListPath',
          'GET ${FakeUploads.directoryPath}',
          'POST ${FakeUploads.uploadPath}',
          'POST ${FakeUploads.uploadPath}',
          'POST $_createLesson',
          'GET ${_detailPath(1)}',
        ],
        reason:
            'the tool\'s reads, the library\'s check, upload, create, '
            'read back',
      );
      expect(bodiesOf(_createLesson), [
        _body(
          name: 'Recursie',
          publicInfo:
              '<p>Hoofdstuk 5</p><p>Lees eerst de inleiding.<br />Maak dan '
              'oefening 1.</p>',
          privateInfo: '<p>Voor mij: &lt;b&gt;niet&lt;/b&gt; vergeten</p>',
          courses: [_informatica],
          weblinks: [
            {
              'name': 'Oefeningen',
              'url': 'https://example.com/oefeningen',
              'icon': 'earth',
              'visibility': _visibility('at-end'),
            },
            {
              'name': 'Quiz',
              'url': 'http://example.com/quiz',
              'icon': 'earth',
              'visibility': _visibility('days-after-end', 3),
            },
          ],
          randomDir: dir,
          visibilityOptions: {
            'recursie.txt': _visibility('never'),
            'schema.png': _visibility('always'),
          },
        ),
      ]);
      expect(planner.writes, ['POST $_createLesson'], reason: 'sent once');

      expect(
        text,
        startsWith(
          'Made the lesson lesfiche "Recursie" in your own library ("Mijn '
          'lesfiches") of the Lesfiches module. Pupils see nothing of it '
          'until it is planned.\n'
          'Its id is $id: plan it into an empty lesson hour of your own '
          'planner with plan_lesfiche, and read it with read_lesfiche '
          '(lesfiche $id).\n'
          'Change it with edit_lesfiche, its weblinks with '
          'set_lesfiche_weblink and remove_lesfiche_weblink, and its '
          'attachments with add_lesfiche_attachments, '
          'set_lesfiche_attachment_visibility and '
          'remove_lesfiche_attachment. Move it to the trash with '
          'trash_lesfiches. Labels are set in the Lesfiches module '
          'itself.\n'
          '\n'
          'Lesfiche $id\n'
          'Kind: lesson\n'
          'Name: Recursie\n'
          'Icon: document_observation\n'
          'Labels: none\n'
          'Courses: informatica\n'
          'In the module: visible\n'
          'Weblinks:\n'
          '- Oefeningen | https://example.com/oefeningen | icon earth | '
          'visible to pupils: from the end of the lesson it is planned in | '
          'id ${_partId('e', 1)}\n'
          '- Quiz | http://example.com/quiz | icon earth | visible to pupils: '
          'from 3 days after the end of the lesson it is planned in | id '
          '${_partId('e', 2)}\n'
          'Attachments:\n'
          '1. recursie.txt | 16 bytes | text/plain | visible to pupils: never '
          '| id ${_partId('f', 3)}\n'
          '2. schema.png | 3 bytes | application/octet-stream | visible to '
          'pupils: always | id ${_partId('f', 4)}\n'
          '\n'
          'Public info (what pupils see):\n'
          'Hoofdstuk 5\n',
        ),
      );
      expect(
        text,
        endsWith(
          'Private info (hidden from pupils):\n'
          'Voor mij: <b>niet</b> vergeten',
        ),
      );
      expect(
        inFull(text),
        await ok('read_lesfiche', {'lesfiche': id}),
        reason: 'the lesfiche as read_lesfiche shows it',
      );
      expect(
        await ok('list_lesfiches', {'query': 'recursie'}),
        contains('lesson | Recursie | no labels | informatica | visible | '),
      );
    });

    test('the lesfiche made is planned with plan_lesfiche, by the id the '
        'result gives', () async {
      final text = await ok('create_lesfiche', {
        'name': 'Recursie',
        'public_info': 'Hoofdstuk 5',
        'courses': ['informatica'],
      });
      final id = fakeNewLesficheId(1);
      expect(text, contains('Its id is $id: plan it'));

      expect(
        await ok('plan_lesfiche', {'hour': fakeOwnSlot.ref, 'lesfiche': id}),
        startsWith('Planned the lesfiche $id in the '),
      );
      expect(
        planner.writes.last,
        startsWith(
          'POST /planner/api/v1/planned-placeholders/4069/${fakeOwnSlot.id}'
          '/replace/planned-lessons',
        ),
      );
    });

    test('makes an assignment lesfiche of one of the school\'s types, by its '
        'abbreviation: checked against the types, sent to assignments/ with '
        'the assignment icon', () async {
      await openSession();

      final text = await ok('create_lesfiche', {
        'name': 'Taak: een eigen spel',
        'type': 'assignment',
        'assignment_type': 'kt',
      });

      final id = fakeNewLesficheId(1);
      expect(bodiesOf(_createAssignment), [
        _body(
          name: 'Taak: een eigen spel',
          icon: 'flags_red_yellow',
          assignmentType: FakeAssignmentType.kt.id,
        ),
      ]);
      expect(
        [for (final request in planner.requests) request.path],
        [
          fakeLesfichesPath,
          fakeAssignmentTypesPath,
          fakeAssignmentTypesPath,
          _createAssignment,
          _detailPath(1, 'assignments'),
        ],
        reason: 'the session\'s types, then the library\'s check of them',
      );
      expect(
        text,
        startsWith(
          'Made the assignment lesfiche "Taak: een eigen spel" in your own '
          'library ("Mijn lesfiches") of the Lesfiches module. Pupils see '
          'nothing of it until it is planned.\n'
          'Its id is $id: read it with read_lesfiche (lesfiche $id, type '
          'assignment). This server plans lesson lesfiches only; an '
          'assignment lesfiche is planned in Smartschool itself.\n'
          'Change it with edit_lesfiche, its weblinks with '
          'set_lesfiche_weblink and remove_lesfiche_weblink, and its '
          'attachments with add_lesfiche_attachments, '
          'set_lesfiche_attachment_visibility and '
          'remove_lesfiche_attachment. Move it to the trash with '
          'trash_lesfiches. Labels are set in the Lesfiches module '
          'itself.\n'
          'Note: you already had 1 other assignment lesfiche named "Taak: '
          'een eigen spel". The module keeps both; tell the user, who can '
          'tell them apart by their labels in the module:\n'
          '- assignment KT Kleine Taak | Taak: een eigen spel | labels '
          'Lussen | 1 course | visible | changed 2025-09-05 | id '
          '${fakeLesficheGame.id}\n'
          '\n'
          'Lesfiche $id\n'
          'Kind: assignment KT Kleine Taak\n'
          'Name: Taak: een eigen spel\n'
          'Icon: flags_red_yellow\n',
        ),
      );
      expect(
        inFull(text),
        await ok('read_lesfiche', {'lesfiche': id, 'type': 'assignment'}),
      );
    });

    test('a name that is taken is kept: the module makes a second lesfiche, '
        'and the result names the others of that name and kind', () async {
      final text = await ok('create_lesfiche', {'name': 'lussen'});

      expect(
        text,
        contains(
          '\nNote: you already had 1 other lesson lesfiche named "lussen". '
          'The module keeps both; tell the user, who can tell them apart by '
          'their labels in the module:\n'
          '- lesson | Lussen | no labels | 1 course | visible | changed '
          '2026-10-05 | id ${fakeLesficheDetailLesson.id}\n\n',
        ),
        reason: 'not the assignment lesfiche "Lussen"',
      );
      expect(named('Lussen'), hasLength(1));
      expect(named('lussen'), hasLength(1));

      // A second call makes a second one, which is why Claude is told to
      // call once per lesfiche.
      expect(
        await ok('create_lesfiche', {'name': 'lussen'}),
        contains('Note: you already had 2 other lesson lesfiches named '),
      );
      expect(named('lussen'), hasLength(2));
    });

    test('refuses, before anything is sent, a name that is empty or too '
        'long, a type without its assignment type and the other way round, '
        'a weblink without a name or with an address the web client '
        'refuses, a visibility it does not offer, and files the local-file '
        'helper refuses', () async {
      await openSession();
      final present = file('lussen.txt');
      final other = Directory('${files.path}${Platform.pathSeparator}andere')
        ..createSync();
      final copy = File('${other.path}${Platform.pathSeparator}LUSSEN.txt')
        ..writeAsStringSync('copy');
      final missing = '${files.path}${Platform.pathSeparator}weg.pdf';
      final big = file('groot.pdf', 'x' * (_limit + 1));
      final hidden = file('.verborgen');
      Future<String> refused(Map<String, Object?> arguments) =>
          error('create_lesfiche', {'name': 'Lussen', ...arguments});

      expect(
        await refused({'name': '   '}),
        'name is empty: give the lesfiche a name. Nothing was sent.',
      );
      expect(
        await refused({'name': 'x' * 256}),
        'name is 256 characters long, and the Lesfiches module takes at most '
        '255: shorten it. Nothing was sent.',
      );
      expect(
        await refused({'type': 'assignment'}),
        'assignment_type is missing: an assignment lesfiche has one of the '
        'school\'s assignment types. Pass it by its abbreviation or name, '
        'such as KT or Kleine Taak (list_class_assignments lists them). '
        'Nothing was sent.',
      );
      expect(
        await refused({'assignment_type': 'KT'}),
        'assignment_type is for an assignment lesfiche only: pass type '
        'assignment with it, or leave it out for a lesson lesfiche. Nothing '
        'was sent.',
      );
      expect(
        await refused({
          'weblinks': [
            {'name': ' ', 'url': 'https://example.com'},
          ],
        }),
        'weblink 1 of weblinks has no name: give it one. Nothing was sent.',
      );
      expect(
        await refused({
          'weblinks': [
            {'name': 'Oefeningen', 'url': 'https://example.com'},
            {'name': 'Quiz', 'url': 'geen url'},
          ],
        }),
        'weblink 2 of weblinks ("Quiz") has the url "geen url", which is not '
        'a web address the Lesfiches web client takes: pass one like '
        'https://example.com/page. Nothing was sent.',
      );
      expect(
        await refused({
          'weblinks': [
            {
              'name': 'Quiz',
              'url': 'https://example.com',
              'visibility': 'soms',
            },
          ],
        }),
        'the visibility of weblink 1 of weblinks ("Quiz") is "soms", which is '
        'not a visibility: pass always (the default), never, at_start (from '
        'the start of the lesson it is planned in), at_end (from its end) or '
        'after_end:N (from N days after its end, N from 1 to 14). Nothing was '
        'sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': present, 'visibility': 'after_end:15'},
          ],
        }),
        'the visibility of attachment 1 of attachments ("$present") is '
        'after_end:15, but the web client offers 1 to 14 days after the end '
        'of the lesson. Nothing was sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': 'lussen.txt'},
          ],
        }),
        '"lussen.txt" in attachments is not a full path: give the whole path '
        'of the file, starting with the drive, like '
        'C:\\Users\\jan\\Documents\\brief.docx. Nothing was sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': missing},
          ],
        }),
        'There is no file "$missing" on this PC (any more): check the path. '
        'Nothing was sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': present},
            {'path': copy.path},
          ],
        }),
        'attachments holds two files named "LUSSEN.txt" ($present and '
        '${copy.path}), which Smartschool would store under the same name: '
        'send one of them, or rename one first. Nothing was sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': big},
          ],
        }),
        'The file "groot.pdf" ($big) is 65 bytes, too large to send from '
        'here: files up to 64 bytes can be sent. The user can add it in '
        'Smartschool. Nothing was sent.',
      );
      expect(
        await refused({
          'attachments': [
            {'path': hidden},
          ],
        }),
        startsWith('Smartschool does not take a file named ".verborgen"'),
      );

      expect(server.requests, isEmpty, reason: 'nothing was sent');
      expect(server.uploads.uploads, isEmpty);
    });

    test('refuses, after reading but before anything is made, a course the '
        'school does not have and an assignment type that is not the '
        'school\'s; a name that two courses have asks for the id', () async {
      planner.courseList.add(
        const FakePlannerCourse(
          'c0000000-0000-4000-8000-000000000099',
          'Informatica',
        ),
      );
      final present = file('lussen.txt');

      expect(
        await error('create_lesfiche', {
          'name': 'Lussen',
          'courses': ['geschiedenis', 'chemie', 'aardrijkskunde'],
          'attachments': [
            {'path': present},
          ],
        }),
        'courses holds "geschiedenis", "aardrijkskunde", which are not '
        'courses of the school\'s course list. Its courses are biologie, '
        'chemie, economie, Informatica, informatica, lichamelijke opvoeding, '
        'Nederlands, wiskunde. Pass a course by its name as list_lesfiches or '
        'list_planner show it. Nothing was sent.',
      );
      expect(
        await error('create_lesfiche', {
          'name': 'Lussen',
          'courses': ['informatica'],
        }),
        'courses holds "informatica", which names 2 of the school\'s courses: '
        'informatica (id c0000000-0000-4000-8000-000000000005), Informatica '
        '(id c0000000-0000-4000-8000-000000000099). Ask the user which one '
        'is meant, and pass its id instead. Nothing was sent.',
      );
      expect(
        await error('create_lesfiche', {
          'name': 'Taak',
          'type': 'assignment',
          'assignment_type': 'XX',
        }),
        'assignment_type "XX" is not one of the school\'s assignment types: '
        'pass one by its abbreviation or its name. The school\'s assignment '
        'types are GO Grote Overhoring, GT Grote Taak, KO Kleine Overhoring, '
        'KT Kleine Taak, MB Meebrengen, V Voorbereiding. Nothing was sent.',
      );
      expect(planner.writes, isEmpty);
      expect(server.uploads.uploads, isEmpty);

      // By its id, the course is found.
      await ok('create_lesfiche', {
        'name': 'Lussen',
        'courses': ['C0000000-0000-4000-8000-000000000099'],
      });
      expect((bodiesOf(_createLesson).single! as Map)['courses'], [
        {'platformId': 4069, 'id': 'c0000000-0000-4000-8000-000000000099'},
      ]);
    });

    test('the school\'s types changed since the session read them: the '
        'library\'s check refuses the type before sending, and every tool on '
        'the session takes the types as they are now', () async {
      await ok('create_lesfiche', {
        'name': 'Taak',
        'type': 'assignment',
        'assignment_type': 'KT',
      });
      planner.assignmentTypes.remove(FakeAssignmentType.kt);

      const types =
          'The school\'s assignment types are GO Grote Overhoring, GT Grote '
          'Taak, KO Kleine Overhoring, MB Meebrengen, V Voorbereiding.';
      expect(
        await error('create_lesfiche', {
          'name': 'Taak 2',
          'type': 'assignment',
          'assignment_type': 'KT',
        }),
        'assignment_type "KT" named the assignment type KT Kleine Taak, '
        'which is no longer one of the school\'s assignment types: they '
        'changed since the server read them. $types Ask the user which one '
        'to use instead. Nothing was sent.',
      );
      expect(
        await error('create_lesfiche', {
          'name': 'Taak 2',
          'type': 'assignment',
          'assignment_type': 'KT',
        }),
        'assignment_type "KT" is not one of the school\'s assignment types: '
        'pass one by its abbreviation or its name. $types Nothing was sent.',
      );
      expect(planner.writes, ['POST $_createAssignment'], reason: 'the first');
    });

    test('the Lesfiches module refuses the create with a bare 400: nothing '
        'was made', () async {
      planner.failing[_createLesson] = 400;

      expect(
        await error('create_lesfiche', {'name': 'Recursie'}),
        'The Lesfiches module refused the lesson lesfiche "Recursie" (HTTP '
        '400), without saying why. No lesfiche was made.',
      );
      expect(named('Recursie'), isEmpty);
      expect(postsTo(_createLesson), 1);
    });

    test('Smartschool\'s upload step refuses a file: Smartschool\'s words, '
        'and the module is not asked to make the lesfiche', () async {
      server.uploads.nextRefusals.add((400, FakeUploads.badNameText));

      expect(
        await error('create_lesfiche', {
          'name': 'Recursie',
          'attachments': [
            {'path': file('recursie.txt')},
          ],
        }),
        'Smartschool refused the file "recursie.txt" (HTTP 400): '
        '"${FakeUploads.badNameText}" Rename the file, or leave it out. No '
        'lesfiche was made.',
      );
      expect(server.uploads.uploads, hasLength(1));
      expect(planner.writes, isEmpty);
    });

    test('the create is answered with the id, but reading it back fails: '
        'made, with its id, and Claude is told to read it rather than call '
        'again', () async {
      planner.failing[_detailPath(1)] = 500;
      final id = fakeNewLesficheId(1);

      expect(
        await error('create_lesfiche', {
          'name': 'Recursie',
          'courses': ['informatica'],
        }),
        'The lesson lesfiche "Recursie" was made, with id $id, but reading '
        'it back failed. Do not call create_lesfiche again for it: it '
        'exists, and a second call would make a second lesfiche. First read '
        'it with read_lesfiche (lesfiche $id) to see what it holds; then '
        'tell the user what you found. What is missing can be added with '
        'edit_lesfiche (the name, the courses), set_lesfiche_weblink or '
        'add_lesfiche_attachments.',
      );
      expect(postsTo(_createLesson), 1, reason: 'not sent again');
      planner.failing.remove(_detailPath(1));
      expect(
        await ok('read_lesfiche', {'lesfiche': id}),
        contains('\nName: Recursie\n'),
      );
    });

    test('the lesfiche read back does not show what was sent: made, with '
        'its id', () async {
      // The module drops the weblink, as the library's check guards
      // against.
      planner.beforeAnswer = (method, path) {
        if (method != 'GET' || path != _detailPath(1, 'assignments')) return;
        final index = planner.lesfiches.indexWhere(
          (lesfiche) => lesfiche.id == fakeNewLesficheId(1),
        );
        final made = planner.lesfiches[index];
        planner.lesfiches[index] = FakeLesfiche(
          id: made.id,
          name: made.name,
          type: made.type,
          icon: made.icon,
          assignmentType: made.assignmentType,
        );
      };
      final id = fakeNewLesficheId(1);

      expect(
        await error('create_lesfiche', {
          'name': 'Taak',
          'type': 'assignment',
          'assignment_type': 'Kleine Taak',
          'weblinks': [
            {'name': 'Oefeningen', 'url': 'https://example.com/oefeningen'},
          ],
        }),
        'The assignment lesfiche "Taak" was made, with id $id, but what the '
        'Lesfiches module shows of it does not match everything that was '
        'sent. Do not call create_lesfiche again for it: it exists, and a '
        'second call would make a second lesfiche. First read it with '
        'read_lesfiche (lesfiche $id, type assignment) to see what it holds; '
        'then tell the user what you found. What is missing can be added with '
        'edit_lesfiche (the name, the courses), set_lesfiche_weblink or '
        'add_lesfiche_attachments.',
      );
      expect(postsTo(_createAssignment), 1);
    });

    test('a create the module does not answer, or answers with a 500: maybe '
        'made, with how to check it, and not sent again', () async {
      const maybe =
          'The lesson lesfiche "Recursie" may or may not have been made: it '
          'was sent, but the Lesfiches module did not confirm it. Do not call '
          'create_lesfiche again for it: the module does not refuse a name '
          'that is taken, so a second call could make it twice. First list '
          'the lesfiches with list_lesfiches (type lessons, query '
          '"Recursie") to see whether it is there. Then tell the user what '
          'you found.';
      planner.lostAnswers.add(_createLesson);

      expect(await error('create_lesfiche', {'name': 'Recursie'}), maybe);
      expect(postsTo(_createLesson), 1);
      expect(named('Recursie'), hasLength(1), reason: 'it was made');

      planner.lostAnswers.clear();
      planner.failing[_createLesson] = 500;
      expect(await error('create_lesfiche', {'name': 'Recursie'}), maybe);
      expect(postsTo(_createLesson), 2, reason: 'one per call');
    });

    test('Smartschool refuses the session for the create, which the library '
        'does not send again: the session repeats the call, which the '
        'library sends in a new session, logging in first, and makes the '
        'lesfiche once', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' && request.uri.path == _createLesson,
      );

      expect(
        await ok('create_lesfiche', {'name': 'Recursie'}),
        startsWith('Made the lesson lesfiche "Recursie" '),
      );
      expect(postsTo(_createLesson), 2, reason: 'the refused one and one');
      final first = server.requests.indexOf('POST $_createLesson');
      final repeat = server.requests.sublist(first + 1);
      expect(
        repeat.first,
        'GET /login',
        reason:
            'after a refused session the library logs in before the next '
            'request (yvanvds/dartschool#134)',
      );
      expect(
        repeat.firstWhere((request) => request.contains('/lesson-content/')),
        'GET $fakeLesfichesPath',
        reason: 'the repeat reads the lesfiches first',
      );
      expect(planner.writes, ['POST $_createLesson'], reason: 'made once');
      expect(server.logins, 2);
      expect(named('Recursie'), hasLength(1));
    });

    test('with attachments, the repeat uploads them again into a new upload '
        'directory, and the lesfiche is made once with them', () async {
      server.expireSessionBefore(
        (RequestOptions request) =>
            request.method == 'POST' && request.uri.path == _createLesson,
      );

      expect(
        await ok('create_lesfiche', {
          'name': 'Recursie',
          'attachments': [
            {'path': file('recursie.txt')},
          ],
        }),
        contains('\n1. recursie.txt | 16 bytes | '),
      );
      expect(postsTo(_createLesson), 2, reason: 'the refused one and one');
      expect(planner.writes, ['POST $_createLesson'], reason: 'made once');
      final second = server.uploads.directories.keys.last;
      expect(server.uploads.directories, hasLength(2));
      expect((bodiesOf(_createLesson).single! as Map)['randomDir'], second);
      expect(named('Recursie').single.attachments, hasLength(1));
    });
  });
}
