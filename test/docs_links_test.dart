/// The links between the README and the pages under `docs/`: every relative
/// link leads to a file that exists, and every link to a heading to a
/// heading on that page, as GitHub names it (#177).
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final pages = [
    'README.md',
    for (final entity in Directory('docs').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.md'))
        entity.path.replaceAll(r'\', '/'),
  ]..sort();

  test('finds the README, the guides and the tool pages', () {
    expect(
      pages,
      containsAll([
        'README.md',
        'docs/development.md',
        'docs/installatie.md',
        'docs/installatie-chatgpt.md',
        'docs/tools/messages.md',
      ]),
    );
  });

  for (final page in pages) {
    test('$page links only to files and headings that exist', () {
      final links = _links(_text(page));
      expect(links, isNotEmpty);
      for (final link in links) {
        if (RegExp(r'^[a-z]+:').hasMatch(link)) continue;
        final hash = link.indexOf('#');
        final path = hash < 0 ? link : link.substring(0, hash);
        final target = path.isEmpty
            ? page
            : Uri.parse(page).resolve(path).toString();
        expect(
          FileSystemEntity.typeSync(target),
          isNot(FileSystemEntityType.notFound),
          reason: '$page: $link',
        );
        if (hash < 0) continue;
        expect(target, endsWith('.md'), reason: '$page: $link');
        expect(
          _anchors(_text(target)),
          contains(link.substring(hash + 1)),
          reason: '$page: $link',
        );
      }
    });
  }
}

/// The text of [path], without HTML comments and fenced code blocks, where
/// GitHub shows no links or headings.
String _text(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
    .replaceAll(RegExp(r'^```.*?^```', multiLine: true, dotAll: true), '');

/// The targets of the Markdown links in [text].
List<String> _links(String text) => [
  for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(text))
    match.group(1)!,
];

/// The anchors GitHub gives the headings of [text]: lower case, without
/// punctuation, with spaces as hyphens, and `-1`, `-2`, ... after a
/// heading that came before.
Set<String> _anchors(String text) {
  final seen = <String, int>{};
  return {
    for (final match in RegExp(
      r'^#{1,6} (.+)$',
      multiLine: true,
    ).allMatches(text))
      _numbered(
        match
            .group(1)!
            .trim()
            .toLowerCase()
            .replaceAll(
              RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true),
              '',
            )
            .replaceAll(' ', '-'),
        seen,
      ),
  };
}

String _numbered(String anchor, Map<String, int> seen) {
  final count = seen[anchor] ?? 0;
  seen[anchor] = count + 1;
  return count == 0 ? anchor : '$anchor-$count';
}
