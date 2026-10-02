/// `search_recipients` and `send_message`, called over MCP on the real
/// server, session and library, against a fake Smartschool whose compose
/// form finds the users and groups of its directory and sends messages.
library;

import 'package:dart_mcp/client.dart';
import 'package:dio/dio.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:smartschool_mcp/src/tools/search_recipients_tool.dart';
import 'package:smartschool_mcp/src/tools/send_message_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _me = fakeDisplayName;

const _sven = 'Sven Lamber (user 1146) | Klas: 5GZ';
const _otherSven = 'Sven Lamber (user 1330) | Klas: 6WE';
const _svenja = 'Svenja Lamberts (user 1412) | Klas: 3B';

const _choose =
    'Show the user who Smartschool finds and let them choose: never choose '
    'for them. Then call send_message again with each recipient as listed '
    'before the "|", like "Sven Lamber (user 146)".';

void _fill(FakeMailbox mailbox) => mailbox.directory.addAll([
  const FakeRecipient.user(_me),
  const FakeRecipient.user('Sven Lamber', id: 1146, className: 'Klas: 5GZ'),
  const FakeRecipient.user('Sven Lamber', id: 1330, className: 'Klas: 6WE'),
  const FakeRecipient.user('Svenja Lamberts', id: 1412, className: 'Klas: 3B'),
  const FakeRecipient.user('An Claes', id: 1007),
  const FakeRecipient.user('Els Wouters', id: 1008),
  const FakeRecipient.user('Directie', id: 1050),
  const FakeRecipient.group('5GZ', id: 298, description: '5 Grieks-Ziekenzorg'),
  const FakeRecipient.group('Directie', id: 320, description: 'Directieteam'),
]);

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
        searchRecipientsTool(session),
        sendMessageTool(session),
      ],
    );
  });

  Future<(CallToolResult, String)> send(Map<String, Object?> arguments) =>
      callTool(connection, 'send_message', arguments);

  /// Calls send_message and expects a result that is not an error.
  Future<String> ok(Map<String, Object?> arguments) async {
    final (result, text) = await send(arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  /// Calls send_message and expects an error result.
  Future<String> error(Map<String, Object?> arguments) async {
    final (result, text) = await send(arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  Future<String> search(String query) async {
    final (result, text) = await callTool(connection, 'search_recipients', {
      'query': query,
    });
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  List<String> sends() => [
    for (final action in mailbox.actions)
      if (action.startsWith('send ')) action,
  ];

  List<String> searches() => [
    for (final action in mailbox.actions)
      if (action.startsWith('search ')) action,
  ];

  bool isRequestTo(RequestOptions request, String function) =>
      request.uri.queryParameters['function'] == function;

  group('the tools are listed', () {
    Future<Tool> tool(String name) async => (await connection.listTools(
      ListToolsRequest(),
    )).tools.singleWhere((t) => t.name == name);

    test('search_recipients as read-only, telling Claude to let the user '
        'choose', () async {
      final search = await tool('search_recipients');

      final annotations = search.toolAnnotations!;
      expect(annotations.readOnlyHint, isTrue);
      expect(annotations.idempotentHint, isTrue);
      expect(annotations.openWorldHint, isTrue);
      expect(search.description, contains('as send_message takes it'));
      expect(
        search.description,
        contains(
          'When it finds several users or groups for a name, or none, ask '
          'the user who they mean: never choose for them.',
        ),
      );
      expect(
        search.description,
        contains('A message to a group goes to all its members.'),
      );
      expect(search.inputSchema.required, ['query']);
      expect(search.inputSchema.properties!['query'], {
        'type': 'string',
        'description': isA<String>(),
        'minLength': 1,
      });
    });

    test('send_message as destructive and not idempotent, telling Claude to '
        'look the recipients up, get explicit confirmation first and never '
        'resend an unconfirmed message', () async {
      final sendTool = await tool('send_message');

      final annotations = sendTool.toolAnnotations!;
      expect(annotations.readOnlyHint, isFalse);
      expect(annotations.destructiveHint, isTrue);
      expect(annotations.idempotentHint, isFalse);
      expect(annotations.openWorldHint, isTrue);
      final description = sendTool.description!;
      expect(description, contains('Sending cannot be undone.'));
      expect(description, contains('use reply_to_message instead'));
      expect(
        description,
        contains(
          'look up every recipient with search_recipients, show the user '
          'exactly who will receive the message (the names as '
          'search_recipients lists them, with their class or group), the '
          'subject and the exact text, and only call it after the user has '
          'explicitly confirmed all of it.',
        ),
      );
      expect(description, contains('never choose for them'));
      expect(
        description,
        contains('A message to a group goes to all its members.'),
      );
      expect(description, contains('"Sven Lamber (user 146)"'));
      expect(description, contains('HTML in body is not interpreted'));
      expect(
        description,
        contains(
          'If the result says the message may or may not have been sent, do '
          'not call this tool again for it',
        ),
      );

      final schema = sendTool.inputSchema;
      expect(schema.required, ['to', 'subject', 'body']);
      expect(schema.properties!.keys, ['to', 'cc', 'bcc', 'subject', 'body']);
      expect(schema.properties!['to'], {
        'type': 'array',
        'description': isA<String>(),
        'items': {'type': 'string', 'minLength': 1},
        'minItems': 1,
        'maxItems': 50,
      });
      for (final field in ['cc', 'bcc']) {
        expect(schema.properties![field], {
          'type': 'array',
          'description': isA<String>(),
          'items': {'type': 'string', 'minLength': 1},
          'maxItems': 50,
        });
      }
      for (final field in ['subject', 'body']) {
        expect(schema.properties![field], {
          'type': 'string',
          'description': isA<String>(),
          'minLength': 1,
        });
      }
    });
  });

  group('search_recipients', () {
    test('lists the users and groups the compose form finds, as send_message '
        'takes them, and changes nothing', () async {
      expect(
        await search('Sven'),
        'Smartschool finds 3 users for "Sven":\n'
        '- $_sven\n'
        '- $_otherSven\n'
        '- $_svenja',
      );
      expect(
        await search('5gz'),
        'Smartschool finds 1 group for "5gz":\n'
        '- 5GZ (group 298) | group: 5 Grieks-Ziekenzorg',
      );
      expect(
        await search(' Directie '),
        'Smartschool finds 1 user and 1 group for "Directie":\n'
        '- Directie (user 1050)\n'
        '- Directie (group 320) | group: Directieteam',
      );
      expect(
        await search('Xavier'),
        'Smartschool finds no users or groups for "Xavier". Check the '
        'spelling, or look for a part of the name, such as the last name.',
      );

      expect(mailbox.actions, [
        'search val=Sven',
        'search val=5gz',
        'search val=Directie',
        'search val=Xavier',
      ]);
      expect(mailbox.submits, 0);
    });

    test('lists at most 50, and counts the rest', () async {
      mailbox.directory.addAll([
        for (var i = 1; i <= 53; i++)
          FakeRecipient.user('Leerling $i', id: 5000 + i),
      ]);

      final lines = (await search('Leerling')).split('\n');

      expect(lines.first, 'Smartschool finds 53 users for "Leerling":');
      expect(lines, hasLength(52));
      expect(lines[50], '- Leerling 50 (user 5050)');
      expect(
        lines.last,
        '3 more not listed: look for a longer part of the name to find '
        'fewer.',
      );
    });

    test('an empty query is refused without contacting Smartschool', () async {
      final (result, text) = await callTool(connection, 'search_recipients', {
        'query': '  ',
      });

      expect(result.isError, isTrue);
      expect(text, 'query is empty: pass the name to look for.');
      expect(server.requests, isEmpty);
    });

    test('says so when Smartschool does not open its compose form', () async {
      mailbox.composeTokens = false;

      final (result, text) = await callTool(connection, 'search_recipients', {
        'query': 'Sven',
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'Smartschool did not open its compose form, so recipients cannot be '
        'looked up, and nothing was sent. The account may not be allowed to '
        'send messages; the details are in the server log.',
      );
    });
  });

  group('send_message sends a new message once, to exactly the recipients '
      'named', () {
    test('a recipient whose name only one user has, by name', () async {
      expect(
        await ok({
          'to': ['Svenja Lamberts'],
          'subject': 'Uitstap',
          'body': 'Hallo Svenja',
        }),
        'Sent the message.\n'
        'To: Svenja Lamberts\n'
        'Subject: Uitstap',
      );
      expect(sends(), [
        'send to=Svenja Lamberts cc= bcc= subject=Uitstap',
      ], reason: 'a new message, not a reply');
      expect(mailbox.submits, 1);
      expect(mailbox.sentBodies, ['<p>Hallo Svenja</p>']);

      // What Claude sees afterwards in the sent box.
      final (_, sent) = await callTool(connection, 'list_messages', {
        'box': 'sent',
      });
      expect(
        sent,
        endsWith(
          '\n- id 9001 | 2024-04-01 10:01 | to Svenja Lamberts | Uitstap',
        ),
      );
      final (_, read) = await callTool(connection, 'read_message', {
        'message_id': 9001,
        'box': 'sent',
      });
      expect(read, startsWith('Message 9001 (Sent)\nFrom: $_me\n'));
      expect(read, contains('\nTo: Svenja Lamberts\n'));
      expect(read, endsWith('\n\nHallo Svenja'));
    });

    test('the one of two namesakes the reference names, a group in CC and a '
        'user in BCC', () async {
      expect(
        await ok({
          'to': ['Sven Lamber (user 1330)'],
          'cc': ['5GZ (group 298)'],
          'bcc': ['An Claes'],
          'subject': 'Oudercontact',
          'body': 'Tot donderdag.',
        }),
        'Sent the message.\n'
        'To: Sven Lamber\n'
        'CC: 5GZ (group)\n'
        'BCC: An Claes\n'
        'Subject: Oudercontact',
      );
      expect(sends(), [
        'send to=Sven Lamber #1330 cc=5GZ (group) bcc=An Claes '
            'subject=Oudercontact',
      ]);
    });

    test('several recipients, in the order given, each once, with each name '
        'searched once', () async {
      expect(
        await ok({
          'to': [
            'Directie (group 320)',
            'Sven Lamber (user 1146)',
            'sven  lamber (USER 1146)',
            'Svenja Lamberts',
            'Svenja Lamberts (user 1412)',
          ],
          'cc': ['Sven Lamber (user 1330)'],
          'subject': 'Planning',
          'body': 'Zie bijlage.',
        }),
        'Sent the message.\n'
        'To: Directie (group), Sven Lamber, Svenja Lamberts\n'
        'CC: Sven Lamber\n'
        'Subject: Planning',
      );
      // The compose form registers the users of a field before its groups.
      expect(sends(), [
        'send to=Sven Lamber #1146,Svenja Lamberts,Directie (group) '
            'cc=Sven Lamber #1330 bcc= subject=Planning',
      ]);
      expect(searches(), [
        'search val=Directie',
        'search val=Sven Lamber',
        'search val=Svenja Lamberts',
      ]);
      expect(mailbox.submits, 1);
    });

    test('a message to the user themself arrives in their inbox', () async {
      expect(
        await ok({
          'to': [_me],
          'subject': 'Test',
          'body': 'Een test aan mezelf.',
        }),
        'Sent the message.\n'
        'To: $_me\n'
        'Subject: Test',
      );

      final (_, inbox) = await callTool(connection, 'list_messages', {});
      expect(
        inbox,
        endsWith('\n- id 9001 | 2024-04-01 10:01 | from $_me | Test | unread'),
      );
      final (_, read) = await callTool(connection, 'read_message', {
        'message_id': 9001,
      });
      expect(read, endsWith('\n\nEen test aan mezelf.'));
    });

    test('the body is converted from Markdown, HTML in it is sent as text, '
        'and the subject is sent on one line', () async {
      await ok({
        'to': ['An Claes'],
        'subject': '  Uitstap\n naar   Gent ',
        'body':
            '  **Beste An**,\n\n- vertrek <b onclick="x()">8 uur</b>\n'
            '- [route](https://example.org/gent)\n',
      });

      expect(sends(), ['send to=An Claes cc= bcc= subject=Uitstap naar Gent']);
      expect(mailbox.sentBodies, [
        '<p><strong>Beste An</strong>,</p>\n'
            '<ul><li>vertrek &lt;b onclick=&quot;x()&quot;&gt;8 uur&lt;/b&gt;'
            '</li><li><a href="https://example.org/gent">route</a></li></ul>',
      ]);
    });
  });

  group('nothing is sent when a recipient does not name exactly one user or '
      'group', () {
    test('several users have the name: they are listed for the user to '
        'choose, and the one chosen gets the message', () async {
      expect(
        await error({
          'to': ['Sven Lamber'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'Nothing was sent: not every recipient names exactly one user or '
        'group.\n'
        '- "Sven Lamber": Smartschool finds 2 users with that name. They '
        'are:\n'
        '  - $_sven\n'
        '  - $_otherSven\n'
        '$_choose',
      );
      expect(mailbox.submits, 0);

      expect(
        await ok({
          'to': ['Sven Lamber (user 1146)'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        startsWith('Sent the message.\nTo: Sven Lamber\n'),
      );
      expect(sends(), ['send to=Sven Lamber #1146 cc= bcc= subject=Uitstap']);
    });

    test('a user and a group have the name', () async {
      expect(
        await error({
          'to': ['Directie'],
          'subject': 'Vraag',
          'body': 'Hallo',
        }),
        'Nothing was sent: not every recipient names exactly one user or '
        'group.\n'
        '- "Directie": Smartschool finds 1 user and 1 group with that name. '
        'They are:\n'
        '  - Directie (user 1050)\n'
        '  - Directie (group 320) | group: Directieteam\n'
        '$_choose',
      );
      expect(mailbox.submits, 0);
    });

    test('no one has exactly the name: what the search finds instead is '
        'listed, never picked', () async {
      expect(
        await error({
          'to': ['Sven'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'Nothing was sent: not every recipient names exactly one user or '
        'group.\n'
        '- "Sven": Smartschool finds no user or group with exactly that name. '
        'It finds:\n'
        '  - $_sven\n'
        '  - $_otherSven\n'
        '  - $_svenja\n'
        '$_choose',
      );
      expect(
        await error({
          'to': ['Xavier Dubois'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        contains(
          '\n- "Xavier Dubois": Smartschool finds no user or group with '
          'exactly that name.\n',
        ),
      );
      expect(mailbox.submits, 0);
    });

    test('the id in brackets does not go with the name', () async {
      expect(
        await error({
          'to': ['Sven Lamber (user 1412)'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'Nothing was sent: not every recipient names exactly one user or '
        'group.\n'
        '- "Sven Lamber (user 1412)": Smartschool finds no user or group with '
        'that name and id. It finds:\n'
        '  - $_sven\n'
        '  - $_otherSven\n'
        '  - $_svenja\n'
        '$_choose',
      );
      expect(
        await error({
          'to': ['5GZ (user 298)'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        contains('"5GZ (user 298)": Smartschool finds no user or group'),
      );
      expect(mailbox.submits, 0);
    });

    test('every unclear recipient is listed at once, also when the others '
        'are clear', () async {
      expect(
        await error({
          'to': ['An Claes', 'Sven Lamber'],
          'cc': ['Xavier'],
          'bcc': ['Els Wouters'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'Nothing was sent: not every recipient names exactly one user or '
        'group.\n'
        '- "Sven Lamber": Smartschool finds 2 users with that name. They '
        'are:\n'
        '  - $_sven\n'
        '  - $_otherSven\n'
        '- "Xavier": Smartschool finds no user or group with exactly that '
        'name.\n'
        '$_choose',
      );
      expect(mailbox.submits, 0);
    });

    test('a long list of candidates is cut off', () async {
      mailbox.directory.addAll([
        for (var i = 1; i <= 12; i++)
          FakeRecipient.user('Leerling $i', id: 5000 + i),
      ]);

      final text = await error({
        'to': ['Leerling'],
        'subject': 'Uitstap',
        'body': 'Hallo',
      });

      expect(text, contains('  - Leerling 10 (user 5010)\n'));
      expect(text, isNot(contains('Leerling 11 (user')));
      expect(
        text,
        contains(
          '  - and 2 more: look them up with search_recipients and a longer '
          'part of the name.\n',
        ),
      );
      expect(mailbox.submits, 0);
    });
  });

  group('nothing is sent when', () {
    test('a recipient is in two fields', () async {
      expect(
        await error({
          'to': ['An Claes'],
          'bcc': ['An Claes (user 1007)'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'An Claes (user 1007) is in both To and BCC: name each recipient in '
        'one of them only. Nothing was sent.',
      );
      expect(mailbox.submits, 0);
    });

    test('Smartschool does not register a recipient on the compose '
        'form', () async {
      mailbox.unregistered.add('5GZ');

      expect(
        await error({
          'to': ['An Claes', '5GZ'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        'Smartschool did not open its compose form, or did not take the '
        'recipients of the message on it, so nothing was sent. The account '
        'may not be allowed to send messages, or to send to one of the '
        'recipients; the details are in the server log.',
      );
      expect(mailbox.submits, 0);
      expect(sends(), isEmpty);
    });

    test('Smartschool does not open its compose form', () async {
      mailbox.composeTokens = false;

      expect(
        await error({
          'to': ['An Claes'],
          'subject': 'Uitstap',
          'body': 'Hallo',
        }),
        startsWith(
          'Smartschool did not open its compose form, so recipients '
          'cannot be looked up, and nothing was sent.',
        ),
      );
      expect(mailbox.submits, 0);
    });

    final invalid = <String, (Map<String, Object?>, String)>{
      'to is missing': ({'subject': 'S', 'body': 'B'}, 'to'),
      'to is empty': ({'to': <String>[], 'subject': 'S', 'body': 'B'}, 'to'),
      'to is not a list': (
        {'to': 'An Claes', 'subject': 'S', 'body': 'B'},
        'to',
      ),
      'a recipient is not a name': (
        {
          'to': [42],
          'subject': 'S',
          'body': 'B',
        },
        'to',
      ),
      'a recipient is only white space': (
        {
          'to': ['An Claes'],
          'cc': ['  '],
          'subject': 'S',
          'body': 'B',
        },
        'Each recipient in cc must be a name, like "Sven Lamber (user 146)"; '
            'an empty one is not. Nothing was sent.',
      ),
      'to has more than 50 recipients': (
        {
          'to': [for (var i = 0; i < 51; i++) 'Leerling $i'],
          'subject': 'S',
          'body': 'B',
        },
        'to',
      ),
      'the subject is only white space': (
        {
          'to': ['An Claes'],
          'subject': ' \n ',
          'body': 'B',
        },
        'subject is empty: pass the subject of the message. Nothing was '
            'sent.',
      ),
      'there is no subject': (
        {
          'to': ['An Claes'],
          'body': 'B',
        },
        'subject',
      ),
      'the body is only white space': (
        {
          'to': ['An Claes'],
          'subject': 'S',
          'body': ' \n ',
        },
        'body is empty: pass the text of the message. Nothing was sent.',
      ),
      'there is no body': (
        {
          'to': ['An Claes'],
          'subject': 'S',
        },
        'body',
      ),
    };
    for (final MapEntry(key: name, value: (arguments, message))
        in invalid.entries) {
      test('$name, without contacting Smartschool', () async {
        final result = await connection.callTool(
          CallToolRequest(name: 'send_message', arguments: arguments),
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
    const message = {
      'to': ['Sven Lamber (user 1146)'],
      'cc': ['5GZ (group 298)'],
      'subject': 'Uitstap',
      'body': 'Hallo',
    };
    const sent =
        'send to=Sven Lamber #1146 cc=5GZ (group) bcc= subject=Uitstap';

    test('before a recipient is searched: logs in again and sends '
        'once', () async {
      // The library retries the search in the new session with the old
      // form's uniqueUsc, which this fake accepts; what Smartschool answers
      // then has not been seen (yvanvds/dartschool#97).
      server.expireSessionBefore(
        (request) =>
            request.method == 'POST' &&
            request.uri.queryParameters['file'] == 'searchUsers' &&
            !request.uri.queryParameters.containsKey('function'),
      );

      expect(await ok(message), startsWith('Sent the message.\n'));
      expect(server.logins, 2);
      expect(sends(), [sent]);
      expect(mailbox.submits, 1);
    });

    test('while recipients are registered on the compose form: logs in again '
        'and sends once', () async {
      server.expireSessionBefore(
        (request) => isRequestTo(request, 'addUserToSelected'),
      );

      expect(await ok(message), startsWith('Sent the message.\n'));
      expect(server.logins, 2);
      expect(sends(), [sent]);
      expect(mailbox.submits, 1);
    });

    test('at the submit: Smartschool refused the submit without sending it, '
        'so logs in again and sends the message once', () async {
      server.expireSessionBefore(FakeMailbox.isSubmit);

      expect(await ok(message), startsWith('Sent the message.\n'));
      expect(mailbox.submits, 2, reason: 'the refused one and the sent one');
      expect(server.logins, 2);
      expect(sends(), [sent], reason: 'sent exactly once');
    });
  });

  group('after the submit went out, a failure is reported as maybe sent and '
      'the submit is never repeated', () {
    const message = {
      'to': ['An Claes'],
      'cc': ['5GZ (group 298)'],
      'subject': 'Uitstap',
      'body': 'Hallo',
    };
    const notConfirmed =
        'The message may or may not have been sent: sending started, but '
        'Smartschool did not confirm it. Do not send it again: first check '
        'the sent box (list_messages with box sent), or ask the user to check '
        'it in Smartschool.\n'
        'To: An Claes\n'
        'CC: 5GZ (group)\n'
        'Subject: Uitstap';

    test('the connection fails after Smartschool sent it', () async {
      mailbox.submitAnswer = SubmitAnswer.responseLost;

      expect(await error(message), notConfirmed);
      expect(mailbox.submits, 1);
      expect(sends(), hasLength(1), reason: 'sent exactly once');
      expect(server.logins, 1);
    });

    test('Smartschool answers with an error page', () async {
      mailbox.submitAnswer = SubmitAnswer.errorPage;

      expect(await error(message), notConfirmed);
      expect(mailbox.submits, 1);
      expect(sends(), isEmpty);
    });

    test('Smartschool answers with a page that does not confirm it', () async {
      mailbox.submitAnswer = SubmitAnswer.otherPage;

      expect(await error(message), notConfirmed);
      expect(mailbox.submits, 1);
      expect(sends(), isEmpty);
    });
  });
}
