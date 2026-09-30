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
    ]) {
      expect(
        () => ServerOptions.parse(args),
        throwsFormatException,
        reason: '$args',
      );
    }
  });
}
