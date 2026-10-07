/// `list_messages` and `read_message`, called over MCP on the real server,
/// session and library, against a fake Smartschool.
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/list_messages_tool.dart';
import 'package:smartschool_mcp/src/tools/read_message_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

const _body = '''
<div style="font-family: Arial"><p>Beste collega's,</p>
<p>Het oudercontact is op <b>donderdag</b> om 17u in de
<a href="https://school.be/refter">refter</a>.</p>
<ul><li>Inschrijven via de planner</li><li>Graag op tijd</li></ul>
<p>&nbsp;</p><p>Groeten,<br>Jan</p><script>track("x")</script></div>''';

void _fill(FakeMailbox mailbox) {
  mailbox.inbox.addAll([
    FakeMessage(
      id: 101,
      sender: 'Jan Peeters',
      subject: 'Oudercontact donderdag',
      date: '2024-03-14 16:05',
      unread: true,
      flag: 3,
      to: ['Els Wouters', 'Tom Maes', 'Sara Janssens', 'Pieter De Smet'],
      cc: ['Directie'],
      attachments: [
        FakeAttachment('Planning oudercontact.pdf', '123.48 KiB'),
        FakeAttachment('Lokalen.xlsx', '8.2 KiB'),
      ],
      body: _body,
    ),
    FakeMessage(
      id: 102,
      sender: 'An Claes',
      subject: 'Re: Toets wiskunde',
      date: '2024-03-15 08:00',
      to: ['Jan Peeters'],
      body: '<p>Prima, bedankt!</p>',
    ),
    FakeMessage(
      id: 103,
      sender: 'Secretariaat',
      subject: 'Verlofaanvraag',
      date: '2024-03-13 10:30',
      unread: true,
    ),
  ]);
  mailbox.archive.addAll([
    FakeMessage(
      id: 201,
      sender: 'Directie',
      subject: 'Personeelsvergadering',
      date: '2024-02-20 12:00',
      to: ['Jan Peeters'],
      body: '<p>Agenda volgt.</p>',
    ),
    FakeMessage(
      id: 202,
      sender: 'Jan Peeters',
      subject: 'Oudercontact januari',
      date: '2024-01-10 09:15',
    ),
  ]);
  mailbox.sent.add(
    FakeMessage(
      id: 301,
      sender: 'Jan Peeters',
      listedAs: 'Els Wouters, Tom Maes',
      subject: 'Uitstap',
      date: '2024-03-12 11:00',
      to: ['Els Wouters', 'Tom Maes'],
      body: '<p>Vertrek om 8u.</p>',
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
      tools: [listMessagesTool(session), readMessageTool(session)],
    );
  });

  Future<(CallToolResult, String)> call(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) => callTool(connection, tool, arguments);

  /// Calls [tool] and expects a successful result without HTML or XML.
  Future<String> ok(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final (result, text) = await call(tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    expect(text, isNot(contains('<')), reason: 'HTML or XML in the output');
    return text;
  }

  test('both tools are listed as read-only, and tell Claude to list first '
      'and read by id', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };

    expect(tools.keys, ['list_messages', 'read_message']);
    for (final tool in tools.values) {
      expect(tool.toolAnnotations?.readOnlyHint, isTrue);
      expect(tool.toolAnnotations?.destructiveHint, isNot(true));
    }
    expect(tools['list_messages']!.description, contains('call read_message'));
    expect(
      tools['list_messages']!.description,
      contains('a folder the user made in Smartschool'),
    );
    expect(
      tools['read_message']!.inputSchema.properties!['box'],
      containsPair(
        'description',
        contains('For a message in a folder the user made, the box'),
      ),
    );
    expect(tools['read_message']!.description, contains('from list_messages'));
    expect(
      tools['read_message']!.description,
      contains('does not mark it as read'),
    );

    final listSchema = tools['list_messages']!.inputSchema;
    expect(listSchema.properties!.keys, [
      'box',
      'folder',
      'query',
      'unread_only',
      'since',
      'until',
      'limit',
    ]);
    expect(
      listSchema.properties!['box'],
      containsPair('enum', ['inbox', 'sent', 'archive']),
    );
    final readSchema = tools['read_message']!.inputSchema;
    expect(readSchema.required, ['message_id']);
  });

  group('list_messages', () {
    test('lists the inbox by default, newest first, one line per '
        'message', () async {
      expect(
        await ok('list_messages'),
        'Inbox: 3 messages, newest first.\n'
        '- id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde\n'
        '- id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact '
        'donderdag | unread, attachments, flag red\n'
        '- id 103 | 2024-03-13 10:30 | from Secretariaat | Verlofaanvraag | '
        'unread',
      );
      expect(server.mailbox.actions, [
        'message list boxID=0 boxType=inbox layout=new poll=false poll_ids= '
            'sortField=date sortKey=desc',
      ]);
    });

    test('lists the archive: its box id is read from the folder tree', () async {
      expect(
        await ok('list_messages', {'box': 'archive'}),
        'Archive: 2 messages, newest first.\n'
        '- id 201 | 2024-02-20 12:00 | from Directie | Personeelsvergadering\n'
        '- id 202 | 2024-01-10 09:15 | from Jan Peeters | Oudercontact '
        'januari',
      );
      expect(
        server.mailbox.actions.single,
        startsWith('message list boxID=305 boxType=inbox '),
      );
      expect(server.mailbox.folderTreeReads, 1);
    });

    test('lists the sent box with the recipients', () async {
      expect(
        await ok('list_messages', {'box': 'sent'}),
        'Sent: 1 message, newest first.\n'
        '- id 301 | 2024-03-12 11:00 | to Els Wouters, Tom Maes | Uitstap',
      );
      expect(
        server.mailbox.actions.single,
        startsWith('message list boxID=0 boxType=outbox '),
      );
    });

    test('unread_only', () async {
      expect(
        await ok('list_messages', {'unread_only': true}),
        'Inbox: 2 of 3 messages match the filters, newest first.\n'
        '- id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact '
        'donderdag | unread, attachments, flag red\n'
        '- id 103 | 2024-03-13 10:30 | from Secretariaat | Verlofaanvraag | '
        'unread',
      );
    });

    test('query matches subject and sender, case-insensitively', () async {
      final text = await ok('list_messages', {
        'box': 'archive',
        'query': 'OUDERCONTACT peeters',
      });
      expect(
        text,
        'Archive: 1 of 2 messages matches the filters, newest first.\n'
        '- id 202 | 2024-01-10 09:15 | from Jan Peeters | Oudercontact '
        'januari',
      );
    });

    test('since and until: whole days, inclusive', () async {
      final text = await ok('list_messages', {
        'since': '2024-03-13',
        'until': '2024-03-14',
      });
      expect(text, startsWith('Inbox: 2 of 3 messages match the filters'));
      expect(text, contains('id 101 '));
      expect(text, contains('id 103 '));
      expect(text, isNot(contains('id 102 ')));

      final afternoon = await ok('list_messages', {
        'since': '2024-03-14 16:05',
      });
      expect(afternoon, contains('id 101 '));
      expect(afternoon, contains('id 102 '));
      expect(afternoon, isNot(contains('id 103 ')));
    });

    test('limit keeps the newest and says that more are older', () async {
      expect(
        await ok('list_messages', {'limit': 1}),
        'Inbox: more than 1 message; showing the newest 1 (raise limit, or '
        'pass until to see older ones), newest first.\n'
        '- id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde',
      );
    });

    test('limit with filters: says how many matched when all are '
        'known', () async {
      expect(
        await ok('list_messages', {'query': 'oudercontact', 'limit': 1}),
        'Inbox: 1 of 3 messages matches the filters, newest first.\n'
        '- id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact '
        'donderdag | unread, attachments, flag red',
      );
      expect(
        await ok('list_messages', {'unread_only': true, 'limit': 1}),
        startsWith(
          'Inbox: more than 1 message matches the filters; showing the newest '
          '1 (raise limit, or pass until to see older ones), newest first.\n'
          '- id 101 ',
        ),
      );
    });

    test('a limit written with a decimal part (2.0) works like 2', () async {
      expect(
        await ok('list_messages', {'limit': 2.0}),
        'Inbox: more than 2 messages; showing the newest 2 (raise limit, or '
        'pass until to see older ones), newest first.\n'
        '- id 102 | 2024-03-15 08:00 | from An Claes | Re: Toets wiskunde\n'
        '- id 101 | 2024-03-14 16:05 | from Jan Peeters | Oudercontact '
        'donderdag | unread, attachments, flag red',
      );
    });

    test('no match', () async {
      expect(
        await ok('list_messages', {'query': 'zwembad'}),
        'Inbox: no messages match the filters (3 messages checked).',
      );
    });

    test('an empty box', () async {
      server.mailbox.sent.clear();
      expect(await ok('list_messages', {'box': 'sent'}), 'Sent: no messages.');
    });

    group('a box of more than 50 messages, which Smartschool lists 50 at a '
        'time', () {
      const firstPage =
          'message list boxID=0 boxType=inbox layout=new poll=false poll_ids= '
          'sortField=date sortKey=desc';
      const nextPage = 'continue_messages boxID=0 boxType=inbox layout=new';

      // 120 newer messages: the fixture's 102, 101 and 103 are the oldest
      // three of 123, on the third page.
      setUp(
        () => server.mailbox.inbox.addAll(
          hourlyMessages(120, firstId: 1000, newest: '2024-04-30 18:00'),
        ),
      );

      test('lists the whole box when the limit allows', () async {
        final text = await ok('list_messages', {'limit': 200});

        final lines = text.split('\n');
        expect(lines.first, 'Inbox: 123 messages, newest first.');
        expect(lines, hasLength(124));
        expect(
          lines[1],
          '- id 1000 | 2024-04-30 18:00 | from Collega 0 | Bericht 0',
        );
        expect(lines.skip(121).map((l) => l.substring(0, 9)), [
          '- id 102 ',
          '- id 101 ',
          '- id 103 ',
        ]);
        expect(server.mailbox.actions, [firstPage, nextPage, nextPage]);
      });

      test('lists only the pages it needs: stops once more messages match '
          'than the limit, and says that more are older', () async {
        final text = await ok('list_messages');

        final lines = text.split('\n');
        expect(
          lines.first,
          'Inbox: more than 50 messages; showing the newest 50 (raise limit, '
          'or pass until to see older ones), newest first.',
        );
        expect(lines, hasLength(51));
        expect(lines.last, startsWith('- id 1049 | 2024-04-28 17:00 |'));
        // 50 fit the limit; the second page shows that more are older.
        expect(server.mailbox.actions, [firstPage, nextPage]);

        server.mailbox.actions.clear();
        expect(
          await ok('list_messages', {'limit': 10}),
          startsWith('Inbox: more than 10 messages; showing the newest 10 '),
        );
        expect(server.mailbox.actions, [firstPage]);
      });

      test('until reaches the older messages', () async {
        final text = await ok('list_messages', {
          'until': '2024-04-26 14:00',
          'limit': 3,
        });

        expect(
          text,
          'Inbox: more than 3 messages match the filters; showing the newest '
          '3 (raise limit, or pass until to see older ones), newest first.\n'
          '- id 1100 | 2024-04-26 14:00 | from Collega 100 | Bericht 100\n'
          '- id 1101 | 2024-04-26 13:00 | from Collega 101 | Bericht 101\n'
          '- id 1102 | 2024-04-26 12:00 | from Collega 102 | Bericht 102',
        );
        expect(server.mailbox.actions, [firstPage, nextPage, nextPage]);
      });

      test('filters search the whole box: an old message is found', () async {
        expect(
          await ok('list_messages', {'query': 'verlofaanvraag'}),
          'Inbox: 1 of 123 messages matches the filters, newest first.\n'
          '- id 103 | 2024-03-13 10:30 | from Secretariaat | Verlofaanvraag | '
          'unread',
        );
        expect(server.mailbox.actions, [firstPage, nextPage, nextPage]);
      });

      test('since: stops at the first page that reaches past it', () async {
        final text = await ok('list_messages', {'since': '2024-04-30'});

        final lines = text.split('\n');
        expect(
          lines.first,
          'Inbox: 19 of the newest 50 messages match the filters, newest '
          'first.',
        );
        expect(lines.last, startsWith('- id 1018 | 2024-04-30 00:00 |'));
        expect(server.mailbox.actions, [firstPage]);
      });

      test('a new login between two pages goes on with the next page: the '
          'whole box is shown', () async {
        var pages = 0;
        server.expireSessionBefore(
          (request) =>
              '${request.data}'.contains('continue_messages') && ++pages == 2,
        );

        final text = await ok('list_messages', {'limit': 200});

        expect(text, startsWith('Inbox: 123 messages, newest first.\n'));
        expect(text.split('\n'), hasLength(124));
        expect(server.logins, 2);
        // The refused request is not answered; the library sends it again
        // after logging in, and Smartschool kept the paging position.
        expect(server.mailbox.actions, [firstPage, nextPage, nextPage]);
      });

      group('the box listed elsewhere while it is paged, as the web client '
          'does when the user opens it (yvanvds/dartschool#76)', () {
        /// Lists the inbox elsewhere before the second `continue_messages`
        /// of each of the next [times] listings of it: once it has paged
        /// past its second page, where Smartschool's restart shows.
        void listElsewhereWhilePaging({required int times}) {
          var left = times;
          var pages = 0;
          server.mailbox.beforeAnswer = (action) {
            if (action == firstPage) pages = 0;
            if (action == nextPage && ++pages == 2 && left > 0) {
              left--;
              server.mailbox.listElsewhere();
            }
          };
        }

        test('the box is listed again, and all of it is shown', () async {
          listElsewhereWhilePaging(times: 1);

          final text = await ok('list_messages', {'limit': 200});

          expect(text, startsWith('Inbox: 123 messages, newest first.\n'));
          expect(text.split('\n'), hasLength(124));
          expect(text, contains('\n- id 103 | 2024-03-13 10:30 |'));
          expect(server.mailbox.actions, [
            firstPage,
            nextPage,
            // Answered with the second page again: the paging was restarted.
            nextPage,
            firstPage,
            nextPage,
            nextPage,
          ]);
          expect(server.logins, 1);
        });

        test('restarted again: an error that says to try again, and the box '
            'is not listed a third time', () async {
          listElsewhereWhilePaging(times: 2);

          final (result, text) = await call('list_messages', {'limit': 200});

          expect(result.isError, isTrue);
          expect(
            text,
            allOf(
              startsWith('Smartschool restarted the listing of a message box'),
              contains('in the browser'),
              contains('Try again in a moment.'),
            ),
          );
          expect(server.mailbox.actions, [
            firstPage,
            nextPage,
            nextPage,
            firstPage,
            nextPage,
            nextPage,
          ]);
        });
      });

      test('two listings at the same time each list the whole box', () async {
        // Smartschool keeps one paging position per user and box, which
        // every listing of the box restarts and every next page moves on:
        // interleaved, the listings would restart or skip each other's
        // pages.
        server.latency = const Duration(milliseconds: 5);

        final texts = await Future.wait([
          ok('list_messages', {'limit': 200}),
          ok('list_messages', {'limit': 200}),
        ]);

        for (final text in texts) {
          expect(text, startsWith('Inbox: 123 messages, newest first.\n'));
          expect(text.split('\n'), hasLength(124));
        }
      });
    });

    group('invalid arguments are errors that say what to fix', () {
      final cases = {
        'a date Claude has to work out': (
          {'since': 'gisteren'},
          'since must be a date like 2024-03-15, or a date and time like '
              '2024-03-15 14:30; "gisteren" is not.',
        ),
        'an impossible date': (
          {'until': '2024-02-30'},
          'until must be a date like 2024-03-15',
        ),
        'since after until': (
          {'since': '2024-03-15', 'until': '2024-03-14'},
          'since must not be later than until.',
        ),
        'an unknown box': ({'box': 'trash'}, 'trash'),
        'a limit of 0': ({'limit': 0}, 'limit'),
        'a limit above 200': ({'limit': 201}, 'limit'),
        'a limit with a fraction': ({'limit': 2.5}, 'limit'),
        'a limit that is not a number': ({'limit': 'tien'}, 'limit'),
      };
      for (final MapEntry(key: name, value: (arguments, message))
          in cases.entries) {
        test(name, () async {
          final (result, text) = await call('list_messages', arguments);
          expect(result.isError, isTrue);
          expect(text, contains(message));
          expect(server.mailbox.actions, isEmpty);
        });
      }
    });
  });

  group('read_message', () {
    test('shows the header, all recipients, the attachments and the body as '
        'text', () async {
      expect(
        await ok('read_message', {'message_id': 101}),
        'Message 101 (Inbox)\n'
        'From: Jan Peeters\n'
        'Date: 2024-03-14 16:05\n'
        'To: Els Wouters, Tom Maes, Sara Janssens, Pieter De Smet\n'
        'CC: Directie\n'
        'Subject: Oudercontact donderdag\n'
        'Status: unread\n'
        'Flag: red\n'
        'Attachments (2):\n'
        '1. Planning oudercontact.pdf (123.48 KiB)\n'
        '2. Lokalen.xlsx (8.2 KiB)\n'
        '\n'
        "Beste collega's,\n"
        '\n'
        'Het oudercontact is op donderdag om 17u in de '
        '[refter](https://school.be/refter).\n'
        '\n'
        '- Inschrijven via de planner\n'
        '- Graag op tijd\n'
        '\n'
        'Groeten,\n'
        'Jan',
      );
      expect(server.mailbox.actions, [
        'show message boxType=inbox limitList=false msgID=101',
        'attachment list boxType=inbox limitList=true msgID=101',
      ]);
    });

    test('does not change the read state', () async {
      await ok('read_message', {'message_id': 101});

      expect(server.mailbox.inbox.first.unread, isTrue);
      expect(
        server.mailbox.actions,
        everyElement(isNot(contains('mark message'))),
      );
      expect(
        await ok('list_messages', {'unread_only': true}),
        contains('id 101 '),
      );
    });

    test('a message without attachments: no attachment request', () async {
      final text = await ok('read_message', {'message_id': 102});

      expect(text, contains('\nAttachments: none\n\nPrima, bedankt!'));
      expect(text, isNot(contains('Status:')));
      expect(text, isNot(contains('CC:')));
      expect(server.mailbox.actions, [
        'show message boxType=inbox limitList=false msgID=102',
      ]);
    });

    test('a message without text says so', () async {
      expect(
        await ok('read_message', {'message_id': 103}),
        endsWith('\nAttachments: none\n\n(The message has no text.)'),
      );
    });

    test('a message in the archive', () async {
      expect(
        await ok('read_message', {'message_id': 201, 'box': 'archive'}),
        'Message 201 (Archive)\n'
        'From: Directie\n'
        'Date: 2024-02-20 12:00\n'
        'To: Jan Peeters\n'
        'Subject: Personeelsvergadering\n'
        'Attachments: none\n'
        '\n'
        'Agenda volgt.',
      );
      expect(server.mailbox.actions, [
        'show message boxType=inbox limitList=false msgID=201',
      ]);
    });

    test('a sent message', () async {
      final text = await ok('read_message', {'message_id': 301, 'box': 'sent'});

      expect(text, startsWith('Message 301 (Sent)\nFrom: Jan Peeters\n'));
      expect(text, contains('\nTo: Els Wouters, Tom Maes\n'));
      expect(server.mailbox.actions, [
        'show message boxType=outbox limitList=false msgID=301',
      ]);
    });

    test('an unknown id is an error, not Smartschool\'s placeholder', () async {
      final (result, text) = await call('read_message', {'message_id': 999});

      expect(result.isError, isTrue);
      expect(
        text,
        'There is no message with id 999 in the inbox box. Take the id from '
        'list_messages and pass the box it was listed in.',
      );
      expect(text, isNot(contains('Niet beschikbaar')));
    });

    test('a real message is shown whatever its date and text: only the '
        'library tells Smartschool\'s placeholder apart', () async {
      // Until #15, the server took a message dated before 1971 without text
      // for the placeholder, which flutter_smartschool 0.2.x returned
      // (yvanvds/dartschool#16).
      server.mailbox.inbox.add(
        FakeMessage(
          id: 104,
          sender: 'Directie',
          subject: 'Leeg',
          date: '1970-01-01 00:00',
        ),
      );

      expect(
        await ok('read_message', {'message_id': 104}),
        'Message 104 (Inbox)\n'
        'From: Directie\n'
        'Date: 1970-01-01 00:00\n'
        'To: (none)\n'
        'Subject: Leeg\n'
        'Attachments: none\n'
        '\n'
        '(The message has no text.)',
      );
    });

    test('a message looked up in the wrong box is not found', () async {
      final (result, text) = await call('read_message', {
        'message_id': 101,
        'box': 'sent',
      });

      expect(result.isError, isTrue);
      expect(text, startsWith('There is no message with id 101 in the sent '));
    });

    test('an id written with a decimal part (102.0) works like 102', () async {
      final text = await ok('read_message', {'message_id': 102.0});

      expect(text, startsWith('Message 102 (Inbox)\nFrom: An Claes\n'));
      expect(text, endsWith('\n\nPrima, bedankt!'));
      expect(server.mailbox.actions, [
        'show message boxType=inbox limitList=false msgID=102',
      ]);
    });

    group('invalid message_id: an error that says what to fix, and nothing '
        'is sent to Smartschool', () {
      final cases = <String, Map<String, Object?>>{
        'absent': {'box': 'inbox'},
        'with a fraction': {'message_id': 101.5},
        'not a number': {'message_id': 'honderd'},
        'zero': {'message_id': 0},
      };
      for (final MapEntry(key: name, value: arguments) in cases.entries) {
        test(name, () async {
          final (result, text) = await call('read_message', arguments);

          expect(result.isError, isTrue);
          expect(text, contains('message_id'));
          expect(text, isNot(contains('unexpected error')));
          expect(server.mailbox.actions, isEmpty);
        });
      }
    });

    test('a very long body is cut off with a note', () async {
      server.mailbox.inbox.add(
        FakeMessage(
          id: 104,
          sender: 'Directie',
          subject: 'Lang',
          date: '2024-03-01 08:00',
          body: '<p>${'woord ' * 5000}</p>',
        ),
      );

      final text = await ok('read_message', {'message_id': 104});

      final body = text.substring(text.indexOf('\n\n') + 2);
      final note = RegExp(
        r'\n\n\[Message text cut off: showing the first (\d+) of 29999 '
        r'characters\.\]$',
      ).firstMatch(body);
      expect(note, isNotNull, reason: 'no cut-off note at the end');
      final shown = body.substring(0, note!.start);
      // Cut at a word boundary, just under the maximum.
      expect(shown.length, int.parse(note[1]!));
      expect(shown.length, inInclusiveRange(maxBodyLength - 10, maxBodyLength));
      expect(shown, startsWith('woord woord'));
      expect(shown, endsWith(' woord'));
    });
  });

  group('a folder the user made in Smartschool (#131)', () {
    String listing(int boxId, {String boxType = 'inbox'}) =>
        'message list boxID=$boxId boxType=$boxType layout=new poll=false '
        'poll_ids= sortField=date sortKey=desc';
    const header401 = 'id 401 | 2024-03-10 09:00 | from Directie | Kalender';
    const header402 =
        'id 402 | 2024-03-11 14:00 | from Els Wouters | Uitstap Brugge | '
        'unread';
    const header411 = 'id 411 | 2024-03-09 12:00 | from Tom Maes | Projectweek';
    const header421 =
        'id 421 | 2024-03-08 10:00 | to Els Wouters | Projectweek: planning';
    const folders =
        'inbox/dartschool test (id 30650), inbox/Projecten (id 31000), '
        'inbox/Projecten/2026 (id 31001)';

    // A folder in the inbox with two messages, an empty one with a folder
    // in it, and a folder of the sent box with the same name.
    setUp(() {
      final mailbox = server.mailbox;
      mailbox.addFolder(30650, 'dartschool test').messages.addAll([
        FakeMessage(
          id: 401,
          sender: 'Directie',
          subject: 'Kalender',
          date: '2024-03-10 09:00',
          to: ['Jan Peeters'],
          body: '<p>De kalender van april.</p>',
        ),
        FakeMessage(
          id: 402,
          sender: 'Els Wouters',
          subject: 'Uitstap Brugge',
          date: '2024-03-11 14:00',
          unread: true,
        ),
      ]);
      final projects = mailbox.addFolder(31000, 'Projecten');
      mailbox
          .addFolder(31001, '2026', parent: projects)
          .messages
          .add(
            FakeMessage(
              id: 411,
              sender: 'Tom Maes',
              subject: 'Projectweek',
              date: '2024-03-09 12:00',
            ),
          );
      mailbox
          .addFolder(32000, 'Projecten', boxType: 'outbox')
          .messages
          .add(
            FakeMessage(
              id: 421,
              sender: 'Jan Peeters',
              listedAs: 'Els Wouters',
              subject: 'Projectweek: planning',
              date: '2024-03-08 10:00',
              to: ['Els Wouters'],
              body: '<p>De planning.</p>',
            ),
          );
    });

    test('list_messages lists a folder by its path, its name or its id, and '
        'says which folder it listed', () async {
      expect(
        await ok('list_messages', {'folder': 'dartschool test'}),
        'Folder inbox/dartschool test: 2 messages, newest first.\n'
        '- $header402\n'
        '- $header401',
      );
      expect(server.mailbox.actions, [listing(30650)]);
      expect(server.mailbox.folderTreeReads, 1);

      // A folder in a folder: its path as the result shows it, its path
      // from the box (ignoring case and spaces around /), its name or its
      // id, also in quotes.
      for (final folder in [
        'inbox/Projecten/2026',
        ' projecten / 2026 ',
        '2026',
        '31001',
        '"Projecten/2026"',
      ]) {
        server.mailbox.actions.clear();
        expect(
          await ok('list_messages', {'folder': folder}),
          'Folder inbox/Projecten/2026: 1 message, newest first.\n'
          '- $header411',
          reason: folder,
        );
        expect(server.mailbox.actions, [listing(31001)], reason: folder);
      }

      // An empty folder argument is none.
      expect(
        await ok('list_messages', {'folder': ' '}),
        startsWith('Inbox: 3 messages, newest first.\n'),
      );
    });

    test('a folder of the sent box is listed with the recipients, as the '
        'sent box is', () async {
      expect(
        await ok('list_messages', {'box': 'sent', 'folder': 'Projecten'}),
        'Folder sent/Projecten: 1 message, newest first.\n- $header421',
      );
      expect(server.mailbox.actions, [listing(32000, boxType: 'outbox')]);
      expect(
        await ok('list_messages', {'folder': 'sent/projecten'}),
        startsWith('Folder sent/Projecten: 1 message, newest first.\n'),
      );
    });

    test('a name two folders have is an error that names both, before '
        'anything is listed; the box or the path picks one', () async {
      final (result, text) = await call('list_messages', {
        'folder': 'Projecten',
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'There is more than one folder "Projecten": inbox/Projecten (id '
        '31000), sent/Projecten (id 32000). Pass the one you mean as folder, '
        'by its path or its id.',
      );
      expect(server.mailbox.actions, isEmpty);

      for (final arguments in [
        {'box': 'inbox', 'folder': 'Projecten'},
        {'folder': 'inbox/Projecten'},
        {'folder': '31000'},
      ]) {
        expect(
          await ok('list_messages', arguments),
          'Folder inbox/Projecten: no messages.',
          reason: '$arguments',
        );
      }
    });

    test('an unknown folder is an error that names the folders the user '
        'made, and nothing is listed', () async {
      final (result, text) = await call('list_messages', {'folder': 'Privé'});

      expect(result.isError, isTrue);
      expect(
        text,
        'There is no folder "Privé" in the inbox or the sent box. The '
        'folders the user made are: $folders, sent/Projecten (id 32000). '
        'Pass one of them as folder, by its path or its id.',
      );
      expect(server.mailbox.actions, isEmpty);

      final (inSent, sentText) = await call('list_messages', {
        'box': 'sent',
        'folder': 'dartschool test',
      });
      expect(inSent.isError, isTrue);
      expect(
        sentText,
        startsWith(
          'There is no folder "dartschool test" in the sent box. The '
          'folders the user made are: inbox/dartschool test (id 30650), ',
        ),
      );
    });

    test('without folders, an unknown folder says that the user has '
        'none', () async {
      server.mailbox.folders.clear();

      final (result, text) = await call('list_messages', {'folder': 'Privé'});

      expect(result.isError, isTrue);
      expect(
        text,
        'There is no folder "Privé": the user has made no folders in '
        "Smartschool's messages. Leave folder out and pass box (inbox, sent "
        'or archive).',
      );
    });

    test('folder with box archive is an error, before anything is '
        'sent', () async {
      final (result, text) = await call('list_messages', {
        'box': 'archive',
        'folder': 'dartschool test',
      });

      expect(result.isError, isTrue);
      expect(
        text,
        'folder names a folder the user made in the inbox or the sent box, '
        'not in the archive: pass box inbox or sent with it, or leave box '
        'out.',
      );
      expect(server.requests, isEmpty);
    });

    test('when nothing matches in a box, the result names the folders the '
        'user made in it, which were not listed', () async {
      const look =
          'To look there, pass one as folder, or use search_messages, which '
          'searches the folders too.';
      expect(
        await ok('list_messages', {'box': 'archive', 'query': 'kalender'}),
        'Archive: no messages match the filters (2 messages checked).\n'
        'Not listed: the folders the user made in the inbox: $folders. '
        '$look',
      );
      expect(
        await ok('list_messages', {'query': 'uitstap'}),
        'Inbox: no messages match the filters (3 messages checked).\n'
        'Not listed: the folders the user made in the inbox: $folders. '
        '$look',
      );
      expect(
        await ok('list_messages', {'box': 'sent', 'query': 'projectweek'}),
        'Sent: no messages match the filters (1 message checked).\n'
        'Not listed: the folders the user made in the sent box: '
        'sent/Projecten (id 32000). $look',
      );

      // Not when something matches, nor for a folder.
      expect(
        await ok('list_messages', {'query': 'oudercontact'}),
        isNot(contains('Not listed')),
      );
      expect(
        await ok('list_messages', {
          'folder': 'dartschool test',
          'query': 'zwembad',
        }),
        'Folder inbox/dartschool test: no messages match the filters (2 '
        'messages checked).',
      );
    });

    test('read_message reads a message in a folder with the box the folder '
        'is in', () async {
      expect(
        await ok('read_message', {'message_id': 401}),
        'Message 401 (Inbox)\n'
        'From: Directie\n'
        'Date: 2024-03-10 09:00\n'
        'To: Jan Peeters\n'
        'Subject: Kalender\n'
        'Attachments: none\n'
        '\n'
        'De kalender van april.',
      );
      expect(
        await ok('read_message', {'message_id': 421, 'box': 'sent'}),
        startsWith('Message 421 (Sent)\nFrom: Jan Peeters\n'),
      );
    });
  });

  test('logs in again when the session expired between calls', () async {
    await ok('list_messages');
    server.expireSession();

    final text = await ok('read_message', {'message_id': 102});

    expect(text, startsWith('Message 102 (Inbox)\n'));
    expect(server.logins, 2);
  });
}
