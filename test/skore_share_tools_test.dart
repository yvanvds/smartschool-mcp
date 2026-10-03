/// `list_skore_gradebook_shares`, `share_skore_gradebook` and
/// `unshare_skore_gradebook` (#44), called over MCP on the real server,
/// session and library, against a fake Smartschool whose Skore serves the
/// gradebooks of a teacher (`getCourses` of the gradebooks service) and
/// carries out the save of their shares (`saveShared`) as the live Skore did
/// in dartschool#74 (`test/support/fake_skore.dart`).
library;

import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:smartschool_mcp/src/skore/skore_opt_in.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _getCourses = 'POST $fakeSkoreGradebooksRpcPath getCourses';
const _saveShared = 'POST $fakeSkoreGradebooksRpcPath saveShared';
const _getTeachers = 'POST $fakeSkoreOwnersRpcPath getTeachers';

/// The read of a share or unshare before its first change: the teachers, to
/// name them. What each teacher had before, and whether a save was sent,
/// come from the library's result.
const _toolReads = [_getTeachers];

/// Gradebook 34826 of the fake school in a sentence, as named from the
/// library's first result.
const _digitale =
    'gradebook 34826 ("Digitale vaardigheden", class 5WW1) of Willems, Wim '
    '(teacher id 1005)';

/// Gradebook 34826 by its id, as named when the change stopped at the first
/// teacher: the library returned nothing to name it from.
const _digitaleById = 'gradebook 34826 of Willems, Wim (teacher id 1005)';

/// What the result says after a check refused the change for [teacher].
String _refused(String reason, String teacher) =>
    'Skore refused the change before saving it: $reason Read the gradebook '
    'again with list_skore_gradebook_shares (and the teachers with '
    'list_skore_teachers) to correct the call. Nothing was saved for '
    '$teacher.';

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
    // Of the gradebooks service, which also deletes and locks, only the
    // read and the save of shares; of owners.php only the teachers.
    for (final request in skore.requests) {
      if (request.rpc case final rpc?) {
        expect(
          rpc,
          isIn(
            request.path == fakeSkoreGradebooksRpcPath
                ? fakeSkoreGradebooksRpcMethods
                : {'getTeachers'},
          ),
          reason: request.path,
        );
      }
    }
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

  Future<(bool, String)> share(
    List<int> teacherIds,
    String access, {
    int ownerId = 1005,
    int gradebookId = 34826,
  }) => callTool(connection, 'share_skore_gradebook', {
    'owner_id': ownerId,
    'gradebook_id': gradebookId,
    'teacher_ids': teacherIds,
    'access': access,
  }).then((call) => (call.$1.isError ?? false, call.$2));

  Future<(bool, String)> unshare(
    List<int> teacherIds, {
    int ownerId = 1005,
    int gradebookId = 34826,
  }) => callTool(connection, 'unshare_skore_gradebook', {
    'owner_id': ownerId,
    'gradebook_id': gradebookId,
    'teacher_ids': teacherIds,
  }).then((call) => (call.$1.isError ?? false, call.$2));

  /// The line of gradebook [gradebookId] in what list_skore_gradebook_shares
  /// answers for teacher [ownerId], from its readers on.
  Future<String> sharesOf(int gradebookId, {int ownerId = 1005}) async {
    final text = await ok('list_skore_gradebook_shares', {
      'teacher_id': ownerId,
    });
    final line = text
        .split('\n')
        .singleWhere((line) => line.contains('| gradebook id $gradebookId |'));
    return line.substring(line.indexOf('| readers: ') + 2);
  }

  bool isShareSave(RequestOptions request) =>
      request.method == 'POST' &&
      request.uri.path == fakeSkoreGradebooksRpcPath &&
      (request.data as Map?)?['rpc_method'] == 'saveShared';

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

    test('the read after the other reads, read-only; the share and unshare '
        'last, as writes Claude Desktop asks approval for every time, and '
        'idempotent', () {
      expect(tools.keys.take(4).last, 'list_skore_gradebook_shares');
      expect(tools.keys.skip(6), [
        'share_skore_gradebook',
        'unshare_skore_gradebook',
      ]);
      final read = tools['list_skore_gradebook_shares']!.toolAnnotations!;
      expect(read.readOnlyHint, isTrue);
      expect(read.idempotentHint, isTrue);
      expect(read.destructiveHint, isNot(true));
      expect(read.openWorldHint, isTrue);
      for (final name in ['share_skore_gradebook', 'unshare_skore_gradebook']) {
        final annotations = tools[name]!.toolAnnotations!;
        expect(annotations.readOnlyHint, isFalse, reason: name);
        expect(annotations.destructiveHint, isTrue, reason: name);
        expect(annotations.idempotentHint, isTrue, reason: name);
        expect(annotations.openWorldHint, isTrue, reason: name);
      }
    });

    test('take the ids the reads give: whole numbers, a list of 1 to 50 '
        'teachers, and the access as read or write', () {
      final list = tools['list_skore_gradebook_shares']!.inputSchema;
      final shareSchema = tools['share_skore_gradebook']!.inputSchema;
      final unshareSchema = tools['unshare_skore_gradebook']!.inputSchema;
      expect(list.required, ['teacher_id']);
      expect(list.properties!['teacher_id'], containsPair('minimum', 1));
      expect(shareSchema.required, [
        'owner_id',
        'gradebook_id',
        'teacher_ids',
        'access',
      ]);
      expect(unshareSchema.required, [
        'owner_id',
        'gradebook_id',
        'teacher_ids',
      ]);
      for (final schema in [shareSchema, unshareSchema]) {
        for (final name in ['owner_id', 'gradebook_id']) {
          expect(schema.properties![name], containsPair('type', 'integer'));
          expect(schema.properties![name], containsPair('minimum', 1));
        }
        expect(schema.properties!['teacher_ids'], {
          'type': 'array',
          'description': isA<String>(),
          'items': {'type': 'integer', 'minimum': 1},
          'minItems': 1,
          'maxItems': 50,
        });
        expect(
          schema.properties!['gradebook_id'],
          containsPair(
            'description',
            'The gradebook id: the assignment id in list_skore_courses, or '
                'the gradebook id in list_skore_gradebook_shares.',
          ),
        );
        expect(
          schema.properties!['owner_id'],
          containsPair(
            'description',
            'The teacher id of the owner of the gradebook: the teacher of its '
                'assignment in list_skore_courses.',
          ),
        );
      }
      expect(shareSchema.properties!['access'], {
        'type': 'string',
        'description': isA<String>(),
        'enum': ['read', 'write'],
      });
    });

    test('tell Claude where the ids come from, the typical flow, to show '
        'the change and wait for the user\'s confirmation, and never to '
        'repeat a change that may have been saved', () {
      final list = tools['list_skore_gradebook_shares']!.description!;
      final shareText = tools['share_skore_gradebook']!.description!;
      final unshareText = tools['unshare_skore_gradebook']!.description!;
      expect(
        list,
        contains(
          'its gradebook id is the assignment id in list_skore_courses, and '
          'its owner is the teacher of that assignment',
        ),
      );
      expect(
        list,
        contains(
          'An empty list means that no gradebook belongs to that teacher id, '
          'or that no teacher has that id.',
        ),
      );
      expect(
        shareText,
        contains(
          'A typical flow: find the class with list_skore_classes, read its '
          'courses with list_skore_courses, take the assignment of the '
          'titularis on the course (its assignment id is the gradebook id, '
          'its teacher the owner), and share it with the other teachers of '
          'the class',
        ),
      );
      expect(
        shareText,
        contains(
          'show the user the gradebook (its course and class), the teachers '
          'to share it with and the access, and only call this tool after '
          'the user has explicitly confirmed it. Pass all teachers of one '
          'confirmation in one call.',
        ),
      );
      expect(
        unshareText,
        contains(
          'show the user the gradebook (its course and class) and the '
          'teachers who lose their access, and only call this tool after the '
          'user has explicitly confirmed it. Pass all teachers of one '
          'confirmation in one call.',
        ),
      );
      expect(
        shareText,
        contains('a teacher with the other access gets the access given'),
      );
      expect(
        shareText,
        contains(
          'That gives those teachers access to the scores of the pupils',
        ),
      );
      for (final (name, description) in [
        ('share_skore_gradebook', shareText),
        ('unshare_skore_gradebook', unshareText),
      ]) {
        expect(
          description,
          contains(
            'The gradebook id is the assignment id in list_skore_courses, '
            'and the owner is the teacher of that assignment.',
          ),
          reason: name,
        );
        expect(
          description,
          contains(
            'stops at the first that fails: the result says per teacher',
          ),
          reason: name,
        );
        expect(
          description,
          contains(
            'If the result says a change may or may not have been saved, do '
            'not call this tool again for it: read the gradebook with '
            'list_skore_gradebook_shares and tell the user.',
          ),
          reason: name,
        );
      }
      for (final (name, description) in [
        ('list_skore_gradebook_shares', list),
        ('share_skore_gradebook', shareText),
        ('unshare_skore_gradebook', unshareText),
      ]) {
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

  test('refuse arguments that are missing or out of range, without asking '
      'Skore', () async {
    for (final arguments in <Map<String, Object?>>[
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': [1001],
      },
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': [1001],
        'access': 'admin',
      },
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': <int>[],
        'access': 'read',
      },
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': [0],
        'access': 'read',
      },
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': [1001.5],
        'access': 'read',
      },
      {
        'owner_id': 1005,
        'gradebook_id': 34826,
        'teacher_ids': [for (var id = 2001; id <= 2051; id++) id],
        'access': 'read',
      },
      {
        'owner_id': 0,
        'gradebook_id': 34826,
        'teacher_ids': [1001],
        'access': 'write',
      },
    ]) {
      await error('share_skore_gradebook', arguments);
    }
    await error('unshare_skore_gradebook', {
      'owner_id': 1005,
      'teacher_ids': [1006],
    });
    await error('list_skore_gradebook_shares', {});
    await error('list_skore_gradebook_shares', {'teacher_id': 0});
    expect(skore.requests, isEmpty);
  });

  group('list_skore_gradebook_shares', () {
    test('lists the gradebooks of a teacher, in Skore\'s order, with their '
        'readers and writers by name; a teacher Skore no longer lists by '
        'id', () async {
      skore.shares[34580] = (readers: [1001, 1999], writers: [1003]);

      expect(
        await ok('list_skore_gradebook_shares', {'teacher_id': 1002}),
        'Skore lists 2 gradebooks of Peeters, Piet (teacher id 1002), in '
        'Skore\'s order, each with the teachers it is shared with: readers '
        'may read it, writers may read and change it. A gradebook id is the '
        'id of its assignment in list_skore_courses.\n'
        '- Nederlands (4 uur) | class 3B1 | gradebook id 40020 | readers: '
        'none | writers: none\n'
        '- Project 1 | class 5WW1 | gradebook id 34580 | readers: Janssens, '
        'Jan (teacher id 1001); teacher id 1999 | writers: Dupré, Céline '
        '(teacher id 1003)',
      );
      // The gradebooks, the owner's id as a number, then the teachers'
      // names.
      expect(skore.calls, [_getCourses, _getTeachers]);
      expect(skore.requests.first.form['rpc_params'], '[1002]');
    });

    test('one gradebook, as in the capture of dartschool#74', () async {
      expect(
        await ok('list_skore_gradebook_shares', {'teacher_id': 1005}),
        'Skore lists 1 gradebook of Willems, Wim (teacher id 1005), in '
        'Skore\'s order, each with the teachers it is shared with: readers '
        'may read it, writers may read and change it. A gradebook id is the '
        'id of its assignment in list_skore_courses.\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'none | writers: Maes, Mira (teacher id 1006)',
      );
    });

    test('says so for a teacher without gradebooks and for an unknown '
        'id', () async {
      skore.teachers.add(const FakeSkoreTeacher(1007, 'Claes, Clara'));
      expect(
        await ok('list_skore_gradebook_shares', {'teacher_id': 1007}),
        'Skore lists no gradebooks for Claes, Clara (teacher id 1007): no '
        'gradebook belongs to that teacher id, or no teacher has that id. '
        'Take the teacher id of an assignment from list_skore_courses.',
      );
      expect(
        await ok('list_skore_gradebook_shares', {'teacher_id': 999999}),
        'Skore lists no gradebooks for teacher id 999999: no gradebook '
        'belongs to that teacher id, or no teacher has that id. Take the '
        'teacher id of an assignment from list_skore_courses.',
      );
    });

    test('an account without the rights: says so, without quoting the '
        'page', () async {
      skore.refusal = SkoreRefusal.forbidden;
      expect(
        await error('list_skore_gradebook_shares', {'teacher_id': 1005}),
        'This account has no rights for score management in Skore: Skore '
        'refused it its gradebook management (Puntenboeken). The Skore tools '
        'need $_rightsAndFix: $_fix.',
      );

      skore.refusal = SkoreRefusal.page;
      final text = await error('list_skore_gradebook_shares', {
        'teacher_id': 1005,
      });
      expect(
        text,
        'Skore gave an answer the server could not use; usually the account '
        'lacks $_rightsAndFix. If so, $_fix. Otherwise try again in a '
        'moment; the technical details are in the server log.',
      );
      expect(text, isNot(contains(fakeSkoreNoAccessName)));
    });
  });

  group('share_skore_gradebook', () {
    test('shares a gradebook with several teachers in one call, one after '
        'the other, each with a save of that one gradebook with the ids as '
        'numbers; the teachers it was shared with keep theirs', () async {
      final (isError, text) = await share([1001, 1002, 1001, 1003], 'read');
      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Shared $_digitale in Skore with read access (they may read it):\n'
        '- Janssens, Jan (teacher id 1001): shared with read access\n'
        '- Peeters, Piet (teacher id 1002): shared with read access\n'
        '- Dupré, Céline (teacher id 1003): shared with read access\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'Janssens, Jan (teacher id 1001); Peeters, Piet (teacher id 1002); '
        'Dupré, Céline (teacher id 1003) | writers: Maes, Mira (teacher id '
        '1006)',
      );
      // The tool's read, then per teacher the library's: the gradebooks and
      // the teachers before the save, the gradebooks after it.
      expect(skore.calls, [
        ..._toolReads,
        for (var i = 0; i < 3; i++) ...[
          _getCourses,
          _getTeachers,
          _saveShared,
          _getCourses,
        ],
      ]);
      // saveShared(userID, readers, writers): only this gradebook, with its
      // complete new readers and writers, the ids as numbers.
      expect(skore.shareSaves, [
        [
          1005,
          {
            '34826': [1001],
          },
          {
            '34826': [1006],
          },
        ],
        [
          1005,
          {
            '34826': [1001, 1002],
          },
          {
            '34826': [1006],
          },
        ],
        [
          1005,
          {
            '34826': [1001, 1002, 1003],
          },
          {
            '34826': [1006],
          },
        ],
      ]);
      final save = skore.requests.firstWhere((r) => r.rpc == 'saveShared');
      expect(
        save.form['rpc_params'],
        '[1005,{"34826":[1001]},{"34826":[1006]}]',
      );
      expect(save.form['rpc_requestType'], 'requestData');
      expect(jsonDecode(save.form['rpc_sessionobj']!), {
        'requestSource': 'skore-web',
        'timelimit': null,
        'client_epoch': isA<int>(),
      });

      expect(
        await sharesOf(34826),
        'readers: Janssens, Jan (teacher id 1001); Peeters, Piet (teacher id '
        '1002); Dupré, Céline (teacher id 1003) | writers: Maes, Mira '
        '(teacher id 1006)',
      );
    });

    test('moves a teacher from read to write access, and from write to '
        'read', () async {
      skore.shares[34826] = (readers: [1001, 1002], writers: [1006]);

      final (_, toWrite) = await share([1001], 'write');
      expect(
        toWrite,
        startsWith(
          'Shared $_digitale in Skore with write access (they may read and '
          'change it):\n'
          '- Janssens, Jan (teacher id 1001): now write access instead of '
          'read access\n',
        ),
      );
      final (_, toRead) = await share([1006], 'read');
      expect(
        toRead,
        contains(
          '- Maes, Mira (teacher id 1006): now read access instead of write '
          'access\n',
        ),
      );
      expect(skore.shareSaves, [
        [
          1005,
          {
            '34826': [1002],
          },
          {
            '34826': [1006, 1001],
          },
        ],
        [
          1005,
          {
            '34826': [1002, 1006],
          },
          {
            '34826': [1001],
          },
        ],
      ]);
      expect(
        await sharesOf(34826),
        'readers: Peeters, Piet (teacher id 1002); Maes, Mira (teacher id '
        '1006) | writers: Janssens, Jan (teacher id 1001)',
      );
    });

    test('the no-op: a teacher who already has that access is reported so, '
        'and nothing is saved', () async {
      final (isError, text) = await share([1006], 'write');
      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Nothing changed in Skore: $_digitale was already shared with these '
        'teachers that way, so nothing was saved:\n'
        '- Maes, Mira (teacher id 1006): already had write access; nothing '
        'saved\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'none | writers: Maes, Mira (teacher id 1006)',
      );
      expect(skore.calls, [..._toolReads, _getCourses]);

      final (_, mixed) = await share([1006, 1001], 'write');
      expect(
        mixed,
        startsWith(
          'Shared $_digitale in Skore with write access (they may read and '
          'change it):\n'
          '- Maes, Mira (teacher id 1006): already had write access; nothing '
          'saved\n'
          '- Janssens, Jan (teacher id 1001): shared with write access\n',
        ),
      );
      expect(skore.shareSaves, hasLength(1));
    });

    test('a failure halfway: the teachers before it are shared, the one '
        'that failed and those after it are not, and the result says so per '
        'teacher', () async {
      final (isError, text) = await share([1001, 4242, 1002], 'read');
      expect(isError, isTrue);
      expect(
        text,
        'Sharing $_digitale in Skore with read access (they may read it) '
        'stopped at teacher id 4242:\n'
        '- Janssens, Jan (teacher id 1001): shared with read access\n'
        '- teacher id 4242: not shared (see below)\n'
        '- Peeters, Piet (teacher id 1002): not tried\n'
        'Skore refused the change before saving it: teacher 4242 is not one '
        "of Skore's teachers (not in getTeachers). Read the gradebook again "
        'with list_skore_gradebook_shares (and the teachers with '
        'list_skore_teachers) to correct the call. Nothing was saved for '
        'teacher id 4242. The teachers listed after them were not tried.\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'Janssens, Jan (teacher id 1001) | writers: Maes, Mira (teacher id '
        '1006)',
      );
      expect(skore.shareSaves, hasLength(1));
      expect(
        await sharesOf(34826),
        'readers: Janssens, Jan (teacher id 1001) | writers: Maes, Mira '
        '(teacher id 1006)',
      );
    });

    test('passes on why Skore refused a change, so Claude can correct the '
        'call, and saves nothing', () async {
      final (isError, owner) = await share([1005], 'read');
      expect(isError, isTrue);
      // Refused at the first teacher: the library returned no gradebook to
      // name it from or to show.
      expect(
        owner,
        'Sharing $_digitaleById in Skore with read access (they may read it) '
        'stopped at Willems, Wim (teacher id 1005):\n'
        '- Willems, Wim (teacher id 1005): not shared (see below)\n'
        '${_refused('teacher 1005 is the owner of the gradebook, who cannot be a reader or a writer of it.', 'Willems, Wim (teacher id 1005)')}',
      );
      // Refused before any request of the library.
      expect(skore.calls, _toolReads);

      final (_, notOwners) = await share([1001], 'read', gradebookId: 34580);
      expect(
        notOwners,
        'Sharing gradebook 34580 of Willems, Wim (teacher id 1005) in Skore '
        'with read access (they may read it) stopped at Janssens, Jan '
        '(teacher id 1001):\n'
        '- Janssens, Jan (teacher id 1001): not shared (see below)\n'
        '${_refused('gradebook 34580 is not one of teacher 1005 (Skore lists 1 gradebooks for them).', 'Janssens, Jan (teacher id 1001)')}',
      );

      final (_, unknownOwner) = await share([1001], 'read', ownerId: 999999);
      expect(
        unknownOwner,
        contains(
          _refused(
            'gradebook 34826 is not one of teacher 999999 (Skore lists 0 '
                'gradebooks for them).',
            'Janssens, Jan (teacher id 1001)',
          ),
        ),
      );
      expect(
        unknownOwner,
        startsWith('Sharing gradebook 34826 of teacher id 999999 in Skore'),
      );

      final (_, unknownTeacher) = await share([4242], 'write');
      expect(
        unknownTeacher,
        contains(
          _refused(
            "teacher 4242 is not one of Skore's teachers (not in "
                'getTeachers).',
            'teacher id 4242',
          ),
        ),
      );
      expect(skore.shareSaves, isEmpty);
      expect(
        await sharesOf(34826),
        'readers: none | writers: Maes, Mira (teacher id 1006)',
      );
    });

    test('an account without the rights: says so, and that nothing was '
        'changed, without quoting the page', () async {
      // The tool's read of the teachers comes first: Skore refuses it its
      // report management.
      skore.refusal = SkoreRefusal.forbidden;
      final (_, forbidden) = await share([1001], 'read');
      expect(
        forbidden,
        'This account has no rights for score management in Skore: Skore '
        'refused it its report management (Rapporten > Modellen). The Skore '
        'tools need $_rightsAndFix: $_fix. Nothing was changed in Skore.',
      );

      skore.refusal = SkoreRefusal.page;
      final (isError, page) = await share([1001], 'read');
      expect(isError, isTrue);
      expect(
        page,
        'Skore gave an answer the server could not use; usually the account '
        'lacks $_rightsAndFix. If so, $_fix. Otherwise try again in a '
        'moment; the technical details are in the server log. Nothing was '
        'changed in Skore.',
      );
      expect(page, isNot(contains(fakeSkoreNoAccessName)));
      expect(skore.calls, [
        _getTeachers,
        _getTeachers,
      ], reason: 'each call refused at its first read');
    });

    test('an account with the rights for report management but not for '
        'gradebook management: the library refuses the first teacher, so '
        'the gradebook is named by its id, and nothing is saved', () async {
      skore
        ..refusal = SkoreRefusal.forbidden
        ..refusedPaths = {fakeSkoreGradebooksRpcPath};
      final (isError, text) = await share([1001, 1002], 'read');
      expect(isError, isTrue);
      expect(
        text,
        'Sharing $_digitaleById in Skore with read access (they may read it) '
        'stopped at Janssens, Jan (teacher id 1001):\n'
        '- Janssens, Jan (teacher id 1001): not shared (see below)\n'
        '- Peeters, Piet (teacher id 1002): not tried\n'
        'This account has no rights for score management in Skore: Skore '
        'refused it its gradebook management (Puntenboeken). The Skore tools '
        'need $_rightsAndFix: $_fix. Nothing was saved for Janssens, Jan '
        '(teacher id 1001). The teachers listed after them were not tried.',
      );
      expect(skore.calls, [..._toolReads, _getCourses]);
      expect(skore.shareSaves, isEmpty);
    });

    group('a save Skore does not confirm is reported as maybe saved, with '
        'what to read, and the teachers after it are not tried', () {
      test('the connection drops after the save went out, halfway', () async {
        final logins = await loggedIn();
        skore.nextSaves.addAll([SkoreSave.confirmed, SkoreSave.answerLost]);

        final (isError, text) = await share([1001, 1002, 1003], 'write');
        expect(isError, isTrue);
        expect(
          text,
          'Sharing $_digitale in Skore with write access (they may read and '
          'change it) stopped at Peeters, Piet (teacher id 1002):\n'
          '- Janssens, Jan (teacher id 1001): shared with write access\n'
          '- Peeters, Piet (teacher id 1002): may or may not have been shared '
          '(see below)\n'
          '- Dupré, Céline (teacher id 1003): not tried\n'
          'Sharing $_digitale with Peeters, Piet (teacher id 1002) with write '
          'access may or may not have been saved: the change was sent, but '
          'Skore did not confirm it. Do not call share_skore_gradebook again '
          'for it: first read the gradebooks with list_skore_gradebook_shares '
          '(teacher_id 1005): when gradebook 34826 lists teacher id 1002 '
          'among its writers, it was saved; when it does not, nothing was '
          'saved. Then tell the user what you found. The teachers listed '
          'after them were not tried.',
        );
        expect(skore.shareSaves, hasLength(2), reason: 'not sent again');
        expect(server.logins, logins);
        // It was saved: the check the result asks for finds it.
        expect(
          await sharesOf(34826),
          'readers: none | writers: Maes, Mira (teacher id 1006); Janssens, '
          'Jan (teacher id 1001); Peeters, Piet (teacher id 1002)',
        );
      });

      test('Skore answers the save as done, but the gradebook read '
          'afterwards does not show it', () async {
        skore.save = SkoreSave.unapplied;

        final (isError, text) = await share([1001], 'read');
        expect(isError, isTrue);
        expect(
          text,
          // The first teacher's save: no result to name the gradebook from
          // (dartschool#120).
          startsWith(
            'Sharing $_digitaleById in Skore with read access (they may read '
            'it) stopped at Janssens, Jan (teacher id 1001):\n'
            '- Janssens, Jan (teacher id 1001): may or may not have been '
            'shared (see below)\n'
            'Sharing $_digitaleById with Janssens, Jan (teacher id 1001) with '
            'read access may or may not have been saved',
          ),
        );
        expect(text, isNot(contains('The gradebook now')));
        expect(skore.calls, [
          ..._toolReads,
          _getCourses,
          _getTeachers,
          _saveShared,
          _getCourses,
        ]);
        expect(
          await sharesOf(34826),
          'readers: none | writers: Maes, Mira (teacher id 1006)',
        );
      });

      test('Skore answers the save with an error page', () async {
        skore.save = SkoreSave.serverError;

        final (isError, text) = await share([1001], 'read');
        expect(isError, isTrue);
        expect(
          text,
          contains(
            'Janssens, Jan (teacher id 1001) with read access may or may not '
            'have been saved: the change was sent, but Skore did not confirm '
            'it. Do not call share_skore_gradebook again for it',
          ),
        );
        expect(skore.shareSaves, hasLength(1));
      });
    });

    test('Smartschool refuses the session for the save: the library logs in '
        'again and sends the same complete save once more, which is '
        'harmless', () async {
      final logins = await loggedIn();
      server.expireSessionBefore(isShareSave);

      final (isError, text) = await share([1001], 'write');
      expect(isError, isFalse, reason: text);
      expect(server.logins, logins + 1);
      expect(
        server.requests.where(
          (request) => request == 'POST $fakeSkoreGradebooksRpcPath',
        ),
        hasLength(4),
        reason:
            "the library's read, the refused save, the save and the read "
            'after it',
      );
      expect(skore.shareSaves, [
        [
          1005,
          {'34826': <int>[]},
          {
            '34826': [1006, 1001],
          },
        ],
      ]);
      expect(
        await sharesOf(34826),
        'readers: none | writers: Maes, Mira (teacher id 1006); Janssens, Jan '
        '(teacher id 1001)',
      );
    });
  });

  group('unshare_skore_gradebook', () {
    test('stops sharing a gradebook with teachers, one after the other: the '
        'others keep theirs', () async {
      skore.shares[34826] = (readers: [1001, 1002], writers: [1006]);

      final (isError, text) = await unshare([1006, 1001]);
      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Stopped sharing $_digitale in Skore with these teachers:\n'
        '- Maes, Mira (teacher id 1006): unshared (had write access)\n'
        '- Janssens, Jan (teacher id 1001): unshared (had read access)\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'Peeters, Piet (teacher id 1002) | writers: none',
      );
      // No read of the teachers by the library: unsharing needs none.
      expect(skore.calls, [
        ..._toolReads,
        _getCourses,
        _saveShared,
        _getCourses,
        _getCourses,
        _saveShared,
        _getCourses,
      ]);
      expect(skore.shareSaves, [
        [
          1005,
          {
            '34826': [1001, 1002],
          },
          {'34826': <int>[]},
        ],
        [
          1005,
          {
            '34826': [1002],
          },
          {'34826': <int>[]},
        ],
      ]);
      expect(
        await sharesOf(34826),
        'readers: Peeters, Piet (teacher id 1002) | writers: none',
      );
    });

    test('a teacher Skore no longer lists can still be taken off', () async {
      skore.shares[34826] = (readers: [1999], writers: [1006]);

      expect(
        await ok('unshare_skore_gradebook', {
          'owner_id': 1005,
          'gradebook_id': 34826,
          'teacher_ids': [1999],
        }),
        contains('- teacher id 1999: unshared (had read access)\n'),
      );
      expect(
        await sharesOf(34826),
        'readers: none | writers: Maes, Mira (teacher id 1006)',
      );
    });

    test('the no-op: a teacher it is not shared with is reported so, and '
        'nothing is saved', () async {
      final (isError, text) = await unshare([1001]);
      expect(isError, isFalse, reason: text);
      expect(
        text,
        'Nothing changed in Skore: $_digitale was not shared with these '
        'teachers, so nothing was saved:\n'
        '- Janssens, Jan (teacher id 1001): was not shared with them; '
        'nothing saved\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'none | writers: Maes, Mira (teacher id 1006)',
      );
      expect(skore.calls, [..._toolReads, _getCourses]);
    });

    test('passes on why Skore refused a change, and saves nothing', () async {
      final (isError, owner) = await unshare([1006, 1005, 1001]);
      expect(isError, isTrue);
      expect(
        owner,
        'Unsharing $_digitale in Skore stopped at Willems, Wim (teacher id '
        '1005):\n'
        '- Maes, Mira (teacher id 1006): unshared (had write access)\n'
        '- Willems, Wim (teacher id 1005): not unshared (see below)\n'
        '- Janssens, Jan (teacher id 1001): not tried\n'
        'Skore refused the change before saving it: teacher 1005 is the '
        'owner of the gradebook, who cannot be a reader or a writer of it. '
        'Read the gradebook again with list_skore_gradebook_shares (and the '
        'teachers with list_skore_teachers) to correct the call. Nothing was '
        'saved for Willems, Wim (teacher id 1005). The teachers listed after '
        'them were not tried.\n'
        'The gradebook now:\n'
        '- Digitale vaardigheden | class 5WW1 | gradebook id 34826 | readers: '
        'none | writers: none',
      );

      final (_, notOwners) = await unshare([1001], gradebookId: 40020);
      expect(
        notOwners,
        contains(
          _refused(
            'gradebook 40020 is not one of teacher 1005 (Skore lists 1 '
                'gradebooks for them).',
            'Janssens, Jan (teacher id 1001)',
          ),
        ),
      );
      expect(skore.shareSaves, hasLength(1));
    });

    test('a save Skore does not confirm: what to read to check it', () async {
      skore.save = SkoreSave.answerLost;

      final (isError, text) = await unshare([1006]);
      expect(isError, isTrue);
      expect(
        text,
        'Unsharing $_digitaleById in Skore stopped at Maes, Mira (teacher id '
        '1006):\n'
        '- Maes, Mira (teacher id 1006): may or may not have been unshared '
        '(see below)\n'
        'Unsharing $_digitaleById with Maes, Mira (teacher id 1006) may or '
        'may not have been saved: the change was sent, but Skore did not '
        'confirm it. Do not call unshare_skore_gradebook again for it: first '
        'read the gradebooks with list_skore_gradebook_shares (teacher_id '
        '1005): when gradebook 34826 no longer lists teacher id 1006 among its '
        'readers or writers, it was saved; when it still does, nothing was '
        'saved. Then tell the user what you found.',
      );
      expect(skore.shareSaves, hasLength(1));
      expect(await sharesOf(34826), 'readers: none | writers: none');
    });
  });

  test('the flow of the issue: the class, its courses, the assignment of '
      'the titularis, then share it with the other teachers of the class, '
      'and read it back', () async {
    expect(
      await ok('list_skore_classes', {'query': '5WW1'}),
      contains('5WW1 | class id 2516'),
    );
    final courses = await ok('list_skore_courses', {'class_id': 2516});
    expect(
      courses,
      contains(
        'Digitale vaardigheden [Digitale vaardigheden] | course id 1588 | '
        'code Digitale vaardigheden | depth 1 | teacher: Willems, Wim '
        '(teacher id 1005, assignment 34826)',
      ),
    );
    final others = {
      for (final match in RegExp(r'teacher id (\d+)').allMatches(courses))
        int.parse(match.group(1)!),
    }..remove(1005);
    expect(others, {1001, 1002, 1003, 1004});

    expect(
      await sharesOf(34826),
      'readers: none | writers: Maes, Mira (teacher id 1006)',
    );
    await ok('share_skore_gradebook', {
      'owner_id': 1005,
      'gradebook_id': 34826,
      'teacher_ids': others.toList(),
      'access': 'read',
    });
    expect(
      await sharesOf(34826),
      'readers: Janssens, Jan (teacher id 1001); Peeters, Piet (teacher id '
      "1002); Dupré, Céline (teacher id 1003); D'Hondt, Karel (teacher id "
      '1004) | writers: Maes, Mira (teacher id 1006)',
    );
    expect(skore.shareSaves, hasLength(4));
  });
}
