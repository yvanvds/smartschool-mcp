/// `archive_messages`, called over MCP on the real server, session and
/// library, against a fake Smartschool.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/archive_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
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
const _nextArchivePage = 'continue_messages boxID=305 boxType=inbox layout=new';

const _line101 =
    '- id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact donderdag '
    '| unread, attachments, flag red';
const _line102 =
    '- id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde';
const _line103 =
    '- id 103 | 2024-03-13 10:30 | from Secretariaat | Verlofaanvraag | unread';
const _line201 =
    '- id 201 | 2024-02-20 12:00 | from Directie | Personeelsvergadering';

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

List<int> _ids(List<FakeMessage> box) => [for (final m in box) m.id];

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
      tools: [listMessagesTool(session), archiveMessagesTool(session)],
    );
  });

  Future<(CallToolResult, String)> archive(List<Object?> ids) =>
      callTool(connection, 'archive_messages', {'message_ids': ids});

  /// Calls archive_messages and expects a result that is not an error.
  Future<String> ok(List<Object?> ids) async {
    final (result, text) = await archive(ids);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  test('is listed as a write that is neither destructive nor read-only, is '
      'idempotent, and tells Claude when to propose and when to '
      'archive', () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == 'archive_messages');

    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isFalse);
    expect(annotations.destructiveHint, isFalse);
    expect(annotations.idempotentHint, isTrue);
    expect(tool.description, contains('Wat kan ik zeker archiveren?'));
    expect(tool.description, contains('do not archive anything'));
    expect(tool.description, contains('propose a list'));
    expect(tool.description, contains('from list_messages'));
    expect(tool.description, isNot(contains('newest 50')));

    final schema = tool.inputSchema;
    expect(schema.required, ['message_ids']);
    expect(schema.properties!.keys, ['message_ids']);
    expect(schema.properties!['message_ids'], {
      'type': 'array',
      'description': isA<String>(),
      'items': {'type': 'integer', 'minimum': 1},
      'minItems': 1,
      'maxItems': maxArchiveIds,
    });
    expect(maxArchiveIds, 100);
  });

  test('moves inbox messages to the archive, where list_messages shows '
      'them', () async {
    expect(
      await ok([101, 103]),
      'Archived 2 messages.\n'
      'Archived:\n'
      '$_line101\n'
      '$_line103',
    );
    expect(server.mailbox.actions, [_inboxListing, 'archive msgIDs=101,103']);
    expect(_ids(server.mailbox.inbox), [102]);

    final (_, archived) = await callTool(connection, 'list_messages', {
      'box': 'archive',
    });
    expect(archived, startsWith('Archive: 3 messages, newest first.\n'));
    expect(archived, contains('- id 101 | '));
    expect(archived, contains('- id 103 | '));
    final (_, inbox) = await callTool(connection, 'list_messages');
    expect(inbox, 'Inbox: 1 message, newest first.\n$_line102');
  });

  test('reports per id: archived, already in the archive, and not in the '
      'inbox; only inbox ids are sent to Smartschool', () async {
    final text = await ok([999, 201, 102, 301]);

    expect(
      text,
      'Archived 1 of 4 messages; 1 was already in the archive, 2 could not '
      'be archived.\n'
      'Archived:\n'
      '$_line102\n'
      'Already in the archive:\n'
      '$_line201\n'
      'Not archived, not in the inbox:\n'
      '- id 999\n'
      '- id 301\n'
      'Note: only messages in the inbox can be archived. Take the ids from '
      'list_messages on the inbox.',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _archiveListing,
      'archive msgIDs=102',
    ]);
    expect(_ids(server.mailbox.sent), [301]);
  });

  test('archiving again is not an error: the messages are already in the '
      'archive', () async {
    await ok([101, 103]);
    server.mailbox.actions.clear();

    expect(
      await ok([103, 101]),
      'Archived 0 of 2 messages; 2 were already in the archive.\n'
      'Already in the archive:\n'
      '$_line103\n'
      '$_line101',
    );
    expect(server.mailbox.actions, [_inboxListing, _archiveListing]);
  });

  test('when nothing can be archived, the result is an error', () async {
    final (result, text) = await archive([999]);

    expect(result.isError, isTrue);
    expect(
      text,
      'Archived 0 of 1 message; 1 could not be archived.\n'
      'Not archived, not in the inbox:\n'
      '- id 999\n'
      'Note: only messages in the inbox can be archived. Take the ids from '
      'list_messages on the inbox.',
    );
    expect(server.mailbox.actions, [_inboxListing, _archiveListing]);
  });

  test('an id older than the newest 50 inbox messages: lists the inbox page '
      'by page until it finds every id, and archives it', () async {
    server.mailbox.inbox.addAll(
      hourlyMessages(120, firstId: 1000, newest: '2024-04-30 18:00'),
    );
    // Message 103 is the oldest of 123, on the third page of 50.

    expect(await ok([103]), 'Archived 1 message.\nArchived:\n$_line103');
    expect(server.mailbox.actions, [
      _inboxListing,
      _nextInboxPage,
      _nextInboxPage,
      'archive msgIDs=103',
    ]);
    expect(_ids(server.mailbox.archive), contains(103));

    server.mailbox.actions.clear();
    expect(await ok([1001]), startsWith('Archived 1 message.\n'));
    expect(server.mailbox.actions, [_inboxListing, 'archive msgIDs=1001']);
  });

  test('an id in neither box: both are listed to the end', () async {
    server.mailbox
      ..inbox.addAll(
        hourlyMessages(60, firstId: 1000, newest: '2024-04-30 18:00'),
      )
      ..archive.addAll(
        hourlyMessages(60, firstId: 2000, newest: '2024-01-31 18:00'),
      );

    final (result, text) = await archive([999]);

    expect(result.isError, isTrue);
    expect(text, contains('Not archived, not in the inbox:\n- id 999\n'));
    expect(server.mailbox.actions, [
      _inboxListing,
      _nextInboxPage,
      _archiveListing,
      _nextArchivePage,
    ]);
  });

  test('an id already in the archive, older than its newest 50: found '
      'there', () async {
    server.mailbox.archive.addAll(
      hourlyMessages(60, firstId: 2000, newest: '2024-03-31 18:00'),
    );

    expect(
      await ok([201]),
      'Archived 0 of 1 message; 1 was already in the archive.\n'
      'Already in the archive:\n'
      '$_line201',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _archiveListing,
      _nextArchivePage,
    ]);
  });

  test('an id Smartschool does not confirm is reported per id', () async {
    server.mailbox.refuseToArchive.add(103);

    final text = await ok([101, 103]);

    expect(
      text,
      'Archived 1 of 2 messages; 1 could not be archived.\n'
      'Archived:\n'
      '$_line101\n'
      'Not archived, Smartschool did not confirm it:\n'
      '$_line103\n'
      'Note: Smartschool did not confirm that it archived the messages under '
      '"Not archived, Smartschool did not confirm it". Check with '
      'list_messages whether they are still in the inbox, then try again or '
      'let the user archive them in Smartschool.',
    );
    expect(server.mailbox.actions.last, 'archive msgIDs=101,103');

    // Only that id, and nothing archived: an error.
    final (result, _) = await archive([103]);
    expect(result.isError, isTrue);
  });

  test('duplicate ids are archived once, also when one is written as a '
      'decimal', () async {
    expect(
      await ok([101, 101.0, 103.0]),
      'Archived 2 messages.\nArchived:\n$_line101\n$_line103',
    );
    expect(server.mailbox.actions.last, 'archive msgIDs=101,103');
  });

  group('the session expires', () {
    test('at the archive request: logs in again and archives once', () async {
      await callTool(connection, 'list_messages');
      server.mailbox.actions.clear();
      server.expireSessionBefore(
        (request) => request.uri.path == FakeMailbox.archivePath,
      );

      expect(await ok([101]), 'Archived 1 message.\nArchived:\n$_line101');
      expect(server.logins, 2);
      expect(
        server.requests.where((r) => r.endsWith(FakeMailbox.archivePath)),
        hasLength(2),
        reason:
            'the first archive request is refused; the library retries it '
            'after logging in again',
      );
      expect(server.mailbox.actions, [_inboxListing, 'archive msgIDs=101']);
    });

    test('at the archive listing, and Smartschool refuses it also after '
        'logging in again: the call is repeated before anything was '
        'archived, and reports the message as archived, not as already '
        'there', () async {
      await callTool(connection, 'list_messages');
      server.mailbox.actions.clear();
      server
        ..expireSessionBefore(
          (request) => '${request.data}'.contains('<![CDATA[305]]>'),
        )
        ..rejectsAfterLogin = 1;

      final text = await ok([101, 999]);

      expect(
        text,
        startsWith(
          'Archived 1 of 2 messages; 1 could not be archived.\n'
          'Archived:\n'
          '$_line101\n'
          'Not archived, not in the inbox:\n'
          '- id 999\n',
        ),
      );
      expect(server.logins, 2);
      expect(server.mailbox.actions, [
        _inboxListing,
        _inboxListing,
        _archiveListing,
        'archive msgIDs=101',
      ]);
    });
  });

  group('invalid arguments are errors that say what to fix, and nothing is '
      'sent to Smartschool', () {
    final cases = <String, (Map<String, Object?>, String)>{
      'no message_ids': (const {}, 'message_ids'),
      'an empty list': ({'message_ids': <int>[]}, 'at least 1'),
      'more than 100 ids': (
        {
          'message_ids': [for (var i = 1; i <= 101; i++) i],
        },
        'List has 101 items',
      ),
      'an id that is not a number': (
        {
          'message_ids': [101, 'abc'],
        },
        'message_ids',
      ),
      'an id of 0': (
        {
          'message_ids': [0],
        },
        'message_ids',
      ),
      'a single id instead of a list': ({'message_ids': 101}, 'message_ids'),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in cases.entries) {
      test(name, () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'archive_messages', arguments: arguments),
        );

        expect(result.isError, isTrue);
        final text = result.content
            .map((c) => (c as TextContent).text)
            .join('\n');
        expect(text, contains(message));
        expect(server.requests, isEmpty);
        expect(_ids(server.mailbox.inbox), [101, 102, 103]);
      });
    }
  });
}
