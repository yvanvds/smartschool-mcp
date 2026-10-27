# Gradebook (Puntenboek)

[Back to the overview](../../README.md)

Your own gradebooks in Skore ("Puntenboek"), as every teacher has them, and
those colleagues shared with you: evaluations, grades, feedback and the
course comments on reports. For every account, without a switch: these tools
need none of the rights of [Skore administration](skore.md). Tools that
change something follow the
[shared rules](../../README.md#changes-and-approval).

A gradebook a colleague shared with you (Skore's tab "Gedeeld"), such as the
behaviour gradebook of a class its form teacher shared with the
co-titularis, works as your own: every answer names its owner, one shared to
read only is never changed, and no evaluation is created in a shared
gradebook. The writes work in gradebooks of Skore's current school year
only.

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_skore_gradebooks`](#list_skore_gradebooks) | Lists your gradebooks and those shared with you | No |
| [`read_skore_gradebook`](#read_skore_gradebook) | Reads a gradebook's periods, reports and pupils | No |
| [`list_skore_evaluations`](#list_skore_evaluations) | Lists the evaluations of a period with their grades | No |
| [`read_skore_feedback`](#read_skore_feedback) | Reads a pupil's feedback on an evaluation | No |
| [`read_skore_report`](#read_skore_report) | Reads a report's results and course comments | No |
| [`create_skore_evaluation`](#create_skore_evaluation) | Creates an evaluation, always unpublished | Yes, asks approval |
| [`save_skore_grades`](#save_skore_grades) | Saves or clears the grades of an evaluation | Yes, asks approval |
| [`save_skore_feedback`](#save_skore_feedback) | Gives a pupil your feedback on an evaluation | Yes, asks approval |
| [`save_skore_report_comment`](#save_skore_report_comment) | Writes a pupil's course comment on a report | Yes, asks approval |

## Tools

### `list_skore_gradebooks`

Lists your own gradebooks of a school year (Skore's current one by default),
one line each with its class, its course and its id; then the gradebooks
colleagues shared with you, each with its owner and whether you may change
it; then the school years Skore offers. Words in the question keep the
gradebooks whose class or course holds them.

### `read_skore_gradebook`

Reads one gradebook: whether you may change it, its evaluation periods (open
or closed, until when, and Skore's note on each), its report periods, and its
pupils with their class number and pupil id. A gradebook with report periods
only, such as a behaviour gradebook, says that it has no evaluations, and
that its course comments are written in its report periods.

### `list_skore_evaluations`

Lists the evaluations of one period of a gradebook (by default the one Skore
opens it on), each with its title, day, max, component and type, and whether
the pupils see it (in capitals when they do). Under each, the averages and
every pupil's grade, marked when the pupil has feedback. With one
evaluation, it gives one line per pupil with the pupil id: the view Claude
uses to match the names you give to pupils. For an open period it also lists
the components a new evaluation can count for. An evaluation on a scale
(Skore's "Waarderingen") shows each pupil's level on the school's scale.

### `read_skore_feedback`

Reads the feedback of one pupil on one evaluation: every feedback text,
whoever wrote it, with its author (yours marked), when it was written and
changed, its attachments by name and whether you may change it, under the
evaluation and the pupil's grade.

### `read_skore_report`

Reads one report period of a gradebook for its course: the components with
their class averages, and per pupil the result per component and the course
comment, with whether you may change it. The course comment is printed on
the report the pupil and their parents get; Skore keeps one per pupil,
course and report, shared by the colleagues who give the course, and does
not say who wrote it. Optionally for one pupil only.

### `create_skore_evaluation`

Creates an evaluation in points (a column of grades out of a max) in a
period of one of your own gradebooks: a title, a day, the max, and
optionally a short name and a component. It is **always unpublished**: you
publish it in Smartschool. An evaluation on a scale is made in Smartschool
too. Asks for approval; Claude reads the period first, so as not to make the
same evaluation twice, and shows you the gradebook, period, title, short
name, day, max and component, and that it will be unpublished.

### `save_skore_grades`

Saves or clears the grades of pupils in one evaluation in points, the whole
list in one call: one approval for a list you saw, rather than one per
pupil. Claude matches the names you give to pupils with
`list_skore_evaluations` and asks rather than guesses; then it shows you the
full list (class number, name, current grade and new grade, out of the max)
and asks for approval. An evaluation that is published or scheduled is
refused until you say yes to exactly that: a grade there is visible to its
pupils at once, with a notification, or from its publication time on. The
values of an evaluation on a scale are entered in Smartschool.

### `save_skore_feedback`

Gives one pupil your written feedback on one evaluation, or changes the
feedback you gave them there. One pupil per call: each text is personal, and
you should see each one. Asks for approval; Claude reads the pupil's
feedback first and, when you gave feedback there already, shows you the old
text and the new one. Feedback others gave the pupil is never changed. A
published or scheduled evaluation is refused as for the grades: the pupil
sees the feedback at once, or from its publication time on.

### `save_skore_report_comment`

Writes, changes or clears the course comment of one pupil on a report
period: the text printed on the report the pupil and their parents get. One
pupil per call, each read and confirmed. Asks for approval; Claude reads the
comment first and shows you the pupil, the report, the comment now and the
new text. A comment that changed since it was read, perhaps a colleague's,
is never overwritten unseen. It never closes, unlocks, calculates or
publishes a report.

## How it works

The gradebook tools work in the user's own gradebooks in Skore
("Puntenboek", `/SkoreGradebook`) and in those colleagues shared with them
(see [Gradebooks shared with the user](#gradebooks-shared-with-the-user)),
with the library's `SkoreGradebookService` (dartschool#148, dartschool#149,
dartschool#150, dartschool#151, dartschool#152, dartschool#191,
dartschool#195). They need none of the rights of the
[Skore tools](skore.md), so they are offered to every account, without a
switch, and no message of theirs speaks of "Skore-beheer" or of rights. The
first five change nothing; `create_skore_evaluation` creates an evaluation,
always unpublished, `save_skore_grades` saves the grades of one,
`save_skore_feedback` gives a pupil the user's feedback on one, and
`save_skore_report_comment` writes a pupil's course comment on a report.

### How `list_skore_gradebooks` works

It reads the user's own gradebooks of one school year
(`getGradebookYear`), one line each in Skore's order: the class, the course
as Skore's left panel names it (with the grade, such as `(6e j DO)`) and the
gradebook id; then those shared with the user, in a section of their own
(see [Gradebooks shared with the user](#gradebooks-shared-with-the-user));
then the school years Skore offers, each with its workyear id.
`workyear_id` asks for an earlier school year (Skore's current one without
it); `query` keeps the gradebooks whose class or course holds every word, as
for `list_skore_classes`. A school year without gradebooks (also an account
without any, such as a pupil's, if Skore answers it with an empty list) gets
a sentence that names the year, not an error.

### How `read_skore_gradebook` works

It reads one gradebook (`gradebook_id`, optional `workyear_id`;
`getGradebook`): whether Skore lets the user change it (`writable`;
read-only in coordinator mode; not asked for a gradebook without periods),
and when it does but no period is open, that it takes no grades now. A
gradebook without evaluation periods says so instead ("no evaluation periods
yet"); one with report periods only (`SkoreGradebookSheet.reports`,
flutter_smartschool 0.4.0), as Skore shows a behaviour gradebook such as
"Gedrag (A-stroom, D/A en D)" (#168), says that it has no evaluation
periods, only report periods, so no evaluations and no grades, and that its
course comments, one per pupil, are written in its report periods and go on
the report (`formatSkoreMissingPeriods`, `skoreReportPeriodsOnlyNote`).

Then its periods in Skore's order, each with its period id, whether it is
open, its closing time (in the time of this PC, Belgium), whether Skore
opens the gradebook on it (`activePeriod`) and Skore's note on it (the
period's `info` as one line, without the paragraphs that only repeat its
name or say `Gesloten!`: what is left is when it opened and the school's
note, such as which weeks it covers); its report periods (#171,
`SkoreGradebookSheet.reports`, Skore's "Rapporten", such as `R1D: Rapport
1`), in Skore's order, each with its report id, whether it is open, its
closing time and Skore's note on it (the same rule as for a period), under a
line that says each pupil's course comment is written there and
`read_skore_report` reads one (none for a gradebook without); and its
pupils, each with the class number (when Skore shows one), the name last
name first, the pupil id, and whether Skore greys the pupil out as inactive.
A gradebook with report periods only also names `read_skore_report` and
`save_skore_report_comment` in its sentence on the course comments.

### How `list_skore_evaluations` works

It reads the evaluations of one period of a gradebook (`gradebook_id`,
optional `period_id` and `workyear_id`; `getGradebook`, then
`getEvaluations` for the period), with their grades. Without `period_id`,
the period Skore opens the gradebook on (`activePeriod`). Each evaluation on
one line, in Skore's order: its title (and short name), its evaluation id
(`SkoreEvaluation.id`, the id the other tools take: Skore's column letter,
also shown, changes when an evaluation is added), its day, max, component,
type (points, a scale), whether it comes from the planner, and last its
publication, in capitals when the pupils see it: `not published`,
`SCHEDULED for <time>` or `PUBLISHED since <time>` (Belgian time, the
library compares Skore's `publicdatetime` with the clock), each saying what
the pupils see. Under it the class and group averages and how many pupils
have a grade, then the grades on one line, every pupil by class number and
name next to the grade as Skore stores it (`15.5`, with a decimal point;
`no grade` for an empty cell), marked `(feedback)` when the pupil has
feedback on it (`hasFeedback`); the pupil ids follow once, after the
evaluations, then the gradebook's other periods.

`evaluation_id` gives only that evaluation, one line per pupil with the
pupil id, the grade out of the max and `feedback`: the view to match the
names a user gives to pupil ids. Without `period_id` it is looked for in
every period (see [Finding an evaluation](#finding-an-evaluation)). The
overview keeps an evaluation's grades on its own line, each grade next to
the pupil's name, rather than a grid with a column per evaluation: Claude
never has to line up a column with an evaluation, a question about one
evaluation ("who has no grade yet?") is one line, and the output stays
smaller than one line per pupil per evaluation.

A period without evaluations, and a gradebook without evaluation periods,
get a sentence (for one with report periods only, the same two sentences as
`read_skore_gradebook`); a `period_id` that is not one of the gradebook's is
an error that lists its periods, before any evaluations are read. In a
gradebook without evaluation periods, a `period_id` (also a report's id) and
an `evaluation_id` are errors that say it has none, as are the other
gradebook tools' calls on it.

For an open period, a last line lists the components a new evaluation in it
can count for (`getComponents`, one small request: `geen` for none and, for
instance, `DW`), each with its component id, and the default
`create_skore_evaluation` takes without a component: the library's rule, the
second when Skore offers exactly two, else `geen` (none when it offers no
`geen`). The library keeps that rule private, so the server repeats it
(`skoreDefaultComponent`, dartschool#156, to be removed in #147). Components
Skore gives in a shape the library does not know leave the evaluations
listed, with a line that says the components could not be read. A closed
period gets no line, and its components are not read: no evaluation can be
created in it.

An evaluation on a scale (Skore's "Waarderingen", `evaltype` 2, such as for
behaviour; #169, flutter_smartschool 0.4.0, yvanvds/dartschool#193) shows
each pupil's value as its level on the school's scale, by its label and
abbreviation, with the value Skore stores out of the max (`Zeer goed (ZG;
stored as 10)`; `SkoreScale.levelOf`, as Skore's web client finds it), and
the scale itself once, its levels from low to high with the percentage of
the max each starts at. The scale is read once per call, and only when an
evaluation shown is on a scale (`getScale`: two `GET`s, of the page
`/SkoreGradebook` and of its frame, which holds it as `defaultScale`;
`readSkoreScaleFor`). A value no level covers says so; a scale the library
cannot read leaves the values as Skore stores them, with a sentence that the
labels could not be read, and the reason in the log only. No evaluation on a
scale was seen live: the library reads it as Skore's web client does.

An evaluation whose grades the library cannot read (`isReadable` false) is
listed with why instead of its grades, and the rest of the period is read
around it (#170): for a type the server does not support yet, its
`evaltype` (`a type the server does not support (evaltype 3)`); for a cell
in a shape it does not know, the library's reason, which names the cell by
its row and quotes nothing of Skore's answer (`skoreUnreadableReason`).
`read_skore_feedback` reads its feedback with "grade not read".

### How `read_skore_feedback` works

It reads the feedback of one pupil on one evaluation (`gradebook_id`,
`evaluation_id`, `pupil_id`, optional `period_id` and `workyear_id`;
`getFeedback`, one `GET` of Skore's REST API as the feedback panel reads
it): every feedback text, whoever wrote it, in the order written, each with
its author (marked when it is the user: the logged-in user, by the session's
user id, not the gradebook's teacher, who is the owner of a shared gradebook;
see [Gradebooks shared with the user](#gradebooks-shared-with-the-user)),
when it was written and last changed (Belgian time), the names of its
attachments, whether Skore lets the user change it (`canEdit`) and its text,
line by line. Above it the evaluation (with its publication: the pupils see
the feedback on a published one) and the pupil with the grade (on a scale,
with its level, the scale read once as for `list_skore_evaluations`). No
feedback is a sentence. The pupil is looked up in the gradebook first, so an
unknown pupil is an error before anything else is read.

### How `read_skore_report` works

It reads one report period of a gradebook (`gradebook_id`, `report_id` from
`read_skore_gradebook`, optional `pupil_id` and `workyear_id`; #171,
`getReport`, one `getReportsResults` as Skore's web client opens a report,
after `getGradebook` for the report periods and the pupils' names): the
report (as `read_skore_gradebook` lists it), the course as the report names
it with its components and their class averages (or, for a course without
components such as behaviour, that the report has only the course comment),
what the course comment is (printed on the report the pupil and their
parents get; one per pupil, course and report, shared by the colleagues who
give the course, without its author, as Skore keeps it; at most
`commentMaxLength` characters), whether the report is open, and per pupil in
Skore's order the result per component as Skore shows it (`no result` for
`-`, `(low)` for `gbc_low`) and the comment: whether Skore lets the user
change it (`isEditable`, and the report open; `closed for this pupil` when
Skore does not), then its text, line by line. Since Skore does not say who
wrote a comment, the result marks none as the user's. In a gradebook shared
with the user to read only, no comment is one the user may change, whatever
Skore marks in its owner's name. `pupil_id` gives that pupil only.

An unknown report id (also a period id) is an error that lists the
gradebook's report periods, and an unknown pupil an error, both before the
report is read (`skoreReportPeriod`, `skoreGradebookPupil`). A course that
is not on the report, which Skore answers with HTTP 404 and "Course not
found in source!" (seen live for a project gradebook,
yvanvds/dartschool#204), is an error that says so and that trying again does
not help, the library's message in the log only (`readSkoreReport`). The
library throws it as a plain `SmartschoolSkoreError`, so the server tells it
apart by the message's text; removing that is #174, blocked on
dartschool#204.

### How `create_skore_evaluation` works

It creates an evaluation in points (the library makes no other type, so one
on a scale is made in Smartschool) in a period of a gradebook of Skore's
current school year (`gradebook_id`, `title`, `date` as a day like
`2026-10-14`, `max` a positive whole number; optional `period_id`, else the
period Skore opens the gradebook on, `short_name` and `component`;
`createEvaluation`), always unpublished: the library sends `public` 0 and no
publication time, and has no way to publish. Marked destructive and not
idempotent, so Claude Desktop asks for approval before every call; its
description tells Claude to read the period with `list_skore_evaluations`
first (not to make an evaluation with the same title and date twice), to
show the user the gradebook (class and course), the period, title, short
name, date, max and component, to say it will be unpublished, and to call
only after explicit confirmation. `component` is a name (ignoring case) or a
component id of those `getComponents` gives for the period; one Skore does
not offer is an error that lists them and the default, before the library is
asked. A blank title or a date that is not a day is an error before anything
is sent. The result is the evaluation as Skore lists it after the save: its
evaluation id, title, date, max, component and that it is not published.
See [Checks before a new evaluation is saved](#checks-before-a-new-evaluation-is-saved)
for what the library checks and how each outcome is reported.

### How `save_skore_grades` works

It saves the grades of pupils in one evaluation of a gradebook of Skore's
current school year, or clears them (`gradebook_id`, `evaluation_id`,
`grades`: a list of `{pupil_id, grade}`, the grade a text such as `"15"`,
`"15.5"` or `"15,5"`, empty or null to clear it; optional `period_id`, to
find the evaluation with one read, and `allow_published`, false by default;
`saveGrades`). Marked destructive, so Claude Desktop asks for approval
before every call, and idempotent: saving the same grades again gives the
same state. Its description tells Claude to read the evaluation with
`list_skore_evaluations` (with `evaluation_id`) first, to match the names
the user gave to pupil ids there and to ask rather than guess a pupil for an
ambiguous name, to show the full list, and to call only after explicit
confirmation. Pupils go by id, not by name: names are ambiguous. An empty
list, a pupil given twice and a grade that is not a text or null are errors
before anything is sent; a pupil the gradebook does not list is an error
that names every such id, before the evaluations are read.

Only an evaluation in points takes grades: one on a scale is refused in the
server's own words (its values are levels, and the library saves no value
on a scale, flutter_smartschool 0.4.0; the user enters them in Smartschool,
and its feedback goes with `save_skore_feedback`), and so is one whose
grades the library cannot read, with why (`skoreUnreadableReason`), both
before the library is asked (#169). The library refuses both too, after
reading Skore again, with a reason worded for its caller ("not in points
(evaltype 2)"). An evaluation that is published or scheduled is refused
unless `allow_published` is true: a grade there is visible to its pupils at
once, and the school sends them a notification, or from its publication
time on. The refusal says that, and that Claude passes
`allow_published: true` only after telling the user exactly that and
getting their explicit yes; the description says the same. The result lists
each pupil (class number, name, pupil id) with the grade as Skore lists it
after the save, in the order given, under the evaluation with its
publication.

The library reads the gradebook, the period and the evaluation again, checks
every pupil and grade first, and refuses the whole list when one does not
fit (`SmartschoolSkoreChangeRefusedError`: a grade that is not a number or
is above the max, a pupil without a cell in the class, a closed or
read-only period, an evaluation from the planner, a published or scheduled
one without `allow_published`; one not in points the server refuses first):
nothing was saved, and the reason is passed on with what to read again
(`list_skore_evaluations` with the `evaluation_id`, `read_skore_gradebook`).
The server checks the publication itself first, from the evaluation it has
just read, so that the refusal says what the pupils would see: the
library's refusal cannot be told apart from its other ones (dartschool#157,
removal tracked in #148). When the evaluation is published between the two
reads, the library's own reason is passed on.

Then the library sends `saveGrade` for each pupil in turn (a failed one does
not stop the others) and reads the period again once. When it cannot
confirm every grade (`SmartschoolSkoreGradeSaveUnconfirmedError`), the
result lists by pupil the grades it confirmed, as Skore lists them, and the
ones that may or may not have been saved, with the grade sent; saving a
grade again is harmless, so it says to read the evaluation again with
`list_skore_evaluations`, tell the user, and save only the grades that
differ. The library's message, which says per pupil why, goes to the log
only. A grade save gives the same state when sent again, so the library
sends it again itself after a new login; when Smartschool refuses the
session for the first save even then, nothing was saved, and the session
repeats the call, which saves each grade once. When it refuses a later one,
the pupils after it are not sent, and the result reports them as not
confirmed; that is not repeated.

### How `save_skore_feedback` works

It gives one pupil the user's written feedback on one evaluation of a
gradebook of Skore's current school year, or changes the text of the
feedback the user gave them there (`gradebook_id`, `evaluation_id`,
`pupil_id`, `text`; optional `period_id`, to find the evaluation with one
read, and `allow_published`, false by default; `saveFeedback`). One pupil
per call, rather than skimming past one in a list. The text is plain text,
trimmed, with its line breaks kept (as the library sends it and Skore lists
it); a blank text is an error before anything is sent. Marked destructive,
so Claude Desktop asks for approval before every call, and not idempotent: a
first call creates the feedback. A second call changes that feedback rather
than adding one, as the library reads the pupil's feedback first; the
description says so instead of claiming idempotence. Its description tells
Claude to read the pupil's feedback with `read_skore_feedback` first, and
when the user already gave feedback there, to show the old text and the new
one, as this replaces it; to show the pupil (class number, name), the
evaluation and the text; and to call only after explicit confirmation.
Feedback that others gave the pupil is never sent: the library keeps to the
user's own. Feedback on an evaluation on a scale goes as on one in points,
with the same checks and the same `POST`s (the library sends it to the same
REST API; not tried live, #169); one whose grades the library cannot read is
refused in the server's own words, with why, before the pupil's feedback is
read. A published or scheduled evaluation is refused without
`allow_published`, as for the grades: the pupil sees the feedback at once
(and the school sends a notification), or from its publication time on. The
result is the feedback as Skore lists it after the save: whether it is new
or a change of the user's feedback, its times (written, changed) and its
text, under the evaluation with its publication.

The server reads the gradebook, the pupil, the evaluation (refusing a
published or scheduled one without `allow_published`, as for the grades)
and the pupil's feedback (`getFeedback`) before the library is asked, and
keeps the user's own feedback (by the gradebook's teacher, the user). Two
cases get their own words, and nothing is sent: the user has **more than
one** feedback of their own for the pupil there (the library changes none of
them, as it cannot tell which one is meant: the user keeps one in
Smartschool), and feedback Skore does not let the user change (`can_edit`
false: no second feedback is added next to it). The library refuses both
too, right before the save, but with a `SmartschoolSkoreChangeRefusedError`
that cannot be told apart from its other refusals, and its result does not
say whether it created or changed the feedback; the server's own read tells
both (dartschool#158, removal tracked in #149).

Then the library reads the gradebook, the evaluation and the pupil's
feedback again and creates the user's feedback
(`POST /skore/api/v1/gradebook/feedback`) or changes its text
(`POST .../feedback/{id}`, its attachments sent back as they are). A refusal
of its checks (also when the feedback changed between the two reads) is
passed on with what to read again (`read_skore_feedback`,
`read_skore_gradebook`); a `SmartschoolSkoreError` from the save (Skore
refused it with a `4xx`, whose `title` and `detail` can quote the text, or a
read before it gave an answer the library cannot use) means nothing was
saved: the library's message goes to the log only, and the result says Skore
did not save it. A save Skore did not confirm
(`SmartschoolSkoreFeedbackSaveUnconfirmedError`) may or may not have gone
through: the result says to read the pupil's feedback with
`read_skore_feedback` and tell the user, and that calling the tool again
with the text is safe when it is not there: a change sends the whole text
again (`isUpdate`), and after a create the library reads first and changes
the feedback that create made rather than adding a second. A create is sent
once: a session Smartschool refuses for it is a
`SmartschoolSessionExpiredError` at once, not handled, and the session
repeats the call, which reads the pupil's feedback again first and creates
it once. A change is sent again by the library after a new login, as it
sends the whole text.

### How `save_skore_report_comment` works

It writes, changes or clears the course comment of one pupil on a report
period of a gradebook of Skore's current school year (`gradebook_id`,
`report_id`, `pupil_id`, and `text`, or `clear: true`; `current_comment`,
the comment it replaces; #171, `saveReportComment` and
`clearReportComment`, dartschool#195 and dartschool#203). One pupil per
call, as for feedback: each comment is personal and goes on a report, so the
user should read and confirm each one, and Claude Desktop's approval of each
call is that confirmation. A list would save no requests either (the library
writes one comment per call, each with its own checks and reads, and has no
list of its own), and it would leave a list half written when one pupil is
refused in between. Marked destructive, so Claude Desktop asks for approval
before every call, and idempotent: a comment that already is the text is not
sent again. Its description tells Claude, as `save_skore_feedback`'s does, to
read the pupil's comment with `read_skore_report` first, to show the pupil
(class number, name), the report, the comment now and the new text (or that
it will be cleared), to tell the user that the comment goes on the report
the pupil and their parents get, to name the owner of a shared gradebook,
and to call only after explicit confirmation. The text is plain text, sent
as the library sends it (trimmed, each line trimmed, no more than one empty
line in a row); a blank text, and a text with `clear`, are errors before
anything is sent.

The server reads the gradebook (its report periods and pupils,
`getGradebook`) and the report (`getReport`) before the library is asked,
and refuses in its own words, with nothing sent: a gradebook shared with the
user to read only (before it is read, see
[Gradebooks shared with the user](#gradebooks-shared-with-the-user)), an
unknown report or pupil, a closed report (before the report is read), a
report without course comments for the course, a pupil without a comment on
it, a comment Skore does not let the user change (closed for the pupil), a
text longer than the report allows (`commentMaxLength`, on the text as the
library sends it), and a course that is not on the report (see
[`read_skore_report`](#how-read_skore_report-works)). Skore keeps one course
comment per pupil, course and report, shared by the colleagues who give the
course, and does not say who wrote it. So the call names the comment it
replaces (`current_comment`, as `read_skore_report` gave it and the user saw
it; none for a pupil without one), and the server refuses, showing the
comment now, when Skore holds another one by then: a colleague's comment is
never overwritten unseen. Comments are compared with their white space
collapsed, as the library compares them (`sameReportComment`). A comment
that already is the text, or an empty one to clear, sends nothing; that is
also what a repeat of a call that saved finds.

Then the library reads Skore again (`getNavigation`, and `accessableList`
for a shared gradebook; `init` for the report periods; the report), checks
the same (`replacing` for the comment the call replaces), sends `saveType`
with the type `info` and reads the report again to confirm the text; it
never closes, unlocks, calculates or publishes a report. A refusal of its
checks (a comment changed between the two reads, say) is passed on with what
to read again (`read_skore_report`). A save Skore did not confirm
(`SmartschoolSkoreReportCommentSaveUnconfirmedError`) may or may not have
gone through: the result says to read the pupil's comment with
`read_skore_report` and tell the user, and that saving it again (or clearing
it again) is harmless, with the comment it shows as `current_comment`; the
library's message goes to the log only. The library sends the save again
itself after a new login, as it sends the whole text; when Smartschool
refuses the session even then, nothing was saved, and the session repeats
the call, which reads the comment again first.

### Gradebooks shared with the user

Gradebooks shared with the user (Skore's tab "Gedeeld", #167,
flutter_smartschool 0.4.0, dartschool#191), such as the behaviour gradebook
("Gedrag") of a class that its form teacher shared with the co-titularis,
work as the user's own, with these differences:

- `list_skore_gradebooks` lists them after the user's own, in a section of
  their own, each with its owner (name and user id) and whether it is
  shared to read and write or to read only; with none shared, it says
  nothing of them. They are read with the user's own
  (`getGradebookYear(includeShared: true)`: one more, small request,
  `accessableList`, next to the big `getNavigation`, and kept in memory with
  it for the session), not behind an option: a user does not think of a
  gradebook a colleague shared with them as another kind and would not know
  to ask for it, and the other tools need the list anyway to find a shared
  gradebook's id. `query` looks in them too.
- The other tools take a shared gradebook's id as an own one's
  (`SkoreGradebookYears` finds it among both, and says "their own or those
  colleagues shared with them" when it finds neither). The library opens it
  as Skore's web client does, in the name of its owner and restricted to
  it. Every result names the owner: its first line (`Its owner, ... (user
  id ...), shared it with the user to read and write`, or `to read only`),
  and the gradebook in every sentence of a write (`gradebook of 5WW2 for
  Gedrag (gradebook id 34980, owner ...)`). `read_skore_gradebook` says of
  one shared to read only that the user may not change it, whatever Skore
  answers. `list_skore_evaluations` lists no components for a shared
  gradebook: no evaluation is created in one.
- "The user's own feedback" is the logged-in user's, by the session's user
  id (`SkoreGradebooks.userId`; `teacherId == userId`, as the library keeps
  it), never the feedback of the gradebook's teacher, who is the owner of a
  shared gradebook. `read_skore_feedback` marks only the user's;
  `save_skore_feedback` changes only the user's, never the owner's, and
  creates the user's own next to it.
- `save_skore_feedback` and `save_skore_grades` save in a gradebook shared
  to read and write, with the same checks; their descriptions tell Claude
  to name the owner too when it asks the user to confirm. One shared to read
  only is refused in the server's own words, right after it is found and
  before it is read, with its owner to ask (`checkSkoreGradebookChangeable`):
  nothing is sent. The library refuses it too, also one Skore lists as
  shared to read only by the time of the save
  (`SmartschoolSkoreGradebookReadOnlyError`), which the server words the
  same way (`skoreReadOnlyGradebookRefusal`).
- `create_skore_evaluation` refuses any shared gradebook, also one shared
  to read and write, before it is read, as the library does: an evaluation
  is created only in one of the user's own gradebooks; its owner can create
  it.

### Checks before a new evaluation is saved

The library checks a new evaluation before it saves it (`saveEvaluation`)
and reads the period again afterwards to confirm it, and
`create_skore_evaluation` reports each outcome with what to do next:

- A check that refused the change (`SmartschoolSkoreChangeRefusedError`: a
  gradebook that is not one of the user's own of the current school year,
  nor one shared with them to write, a closed or read-only period, a date
  outside the school year, a course or component Skore does not offer) is
  passed on with the library's reason and what to read again to correct the
  call (`read_skore_gradebook`, `list_skore_evaluations`), and that nothing
  was changed. So is an answer the server cannot use before the save. A
  gradebook of an earlier school year (when it is in memory) or an unknown
  one is an error that says only a gradebook of the current school year can
  be changed, before the library is asked.
- A save Skore did not confirm
  (`SmartschoolSkoreEvaluationCreateUnconfirmedError`) may or may not have
  created the evaluation: the result says not to call the tool again, but
  to read the period with `list_skore_evaluations` and look for the title on
  that day (or the evaluation id, when Skore answered one), and tell the
  user.
- An evaluation that was created but that Skore shows as public anyway
  (`SmartschoolSkoreEvaluationPublicError`, not seen live) is reported as
  created, published or scheduled: the user must check its publication in
  Smartschool now, and Claude must not create it again. Nothing is sent to
  undo it: the library never touches a publication.

The save is sent once: the library never sends it again after logging in
again, and a session Smartschool refuses for it is a
`SmartschoolSessionExpiredError` at once (Skore did not handle it). The
session then repeats the call (`SmartschoolSession.run`), which reads the
gradebook again and saves once; an unconfirmed or public save is not a
refused session, so it is not repeated.

### Finding an evaluation

The library takes an evaluation as `getEvaluations` lists it, so a gradebook
tool that takes an `evaluation_id` looks it up in its period
(`findSkoreEvaluation`): with `period_id`, one `getEvaluations` for that
period; without it, the period Skore opens the gradebook on first, then the
others from the last to the first, until it is found, one request per
period. The error for an id that is not there names the periods read, and
says to take the id from `list_skore_evaluations`, with the `period_id` of
its period; with a `period_id`, that the evaluation is not in that period.
The evaluations are read again on every call, as grades change; the
gradebook's periods and pupils too (`getGradebook`, two requests), to check
the `period_id` and `pupil_id` before anything else is sent.

### The gradebooks of a school year

The library's methods take a gradebook as `getGradebookYear` reads it, and
that answer is big (some 270 KB for 22 gradebooks, 1.7 MB for 50). So the
gradebooks of a school year are read once per session and kept in memory
(`SkoreGradebookYears`), for every gradebook tool; a gradebook id that is
not in memory reads its school year again (without `workyear_id`: Skore's
current one, after looking in every school year read so far), and an id
that is not there either is an error that says to take it from
`list_skore_gradebooks`, with `workyear_id` for an earlier school year. A
read that failed is tried again on the next call. A `workyear_id` Skore does
not offer (Skore answers it with no gradebooks; the library refuses it with
an `ArgumentError`) is an error that passes on the school years Skore
offers.

Any `SmartschoolSkoreError` is an answer the server could not use (an error
page, another HTTP status, also a redirect, or data in a shape the library
does not know; also a feedback read Skore refuses, or feedback about another
pupil), reported with "try again in a moment" and, when it keeps happening,
to use Skore in Smartschool itself (`skoreGradebookUnusableAnswer`). The
library's message goes to the log only, as it can quote Skore's answer:
names, titles and feedback texts; for a redirect it names the target, by
path and module only. What Skore answers an account without gradebooks of
its own, such as a pupil's, was not captured, and the message does not
guess: its old remark that a pupil's account may get it too sent a teacher
the wrong way in #168.

### An expired session

A session Smartschool no longer accepts is not such an answer. Skore's
gradebook answers an RPC call in an expired session with `302 Location: /`
and an empty body (seen live, yvanvds/dartschool#192: the cause of #168,
where `init` of a gradebook was the first call after reusing a saved
session). flutter_smartschool 0.4.0 takes that for a refused session: it
logs in again and sends the call once more. Refused again, it is a
`SmartschoolSessionExpiredError`, which the session tries once more and then
reports as Smartschool not accepting the session, with "try again in a
moment". The fake Smartschool of the tests answers the gradebook's RPC calls
in a refused session that way (`FakeSmartschool.refusedPosts` records it), so
every test that lets the session expire before such a call goes through it.

### Helpers and tests

The gradebook helpers, for the user's own gradebooks
(`SkoreGradebookService`, no switch), live in `lib/src/skore/`, next to the
helpers of the [admin side](skore.md#helpers-and-tests) and apart from them.
In `skore_gradebook_access.dart`: `withSkoreGradebook`, which runs an action
with a `SkoreGradebookService` on the session and turns the library's errors
into `ToolError`s (`skoreGradebookToolError`, a sibling of `skoreToolError`
whose texts never speak of rights or "Skore-beheer": an `ArgumentError` for
an argument it knows, passed on with the tool's name of the argument and
what to correct; a user id the calls cannot be built from; an answer the
server cannot use, whose details go to the log only. The writes add their
own cases there: the change a check refused comes before the last one, and
the saves Skore did not confirm and a new evaluation that came back public,
which are not `SmartschoolSkoreError`s, come out for the write tools to
report); and `SkoreGradebookYears`, the gradebooks per school year kept in
memory per session (`read`), which finds a gradebook by its id (`find`, with
its school year) and reads the school year again for an id that is not in
memory. Next to them, the lookups by id every tool about a gradebook's
contents uses: `readSkoreGradebook` (find, then `getGradebook`: periods,
pupils, `writable`), `skoreGradebookPeriod` (a `period_id`, or the active
period; an unknown one is a `ToolError` that lists the periods),
`skoreGradebookPupil` (a `pupil_id`; an unknown one is a `ToolError`) and
`findSkoreEvaluation` (an `evaluation_id`, in its `period_id` or in every
period, active first, one `getEvaluations` per period; it returns the
period, the period's evaluations and the evaluation, with its publication
and grades). The arguments of `_arguments` are `workyearId`, `periodId`,
`pupilId` and `evaluation`.

In `skore_gradebook_format.dart`: one line per gradebook, period, pupil and
evaluation (`formatSkoreEvaluation`, its publication last,
`formatSkorePublication`), a gradebook in a sentence
(`formatSkoreGradebookTitle`) and in an error (`formatSkoreGradebookName`),
a period's state and name, an evaluation's averages, a grade, a feedback
text (`formatSkoreFeedback`), the school years, Skore's note on a period
(`skorePeriodNote`) and times in the time of this PC.

The tests run against a fake gradebook
(`test/support/fake_skore_gradebook.dart`, `FakeSmartschool.skoreGradebook`)
that answers `getNavigation`, `init`, `getGradebookContext` and
`getEvaluations` in the shape of dartschool's captures of #148 and #149, from
gradebooks per school year (`FakeSkoreOwnGradebook`, with periods, pupils,
whether it is writable or in coordinator mode, and evaluations per period:
`FakeSkoreEvaluation`, with its publication, its grades and its feedback per
pupil, `FakeSkoreFeedback`), with the school years Skore offers; a school
year it does not offer gets an empty tree, as live, and a period without
evaluations an empty `head` and the stream `1`. It also answers the feedback
reads of Skore's REST API (a `GET` of `/skore/api/v1/gradebook/feedback/...`,
in `FakeSmartschool`'s GET chain), recorded in `feedbackReads`, from the
evaluations' feedback; the fake account's platform is 12 (`12_345_0`). A
test can replace the answer to a method (`answers`) or to the feedback reads
(`feedbackAnswer`), or answer every call with an error page (`unusable`); it
answers any other RPC method with HTTP 501.

The writes in a gradebook (`create_skore_evaluation`, `save_skore_grades`,
`save_skore_feedback`, `save_skore_report_comment`) run with
`withSkoreGradebookWrite` in `skore_gradebook_access.dart`:
`withSkoreGradebook` with the reason of a change a check refused
(`SmartschoolSkoreChangeRefusedError`, before the last case of
`skoreGradebookToolError`) passed on with what to read again (`reread`,
`rereadSkoreGradebookContents` by default), and every `ToolError`, also one
of the write itself, ending in `nothingChangedInSkore`. A save Skore did not
confirm and a new evaluation that came back public are thrown as they are,
for the tool to report: the first with `skoreWriteNotConfirmed` of
`skore_writes.dart`. `skoreRefusalReason` (in `skore_format.dart`) takes the
library's method name and closing sentence off a refusal, for the Skore
tools and the gradebook tools alike.
`SkoreGradebookYears.findInCurrentYear` finds a gradebook of Skore's current
school year, the only one the library writes in, and `skoreDefaultComponent`
repeats the library's default component (dartschool#156, #147). The fake
gradebook answers the "new evaluation" dialog (`getNewEvalDialogBox`, the
gradebook's course; `getPosComponents`, a gradebook's `components`) and
carries out `saveEvaluation` as the live Skore did in dartschool#150: the
new evaluation is listed from then on in column A of its period, with what
was sent, under `nextEvaluationId`. `evaluationSaves` holds the parameters
of every `saveEvaluation` that reached it (also those `answers` answered,
which are not carried out); `saveAnswerLost` carries a save out and answers
it with HTTP 500; `onEvaluationSaved` changes how the new evaluation is
listed (public, or not at all).

A write into an evaluation (the grades, the feedback) first calls
`checkSkoreWritePublication` (in `skore_gradebook_access.dart`) with the
evaluation as the tool read it, what it writes and its name: for one that is
published or scheduled, without `allow_published`, a `ToolError` that says
what the pupils would see and that `allow_published: true` comes only after
the user said yes to exactly that (dartschool#157, #148).
`formatSkoreEvaluationName` (in `skore_gradebook_format.dart`) names an
evaluation in such a sentence. The fake gradebook carries out `saveGrade` as
the live Skore did in dartschool#151: a grade with a comma is kept with a
point, `""` clears it, and one above the max gets HTTP 500 and is not kept;
a save whose parameters are not the web client's for that cell gets HTTP
400. `gradeSaves` holds the parameters of every `saveGrade` that reached it;
`gradeSaveFails` answers the saves of some pupils with HTTP 500 without
carrying them out; `onGradeSaved` changes what Skore lists for a grade after
it was saved; and `beforeAnswer` sees every RPC call before it is answered,
to change the gradebooks between two reads. It carries out the feedback
`POST`s of Skore's REST API as the live Skore did in dartschool#152
(`_saveFeedback`): a create (`fakeSkoreFeedbackCreatePath`) adds the
teacher's feedback after the pupil's others, under a new fake UUID
(`nextFeedbackNumber`), also next to one of theirs (a create is not an
upsert); a change (`.../feedback/{id}`) replaces the text and sets
`changedAt` (`feedbackSavedAt`); both answer with the feedback. A body other
than the web client's (its keys in order, the user as the teacher, a pupil
and an evaluation of the gradebook, the attachments sent back as they are),
another content type or no `X-Requested-With` gets HTTP 400, a change of
feedback the pupil does not have HTTP 404, and one of another teacher's HTTP
403. `feedbackSaves` records every `POST` with its body and headers (the
tests check that none is about another teacher's feedback);
`feedbackSaveAnswer` answers them without carrying them out (a `4xx`);
`feedbackSaveAnswerLost` carries one out and answers it with HTTP 500; and
`onFeedbackSaved` changes what the feedback reads show after a save.

The report periods of a gradebook (#171) are `FakeSkoreReportPeriod`s in
`init`'s `reports` (`fakeSkoreReportR1D`, open, and `fakeSkoreReportR0`,
closed), and what a report shows for the course is a `FakeSkoreReport` per
report id (`reportContents`, `reportOf`: components with each pupil's result
and the class average, each pupil's comment, the pupils whose comment is
closed, the `length`; `fakeSkoreReport6EWI` for 6EWI's R1D). The fake
gradebook answers `getReportsResults` in the shape of dartschool's capture
of #195 (the comment's line breaks as U+205F, a row of another class along,
HTTP 404 "Course not found in source!" for a report with `courseOnReport`
false), and carries out `saveType` as the live Skore did in dartschool#201:
the text is the pupil's comment from then on, `""` clears it. A save other
than the web client's (another type than `info`, a closed report, a comment
closed for the pupil) gets HTTP 400. `reportCommentSaves` holds the
parameters of every `saveType`, and `onReportCommentSaved` changes what the
report shows after a save. In `skore_gradebook_access.dart`,
`skoreReportPeriod` finds a report period of a gradebook by its id, and
`readSkoreReport` reads a report, saying in its own words when the course is
not on it (#174); in `skore_gradebook_format.dart`,
`formatSkoreReportPeriod`, `formatSkoreReportName`,
`formatSkoreReportState`, `skoreReportNote` and
`formatSkoreReportCommentText` show a report and a comment.
