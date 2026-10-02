/// `mark_messages`, called over MCP on the real server, session and library,
/// against a fake Smartschool.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/mark_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/message_changes.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _inboxListing =
    'message list boxID=0 boxType=inbox layout=new poll=false poll_ids= '
    'sortField=date sortKey=desc';
const _archiveListing =
    'message list boxID=305 boxType=inbox layout=new poll=false poll_ids= '
    'sortField=date sortKey=desc';
const _nextInboxPage = 'continue_messages boxID=0 boxType=inbox layout=new';

String _read(int id) =>
    'mark message read boxType=inbox limitList=true msgID=$id';
String _unread(int id, {int box = 0}) =>
    'mark message unread boxID=$box boxType=inbox clAction=status msgID=$id';

const _header101 =
    'id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact donderdag';
const _header102 =
    'id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde';
const _header103 =
    'id 103 | 2024-03-13 10:30 | from Secretariaat | Verlofaanvraag';
const _header201 =
    'id 201 | 2024-02-20 12:00 | from Directie | Personeelsvergadering';

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
      subject: 'Verlofaanvraag',
      date: '2024-03-13 10:30',
      unread: true,
    ),
  ]);
  mailbox.archive.add(
    FakeMessage(
      id: 201,
      sender: 'Directie',
      subject: 'Personeelsvergadering',
      date: '2024-02-20 12:00',
    ),
  );
  mailbox.sent.add(
    FakeMessage(
      id: 301,
      sender: 'Jan Peeters',
      listedAs: 'Els Wouters',
      subject: 'Uitstap',
      date: '2024-03-12 11:00',
    ),
  );
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
      tools: [listMessagesTool(session), markMessagesTool(session)],
    );
  });

  Future<(CallToolResult, String)> mark(
    List<Object?> ids, {
    required bool read,
    String? box,
  }) => callTool(connection, 'mark_messages', {
    'message_ids': ids,
    'read': read,
    'box': ?box,
  });

  /// Calls mark_messages and expects a result that is not an error.
  Future<String> ok(
    List<Object?> ids, {
    required bool read,
    String? box,
  }) async {
    final (result, text) = await mark(ids, read: read, box: box);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  test('is listed as a write that is neither destructive nor read-only, is '
      'idempotent, says that reading does not mark, and refuses the sent '
      'box', () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == 'mark_messages');

    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isFalse);
    expect(annotations.destructiveHint, isFalse);
    expect(annotations.idempotentHint, isTrue);
    expect(
      tool.description,
      contains(
        'Reading a message with read_message does not mark it as read; this '
        'tool does.',
      ),
    );
    expect(tool.description, contains('do not mark anything'));
    expect(tool.description, contains('propose a list'));
    expect(tool.description, contains('sent messages have no read state'));

    final schema = tool.inputSchema;
    expect(schema.required, ['message_ids', 'read']);
    expect(schema.properties!.keys, ['message_ids', 'read', 'box']);
    expect(schema.properties!['message_ids'], {
      'type': 'array',
      'description': isA<String>(),
      'items': {'type': 'integer', 'minimum': 1},
      'minItems': 1,
      'maxItems': maxMessageIds,
    });
    expect(schema.properties!['read'], {
      'type': 'boolean',
      'description': isA<String>(),
    });
    expect(schema.properties!['box'], {
      'type': 'string',
      'description': isA<String>(),
      'default': 'inbox',
      'enum': ['inbox', 'archive'],
    });
  });

  test('marks inbox messages as read, after which list_messages shows them '
      'read', () async {
    expect(
      await ok([101, 103], read: true),
      'Marked 2 messages as read.\n'
      'Marked as read:\n'
      '- $_header101 | attachments, flag red\n'
      '- $_header103',
    );
    expect(server.mailbox.actions, [_inboxListing, _read(101), _read(103)]);

    final (_, unread) = await callTool(connection, 'list_messages', {
      'unread_only': true,
    });
    expect(
      unread,
      'Inbox: no messages match the filters (3 messages checked).',
    );
  });

  test('marks inbox messages as unread, after which list_messages shows them '
      'unread', () async {
    expect(
      await ok([102], read: false),
      'Marked 1 message as unread.\n'
      'Marked as unread:\n'
      '- $_header102 | unread',
    );
    expect(server.mailbox.actions, [_inboxListing, _unread(102)]);

    final (_, inbox) = await callTool(connection, 'list_messages');
    expect(inbox, contains('- $_header102 | unread\n'));
  });

  test('in the archive: marking unread names the archive folder, marking '
      'read the inbox box type, and list_messages on the archive shows '
      'each', () async {
    expect(
      await ok([201], read: false, box: 'archive'),
      'Marked 1 message as unread.\n'
      'Marked as unread:\n'
      '- $_header201 | unread',
    );
    expect(server.mailbox.actions, [_archiveListing, _unread(201, box: 305)]);
    final (_, unread) = await callTool(connection, 'list_messages', {
      'box': 'archive',
    });
    expect(unread, 'Archive: 1 message, newest first.\n- $_header201 | unread');

    server.mailbox.actions.clear();
    expect(
      await ok([201], read: true, box: 'archive'),
      'Marked 1 message as read.\nMarked as read:\n- $_header201',
    );
    expect(server.mailbox.actions, [_archiveListing, _read(201)]);
    final (_, read) = await callTool(connection, 'list_messages', {
      'box': 'archive',
    });
    expect(read, 'Archive: 1 message, newest first.\n- $_header201');
  });

  test('marking again is not an error: Smartschool confirms the state the '
      'message already has', () async {
    await ok([101], read: true);

    expect(
      await ok([101, 102], read: true),
      startsWith('Marked 2 messages as read.\n'),
    );
  });

  test('reports per id: marked, and not in the box; only ids in the box are '
      'sent to Smartschool, once each', () async {
    final text = await ok([999, 201, 103, 103.0, 301], read: true);

    expect(
      text,
      'Marked 1 of 4 messages as read; 3 could not be marked.\n'
      'Marked as read:\n'
      '- $_header103\n'
      'Not marked, not in the inbox:\n'
      '- id 999\n'
      '- id 201\n'
      '- id 301\n'
      'Note: the messages under "Not marked, not in the inbox" are not in '
      'the inbox. Take the ids from list_messages on the box the messages '
      'are in, and pass that box.',
    );
    expect(server.mailbox.actions, [_inboxListing, _read(103)]);
  });

  test('an answer without the message (null) or with another state: not '
      'confirmed, shown as listed, with what to do', () async {
    server.mailbox
      ..refuseToChange.add(101)
      ..keepUnchanged.add(103);

    final text = await ok([101, 102, 103], read: true);

    expect(
      text,
      'Marked 1 of 3 messages as read; 2 could not be marked.\n'
      'Marked as read:\n'
      '- $_header102\n'
      'Not marked, Smartschool did not confirm it:\n'
      '- $_header101 | unread, attachments, flag red\n'
      '- $_header103 | unread\n'
      'Note: Smartschool did not confirm the change of the messages under '
      '"Not marked, Smartschool did not confirm it"; they are shown as they '
      'were before. Check with list_messages (box inbox) whether they '
      'changed, then try again or let the user change them in Smartschool.',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _read(101),
      _read(102),
      _read(103),
    ]);
  });

  test('when no message is marked, the result is an error', () async {
    server.mailbox.refuseToChange.add(103);

    final (notConfirmed, _) = await mark([103], read: true);
    final (notInBox, text) = await mark([999], read: false, box: 'archive');

    expect(notConfirmed.isError, isTrue);
    expect(notInBox.isError, isTrue);
    expect(
      text,
      'Marked 0 of 1 message as unread; 1 could not be marked.\n'
      'Not marked, not in the archive:\n'
      '- id 999\n'
      'Note: the messages under "Not marked, not in the archive" are not in '
      'the archive. Take the ids from list_messages on the box the messages '
      'are in, and pass that box.',
    );
  });

  test('an id older than the newest 50 inbox messages: lists the inbox page '
      'by page until it finds every id, and marks it', () async {
    server.mailbox.inbox.addAll(
      hourlyMessages(120, firstId: 1000, newest: '2024-04-30 18:00'),
    );

    expect(
      await ok([1000, 103], read: true),
      startsWith('Marked 2 messages as read.\n'),
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _nextInboxPage,
      _nextInboxPage,
      _read(1000),
      _read(103),
    ]);
  });

  test('the session expires at a mark request: logs in again and marks the '
      'message once', () async {
    await callTool(connection, 'list_messages');
    server.mailbox.actions.clear();
    server.expireSessionBefore(
      (request) => '${request.data}'.contains('mark message read'),
    );

    expect(
      await ok([103], read: true),
      'Marked 1 message as read.\nMarked as read:\n- $_header103',
    );
    expect(server.logins, 2);
    expect(server.mailbox.actions, [_inboxListing, _read(103)]);
  });

  group('invalid arguments are errors that say what to fix, and nothing is '
      'sent to Smartschool', () {
    final cases = <String, (Map<String, Object?>, String)>{
      'the sent box': (
        {
          'message_ids': [301],
          'read': true,
          'box': 'sent',
        },
        'inbox, archive',
      ),
      'no read': (
        {
          'message_ids': [101],
        },
        'read',
      ),
      'read as a word': (
        {
          'message_ids': [101],
          'read': 'yes',
        },
        'read',
      ),
      'no message_ids': ({'read': true}, 'message_ids'),
      'more than 100 ids': (
        {
          'message_ids': [for (var i = 1; i <= 101; i++) i],
          'read': true,
        },
        'List has 101 items',
      ),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in cases.entries) {
      test(name, () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'mark_messages', arguments: arguments),
        );

        expect(result.isError, isTrue);
        final text = result.content
            .map((c) => (c as TextContent).text)
            .join('\n');
        expect(text, contains(message));
        expect(server.requests, isEmpty);
      });
    }
  });
}
