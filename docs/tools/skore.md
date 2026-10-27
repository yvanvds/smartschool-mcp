# Skore administration

[Back to the overview](../../README.md)

Skore's score management, as a Skore administrator has it: the classes of
the report models, which teachers give which course ("lesopdrachten"), and
who a gradebook is shared with. Opt-in: offered only when the switch
"Skore-beheer" is on (`SMARTSCHOOL_SKORE`), as these tools need rights most
teachers and all pupils lack. Your own gradebooks need no switch: see
[Gradebook](gradebook.md). Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_skore_classes`](#list_skore_classes) | Lists the classes of Skore's report models | No |
| [`list_skore_courses`](#list_skore_courses) | Lists a class's courses with their teachers | No |
| [`list_skore_teachers`](#list_skore_teachers) | Lists the teachers that can be assigned | No |
| [`list_skore_gradebook_shares`](#list_skore_gradebook_shares) | Lists a teacher's gradebooks and who they are shared with | No |
| [`add_skore_teacher`](#add_skore_teacher) | Assigns a teacher to a course | Yes, asks approval |
| [`replace_skore_teacher`](#replace_skore_teacher) | Gives an assignment another teacher | Yes, asks approval |
| [`share_skore_gradebook`](#share_skore_gradebook) | Shares a gradebook with teachers | Yes, asks approval |
| [`unshare_skore_gradebook`](#unshare_skore_gradebook) | Stops sharing a gradebook with teachers | Yes, asks approval |

## Tools

### `list_skore_classes`

Lists the classes of Skore's report models, one line each with its name,
its Skore class id, its group and its report model, optionally only those
whose name or group holds the words asked for.

### `list_skore_courses`

Lists the courses of one class with the teachers assigned to each, in
Skore's order and indented by depth: per course its label, id and code, and
its teachers with their assignment id (which is also the gradebook's id).
Courses that still need a teacher are marked "no teacher"; a group header
and a course with sub-courses need none of their own.

### `list_skore_teachers`

Lists the teachers Skore lets assign to a course, by name with their teacher
id, optionally only those whose name holds the words asked for.

### `list_skore_gradebook_shares`

Lists the gradebooks of one teacher, as Skore's "share gradebooks" manager
shows them: per gradebook its course, class and id, and the colleagues who
may read it or write in it.

### `add_skore_teacher`

Assigns a teacher to a course of a class: a new assignment, which holds all
pupils of the class; the teachers already on the course keep theirs. To give
a course another teacher, use `replace_skore_teacher`. Asks for approval;
Claude shows you the class, the course, its teachers now and the teacher to
assign first.

### `replace_skore_teacher`

Gives an assignment of a course another teacher: the assignment keeps its
id, and its gradebook stays. When the current teacher works with "Mijn
lesgroepen" for the course, nothing is saved: those groups are left to you
in Skore. Asks for approval, as `add_skore_teacher`.

### `share_skore_gradebook`

Shares a gradebook with 1 to 50 teachers, to read or to write: sharing with
all teachers of a class takes one approval. The teachers it is shared with
already keep their access, unless they are named with the other access.
Asks for approval: sharing gives colleagues access to pupils' scores.

### `unshare_skore_gradebook`

Stops sharing a gradebook with one or more teachers; the others keep their
access. Asks for approval.

## How it works

The Skore tools are offered only when the switch "Skore-beheer" is on (see
[Opt-in tools](../development.md#opt-in-tools)): they need the rights for
score management in Skore (Rapporten > Modellen and Puntenboeken), as a
Skore administrator has, and most teachers and all pupils lack them. The
first four read Skore with the library's `SkoreService` (dartschool#70,
dartschool#74) and change nothing; the last four assign teachers to courses
(dartschool#71) and share gradebooks (dartschool#74).

### How `list_skore_classes` works

It reads the classes with `getClasses`, one line per class with its name,
Skore class id, group and report model, in Skore's order. `query` keeps the
classes whose name or group holds every word (ignoring case and accents, as
`search_messages`), since a school has many classes. The class id is
Skore's own, not a planner id.

### How `list_skore_courses` works

It reads the courses of one class (`class_id`, from `list_skore_classes`)
with the teachers assigned to each, Skore's "lesopdrachten" (`getCourses`),
in Skore's order and indented by depth. Per row: its label, course id, code
and depth, and then its teachers with their teacher id and assignment id
(which is also the gradebook's id), or, without any, that it is a group
header (which cannot get a teacher), a course with sub-courses (which needs
no teacher of its own: its sub-courses carry the assignments, as a Skore
administrator confirmed in #100), or a course with no teacher. A row is a
course with sub-courses when the next row is deeper: the tree tells it, not
the labels. The first line counts the courses, those that still need a
teacher (no teacher and no sub-courses), and the group headers; the
description tells Claude that only the courses marked "no teacher" still
need one. Course codes are not unique within a class (a course and its
sub-course can share one), so the description tells Claude to name a course
by its id. An empty list means a class without a course structure or an
unknown id; the result says so.

### How `list_skore_teachers` works

It reads the teachers with `getTeachers`, by name with their teacher id (the
Smartschool user id), in Skore's order; `query` as for
`list_skore_classes`.

### How `list_skore_gradebook_shares` works

It reads the gradebooks of one teacher (`teacher_id`, the owner;
`getGradebookShares`), as Skore's "share gradebooks" manager shows them
(Puntenboeken), one line per gradebook in Skore's order: its course, class
and gradebook id, and its readers and writers by name, joined with
`getTeachers` (a teacher Skore no longer lists shows by teacher id only).
The gradebook id is the assignment id of `list_skore_courses`, and the owner
the teacher of that assignment. An empty list means a teacher without
gradebooks or an unknown id; the result says so.

### How `add_skore_teacher` works

It assigns a teacher (`teacher_id`, from `list_skore_teachers`) to a course
(`course_id`) of a class (`class_id`), with the library's `addTeacher`.
Marked destructive, not idempotent: Claude is told to read the class and
look up the teacher first, to show the user the class, the course's label,
its teachers now and the teacher to assign, and to wait for the user's
confirmation; that nothing needs to happen when the teacher is already on
the course; and to use `replace_skore_teacher`, not this tool, to give a
course another teacher. The result gives the assignment as saved: the
course's label, the class id, the teacher and the assignment id. See
[The writes on assignments](#the-writes-on-assignments).

### How `replace_skore_teacher` works

It gives an assignment (`assignment_id`, from `list_skore_courses`) another
teacher (`teacher_id`), with `replaceTeacher`. Marked destructive, not
idempotent, with the same confirmation. Before the save the library asks
Skore (`getMyGroups`) whether the current teacher works with "Mijn
lesgroepen" for the course; if so, nothing is saved
(`SmartschoolSkoreMyGroupsError`), and Claude is told to leave those groups
to the user in Skore: the library never deletes them (`explodeMyGroups`),
and the tool tries no other way; the message names that teacher, as the
library read them. The result also names the teacher replaced. See
[The writes on assignments](#the-writes-on-assignments).

### How `share_skore_gradebook` works

It shares a gradebook (`owner_id`, `gradebook_id`) with one or more teachers
(`teacher_ids`, 1 to 50) with `read` or `write` access (`access`), with
`shareGradebook`, once per teacher, one after the other. A teacher with the
other access moves to the access given. Marked destructive, and idempotent:
sharing again the same way saves nothing. Claude is told the typical flow
(the class, its courses, the assignment of the titularis, then the other
teachers of the class, all from `list_skore_courses`), to read the gradebook
with `list_skore_gradebook_shares` first, and to show the user the gradebook
(course and class), the teachers and the access and wait for the user's
confirmation. See [The writes on gradebooks](#the-writes-on-gradebooks).

### How `unshare_skore_gradebook` works

It stops sharing with `unshareGradebook`, likewise; a teacher Skore no
longer lists can still be taken off. Marked destructive and idempotent, with
the same confirmation. See
[The writes on gradebooks](#the-writes-on-gradebooks).

### The writes on gradebooks

For both writes on gradebooks, the tool first reads the teachers, to name
them: a gradebook gives its owner, readers and writers by id only. It then
changes the shares for one teacher after the other and stops at the first
that fails. The result says per teacher whether the gradebook was shared (or
unshared, with the access the teacher had), was already shared that way
(nothing saved), or was not, or not tried, followed by why it stopped and
the gradebook's readers and writers afterwards; it is an error when it
stopped. What each teacher had before, and whether a save was sent, come
from the library's result (`SkoreGradebookShareChange`, dartschool#103),
without a read of the tool's own. The tool names the gradebook (its course
and class) from the first result; when the save for the first teacher is not
confirmed, from the library's error, which carries the gradebook as it was
read before the save (`SmartschoolSkoreShareSaveUnconfirmedError`,
dartschool#120). So it names the gradebook by its id only when it stopped at
the first teacher before a save, and then gives no readers and writers
either.

Before each change the library reads the gradebooks (and, to share, the
teachers) again and refuses the owner among the teachers, a gradebook that
is not the owner's, and, to share, a teacher Skore does not list
(`SmartschoolSkoreChangeRefusedError`); the tool passes the reason on, and
tells Claude to read the gradebook again. The save (`saveShared`) holds the
complete readers and writers of that one gradebook, the ids as numbers, so
sending it again does not change the outcome: the library sends it again
after logging in again. It reads the gradebooks again after the save, so a
teacher reported as done is certain; a save that Skore or that read does not
confirm (`SmartschoolSkoreSaveUnconfirmedError`) is reported as maybe saved,
with what to look for in `list_skore_gradebook_shares`, and Claude is told
not to call the tool again for it. Sharing from a teacher's own account,
without the rights (Skore's `/SkoreGradebook`), is not offered: the library
does not support it.

### The writes on assignments

For both writes on assignments, the library reads the class (`getCourses`)
and the teachers (`getTeachers`) again and refuses, before saving, a course
that is not in the class or is a group header, an assignment that is not the
course's, a teacher already on the course (for a replace, its current one
too) and one Skore does not let assign (`SmartschoolSkoreChangeRefusedError`);
the tool passes the reason on, says that nothing was changed, and tells
Claude to read the class again. The save (`saveOwner`) is sent once, never
again after logging in again. A save that Skore does not confirm
(`SmartschoolSkoreSaveUnconfirmedError`: another answer, an error page, a
connection lost after it went out) is reported as maybe saved, with what to
look for in `list_skore_courses`, and Claude is told not to call the tool
again for it, as for a message whose send Smartschool did not confirm. A
session that Smartschool refused for the save means the save was not
carried out: the session repeats the call, which reads the class again, so a
teacher who is on the course by then is refused rather than added twice.

The writes return the assignment with the course as the library read it
before the save, and for a replace the assignment as it was
(`SkoreSavedAssignment`, dartschool#102), so the tools name the course and
the teacher replaced without a read of their own. A save that Skore does not
confirm returns nothing, but the library's error carries the same
(`SmartschoolSkoreAssignmentSaveUnconfirmedError`, dartschool#120): its
result names the course by its label, and for a replace the teacher the
assignment had, as the library read them before the save (a read afterwards
cannot tell what was there before a save that may have gone through).
Removing an assignment, choosing its pupils and Skore's import of
assignments are not offered.

### No rights, and other refusals

Skore refusing a request to the account (`SmartschoolSkoreAccessDeniedError`)
is reported as an account without the rights, with the part of Skore it was
refused, what rights are needed, and to ask the school's Smartschool
administrator for them or turn "Skore-beheer" off. Skore sends every request
of a teacher without the rights on to Smartschool's start page (seen live,
yvanvds/dartschool#91), never with an empty list, and the library reports
that from every call as that error (as it does HTTP 403). Any other
`SmartschoolSkoreError` is an answer the server could not use, and is
reported as such, with "try again in a moment"; the library's message goes
to the log only, as it can quote the page. From a write, each of these
errors also says that nothing was changed in Skore.

A read that Skore sends on to Smartschool's start page at `/` without a
query, its answer to a session it does not accept (once, the list of report
models right after a login with 2FA, #170), the library asks once more; sent
there again, it is a refused session (yvanvds/dartschool#194), which the
session tries once more and then reports as Smartschool not accepting the
session, with "try again in a moment". The library's login with 2FA opens
the start page after the 2FA step, as a browser does
(yvanvds/dartschool#192): until it was loaded once, Skore refused the new
session that way. What Skore answers a pupil, and an account with only one
of the two parts of the rights, was not captured.

### Helpers and tests

Skore helpers for later tools live in `lib/src/skore/`. In
`skore_access.dart`: `withSkore`, which runs an action with a `SkoreService`
on the session and turns Skore's errors into `ToolError`s
(`skoreToolError`: no rights, or an answer the server cannot use, whose
details go to the log only), and `checkSkoreAccess`, the access check of
`smartschool_status`; `skoreToolError` also passes on why a check refused a
change (with what to read again: the class, or for a gradebook
`rereadSkoreGradebook`), and says what to do about "Mijn lesgroepen". In
`skore_writes.dart`, for the tools that change Skore: `withSkoreWrite`,
which runs a write and adds to its `ToolError` that nothing was changed, and
`skoreWriteNotConfirmed` (and its text, `skoreNotConfirmed`), the result of
a save Skore did not confirm. In `skore_shares.dart`: `changeSkoreShares`,
which shares a gradebook with teachers or unshares it, one teacher after the
other, and the arguments' schemas. In `skore_format.dart`: one line per
class, course row, assignment, teacher and gradebook, a course or a teacher
in a sentence, and the `query` filter (`skoreMatches`). In
`skore_opt_in.dart`: the Skore tools behind their switch (`skoreOptIn`). The
helpers of the [gradebook tools](gradebook.md#helpers-and-tests) live next
to them.

The tests run against a fake Skore (`test/support/fake_skore.dart`) that
serves the endpoints `SkoreService` reads, in the shape of dartschool's
anonymised captures, with fake names; it can refuse an account without the
rights by sending the request on to the start page, as Skore did live
(dartschool#91), or with HTTP 403, for every request or only for some
services (`refusedPaths`), and answer with an error page instead of data
(`unusable`). It carries out the save of an assignment (`saveOwner`) and
answers `getMyGroups` as the live Skore did in dartschool#71; it gives a
teacher's gradebooks, one per assignment, with their shares (`getCourses` of
the gradebooks service), and carries out the save of their shares
(`saveShared`) as the live Skore did in dartschool#74. It can lose the answer
to a save, answer it with an error page, or (`saveShared`) answer it as done
without carrying it out, also for one save of several (`nextSaves`); it
answers any other RPC method with HTTP 501.
