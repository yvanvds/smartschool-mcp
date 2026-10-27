import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';
import 'lvs_access.dart';

// The support plan of a pupil's file in the LVS, for `read_lvs_support_plan`
// (#156): the individual plan ("IHP", "individueel handelingsplan") of a
// school that uses the LVS's support plans ("handelingsplannen"), with the
// pupil's support needs, goals and approach, and the profile sketch
// ("profielschets"), of one period. Read with the library's reads of the
// support plans (yvanvds/dartschool#163): the period menu, the plan and the
// sketch; chosen (period, course) and written here.
//
// The library keeps the ids the LVS's web client filters a plan's items by
// (yvanvds/dartschool#189). So the items the user wrote come first (#163),
// by their author's user id against the logged-in user's; and `course`
// keeps an item for a course by the course ids of the item and of its
// goals' planning. Which courses the user teaches the library does not read
// yet (yvanvds/dartschool#196): `course` is how the user names theirs.
//
// Not read: the plan's evaluation, its report and the earlier versions of
// its items, which the library does not read yet (yvanvds/dartschool#170).
//
// No real pupil's plan was captured (yvanvds/dartschool#168): the shapes are
// those of the LVS's JavaScript. So the answer is tolerant: an item of a kind
// the library does not know is shown as such, empty fields are left out.
//
// What a plan holds goes to Claude only: never to the log, never to disk
// (lvs_access.dart).

/// The part of the file `read_lvs_support_plan` reads, for the sentence of a
/// refusal with HTTP 403 ([withLvs]).
const lvsSupportPlanPart = 'the support plans (handelingsplannen)';

/// What `read_lvs_support_plan` read: the [periods] of the support plans,
/// the one asked for ([period]; `null` for the current one), the [plan] and
/// the profile [sketch] of that period, and whether the pupil's file has a
/// part of support plans ([fileHasSupportPlans]; known only when the file
/// was read, see [readLvsSupportPlan], else `true`). [plan] and [sketch]
/// are `null` when they were not read, as the file has no such part.
/// [userId] is the logged-in user's Smartschool user id, read for a plan
/// that holds items, to tell the items the user wrote; else `null`.
typedef LvsSupportPlanRead = ({
  List<LvsPlanPeriod> periods,
  LvsPlanPeriod? period,
  LvsSupportPlan? plan,
  LvsProfileSketch? sketch,
  bool fileHasSupportPlans,
  int? userId,
});

/// Reads the support plan of the pupil [pupilId] in class [classId]: of the
/// period [period] names ([pickLvsPlanPeriod]; the current one when
/// `null`).
///
/// The reads, as the web client opens the plan: the period menu
/// ([LvsService.getSupportPlanPeriods]), the plan
/// ([LvsService.getSupportPlan]) and the profile sketch
/// ([LvsService.getProfileSketch]) of the period.
///
/// What the LVS answers a pupil it does not know, or a school without
/// support plans, was not captured (yvanvds/dartschool#168): for a made-up
/// pupil in a made-up class it gave no period menu and a period error. So
/// the pupil's file is read too ([LvsService.getPupilFile]) when the plan
/// holds no item and there is no sketch, or before saying that there is no
/// period to pick from: it tells an unknown pupil apart (a
/// [SmartschoolLvsPupilNotFoundError]), and a file without a part of
/// support plans ([LvsPupilFile.supportPlanSections]), as at a school that
/// does not use them, from a pupil without a plan. That read leaves today's
/// attendance out (`withTodayStatus: false`).
///
/// For a plan that holds items, the logged-in user's id too
/// ([LvsReads.userId]; no request to the LVS), which the items name their
/// author by.
///
/// Throws a [ToolError] when [period] names no period of the menu, or more
/// than one; the LVS's errors as the library throws them.
Future<LvsSupportPlanRead> readLvsSupportPlan(
  LvsReads lvs, {
  required int pupilId,
  required int classId,
  required String? period,
}) async {
  bool? fileHasSupportPlans;
  Future<bool> readFile() async =>
      fileHasSupportPlans ??= (await lvs.getPupilFile(
        pupilId: pupilId,
        classId: classId,
        withTodayStatus: false,
      )).supportPlanSections.isNotEmpty;

  final periods = await lvs.getSupportPlanPeriods(
    pupilId: pupilId,
    classId: classId,
  );
  LvsPlanPeriod? chosen;
  if (period != null) {
    if (periods.isEmpty && !await readFile()) {
      return (
        periods: periods,
        period: null,
        plan: null,
        sketch: null,
        fileHasSupportPlans: false,
        userId: null,
      );
    }
    chosen = pickLvsPlanPeriod(periods, period);
  }
  final plan = await lvs.getSupportPlan(
    pupilId: pupilId,
    classId: classId,
    periodId: chosen?.id,
  );
  final sketch = await lvs.getProfileSketch(
    pupilId: pupilId,
    classId: classId,
    periodId: chosen?.id,
  );
  final hasItems = plan.status == LvsSupportPlanStatus.plan;
  if (!hasItems && !sketch.hasSketch) await readFile();
  return (
    periods: periods,
    period: chosen,
    plan: plan,
    sketch: sketch,
    fileHasSupportPlans: fileHasSupportPlans ?? true,
    userId: hasItems ? await lvs.userId() : null,
  );
}

/// The `period` argument: a period's id or name ([lvsIdOrNameArgument]).
String? lvsPlanPeriodArgument(Map<String, Object?> arguments) =>
    lvsIdOrNameArgument(
      arguments,
      'period',
      what:
          'a period_id or the name of a period, as read_lvs_support_plan '
          'lists them',
    );

/// The `course` argument: (part of) a course's name ([lvsIdOrNameArgument]).
/// Not an id: the answer prints none, and whether the LVS's course ids are
/// those of `read_lvs_results` is not known (yvanvds/dartschool#196).
String? lvsPlanCourseArgument(Map<String, Object?> arguments) =>
    lvsIdOrNameArgument(
      arguments,
      'course',
      what: 'the name of a course, or part of it',
    );

/// The period of [periods] (the menu of the support plans) that [which]
/// names: the one with that `period_id` (digits, or `period_id <digits>`),
/// or the one with that name (ignoring case and runs of white space), or
/// else the one whose name holds it.
///
/// Throws a [ToolError] that lists the periods when [which] names none of
/// them (or the LVS lists none), and the matching ones, with their ids,
/// when it names several.
LvsPlanPeriod pickLvsPlanPeriod(List<LvsPlanPeriod> periods, String which) {
  if (periods.isEmpty) {
    throw ToolError(
      "The LVS lists no periods of this pupil's support plans to choose "
      'from. Leave period out for the current period.',
    );
  }
  if (lvsIdIn(which, 'period_id') case final id?) {
    for (final period in periods) {
      if (period.id == id) return period;
    }
  }
  final named = lvsNamed(periods, which, (period) => period.name);
  if (named.length == 1) return named.single;
  if (named.length > 1) {
    throw ToolError(
      'Several periods of the support plans match "$which": '
      '${_periodList(named)}. Pass the one you mean as period, by its '
      'period_id.',
    );
  }
  throw ToolError(
    'The support plans have no period "$which". Their periods are: '
    '${_periodList(periods)}. Pass one of them as period, by its period_id '
    'or its name, or leave period out for the current period.',
  );
}

/// The items of a plan that `read_lvs_support_plan` shows
/// ([selectLvsPlanItems]).
typedef LvsPlanSelection = ({
  /// The items shown: those the user wrote first, then the others, each in
  /// the LVS's order.
  List<LvsPlanItem> shown,

  /// The course names of the plan that the course matched; empty for no
  /// course, or when it matched none.
  List<String> matched,

  /// How many items are for other courses only, left out.
  int otherCourses,
});

/// The items of [plan] for the course [course] (all when it is `null`),
/// those the user [userId] wrote first ([lvsPlanItemByUser]).
///
/// A course is named by name (ignoring case and runs of white space), or
/// else by part of its name ([lvsNamed]): the plan's courses
/// ([LvsSupportPlan.courses]) and those its items name. It keeps the items
/// planned in it, by its id ([LvsPlanItem.courseIds], and the courses of
/// their goals' planning, [LvsPlanMoment.id]) as the LVS's web client
/// filters them, or by its name among their courses ([LvsPlanItem.courses])
/// or their goals' planning ([LvsPlanGoal.planning]); and those tied to no
/// course at all, which may concern every course (an uploaded plan, an item
/// of a kind the library does not know). A filter: several courses may
/// match.
LvsPlanSelection selectLvsPlanItems(
  LvsSupportPlan plan,
  String? course, {
  required int? userId,
}) {
  final items = plan.items;
  List<LvsPlanItem> byUserFirst(List<LvsPlanItem> items) => [
    for (final item in items)
      if (lvsPlanItemByUser(item, userId)) item,
    for (final item in items)
      if (!lvsPlanItemByUser(item, userId)) item,
  ];
  if (course == null) {
    return (shown: byUserFirst(items), matched: const [], otherCourses: 0);
  }
  final byId = _courseNamesById(plan);
  final matched = lvsNamed(
    _distinct([...byId.values, ..._planCourseNames(items, byId)]),
    course,
    (name) => name,
  );
  final keys = {for (final name in matched) lvsNameKey(name)};
  final ids = {
    for (final MapEntry(:key, :value) in byId.entries)
      if (keys.contains(lvsNameKey(value))) key,
  };
  final shown = <LvsPlanItem>[];
  var otherCourses = 0;
  for (final item in items) {
    final itemIds = _courseIds(item);
    final named = _courseNames(item, byId);
    if ((itemIds.isEmpty && named.isEmpty) ||
        itemIds.any(ids.contains) ||
        named.any((name) => keys.contains(lvsNameKey(name)))) {
      shown.add(item);
    } else {
      otherCourses++;
    }
  }
  return (
    shown: byUserFirst(shown),
    matched: matched,
    otherCourses: otherCourses,
  );
}

/// Whether the user [userId] wrote [item]: its author's user id
/// ([LvsPlanItem.authorId]) is theirs, as the LVS's web client keeps the
/// items of a teacher (yvanvds/dartschool#189). Never for an unknown user.
bool lvsPlanItemByUser(LvsPlanItem item, int? userId) =>
    userId != null && item.authorId == userId;

/// The names of the courses of [plan] by their ids: the plan's courses
/// ([LvsSupportPlan.courses]), and the courses of its goals' planning
/// ([LvsPlanMoment]) whose ids those do not name.
Map<int, String> _courseNamesById(LvsSupportPlan plan) {
  final names = {
    for (final course in plan.courses)
      if (_oneLine(course.name) case final name when name.isNotEmpty)
        course.id: name,
  };
  for (final item in plan.items) {
    for (final goal in item.goals) {
      for (final moment in goal.moments) {
        if (moment case LvsPlanMoment(
          isCourse: true,
          :final id?,
        ) when _oneLine(moment.name).isNotEmpty) {
          names.putIfAbsent(id, () => _oneLine(moment.name));
        }
      }
    }
  }
  return names;
}

/// The ids of the courses [item] is planned in: its own
/// ([LvsPlanItem.courseIds]) and those of its goals' planning.
Set<int> _courseIds(LvsPlanItem item) => {
  ...item.courseIds,
  for (final goal in item.goals)
    for (final moment in goal.moments)
      if (moment case LvsPlanMoment(isCourse: true, :final id?)) id,
};

/// The courses the items of [items] name ([_courseNames]), each once, in
/// their order.
List<String> _planCourseNames(List<LvsPlanItem> items, Map<int, String> byId) =>
    _distinct([for (final item in items) ..._courseNames(item, byId)]);

/// The courses [item] names, on one line each, without empty ones: its
/// courses, the planning of its goals (a course, or another moment), and
/// the courses of its course ids that [byId] names.
List<String> _courseNames(LvsPlanItem item, Map<int, String> byId) => [
  for (final name in [
    ...item.courses,
    for (final goal in item.goals) ...goal.planning,
    for (final id in _courseIds(item)) ?byId[id],
  ])
    if (_oneLine(name).isNotEmpty) _oneLine(name),
];

/// [names] without the ones named before ([lvsNameKey]), in their order.
List<String> _distinct(List<String> names) {
  final seen = <String>{};
  return [
    for (final name in names)
      if (seen.add(lvsNameKey(name))) name,
  ];
}

/// What `read_lvs_support_plan` answers for [read], of the pupil [pupilId]
/// in class [classId], with the items for [course] only when it is given
/// ([selectLvsPlanItems]):
///
/// - a file without a part of support plans: a sentence that points to the
///   note categories (`read_lvs_notes`);
/// - no period of support plans ([LvsSupportPlanStatus.noPeriod]), or no
///   plan in the period ([LvsSupportPlanStatus.noPlan]): a sentence each;
/// - a plan: a line on whose plan, of which period, how many items, and
///   how many of them the user wrote, which come first; for a course, which
///   items are shown; that the evaluation is not read; then the items, those
///   the user wrote first, each in the LVS's order ([formatLvsPlanItem]);
///
/// then the profile sketch ([formatLvsProfileSketch]; for no period only
/// when there is one) and the periods to ask for.
String formatLvsSupportPlan(
  LvsSupportPlanRead read, {
  required int pupilId,
  required int classId,
  required String? course,
}) {
  final pupil = 'the pupil with pupil_id $pupilId (class_id $classId)';
  final plan = read.plan;
  if (!read.fileHasSupportPlans || plan == null) {
    return "The file of $pupil in the LVS has no part of support plans "
        '(handelingsplannen): the school does not use the LVS\'s support '
        'plans, or this account may not see them. A school without them '
        'keeps educational needs (onderwijsbehoeften) and measures in its '
        'note categories instead: read_lvs_pupil lists the categories of the '
        'file, and read_lvs_notes reads them.';
  }
  final sketch = read.sketch;
  final period = _periodScope(plan.period, read.period, read.periods);
  final message = _oneLine(plan.period.message);
  return [
    ...switch (plan.status) {
      LvsSupportPlanStatus.noPeriod => [
        'The LVS gives no period of support plans for $pupil'
            '${read.period == null ? '' : ' in $period'}: their class may '
            'have no structure of support plans'
            '${message.isEmpty ? '' : ' (the LVS says: "$message")'}. There '
            'is no plan to read.',
      ],
      LvsSupportPlanStatus.noPlan => [
        '${_capitalized(pupil)} has no support plan (handelingsplan) in the '
            'LVS in $period.',
      ],
      LvsSupportPlanStatus.plan => _planLines(
        plan,
        period,
        pupil,
        course,
        read.userId,
      ),
    },
    if (sketch != null &&
        (sketch.hasSketch || plan.status != LvsSupportPlanStatus.noPeriod))
      formatLvsProfileSketch(sketch),
    _periodsLine(read.periods),
  ].join('\n');
}

/// The lines of a [plan] that holds items, of [period] (in words), with the
/// items for [course] only when it is given, and those the user [userId]
/// wrote first.
List<String> _planLines(
  LvsSupportPlan plan,
  String period,
  String pupil,
  String? course,
  int? userId,
) {
  final items = plan.items;
  final byId = _courseNamesById(plan);
  final (:shown, :matched, :otherCourses) = selectLvsPlanItems(
    plan,
    course,
    userId: userId,
  );
  final byUser = items.where((item) => lvsPlanItemByUser(item, userId));
  final order = switch (byUser.length) {
    _ when userId == null => ", in the LVS's order",
    0 => ", in the LVS's order; the user wrote none of them",
    final count when count == items.length =>
      ", in the LVS's order; the user wrote "
          '${count == 1 ? 'it' : 'all of them'}',
    final count =>
      ': first the ${count == 1 ? 'item' : '$count items'} the user wrote, '
          'marked "by the user", then the others, each in the LVS\'s order',
  };
  return [
    'The support plan (handelingsplan) of $pupil in the LVS, $period: '
        '${_count(items.length, 'item')}$order.',
    if (course != null)
      if (matched.isEmpty)
        // Then only the items that name no course are shown.
        'No item of this plan names a course "$course"'
            '${_namedCourses(items, byId)}. '
            '${shown.isEmpty ? 'Nothing is shown' : 'Shown: only the ${_count(shown.length, 'item')} tied to no course, which may concern every course'}; '
            'leave course out to see all ${items.length}.'
      else
        'Only the items for ${matched.length == 1 ? 'the course' : 'the '
                      'courses'} ${matched.join(', ')}, and those tied to no '
            'course, which may concern every course: ${shown.length} of the '
            '${items.length}.'
            '${otherCourses == 0 ? '' : ' Not shown: ${_count(otherCourses, 'item')} for other courses only; leave course out to see ${otherCourses == 1 ? 'it' : 'them'}.'}',
    "Not read: the plan's evaluation and its report, and the earlier "
        'versions of its items; the server cannot read them yet.',
    for (final item in shown)
      formatLvsPlanItem(
        item,
        byUser: lvsPlanItemByUser(item, userId),
        courseNames: byId,
      ),
  ];
}

/// `; its items name: Testvak, Testvak 2` for [items] that name courses
/// (with [byId], the plan's names of course ids); empty when none does.
String _namedCourses(List<LvsPlanItem> items, Map<int, String> byId) {
  final names = _planCourseNames(items, byId);
  return names.isEmpty ? '' : '; its items name: ${names.join(', ')}';
}

/// One item of a plan as `read_lvs_support_plan` shows it: a line with its
/// kind, author (`by the user` first when [byUser]), date, and what it is
/// for, then what it holds, indented, a line per field that holds something
/// (`label: value`, a list or a text of more lines under its label). An
/// uploaded plan by its file name only (nothing is downloaded); an item of a
/// kind the library does not know by its type, said so.
///
/// What it is for: the courses the LVS names for it, and those of its
/// course ids that [courseNames] (the plan's, by id) names; an item of
/// support needs without any is tied to no course.
///
/// ```text
/// - Support needs and approach | by Piet Peeters | 14/10/2030 | for Testvak
///   Support needs (ondersteuningsnoden): Testondersteuningsnood
///   Approach (aanpak): Testaanpak
/// ```
String formatLvsPlanItem(
  LvsPlanItem item, {
  bool byUser = false,
  Map<int, String> courseNames = const {},
}) {
  final courses = _forCourses(item, courseNames);
  final author = _oneLine(item.author);
  final head = <String>[
    switch (item.kind) {
      LvsPlanItemKind.needs => 'Support needs and approach',
      LvsPlanItemKind.goals =>
        item.fromGroupPlan
            ? "Goals taken over from the class's group plan (groepswerkplan)"
            : 'Goals chosen for the pupil',
      LvsPlanItemKind.document => 'An uploaded plan',
      LvsPlanItemKind.unknown =>
        'An item of a type the server does not know ("${_oneLine(item.type)}")',
    },
    if (byUser)
      author.isEmpty ? 'by the user' : 'by the user, $author'
    else if (author.isNotEmpty)
      'by $author',
    if (_oneLine(item.date) case final date when date.isNotEmpty) date,
    if (item.kind == LvsPlanItemKind.needs)
      courses.isEmpty ? 'tied to no course' : 'for ${courses.join(', ')}',
    if (item.kind == LvsPlanItemKind.goals) ...[
      if (courses.isNotEmpty) 'for ${courses.join(', ')}',
      if (_oneLine(item.theme) case final theme when theme.isNotEmpty)
        'theme $theme',
      ?_goalsKind(item.versionType),
    ],
    if (item.kind == LvsPlanItemKind.document)
      '${_label(item.fileName, empty: '(no file name)')}'
          '${_oneLine(item.mimeType).isEmpty ? '' : ' (${_oneLine(item.mimeType)})'}'
          ', by name only: not opened',
    if (item.kind == LvsPlanItemKind.unknown) 'its content is not read',
  ];
  final body = switch (item.kind) {
    LvsPlanItemKind.needs => [
      ..._listLines('Support needs (ondersteuningsnoden)', item.supportNeeds),
      ..._listLines('Main goals (hoofddoelen)', item.mainGoals),
      ..._listLines('Work goals (werkdoelen)', item.workGoals),
      ..._listLines('Approach (aanpak)', item.approach),
      ..._textLines('Comment on the approach', item.approachComment),
    ],
    LvsPlanItemKind.goals => [
      ..._textLines('Start situation (beginsituatie)', item.startSituation),
      for (final goal in item.goals) ..._goalLines(goal),
    ],
    LvsPlanItemKind.document || LvsPlanItemKind.unknown => const <String>[],
  };
  // An uploaded plan and an item of an unknown kind are their line only.
  final lineOnly =
      item.kind == LvsPlanItemKind.document ||
      item.kind == LvsPlanItemKind.unknown;
  return [
    '- ${head.join(' | ')}',
    ...body,
    if (body.isEmpty && !lineOnly) '  (nothing filled in)',
  ].join('\n');
}

/// The lines of [goal] in an item of goals: a line with its name, its
/// domain and whether it is no longer in its curriculum, then its
/// objectives, approach and planning.
List<String> _goalLines(LvsPlanGoal goal) {
  final domain = _oneLine(goal.domain);
  final head = [
    'Goal: ${_label(goal.name)}',
    if (domain.isNotEmpty) 'domain $domain',
    if (goal.isDeprecated) 'no longer in its curriculum',
  ];
  return [
    '  - ${head.join(' | ')}',
    ..._listLines('Objectives (doelstellingen)', goal.objectives, indent: 4),
    ..._listLines('Approach (aanpak)', goal.approach, indent: 4),
    ..._listLines('Planning', goal.planning, indent: 4),
  ];
}

/// What goals the kind [versionType] of an item's goals stands for, in
/// words; `null` for the usual goals (`normal`) or none.
String? _goalsKind(String versionType) => switch (_oneLine(versionType)) {
  '' || 'normal' => null,
  'eigendb' => "the school's own goals",
  'bubao' => 'goals of special primary education (BuBaO)',
  final other => 'goals of kind "$other"',
};

/// The courses [item] is for, on one line each, for its first line: the
/// courses the LVS names for it ([LvsPlanItem.courses]), then those of its
/// course ids ([LvsPlanItem.courseIds]) that [byId] names and that are not
/// among them. Without names, its course ids that [byId] does not name are
/// counted (`1 course the plan does not name`); with names, those are taken
/// for the courses named.
List<String> _forCourses(LvsPlanItem item, Map<int, String> byId) {
  final names = _distinct([
    for (final name in [
      ...item.courses,
      for (final id in item.courseIds) ?byId[id],
    ])
      if (_oneLine(name).isNotEmpty) _oneLine(name),
  ]);
  final unnamed = item.courseIds.where((id) => byId[id] == null).length;
  if (names.isNotEmpty || unnamed == 0) return names;
  return ['${_count(unnamed, 'course')} the plan does not name'];
}

/// The lines of a list [entries] under [label], at [indent]: `label: entry`
/// for one entry of one line; else the label, then each entry as `- line`,
/// with the further lines of an entry under it. Nothing for no entry (empty
/// entries left out).
List<String> _listLines(String label, List<String> entries, {int indent = 2}) {
  final pad = ' ' * indent;
  final lists = [
    for (final entry in entries)
      if (_lines(entry) case final lines when lines.isNotEmpty) lines,
  ];
  if (lists.isEmpty) return const [];
  if (lists case [[final line]]) return ['$pad$label: $line'];
  return [
    '$pad$label:',
    for (final lines in lists) ...[
      '$pad  - ${lines.first}',
      for (final line in lines.skip(1)) '$pad    $line',
    ],
  ];
}

/// `label: value` at an indent of two, or the label with each line of a
/// value of more lines under it; nothing for an empty value.
List<String> _textLines(String label, String value) {
  final lines = _lines(value);
  if (lines.isEmpty) return const [];
  if (lines.length == 1) return ['  $label: ${lines.single}'];
  return ['  $label:', for (final line in lines) '    $line'];
}

/// The lines of [text], the library's plain text (a line for each line
/// break and block), trimmed, without empty ones.
List<String> _lines(String text) => [
  for (final line in text.split('\n'))
    if (_oneLine(line).isNotEmpty) _oneLine(line),
];

/// The profile sketch as `read_lvs_support_plan` shows it: its text, a line
/// for each of its lines, indented, with its last change as the LVS shows
/// it; or that there is none.
///
/// ```text
/// Profile sketch (profielschets; last change: Testversie van 01/10/2030):
///   Testprofielschets van de leerling: sterk in testen.
/// ```
String formatLvsProfileSketch(LvsProfileSketch sketch) {
  if (!sketch.hasSketch) {
    return 'Profile sketch (profielschets): none in this period.';
  }
  final revision = _oneLine(sketch.lastRevision);
  final lines = _lines(sketch.text);
  return [
    'Profile sketch (profielschets'
        '${revision.isEmpty ? '' : '; last change: $revision'})'
        '${lines.isEmpty ? ': there, but empty.' : ':'}',
    for (final line in lines) '  $line',
  ].join('\n');
}

/// Which period a read is of, in words: the one asked for ([chosen]), or
/// the current one, named by the menu ([periods]) when it lists the period
/// the LVS answered with, else as the LVS describes it; closed when the LVS
/// says so.
String _periodScope(
  LvsPlanPeriodInfo info,
  LvsPlanPeriod? chosen,
  List<LvsPlanPeriod> periods,
) {
  final listed = chosen ?? periods.where((p) => p.id == info.id).firstOrNull;
  final message = _oneLine(info.message);
  final String named;
  if (listed != null) {
    named = _periodLabel(listed);
  } else if (info.hasError) {
    named = '';
  } else {
    named = [
      if (message.isNotEmpty) message,
      if (info.id case final id?) '(period_id $id)',
    ].join(' ');
  }
  final closed = info.isOpen == false && !info.hasError
      ? ', closed (read only in Smartschool)'
      : '';
  final which = chosen == null ? 'the current period' : 'the period';
  return named.isEmpty ? '$which$closed' : '$which $named$closed';
}

/// The line that lists the periods of the support plans, to ask for.
String _periodsLine(List<LvsPlanPeriod> periods) => periods.isEmpty
    ? 'The LVS lists no periods of the support plans to choose from.'
    : 'Periods of the support plans, to pass as period (its period_id or '
          'name): ${_periodList(periods)}.';

/// [period] with its id and its heading in the menu: `Testperiode
/// (period_id 900501, in Testschooljaar)`.
String _periodLabel(LvsPlanPeriod period) {
  final heading = _oneLine(period.heading);
  return '${_label(period.name)} (period_id ${period.id}'
      '${heading.isEmpty ? '' : ', in $heading'})';
}

/// [periods] as the answer and its errors list them.
String _periodList(List<LvsPlanPeriod> periods) =>
    [for (final period in periods) _periodLabel(period)].join(', ');

/// [count] [noun]s: `1 item`, `2 items`.
String _count(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';

/// [text] with its first letter in upper case.
String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// [text] on one line: each run of white space one space, trimmed.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [text] on one line, or [empty] when it is empty.
String _label(String text, {String empty = '(no name)'}) {
  final line = _oneLine(text);
  return line.isEmpty ? empty : line;
}
