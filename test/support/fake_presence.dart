import 'dart:convert';

import 'package:dio/dio.dart';

// A fake of Smartschool's Presence module (Aanwezigheden): the endpoints the
// library's `PresenceService` reads and writes, answered in the shape of
// dartschool's trimmed captures of the live module
// (`test/presence_service_flow_test.dart` and
// `test/presence_service_errors_test.dart` there), with fake names, and the
// save of a half-day (`savePupilsPresences`), carried out on the half-days as
// the live module did in dartschool#2: the cell named by its `presenceID`
// (a new one when it is null) gets the code or the alias sent, and its
// motivation.

/// The module's configuration: the classes the account may view.
const fakePresenceConfigPath = '/Presence/Main/getConfig';

/// The codes of a school structure (`structID`).
const fakePresenceCodesPath = '/Presence/Code/getAllCodes';

/// The pupils of a class with their presences for a period.
const fakePresenceClassPath = '/Presence/Class/getClass';

/// The save of half-days.
const fakePresenceSavePath = '/Presence/Class/savePupilsPresences';

/// The school structure of the official classes, as in the captures.
const fakePresenceStruct = 311;

/// The codes of [fakePresenceStruct], as in the capture: "Aanwezig", "Te
/// laat" with its alias "Te laat zonder geldige reden", and a code the
/// writes never overwrite, "Doktersattest".
const fakePresenceAanwezig = 70;
const fakePresenceTeLaat = 497;
const fakePresenceZonderReden = 14;
const fakePresenceDoktersattest = 479;

/// How the fake answers a save, for the tests of a save that fails.
enum PresenceSave {
  /// Carried out, and answered as the live module did: the saved records
  /// with an empty `errors`.
  confirmed,

  /// Not carried out: answered with errors, as the module refuses a save.
  rejected,

  /// Not carried out: answered with HTTP 500 and Smartschool's error page.
  errorPage,

  /// Carried out, but the connection drops before the answer arrives.
  answerLost,

  /// Answered as confirmed, but not carried out, so the class read
  /// afterwards does not show it.
  unapplied,
}

/// A pupil of a class, by internal user id.
class FakePresencePupil {
  const FakePresencePupil(this.userId, this.movementId, this.name);

  final int userId;
  final int movementId;
  final String name;
}

/// A class as the module's configuration lists it, with its pupils.
class FakePresenceClass {
  const FakePresenceClass(
    this.groupId,
    this.name, {
    this.structId = fakePresenceStruct,
    this.userCanRecord = true,
    this.pupils = const [],
  });

  final int groupId;

  /// The name, which the module pads with spaces (`"1A  "`).
  final String name;

  /// The school structure, or null for a grouping class (`""`).
  final int? structId;

  final bool userCanRecord;
  final List<FakePresencePupil> pupils;
}

/// A half-day of a pupil: its record id and what it holds.
class FakeHalfDay {
  FakeHalfDay(this.presenceId, {this.codeId, this.aliasId, this.motivation});

  final int presenceId;
  int? codeId;
  int? aliasId;

  /// The motivation; null as the module sends an empty one.
  String? motivation;
}

/// The pupils of class 1A of the fake school, with fake names.
const fakePeeters = FakePresencePupil(1001, 5001, 'Peeters, Lotte');
const fakeJanssens = FakePresencePupil(1002, 5002, 'Janssens, Emma');
const fakeDupont = FakePresencePupil(1003, 5003, 'Dupont, Noah');
const fakeClaes = FakePresencePupil(1004, 5004, 'Claes, Mila');

/// Class 1A: official, and the account may record presences for it.
const fake1A = FakePresenceClass(
  298,
  '1A  ',
  pupils: [fakePeeters, fakeJanssens, fakeDupont, fakeClaes],
);

/// Class 1B: the account may only view it.
const fake1B = FakePresenceClass(
  312,
  '1B  ',
  userCanRecord: false,
  pupils: [FakePresencePupil(1101, 5101, 'Wouters, Lars')],
);

/// Class 2A: a grouping class without a school structure.
const fake2A = FakePresenceClass(
  1650,
  '2A  ',
  structId: null,
  pupils: [FakePresencePupil(1201, 5201, 'Maes, Finn')],
);

/// A fake Presence module, served by `FakeSmartschool` to logged-in
/// requests.
///
/// Every Presence request is recorded in [requests]. With [refused] set,
/// every request is answered with Smartschool's error page (HTTP 500), as
/// the module answers a request it cannot handle. A class the account may
/// not record for is answered as the live module does: without pupils,
/// with `saveIsAllowed: false` and an `errorMessage`.
class FakePresence {
  /// The classes of the configuration, in the module's order.
  final List<FakePresenceClass> classes = [];

  /// The half-days, by pupil, day (`yyyy-MM-dd`) and part (`am`, `pm`).
  final Map<(int, String, String), FakeHalfDay> halfDays = {};

  /// Days with a registration per lesson (`partOfDay: "none"`), by pupil and
  /// day: the module lists it among the presences, and the library ignores
  /// it.
  final Set<(int, String)> lessonRows = {};

  /// When set, every request is answered with the error page.
  bool refused = false;

  /// How the fake answers a save, after [nextSaves].
  PresenceSave save = PresenceSave.confirmed;

  /// How the fake answers the next saves, in order, before [save].
  final List<PresenceSave> nextSaves = [];

  /// Called before each `getClass` is answered, with how many there were
  /// (1 for the first): for a test that changes a half-day meanwhile, or
  /// refuses the requests from then on ([refused]).
  void Function(int count)? onGetClass;

  int _getClassCount = 0;
  int _nextPresenceId = 95001;

  /// The Presence requests, in order, with the fields of their form.
  final List<({String path, Map<String, String> form})> requests = [];

  /// The requests, as `POST path`.
  List<String> get calls => [
    for (final request in requests) 'POST ${request.path}',
  ];

  /// The saves that reached the module, as the half-days they sent: one map
  /// per presence of the `pupils` payload, with `userID` and `movementID`.
  List<Map<String, Object?>> get saves => [
    for (final request in requests)
      if (request.path == fakePresenceSavePath)
        for (final pupil in jsonDecode(request.form['pupils']!) as List)
          for (final presence in (pupil as Map)['presence'] as List)
            {
              'userID': pupil['userID'],
              'movementID': pupil['movementID'],
              ...(presence as Map).cast<String, Object?>(),
            },
  ];

  /// The school of the captures, trimmed and with fake names: 1A, 1B (view
  /// only) and 2A (a grouping class). On [day] (`yyyy-MM-dd`), in 1A:
  /// Peeters is present in the morning and the afternoon and has a
  /// registration per lesson; Janssens has nothing recorded; Dupont has a
  /// doctor's note in the morning; Claes is late in the morning, with a
  /// motivation, and late without a valid reason in the afternoon.
  void loadSchool(String day) {
    classes.addAll(const [fake1A, fake1B, fake2A]);
    halfDays[(fakePeeters.userId, day, 'am')] = FakeHalfDay(
      90001,
      codeId: fakePresenceAanwezig,
    );
    halfDays[(fakePeeters.userId, day, 'pm')] = FakeHalfDay(
      90002,
      codeId: fakePresenceAanwezig,
    );
    lessonRows.add((fakePeeters.userId, day));
    halfDays[(fakeDupont.userId, day, 'am')] = FakeHalfDay(
      90003,
      codeId: fakePresenceDoktersattest,
      motivation: 'attest huisarts',
    );
    halfDays[(fakeClaes.userId, day, 'am')] = FakeHalfDay(
      90004,
      codeId: fakePresenceTeLaat,
      motivation: 'bus te laat',
    );
    halfDays[(fakeClaes.userId, day, 'pm')] = FakeHalfDay(
      90005,
      aliasId: fakePresenceZonderReden,
    );
    halfDays[(1101, day, 'am')] = FakeHalfDay(
      91001,
      codeId: fakePresenceTeLaat,
    );
    halfDays[(1201, day, 'am')] = FakeHalfDay(
      92001,
      codeId: fakePresenceTeLaat,
    );
  }

  /// What pupil [userId]'s half-day [part] (`am`, `pm`) of [day] holds now.
  FakeHalfDay? halfDay(int userId, String day, String part) =>
      halfDays[(userId, day, part)];

  FakePresenceClass? _class(int? groupId) =>
      classes.where((c) => c.groupId == groupId).firstOrNull;

  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (!path.startsWith('/Presence/')) return null;
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    requests.add((path: path, form: form));
    if (path == fakePresenceClassPath) onGetClass?.call(++_getClassCount);
    if (refused) return _html(_errorPage, status: 500);
    switch (path) {
      case fakePresenceConfigPath:
        return _json(jsonEncode(_config()));
      case fakePresenceCodesPath:
        return _json(
          jsonEncode(
            int.tryParse(form['structID'] ?? '') == fakePresenceStruct &&
                    form['ofschoolage'] == 'of_school_age'
                ? _codes
                : const [],
          ),
        );
      case fakePresenceClassPath:
        return _getClass(form);
      case fakePresenceSavePath:
        return _save(options, form);
    }
    return _html(_errorPage, status: 500);
  }

  Map<String, Object?> _config() {
    Map<String, Object?> ref(FakePresenceClass c) => {
      'groupID': c.groupId,
      'name': c.name,
      'adminNumber': c.structId == null ? '' : 6000 + c.groupId,
      'isOfficial': c.structId == null ? 0 : 1,
      'userCanRecord': c.userCanRecord,
      'userCanConfirm': c.userCanRecord,
      'instituteNumber': c.structId == null ? '' : 125252,
      'structID': c.structId ?? '',
    };
    return {
      'hasErrors': false,
      'errors': const [],
      'state': {
        'activeClass': classes.isEmpty ? null : ref(classes.first),
        'schoolyear': '2025-11-05',
      },
      'main': {
        'allowedClasses': [for (final c in classes) ref(c)],
      },
    };
  }

  /// The pupils of a class with their presences on one day, as the module
  /// answers `getClass` for a single day with pupils and presences. A class
  /// the account may not record for (or does not know) gets no pupils, as
  /// in the live module.
  ResponseBody _getClass(Map<String, String> form) {
    final presenceClass = _class(int.tryParse(form['classID'] ?? ''));
    final day = form['startDate'];
    if (day == null ||
        form['endDate'] != day ||
        form['schoolyearRefDate'] != '2025-11-05' ||
        form['includePupils'] != '1' ||
        form['includePresences'] != '1') {
      return _html(_errorPage, status: 500);
    }
    if (presenceClass == null || !presenceClass.userCanRecord) {
      return _json(
        jsonEncode({
          'pupils': const [],
          'saveIsAllowed': false,
          'errorMessage':
              'Je hebt geen rechten om de aanwezigheden van deze klas te '
              'registreren.',
        }),
      );
    }
    return _json(
      jsonEncode({
        'groupID': presenceClass.groupId,
        'structID': presenceClass.structId ?? '',
        'saveIsAllowed': true,
        'pupils': [
          for (final pupil in presenceClass.pupils)
            {
              'movementID': pupil.movementId,
              'userID': pupil.userId,
              'name': pupil.name,
              'presence': [
                for (final part in ['am', 'pm'])
                  if (halfDay(pupil.userId, day, part) case final cell?)
                    {
                      'presenceID': cell.presenceId,
                      'presenceDate': day,
                      'studentID': pupil.userId,
                      'hourID': null,
                      'partOfDay': part,
                      'codeID': cell.codeId,
                      'aliasID': cell.aliasId,
                      'motivation': cell.motivation,
                      'deleteStatus': 0,
                    },
                if (lessonRows.contains((pupil.userId, day)))
                  {
                    'presenceID': 90099,
                    'presenceDate': day,
                    'studentID': pupil.userId,
                    'hourID': 198,
                    'partOfDay': 'none',
                    'codeID': 1,
                    'aliasID': null,
                    'motivation': null,
                    'deleteStatus': 0,
                  },
              ],
            },
        ],
      }),
    );
  }

  /// Carries out a save as the next save says, and answers it as the live
  /// module did: the saved records, with an empty `errors`.
  ///
  /// The library reads the class before it saves, so a save the fake cannot
  /// carry out (a pupil not in a class the account may record for, another
  /// movement id, a presence id that is not the half-day's, a half-day per
  /// lesson, a code that is not one of the structure) is answered with HTTP
  /// 400, which no test expects.
  ResponseBody _save(RequestOptions options, Map<String, String> form) {
    final outcome = nextSaves.isEmpty ? save : nextSaves.removeAt(0);
    if (outcome == PresenceSave.errorPage) {
      return _html(_errorPage, status: 500);
    }
    if (outcome == PresenceSave.rejected) {
      return _json(
        jsonEncode({
          'hasErrors': true,
          'errors': ['De aanwezigheid kon niet bewaard worden.'],
        }),
      );
    }
    final changes = _changes(form['pupils']);
    if (changes == null) {
      return _json('{"error":"the fake cannot save this"}', status: 400);
    }
    final saved = <Map<String, Object?>>[];
    for (final (key, codeId, aliasId, motivation) in changes) {
      if (outcome == PresenceSave.unapplied) continue;
      final cell = halfDays[key] ??= FakeHalfDay(_nextPresenceId++);
      cell
        ..codeId = codeId
        ..aliasId = aliasId
        ..motivation = motivation.isEmpty ? null : motivation;
      saved.add({
        'presenceID': cell.presenceId,
        'presenceDate': key.$2,
        'studentID': key.$1,
        'partOfDay': key.$3,
        'codeID': codeId,
        'aliasID': aliasId,
      });
    }
    if (outcome == PresenceSave.answerLost) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection reset by peer',
      );
    }
    return _json(
      jsonEncode({'hasErrors': false, 'errors': const [], 'presences': saved}),
    );
  }

  /// The half-days a save's `pupils` payload changes, with the code, alias
  /// and motivation each gets, or null when the fake cannot carry it out
  /// (see [_save]).
  List<((int, String, String), int?, int?, String)>? _changes(String? payload) {
    if (payload == null) return null;
    final changes = <((int, String, String), int?, int?, String)>[];
    for (final pupil in jsonDecode(payload) as List) {
      final userId = (pupil as Map)['userID'];
      final presenceClass = classes
          .where(
            (c) =>
                c.userCanRecord &&
                c.structId != null &&
                c.pupils.any(
                  (p) =>
                      p.userId == userId && p.movementId == pupil['movementID'],
                ),
          )
          .firstOrNull;
      if (presenceClass == null) return null;
      for (final presence in pupil['presence'] as List) {
        if (presence case {
          'presenceID': final presenceId,
          'presenceDate': final String day,
          'studentID': final studentId,
          'hourID': null,
          'partOfDay': final String part,
          'codeID': final int? codeId,
          'aliasID': final int? aliasId,
          'motivation': final String motivation,
          'deleteStatus': 0,
        } when studentId == userId && (part == 'am' || part == 'pm')) {
          final key = (userId as int, day, part);
          final known = codeId == null
              ? aliasId == fakePresenceZonderReden
              : aliasId == null &&
                    _codes.any((code) => code['codeID'] == codeId);
          if (presenceId != halfDays[key]?.presenceId || !known) return null;
          changes.add((key, codeId, aliasId, motivation));
        } else {
          return null;
        }
      }
    }
    return changes;
  }

  /// The codes of [fakePresenceStruct], as `getAllCodes` answers them.
  static const _codes = [
    {
      'codeID': fakePresenceAanwezig,
      'code': '|',
      'name': 'Aanwezig',
      'alias': [],
    },
    {
      'codeID': fakePresenceTeLaat,
      'code': 'L',
      'name': 'Te laat',
      'alias': [
        {
          'aliasID': fakePresenceZonderReden,
          'codeID': fakePresenceTeLaat,
          'code': '  ',
          'name': 'Te laat zonder geldige reden',
          'codeOrder': 0,
        },
      ],
    },
    {
      'codeID': fakePresenceDoktersattest,
      'code': 'D',
      'name': 'Doktersattest',
      'alias': [],
    },
  ];

  static ResponseBody _html(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
        },
      );

  static ResponseBody _json(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}

/// Smartschool's generic error page, as the module sends it with a `500`
/// for a request it refuses.
const _errorPage =
    '<!DOCTYPE html><html><head><title></title></head><body>'
    '<div id="#smscMain"><h1>Oeps, er ging iets mis</h1></div></body></html>';
