import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart'
    show PlannerService;

/// The planner user id of the fake's own account: the `authenticatedUser.id`
/// of the fake's pages ([fakeDisplayName] in `fake_smartschool.dart`).
const fakePlannerMe = '12_345_0';

const _api = '/planner/api/v1';

/// Where the school's assignment types are read: the lesson-content API.
const fakeAssignmentTypesPath =
    '/lesson-content/api/v1/assignments/applicable-assignment-types';

/// Where the user's lesfiches are read: the Lesfiches module's list, with
/// the slash at the end, as the library asks for it.
const fakeLesfichesPath = '/lesson-content/api/v1/lesson-content/';

/// The moment [year]-[month]-[day] [hour]:[minute]:[second] in the time of
/// this PC, written as the planner writes a date and time: ISO 8601 with the
/// offset (`2026-10-05T10:20:00+02:00` in Belgium in October,
/// `2026-11-20T11:10:00+01:00` in November).
///
/// The elements of the captures are written so, so that a test reads the
/// same clock times on any PC, in CI (UTC) too; on a PC in Belgium they are
/// the captures' own times. A test of the offsets themselves writes them out.
String plannerTime(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) => PlannerService.formatDateTime(
  DateTime(year, month, day, hour, minute, second),
);

/// A user as the planner names one: an organiser or a participant.
class FakePlannerUser {
  const FakePlannerUser(this.id, this.name, this.nameLastFirst);

  /// The fake's own account.
  static const me = FakePlannerUser(
    fakePlannerMe,
    'Jan Peeters',
    'Peeters Jan',
  );

  /// The planner user id, `{platformId}_{userId}_{coaccount}`.
  final String id;
  final String name;
  final String nameLastFirst;

  Map<String, Object?> toJson() => {
    'id': id,
    'pictureHash': 'initials_XX',
    'pictureUrl':
        'https://userpicture20.smartschool.be/User/Userimage/hashimage/hash/'
        'initials_XX/plain/1/res/128',
    'description': {'startingWithFirstName': '', 'startingWithLastName': ''},
    'name': {
      'startingWithFirstName': name,
      'startingWithLastName': nameLastFirst,
    },
    'sort': nameLastFirst.toLowerCase().replaceAll(' ', '-'),
    'deleted': false,
  };
}

/// A class as the planner names one.
class FakePlannerGroup {
  const FakePlannerGroup(this.id, this.name);

  /// The planner group id, `{platformId}_{groupId}`.
  final String id;
  final String name;

  Map<String, Object?> toJson() => {
    'identifier': id,
    'id': id,
    'platformId': int.parse(id.split('_').first),
    'name': name,
    'type': 'K',
    'icon': 'briefcase',
    'sort': name,
  };
}

/// A course as the planner names one.
class FakePlannerCourse {
  const FakePlannerCourse(this.id, this.name, [this.codes = const []]);

  final String id;
  final String name;
  final List<String> codes;

  Map<String, Object?> toJson() => {
    'id': id,
    'platformId': 4069,
    'name': name,
    'scheduleCodes': codes,
    'icon': 'schoolbord',
    'courseCluster': null,
    'isVisible': true,
  };
}

/// A room as the planner names one; its planner is `location/4069_<id>`.
class FakePlannerRoom {
  const FakePlannerRoom(this.id, this.title);

  final String id;
  final String title;

  /// The planner id of the room, as `search_planners` prints it.
  String get planner => 'location/4069_$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'platformId': 4069,
    'platformName': 'Springfield Academy',
    'number': '',
    'title': title,
    'icon': '',
    'type': 'mini-db-item',
    'selectable': true,
  };
}

/// An assignment type, such as `KO Kleine Overhoring`: the six types of
/// dartschool's capture of a school's types
/// (`test/planner_workload_test.dart` there), in [school].
class FakeAssignmentType {
  const FakeAssignmentType(this.id, this.name, this.abbreviation);

  static const go = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000002',
    'Grote Overhoring',
    'GO',
  );
  static const gt = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000003',
    'Grote Taak',
    'GT',
  );
  static const ko = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000001',
    'Kleine Overhoring',
    'KO',
  );
  static const kt = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000004',
    'Kleine Taak',
    'KT',
  );
  static const mb = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000005',
    'Meebrengen',
    'MB',
  );
  static const v = FakeAssignmentType(
    'a0000000-0000-4000-8000-000000000006',
    'Voorbereiding',
    'V',
  );

  /// The school's types, in the order the planner gave them.
  static const school = [go, gt, ko, kt, mb, v];

  final String id;
  final String name;
  final String abbreviation;

  /// The type as a planned element names it.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'abbreviation': abbreviation,
    'isVisible': true,
    'defaultTiming': 'deadline',
    'weight': 0,
  };

  /// The type as the list of the school's types and a workload setting name
  /// it: with its platform.
  Map<String, Object?> schoolJson() => {
    'id': id,
    'platformId': 4069,
    'name': name,
    'abbreviation': abbreviation,
    'isVisible': true,
    'defaultTiming': 'deadline',
    'weight': 0,
  };
}

/// The workload setting of a class: the limit the school set for it, in the
/// shape of dartschool's capture of the workload schedule.
class FakeWorkloadSetting {
  const FakeWorkloadSetting(
    this.id,
    this.name, {
    required this.limit,
    this.period = 'day',
    this.type = 'soft',
  });

  /// The setting of every class at the school seen live: no limit (`-1`).
  static const noLimit = FakeWorkloadSetting(
    'b0000000-0000-4000-8000-000000000001',
    'Geen limiet',
    limit: -1,
  );

  final String id;
  final String name;
  final num limit;
  final String period;
  final String type;

  Map<String, Object?> toJson(List<FakeAssignmentType> allowed) => {
    'id': id,
    'platformId': 4069,
    'color': 'aqua-500',
    'name': name,
    'limit': {'value': limit, 'period': period, 'type': type},
    'allowedAssignmentTypes': [for (final type in allowed) type.schoolJson()],
  };
}

/// An element of the fake planner, which it serves in the calendars it was
/// added to (the list form) and on its own (the detail).
///
/// The JSON has the shape of dartschool's anonymised captures of the live
/// planner (`test/planner_service_test.dart` there): a list element, and a
/// detail that adds the info texts, labels, attachments and weblinks, and
/// for an assignment its visibility and announcement. [from] and [to] are
/// written as the planner writes them, with the school's offset
/// (`2026-10-05T10:20:00+02:00`).
class FakePlannedElement {
  FakePlannedElement({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    this.name,
    this.platformId = 4069,
    this.wholeDay = false,
    this.deadline = false,
    this.organisers = const [],
    this.groups = const [],
    this.users = const [],
    this.courses = const [],
    this.rooms = const [],
    this.assignmentType,
    this.publicInfo = '',
    this.privateInfo = '',
    this.labels = const [],
    this.attachments = const [],
    this.weblinks = const [],
    this.visibleFrom,
    this.isAnnounced,
    this.capabilities = const {},
  });

  final String id;

  /// The planner's name of the type (`planned-lessons`).
  final String type;
  final int platformId;
  final String? name;
  final String from;
  final String to;
  final bool wholeDay;
  final bool deadline;
  final List<FakePlannerUser> organisers;
  final List<FakePlannerGroup> groups;
  final List<FakePlannerUser> users;
  final List<FakePlannerCourse> courses;
  final List<FakePlannerRoom> rooms;
  final FakeAssignmentType? assignmentType;

  /// HTML, as the planner keeps it.
  final String publicInfo;
  final String privateInfo;

  /// The texts of the labels.
  final List<String> labels;

  /// The names of the attachments.
  final List<String> attachments;

  /// The weblinks: name and address.
  final List<(String, String)> weblinks;
  final String? visibleFrom;
  final bool? isAnnounced;

  /// Capabilities that differ from what the planner gives an element of
  /// this type ([capabilityJson]), such as `{'canUserReplace': false}`.
  final Map<String, bool> capabilities;

  /// The element id as the planner tools print it.
  String get ref => '$type/$platformId/$id';

  bool get _isAssignment => type == 'planned-assignments';

  /// Whether the fake's own account organises it.
  bool get isOwn => organisers.any((user) => user.id == fakePlannerMe);

  /// What the planner lets the fake's own account do with the element, as
  /// dartschool's captures of #87 and #89 show it: everything the type
  /// allows for an element of its own (an empty lesson hour can be filled,
  /// not renamed; a lesson in a lesson hour can be edited and cleared, not
  /// trashed or deleted; an assignment can be trashed), nothing for a
  /// colleague's; then [capabilities].
  Map<String, Object?> capabilityJson() => {
    ...switch (type) {
      'planned-placeholders' => {
        'canUserTrash': false,
        'canUserDelete': false,
        'canUserEdit': isOwn,
        'canUserReplace': isOwn,
        'canUserRename': false,
      },
      'planned-lessons' => {
        'canUserTrash': false,
        'canUserDelete': false,
        'canUserEdit': isOwn,
        'canUserChangePrivateInfo': isOwn,
        'canUserChangePublicInfo': isOwn,
        'canUserReplace': isOwn,
        'canUserRename': isOwn,
      },
      'planned-assignments' => {
        'canUserTrash': isOwn,
        'canUserDelete': isOwn,
        'canUserEdit': isOwn,
        'canUserChangePrivateInfo': isOwn,
        'canUserChangePublicInfo': isOwn,
        'canUserRename': isOwn,
      },
      _ => {'canUserEdit': isOwn},
    },
    ...capabilities,
    'canUserSeeProperties': {'id': true, 'name': true},
  };

  /// This element with the [name], [publicInfo] and [privateInfo] given
  /// changed, as an edit of the planner leaves it.
  FakePlannedElement withChanges({
    String? name,
    String? publicInfo,
    String? privateInfo,
  }) => FakePlannedElement(
    id: id,
    type: type,
    from: from,
    to: to,
    name: name ?? this.name,
    platformId: platformId,
    wholeDay: wholeDay,
    deadline: deadline,
    organisers: organisers,
    groups: groups,
    users: users,
    courses: courses,
    rooms: rooms,
    assignmentType: assignmentType,
    publicInfo: publicInfo ?? this.publicInfo,
    privateInfo: privateInfo ?? this.privateInfo,
    labels: labels,
    attachments: attachments,
    weblinks: weblinks,
    visibleFrom: visibleFrom,
    isAnnounced: isAnnounced,
    capabilities: capabilities,
  );

  /// A new element of [type] with the id [id] in this element's lesson
  /// hour: its period, organisers, classes, course and rooms, as the planner
  /// makes a lesson of an empty lesson hour and the other way round.
  FakePlannedElement inSameHour({
    required String id,
    required String type,
    String? name,
    String publicInfo = '',
    String privateInfo = '',
    List<String> labels = const [],
  }) => FakePlannedElement(
    id: id,
    type: type,
    from: from,
    to: to,
    name: name,
    platformId: platformId,
    wholeDay: wholeDay,
    organisers: organisers,
    groups: groups,
    users: users,
    courses: courses,
    rooms: rooms,
    publicInfo: publicInfo,
    privateInfo: privateInfo,
    labels: labels,
  );

  bool overlaps(DateTime start, DateTime end) =>
      !DateTime.parse(from).isAfter(end) && !DateTime.parse(to).isBefore(start);

  Map<String, Object?> listJson() => {
    'id': id,
    'platformId': platformId,
    'name': ?name,
    if (assignmentType case final type?) 'assignmentType': type.toJson(),
    'period': {
      'dateTimeFrom': from,
      'dateTimeTo': to,
      'wholeDay': wholeDay,
      'deadline': deadline,
    },
    'organisers': {
      'users': [for (final user in organisers) user.toJson()],
      'groups': <Object?>[],
    },
    'participants': {
      'users': [for (final user in users) user.toJson()],
      'groups': [for (final group in groups) group.toJson()],
      'userRoles': <Object?>[],
      'groupFilters': {'filters': <Object?>[], 'additionalUsers': <Object?>[]},
    },
    'plannedElementType': type,
    'isParticipant': false,
    'capabilities': capabilityJson(),
    'onlineSession': null,
    if (_isAssignment) 'resolvedStatus': 'unresolved',
    if (name != null)
      'icon': _isAssignment ? 'flags_red_yellow' : 'document_observation',
    'courses': [for (final course in courses) course.toJson()],
    'locations': [for (final room in rooms) room.toJson()],
    'sort': '${from.replaceAll(RegExp(r'\D'), '').substring(0, 14)}_$id',
    'unconfirmed': false,
    'pinned': false,
    'color': 'aqua-200',
  };

  Map<String, Object?> detailJson() => {
    ...listJson(),
    'info': privateInfo,
    'privateInfo': privateInfo,
    'publicInfo': publicInfo,
    'miniDBItems': <Object?>[],
    'labels': [
      for (final (index, text) in labels.indexed)
        {
          'identifier': '4069_d0000000-0000-4000-8000-00000000000$index',
          'type': 'platform',
          'text': text,
          'color': 'aqua',
          'isVisible': true,
          'id': '4069_d0000000-0000-4000-8000-00000000000$index',
        },
    ],
    'attachments': [
      for (final (index, name) in attachments.indexed)
        {'id': 'f0000000-0000-4000-8000-00000000003$index', 'name': name},
    ],
    'weblinks': [
      for (final (index, (name, url)) in weblinks.indexed)
        {
          'id': 'e0000000-0000-4000-8000-00000000002$index',
          'name': name,
          'url': url,
          'icon': 'earth',
          'visibility': {'option': 'always', 'daysAfterEnd': null},
        },
    ],
    'courseLinks': <Object?>[],
    'goals': <Object?>[],
    'reminders': <Object?>[],
    if (_isAssignment) ...{
      'uploadFolder': null,
      'isAnnounced': isAnnounced ?? false,
      'visibility': {'afterDate': ?visibleFrom},
      'hasLinkedEvaluation': false,
      'linkedEvaluation': null,
      'dateCreated': visibleFrom ?? from,
    },
  };
}

/// A lesfiche of the Lesfiches module (lesson content), which the fake
/// lists at [fakeLesfichesPath] and the planner plans into an empty lesson
/// hour.
///
/// The JSON has the shape of dartschool's anonymised capture of the live
/// list (`test/lesson_content_service_test.dart` there, #88): dates without
/// an offset, courses by id only, the school's labels (`platform`) and the
/// user's own (`user`).
class FakeLesfiche {
  const FakeLesfiche({
    required this.id,
    required this.name,
    this.type = 'lessons',
    this.icon = 'document_observation',
    this.publicInfo = '',
    this.isVisible = true,
    this.owner = fakePlannerMe,
    this.lastChanged = '2025-09-12 12:24:59',
    this.courses = const [],
    this.labels = const [],
    this.ownLabels = const [],
    this.assignmentType,
    this.attachments = const [],
  });

  final String id;
  final String name;

  /// The module's name of the kind: `lessons` or `assignments`.
  final String type;
  final String? icon;

  /// HTML, as the module keeps it.
  final String publicInfo;
  final bool isVisible;

  /// The whole user id of the owner.
  final String owner;

  /// When it was last changed, as the module writes it: `2025-09-12
  /// 12:24:59`, without an offset.
  final String lastChanged;
  final List<FakePlannerCourse> courses;

  /// The texts of the school's labels, such as `JAAR 6`.
  final List<String> labels;

  /// The texts of the user's own labels.
  final List<String> ownLabels;
  final FakeAssignmentType? assignmentType;

  /// The names of the attachments.
  final List<String> attachments;

  Map<String, Object?> toJson() => {
    'id': id,
    'platformId': 4069,
    if (assignmentType case final type?) 'assignmentType': type.schoolJson(),
    'name': name,
    'icon': ?icon,
    'publicInfo': publicInfo,
    'isVisible': isVisible,
    'owner': owner,
    'dateStateChanged': lastChanged,
    'dateLastChanged': lastChanged,
    'courses': [
      for (final course in courses) {'platformId': 4069, 'id': course.id},
    ],
    'labels': [
      for (final (index, text) in labels.indexed)
        {
          'identifier': '4069_d0000000-0000-4000-8000-00000000000$index',
          'type': 'platform',
          'text': text,
          'color': 'aqua',
          'isVisible': true,
          'id': '4069_d0000000-0000-4000-8000-00000000000$index',
          'platformId': 4069,
          'ssId': 4069,
          'locations': ['lesson_content', 'planner'],
        },
      for (final (index, text) in ownLabels.indexed)
        {
          'identifier': '${owner}_d0000000-0000-4000-8000-00000000010$index',
          'type': 'user',
          'text': text,
          'color': 'steel',
          'isVisible': true,
          'id': '${owner}_d0000000-0000-4000-8000-00000000010$index',
          'userId': owner,
        },
    ],
    'weblinks': <Object?>[],
    'partnerWeblinks': <Object?>[],
    'attachments': [
      for (final (index, name) in attachments.indexed)
        {'id': 'f0000000-0000-4000-8000-00000000004$index', 'name': name},
    ],
    'deeplinks': <Object?>[],
    'capabilities': {
      'canUserSeeDetails': true,
      'canUserEdit': true,
      'canUserTrash': true,
      'canUserTrashAsAdmin': false,
    },
    'type': type,
  };
}

/// A hit of the planner's search, in the shape of dartschool's anonymised
/// captures of `POST quick-search/planner/search`.
class FakePlannerHit {
  FakePlannerHit.group(String id, this.name, {String description = ''})
    : json = {
        'identifier': {'id': id, 'type': 'group'},
        'title': [
          {'part': name, 'isHighlighted': false},
        ],
        'description': <Object?>[],
        'graphic': {'type': 'icon', 'value': 'briefcase'},
        'origin': {
          'groupIdentifier': id,
          'name': name,
          'description': description,
        },
      };

  /// A person: [listedAs] is the title of the search list, last name first,
  /// for a pupil with the class (`Janssens Lotte • 6A1`).
  FakePlannerHit.user(
    FakePlannerUser user, {
    String? listedAs,
    String description = '',
  }) : name = user.name,
       json = {
         'identifier': {'id': user.id, 'type': 'user'},
         'title': [
           {'part': listedAs ?? user.nameLastFirst, 'isHighlighted': false},
         ],
         'description': <Object?>[],
         'graphic': {'type': 'image', 'value': 'https://example.invalid/48'},
         'origin': {
           'userIdentifier': user.id,
           'name': user.name,
           'nameReverse': user.nameLastFirst,
           'description': description,
         },
       };

  FakePlannerHit.room(FakePlannerRoom room)
    : name = room.title,
      json = {
        'identifier': {'id': '4069_${room.id}', 'type': 'mini-db-2'},
        'title': [
          {'part': room.title, 'isHighlighted': true},
        ],
        'description': [
          {'part': 'Locatie', 'isHighlighted': false},
        ],
        'graphic': {'type': 'icon', 'value': 'location_ic_action'},
        'origin': {
          'itemId': room.id,
          'name': room.title,
          'breadCrumbs': ['Locatie'],
          'modules': ['location'],
        },
      };

  /// A hit of a kind the library cannot map to a planner (made up in
  /// dartschool's tests too: none was seen live).
  FakePlannerHit.other(String id, String type, this.name)
    : json = {
        'identifier': {'id': id, 'type': type},
        'title': [
          {'part': name, 'isHighlighted': true},
        ],
        'description': <Object?>[],
        'graphic': {'type': 'icon', 'value': type},
        'origin': {'name': name},
      };

  final String name;
  final Map<String, Object?> json;
}

/// The planner module of a fake Smartschool: the elements of the calendars
/// of users, classes and rooms, the detail of each element, the search, and
/// the workload view of classes with the school's assignment types.
///
/// It serves:
/// - `GET /planner/api/v1/planned-elements/{user|group|location}/{id}` with
///   `from`, `to` and an optional `types`: the elements added to that
///   calendar that overlap the period, of those types. A calendar it does
///   not know is answered with `400`, as the planner answers an id it
///   refuses;
/// - `GET /planner/api/v1/{plannedElementType}/{platformId}/{id}`: the
///   detail, or the planner's `404` for an element it does not have;
/// - `POST /planner/api/v1/quick-search/planner/search`: the [hits] whose
///   name or title holds the search string, ignoring case;
/// - `POST /planner/api/v1/workload/planned-elements` with `from` and `to`
///   and the `groups`: the assignments of those classes that overlap the
///   period, once each, in the order they were added (not by date, like
///   the planner's);
/// - `POST /planner/api/v1/workload/schedule` with `from` and `to` and the
///   `groups`: for every day of the period (in the time of this PC), the
///   workload of each class: its [workloadWeights] (0 by default) and its
///   [workloadSettings] ([FakeWorkloadSetting.noLimit] by default);
/// - `GET` [fakeAssignmentTypesPath]: the [assignmentTypes];
/// - `GET` [fakeLesfichesPath]: the [lesfiches], in the order added.
///
/// The workload calls answer `400` for a class the fake does not know (one
/// of no element or calendar), as the calendars do.
///
/// And the writes of dartschool#87, which change what it serves as the live
/// planner did (the request bodies are recorded as sent, for the tests to
/// compare with dartschool's):
/// - `POST /planner/api/v1/planned-placeholders/{platformId}/{id}/replace/planned-lessons/blanco`:
///   fills the empty lesson hour as [fillSlot] does, and answers with the
///   lesson;
/// - `POST /planner/api/v1/planned-placeholders/{platformId}/{id}/replace/planned-lessons`
///   (dartschool#88, its `sourceId` a lesfiche id): fills the empty lesson
///   hour with a lesson named after the lesfiche, with its labels and its
///   public info, as the live planner did (it took the name, the labels and
///   the empty info of the lesfiche tried), and answers with the lesson; a
///   lesfiche it does not have is answered with `400` (made up: the library
///   refuses one before sending);
/// - `POST /planner/api/v1/{plannedElementType}/{platformId}/{id}/rename`
///   (`newName`), `.../change-public-info` and `.../change-private-info`
///   (`newInfo`): changes the element, and answers with it;
/// - `POST /planner/api/v1/planned-elements/clear` (`type`, `elementId`,
///   `elementPlatformId`): clears the lesson as [clearLesson] does, and
///   answers with the empty lesson hour.
///
/// A write of an element the fake does not have is answered with `404`.
/// The fake does not check whose element it changes: the library does that
/// before it sends a write, and the tests check that none is sent for a
/// colleague's.
///
/// Every planner request is recorded in [requests]. [failing] answers a
/// path with another status instead (a write is then not carried out);
/// [lostAnswers] carries the write to a path out, but drops the connection
/// before the answer.
class FakePlanner {
  /// The elements of each calendar, by `user/{id}`, `group/{id}` or
  /// `location/{id}`.
  final Map<String, List<FakePlannedElement>> calendars = {};

  /// Every element, by [FakePlannedElement.ref].
  final Map<String, FakePlannedElement> elements = {};

  /// What the search finds.
  final List<FakePlannerHit> hits = [];

  /// The classes the fake knows, by id: those of the elements and of the
  /// class calendars.
  final Map<String, FakePlannerGroup> classes = {};

  /// The school's assignment types.
  final List<FakeAssignmentType> assignmentTypes = [];

  /// The user's lesfiches in the Lesfiches module.
  final List<FakeLesfiche> lesfiches = [];

  /// The workload setting of a class, by class id; the others have
  /// [FakeWorkloadSetting.noLimit].
  final Map<String, FakeWorkloadSetting> workloadSettings = {};

  /// The planner's workload figure (`weight`) of a class on a day, by class
  /// id and day (`2026-10-05`); 0 when not set.
  final Map<(String, String), num> workloadWeights = {};

  /// The planner requests, in order.
  final List<
    ({String method, String path, Map<String, String> query, Object? data})
  >
  requests = [];

  /// Paths answered with this status (and an answer the planner might give)
  /// instead.
  final Map<String, int> failing = {};

  /// Paths of writes that are carried out, after which the connection drops
  /// before the answer arrives.
  final Set<String> lostAnswers = {};

  /// How many elements the writes made, for their ids.
  int _made = 0;

  /// The planner requests that change something, as `POST path`, in order.
  List<String> get writes => [
    for (final request in requests)
      if (request.method == 'POST' && _isWrite(request.path))
        'POST ${request.path}',
  ];

  static bool _isWrite(String path) =>
      !path.startsWith('$_api/quick-search/') &&
      !path.startsWith('$_api/workload/');

  /// Fills the empty lesson hour [ref] (`planned-placeholders/4069/<id>`)
  /// with a lesson named [name], as the planner does: the hour is gone under
  /// its id, and a lesson with a new id takes its place, in its period, with
  /// its organisers, classes, course and rooms, in every calendar it was
  /// in. Returns the lesson, or null when the fake has no such hour.
  FakePlannedElement? fillSlot(
    String ref, {
    required String name,
    String publicInfo = '',
    String privateInfo = '',
    List<String> labels = const [],
  }) {
    final slot = elements[ref];
    if (slot == null || slot.type != 'planned-placeholders') return null;
    final lesson = slot.inSameHour(
      id: _newId('4000'),
      type: 'planned-lessons',
      name: name,
      publicInfo: publicInfo,
      privateInfo: privateInfo,
      labels: labels,
    );
    _replace(slot, lesson);
    return lesson;
  }

  /// Clears the lesson [ref] (`planned-lessons/4069/<id>`), as the planner
  /// does: the lesson is gone, and an empty lesson hour with a new id takes
  /// its place. Returns the hour, or null when the fake has no such lesson.
  FakePlannedElement? clearLesson(String ref) {
    final lesson = elements[ref];
    if (lesson == null || lesson.type != 'planned-lessons') return null;
    final slot = lesson.inSameHour(
      id: _newId('5000'),
      type: 'planned-placeholders',
    );
    _replace(lesson, slot);
    return slot;
  }

  /// A new element id, with [version] as its third part (`4000` for a
  /// lesson, `5000` for an empty lesson hour, as in the captures).
  String _newId(String version) =>
      'e0000000-0000-$version-9000-${(++_made).toString().padLeft(12, '0')}';

  /// Puts [replacement] in the place of [element]: in [elements] and in
  /// every calendar.
  void _replace(FakePlannedElement element, FakePlannedElement replacement) {
    elements.remove(element.ref);
    elements[replacement.ref] = replacement;
    for (final listed in calendars.values) {
      final index = listed.indexOf(element);
      if (index >= 0) listed[index] = replacement;
    }
  }

  /// Adds [element] to each of [calendars] (such as `group/4069_2001`), and
  /// makes its detail readable.
  void add(FakePlannedElement element, {required List<String> calendars}) {
    elements[element.ref] = element;
    for (final group in element.groups) {
      classes.putIfAbsent(group.id, () => group);
    }
    for (final calendar in calendars) {
      this.calendars.putIfAbsent(calendar, () => []).add(element);
    }
  }

  /// Makes [calendar] known, without elements.
  void addCalendar(String calendar) =>
      calendars.putIfAbsent(calendar, () => []);

  /// Makes class [group] and its calendar known, without elements.
  void addClass(FakePlannerGroup group) {
    classes.putIfAbsent(group.id, () => group);
    addCalendar('group/${group.id}');
  }

  /// The `from`, `to` and `types` of the calendar requests, in order.
  List<Map<String, String>> get calendarQueries => [
    for (final request in requests)
      if (request.path.startsWith('$_api/planned-elements/')) request.query,
  ];

  ResponseBody? respond(RequestOptions options) {
    final path = options.uri.path;
    if (!path.startsWith('$_api/') &&
        path != fakeAssignmentTypesPath &&
        path != fakeLesfichesPath) {
      return null;
    }
    requests.add((
      method: options.method,
      path: path,
      query: options.uri.queryParameters,
      data: options.data,
    ));
    if (failing[path] case final status?) {
      return _json(
        '{"status":$status,"title":"Error","detail":"","type":""}',
        status: status,
      );
    }
    if (path == fakeAssignmentTypesPath) {
      if (options.method != 'GET') return null;
      return _json(
        jsonEncode([for (final type in assignmentTypes) type.schoolJson()]),
      );
    }
    if (path == fakeLesfichesPath) {
      if (options.method != 'GET') return null;
      return _json(
        jsonEncode([for (final lesfiche in lesfiches) lesfiche.toJson()]),
      );
    }
    final route = path.substring(_api.length + 1).split('/');
    if (options.method == 'POST') {
      final answer = switch (route) {
        ['quick-search', 'planner', 'search'] => _search(options.data),
        ['workload', 'planned-elements'] => _workloadAssignments(
          options.uri.queryParameters,
          options.data,
        ),
        ['workload', 'schedule'] => _workloadSchedule(
          options.uri.queryParameters,
          options.data,
        ),
        [
          'planned-placeholders',
          final platform,
          final id,
          'replace',
          'planned-lessons',
          'blanco',
        ] =>
          _fill(
            'planned-placeholders/$platform/${Uri.decodeComponent(id)}',
            options.data,
          ),
        [
          'planned-placeholders',
          final platform,
          final id,
          'replace',
          'planned-lessons',
        ] =>
          _fillWithLesfiche(
            'planned-placeholders/$platform/${Uri.decodeComponent(id)}',
            options.data,
          ),
        ['planned-elements', 'clear'] => _clear(options.data),
        [
          final type,
          final platform,
          final id,
          final action &&
              ('rename' || 'change-public-info' || 'change-private-info'),
        ] =>
          _edit(
            '$type/$platform/${Uri.decodeComponent(id)}',
            action,
            options.data,
          ),
        _ => null,
      };
      if (answer != null && lostAnswers.contains(path)) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection reset by peer',
        );
      }
      return answer;
    }
    if (options.method != 'GET') return null;
    if (route case ['planned-elements', final kind, final id]) {
      return _calendar(
        '$kind/${Uri.decodeComponent(id)}',
        options.uri.queryParameters,
      );
    }
    if (route case [final type, final platform, final id]) {
      final element = elements['$type/$platform/${Uri.decodeComponent(id)}'];
      if (element == null) {
        return _json(
          '{"status":404,"title":"Not Found","detail":"","type":""}',
          status: 404,
        );
      }
      return _json(jsonEncode(element.detailJson()));
    }
    return null;
  }

  ResponseBody _notFound() => _json(
    '{"status":404,"title":"Not Found","detail":"","type":""}',
    status: 404,
  );

  ResponseBody _fill(String ref, Object? data) {
    final body = data as Map;
    final lesson = fillSlot(
      ref,
      name: body['name'] as String,
      publicInfo: body['publicInfo'] as String,
      privateInfo: body['privateInfo'] as String,
    );
    if (lesson == null) return _notFound();
    return _json(jsonEncode(lesson.detailJson()));
  }

  ResponseBody _fillWithLesfiche(String ref, Object? data) {
    final sourceId = ((data as Map)['sourceId'] as String).toLowerCase();
    final lesfiche = lesfiches
        .where((lesfiche) => lesfiche.id.toLowerCase() == sourceId)
        .firstOrNull;
    if (lesfiche == null) return _badRequest();
    final lesson = fillSlot(
      ref,
      name: lesfiche.name,
      publicInfo: lesfiche.publicInfo,
      labels: [...lesfiche.labels, ...lesfiche.ownLabels],
    );
    if (lesson == null) return _notFound();
    return _json(jsonEncode(lesson.detailJson()));
  }

  ResponseBody _clear(Object? data) {
    final body = data as Map;
    final slot = clearLesson(
      '${body['type']}/${body['elementPlatformId']}/${body['elementId']}',
    );
    if (slot == null) return _notFound();
    return _json(jsonEncode(slot.detailJson()));
  }

  ResponseBody _edit(String ref, String action, Object? data) {
    final element = elements[ref];
    if (element == null) return _notFound();
    final body = data as Map;
    final changed = switch (action) {
      'rename' => element.withChanges(name: body['newName'] as String),
      'change-public-info' => element.withChanges(
        publicInfo: body['newInfo'] as String,
      ),
      _ => element.withChanges(privateInfo: body['newInfo'] as String),
    };
    _replace(element, changed);
    return _json(jsonEncode(changed.detailJson()));
  }

  /// The classes of a workload request, or null when the fake does not know
  /// one of them.
  List<FakePlannerGroup>? _workloadClasses(Object? data) {
    final groups = <FakePlannerGroup>[];
    for (final id in (data as Map)['groups'] as List) {
      final group = classes[id];
      if (group == null) return null;
      groups.add(group);
    }
    return groups;
  }

  ResponseBody _badRequest() => _json(
    '{"status":400,"title":"Bad Request","detail":"","type":""}',
    status: 400,
  );

  ResponseBody _workloadAssignments(Map<String, String> query, Object? data) {
    final groups = _workloadClasses(data);
    if (groups == null) return _badRequest();
    final ids = {for (final group in groups) group.id};
    final from = DateTime.parse(query['from']!);
    final to = DateTime.parse(query['to']!);
    return _json(
      jsonEncode([
        for (final element in elements.values)
          if (element._isAssignment &&
              element.overlaps(from, to) &&
              element.groups.any((group) => ids.contains(group.id)))
            element.listJson(),
      ]),
    );
  }

  ResponseBody _workloadSchedule(Map<String, String> query, Object? data) {
    final groups = _workloadClasses(data);
    if (groups == null) return _badRequest();
    final from = DateTime.parse(query['from']!).toLocal();
    final to = DateTime.parse(query['to']!).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final schedule = <String, Object?>{};
    for (
      var day = DateTime(from.year, from.month, from.day);
      !day.isAfter(to);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final date = '${day.year}-${two(day.month)}-${two(day.day)}';
      schedule[date] = [
        for (final group in groups)
          {
            'group': group.toJson(),
            'weight': workloadWeights[(group.id, date)] ?? 0,
            'concurrentWeight': 0,
            'workloadSetting':
                (workloadSettings[group.id] ?? FakeWorkloadSetting.noLimit)
                    .toJson(assignmentTypes),
          },
      ];
    }
    return _json(jsonEncode({'schedule': schedule}));
  }

  ResponseBody _calendar(String calendar, Map<String, String> query) {
    final listed = calendars[calendar];
    if (listed == null) return _badRequest();
    final from = DateTime.parse(query['from']!);
    final to = DateTime.parse(query['to']!);
    final types = query['types']?.split(',').toSet();
    return _json(
      jsonEncode([
        for (final element in listed)
          if (element.overlaps(from, to) &&
              (types == null || types.contains(element.type)))
            element.listJson(),
      ]),
    );
  }

  ResponseBody _search(Object? data) {
    final text = ((data as Map)['searchString'] as String).toLowerCase();
    // The names, first or last name first: the class a pupil's title ends
    // in is not searched (the captured search for 6A found only classes).
    bool matches(FakePlannerHit hit) => [
      hit.name,
      ?(hit.json['origin'] as Map)['nameReverse'] as String?,
    ].any((name) => name.toLowerCase().contains(text));

    return _json(
      jsonEncode([
        for (final hit in hits)
          if (matches(hit)) hit.json,
      ]),
    );
  }

  ResponseBody _json(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}

// ---------------------------------------------------------------------------
// The planner of dartschool's captures
// ---------------------------------------------------------------------------

/// Class 6A1, whose planner is `group/4069_2001`.
const fake6A1 = FakePlannerGroup('4069_2001', '6A1');
const fake6A2 = FakePlannerGroup('4069_2002', '6A2');
const fake6B1 = FakePlannerGroup('4069_2003', '6B1');

/// Colleagues; Piet Peeters's planner is `user/4069_1002_0`.
const fakePiet = FakePlannerUser('4069_1002_0', 'Piet Peeters', 'Peeters Piet');
const fakeWim = FakePlannerUser('4069_1003_0', 'Wim Willems', 'Willems Wim');

const fakeRoom101 = FakePlannerRoom(
  '10000000-0000-4000-8000-000000000101',
  '101',
);
const fakeRoom102 = FakePlannerRoom(
  '10000000-0000-4000-8000-000000000102',
  '102',
);
const fakeRoom103 = FakePlannerRoom(
  '10000000-0000-4000-8000-000000000103',
  '103',
);

const _wiskunde = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000001',
  'wiskunde',
  ['WISKU'],
);
const _biologie = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000002',
  'biologie',
  ['BIOLO'],
);
const _nederlands = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000003',
  'Nederlands',
  ['NEDER'],
);
const _lo = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000004',
  'lichamelijke opvoeding',
  ['LO'],
);
const fakeInformatica = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000005',
  'informatica',
  ['INFO'],
);

/// The elements of dartschool's capture of one week of class 6A1 (Monday
/// 2026-10-05 to Friday 2026-10-09; see [plannerTime] for the times): a
/// colleague's empty lesson
/// hour in two rooms, a colleague's lesson with info, a colleague's
/// assignment, a lesson without a room, and an element of a type the
/// library does not know.
final fakeSlot = FakePlannedElement(
  id: 'e0000000-0000-5000-8000-000000000001',
  type: 'planned-placeholders',
  from: plannerTime(2026, 10, 5, 14, 40),
  to: plannerTime(2026, 10, 5, 15, 30),
  organisers: [fakePiet],
  groups: [fake6A1, fake6B1],
  courses: [_wiskunde],
  rooms: [fakeRoom101, fakeRoom102],
);
final fakeLesson = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000002',
  type: 'planned-lessons',
  name: 'Erfelijkheid',
  from: plannerTime(2026, 10, 9, 14, 40),
  to: plannerTime(2026, 10, 9, 15, 30),
  organisers: [fakeWim],
  groups: [fake6A1, fake6A2],
  courses: [_biologie],
  rooms: [fakeRoom103],
  publicInfo: r'<p>Lees hoofdstuk 4</p>',
  privateInfo: r'<p><strong>Opmerkingen</strong><br />Boek meebrengen</p>',
  labels: ['JAAR 6', 'TRIMESTER 1'],
  attachments: ['hoofdstuk4.pdf'],
  weblinks: [('Opdracht', 'https://example.com/opdracht')],
);
final fakeAssignment = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000003',
  type: 'planned-assignments',
  name: 'Test: hoofdstuk 3',
  from: plannerTime(2026, 10, 6, 8, 30),
  to: plannerTime(2026, 10, 6, 9, 20),
  deadline: true,
  organisers: [fakePiet],
  groups: [fake6A1],
  courses: [_nederlands],
  rooms: [fakeRoom102],
  assignmentType: FakeAssignmentType.ko,
  visibleFrom: plannerTime(2026, 9, 26, 10, 50),
);
final fakeGymLesson = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000004',
  type: 'planned-lessons',
  name: 'Volleybal: de opslag',
  from: plannerTime(2026, 10, 7, 10, 20),
  to: plannerTime(2026, 10, 7, 11, 10),
  organisers: [fakeWim],
  groups: [fake6A1],
  courses: [_lo],
);
final fakeExcursion = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000005',
  type: 'planned-excursions',
  name: 'Uitstap naar Brussel',
  from: plannerTime(2026, 10, 8, 0, 0),
  to: plannerTime(2026, 10, 8, 23, 59, 59),
  wholeDay: true,
  organisers: [fakePiet],
  groups: [fake6A1],
);

/// An empty lesson hour of the fake's own planner in November, as in
/// dartschool's capture of an own slot (winter time in Belgium, `+01:00`).
final fakeOwnSlot = FakePlannedElement(
  id: 'e0000000-0000-5000-8000-000000000006',
  type: 'planned-placeholders',
  from: plannerTime(2026, 11, 20, 11, 10),
  to: plannerTime(2026, 11, 20, 12, 0),
  organisers: [FakePlannerUser.me],
  groups: [fake6A1, fake6A2],
  courses: [fakeInformatica],
  rooms: [fakeRoom101],
);

/// A lesson of the fake's own planner in October (summer time in Belgium,
/// `+02:00`).
final fakeOwnLesson = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000007',
  type: 'planned-lessons',
  name: 'Lussen: for en while',
  from: plannerTime(2026, 10, 5, 10, 20),
  to: plannerTime(2026, 10, 5, 11, 10),
  organisers: [FakePlannerUser.me],
  groups: [fake6A1, fake6A2],
  courses: [fakeInformatica],
  rooms: [fakeRoom101],
  publicInfo: '<p>Breng je laptop mee.</p>',
);

/// The captures, served by [FakePlanner.loadCaptures].
extension FakePlannerCaptures on FakePlanner {
  /// Serves dartschool's captures: the week of 6A1 in its class planner,
  /// the colleagues' elements in their own planners, the own lesson and
  /// empty lesson hour in the own planner (`user/12_345_0`), every element
  /// with a room in that room's planner, and the search hits of the
  /// captures (the classes 6A1 and 6A2, three people called Janssens, the
  /// room 101, and a hit of a kind without a planner).
  void loadCaptures() {
    for (final element in [
      fakeSlot,
      fakeLesson,
      fakeAssignment,
      fakeGymLesson,
      fakeExcursion,
      fakeOwnLesson,
      fakeOwnSlot,
    ]) {
      add(
        element,
        calendars: {
          for (final group in element.groups) 'group/${group.id}',
          for (final user in element.organisers) 'user/${user.id}',
          for (final room in element.rooms) room.planner,
        }.toList(),
      );
    }
    addCalendar('user/$fakePlannerMe');
    hits.addAll([
      FakePlannerHit.group('4069_2001', '6A1', description: '6 Latijn 1'),
      FakePlannerHit.group('4069_2002', '6A2', description: '6 Latijn 2'),
      FakePlannerHit.user(
        const FakePlannerUser('4069_1001_0', 'Jan Janssens', 'Janssens Jan'),
      ),
      FakePlannerHit.user(
        const FakePlannerUser(
          '4069_3001_0',
          'Lotte Janssens',
          'Janssens Lotte',
        ),
        listedAs: 'Janssens Lotte • 6A1',
      ),
      FakePlannerHit.user(
        const FakePlannerUser('4069_1004_1', 'ELS JANSSENS', 'JANSSENS ELS'),
        description: 'Interimaris van Piet Peeters',
      ),
      FakePlannerHit.room(fakeRoom101),
      FakePlannerHit.other('4069_77', 'partner', 'Bibliotheek Springfield'),
    ]);
  }
}

// ---------------------------------------------------------------------------
// The workload view of dartschool's captures
// ---------------------------------------------------------------------------

const fake6C1 = FakePlannerGroup('4069_2004', '6C1');
const fake6C2 = FakePlannerGroup('4069_2005', '6C2');
const fake6D1 = FakePlannerGroup('4069_2006', '6D1');
const fake6D2 = FakePlannerGroup('4069_2007', '6D2');

/// A colleague who plans two assignments in the same hour.
const fakeAn = FakePlannerUser('4069_1005_0', 'An Claes', 'Claes An');

const fakeRoom104 = FakePlannerRoom(
  '10000000-0000-4000-8000-000000000104',
  '104',
);
const fakeRoom105 = FakePlannerRoom(
  '10000000-0000-4000-8000-000000000105',
  '105',
);

const _chemie = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000006',
  'chemie',
  ['CHEMI'],
);
const _economie = FakePlannerCourse(
  'c0000000-0000-4000-8000-000000000007',
  'economie',
  ['ECONO'],
);

/// The assignments of dartschool's capture of the workload view of class
/// 6A1 in the week of 2026-10-05 (`test/planner_workload_test.dart` there),
/// besides [fakeAssignment] (its KO on Tuesday): on Monday a GO of six
/// classes, and an MB and a KO of one colleague in the same hour.
final fakeChemistryTest = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000012',
  type: 'planned-assignments',
  name: 'Toets: atoombouw',
  from: plannerTime(2026, 10, 5, 12, 50),
  to: plannerTime(2026, 10, 5, 13, 40),
  deadline: true,
  organisers: [fakeWim],
  groups: [fake6A1, fake6A2, fake6D2, fake6D1, fake6C2, fake6C1],
  courses: [_chemie],
  rooms: [fakeRoom104],
  assignmentType: FakeAssignmentType.go,
);
final fakeBringCalculator = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000013',
  type: 'planned-assignments',
  name: 'Rekenmachine meebrengen',
  from: plannerTime(2026, 10, 5, 9, 20),
  to: plannerTime(2026, 10, 5, 10, 10),
  deadline: true,
  organisers: [fakeAn],
  groups: [fake6A1, fake6A2],
  courses: [_economie],
  rooms: [fakeRoom105],
  assignmentType: FakeAssignmentType.mb,
);
final fakeBudgetTest = FakePlannedElement(
  id: 'e0000000-0000-4000-8000-000000000014',
  type: 'planned-assignments',
  name: 'Test: begroting',
  from: plannerTime(2026, 10, 5, 9, 20),
  to: plannerTime(2026, 10, 5, 10, 10),
  deadline: true,
  organisers: [fakeAn],
  groups: [fake6A1, fake6A2],
  courses: [_economie],
  rooms: [fakeRoom105],
  assignmentType: FakeAssignmentType.ko,
);

/// The workload view of the captures, served by
/// [FakePlannerWorkloadCaptures.loadWorkloadCaptures].
extension FakePlannerWorkloadCaptures on FakePlanner {
  /// Serves, on top of [FakePlannerCaptures.loadCaptures], dartschool's
  /// captures of the workload view: the school's six assignment types, and
  /// the assignments of 6A1 in the week of 2026-10-05 besides
  /// [fakeAssignment] ([fakeChemistryTest], [fakeBringCalculator],
  /// [fakeBudgetTest]), in the calendars of their classes, organisers and
  /// rooms. Every class has the setting `Geen limiet` and weight 0, as at
  /// the school seen live.
  void loadWorkloadCaptures() {
    assignmentTypes.addAll(FakeAssignmentType.school);
    for (final element in [
      fakeChemistryTest,
      fakeBringCalculator,
      fakeBudgetTest,
    ]) {
      add(
        element,
        calendars: {
          for (final group in element.groups) 'group/${group.id}',
          for (final user in element.organisers) 'user/${user.id}',
          for (final room in element.rooms) room.planner,
        }.toList(),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// The Lesfiches module of dartschool's capture
// ---------------------------------------------------------------------------

/// The three lesfiches of dartschool's trimmed capture of the live
/// Lesfiches list (#88), owned by the fake's own account: a hidden lesson
/// lesfiche with the school's labels `JAAR 6` and `TRIMESTER 1` and no info.
final fakeLesficheLussen = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000001',
  name: 'Herhaling: lussen',
  isVisible: false,
  lastChanged: '2026-09-07 19:51:25',
  courses: [fakeInformatica],
  labels: ['JAAR 6', 'TRIMESTER 1'],
);

/// A visible assignment lesfiche (`KT Kleine Taak`) with public info and an
/// own label.
final fakeLesficheGame = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000002',
  name: 'Taak: een eigen spel',
  type: 'assignments',
  icon: 'flags_red_yellow',
  publicInfo: '<p>Dien je taak in via de digitale klas.</p>',
  lastChanged: '2025-09-05 11:30:28',
  courses: [fakeInformatica],
  ownLabels: ['Lussen'],
  assignmentType: FakeAssignmentType.kt,
);

/// A visible lesson lesfiche of two courses, without labels, with public
/// info and a (made-up) attachment.
final fakeLesficheFuncties = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000003',
  name: 'Functies',
  publicInfo: '<p>Hoofdstuk 4</p>',
  courses: [fakeInformatica, _chemie],
  attachments: ['hoofdstuk4.pdf'],
);

/// The Lesfiches module of the capture, served by
/// [FakePlannerLesficheCaptures.loadLesfiches].
extension FakePlannerLesficheCaptures on FakePlanner {
  /// Serves dartschool's capture of the Lesfiches list: [fakeLesficheLussen],
  /// [fakeLesficheGame] and [fakeLesficheFuncties], in that order.
  void loadLesfiches() => lesfiches.addAll([
    fakeLesficheLussen,
    fakeLesficheGame,
    fakeLesficheFuncties,
  ]);
}
