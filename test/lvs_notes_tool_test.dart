/// `read_lvs_notes` (#154), called over MCP on the real server, session and
/// library (`LvsService.getNotes`, `getAllNotes`), against a fake
/// Smartschool whose pupil tracking system (LVS) answers with the
/// hand-written fixtures of `test/fixtures/lvs/notes/` (the fakes of
/// `FAKES.md` only, checked by `test/lvs_fixtures_guard_test.dart`): one
/// category with its sub-categories, all categories, the school year,
/// since, limit and confidential notes; and the privacy rules every LVS
/// tool follows (#153): only reads, nothing on disk, nothing of an answer
/// or an error's message in the log.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:smartschool_mcp/src/lvs/lvs_format.dart';
import 'package:smartschool_mcp/src/lvs/lvs_notes.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/lvs_tool_harness.dart';

/// Today for the tests: in school year 2030-2031, that of the fixtures.
final _now = DateTime.utc(2030, 10, 25, 9);

/// The `syRange` the library sends for school year 2030-2031.
const _range2030 = 'syRange={"from":"2030-09-01","until":"2031-08-31"}';

/// The request for the notes of category [id] of Jan Janssens in 2030-2031.
String _categoryCall(int id, {String range = _range2030}) =>
    'POST /?module=LVS&file=dispatcher lvs_cats/getUserCatItems '
    'catID=$id userID=900001 toolbarType=main $range groupID=900101 '
    'toolbarSide=left';

/// The request for all notes of [pupil] in 2030-2031.
String _allCall(FakeLvsPupil pupil, {String range = _range2030}) =>
    'POST /?module=LVS&file=dispatcher lvs_pupils/getUserData '
    'userID=${pupil.pupilId} toolbarType=main groupID=${pupil.classId} '
    '$range viewAllFilter=[] filterData=0';

/// The request of Jan Janssens's file: the file only, without today's
/// attendance (`getStatusInfo`), which the tool does not show.
const _janFileCall = 'GET /LVS/Spotlight/900001?classID=900101';

/// The notes of Jan Janssens as `read_lvs_notes` shows them, newest first
/// (`notes/category.xml`, `subcategory.xml`, `subcategory_deep.xml`), the
/// first of each of its categories read with the category.
const _talk =
    '- 2030-11-05 | Testsubcategorie (category_id 900402) | Testgesprek met '
    'Koen Wouters. | by Jacobs Els | new\n'
    '  Testveld afspraken:\n'
    '    Testafspraak een.\n'
    '    Testafspraak twee.';

/// A note just after midnight in Belgian time: 22:30 UTC the day before.
const _midnight =
    '- 2030-10-15 | Testcategorie (category_id 900401) | (no title) | by '
    'Peeters Piet\n'
    '  (no field filled in)';

/// The note with a field of every type, as a read of its category shows
/// it.
const _everyField =
    '- 2030-10-01 | Testcategorie (category_id 900401) | Testnotitie over de '
    'les. | by Peeters Piet | new\n'
    '  Testveld tekst: Testtekst over het gedrag.\n'
    '  Testveld verslag:\n'
    '    Testverslag met nadruk & meer.\n'
    '    Testregel twee.\n'
    '    Testregel drie.\n'
    '  Testtitel (heading)\n'
    '  Testveld keuze: Testoptie goed\n'
    '  Testveld vinkjes: Testoptie een, Testoptie twee\n'
    '  Testveld lijst: Testoptie & meer\n'
    '  Testveld bijlagen: Testbijlage.pdf, Testfoto.jpg (attachments, by '
    'name only)\n'
    '  Testveld datum: 2030-10-23\n'
    '  Testveld vandaag: "current" (as the LVS gives it, no day)\n'
    '  Testveld onbekend (a field of a type the server does not know, as '
    'the LVS gives it): Testwaarde onbekend';

/// The confidential note, when it is asked for.
const _confidential =
    '- 2030-10-08 | Testcategorie (category_id 900401) | Testnotitie '
    'vertrouwelijk. | by Dupré Céline | vertrouwelijk (confidential)\n'
    '  Testveld verslag: Testnotitie, vertrouwelijk.';

/// The note of a sub-category under a heading, as a read of its category
/// names it (its own answer has no category name: catInfo gives it).
const _deep =
    '- 2030-09-20 | Testsubcategorie (category_id 900404) | Testnotitie '
    'zonder categorienaam. | by Peeters Piet\n'
    '  Testveld tekst: Testtekst in een oudere vorm.';

/// What the confidential note is: none of it may show when it is left out.
const _confidentialParts = [
  'Testnotitie vertrouwelijk.',
  'Testnotitie, vertrouwelijk.',
  'Dupré',
  'Céline',
  '2030-10-08',
];

/// The line on one confidential note left out.
const _oneConfidential =
    '1 confidential (vertrouwelijk), of which nothing is shown: pass '
    'include_confidential true only when the user explicitly asks for '
    'confidential notes';

const _refused =
    "Smartschool's pupil tracking system (LVS) refused this read to the "
    'account: it may have no access to the LVS, or may not see this pupil.';

const _unreadable =
    "Smartschool's pupil tracking system (LVS) answered with something the "
    'server could not read';

void main() {
  late LvsToolHarness h;
  late FakeLvs lvs;

  setUp(() async {
    h = await LvsToolHarness.start(now: () => _now);
    lvs = h.lvs;
  });

  Map<String, Object?> jan([Map<String, Object?> more = const {}]) => {
    ...fakeLvsPupilArguments(fakeLvsJan),
    ...more,
  };

  Future<String> read(Map<String, Object?> arguments) =>
      h.ok('read_lvs_notes', arguments);

  Future<String> refused(Map<String, Object?> arguments) =>
      h.error('read_lvs_notes', arguments);

  group('the tool is listed', () {
    late Tool tool;
    late List<String> names;

    setUp(() async {
      final tools = await h.listTools();
      names = tools.keys.toList();
      tool = tools['read_lvs_notes']!;
    });

    test('after the overview of the file, read-only and idempotent', () {
      expect(names.take(3), [
        'search_lvs_pupils',
        'read_lvs_pupil',
        'read_lvs_notes',
      ]);
      final annotations = tool.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.destructiveHint, isNot(true));
    });

    test('its description: the privacy rules of every LVS tool, confidential '
        'notes only when the user explicitly asks, and what is not known yet '
        'of the "new" mark (yvanvds/dartschool#168: whether the LVS takes a '
        'read note as seen was not captured)', () {
      final description = tool.description!;
      expect(description, contains(lvsPrivacyRules));
      expect(
        description,
        contains(
          'Confidential notes (vertrouwelijk) are left out and only counted, '
          'unless include_confidential is true: set it only when the user '
          'explicitly asks for confidential notes.',
        ),
      );
      expect(
        description,
        endsWith(
          'This tool only reads, and the server sends nothing that marks a '
          'note as seen; whether Smartschool takes notes as seen by this '
          'account when they are read (their "new" mark) is not known yet.',
        ),
      );
      expect(description, isNot(contains('Reading changes nothing')));
    });

    test('takes pupil_id and class_id, and optionally a category (id or '
        'name), a school year, since, a limit and include_confidential', () {
      final schema = tool.inputSchema;
      expect(schema.required, ['pupil_id', 'class_id']);
      expect(schema.properties!.keys, [
        'pupil_id',
        'class_id',
        'category',
        'school_year',
        'since',
        'limit',
        'include_confidential',
      ]);
      expect(schema.properties!['category'], {
        'description': contains('category_id'),
        'anyOf': [
          {'type': 'integer', 'minimum': 1},
          {'type': 'string', 'minLength': 1},
        ],
      });
      expect(schema.properties!['school_year'], {
        'type': 'string',
        'description': contains('Default: the current school year.'),
      });
      expect(schema.properties!['limit'], {
        'type': 'integer',
        'description': contains('Default 20, at most 100.'),
        'minimum': 1,
        'maximum': 100,
      });
      expect(schema.properties!['include_confidential'], {
        'type': 'boolean',
        'description': contains('only when the user explicitly asks'),
      });
    });
  });

  group('all categories', () {
    test('by default: the "all items" view of the current school year, '
        'newest first by their Belgian day, every note with its category, '
        'and the confidential one left out and counted, with nothing of '
        'it', () async {
      final text = await read(jan());

      expect(
        text,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2030-2031, in all note categories, newest first.\n'
        '$_talk\n'
        '$_midnight\n'
        '- 2030-10-01 | Testcategorie (category_id 900401) | Testnotitie over '
        'de les. | by Peeters Piet | new\n'
        '  Testveld tekst: Testtekst over het gedrag.\n'
        '- 2030-09-20 | category_id 900404 | Testnotitie zonder '
        'categorienaam. | by Peeters Piet\n'
        '  Testveld tekst: Testtekst in een oudere vorm.\n'
        'Shown: 4 of the 5 notes. Left out: $_oneConfidential.',
      );
      for (final part in _confidentialParts) {
        expect(text, isNot(contains(part)));
      }
      // The note of 2029-2030 in the answer is not of this school year.
      expect(text, isNot(contains('vorig schooljaar')));
      expect(lvs.calls, [_allCall(fakeLvsJan)]);
      expect(lvs.reads, [FakeLvsRead.allNotes]);
    });

    test('the current school year is that of today: an earlier one '
        'than the notes\' holds none of them, and the file is read to tell '
        'that from a pupil the LVS does not know', () async {
      final h = await LvsToolHarness.start(
        now: () => DateTime.utc(2027, 8, 31, 22, 30), // 00:30, 1 September
        // in Belgium
      );

      final text = await h.ok('read_lvs_notes', jan());

      expect(
        text,
        'The LVS holds no notes of the pupil with pupil_id 900001 (class_id '
        '900101) in school year 2027-2028, in all note categories. Pass '
        'school_year for the notes of another school year.',
      );
      expect(h.lvs.calls, [
        _allCall(
          fakeLvsJan,
          range: 'syRange={"from":"2027-09-01","until":"2028-08-31"}',
        ),
        _janFileCall,
      ]);
    });

    test('school_year: the notes of that school year only', () async {
      final text = await read(jan({'school_year': ' 2029 - 2030 '}));

      expect(
        text,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2029-2030, in all note categories, newest first.\n'
        '- 2030-03-12 | Testcategorie (category_id 900401) | Testnotitie van '
        'vorig schooljaar. | by Peeters Piet\n'
        '  (no field filled in)\n'
        '1 note in total, shown.',
      );
      expect(lvs.calls, [
        _allCall(
          fakeLvsJan,
          range: 'syRange={"from":"2029-09-01","until":"2030-08-31"}',
        ),
      ]);
    });

    test('include_confidential: the confidential note too, marked, and the '
        'answer says it is shown as asked', () async {
      final text = await read(jan({'include_confidential': true}));

      expect(
        text,
        contains(
          '\n$_midnight\n'
          '- 2030-10-08 | Testcategorie (category_id 900401) | Testnotitie '
          'vertrouwelijk. | by Dupré Céline | vertrouwelijk (confidential)\n'
          '  Testveld verslag: Testnotitie, vertrouwelijk.\n'
          '- 2030-10-01 | ',
        ),
      );
      expect(
        text,
        endsWith(
          '\n5 notes in total, all shown.\n'
          '1 of the notes shown is confidential (vertrouwelijk), shown as the '
          'user asked for confidential notes.',
        ),
      );
    });

    test('since: from that Belgian day on, a note at 00:30 there (22:30 UTC '
        'the day before) included; the older ones counted, the confidential '
        'one among them', () async {
      final text = await read(jan({'since': '2030-10-15'}));

      expect(
        text,
        endsWith(
          'newest first.\n'
          '$_talk\n'
          '$_midnight\n'
          'Shown: 2 of the 5 notes. Left out: 3 dated before 2030-10-15 '
          '(since).',
        ),
      );

      final later = await read(jan({'since': '2030-10-16'}));
      expect(later, isNot(contains('(no title)')));
      expect(later, contains('Left out: 4 dated before 2030-10-16 (since).'));
    });

    test('limit: the newest that many, the older ones counted, besides the '
        'confidential one', () async {
      final text = await read(jan({'limit': 2}));

      expect(
        text,
        endsWith(
          'newest first.\n'
          '$_talk\n'
          '$_midnight\n'
          'Shown: 2 of the 5 notes. Left out: $_oneConfidential; 2 older than '
          'those shown, over the limit of 2: pass a higher limit to see them.',
        ),
      );
      final one = await read(jan({'limit': 3.0, 'since': '2030-10-01'}));
      expect(
        one,
        endsWith(
          'Left out: 1 dated before 2030-10-01 (since); $_oneConfidential.',
        ),
      );
      final first = await read(jan({'limit': 1, 'since': '2030-10-15'}));
      expect(
        first,
        endsWith(
          '1 older than those shown, over the limit of 1: pass a higher '
          'limit to see it.',
        ),
      );
    });

    test('a pupil without notes: a sentence, after the file says the pupil '
        'is known', () async {
      final text = await read(fakeLvsPupilArguments(fakeLvsMarie));

      expect(
        text,
        'The LVS holds no notes of the pupil with pupil_id 900002 (class_id '
        '900102) in school year 2030-2031, in all note categories. Pass '
        'school_year for the notes of another school year.',
      );
      expect(lvs.reads, [FakeLvsRead.allNotes, FakeLvsRead.pupilFile]);
    });

    for (final (what, asked) in [
      ('a pupil the LVS does not know', fakeLvsLars),
      (
        'a pupil asked for in another class than theirs',
        (pupilId: fakeLvsJan.pupilId, classId: fakeLvsMarie.classId),
      ),
    ]) {
      test('$what: the "all items" view answers no notes, and the file says '
          'that the LVS does not know the pupil: an error, not "no '
          'notes"', () async {
        final text = await refused(fakeLvsPupilArguments(asked));

        expect(
          text,
          'The LVS knows no pupil with pupil_id ${asked.pupilId} in the class '
          'with class_id ${asked.classId} that this account may see. Take '
          'pupil_id and class_id from the same line of search_lvs_pupils.',
        );
        expect(lvs.reads, [FakeLvsRead.allNotes, FakeLvsRead.pupilFile]);
      });
    }
  });

  group('one category', () {
    test('by its name, ignoring case: the file for its sub-categories, then '
        'the category and each sub-category on its own, but the heading; '
        'every field type shown readably, newest first', () async {
      final text = await read(jan({'category': ' testCATEGORIE '}));

      expect(
        text,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2030-2031, in Testcategorie (category_id 900401) '
        'and its sub-categories, newest first.\n'
        '$_talk\n'
        '$_midnight\n'
        '$_everyField\n'
        '$_deep\n'
        'Shown: 4 of the 5 notes. Left out: $_oneConfidential.',
      );
      for (final part in _confidentialParts) {
        expect(text, isNot(contains(part)));
      }
      expect(text, isNot(contains('Testveld leeg')), reason: 'empty fields');
      expect(lvs.calls, [
        _janFileCall,
        _categoryCall(900401),
        _categoryCall(900402),
        _categoryCall(900404),
      ]);
    });

    test('by its category_id, as a number, as digits or as the tools print '
        'it: a category without sub-categories is read alone', () async {
      for (final category in <Object>[900402, 900402.0, '900402']) {
        lvs.requests.clear();
        final text = await read(jan({'category': category}));

        expect(
          text,
          'The notes of the pupil with pupil_id 900001 (class_id 900101) in '
          'the LVS, school year 2030-2031, in Testsubcategorie (category_id '
          '900402), newest first.\n'
          '$_talk\n'
          '1 note in total, shown.',
          reason: '$category',
        );
        expect(lvs.calls, [_janFileCall, _categoryCall(900402)]);
      }
      final printed = await read(jan({'category': 'category_id 900404'}));
      expect(printed, contains('\n$_deep\n'));
    });

    test('a heading: the notes of its sub-categories, without reading the '
        'heading itself', () async {
      final text = await read(jan({'category': 900403}));

      expect(
        text,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2030-2031, in the sub-categories of the heading '
        'Testsubcategorie (category_id 900403), newest first.\n'
        '$_deep\n'
        '1 note in total, shown.',
      );
      expect(lvs.calls, [_janFileCall, _categoryCall(900404)]);
    });

    test('with include_confidential, school_year, since and limit, as for '
        'all categories', () async {
      final confidential = await read(
        jan({'category': 900401, 'include_confidential': true, 'limit': 3}),
      );
      expect(
        confidential,
        contains('\n$_midnight\n$_confidential\nShown: 3 of the 5 notes.'),
      );

      lvs.requests.clear();
      final earlier = await read(
        jan({'category': 900401, 'school_year': '2029-2030'}),
      );
      expect(
        earlier,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2029-2030, in Testcategorie (category_id 900401) '
        'and its sub-categories, newest first.\n'
        '- 2030-03-12 | Testcategorie (category_id 900401) | Testnotitie van '
        'vorig schooljaar. | by Peeters Piet\n'
        '  Testveld tekst: Testtekst van vorig schooljaar.\n'
        '1 note in total, shown.',
      );
      const range = 'syRange={"from":"2029-09-01","until":"2030-08-31"}';
      expect(lvs.calls, [
        _janFileCall,
        _categoryCall(900401, range: range),
        _categoryCall(900402, range: range),
        _categoryCall(900404, range: range),
      ]);

      final since = await read(
        jan({'category': 900401, 'since': '2030-10-02'}),
      );
      expect(
        since,
        endsWith(
          'newest first.\n$_talk\n$_midnight\n'
          'Shown: 2 of the 5 notes. Left out: 2 dated before 2030-10-02 '
          '(since); $_oneConfidential.',
        ),
      );

      final none = await read(jan({'category': 900402, 'since': '2030-12-01'}));
      expect(
        none,
        'The notes of the pupil with pupil_id 900001 (class_id 900101) in the '
        'LVS, school year 2030-2031, in Testsubcategorie (category_id 900402), '
        'newest first.\n'
        'Shown: 0 of the 1 note. Left out: 1 dated before 2030-12-01 (since).',
      );
    });

    test('a category without notes in the school year: a sentence', () async {
      final text = await read({
        ...fakeLvsPupilArguments(fakeLvsMarie),
        'category': 'Testcategorie',
      });

      expect(
        text,
        'The LVS holds no notes of the pupil with pupil_id 900002 (class_id '
        '900102) in school year 2030-2031, in Testcategorie (category_id '
        '900401). Pass school_year for the notes of another school year.',
      );
    });

    test('a name several categories have: an error that lists them with '
        'their path and id, and no notes are read', () async {
      final text = await refused(jan({'category': 'testsubcategorie'}));

      expect(
        text,
        'Several note categories of this pupil\'s file are named '
        '"testsubcategorie": Testcategorie / Testsubcategorie (category_id '
        '900402), Testcategorie / Testsubcategorie (category_id 900403, a '
        'heading), Testcategorie / Testsubcategorie / Testsubcategorie '
        '(category_id 900404). Pass the one you mean as category, by its '
        'category_id.',
      );
      expect(lvs.calls, [_janFileCall]);
    });

    for (final category in <Object>['Gedrag', 900499]) {
      test('a category the file does not have ($category): an error that '
          'lists the file\'s categories, and no notes are read', () async {
        final text = await refused(jan({'category': category}));

        expect(
          text,
          'This pupil\'s file has no note category "$category". Its note '
          'categories are: Testcategorie (category_id 900401), Testcategorie '
          '/ Testsubcategorie (category_id 900402), Testcategorie / '
          'Testsubcategorie (category_id 900403, a heading), Testcategorie / '
          'Testsubcategorie / Testsubcategorie (category_id 900404). Pass one '
          'of them as category, by its category_id or its name, or leave '
          'category out to read all notes.',
        );
        expect(lvs.calls, [_janFileCall]);
      });
    }

    test('a category of the file the LVS does not know: the library\'s '
        'error, worded', () async {
      lvs.categoryNotes.remove((fakeLvsJan.pupilId, 900404));

      final text = await refused(jan({'category': 900404}));

      expect(
        text,
        'The LVS knows no note category with category_id 900404 in this '
        "pupil's file. Take it from the parts of the file that read_lvs_pupil "
        'lists.',
      );
    });

    test('a pupil the LVS does not know: the file says so, and no notes are '
        'read', () async {
      final text = await refused({
        ...fakeLvsPupilArguments(fakeLvsLars),
        'category': 900401,
      });

      expect(text, startsWith('The LVS knows no pupil with pupil_id 900005'));
      expect(lvs.reads, [FakeLvsRead.pupilFile]);
    });
  });

  group('arguments that cannot be read: an error that says what to pass, '
      'before logging in', () {
    for (final (arguments, error) in <(Map<String, Object?>, String)>[
      ({'school_year': '2030'}, 'school_year must be a school year like'),
      ({'school_year': '2030-2032'}, 'school_year must be a school year like'),
      // Not a text: refused by the schema.
      ({'school_year': 2030}, 'school_year'),
      ({'since': '15/10/2030'}, 'since must be a date like'),
      ({'since': '2030-02-30'}, 'since must be a date like'),
      ({'limit': 0}, 'limit'),
      ({'limit': 101}, 'limit'),
      ({'limit': 2.5}, 'limit'),
      ({'category': 2.5}, 'category'),
      ({'class_id': null}, 'class_id'),
      ({'pupil_id': 0}, 'pupil_id'),
    ]) {
      test('$arguments', () async {
        final text = await refused(
          jan(arguments)..removeWhere((_, v) => v == null),
        );

        expect(text, contains(error));
        expect(h.server.requests, isEmpty);
      });
    }

    test('an empty category or school year counts as none', () async {
      final text = await read(jan({'category': '  ', 'school_year': ''}));

      expect(text, contains('school year 2030-2031, in all note categories'));
      expect(lvs.reads, [FakeLvsRead.allNotes]);
    });
  });

  group('a refusal or an answer the server cannot read: an error that says '
      'what to do, and quotes nothing of the answer', () {
    for (final (refusal, reads, arguments) in [
      (FakeLvsRefusal.forbidden, {FakeLvsRead.allNotes}, jan()),
      (FakeLvsRefusal.startPage, {FakeLvsRead.allNotes}, jan()),
      (
        FakeLvsRefusal.startPage,
        {FakeLvsRead.categoryNotes},
        jan({'category': 900401}),
      ),
    ]) {
      test('refused (${refusal.name}, ${reads.single.name})', () async {
        lvs
          ..refusal = refusal
          ..refusedReads = reads;

        final text = await refused(arguments);

        expect(text, startsWith(_refused));
        expect(text, isNot(contains(fakeLvsNoAccessName)));
      });
    }

    test('an HTML page instead of the notes: could not read', () async {
      lvs
        ..refusal = FakeLvsRefusal.htmlPage
        ..refusedReads = {FakeLvsRead.categoryNotes};

      final text = await refused(jan({'category': 900402}));

      expect(text, startsWith('$_unreadable. Try again in a moment.'));
      expect(text, isNot(contains('Oeps')));
    });
  });

  group('privacy', () {
    test('only the reads of the library are sent, each one command of the '
        'dispatcher: no "viewed" flag, no PUT, nothing marked as '
        'seen', () async {
      await read(jan());
      await read(jan({'category': 900401, 'include_confidential': true}));
      await read(fakeLvsPupilArguments(fakeLvsMarie));

      expect(lvs.reads, [
        FakeLvsRead.allNotes,
        FakeLvsRead.pupilFile,
        FakeLvsRead.categoryNotes,
        FakeLvsRead.categoryNotes,
        FakeLvsRead.categoryNotes,
        FakeLvsRead.allNotes,
        FakeLvsRead.pupilFile,
      ]);
      expect({for (final r in lvs.requests) r.method}, {'GET', 'POST'});
      expect(
        {
          for (final r in lvs.requests)
            if (r.command case final command?)
              '${command.subsystem}/${command.action}',
        },
        {'lvs_pupils/getUserData', 'lvs_cats/getUserCatItems'},
      );
    });

    test('nothing is kept on disk: the cache folder holds the same files '
        'before and after, none with a note\'s text', () async {
      // The first call logs in, which saves the session there.
      await read(jan());
      final before = h.cacheFiles();

      await read(jan({'category': 900401, 'include_confidential': true}));
      await read(jan({'school_year': '2029-2030'}));

      expect(h.cacheFiles(), before);
      for (final path in h.cacheFiles()) {
        final content = File(path).readAsStringSync().toLowerCase();
        for (final word in ['testnotitie', 'testveld', 'janssens', 'jacobs']) {
          expect(content, isNot(contains(word)), reason: path);
        }
      }
    });

    test(
      'the log of a call that succeeds holds nothing of the notes',
      () async {
        final (_, all, allLog) = await h.logged(
          'read_lvs_notes',
          jan({'include_confidential': true}),
        );
        final (_, one, oneLog) = await h.logged(
          'read_lvs_notes',
          jan({'category': 'Testcategorie'}),
        );

        expect(all, contains('Testnotitie vertrouwelijk.'));
        expect(one, contains('Testveld'));
        // The log is captured: the login shows in it.
        expect(allLog, contains('Smartschool: checking the session'));
        for (final log in [allLog.toLowerCase(), oneLog.toLowerCase()]) {
          for (final word in [
            'testnotitie',
            'testveld',
            'testgesprek',
            'testcategorie',
            'jacobs',
            'dupré',
            'peeters',
          ]) {
            expect(log, isNot(contains(word)));
          }
        }
      },
    );

    test('a session Smartschool refuses during the notes: the log names the '
        "error's type, not the request, which holds the pupil's id", () async {
      await read(jan());
      h.server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      final (isError, text, log) = await h.logged(
        'read_lvs_notes',
        jan({'category': 900402}),
      );

      expect(isError, isNot(true), reason: text);
      expect(
        log,
        contains(
          'Smartschool did not accept the session '
          '(SmartschoolSessionExpiredError); trying once more',
        ),
      );
      expect(log, isNot(contains('${fakeLvsJan.pupilId}')));
      expect(log, isNot(contains('900402')));
      expect(log, isNot(contains('dispatcher')));
    });

    test('an error whose message holds a name: the log has its type and '
        'HTTP status only, the result neither', () async {
      lvs.failure = const SmartschoolLvsError(
        'Testfout over Janssens Jan.',
        statusCode: 500,
      );

      final (isError, text, log) = await h.logged('read_lvs_notes', jan());

      expect(isError, isTrue);
      expect(text, startsWith('$_unreadable (HTTP 500).'));
      expect(log, contains('lvs: SmartschoolLvsError (HTTP 500)\n'));
      for (final shown in [text, log]) {
        expect(shown, isNot(contains('Janssens')));
        expect(shown, isNot(contains('Testfout')));
      }
    });
  });

  group('the parts, worded', () {
    LvsNoteField field(
      LvsNoteFieldType type, {
      String label = 'Testveld',
      String value = '',
      DateTime? date,
      List<LvsAttachment> attachments = const [],
    }) => LvsNoteField(
      paramId: 900601,
      typeCode: type.code,
      type: type,
      label: label,
      value: value,
      date: date,
      attachments: attachments,
      rawValue: '',
      rawOptionValue: '',
    );

    LvsNote note(int id, DateTime date, {bool confidential = false}) => LvsNote(
      id: id,
      categoryId: 900401,
      categoryName: 'Testcategorie',
      title: 'Testnotitie.',
      date: date,
      author: 'Peeters Piet',
      isConfidential: confidential,
      isNew: false,
      viewed: false,
      schoolYear: '2030-2031',
      fields: const [],
    );

    test('a field: nothing when it holds nothing; the label when it has '
        'none; a heading without text left out', () {
      expect(formatLvsNoteField(field(LvsNoteFieldType.text)), isEmpty);
      expect(formatLvsNoteField(field(LvsNoteFieldType.unknown)), isEmpty);
      expect(formatLvsNoteField(field(LvsNoteFieldType.attachment)), isEmpty);
      expect(
        formatLvsNoteField(field(LvsNoteFieldType.heading, label: ' ')),
        isEmpty,
      );
      expect(
        formatLvsNoteField(
          field(LvsNoteFieldType.radio, label: '', value: 'Testoptie'),
        ),
        ['  (no label): Testoptie'],
      );
      expect(
        formatLvsNoteField(
          field(
            LvsNoteFieldType.date,
            value: '2030-10-23',
            date: DateTime.utc(2030, 10, 22, 22),
          ),
        ),
        ['  Testveld: 2030-10-23'],
      );
      expect(
        formatLvsNoteField(
          field(LvsNoteFieldType.text, value: 'Testregel een.\n\nTestregel.'),
        ),
        ['  Testveld:', '    Testregel een.', '    Testregel.'],
      );
    });

    test("a note on its Belgian day, the library's (lvsDayOf), also across "
        'summer time and the year: in its line, and for since', () {
      for (final (instant, day) in [
        (DateTime.utc(2030, 3, 31, 0, 30), '2030-03-31'), // 01:30 CET
        (DateTime.utc(2030, 3, 31, 22, 30), '2030-04-01'), // 00:30 CEST
        (DateTime.utc(2030, 10, 26, 22, 30), '2030-10-27'), // 00:30 CEST
        (DateTime.utc(2030, 10, 27, 22, 30), '2030-10-27'), // 23:30 CET
        (DateTime.utc(2030, 12, 31, 23, 30), '2031-01-01'), // 00:30 CET
        (DateTime.utc(2030, 6, 30, 21, 59), '2030-06-30'), // 23:59 CEST
        (DateTime(2030, 6, 30, 12), '2030-06-30'), // local time, noon
      ]) {
        final dated = note(900301, instant);
        expect(
          formatLvsNote(dated),
          startsWith('- $day | '),
          reason: '$instant',
        );
        expect(
          selectLvsNotes(
            [dated],
            since: day,
            includeConfidential: false,
            limit: 1,
          ).shown,
          [dated],
          reason: '$instant',
        );
      }
    });

    test('a school year by its label, another range of days by its days', () {
      expect(formatLvsSchoolYear(LvsSchoolYear.starting(2030)), '2030-2031');
      expect(
        formatLvsSchoolYear(
          LvsSchoolYear(
            from: DateTime.utc(2030, 9),
            until: DateTime.utc(2030, 12, 31),
          ),
        ),
        '2030-09-01 to 2030-12-31',
      );
    });

    test('school_year: a label, with spaces around the dash; the current one '
        'in Belgian time when absent', () {
      expect(
        lvsSchoolYearArgument({'school_year': '2031 - 2032'}, now: _now),
        LvsSchoolYear.starting(2031),
      );
      expect(
        lvsSchoolYearArgument({}, now: _now),
        LvsSchoolYear.starting(2030),
      );
      expect(
        lvsSchoolYearArgument({}, now: DateTime.utc(2031, 8, 31, 22, 30)),
        LvsSchoolYear.starting(2031),
        reason: '00:30 on 1 September in Belgium',
      );
      expect(
        () => lvsSchoolYearArgument({'school_year': 'volgend jaar'}, now: _now),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            'school_year must be a school year like 2025-2026: two years, the '
                'second the one after the first; "volgend jaar" is not. Leave '
                'it out for the current school year.',
          ),
        ),
      );
    });

    test('the choice of notes: a confidential note before since counts as '
        'older; notes of the same moment keep their order', () {
      final notes = [
        note(900301, DateTime.utc(2030, 10, 1)),
        note(900302, DateTime.utc(2030, 9, 20), confidential: true),
        note(900303, DateTime.utc(2030, 10, 1)),
        note(900304, DateTime.utc(2030, 11, 5)),
      ];

      final selection = selectLvsNotes(
        notes,
        since: '2030-09-25',
        includeConfidential: false,
        limit: 2,
      );

      expect([for (final n in selection.shown) n.id], [900304, 900301]);
      expect(selection.total, 4);
      expect(selection.older, 1);
      expect(selection.confidential, 0);
      expect(selection.overLimit, 1);
    });
  });
}
