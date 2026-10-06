/// The helpers for one lesfiche in full (`lib/src/planner/lesfiche_detail.dart`,
/// #113), which `read_lesfiche` and the tools that make, change or trash a
/// lesfiche share: the `type` argument, the wording of when pupils see a
/// weblink or an attachment, the lines of a weblink and an attachment, the
/// lesfiche as text, and the pick of an attachment by number or name.
library;

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/planner/lesfiche_detail.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

const _id = 'b0000000-0000-4000-8000-000000000011';

/// The visibility the module writes as [option] with [days].
LessonContentVisibility _visibility(String option, [int? days]) =>
    LessonContentVisibility.fromJson({'option': option, 'daysAfterEnd': days});

/// A lesfiche's detail as the module gives it, with [extra] fields.
LessonContentDetail _detail({
  String type = 'lessons',
  String name = 'Lussen',
  List<Map<String, Object?>> weblinks = const [],
  List<Map<String, Object?>> attachments = const [],
  Map<String, Object?> extra = const {},
}) => LessonContentDetail.fromJson({
  'id': _id,
  'platformId': 4069,
  'name': name,
  'type': type,
  'weblinks': weblinks,
  'attachments': attachments,
  ...extra,
});

/// An attachment as the module gives it.
Map<String, Object?> _attachment(String n, String fileName, {int? size}) => {
  'id': 'f0000000-0000-4000-8000-0000000000$n',
  'fileName': fileName,
  'fileSize': ?size,
};

Matcher _toolError(Object? message) =>
    isA<ToolError>().having((e) => e.message, 'message', message);

void main() {
  group('the type argument', () {
    test('a lesson unless it names an assignment', () {
      expect(lesficheTypeArgument(null), LessonContentType.lesson);
      expect(lesficheTypeArgument('lesson'), LessonContentType.lesson);
      expect(lesficheTypeArgument('assignment'), LessonContentType.assignment);
      expect(lesficheTypes.keys, ['lesson', 'assignment']);
    });

    test('names a kind, and a lesfiche by its name or else its id', () {
      expect(lesficheKindName(LessonContentType.lesson), 'lesson lesfiche');
      expect(
        lesficheKindName(LessonContentType.assignment),
        'assignment lesfiche',
      );
      expect(lesficheKindName(LessonContentType.other), 'lesfiche');
      expect(lesficheTitle(_detail()), 'the lesson lesfiche "Lussen"');
      expect(
        lesficheTitle(_detail(type: 'assignments', name: ' ')),
        'the assignment lesfiche $_id',
      );
    });
  });

  group('formatLesficheVisibility', () {
    test('words every option the web client offers, from the lesson the '
        'lesfiche is planned in', () {
      expect(
        formatLesficheVisibility(LessonContentVisibility.always),
        'always',
      );
      expect(formatLesficheVisibility(LessonContentVisibility.never), 'never');
      expect(
        formatLesficheVisibility(LessonContentVisibility.atStart),
        'from the start of the lesson it is planned in',
      );
      expect(
        formatLesficheVisibility(LessonContentVisibility.atEnd),
        'from the end of the lesson it is planned in',
      );
      expect(
        formatLesficheVisibility(LessonContentVisibility.afterEnd(1)),
        'from 1 day after the end of the lesson it is planned in',
      );
      expect(
        formatLesficheVisibility(LessonContentVisibility.afterEnd(14)),
        'from 14 days after the end of the lesson it is planned in',
      );
    });

    test('days after the end without a number, and an option the library '
        'does not know, by the module\'s name', () {
      expect(
        formatLesficheVisibility(_visibility('days-after-end')),
        'some days after the end of the lesson it is planned in (the module '
        'gave no number)',
      );
      expect(
        formatLesficheVisibility(_visibility('after-exam')),
        'as the module\'s option "after-exam", which this server does not '
        'know',
      );
      expect(
        formatLesficheVisibility(_visibility('after-exam', 2)),
        'as the module\'s option "after-exam" with 2 days, which this server '
        'does not know',
      );
    });
  });

  group('lesficheVisibilityArgument', () {
    LessonContentVisibility parse(Object? value) =>
        lesficheVisibilityArgument(value, where: 'the visibility');

    test('every option the web client offers, always when absent or empty; '
        'case, white space and a hyphen for an underscore do not matter', () {
      expect(parse(null), LessonContentVisibility.always);
      expect(parse(''), LessonContentVisibility.always);
      expect(parse('  '), LessonContentVisibility.always);
      expect(parse('always'), LessonContentVisibility.always);
      expect(parse('never'), LessonContentVisibility.never);
      expect(parse('at_start'), LessonContentVisibility.atStart);
      expect(parse(' AT-START '), LessonContentVisibility.atStart);
      expect(parse('at_end'), LessonContentVisibility.atEnd);
      expect(parse('after_end:1'), LessonContentVisibility.afterEnd(1));
      expect(parse('after-end: 14'), LessonContentVisibility.afterEnd(14));
      expect(parse('After_End:07'), LessonContentVisibility.afterEnd(7));
    });

    test('goes out as the module takes it, and reads back in the words of '
        'formatLesficheVisibility', () {
      expect(parse('at_start').toJson(), {
        'option': 'at-start',
        'daysAfterEnd': null,
      });
      expect(parse('after_end:3').toJson(), {
        'option': 'days-after-end',
        'daysAfterEnd': 3,
      });
      expect(
        formatLesficheVisibility(parse('after_end:3')),
        'from 3 days after the end of the lesson it is planned in',
      );
    });

    test('refuses days the web client does not offer, and anything else, '
        'with the values', () {
      const values =
          'always (the default), never, at_start (from the start of the '
          'lesson it is planned in), at_end (from its end) or after_end:N '
          '(from N days after its end, N from 1 to 14)';
      expect(lesficheVisibilityValues, values);
      for (final days in [0, 15, 99]) {
        expect(
          () => parse('after_end:$days'),
          throwsA(
            _toolError(
              'the visibility is after_end:$days, but the web client offers '
              '1 to 14 days after the end of the lesson. Nothing was sent.',
            ),
          ),
        );
      }
      for (final (value, shown) in [
        ('sometimes', '"sometimes"'),
        ('after_end', '"after_end"'),
        ('after_end:-1', '"after_end:-1"'),
        ('after_end:99999', '"after_end:99999"'),
        ('days-after-end', '"days-after-end"'),
        (3, '3'),
        (true, 'true'),
      ]) {
        expect(
          () => parse(value),
          throwsA(
            _toolError(
              'the visibility is $shown, which is not a visibility: pass '
              '$values. Nothing was sent.',
            ),
          ),
          reason: '$value',
        );
      }
    });
  });

  group('a weblink and an attachment on a line', () {
    test('with what the module gave, and what it left out said so', () {
      expect(
        formatLesficheWeblink(
          LessonContentWeblink(
            id: 'e1',
            name: ' ',
            url: '',
            visibility: _visibility('at-start'),
          ),
        ),
        '(no name) | (no address) | visible to pupils: from the start of the '
        'lesson it is planned in | id e1',
      );
      expect(
        formatLesficheAttachment(
          const LessonContentAttachment(id: 'f1', fileName: ''),
        ),
        '(no name) | visible to pupils: always | id f1',
      );
      expect(
        formatLesficheAttachment(
          const LessonContentAttachment(
            id: 'f2',
            fileName: 'verslag.docx',
            fileSize: 2048,
            mimeType: 'application/msword',
          ),
        ),
        'verslag.docx | 2.0 KB | application/msword | visible to pupils: '
        'always | id f2',
      );
    });
  });

  group('formatLesficheDetail', () {
    test('counts the weblinks of publishers and the deeplinks it does not '
        'show; without courses, no note on the course list', () {
      final text = formatLesficheDetail(
        _detail(
          extra: {
            'partnerWeblinks': [{}],
            'deeplinks': [{}, {}],
          },
        ),
        courseError: const SmartschoolLessonContentCourseListError(
          'course list',
          statusCode: 500,
          items: [],
        ),
      );
      expect(
        text,
        'Lesfiche $_id\n'
        'Kind: lesson\n'
        'Name: Lussen\n'
        'Labels: none\n'
        'Courses: none\n'
        'In the module: visible\n'
        'Weblinks: none\n'
        'Attachments: none\n'
        'Note: it also has 1 weblink of a publisher and 2 deeplinks, which '
        'are not shown here.\n'
        '\n'
        'Public info (what pupils see):\n'
        '(none)\n'
        '\n'
        'Private info (hidden from pupils):\n'
        '(none)',
      );
    });
  });

  group('pickLesficheAttachment', () {
    final lesfiche = _detail(
      attachments: [
        _attachment('01', 'opgave.txt', size: 12),
        _attachment('02', '1'),
        _attachment('03', 'Opgave.txt'),
      ],
    );

    test('by number, by name exactly, else ignoring case', () {
      expect(pickLesficheAttachment(lesfiche, 3).$1, 3);
      expect(pickLesficheAttachment(lesfiche, 'Opgave.txt').$1, 3);
      expect(pickLesficheAttachment(lesfiche, 'opgave.txt').$1, 1);
      expect(
        pickLesficheAttachment(
          _detail(attachments: [_attachment('01', 'Opgave.txt')]),
          'OPGAVE.TXT',
        ).$1,
        1,
      );
    });

    test('a name that is a number names the attachment of that name; a '
        'number written as text that no attachment has as its name, the '
        'attachment with that number', () {
      expect(pickLesficheAttachment(lesfiche, '1').$1, 2);
      expect(pickLesficheAttachment(lesfiche, '3').$1, 3);
    });

    test('a name two attachments have ignoring case: their numbers', () {
      expect(
        () => pickLesficheAttachment(lesfiche, 'OPGAVE.TXT'),
        throwsA(
          _toolError(
            'The lesson lesfiche "Lussen" has more than one attachment named '
            '"OPGAVE.TXT": pass its number instead.\n'
            '1. opgave.txt (12 bytes)\n'
            '3. Opgave.txt',
          ),
        ),
      );
    });

    test('a number out of range, and a lesfiche without attachments', () {
      expect(
        () => pickLesficheAttachment(lesfiche, 0),
        throwsA(
          _toolError(
            startsWith(
              'The lesson lesfiche "Lussen" has 3 attachments, so there is no '
              'attachment 0: pass a number from 1 to 3, or the file name.\n',
            ),
          ),
        ),
      );
      expect(
        () => pickLesficheAttachment(_detail(), 1),
        throwsA(_toolError('The lesson lesfiche "Lussen" has no attachments.')),
      );
    });
  });
}
