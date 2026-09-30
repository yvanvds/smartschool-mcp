/// `reply_to_message`, called over MCP on the real server, session and
/// library, against a fake Smartschool that sends messages.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/reply_to_message_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _me = fakeDisplayName;

void _fill(FakeMailbox mailbox) {
  mailbox
    ..inbox.addAll([
      FakeMessage(
        id: 101,
        sender: 'An Claes',
        subject: 'RE: Re: Toets wiskunde',
        date: '2024-03-15 08:00',
        to: [_me, 'Els Wouters'],
        cc: ['Piet Janssens'],
      ),
      FakeMessage(
        id: 102,
        sender: _me,
        subject: 'Notitie',
        date: '2024-03-14 08:00',
        to: [_me],
      ),
      FakeMessage(
        id: 103,
        sender: 'Directie',
        subject: 'Mededeling',
        date: '2024-03-13 08:00',
        to: [_me],
        canReply: false,
      ),
    ])
    ..archive.add(
      FakeMessage(
        id: 201,
        sender: 'Secretariaat',
        subject: 'Verlofaanvraag',
        date: '2024-02-20 12:00',
        to: [_me],
      ),
    )
    ..sent.addAll([
      FakeMessage(
        id: 301,
        sender: _me,
        listedAs: 'Els Wouters, An Claes',
        subject: 'Uitstap',
        date: '2024-03-12 11:00',
        to: ['Els Wouters', 'An Claes'],
        cc: ['Piet Janssens'],
      ),
      FakeMessage(
        id: 302,
        sender: _me,
        subject: 'Herinnering',
        date: '2024-03-11 11:00',
        to: [_me],
      ),
    ]);
}

const _notConfirmed =
    'The reply to message 101 may or may not have been sent: sending '
    'started, but Smartschool did not confirm it. Do not send it again: '
    'first check the sent box (list_messages with box sent), or ask the '
    'user to check it in Smartschool.\n'
    'To: An Claes\n'
    'Subject: Re: Toets wiskunde';

void main() {
  late FakeSmartschool server;
  late FakeMailbox mailbox;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    mailbox = server.mailbox;
    _fill(mailbox);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listMessagesTool(session),
        readMessageTool(session),
        replyToMessageTool(session),
      ],
    );
  });

  Future<(CallToolResult, String)> reply(Map<String, Object?> arguments) =>
      callTool(connection, 'reply_to_message', arguments);

  /// Calls reply_to_message and expects a result that is not an error.
  Future<String> ok(Map<String, Object?> arguments) async {
    final (result, text) = await reply(arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  /// Calls reply_to_message and expects an error result.
  Future<String> error(Map<String, Object?> arguments) async {
    final (result, text) = await reply(arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  List<String> sends() => [
    for (final action in mailbox.actions)
      if (action.startsWith('send ')) action,
  ];

  test('is listed as destructive and not idempotent, and tells Claude to get '
      'explicit confirmation first and never to resend an unconfirmed '
      'reply', () async {
    final tool = (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == 'reply_to_message');

    final annotations = tool.toolAnnotations!;
    expect(annotations.readOnlyHint, isFalse);
    expect(annotations.destructiveHint, isTrue);
    expect(annotations.idempotentHint, isFalse);
    expect(annotations.openWorldHint, isTrue);
    final description = tool.description!;
    expect(description, contains('Sending cannot be undone.'));
    expect(description, contains('read_message'));
    expect(
      description,
      contains(
        'show the user the exact text of the reply and who will receive it, '
        'and only call it after the user has explicitly confirmed both',
      ),
    );
    expect(description, contains('goes to its sender'));
    expect(description, contains('except the user'));
    expect(description, contains('one "Re:"'));
    expect(description, contains('HTML in body is not interpreted'));
    expect(
      description,
      contains(
        'If the result says the reply may or may not have been sent, do not '
        'call this tool again for it',
      ),
    );

    final schema = tool.inputSchema;
    expect(schema.required, ['message_id', 'body']);
    expect(schema.properties!.keys, ['message_id', 'body', 'reply_all', 'box']);
    expect(schema.properties!['message_id'], {
      'type': 'integer',
      'description': isA<String>(),
      'minimum': 1,
    });
    expect(schema.properties!['body'], {
      'type': 'string',
      'description': isA<String>(),
      'minLength': 1,
    });
    expect(schema.properties!['reply_all'], {
      'type': 'boolean',
      'description': isA<String>(),
    });
  });

  group('sends the reply once, with a single "Re:"', () {
    test('a plain reply to an inbox message goes to its sender only', () async {
      expect(
        await ok({'message_id': 101, 'body': 'Donderdag kan ik.'}),
        'Sent the reply to message 101.\n'
        'To: An Claes\n'
        'Subject: Re: Toets wiskunde',
      );
      expect(sends(), ['send to=An Claes cc= subject=Re: Toets wiskunde']);
      expect(mailbox.submits, 1);
      expect(mailbox.sentBodies, ['<p>Donderdag kan ik.</p>']);

      // What Claude sees afterwards in the sent box.
      final (_, sent) = await callTool(connection, 'list_messages', {
        'box': 'sent',
        'query': 'toets',
      });
      expect(
        sent,
        'Sent: 1 of 3 messages matches the filters, newest first.\n'
        '- id 9001 | 2024-04-01 10:01 | to An Claes | Re: Toets wiskunde',
      );
      final (_, read) = await callTool(connection, 'read_message', {
        'message_id': 9001,
        'box': 'sent',
      });
      expect(read, startsWith('Message 9001 (Sent)\nFrom: $_me\n'));
      expect(read, contains('\nTo: An Claes\n'));
      expect(read, endsWith('\n\nDonderdag kan ik.'));
    });

    test('a reply to all goes to the sender and everyone in To and CC except '
        'the user', () async {
      expect(
        await ok({'message_id': 101, 'body': 'Ok', 'reply_all': true}),
        'Sent the reply to message 101.\n'
        'To: Els Wouters, An Claes\n'
        'CC: Piet Janssens\n'
        'Subject: Re: Toets wiskunde',
      );
      expect(sends(), [
        'send to=Els Wouters,An Claes cc=Piet Janssens '
            'subject=Re: Toets wiskunde',
      ]);
    });

    test('a message in the archive', () async {
      expect(
        await ok({'message_id': 201, 'box': 'archive', 'body': 'Bedankt'}),
        'Sent the reply to message 201.\n'
        'To: Secretariaat\n'
        'Subject: Re: Verlofaanvraag',
      );
      expect(sends(), ['send to=Secretariaat cc= subject=Re: Verlofaanvraag']);
    });

    test('a message in the sent box: a reply goes to its To recipients, a '
        'reply to all also to its CC recipients', () async {
      expect(
        await ok({'message_id': 301, 'box': 'sent', 'body': 'Vergeet niet'}),
        'Sent the reply to message 301.\n'
        'To: Els Wouters, An Claes\n'
        'Subject: Re: Uitstap',
      );
      expect(
        await ok({
          'message_id': 301,
          'box': 'sent',
          'body': 'Vergeet niet',
          'reply_all': true,
        }),
        'Sent the reply to message 301.\n'
        'To: Els Wouters, An Claes\n'
        'CC: Piet Janssens\n'
        'Subject: Re: Uitstap',
      );
      expect(sends(), [
        'send to=Els Wouters,An Claes cc= subject=Re: Uitstap',
        'send to=Els Wouters,An Claes cc=Piet Janssens subject=Re: Uitstap',
      ]);
    });

    test('a reply to a message the user sent to themself arrives in their '
        'inbox, where list_messages and read_message show it', () async {
      await ok({'message_id': 102, 'body': 'Niet vergeten:\n- **toets**'});

      final (_, inbox) = await callTool(connection, 'list_messages', {
        'query': 'notitie',
      });
      expect(
        inbox,
        'Inbox: 2 of 4 messages match the filters, newest first.\n'
        '- id 9001 | 2024-04-01 10:01 | from $_me | Re: Notitie | unread\n'
        '- id 102 | 2024-03-14 08:00 | from $_me | Notitie',
      );
      final (_, read) = await callTool(connection, 'read_message', {
        'message_id': 9001,
      });
      expect(read, endsWith('\n\nNiet vergeten:\n\n- toets'));
    });

    test('the body is converted from Markdown, and HTML in it is sent as '
        'text', () async {
      await ok({
        'message_id': 101,
        'body':
            '  **Ja**, donderdag <b onclick="x()">kan</b> ik.\n\n'
            '<script>alert(1)</script>\n',
      });

      expect(mailbox.sentBodies, [
        '<p><strong>Ja</strong>, donderdag '
            '&lt;b onclick=&quot;x()&quot;&gt;kan&lt;/b&gt; ik.</p>\n'
            '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>',
      ]);
    });

    test('two replies at the same time are sent one after the other, each '
        'confirmed', () async {
      final results = await Future.wait([
        reply({'message_id': 101, 'body': 'Een'}),
        reply({'message_id': 201, 'box': 'archive', 'body': 'Twee'}),
      ]);

      for (final (result, text) in results) {
        expect(result.isError, isNot(true), reason: text);
      }
      expect(sends(), hasLength(2));
      expect(mailbox.submits, 2);
    });
  });

  group('nothing is sent when', () {
    test('the message does not exist', () async {
      expect(
        await error({'message_id': 999, 'body': 'Hallo'}),
        'There is no message with id 999 in the inbox box. Take the id from '
        'list_messages and pass the box it was listed in. Nothing was sent.',
      );
      expect(
        await error({'message_id': 101, 'box': 'sent', 'body': 'Hallo'}),
        contains('no message with id 101 in the sent box'),
      );
      expect(mailbox.submits, 0);
    });

    test('Smartschool does not allow replies to it', () async {
      expect(
        await error({'message_id': 103, 'body': 'Hallo'}),
        'Smartschool does not allow replies to message 103. Nothing was '
        'sent.',
      );
      expect(mailbox.submits, 0);
    });

    test('Smartschool gives no one to reply to', () async {
      expect(
        await error({'message_id': 302, 'box': 'sent', 'body': 'Hallo'}),
        'Smartschool gives no one to send a reply to message 302 to (it does '
        'not for some sent messages, for example when the user was the only '
        'recipient). Nothing was sent. The user can reply in Smartschool '
        'itself.',
      );
      mailbox.replyFormNames[101] = [];
      expect(
        await error({'message_id': 101, 'body': 'Hallo'}),
        'Smartschool gives no one to send a reply to message 101 to. Nothing '
        'was sent. The user can reply in Smartschool itself.',
      );
      expect(mailbox.submits, 0);
    });

    test("Smartschool's reply form names more than the sender", () async {
      mailbox.replyFormNames[101] = ['An Claes', 'Els Wouters'];

      expect(
        await error({'message_id': 101, 'body': 'Hallo'}),
        "Smartschool's reply form for message 101 does not name just the "
        'sender, so the reply was not sent. The user can reply in '
        'Smartschool itself.',
      );
      expect(mailbox.submits, 0);
    });

    final invalid = <String, (Map<String, Object?>, String)>{
      'body is only white space': (
        {'message_id': 101, 'body': ' \n '},
        'body is empty: pass the text of the reply. Nothing was sent.',
      ),
      'body is empty': ({'message_id': 101, 'body': ''}, 'body'),
      'there is no body': ({'message_id': 101}, 'body'),
      'there is no message_id': ({'body': 'Hallo'}, 'message_id'),
      'message_id is not a whole number': (
        {'message_id': 101.5, 'body': 'Hallo'},
        'message_id',
      ),
      'box is unknown': (
        {'message_id': 101, 'body': 'Hallo', 'box': 'trash'},
        'box',
      ),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in invalid.entries) {
      test('$name, without contacting Smartschool', () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'reply_to_message', arguments: arguments),
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

  group('the session expires', () {
    test('while recipients are added to the form: logs in again and sends '
        'once', () async {
      server.expireSessionBefore(
        (request) =>
            request.uri.queryParameters['function'] == 'addUserToSelected',
      );

      expect(
        await ok({'message_id': 101, 'body': 'Hallo'}),
        startsWith('Sent the reply to message 101.\n'),
      );
      expect(server.logins, 2);
      expect(sends(), ['send to=An Claes cc= subject=Re: Toets wiskunde']);
      expect(mailbox.submits, 1);
    });

    test('before the compose form is loaded: logs in again and sends '
        'once', () async {
      server.expireSessionBefore(
        (request) =>
            request.method == 'GET' &&
            request.uri.queryParameters['composeType'] == '0',
      );

      expect(
        await ok({'message_id': 101, 'body': 'Hallo'}),
        startsWith('Sent the reply to message 101.\n'),
      );
      expect(server.logins, 2);
      expect(mailbox.submits, 1);
    });

    test('at the submit: not sent again, and the user is told to check the '
        'sent box', () async {
      server.expireSessionBefore(FakeMailbox.isSubmit);

      expect(await error({'message_id': 101, 'body': 'Hallo'}), _notConfirmed);
      expect(mailbox.submits, 1, reason: 'the submit must not be repeated');
      expect(server.logins, 1);
      expect(sends(), isEmpty);
    });
  });

  group('after the submit went out, a failure is reported as maybe sent and '
      'the submit is never repeated', () {
    test('the connection fails after Smartschool sent it', () async {
      mailbox.submitAnswer = SubmitAnswer.responseLost;

      expect(await error({'message_id': 101, 'body': 'Hallo'}), _notConfirmed);
      expect(mailbox.submits, 1);
      expect(sends(), hasLength(1), reason: 'sent exactly once');
    });

    test('Smartschool answers with an error page', () async {
      mailbox.submitAnswer = SubmitAnswer.errorPage;

      expect(await error({'message_id': 101, 'body': 'Hallo'}), _notConfirmed);
      expect(mailbox.submits, 1);
    });

    test('Smartschool answers with a page that does not confirm it, which '
        'the library takes as sent', () async {
      mailbox.submitAnswer = SubmitAnswer.otherPage;

      expect(await error({'message_id': 101, 'body': 'Hallo'}), _notConfirmed);
      expect(mailbox.submits, 1);
      expect(sends(), isEmpty);
    });
  });
}
