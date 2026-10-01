/// `read_intradesk_file`, called over MCP on the real server, session,
/// library, index cache and document reader, against a fake Smartschool
/// serving the dartschool Intradesk fixtures plus sample files.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/documents/document_reader.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_intradesk_folder_tool.dart';
import 'package:smartschool_mcp/src/tools/read_intradesk_file_tool.dart';
import 'package:smartschool_mcp/src/tools/search_intradesk_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';
import 'support/sample_documents.dart';

const _documenten = 'aaaa1111-1111-4111-b111-111111111111';

void main() {
  late FakeSmartschool server;
  late Directory cookies;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool()..intradesk.loadFixtures();
    cookies = await tempCache();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cookies),
    );
    addTearDown(session.close);
    final cache = IntradeskIndexCache(await tempCache());
    addTearDown(() => cache.walkDone);
    (connection, _) = await connect(
      tools: [
        searchIntradeskTool(session, cache),
        listIntradeskFolderTool(session, cache),
        readIntradeskFileTool(session, cache),
      ],
    );
  });

  Future<CallToolResult> call(String id) => connection.callTool(
    CallToolRequest(name: 'read_intradesk_file', arguments: {'file_id': id}),
  );

  Future<String> read(String id) async {
    final result = await call(id);
    final text = (result.content.first as TextContent).text;
    expect(result.isError, isNot(true), reason: text);
    expect(result.content, hasLength(1));
    return text;
  }

  Future<String> error(String id) async {
    final result = await call(id);
    final text = (result.content.single as TextContent).text;
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// Builds the index, so the tool knows paths, sizes and names.
  Future<void> index() async {
    final (result, _) = await callTool(connection, 'search_intradesk', {
      'query': 'welkom',
    });
    expect(result.isError, isNot(true));
  }

  test('is listed as read-only, with file_id', () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((tool) => tool.name == 'read_intradesk_file');

    expect(tool.toolAnnotations?.readOnlyHint, isTrue);
    expect(tool.toolAnnotations?.destructiveHint, isNot(true));
    expect(tool.inputSchema.required, ['file_id']);
    expect(tool.inputSchema.properties!.keys, ['file_id']);
    expect(tool.description, contains('search_intradesk'));
    expect(tool.description, contains('25 MB'));
    expect(tool.description, contains('$defaultMaxDocumentChars characters'));
  });

  test('reads a Word file named by its path in the index: a line saying '
      'what it is, then its text', () async {
    final docx = sampleDocx();
    final id = server.intradesk.addFile(
      'uitstap.docx',
      parent: _documenten,
      content: docx,
    );
    await index();

    expect(
      await read(id),
      'Intradesk file Documenten / uitstap.docx (id $id, '
      '${formatFileSize(docx.length)}, changed 2024-08-29): Word document, '
      '${sampleDocxText.length} characters.\n'
      '\n'
      '$sampleDocxText',
    );
    expect(server.intradesk.downloaded, [id]);
  });

  test('reads Excel, PowerPoint, PDF, CSV and HTML files', () async {
    final xlsx = server.intradesk.addFile('punten.xlsx', content: sampleXlsx());
    final pptx = server.intradesk.addFile(
      'infoavond.pptx',
      content: samplePptx(),
    );
    final pdf = server.intradesk.addFile(
      'brief.pdf',
      content: samplePdf([
        ['Beste ouders,'],
        ['Met vriendelijke groeten'],
      ]),
    );
    final csv = server.intradesk.addFile(
      'lijst.csv',
      content: Uint8List.fromList(utf8.encode('Naam;Klas\nAn;3A\n')),
    );
    final html = server.intradesk.addFile(
      'info.html',
      content: Uint8List.fromList(utf8.encode('<p>Hallo <b>allemaal</b></p>')),
    );
    await index();

    expect(
      await read(xlsx),
      allOf(
        contains(
          ': Excel workbook, 3 sheets, ${sampleXlsxText.length} '
          'characters.\n\n',
        ),
        endsWith('\n\n$sampleXlsxText'),
      ),
    );
    expect(
      await read(pptx),
      allOf(
        contains(': PowerPoint presentation, 3 slides, '),
        endsWith('\n\n$samplePptxText'),
      ),
    );
    expect(
      await read(pdf),
      endsWith(
        ': PDF, 2 pages, 59 characters.\n\n'
        '## Page 1\nBeste ouders,\n\n## Page 2\nMet vriendelijke groeten',
      ),
    );
    expect(
      await read(csv),
      endsWith(': text file, 16 characters.\n\nNaam;Klas\nAn;3A\n'),
    );
    expect(
      await read(html),
      endsWith(': web page, 14 characters.\n\nHallo allemaal'),
    );
  });

  test('a file the index does not know is named from the download, or by '
      'its id alone', () async {
    final docx = sampleDocx();
    final id = server.intradesk.addFile('uitstap.docx', content: docx);
    final size = formatFileSize(docx.length);

    expect(
      await read(id),
      startsWith('Intradesk file uitstap.docx (id $id, $size): Word document'),
    );

    server.intradesk.announceDownloads = false;
    expect(
      await read(id),
      startsWith('Intradesk file (id $id, $size): Word document'),
    );
  });

  test('text over the budget is cut off, with a note', () async {
    final id = server.intradesk.addFile(
      'reglement.docx',
      content: docxWithParagraphs([
        for (var i = 1; i <= 3000; i++) 'Artikel $i: iedereen is op tijd.',
      ]),
    );

    final text = await read(id);

    final header = RegExp(
      r'^Intradesk file reglement\.docx \(id [0-9a-f-]+, [\d.]+ KB\): Word '
      r'document, the first (\d+) of (\d+) characters\.$',
    ).firstMatch(text.split('\n').first);
    expect(header, isNotNull, reason: text.split('\n').first);
    final shown = int.parse(header![1]!);
    final full = int.parse(header[2]!);
    expect(shown, lessThanOrEqualTo(defaultMaxDocumentChars));
    expect(full, greaterThan(defaultMaxDocumentChars));
    expect(
      text,
      endsWith(
        '\n\nNote: The text is cut off here, after $shown of $full '
        'characters.',
      ),
    );
  });

  test('an image comes back as image content', () async {
    final png = samplePng(40, 30);
    final id = server.intradesk.addFile('logo.png', content: png);

    final result = await call(id);

    expect(result.isError, isNot(true));
    expect(result.content, hasLength(2));
    expect(
      (result.content.first as TextContent).text,
      'Intradesk file logo.png (id $id, ${formatFileSize(png.length)}): '
      'image (image/png).',
    );
    final image = result.content.last as ImageContent;
    expect(image.mimeType, 'image/png');
    expect(base64Decode(image.data), png);
  });

  test(
    'a file too large by the index is refused without downloading it',
    () async {
      final id = server.intradesk.addFile(
        'opname.pdf',
        parent: _documenten,
        size: 427 * 1024 * 1024,
      );
      await index();

      expect(
        await error(id),
        'Intradesk file Documenten / opname.pdf (id $id, 427 MB, changed '
        '2024-08-29) is too large to open here: files up to 25 MB can be read. '
        'The teacher can open it in Smartschool.',
      );
      expect(server.intradesk.downloaded, isEmpty);
    },
  );

  test('a file too large by its announced size is not read', () async {
    final id = server.intradesk.addFile(
      'opname.pdf',
      content: Uint8List(maxIntradeskFileBytes + 1),
    );

    expect(
      await error(id),
      'Intradesk file (id $id, 25 MB) is too large to open here: files up '
      'to 25 MB can be read. The teacher can open it in Smartschool.',
    );
    expect(server.intradesk.downloaded, [id]);
    // The download is cancelled, not left running in the background.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.intradesk.stoppedDownloads, 1);
    expect(server.intradesk.bytesSent, lessThan(1024 * 1024));
  });

  test('a file too large without an announced size stops downloading once '
      'past the limit', () async {
    final content = Uint8List(maxIntradeskFileBytes + 4 * 1024 * 1024);
    final id = server.intradesk.addFile('opname.pdf', content: content);
    server.intradesk.announceDownloads = false;

    expect(
      await error(id),
      'Intradesk file (id $id) is too large to open here (more than 25 MB): '
      'files up to 25 MB can be read. The teacher can open it in Smartschool.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.intradesk.stoppedDownloads, 1);
    expect(
      server.intradesk.bytesSent,
      inInclusiveRange(
        maxIntradeskFileBytes,
        maxIntradeskFileBytes + 1024 * 1024,
      ),
    );
  });

  test('a connection that fails halfway: Smartschool could not be reached, '
      'and the next call downloads the file again', () async {
    // 84 KB: two chunks, and less text than is cut off.
    final text = 'Beste ouders,\n' * 6000;
    final id = server.intradesk.addFile(
      'brief.txt',
      content: utf8.encode(text),
    );
    server.intradesk.failDownloadsAfter = 64 * 1024;

    expect(await error(id), startsWith('Could not reach Smartschool at '));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.intradesk.stoppedDownloads, 1);
    expect(server.intradesk.bytesSent, 64 * 1024);

    server.intradesk.failDownloadsAfter = null;
    expect(await read(id), endsWith('\n\n$text'));
    expect(server.intradesk.downloaded, [id, id]);
    expect(server.logins, 1);
  });

  test('a type that cannot be read is refused by the index without '
      'downloading, else after', () async {
    final known = server.intradesk.addFile(
      'oud verslag.doc',
      parent: _documenten,
      size: 50000,
    );
    await index();
    final unknown = server.intradesk.addFile(
      'oud verslag.doc',
      content: sampleOle2(),
    );

    expect(
      await error(known),
      'Intradesk file Documenten / oud verslag.doc (id $known, 49 KB, '
      'changed 2024-08-29): It is in the old Word format (.doc), which '
      'cannot be read: only $readableFormats can. Saved in the new format '
      '(.docx) it can be read.',
    );
    expect(
      await error(unknown),
      'Intradesk file oud verslag.doc (id $unknown, 512 bytes): It is in the '
      'old Word format (.doc), which cannot be read: only $readableFormats '
      'can. Saved in the new format (.docx) it can be read.',
    );
    expect(server.intradesk.downloaded, [unknown]);

    final scan = server.intradesk.addFile('scan.pdf', content: samplePdf([[]]));
    expect(
      await error(scan),
      endsWith(
        ': The PDF has no text that can be read: it is probably a scan '
        '(pictures of pages).',
      ),
    );
  });

  test('a folder id: the index says it is a folder; without an index, '
      'Smartschool refuses the download', () async {
    expect(
      await error(_documenten),
      startsWith(
        'Smartschool could not download an Intradesk file with id '
        '$_documenten (status 404). Most likely it is not the id of a file '
        'you can open, for example a folder\'s id or a file that was '
        'removed: take the id of a file from search_intradesk or '
        'list_intradesk_folder.',
      ),
    );

    await index();
    expect(
      await error(_documenten),
      '$_documenten is the id of the Intradesk folder Documenten, not of a '
      'file: use list_intradesk_folder to see what is in it.',
    );
  });

  test('an id that is not an Intradesk id, or none, is refused without '
      'asking Smartschool', () async {
    expect(
      await error('../../messages'),
      startsWith('file_id must be an Intradesk id like '),
    );
    expect(
      await error('  '),
      'file_id is empty: pass the id of a file, from search_intradesk or '
      'list_intradesk_folder.',
    );
    expect(server.requests, isEmpty);
  });

  test('an id in capitals is the same file', () async {
    final id = server.intradesk.addFile('a.txt', content: utf8.encode('Hoi'));

    expect(await read(id.toUpperCase()), endsWith('\n\nHoi'));
    expect(server.intradesk.downloaded, [id]);
  });

  test('when the session expires right before the download, it logs in '
      'again once and downloads again', () async {
    final id = server.intradesk.addFile('a.txt', content: utf8.encode('Hoi'));
    await read(id);
    expect(server.logins, 1);
    server.expireSessionBefore(
      (request) => request.uri.path.endsWith('/$id/download'),
    );

    expect(await read(id), endsWith('\n\nHoi'));
    expect(server.logins, 2);
    expect(server.intradesk.downloaded, [id, id]);
  });

  test('without Smartschool settings: the missing settings', () async {
    final session = SmartschoolSession(
      fakeExtensionSettings(FakeCredentials(username: '', password: '')),
      createClient: fakeClientFactory(server, cookies),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(
      tools: [readIntradeskFileTool(session, IntradeskIndexCache.of(session))],
    );

    final (result, text) = await callTool(connection, 'read_intradesk_file', {
      'file_id': 'cccc1111-1111-4111-b111-111111111111',
    });

    expect(result.isError, isTrue);
    expect(
      text,
      startsWith('Not all Smartschool settings are filled in. Missing: '),
    );
    expect(server.requests, isEmpty);
  });
}
