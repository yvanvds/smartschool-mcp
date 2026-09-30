import 'dart:convert';
import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/message_cache.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/settings.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

void main() {
  late Directory root;
  late Directory folder;
  late MessageTextCache cache;

  setUp(() async {
    root = await tempCache();
    folder = Directory('${root.path}${Platform.pathSeparator}messages');
    cache = MessageTextCache(folder);
  });

  File file(String name) =>
      File('${folder.path}${Platform.pathSeparator}$name');

  test('a saved text is read back, also by a new cache on the same '
      'folder', () async {
    expect(folder.existsSync(), isFalse, reason: 'created on first write');

    await cache.write(BoxType.inbox, 101, 'Beste collega’s,\n\nÉén regel.');

    expect(
      await cache.read(BoxType.inbox, 101),
      'Beste collega’s,\n\nÉén regel.',
    );
    expect(
      await MessageTextCache(folder).read(BoxType.inbox, 101),
      'Beste collega’s,\n\nÉén regel.',
    );
    expect(folder.listSync().map((f) => f.uri.pathSegments.last), [
      'inbox-101.json',
    ], reason: 'no temporary file left behind');
    expect(jsonDecode(file('inbox-101.json').readAsStringSync()), {
      'format': MessageTextCache.format,
      'id': 101,
      'text': 'Beste collega’s,\n\nÉén regel.',
    });
  });

  test('an empty text is saved too', () async {
    await cache.write(BoxType.inbox, 103, '');

    expect(await cache.read(BoxType.inbox, 103), '');
  });

  test('a message that was not saved is null', () async {
    expect(await cache.read(BoxType.inbox, 101), isNull);
    await cache.write(BoxType.inbox, 101, 'inbox');
    expect(await cache.read(BoxType.inbox, 102), isNull);
  });

  test('the inbox and the sent box are kept apart', () async {
    await cache.write(BoxType.inbox, 9001, 'received');
    await cache.write(BoxType.sent, 9001, 'sent');

    expect(await cache.read(BoxType.inbox, 9001), 'received');
    expect(await cache.read(BoxType.sent, 9001), 'sent');
    expect(file('outbox-9001.json').existsSync(), isTrue);
  });

  test('saving again replaces the text', () async {
    await cache.write(BoxType.inbox, 101, 'old');
    await cache.write(BoxType.inbox, 101, 'new');

    expect(await cache.read(BoxType.inbox, 101), 'new');
  });

  test('a damaged file, another format or another id counts as not '
      'saved', () async {
    await folder.create(recursive: true);
    file('inbox-1.json').writeAsStringSync('{"format":1,"id":1,"te');
    file('inbox-2.json').writeAsStringSync(
      jsonEncode({'format': MessageTextCache.format + 1, 'id': 2, 'text': 'x'}),
    );
    file('inbox-3.json').writeAsStringSync(
      jsonEncode({'format': MessageTextCache.format, 'id': 4, 'text': 'x'}),
    );
    file('inbox-5.json').writeAsStringSync('[]');

    for (final id in [1, 2, 3, 5]) {
      expect(await cache.read(BoxType.inbox, id), isNull, reason: '$id');
    }
    await cache.write(BoxType.inbox, 1, 'repaired');
    expect(await cache.read(BoxType.inbox, 1), 'repaired');
  });

  test('a folder that cannot be created: nothing is saved, and nothing '
      'is thrown', () async {
    // A file where the folder should be.
    final blocked = File('${root.path}${Platform.pathSeparator}blocked')
      ..writeAsStringSync('');
    final broken = MessageTextCache(Directory(blocked.path));

    await broken.write(BoxType.inbox, 101, 'text');

    expect(await broken.read(BoxType.inbox, 101), isNull);
  });

  test('of a session: messages/<host> in the user\'s cache folder, worked '
      'out on first use', () async {
    var reads = 0;
    final session = SmartschoolSession(
      ExtensionSettings(
        read: () {
          reads++;
          return FakeCredentials();
        },
      ),
    );
    final cache = MessageTextCache.of(session);
    expect(reads, 0, reason: 'the settings are read on first use');

    final settings = session.settings;
    expect(
      cache.directory.path,
      [
        settings.cacheDirectory,
        'messages',
        fakeHost,
      ].join(Platform.pathSeparator),
    );
    expect(
      settings.cacheDirectory,
      SmartschoolSettings.userCacheDirectory('jan.peeters'),
    );
  });
}
