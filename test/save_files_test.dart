/// `save_intradesk_file` and `save_message_attachment`, called over MCP on
/// the real server, session, library, index cache and download folder,
/// against a fake Smartschool, saving into a temporary folder.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/downloads/download_folder.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/save_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/save_message_attachment_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';
import 'support/sample_documents.dart';

const _documenten = 'aaaa1111-1111-4111-b111-111111111111';

/// The size limit of the tools here, so a test needs no 200 MB file.
const _limit = 1024 * 1024;

final _sep = Platform.pathSeparator;

/// [length] bytes that are not all the same.
Uint8List _bytes(int length, {int seed = 7}) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * seed + i ~/ 251) & 0xFF,
]);

void main() {
  late FakeSmartschool server;
  late Directory cookies;
  late Directory downloads;
  late DownloadFolder folder;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool()..intradesk.loadFixtures();
    cookies = await tempCache();
    final root = await Directory.systemTemp.createTemp('smartschool_save_');
    addTearDown(() => root.delete(recursive: true));
    downloads = Directory('${root.path}${_sep}Downloads${_sep}Smartschool');
    folder = DownloadFolder(
      downloads.path,
      origin: const DownloadFolderOrigin(
        'set in "Downloadmap" (SMARTSCHOOL_DOWNLOAD_DIR)',
        fix: 'choose another folder in "Downloadmap"',
      ),
    );
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cookies),
    );
    addTearDown(session.close);
    final cache = IntradeskIndexCache(await tempCache());
    addTearDown(() => cache.walkDone);
    (connection, _) = await connect(
      tools: [
        readMessageTool(session),
        saveMessageAttachmentTool(session, folder, maxBytes: _limit),
        searchIntradeskTool(session, cache),
        saveIntradeskFileTool(session, cache, folder, maxBytes: _limit),
      ],
    );
  });

  Future<(CallToolResult, String)> call(
    String tool,
    Map<String, Object?> arguments,
  ) => callTool(connection, tool, arguments);

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await call(tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await call(tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
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

  /// The names on the list of saved files.
  List<String> listed() => [
    for (final file
        in (jsonDecode(
                  savedFile(DownloadFolder.manifestName).readAsStringSync(),
                )
                as Map)['files']
            as List)
      (file as Map)['name'] as String,
  ];

  /// Builds the index, so the tool knows paths, sizes and names.
  Future<void> index() => ok('search_intradesk', {'query': 'welkom'});

  String closing(int days) =>
      'Open the file from this path with your own file tools if you can; '
      'otherwise tell the user where it is, so they can open it or drag it '
      'into the chat. It is deleted from the download folder after $days '
      'days.';

  test('both tools are listed as writing a file without replacing one, and '
      'tell Claude to open the saved file from its path', () async {
    final session = SmartschoolSession(fakeExtensionSettings());
    final (connection, _) = await connect(
      tools: [
        saveIntradeskFileTool(
          session,
          IntradeskIndexCache(await tempCache()),
          folder,
        ),
        saveMessageAttachmentTool(session, folder),
      ],
    );
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };

    expect(tools.keys, ['save_intradesk_file', 'save_message_attachment']);
    for (final tool in tools.values) {
      expect(tool.toolAnnotations?.readOnlyHint, isFalse);
      expect(tool.toolAnnotations?.destructiveHint, isFalse);
      expect(tool.toolAnnotations?.idempotentHint, isFalse);
      expect(tool.description, contains('200 MB'));
      expect(tool.description, contains('returned path with your own file'));
      expect(tool.description, contains('tell the user where the file is'));
      expect(tool.description, contains('deleted after 7 days'));
      expect(tool.description, contains('never replaced'));
    }
    final intradesk = tools['save_intradesk_file']!;
    expect(intradesk.inputSchema.required, ['file_id']);
    expect(intradesk.inputSchema.properties!.keys, ['file_id']);
    expect(intradesk.description, contains('read_intradesk_file'));
    final attachment = tools['save_message_attachment']!;
    expect(attachment.inputSchema.required, ['message_id', 'attachment']);
    expect(attachment.inputSchema.properties!.keys, [
      'message_id',
      'attachment',
      'box',
    ]);
    expect(attachment.description, contains('read_message'));
  });

  group('save_intradesk_file', () {
    test('saves the file\'s bytes under its name from the index and returns '
        'its full path, name and size', () async {
      final content = sampleDocx();
      final id = server.intradesk.addFile(
        'uitstap.docx',
        parent: _documenten,
        content: content,
      );
      await index();

      final text = await ok('save_intradesk_file', {'file_id': id});

      final file = savedFile('uitstap.docx');
      expect(file.readAsBytesSync(), content);
      expect(
        text,
        'Saved Intradesk file Documenten / uitstap.docx (id $id, '
        '${formatFileSize(content.length)}, changed 2024-08-29) in the '
        'download folder.\n'
        'Path: ${file.path}\n'
        'File name: uitstap.docx\n'
        'Size: ${formatFileSize(content.length)} (${content.length} bytes)\n'
        '${closing(7)}',
      );
      expect(saved(), ['uitstap.docx']);
      expect(listed(), ['uitstap.docx']);
      expect(server.intradesk.downloaded, [id]);
    });

    test('any format, also one read_intradesk_file cannot read', () async {
      final scan = samplePdf([[]]);
      final doc = sampleOle2();
      final binary = _bytes(300 * 1024);
      final ids = [
        server.intradesk.addFile('scan.pdf', content: scan),
        server.intradesk.addFile('oud verslag.doc', content: doc),
        server.intradesk.addFile('opname.mp3', content: binary),
      ];

      for (final id in ids) {
        await ok('save_intradesk_file', {'file_id': id});
      }

      expect(savedFile('scan.pdf').readAsBytesSync(), scan);
      expect(savedFile('oud verslag.doc').readAsBytesSync(), doc);
      expect(savedFile('opname.mp3').readAsBytesSync(), binary);
    });

    test('a file the index does not know is named from the download; '
        'without a name, by its id, with a note', () async {
      final content = utf8.encode('Hallo');
      final id = server.intradesk.addFile('brief.txt', content: content);

      final named = await ok('save_intradesk_file', {'file_id': id});
      server.intradesk.announceDownloads = false;
      final unnamed = await ok('save_intradesk_file', {'file_id': id});

      expect(
        named,
        startsWith(
          'Saved Intradesk file brief.txt (id $id, 5 bytes) in the download '
          'folder.\nPath: ${savedFile('brief.txt').path}\n',
        ),
      );
      expect(
        unnamed,
        contains(
          'File name: intradesk-$id\n'
          'Size: 5 bytes\n'
          'Note: Smartschool gave no file name, so it was saved as '
          '"intradesk-$id".\n',
        ),
      );
      expect(savedFile('intradesk-$id').readAsStringSync(), 'Hallo');
    });

    test(
      'never replaces a file: the same name again gets (2), with a note',
      () async {
        final id = server.intradesk.addFile(
          'brief.txt',
          content: utf8.encode('nieuw'),
        );
        downloads.createSync(recursive: true);
        savedFile('brief.txt').writeAsStringSync('van de leraar');

        final first = await ok('save_intradesk_file', {'file_id': id});
        final second = await ok('save_intradesk_file', {'file_id': id});

        expect(
          first,
          contains(
            'File name: brief (2).txt\n'
            'Size: 5 bytes\n'
            'Note: A file named "brief.txt" was already in the download '
            'folder, so this one was saved as "brief (2).txt"; the other file '
            'was not changed.\n',
          ),
        );
        expect(second, contains('File name: brief (3).txt\n'));
        expect(savedFile('brief.txt').readAsStringSync(), 'van de leraar');
        expect(savedFile('brief (2).txt').readAsStringSync(), 'nieuw');
        expect(savedFile('brief (3).txt').readAsStringSync(), 'nieuw');
        expect(listed(), ['brief (2).txt', 'brief (3).txt']);
      },
    );

    test('an unsafe name from the download stays inside the folder, made '
        'safe, with a note', () async {
      final id = server.intradesk.addFile(
        r'..\..\CON:evil.txt',
        content: utf8.encode('x'),
      );

      final text = await ok('save_intradesk_file', {'file_id': id});

      expect(saved(), ['.._.._CON_evil.txt']);
      expect(
        text,
        contains(
          'Note: The file name Smartschool gives, "..\\..\\CON:evil.txt", '
          'cannot be used as it is (it holds characters a file name cannot '
          'have), so it was saved as ".._.._CON_evil.txt".',
        ),
      );
      expect(downloads.parent.listSync(), hasLength(1));
    });

    test('a file too large by the index is refused without downloading it '
        'or creating the folder', () async {
      final id = server.intradesk.addFile(
        'opname.mp4',
        parent: _documenten,
        size: 427 * 1024 * 1024,
      );
      await index();

      expect(
        await error('save_intradesk_file', {'file_id': id}),
        'Intradesk file Documenten / opname.mp4 (id $id, 427 MB, changed '
        '2024-08-29) is too large to save here: files up to 1.0 MB can be '
        'saved. The teacher can download it in Smartschool.',
      );
      expect(server.intradesk.downloaded, isEmpty);
      expect(downloads.existsSync(), isFalse);
    });

    test('a file too large by its announced size is not saved, and the '
        'download is stopped', () async {
      final id = server.intradesk.addFile(
        'opname.mp4',
        content: Uint8List(_limit + 1),
      );

      expect(
        await error('save_intradesk_file', {'file_id': id}),
        'Intradesk file (id $id, 1.0 MB) is too large to save here: files up '
        'to 1.0 MB can be saved. The teacher can download it in Smartschool.',
      );
      expect(saved(), isEmpty, reason: 'no temporary file left');
      await server.intradesk.stops.reached(1);
      expect(server.intradesk.stoppedDownloads, 1);
    });

    test('a file too large without an announced size stops once past the '
        'limit, and what came in is deleted', () async {
      final id = server.intradesk.addFile(
        'opname.mp4',
        content: Uint8List(_limit + 16 * 1024 * 1024),
      );
      server.intradesk.announceDownloads = false;

      expect(
        await error('save_intradesk_file', {'file_id': id}),
        'Intradesk file (id $id) is too large to save here (more than 1.0 '
        'MB): files up to 1.0 MB can be saved. The teacher can download it '
        'in Smartschool.',
      );
      expect(saved(), isEmpty, reason: 'no temporary file left');
      await server.intradesk.stops.reached(1);
      expect(server.intradesk.stoppedDownloads, 1);
      // The download is read as soon as it comes in, so little more than the
      // limit is sent, as for read_intradesk_file; far from all 17 MB. (When
      // it was read only once the file was open, the HTTP client took in up
      // to all of it meanwhile, #36.)
      expect(
        server.intradesk.bytesSent,
        inInclusiveRange(_limit, _limit + 1024 * 1024),
      );
    });

    test('a connection that fails halfway: Smartschool could not be reached, '
        'nothing is left; the next call saves the file', () async {
      final content = _bytes(200 * 1024);
      final id = server.intradesk.addFile('les.pptx', content: content);
      server.intradesk.failDownloadsAfter = 64 * 1024;

      expect(
        await error('save_intradesk_file', {'file_id': id}),
        startsWith('Could not reach Smartschool at '),
      );
      expect(saved(), isEmpty);

      server.intradesk.failDownloadsAfter = null;
      await ok('save_intradesk_file', {'file_id': id});
      expect(saved(), ['les.pptx']);
      expect(savedFile('les.pptx').readAsBytesSync(), content);
    });

    test('when the session expires right before the download, it logs in '
        'again and saves the file once', () async {
      final id = server.intradesk.addFile('a.txt', content: utf8.encode('Hoi'));
      await ok('save_intradesk_file', {'file_id': id});
      server.expireSessionBefore(
        (request) => request.uri.path.endsWith('/$id/download'),
      );

      await ok('save_intradesk_file', {'file_id': id});

      expect(server.logins, 2);
      expect(saved(), ['a (2).txt', 'a.txt']);
      expect(savedFile('a (2).txt').readAsStringSync(), 'Hoi');
    });

    test('a folder id: the index says it is a folder; without an index, '
        'Smartschool refuses the download', () async {
      expect(
        await error('save_intradesk_file', {'file_id': _documenten}),
        startsWith(
          'Smartschool could not download an Intradesk file with id '
          '$_documenten (status 404).',
        ),
      );
      await index();
      expect(
        await error('save_intradesk_file', {'file_id': _documenten}),
        '$_documenten is the id of the Intradesk folder Documenten, not of a '
        'file: use list_intradesk_folder to see what is in it.',
      );
      expect(saved(), isEmpty);
    });

    test('an id that is not an Intradesk id, or none, is refused without '
        'asking Smartschool', () async {
      expect(
        await error('save_intradesk_file', {'file_id': '../../messages'}),
        startsWith('file_id must be an Intradesk id like '),
      );
      expect(
        await error('save_intradesk_file', {'file_id': ' '}),
        startsWith('file_id is empty: '),
      );
      expect(server.requests, isEmpty);
    });

    test('a download folder that cannot be created: an error that says how '
        'to choose another, before downloading', () async {
      downloads.parent.createSync(recursive: true);
      File(downloads.path).writeAsStringSync('een bestand');
      final id = server.intradesk.addFile('a.txt', content: utf8.encode('x'));

      expect(
        await error('save_intradesk_file', {'file_id': id}),
        allOf(
          startsWith(
            'The download folder ${downloads.path} cannot be created (',
          ),
          endsWith('). To save files, choose another folder in "Downloadmap".'),
        ),
      );
      expect(server.intradesk.downloaded, isEmpty);
    });

    test(
      'without Smartschool settings: the missing settings, and no folder',
      () async {
        final session = SmartschoolSession(
          fakeExtensionSettings(FakeCredentials(username: '', password: '')),
          createClient: fakeClientFactory(server, cookies),
        );
        addTearDown(session.close);
        final (connection, _) = await connect(
          tools: [
            saveIntradeskFileTool(
              session,
              IntradeskIndexCache.of(session),
              folder,
            ),
            saveMessageAttachmentTool(session, folder),
          ],
        );

        for (final (tool, arguments) in [
          (
            'save_intradesk_file',
            {'file_id': 'cccc1111-1111-4111-b111-111111111111'},
          ),
          ('save_message_attachment', {'message_id': 101, 'attachment': 1}),
        ]) {
          final (result, text) = await callTool(connection, tool, arguments);
          expect(result.isError, isTrue);
          expect(
            text,
            startsWith('Not all Smartschool settings are filled in. Missing: '),
          );
        }
        expect(server.requests, isEmpty);
        expect(downloads.existsSync(), isFalse);
      },
    );

    test('without a download folder: how to set one', () async {
      final session = SmartschoolSession(
        fakeExtensionSettings(),
        createClient: fakeClientFactory(server, cookies),
      );
      addTearDown(session.close);
      final (connection, _) = await connect(
        tools: [
          saveIntradeskFileTool(session, IntradeskIndexCache.of(session), null),
          saveMessageAttachmentTool(session, null),
        ],
      );

      for (final (tool, arguments) in [
        (
          'save_intradesk_file',
          {'file_id': 'cccc1111-1111-4111-b111-111111111111'},
        ),
        ('save_message_attachment', {'message_id': 101, 'attachment': 1}),
      ]) {
        final (result, text) = await callTool(connection, tool, arguments);
        expect(result.isError, isTrue);
        expect(
          text,
          'There is no download folder to save files in. Set "Downloadmap" '
          '(SMARTSCHOOL_DOWNLOAD_DIR) in the Smartschool extension settings '
          'to a folder, then restart Claude Desktop.',
        );
      }
      expect(server.requests, isEmpty);
    });
  });

  group('save_message_attachment', () {
    // Each sample is built once and compared with the same bytes: a sample
    // zip carries the time it was built (in 2-second steps), so a second
    // sampleDocx() can differ from the one served (#37).
    late Uint8List planning;
    late Uint8List lokalen;
    late Uint8List agenda;
    late Uint8List route;

    setUp(() {
      planning = samplePdf([
        ['Planning'],
      ]);
      lokalen = sampleXlsx();
      agenda = sampleDocx();
      route = samplePng(4, 4);
      server.mailbox.inbox.addAll([
        FakeMessage(
          id: 101,
          sender: 'Jan Peeters',
          subject: 'Oudercontact donderdag',
          date: '2024-03-14 16:05',
          unread: true,
          attachments: [
            FakeAttachment(
              'Planning oudercontact.pdf',
              '1.2 KiB',
              content: planning,
            ),
            FakeAttachment('Lokalen.xlsx', '8.2 KiB', content: lokalen),
            FakeAttachment('Planning.pdf', '1 KiB', content: _bytes(10)),
            FakeAttachment('Planning.pdf', '2 KiB', content: _bytes(20)),
          ],
        ),
        FakeMessage(
          id: 102,
          sender: 'An Claes',
          subject: 'Re: Toets wiskunde',
          date: '2024-03-15 08:00',
        ),
        FakeMessage(
          id: 103,
          sender: 'Secretariaat',
          subject: 'Video',
          date: '2024-03-13 10:30',
          attachments: [
            FakeAttachment(
              'opname.mp4',
              '1.5 MiB',
              content: Uint8List(_limit + 512 * 1024),
            ),
            FakeAttachment('weg.pdf', '3 KiB'),
            FakeAttachment('../CON.pdf', '1 KiB', content: _bytes(5)),
          ],
        ),
      ]);
      server.mailbox.archive.add(
        FakeMessage(
          id: 201,
          sender: 'Directie',
          subject: 'Personeelsvergadering',
          date: '2024-02-20 12:00',
          attachments: [
            FakeAttachment('agenda.docx', '9 KiB', content: agenda),
          ],
        ),
      );
      server.mailbox.sent.add(
        FakeMessage(
          id: 301,
          sender: 'Jan Peeters',
          subject: 'Uitstap',
          date: '2024-03-12 11:00',
          to: ['Els Wouters'],
          attachments: [FakeAttachment('route.png', '1 KiB', content: route)],
        ),
      );
    });

    test('saves an attachment by its number in read_message, with its '
        'bytes and name, and returns its full path, name and size', () async {
      final read = await ok('read_message', {'message_id': 101});
      expect(
        read,
        contains(
          'Attachments (4):\n'
          '1. Planning oudercontact.pdf (1.2 KiB)\n'
          '2. Lokalen.xlsx (8.2 KiB)\n',
        ),
      );

      final text = await ok('save_message_attachment', {
        'message_id': 101,
        'attachment': 2,
      });

      final file = savedFile('Lokalen.xlsx');
      expect(file.readAsBytesSync(), lokalen);
      expect(
        text,
        'Saved attachment 2 of message 101 (Inbox), "Lokalen.xlsx" in the '
        'download folder.\n'
        'Path: ${file.path}\n'
        'File name: Lokalen.xlsx\n'
        'Size: ${formatFileSize(lokalen.length)} (${lokalen.length} bytes)\n'
        '${closing(7)}',
      );
      expect(server.mailbox.attachmentDownloads, ['101/2']);
      expect(listed(), ['Lokalen.xlsx']);
    });

    test('by its file name, in any case, or by its number as text', () async {
      await ok('save_message_attachment', {
        'message_id': 101,
        'attachment': 'Planning oudercontact.pdf',
      });
      await ok('save_message_attachment', {
        'message_id': 101,
        'attachment': ' lokalen.XLSX ',
      });
      await ok('save_message_attachment', {
        'message_id': 101,
        'attachment': '1',
      });
      await ok('save_message_attachment', {
        'message_id': 101,
        'attachment': 2.0,
      });

      expect(server.mailbox.attachmentDownloads, [
        '101/1',
        '101/2',
        '101/1',
        '101/2',
      ]);
      expect(
        savedFile('Planning oudercontact.pdf').readAsBytesSync(),
        planning,
      );
      expect(saved(), [
        'Lokalen (2).xlsx',
        'Lokalen.xlsx',
        'Planning oudercontact (2).pdf',
        'Planning oudercontact.pdf',
      ]);
    });

    test('in the archive and the sent box, with the box', () async {
      await ok('save_message_attachment', {
        'message_id': 201,
        'attachment': 1,
        'box': 'archive',
      });
      final sent = await ok('save_message_attachment', {
        'message_id': 301,
        'attachment': 1,
        'box': 'sent',
      });

      expect(savedFile('agenda.docx').readAsBytesSync(), agenda);
      expect(sent, startsWith('Saved attachment 1 of message 301 (Sent), '));
      expect(savedFile('route.png').readAsBytesSync(), route);
    });

    test('a name that is not there, or that two attachments have, or a '
        'number out of range: what to pass instead', () async {
      expect(
        await error('save_message_attachment', {
          'message_id': 101,
          'attachment': 'rooster.pdf',
        }),
        'Message 101 (Inbox) has no attachment named "rooster.pdf". Its 4 '
        'attachments:\n'
        '1. Planning oudercontact.pdf (1.2 KiB)\n'
        '2. Lokalen.xlsx (8.2 KiB)\n'
        '3. Planning.pdf (1 KiB)\n'
        '4. Planning.pdf (2 KiB)',
      );
      expect(
        await error('save_message_attachment', {
          'message_id': 101,
          'attachment': 'planning.pdf',
        }),
        'Message 101 (Inbox) has more than one attachment named '
        '"planning.pdf": pass its number instead.\n'
        '3. Planning.pdf (1 KiB)\n'
        '4. Planning.pdf (2 KiB)',
      );
      expect(
        await error('save_message_attachment', {
          'message_id': 101,
          'attachment': 5,
        }),
        startsWith(
          'Message 101 (Inbox) has 4 attachments, so there is no attachment '
          '5: pass a number from 1 to 4, or the file name.\n1. Planning ',
        ),
      );
      expect(
        await error('save_message_attachment', {
          'message_id': 101,
          'attachment': 0,
        }),
        contains('attachment'),
      );
      expect(server.mailbox.attachmentDownloads, isEmpty);
      expect(downloads.existsSync(), isFalse);
    });

    test('a message without attachments, or none with that id', () async {
      expect(
        await error('save_message_attachment', {
          'message_id': 102,
          'attachment': 1,
        }),
        'Message 102 (Inbox) has no attachments.',
      );
      expect(
        await error('save_message_attachment', {
          'message_id': 999,
          'attachment': 1,
          'box': 'archive',
        }),
        'There is no message with id 999 in the archive box. Take the id from '
        'list_messages and pass the box it was listed in.',
      );
      expect(downloads.existsSync(), isFalse);
    });

    test('an attachment too large is not saved, and the download is '
        'stopped', () async {
      expect(
        await error('save_message_attachment', {
          'message_id': 103,
          'attachment': 'opname.mp4',
        }),
        'Attachment 1 of message 103 (Inbox), "opname.mp4" (1.5 MB) is too '
        'large to save here: files up to 1.0 MB can be saved. The teacher '
        'can download it in Smartschool.',
      );
      expect(saved(), isEmpty);
      await server.mailbox.attachmentStops.reached(1);
      expect(server.mailbox.stoppedAttachmentDownloads, 1);

      server.mailbox.announceAttachmentDownloads = false;
      expect(
        await error('save_message_attachment', {
          'message_id': 103,
          'attachment': 1,
        }),
        'Attachment 1 of message 103 (Inbox), "opname.mp4" is too large to '
        'save here (more than 1.0 MB): files up to 1.0 MB can be saved. The '
        'teacher can download it in Smartschool.',
      );
      expect(saved(), isEmpty);
    });

    test('an attachment Smartschool does not send: an error, nothing '
        'saved', () async {
      expect(
        await error('save_message_attachment', {
          'message_id': 103,
          'attachment': 2,
        }),
        'Smartschool could not download attachment 2 of message 103 (Inbox), '
        '"weg.pdf" (status 404). Try again later; the teacher can download '
        'it in Smartschool.',
      );
      expect(saved(), isEmpty);
    });

    test('an unsafe attachment name is saved inside the folder, made safe, '
        'with a note', () async {
      final text = await ok('save_message_attachment', {
        'message_id': 103,
        'attachment': 3,
      });

      expect(saved(), ['.._CON.pdf']);
      expect(
        text,
        contains(
          'Note: The file name Smartschool gives, "../CON.pdf", cannot be '
          'used as it is (it holds characters a file name cannot have), so '
          'it was saved as ".._CON.pdf".',
        ),
      );
    });

    test('does not mark the message as read', () async {
      await ok('save_message_attachment', {'message_id': 101, 'attachment': 1});

      expect(server.mailbox.inbox.first.unread, isTrue);
      expect(
        server.mailbox.actions,
        everyElement(isNot(contains('mark message'))),
      );
    });
  });
}
