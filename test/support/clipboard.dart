import 'dart:ffi';
import 'dart:io';

import 'package:smartschool_mcp/src/clipboard.dart';
import 'package:test/test.dart';

/// Set to `on` to run the tests that use the clipboard outside CI. They
/// replace what is on it, and put back the text that was there.
const clipboardTestVariable = 'SMARTSCHOOL_MCP_CLIPBOARD_TEST';

/// Why the clipboard tests are skipped here, or null to run them: they run
/// in CI (`CI` is set) and with [clipboardTestVariable], so a developer's
/// `dart test` leaves the clipboard alone.
String? get clipboardSkipReason =>
    Platform.environment.containsKey('CI') ||
        Platform.environment[clipboardTestVariable] == 'on'
    ? null
    : 'changes the clipboard; set $clipboardTestVariable=on to run it';

/// Keeps the text on the clipboard and puts it back after the test.
void restoreClipboardAfterTest() {
  final before = readClipboard();
  addTearDown(() {
    if (before != null) copyToClipboard(before);
  });
}

/// The text on the clipboard (`CF_UNICODETEXT`) exactly, or null when there
/// is none or the clipboard cannot be opened.
String? readClipboard() {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final openClipboard = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'OpenClipboard',
      );
  final getClipboardData = user32
      .lookupFunction<IntPtr Function(Uint32), int Function(int)>(
        'GetClipboardData',
      );
  final closeClipboard = user32
      .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
  final globalLock = kernel32
      .lookupFunction<
        Pointer<Uint16> Function(IntPtr),
        Pointer<Uint16> Function(int)
      >('GlobalLock');
  final globalUnlock = kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'GlobalUnlock',
      );

  if (openClipboard(0) == 0) return null;
  try {
    final data = getClipboardData(13); // CF_UNICODETEXT
    if (data == 0) return null;
    final pointer = globalLock(data);
    if (pointer == nullptr) return null;
    try {
      final units = <int>[];
      for (var i = 0; pointer[i] != 0; i++) {
        units.add(pointer[i]);
      }
      return String.fromCharCodes(units);
    } finally {
      globalUnlock(data);
    }
  } finally {
    closeClipboard();
  }
}
