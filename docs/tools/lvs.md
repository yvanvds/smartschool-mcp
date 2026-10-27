# Pupil tracking system (LVS)

[Back to the overview](../../README.md)

The pupil tracking system ("leerlingvolgsysteem", LVS): a pupil's file with
its notes, results, support plan and absences. Opt-in: offered only when the
switch "Leerlingvolgsysteem" is on (`SMARTSCHOOL_LVS`). Most teachers can
read the LVS, so the switch is not about rights: the LVS holds the most
sensitive data about pupils (care, behaviour, educational needs, sometimes
health), and you and your school must choose to let an AI assistant read it.

Every LVS tool only reads, one pupil per call. Nothing is kept on this PC
and nothing of a pupil goes into the server's log. Claude is told to use the
tools only when you ask about a particular pupil, and not to copy what they
return into files, artifacts, messages or other tools unless you ask. See
[Privacy](#privacy) for how.

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`search_lvs_pupils`](#search_lvs_pupils) | Finds pupils by name | No |
| [`read_lvs_pupil`](#read_lvs_pupil) | Reads the overview of a pupil's file | No |
| [`read_lvs_notes`](#read_lvs_notes) | Reads the notes of a pupil's file | No |
| [`read_lvs_results`](#read_lvs_results) | Reads a pupil's results in every course | No |
| [`read_lvs_support_plan`](#read_lvs_support_plan) | Reads a pupil's support plan | No |
| [`read_lvs_absences`](#read_lvs_absences) | Reads a pupil's absences | No |

## Tools

### `search_lvs_pupils`

Finds the pupils whose name matches, among those you may see, one line each
with name, class and the two ids the other tools take. With several matches
Claude lets you choose, and never picks one.

### `read_lvs_pupil`

Reads the overview of one pupil's file: name, class, form tutors
(titularissen), today's attendance per half-day, and the parts of the file
that hold something (the school's note categories, results, support plans,
absences, ...), each marked when it has something new and with the tool that
reads it; then the parts that hold nothing.

### `read_lvs_notes`

Reads the notes of one pupil's file, what schools keep on behaviour, care
and educational needs, class council remarks and talks with parents: of one
school year (the current one by default), newest first, optionally of one
category, since a day, and at most 20 by default (100 at most).
Confidential notes are left out, and only counted, unless you explicitly ask
for them. Attachments are named, never downloaded. Whether the LVS takes a
note read this way as seen is not known.

### `read_lvs_results`

Reads one pupil's results, the "Resultaten" part of the file: the results
app pupils and parents see, in every course, not only your own gradebooks.
Of one school year (the current one by default) and by default its active
period, optionally one period or one course. Per course its evaluations,
newest first, with the score as given; for a course with 5 or more, a line
that counts those below half, computed by the server. Then the feedback, the
reports by name and day (nothing is downloaded) and the periods to ask for.

### `read_lvs_support_plan`

Reads one pupil's support plan ("handelingsplannen"), for schools that use
the LVS's support plans: the individual plan and the profile sketch of one
period (the current one by default), with the items you wrote first. Pass
your course to keep the items planned in it and those tied to no course.
Uploaded plans are named, never downloaded. The plan's evaluation, its
report and the earlier versions of its items are not read.

### `read_lvs_absences`

Reads one pupil's absences: the half-days the school registered with an
absence code, of one school year (the current one by default), with the
total per code, and the totals of the other school years. A motivation can
hold health information: by default the answer only counts them, and shows
them only when you ask why the pupil was absent.

## How it works

The tools of the pupil tracking system (LVS, "leerlingvolgsysteem",
`/?module=LVS`) are offered only when the switch "Leerlingvolgsysteem" is on
(see [Opt-in tools](../development.md#opt-in-tools)). The tools use the
library's `LvsService` (yvanvds/dartschool#160 to #164), which sends only
its reads, by an allowlist; all of them only read. The rules for LVS data in
this repository are in
[Pupil tracking system (LVS) data](../development.md#pupil-tracking-system-lvs-data).

### How `search_lvs_pupils` works

It searches with `searchPupils`, among the pupils the account may see, one
line each with name, class, `pupil_id` and `class_id`, in the LVS's order,
without the markup that highlights the match. With several matches the
result asks Claude to let the user choose, never to pick one; with none it
is a sentence, not an error.

### How `read_lvs_pupil` works

It reads the overview of one pupil's file (`pupil_id`, `class_id`;
`getPupilFile`): name, class and its description, the form tutors
(titularissen), today's attendance per half-day (`getStatusInfo`; a
half-day other than `am` or `pm` is named as the LVS names it: three were
seen on a school day, yvanvds/dartschool#168), and the parts of the file
that hold something (`hasItems`), as a list indented by depth: the school's
note categories with their `category_id`, headings marked, and the LVS's
own parts (results, support plans, absences, ...), each marked "with new
notes" or "with something new" (`hasNewItems`); then the parts that hold
nothing. A part's line names the tool that reads it, once there is one
(`lvsSectionReaders` in `lib/src/lvs/lvs_format.dart`): `read_lvs_notes` for
the note categories and their headings, `read_lvs_results` for the results
(Resultaten), `read_lvs_support_plan` for the support plans
(handelingsplannen), `read_lvs_absences` for the absences (Afwezigheden).
The LVS answers a pupil it does not know in that class with a placeholder
pupil, which the library reports (`SmartschoolLvsPupilNotFoundError`): the
error says to take both ids from one line of the search.

### How `read_lvs_notes` works

It reads the notes of one pupil's file (`pupil_id`, `class_id`; `getNotes`,
`getAllNotes`) in one school year (`school_year`, a label like `2025-2026`;
by default the current one in Belgian time; the library keeps only the notes
of that school year, as the LVS does not apply it reliably), newest first by
their Belgian day. With `category`, a `category_id` or a name (ignoring
case; a name several categories have, or one the file does not have, is an
error that lists them by path, with their ids), the notes of that category
and of each of its sub-categories: the file is read for them, then each on
its own (`getNotes` reads a category's own notes only; headings hold none
and are not read). Without it, the "all items" view of the file, its notes
only; as the LVS answers a pupil it does not know with no notes at all, an
empty answer has the file read too, so that the error says so. `since` (a
day) and `limit` (default 20, at most 100) keep the answer short.

Each note: its day, category, title, author and "new", then its fields as
`label: value`, in the library's plain text (a rich text with its lines, the
chosen options, a date's day, attachments by name only, nothing downloaded;
a heading by its text; a field type the library does not know as the LVS
gives it, which the line says; empty fields left out). Confidential notes
("vertrouwelijk"), which the library returns marked, are left out unless
`include_confidential` is true, which the description says to set only when
the user explicitly asks for them; the answer ends with how many notes there
are and how many were left out, and why: older than `since`, confidential
(counted only, nothing of them shown) or over the limit. The library sends
no "viewed" flag; whether the LVS takes a read note as seen was not captured
(yvanvds/dartschool#168), and the description says so.

A note's Belgian day is the library's (`lvsDayOf`,
yvanvds/dartschool#185), the very day it keeps the notes of a school year
by; and the file is read without today's attendance
(`withTodayStatus: false`, yvanvds/dartschool#186), which the tool does not
show (#160). The notes are read and written in `lib/src/lvs/lvs_notes.dart`;
`lvsSchoolYearArgument` and `lvsSchoolYearSchema` in `lvs_access.dart` are
the `school_year` argument of the LVS tools that read a school year.

### How `read_lvs_results` works

It reads one pupil's results (`pupil_id`, `class_id`), the "Resultaten" part
of the file (`getResultsPeriods`, `getResultsCourses`, `getAllEvaluations`,
`getFeedback`, `getReports`, which the library sends with the app's
headers). Of one school year (`school_year`, as for `read_lvs_notes`; for
another than the current one the app's configuration is read first,
`getResultsConfiguration`, and an account it lets see the current school
year only, `canSeeAll` false, gets an error), by default of its active
period (`isActive`; all periods when none is, which the answer says).
`period` takes a `period_id` or a name (ignoring case, or else the period
whose name holds it; several matches are an error that lists them with their
ids), or `all`. `course` is a filter: the course with that `course_id`, or
those with that name (ignoring case), or else those whose name holds it,
with their parts (`parentCourseId`, at any depth); a course the results do
not have is an error that lists them. Both go to the LVS as ids, and the
server keeps only the evaluations of the periods and courses chosen, also
when the LVS sends others (whether it applies the ids was not captured).

Per course, in the LVS's order, its teachers and count, then its evaluations
newest first by their Belgian day, each with its name, the score as given
(`formatLvsScore`: points with their percentage, a text with its
description, a symbol by its icon, an image, a rubric, a type the server
does not know, or none; nothing computed), whether it counts, whether it is
not published to the pupil, its component, its period when several are
shown, the other courses it is for, and whether it has feedback. A course
with 5 or more evaluations gets a summary line computed from the scores
given (`formatLvsResultsSummary`): how many are below half, of those whose
score is a number (`LvsScore.percentage`), and how many could not be
counted; the line says it is computed, not the LVS's. Then the courses
without evaluations; the feedback, newest first (day, teacher, what it is
on, its text as plain text, attachments by name only), of the periods and
courses chosen (feedback on an evaluation by its evaluation, a remark per
course on a report by its course; the class council's remarks are about no
one course and left out with `course`), with what was left out counted; the
reports of the school year by name and day (nothing is downloaded); and the
periods to ask for.

Evaluations are read 100 a page, at most 10 pages: when the cap stops at a
full page, the answer says the LVS may have more. A refusal with HTTP 403 is
"no access to the results" in a sentence (`withLvs`'s `part`). As the LVS
answers a pupil it does not know with empty lists, the file is read too when
no evaluation, feedback or report came, or before saying that there is no
period or course to pick from: the error then says the LVS does not know the
pupil, and a file that shows the older Skore part instead of Resultaten,
which the library does not read, is said so. The comments on reports
(`/LVS/Skorecomments`) are not read: the library does not read them, nor
that older part (yvanvds/dartschool#169). The library gives the feedback's
text as plain text with its lines, as its other LVS texts
(flutter_smartschool 0.4.0, yvanvds/dartschool#187), and it is shown as it
is: never parsed as HTML again, which would drop markup a teacher wrote
about and decode an entity twice (#170, #161). The results are read and
written in `lib/src/lvs/lvs_results.dart`; `lvsIdOrNameArgument`, `lvsIdIn`
and `lvsNameKey` in `lvs_access.dart` are an argument that names a part of
the file by its id or name (the notes' `category` too). As for
`read_lvs_notes`, the file is read without today's attendance, and the
Belgian day is the library's (`lvsDayOf`).

### How `read_lvs_support_plan` works

It reads one pupil's support plan (`pupil_id`, `class_id`), the
"handelingsplannen" part of the file: the individual plan (IHP) and the
profile sketch of one period (`getSupportPlanPeriods`, `getSupportPlan`,
`getProfileSketch`; only the live plan, `exportID` 0). By default the
current period (`periodID` 0); `period` takes a `period_id` or a name of the
period menu (ignoring case, or else the period whose name holds it; several
matches, or none, are an error that lists them with their ids and the menu's
heading). The items the user wrote first, marked "by the user" (an item's
author by user id, `LvsPlanItem.authorId`, against the logged-in user's,
`getCurrentUser`, which sends nothing to the LVS; yvanvds/dartschool#189,
#163), and the answer's first line says how many; then the others, each part
in the LVS's order.

Each item with its kind, author, date (as the LVS shows it) and courses
(those the LVS names for it, and those of its course ids, `courseIds`, that
the plan names; a course id the plan does not name is counted): an item of
support needs with its support needs (ondersteuningsnoden), main and work
goals, approach and the comment on it; an item of goals (from the class's
group plan, or chosen for the pupil, and the school's own goals or those of
special primary education when the LVS says so) with its theme, start
situation and goals, each with its domain, objectives, approach and
planning, and whether it is no longer in its curriculum; an uploaded plan by
its file name and kind only (nothing is downloaded); an item of a kind the
library does not know by its type, said so. Lists and texts of more lines
keep their lines; empty fields are left out, and an item with nothing filled
in says so. Then the profile sketch (profielschets) with its last change,
and the periods to ask for.

`course` is a filter by name (ignoring case, or else the courses whose name
holds it), among the plan's courses (`LvsSupportPlan.courses`) and those its
items name: the items planned in it by its id (an item's `courseIds`, and
the course ids of its goals' planning, `LvsPlanGoal.moments`, as the LVS's
web client filters them), or that name it among their courses or their
goals' planning, and the items tied to no course, which may concern every
course; the others are counted. `course` takes no id: the answer prints
none, and the LVS's course ids need not be those of `read_lvs_results`.
Which courses the user teaches the library does not read yet
(yvanvds/dartschool#196): the description says to pass the user's course as
`course`.

The three cases without a plan each get a sentence: a file without a part of
support plans (a school that does not use them, or an account that may not
see them: the sentence points to the note categories and `read_lvs_notes`),
a pupil without a plan in the period (`noPlan`), and no period of support
plans (`noPeriod`, as for a class without a structure of them, with the
LVS's message). As what the LVS answers a pupil it does not know was not
captured, the file is read too when the plan holds no item and there is no
sketch, or before saying that there is no period to pick from: the error
then says the LVS does not know the pupil. A refusal with HTTP 403 is "no
access to the support plans" in a sentence. Not read: the plan's
evaluation, its report and the earlier versions of its items, which the
library does not read yet (yvanvds/dartschool#170, #162); the description
and every answer with a plan say so. The plan is read and written in
`lib/src/lvs/lvs_support_plan.dart`; `lvsNamed` in `lvs_access.dart` finds a
period or a course by name (the results' too). No real pupil's plan was
captured (yvanvds/dartschool#168): the fixtures are in the shapes of the
LVS's JavaScript. As for `read_lvs_notes`, the file is read without today's
attendance.

### How `read_lvs_absences` works

It reads one pupil's absences (`pupil_id`, `class_id`), the "Afwezigheden"
part of the file: the half-days the school registered with an absence code
(`getAbsences`, one read). The library sends no school year: the LVS
answers with the school years it picks, each a period of its answer.
`school_year` (as for `read_lvs_notes`; by default the current one in
Belgian time) picks the periods labelled with it; for those, the total per
code (its description and code, in half-days, a whole day counting two: the
library's `totalsByCode`), then each absence day after day in the LVS's
order, with its day (`YYYY-MM-DD`) and day of the week, morning, afternoon
or whole day, and its code; a day the library could not read (`date` null)
is shown as the LVS shows it, said so. Then the other school years the LVS
gives, each with its totals (a period whose label is not a school year by
its label, said so). The codes are the school's own.

A motivation can hold health information: by default the answer says only
how many absences have one, never what they say; `with_motivation` (the
description says to set it only when the user asks why the pupil was
absent) shows each under its absence, as plain text with its lines. No
absences is a sentence: none in the school year asked for (with the school
years the LVS gives), none at all, or none and no part of absences in the
file. The LVS answered a made-up pupil with HTTP 500 and an error page:
after a 500 the library reads the file itself, without today's attendance,
and throws `SmartschoolLvsPupilNotFoundError` for a pupil the LVS does not
know (yvanvds/dartschool#190), so the error says so. When there are no
absences at all, the file is read here too, to tell an unknown pupil and a
file without a part of absences apart. A refusal with HTTP 403 is "no access
to the absences" in a sentence, without reading the file. The absences are
read and written in `lib/src/lvs/lvs_absences.dart`. As the library's read
after a 500, the file is read here without today's attendance.

### Privacy

Privacy, for every LVS tool (`lib/src/lvs/lvs_access.dart`): read-only;
nothing on disk (no cache, no downloads); nothing in the log but an error's
type and HTTP status (`lvsTool` and `lvsLogDescription`: the server's own
catch-all would log an error's message, which may quote the LVS; and
`withLvs` has the session log a refused session that way too, through
`SmartschoolSession.run`'s `describeError`, as its message names the
request, with the pupil's id); errors say what to do, not what the answer
held (`lvsToolError`); the descriptions say that the data is confidential,
to use the tool only when the user asks about a particular pupil, and not to
copy what it returns into files, artifacts, messages or other tools unless
the user asks (`lvsPrivacyRules`); one pupil per call. A refusal (HTTP 403,
or a redirect to the start page) says that the account may have no access to
the LVS or may not see this pupil, and `smartschool_status` checks access
with the root of the LVS's class tree, which holds no pupil: what the LVS
answers an account without access was not captured
(yvanvds/dartschool#168). #159 is the live check.

### Helpers and tests

LVS helpers live in `lib/src/lvs/`. In `lvs_access.dart`: `withLvs`, which
runs an action with an `LvsReads` (an `LvsService` that also tells the
logged-in user's id, `userId`) on the session and turns the LVS's errors
into `ToolError`s that say what to do (`lvsToolError`, with `lvsFix` for an
account without access); `lvsTool`, which every LVS tool is, so that nothing
of an error reaches the log but its type and HTTP status
(`lvsLogDescription`); the sentences every description ends with
(`lvsPrivacyRules`); what turning the switch on means, for
`smartschool_status` (`lvsRights`, and `lvsCaution` with
`lvsPrivacyGuideUrl`, the guide's privacy section); the arguments the tools
share (`lvsPupilArguments` with `lvsPupilIdSchema` and `lvsClassIdSchema`,
`lvsSchoolYearArgument` and `lvsSchoolYearSchema`, and an id or a name with
`lvsIdOrNameArgument`, `lvsIdIn`, `lvsNameKey` and `lvsNamed`); and
`checkLvsAccess`, the access check of `smartschool_status`. In
`lvs_format.dart`: the lines of `search_lvs_pupils` and `read_lvs_pupil`
(`formatLvsMatches`, `formatLvsPupilFile`, with `lvsSectionReaders`, the
tool that reads each part) and a school year (`formatLvsSchoolYear`); a
Belgian day is the library's `lvsDayOf`. Each part of the file the tools
read has a file of its own, which reads it, picks from it and writes the
answer: `lvs_notes.dart` (`readLvsNotes`, `selectLvsNotes`,
`formatLvsNotes`), `lvs_results.dart` (`readLvsResults`,
`formatLvsResults`), `lvs_support_plan.dart` (`readLvsSupportPlan`,
`formatLvsSupportPlan`) and `lvs_absences.dart` (`readLvsAbsences`,
`formatLvsAbsences`). In `lvs_opt_in.dart`: the LVS tools behind their
switch (`lvsOptIn`).

The tests run against a fake LVS (`test/support/fake_lvs.dart`,
`FakeSmartschool.lvs`) that answers the reads of `LvsService` with the
hand-written fixtures of `test/fixtures/lvs/`, with the fakes of
`test/fixtures/lvs/FAKES.md` only (see
[Pupil tracking system (LVS) data](../development.md#pupil-tracking-system-lvs-data)).
`test/support/lvs_tool_harness.dart` calls the LVS tools over MCP on the
real server and library against that fake, and gives each test the requests
the fake LVS got, the server's log of a call
(`test/support/log_capture.dart`) and the cache folder, to check that
nothing of a pupil reaches either.
