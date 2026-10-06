/// The helpers of the tools that make or change a lesfiche
/// (`lib/src/planner/lesfiche_writes.dart`, #114): the name, the courses
/// (found by name in the school's course list), the weblinks and the
/// attachments a tool takes, each checked before anything is sent. The
/// write itself and its errors are tested over MCP in
/// `lesfiche_create_tool_test.dart`.
library;

import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/planner/lesfiche_writes.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

Matcher _toolError(Object? message) =>
    isA<ToolError>().having((e) => e.message, 'message', message);

PlannerCourse _course(String n, String name) => PlannerCourse(
  id: 'c0000000-0000-4000-8000-0000000000$n',
  platformId: 4069,
  name: name,
);

final _informatica = _course('05', 'informatica');
final _chemie = _course('06', 'chemie');
final _lo = _course('04', 'lichamelijke opvoeding');
final _school = [_informatica, _chemie, _lo];

void main() {
  group('lesficheNameArgument', () {
    test('without the white space around it, up to 255 characters', () {
      expect(lesficheNameArgument('  Lussen '), 'Lussen');
      expect(lesficheNameArgument('x' * 255), hasLength(255));
    });

    test('refuses an empty name and a longer one', () {
      for (final value in [null, '', '   ', 3]) {
        expect(
          () => lesficheNameArgument(value),
          throwsA(
            _toolError(
              'name is empty: give the lesfiche a name. Nothing was sent.',
            ),
          ),
        );
      }
      expect(
        () => lesficheNameArgument(' ${'x' * 256} '),
        throwsA(_toolError(startsWith('name is 256 characters long'))),
      );
    });
  });

  group('the courses', () {
    test('the argument: trimmed, once each ignoring case, in order; null '
        'when absent, an empty list for none', () {
      expect(lesficheCoursesArgument(null), isNull);
      expect(lesficheCoursesArgument(<Object?>[]), isEmpty);
      expect(
        lesficheCoursesArgument([' informatica ', 'Chemie', 'INFORMATICA']),
        ['informatica', 'Chemie'],
      );
      expect(
        () => lesficheCoursesArgument(['informatica', ' ']),
        throwsA(
          _toolError(
            'each item of courses must be a course by its name as '
            'list_lesfiches or list_planner show it (like informatica); " " '
            'is not. Nothing was sent.',
          ),
        ),
      );
    });

    test('found by id, else by name ignoring case and extra white space, '
        'each once, in the order given', () {
      expect(
        lesficheCourses(_school, [
          'Lichamelijke  Opvoeding',
          _informatica.id.toUpperCase(),
          'informatica',
        ]),
        [_lo, _informatica],
      );
    });

    test('a course the list does not have: the names of the school\'s '
        'courses', () {
      expect(
        () => lesficheCourses(_school, ['geschiedenis', 'chemie']),
        throwsA(
          _toolError(
            'courses holds "geschiedenis", which is not a course of the '
            'school\'s course list. Its courses are chemie, informatica, '
            'lichamelijke opvoeding. Pass a course by its name as '
            'list_lesfiches or list_planner show it. Nothing was sent.',
          ),
        ),
      );
    });

    test('a name two courses have: their ids, which tell them apart', () {
      final other = _course('99', 'Informatica');
      expect(
        () => lesficheCourses([..._school, other], ['informatica']),
        throwsA(
          _toolError(
            'courses holds "informatica", which names 2 of the school\'s '
            'courses: informatica (id ${_informatica.id}), Informatica (id '
            '${other.id}). Ask the user which one is meant, and pass its id '
            'instead. Nothing was sent.',
          ),
        ),
      );
      expect(lesficheCourses([..._school, other], [other.id]), [other]);
    });
  });

  group('lesficheWeblinksArgument', () {
    test('each with its name, its address as the web client sends it, the '
        'web client\'s icon and when pupils see it; none when absent', () {
      expect(lesficheWeblinksArgument(null), isEmpty);
      final weblinks = lesficheWeblinksArgument([
        {'name': ' Oefeningen ', 'url': 'https://example.com/oefeningen'},
        {
          'name': 'Quiz',
          'url': ' example.com/quiz?q=a b ',
          'visibility': 'after_end:2',
        },
      ]);
      expect(
        [
          for (final weblink in weblinks)
            (weblink.name, weblink.url, weblink.icon, weblink.visibility),
        ],
        [
          (
            'Oefeningen',
            'https://example.com/oefeningen',
            'earth',
            LessonContentVisibility.always,
          ),
          (
            'Quiz',
            'http://example.com/quiz?q=a%20b',
            'earth',
            LessonContentVisibility.afterEnd(2),
          ),
        ],
      );
    });

    test('refuses a weblink that is not an object, without a name or url, '
        'or with an address the web client refuses, naming it', () {
      for (final (item, message) in [
        (
          'https://example.com',
          'weblink 1 of weblinks must be an object with the name and the url '
              'of the weblink, and optionally its visibility. Nothing was '
              'sent.',
        ),
        (
          {'url': 'https://example.com'},
          'weblink 1 of weblinks has no name: give it one. Nothing was sent.',
        ),
        (
          {'name': 'Quiz', 'url': ' '},
          'weblink 1 of weblinks ("Quiz") has no url. Nothing was sent.',
        ),
        (
          {'name': 'Quiz', 'url': 'geen url'},
          'weblink 1 of weblinks ("Quiz") has the url "geen url", which is '
              'not a web address the Lesfiches web client takes: pass one '
              'like https://example.com/page. Nothing was sent.',
        ),
        (
          {'name': 'Quiz', 'url': 'https://example.com', 'visibility': 'nu'},
          startsWith(
            'the visibility of weblink 1 of weblinks ("Quiz") is "nu", which '
            'is not a visibility: pass always (the default), ',
          ),
        ),
      ]) {
        expect(
          () => lesficheWeblinksArgument([item]),
          throwsA(_toolError(message)),
          reason: '$item',
        );
      }
    });
  });

  group('lesficheAttachmentsArgument', () {
    late Directory files;
    late String lussen;
    late String schema;

    setUp(() async {
      files = await Directory.systemTemp.createTemp('lesfiche_writes_test_');
      addTearDown(() => files.delete(recursive: true));
      lussen = '${files.path}${Platform.pathSeparator}lussen.txt';
      File(lussen).writeAsStringSync('dartschool test\n');
      schema = '${files.path}${Platform.pathSeparator}schema.png';
      File(schema).writeAsStringSync('png');
    });

    test('the files checked, each with when pupils see it, as the library '
        'takes them; none when absent or empty', () {
      expect(lesficheAttachmentsArgument(null), isEmpty);
      expect(lesficheAttachmentsArgument(<Object?>[]), isEmpty);
      final attached = lesficheAttachmentsArgument([
        {'path': ' $lussen ', 'visibility': 'never'},
        {'path': schema},
      ]);
      expect(
        [
          for (final (:file, :visibility) in attached)
            (file.path, file.name, file.size, visibility),
        ],
        [
          (lussen, 'lussen.txt', 16, LessonContentVisibility.never),
          (schema, 'schema.png', 3, LessonContentVisibility.always),
        ],
      );
      expect(
        [
          for (final attachment in lesficheAttachments(attached))
            (attachment.path, attachment.visibility),
        ],
        [
          (lussen, LessonContentVisibility.never),
          (schema, LessonContentVisibility.always),
        ],
      );
    });

    test('refuses an item without a path, a visibility the web client does '
        'not offer, and what the local-file helper refuses', () {
      for (final item in <Object?>[
        lussen,
        {'visibility': 'never'},
        {'path': ' '},
      ]) {
        expect(
          () => lesficheAttachmentsArgument([item]),
          throwsA(
            _toolError(
              'attachment 1 of attachments must be an object with the full '
              'path of a file on this PC (path, like '
              'C:\\Users\\jan\\Documents\\werkblad.docx), and optionally its '
              'visibility. Nothing was sent.',
            ),
          ),
          reason: '$item',
        );
      }
      expect(
        () => lesficheAttachmentsArgument([
          {'path': lussen},
          {'path': schema, 'visibility': 'after_end:0'},
        ]),
        throwsA(
          _toolError(
            'the visibility of attachment 2 of attachments ("$schema") is '
            'after_end:0, but the web client offers 1 to 14 days after the '
            'end of the lesson. Nothing was sent.',
          ),
        ),
      );
      expect(
        () => lesficheAttachmentsArgument([
          {'path': lussen},
        ], maxBytes: 10),
        throwsA(_toolError(startsWith('The file "lussen.txt" ($lussen) is '))),
      );
    });
  });
}
