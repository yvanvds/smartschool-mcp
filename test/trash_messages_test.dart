/// `trash_messages`, called over MCP on the real server, session and library,
/// against a fake Smartschool.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/message_changes.dart';
import 'package:smartschool_mcp/src/tools/trash_messages_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _inboxListing =
    'message list boxID=0 boxType=inbox layout=new poll=false poll_ids= '
    'sortField=date sortKey=desc';
const _sentListing =
    'message list boxID=0 boxType=outbox layout=new poll=false poll_ids= '
    'sortField=date sortKey=desc';
const _archiveListing =
    'message list boxID=305 boxType=inbox layout=new poll=false poll_ids= '
    'sortField=date sortKey=desc';

/// The move of message [id] out of the box [boxType] (its folder [box]) to
/// the trash, as the fake records it.
String _move(int id, {String boxType = 'inbox', int box = 0}) =>
    'quickmove messages boxID=$box boxType=$boxType msgID=$id toBoxID=0 '
    'toBoxType=trash';

/// The check after a move: message [id] read from the box [boxType].
String _show(int id, {String boxType = 'inbox'}) =>
    'show message boxType=$boxType limitList=true msgID=$id';

const _line101 =
    'id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact donderdag | '
    'unread, attachments, flag red';
const _header102 =
    'id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde';
const _line103 =
    'id 103 | 2024-03-13 10:30 | from Secretariaat | Nieuwsbrief maart | '
    'unread';
const _header201 =
    'id 201 | 2024-02-20 12:00 | from Directie | Personeelsvergadering';
const _header301 = 'id 301 | 2024-03-12 11:00 | to Els Wouters | Uitstap';

/// Message 401, which the user sent to themselves: the same id in the inbox
/// and in the sent box.
const _inbox401 =
    'id 401 | 2024-03-11 09:00 | from Jan Peeters | Notitie voor mezelf';
const _sent401 =
    'id 401 | 2024-03-11 09:00 | to Jan Peeters | Notitie voor mezelf';

FakeMessage _note() => FakeMessage(
  id: 401,
  sender: fakeDisplayName,
  listedAs: fakeDisplayName,
  subject: 'Notitie voor mezelf',
  date: '2024-03-11 09:00',
  to: [fakeDisplayName],
);

void _fill(FakeMailbox mailbox) {
  mailbox.inbox.addAll([
    FakeMessage(
      id: 101,
      sender: 'Jan Peeters',
      subject: 'Oudercontact donderdag',
      date: '2024-03-14 16:05',
      unread: true,
      flag: 3,
      attachments: [FakeAttachment('Planning.pdf', '12 KiB')],
    ),
    FakeMessage(
      id: 102,
      sender: 'An Claes',
      subject: 'Re: Toets wiskunde',
      date: '2024-03-15 08:00',
    ),
    FakeMessage(
      id: 103,
      sender: 'Secretariaat',
      subject: 'Nieuwsbrief maart',
      date: '2024-03-13 10:30',
      unread: true,
    ),
    _note(),
  ]);
  mailbox.archive.add(
    FakeMessage(
      id: 201,
      sender: 'Directie',
      subject: 'Personeelsvergadering',
      date: '2024-02-20 12:00',
    ),
  );
  mailbox.sent.addAll([
    FakeMessage(
      id: 301,
      sender: 'Jan Peeters',
      listedAs: 'Els Wouters',
      subject: 'Uitstap',
      date: '2024-03-12 11:00',
    ),
    _note(),
  ]);
}

void main() {
  late FakeSmartschool server;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    _fill(server.mailbox);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [listMessagesTool(session), trashMessagesTool(session)],
    );
  });

  Future<(CallToolResult, String)> trash(List<Object?> ids, {String? box}) =>
      callTool(connection, 'trash_messages', {'message_ids': ids, 'box': ?box});

  /// Calls trash_messages and expects a result that is not an error.
  Future<String> ok(List<Object?> ids, {String? box}) async {
    final (result, text) = await trash(ids, box: box);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> list([String box = 'inbox']) async =>
      (await callTool(connection, 'list_messages', {'box': box})).$2;

  List<int> trashed() => [for (final m in server.mailbox.trash) m.id];

  test('is listed as destructive and not idempotent, says the trash can be '
      'restored in Smartschool but not by this tool, and tells Claude to '
      "wait for the user's confirmation of the list", () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == 'trash_messages');

    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isFalse);
    expect(annotations.destructiveHint, isTrue);
    expect(annotations.idempotentHint, isFalse);
    expect(annotations.openWorldHint, isTrue);
    final description = tool.description!;
    expect(description, contains('a move, not a deletion'));
    expect(
      description,
      contains(
        'the user can restore a message from the trash in Smartschool '
        'itself, as long as the trash has not been emptied',
      ),
    );
    expect(
      description,
      contains('cannot take a message out of the trash again'),
    );
    expect(
      description,
      contains('after the user has explicitly confirmed that list'),
    );
    expect(description, contains('do not move anything'));
    expect(description, contains('propose a list'));
    expect(
      description,
      contains('the same id in the inbox and in the sent box'),
    );
    expect(description, contains('moves only the copy in the box passed'));

    final schema = tool.inputSchema;
    expect(schema.required, ['message_ids']);
    expect(schema.properties!.keys, ['message_ids', 'box']);
    expect(schema.properties!['message_ids'], {
      'type': 'array',
      'description': isA<String>(),
      'items': {'type': 'integer', 'minimum': 1},
      'minItems': 1,
      'maxItems': maxMessageIds,
    });
    expect(schema.properties!['box'], {
      'type': 'string',
      'description': isA<String>(),
      'default': 'inbox',
      'enum': ['inbox', 'sent', 'archive'],
    });
  });

  test('moves inbox messages to the trash, one at a time, checking each '
      'afterwards; list_messages no longer shows them', () async {
    expect(
      await ok([101, 103]),
      'Moved 2 messages from the inbox to the trash.\n'
      'Moved to the trash:\n'
      '- $_line101\n'
      '- $_line103',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _move(101),
      _show(101),
      _move(103),
      _show(103),
    ]);
    expect(trashed(), [101, 103]);
    expect(
      await list(),
      'Inbox: 2 messages, newest first.\n- $_header102\n- $_inbox401',
    );
  });

  test('moves a message of the sent box out of the sent box', () async {
    expect(
      await ok([301], box: 'sent'),
      'Moved 1 message from the sent box to the trash.\n'
      'Moved to the trash:\n'
      '- $_header301',
    );
    expect(server.mailbox.actions, [
      _sentListing,
      _move(301, boxType: 'outbox'),
      _show(301, boxType: 'outbox'),
    ]);
    expect(trashed(), [301]);
    expect(await list('sent'), 'Sent: 1 message, newest first.\n- $_sent401');
  });

  test('moves a message of the archive out of the archive folder: the inbox '
      "box type with the archive's box id", () async {
    expect(
      await ok([201], box: 'archive'),
      'Moved 1 message from the archive to the trash.\n'
      'Moved to the trash:\n'
      '- $_header201',
    );
    expect(server.mailbox.actions, [
      _archiveListing,
      _move(201, box: 305),
      _show(201),
    ]);
    expect(trashed(), [201]);
    expect(await list('archive'), 'Archive: no messages.');
  });

  test('a message the user sent to themselves: moving the sent-box copy '
      'leaves the inbox copy in the inbox, and the other way round', () async {
    expect(
      await ok([401], box: 'sent'),
      'Moved 1 message from the sent box to the trash.\n'
      'Moved to the trash:\n'
      '- $_sent401',
    );
    expect(await list(), contains('\n- $_inbox401'));
    expect(trashed(), [401]);

    expect(
      await ok([401]),
      'Moved 1 message from the inbox to the trash.\n'
      'Moved to the trash:\n'
      '- $_inbox401',
    );
    expect(await list(), isNot(contains('id 401')));
    expect(await list('sent'), isNot(contains('id 401')));
    expect(trashed(), [401, 401]);
    expect(server.mailbox.actions.where((a) => a.startsWith('quickmove')), [
      _move(401, boxType: 'outbox'),
      _move(401),
    ]);
  });

  test('reports per id: moved, and not in the box; only ids found in the box '
      'are moved, once each', () async {
    final text = await ok([999, 201, 103, 103.0, 301]);

    expect(
      text,
      'Moved 1 of 4 messages from the inbox to the trash; 3 could not be '
      'moved.\n'
      'Moved to the trash:\n'
      '- $_line103\n'
      'Not moved, not in the inbox:\n'
      '- id 999\n'
      '- id 201\n'
      '- id 301\n'
      'Note: the messages under "Not moved, not in the inbox" are not in '
      'the inbox. Take the ids from list_messages on the box the messages '
      'are in, and pass that box.',
    );
    expect(server.mailbox.actions, [_inboxListing, _move(103), _show(103)]);
    expect(trashed(), [103]);
    expect(server.mailbox.archive.map((m) => m.id), [201]);
    expect(server.mailbox.sent.map((m) => m.id), [301, 401]);
  });

  test('a move that did not take effect: the check afterwards finds the '
      'message still in the box, whatever Smartschool answered', () async {
    server.mailbox.refuseToTrash.add(101);

    expect(
      await ok([101, 102]),
      'Moved 1 of 2 messages from the inbox to the trash; 1 could not be '
      'moved.\n'
      'Moved to the trash:\n'
      '- $_header102\n'
      'Not moved, still in the inbox:\n'
      '- $_line101\n'
      'Note: the messages under "Not moved, still in the inbox" were still '
      'in the inbox after the move to the trash. Check with list_messages '
      '(box inbox) whether they are still there, then try again or let the '
      'user move them to the trash in Smartschool.',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _move(101),
      _show(101),
      _move(102),
      _show(102),
    ]);
    expect(trashed(), [102]);
    expect(await list(), contains('\n- $_line101\n'));
  });

  test('when no message is moved, the result is an error', () async {
    server.mailbox.refuseToTrash.add(201);

    final (notMoved, notMovedText) = await trash([201], box: 'archive');
    final (notInBox, notInBoxText) = await trash([999], box: 'sent');

    expect(notMoved.isError, isTrue);
    expect(
      notMovedText,
      startsWith(
        'Moved 0 of 1 message from the archive to the trash; 1 could not be '
        'moved.\n'
        'Not moved, still in the archive:\n'
        '- $_header201\n',
      ),
    );
    expect(notInBox.isError, isTrue);
    expect(
      notInBoxText,
      startsWith(
        'Moved 0 of 1 message from the sent box to the trash; 1 could not be '
        'moved.\n'
        'Not moved, not in the sent box:\n'
        '- id 999\n',
      ),
    );
    expect(trashed(), isEmpty);
  });

  test('moves only with quickmove messages, never with a quick delete, from '
      'each box', () async {
    await ok([101]);
    await ok([301, 401], box: 'sent');
    await ok([201], box: 'archive');
    await ok([401]);

    expect(trashed(), [101, 301, 401, 201, 401]);
    final actions = server.mailbox.actions;
    expect(actions.where((a) => a.startsWith('quickmove messages ')), [
      _move(101),
      _move(301, boxType: 'outbox'),
      _move(401, boxType: 'outbox'),
      _move(201, box: 305),
      _move(401),
    ]);
    for (final action in actions) {
      expect(
        action,
        anyOf(
          startsWith('message list '),
          startsWith('quickmove messages '),
          startsWith('show message '),
        ),
      );
    }
  });

  test('the server never calls moveToTrash, whose quick delete names no box '
      'and deletes a copy in the trash for good (yvanvds/dartschool#19, '
      '#61)', () {
    final sources = [
      for (final folder in ['lib', 'bin'])
        ...Directory(folder)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];
    expect(sources, isNotEmpty);
    final call = RegExp(r'\.moveToTrash\s*\(');
    for (final file in sources) {
      expect(file.readAsStringSync(), isNot(matches(call)), reason: file.path);
    }
    expect(
      File('lib/src/tools/trash_messages_tool.dart').readAsStringSync(),
      contains('moveToTrashFrom('),
    );
  });

  group('the session expires', () {
    test('at a move: logs in again and moves the message once', () async {
      await list();
      server.mailbox.actions.clear();
      server.expireSessionBefore(
        (request) => '${request.data}'.contains('quickmove messages'),
      );

      expect(
        await ok([103]),
        'Moved 1 message from the inbox to the trash.\n'
        'Moved to the trash:\n'
        '- $_line103',
      );
      expect(server.logins, 2);
      expect(server.mailbox.actions, [_inboxListing, _move(103), _show(103)]);
      expect(trashed(), [103]);
    });

    test('at the move of the second message, and Smartschool refuses it also '
        'after logging in again: the call is repeated, reports the first '
        'message as moved, not as not in the inbox, and moves each message '
        'once', () async {
      await list();
      server.mailbox.actions.clear();
      server
        ..expireSessionBefore(
          (request) =>
              '${request.data}'.contains('quickmove messages') &&
              '${request.data}'.contains('<![CDATA[103]]>'),
        )
        ..rejectsAfterLogin = 1;

      expect(
        await ok([101, 103]),
        'Moved 2 messages from the inbox to the trash.\n'
        'Moved to the trash:\n'
        '- $_line101\n'
        '- $_line103',
      );
      expect(server.logins, 2);
      // The repeat lists the inbox no more: it checks the message moved
      // before, and moves the one whose move was refused.
      expect(server.mailbox.actions, [
        _inboxListing,
        _move(101),
        _show(101),
        _show(101),
        _move(103),
        _show(103),
      ]);
      expect(trashed(), [101, 103]);
    });

    test('at the check after a move, also after logging in again: the call '
        'is repeated, checks the message again and does not move it '
        'again', () async {
      await list();
      server.mailbox.actions.clear();
      server
        ..expireSessionBefore(
          (request) => '${request.data}'.contains('show message'),
        )
        ..rejectsAfterLogin = 1;

      expect(
        await ok([101]),
        'Moved 1 message from the inbox to the trash.\n'
        'Moved to the trash:\n'
        '- $_line101',
      );
      expect(server.logins, 2);
      expect(server.mailbox.actions, [_inboxListing, _move(101), _show(101)]);
      expect(trashed(), [101]);
    });
  });

  group('invalid arguments are errors that say what to fix, and nothing is '
      'sent to Smartschool', () {
    final cases = <String, (Map<String, Object?>, String)>{
      'the trash as the box': (
        {
          'message_ids': [101],
          'box': 'trash',
        },
        '"trash" is not one of the allowed values',
      ),
      'no message_ids': (const {}, 'message_ids'),
      'an empty list': ({'message_ids': <int>[]}, 'at least 1'),
      'an id of 0': (
        {
          'message_ids': [0],
        },
        'message_ids',
      ),
      'more than 100 ids': (
        {
          'message_ids': [for (var i = 1; i <= 101; i++) i],
        },
        'List has 101 items',
      ),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in cases.entries) {
      test(name, () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'trash_messages', arguments: arguments),
        );

        expect(result.isError, isTrue);
        final text = result.content
            .map((c) => (c as TextContent).text)
            .join('\n');
        expect(text, contains(message));
        expect(server.requests, isEmpty);
        expect(trashed(), isEmpty);
      });
    }
  });
}
