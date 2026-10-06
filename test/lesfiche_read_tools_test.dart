/// `read_lesfiche`, `read_lesfiche_attachment` and `save_lesfiche_attachment`
/// (#113), called over MCP on the real server, session, library, document
/// reader and download folder, against a fake Smartschool whose Lesfiches
/// module serves dartschool's trimmed captures of the detail of a lesfiche,
/// with a weblink and an attachment, and of the download of that attachment
/// (dartschool#129), and whose course list names the courses of the
/// lesfiches (`test/support/fake_planner.dart`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_attachment_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/save_lesfiche_attachment_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';
import 'support/sample_documents.dart';

/// The size limit of `save_lesfiche_attachment` here, so a test needs no
/// 200 MB file.
const _limit = 1024 * 1024;

final _sep = Platform.pathSeparator;

/// The lesson lesfiche of dartschool's capture of the detail, as
/// `read_lesfiche` shows it.
final _lessonInFull =
    'Lesfiche ${fakeLesficheDetailLesson.id}\n'
    'Kind: lesson\n'
    'Name: Lussen\n'
    'Icon: document_observation\n'
    'Labels: none\n'
    'Courses: informatica\n'
    'In the module: visible\n'
    'Weblinks:\n'
    '- Oefeningen | https://example.com/oefeningen | icon earth | visible to '
    'pupils: from the end of the lesson it is planned in | id '
    'e0000000-0000-4000-8000-000000000021\n'
    'Attachments:\n'
    '1. lussen.txt | 16 bytes | text/plain | visible to pupils: never | id '
    'f0000000-0000-4000-8000-000000000031\n'
    '\n'
    'Public info (what pupils see):\n'
    'Hoofdstuk 3\n'
    '\n'
    'Private info (hidden from pupils):\n'
    'Voor mij';

/// A lesson lesfiche with an attachment of each kind [readable] gives.
FakeLesfiche _withFiles(List<FakeLesficheAttachment> attachments) =>
    FakeLesfiche(
      id: 'b0000000-0000-4000-8000-000000000031',
      name: 'Bestanden',
      attachments: attachments,
    );

/// An attachment of [_withFiles].
FakeLesficheAttachment _file(
  String n,
  String fileName, {
  List<int> content = const [],
  int? fileSize,
  String? mimeType = 'text/plain',
}) => FakeLesficheAttachment(
  id: 'f0000000-0000-4000-8000-0000000001$n',
  fileName: fileName,
  content: content,
  fileSize: fileSize,
  mimeType: mimeType,
);

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late Directory downloads;
  late DownloadFolder folder;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner
      ..loadLesfiches()
      ..loadLesficheDetails();
    final root = await Directory.systemTemp.createTemp('smartschool_fiche_');
    addTearDown(() => root.delete(recursive: true));
    downloads = Directory('${root.path}${_sep}Downloads${_sep}Smartschool');
    folder = DownloadFolder(
      downloads.path,
      origin: DownloadFolderOrigin(
        'set in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)',
        fix: 'choose another folder in "Downloadmap"',
      ),
    );
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        readLesficheTool(session),
        readLesficheAttachmentTool(session),
        saveLesficheAttachmentTool(session, folder, maxBytes: _limit),
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

  /// What a call of [tool] with [arguments] sends to the fake Smartschool
  /// once the session is open, as `METHOD path`; with [fails], a call that
  /// ends in an error. The session check reads the school's course list
  /// too, so a call of list_lesfiches opens the session first.
  Future<List<String>> requestsOf(
    String tool,
    Map<String, Object?> arguments, {
    bool fails = false,
  }) async {
    await ok('list_lesfiches', {});
    server.requests.clear();
    fails ? await error(tool, arguments) : await ok(tool, arguments);
    return [...server.requests];
  }

  /// The names in the download folder, sorted, without the list of saved
  /// files; empty when it does not exist.
  List<String> saved() =>
      !downloads.existsSync()
            ? []
            : ([
                for (final entity in downloads.listSync())
                  entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
              ]..remove(DownloadFolder.manifestName))
        ..sort();

  File savedFile(String name) => File('${downloads.path}$_sep$name');

  final lesson = fakeLesficheDetailLesson;
  final lussen = lesson.attachments.single;

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

    test('read_lesfiche and read_lesfiche_attachment as reads, '
        'save_lesfiche_attachment as writing a file without replacing one, '
        'as the other save tools', () {
      for (final name in ['read_lesfiche', 'read_lesfiche_attachment']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isTrue, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
      }
      final save = tools['save_lesfiche_attachment']!.toolAnnotations!;
      expect(save.readOnlyHint, isFalse);
      expect(save.destructiveHint, isFalse);
      expect(save.idempotentHint, isFalse);
      expect(save.openWorldHint, isTrue);
    });

    test('with the lesfiche, its kind and the attachment by number or '
        'name', () {
      final read = tools['read_lesfiche']!.inputSchema;
      expect(read.required, ['lesfiche']);
      expect(read.properties!.keys, ['lesfiche', 'type']);
      expect((read.properties!['type']! as Map)['enum'], [
        'lesson',
        'assignment',
      ]);
      for (final name in [
        'read_lesfiche_attachment',
        'save_lesfiche_attachment',
      ]) {
        final schema = tools[name]!.inputSchema;
        expect(schema.required, ['lesfiche', 'attachment'], reason: name);
        expect(schema.properties!.keys, [
          'lesfiche',
          'type',
          'attachment',
        ], reason: name);
        expect((schema.properties!['attachment']! as Map)['anyOf'], [
          {'type': 'integer', 'minimum': 1},
          {'type': 'string', 'minLength': 1},
        ], reason: name);
      }
    });

    test('the descriptions say where the id and the attachments come from, '
        'when pupils see a link or a file, and that nothing changes', () {
      final read = tools['read_lesfiche']!.description!;
      for (final phrase in [
        'by the id and kind list_lesfiches shows',
        'counts from the lesson the lesfiche is planned in',
        'read_planned_element',
        'read_lesfiche_attachment',
        'save_lesfiche_attachment',
        'Pass type assignment for an assignment lesfiche',
        'Reading changes nothing in Smartschool.',
      ]) {
        expect(read, contains(phrase));
      }
      final readFile = tools['read_lesfiche_attachment']!.description!;
      expect(readFile, contains('read_lesfiche lists the attachments'));
      expect(readFile, contains('25 MB'));
      expect(readFile, contains('save_lesfiche_attachment saves any'));
      final save = tools['save_lesfiche_attachment']!.description!;
      expect(save, contains('read_lesfiche lists the attachments'));
      expect(save, contains('up to 1.0 MB'));
      expect(save, contains('returned path with your own file'));
      expect(save, contains('deleted after 7 days'));
      expect(save, contains('never replaced'));
    });
  });

  group('read_lesfiche', () {
    test('reads a lesson lesfiche in full: its fields, the weblink and the '
        'attachment with when pupils see them, and both infos as text, its '
        'course named after the school\'s course list', () async {
      expect(await ok('read_lesfiche', {'lesfiche': lesson.id}), _lessonInFull);
      // The detail of the lesson, and the course list that names its
      // course; nothing else.
      expect(await requestsOf('read_lesfiche', {'lesfiche': lesson.id}), [
        'GET ${fakeLesficheDetailPath(lesson)}',
        'GET $fakeCourseListPath',
      ]);
      expect(planner.writes, isEmpty);
    });

    test('type lesson is the default; the id as list_lesfiches prints it, '
        'with "id " and in capitals, is the same lesfiche, shown with the '
        'module\'s id', () async {
      expect(
        await ok('read_lesfiche', {
          'lesfiche': ' id ${lesson.id.toUpperCase()} ',
          'type': 'lesson',
        }),
        _lessonInFull,
      );
    });

    test('reads an assignment lesfiche at assignments/{id}, with its '
        'type', () async {
      final assignment = fakeLesficheDetailAssignment;
      final arguments = {'lesfiche': assignment.id, 'type': 'assignment'};
      expect(
        await ok('read_lesfiche', arguments),
        _lessonInFull
            .replaceFirst(lesson.id, assignment.id)
            .replaceFirst('Kind: lesson', 'Kind: assignment KT Kleine Taak'),
      );
      expect(await requestsOf('read_lesfiche', arguments), [
        'GET ${fakeLesficheDetailPath(assignment)}',
        'GET $fakeCourseListPath',
      ]);
    });

    test('words when pupils see each weblink and attachment, and gives the '
        'labels, an icon and a hidden lesfiche', () async {
      const fiche = FakeLesfiche(
        id: 'b0000000-0000-4000-8000-000000000021',
        name: 'Zichtbaarheid',
        icon: 'flags_red_yellow',
        isVisible: false,
        labels: ['JAAR 6'],
        ownLabels: ['Herhaling'],
        weblinks: [
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000101',
            name: 'Altijd',
            url: 'https://example.com/1',
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000102',
            name: 'Nooit',
            url: 'https://example.com/2',
            option: 'never',
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000103',
            name: 'Begin',
            url: 'https://example.com/3',
            option: 'at-start',
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000104',
            name: 'Einde',
            url: 'https://example.com/4',
            option: 'at-end',
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000105',
            name: 'Een dag',
            url: 'https://example.com/5',
            icon: 'book',
            option: 'days-after-end',
            daysAfterEnd: 1,
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000106',
            name: 'Twee weken',
            url: 'https://example.com/6',
            option: 'days-after-end',
            daysAfterEnd: 14,
          ),
          FakeLesficheWeblink(
            id: 'e0000000-0000-4000-8000-000000000107',
            name: 'Later',
            url: 'https://example.com/7',
            option: 'after-exam',
            daysAfterEnd: 2,
          ),
        ],
        attachments: [
          FakeLesficheAttachment(
            id: 'f0000000-0000-4000-8000-000000000101',
            fileName: 'oplossingen.pdf',
            fileSize: 48213,
            mimeType: 'application/pdf',
            option: 'days-after-end',
            daysAfterEnd: 3,
          ),
          FakeLesficheAttachment(
            id: 'f0000000-0000-4000-8000-000000000102',
            fileName: 'opgave.txt',
            content: [104, 105],
            mimeType: null,
            option: 'at-start',
          ),
        ],
      );
      planner.lesfiches.add(fiche);

      expect(
        await ok('read_lesfiche', {'lesfiche': fiche.id}),
        'Lesfiche ${fiche.id}\n'
        'Kind: lesson\n'
        'Name: Zichtbaarheid\n'
        'Icon: flags_red_yellow\n'
        'Labels: JAAR 6, Herhaling\n'
        'Courses: none\n'
        'In the module: hidden\n'
        'Weblinks:\n'
        '- Altijd | https://example.com/1 | icon earth | visible to pupils: '
        'always | id e0000000-0000-4000-8000-000000000101\n'
        '- Nooit | https://example.com/2 | icon earth | visible to pupils: '
        'never | id e0000000-0000-4000-8000-000000000102\n'
        '- Begin | https://example.com/3 | icon earth | visible to pupils: '
        'from the start of the lesson it is planned in | id '
        'e0000000-0000-4000-8000-000000000103\n'
        '- Einde | https://example.com/4 | icon earth | visible to pupils: '
        'from the end of the lesson it is planned in | id '
        'e0000000-0000-4000-8000-000000000104\n'
        '- Een dag | https://example.com/5 | icon book | visible to pupils: '
        'from 1 day after the end of the lesson it is planned in | id '
        'e0000000-0000-4000-8000-000000000105\n'
        '- Twee weken | https://example.com/6 | icon earth | visible to '
        'pupils: from 14 days after the end of the lesson it is planned in | '
        'id e0000000-0000-4000-8000-000000000106\n'
        '- Later | https://example.com/7 | icon earth | visible to pupils: '
        'as the module\'s option "after-exam" with 2 days, which this server '
        'does not know | id e0000000-0000-4000-8000-000000000107\n'
        'Attachments:\n'
        '1. oplossingen.pdf | 47 KB | application/pdf | visible to pupils: '
        'from 3 days after the end of the lesson it is planned in | id '
        'f0000000-0000-4000-8000-000000000101\n'
        '2. opgave.txt | 2 bytes | visible to pupils: from the start of the '
        'lesson it is planned in | id f0000000-0000-4000-8000-000000000102\n'
        '\n'
        'Public info (what pupils see):\n'
        '(none)\n'
        '\n'
        'Private info (hidden from pupils):\n'
        '(none)',
      );
      // No course to name: the course list is not read.
      expect(await requestsOf('read_lesfiche', {'lesfiche': fiche.id}), [
        'GET ${fakeLesficheDetailPath(fiche)}',
      ]);
    });

    test('a lesfiche without weblinks or attachments, with weblinks of '
        'publishers it does not show, a course the course list does not '
        'name, and info as text', () async {
      const fysica = FakePlannerCourse(
        'c0000000-0000-4000-8000-000000000099',
        'fysica',
      );
      const fiche = FakeLesfiche(
        id: 'b0000000-0000-4000-8000-000000000022',
        name: 'Krachten',
        courses: [fakeInformatica, fysica],
        publicInfo: '<p><strong>Breng mee:</strong><br />je boek</p>',
        partnerWeblinks: 2,
      );
      planner.lesfiches.add(fiche);

      expect(
        await ok('read_lesfiche', {'lesfiche': fiche.id}),
        'Lesfiche ${fiche.id}\n'
        'Kind: lesson\n'
        'Name: Krachten\n'
        'Icon: document_observation\n'
        'Labels: none\n'
        'Courses: informatica, 1 unnamed course\n'
        'In the module: visible\n'
        'Weblinks: none\n'
        'Attachments: none\n'
        'Note: it also has 2 weblinks of publishers, which are not shown '
        'here.\n'
        'A course that the school\'s course list does not name shows as '
        '"unnamed course".\n'
        '\n'
        'Public info (what pupils see):\n'
        'Breng mee:\n'
        'je boek\n'
        '\n'
        'Private info (hidden from pupils):\n'
        '(none)',
      );
    });

    test('when the school\'s course list cannot be read, reads the lesfiche '
        'with how many courses it has, and says why', () async {
      // The session check reads the course list too: a first call opens the
      // session, then the list fails.
      await ok('list_lesfiches', {});
      planner.failing[fakeCourseListPath] = 500;

      expect(
        await ok('read_lesfiche', {'lesfiche': lesson.id}),
        _lessonInFull
            .replaceFirst(
              'Courses: informatica\n'
                  'In the module: visible\n',
              'Courses: 1 course\n'
                  'In the module: visible\n',
            )
            .replaceFirst(
              '\n\nPublic info',
              '\nNote: the names of the courses could not be read from the '
                  'school\'s course list (HTTP 500), so only the number of '
                  'courses is shown.\n\nPublic info',
            ),
      );
    });

    test('a made-up id, and a lesson\'s id asked for as an assignment (the '
        'module answers 404): take the id and the kind from '
        'list_lesfiches', () async {
      const madeUp = 'b0000000-0000-4000-8000-000000000999';
      expect(
        await error('read_lesfiche', {'lesfiche': madeUp}),
        'You have no lesson lesfiche with id $madeUp. Take the id and the '
        'kind from list_lesfiches (type all lists both kinds): an assignment '
        'lesfiche is read with type assignment, and a lesfiche asked for as '
        'the other kind is not found.',
      );
      expect(
        await error('read_lesfiche', {
          'lesfiche': lesson.id,
          'type': 'assignment',
        }),
        'You have no assignment lesfiche with id ${lesson.id}. Take the id '
        'and the kind from list_lesfiches (type all lists both kinds): a '
        'lesson lesfiche is read with type lesson, and a lesfiche asked for '
        'as the other kind is not found.',
      );
      expect(
        await requestsOf('read_lesfiche', {
          'lesfiche': lesson.id,
          'type': 'assignment',
        }, fails: true),
        ['GET /lesson-content/api/v1/assignments/${lesson.id}'],
      );
    });

    test('an id that is not a UUID is not found without a request (the '
        'module answers it with a bare 500); a name with spaces, or the id '
        'of a planner element, is refused as not an id', () async {
      for (final value in ['b0000000', 'Lussen']) {
        expect(
          await requestsOf('read_lesfiche', {'lesfiche': value}, fails: true),
          isEmpty,
        );
        expect(
          await error('read_lesfiche', {'lesfiche': value}),
          startsWith(
            'You have no lesson lesfiche with id $value. Take the id and the '
            'kind from list_lesfiches',
          ),
        );
      }
      for (final value in [
        'Herhaling: lussen',
        'planned-lessons/4069/225c0b54-0000-4000-8000-000000000000',
      ]) {
        expect(
          await error('read_lesfiche', {'lesfiche': value}),
          'lesfiche must be the id of a lesfiche as list_lesfiches shows it, '
          'like b0000000-0000-4000-8000-000000000001; "$value" is not. '
          'Nothing was sent.',
        );
      }
    });

    test('an answer of the Lesfiches module the server cannot use: an error '
        'that says so, without the answer', () async {
      planner.failing[fakeLesficheDetailPath(lesson)] = 500;

      expect(
        await error('read_lesfiche', {'lesfiche': lesson.id}),
        'The Lesfiches module gave an answer the server could not use (HTTP '
        '500). Try again in a moment; the technical details are in the '
        'server log.',
      );
    });
  });

  group('read_lesfiche_attachment', () {
    test('reads the attachment by its number or its file name, without the '
        'course list', () async {
      const expected =
          'Attachment 1 of the lesson lesfiche "Lussen", "lussen.txt" (16 '
          'bytes): text file, 16 characters.\n'
          '\n'
          'dartschool test\n';
      for (final attachment in <Object>[1, 'lussen.txt', 'LUSSEN.TXT', '1']) {
        expect(
          await ok('read_lesfiche_attachment', {
            'lesfiche': lesson.id,
            'attachment': attachment,
          }),
          expected,
          reason: '$attachment',
        );
      }
      expect(
        await requestsOf('read_lesfiche_attachment', {
          'lesfiche': lesson.id,
          'attachment': 1,
        }),
        [
          'GET ${fakeLesficheDetailPath(lesson)}',
          'GET ${fakeLesficheDownloadPath(lesson, lussen)}',
        ],
      );
    });

    test('of an assignment lesfiche, at assignments/{id}', () async {
      final assignment = fakeLesficheDetailAssignment;
      expect(
        await ok('read_lesfiche_attachment', {
          'lesfiche': assignment.id,
          'type': 'assignment',
          'attachment': 'lussen.txt',
        }),
        startsWith(
          'Attachment 1 of the assignment lesfiche "Lussen", "lussen.txt" '
          '(16 bytes): text',
        ),
      );
      expect(
        planner.requests.map((request) => request.path),
        contains(fakeLesficheDownloadPath(assignment, lussen)),
      );
    });

    test('a Word file as text, an image as image content', () async {
      final docx = sampleDocx();
      final png = samplePng(40, 30);
      planner.lesfiches.add(
        _withFiles([
          _file('01', 'opgave.docx', content: docx, mimeType: null),
          _file('02', 'schema.png', content: png, mimeType: 'image/png'),
        ]),
      );
      const id = 'b0000000-0000-4000-8000-000000000031';

      expect(
        await ok('read_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 'opgave.docx',
        }),
        startsWith(
          'Attachment 1 of the lesson lesfiche "Bestanden", "opgave.docx" '
          '(${formatFileSize(docx.length)}): Word document',
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'read_lesfiche_attachment',
          arguments: {'lesfiche': id, 'attachment': 2},
        ),
      );
      expect(result.isError, isNot(true));
      expect(result.content, hasLength(2));
      expect(
        (result.content.first as TextContent).text,
        'Attachment 2 of the lesson lesfiche "Bestanden", "schema.png" '
        '(${formatFileSize(png.length)}): image (image/png).',
      );
      final image = result.content.last as ImageContent;
      expect(image.mimeType, 'image/png');
      expect(base64Decode(image.data), png);
    });

    test('an attachment too large by its size in the lesfiche, or of a type '
        'that cannot be read, is refused without downloading it', () async {
      planner.lesfiches.add(
        _withFiles([
          _file('01', 'film.txt', fileSize: 30 * 1024 * 1024),
          _file('02', 'oud.doc', content: sampleOle2(), mimeType: null),
        ]),
      );
      const id = 'b0000000-0000-4000-8000-000000000031';

      expect(
        await error('read_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 1,
        }),
        'Attachment 1 of the lesson lesfiche "Bestanden", "film.txt" (30 MB) '
        'is too large to open here: files up to 25 MB can be read. The '
        'user can open it in Smartschool.',
      );
      expect(
        await error('read_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 'oud.doc',
        }),
        startsWith(
          'Attachment 2 of the lesson lesfiche "Bestanden", "oud.doc": It is '
          'in the old Word format (.doc)',
        ),
      );
      expect(
        planner.requests.map((request) => request.path),
        everyElement(isNot(endsWith('/download'))),
      );
    });

    test('a download Smartschool refuses: an error that says so', () async {
      planner.failing[fakeLesficheDownloadPath(lesson, lussen)] = 500;

      expect(
        await error('read_lesfiche_attachment', {
          'lesfiche': lesson.id,
          'attachment': 1,
        }),
        'Smartschool could not download attachment 1 of the lesson lesfiche '
        '"Lussen", "lussen.txt" (status 500). Try again later; the user can '
        'open it in Smartschool.',
      );
    });
  });

  group('the attachment argument', () {
    test('a number the lesfiche does not have, or a name: the attachments '
        'it has', () async {
      for (final tool in [
        'read_lesfiche_attachment',
        'save_lesfiche_attachment',
      ]) {
        expect(
          await error(tool, {'lesfiche': lesson.id, 'attachment': 2}),
          'The lesson lesfiche "Lussen" has 1 attachment, so there is no '
          'attachment 2: pass a number from 1 to 1, or the file name.\n'
          '1. lussen.txt (16 bytes)',
          reason: tool,
        );
        expect(
          await error(tool, {'lesfiche': lesson.id, 'attachment': 'les.txt'}),
          'The lesson lesfiche "Lussen" has no attachment named "les.txt". '
          'Its 1 attachment:\n'
          '1. lussen.txt (16 bytes)',
          reason: tool,
        );
      }
      expect(saved(), isEmpty);
    });

    test('a name that two attachments have (the module keeps both): pass '
        'its number', () async {
      planner.lesfiches.add(
        _withFiles([
          _file('01', 'opgave.txt', content: utf8.encode('versie 1')),
          _file('02', 'Opgave.txt', content: utf8.encode('versie 2')),
          _file('03', 'opgave.txt', content: utf8.encode('versie 3')),
        ]),
      );
      const id = 'b0000000-0000-4000-8000-000000000031';

      expect(
        await error('save_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 'opgave.txt',
        }),
        'The lesson lesfiche "Bestanden" has more than one attachment named '
        '"opgave.txt": pass its number instead.\n'
        '1. opgave.txt (8 bytes)\n'
        '3. opgave.txt (8 bytes)',
      );
      // The name exactly comes first; ignoring case only when no name is
      // the same exactly.
      expect(
        await ok('read_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 'Opgave.txt',
        }),
        endsWith('versie 2'),
      );
      expect(
        await ok('read_lesfiche_attachment', {'lesfiche': id, 'attachment': 3}),
        endsWith('versie 3'),
      );
    });

    test('a lesfiche without attachments, an empty name, and a lesfiche '
        'that is not there', () async {
      for (final tool in [
        'read_lesfiche_attachment',
        'save_lesfiche_attachment',
      ]) {
        expect(
          await error(tool, {
            'lesfiche': fakeLesficheLussen.id,
            'attachment': 1,
          }),
          'The lesson lesfiche "Herhaling: lussen" has no attachments.',
          reason: tool,
        );
        expect(
          await error(tool, {'lesfiche': lesson.id, 'attachment': ' '}),
          'attachment is empty: pass its number as read_lesfiche lists it (1 '
          'for the first), or its file name.',
          reason: tool,
        );
        expect(
          await error(tool, {
            'lesfiche': lesson.id,
            'type': 'assignment',
            'attachment': 1,
          }),
          startsWith(
            'You have no assignment lesfiche with id ${lesson.id}. Take the '
            'id and the kind from list_lesfiches',
          ),
          reason: tool,
        );
      }
    });
  });

  group('save_lesfiche_attachment', () {
    String closing(int days) =>
        'Open the file from this path with your own file tools if you can; '
        'otherwise tell the user where it is, so they can open it or drag it '
        'into the chat. It is deleted from the download folder after $days '
        'days.';

    test('saves the attachment by its number under its file name, and '
        'returns its full path, name and size', () async {
      final text = await ok('save_lesfiche_attachment', {
        'lesfiche': lesson.id,
        'attachment': 1,
      });

      final file = savedFile('lussen.txt');
      expect(file.readAsStringSync(), 'dartschool test\n');
      expect(
        text,
        'Saved attachment 1 of the lesson lesfiche "Lussen", "lussen.txt" in '
        'the download folder.\n'
        'Path: ${file.path}\n'
        'File name: lussen.txt\n'
        'Size: 16 bytes\n'
        '${closing(7)}',
      );
      expect(saved(), ['lussen.txt']);
    });

    test('by its file name, without the course list; a name that is taken '
        'gets a number', () async {
      expect(
        await requestsOf('save_lesfiche_attachment', {
          'lesfiche': lesson.id,
          'attachment': 'lussen.txt',
        }),
        [
          'GET ${fakeLesficheDetailPath(lesson)}',
          'GET ${fakeLesficheDownloadPath(lesson, lussen)}',
        ],
      );
      final text = await ok('save_lesfiche_attachment', {
        'lesfiche': fakeLesficheDetailAssignment.id,
        'type': 'assignment',
        'attachment': 'Lussen.TXT',
      });

      expect(saved(), ['lussen (2).txt', 'lussen.txt']);
      expect(
        text,
        startsWith(
          'Saved attachment 1 of the assignment lesfiche "Lussen", '
          '"lussen.txt" in the download folder.\n'
          'Path: ${savedFile('lussen (2).txt').path}\n'
          'File name: lussen (2).txt\n',
        ),
      );
      expect(
        savedFile('lussen (2).txt').readAsStringSync(),
        'dartschool test\n',
      );
    });

    test('any format, also one read_lesfiche_attachment cannot read', () async {
      final doc = sampleOle2();
      planner.lesfiches.add(
        _withFiles([_file('01', 'oud.doc', content: doc, mimeType: null)]),
      );

      await ok('save_lesfiche_attachment', {
        'lesfiche': 'b0000000-0000-4000-8000-000000000031',
        'attachment': 'oud.doc',
      });

      expect(savedFile('oud.doc').readAsBytesSync(), doc);
    });

    test('an attachment larger than the limit by its size in the lesfiche '
        'is refused without downloading it; by its download, the transfer '
        'stops and nothing is left behind', () async {
      planner.lesfiches.add(
        _withFiles([
          _file('01', 'groot.pdf', fileSize: 2 * _limit),
          _file(
            '02',
            'stil.pdf',
            content: List.filled(_limit + 1, 7),
            fileSize: 10,
          ),
        ]),
      );
      const id = 'b0000000-0000-4000-8000-000000000031';

      expect(
        await error('save_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 1,
        }),
        'Attachment 1 of the lesson lesfiche "Bestanden", "groot.pdf" (2.0 '
        'MB) is too large to save here: files up to 1.0 MB can be saved. The '
        'user can download it in Smartschool.',
      );
      expect(
        planner.requests.map((request) => request.path),
        everyElement(isNot(endsWith('/download'))),
      );

      expect(
        await error('save_lesfiche_attachment', {
          'lesfiche': id,
          'attachment': 2,
        }),
        'Attachment 2 of the lesson lesfiche "Bestanden", "stil.pdf" (1.0 MB) '
        'is too large to save here: files up to 1.0 MB can be saved. The user '
        'can download it in Smartschool.',
      );
      expect(saved(), isEmpty);
    });

    test('a download Smartschool refuses: an error that says so, and '
        'nothing saved', () async {
      planner.failing[fakeLesficheDownloadPath(lesson, lussen)] = 500;

      expect(
        await error('save_lesfiche_attachment', {
          'lesfiche': lesson.id,
          'attachment': 1,
        }),
        'Smartschool could not download attachment 1 of the lesson lesfiche '
        '"Lussen", "lussen.txt" (status 500). Try again later; the user can '
        'download it in Smartschool.',
      );
      expect(saved(), isEmpty);
    });

    test('without a download folder: how to set one, before anything is '
        'read', () async {
      final (connection, _) = await connect(
        tools: [saveLesficheAttachmentTool(session, null)],
      );
      server.requests.clear();

      final (result, text) = await callTool(
        connection,
        'save_lesfiche_attachment',
        {'lesfiche': lesson.id, 'attachment': 1},
      );

      expect(result.isError, isTrue);
      expect(
        text,
        startsWith('There is no download folder to save files in. Set '),
      );
      expect(server.requests, isEmpty);
    });
  });
}
