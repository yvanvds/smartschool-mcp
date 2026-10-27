# Lesfiches

[Back to the overview](../../README.md)

The Lesfiches module: your own library of lesson and assignment lesfiches,
with their info, weblinks and attachments, and planning them as lessons. For
everyone, without a switch. Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_lesfiches`](#list_lesfiches) | Lists your lesfiches, by label and name | No |
| [`read_lesfiche`](#read_lesfiche) | Reads one lesfiche in full | No |
| [`read_lesfiche_attachment`](#read_lesfiche_attachment) | Returns the text of an attachment, or an image | No |
| [`save_lesfiche_attachment`](#save_lesfiche_attachment) | Saves an attachment into the download folder | No, saves a file on this PC |
| [`create_lesfiche`](#create_lesfiche) | Makes a lesfiche in your own library | Yes, asks approval |
| [`edit_lesfiche`](#edit_lesfiche) | Changes a lesfiche's name, icon, info, courses or visibility | Yes, asks approval |
| [`set_lesfiche_weblink`](#set_lesfiche_weblink) | Adds or changes a weblink | Yes, asks approval |
| [`remove_lesfiche_weblink`](#remove_lesfiche_weblink) | Removes a weblink | Yes, asks approval |
| [`add_lesfiche_attachments`](#add_lesfiche_attachments) | Adds files from this PC | Yes, asks approval |
| [`set_lesfiche_attachment_visibility`](#set_lesfiche_attachment_visibility) | Sets when pupils see an attachment | Yes, asks approval |
| [`remove_lesfiche_attachment`](#remove_lesfiche_attachment) | Removes an attachment | Yes, asks approval |
| [`trash_lesfiches`](#trash_lesfiches) | Moves lesfiches to the module's trash | Yes, asks approval |
| [`plan_lesfiche`](#plan_lesfiche) | Plans a lesfiche as a lesson in an empty lesson hour | Yes, asks approval |

## Tools

### `list_lesfiches`

Lists your lesfiches: lesson lesfiches by default, or assignments, or all,
filtered by labels (the whole label, such as `JAAR 6`) and by words in the
name. One line each, by name with the numbers in order (`Les 2` before
`Les 10`): kind, name, labels, courses, visible or hidden in the module, the
day it was last changed and its id. A label filter that matches nothing
lists the labels there are. At most 200 lines.

### `read_lesfiche`

Reads one lesfiche in full: its kind, name, icon, labels and courses,
whether it is visible in the module, its weblinks and attachments (each with
when pupils see it) and its public and private info. A lesfiche in the trash
is still read.

### `read_lesfiche_attachment`

Opens one attachment of a lesfiche, by its number in `read_lesfiche` or its
file name, and returns its text, or an image, as
[`read_intradesk_file`](intradesk.md#read_intradesk_file) does. Up to 25 MB.

### `save_lesfiche_attachment`

Saves one attachment of a lesfiche into your
[download folder](../development.md#saving-files) and returns its full path,
name and size.

### `create_lesfiche`

Makes a lesfiche in your own library ("Mijn lesfiches"): a lesson, or an
assignment of one of the school's types, with a name and optionally public
and private info, courses, weblinks, files from this PC and an icon. For each
weblink and file you choose when pupils see it: always, never, from the
start or the end of the lesson it is planned in, or 1 to 14 days after its
end. Labels are set in the module itself. Your library is private until you
plan a lesson from the lesfiche, but the tool still asks for approval:
Claude shows you everything first and makes the lesfiche once. A name that
is taken is kept (the module makes a second lesfiche), and the answer names
the others.

### `edit_lesfiche`

Changes one lesfiche of your own library: its name, icon, public or private
info, courses, or whether it is visible in the module (a hidden lesfiche is
still listed and can still be planned). An info is replaced whole, and an
empty text empties it; the courses given replace all of them. Asks for
approval. A lesfiche in the trash cannot be changed: restore it in the
module first. Whether a lesson planned from the lesfiche earlier changes
with it has not been checked.

### `set_lesfiche_weblink`

Adds a weblink to a lesfiche, or changes one: its name, its address, its
icon and when pupils see it. Asks for approval. A second add adds a second
weblink.

### `remove_lesfiche_weblink`

Removes one weblink of a lesfiche. Asks for approval.

### `add_lesfiche_attachments`

Adds 1 to 10 files from this PC to a lesfiche, each with when pupils see
it. Asks for approval; Claude shows you every file with its size first. A
second call adds the files a second time.

### `set_lesfiche_attachment_visibility`

Sets when pupils see one attachment of a lesfiche, and says what it was
before. Asks for approval.

### `remove_lesfiche_attachment`

Removes one attachment of a lesfiche, and says which file with its size;
`save_lesfiche_attachment` keeps a copy first. Asks for approval.

### `trash_lesfiches`

Moves 1 to 20 lesfiches, lessons and assignments together, to the module's
trash, after which `list_lesfiches` no longer lists them. A move, not a
deletion: you restore a lesfiche from the trash in the module itself. A
lesson planned from a lesfiche earlier stays in the planner. Asks for
approval; Claude shows you each lesfiche by name and kind first.

### `plan_lesfiche`

Plans a lesson lesfiche into an empty lesson hour of your own planner: the
lesson is named after the lesfiche and takes over its public and private
info, labels and goals, attachments and weblinks, each attachment and
weblink with the visibility it has in the lesfiche. The lesson keeps the
course of the hour, not the lesfiche's. It works as [`plan_lesson`](planner.md#plan_lesson):
asks for approval, after Claude shows you which lesfiche goes into which
hour. An assignment lesfiche cannot be planned.

## How it works

### How `list_lesfiches` works

It reads the user's lesfiches in the Lesfiches module (the library's
`LessonContentService.getItems`, dartschool#88) in full on every call: lesson
lesfiches by default, or assignments or all (`type`), with every `label`
given (the whole label, case-insensitive, such as `JAAR 6` and
`TRIMESTER 1`) and every word of `query` in the name. The kind is an
assignment with its type; the day it was last changed is read from the
module's dates, which have no offset: Smartschool time. The courses are
named as the library names them (`LessonContentCourse.name`,
dartschool#101), after the school's course list (one request more, when any
lesfiche has a course); a course the list does not name is an "unnamed
course". When the course list cannot be read, the library still gives the
lesfiches (`SmartschoolLessonContentCourseListError.items`,
dartschool#118), and only the number of courses is shown, with a note when a
lesfiche listed has a course. At most 200 lines, with a note to narrow the
list. An answer of the module the server cannot use
(`SmartschoolLessonContentError`) is "the Lesfiches module gave an answer
the server could not use", with the details in the log only.

### How `read_lesfiche` works

It takes `lesfiche`, an id from `list_lesfiches`, and `type`: `lesson`, the
default, or `assignment`, and reads it with the library's
`LessonContentService.getDetailById` (dartschool#129), at `lessons/{id}` or
`assignments/{id}`. One field per line: kind (an assignment with its type),
name, icon, labels, courses (named as `list_lesfiches` names them; when the
course list cannot be read, `SmartschoolLessonContentCourseListError.items`
holds the detail, and only the number of courses is shown, with a note),
visible or hidden in the module, the weblinks (name, address, icon, when
pupils see it, id) and the attachments (numbered, with file name, size,
type, when pupils see it, id); then the public and private info as plain
text (through `htmlToText`, as `read_planned_element`). When pupils see a
weblink or an attachment (`LessonContentVisibility`) is worded from the
lesson the lesfiche is planned in: always, never, from its start, from its
end, or a number of days after its end; an option the library does not
know, by the module's name for it. Weblinks of publishers and deeplinks are
counted, not shown. The module answers a made-up id, and a lesfiche asked
for as the other kind, with `404` (`SmartschoolLessonContentNotFoundError`),
and an id that is not a UUID with a bare `500`, so that one is not sent:
both say to take the id and the kind from `list_lesfiches`. A lesfiche in
the trash is still answered, as live. Its description points to
`edit_lesfiche` and the tools that change the weblinks and attachments, by
the ids it shows, and to `trash_lesfiches`.

### How `read_lesfiche_attachment` works

It takes `lesfiche`, `type`, and `attachment`: its number in
`read_lesfiche`, or its file name, as `save_message_attachment` takes it; a
name that two attachments have, which the module allows, asks for the
number. It returns the text or image as `read_intradesk_file` does (see
[Reading Intradesk files](../development.md#reading-intradesk-files)), with
the library's `downloadAttachmentStream`. It reads the lesfiche first,
without the course names (one request less), and refuses an attachment that
is larger than 25 MB by the size the lesfiche gives, or of a type that
cannot be read by its name, without downloading it. The library sends the
download without `Accept: application/json`: with it, Smartschool answered
`503` (seen live).

### How `save_lesfiche_attachment` works

The attachment is named as `read_lesfiche_attachment` names it, and saved as
`save_message_attachment` saves one (see
[Saving files](../development.md#saving-files)).

### How `create_lesfiche` works

It makes the lesfiche in one create, as the web client makes one, with the
library's `LessonContentService.createLesson` or `createAssignment`
(dartschool#129): a `name` (at most 255 characters), a `type` (`lesson`, the
default, or `assignment` with `assignment_type`, one of the school's types
by abbreviation or name, matched as `plan_assignment` matches its `type`),
and optionally `public_info` and `private_info` (plain text, as
`plan_lesson`), `courses` (each by its name as the tools show it, or by its
id, found in the school's course list: one the list does not have is an
error that lists the names, and a name two courses have one that gives
their ids), `weblinks` (`{name, url, visibility?}`, the address as the web
client sends it, `normalizeWeblinkUrl`; one it refuses is refused before
sending), `attachments` (`{path, visibility?}`, 1 to 10 files from this PC,
checked as `upload_intradesk_files` checks them, see
[Uploading files](../development.md#uploading-files)) and `icon` (the web
client's by default: `document_observation` for a lesson,
`flags_red_yellow` for an assignment). A visibility is `always` (the
default), `never`, `at_start`, `at_end` or `after_end:N`, N from 1 to 14
days after the end of the lesson the lesfiche is planned in
(`LessonContentVisibility`).

The own library is private to the teacher until a lesson is planned from the
lesfiche, but the tool is still marked destructive (and not idempotent): it
is a write that Claude is told to show the user first (kind, name, courses,
info, each weblink, each file with its size, and when pupils see them) and
to make once per lesfiche after the user's confirmation, a second call makes
a second lesfiche, and it sends files from this PC; Claude Desktop and Codex
ask for approval only for a tool marked destructive.

Before sending, it reads the user's lesfiches (for the note on namesakes),
the course list for the courses, and for an assignment the school's
types (read once per session). The library checks the courses and the type
again, uploads the files into a new upload directory, sends the create once
(`POST lessons/` or `assignments/`, answered `201` with the id only) and
reads the lesfiche back. When Smartschool refuses the session for the
create, the session repeats the call, and the library logs in again before
the repeat's first request (dartschool#134). A name that is taken is kept
(the module makes a second lesfiche, seen live), and the result names the
other lesfiches of that name and kind. The result is the lesfiche as
`read_lesfiche` shows it, with its id for `plan_lesfiche` (a lesson),
`read_lesfiche` and `edit_lesfiche`, the tools that change its weblinks and
attachments, and `trash_lesfiches` to undo it. Labels are not in the
library: the description says the user sets them in the module.

A refusal by the module (a bare `400`) and a file Smartschool's upload step
refuses (in Smartschool's words) say that no lesfiche was made; a create the
module does not confirm is reported as maybe made, with `list_lesfiches` to
check it, and a lesfiche that was made but whose read-back failed or did not
show everything sent (`SmartschoolLessonContentSaveUnconfirmedError` with
its `lessonContentId`) as made, with its id and `read_lesfiche` (what is
missing is added with `edit_lesfiche`, `set_lesfiche_weblink` or
`add_lesfiche_attachments`); for both, Claude is told not to call the tool
again. When the school's types changed since the session read them, the
library refuses the type before sending, and the error lists the types as
they are now, which every tool on the session takes from then on.

### How `edit_lesfiche` works

It changes one lesfiche of the user's own library (`lesfiche` and `type`, as
`read_lesfiche` takes them) with the library's edits (dartschool#129), one
per field given, in this order: `name` (`rename`, at most 255 characters),
`icon` (`changeIcon`), `public_info` and `private_info` (`changePublicInfo`,
`changePrivateInfo`; plain text, as `edit_planned_element`: it replaces the
whole info, and an empty text empties it), `courses` (`changeCourses`, by
name or id as `create_lesfiche` takes them, in place of all its courses; an
empty list removes them) and `visible` (`setVisible`: shown or hidden in the
module). Marked destructive (as `create_lesfiche`, for Claude Desktop and
Codex to ask approval) and idempotent: each edit sets a value. Claude shows
the lesfiche and what changes, and calls after the user's confirmation.

The tool reads the lesfiche first (the edits take it as read) and, for
`courses`, the school's course list, so that an unknown course is refused
before any edit; the library checks the courses again. It stops at the
first edit that fails, and says which fields were changed before it and
which were not sent, as `edit_planned_element` does; a field that already
had the value given is sent all the same, and the result says so. The edits
answer with the whole lesfiche, but only `changeCourses` names its courses,
so the result reads the lesfiche once more at the end and gives it as
`read_lesfiche` shows it (`lesficheChangedResult`, in a session action of
its own); when that read fails, the result says what changed and to read it
with `read_lesfiche`.

A lesfiche in the trash is still read, but its edits are answered `404`
(seen live, `SmartschoolLessonContentNotFoundError`): the error says that it
is in the trash or no longer exists, and that the user restores it in the
module; an id or kind that is wrong is the `404` of the read before (take
them from `list_lesfiches`). An edit the module does not confirm
(`SmartschoolLessonContentSaveUnconfirmedError`) is reported as maybe saved,
with what was changed before it and `read_lesfiche` to check it. The library
retries an edit after logging in again, as a read. Whether a lesson planned
from the lesfiche earlier changes with it has not been checked (#117): the
descriptions of these tools do not promise it.

### How `set_lesfiche_weblink` works

It adds a weblink (`addWeblink`), or, with `weblink_id` (as `read_lesfiche`
shows it), changes one (`changeWeblink`): `name`, `url` (sent as the web
client sends it, as for `create_lesfiche`), and optionally `icon` (`earth`
for a new one) and `visibility` (as for `create_lesfiche`). A change sends
every value: the icon and the visibility that are not given stay as the
weblink has them. Marked destructive, and not idempotent. The tool reads the
lesfiche first, in the session action of the write: the library takes it as
read, and a weblink id the lesfiche does not have is refused before sending
(with its weblinks and their ids). The library sends an add once only, never
again after logging in again: when Smartschool refuses the session for it,
the session repeats the call, and the library logs in again before the
repeat's first request (dartschool#134). The result says what was added or
changed, with the weblink's id, and gives the lesfiche as `read_lesfiche`
shows it. A refusal by the module (a bare `400`) says that nothing changed;
an add the module does not confirm is maybe added, with `read_lesfiche` to
check it and not to call again; a `404` is the trash, as for
`edit_lesfiche`, or a weblink removed meanwhile.

### How `remove_lesfiche_weblink` works

It removes the weblink (`weblink_id`) with `removeWeblink` (a `DELETE`,
answered `204`). Marked destructive and idempotent. It reads the lesfiche
first and refuses a weblink id it does not have before sending; the result
names the weblink removed and gives the lesfiche. A removal the module does
not confirm is maybe removed, with `read_lesfiche` to check it.

### How `add_lesfiche_attachments` works

It adds the files (`attachments`, `{path, visibility?}`, 1 to 10, checked as
for `create_lesfiche`, see [Uploading files](../development.md#uploading-files))
with `addAttachments`: the library reads the lesfiche, uploads the files
into a new upload directory, has the module take them once (never again
after logging in again), and then sets each visibility other than `always`
(`changeAttachmentVisibility`): the module gives every new attachment
`always`, and ignores the visibility sent with them (seen live). Marked
destructive, and not idempotent. The tool reads the lesfiche first in the
session action. When Smartschool refuses the session for the take, the
session repeats the call, and the library logs in again before the repeat's
first request, as for an add of `set_lesfiche_weblink` (dartschool#134). The
result lists the attachments added with their ids, notes a name the
lesfiche had already (the module keeps both), and gives the lesfiche.

A file the upload step refuses (in Smartschool's words), a refusal and a
`404` say that nothing changed. When the module took the files and only
setting a visibility failed (`SmartschoolLessonContentVisibilityNotSetError`,
dartschool#135, #126), the result is an error that lists the attachments
added, with their ids and their visibility as far as the library knows, says
why the visibility was not set (refused: not set; not confirmed: maybe set;
the session refused: not set), and gives each visibility not set (that one,
and those after it, which the library did not try) as a call of
`set_lesfiche_attachment_visibility`, without reading the lesfiche: the
files are on it, so not to call the tool again. A take the module does not
confirm (any other `SmartschoolLessonContentSaveUnconfirmedError`) says that
the files may or may not have been added, or added with `always`, and not to
call again but to read the lesfiche and set a visibility with
`set_lesfiche_attachment_visibility`.

### How `set_lesfiche_attachment_visibility` works

It sets the visibility of one attachment (`attachment_id`, as
`read_lesfiche` shows it, and `visibility`) with
`changeAttachmentVisibility`. Marked destructive and idempotent. It reads the
lesfiche first and refuses an attachment id it does not have before
sending; the result says what the visibility was before, and gives the
lesfiche.

### How `remove_lesfiche_attachment` works

It removes the attachment (`attachment_id`) with `removeAttachment` (a
`DELETE`, answered `204`). Marked destructive and idempotent; the
description points to `save_lesfiche_attachment` to keep a copy. It reads
the lesfiche first and refuses an attachment id it does not have before
sending; the result names the file removed with its size, and gives the
lesfiche.

### How `trash_lesfiches` works

It moves the lesfiches (`lesfiches`, 1 to 20 ids from `list_lesfiches`) with
the library's `trash` (dartschool#129): one
`POST lesson-content/trash/bulk` for all of them, after which
`list_lesfiches` no longer lists them (their detail is still read). The
library takes each lesfiche as listed, with its kind and platform, so the
tool reads the list first (`getItems`, without the course names), in the
session action of the move, and matches the ids (ignoring case, each once);
an id that names no listed lesfiche is refused before anything is sent,
with a note that a lesfiche in the trash is not listed, and so is a lesfiche
of a kind the library cannot write. The library neither restores nor deletes
for good (`delete/bulk` is left out on purpose). A lesson planned from a
lesfiche earlier stays in the planner, which copied the lesfiche (its info,
attachments and weblinks, #117); the description says so.

Marked destructive, for Claude Desktop and Codex to ask approval: Claude
shows each lesfiche by name and kind, and calls once after the user's
confirmation. Idempotent, as `remove_lesfiche_attachment`: a second call
finds the lesfiches no longer listed and sends nothing. The result lists the
lesfiches moved, one line each as `list_lesfiches` shows them (their courses
counted). The library retries the move after logging in again, as a read.
The module answers the move of a lesfiche that is in the trash already with
a bare `500` (seen live; it was moved there after the tool read the list),
and an answer whose `exceptions` are not empty is not confirmed either
(`SmartschoolLessonContentSaveUnconfirmedError`): the result says that some
or all of them may or may not have been moved, and to check with
`list_lesfiches` which are still listed. A refusal by the module (`400` to
`499`) says that none was moved.

### How `plan_lesfiche` works

It plans the lesfiche (`lesfiche`, an id from `list_lesfiches`) into `hour`,
as `plan_lesson` takes it, with the library's `planLessonContent`
(dartschool#88): the planner names the lesson after the lesfiche and takes
over its content. Seen live: its labels and goals (dartschool#88), and its
public and private info, attachments and weblinks, each attachment and
weblink with the visibility it has in the lesfiche (#117: one from the start
of the lesson, one from its end, a weblink always, as the web client
showed). The description says what is copied. It works as `plan_lesson`
does: marked destructive, Claude shows the mapping of lesfiches onto hours
(date and time, class, course, lesfiche) and plans after the user's
confirmation, one call per hour, in order; the result gives the lesson as
saved and its new id. The library reads the lesfiches before it plans and
refuses, before sending anything, an id the user has no lesfiche with and an
assignment lesfiche; the tool says so in its own words and points to
`list_lesfiches`. A hidden lesfiche is planned like any other. Its
description points to `create_lesfiche` for a lesfiche that does not exist
yet. It is one of the planner writes, which report a write the planner did
not confirm as the others do (see
[The planner writes](planner.md#the-planner-writes)).

### Helpers and tests

The helpers of the Lesfiches module live next to the planner's, in
`lib/src/planner/` (see [Planner](planner.md#helpers-and-tests)). In
`lesfiches.dart`: the kinds `list_lesfiches` lists (`LesficheKind`), the
`lesfiche` argument (`lesficheArgument`), the filters (`lesficheMatches`),
the order of the names (`compareLesficheNames`), one line per lesfiche with
its courses as the library names them (`formatLesficheLine`), and the notes
on courses the course list does not name or could not name
(`unnamedLesficheCourseNote`, `lesficheCourseListNote`).

In `lesfiche_detail.dart`, one lesfiche in full, for `read_lesfiche` and the
tools that make or change a lesfiche, which give it back in the same form:
the `type` argument of a tool that takes one lesfiche (`lesficheTypeSchema`,
`lesficheTypeArgument`), the read of its detail (`readLesficheDetail`, which
keeps the detail when the course list fails and turns a `404` into "take the
id and the kind from `list_lesfiches`", `lesficheNotFound`), the lesfiche as
text (`formatLesficheDetail`, with `formatLesficheWeblink`,
`formatLesficheAttachment` and `formatLesficheVisibility`, the wording of a
`LessonContentVisibility`), the `visibility` of a weblink or an attachment
that a write takes (`lesficheVisibilityArgument`,
`lesficheVisibilitySchema`, `lesficheVisibilityValues`: `always`, `never`,
`at_start`, `at_end`, `after_end:N`), the lesfiche in a few words
(`lesficheTitle`, `lesficheKindName`), and the `attachment` argument of the
tools that read or save one (`lesficheAttachmentSchema`,
`lesficheAttachmentArgument`, `pickLesficheAttachment`,
`findLesficheAttachment`, `lesficheAttachmentTitle`).

In `lesfiche_writes.dart`, for the tools that make or change a lesfiche or
move it to the trash: the `name`, `courses`, `weblinks` and `attachments`
arguments, checked before anything is sent (`lesficheNameArgument`;
`lesficheCoursesArgument` with `lesficheCourses`, which finds them by id or
name in the school's course list; `lesficheWeblinksArgument` with
`lesficheWeblinkArgument`; `lesficheAttachmentsArgument`,
`{path, visibility?}` through the local-file helper, with
`lesficheAttachments`; and their schemas), the weblink or attachment a tool
names by its id (`lesfichePartIdArgument`, `lesficheWeblinkById`,
`lesficheAttachmentById`), `withLesficheWrite` (the session runner for a
write, with the library's errors as `ToolError`s that say nothing was made
or changed, `lesficheWriteToolError`; a `404` of a write says that the
lesfiche is in the trash), the result of a write the module did not confirm
(`lesficheWriteNotConfirmed`), and the result of a change, with the lesfiche
read back (`lesficheChangedResult`); a header note says why the session's
repeat of a write cannot make a lesfiche, a weblink or an attachment twice,
and why a read comes before the write.

The tests run against the fake planner (`test/support/fake_planner.dart`),
which also serves dartschool's anonymised captures of the Lesfiches list and
the detail of a lesfiche with the download of its attachment
(dartschool#129), with the school's course list, and carries out the writes
of a lesfiche of dartschool#129: the create from the web client's body, with
its attachments from the fake upload step (`fakeLesficheCreatePath`,
`fakeNewLesficheId`), the edits, and the weblinks and attachments added,
changed and removed, and the move of lesfiches to the trash
(`fakeLesficheTrashPath`; a lesfiche in the trash already answered with a
bare `500`, and `lesficheTrashExceptions` for an answer with `exceptions`),
with a trash (`trashedLesfiches`) whose lesfiches are read but not written,
and no longer listed, as live.
