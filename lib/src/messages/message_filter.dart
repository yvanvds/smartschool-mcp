import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';

/// Which message headers to show, applied to a whole box (Smartschool always
/// returns all of it).
final class MessageFilter {
  const MessageFilter({
    this.query,
    this.unreadOnly = false,
    this.since,
    this.until,
    this.limit = defaultLimit,
  });

  static const defaultLimit = 50;
  static const maxLimit = 200;

  /// Words that must all occur (case-insensitively) in the subject or the
  /// sender, in any order.
  final String? query;

  final bool unreadOnly;

  /// Only messages from this moment on (inclusive).
  final DateTime? since;

  /// Only messages up to this moment (inclusive).
  final DateTime? until;

  /// How many of the matching messages to return, newest first.
  final int limit;

  /// The lowercased words of [query].
  List<String> get _terms => (query ?? '')
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();

  bool matches(ShortMessage message) => _matches(message, _terms);

  bool _matches(ShortMessage message, List<String> terms) {
    if (unreadOnly && !message.unread) return false;
    if (since case final since? when message.date.isBefore(since)) {
      return false;
    }
    if (until case final until? when message.date.isAfter(until)) {
      return false;
    }
    if (terms.isEmpty) return true;
    final haystack = '${message.subject}\n${message.sender}'.toLowerCase();
    return terms.every(haystack.contains);
  }

  /// The messages in [messages] that match, newest first, and how many
  /// matched before [limit] was applied.
  ({List<ShortMessage> shown, int matching}) apply(
    Iterable<ShortMessage> messages,
  ) {
    final terms = _terms;
    final matching = messages.where((m) => _matches(m, terms)).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    return (shown: matching.take(limit).toList(), matching: matching.length);
  }
}

final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _dateTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?$',
);

/// Parses the date argument [name] ([value] like `2024-03-15` or
/// `2024-03-15 14:30`) as local time, the time zone of Smartschool's dates.
///
/// A date without a time means the start of that day, or with [endOfDay]
/// its last moment, so a `since` and `until` of the same day cover the whole
/// day.
///
/// Throws a [ToolError] for anything else.
DateTime parseDateArgument(String name, String value, {bool endOfDay = false}) {
  final text = value.trim();
  final dateOnly = _dateOnly.firstMatch(text);
  final match = dateOnly ?? _dateTime.firstMatch(text);
  if (match != null) {
    int part(int group) => int.parse(match.group(group) ?? '0');
    final hasTime = dateOnly == null;
    final (year, month, day) = (part(1), part(2), part(3));
    final (hour, minute, second) = hasTime
        ? (part(4), part(5), part(6))
        : endOfDay
        ? (23, 59, 59)
        : (0, 0, 0);
    final date = DateTime(
      year,
      month,
      day,
      hour,
      minute,
      second,
      !hasTime && endOfDay ? 999 : 0,
    );
    // DateTime rolls invalid dates over (February 30 becomes March 1).
    if (date.year == year &&
        date.month == month &&
        date.day == day &&
        date.hour == hour &&
        date.minute == minute) {
      return date;
    }
  }
  throw ToolError(
    '$name must be a date like 2024-03-15, or a date and time like '
    '2024-03-15 14:30; "$value" is not.',
  );
}
