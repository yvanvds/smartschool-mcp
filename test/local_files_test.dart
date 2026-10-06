/// The local-file helper the upload tools share
/// (`lib/src/uploads/local_files.dart`): checking the paths a tool is given,
/// describing the files, and the library's refusals as ToolErrors.
library;

import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:smartschool_mcp/src/uploads/local_files.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart' show tempCache;

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

      final files = checkLocalFiles([brief, toets], argument: 'paths');

      expect([for (final f in files) f.path], [brief, toets]);
      expect([for (final f in files) f.name], ['brief.docx', 'toets #1.pdf']);
      expect([for (final f in files) f.size], [5, 8]);
      expect(files.first.description, '"brief.docx" (5 bytes)');
      expect(localFileName(toets), 'toets #1.pdf');
    });

    test('refuses no paths and more than the maximum', () {
      expect(
        () => checkLocalFiles([], argument: 'paths'),
        toolError(startsWith('paths is empty: give 1 to 10 full paths')),
      );
      final one = file('a.txt');
      expect(
        () => checkLocalFiles([one, one, one], argument: 'paths', maxCount: 2),
        toolError(
          'paths holds 3 files; at most 2 go in one call. Nothing was sent.',
        ),
      );
    });

    test('refuses a relative path, a missing file and a folder', () {
      expect(
        () => checkLocalFiles(['brief.docx'], argument: 'paths'),
        toolError(startsWith('"brief.docx" in paths is not a full path')),
      );
      expect(
        () => checkLocalFiles([path('weg.pdf')], argument: 'paths'),
        toolError(
          'There is no file "${path('weg.pdf')}" on this PC (any more): '
          'check the path. Nothing was sent.',
        ),
      );
      expect(
        () => checkLocalFiles([folder.path], argument: 'paths'),
        toolError(startsWith('"${folder.path}" in paths is a folder')),
      );
    });

    test('refuses a name Smartschool does not allow: a dot at the start or '
        'end of the name or of the part before the extension', () {
      for (final name in ['.verborgen', 'notes..txt']) {
        expect(
          () => checkLocalFiles([file(name)], argument: 'paths'),
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
        () => checkLocalFiles([big], argument: 'paths', maxBytes: 10),
        toolError(
          'The file "groot.pdf" ($big) is 11 bytes, too large to send from '
          'here: files up to 10 bytes can be sent. The user can add it in '
          'Smartschool. Nothing was sent.',
        ),
      );
      expect(
        checkLocalFiles([big], argument: 'paths', maxBytes: 11),
        hasLength(1),
      );

      final first = file('Brief.docx');
      final other = Directory(path('andere'))..createSync();
      final second = File('${other.path}${Platform.pathSeparator}brief.DOCX')
        ..writeAsStringSync('x');
      expect(
        () => checkLocalFiles([first, second.path], argument: 'attachments'),
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
          for (final f in localFilesArgument([' $brief '], argument: 'paths'))
            f.path,
        ],
        [brief],
      );
      expect(localFilesArgument(brief, argument: 'paths'), hasLength(1));
    });

    test('refuses an item that is not a path, and nothing', () {
      expect(
        () => localFilesArgument(['  '], argument: 'paths'),
        toolError(
          'each item of paths must be the full path of a file on this PC, '
          'like C:\\Users\\jan\\Documents\\brief.docx; "  " is not. Nothing '
          'was sent.',
        ),
      );
      expect(
        () => localFilesArgument([12], argument: 'paths'),
        toolError(contains('; 12 is not.')),
      );
      expect(
        () => localFilesArgument(null, argument: 'paths'),
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
}
