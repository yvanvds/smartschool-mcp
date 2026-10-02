import 'dart:convert';

import 'package:dio/dio.dart';

// A fake of Smartschool's Skore module: the endpoints the library's
// `SkoreService` reads, answered in the shape of dartschool's anonymised
// captures of the live Skore (`test/skore_service_test.dart` there, read-only,
// 2026-10-01), with fake names.

/// The tree of report models (`select_models`), answered as JSON.
const fakeSkoreModelsPath = '/modules/Skore/modules/rapportbeheer/data.php';

/// The assignments page of a class (`?classID=`), answered as an HTML table.
const fakeSkoreOwnersPagePath =
    '/turbowidgets_dev/skore/templates/module/owners/template.php';

/// The RPC service behind the assignments page (`getTeachers`; the writes of
/// #43 call `getMyGroups` and `saveOwner` on it).
const fakeSkoreOwnersRpcPath = '/modules/Skore/backend/models/owners.php';

/// The RPC service behind the "share gradebooks" manager (#44).
const fakeSkoreGradebooksRpcPath =
    '/modules/Skore/modules/rapportbeheer/rpc/data.php';

/// How the fake refuses an account without the rights for score management.
///
/// What the live Skore answers such an account has not been captured
/// (yvanvds/dartschool#91), so the fake can answer both ways the library
/// tells apart.
enum SkoreRefusal {
  /// HTTP 403 (Forbidden), with a page that names the user: the library's
  /// `SmartschoolSkoreAccessDeniedError`, the only answer it takes for no
  /// rights.
  forbidden,

  /// A "no access" page that names the user, with HTTP 200, instead of
  /// data: most likely what such an account gets. The library reports it
  /// as a plain `SmartschoolSkoreError` (an answer it cannot use).
  page,
}

/// A teacher as Skore names one (`"Last, First"`), by Smartschool user id.
class FakeSkoreTeacher {
  const FakeSkoreTeacher(this.id, this.name);

  static const janssens = FakeSkoreTeacher(1001, 'Janssens, Jan');
  static const peeters = FakeSkoreTeacher(1002, 'Peeters, Piet');
  static const dupre = FakeSkoreTeacher(1003, 'Dupré, Céline');
  static const dhondt = FakeSkoreTeacher(1004, "D'Hondt, Karel");
  static const willems = FakeSkoreTeacher(1005, 'Willems, Wim');
  static const maes = FakeSkoreTeacher(1006, 'Maes, Mira');

  /// The teachers of [FakeSkore.loadSchool], in Skore's order (by name).
  static const school = [dhondt, dupre, janssens, maes, peeters, willems];

  final int id;
  final String name;
}

/// A teacher assigned to a course: the assignment, which holds the
/// gradebook.
class FakeSkoreAssignment {
  const FakeSkoreAssignment(this.id, this.teacher);

  final int id;
  final FakeSkoreTeacher teacher;
}

/// A row of a class's assignments page: a course, or a group header.
class FakeSkoreCourse {
  const FakeSkoreCourse(
    this.id,
    this.name,
    this.label, {
    this.depth = 0,
    this.groupHeader = false,
    this.assignments = const [],
  });

  final int id;

  /// The course name (`coursename`).
  final String name;

  /// The label as Skore shows it, the code in square brackets at the end.
  final String label;

  final int depth;
  final bool groupHeader;
  final List<FakeSkoreAssignment> assignments;
}

/// A class under a report model; [courses] null for a class without a
/// course structure.
class FakeSkoreClass {
  const FakeSkoreClass(this.id, this.name, [this.courses]);

  final int id;
  final String name;
  final List<FakeSkoreCourse>? courses;
}

/// A group of classes under a model's members ("Leden"); with [id] null,
/// the classes are listed under the members without a group.
class FakeSkoreGroup {
  const FakeSkoreGroup(this.id, this.name, this.classes);

  final int? id;
  final String name;
  final List<FakeSkoreClass> classes;
}

/// A report model with its groups of classes.
class FakeSkoreModel {
  const FakeSkoreModel(this.id, this.name, this.groups);

  final int id;
  final String name;
  final List<FakeSkoreGroup> groups;
}

/// Class 5WW1 of dartschool's capture: two group headers, a course with one
/// teacher, a course with a sub-course and no teacher, a sub-course with
/// three teachers, a course and its sub-course with the same code
/// (`T.SOGEWE`), and a code with a space in it.
const fakeSkore5WW1 = FakeSkoreClass(2516, '5WW1', [
  FakeSkoreCourse(1966, 'Vakken', 'Vakken [Vak]', groupHeader: true),
  FakeSkoreCourse(
    2164,
    'Aardrijkskunde (1 uur)',
    'Aardrijkskunde (1 uur) (5e j DG) [AARDR]',
    depth: 1,
    assignments: [FakeSkoreAssignment(31882, FakeSkoreTeacher.janssens)],
  ),
  FakeSkoreCourse(
    2142,
    'Eye4Skills (2 uur)',
    'Eye4Skills (2 uur) (3e graad) [PROJE]',
    depth: 1,
  ),
  FakeSkoreCourse(
    1840,
    'Project 1',
    'Project 1 (3e graad) [PROJE1]',
    depth: 2,
    assignments: [
      FakeSkoreAssignment(34580, FakeSkoreTeacher.peeters),
      FakeSkoreAssignment(34582, FakeSkoreTeacher.dupre),
      FakeSkoreAssignment(34584, FakeSkoreTeacher.dhondt),
    ],
  ),
  FakeSkoreCourse(
    1776,
    'Toegepaste sociale- en gedragswetenschappen (6 uur)',
    'Toegepaste sociale- en gedragswetenschappen (6 uur) (5e j DG (5WW)) '
        '[T.SOGEWE]',
    depth: 1,
  ),
  FakeSkoreCourse(
    2676,
    'Toegepaste sociale- en gedragswetenschappen (/90)',
    'Toegepaste sociale- en gedragswetenschappen (/90) (5e j DG (5WW)) '
        '[T.SOGEWE]',
    depth: 2,
  ),
  FakeSkoreCourse(
    1590,
    'Extra rapporten',
    'Extra rapporten  [Extra rapporten]',
    groupHeader: true,
  ),
  FakeSkoreCourse(
    1588,
    'Digitale vaardigheden',
    'Digitale vaardigheden  [Digitale vaardigheden]',
    depth: 1,
    assignments: [FakeSkoreAssignment(34826, FakeSkoreTeacher.willems)],
  ),
]);

/// Class 3B1: who teaches mathematics.
const fakeSkore3B1 = FakeSkoreClass(2450, '3B1', [
  FakeSkoreCourse(3001, 'Vakken', 'Vakken [Vak]', groupHeader: true),
  FakeSkoreCourse(
    3010,
    'Wiskunde (5 uur)',
    'Wiskunde (5 uur) (3e j A) [WISK]',
    depth: 1,
    assignments: [FakeSkoreAssignment(40010, FakeSkoreTeacher.maes)],
  ),
  FakeSkoreCourse(
    3020,
    'Nederlands (4 uur)',
    'Nederlands (4 uur) (3e j A) [NED]',
    depth: 1,
    assignments: [FakeSkoreAssignment(40020, FakeSkoreTeacher.peeters)],
  ),
]);

/// Class 1B2: not linked to a course structure yet.
const fakeSkore1B2 = FakeSkoreClass(2378, '1B2');

/// A fake Skore, served by `FakeSmartschool` to logged-in requests.
///
/// Every Skore request is recorded in [requests]. With [refusal] set, every
/// request is refused as for an account without the rights. The RPC
/// services answer only the reads: another method of `owners.php` (the
/// writes of #43) is answered with HTTP 501, and the gradebooks service
/// (#44) is not served yet.
class FakeSkore {
  /// The report models, with their groups and classes.
  final List<FakeSkoreModel> models = [];

  /// The teachers Skore lets assign, in Skore's order.
  final List<FakeSkoreTeacher> teachers = [];

  /// When set, how every request is refused.
  SkoreRefusal? refusal;

  /// The Skore requests, in order; `rpc` is the RPC method of a POST.
  final List<
    ({String method, String path, Map<String, String> query, String? rpc})
  >
  requests = [];

  /// The requests, as `GET path` or `POST path method`.
  List<String> get calls => [
    for (final request in requests)
      [request.method, request.path, ?request.rpc].join(' '),
  ];

  /// The school of dartschool's capture, trimmed: three report models; the
  /// classes 1B1, 1B2 (no course structure) and 2B1, 3B1, and 5WW1, and
  /// OKAN, listed without a group; and six teachers.
  void loadSchool() {
    models.addAll(const [
      FakeSkoreModel(178, '1gr B-str.', [
        FakeSkoreGroup(456, '1B', [
          FakeSkoreClass(2376, '1B1', []),
          fakeSkore1B2,
        ]),
        FakeSkoreGroup(464, '2B', [FakeSkoreClass(2368, '2B1', [])]),
      ]),
      FakeSkoreModel(177, '2gr A-str.', [
        FakeSkoreGroup(470, '3B', [fakeSkore3B1]),
      ]),
      FakeSkoreModel(176, '3gr D-D/A', [
        FakeSkoreGroup(492, '5DG', [fakeSkore5WW1]),
        FakeSkoreGroup(null, '', [FakeSkoreClass(2600, 'OKAN', [])]),
      ]),
    ]);
    teachers.addAll(FakeSkoreTeacher.school);
  }

  /// The class with [id], or null.
  FakeSkoreClass? classWithId(int id) {
    for (final model in models) {
      for (final group in model.groups) {
        for (final skoreClass in group.classes) {
          if (skoreClass.id == id) return skoreClass;
        }
      }
    }
    return null;
  }

  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (path != fakeSkoreModelsPath &&
        path != fakeSkoreOwnersPagePath &&
        path != fakeSkoreOwnersRpcPath &&
        path != fakeSkoreGradebooksRpcPath) {
      return null;
    }
    final data = options.data;
    final form = data is Map
        ? {for (final entry in data.entries) '${entry.key}': '${entry.value}'}
        : const <String, String>{};
    requests.add((
      method: options.method,
      path: path,
      query: options.uri.queryParameters,
      rpc: form['rpc_method'],
    ));
    if (refusal case final refusal?) {
      return _html(
        _noAccessPage,
        status: refusal == SkoreRefusal.forbidden ? 403 : 200,
      );
    }
    final query = options.uri.queryParameters;
    switch ((options.method, path)) {
      case ('GET', fakeSkoreModelsPath)
          when query['skajax_function'] == 'select_models':
        return _json(jsonEncode(_modelsTree()));
      case ('GET', fakeSkoreOwnersPagePath):
        final skoreClass = classWithId(
          int.tryParse(query['classID'] ?? '') ?? 0,
        );
        final courses = skoreClass?.courses;
        // A class without a structure and an unknown class id get the same
        // answer, as in the capture.
        return _html(
          courses == null
              ? _noStructurePage
              : _ownersPage(skoreClass!, courses),
        );
      case ('POST', fakeSkoreOwnersRpcPath):
        final method = form['rpc_method'];
        if (method != 'getTeachers') {
          return _json(
            '{"error":"the fake does not serve $method"}',
            status: 501,
          );
        }
        return _json(
          jsonEncode({
            'result': [
              for (final teacher in teachers)
                {'userID': '${teacher.id}', 'name': teacher.name},
            ],
            'session': 1,
            'method': 'getTeachers',
            'timelimit': 0,
            'limitInfo': null,
          }),
        );
    }
    return null;
  }

  /// The tree of report models as Skore answers `select_models`: a model
  /// node holds a members node, which holds groups (`childmember`) of
  /// classes (`classroom`), or classes directly; and a node of another
  /// kind that holds no classes.
  Map<String, Object?> _modelsTree() => {
    'content': _content('modellen16.gif', 'Modellen'),
    'data': {'item': 'models', 'func': 1},
    'children': [
      for (final model in models)
        {
          'content': _content('blockdevice.png', model.name),
          'data': {
            'item': 'model',
            'func': '${model.id}',
            'modelname': model.name,
          },
          'closed': 1,
          'children': [
            {
              'content': _content('users2_16x16.png', 'Leden'),
              'data': {
                'item': 'members',
                'func': '${model.id}',
                'modelname': model.name,
              },
              'closed': 1,
              'children': [
                for (final group in model.groups)
                  if (group.id == null)
                    for (final skoreClass in group.classes)
                      _classNode(skoreClass)
                  else
                    {
                      'content': _content('users3_16x16.png', group.name),
                      'data': {
                        'item': 'childmember',
                        'func': '${model.id}_${group.id}',
                        'groupname': group.name,
                      },
                      'children': [
                        for (final skoreClass in group.classes)
                          _classNode(skoreClass),
                      ],
                    },
              ],
            },
            {
              'content': _content('calculator_flat_16x16.png', 'Rapporten'),
              'data': {'item': 'reports', 'func': '${model.id}'},
              'closed': 1,
            },
          ],
        },
    ],
  };

  static Map<String, Object?> _classNode(FakeSkoreClass skoreClass) => {
    'content': _content('briefcase_16x16.png', skoreClass.name),
    'data': {'item': 'classroom', 'func': '${skoreClass.id}'},
  };

  /// A tree node's content: an icon, `&nbsp;` and the name.
  static String _content(String icon, String name) =>
      '<img src="/smsc/img/$icon" border="0" height="16" width="16" '
      'align="absmidle"/>&nbsp;${_text.convert(name)}';

  /// The assignments page of [skoreClass], a row per course.
  static String _ownersPage(
    FakeSkoreClass skoreClass,
    List<FakeSkoreCourse> courses,
  ) {
    final rows = StringBuffer();
    for (final course in courses) {
      final kind = course.groupHeader ? 'owners_vz' : 'owners_v';
      final header = course.groupHeader ? ' grouponly="true"' : '';
      final owners = StringBuffer();
      for (final assignment in course.assignments) {
        owners.write(
          '<div dojoType="ownernode" ownerID="${assignment.id}" '
          'userID="${assignment.teacher.id}" courseID="${course.id}" '
          'classID="${skoreClass.id}" '
          'coursename="${_attribute.convert(course.name)}" '
          'style="visibility:hidden;">'
          '${_text.convert(assignment.teacher.name)}</div>',
        );
      }
      rows.write('''
  <tr class="ownertable_odd">
      <td>
          <div class="$kind" style="margin-left:${course.depth * 10}px;">${_text.convert(course.label)}</div></td>
      <td>
          <div class="class" dojoType="ownercontainer" courseID="${course.id}" coursename="${_attribute.convert(course.name)}" classID="${skoreClass.id}"$header>$owners</div></td></tr>
''');
    }
    return '<table width="100%" border="0" cellspacing="0" cellpadding="0" '
        'class="ownertable">\n$rows</table>';
  }

  static const _text = HtmlEscape(HtmlEscapeMode.element);
  static const _attribute = HtmlEscape(HtmlEscapeMode.attribute);

  static ResponseBody _html(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=UTF-8'],
        },
      );

  /// A JSON answer, which Skore sends as `text/html`, as in the captures.
  static ResponseBody _json(String body, {int status = 200}) =>
      _html(body, status: status);
}

/// Skore's answer to the assignments page of a class without a structure,
/// and of a class id it does not know.
const _noStructurePage =
    '<span data-i18n="class_has_no_structure">Deze klas bevat nog geen '
    "structuur. Geef deze klas een structuur via 'Koppeling'.</span>";

/// A "no access" page that names the user, as a refusal might.
const fakeSkoreNoAccessName = 'Lena Vermeulen';
const _noAccessPage =
    '<!DOCTYPE html><html><body><h1>Geen toegang</h1>'
    '<p>$fakeSkoreNoAccessName heeft geen rechten voor deze pagina.</p>'
    '</body></html>';
