import 'package:smartschool_mcp/src/messages/message_search.dart';
import 'package:test/test.dart';

SearchQuery _query(String text) => SearchQuery.parse(text)!;

void main() {
  group('foldForSearch', () {
    test('lowercases and drops accents', () {
      expect(
        foldForSearch('Financiële Één Ça Ñandú'),
        'financiele een ca nandu',
      );
      expect(foldForSearch('ÀÉÎÕÜ ÿ ž Ł'), 'aeiou y z l');
    });

    test('keeps the length, so positions stay valid', () {
      for (final text in [
        'Café Brûlé',
        'İstanbul',
        'straße œuvre',
        'emoji 😀 ok',
        '',
      ]) {
        expect(foldForSearch(text).length, text.length, reason: text);
      }
      // Where İ lowercases to two code units (in JavaScript), it is kept.
      expect(foldForSearch('İSTANBUL'), endsWith('stanbul'));
    });
  });

  group('SearchQuery.parse', () {
    test('folds the words, drops duplicates and punctuation around them', () {
      expect(
        _query('  "Facultatieve   VERLOFDAG?" verlofdag, (financiële) ').terms,
        ['facultatieve', 'verlofdag', 'financiele'],
      );
    });

    test('keeps punctuation inside a word', () {
      expect(_query('e-mail 12/05 3.5').terms, ['e-mail', '12/05', '3.5']);
    });

    test('is null without words', () {
      expect(SearchQuery.parse(''), isNull);
      expect(SearchQuery.parse('   '), isNull);
      expect(SearchQuery.parse(' "" ? , '), isNull);
    });
  });

  group('SearchQuery.matches', () {
    final query = _query('facultatieve verlofdag');

    test('every word must occur, in any order, in any of the texts', () {
      expect(query.matches(['Is de verlofdag facultatieve?']), isTrue);
      expect(
        query.matches(['Verlofdag', 'Directie', 'een facultatieve dag']),
        isTrue,
      );
      expect(query.matches(['De facultatieve dag']), isFalse);
      expect(query.matches(const []), isFalse);
    });

    test('ignores case and accents, and matches inside longer words', () {
      expect(_query('verlof').matches(['FACULTATIEVE VERLOFDAGEN']), isTrue);
      expect(_query('financiele').matches(['Financiële dienst']), isTrue);
      expect(_query('financiële').matches(['financiele dienst']), isTrue);
    });

    test('a word does not match across two texts', () {
      expect(_query('verlofdag').matches(['verlof', 'dag']), isFalse);
    });
  });

  group('SearchQuery.snippet', () {
    const filler =
        'Dit is een lange zin zonder de gezochte woorden die alleen dient om '
        'de tekst lang genoeg te maken voor een knipsel. ';

    test('a short text is shown whole, its whitespace collapsed', () {
      expect(
        _query(
          'verlofdag',
        ).snippet('De  facultatieve\n\nverlofdag is\tmaandag.'),
        'De facultatieve verlofdag is maandag.',
      );
    });

    test('cuts around the hit between words, with … where the text goes '
        'on', () {
      final text =
          '${filler * 3}De facultatieve verlofdag valt op maandag 3 '
          'juni. ${filler * 3}';
      final snippet = _query('verlofdag').snippet(text, width: 80);

      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
      expect(snippet, contains('De facultatieve verlofdag valt op maandag'));
      expect(snippet.length, lessThanOrEqualTo(82));
      // Whole words only.
      final words = text.split(RegExp(r'\s+')).toSet();
      for (final word in snippet.replaceAll('…', '').split(' ')) {
        expect(words, contains(word));
      }
    });

    test('picks the stretch with the most different words', () {
      final text =
          'Verlofdag hier alleen. ${filler * 4}'
          'Pas hier staan facultatieve en verlofdag samen. ${filler * 4}';
      final snippet = _query('facultatieve verlofdag').snippet(text, width: 80);

      expect(snippet, contains('facultatieve en verlofdag samen'));
      expect(snippet, isNot(contains('hier alleen')));
    });

    test('takes the first stretch when several hold as many words', () {
      final text =
          '${filler * 2}eerste verlofdag ${filler * 2}tweede '
          'verlofdag ${filler * 2}';

      expect(
        _query('verlofdag').snippet(text, width: 60),
        contains('eerste verlofdag'),
      );
    });

    test('a hit at the start or end uses the room on the other side', () {
      final start = 'Verlofdag op maandag. ${filler * 3}';
      final end = '${filler * 3}Tot slot: de verlofdag';

      final atStart = _query('verlofdag').snippet(start, width: 80);
      final atEnd = _query('verlofdag').snippet(end, width: 80);

      expect(atStart, startsWith('Verlofdag op maandag.'));
      expect(atStart, endsWith('…'));
      expect(atStart.length, greaterThan(60));
      expect(atEnd, startsWith('…'));
      expect(atEnd, endsWith('Tot slot: de verlofdag'));
      expect(atEnd.length, greaterThan(60));
    });

    test('finds a hit through accents and case, and shows the original '
        'text', () {
      final text = '${filler * 2}De FINANCIËLE dienst betaalt. ${filler * 2}';

      expect(
        _query('financiele').snippet(text, width: 60),
        contains('De FINANCIËLE dienst betaalt.'),
      );
    });

    test('without a hit in the text: its start', () {
      final text = filler * 3;
      final snippet = _query('verlofdag').snippet(text, width: 60);

      expect(snippet, startsWith('Dit is een lange zin'));
      expect(snippet, endsWith('…'));
      expect(snippet.length, lessThanOrEqualTo(61));
    });

    test('a hit longer than the width is shown whole', () {
      final text = '$filler${'x' * 50} $filler';

      expect(_query('x' * 50).snippet(text, width: 20), contains('x' * 50));
    });

    test('an empty text gives an empty snippet', () {
      expect(_query('verlofdag').snippet(''), '');
    });
  });
}
