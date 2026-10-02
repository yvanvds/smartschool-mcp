import 'package:smartschool_mcp/src/options.dart';
import 'package:test/test.dart';

void main() {
  test('no arguments: no credentials file (use the extension settings)', () {
    expect(ServerOptions.parse([]).credentialsPath, isNull);
  });

  test('--credentials <path> and --credentials=<path>', () {
    expect(
      ServerOptions.parse(['--credentials', 'credentials.yml']).credentialsPath,
      'credentials.yml',
    );
    expect(
      ServerOptions.parse(['--credentials=C:\\dev\\c.yml']).credentialsPath,
      'C:\\dev\\c.yml',
    );
  });

  test('rejects a missing or empty path, a repeated flag and unknown '
      'arguments', () {
    for (final args in [
      ['--credentials'],
      ['--credentials='],
      ['--credentials', '  '],
      ['--credentials', 'a.yml', '--credentials', 'b.yml'],
      ['--verbose'],
      ['credentials.yml'],
      ['--install', '--credentials', 'a.yml'],
      ['--no-clipboard'],
    ]) {
      expect(
        () => ServerOptions.parse(args),
        throwsFormatException,
        reason: '$args',
      );
    }
  });

  test('--install, with or without --no-clipboard', () {
    final install = ServerOptions.parse(['--install']);
    expect(install.install, isTrue);
    expect(install.clipboard, isTrue);
    final quiet = ServerOptions.parse(['--no-clipboard', '--install']);
    expect(quiet.install, isTrue);
    expect(quiet.clipboard, isFalse);
    expect(ServerOptions.parse([]).install, isFalse);
  });

  test('installs with --install, or when started without options from a '
      'console (a double-click); serves when an MCP client starts it with '
      'pipes, or with a credentials file', () {
    bool installs(List<String> args, {required bool interactive}) =>
        ServerOptions.parse(args).installs(interactive: interactive);

    expect(installs([], interactive: true), isTrue);
    expect(installs(['--install'], interactive: false), isTrue);
    expect(installs([], interactive: false), isFalse);
    expect(installs(['--credentials', 'c.yml'], interactive: true), isFalse);
  });
}
