/// The clipboard the installer puts the installed path on. These tests
/// change the clipboard: see `clipboardSkipReason`.
@TestOn('windows')
library;

import 'package:smartschool_mcp/src/clipboard.dart';
import 'package:test/test.dart';

import 'support/clipboard.dart';

void main() {
  test('holds exactly the text put on it: no byte order mark in front (#49), '
      'accents intact', () {
    restoreClipboardAfterTest();
    const path =
        r'C:\Users\Jürgen Ölçek\AppData\Local\Programs\smartschool-mcp'
        r'\smartschool-mcp.exe';

    if (!copyToClipboard(path)) {
      markTestSkipped('the clipboard cannot be opened here');
      return;
    }
    final text = readClipboard();

    expect(text, path);
    expect(text!.codeUnits.first, isNot(0xFEFF));
  }, skip: clipboardSkipReason);
}
