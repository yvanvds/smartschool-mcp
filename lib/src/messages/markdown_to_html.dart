/// Converts the text of a message Claude writes, plain text or simple
/// Markdown, to the HTML body Smartschool sends.
///
/// Every character of [text] is escaped, so HTML in it shows as text and
/// never becomes markup: the text cannot add tags, attributes or scripts to
/// the message. Only this converter writes tags:
///
/// - a blank line starts a new paragraph (`<p>`), a single line break becomes
///   `<br>`;
/// - lines starting with `- `, `* ` or `+ ` become a bulleted list, lines
///   starting with `1. ` or `1) ` a numbered list (an indented line that
///   follows an item continues it);
/// - `**bold**` and `__bold__` become `<strong>`, `*italic*` and `_italic_`
///   `<em>` (not inside a word for `_`, and not with a space right inside
///   the markers, so `5 * 3` and `file_name` stay as written);
/// - `[text](https://...)` becomes a link for `http`, `https` and `mailto`
///   addresses; any other link is left as written.
///
/// Anything else (headings, code, tables) is kept as the text it is.
String markdownToHtml(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <String>[];
  final paragraph = <String>[];
  final items = <String>[];
  _ListKind? list;
  int? listStart;

  void endParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add('<p>${paragraph.map(_inline).join('<br>')}</p>');
    paragraph.clear();
  }

  void endList() {
    if (list == null) return;
    final start = listStart != null && listStart != 1
        ? ' start="$listStart"'
        : '';
    blocks.add(
      '<${list!.tag}$start>'
      '${items.map((item) => '<li>$item</li>').join()}'
      '</${list!.tag}>',
    );
    items.clear();
    list = null;
    listStart = null;
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      endParagraph();
      endList();
      continue;
    }
    if (_bullet.firstMatch(line) case final match?) {
      endParagraph();
      if (list != _ListKind.bulleted) endList();
      list = _ListKind.bulleted;
      items.add(_inline(match[1]!.trim()));
    } else if (_numbered.firstMatch(line) case final match?) {
      endParagraph();
      if (list != _ListKind.numbered) {
        endList();
        listStart = int.tryParse(match[1]!);
      }
      list = _ListKind.numbered;
      items.add(_inline(match[2]!.trim()));
    } else if (list != null && line.startsWith(RegExp(r'\s'))) {
      items.add('${items.removeLast()}<br>${_inline(line.trim())}');
    } else {
      endList();
      paragraph.add(line.trim());
    }
  }
  endParagraph();
  endList();
  return blocks.join('\n');
}

enum _ListKind {
  bulleted('ul'),
  numbered('ol');

  const _ListKind(this.tag);

  final String tag;
}

final _bullet = RegExp(r'^\s*[-*+]\s+(\S.*)$');
final _numbered = RegExp(r'^\s*(\d{1,9})[.)]\s+(\S.*)$');

/// One line of text with its inline markup converted and everything else
/// escaped.
String _inline(String text) => text.splitMapJoin(
  _inlineMarkup,
  onMatch: (found) {
    final match = found as RegExpMatch;
    if (match.namedGroup('linkText') case final linkText?) {
      final url = match.namedGroup('url')!;
      if (!_allowedUrl.hasMatch(url)) return _escape(match[0]!);
      return '<a href="${_escape(url)}">${_inline(linkText)}</a>';
    }
    if (match.namedGroup('boldItalic') case final both?) {
      return '<strong><em>${_inline(both)}</em></strong>';
    }
    if (match.namedGroup('bold') ?? match.namedGroup('bold2')
        case final bold?) {
      return '<strong>${_inline(bold)}</strong>';
    }
    final italic = match.namedGroup('italic') ?? match.namedGroup('italic2');
    return '<em>${_inline(italic!)}</em>';
  },
  onNonMatch: _escape,
);

/// Links, bold and italic, leftmost first. Bold and italic together
/// (`***x***`) come before bold, and bold before italic, so `**x**` is not
/// read as italic `*` around `*x*`.
final _inlineMarkup = RegExp(
  r'\[(?<linkText>[^\]\n]+)\]\((?<url>[^()\s]+)\)'
  r'|\*\*\*(?<boldItalic>[^\s*](?:.*?[^\s*])?)\*\*\*'
  r'|\*\*(?<bold>\S(?:.*?\S)?)\*\*'
  r'|(?<![\p{L}\p{N}_])__(?<bold2>\S(?:.*?\S)?)__(?![\p{L}\p{N}_])'
  r'|\*(?<italic>[^\s*](?:[^*]*?[^\s*])?)\*'
  r'|(?<![\p{L}\p{N}_])_(?<italic2>[^\s_](?:[^_]*?[^\s_])?)_(?![\p{L}\p{N}_])',
  unicode: true,
);

final _allowedUrl = RegExp(r'^(https?://|mailto:)\S+$', caseSensitive: false);

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
