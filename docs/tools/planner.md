# Planner

[Back to the overview](../../README.md)

Smartschool's planner: lessons, tests and tasks, in your own planner and in
those of classes, people and rooms. For everyone, without a switch; the
writes work in your own planner only. Planning a lesfiche is on the
[Lesfiches](lesfiches.md#plan_lesfiche) page. Tools that change something
follow the [shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`search_planners`](#search_planners) | Finds the planner of a class, person or room | No |
| [`list_planner`](#list_planner) | Lists what is planned in a period | No |
| [`read_planned_element`](#read_planned_element) | Reads one lesson or assignment in full | No |
| [`list_class_assignments`](#list_class_assignments) | Lists the tests and tasks of classes | No |
| [`plan_lesson`](#plan_lesson) | Fills an empty lesson hour with a lesson | Yes, asks approval |
| [`edit_planned_element`](#edit_planned_element) | Changes the name or info of a lesson or assignment | Yes, asks approval |
| [`clear_lesson`](#clear_lesson) | Empties a lesson hour again | Yes, asks approval |
| [`plan_assignment`](#plan_assignment) | Plans a test or task in one of your lesson hours | Yes, asks approval |
| [`trash_assignment`](#trash_assignment) | Moves an assignment to the planner's trash | Yes, asks approval |

## Tools

### `search_planners`

Finds the planner of a class, a person or a room by name, with its planner
id for `list_planner` and what the planner says about it: a class's full
name, the class a pupil is listed with. People are pupils and staff alike.

### `list_planner`

Lists what is planned in your own planner, or in that of a class, a person or
a room, in a period (by default today to 7 days ahead), optionally only some
kinds: lessons, assignments, empty lesson hours, meetings, lesson-free days,
other. Per day, one line per element: the time, the kind, name, course,
classes, organiser, rooms and id. At most 200 elements are shown: a class
planner holds a slot for every teacher of every hour, so narrow down the
period for a class.

### `read_planned_element`

Reads one lesson or assignment in full: its public and private info, its
labels, its attachments and weblinks (with when pupils see them), and for an
assignment when pupils see it, whether it was announced and its status.
Private info is hidden from pupils, but colleagues who can see the element
read it too.

### `list_class_assignments`

Lists the tests and tasks of 1 to 10 classes in a period (by default today to
4 weeks ahead), of everyone who plans them, per day: a weekday without any
reads `no assignments`, so free days show at a glance. It adds the class's
workload limit when the school set one, and the school's assignment types.
Choosing the moment is left to you, with Claude; `plan_assignment` plans the
test.

### `plan_lesson`

Fills an empty lesson hour of your own planner with a lesson: a name, and
optionally public info (what pupils see) and private info, as plain text.
Pupils of the hour's classes see the name and public info at once. Asks for
approval; Claude shows you every hour (date and time, class, course, name and
info) first, and one confirmation for a week's list is enough. The lesson
gets a new id, which the answer gives.

### `edit_planned_element`

Changes the name, the public info or the private info of a lesson or an
assignment of your own planner; an empty text empties an info. Asks for
approval. A colleague's element is refused.

### `clear_lesson`

Empties a lesson hour of your own planner again: the lesson, its name and
info are gone, and the hour is an empty lesson hour with a new id, which the
answer gives. Asks for approval.

### `plan_assignment`

Plans a test, a task or something to bring along in one of your own lesson
hours, for its classes (or some of them): a type of the school's (`KO`,
`Kleine Overhoring`), a name and optional info. It is due at the start of the
hour. Pupils see it at once; it is not announced. Asks for approval; Claude
checks the class's other tests with `list_class_assignments` first, and shows
you the classes, the date and hour, the type, the name and the info. The name
and info can change later with `edit_planned_element`; the date, type and
classes cannot.

### `trash_assignment`

Moves a test or task of your own planner to the planner's trash, where
Smartschool keeps it for 30 days and you can restore it in Smartschool
itself. One with a linked Skore evaluation is refused. Asks for approval.

## How it works

### How `search_planners` works

It searches with the planner's own search (the library's
`searchCalendars`). Each hit is listed with its kind (class, person, room),
its name, what the planner says about it (a class's full name, a
co-account's "Interimaris van …", the class a pupil is listed with) and its
planner id, like `group/4069_4256`, `user/4069_218_0` or
`location/4069_<id>`, which `list_planner` takes. People are pupils and staff
alike: the planner's answer does not tell them apart. A hit of another kind
is shown without a planner id.

### How `list_planner` works

The planner is `me`, the default, or a planner id; the period is `from` and
`until`; `types` takes lessons, assignments, empty lesson hours, meetings,
lesson-free days and other (other holds every kind not named, such as
excursions). The planner is asked only for lessons, assignments and empty
lesson hours; for any other kind every type is read and the kinds asked for
are kept (asking the planner for meetings or lesson-free days was never
tried live).

Per day, in date order, one line per element: the time (`10:20–11:10`, or
`08:30 (deadline)` for an assignment), the kind (lesson, an assignment with
its type, such as `KO Kleine Overhoring`, empty lesson hour, meeting,
lesson-free day, or the planner's type name of any other type, such as
`planned-excursions`), name, course, classes, organiser (left out in the
user's own planner), rooms and the element id. The header counts the
elements by those kinds. A lesson-free day can run over several days (the
autumn holiday seen live was one element of a week) and is listed on the day
it starts. A class planner holds a timetable slot for every teacher of every
hour (32 in one week of a class seen live), so at most 200 elements are
shown, with a note on how to narrow down; the request itself may span a
school year.

The header names a planner other than `me` from the elements read (the
class, person or room they name). When nothing is planned there and no
element read names it, the planner is looked up by its id with the library's
`getCalendar` (one more request, which only reads): the header names it as
the lookup does, and marks a person the planner counts as deleted. The
planner answers a room it does not have, and a group its search does not
offer, as an empty planner, without an error; when the lookup does not know
the id, the answer says so, and to check the id with `search_planners`. When
the lookup fails, a note says that the planner could not be named, with the
details in the server log. The planner answers a person or class it does not
have with HTTP 500, an error that does not say why: on a 500 for a planner
other than `me`, the planner is looked up the same way, and when the lookup
does not know the id either, the answer says that the planner's search
offers no class, person or room with that id, and to check it with
`search_planners`, rather than to try again. When the lookup names the
planner, or fails too, the planner's error stays.

### How `read_planned_element` works

It reads the element by its id: what its list line says, plus its public and
private info as plain text (through `htmlToText`, never raw HTML), its
labels, its attachments and weblinks (one line each, with when pupils see
it, counted from the lesson or the assignment), and for an assignment from
when pupils see it, whether it was announced and its status. Colleagues who
can see the element read its private info too (dartschool#84). The labels,
attachments and weblinks are the library's typed lists (dartschool#98; seen
live with a planned lesfiche's attachments and weblink, #117), and every
element is read by its type name, also one of a type the library does not
know (`getPlannedElement` with `typeName`, dartschool#99).

### How `list_class_assignments` works

`classes` takes 1 to 10 planner ids such as `group/4069_4256`; the period is
`from` and `until`. The assignments are read in one request (the library's
`getAssignmentsOfGroups`, the planner's workload view). Per day, in date
order, one line per assignment as `list_planner` writes it; a Saturday or
Sunday is listed only when something falls on it. When the school set a
workload limit for a class (`getWorkloadSchedule`, a limit of 0 or more),
the answer gives it with the planner's own figure for the days it is not 0,
such as `6A1: limit 2 per day (soft); 2026-10-06 is at 2`; the figures are
not interpreted (at the school seen live every class had `Geen limiet`, and
every weight was 0). The school's assignment types are read once per session
(`getAssignmentTypes`). The tool only reads.

### How `plan_lesson` works

The `hour` is an id `planned-placeholders/…` from `list_planner` with `me`;
the lesson takes a `name`, and optionally `public_info` and `private_info`,
written as plain text (the library's `planLesson`, dartschool#87). The
server turns the text into the HTML the planner's own editor makes
(`plainTextToHtml`: a `<p>` per paragraph, `<br />` per line break),
escaping `&`, `<` and `>`. Quotes stay as they are: the planner answers
`&quot;` and `&#39;` as quotes, and the library compares the info of an edit
literally, so an escaped quote made a saved edit unconfirmed (seen live in
#72; dartschool#155, until then #137).

The tool is marked destructive, so Claude Desktop asks for approval every
time, and Claude is told to show the user every hour and wait for the user's
confirmation first, with one call per hour. The library reads the hour
again and refuses, before sending anything, an hour that is not the user's
own, or that the planner does not let the user fill; an hour that was filled
since it was listed is gone under its id. It sends the fill once, never
again after logging in again. The result gives the lesson as saved and its
new id (the hour's id is gone), and says that `list_planner` can show the
old state for a few seconds while `read_planned_element` is up to date at
once.

### How `edit_planned_element` works

It changes `name`, `public_info` and/or `private_info` (plain text, as
`plan_lesson`), by the element's id (`renameElement`, `changePublicInfo`,
`changePrivateInfo`, in that order). Marked destructive and idempotent: each
change sets a value, and the library sends nothing for a value the element
already has. The library refuses a colleague's element, or a change the
planner does not allow, before sending it. When one change fails after
another was saved, the answer says which were saved.

### How `clear_lesson` works

It empties the hour with `clearLesson`. Marked destructive. The library
refuses a colleague's lesson, and a lesson the planner lets the user trash
or delete (one outside the timetable, which it does not clear), and sends
the clear once.

### How `plan_assignment` works

It plans the assignment in `hour` (an empty lesson hour or a lesson from
`list_planner` with `me`) with the library's `planAssignment`
(dartschool#89): of a `type`, by abbreviation or name, matched against the
school's types (read once per session; one that matches none is an error
that lists them), with a `name` and optionally `public_info` and
`private_info` (plain text, as `plan_lesson`). The server reads the hour's
detail and takes from it the classes (all of them, or those `classes` names,
by name or planner id; a class that is not the hour's is an error), the
course (the first), the rooms and the period: the assignment is due at the
start of the hour and runs to its end, and the hour itself stays as it is.
The library's create takes no hour, so the server refuses an hour that is
not the user's own, and one without classes or a course, before sending
anything. Smartschool's "aankondigen" is not offered.

Marked destructive, not idempotent: Claude is told to check the class's
other tests with `list_class_assignments` first, to show the user the
classes, the date and hour, the type, the name and the info, and to wait for
the user's confirmation. The library checks the type against the school's
types again; when the school no longer has it (the types changed since the
session read them), the error lists the types that check read (the
library's refusal carries them, dartschool#119), and every tool on the
session takes them, without reading them again. The library sends the
create (`POST planned-assignments/blanco?waitForRefresh=true`, answered
`201`) once. The result gives the assignment as saved, with its id.

### How `trash_assignment` works

It moves the assignment (`id`) with `trashAssignment` (dartschool#89). The
tool restores nothing and never deletes for good. Marked destructive, not
idempotent; Claude is told to say that it can be restored. The library reads
the assignment again and refuses, before sending anything, a colleague's
assignment, one the planner does not let the user trash (`canUserTrash`) and
one with a linked Skore evaluation; it sends the trash once, and confirms it
by reading the assignment again (the planner answers `404`).

### The planner writes

For the six planner writes (`plan_lesson`, `edit_planned_element`,
`clear_lesson`, `plan_lesfiche`, `plan_assignment`, `trash_assignment`), a
write that went out without the planner confirming it
(`SmartschoolPlannerSaveUnconfirmedError`) is reported as maybe saved, with
what to read to check it, and Claude is told not to call the tool again for
it, as for a message whose send Smartschool did not confirm (for a new
assignment: the class's assignments, with `list_class_assignments`). A
session that Smartschool refused for a fill, a clear, a create or a trash
means the write was not carried out: the session repeats the call, which
reads the element again (a lesson hour filled meanwhile is gone, so nothing
is sent).

### Helpers and tests

Planner helpers for later tools live in `lib/src/planner/` (the helpers of
the Lesfiches module live there too: see [Lesfiches](lesfiches.md#helpers-and-tests)).
In `planner_access.dart`: `withPlanner`, which runs an action on the session
and turns the planner's errors into `ToolError`s (`plannerToolError`: an
element that is gone or got a new id, an answer the server cannot use of the
planner or of the Lesfiches module, whose details go to the log only, and a
request the library refused before sending it), and `withPlannerClient`, the
same with the client itself, for a tool that also needs the Lesfiches
module; the planner ids (`PlannerRef`, `me` or `user/…`, `group/…`,
`location/…`, and `formatPlannerId`); the compound element id
`<plannedElementType>/<platformId>/<id>` (`PlannedElementRef`, which also
reads an element's detail); the `classes` argument, 1 to a maximum of class
planner ids (`classPlannersArgument`); the `from` and `until` arguments with
a default period (`plannerPeriodArguments`); and the school's assignment
types, read once per session (`AssignmentTypes.of`), and replaced by those
the library's check read when it refused a type the school no longer has
(`replace`).

In `planner_format.dart`: dates and times in the time of this PC, a period
(`formatPlannerPeriod`), the kind and time of an element, an assignment type
(`formatAssignmentType`), one line per element (`formatElementLine`), an
element in a few words for a write's result (`formatElementSummary`),
elements per day (`elementsByDay`) and an element's detail
(`formatElementDetail`).

In `planner_writes.dart`, for the tools that change the planner: the info
text Claude writes as HTML (`plainTextToHtml`), the `hour` argument
(`emptyHourArgument`), the fill of an empty lesson hour with its result
(`fillLessonHour`, which takes the library call that fills, so a lesfiche
can be planned the same way), the lesson hour, the classes and the type of a
new assignment (`lessonHourArgument`, `lessonHourClassesArgument`,
`lessonHourClasses`, `assignmentTypeArgument`), `withPlannerWrite`
(`withPlanner`, with a note that nothing changed on an error), and the
result of a write the planner did not confirm (`plannerWriteNotConfirmed`).
`plannerToolError` says why the library refused a write
(`SmartschoolPlannerWriteRefusedError`) in the tools' own words, from its
reason (`PlannerWriteRefusalReason`, dartschool#100): the element by its
kind, name, day, time, classes and course, who organises a colleague's
element, which capability the planner does not set, and what to do next
(`list_planner`, `list_lesfiches`, or Smartschool itself). The library's
message, written for a developer, goes to the log only. Its switch has no
default, so a reason a later version of the library adds fails the build.

The tests run against a fake planner (`test/support/fake_planner.dart`),
built from dartschool's anonymised captures of the live planner and its
workload view, which carries out the writes of dartschool#87 (fill, rename,
change of the info, clear), the plan of a lesfiche of dartschool#88, and the
create and the trash of an assignment of dartschool#89 as the live planner
did. The same fake serves the Lesfiches module (see
[Lesfiches](lesfiches.md#helpers-and-tests)).
