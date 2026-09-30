// Full-text matching for `search_messages`: the query, matching a message
// and the snippet shown around a hit.

/// [text] lowercased and without accents (`É` becomes `e`), for matching.
///
/// The result has the same length as [text], so a position in it is the same
/// position in [text]: a snippet is cut from the original text at the place
/// a match was found in the folded one.
String foldForSearch(String text) {
  var lower = text.toLowerCase();
  if (lower.length != text.length) {
    // A few characters lowercase to more than one code unit (like `İ`); those
    // are kept as they are.
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      final char = String.fromCharCode(unit);
      final folded = char.toLowerCase();
      buffer.write(folded.length == 1 ? folded : char);
    }
    lower = buffer.toString();
  }
  List<int>? units;
  for (var i = 0; i < lower.length; i++) {
    final plain = _unaccented[lower.codeUnitAt(i)];
    if (plain != null) (units ??= lower.codeUnits.toList())[i] = plain;
  }
  return units == null ? lower : String.fromCharCodes(units);
}

/// Lowercase letters with an accent, by the letter without it.
const _accented = {
  'a': 'àáâãäåāăą',
  'c': 'çćč',
  'd': 'ďđ',
  'e': 'èéêëēėęě',
  'g': 'ğ',
  'i': 'ìíîïīįı',
  'l': 'łľĺ',
  'n': 'ñńň',
  'o': 'òóôõöøōő',
  'r': 'ŕř',
  's': 'šśş',
  't': 'ťţ',
  'u': 'ùúûüūůűų',
  'y': 'ýÿ',
  'z': 'žźż',
};

final Map<int, int> _unaccented = {
  for (final MapEntry(key: plain, value: letters) in _accented.entries)
    for (final letter in letters.codeUnits) letter: plain.codeUnitAt(0),
};

/// Punctuation around a word of the query that is not part of it, like the
/// quotes of `"verlofdag"` or the question mark of `verlofdag?`.
final _edgePunctuation = RegExp(
  '^["\'“”‘’„«»,.;:!?()\\[\\]]+|["\'“”‘’„«»,.;:!?()\\[\\]]+\$',
);

final _whitespace = RegExp(r'\s+');
final _space = RegExp(r'\s');

/// The words to look for, folded with [foldForSearch].
///
/// A message matches when every word occurs in it, in any order and also as
/// part of a longer word: `verlof` finds `verlofdag`.
final class SearchQuery {
  SearchQuery._(this.terms);

  /// The words of [text], or null when it has none.
  static SearchQuery? parse(String text) {
    final terms = <String>{
      for (final word in foldForSearch(text).split(_whitespace))
        if (word.replaceAll(_edgePunctuation, '') case final term
            when term.isNotEmpty)
          term,
    };
    return terms.isEmpty ? null : SearchQuery._(terms.toList());
  }

  /// The folded words, without duplicates, in the order of the query.
  final List<String> terms;

  /// Whether every word occurs in [texts] (together).
  bool matches(Iterable<String> texts) {
    final folded = texts.map(foldForSearch).join('\n');
    return terms.every(folded.contains);
  }

  /// A piece of [text] of about [width] characters around the words: the
  /// stretch that holds the most different words (the first such stretch
  /// when there are several), with as much context before as after.
  ///
  /// Line breaks and runs of whitespace become one space, the piece is cut
  /// between words, and `…` marks where [text] goes on. When [text] holds
  /// none of the words, its start.
  String snippet(String text, {int width = 200}) {
    final folded = foldForSearch(text);
    final hits = <({int start, int end, int term})>[
      for (final (index, term) in terms.indexed)
        for (
          var at = folded.indexOf(term);
          at >= 0;
          at = folded.indexOf(term, at + 1)
        )
          (start: at, end: at + term.length, term: index),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // The hits to show: from..to.
    var (from, to) = (0, 0);
    if (hits.isNotEmpty) {
      // Slides a window over the hits: hits[first] up to (not including)
      // hits[next], all ending within [width] of hits[first]'s start.
      final counts = List.filled(terms.length, 0);
      var distinct = 0;
      var best = 0;
      var next = 0;
      void add(int hit) {
        if (counts[hits[hit].term]++ == 0) distinct++;
      }

      for (var first = 0; first < hits.length; first++) {
        // The window always holds hits[first], even one longer than [width].
        if (next == first) add(next++);
        while (next < hits.length &&
            hits[next].end <= hits[first].start + width) {
          add(next++);
        }
        if (distinct > best) {
          best = distinct;
          from = hits[first].start;
          to = hits
              .sublist(first, next)
              .map((hit) => hit.end)
              .reduce((a, b) => a > b ? a : b);
        }
        if (--counts[hits[first].term] == 0) distinct--;
      }
    }

    // Widen from..to to [width] characters, the same amount on both sides,
    // or more on one side at the start or end of the text.
    final length = to - from > width ? to - from : width;
    var start = from - (length - (to - from)) ~/ 2;
    if (start < 0) start = 0;
    var end = start + length;
    if (end > text.length) {
      end = text.length;
      start = end - length < 0 ? 0 : end - length;
    }
    // Cut between words, never through a hit.
    if (start > 0) {
      final space = text.indexOf(_space, start);
      if (space >= 0 && space < from) start = space + 1;
    }
    if (end < text.length) {
      final space = text.lastIndexOf(_space, end);
      if (space >= to && space > start) end = space;
    }

    final piece = text.substring(start, end).replaceAll(_whitespace, ' ');
    return [
      if (start > 0) '…',
      piece.trim(),
      if (end < text.length) '…',
    ].join();
  }
}
