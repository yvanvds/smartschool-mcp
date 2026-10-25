import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../messages/html_to_text.dart';
import '../tools/server_tool.dart';
import 'lvs_access.dart';
import 'lvs_format.dart';

// The results of a pupil's file in the LVS, for `read_lvs_results` (#155):
// the "Resultaten" part of the file, the results app pupils and parents
// see, in every course (not only the user's own gradebooks). Read with the
// library's reads of the results app (yvanvds/dartschool#162): the periods,
// courses, evaluations, feedback and reports of one school year; chosen
// (period, course) and written here, with a summary per course computed
// from the scores given (the library computes nothing).
//
// Not read: the report comments of /LVS/Skorecomments, and the older Skore
// part some schools' files still show instead of Resultaten; the library
// reads neither (yvanvds/dartschool#169).
//
// What these results hold goes to Claude only: never to the log, never to
// disk (lvs_access.dart).

/// How many evaluations `read_lvs_results` asks for per page.
const lvsEvaluationsPerPage = 100;

/// The most pages of evaluations `read_lvs_results` reads in one call: with
/// [lvsEvaluationsPerPage], 1000 evaluations. The answer says when there are
/// more ([LvsEvaluationList.isComplete]).
const lvsEvaluationsMaxPages = 10;

/// From how many evaluations a course gets a summary line
/// ([formatLvsResultsSummary]).
const lvsResultsSummaryFrom = 5;

/// The part of the file `read_lvs_results` reads, for the sentence of a
/// refusal with HTTP 403 ([withLvs]): "no access to results".
const lvsResultsPart = 'the results (Resultaten)';

/// How the periods of a read of the results were chosen.
enum LvsPeriodScope {
  /// The active periods ([LvsResultsPeriod.isActive]), by default.
  active,

  /// All periods, by default, as none is marked active (or the LVS lists
  /// none).
  noneActive,

  /// All periods, as asked (`period` `all`).
  all,

  /// The one period asked for.
  chosen,
}

/// The periods a read of the results is of: [periods], chosen as [scope]
/// says; empty for all periods.
typedef LvsPeriodChoice = ({
  LvsPeriodScope scope,
  List<LvsResultsPeriod> periods,
});

/// What `read_lvs_results` read: all [periods] and [courses] of the school
/// year, those chosen ([periodChoice]; [chosenCourses], `null` for all
/// courses), the [evaluations] read for them, the [feedback] and the
/// [reports] of the school year, and whether the pupil's file shows the
/// older Skore part instead of Resultaten ([olderSkorePart], known only
/// when the file was read, see [readLvsResults]).
typedef LvsResultsRead = ({
  List<LvsResultsPeriod> periods,
  LvsPeriodChoice periodChoice,
  List<LvsResultsCourse> courses,
  List<LvsResultsCourse>? chosenCourses,
  LvsEvaluationList evaluations,
  List<LvsFeedback> feedback,
  List<LvsReport> reports,
  bool olderSkorePart,
});

/// Reads the results of the pupil [pupilId] in class [classId] in
/// [schoolYear]: of the periods [period] names ([pickLvsResultsPeriods]; the
/// active ones when `null`) and the courses [course] names
/// ([pickLvsResultsCourses]; all when `null`).
///
/// The reads of the results app, in its order: the configuration, for a
/// school year that is not the current one ([isCurrentSchoolYear]), as the
/// app lets an account see other school years only with `canSeeAll`; the
/// periods; the courses; the evaluations, page by page
/// ([LvsService.getAllEvaluations], with the ids of the periods and courses
/// chosen, as the app asks); the feedback; the reports.
///
/// The LVS answers a pupil it does not know with empty lists (seen live for
/// a made-up pupil, yvanvds/dartschool#162), so the pupil's file is read
/// too ([LvsService.getPupilFile]) when no evaluation, feedback or report
/// came, or before saying that the LVS lists no periods or courses to pick
/// from: it tells the two apart (a [SmartschoolLvsPupilNotFoundError]), and
/// whether the file shows the older Skore part instead of Resultaten. That
/// read takes today's attendance along, unused (yvanvds/dartschool#186,
/// tracked in #160).
///
/// Throws a [ToolError] when [period] or [course] names nothing of the
/// results, [period] more than one period, or the account may not see
/// [schoolYear]; the LVS's errors as the library throws them.
Future<LvsResultsRead> readLvsResults(
  LvsService lvs, {
  required int pupilId,
  required int classId,
  required LvsSchoolYear schoolYear,
  required bool isCurrentSchoolYear,
  required String? period,
  required String? course,
}) async {
  bool? olderSkorePart;
  Future<void> readFile() async {
    if (olderSkorePart != null) return;
    final file = await lvs.getPupilFile(pupilId: pupilId, classId: classId);
    final types = {for (final section in file.allSections) section.type};
    olderSkorePart =
        types.contains(LvsSectionType.skore) &&
        !types.contains(LvsSectionType.results);
  }

  if (!isCurrentSchoolYear) {
    final configuration = await lvs.getResultsConfiguration(
      pupilId: pupilId,
      classId: classId,
    );
    if (configuration.canSeeAll == false) {
      throw ToolError(
        'The results app lets this account see the results of the current '
        'school year only, not those of school year '
        '${formatLvsSchoolYear(schoolYear)}. Leave school_year out for the '
        'current school year.',
      );
    }
  }
  final periods = await lvs.getResultsPeriods(
    pupilId: pupilId,
    classId: classId,
    schoolYear: schoolYear,
  );
  if (periods.isEmpty && period != null && !_isAll(period)) await readFile();
  final periodChoice = pickLvsResultsPeriods(
    periods,
    period,
    schoolYear: schoolYear,
  );
  final courses = await lvs.getResultsCourses(
    pupilId: pupilId,
    classId: classId,
    schoolYear: schoolYear,
  );
  if (courses.isEmpty && course != null) await readFile();
  final chosenCourses = course == null
      ? null
      : pickLvsResultsCourses(courses, course, schoolYear: schoolYear);
  final evaluations = await lvs.getAllEvaluations(
    pupilId: pupilId,
    classId: classId,
    courseIds: [for (final each in chosenCourses ?? const []) each.id],
    periodIds: [for (final each in periodChoice.periods) each.id],
    itemsOnPage: lvsEvaluationsPerPage,
    maxPages: lvsEvaluationsMaxPages,
    schoolYear: schoolYear,
  );
  final feedback = await lvs.getFeedback(
    pupilId: pupilId,
    classId: classId,
    schoolYear: schoolYear,
  );
  final reports = await lvs.getReports(
    pupilId: pupilId,
    classId: classId,
    schoolYear: schoolYear,
  );
  if (evaluations.evaluations.isEmpty && feedback.isEmpty && reports.isEmpty) {
    await readFile();
  }
  return (
    periods: periods,
    periodChoice: periodChoice,
    courses: courses,
    chosenCourses: chosenCourses,
    evaluations: evaluations,
    feedback: feedback,
    reports: reports,
    olderSkorePart: olderSkorePart ?? false,
  );
}

/// Whether [which], a `period`, asks for all periods.
bool _isAll(String which) => lvsNameKey(which) == 'all';

/// The `period` argument: a period's id or name, or `all`
/// ([lvsIdOrNameArgument]).
String? lvsResultsPeriodArgument(Map<String, Object?> arguments) =>
    lvsIdOrNameArgument(
      arguments,
      'period',
      what:
          'a period_id or the name of a period, as read_lvs_results lists '
          'them, or all',
    );

/// The `course` argument: a course's id or (part of) its name
/// ([lvsIdOrNameArgument]).
String? lvsResultsCourseArgument(Map<String, Object?> arguments) =>
    lvsIdOrNameArgument(
      arguments,
      'course',
      what: 'a course_id or (part of) the name of a course',
    );

/// The periods of [periods] (those of the results in [schoolYear]) that
/// [which] asks for: by default (`null`) the active ones, or all when none
/// is; all for `all`; else the one with that `period_id` (digits, or
/// `period_id <digits>`), or the one with that name (ignoring case and runs
/// of white space), or else the one whose name holds it.
///
/// Throws a [ToolError] that lists the periods when [which] names none of
/// them (or the LVS lists none), and the matching ones, with their ids, when
/// it names several.
LvsPeriodChoice pickLvsResultsPeriods(
  List<LvsResultsPeriod> periods,
  String? which, {
  required LvsSchoolYear schoolYear,
}) {
  if (which == null) {
    final active = [
      for (final period in periods)
        if (period.isActive) period,
    ];
    return active.isEmpty
        ? (scope: LvsPeriodScope.noneActive, periods: const [])
        : (scope: LvsPeriodScope.active, periods: active);
  }
  if (_isAll(which)) return (scope: LvsPeriodScope.all, periods: const []);
  final year = formatLvsSchoolYear(schoolYear);
  if (periods.isEmpty) {
    throw ToolError(
      "The LVS lists no periods of this pupil's results in school year "
      '$year. Leave period out.',
    );
  }
  if (lvsIdIn(which, 'period_id') case final id?) {
    for (final period in periods) {
      if (period.id == id) {
        return (scope: LvsPeriodScope.chosen, periods: [period]);
      }
    }
  }
  final named = _named(periods, which, (period) => period.name);
  if (named.length == 1) {
    return (scope: LvsPeriodScope.chosen, periods: named);
  }
  if (named.length > 1) {
    throw ToolError(
      "Several periods of this pupil's results in school year $year match "
      '"$which": ${_periodList(named)}. Pass the one you mean as period, by '
      'its period_id.',
    );
  }
  throw ToolError(
    "This pupil's results in school year $year have no period \"$which\". "
    'Their periods are: ${_periodList(periods)}. Pass one of them as period, '
    'by its period_id or its name, or all for every period; leave period '
    'out for the active period.',
  );
}

/// The courses of [courses] (those of the results in [schoolYear]) that
/// [which] names, with their parts (the courses whose `parentCourseId` is
/// one of them, at any depth), in the LVS's order: the one with that
/// `course_id` (digits, or `course_id <digits>`), or those with that name
/// (ignoring case and runs of white space), or else those whose name holds
/// it. A filter: several courses may match.
///
/// Throws a [ToolError] that lists the courses when [which] names none of
/// them, or the LVS lists none.
List<LvsResultsCourse> pickLvsResultsCourses(
  List<LvsResultsCourse> courses,
  String which, {
  required LvsSchoolYear schoolYear,
}) {
  final year = formatLvsSchoolYear(schoolYear);
  if (courses.isEmpty) {
    throw ToolError(
      "The LVS lists no courses of this pupil's results in school year "
      '$year. Leave course out.',
    );
  }
  final id = lvsIdIn(which, 'course_id');
  final byId = [
    for (final course in courses)
      if (course.id == id) course,
  ];
  final picked = byId.isNotEmpty
      ? byId
      : _named(courses, which, (course) => course.name);
  if (picked.isEmpty) {
    throw ToolError(
      "This pupil's results in school year $year have no course \"$which\". "
      'Their courses are: ${_courseList(courses)}. Pass one of them as '
      'course, by its course_id or (part of) its name, or leave course out '
      'for all courses.',
    );
  }
  final ids = {for (final course in picked) course.id};
  for (var added = true; added;) {
    added = false;
    for (final course in courses) {
      if (course.parentCourseId case final parent?
          when ids.contains(parent) && ids.add(course.id)) {
        added = true;
      }
    }
  }
  return [
    for (final course in courses)
      if (ids.contains(course.id)) course,
  ];
}

/// The items of [items] named [which] by [name] (ignoring case and runs of
/// white space), or, when none is, those whose name holds it.
List<T> _named<T>(List<T> items, String which, String Function(T) name) {
  final key = lvsNameKey(which);
  final exact = [
    for (final item in items)
      if (lvsNameKey(name(item)) == key) item,
  ];
  if (exact.isNotEmpty) return exact;
  return [
    for (final item in items)
      if (lvsNameKey(name(item)).contains(key)) item,
  ];
}

/// What `read_lvs_results` answers for [read]: a line on whose results, of
/// which school year, periods and courses; per course, a heading, a summary
/// line for many evaluations ([formatLvsResultsSummary]) and the
/// evaluations, newest first ([formatLvsEvaluation]); the courses without
/// evaluations; the feedback ([formatLvsFeedback]); the reports; and the
/// periods to ask for.
///
/// Evaluations and feedback on evaluations of other periods or courses than
/// those chosen are left out, also when the LVS sends them: whether it
/// applies the ids it is sent was not captured (yvanvds/dartschool#168).
String formatLvsResults(
  LvsResultsRead read, {
  required int pupilId,
  required int classId,
  required LvsSchoolYear schoolYear,
}) {
  final year = formatLvsSchoolYear(schoolYear);
  final byId = {for (final course in read.courses) course.id: course};
  final periodIds = {for (final period in read.periodChoice.periods) period.id};
  final courseIds = {
    for (final course in read.chosenCourses ?? const <LvsResultsCourse>[])
      course.id,
  };
  final evaluations = [
    for (final evaluation in read.evaluations.evaluations)
      if (_inPeriods(evaluation.period, periodIds) &&
          _inCourses(evaluation.courses, courseIds))
        evaluation,
  ];
  final scope =
      '${_periodScope(read.periodChoice, read.periods)}, '
      '${_courseScope(read.chosenCourses, byId)}';
  final pupil = 'the pupil with pupil_id $pupilId (class_id $classId)';
  final groups = _byCourse(evaluations, courseIds);
  final scopeCourses = read.chosenCourses ?? read.courses;
  final withoutEvaluations = [
    for (final course in scopeCourses)
      if (!groups.containsKey(course.id)) _courseLabel(course, byId),
  ];
  final list = read.evaluations;
  return [
    if (evaluations.isEmpty)
      'The LVS holds no evaluations of $pupil in school year $year, $scope.'
    else
      'The results of $pupil in the LVS, school year $year, $scope: '
          '${_count(evaluations.length, 'evaluation')}, per course, newest '
          'first.',
    if (!list.isComplete)
      'Only the first ${list.evaluations.length} evaluations were read '
          '(${list.pagesRead} pages of $lvsEvaluationsPerPage): the LVS may '
          'have more. Pass a period or a course to read fewer at a time.',
    if (read.olderSkorePart)
      "This pupil's file shows its results in the older Skore part (reports "
          'in Skore), which this tool does not read: it reads the Resultaten '
          'part only.',
    for (final MapEntry(key: id, value: shown) in _ordered(
      groups,
      read.courses,
    ))
      ..._courseBlock(id, shown, read, byId, courseIds),
    if (evaluations.isNotEmpty && withoutEvaluations.isNotEmpty)
      'Courses without evaluations here: ${withoutEvaluations.join(', ')}.',
    ..._feedbackBlock(
      read.feedback,
      periodIds: periodIds,
      courseIds: courseIds,
      year: year,
    ),
    ..._reportsBlock(read.reports, year),
    _periodsLine(read.periods, year),
  ].join('\n');
}

/// The lines of the course [id] (`null` for the evaluations without a
/// course) with its evaluations [shown], newest first: a heading with its
/// teachers and count, a summary line for many, then one line each.
List<String> _courseBlock(
  int? id,
  List<LvsEvaluation> shown,
  LvsResultsRead read,
  Map<int, LvsResultsCourse> byId,
  Set<int> courseIds,
) {
  final count = _count(shown.length, 'evaluation');
  final String heading;
  if (id == null) {
    heading = 'Without a course: $count.';
  } else {
    final course =
        byId[id] ?? shown.first.courses.firstWhere((course) => course.id == id);
    final teachers = <String>[];
    for (final evaluation in shown) {
      for (final each in evaluation.courses) {
        if (each.id != id) continue;
        for (final name in each.teacherNames) {
          final teacher = _oneLine(name);
          if (teacher.isNotEmpty && !teachers.contains(teacher)) {
            teachers.add(teacher);
          }
        }
      }
    }
    final taught = teachers.isEmpty
        ? ''
        : ', ${teachers.length == 1 ? 'teacher' : 'teachers'} '
              '${teachers.join(', ')}';
    heading = '${_courseLabel(course, byId)}$taught: $count.';
  }
  final withPeriod = read.periodChoice.periods.length != 1;
  return [
    heading,
    if (formatLvsResultsSummary(shown) case final summary?) '  $summary',
    for (final evaluation in shown)
      '  ${formatLvsEvaluation(evaluation, courseId: id, withPeriod: withPeriod)}',
  ];
}

/// The evaluations of [evaluations], newest first (by their date, those
/// without one last; of the same moment in their order), grouped by course:
/// the first of an evaluation's courses that is one of [courseIds] (the
/// first of all when that is empty), `null` for one without a course.
Map<int?, List<LvsEvaluation>> _byCourse(
  List<LvsEvaluation> evaluations,
  Set<int> courseIds,
) {
  final groups = <int?, List<LvsEvaluation>>{};
  for (final evaluation in _newestFirst(evaluations, (e) => e.date)) {
    final courses = evaluation.courses;
    final course = courseIds.isEmpty
        ? courses.firstOrNull
        : courses.where((each) => courseIds.contains(each.id)).firstOrNull ??
              courses.firstOrNull;
    groups.putIfAbsent(course?.id, () => []).add(evaluation);
  }
  return groups;
}

/// The entries of [groups] in the order of [courses] (the LVS's), then
/// those of other courses in the order they came, then the one without a
/// course.
Iterable<MapEntry<int?, List<LvsEvaluation>>> _ordered(
  Map<int?, List<LvsEvaluation>> groups,
  List<LvsResultsCourse> courses,
) {
  final known = {for (final course in courses) course.id};
  return [
    for (final course in courses)
      if (groups[course.id] case final shown?) MapEntry(course.id, shown),
    for (final entry in groups.entries)
      if (entry.key != null && !known.contains(entry.key)) entry,
    if (groups[null] case final shown?) MapEntry(null, shown),
  ];
}

/// [items], newest first by [date] (those without one last; of the same
/// moment in their order).
List<T> _newestFirst<T>(List<T> items, DateTime? Function(T) date) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final (dateA, dateB) = (date(a.$2), date(b.$2));
      final byDate = switch ((dateA, dateB)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final x?, final y?) => y.compareTo(x),
      };
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in indexed) item];
}

/// The line that sums up the scores of [evaluations] (one course's), from
/// [lvsResultsSummaryFrom] evaluations on; `null` for fewer. Computed here
/// from the scores the LVS gives, and saying so: only a score that is a
/// number ([LvsScore.percentage]) counts, and the line says how many could
/// not be counted.
///
/// ```text
/// Computed from the scores given (not by the LVS): 6 evaluations; of the 4 with a score as a number, 2 below half (under 50%); 2 could not be counted (a text, a symbol or no score).
/// ```
String? formatLvsResultsSummary(List<LvsEvaluation> evaluations) {
  final total = evaluations.length;
  if (total < lvsResultsSummaryFrom) return null;
  final numbers = [
    for (final evaluation in evaluations) ?evaluation.score.percentage,
  ];
  final below = numbers.where((percentage) => percentage < 50).length;
  final others = total - numbers.length;
  final counted = numbers.isEmpty
      ? '$total evaluations, none with a score as a number: none could be '
            'counted (texts, symbols or no score)'
      : others == 0
      ? '$total evaluations, all with a score as a number: $below below half '
            '(under 50%)'
      : '$total evaluations; of the ${numbers.length} with a score as a '
            'number, $below below half (under 50%); $others could not be '
            'counted (a text, a symbol or no score)';
  return 'Computed from the scores given (not by the LVS): $counted.';
}

/// One evaluation as `read_lvs_results` shows it under its course
/// [courseId]: its day (Belgian time), name, score as given
/// ([formatLvsScore]), whether it counts, whether it is not published to the
/// pupil, its component, its period ([withPeriod]), the other courses it is
/// for, and whether it has feedback.
///
/// ```text
/// - 2030-10-15 | Testevaluatie | 7/10 (70%) | counts | Testcomponent (TEST) | with feedback
/// ```
String formatLvsEvaluation(
  LvsEvaluation evaluation, {
  int? courseId,
  bool withPeriod = false,
}) {
  final name = _oneLine(evaluation.name);
  final component = [
    _oneLine(evaluation.componentName),
    if (_oneLine(evaluation.componentAbbreviation) case final short
        when short.isNotEmpty)
      '($short)',
  ].where((part) => part.isNotEmpty).join(' ');
  final others = [
    if (courseId != null)
      for (final course in evaluation.courses)
        if (course.id != courseId) _label(course.name),
  ];
  return '- ${[if (evaluation.date case final date?) lvsDay(date) else '(no date)', name.isEmpty ? '(no name)' : name, formatLvsScore(evaluation.score), if (evaluation.doesCount case final counts?) counts ? 'counts' : 'does not count', if (evaluation.isPublished == false) 'not published to the pupil', if (component.isNotEmpty) component, if (withPeriod && evaluation.period != null) _label(evaluation.period!.name), if (others.isNotEmpty) 'also for ${others.join(', ')}', if (evaluation.feedbackCount > 0) 'with feedback'].join(' | ')}';
}

/// [score] as the LVS gives it: points with their percentage (`7/10
/// (70%)`), a text with its description, a symbol by its icon's name, an
/// image, a rubric, a type the server does not know (said so), or no score.
/// Nothing is computed.
String formatLvsScore(LvsScore score) {
  final value = _oneLine(score.value);
  final description = _oneLine(score.description);
  String described(String what) =>
      description.isEmpty ? what : '$what ($description)';
  switch (score.type) {
    case '' when value.isEmpty && description.isEmpty:
      return 'no score';
    case LvsScoreType.percentage:
      final number = score.percentage ?? num.tryParse(value);
      final percent = number == null ? value : '${_number(number)}%';
      if (percent.isEmpty) {
        return description.isEmpty ? 'no score' : description;
      }
      return description.isEmpty ? percent : '$description ($percent)';
    case LvsScoreType.text:
      if (value.isEmpty) {
        return description.isEmpty ? 'no score' : description;
      }
      return described(value);
    case LvsScoreType.icon:
      return described(value.isEmpty ? 'a symbol' : 'a symbol, icon "$value"');
    case LvsScoreType.image:
      return described('an image');
    case LvsScoreType.rubrics:
      return described(value.isEmpty ? 'a rubric' : 'a rubric, "$value"');
    case final type:
      final kind = type.isEmpty
          ? 'a score without a type'
          : 'a score of type "${_oneLine(type)}", which the server does not '
                'know';
      return described(value.isEmpty ? kind : '$kind: "$value"');
  }
}

/// [number] as a percentage shows it: whole, or with one decimal.
String _number(num number) {
  if (number == number.roundToDouble()) return '${number.round()}';
  final text = number.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// The lines of the feedback: those on the periods and courses chosen
/// (all with [periodIds] and [courseIds] empty), newest first
/// ([formatLvsFeedback]), and how many were left out, and why.
///
/// Feedback on an evaluation follows its evaluation's period and courses; a
/// remark per course on a report its course; the class council's remarks
/// (and feedback of a kind the server does not know) are about no one
/// course, so a course chosen leaves them out. Remarks on reports are of
/// the school year: the period does not leave them out.
List<String> _feedbackBlock(
  List<LvsFeedback> feedback, {
  required Set<int> periodIds,
  required Set<int> courseIds,
  required String year,
}) {
  if (feedback.isEmpty) return ['Feedback: none in school year $year.'];
  var outside = 0;
  var noCourse = 0;
  final shown = <LvsFeedback>[];
  for (final item in feedback) {
    switch (item.kind) {
      case LvsFeedbackKind.evaluation || LvsFeedbackKind.goal:
        if (item.evaluation case final evaluation?
            when !_inPeriods(evaluation.period, periodIds) ||
                !_inCourses(evaluation.courses, courseIds)) {
          outside++;
          continue;
        }
      case LvsFeedbackKind.course:
        if (item.course case final course?
            when courseIds.isNotEmpty && !courseIds.contains(course.id)) {
          outside++;
          continue;
        }
      case LvsFeedbackKind.classCouncil || LvsFeedbackKind.unknown:
        if (courseIds.isNotEmpty) {
          noCourse++;
          continue;
        }
    }
    shown.add(item);
  }
  return [
    if (shown.isEmpty)
      'Feedback: none on these periods and courses.'
    else ...[
      'Feedback (${shown.length}), newest first:',
      for (final item in _newestFirst(shown, _feedbackDate))
        formatLvsFeedback(item),
    ],
    if (outside > 0)
      'Not shown: ${_count(outside, 'feedback')} on other periods or courses.',
    if (noCourse > 0)
      'Not shown: ${_count(noCourse, 'remark')} about no one course (of the '
          'class council, or the like); leave course out to see '
          '${noCourse == 1 ? 'it' : 'them'}.',
  ];
}

/// The day of [feedback]: that of its evaluation, or of its report.
DateTime? _feedbackDate(LvsFeedback feedback) =>
    feedback.evaluation?.date ?? feedback.report?.date;

/// One feedback as `read_lvs_results` shows it: a line with its day
/// (Belgian time; that of its evaluation or report), its teacher, what it is
/// on, and its text (as plain text; a text of more lines under the line,
/// indented), then its attachments by name only (nothing is downloaded).
///
/// The library gives the text as the LVS sends it, HTML, unlike its other
/// rich texts (yvanvds/dartschool#187), so it goes through the server's
/// [htmlToText] here, without its empty lines. Tracked for removal in #161.
///
/// ```text
/// - 2030-10-15 | by Piet Peeters | on the evaluation Testevaluatie (Testvak) | Testfeedback bij de evaluatie.
///   Attachments, by name only (not opened): Testbijlage.pdf
/// ```
String formatLvsFeedback(LvsFeedback feedback) {
  final author = _oneLine(feedback.author);
  final report = feedback.report == null
      ? 'a report'
      : 'the report ${_label(feedback.report!.name)}';
  final evaluation = feedback.evaluation;
  final evaluationName = evaluation == null
      ? 'an evaluation'
      : 'the evaluation ${_label(evaluation.name)}'
            '${evaluation.courses.isEmpty ? '' : ' (${[for (final course in evaluation.courses) _label(course.name)].join(', ')})'}';
  final about = switch (feedback.kind) {
    LvsFeedbackKind.evaluation => 'on $evaluationName',
    LvsFeedbackKind.goal => 'on a goal of $evaluationName',
    LvsFeedbackKind.course =>
      'on $report'
          '${feedback.course == null ? '' : ', for ${_label(feedback.course!.name)}'}',
    LvsFeedbackKind.classCouncil =>
      'the class council, on $report'
          '${_oneLine(feedback.reportPart).isEmpty ? '' : ', in its part ${_oneLine(feedback.reportPart)}'}',
    LvsFeedbackKind.unknown => 'feedback of a kind the server does not know',
  };
  final date = _feedbackDate(feedback);
  final head = [
    date == null ? '(no date)' : lvsDay(date),
    if (author.isNotEmpty) 'by $author',
    about,
  ].join(' | ');
  final text = [
    for (final line in htmlToText(feedback.text).split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  final attachments = [
    for (final attachment in feedback.attachments) _label(attachment.name),
  ];
  return [
    switch (text) {
      [] => '- $head | (no text)',
      [final line] => '- $head | $line',
      _ => '- $head',
    },
    if (text.length > 1)
      for (final line in text) '  $line',
    if (attachments.isNotEmpty)
      '  Attachments, by name only (not opened): ${attachments.join(', ')}',
  ].join('\n');
}

/// The lines of the reports of the school year: newest first, by day and
/// name only (the server does not open them).
List<String> _reportsBlock(List<LvsReport> reports, String year) {
  if (reports.isEmpty) return ['Reports: none in school year $year.'];
  return [
    'Reports of school year $year (${reports.length}), newest first, by name '
        'and day only: the server does not open them.',
    for (final report in _newestFirst(reports, (report) => report.date))
      '- ${report.date == null ? '(no date)' : lvsDay(report.date!)} | '
          '${_label(report.name)}',
  ];
}

/// The line that lists the periods of the school year, to ask for.
String _periodsLine(List<LvsResultsPeriod> periods, String year) =>
    periods.isEmpty
    ? 'The LVS lists no periods of the results in school year $year.'
    : 'Periods of the results in school year $year, to pass as period (its '
          'period_id or name, or all for every period): '
          '${_periodList(periods)}.';

/// Which periods a read is of, in words.
String _periodScope(LvsPeriodChoice choice, List<LvsResultsPeriod> all) {
  final named = [
    for (final period in choice.periods)
      _periodLabel(period, marked: choice.scope != LvsPeriodScope.active),
  ];
  return switch (choice.scope) {
    LvsPeriodScope.active when named.length == 1 =>
      'the active period ${named.single}',
    LvsPeriodScope.active => 'the active periods ${named.join(', ')}',
    LvsPeriodScope.noneActive when all.isEmpty =>
      'all periods (the LVS lists none)',
    LvsPeriodScope.noneActive => 'all periods (none is marked active)',
    LvsPeriodScope.all => 'all periods',
    LvsPeriodScope.chosen => 'the period ${named.join(', ')}',
  };
}

/// Which courses a read is of, in words: all ([chosen] `null`), or those
/// chosen.
String _courseScope(
  List<LvsResultsCourse>? chosen,
  Map<int, LvsResultsCourse> byId,
) {
  if (chosen == null) return 'all courses';
  final named = [for (final course in chosen) _courseLabel(course, byId)];
  return '${named.length == 1 ? 'the course' : 'the courses'} '
      '${named.join(', ')}';
}

/// Whether an evaluation of [period] is of the periods [ids]: always when
/// [ids] is empty (all periods) or it names no period.
bool _inPeriods(LvsResultsPeriod? period, Set<int> ids) =>
    ids.isEmpty || period == null || ids.contains(period.id);

/// Whether an evaluation of [courses] is of the courses [ids]: always when
/// [ids] is empty (all courses) or it names no course.
bool _inCourses(List<LvsResultsCourse> courses, Set<int> ids) =>
    ids.isEmpty ||
    courses.isEmpty ||
    courses.any((course) => ids.contains(course.id));

/// [period] with its id, and marked active unless [marked] is false:
/// `Testperiode (period_id 900401, active)`.
String _periodLabel(LvsResultsPeriod period, {bool marked = true}) =>
    '${_label(period.name)} (period_id ${period.id}'
    '${marked && period.isActive ? ', active' : ''})';

/// [periods] as the answer and its errors list them.
String _periodList(List<LvsResultsPeriod> periods) =>
    [for (final period in periods) _periodLabel(period)].join(', ');

/// [course] with its id, and the course it is a part of: `Testvak 2
/// (course_id 900302, a part of Testvak)`.
String _courseLabel(LvsResultsCourse course, Map<int, LvsResultsCourse> byId) {
  final parent = course.parentCourseId;
  final partOf = parent == null
      ? ''
      : ', a part of ${byId[parent] == null ? 'course_id $parent' : _label(byId[parent]!.name)}';
  return '${_label(course.name)} (course_id ${course.id}$partOf)';
}

/// [courses] as the errors list them.
String _courseList(List<LvsResultsCourse> courses) {
  final byId = {for (final course in courses) course.id: course};
  return [for (final course in courses) _courseLabel(course, byId)].join(', ');
}

/// [count] [noun]s: `1 evaluation`, `2 evaluations`; `feedback` stays the
/// same.
String _count(int count, String noun) =>
    '$count ${count == 1 || noun == 'feedback' ? noun : '${noun}s'}';

/// [text] on one line: each run of white space one space, trimmed.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [text] on one line, or `(no name)` when it is empty.
String _label(String text) {
  final line = _oneLine(text);
  return line.isEmpty ? '(no name)' : line;
}
