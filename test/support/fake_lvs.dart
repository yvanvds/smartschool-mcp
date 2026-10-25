import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

// A fake of Smartschool's pupil tracking system (LVS, "leerlingvolgsysteem",
// `/?module=LVS`): the reads of the library's `LvsService`, answered with
// the hand-written fixtures of `test/fixtures/lvs/` (#153).
//
// The LVS holds the most sensitive data Smartschool has. No answer of a live
// LVS is ever used here, also not trimmed: the fixtures are copies of the
// library's own (yvanvds/dartschool, `test/fixtures/lvs/`, written by hand
// in the shapes of #160) or written by hand in those shapes, with the fakes
// of `test/fixtures/lvs/FAKES.md` only. `test/lvs_fixtures_guard_test.dart`
// checks them. A new kind of answer (the notes of #154, say) goes in a
// folder of its own under `test/fixtures/lvs/`, registered in that guard's
// `lvsFixtureKinds`, and gets a [FakeLvsRead] and a case in
// [FakeLvs.respond].

/// The folder of the fixtures the fake answers with.
const fakeLvsFixtures = 'test/fixtures/lvs';

/// A pupil of the fixtures: their pupil id and the id of their class.
typedef FakeLvsPupil = ({int pupilId, int classId});

/// Jan Janssens of class 1A: the one pupil a search for "janssens" finds,
/// with a file whose notes hold something (sub-categories, a heading, new
/// notes) and results, and attendance in the morning and the afternoon.
const fakeLvsJan = (pupilId: 900001, classId: 900101);

/// Marie Peeters of class 2B: found with Lars by "peeters", with a file
/// without form tutors whose support plans and absences hold something (the
/// absences something new), but not its note category, and attendance in
/// the morning only.
const fakeLvsMarie = (pupilId: 900002, classId: 900102);

/// Lars Peeters of class 3C: found by "peeters", but the LVS answers his
/// file with its placeholder pupil, as for a pupil it does not know.
const fakeLvsLars = (pupilId: 900005, classId: 900103);

/// The reads of `LvsService` the fake answers.
enum FakeLvsRead {
  /// The root of the class tree (`checkAccess`):
  /// `POST /?module=LVS&file=treeBuilder` with `id`.
  tree,

  /// The pupil search (`searchPupils`): `GET /LVS/Spotlight?searchVal=`.
  search,

  /// A pupil's file (`getPupilFile`):
  /// `GET /LVS/Spotlight/<pupil id>?classID=<class id>`.
  pupilFile,

  /// A pupil's attendance today (`getPupilFile`, after the file):
  /// `POST /LVS/Pupilxhr/getStatusInfo` with `pupilID`.
  todayStatus,
}

/// How the fake refuses or breaks a read ([FakeLvs.refusal]).
enum FakeLvsRefusal {
  /// HTTP 403, with a page that names a pupil: what the library takes for a
  /// refusal to the account. What the LVS answers an account without
  /// access was not captured (yvanvds/dartschool#168).
  forbidden,

  /// Sends the request on to Smartschool's start page, as Skore does for an
  /// account without its rights: the library's other refusal. A POST gets
  /// the `302` unfollowed; a GET the start page with the redirect it
  /// followed, as `dart:io`'s `HttpClient` gives them.
  startPage,

  /// HTTP 500 with Smartschool's error page, as the LVS answered reads of a
  /// made-up pupil (seen live, yvanvds/dartschool#168).
  serverError,

  /// HTTP 200 with an HTML page instead of data.
  htmlPage,
}

/// One request the fake LVS got.
typedef FakeLvsRequest = ({
  String method,
  String path,
  Map<String, String> query,
  Map<String, String> form,
  FakeLvsRead? read,
});

/// The fake LVS, served by `FakeSmartschool` to logged-in requests.
class FakeLvs {
  FakeLvs({required this.startPage});

  /// The page Smartschool's start page answers, for [FakeLvsRefusal.startPage].
  final String startPage;

  /// Every request to the LVS, in order, with the read it is (`null` for a
  /// request that is none of [FakeLvsRead]: the LVS tools never send one).
  final List<FakeLvsRequest> requests = [];

  /// The reads, in order.
  List<FakeLvsRead?> get reads => [for (final r in requests) r.read];

  /// The requests, in order, each as one line: the method, the path with
  /// the query, and the form fields, such as
  /// `POST /LVS/Pupilxhr/getStatusInfo pupilID=900001`.
  List<String> get calls => [
    for (final r in requests)
      [
        '${r.method} ${r.path}'
            '${r.query.isEmpty ? '' : '?${_fields(r.query, '&')}'}',
        if (r.form.isNotEmpty) _fields(r.form, ' '),
      ].join(' '),
  ];

  static String _fields(Map<String, String> fields, String separator) => [
    for (final MapEntry(:key, :value) in fields.entries) '$key=$value',
  ].join(separator);

  /// The fixture a search answers with, by a text the search text holds
  /// (any case); a search for anything else finds no one.
  final Map<String, String> searches = {
    'janssens': 'spotlight/search_one.json',
    'peeters': 'spotlight/search_several.json',
  };

  /// The fixture of each pupil's file, by pupil id. A pupil without one, or
  /// asked for in another class than the file's, gets the LVS's placeholder
  /// pupil (`spotlight/pupil_not_found.json`, with the pupil id asked for),
  /// as the LVS answers a made-up pupil id (yvanvds/dartschool#168).
  final Map<int, String> pupilFiles = {
    fakeLvsJan.pupilId: 'spotlight/pupil_file.json',
    fakeLvsMarie.pupilId: 'spotlight/pupil_file_parts.json',
  };

  /// The fixture of each pupil's attendance today, by pupil id; none for
  /// any other pupil.
  final Map<int, String> statuses = {
    fakeLvsJan.pupilId: 'status/both.json',
    fakeLvsMarie.pupilId: 'status/am.json',
  };

  /// When set, the reads of [refusedReads] (all of them when that is null)
  /// are answered this way.
  FakeLvsRefusal? refusal;

  /// The reads [refusal] is for; null for all.
  Set<FakeLvsRead>? refusedReads;

  /// When set, every LVS request fails with it: thrown by the HTTP adapter,
  /// as a connection that breaks would, so that a test can feed the server
  /// an error of its choice (one whose message holds a name, say).
  Object? failure;

  /// Answers [options] when it is an LVS request; null otherwise.
  ResponseBody? respond(RequestOptions options) {
    final uri = options.uri;
    final path = uri.path;
    final query = uri.queryParameters;
    final isLvs =
        path.startsWith('/LVS/') || path == '/LVS' || query['module'] == 'LVS';
    if (!isLvs) return null;
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    final read = _readOf(options.method, path, query, form);
    requests.add((
      method: options.method,
      path: path,
      query: query,
      form: form,
      read: read,
    ));
    if (failure case final failure?) throw failure;
    if (read == null) return _html(_errorPage, status: 500);
    if (refusal case final refusal? when refusedReads?.contains(read) ?? true) {
      return _refuse(refusal, options);
    }
    return switch (read) {
      FakeLvsRead.tree => _fixture('tree/root.json', type: 'text/json'),
      FakeLvsRead.search => _search(query['searchVal'] ?? ''),
      FakeLvsRead.pupilFile => _pupilFile(path, query),
      FakeLvsRead.todayStatus => _fixture(
        statuses[int.tryParse(form['pupilID'] ?? '')] ?? 'status/none.json',
      ),
    };
  }

  static FakeLvsRead? _readOf(
    String method,
    String path,
    Map<String, String> query,
    Map<String, String> form,
  ) {
    bool only(Map<String, String> fields, Set<String> names) =>
        fields.keys.toSet().difference(names).isEmpty;
    return switch ((method, path)) {
      ('POST', '/')
          when query['module'] == 'LVS' &&
              query['file'] == 'treeBuilder' &&
              only(query, {'module', 'file'}) &&
              only(form, {'id'}) =>
        FakeLvsRead.tree,
      ('GET', '/LVS/Spotlight')
          when query.containsKey('searchVal') &&
              only(query, {'searchVal'}) &&
              form.isEmpty =>
        FakeLvsRead.search,
      ('GET', _)
          when RegExp(r'^/LVS/Spotlight/\d+$').hasMatch(path) &&
              query.containsKey('classID') &&
              only(query, {'classID'}) &&
              form.isEmpty =>
        FakeLvsRead.pupilFile,
      ('POST', '/LVS/Pupilxhr/getStatusInfo')
          when query.isEmpty && only(form, {'pupilID'}) =>
        FakeLvsRead.todayStatus,
      _ => null,
    };
  }

  ResponseBody _search(String text) {
    final search = text.toLowerCase();
    for (final MapEntry(:key, :value) in searches.entries) {
      if (search.contains(key)) return _fixture(value);
    }
    return _fixture('spotlight/search_none.json');
  }

  ResponseBody _pupilFile(String path, Map<String, String> query) {
    final pupilId = int.parse(path.substring('/LVS/Spotlight/'.length));
    final classId = int.tryParse(query['classID'] ?? '');
    if (pupilFiles[pupilId] case final fixture?) {
      final file = jsonDecode(_read(fixture)) as Map<String, Object?>;
      final pupil = file['pupil'] as Map<String, Object?>;
      if (pupil['classID'] == classId) return _json(jsonEncode(file));
    }
    // The placeholder pupil, for the pupil id asked for.
    final placeholder =
        jsonDecode(_read('spotlight/pupil_not_found.json'))
            as Map<String, Object?>;
    (placeholder['pupil'] as Map<String, Object?>)['pupilID'] = pupilId;
    return _json(jsonEncode(placeholder));
  }

  ResponseBody _refuse(FakeLvsRefusal refusal, RequestOptions options) =>
      switch ((refusal, options.method)) {
        (FakeLvsRefusal.forbidden, _) => _html(_noAccessPage, status: 403),
        (FakeLvsRefusal.startPage, 'GET') =>
          _html(startPage)
            ..redirects = [
              RedirectRecord(
                302,
                'GET',
                options.uri.resolve(_startPageLocation),
              ),
            ],
        (FakeLvsRefusal.startPage, _) => ResponseBody.fromString(
          '',
          302,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
            'location': [_startPageLocation],
          },
        ),
        (FakeLvsRefusal.serverError, _) => _html(_errorPage, status: 500),
        (FakeLvsRefusal.htmlPage, _) => _html(_errorPage),
      };

  static String _read(String fixture) =>
      File('$fakeLvsFixtures/$fixture').readAsStringSync();

  static ResponseBody _fixture(
    String fixture, {
    String type = Headers.jsonContentType,
  }) => _json(_read(fixture), type: type);

  static ResponseBody _json(
    String body, {
    String type = Headers.jsonContentType,
  }) => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [type],
    },
  );

  static ResponseBody _html(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
        },
      );
}

/// Smartschool's error page, as the LVS answers a read it cannot carry out.
const _errorPage =
    '<!DOCTYPE html><html><head><title></title></head><body>'
    '<div id="#smscMain"><h1>Oeps, er ging iets mis</h1></div></body></html>';

/// Where Smartschool sends a request of an account without the rights.
const _startPageLocation = '/?module=Homepage';

/// A "no access" page that names a pupil, to check that no message quotes
/// it.
const fakeLvsNoAccessName = 'Janssens Jan';
const _noAccessPage =
    '<!DOCTYPE html><html><body><h1>Geen toegang</h1>'
    '<p>Testpagina: geen toegang tot $fakeLvsNoAccessName.</p></body></html>';
