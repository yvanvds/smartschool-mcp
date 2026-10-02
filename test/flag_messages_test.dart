/// `flag_messages`, called over MCP on the real server, session and library,
/// against a fake Smartschool.
library;

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/message_format.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/flag_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/message_changes.dart';
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

String _label(int id, int label, {String boxType = 'inbox'}) =>
    'save msglabel boxType=$boxType clAction=label msgID=$id msgLabel=$label';

const _header101 =
    'id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact donderdag';
const _header102 =
    'id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde';
const _header201 =
    'id 201 | 2024-02-20 12:00 | from Directie | Personeelsvergadering';
const _header301 = 'id 301 | 2024-03-12 11:00 | to Els Wouters | Uitstap';

void _fill(FakeMailbox mailbox) {
  mailbox.inbox.addAll([
    FakeMessage(
      id: 101,
      sender: 'Jan Peeters',
      subject: 'Oudercontact donderdag',
      date: '2024-03-14 16:05',
      unread: true,
      flag: 3,
    ),
    FakeMessage(
      id: 102,
      sender: 'An Claes',
      subject: 'Re: Toets wiskunde',
      date: '2024-03-15 08:00',
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
      tools: [listMessagesTool(session), flagMessagesTool(session)],
    );
  });

  Future<(CallToolResult, String)> flag(
    List<Object?> ids,
    String flag, {
    String? box,
  }) => callTool(connection, 'flag_messages', {
    'message_ids': ids,
    'flag': flag,
    'box': ?box,
  });

  /// Calls flag_messages and expects a result that is not an error.
  Future<String> ok(List<Object?> ids, String name, {String? box}) async {
    final (result, text) = await flag(ids, name, box: box);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> list([String box = 'inbox']) async =>
      (await callTool(connection, 'list_messages', {'box': box})).$2;

  test('takes the flag names list_messages shows, and none', () {
    expect(flagLabels, {
      'none': MessageLabel.noFlag,
      'green': MessageLabel.greenFlag,
      'yellow': MessageLabel.yellowFlag,
      'red': MessageLabel.redFlag,
      'blue': MessageLabel.blueFlag,
    });
    for (final MapEntry(key: name, value: label) in flagLabels.entries) {
      expect(flagName(label.value), name == 'none' ? isNull : name);
    }
  });

  test('is listed as a write that is neither destructive nor read-only, is '
      'idempotent, and tells Claude when to propose and when to '
      'flag', () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == 'flag_messages');

    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isFalse);
    expect(annotations.destructiveHint, isFalse);
    expect(annotations.idempotentHint, isTrue);
    expect(tool.description, contains('Zet een rode vlag'));
    expect(tool.description, contains('do not flag anything'));
    expect(tool.description, contains('propose a list'));

    final schema = tool.inputSchema;
    expect(schema.required, ['message_ids', 'flag']);
    expect(schema.properties!.keys, ['message_ids', 'flag', 'box']);
    expect(schema.properties!['message_ids'], {
      'type': 'array',
      'description': isA<String>(),
      'items': {'type': 'integer', 'minimum': 1},
      'minItems': 1,
      'maxItems': maxMessageIds,
    });
    expect(schema.properties!['flag'], {
      'type': 'string',
      'description': isA<String>(),
      'enum': ['none', 'green', 'yellow', 'red', 'blue'],
    });
    expect(schema.properties!['box'], {
      'type': 'string',
      'description': isA<String>(),
      'default': 'inbox',
      'enum': ['inbox', 'sent', 'archive'],
    });
  });

  test('flags inbox messages, after which list_messages shows the flag; '
      'none clears it', () async {
    expect(
      await ok([102, 101], 'yellow'),
      'Flagged 2 messages yellow.\n'
      'Flagged yellow:\n'
      '- $_header102 | flag yellow\n'
      '- $_header101 | unread, flag yellow',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _label(102, 2),
      _label(101, 2),
    ]);
    expect(
      await list(),
      'Inbox: 2 messages, newest first.\n'
      '- $_header102 | flag yellow\n'
      '- $_header101 | unread, flag yellow',
    );

    server.mailbox.actions.clear();
    expect(
      await ok([101], 'none'),
      'Cleared the flag of 1 message.\n'
      'Flag cleared:\n'
      '- $_header101 | unread',
    );
    expect(server.mailbox.actions, [_inboxListing, _label(101, 0)]);
    expect(await list(), contains('\n- $_header101 | unread'));
  });

  test('flags a message in the sent box and one in the archive, which '
      'list_messages then shows', () async {
    expect(
      await ok([301], 'blue', box: 'sent'),
      'Flagged 1 message blue.\nFlagged blue:\n- $_header301 | flag blue',
    );
    expect(server.mailbox.actions, [
      _sentListing,
      _label(301, 4, boxType: 'outbox'),
    ]);
    expect(
      await list('sent'),
      'Sent: 1 message, newest first.\n- $_header301 | flag blue',
    );

    server.mailbox.actions.clear();
    expect(
      await ok([201], 'green', box: 'archive'),
      'Flagged 1 message green.\nFlagged green:\n- $_header201 | flag green',
    );
    expect(server.mailbox.actions, [_archiveListing, _label(201, 1)]);
    expect(
      await list('archive'),
      'Archive: 1 message, newest first.\n- $_header201 | flag green',
    );
  });

  test('reports per id: flagged, not in the box, and not confirmed (no '
      'answer, or the old flag); only ids in the box are sent, once '
      'each', () async {
    server.mailbox
      ..refuseToChange.add(101)
      ..keepUnchanged.add(102);

    final (result, text) = await flag([999, 101, 102, 102.0, 201, 301], 'red');

    expect(result.isError, isTrue, reason: 'no message was flagged');
    expect(
      text,
      'Flagged 0 of 5 messages red; 5 could not be flagged.\n'
      'Not flagged, not in the inbox:\n'
      '- id 999\n'
      '- id 201\n'
      '- id 301\n'
      'Not flagged, Smartschool did not confirm it:\n'
      '- $_header101 | unread, flag red\n'
      '- $_header102\n'
      'Note: the messages under "Not flagged, not in the inbox" are not in '
      'the inbox. Take the ids from list_messages on the box the messages '
      'are in, and pass that box.\n'
      'Note: Smartschool did not confirm the change of the messages under '
      '"Not flagged, Smartschool did not confirm it"; they are shown as they '
      'were before. Check with list_messages (box inbox) whether they '
      'changed, then try again or let the user change them in Smartschool.',
    );
    expect(server.mailbox.actions, [
      _inboxListing,
      _label(101, 3),
      _label(102, 3),
    ]);
    expect(server.mailbox.sent.single.flag, 0);
    expect(server.mailbox.archive.single.flag, 0);

    server.mailbox.refuseToChange.clear();
    expect(
      await ok([101, 999], 'none'),
      'Cleared the flag of 1 of 2 messages; 1 could not be cleared.\n'
      'Flag cleared:\n'
      '- $_header101 | unread\n'
      'Not cleared, not in the inbox:\n'
      '- id 999\n'
      'Note: the messages under "Not cleared, not in the inbox" are not in '
      'the inbox. Take the ids from list_messages on the box the messages '
      'are in, and pass that box.',
    );
  });

  group('invalid arguments are errors that say what to fix, and nothing is '
      'sent to Smartschool', () {
    final cases = <String, (Map<String, Object?>, String)>{
      'an unknown flag': (
        {
          'message_ids': [101],
          'flag': 'purple',
        },
        'none, green, yellow, red, blue',
      ),
      'no flag': (
        {
          'message_ids': [101],
        },
        'flag',
      ),
      'an unknown box': (
        {
          'message_ids': [101],
          'flag': 'red',
          'box': 'trash',
        },
        'inbox, sent, archive',
      ),
      'an empty list': ({'message_ids': <int>[], 'flag': 'red'}, 'at least 1'),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in cases.entries) {
      test(name, () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'flag_messages', arguments: arguments),
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
