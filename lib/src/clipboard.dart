/// The Windows clipboard, for the installer: it puts the installed path
/// there for the teacher to paste into ChatGPT's form.
///
/// Through the Windows API (`dart:ffi`), not `clip.exe`: given UTF-16 with a
/// byte order mark, `clip.exe` keeps the mark as a character (U+FEFF), which
/// then lands invisibly in front of the pasted path, and ChatGPT cannot
/// start the server (#49). Without the mark, it guesses the encoding.
library;

import 'dart:ffi';
import 'dart:io';

/// The clipboard format for UTF-16 text, ending in a 0.
const _cfUnicodeText = 13;

/// `GlobalAlloc` memory the clipboard can take over.
const _gmemMoveable = 0x0002;

/// Puts exactly [text] on the clipboard as Unicode text, and returns whether
/// it worked; never throws. Retries for a moment while another program has
/// the clipboard open. False on other systems than Windows.
bool copyToClipboard(String text) {
  if (!Platform.isWindows) return false;
  try {
    return _copy(text);
  } on Object {
    return false;
  }
}

bool _copy(String text) {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final openClipboard = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'OpenClipboard',
      );
  final emptyClipboard = user32
      .lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
  final setClipboardData = user32
      .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
        'SetClipboardData',
      );
  final closeClipboard = user32
      .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
  final globalAlloc = kernel32
      .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
        'GlobalAlloc',
      );
  final globalLock = kernel32
      .lookupFunction<
        Pointer<Uint16> Function(IntPtr),
        Pointer<Uint16> Function(int)
      >('GlobalLock');
  final globalUnlock = kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'GlobalUnlock',
      );
  final globalFree = kernel32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');

  final units = text.codeUnits;
  final memory = globalAlloc(_gmemMoveable, (units.length + 1) * 2);
  if (memory == 0) return false;
  final pointer = globalLock(memory);
  if (pointer == nullptr) {
    globalFree(memory);
    return false;
  }
  pointer.asTypedList(units.length + 1)
    ..setRange(0, units.length, units)
    ..[units.length] = 0;
  globalUnlock(memory);

  var opened = false;
  for (var attempt = 0; attempt < 10 && !opened; attempt++) {
    if (attempt > 0) sleep(const Duration(milliseconds: 50));
    opened = openClipboard(0) != 0;
  }
  if (!opened) {
    globalFree(memory);
    return false;
  }
  try {
    emptyClipboard();
    // On success the clipboard owns the memory; on failure it is ours.
    if (setClipboardData(_cfUnicodeText, memory) != 0) return true;
    globalFree(memory);
    return false;
  } finally {
    closeClipboard();
  }
}
