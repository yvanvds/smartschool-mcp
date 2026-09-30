import 'server_tool.dart';

// Reading the integer arguments of a tool call.
//
// dart_mcp checks the arguments against the tool's input schema before the
// handler runs. Its integer schema accepts any whole number, also one written
// with a decimal part (`101.0`), which JSON decodes to a double; reading that
// with `as int` throws. These functions accept an int and a whole-number
// double, and throw a [ToolError] that says what to fix for anything else,
// so every tool reads integers the same way.

/// The integer argument [name] of [arguments], or null when it is absent.
///
/// Throws a [ToolError] when the value is not a whole number.
int? intArgument(Map<String, Object?> arguments, String name) =>
    switch (arguments[name]) {
      null => null,
      final value => _wholeNumber(value, name),
    };

/// The integer argument [name] of [arguments].
///
/// Throws a [ToolError] when it is absent or not a whole number.
int requiredIntArgument(Map<String, Object?> arguments, String name) =>
    intArgument(arguments, name) ?? (throw ToolError('$name is required.'));

/// The list argument [name] of [arguments] as integers, in the order given.
///
/// Throws a [ToolError] when it is absent, not a list, or holds something
/// that is not a whole number.
List<int> intListArgument(Map<String, Object?> arguments, String name) =>
    switch (arguments[name]) {
      final List<Object?> values => [
        for (final value in values) _wholeNumber(value, 'each item of $name'),
      ],
      null => throw ToolError('$name is required.'),
      final value => throw ToolError(
        '$name must be a list of whole numbers; ${_show(value)} is not.',
      ),
    };

/// [value] as an int when it is a whole number: an int, or a double without
/// a fractional part that fits in an int.
int _wholeNumber(Object? value, String what) {
  if (value is int) return value;
  if (value is double && value.isFinite) {
    // toInt() clamps a double beyond the int range, so compare.
    final whole = value.toInt();
    if (whole == value) return whole;
  }
  throw ToolError('$what must be a whole number; ${_show(value)} is not.');
}

String _show(Object? value) => value is String ? '"$value"' : '$value';
