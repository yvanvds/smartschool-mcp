import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/cache_folder.dart';
import 'package:test/test.dart';

void main() {
  final sep = Platform.pathSeparator;

  test('the shared cache folder holds the library\'s per-user folders', () {
    for (final username in ['jan.peeters', 'an.claes']) {
      expect(
        SmartschoolClient.defaultCacheDir(username),
        [sharedCacheDirectory(), username].join(sep),
        reason: username,
      );
    }
  });

  test('the shared cache folder is .cache/smartschool, as the README '
      'documents', () {
    expect(sharedCacheDirectory(), endsWith('$sep.cache${sep}smartschool'));
  });
}
