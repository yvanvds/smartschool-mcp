import 'dart:io';

import 'package:smartschool_mcp/src/client_app.dart';
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

    test('a 2FA key copied in groups: the white space is removed', () {
      // Also a non-breaking space and a tab, as a copy from a web page may
      // hold.
      for (final key in ['JBSW Y3DP EHPK 3PXP', ' JBSW Y3DP\tEHPK  3PXP ']) {
        final settings = SmartschoolSettings.read(
          fakeExtensionSettings(FakeCredentials(mfa: key)),
        );

        expect(settings.mfa, fakeTotpSecret, reason: key);
        expect(settings.toCredentials().mfa, fakeTotpSecret, reason: key);
        expect(settings.mfaProblem, isNull, reason: key);
        expect(settings.missing, isEmpty, reason: key);
      }
    });

    test('a 2FA key in lower case or with "=" padding is valid', () {
      for (final key in [
        fakeTotpSecret,
        fakeTotpSecret.toLowerCase(),
        'jbsw y3dp EHPK 3pxp',
        // 26 characters, padded to 32 the way RFC 4648 pads them.
        'JBSWY3DPEHPK3PXPJBSWY3DPEH======',
      ]) {
        expect(
          SmartschoolSettings.isTotpSecret(key.replaceAll(' ', '')),
          isTrue,
        );
        expect(
          SmartschoolSettings.read(
            fakeExtensionSettings(FakeCredentials(mfa: key)),
          ).mfaProblem,
          isNull,
          reason: key,
        );
      }
    });

    test('a 6-digit code or a key with other characters is not valid, and '
        'is not missing either', () {
      final problems = {
        // A code of the authenticator app: with a 1, 8, 9 or 0 it is not
        // Base32, with only 2 to 7 it is.
        '123456': 'not Base32',
        '234 567': 'digits only',
        // Hyphens, a 0 for an O, a date of birth.
        'JBSW-Y3DP-EHPK-3PXP': 'not Base32',
        'JBSWY3DPEHPK3PX0': 'not Base32',
        '2010-05-15': 'not Base32',
        '=JBSWY3DPEHPK3PXP': 'not Base32',
      };
      for (final MapEntry(key: key, value: problem) in problems.entries) {
        final settings = SmartschoolSettings.read(
          fakeExtensionSettings(FakeCredentials(mfa: key)),
        );

        expect(settings.mfaProblem, startsWith(problem), reason: key);
        expect(settings.mfaProblem, isNot(contains(key)), reason: key);
        expect(settings.missing, isEmpty, reason: key);
      }
    });

    test('name each setting by its install-form title and variable', () {
      const source = ExtensionSettings();
      expect(source.name(Setting.mfa), '"2FA-sleutel" (SMARTSCHOOL_MFA)');
      expect(
        source.name(Setting.mainUrl),
        '"Smartschool-adres" (SMARTSCHOOL_MAIN_URL)',
      );
    });

    test('are worded for the app the server runs in, once it is '
        'known', () {
      final client = ClientContext();
      final source = ExtensionSettings(client: client);
      String words() => [
        source.label,
        source.name(Setting.mfa),
        source.where,
        source.restart,
      ].join(' | ');

      final claude = words();
      expect(
        claude,
        'extension settings | "2FA-sleutel" (SMARTSCHOOL_MFA) | in the '
        'Smartschool extension settings in Claude Desktop (Settings → '
        'Extensions) | restart Claude Desktop',
      );
      expect(words(), claude, reason: 'the same without a client');

      client.app = ClientApp.codex;
      expect(
        words(),
        'environment variables of the MCP server | SMARTSCHOOL_MFA '
        '("2FA-sleutel") | in the ChatGPT app, under Instellingen (Settings) '
        "→ Plug-ins → MCP's → smartschool → Omgevingsvariabelen (Environment "
        'variables); in the Codex CLI or IDE extension, under '
        r'[mcp_servers.smartschool.env] in %USERPROFILE%\.codex\config.toml '
        '| restart ChatGPT (or Codex)',
      );
      expect(source.logDescription, contains('SMARTSCHOOL_*'));
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

    test('a 2FA key in groups works there too; a 6-digit code (a number in '
        'YAML) is not valid', () {
      SmartschoolSettings readWithKey(String mfa) {
        final file = File('${dir.path}/dev.yml')
          ..writeAsStringSync(
            'username: jan.peeters\n'
            'password: $fakePassword\n'
            'main_url: $fakeHost\n'
            'mfa: $mfa\n',
          );
        return SmartschoolSettings.read(CredentialsFile(file.path));
      }

      final grouped = readWithKey('JBSW Y3DP EHPK 3PXP');
      expect(grouped.mfa, fakeTotpSecret);
      expect(grouped.mfaProblem, isNull);

      final code = readWithKey('123456');
      expect(code.missing, isEmpty);
      expect(code.mfaProblem, startsWith('not Base32'));
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

  group('misnamed settings', () {
    List<(String, Setting?)> found(Iterable<String> names) => [
      for (final variable in MisnamedSetting.find(names))
        (variable.name, variable.meant),
    ];

    test('the right names, in any case, and other variables are not '
        'reported', () {
      expect(
        found([
          for (final setting in Setting.values) setting.envVar,
          'smartschool_mfa',
          'Smartschool_Main_Url',
          'PATH',
          'SYSTEMROOT',
          'USERPROFILE',
          'LOCALAPPDATA',
          'SMARTSCHOOL_MCP_UPDATE_CHECK',
          'SMARTSCHOOL_MCP_UPDATE_URL',
          'SMARTSCHOOL_LIVE_CREDENTIALS',
        ]),
        isEmpty,
      );
    });

    test('a name close to a setting is that setting, mistyped', () {
      expect(
        found([
          'SMARTSCHOOL_MAINURL',
          'SMARTSCHOOL_MFA ',
          'SMARTSHOOL_PASSWORD',
          'SMARTSCHOOL_2FA',
          'SMARTSCHOOL-USERNAME',
          'SMARTSCHOOL_DOWNLOADDIR',
        ]),
        [
          ('SMARTSCHOOL-USERNAME', Setting.username),
          ('SMARTSCHOOL_2FA', Setting.mfa),
          ('SMARTSCHOOL_DOWNLOADDIR', Setting.downloadDir),
          ('SMARTSCHOOL_MAINURL', Setting.mainUrl),
          ('SMARTSCHOOL_MFA ', Setting.mfa),
          ('SMARTSHOOL_PASSWORD', Setting.password),
        ],
      );
    });

    test('another name starting with SMARTSCHOOL is reported without a '
        'guess', () {
      expect(found(['SMARTSCHOOL_WACHTWOORD']), [
        ('SMARTSCHOOL_WACHTWOORD', null),
      ]);
    });

    test('are described by name, never by value', () {
      expect(MisnamedSetting.describe(const []), isNull);
      expect(
        MisnamedSetting.describe(MisnamedSetting.find(['SMARTSCHOOL_MAINURL'])),
        '"SMARTSCHOOL_MAINURL" is set, but that is not the name of a setting: '
        'probably SMARTSCHOOL_MAIN_URL.',
      );
      expect(
        MisnamedSetting.describe(
          MisnamedSetting.find(['SMARTSCHOOL_2FA', 'SMARTSCHOOL_MAINURL']),
        ),
        '"SMARTSCHOOL_2FA" and "SMARTSCHOOL_MAINURL" are set, but those are '
        'not names of settings: probably SMARTSCHOOL_MFA and '
        'SMARTSCHOOL_MAIN_URL.',
      );
      expect(
        MisnamedSetting.describe(
          MisnamedSetting.find(['SMARTSCHOOL_WACHTWOORD']),
        ),
        '"SMARTSCHOOL_WACHTWOORD" is set, but that is not the name of a '
        'setting: the names are SMARTSCHOOL_MAIN_URL, SMARTSCHOOL_USERNAME, '
        'SMARTSCHOOL_PASSWORD, SMARTSCHOOL_MFA and SMARTSCHOOL_DOWNLOAD_DIR.',
      );
    });

    test('extension settings look in their environment; a credentials file '
        'has none', () {
      final source = ExtensionSettings(
        environment: () => {'SMARTSCHOOL_MAINURL': 'x', 'PATH': 'y'},
      );
      expect(
        [for (final variable in source.misnamed) variable.name],
        ['SMARTSCHOOL_MAINURL'],
      );
      expect(CredentialsFile('credentials.yml').misnamed, isEmpty);
    });
  });
}
