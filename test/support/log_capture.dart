import 'dart:io';

/// Runs [body] with what the server logs captured: `log` (lib/src/log.dart)
/// writes to stderr, which [body] and everything it starts (an MCP server
/// connected in it, the calls it handles) see as [CapturedLog.sink].
/// Returns what [body] returns, with the log.
Future<(T, String)> captureLog<T>(Future<T> Function() body) async {
  final captured = CapturedLog();
  final result = await IOOverrides.runZoned(body, stderr: () => captured);
  return (result, captured.text);
}

/// A stderr that keeps what is written to it, for [captureLog].
final class CapturedLog implements Stdout {
  final _text = StringBuffer();

  /// Everything written so far.
  String get text => _text.toString();

  @override
  void write(Object? object) => _text.write(object);

  @override
  void writeln([Object? object = '']) => _text.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _text.writeAll(objects, separator);

  // Nothing else of a Stdout is used by `log`.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
