/// `search_messages`, called over MCP on the real server, session, library
/// and cache, against a fake Smartschool.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/message_cache.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/search_messages_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

void _fill(FakeMailbox mailbox) {
  mailbox.inbox.addAll([
    FakeMessage(
      id: 101,
      sender: 'Directie',
      subject: 'Planning derde trimester',
      date: '2024-03-14 16:05',
      body:
          "<p>Beste collega's,</p><p>De <b>facultatieve verlofdag</b> valt "
          'op maandag 3 juni.</p>',
    ),
    FakeMessage(
      id: 102,
      sender: 'An Claes',
      subject: 'Re: Toets wiskunde',
      date: '2024-03-15 08:00',
      body: '<p>Prima, bedankt!</p>',
    ),
    FakeMessage(
      id: 103,
      sender: 'Secretariaat',
      subject: 'Verlofaanvraag',
      date: '2024-03-13 10:30',
      unread: true,
      body: '<p>Uw verlof op 3 juni is goedgekeurd.</p>',
    ),
  ]);
  mailbox.archive.addAll([
    FakeMessage(
      id: 201,
      sender: 'Directie',
      subject: 'Jaarkalender',
      date: '2024-02-20 12:00',
      body:
          '<ul><li>Facultatieve verlofdag: 3 juni</li>'
          '<li>Pedagogische studiedag: 12 maart</li></ul>',
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
      listedAs: 'Els Wouters',
      subject: 'Verlofdag',
      date: '2024-03-12 11:00',
      to: ['Els Wouters'],
      body: '<p>Ik neem de facultatieve verlofdag op.</p>',
    ),
  );
}

const _line101 =
    '- inbox | id 101 | 2024-03-14 16:05 | from Directie | Planning derde '
    'trimester';
const _line201 =
    '- archive | id 201 | 2024-02-20 12:00 | from Directie | Jaarkalender';

/// The expected result of searching the fixture for `facultatieve
/// verlofdag`.
const _verlofdag =
    'Inbox and Archive: 2 of the 5 messages searched contain all of: '
    'facultatieve, verlofdag, newest first.\n'
    '$_line101\n'
    "  Beste collega's, De facultatieve verlofdag valt op maandag 3 juni.\n"
    '$_line201\n'
    '  - Facultatieve verlofdag: 3 juni - Pedagogische studiedag: 12 maart';

void main() {
  late FakeSmartschool server;
  late Directory cookies;
  late Directory cacheFolder;
  late ServerConnection connection;

  /// Starts a server with its own session on the same cookie and message
  /// caches, like a new server process.
  Future<ServerConnection> start() async {
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, cookies),
    );
    addTearDown(session.close);
    final (connection, _) = await connect(
      tools: [searchMessagesTool(session, MessageTextCache(cacheFolder))],
    );
    return connection;
  }

  setUp(() async {
    server = FakeSmartschool();
    _fill(server.mailbox);
    cookies = await tempCache();
    cacheFolder = await tempCache();
    connection = await start();
  });

  Future<(CallToolResult, String)> call(
    Map<String, Object?> arguments, [
    ServerConnection? on,
  ]) => callTool(on ?? connection, 'search_messages', arguments);

  /// Searches and expects a successful result without HTML or XML.
  Future<String> ok(
    Map<String, Object?> arguments, [
    ServerConnection? on,
  ]) async {
    final (result, text) = await call(arguments, on);
    expect(result.isError, isNot(true), reason: text);
    expect(text, isNot(contains('<')), reason: 'HTML or XML in the output');
    return text;
  }

  Future<String> error(Map<String, Object?> arguments) async {
    final (result, text) = await call(arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  /// The `show message` requests (message downloads) so far.
  List<String> downloads() => [
    for (final action in server.mailbox.actions)
      if (action.startsWith('show message ')) action,
  ];

  /// The ids of the downloaded messages, with how often each was
  /// downloaded.
  Map<int, int> downloadCounts() {
    final counts = <int, int>{};
    for (final action in downloads()) {
      final id = int.parse(RegExp(r'msgID=(\d+)').firstMatch(action)![1]!);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  test('is listed as read-only, requires a query and says how to read a '
      'hit and when messages are left unsearched', () async {
    final tool = (await connection.listTools(ListToolsRequest())).tools.single;

    expect(tool.name, 'search_messages');
    expect(tool.toolAnnotations?.readOnlyHint, isTrue);
    expect(tool.toolAnnotations?.destructiveHint, isNot(true));
    expect(tool.description, contains('call read_message with its id and box'));
    expect(tool.description, contains('at most 100 are downloaded per search'));
    expect(tool.description, contains('keeps them on this PC'));
    expect(tool.description, contains('newest 50 messages of each box'));
    final schema = tool.inputSchema;
    expect(schema.required, ['query']);
    expect(schema.properties!.keys, [
      'query',
      'boxes',
      'since',
      'until',
      'limit',
    ]);
    expect(schema.properties!['boxes'], {
      'type': 'array',
      'description': isA<String>(),
      'default': ['inbox', 'archive'],
      'minItems': 1,
      'items': {
        'enum': ['inbox', 'sent', 'archive'],
        'type': 'string',
      },
    });
  });

  test('finds the words in the text of inbox and archive messages, newest '
      'first, with a snippet; downloads each text once, with its recipients '
      'limited', () async {
    expect(await ok({'query': 'Facultatieve VERLOFDAG'}), _verlofdag);

    expect(server.mailbox.actions.where((a) => a.startsWith('message list')), [
      startsWith('message list boxID=0 boxType=inbox '),
      startsWith('message list boxID=305 boxType=inbox '),
    ]);
    expect(
      downloads(),
      unorderedEquals([
        for (final id in [101, 102, 103, 201, 202])
          'show message boxType=inbox limitList=true msgID=$id',
      ]),
    );
  });

  test('a second search is served from the cache, also after a restart, '
      'and gives the same result', () async {
    final first = await ok({'query': 'facultatieve verlofdag'});
    server.mailbox.actions.clear();

    expect(await ok({'query': 'facultatieve verlofdag'}), first);
    expect(await ok({'query': 'goedgekeurd'}), contains('id 103'));
    final restarted = await start();
    expect(await ok({'query': 'facultatieve verlofdag'}, restarted), first);

    expect(downloads(), isEmpty);
    expect(server.logins, 1, reason: 'the restart reuses the saved session');
    for (final id in [101, 102, 103, 201, 202]) {
      expect(
        await MessageTextCache(cacheFolder).read(BoxType.inbox, id),
        isNotNull,
        reason: 'text of $id saved',
      );
    }
  });

  test('matches the subject and the sender too; an empty message shows '
      '"(no text)"', () async {
    expect(
      await ok({'query': 'secretariaat goedgekeurd'}),
      'Inbox and Archive: 1 of the 5 messages searched contains all of: '
      'secretariaat, goedgekeurd, newest first.\n'
      '- inbox | id 103 | 2024-03-13 10:30 | from Secretariaat | '
      'Verlofaanvraag | unread\n'
      '  Uw verlof op 3 juni is goedgekeurd.',
    );
    expect(
      await ok({'query': 'oudercontact'}),
      'Inbox and Archive: 1 of the 5 messages searched contains all of: '
      'oudercontact, newest first.\n'
      '- archive | id 202 | 2024-01-10 09:15 | from Jan Peeters | '
      'Oudercontact januari\n'
      '  (no text)',
    );
  });

  test('boxes: only the boxes named, in a fixed order', () async {
    expect(
      await ok({
        'query': 'verlofdag',
        'boxes': ['sent'],
      }),
      'Sent: 1 of the 1 message searched contains all of: verlofdag, newest '
      'first.\n'
      '- sent | id 301 | 2024-03-12 11:00 | to Els Wouters | Verlofdag\n'
      '  Ik neem de facultatieve verlofdag op.',
    );
    expect(downloads(), [
      'show message boxType=outbox limitList=true msgID=301',
    ]);

    final all = await ok({
      'query': 'facultatieve verlofdag',
      'boxes': ['archive', 'sent', 'inbox', 'archive'],
    });
    expect(
      all,
      startsWith(
        'Inbox, Sent and Archive: 3 of the 6 messages searched contain all '
        'of: facultatieve, verlofdag, newest first.\n'
        '$_line101\n',
      ),
    );
    expect(all, contains('- sent | id 301 '));
  });

  test(
    'since and until: messages outside the range are not downloaded',
    () async {
      expect(
        await ok({'query': 'verlofdag', 'since': '2024-03-14'}),
        'Inbox and Archive: 1 of the 2 messages searched contains all of: '
        'verlofdag, newest first.\n'
        '$_line101\n'
        "  Beste collega's, De facultatieve verlofdag valt op maandag 3 juni.",
      );
      expect(downloadCounts().keys, unorderedEquals([101, 102]));

      expect(
        await ok({
          'query': 'verlofdag',
          'since': '2024-02-01',
          'until': '2024-02-29 12:00',
        }),
        startsWith(
          'Inbox and Archive: 1 of the 1 message searched contains all of: '
          'verlofdag, newest first.\n$_line201\n',
        ),
      );
      expect(
        await ok({'query': 'verlofdag', 'since': '2024-04-01'}),
        'Inbox and Archive: no messages in the date range (5 checked).',
      );
      expect(downloadCounts().keys, unorderedEquals([101, 102, 201]));
    },
  );

  test('no match, and empty boxes', () async {
    expect(
      await ok({'query': 'zwembad verlofdag'}),
      'Inbox and Archive: none of the 5 messages searched contains all of: '
      'zwembad, verlofdag.',
    );

    server.mailbox
      ..inbox.clear()
      ..archive.clear();
    expect(await ok({'query': 'zwembad'}), 'Inbox and Archive: no messages.');
  });

  test('limit: only the newest hits, and says so', () async {
    expect(
      await ok({'query': 'verlof', 'limit': 1.0}),
      'Inbox and Archive: 3 of the 5 messages searched contain all of: '
      'verlof; showing the newest 1 (raise limit to see the rest), newest '
      'first.\n'
      '$_line101\n'
      "  Beste collega's, De facultatieve verlofdag valt op maandag 3 juni.",
    );
  });

  test('invalid arguments: an error that says what to fix, before '
      'contacting Smartschool', () async {
    expect(
      await error({'query': ' "" ? '}),
      'query is empty: pass the words to look for.',
    );
    expect(
      await error({
        'query': 'verlof',
        'since': '2024-03-15',
        'until': '2024-03-01',
      }),
      'since must not be later than until.',
    );
    expect(
      await error({'query': 'verlof', 'since': 'gisteren'}),
      contains('"gisteren" is not'),
    );
    expect(await error({}), contains('query'));
    expect(
      await error({
        'query': 'verlof',
        'boxes': ['trash'],
      }),
      contains('trash'),
    );
    expect(server.requests, isEmpty);
  });

  test('downloads at most 100 texts per search, the newest first, and says '
      'which were left; the next search downloads the rest', () async {
    String minute(int i) => i.toString().padLeft(2, '0');
    server.mailbox
      ..inbox.clear()
      ..archive.clear()
      ..sent.clear();
    for (var i = 0; i < 50; i++) {
      final body =
          '<p>Bericht $i${i == 49 ? ': het zwembad is dicht' : ''}</p>';
      server.mailbox
        ..inbox.add(
          FakeMessage(
            id: 1000 + i,
            sender: 'Collega $i',
            subject: 'Inbox $i',
            date: '2024-03-10 10:${minute(i)}',
            body: body,
          ),
        )
        ..archive.add(
          FakeMessage(
            id: 2000 + i,
            sender: 'Collega $i',
            subject: 'Archief $i',
            date: '2024-02-10 10:${minute(i)}',
            body: '<p>Bericht $i</p>',
          ),
        )
        ..sent.add(
          FakeMessage(
            id: 3000 + i,
            sender: 'Jan Peeters',
            listedAs: 'Collega $i',
            subject: 'Verstuurd $i',
            date: '2024-01-10 10:${minute(i)}',
            body: '<p>Bericht $i${i == 0 ? ': zwembad' : ''}</p>',
          ),
        );
    }
    const arguments = {
      'query': 'zwembad',
      'boxes': ['inbox', 'sent', 'archive'],
    };
    const pageNote =
        'Note: Smartschool only returns the newest 50 messages of a box, so '
        'older messages in Inbox, Sent and Archive were not searched.';
    const hit1049 =
        '- inbox | id 1049 | 2024-03-10 10:49 | from Collega 49 | Inbox 49\n'
        '  Bericht 49: het zwembad is dicht';

    expect(
      await ok(arguments),
      'Inbox, Sent and Archive: 1 of the 100 messages searched contains all '
      'of: zwembad, newest first.\n'
      '$hit1049\n'
      'Not searched: the 50 oldest messages, because at most 100 message '
      'texts are downloaded per search. Search again to search them too: '
      'downloaded texts are kept, so the next search only downloads the '
      'rest.\n'
      '$pageNote',
    );
    expect(downloadCounts().keys.toSet(), {
      for (var i = 0; i < 50; i++) ...{1000 + i, 2000 + i},
    });
    server.mailbox.actions.clear();

    expect(
      await ok(arguments),
      'Inbox, Sent and Archive: 2 of the 150 messages searched contain all '
      'of: zwembad, newest first.\n'
      '$hit1049\n'
      '- sent | id 3000 | 2024-01-10 10:00 | to Collega 0 | Verstuurd 0\n'
      '  Bericht 0: zwembad\n'
      '$pageNote',
    );
    expect(downloadCounts().keys.toSet(), {
      for (var i = 0; i < 50; i++) 3000 + i,
    });
    server.mailbox.actions.clear();

    await ok(arguments);
    expect(downloads(), isEmpty);
  });

  test('downloads at most 4 texts at the same time', () async {
    for (var i = 0; i < 12; i++) {
      server.mailbox.inbox.add(
        FakeMessage(
          id: 500 + i,
          sender: 'Collega',
          subject: 'Bericht $i',
          date: '2024-03-01 09:${i.toString().padLeft(2, '0')}',
          body: '<p>Tekst $i</p>',
        ),
      );
    }
    server.latency = const Duration(milliseconds: 10);

    await ok({'query': 'tekst'});

    expect(downloads(), hasLength(17));
    expect(server.maxInFlight, downloadConcurrency);
    expect(downloadConcurrency, 4);
  });

  test('when the session expires halfway: logs in again and only downloads '
      'what was not saved yet', () async {
    var shows = 0;
    server.expireSessionBefore(
      (request) => '${request.data}'.contains('show message') && ++shows == 3,
    );

    expect(await ok({'query': 'facultatieve verlofdag'}), _verlofdag);

    expect(server.logins, 2);
    final counts = downloadCounts();
    expect(counts.keys, unorderedEquals([101, 102, 103, 201, 202]));
    expect(counts.values, everyElement(lessThanOrEqualTo(2)));
    expect(
      counts.values.where((n) => n == 1).length,
      greaterThanOrEqualTo(2),
      reason:
          'texts saved before the session expired are not downloaded '
          'again',
    );
    server.mailbox.actions.clear();
    await ok({'query': 'facultatieve verlofdag'});
    expect(downloads(), isEmpty);
  });

  test('a listed message that Smartschool no longer returns is skipped, '
      'said so, and not saved', () async {
    server.mailbox.vanished.add(103);

    final text = await ok({'query': 'verlof'});

    expect(
      text,
      startsWith(
        'Inbox and Archive: 2 of the 4 messages searched contain all of: '
        'verlof, newest first.\n$_line101\n',
      ),
    );
    expect(text, isNot(contains('id 103')));
    expect(
      text,
      endsWith(
        '\nSkipped: 1 listed message that Smartschool no longer returned '
        '(deleted in the meantime?).',
      ),
    );
    expect(
      await MessageTextCache(cacheFolder).read(BoxType.inbox, 103),
      isNull,
    );
  });

  test('a page-size note when a box returns 50 messages', () async {
    for (var i = 0; i < 48; i++) {
      server.mailbox.archive.add(
        FakeMessage(
          id: 700 + i,
          sender: 'Directie',
          subject: 'Oud $i',
          date: '2023-12-01 10:${i.toString().padLeft(2, '0')}',
        ),
      );
    }
    server.mailbox.archive.add(
      FakeMessage(
        id: 800,
        sender: 'Directie',
        subject: 'Nog ouder',
        date: '2023-11-01 10:00',
        body: '<p>zwembad</p>',
      ),
    );

    final text = await ok({'query': 'zwembad'});

    expect(
      text,
      'Inbox and Archive: none of the 53 messages searched contains all of: '
      'zwembad.\n'
      'Note: Smartschool only returns the newest 50 messages of a box, so '
      'older messages in Archive were not searched.',
    );
  });
}
