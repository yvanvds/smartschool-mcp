/// The pieces the planner tools that write share
/// (`lib/src/planner/planner_writes.dart`): the info text Claude writes as
/// the planner's HTML, and the empty lesson hour a fill takes. The writes
/// themselves are tested over MCP in `planner_lesson_tools_test.dart`.
library;

import 'package:smartschool_mcp/src/planner/planner_writes.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

const _uuid = 'e0000000-0000-5000-8000-000000000006';

void main() {
  group('plainTextToHtml', () {
    test('writes a paragraph per block of lines, as the planner\'s editor '
        'does', () {
      expect(
        plainTextToHtml('Breng je laptop mee.'),
        '<p>Breng je laptop mee.</p>',
      );
      expect(
        plainTextToHtml('Eerste regel\nTweede regel\n\nNieuwe alinea'),
        '<p>Eerste regel<br />Tweede regel</p><p>Nieuwe alinea</p>',
      );
    });

    test('escapes <, &, > and quotes, so that HTML shows as text', () {
      expect(
        plainTextToHtml('<b>vet</b> & "citaat" \'n test'),
        '<p>&lt;b&gt;vet&lt;/b&gt; &amp; &quot;citaat&quot; &#39;n test</p>',
      );
      expect(
        plainTextToHtml('<script>alert(1)</script>'),
        '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>',
      );
      expect(plainTextToHtml('&amp;'), '<p>&amp;amp;</p>');
    });

    test('takes Windows and old Mac line ends, several blank lines, and '
        'blank lines with spaces, and leaves out the white space around a '
        'paragraph or a line', () {
      expect(
        plainTextToHtml('  a  \r\n  b\r\r\n \t \n\n\nc\n'),
        '<p>a<br />b</p><p>c</p>',
      );
    });

    test('is empty for no text', () {
      expect(plainTextToHtml(''), '');
      expect(plainTextToHtml(' \n\n \t'), '');
    });
  });

  group('emptyHourArgument', () {
    test('takes the id of an empty lesson hour, also after "id "', () {
      for (final value in [
        'planned-placeholders/4069/$_uuid',
        ' id planned-placeholders/4069/$_uuid ',
      ]) {
        expect(
          '${emptyHourArgument(value)}',
          'planned-placeholders/4069/$_uuid',
        );
      }
    });

    test('refuses a lesson, an assignment, another element and what is no '
        'element id, saying what to use', () {
      Matcher refused(String message) => throwsA(
        isA<ToolError>().having((e) => e.message, 'message', message),
      );

      expect(
        () => emptyHourArgument('planned-lessons/4069/$_uuid'),
        refused(
          'hour must be an empty lesson hour of your own planner, as '
          'list_planner (planner me) shows it, with an id like '
          'planned-placeholders/4069/…; planned-lessons/4069/$_uuid is a '
          'lesson, not an empty lesson hour: change a lesson with '
          'edit_planned_element, or empty its hour first with clear_lesson. '
          'Nothing was sent.',
        ),
      );
      expect(
        () => emptyHourArgument('planned-assignments/4069/$_uuid'),
        refused(
          'hour must be an empty lesson hour of your own planner, as '
          'list_planner (planner me) shows it, with an id like '
          'planned-placeholders/4069/…; planned-assignments/4069/$_uuid is an '
          'assignment, not an empty lesson hour. Nothing was sent.',
        ),
      );
      expect(
        () => emptyHourArgument('planned-excursions/4069/$_uuid', name: 'slot'),
        refused(
          'slot must be an empty lesson hour of your own planner, as '
          'list_planner (planner me) shows it, with an id like '
          'planned-placeholders/4069/…; planned-excursions/4069/$_uuid is a '
          'planned-excursions, not an empty lesson hour. Nothing was sent.',
        ),
      );
      expect(
        () => emptyHourArgument('maandag het 3e uur'),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            startsWith('hour must be the id of a planner element'),
          ),
        ),
      );
    });
  });
}
