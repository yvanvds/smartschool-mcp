import 'package:smartschool_mcp/src/tools/arguments.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

Matcher _toolError(String message) =>
    isA<ToolError>().having((e) => e.message, 'message', message);

void main() {
  group('intArgument', () {
    test('an int', () {
      expect(intArgument({'limit': 10}, 'limit'), 10);
      expect(intArgument({'limit': 0}, 'limit'), 0);
      expect(intArgument({'limit': -3}, 'limit'), -3);
    });

    test('a whole number written with a decimal part, which JSON decodes to '
        'a double', () {
      final value = intArgument({'limit': 101.0}, 'limit');
      expect(value, isA<int>());
      expect(value, 101);
      expect(intArgument({'limit': -0.0}, 'limit'), 0);
    });

    test('absent or null: null', () {
      expect(intArgument({}, 'limit'), isNull);
      expect(intArgument({'limit': null}, 'limit'), isNull);
    });

    test('anything else: a ToolError that names the argument and the '
        'value', () {
      final cases = {
        101.5: 'limit must be a whole number; 101.5 is not.',
        '10': 'limit must be a whole number; "10" is not.',
        true: 'limit must be a whole number; true is not.',
        const [10]: 'limit must be a whole number; [10] is not.',
        // Whole, but beyond the int range: toInt() would clamp it.
        1e300: 'limit must be a whole number; 1e+300 is not.',
        double.nan: 'limit must be a whole number; NaN is not.',
        double.infinity: 'limit must be a whole number; Infinity is not.',
      };
      for (final MapEntry(key: value, value: message) in cases.entries) {
        expect(
          () => intArgument({'limit': value}, 'limit'),
          throwsA(_toolError(message)),
          reason: '$value',
        );
      }
    });
  });

  group('requiredIntArgument', () {
    test('an int or a whole-number double', () {
      expect(requiredIntArgument({'message_id': 7}, 'message_id'), 7);
      expect(requiredIntArgument({'message_id': 7.0}, 'message_id'), 7);
    });

    test('absent or null: a ToolError', () {
      for (final arguments in [
        <String, Object?>{},
        <String, Object?>{'message_id': null},
      ]) {
        expect(
          () => requiredIntArgument(arguments, 'message_id'),
          throwsA(_toolError('message_id is required.')),
        );
      }
    });

    test('a fraction: a ToolError', () {
      expect(
        () => requiredIntArgument({'message_id': 7.5}, 'message_id'),
        throwsA(_toolError('message_id must be a whole number; 7.5 is not.')),
      );
    });
  });

  group('intListArgument', () {
    test('ints and whole-number doubles, in the order given, duplicates '
        'kept', () {
      final ids = intListArgument({
        'message_ids': [103, 101.0, 102, 101],
      }, 'message_ids');
      expect(ids, [103, 101, 102, 101]);
      expect(ids, everyElement(isA<int>()));
      expect(intListArgument({'message_ids': []}, 'message_ids'), isEmpty);
    });

    test('an item that is not a whole number: a ToolError', () {
      for (final (item, shown) in [
        (101.5, '101.5'),
        ('abc', '"abc"'),
        (null, 'null'),
      ]) {
        expect(
          () => intListArgument({
            'message_ids': [101, item],
          }, 'message_ids'),
          throwsA(
            _toolError(
              'each item of message_ids must be a whole number; $shown is '
              'not.',
            ),
          ),
        );
      }
    });

    test('not a list: a ToolError', () {
      expect(
        () => intListArgument({'message_ids': 101}, 'message_ids'),
        throwsA(
          _toolError(
            'message_ids must be a list of whole numbers; 101 is not.',
          ),
        ),
      );
    });

    test('absent or null: a ToolError', () {
      for (final arguments in [
        <String, Object?>{},
        <String, Object?>{'message_ids': null},
      ]) {
        expect(
          () => intListArgument(arguments, 'message_ids'),
          throwsA(_toolError('message_ids is required.')),
        );
      }
    });
  });
}
