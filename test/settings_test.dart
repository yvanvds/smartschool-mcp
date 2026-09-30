import 'dart:io';

import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

void main() {
  group('SmartschoolSettings.normalizeHost', () {
    test('reduces what a teacher may type to the host name', () {
      for (final address in [
        'school.smartschool.be',
        '  school.smartschool.be  ',
        'https://school.smartschool.be',
        'https://school.smartschool.be/',
        'HTTP://school.smartschool.be/index.php?module=Messages',
      ]) {
        expect(
          SmartschoolSettings.normalizeHost(address),
          'school.smartschool.be',
          reason: address,
        );
      }
      expect(SmartschoolSettings.normalizeHost('   '), '');
    });
  });

  group('extension settings', () {
    test('are read, trimmed and checked for completeness', () {
      final settings = SmartschoolSettings.read(
        fakeExtensionSettings(
          FakeCredentials(
            mainUrl: ' https://$fakeHost/ ',
            username: ' jan.peeters ',
            password: '',
            mfa: '   ',
          ),
        ),
      );

      expect(settings.host, fakeHost);
      expect(settings.username, 'jan.peeters');
      expect(settings.missing, [Setting.password, Setting.mfa]);
    });

    test('with all four values filled in, nothing is missing', () {
      final settings = SmartschoolSettings.read(fakeExtensionSettings());

      expect(settings.missing, isEmpty);
      final credentials = settings.toCredentials();
      expect(credentials.mainUrl, fakeHost);
      expect(credentials.mfa, fakeTotpSecret);
    });

    test('name each setting by its install-form title and variable', () {
      const source = ExtensionSettings();
      expect(source.name(Setting.mfa), '"2FA-sleutel" (SMARTSCHOOL_MFA)');
      expect(
        source.name(Setting.mainUrl),
        '"Smartschool-adres" (SMARTSCHOOL_MAIN_URL)',
      );
    });
  });

  group('credentials file', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('smartschool_settings_');
      addTearDown(() => dir.delete(recursive: true));
    });

    test('is read from exactly the given path', () {
      final file = File('${dir.path}/dev.yml')
        ..writeAsStringSync(
          'username: jan.peeters\n'
          'password: $fakePassword\n'
          'main_url: https://$fakeHost\n'
          'mfa: $fakeTotpSecret\n',
        );

      final source = CredentialsFile(file.path);
      final settings = SmartschoolSettings.read(source);

      expect(source.path, file.absolute.path);
      expect(settings.host, fakeHost);
      expect(settings.password, fakePassword);
      expect(settings.missing, isEmpty);
      expect(source.name(Setting.mfa), 'mfa');
      expect(source.where, contains(file.absolute.path));
    });

    test('a relative path is resolved against the working directory', () {
      expect(
        CredentialsFile('credentials.yml').path,
        File('credentials.yml').absolute.path,
      );
    });

    test('that does not exist is reported, not looked for elsewhere', () {
      // PathCredentials alone would fall back to a credentials.yml in the
      // working directory, its parents or the home directory.
      final source = CredentialsFile('${dir.path}/missing.yml');

      expect(
        () => source.read(),
        throwsA(
          isA<CredentialsFileException>()
              .having((e) => e.exists, 'exists', isFalse)
              .having((e) => e.path, 'path', source.path),
        ),
      );
    });

    test('that is not valid YAML is reported without quoting it', () {
      final file = File('${dir.path}/broken.yml')
        ..writeAsStringSync('password: [$fakePassword\n');

      final source = CredentialsFile(file.path);

      expect(
        () => source.read(),
        throwsA(
          isA<CredentialsFileException>()
              .having((e) => e.exists, 'exists', isTrue)
              .having((e) => e.toString(), 'toString', contains(file.path))
              .having(
                (e) => e.toString().contains(fakePassword),
                'quotes the file',
                isFalse,
              ),
        ),
      );
    });
  });
}
