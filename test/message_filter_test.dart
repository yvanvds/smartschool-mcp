import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/message_filter.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

ShortMessage header(
  int id,
  String date, {
  String sender = 'Jan Peeters',
  String subject = 'Onderwerp',
  bool unread = false,
}) => ShortMessage(
  id: id,
  sender: sender,
  fromImage: '',
  subject: subject,
  date: DateTime.parse(date),
  status: unread ? 0 : 1,
  attachment: 0,
  unread: unread,
  deleted: false,
  allowReply: true,
  allowReplyEnabled: true,
  hasReply: false,
  hasForward: false,
  realBox: 'inbox',
);

List<int> ids(Iterable<ShortMessage> messages) => [
  for (final message in messages) message.id,
];

void main() {
  final box = [
    header(1, '2024-03-10 09:00', subject: 'Oudercontact maart'),
    header(
      2,
      '2024-03-15 08:00',
      sender: 'An Claes',
      subject: 'Re: Toets wiskunde',
      unread: true,
    ),
    header(3, '2024-03-14 23:59', sender: 'Directie', subject: 'Personeel'),
    header(4, '2024-03-15 16:30', subject: 'Uitstap', unread: true),
    header(5, '2024-03-15 08:00', sender: 'Secretariaat', subject: 'Verlof'),
    header(6, '2024-03-16 00:00', sender: 'Directie', subject: 'OUDERCONTACT'),
  ];

  group('MessageFilter', () {
    test('without filters: all messages, newest first, ties by id', () {
      final (:shown, :matching) = const MessageFilter().apply(box);

      expect(ids(shown), [6, 4, 5, 2, 3, 1]);
      expect(matching, 6);
    });

    test('limit keeps the newest and still counts all matches', () {
      final (:shown, :matching) = const MessageFilter(limit: 2).apply(box);

      expect(ids(shown), [6, 4]);
      expect(matching, 6);
    });

    test('query matches subject and sender case-insensitively', () {
      expect(ids(const MessageFilter(query: 'oudercontact').apply(box).shown), [
        6,
        1,
      ]);
      expect(ids(const MessageFilter(query: 'DIRECTIE').apply(box).shown), [
        6,
        3,
      ]);
      expect(ids(const MessageFilter(query: 'toets').apply(box).shown), [2]);
    });

    test('every word of the query must occur, in subject or sender, in '
        'any order', () {
      expect(
        ids(
          const MessageFilter(query: 'oudercontact directie').apply(box).shown,
        ),
        [6],
      );
      expect(
        ids(const MessageFilter(query: '  wiskunde   claes ').apply(box).shown),
        [2],
      );
      expect(
        const MessageFilter(query: 'oudercontact april').apply(box).matching,
        0,
      );
    });

    test('an empty or blank query filters nothing', () {
      expect(const MessageFilter(query: '').apply(box).matching, 6);
      expect(const MessageFilter(query: '   ').apply(box).matching, 6);
    });

    test('unreadOnly keeps the unread messages', () {
      expect(ids(const MessageFilter(unreadOnly: true).apply(box).shown), [
        4,
        2,
      ]);
    });

    test('since and until are inclusive', () {
      final filter = MessageFilter(
        since: DateTime(2024, 3, 15, 8),
        until: DateTime(2024, 3, 15, 16, 30),
      );
      expect(ids(filter.apply(box).shown), [4, 5, 2]);
    });

    test('a date-only since and until cover whole days', () {
      final filter = MessageFilter(
        since: parseDateArgument('since', '2024-03-14'),
        until: parseDateArgument('until', '2024-03-15', endOfDay: true),
      );
      expect(ids(filter.apply(box).shown), [4, 5, 2, 3]);
    });

    test('filters combine', () {
      final filter = MessageFilter(
        query: 'jan',
        unreadOnly: true,
        since: DateTime(2024, 3, 15),
        limit: 5,
      );
      expect(ids(filter.apply(box).shown), [4]);
    });
  });

  group('parseDateArgument', () {
    test('a date is the start of the day, or with endOfDay its end', () {
      expect(parseDateArgument('since', '2024-03-15'), DateTime(2024, 3, 15));
      expect(
        parseDateArgument('until', ' 2024-03-15 ', endOfDay: true),
        DateTime(2024, 3, 15, 23, 59, 59, 999),
      );
    });

    test('a date and time is taken as given, in local time', () {
      expect(
        parseDateArgument('since', '2024-03-15 14:30'),
        DateTime(2024, 3, 15, 14, 30),
      );
      expect(
        parseDateArgument('until', '2024-03-15T14:30:15', endOfDay: true),
        DateTime(2024, 3, 15, 14, 30, 15),
      );
    });

    for (final invalid in [
      '15/03/2024',
      'gisteren',
      '2024-3-15',
      '2024-02-30',
      '2024-13-01',
      '2024-03-15 25:00',
      '2024-03-15 14:60',
      '2024-03-15T14:30:00Z',
      '',
    ]) {
      test('rejects "$invalid" with a message naming the argument', () {
        expect(
          () => parseDateArgument('since', invalid),
          throwsA(
            isA<ToolError>().having(
              (e) => e.message,
              'message',
              allOf(
                startsWith('since must be a date like 2024-03-15'),
                contains('"$invalid"'),
              ),
            ),
          ),
        );
      });
    }
  });
}
