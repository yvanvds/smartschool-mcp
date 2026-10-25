/// `search_lvs_pupils` and `read_lvs_pupil` (#153), called over MCP on the
/// real server, session and library (`LvsService`), against a fake
/// Smartschool whose pupil tracking system (LVS) answers with the
/// hand-written fixtures of `test/fixtures/lvs/` (`test/support/fake_lvs.dart`,
/// the fakes of `FAKES.md` only, checked by
/// `test/lvs_fixtures_guard_test.dart`); and the privacy rules every LVS
/// tool follows: only reads, nothing on disk, nothing of an answer or an
/// error's message in the log.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/lvs/lvs_access.dart';
import 'package:smartschool_mcp/src/lvs/lvs_format.dart';
import 'package:smartschool_mcp/src/lvs/lvs_opt_in.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/log_capture.dart';
import 'support/mcp.dart';

/// What the tools say to an account without access, at the end.
const _fix =
    "ask the school's Smartschool administrator for access to the LVS, or "
    'turn off "Leerlingvolgsysteem" (SMARTSCHOOL_LVS) in the Smartschool '
    'extension settings in Claude Desktop (Settings → Extensions), then '
    'restart Claude Desktop';

const _refused =
    "Smartschool's pupil tracking system (LVS) refused this read to the "
    'account: it may have no access to the LVS, or may not see this pupil. '
    'smartschool_status says whether the account can read the LVS. Without '
    'access, $_fix.';

const _unreadable =
    "Smartschool's pupil tracking system (LVS) answered with something the "
    'server could not read';

/// What the overview of Jan Janssens's file says
/// (`spotlight/pupil_file.json`, `status/both.json`).
const _janFile =
    "Janssens Jan, class 1A (Testrichting): the overview of the pupil's "
    'file in the LVS (pupil_id 900001, class_id 900101).\n'
    'Form tutors (titularissen): Peeters Piet, Dupré Céline.\n'
    "Today's attendance: morning: Testcode (TA); afternoon: Testcode (TB).\n"
    "The parts of the file that hold something, in the LVS's order (5). "
    'What they hold is not shown here.\n'
    '- Testcategorie: note category (category_id 900401), with new notes, '
    'read it with read_lvs_notes\n'
    '  - Testsubcategorie: note category (category_id 900402), with new '
    'notes, read it with read_lvs_notes\n'
    '  - Testsubcategorie: heading of note categories (category_id 900403), '
    'read it with read_lvs_notes\n'
    '    - Testsubcategorie: note category (category_id 900404), read it with '
    'read_lvs_notes\n'
    '- Testsectie: results\n'
    'Parts that hold nothing for this pupil: Testsectie (support plans), '
    'Testsectie (a part of type "testsection").';

void main() {
  late FakeSmartschool server;
  late FakeLvs lvs;
  late Directory cache;
  late SmartschoolSession session;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    lvs = server.lvs;
    cache = await tempCache();
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cache),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: lvsOptIn(session, SwitchState.on).offered,
    );
  });

  Future<String> ok(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, [Map<String, Object?>? arguments]) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  Map<String, Object?> pupil(FakeLvsPupil pupil) => {
    'pupil_id': pupil.pupilId,
    'class_id': pupil.classId,
  };

  group('the switch "Leerlingvolgsysteem"', () {
    test('off or unclear: no LVS tool is offered', () {
      final session = SmartschoolSession(fakeExtensionSettings());
      for (final state in [SwitchState.off, SwitchState.unclear]) {
        final optIn = lvsOptIn(session, state);
        expect(optIn.setting, Setting.lvs);
        expect(optIn.offered, isEmpty, reason: state.name);
        expect(optIn.tools, hasLength(3));
      }
    });

    test('is a choice about pupils\' data, not about rights: its caution '
        'says what turning it on means, and links the privacy section of '
        'the guide', () {
      final optIn = lvsOptIn(
        SmartschoolSession(fakeExtensionSettings()),
        SwitchState.off,
      );
      expect(optIn.rights, contains('as most teachers have'));
      expect(
        optIn.caution,
        allOf(
          contains('the most sensitive data in Smartschool'),
          contains('turn it on only when the user, and their school, choose'),
          endsWith('docs/installatie.md#8-veiligheid-en-privacy'),
        ),
      );
    });
  });

  group('the tools are listed', () {
    late Map<String, Tool> tools;

    setUp(() async {
      tools = {
        for (final tool in (await connection.listTools(
          ListToolsRequest(),
        )).tools)
          tool.name: tool,
      };
    });

    test('finding a pupil first, then their file, then the parts of it (the '
        'notes, #154); all read-only', () {
      expect(tools.keys, [
        'search_lvs_pupils',
        'read_lvs_pupil',
        'read_lvs_notes',
      ]);
      for (final tool in tools.values) {
        final annotations = tool.toolAnnotations!;
        expect(annotations.readOnlyHint, isTrue, reason: tool.name);
        expect(annotations.idempotentHint, isTrue, reason: tool.name);
        expect(annotations.destructiveHint, isNot(true), reason: tool.name);
      }
      expect(
        tools['search_lvs_pupils']!.description,
        endsWith('Searching changes nothing.'),
      );
      expect(
        tools['read_lvs_pupil']!.description,
        endsWith('Reading changes nothing.'),
      );
    });

    test('each says the data is confidential, to use it only when the user '
        'asks about a pupil, and not to copy what it returns elsewhere', () {
      expect(
        lvsPrivacyRules,
        allOf(
          contains('confidential'),
          contains('only when the user asks about a particular pupil'),
          contains(
            'do not copy what it returns into files, artifacts, messages or '
            'other tools unless the user asks for it',
          ),
        ),
      );
      for (final tool in tools.values) {
        expect(tool.description, contains(lvsPrivacyRules), reason: tool.name);
      }
    });

    test('the search asks Claude to let the user choose among several '
        'pupils, never to pick one', () {
      expect(
        tools['search_lvs_pupils']!.description,
        contains(
          'When several pupils match, ask the user which one they mean (by '
          'name and class): never pick one yourself.',
        ),
      );
    });

    test('the search takes part of a name; the file takes pupil_id and '
        'class_id, whole numbers from 1', () {
      final search = tools['search_lvs_pupils']!.inputSchema;
      expect(search.required, ['query']);
      expect(search.properties!.keys, ['query']);
      expect(search.properties!['query'], {
        'type': 'string',
        'description': isA<String>(),
        'minLength': 1,
      });
      final read = tools['read_lvs_pupil']!.inputSchema;
      expect(read.required, ['pupil_id', 'class_id']);
      expect(read.properties!.keys, ['pupil_id', 'class_id']);
      for (final name in ['pupil_id', 'class_id']) {
        expect(read.properties![name], {
          'type': 'integer',
          'description': contains('search_lvs_pupils'),
          'minimum': 1,
        }, reason: name);
      }
    });
  });

  group('search_lvs_pupils', () {
    test('one match: the pupil with class and ids, with what to call '
        'next', () async {
      final text = await ok('search_lvs_pupils', {'query': ' janssens '});

      expect(
        text,
        'The pupil tracking system (LVS) finds 1 pupil whose name matches '
        '"janssens". Pass its pupil_id and class_id to read_lvs_pupil.\n'
        '- Janssens Jan | class 1A | pupil_id 900001 | class_id 900101',
      );
      expect(lvs.calls, ['GET /LVS/Spotlight?searchVal=janssens']);
      expect(lvs.reads, [FakeLvsRead.search]);
    });

    test('several matches: each one, in the LVS\'s order, without the '
        'markup that highlights the match, and Claude is to ask the user '
        'which one', () async {
      final text = await ok('search_lvs_pupils', {'query': 'Peeters'});

      expect(
        text,
        'The pupil tracking system (LVS) finds 2 pupils whose name matches '
        '"Peeters", in its order. Several pupils match: ask the user which one '
        'they mean, by name and class, before reading a file. Do not pick one '
        'yourself.\n'
        '- Peeters Marie | class 2B | pupil_id 900002 | class_id 900102\n'
        '- Peeters Lars | class 3C | pupil_id 900005 | class_id 900103',
      );
      expect(text, isNot(contains('<')));
    });

    test('no match: a sentence, not an error', () async {
      final text = await ok('search_lvs_pupils', {'query': 'Wouters'});

      expect(
        text,
        'The pupil tracking system (LVS) finds no pupil whose name matches '
        '"Wouters" among the pupils this account may see. Check the '
        'spelling, or search for part of the name, such as the last name.',
      );
    });

    test('a blank query: an error, before logging in', () async {
      final text = await error('search_lvs_pupils', {'query': '   '});

      expect(text, startsWith('query is empty'));
      expect(server.requests, isEmpty);
    });
  });

  group('read_lvs_pupil', () {
    test('the overview of the file: who, the class, the form tutors, '
        'today, and the parts that hold something, indented by depth, with '
        'their category ids and what is new, then those that hold '
        'nothing', () async {
      final text = await ok('read_lvs_pupil', pupil(fakeLvsJan));

      expect(text, _janFile);
      expect(lvs.calls, [
        'GET /LVS/Spotlight/900001?classID=900101',
        'POST /LVS/Pupilxhr/getStatusInfo pupilID=900001',
      ]);
      expect(lvs.reads, [FakeLvsRead.pupilFile, FakeLvsRead.todayStatus]);
    });

    test('a file without form tutors, with the morning only, and whose '
        'support plans and absences hold something but not its note '
        'category', () async {
      final text = await ok('read_lvs_pupil', pupil(fakeLvsMarie));

      expect(
        text,
        "Peeters Marie, class 2B: the overview of the pupil's file in the "
        'LVS (pupil_id 900002, class_id 900102).\n'
        'Form tutors (titularissen): none given.\n'
        "Today's attendance: morning: Testcode (TA).\n"
        "The parts of the file that hold something, in the LVS's order (2). "
        'What they hold is not shown here.\n'
        '- Testsectie: support plans\n'
        '- Testsectie: absences, with something new\n'
        'Parts that hold nothing for this pupil: Testcategorie (note '
        'category), Testsectie (reports in Skore).',
      );
    });

    test('today without a code: nothing registered', () async {
      lvs.statuses.remove(fakeLvsJan.pupilId);

      final text = await ok('read_lvs_pupil', pupil(fakeLvsJan));

      expect(
        text,
        contains(
          "\nToday's attendance: nothing registered (no school today, or "
          'nothing registered yet).\n',
        ),
      );
    });

    test('takes ids written with a decimal part', () async {
      final text = await ok('read_lvs_pupil', {
        'pupil_id': 900001.0,
        'class_id': 900101.0,
      });

      expect(text, _janFile);
    });

    for (final (what, asked) in [
      ('a pupil the LVS does not know', fakeLvsLars),
      (
        'a pupil asked for in another class than theirs',
        (pupilId: fakeLvsJan.pupilId, classId: fakeLvsMarie.classId),
      ),
    ]) {
      test('$what: the LVS\'s placeholder pupil is an error that says to '
          'take both ids from one line of the search, and today is not '
          'read', () async {
        final text = await error('read_lvs_pupil', pupil(asked));

        expect(
          text,
          'The LVS knows no pupil with pupil_id ${asked.pupilId} in the class '
          'with class_id ${asked.classId} that this account may see. Take '
          'pupil_id and class_id from the same line of search_lvs_pupils.',
        );
        expect(text, isNot(contains('Niet beschikbaar')));
        expect(lvs.reads, [FakeLvsRead.pupilFile]);
      });
    }

    test('an id that is missing: an error, before logging in', () async {
      final text = await error('read_lvs_pupil', {'pupil_id': 900001});

      expect(text, contains('class_id'));
      expect(server.requests, isEmpty);
    });
  });

  group('a refusal or an answer the server cannot read: an error that says '
      'what to do, and quotes nothing of the answer', () {
    for (final (refusal, reads) in [
      (FakeLvsRefusal.forbidden, null),
      (FakeLvsRefusal.startPage, {FakeLvsRead.pupilFile}),
      (FakeLvsRefusal.startPage, {FakeLvsRead.todayStatus}),
    ]) {
      final which = reads == null ? 'every read' : reads.single.name;
      test('refused (${refusal.name}, $which): perhaps no access, or not '
          'this pupil', () async {
        lvs
          ..refusal = refusal
          ..refusedReads = reads;

        final search = reads == null
            ? await error('search_lvs_pupils', {'query': 'janssens'})
            : null;
        final read = await error('read_lvs_pupil', pupil(fakeLvsJan));

        for (final text in [?search, read]) {
          expect(text, _refused);
          expect(text, isNot(contains(fakeLvsNoAccessName)));
          expect(text, isNot(contains('Geen toegang')));
        }
      });
    }

    test('HTTP 500 with an error page: could not read, with the status, try '
        'again', () async {
      lvs.refusal = FakeLvsRefusal.serverError;

      final text = await error('read_lvs_pupil', pupil(fakeLvsJan));

      expect(
        text,
        '$_unreadable (HTTP 500). Try again in a moment. If it keeps failing, '
        'the server log names the type of the error, and nothing of what the '
        'LVS answered.',
      );
      expect(text, isNot(contains('Oeps')));
    });

    test('an HTML page instead of data: could not read', () async {
      lvs.refusal = FakeLvsRefusal.htmlPage;

      final text = await error('search_lvs_pupils', {'query': 'janssens'});

      expect(text, startsWith('$_unreadable. Try again in a moment.'));
    });
  });

  group('privacy', () {
    test('only the reads of the library are sent: no PUT, no "last pupil '
        'viewed", nothing marked as seen', () async {
      await ok('search_lvs_pupils', {'query': 'peeters'});
      await ok('read_lvs_pupil', pupil(fakeLvsMarie));
      await ok('search_lvs_pupils', {'query': 'janssens'});
      await ok('read_lvs_pupil', pupil(fakeLvsJan));
      await error('read_lvs_pupil', pupil(fakeLvsLars));

      expect(lvs.reads, [
        FakeLvsRead.search,
        FakeLvsRead.pupilFile,
        FakeLvsRead.todayStatus,
        FakeLvsRead.search,
        FakeLvsRead.pupilFile,
        FakeLvsRead.todayStatus,
        FakeLvsRead.pupilFile,
      ]);
      expect({for (final r in lvs.requests) r.method}, {'GET', 'POST'});
    });

    test('nothing is kept on disk: the cache folder holds the same files '
        'before and after, none with a pupil\'s name', () async {
      // The first call logs in, which saves the session there.
      await ok('search_lvs_pupils', {'query': 'janssens'});
      List<String> files() => [
        for (final file in cache.listSync(recursive: true))
          if (file is File) file.path,
      ]..sort();
      final before = files();

      await ok('read_lvs_pupil', pupil(fakeLvsJan));
      await ok('search_lvs_pupils', {'query': 'peeters'});
      await ok('read_lvs_pupil', pupil(fakeLvsMarie));

      expect(files(), before);
      for (final path in files()) {
        final content = File(path).readAsStringSync().toLowerCase();
        for (final word in ['janssens', 'peeters', 'testcategorie']) {
          expect(content, isNot(contains(word)), reason: path);
        }
      }
    });

    /// Calls [tool] with [arguments] on a server connected with the log
    /// captured, over the same session; returns its result, its text and
    /// the log.
    Future<(bool?, String, String)> logged(
      String tool,
      Map<String, Object?> arguments,
    ) async {
      final ((result, text), log) = await captureLog(() async {
        final (connection, _) = await connect(
          tools: lvsOptIn(session, SwitchState.on).offered,
        );
        return callTool(connection, tool, arguments);
      });
      return (result.isError, text, log);
    }

    test('the log of a call that succeeds holds no answer and no search '
        'text', () async {
      final (_, _, search) = await logged('search_lvs_pupils', {
        'query': 'Peeters',
      });
      final (_, _, read) = await logged('read_lvs_pupil', pupil(fakeLvsJan));

      // The log is captured: the login shows in it.
      expect(search, contains('Smartschool: checking the session'));
      for (final log in [search.toLowerCase(), read.toLowerCase()]) {
        for (final word in ['peeters', 'janssens', 'testcategorie', '1a']) {
          expect(log, isNot(contains(word)));
        }
      }
    });

    test('a session Smartschool refuses during a read: the log names the '
        "error's type, not the request, which holds the pupil's id", () async {
      await ok('search_lvs_pupils', {'query': 'janssens'});
      server
        ..expireSession()
        ..rejectsAfterLogin = 1;

      final (isError, text, log) = await logged(
        'read_lvs_pupil',
        pupil(fakeLvsJan),
      );

      // The library logged in again, the retry was refused, and the read
      // ran once more.
      expect(isError, isNot(true), reason: text);
      expect(server.logins, 2);
      expect(
        log,
        contains(
          'Smartschool did not accept the session '
          '(SmartschoolSessionExpiredError); trying once more',
        ),
      );
      expect(log, isNot(contains('${fakeLvsJan.pupilId}')));
      expect(log, isNot(contains('${fakeLvsJan.classId}')));
      expect(log, isNot(contains('/LVS/')));

      // Refused for good: the problem is logged by type too.
      server
        ..expireSession()
        ..rejectsAfterLogin = 3;
      final (failed, problem, failedLog) = await logged(
        'read_lvs_pupil',
        pupil(fakeLvsJan),
      );
      expect(failed, isTrue, reason: problem);
      expect(
        failedLog,
        contains(
          'Smartschool problem (sessionRejected): '
          'SmartschoolSessionExpiredError',
        ),
      );
      expect(failedLog, isNot(contains('${fakeLvsJan.pupilId}')));
      expect(failedLog, isNot(contains('/LVS/')));
    });

    test('an LVS error whose message holds a name: the log has its type '
        'and HTTP status only, the result neither', () async {
      lvs.failure = const SmartschoolLvsError(
        'Testfout over Janssens Jan.',
        statusCode: 500,
      );

      final (isError, text, log) = await logged(
        'read_lvs_pupil',
        pupil(fakeLvsJan),
      );

      expect(isError, isTrue);
      expect(text, startsWith('$_unreadable (HTTP 500).'));
      expect(log, contains('lvs: SmartschoolLvsError (HTTP 500)\n'));
      for (final shown in [text, log]) {
        expect(shown, isNot(contains('Janssens')));
        expect(shown, isNot(contains('Testfout')));
      }
    });

    test('another error whose message holds a name: the log has its type '
        'and the code\'s lines only, the result says it failed', () async {
      lvs.failure = const FormatException('Testfout over Janssens Jan.');

      final (isError, text, log) = await logged('search_lvs_pupils', {
        'query': 'Janssens',
      });

      expect(isError, isTrue);
      expect(
        text,
        'The tool search_lvs_pupils failed with an unexpected error. The '
        'server log names its type, and nothing of what the LVS answered.',
      );
      expect(log, contains('tool search_lvs_pupils failed: DioException\n'));
      expect(log, contains('#0 '), reason: 'the stack trace');
      for (final shown in [text, log]) {
        expect(shown, isNot(contains('Janssens')));
        expect(shown, isNot(contains('Testfout')));
      }
    });
  });

  group('the errors of LvsService, worded', () {
    final source = fakeExtensionSettings();

    String worded(SmartschoolLvsError error) =>
        lvsToolError(error, source).message;

    test('a refusal, a pupil or category the LVS does not know, a request '
        'the library refused to send, and any other: without the library\'s '
        'message', () {
      const message = 'Testfout over Janssens Jan.';
      expect(
        worded(const SmartschoolLvsAccessDeniedError(message, statusCode: 403)),
        _refused,
      );
      expect(
        worded(
          const SmartschoolLvsPupilNotFoundError(
            message,
            pupilId: 900009,
            classId: 900109,
          ),
        ),
        startsWith(
          'The LVS knows no pupil with pupil_id 900009 in the class '
          'with class_id 900109',
        ),
      );
      expect(
        worded(
          const SmartschoolLvsCategoryNotFoundError(
            message,
            pupilId: 900001,
            classId: 900101,
            categoryId: 900499,
          ),
        ),
        'The LVS knows no note category with category_id 900499 in this '
        "pupil's file. Take it from the parts of the file that read_lvs_pupil "
        'lists.',
      );
      expect(
        worded(
          const SmartschoolLvsRequestNotAllowedError(
            message,
            method: 'PUT',
            path: '/LVS/Message',
          ),
        ),
        allOf(
          contains('a bug of the library'),
          contains('Nothing was sent, so nothing changed.'),
        ),
      );
      expect(
        worded(const SmartschoolLvsError(message, statusCode: 200)),
        startsWith('$_unreadable. Try again'),
      );
      expect(
        worded(const SmartschoolLvsError(message)),
        startsWith('$_unreadable. Try again'),
      );
    });

    test('for the log: the type, and the HTTP status when there is one', () {
      expect(
        lvsLogDescription(
          const SmartschoolLvsAccessDeniedError('x', statusCode: 403),
        ),
        'SmartschoolLvsAccessDeniedError (HTTP 403)',
      );
      expect(
        lvsLogDescription(const SmartschoolLvsError('x')),
        'SmartschoolLvsError',
      );
      final request = RequestOptions(path: '/LVS/Spotlight');
      expect(
        lvsLogDescription(
          DioException(
            requestOptions: request,
            response: Response<Object?>(
              requestOptions: request,
              statusCode: 502,
            ),
            message: 'Janssens',
          ),
        ),
        'DioException (HTTP 502)',
      );
      expect(lvsLogDescription(StateError('Janssens')), 'StateError');
    });

    test('lvsTool passes a ToolError on as it is', () async {
      final (connection, _) = await connect(
        tools: [
          lvsTool(
            definition: Tool(name: 'lvs_test', inputSchema: Schema.object()),
            handler: (_) => throw const ToolError('Testfout.'),
          ),
        ],
      );

      final (result, text) = await callTool(connection, 'lvs_test');

      expect(result.isError, isTrue);
      expect(text, 'Testfout.');
    });
  });

  group('the overview, worded', () {
    LvsSection section(
      int id,
      String type, {
      bool hasItems = true,
      List<LvsSection> children = const [],
    }) => LvsSection(
      id: id,
      type: type,
      name: 'Testsectie',
      hasItems: hasItems,
      hasNewItems: false,
      children: children,
    );

    LvsPupilFile file(List<LvsSection> sections, [LvsTodayStatus? today]) =>
        LvsPupilFile(
          pupilId: 900001,
          classId: 900101,
          name: 'Janssens Jan',
          className: '1A',
          classDescription: '',
          teachers: const [LvsTeacher(id: 900201, name: 'Peeters Piet')],
          sections: sections,
          todayStatus: today ?? LvsTodayStatus.none,
        );

    test('names the tool that reads a part, once there is one: the notes '
        '(#154; the other parts follow in #155 to #157)', () {
      expect(lvsSectionReaders, {LvsSectionType.items: 'read_lvs_notes'});
      final text = formatLvsPupilFile(
        file([
          section(900401, LvsSectionType.items),
          section(0, LvsSectionType.absences),
        ]),
        readers: const {LvsSectionType.items: 'read_lvs_test'},
      );

      expect(
        text,
        endsWith(
          '\n- Testsectie: note category (category_id 900401), read it with '
          'read_lvs_test\n'
          '- Testsectie: absences',
        ),
      );
    });

    test('a file with nothing in it, and a heading whose parts hold '
        'nothing', () {
      final text = formatLvsPupilFile(
        file([
          section(
            900401,
            LvsSectionType.items,
            hasItems: false,
            children: [section(900402, LvsSectionType.items, hasItems: false)],
          ),
        ]),
      );

      expect(
        text,
        endsWith(
          '\nNo part of the file holds anything for this pupil.\n'
          'Parts that hold nothing for this pupil: Testsectie (note '
          'category), Testsectie (note category).',
        ),
      );
    });

    test('a half-day the LVS names otherwise than am or pm is kept as it '
        'comes (three were seen on a school day, yvanvds/dartschool#168)', () {
      expect(
        formatLvsToday(
          const LvsTodayStatus([
            LvsHalfDayStatus(partOfDay: 'am', code: 'TA', name: 'Testcode'),
            LvsHalfDayStatus(partOfDay: 'pm', code: 'TB', name: ''),
            LvsHalfDayStatus(partOfDay: 'xx', code: 'TC', name: 'Testcode'),
          ]),
        ),
        "Today's attendance: morning: Testcode (TA); afternoon: TB; part of "
        'the day "xx": Testcode (TC).',
      );
    });
  });
}
