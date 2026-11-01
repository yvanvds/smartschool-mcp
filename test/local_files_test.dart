/// The local-file helper the upload tools share
/// (`lib/src/uploads/local_files.dart`): checking the paths a tool is given,
/// describing the files, and the library's refusals as ToolErrors.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:dart_mcp/server.dart';
import 'package:smartschool_mcp/src/client_app.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/planner/lesfiche_writes.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/add_lesfiche_attachments_tool.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/reply_to_message_tool.dart';
import 'package:smartschool_mcp/src/tools/send_message_tool.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/tools/upload_intradesk_files_tool.dart';
import 'package:smartschool_mcp/src/uploads/local_files.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart' show fakeExtensionSettings, tempCache;

/// The wording the tests above pin: Windows, the extension's platform,
/// on any system the tests run on (#202).
const _windows = ServerPlatform.windows;

void main() {
  late Directory folder;

  setUp(() async => folder = await tempCache());

  String path(String name) => '${folder.path}${Platform.pathSeparator}$name';

  String file(String name, [String content = 'test']) {
    File(path(name)).writeAsStringSync(content);
    return path(name);
  }

  Matcher toolError(Object? message) =>
      throwsA(isA<ToolError>().having((e) => e.message, 'message', message));

  group('checkLocalFiles', () {
    test('takes absolute paths of files, with the name Smartschool gets and '
        'the size', () {
      final brief = file('brief.docx', '12345');
      final toets = file('toets #1.pdf', '%PDF-1.7');

      final files = checkLocalFiles(
        [brief, toets],
        argument: 'paths',
        platform: _windows,
      );

      expect([for (final f in files) f.path], [brief, toets]);
      expect([for (final f in files) f.name], ['brief.docx', 'toets #1.pdf']);
      expect([for (final f in files) f.size], [5, 8]);
      expect(files.first.description, '"brief.docx" (5 bytes)');
      expect(localFileName(toets), 'toets #1.pdf');
    });

    test('refuses no paths and more than the maximum', () {
      expect(
        () => checkLocalFiles([], argument: 'paths', platform: _windows),
        toolError(startsWith('paths is empty: give 1 to 10 full paths')),
      );
      final one = file('a.txt');
      expect(
        () => checkLocalFiles(
          [one, one, one],
          argument: 'paths',
          platform: _windows,
          maxCount: 2,
        ),
        toolError(
          'paths holds 3 files; at most 2 go in one call. Nothing was sent.',
        ),
      );
    });

    test('refuses a relative path, a missing file and a folder', () {
      expect(
        () => checkLocalFiles(
          ['brief.docx'],
          argument: 'paths',
          platform: _windows,
        ),
        toolError(startsWith('"brief.docx" in paths is not a full path')),
      );
      expect(
        () => checkLocalFiles(
          [path('weg.pdf')],
          argument: 'paths',
          platform: _windows,
        ),
        toolError(
          'There is no file "${path('weg.pdf')}" on this PC (any more): '
          'check the path. Nothing was sent.',
        ),
      );
      expect(
        () => checkLocalFiles(
          [folder.path],
          argument: 'paths',
          platform: _windows,
        ),
        toolError(startsWith('"${folder.path}" in paths is a folder')),
      );
    });

    test('refuses a name Smartschool does not allow: a dot at the start or '
        'end of the name or of the part before the extension', () {
      for (final name in ['.verborgen', 'notes..txt']) {
        expect(
          () => checkLocalFiles(
            [file(name)],
            argument: 'paths',
            platform: _windows,
          ),
          toolError(
            startsWith('Smartschool does not take a file named "$name"'),
          ),
          reason: name,
        );
      }
    });

    test('refuses a file over the limit, and two files with one name, '
        'ignoring case', () {
      final big = file('groot.pdf', 'x' * 11);
      expect(
        () => checkLocalFiles(
          [big],
          argument: 'paths',
          platform: _windows,
          maxBytes: 10,
        ),
        toolError(
          'The file "groot.pdf" ($big) is 11 bytes, too large to send from '
          'here: files up to 10 bytes can be sent. The user can add it in '
          'Smartschool. Nothing was sent.',
        ),
      );
      expect(
        checkLocalFiles(
          [big],
          argument: 'paths',
          platform: _windows,
          maxBytes: 11,
        ),
        hasLength(1),
      );

      final first = file('Brief.docx');
      final other = Directory(path('andere'))..createSync();
      final second = File('${other.path}${Platform.pathSeparator}brief.DOCX')
        ..writeAsStringSync('x');
      expect(
        () => checkLocalFiles(
          [first, second.path],
          argument: 'attachments',
          platform: _windows,
        ),
        toolError(
          'attachments holds two files named "brief.DOCX" ($first and '
          '${second.path}), which Smartschool would store under the same '
          'name: send one of them, or rename one first. Nothing was sent.',
        ),
      );
    });
  });

  group('localFilesArgument', () {
    test('takes a list of paths, or one path, without the white space around '
        'each', () {
      final brief = file('brief.docx');
      expect(
        [
          for (final f in localFilesArgument(
            [' $brief '],
            argument: 'paths',
            platform: _windows,
          ))
            f.path,
        ],
        [brief],
      );
      expect(
        localFilesArgument(brief, argument: 'paths', platform: _windows),
        hasLength(1),
      );
    });

    test('refuses an item that is not a path, and nothing', () {
      expect(
        () => localFilesArgument(['  '], argument: 'paths', platform: _windows),
        toolError(
          'each item of paths must be the full path of a file on this PC, '
          'like C:\\Users\\jan\\Documents\\brief.docx; "  " is not. Nothing '
          'was sent.',
        ),
      );
      expect(
        () => localFilesArgument([12], argument: 'paths', platform: _windows),
        toolError(contains('; 12 is not.')),
      );
      expect(
        () => localFilesArgument(null, argument: 'paths', platform: _windows),
        toolError(startsWith('paths is empty')),
      );
    });
  });

  test('describeLocalFiles names each file with its size', () {
    const a = LocalFile(path: r'C:\a.pdf', name: 'a.pdf', size: 1024);
    const b = LocalFile(path: r'C:\b.pdf', name: 'b.pdf', size: 3 * 1048576);
    const c = LocalFile(path: r'C:\c.txt', name: 'c.txt', size: 1);
    expect(describeLocalFiles([a]), '"a.pdf" (1.0 KB)');
    expect(describeLocalFiles([a, b]), '"a.pdf" (1.0 KB) and "b.pdf" (3.0 MB)');
    expect(
      describeLocalFiles([a, b, c]),
      '"a.pdf" (1.0 KB), "b.pdf" (3.0 MB) and "c.txt" (1 byte)',
    );
  });

  group('uploadToolError', () {
    const files = [
      LocalFile(path: r'C:\docs\brief.docx', name: 'brief.docx', size: 5),
    ];
    const done = 'Nothing was added to Intradesk.';

    String? message(Object error) =>
        uploadToolError(error, files: files, nothingDone: done)?.message;

    test('a file the upload step refused, in Smartschool\'s words', () {
      expect(
        message(
          const SmartschoolAttachmentUploadError(
            'library message',
            fileName: 'brief.docx',
            statusCode: 400,
            serverMessage: 'De karakters zijn niet toegestaan.',
          ),
        ),
        'Smartschool refused the file "brief.docx" (HTTP 400): "De karakters '
        'zijn niet toegestaan." Rename the file, or leave it out. Nothing was '
        'added to Intradesk.',
      );
      expect(
        message(
          const SmartschoolAttachmentUploadError(
            'library message',
            fileName: 'brief.docx',
            statusCode: 200,
          ),
        ),
        'Smartschool did not take the file "brief.docx" (HTTP 200). Try again '
        'in a moment. Nothing was added to Intradesk.',
      );
      expect(
        message(
          const SmartschoolAttachmentUploadError(
            'library message',
            statusCode: 500,
          ),
        ),
        startsWith('Smartschool gave no upload directory (HTTP 500), so no '),
      );
      expect(
        message(const SmartschoolAttachmentUploadError('not found: x')),
        startsWith('A file could not be uploaded: it was not found any more.'),
      );
    });

    test('a file the library refused before sending, by its path', () {
      expect(
        message(
          ArgumentError.value(
            r'C:\docs\brief.docx',
            'filePaths',
            'names no file',
          ),
        ),
        'The file "brief.docx" (C:\\docs\\brief.docx) was refused before '
        'anything was sent: it names no file. Nothing was added to Intradesk.',
      );
    });

    test('is null for anything else', () {
      expect(
        message(ArgumentError.value('mauve', 'color', 'no colour')),
        isNull,
      );
      expect(message(RangeError.value(3)), isNull);
      expect(message(StateError('x')), isNull);
    });
  });

  group('by platform (#202)', () {
    const linux = ServerPlatform.linux;

    /// What a message says about files that only fits Windows.
    final windowsOnly = RegExp(r'C:\\|drive|Windows|\bPC\b');

    test('LocalPaths words paths for the platform', () {
      const windows = LocalPaths(ServerPlatform.windows);
      expect(windows.computer, 'this PC');
      expect(windows.example(), r'C:\Users\jan\Documents\brief.docx');
      expect(
        windows.example('werkblad.docx'),
        r'C:\Users\jan\Documents\werkblad.docx',
      );
      expect(windows.start, 'starting with the drive');
      expect(windows.readableBy, "the user's Windows account");

      const onLinux = LocalPaths(linux);
      expect(onLinux.computer, 'this computer');
      expect(onLinux.example(), '/home/jan/Documents/brief.docx');
      expect(
        onLinux.example('werkblad.docx'),
        '/home/jan/Documents/werkblad.docx',
      );
      expect(onLinux.start, 'starting with /');
      expect(onLinux.readableBy, "the user's account");
    });

    test('takes a Linux absolute path, and refuses a relative one and a '
        'Windows path, with a Linux example', () {
      final brief = file('brief.docx', '12345');
      expect(brief, startsWith('/'));
      expect(
        [
          for (final f in checkLocalFiles(
            [brief],
            argument: 'paths',
            platform: linux,
          ))
            f.name,
        ],
        ['brief.docx'],
      );
      // An absolute path that names no file passes the full-path check.
      expect(
        () => checkLocalFiles(
          ['/home/jan/Documents/brief.docx'],
          argument: 'paths',
          platform: linux,
        ),
        toolError(
          'There is no file "/home/jan/Documents/brief.docx" on this computer '
          '(any more): check the path. Nothing was sent.',
        ),
      );
      for (final relative in [
        'brief.docx',
        'Documents/brief.docx',
        r'C:\Users\jan\Documents\brief.docx',
      ]) {
        expect(
          () => checkLocalFiles([relative], argument: 'paths', platform: linux),
          toolError(
            '"$relative" in paths is not a full path: give the whole path of '
            'the file, starting with /, like /home/jan/Documents/brief.docx. '
            'Nothing was sent.',
          ),
          reason: relative,
        );
      }
    }, testOn: 'linux');

    test('the argument errors name no drive, no Windows and no PC', () {
      String? refused(void Function() check) {
        try {
          check();
        } on ToolError catch (error) {
          return error.message;
        }
        return null;
      }

      // The temporary folder is a real path of the host (C:\ on Windows),
      // which the message quotes as given: only the wording around it counts.
      final missing = path('weg.pdf');
      final messages = [
        refused(
          () => localFilesArgument(['  '], argument: 'paths', platform: linux),
        ),
        refused(
          () => localFilesArgument(null, argument: 'paths', platform: linux),
        ),
        refused(
          () => checkLocalFiles(
            ['brief.docx'],
            argument: 'paths',
            platform: linux,
          ),
        ),
        refused(
          () => checkLocalFiles([missing], argument: 'paths', platform: linux),
        ),
        refused(
          () => lesficheAttachmentsArgument([
            {'path': ' '},
          ], platform: linux),
        ),
      ];
      expect(messages, everyElement(isNotNull));
      expect([
        for (final m in messages) m!.replaceAll(missing, '<file>'),
      ], everyElement(isNot(contains(windowsOnly))));
      expect(messages[0], contains('like /home/jan/Documents/brief.docx'));
      expect(messages[1], contains('files on this computer, like /home/jan/'));
      expect(
        messages[4],
        'attachment 1 of attachments must be an object with the full path of '
        'a file on this computer (path, like '
        '/home/jan/Documents/werkblad.docx), and optionally its visibility. '
        'Nothing was sent.',
      );
    });

    /// The tools that send files from this computer, made for a session whose
    /// settings say the server runs on [platform].
    List<ServerTool> uploadTools(ServerPlatform platform) {
      final session = SmartschoolSession(
        fakeExtensionSettings(
          null,
          ClientContext(ClientApp.claudeDesktop, platform),
        ),
      );
      addTearDown(session.close);
      return [
        uploadIntradeskFilesTool(session, IntradeskIndexCache.of(session)),
        createLesficheTool(session),
        addLesficheAttachmentsTool(session),
        sendMessageTool(session),
        replyToMessageTool(session),
      ];
    }

    /// The description and input schema of [tool], as the client lists them.
    String listed(ServerTool tool) => jsonEncode({
      'description': tool.definition.description,
      'inputSchema': tool.definition.inputSchema,
    });

    test('the descriptions and schemas of the upload tools give a Linux '
        'path, and name no drive, no Windows and no PC', () {
      for (final tool in uploadTools(linux)) {
        final text = listed(tool);
        expect(
          text,
          isNot(contains(windowsOnly)),
          reason: tool.definition.name,
        );
        expect(
          text,
          contains('/home/jan/Documents/'),
          reason: tool.definition.name,
        );
        expect(text, contains('this computer'), reason: tool.definition.name);
      }
    });

    test('on Windows they keep the Windows path, the PC and the Windows '
        'account', () {
      for (final tool in uploadTools(ServerPlatform.windows)) {
        final text = listed(tool);
        expect(
          text,
          contains(r'C:\\Users\\jan\\Documents\\'),
          reason: tool.definition.name,
        );
        expect(text, contains('this PC'), reason: tool.definition.name);
        expect(
          text,
          contains("the user's Windows account"),
          reason: tool.definition.name,
        );
        expect(
          text,
          isNot(contains('/home/jan')),
          reason: tool.definition.name,
        );
      }
    });

    test('a tool refuses a relative path in Linux words', () async {
      final upload = uploadTools(linux).first;
      expect(
        () => upload.handler(
          CallToolRequest(
            name: 'upload_intradesk_files',
            arguments: {
              'folder_id': '0a1b2c3d-1111-4222-8333-444455556666',
              'paths': ['brief.docx'],
            },
          ),
        ),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            '"brief.docx" in paths is not a full path: give the whole path of '
                'the file, starting with /, like /home/jan/Documents/brief.docx. '
                'Nothing was sent.',
          ),
        ),
      );
    });
  });
}
