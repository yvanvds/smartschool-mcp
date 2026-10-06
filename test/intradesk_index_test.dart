/// The Intradesk helpers in `lib/src/intradesk/`: items, the index and its
/// cache, name matching, formatting and the id argument.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_access.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_cache.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_format.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_index.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_search.dart';
import 'package:smartschool_mcp/src/intradesk/intradesk_walk.dart';
import 'package:smartschool_mcp/src/messages/message_search.dart';
import 'package:smartschool_mcp/src/tools/server_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';

IntradeskItem _folder(String id, String name, {String parent = ''}) =>
    IntradeskItem(
      kind: IntradeskItemKind.folder,
      id: id,
      name: name,
      parentId: parent,
      parentPath: '',
    );

/// A small tree: `Leerkrachten / Formulieren / {uitstap.docx, Aanvraag
/// uitstappen.pdf}`, `Leerkrachten / Uitstappen`, `Leerlingen / uitstap
/// info.pdf` and a weblink.
final _items = [
  const IntradeskItem(
    kind: IntradeskItemKind.folder,
    id: 'f1',
    name: 'Leerkrachten',
    parentId: '',
    parentPath: '',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.folder,
    id: 'f2',
    name: 'Leerlingen',
    parentId: '',
    parentPath: '',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.folder,
    id: 'f3',
    name: 'Formulieren',
    parentId: 'f1',
    parentPath: 'Leerkrachten',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.folder,
    id: 'f4',
    name: 'Uitstappen',
    parentId: 'f1',
    parentPath: 'Leerkrachten',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.file,
    id: 'c1',
    name: 'uitstap.docx',
    parentId: 'f3',
    parentPath: 'Leerkrachten / Formulieren',
    size: 182108,
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.file,
    id: 'c2',
    name: 'Aanvraag uitstappen.pdf',
    parentId: 'f3',
    parentPath: 'Leerkrachten / Formulieren',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.file,
    id: 'c3',
    name: 'Uitstap info.pdf',
    parentId: 'f2',
    parentPath: 'Leerlingen',
  ),
  const IntradeskItem(
    kind: IntradeskItemKind.weblink,
    id: '',
    name: 'Schoolsite',
    parentId: 'f1',
    parentPath: 'Leerkrachten',
    url: 'https://example.com',
  ),
];

List<String> _match(String query, [Iterable<IntradeskItem>? items]) => [
  for (final item in matchIntradeskItems(
    items ?? _items,
    SearchQuery.parse(query)!,
  ))
    item.path,
];

IntradeskIndex _index({DateTime? builtAt}) => IntradeskIndex(
  builtAt: builtAt ?? DateTime.utc(2024, 9, 1, 8),
  items: _items,
  unlisted: 1,
  skipped: 2,
  walkTime: const Duration(milliseconds: 1234),
);

void main() {
  group('IntradeskItem', () {
    test('path joins the folder names and the name', () {
      expect(_items[0].path, 'Leerkrachten');
      expect(_items[4].path, 'Leerkrachten / Formulieren / uitstap.docx');
    });

    test('a file has its extension in lowercase and a MIME type for common '
        'formats; folders and weblinks have none', () {
      IntradeskItem file(String name) => IntradeskItem(
        kind: IntradeskItemKind.file,
        id: 'c',
        name: name,
        parentId: '',
        parentPath: '',
      );
      expect(file('Verslag.DOCX').extension, 'docx');
      expect(
        file('Verslag.DOCX').mimeType,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.'
        'document',
      );
      expect(file('foto.jpeg').mimeType, 'image/jpeg');
      expect(file('lijst.v2.xlsx').extension, 'xlsx');
      expect(file('lijst.pdf').mimeType, 'application/pdf');
      expect(file('README').extension, '');
      expect(file('.hidden').extension, '');
      expect(file('punt.').extension, '');
      expect(file('archief.xyz').mimeType, isNull);
      expect(_folder('f', 'map.pdf').extension, '');
      expect(_folder('f', 'map.pdf').mimeType, isNull);
    });

    test('a weblink takes its name, address, id and date from the library\'s '
        'weblink and is left out without a name', () {
      // The keys of a weblink in a live folder listing.
      IntradeskWeblink weblink(Map<String, Object> json) =>
          IntradeskWeblink.fromJson({
            'id': 'w1',
            'platform': {'id': 4069, 'name': 'School'},
            'name': 'Schoolsite',
            'url': 'https://example.com',
            'icon': 'folder_orange',
            'state': 'active',
            'parentFolderId': 'f1',
            'dateCreated': '2024-08-29T17:01:56+02:00',
            'dateStateChanged': '2024-08-29T17:01:56+02:00',
            'dateChanged': '2024-08-29T17:01:56+02:00',
            'isFavourite': false,
            'confidential': false,
            'ownerId': '12_345_0',
            ...json,
          });
      final link = IntradeskItem.weblink(
        weblink({'name': ' Schoolsite ', 'confidential': true}),
        parentId: 'f1',
        parentPath: 'Leerkrachten',
      )!;
      expect(link.kind, IntradeskItemKind.weblink);
      expect(link.id, 'w1');
      expect(link.name, 'Schoolsite');
      expect(link.url, 'https://example.com');
      expect(link.changed, DateTime.utc(2024, 8, 29, 15, 1, 56));
      expect(link.confidential, isTrue);
      expect(link.parentId, 'f1');
      expect(link.path, 'Leerkrachten / Schoolsite');
      IntradeskItem? at(Map<String, Object> json) =>
          IntradeskItem.weblink(weblink(json), parentId: '', parentPath: '');
      expect(at({'name': 'Rooster', 'url': ''})?.url, isNull);
      expect(at({'name': '', 'url': 'https://x'}), isNull);
      expect(at({'name': ' '}), isNull);
    });

    test('survives a JSON round trip', () {
      final item = IntradeskItem(
        kind: IntradeskItemKind.file,
        id: 'c1',
        name: 'uitstap.docx',
        parentId: 'f3',
        parentPath: 'Leerkrachten / Formulieren',
        changed: DateTime.utc(2024, 8, 29, 15, 1, 56),
        size: 182108,
        confidential: true,
      );
      final copy = IntradeskItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())),
      );
      expect(copy.toJson(), item.toJson());
      expect(copy.changed, DateTime.utc(2024, 8, 29, 15, 1, 56));
      expect(copy.confidential, isTrue);
      expect(
        () => IntradeskItem.fromJson({'kind': 'file'}),
        throwsFormatException,
      );
      expect(
        () => IntradeskItem.fromJson({..._items[0].toJson(), 'kind': 'x'}),
        throwsFormatException,
      );
    });
  });

  group('IntradeskIndex', () {
    test('finds folders and files by id, counts by kind and lists what is '
        'inside a folder at any depth', () {
      final index = _index();
      expect(index.find('c1')?.name, 'uitstap.docx');
      expect(index.find('f3')?.kind, IntradeskItemKind.folder);
      expect(index.find('nope'), isNull);
      expect(index.count(IntradeskItemKind.folder), 4);
      expect(index.findItem('c1')?.name, 'uitstap.docx');
      expect(index.findItem(''), isNull, reason: 'a weblink without an id');
      expect(index.count(IntradeskItemKind.file), 3);
      expect(index.count(IntradeskItemKind.weblink), 1);
      expect(
        [for (final item in index.within('f1')) item.name],
        [
          'Formulieren',
          'Uitstappen',
          'uitstap.docx',
          'Aanvraag uitstappen.pdf',
          'Schoolsite',
        ],
      );
      expect(index.within('f4'), isEmpty);
    });

    test('findItem finds a weblink by the id Smartschool gave it too, where '
        'find finds only folders and files (#112)', () {
      const weblink = IntradeskItem(
        kind: IntradeskItemKind.weblink,
        id: 'e1',
        name: 'Oefensite',
        parentId: 'f4',
        parentPath: 'Leerkrachten / Uitstappen',
        url: 'https://example.com/oefenen',
      );
      final index = IntradeskIndex(
        builtAt: DateTime.utc(2026, 10, 6),
        items: [..._items, weblink],
      );

      expect(index.findItem('e1'), same(weblink));
      expect(index.find('e1'), isNull);
      expect(index.findItem('f3')?.kind, IntradeskItemKind.folder);
      expect(index.findItem('nope'), isNull);
    });

    test('patched adds items after their folder, puts an item with a known id '
        'in that one\'s place, and removes items with everything in a removed '
        'folder, keeping when the index was built', () {
      final index = _index();
      const added = IntradeskItem(
        kind: IntradeskItemKind.file,
        id: 'c9',
        name: 'nieuw.pdf',
        parentId: 'f4',
        parentPath: 'Leerkrachten / Uitstappen',
      );
      // A walk found it already, under its old name; ids in another case.
      const renamed = IntradeskItem(
        kind: IntradeskItemKind.folder,
        id: 'F3',
        name: 'Formulieren 2026',
        parentId: 'f1',
        parentPath: 'Leerkrachten',
      );

      final patched = index.patched(added: [added, renamed], removed: ['F2']);

      expect(
        [for (final item in patched.items) item.path],
        [
          'Leerkrachten',
          'Leerkrachten / Formulieren 2026',
          'Leerkrachten / Uitstappen',
          'Leerkrachten / Formulieren / uitstap.docx',
          'Leerkrachten / Formulieren / Aanvraag uitstappen.pdf',
          'Leerkrachten / Schoolsite',
          'Leerkrachten / Uitstappen / nieuw.pdf',
        ],
      );
      expect(patched.within('f4'), [added]);
      expect(patched.find('c3'), isNull, reason: 'it was in Leerlingen');
      expect(patched.builtAt, index.builtAt);
      expect(patched.unlisted, 1);
      expect(patched.skipped, 2);
      expect(patched.walkTime, index.walkTime);
      expect(index.items, _items, reason: 'the index itself is unchanged');

      expect(index.patched(removed: ['']).items, _items);
      expect(
        [
          for (final item in index.patched(removed: ['f3']).items) item.name,
        ],
        [
          'Leerkrachten',
          'Leerlingen',
          'Uitstappen',
          'Uitstap info.pdf',
          'Schoolsite',
        ],
      );
    });

    test('survives a JSON round trip; another format is refused', () {
      final index = _index();
      final copy = IntradeskIndex.fromJson(
        jsonDecode(jsonEncode(index.toJson())),
      );
      expect(copy.toJson(), index.toJson());
      expect(copy.builtAt, index.builtAt);
      expect(copy.unlisted, 1);
      expect(copy.skipped, 2);
      expect(copy.walkTime, const Duration(milliseconds: 1234));
      expect(
        () => IntradeskIndex.fromJson({...index.toJson(), 'format': 0}),
        throwsFormatException,
      );
    });
  });

  group('matchIntradeskItems', () {
    test('every word must occur in the path and at least one in the name, '
        'ignoring case and accents; most words in the name first', () {
      expect(_match('formulier uitstap'), [
        'Leerkrachten / Formulieren / Aanvraag uitstappen.pdf',
        'Leerkrachten / Formulieren / uitstap.docx',
      ]);
      expect(_match('UITSTAP'), [
        'Leerkrachten / Formulieren / Aanvraag uitstappen.pdf',
        'Leerkrachten / Formulieren / uitstap.docx',
        'Leerkrachten / Uitstappen',
        'Leerlingen / Uitstap info.pdf',
      ]);
      expect(_match('uitstap info'), ['Leerlingen / Uitstap info.pdf']);
      expect(_match('uïtstap leerlingen'), ['Leerlingen / Uitstap info.pdf']);
    });

    test('a folder name matches the folder, not everything in it', () {
      expect(_match('formulieren'), ['Leerkrachten / Formulieren']);
      expect(_match('leerkrachten'), ['Leerkrachten']);
    });

    test('weblinks match by name; nothing matches a word that is nowhere', () {
      expect(_match('schoolsite'), ['Leerkrachten / Schoolsite']);
      expect(_match('uitstap zwembad'), isEmpty);
      expect(_match('docx'), ['Leerkrachten / Formulieren / uitstap.docx']);
    });
  });

  group('formatting', () {
    test('file sizes', () {
      expect(formatFileSize(0), '0 bytes');
      expect(formatFileSize(1), '1 byte');
      expect(formatFileSize(1023), '1023 bytes');
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(182108), '178 KB');
      expect(formatFileSize(2516582), '2.4 MB');
      expect(formatFileSize(50 * 1024 * 1024), '50 MB');
      expect(formatFileSize(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('an item line: kind, path or name, id, size, date changed and '
        'confidential; a weblink with its id when it has one (#112), and its '
        'address', () {
      final file = IntradeskItem(
        kind: IntradeskItemKind.file,
        id: 'c1',
        name: 'uitstap.docx',
        parentId: 'f3',
        parentPath: 'Leerkrachten / Formulieren',
        changed: DateTime(2024, 8, 29, 17),
        size: 182108,
        confidential: true,
      );
      expect(
        formatIntradeskItem(file),
        'file | Leerkrachten / Formulieren / uitstap.docx | id c1 | 178 KB | '
        'changed 2024-08-29 | confidential',
      );
      expect(
        formatIntradeskItem(file, fullPath: false),
        'file | uitstap.docx | id c1 | 178 KB | changed 2024-08-29 | '
        'confidential',
      );
      expect(
        formatIntradeskItem(_items[2]),
        'folder | Leerkrachten / '
        'Formulieren | id f3',
      );
      expect(
        formatIntradeskItem(_items[7]),
        'weblink | Leerkrachten / Schoolsite | https://example.com',
      );
      const weblink = IntradeskItem(
        kind: IntradeskItemKind.weblink,
        id: 'e1',
        name: 'Schoolsite',
        parentId: 'f1',
        parentPath: 'Leerkrachten',
        url: 'https://example.com',
        confidential: true,
      );
      expect(
        formatIntradeskItem(weblink),
        'weblink | Leerkrachten / Schoolsite | id e1 | https://example.com | '
        'confidential',
      );
    });

    test('dates in the time of this PC', () {
      final date = DateTime(2024, 3, 5, 9, 7);
      expect(formatIntradeskDate(date.toUtc()), '2024-03-05');
      expect(formatIntradeskTime(date.toUtc()), '2024-03-05 09:07');
    });
  });

  group('intradeskIdArgument', () {
    test('accepts a UUID in either case, trimmed, in lowercase like '
        'Smartschool writes ids; absent or empty is null', () {
      const id = 'aaaa1111-1111-4111-b111-111111111111';
      expect(intradeskIdArgument({'folder_id': id}, 'folder_id'), id);
      expect(
        intradeskIdArgument({
          'folder_id': ' ${id.toUpperCase()} ',
        }, 'folder_id'),
        id,
      );
      expect(intradeskIdArgument({}, 'folder_id'), isNull);
      expect(intradeskIdArgument({'folder_id': ' '}, 'folder_id'), isNull);
    });

    test('refuses anything else, so it never goes into a request path', () {
      for (final value in [
        '../../messages',
        'aaaa1111-1111-4111-b111-11111111111',
        'aaaa1111-1111-4111-b111-111111111111/x',
        123,
      ]) {
        expect(
          () => intradeskIdArgument({'folder_id': value}, 'folder_id'),
          throwsA(
            isA<ToolError>().having(
              (e) => e.message,
              'message',
              startsWith('folder_id must be an Intradesk id like '),
            ),
          ),
          reason: '$value',
        );
      }
    });
  });

  group('IntradeskIndexCache', () {
    late Directory folder;
    late DateTime now;
    late IntradeskIndexCache cache;
    late int builds;

    /// A cache on [folder] that waits [wait] for a walk.
    IntradeskIndexCache newCache({
      Duration wait = const Duration(seconds: 5),
    }) => IntradeskIndexCache(folder, buildWait: wait, now: () => now);

    setUp(() async {
      folder = Directory(
        '${(await tempCache()).path}${Platform.pathSeparator}intradesk',
      );
      now = DateTime.utc(2024, 9, 1, 8);
      cache = newCache();
      builds = 0;
    });

    Future<IntradeskIndex> build(IntradeskWalkProgress progress) async {
      builds++;
      return _index(builtAt: now);
    }

    /// A build that waits for [gate], with some progress to show.
    IntradeskIndexBuilder slow(Completer<void> gate) => (progress) async {
      progress
        ..listed = 12
        ..waiting = 30
        ..found = 80;
      await gate.future;
      return build(progress);
    };

    test('builds once, then serves the index from memory and, in a new '
        'cache on the same folder, from disk', () async {
      expect(folder.existsSync(), isFalse, reason: 'created on first write');

      final first = await cache.load(build);
      expect(first.source, IntradeskIndexSource.walk);
      expect(first.building, isNull);
      now = now.add(const Duration(hours: 23));
      final second = await cache.load(build);
      expect(second.source, IntradeskIndexSource.memory);
      expect(identical(second.index, first.index), isTrue);
      final fromDisk = await newCache().load(build);
      expect(fromDisk.source, IntradeskIndexSource.disk);
      expect(fromDisk.index!.toJson(), first.index!.toJson());
      expect(builds, 1);
      expect(folder.listSync().map((f) => f.uri.pathSegments.last), [
        'index.json',
      ], reason: 'no temporary file left behind');
    });

    test('an index older than maxAge is returned while a new one is built '
        'in the background; the next call gets the new one', () async {
      final old = (await cache.load(build)).index!;
      now = now.add(IntradeskIndexCache.defaultMaxAge);
      final gate = Completer<void>();

      final expired = await cache.load(slow(gate));
      expect(expired.index, same(old));
      expect(expired.source, IntradeskIndexSource.memory);
      expect(expired.building?.listed, 12);
      expect(builds, 1);

      gate.complete();
      await cache.walkDone;
      final renewed = await cache.load(build);
      expect(builds, 2);
      expect(renewed.source, IntradeskIndexSource.memory);
      expect(renewed.index!.builtAt, now);
      expect(renewed.building, isNull);
      expect((await newCache().read())!.builtAt, now);
    });

    test('refresh waits for the new index; when that takes longer than '
        'buildWait, it returns the old one with the progress, and so do '
        'other calls while the walk runs', () async {
      await cache.load(build);
      now = now.add(const Duration(minutes: 1));
      final refreshed = await cache.load(build, refresh: true);
      expect(refreshed.source, IntradeskIndexSource.walk);
      expect(refreshed.index!.builtAt, now);
      expect(builds, 2);

      cache = newCache(wait: const Duration(milliseconds: 50));
      final gate = Completer<void>();
      final slowRefresh = await cache.load(slow(gate), refresh: true);
      expect(slowRefresh.index!.toJson(), refreshed.index!.toJson());
      expect(slowRefresh.source, IntradeskIndexSource.disk);
      expect(slowRefresh.building?.waiting, 30);
      final during = await cache.load(build);
      expect(during.index, same(slowRefresh.index), reason: 'still fresh');
      expect(during.building, same(slowRefresh.building));
      gate.complete();
      await cache.walkDone;
      expect(builds, 3);
    });

    test('without any index and a walk longer than buildWait: no index but '
        'the progress; a later call gets the index', () async {
      cache = newCache(wait: const Duration(milliseconds: 50));
      final gate = Completer<void>();

      final first = await cache.load(slow(gate));
      expect(first.index, isNull);
      expect(first.source, isNull);
      expect(first.building?.found, 80);
      final second = await cache.load(slow(gate));
      expect(second.index, isNull, reason: 'still walking');

      gate.complete();
      await cache.walkDone;
      final done = await cache.load(slow(gate));
      expect(done.index, isNotNull);
      expect(done.source, IntradeskIndexSource.memory);
      expect(builds, 1, reason: 'the calls shared one walk');
    });

    test(
      'an index from the future (a changed PC clock) counts as old',
      () async {
        await cache.load(build);
        now = now.subtract(const Duration(hours: 1));
        final result = await cache.load(build);
        expect(result.building, isNotNull);
        await cache.walkDone;
        expect(builds, 2);
      },
    );

    test('calls during a build share it', () async {
      final gate = Completer<void>();
      final calls = [
        cache.load(slow(gate)),
        cache.load(slow(gate)),
        cache.load(slow(gate), refresh: true),
      ];
      gate.complete();
      final results = await Future.wait(calls);
      expect(builds, 1);
      expect(results.map((r) => r.source).toSet(), {IntradeskIndexSource.walk});
    });

    test('a failed build is thrown to the call waiting for it, and the next '
        'call builds again', () async {
      await expectLater(
        cache.load((_) async => throw StateError('offline')),
        throwsStateError,
      );
      expect((await cache.load(build)).source, IntradeskIndexSource.walk);
    });

    test('a failed build nobody waits for is logged, not left unhandled; the '
        'next call builds again', () async {
      await cache.load(build);
      now = now.add(const Duration(days: 2));
      final gate = Completer<void>();
      final stale = await cache.load((progress) async {
        await gate.future;
        throw StateError('offline');
      });
      expect(stale.building, isNotNull);
      gate.complete();
      await cache.walkDone;

      final retried = await cache.load(build, refresh: true);
      expect(retried.source, IntradeskIndexSource.walk);
      expect(builds, 2);
    });

    test('a newer index saved by another server process is used', () async {
      await cache.load(build);
      now = now.add(const Duration(days: 2));
      await newCache().load(build, refresh: true);

      final result = await cache.load(build);
      expect(result.source, IntradeskIndexSource.disk);
      expect(result.index!.builtAt, now);
      expect(result.building, isNull);
      expect(builds, 2);
    });

    test('a damaged or old saved index counts as none; saved() returns an '
        'index of any age without building', () async {
      expect(await cache.saved(), isNull);
      await folder.create(recursive: true);
      final file = File('${folder.path}${Platform.pathSeparator}index.json');
      file.writeAsStringSync('{"format": 1, "items": [');
      expect(await cache.read(), isNull);
      file.writeAsStringSync(jsonEncode({..._index().toJson(), 'format': 0}));
      expect(await cache.read(), isNull);

      expect((await cache.load(build)).source, IntradeskIndexSource.walk);
      now = now.add(const Duration(days: 30));
      expect((await newCache().saved())?.builtAt, DateTime.utc(2024, 9, 1, 8));
      expect(builds, 1);
    });

    group('patch', () {
      const added = IntradeskItem(
        kind: IntradeskItemKind.file,
        id: 'c9',
        name: 'nieuw.pdf',
        parentId: 'f4',
        parentPath: 'Leerkrachten / Uitstappen',
      );

      test(
        'without an index does nothing: nothing is built or written',
        () async {
          expect(await cache.patch(added: [added]), isNull);
          expect(builds, 0);
          expect(folder.existsSync(), isFalse);
        },
      );

      test('patches the index in memory and on disk, of any age, keeping when '
          'it was built; patches run in order', () async {
        await cache.load(build);
        now = now.add(const Duration(days: 3));

        final first = cache.patch(added: [added]);
        final second = cache.patch(removed: ['f2']);
        expect((await first)!.find('c9'), isNotNull);
        final patched = (await second)!;
        expect(patched.find('c9'), isNotNull);
        expect(patched.find('c3'), isNull);
        expect(patched.builtAt, DateTime.utc(2024, 9, 1, 8));

        expect((await cache.saved())!.toJson(), patched.toJson());
        expect((await newCache().saved())!.toJson(), patched.toJson());
        await cache.patch(removed: ['c9']);
        expect((await newCache().saved())!.find('c9'), isNull);
        expect(builds, 1);
      });

      test('a patch made while a walk runs is applied to the walk\'s index '
          'before it is saved', () async {
        final started = Completer<void>();
        final gate = Completer<void>();
        final loading = cache.load((progress) async {
          started.complete();
          await gate.future;
          return build(progress);
        });
        await started.future;

        expect(
          await cache.patch(added: [added]),
          isNull,
          reason: 'no index yet',
        );
        gate.complete();

        expect((await loading).index!.find('c9'), isNotNull);
        expect((await newCache().saved())!.find('c9'), isNotNull);
      });
    });

    test('an index that cannot be saved is still returned', () async {
      // A file where the folder should be.
      await File(folder.path).create(recursive: true);
      final result = await cache.load(build);
      expect(result.source, IntradeskIndexSource.walk);
      expect(result.index, isNotNull);
      expect(await cache.read(), isNull);
    });
  });
}
