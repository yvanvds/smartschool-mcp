import 'dart:io';

import 'package:smartschool_mcp/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(packageVersion, match!.group(1));
  });
}
