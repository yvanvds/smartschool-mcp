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
// Not read: the plan's evaluation, its report and the earlier versions of
// its items, which the library does not read yet (yvanvds/dartschool#170).
// Nor which courses are the user's own: the library does not tell
// (yvanvds/dartschool#189), so the items come in the LVS's order, and
// `course` keeps those of one course.
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
typedef LvsSupportPlanRead = ({
  List<LvsPlanPeriod> periods,
  LvsPlanPeriod? period,
  LvsSupportPlan? plan,
  LvsProfileSketch? sketch,
  bool fileHasSupportPlans,
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
/// Throws a [ToolError] when [period] names no period of the menu, or more
/// than one; the LVS's errors as the library throws them.
Future<LvsSupportPlanRead> readLvsSupportPlan(
  LvsService lvs, {
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
  if (plan.status != LvsSupportPlanStatus.plan && !sketch.hasSketch) {
    await readFile();
  }
  return (
    periods: periods,
    period: chosen,
    plan: plan,
    sketch: sketch,
    fileHasSupportPlans: fileHasSupportPlans ?? true,
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

/// The `course` argument: (part of) a course's name ([lvsIdOrNameArgument];
/// the plan names its courses, without ids).
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

/// The items of a plan that a `course` keeps ([selectLvsPlanItems]).
typedef LvsPlanSelection = ({
  /// The items shown, in the LVS's order.
  List<LvsPlanItem> shown,

  /// The course names of the plan that the course matched; empty for no
  /// course, or when it matched none.
  List<String> matched,

  /// How many items name only other courses, left out.
  int otherCourses,
});

/// The items of [items] for the course [course] (all when it is `null`):
/// those that name it, among their courses ([LvsPlanItem.courses]) or the
/// planning of their goals ([LvsPlanGoal.planning]), by name (ignoring case
/// and runs of white space), or else those that name a course whose name
/// holds it ([lvsNamed]); and those that name no course at all, which may
/// concern every course (an uploaded plan, an item of a kind the library
/// does not know). A filter: several courses may match.
LvsPlanSelection selectLvsPlanItems(List<LvsPlanItem> items, String? course) {
  if (course == null) return (shown: items, matched: const [], otherCourses: 0);
  final matched = lvsNamed(_planCourseNames(items), course, (name) => name);
  final keys = {for (final name in matched) lvsNameKey(name)};
  final shown = <LvsPlanItem>[];
  var otherCourses = 0;
  for (final item in items) {
    final named = _courseNames(item);
    if (named.isEmpty || named.any((name) => keys.contains(lvsNameKey(name)))) {
      shown.add(item);
    } else {
      otherCourses++;
    }
  }
  return (shown: shown, matched: matched, otherCourses: otherCourses);
}

/// The courses the items of [items] name ([_courseNames]), each once, in
/// their order.
List<String> _planCourseNames(List<LvsPlanItem> items) =>
    {for (final item in items) ..._courseNames(item)}.toList();

/// The courses [item] names, on one line each, without empty ones: its
/// courses, and the planning of its goals (a course, or another moment).
List<String> _courseNames(LvsPlanItem item) => [
  for (final name in [
    ...item.courses,
    for (final goal in item.goals) ...goal.planning,
  ])
    if (_oneLine(name).isNotEmpty) _oneLine(name),
];

/// What `read_lvs_support_plan` answers for [read], of the pupil [pupilId]
/// in class [classId], with the items for [course] only when it is given
/// ([selectLvsPlanItems]):
///
/// - a file without a part of support plans: a sentence that points to the
///   note categories (`read_lvs_notes`);
/// - no period of support plans ([LvsSupportPlanStatus.noPeriod]), or no
///   plan in the period ([LvsSupportPlanStatus.noPlan]): a sentence each;
/// - a plan: a line on whose plan, of which period, and how many items; for
///   a course, which items are shown; that the evaluation is not read; then
///   the items in the LVS's order ([formatLvsPlanItem]);
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
      LvsSupportPlanStatus.plan => _planLines(plan, period, pupil, course),
    },
    if (sketch != null &&
        (sketch.hasSketch || plan.status != LvsSupportPlanStatus.noPeriod))
      formatLvsProfileSketch(sketch),
    _periodsLine(read.periods),
  ].join('\n');
}

/// The lines of a [plan] that holds items, of [period] (in words), with the
/// items for [course] only when it is given.
List<String> _planLines(
  LvsSupportPlan plan,
  String period,
  String pupil,
  String? course,
) {
  final items = plan.items;
  final (:shown, :matched, :otherCourses) = selectLvsPlanItems(items, course);
  return [
    'The support plan (handelingsplan) of $pupil in the LVS, $period: '
        '${_count(items.length, 'item')}, in the LVS\'s order.',
    if (course != null)
      if (matched.isEmpty)
        // Then only the items that name no course are shown.
        'No item of this plan names a course "$course"'
            '${_namedCourses(items)}. '
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
    for (final item in shown) formatLvsPlanItem(item),
  ];
}

/// `; its items name: Testvak, Testvak 2` for [items] that name courses;
/// empty when none does.
String _namedCourses(List<LvsPlanItem> items) {
  final names = _planCourseNames(items);
  return names.isEmpty ? '' : '; its items name: ${names.join(', ')}';
}

/// One item of a plan as `read_lvs_support_plan` shows it: a line with its
/// kind, author, date, and what it is for, then what it holds, indented, a
/// line per field that holds something (`label: value`, a list or a text of
/// more lines under its label). An uploaded plan by its file name only
/// (nothing is downloaded); an item of a kind the library does not know by
/// its type, said so.
///
/// ```text
/// - Support needs and approach | by Piet Peeters | 14/10/2030 | for Testvak
///   Support needs (ondersteuningsnoden): Testondersteuningsnood
///   Approach (aanpak): Testaanpak
/// ```
String formatLvsPlanItem(LvsPlanItem item) {
  final courses = _courseNamesOf(item.courses);
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
    if (_oneLine(item.author) case final author when author.isNotEmpty)
      'by $author',
    if (_oneLine(item.date) case final date when date.isNotEmpty) date,
    if (item.kind == LvsPlanItemKind.needs)
      courses.isEmpty ? 'tied to no course' : 'for ${courses.join(', ')}',
    if (item.kind == LvsPlanItemKind.goals) ...[
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

/// [names] on one line each, without empty ones.
List<String> _courseNamesOf(List<String> names) => [
  for (final name in names)
    if (_oneLine(name).isNotEmpty) _oneLine(name),
];

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
