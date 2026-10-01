/// Who a reply goes to ([loadReplyRecipients]), with the real library
/// against a fake Smartschool whose reply forms are filled in as seen live.
library;

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/message_box.dart';
import 'package:smartschool_mcp/src/messages/reply_recipients.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

const _me = fakeDisplayName;

void main() {
  late FakeSmartschool server;
  late SmartschoolSession session;

  setUp(() async {
    server = FakeSmartschool();
    server.mailbox
      ..inbox.addAll([
        FakeMessage(
          id: 101,
          sender: 'An Claes',
          subject: 'Toets wiskunde',
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
          sender: 'Secretariaat',
          subject: 'Verlof',
          date: '2024-03-13 08:00',
          to: ['Els Wouters'],
          cc: [_me],
        ),
      ])
      ..archive.add(
        FakeMessage(
          id: 201,
          sender: 'Directie',
          subject: 'Personeelsvergadering',
          date: '2024-02-20 12:00',
          to: [_me, 'An Claes'],
        ),
      )
      ..sent.addAll([
        FakeMessage(
          id: 301,
          sender: _me,
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
        FakeMessage(
          id: 303,
          sender: _me,
          subject: 'Oudercontact',
          date: '2024-03-10 11:00',
          to: ['Els Wouters'],
          cc: ['An Claes'],
          bcc: ['Piet Janssens'],
        ),
        FakeMessage(
          id: 304,
          sender: _me,
          subject: 'Rapport',
          date: '2024-03-09 11:00',
          bcc: ['Els Wouters', 'An Claes'],
        ),
      ]);
    session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
  });

  /// The recipients of a reply to [id] in [box], as `to: A, B | cc: C`
  /// (`-` for none).
  Future<String> recipients(
    MessageBox box,
    int id, {
    required bool replyAll,
  }) async {
    final result = await session.run((client) async {
      final messages = MessagesService(client);
      try {
        return await loadReplyRecipients(
          client,
          messages,
          box,
          id,
          replyAll: replyAll,
        );
      } finally {
        await messages.dispose();
      }
    });
    for (final user in [...result.to, ...result.cc]) {
      // What sendMessage registers each recipient with.
      expect(user.userId, server.mailbox.userId(user.displayName));
      expect(user.ssId, FakeMailbox.platformId);
      expect(user.userLt, 0);
    }
    String names(List<MessageSearchUser> users) =>
        users.isEmpty ? '-' : users.map((user) => user.displayName).join(', ');
    return 'to: ${names(result.to)} | cc: ${names(result.cc)}';
  }

  group('a received message (inbox)', () {
    test('a plain reply goes to the sender only', () async {
      expect(
        await recipients(MessageBox.inbox, 101, replyAll: false),
        'to: An Claes | cc: -',
      );
      expect(
        await recipients(MessageBox.inbox, 103, replyAll: false),
        'to: Secretariaat | cc: -',
      );
    });

    test('a reply to all goes to the sender and the To recipients in To and '
        'the CC recipients in CC, without the user', () async {
      expect(
        await recipients(MessageBox.inbox, 101, replyAll: true),
        'to: Els Wouters, An Claes | cc: Piet Janssens',
      );
      expect(
        await recipients(MessageBox.inbox, 103, replyAll: true),
        'to: Els Wouters, Secretariaat | cc: -',
      );
    });

    test('a message the user sent to themself: both go to the user', () async {
      expect(
        await recipients(MessageBox.inbox, 102, replyAll: false),
        'to: $_me | cc: -',
      );
      expect(
        await recipients(MessageBox.inbox, 102, replyAll: true),
        'to: $_me | cc: -',
      );
    });
  });

  test('an archived message is answered like an inbox message', () async {
    expect(
      await recipients(MessageBox.archive, 201, replyAll: false),
      'to: Directie | cc: -',
    );
    expect(
      await recipients(MessageBox.archive, 201, replyAll: true),
      'to: An Claes, Directie | cc: -',
    );
  });

  group('a sent message', () {
    test('a plain reply goes to its To recipients, not to the user (whom '
        "Smartschool's reply form names)", () async {
      expect(
        await recipients(MessageBox.sent, 301, replyAll: false),
        'to: Els Wouters, An Claes | cc: -',
      );
    });

    test('a reply to all also goes to its CC recipients', () async {
      expect(
        await recipients(MessageBox.sent, 301, replyAll: true),
        'to: Els Wouters, An Claes | cc: Piet Janssens',
      );
    });

    test('sent only to the user: both go to the user, as for its inbox '
        'copy', () async {
      expect(
        await recipients(MessageBox.sent, 302, replyAll: false),
        'to: $_me | cc: -',
      );
      expect(
        await recipients(MessageBox.sent, 302, replyAll: true),
        'to: $_me | cc: -',
      );
    });

    test('the BCC recipients are left out, so a reply never reveals '
        'them', () async {
      expect(
        await recipients(MessageBox.sent, 303, replyAll: false),
        'to: Els Wouters | cc: -',
      );
      expect(
        await recipients(MessageBox.sent, 303, replyAll: true),
        'to: Els Wouters | cc: An Claes',
      );
      expect(
        await recipients(MessageBox.sent, 304, replyAll: true),
        'to: - | cc: -',
      );
    });
  });

  test('only loads the reply forms and the message: nothing is sent and no '
      'recipient is added to a form', () async {
    for (final box in [MessageBox.inbox, MessageBox.sent]) {
      for (final replyAll in [false, true]) {
        await recipients(
          box,
          box == MessageBox.sent ? 301 : 101,
          replyAll: replyAll,
        );
      }
    }

    // GETs of the forms, and for a sent message the message itself (a
    // `show message` POST to the XML dispatcher).
    final posts = server.requests.where(
      (r) =>
          r.startsWith('POST ') && !r.contains('/login') && !r.contains('2fa'),
    );
    expect(server.mailbox.actions, everyElement(startsWith('show message ')));
    expect(posts, hasLength(server.mailbox.actions.length));
    expect(server.mailbox.submits, 0);
  });
}
