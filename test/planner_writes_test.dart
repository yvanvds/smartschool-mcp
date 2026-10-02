/// The pieces the planner tools that write share
/// (`lib/src/planner/planner_writes.dart`): the info text Claude writes as
/// the planner's HTML, the empty lesson hour a fill takes, and the lesson
/// hour, the classes and the type of a new assignment. The writes
/// themselves are tested over MCP in `planner_lesson_tools_test.dart` and
/// `planner_assignment_tools_test.dart`.
library;

import 'package:flutter_smartschool/flutter_smartschool.dart';
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

  group('lessonHourArgument', () {
    test('takes an empty lesson hour or a lesson', () {
      for (final value in [
        'planned-placeholders/4069/$_uuid',
        'id planned-lessons/4069/$_uuid',
      ]) {
        expect('${lessonHourArgument(value)}', value.replaceFirst('id ', ''));
      }
    });

    test('refuses an assignment, another element and what is no element '
        'id', () {
      expect(
        () => lessonHourArgument('planned-assignments/4069/$_uuid'),
        _refused(
          'hour must be a lesson hour of your own planner, as list_planner '
          '(planner me) shows it: an empty lesson hour '
          '(planned-placeholders/4069/…) or a lesson (planned-lessons/4069/…); '
          'planned-assignments/4069/$_uuid is an assignment. Nothing was sent.',
        ),
      );
      expect(
        () => lessonHourArgument('planned-excursions/4069/$_uuid'),
        _refused(
          endsWith(
            'planned-excursions/4069/$_uuid is a planned-excursions. Nothing '
            'was sent.',
          ),
        ),
      );
      expect(
        () => lessonHourArgument('dinsdag het 3e uur'),
        _refused(startsWith('hour must be the id of a planner element')),
      );
    });
  });

  group('lessonHourClassesArgument', () {
    test('is null when absent; else the items without white space and '
        'duplicates, in order', () {
      expect(lessonHourClassesArgument(null), isNull);
      expect(lessonHourClassesArgument([' 6A1 ', 'group/4069_2002', '6a1']), [
        '6A1',
        'group/4069_2002',
      ]);
      expect(lessonHourClassesArgument('6A1'), ['6A1']);
    });

    test('refuses an empty list and an item that is no text', () {
      expect(
        () => lessonHourClassesArgument(const <Object?>[]),
        _refused(
          'classes is empty: name some of the classes of the lesson hour, or '
          'leave classes out for all of them. Nothing was sent.',
        ),
      );
      for (final item in ['', '  ', 12, null]) {
        expect(
          () => lessonHourClassesArgument(['6A1', item]),
          _refused(startsWith('each item of classes must be a class of the ')),
          reason: '$item',
        );
      }
    });
  });

  group('lessonHourClasses', () {
    const a1 = PlannerGroup(id: '4069_2001', platformId: 4069, name: '6A1');
    const a2 = PlannerGroup(id: '4069_2002', platformId: 4069, name: '6A2');
    final hour = PlannedElement(
      id: _uuid,
      platformId: 4069,
      type: PlannedElementType.placeholder,
      typeName: 'planned-placeholders',
      period: PlannerPeriod(
        from: DateTime(2026, 11, 20, 11, 10),
        to: DateTime(2026, 11, 20, 12),
      ),
      participantGroups: const [a1, a2],
    );

    test('gives all classes of the hour, or those named, by name (ignoring '
        'case) or planner id, each once, in the order named', () {
      expect(lessonHourClasses(hour, null), [a1, a2]);
      expect(lessonHourClasses(hour, ['6a2', 'group/4069_2001', '4069_2002']), [
        a2,
        a1,
      ]);
    });

    test('refuses a class that is not the hour\'s, naming its classes', () {
      expect(
        () => lessonHourClasses(hour, ['6A1', '6B1']),
        _refused(
          'classes holds "6B1", which is not a class of the empty lesson hour '
          'on Friday 2026-11-20 11:10–12:00 (6A1, 6A2). Its classes are 6A1 '
          '(group/4069_2001) and 6A2 (group/4069_2002): name some of those, '
          'or leave classes out for all of them.',
        ),
      );
    });

    test('refuses an hour without classes', () {
      final empty = PlannedElement(
        id: _uuid,
        platformId: 4069,
        type: PlannedElementType.placeholder,
        typeName: 'planned-placeholders',
        period: hour.period,
      );
      expect(
        () => lessonHourClasses(empty, null),
        _refused(contains('has no classes, so it cannot get an assignment')),
      );
    });
  });

  group('assignmentTypeArgument', () {
    const ko = PlannerAssignmentType(
      id: 'a1',
      name: 'Kleine Overhoring',
      abbreviation: 'KO',
    );
    const go = PlannerAssignmentType(
      id: 'a2',
      name: 'Grote Overhoring',
      abbreviation: 'GO',
    );
    const types = [go, ko];

    test('finds a type by abbreviation, name, or both, ignoring case and '
        'extra white space', () {
      for (final value in [
        'KO',
        ' ko ',
        'Kleine Overhoring',
        'kleine  overhoring',
        'KO Kleine Overhoring',
      ]) {
        expect(assignmentTypeArgument(value, types), ko, reason: value);
      }
    });

    test('takes an abbreviation before a name', () {
      const odd = PlannerAssignmentType(
        id: 'a3',
        name: 'GO',
        abbreviation: 'X',
      );
      expect(assignmentTypeArgument('GO', [odd, go]), go);
    });

    test('refuses a type that is not the school\'s, listing the school\'s', () {
      expect(
        () => assignmentTypeArgument('Toets', types),
        _refused(
          'type "Toets" is not one of the school\'s assignment types: pass '
          'one by its abbreviation or its name. The school\'s assignment '
          'types are GO Grote Overhoring, KO Kleine Overhoring.',
        ),
      );
      expect(
        () => assignmentTypeArgument('KO', const []),
        _refused(
          endsWith('The planner lists no assignment types for the school.'),
        ),
      );
    });

    test('refuses a value that names more than one type', () {
      const ko2 = PlannerAssignmentType(
        id: 'a4',
        name: 'Korte Opdracht',
        abbreviation: 'KO',
      );
      expect(
        () => assignmentTypeArgument('ko', [ko, ko2]),
        _refused(
          startsWith(
            'type "ko" names 2 assignment types (KO Kleine Overhoring, KO '
            'Korte Opdracht): pass its abbreviation and name together',
          ),
        ),
      );
      expect(assignmentTypeArgument('KO Korte Opdracht', [ko, ko2]), ko2);
    });
  });
}

/// Throws a [ToolError] whose message is (or matches) [message].
Matcher _refused(Object message) =>
    throwsA(isA<ToolError>().having((e) => e.message, 'message', message));
