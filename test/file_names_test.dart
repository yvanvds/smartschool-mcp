import 'dart:io';

import 'package:smartschool_mcp/src/downloads/file_names.dart';
import 'package:test/test.dart';

void main() {
  SafeFileName safe(String? name) => safeFileName(name, fallback: 'bestand');

  group('safeFileName', () {
    test('keeps a name Windows accepts, without spaces around it', () {
      for (final name in [
        'uitstap.docx',
        'Planning oudercontact 2024-2025.pdf',
        'ëèçà – résumé (v2).xlsx',
        '.verborgen',
        'geen extensie',
      ]) {
        final result = safe('  $name ');
        expect(result.name, name);
        expect(result.changes, isEmpty, reason: name);
        expect(result.given, '  $name ');
      }
    });

    test('a folder in the name is no folder: every separator becomes _', () {
      expect(safe('../../Windows/win.ini').name, '.._.._Windows_win.ini');
      expect(safe(r'..\..\evil.bat').name, '.._.._evil.bat');
      expect(safe(r'C:\Users\x\a.pdf').name, 'C__Users_x_a.pdf');
      expect(safe('/etc/passwd').changes, [
        'it holds characters a file name cannot have',
      ]);
    });

    test('characters Windows refuses, and control characters, become _', () {
      expect(safe('a<b>c:d"e|f?g*h.txt').name, 'a_b_c_d_e_f_g_h.txt');
      expect(safe('regel\neen\tx\u0000.txt').name, 'regel_een_x_.txt');
    });

    test('dots and spaces at the end are left out, as Windows would', () {
      final result = safe('verslag.pdf. . ');
      expect(result.name, 'verslag.pdf');
      expect(result.changes, ['it ends in a dot or a space']);
    });

    test('device names Windows keeps for itself get a _ in front, also with '
        'an extension and in any case', () {
      for (final name in [
        'CON',
        'con.txt',
        'Nul.tar.gz',
        'aux',
        'PRN.pdf',
        'COM1.docx',
        'lpt9',
        'COM\u00B9.txt',
        'com0',
      ]) {
        final result = safe(name);
        expect(result.name, '_$name', reason: name);
        expect(result.changes, ['Windows keeps it for a device']);
      }
      for (final name in ['CONTRACT.pdf', 'console.txt', 'COM10', 'nullen']) {
        expect(safe(name).name, name, reason: name);
      }
    });

    test('a name like the server\'s own files gets a _ in front', () {
      final result = safe('.smartschool-mcp-downloads.json');
      expect(result.name, '_.smartschool-mcp-downloads.json');
      expect(result.changes, [
        'it looks like the name of a file of this server',
      ]);
      expect(
        safe('.SMARTSCHOOL-MCP-0123456789abcdef.part').name,
        startsWith('_'),
      );
    });

    test('a long name is cut short, keeping its extension', () {
      final result = safe('${'verslag ' * 30}.docx');
      expect(result.name.length, lessThanOrEqualTo(maxFileNameLength));
      expect(result.name, startsWith('verslag verslag'));
      expect(result.name, endsWith('ver.docx'));
      expect(result.changes, [
        'it is longer than $maxFileNameLength characters',
      ]);

      final long = safe('a' * 300);
      expect(long.name, 'a' * maxFileNameLength);
    });

    test('a long name is not cut inside a character made of two code '
        'units', () {
      // 🙂 is two UTF-16 code units.
      final result = safe('${'a' * (maxFileNameLength - 6)}🙂🙂🙂.pdf');
      expect(result.name.length, lessThanOrEqualTo(maxFileNameLength));
      expect(result.name, endsWith('🙂.pdf'));
      expect(
        result.name.runes.every((rune) => rune < 0xD800 || rune > 0xDFFF),
        isTrue,
        reason: 'a lone surrogate',
      );
    });

    test('no name, or nothing left of it: the fallback', () {
      for (final name in [null, '', '   ']) {
        final result = safe(name);
        expect(result.name, 'bestand');
        expect(result.given, isNull);
        expect(result.changes, isEmpty);
      }
      for (final name in ['..', '...', ' . ']) {
        final result = safe(name);
        expect(result.name, 'bestand', reason: name);
        expect(result.given, name);
        expect(result.changes, ['it is not a file name']);
      }
    });

    test(
      'every name it gives can be created, and is the file\'s name',
      () async {
        final dir = await Directory.systemTemp.createTemp('smartschool_names_');
        addTearDown(() => dir.delete(recursive: true));
        for (final name in [
          '../../x.pdf',
          'CON',
          'nul.txt',
          'a:b.txt',
          'eind. ',
          '${'x' * 300}.pdf',
          'tab\there.txt',
        ]) {
          final file = File(
            '${dir.path}${Platform.pathSeparator}${safe(name).name}',
          );
          await file.create(exclusive: true);
          expect(file.parent.path, dir.path, reason: name);
          expect(
            dir.listSync().map((e) => e.uri.pathSegments.last),
            contains(safe(name).name),
            reason: name,
          );
        }
      },
    );
  });

  test('numberedFileName puts the number before the extension', () {
    expect(numberedFileName('uitstap.docx', 2), 'uitstap (2).docx');
    expect(numberedFileName('archief.tar.gz', 3), 'archief.tar (3).gz');
    expect(numberedFileName('README', 2), 'README (2)');
    expect(numberedFileName('.verborgen', 2), '.verborgen (2)');
  });
}
