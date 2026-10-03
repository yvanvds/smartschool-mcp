/// `add_skore_teacher` and `replace_skore_teacher` (#43), called over MCP on
/// the real server, session and library, against a fake Smartschool whose
/// Skore carries out the save of an assignment (`saveOwner`) as the live
/// Skore did in dartschool#71 (`test/support/fake_skore.dart`).
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_access.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _page = 'GET $fakeSkoreOwnersPagePath';
String _rpc(String method) => 'POST $fakeSkoreOwnersRpcPath $method';

/// What a write says after a check refused the change.
String _refused(String reason) =>
    'Skore refused the change before saving it: $reason Read the class '
    'again with list_skore_courses (and the teachers with '
    'list_skore_teachers) to correct the call. Nothing was changed in Skore.';

/// What the tools say to an account without the rights, after the reason.
const _rightsAndFix =
    'the rights for score management in Skore (Rapporten > Modellen and '
    'Puntenboeken), as a Skore administrator has';
const _fix =
    "ask the school's Smartschool administrator for them, or turn off "
    '"Skore-beheer" (SMARTSCHOOL_SKORE) in the Smartschool extension '
    'settings in Claude Desktop (Settings → Extensions), then restart Claude '
    'Desktop';

void main() {
  late FakeSmartschool server;
  late FakeSkore skore;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    skore = server.skore..loadSchool();
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: skoreOptIn(session, SwitchState.on).offered,
    );
  });

  tearDown(() {
    // Never deleteOwner, explodeMyGroups or any other method.
    expect([
      for (final request in skore.requests) ?request.rpc,
    ], everyElement(isIn(fakeSkoreOwnersRpcMethods)));
  });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  Future<String> add(int classId, int courseId, int teacherId) => callTool(
    connection,
    'add_skore_teacher',
    {'class_id': classId, 'course_id': courseId, 'teacher_id': teacherId},
  ).then((call) => call.$2);

  Future<String> replace(
    int classId,
    int courseId,
    int assignmentId,
    int teacherId,
  ) => callTool(connection, 'replace_skore_teacher', {
    'class_id': classId,
    'course_id': courseId,
    'assignment_id': assignmentId,
    'teacher_id': teacherId,
  }).then((call) => call.$2);

  /// The row of course [courseId] in what list_skore_courses answers for
  /// class [classId], from its teachers on.
  Future<String> teachersOf(int classId, int courseId) async {
    final text = await ok('list_skore_courses', {'class_id': classId});
    final row = text
        .split('\n')
        .singleWhere((line) => line.contains('| course id $courseId |'));
    return row.substring(row.lastIndexOf(' | ') + 3);
  }

  bool isSave(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path == fakeSkoreOwnersRpcPath &&
      (request.data as Map?)?['rpc_method'] == 'saveOwner';

  /// How many POSTs to Skore's RPC service reached the fake Smartschool,
  /// also those it refused because the session was not accepted.
  int rpcPosts() => server.requests
      .where((request) => request == 'POST $fakeSkoreOwnersRpcPath')
      .length;

  /// Logs in with a read, and forgets the requests it made.
  Future<int> loggedIn() async {
    await ok('list_skore_teachers', {});
    skore.requests.clear();
    server.requests.clear();
    return server.logins;
  }

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

    test('after the reads, as writes Claude Desktop asks approval for every '
        'time, not idempotent', () {
      // After the four reads (#44 added list_skore_gradebook_shares).
      expect(tools.keys.skip(4).take(2), [
        'add_skore_teacher',
        'replace_skore_teacher',
      ]);
      for (final name in ['add_skore_teacher', 'replace_skore_teacher']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isFalse, reason: name);
        expect(annotations.destructiveHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isFalse, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
      }
    });

    test('take the ids the reads give, as whole numbers', () {
      final add = tools['add_skore_teacher']!.inputSchema;
      final replace = tools['replace_skore_teacher']!.inputSchema;
      expect(add.required, ['class_id', 'course_id', 'teacher_id']);
      expect(replace.required, [
        'class_id',
        'course_id',
        'assignment_id',
        'teacher_id',
      ]);
      for (final schema in [add, replace]) {
        for (final MapEntry(:key, :value) in schema.properties!.entries) {
          expect(value, containsPair('type', 'integer'), reason: key);
          expect(value, containsPair('minimum', 1), reason: key);
        }
      }
      expect(
        add.properties!['teacher_id'],
        containsPair(
          'description',
          'The teacher id of the teacher to assign, from list_skore_teachers.',
        ),
      );
      expect(
        replace.properties!['assignment_id'],
        containsPair(
          'description',
          'The assignment id on that course whose teacher changes, from '
              'list_skore_courses.',
        ),
      );
      expect(
        add.properties!['course_id'],
        containsPair(
          'description',
          'The course id of the course in that class, from '
              'list_skore_courses (not its code, which is not unique).',
        ),
      );
    });

    test('tell Claude to show the change and wait for the user\'s '
        'confirmation, to replace rather than add for another teacher, and '
        'never to repeat a change that may have been saved', () {
      final add = tools['add_skore_teacher']!.description!;
      final replace = tools['replace_skore_teacher']!.description!;
      expect(
        add,
        contains(
          'Before calling this tool, read the class with list_skore_courses '
          'and look up the teacher with list_skore_teachers; show the user '
          'the class, the course (its label), the teachers it has now and '
          'the teacher to assign, and only call this tool after the user has '
          'explicitly confirmed it.',
        ),
      );
      expect(
        replace,
        contains(
          'Before calling this tool, read the class with list_skore_courses '
          'and look up the new teacher with list_skore_teachers; show the '
          'user the class, the course (its label), the teacher of the '
          'assignment now and the new one, and only call this tool after the '
          'user has explicitly confirmed it.',
        ),
      );
      expect(
        add,
        contains(
          'If the teacher to assign already has an assignment on the course, '
          'nothing needs to happen: do not call this tool. To give a course '
          'another teacher instead of one it has, use replace_skore_teacher, '
          'not this tool',
        ),
      );
      expect(add, contains('The new assignment holds all pupils of the class'));
      expect(
        replace,
        contains(
          'To add a teacher next to those on the course instead, use '
          'add_skore_teacher.',
        ),
      );
      expect(
        replace,
        contains(
          'The assignment and its gradebook stay, with the same assignment '
          'id; only its teacher changes',
        ),
      );
      expect(
        replace,
        contains(
          'works with "Mijn lesgroepen" (their own groups of pupils) for the '
          'course, nothing is saved: those groups have to be handled in Skore '
          'itself, and the server never deletes them.',
        ),
      );
      for (final (name, description) in [
        ('add_skore_teacher', add),
        ('replace_skore_teacher', replace),
      ]) {
        expect(
          description,
          contains(
            'If the result says the change may or may not have been saved, '
            'do not call this tool again for it: read the class with '
            'list_skore_courses and tell the user.',
          ),
          reason: name,
        );
        expect(
          description,
          contains(
            'Only for an account with the rights for score management in '
            'Skore; without them, the tool says so.',
          ),
          reason: name,
        );
      }
    });
  });

  test('refuse an id that is missing or not a whole number, without asking '
      'Skore', () async {
    for (final arguments in <Map<String, Object?>>[
      {'class_id': 2516, 'course_id': 2142},
      {'class_id': 2516, 'course_id': 2142, 'teacher_id': 1005.5},
      {'class_id': 2516, 'course_id': 2142, 'teacher_id': 0},
    ]) {
      await error('add_skore_teacher', arguments);
    }
    await error('replace_skore_teacher', {
      'class_id': 2516,
      'course_id': 1588,
      'teacher_id': 1006,
    });
    expect(skore.requests, isEmpty);
  });

  group('add_skore_teacher', () {
    test('assigns a teacher to a course without one with the exact save of '
        'dartschool#71, after reading the class and the teachers; the class '
        'then lists the new assignment', () async {
      expect(
        await add(2516, 2142, 1005),
        'Assigned Willems, Wim to course "Eye4Skills (2 uur) (3e graad) '
        '[PROJE]" (course id 2142) of class id 2516 in Skore: a new '
        'assignment, which holds all pupils of the class.\n'
        'Saved: Willems, Wim (teacher id 1005, assignment 35001). The '
        'assignment id is also the id of its gradebook.',
      );
      // The library's checks are the only reads: the class (the label in the
      // result is the one they read) and the teachers. No getMyGroups: there
      // is no current teacher.
      expect(skore.calls, [_page, _rpc('getTeachers'), _rpc('saveOwner')]);
      expect(skore.requests.first.query, {'classID': '2516'});
      // saveOwner(classID, courseID, ownerID, userID), ownerID empty for a
      // new assignment, as Skore's web client sends it.
      expect(skore.saves, [
        ['2516', '2142', '', '1005'],
      ]);
      final save = skore.requests.last.form;
      expect(
        save.keys,
        unorderedEquals([
          'rpc_sessionobj',
          'rpc_requestType',
          'rpc_method',
          'rpc_params',
        ]),
      );
      expect(save['rpc_requestType'], 'requestData');
      expect(save['rpc_params'], '["2516","2142","","1005"]');
      expect(jsonDecode(save['rpc_sessionobj']!), {
        'requestSource': 'skore-web',
        'timelimit': null,
        'client_epoch': isA<int>(),
      });

      expect(
        await teachersOf(2516, 2142),
        'teacher: Willems, Wim (teacher id 1005, assignment 35001)',
      );
    });

    test('adds a teacher next to those a course has: they keep their '
        'assignments', () async {
      expect(
        await add(2516, 1840, 1006),
        startsWith(
          'Assigned Maes, Mira to course "Project 1 (3e graad) [PROJE1]" '
          '(course id 1840) of class id 2516 in Skore',
        ),
      );
      expect(skore.saves, [
        ['2516', '1840', '', '1006'],
      ]);
      expect(
        await teachersOf(2516, 1840),
        '4 teachers: Peeters, Piet (teacher id 1002, assignment 34580); '
        'Dupré, Céline (teacher id 1003, assignment 34582); D\'Hondt, Karel '
        '(teacher id 1004, assignment 34584); Maes, Mira (teacher id 1006, '
        'assignment 35001)',
      );
    });

    test('a teacher already on the course is refused with the reason, '
        'saving nothing: a second call never adds a second '
        'assignment', () async {
      expect(
        await add(2516, 1588, 1005),
        _refused(
          'teacher 1005 (Willems, Wim) already has assignment 34826 on '
          'course 1588 of class 2516 ("Digitale vaardigheden  [Digitale '
          'vaardigheden]").',
        ),
      );
      expect(skore.saves, isEmpty);

      await ok('add_skore_teacher', {
        'class_id': 2516,
        'course_id': 2142,
        'teacher_id': 1005,
      });
      expect(
        await add(2516, 2142, 1005),
        _refused(
          'teacher 1005 (Willems, Wim) already has assignment 35001 on '
          'course 2142 of class 2516 ("Eye4Skills (2 uur) (3e graad) '
          '[PROJE]").',
        ),
      );
      expect(skore.saves, hasLength(1));
      expect(
        await teachersOf(2516, 2142),
        'teacher: Willems, Wim (teacher id 1005, assignment 35001)',
      );
    });

    test('passes on why Skore refused a change, so Claude can correct the '
        'call, and saves nothing', () async {
      final refusals = {
        (2516, 1966, 1005):
            'course 1966 of class 2516 ("Vakken [Vak]") is a group header, '
            'which cannot get a teacher.',
        (2516, 3010, 1005):
            'course 3010 is not in class 2516 (Skore lists 8 courses for '
            'it).',
        (999999, 2142, 1005):
            'course 2142 is not in class 999999 (Skore lists 0 courses for '
            'it).',
        (2516, 2142, 4242):
            "teacher 4242 is not one of Skore's teachers (not in "
            'getTeachers).',
      };
      for (final MapEntry(key: (classId, courseId, teacherId), :value)
          in refusals.entries) {
        final (result, text) = await callTool(connection, 'add_skore_teacher', {
          'class_id': classId,
          'course_id': courseId,
          'teacher_id': teacherId,
        });
        expect(result.isError, isTrue, reason: text);
        expect(text, _refused(value));
      }
      expect(skore.saves, isEmpty);
    });

    test('an account without the rights: says so, and that nothing was '
        'changed, without quoting the page', () async {
      skore.refusal = SkoreRefusal.forbidden;
      expect(
        await error('add_skore_teacher', {
          'class_id': 2516,
          'course_id': 2142,
          'teacher_id': 1005,
        }),
        'This account has no rights for score management in Skore: Skore '
        'refused it its report management (Rapporten > Modellen). The Skore '
        'tools need $_rightsAndFix: $_fix. Nothing was changed in Skore.',
      );

      skore.refusal = SkoreRefusal.page;
      final text = await add(2516, 2142, 1005);
      expect(
        text,
        'Skore gave an answer the server could not use; usually the account '
        'lacks $_rightsAndFix. If so, $_fix. Otherwise try again in a '
        'moment; the technical details are in the server log. Nothing was '
        'changed in Skore.',
      );
      expect(text, isNot(contains(fakeSkoreNoAccessName)));
      expect(skore.calls, [_page, _page], reason: 'the first read, refused');
    });

    group('a save Skore does not confirm is never sent again, and is not '
        'repeated as a refused session', () {
      test('the connection drops after the save went out', () async {
        final logins = await loggedIn();
        skore.save = SkoreSave.answerLost;

        expect(
          await error('add_skore_teacher', {
            'class_id': 2516,
            'course_id': 2142,
            'teacher_id': 1005,
          }),
          // The course by id only: the library's error carries nothing of
          // the course it read (dartschool#120).
          'Assigning teacher id 1005 to course id 2142 of class id 2516 may '
          'or may not have been saved: the change was sent, but Skore did '
          'not confirm it. Do not call add_skore_teacher again for it: first '
          'read the class with list_skore_courses (class_id 2516): when '
          'course id 2142 lists teacher id 1005, it was saved; when it does '
          'not, nothing was saved. Then tell the user what you found.',
        );
        expect(skore.calls, [
          _page,
          _rpc('getTeachers'),
          _rpc('saveOwner'),
        ], reason: 'not repeated');
        expect(server.logins, logins);
        // It was saved: the check the result asks for finds it.
        expect(
          await teachersOf(2516, 2142),
          'teacher: Willems, Wim (teacher id 1005, assignment 35001)',
        );
      });

      test('Skore answers the save with an error page', () async {
        final logins = await loggedIn();
        skore.save = SkoreSave.serverError;

        expect(
          await add(2516, 2142, 1005),
          startsWith(
            'Assigning teacher id 1005 to course id 2142 of class id 2516 may '
            'or may not have been saved: the change was sent, but Skore did '
            'not confirm it. Do not call add_skore_teacher again for it',
          ),
        );
        expect(skore.saves, hasLength(1));
        expect(skore.calls.last, _rpc('saveOwner'));
        expect(server.logins, logins);
        expect(await teachersOf(2516, 2142), 'no teacher');
      });
    });

    group('Smartschool refuses the session for the save', () {
      test('the library does not send it again: the session repeats the '
          'call, which reads the class again and saves once', () async {
        final logins = await loggedIn();
        server.expireSessionBefore(isSave);

        expect(
          await add(2516, 2142, 1005),
          startsWith('Assigned Willems, Wim to course "Eye4Skills'),
        );
        expect(server.logins, logins + 1);
        // The refused save never reached Skore; the repeat read the class
        // and the teachers again.
        expect(skore.calls, [
          _page,
          _rpc('getTeachers'),
          _page,
          _rpc('getTeachers'),
          _rpc('saveOwner'),
        ]);
        expect(
          rpcPosts(),
          skore.calls.where((call) => call.startsWith('POST')).length + 1,
          reason: 'the refused save and the one save',
        );
        expect(skore.saves, hasLength(1));
        expect(
          await teachersOf(2516, 2142),
          'teacher: Willems, Wim (teacher id 1005, assignment 35001)',
        );
      });

      test('the repeat reads the class again: a teacher on the course by '
          'then is refused, so there is never a second assignment', () async {
        await loggedIn();
        server.expireSessionBefore((request) {
          if (!isSave(request)) return false;
          // Meanwhile, the same teacher is assigned in Skore's web client.
          skore.addAssignment(2516, 2142, FakeSkoreTeacher.willems);
          return true;
        });

        expect(
          await add(2516, 2142, 1005),
          _refused(
            'teacher 1005 (Willems, Wim) already has assignment 35001 on '
            'course 2142 of class 2516 ("Eye4Skills (2 uur) (3e graad) '
            '[PROJE]").',
          ),
        );
        expect(skore.saves, isEmpty);
        expect(
          await teachersOf(2516, 2142),
          'teacher: Willems, Wim (teacher id 1005, assignment 35001)',
        );
      });
    });
  });

  group('replace_skore_teacher', () {
    test('gives an assignment another teacher with the exact save of '
        'dartschool#71, after asking whether its teacher works with "Mijn '
        'lesgroepen"; the assignment keeps its id', () async {
      expect(
        await replace(2516, 1588, 34826, 1006),
        'Gave assignment 34826 on course "Digitale vaardigheden [Digitale '
        'vaardigheden]" (course id 1588) of class id 2516 another teacher in '
        'Skore: Maes, Mira instead of Willems, Wim (teacher id 1005). The '
        'assignment and its gradebook stay; only its teacher changed.\n'
        'Saved: Maes, Mira (teacher id 1006, assignment 34826).',
      );
      // The library's checks are the only reads: the teacher replaced in the
      // result is the one they read.
      expect(skore.calls, [
        _page,
        _rpc('getTeachers'),
        _rpc('getMyGroups'),
        _rpc('saveOwner'),
      ]);
      // getMyGroups(userID, classID, courseID), for the current teacher.
      expect(skore.paramsOf('getMyGroups'), [
        ['1005', '2516', '1588'],
      ]);
      expect(skore.saves, [
        ['2516', '1588', '34826', '1006'],
      ]);
      expect(
        await teachersOf(2516, 1588),
        'teacher: Maes, Mira (teacher id 1006, assignment 34826)',
      );
    });

    test('one of several teachers: the others keep theirs', () async {
      await ok('replace_skore_teacher', {
        'class_id': 2516,
        'course_id': 1840,
        'assignment_id': 34582,
        'teacher_id': 1001,
      });
      expect(skore.paramsOf('getMyGroups'), [
        ['1003', '2516', '1840'],
      ]);
      expect(
        await teachersOf(2516, 1840),
        '3 teachers: Peeters, Piet (teacher id 1002, assignment 34580); '
        'Janssens, Jan (teacher id 1001, assignment 34582); D\'Hondt, Karel '
        '(teacher id 1004, assignment 34584)',
      );
    });

    test('passes on why Skore refused a change, saving nothing and asking '
        'nothing about "Mijn lesgroepen"', () async {
      final refusals = {
        (2516, 1588, 31882, 1006):
            'assignment 31882 is not one of course 1588 of class 2516.',
        (2516, 1840, 34580, 1003):
            'teacher 1003 (Dupré, Céline) already has assignment 34582 on '
            'course 1840 of class 2516 ("Project 1 (3e graad) [PROJE1]").',
        (2516, 1588, 34826, 1005):
            'teacher 1005 (Willems, Wim) already has assignment 34826 on '
            'course 1588 of class 2516 ("Digitale vaardigheden  [Digitale '
            'vaardigheden]").',
        (2516, 1590, 34826, 1006):
            'course 1590 of class 2516 ("Extra rapporten  [Extra '
            'rapporten]") is a group header, which cannot get a teacher.',
      };
      for (final MapEntry(
            key: (classId, courseId, assignmentId, teacherId),
            :value,
          )
          in refusals.entries) {
        expect(
          await replace(classId, courseId, assignmentId, teacherId),
          _refused(value),
        );
      }
      expect(skore.saves, isEmpty);
      expect(skore.paramsOf('getMyGroups'), isEmpty);
    });

    test('the current teacher works with "Mijn lesgroepen": nothing is '
        'saved, the groups are left alone, and Claude is told to leave them '
        'to the user in Skore', () async {
      skore.myGroups.add((1005, 2516, 1588));

      expect(
        await error('replace_skore_teacher', {
          'class_id': 2516,
          'course_id': 1588,
          'assignment_id': 34826,
          'teacher_id': 1006,
        }),
        // The current teacher named as the library read them.
        'Skore did not save the change: the current teacher of the '
        'assignment, Willems, Wim (teacher id 1005), works with "Mijn '
        'lesgroepen", their own groups of pupils, for course id 1588 of class '
        'id 2516. Those groups have to be handled in Skore itself first: tell '
        'the user, who can make this change in Skore, where Skore asks to '
        'delete the groups (which cannot be undone). The server never deletes '
        'them; do not try another way to change this assignment. Nothing was '
        'changed in Skore.',
      );
      expect(skore.calls, [_page, _rpc('getTeachers'), _rpc('getMyGroups')]);
      expect(
        await teachersOf(2516, 1588),
        'teacher: Willems, Wim (teacher id 1005, assignment 34826)',
      );
    });

    test('an error about "Mijn lesgroepen" without the name of the current '
        'teacher, which the library always gives, names them by id', () {
      final error = skoreToolError(
        const SmartschoolSkoreMyGroupsError(
          'replaceTeacher: the current teacher works with "Mijn lesgroepen".',
          classId: 2516,
          courseId: 1588,
          teacherId: 1005,
        ),
        fakeExtensionSettings(),
      );
      expect(
        error?.message,
        startsWith(
          'Skore did not save the change: the current teacher of the '
          'assignment (teacher id 1005) works with "Mijn lesgroepen", their '
          'own groups of pupils, for course id 1588 of class id 2516. ',
        ),
      );
    });

    test('a save Skore does not confirm is never sent again: the result '
        'says what to read to check it', () async {
      final logins = await loggedIn();
      skore.save = SkoreSave.answerLost;

      expect(
        await error('replace_skore_teacher', {
          'class_id': 2516,
          'course_id': 1588,
          'assignment_id': 34826,
          'teacher_id': 1006,
        }),
        // The course by id only, and not the teacher it had: the library's
        // error carries nothing of what it read (dartschool#120).
        'Giving assignment 34826 on course id 1588 of class id 2516 teacher '
        'id 1006 may or may not have been saved: the change was sent, but '
        'Skore did not confirm it. Do not call replace_skore_teacher again '
        'for it: first read the class with list_skore_courses (class_id '
        '2516): when assignment 34826 has teacher id 1006, it was saved; when '
        'it still has the teacher it had, nothing was saved. Then tell the '
        'user what you found.',
      );
      expect(skore.saves, hasLength(1));
      expect(skore.calls.last, _rpc('saveOwner'), reason: 'not repeated');
      expect(server.logins, logins);
      expect(
        await teachersOf(2516, 1588),
        'teacher: Maes, Mira (teacher id 1006, assignment 34826)',
      );
    });

    test('Smartschool refuses the session for the save: the session repeats '
        'the call, which reads the class and asks about "Mijn lesgroepen" '
        'again, and saves once', () async {
      final logins = await loggedIn();
      server.expireSessionBefore(isSave);

      expect(
        await replace(2516, 1588, 34826, 1006),
        startsWith('Gave assignment 34826 on course "Digitale vaardigheden'),
      );
      expect(server.logins, logins + 1);
      expect(skore.paramsOf('getMyGroups'), hasLength(2));
      expect(skore.saves, [
        ['2516', '1588', '34826', '1006'],
      ]);
      expect(
        rpcPosts(),
        skore.calls.where((call) => call.startsWith('POST')).length + 1,
        reason: 'the refused save and the one save',
      );
      expect(
        await teachersOf(2516, 1588),
        'teacher: Maes, Mira (teacher id 1006, assignment 34826)',
      );
    });
  });

  test('the flow of the issue: read the class, look up the teacher, assign, '
      'then give the course another teacher', () async {
    expect(
      await ok('list_skore_courses', {'class_id': 2516}),
      contains('[PROJE] | course id 2142 | code PROJE | depth 1 | no teacher'),
    );
    expect(
      await ok('list_skore_teachers', {'query': 'dupre'}),
      contains('- Dupré, Céline | teacher id 1003'),
    );
    await ok('add_skore_teacher', {
      'class_id': 2516,
      'course_id': 2142,
      'teacher_id': 1003,
    });
    expect(
      await teachersOf(2516, 2142),
      'teacher: Dupré, Céline (teacher id 1003, assignment 35001)',
    );
    await ok('replace_skore_teacher', {
      'class_id': 2516,
      'course_id': 2142,
      'assignment_id': 35001,
      'teacher_id': 1001,
    });
    expect(
      await teachersOf(2516, 2142),
      'teacher: Janssens, Jan (teacher id 1001, assignment 35001)',
    );
    expect(skore.saves, [
      ['2516', '2142', '', '1003'],
      ['2516', '2142', '35001', '1001'],
    ]);
  });
}
