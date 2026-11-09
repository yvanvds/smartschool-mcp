# Lesfiches

[Back to the overview](../../README.md)

The Lesfiches module: your own library of lesson and assignment lesfiches,
with their info, weblinks and attachments, planning them as lessons, and
year plans built from them. For
everyone, without a switch. Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_lesfiches`](#list_lesfiches) | Lists your lesfiches, by label and name | No |
| [`read_lesfiche`](#read_lesfiche) | Reads one lesfiche in full | No |
| [`read_lesfiche_attachment`](#read_lesfiche_attachment) | Returns the text of an attachment, or an image | No |
| [`save_lesfiche_attachment`](#save_lesfiche_attachment) | Saves an attachment into the download folder | No, saves a file on this PC |
| [`list_lesfiche_labels`](#list_lesfiche_labels) | Lists the labels a lesfiche can get, the school's and your own | No |
| [`create_lesfiche`](#create_lesfiche) | Makes a lesfiche in your own library | Yes, asks approval |
| [`duplicate_lesfiches`](#duplicate_lesfiches) | Copies lesfiches in your own library | Yes, asks approval |
| [`edit_lesfiche`](#edit_lesfiche) | Changes a lesfiche's name, icon, info, courses, goals, labels or visibility | Yes, asks approval |
| [`set_lesfiche_weblink`](#set_lesfiche_weblink) | Adds or changes a weblink | Yes, asks approval |
| [`remove_lesfiche_weblink`](#remove_lesfiche_weblink) | Removes a weblink | Yes, asks approval |
| [`add_lesfiche_attachments`](#add_lesfiche_attachments) | Adds files from this PC | Yes, asks approval |
| [`set_lesfiche_attachment_visibility`](#set_lesfiche_attachment_visibility) | Sets when pupils see an attachment | Yes, asks approval |
| [`remove_lesfiche_attachment`](#remove_lesfiche_attachment) | Removes an attachment | Yes, asks approval |
| [`trash_lesfiches`](#trash_lesfiches) | Moves lesfiches to the module's trash | Yes, asks approval |
| [`list_trashed_lesfiches`](#list_trashed_lesfiches) | Lists the lesfiches in the module's trash | No |
| [`restore_lesfiches`](#restore_lesfiches) | Takes lesfiches out of the trash, back into your library | Yes, asks approval |
| [`plan_lesfiche`](#plan_lesfiche) | Plans a lesfiche as a lesson in one or more lesson hours, replacing a lesson only when asked | Yes, asks approval |
| [`save_lesson_as_lesfiche`](#save_lesson_as_lesfiche) | Saves a lesson of your planner as a new lesfiche | Yes, asks approval |
| [`create_lesfiche_label`](#create_lesfiche_label) | Makes an own label, with its colour | Yes, asks approval |
| [`list_year_plans`](#list_year_plans) | Lists your year plans, with their lesson clusters | No |
| [`read_year_plan`](#read_year_plan) | Reads a year plan: each cluster with its goals, titles and lesfiches in order | No |
| [`create_year_plan`](#create_year_plan) | Makes an empty year plan | Yes, asks approval |
| [`add_lesson_cluster`](#add_lesson_cluster) | Adds a lesson cluster to a year plan | Yes, asks approval |
| [`add_to_lesson_cluster`](#add_to_lesson_cluster) | Adds a title and lesfiches to a cluster | Yes, asks approval |
| [`set_lesson_cluster_goals`](#set_lesson_cluster_goals) | Sets the learning goals of a cluster | Yes, asks approval |
| [`delete_year_plan`](#delete_year_plan) | Deletes a year plan with its clusters; its lesfiches stay | Yes, asks approval, cannot be undone |

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
when pupils see it), its learning goals (see [Learning goals](goals.md)) and
its public and private info. A lesfiche in the trash
is still read.

### `read_lesfiche_attachment`

Opens one attachment of a lesfiche, by its number in `read_lesfiche` or its
file name, and returns its text, or an image, as
[`read_intradesk_file`](intradesk.md#read_intradesk_file) does. Up to 25 MB.

### `save_lesfiche_attachment`

Saves one attachment of a lesfiche into your
[download folder](../development.md#saving-files) and returns its full path,
name and size.

### `list_lesfiche_labels`

Lists the labels a lesfiche can get: the school's labels for the Lesfiches
module (such as `JAAR 6`), then your own, each with its colour and id.
`create_lesfiche` and `edit_lesfiche` take them by their text,
`list_lesfiches` filters by them.

### `create_lesfiche`

Makes a lesfiche in your own library ("Mijn lesfiches"): a lesson, or an
assignment of one of the school's types, with a name and optionally public
and private info, courses, learning goals (from
[`read_curriculum`](goals.md#read_curriculum)), labels (from
[`list_lesfiche_labels`](#list_lesfiche_labels)), weblinks, files from this
PC and an icon. For each
weblink and file you choose when pupils see it: always, never, from the
start or the end of the lesson it is planned in, or 1 to 14 days after its
end. Your library is private until you
plan a lesson from the lesfiche, but the tool still asks for approval:
Claude shows you everything first and makes the lesfiche once. A name that
is taken is kept (the module makes a second lesfiche), and the answer names
the others.

### `duplicate_lesfiches`

Copies 1 to 20 lesfiches, lessons and assignments together, in your own
library: each copy gets a new id and the name of its lesfiche with
` - kopie` behind it, and its icon, info, visibility, courses, labels,
learning goals, weblinks and attachments. The lesfiches themselves do not
change. Change a copy afterwards with `edit_lesfiche` and the other tools,
by the id the answer gives. A lesfiche in the trash cannot be copied:
restore it first. Asks for approval; every call makes new copies, so Claude
copies once.

### `edit_lesfiche`

Changes one lesfiche of your own library: its name, icon, public or private
info, courses, learning goals, labels, or whether it is visible in the
module (a hidden lesfiche is still listed and can still be planned). An info
is replaced whole, and an empty text empties it; the courses, the goals and
the labels given replace all of them (to add a goal or a label, Claude
passes the ones it has with the new one). A goal the goal selector does not
know is refused, and so is a label that does not exist. Asks for
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
deletion: `restore_lesfiches` takes a lesfiche back out of the trash. A
lesson planned from a lesfiche earlier stays in the planner. Asks for
approval; Claude shows you each lesfiche by name and kind first.

### `list_trashed_lesfiches`

Lists the lesfiches in the module's trash, lessons and assignments, most
recently moved first: one line each as `list_lesfiches` shows it, with the
day it went to the trash instead of the day it was last changed, and its id
for `restore_lesfiches`. Filtered by words in the name. The module says a
lesfiche in its trash can be restored within 100 days.

### `restore_lesfiches`

Takes 1 to 20 lesfiches out of the module's trash, back into your library,
by the ids `list_trashed_lesfiches` shows; `list_lesfiches` lists them
again. Asks for approval; Claude shows you each lesfiche by name and kind
first.

### `plan_lesfiche`

Plans a lesson lesfiche into 1 to 20 lesson hours of your own planner in one
call, such as the same lesson in all your parallel classes: each lesson is
named after the lesfiche and takes over its public and private info, labels
and goals, attachments and weblinks, each attachment and weblink with the
visibility it has in the lesfiche. The lesson keeps the course of the hour,
not the lesfiche's. Planning **copies** the lesfiche: a later change to the
lesfiche does not reach the lessons planned from it. The result says per
hour whether it was planned, with the new lesson's id.

An hour that already holds a lesson (one you typed in by hand, say) is
**refused, unless `replace` is set**: then the lesson is replaced by the
lesfiche, and its old name, info and goals are gone. Nothing is overwritten
by accident: Claude sets `replace` only when you asked to replace those
lessons. It works as [`plan_lesson`](planner.md#plan_lesson): asks for
approval, after Claude shows you which lesfiche goes into which hour, and
which lesson it replaces. An assignment lesfiche cannot be planned.

### `save_lesson_as_lesfiche`

Saves a lesson of your own planner as a new lesson lesfiche in your library,
as the planner's "Opslaan in Lesfiches" does: to reuse it next year, or plan
it into other hours with `plan_lesfiche`. The lesfiche gets the lesson's
icon, public and private info and goals, and its name, or the `name` you
give. The lesson stays as it is and keeps no link to the lesfiche. Every
call makes a new lesfiche, also when one of that name exists. Asks for
approval; the result gives the lesfiche with its id.

### `create_lesfiche_label`

Makes a new own label with a text (at most 50 characters) and one of the web
client's 18 colours (`steel` by default), to put on lesfiches. A text one of
your own labels has already is refused, in plain words. Asks for approval.
The server does not change or remove a label: do that in Smartschool.

### `list_year_plans`

Lists your year plans ("leeropdrachten", teaching assignments): each a
collection of your lesfiches split into lesson clusters, the units of the
year. One line each: name, which lesfiches it takes (all yours, for a plan
made here), its clusters by name, hidden or a favourite, and its id.

### `read_year_plan`

Reads one year plan, by its id: each lesson cluster with its number of
lesson and assignment lesfiches and of its own goals (those its `Goals:`
lists), its estimate of teaching hours (left out when the module gives none
or 0), its learning goals by name (see [Learning goals](goals.md)), and its
content in order: titles such as "Week 1", and lesfiches with their
teaching hours, number of goals and id. With `cluster`, only that cluster.

### `create_year_plan`

Makes a new, empty year plan with a name (at most 50 characters) that takes
all your lesfiches. Every call makes a new one, also when one of that name
exists. Asks for approval; the result gives its id.

### `add_lesson_cluster`

Adds a new, empty lesson cluster with a name (at most 50 characters) to the
end of a year plan. Every call adds a new one. Asks for approval; the result
gives its id.

### `add_to_lesson_cluster`

Adds a title (at most 50 characters), lesfiches (1 to 20, by their ids from
`list_lesfiches`), or a title followed by lesfiches to the end of a lesson
cluster, in the order given. The lesfiches are not copied or changed: the
cluster refers to them. A lesfiche the year plan does not take is refused
before anything is sent. Every call adds them again, also a lesfiche that is
in the cluster already. Asks for approval; the result shows the cluster as
it is now.

### `set_lesson_cluster_goals`

Sets the learning goals of a lesson cluster, as `edit_lesfiche` does for a
lesfiche: the list replaces the goals, and a goal the goal selector does not
know is refused. The goals of the lesfiches in the cluster stay as they are.
Asks for approval; the result shows the cluster with its goals.

### `delete_year_plan`

Deletes a year plan with its lesson clusters, their titles and goals. **It
cannot be undone**: a year plan has no trash. The lesfiches in it stay in
your library, unchanged. Asks for approval, after Claude shows you the year
plan with its clusters and says that it cannot be undone.

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
know, by the module's name for it. The learning goals
(`LessonContentDetail.goals`, dartschool#223) are named by the goal selector
(`GoalService.resolve`, #186; see [How the goals of a lesfiche or a lesson
are named](goals.md#how-the-goals-of-a-lesfiche-or-a-lesson-are-named)),
`Goals: none` without any. Weblinks of publishers and deeplinks are
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

### How `list_lesfiche_labels` works

It reads the labels with the library's `LessonContentService.getLabels`
(dartschool#228), as the Lesfiches web client's label picker does: two reads
of Smartschool's labels module (`/labels/api/v1`), the school's labels whose
locations hold the Lesfiches module and the user's own labels. It takes no
arguments. The school's labels come first, then the own ones, each in
Smartschool's order, one line each: text, colour, `hidden` when it is not
visible, and id. An answer the server cannot use is "the Lesfiches module
gave an answer the server could not use", with the details in the log only.

### How labels are set

`create_lesfiche` and `edit_lesfiche` take `labels`: each label by its whole
text as `list_lesfiche_labels` shows it (case-insensitive, extra white space
ignored, each once), or by its id. Before anything is sent, the tool reads
the labels (`getLabels`) and finds each one there; `edit_lesfiche` also
finds the labels the lesfiche has, so that a label that is no longer offered
is kept when it is passed again. A text that names no label is refused with
the labels there are, and one that a school label and an own label both have
is refused with their ids, to pass the id instead. An empty list sends no
read. The labels go out as the labels module gives them
(`LessonContentLabel.toWire`): the module answers an own label without its
owner, or a school label with only its id, with a bare `500` (seen live).
`create_lesfiche` sends them in the create; `edit_lesfiche` with
`changeLabels`, in the order of the fields after the goals. The list
replaces the labels, and an empty one takes them all off; the library checks
that the lesfiche has exactly the labels sent.

### How `create_lesfiche` works

It makes the lesfiche in one create, as the web client makes one, with the
library's `LessonContentService.createLesson` or `createAssignment`
(dartschool#129): a `name` (at most 255 characters), a `type` (`lesson`, the
default, or `assignment` with `assignment_type`, one of the school's types
by abbreviation or name, matched as `plan_assignment` matches its `type`),
and optionally `labels` (see [How labels are set](#how-labels-are-set)),
`public_info` and `private_info` (plain text, as
`plan_lesson`), `courses` (each by its name as the tools show it, or by its
id, found in the school's course list: one the list does not have is an
error that lists the names, and a name two courses have one that gives
their ids), `goals` (`{id, leerplanId, type}` as `read_curriculum` shows
them, checked with the goal selector before anything is sent, see [How goals
are set](goals.md#how-goals-are-set)), `weblinks` (`{name, url, visibility?}`, the address as the web
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
the course list for the courses, the labels for the labels, for an
assignment the school's
types (read once per session), and checks the goals with the goal selector,
whose answer names them in the result. The library checks the courses and the type
again, uploads the files into a new upload directory, sends the create once
(`POST lessons/` or `assignments/`, answered `201` with the id only) and
reads the lesfiche back. When Smartschool refuses the session for the
create, the session repeats the call, and the library logs in again before
the repeat's first request (dartschool#134). A name that is taken is kept
(the module makes a second lesfiche, seen live), and the result names the
other lesfiches of that name and kind. The result is the lesfiche as
`read_lesfiche` shows it, with its id for `plan_lesfiche` (a lesson),
`read_lesfiche` and `edit_lesfiche`, the tools that change its weblinks and
attachments, and `trash_lesfiches` to undo it.

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
empty list removes them), `goals` (`changeGoals`, dartschool#223, in place
of all its goals; an empty list clears them; see [How goals are
set](goals.md#how-goals-are-set)), `labels` (`changeLabels`, dartschool#228,
in place of all its labels; an empty list clears them; see [How labels are
set](#how-labels-are-set)) and `visible` (`setVisible`: shown or
hidden in the module). Marked destructive (as `create_lesfiche`, for Claude Desktop and
Codex to ask approval) and idempotent: each edit sets a value. Claude shows
the lesfiche and what changes, and calls after the user's confirmation.

The tool reads the lesfiche first (the edits take it as read), for
`courses` the school's course list, so that an unknown course is refused
before any edit (the library checks the courses again), and for `goals`
asks the goal selector about the goals the lesfiche does not have yet, so
that an unknown goal is refused before any edit, and for `labels` the
labels there are, so that an unknown label is refused before any edit. It
stops at the
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
of a kind the library cannot write. `restore_lesfiches` takes lesfiches back
out of the trash; nothing deletes for good (`delete/bulk` is left out on
purpose). A lesson planned from a
lesfiche earlier stays in the planner, which copied the lesfiche (its info,
attachments and weblinks, #117); the description says so.

Marked destructive, for Claude Desktop and Codex to ask approval: Claude
shows each lesfiche by name and kind, and calls once after the user's
confirmation. Idempotent, as `remove_lesfiche_attachment`: a second call
finds the lesfiches no longer listed and sends nothing. The result lists the
lesfiches moved, one line each as `list_lesfiches` shows them, their courses
by name (#206): the list is read without the course names, so the tool reads
the school's course list (`getCourses`) once before the move, when one of the
lesfiches has a course; when that list cannot be read, the move goes ahead
and the courses are counted, with a note. `restore_lesfiches` and
`duplicate_lesfiches` name the courses the same way. The library retries the move after logging in again, as a read.
An answer whose `exceptions` are not empty is not confirmed: the result says
from the library's record of it which lesfiches were moved, which the module
answered with an exception (each with its status and words), and which its
answer names neither way. The module answers the move of a lesfiche that is
in the trash already with a bare `500` (seen live; it was moved there after
the tool read the list), which says nothing about any lesfiche: the tool
then reads the trash again, in a session action of its own, and lists which
lesfiches are in it and which are still in the library. Either is an error
result when some were not moved (see [How the bulk writes check an
unconfirmed answer](#how-the-bulk-writes-check-an-unconfirmed-answer)). When
that read fails too, the result says that some or all of them may or may
not have been moved, and to check with `list_trashed_lesfiches`. A refusal
by the module (`400` to `499`) says that none was moved.

### How `list_trashed_lesfiches` works

It reads the trash with the library's `getTrash` (dartschool#227,
`GET lesson-content/trashed`), which gives the lesfiches in the shape of
`getItems`, with their courses named after the school's course list; when
only that list fails, the lesfiches are listed with the number of their
courses and a note, as `list_lesfiches` does. Each line is
`formatLesficheLine` with `inTrash`: `in the trash since <day>`, from the
lesfiche's `dateStateChanged`. The order is most recently moved first, then
by name; `query` keeps the lesfiches whose name holds every word. At most
200 lines. Read-only.

### How `restore_lesfiches` works

It takes the lesfiches (`lesfiches`, 1 to 20 ids) out of the trash with the
library's `restore` (dartschool#227): one `POST lesson-content/restore/bulk`
with the body of the trash. The library takes each lesfiche as read, so the
tool reads the trash first (`getTrash`, without the course names), in the
session action of the restore, and matches the ids (ignoring case, each
once). An id the trash does not list is looked up in the library
(`getItems`): a lesfiche there is "not in the trash, nothing to restore",
any other names no lesfiche; both are refused before anything is sent.
Not destructive (it brings lesfiches back), and idempotent: a second call
finds them no longer in the trash and sends nothing. The library retries
the restore after logging in again, as a read.

The module answers the restore of a lesfiche that is not in the trash with
an exception (`404`, seen live): the result says from the library's record
of the answer which lesfiches were restored, which got an exception (with
its status and words) and which the answer names neither way. Only for no
answer does the tool read the trash again and list which lesfiches left it
and which are still there; when that read fails too, maybe restored, with
`list_trashed_lesfiches` to check.

### How `duplicate_lesfiches` works

It copies the lesfiches (`lesfiches`, 1 to 20 ids from `list_lesfiches`)
with the library's `duplicate` (dartschool#227): one
`POST lesson-content/duplicate/bulk` with the body of the trash, which the
module answers with each copy, keyed by the lesfiche as sent. The library
returns the copies in the order given; the result has a line per copy (as
`list_lesfiches` shows it, its courses by name as for `trash_lesfiches`,
without a date: the copy comes in the shape of the detail) with the id of
the lesfiche it copies.

As `trash_lesfiches`, the tool reads the list first, in the session action
of the copy. An id the list does not hold is looked up in the trash
(`getTrash`): a lesfiche there cannot be copied (the module answers `403`),
so the tool says to restore it first; any other names no lesfiche; both
before anything is sent. The library sends the copy **once**, never again
after logging in again: a second send makes more copies. So the tool is not
idempotent, and Claude is told never to copy a lesfiche again that was
copied. A refused session repeats the whole action in a new session, which
is safe: the library did not send the copy then.

When the module refuses every lesfiche (`403`: one went to the trash after
the read), the library throws a `SmartschoolLessonContentWriteRefusedError`
and the tool says no copy was made, and to restore it first. When some
copies were made and others not, it throws a
`SmartschoolLessonContentBulkSaveUnconfirmedError`, which pairs each copy
made with its lesfiche: the result lists the copies made (each with the id
of the lesfiche it copies), the lesfiches the module answered with an
exception (`403` for one in the trash), and those its answer names neither
way, which Claude checks with `list_lesfiches` before copying them again.
Only when no answer came does the tool read the list again, and take the
lesfiches new since its first read as the copies made, each matched with
the lesfiche of its name (with ` - kopie` behind it) and kind: the result
lists the copies made, the lesfiches without a copy, and any other lesfiche
new in the library. When that read fails too, maybe made, with
`list_lesfiches` to check.

### How the bulk writes check an unconfirmed answer

When the module's answer to `trash_lesfiches`, `restore_lesfiches` or
`duplicate_lesfiches` says lesfiche by lesfiche what it did, but not that it
did all of it, the library throws a
`SmartschoolLessonContentBulkSaveUnconfirmedError`: each lesfiche sent is in
its `done` (with its copy in `copies`, from a copy), in `failed` (with the
module's exception: its status and words, never a name) or in `unanswered`
(the answer names it neither way). The tool says so from that record,
without reading anything again (`lesficheBulkAnswerResult`): an error
result, with Claude told not to repeat the ones that were done, and to check
the ones not named with `list_trashed_lesfiches` or `list_lesfiches` first.

A plain `SmartschoolLessonContentSaveUnconfirmedError` means the answer
says nothing usable about any lesfiche (no answer, a bare `500`). Only then
does the tool read again where the lesfiches are (the trash, or the list for
a copy), in a session action of its own, and say from that read which were
done and which not (`lesficheBulkPartialResult`; an error result when some
were not done). The library's message, which names the lesfiches, is never
shown or logged; the log gives only the counts and statuses.

### How `plan_lesfiche` works

It plans the lesfiche (`lesfiche`, an id from `list_lesfiches`) into the
`hours` (1 to 20 ids from `list_planner`, each planned once): the planner
names each lesson after the lesfiche and takes over its content. Seen live:
its labels and goals (dartschool#88), and its public and private info,
attachments and weblinks, each attachment and weblink with the visibility it
has in the lesfiche (#117: one from the start of the lesson, one from its
end, a weblink always, as the web client showed). Planning copies the
lesfiche: a planned lesson keeps no link to it, and a later change to the
lesfiche does not reach the lesson (dartschool#224). The description says
what is copied.

An hour is an empty lesson hour (`planned-placeholders/…`) or, only with
`replace` true, a lesson (`planned-lessons/…`). The product decision of #190:
a lesson among the `hours` without `replace` is refused before anything is
sent, so that a lesson typed in by hand is never overwritten by accident;
the description tells Claude to set `replace` only when the user asked to
replace those lessons, and to show any lesson that is replaced. An empty
lesson hour id of an hour that was filled meanwhile is gone (its id
changed), so the library refuses it too: only the ids of lessons are
replaced.

One empty hour is filled with the library's `planLessonContent`
(dartschool#88), one lesson replaced with `replaceWithLessonContent`
(dartschool#224, `POST planned-lessons/replace/planned-lessons/{platformId}/{id}`);
both give the lesson as saved, with its new id, and its goals named as
`read_planned_element` names them (in a session action of their own, after
the write: `nameGoalsAfterWrite`). Two or more hours go in one request,
`planLessonContentInto` (dartschool#224, `POST
planned-elements/replace-with-lesson-content`, the planner's copy dialog):
the tool reads the hours first, and the library reads them again and checks
every one before it sends (the first that fails refuses the whole call,
and nothing is sent). The planner answers per hour; the result has a line
per hour, planned (with the lesson's new id) or not planned (with the
planner's reason when it gives a text, else that its answer is in the
server log), then the first new lesson in full: the others hold the same
content, each in its own hour. When an hour was not planned, the result is
an error, and Claude is told not to plan the others again. An hour the
planner did not plan is left as it was, and is not retried.

It works as `plan_lesson` does: marked destructive, Claude shows the mapping
of lesfiches onto hours (date and time, class, course, lesfiche, any lesson
replaced) and plans after the user's confirmation, one call per lesfiche
with all its hours. The library reads the lesfiches before it plans and
refuses, before sending anything, an id the user has no lesfiche with and an
assignment lesfiche; the tool says so in its own words and points to
`list_lesfiches`. A hidden lesfiche is planned like any other. Its
description points to `create_lesfiche` for a lesfiche that does not exist
yet, and to `save_lesson_as_lesfiche` for a lesson to keep as one. It is one
of the planner writes, which report a write the planner did not confirm as
the others do (see [The planner writes](planner.md#the-planner-writes)): for
several hours, that it may have been saved in all or some of them, with
`read_planned_element` for each hour to check (an hour the planner no longer
has under its id was planned). The result names the lesfiche by its name, as
the planner names the lesson after it (`Planned the lesfiche "Lussen 1" into
all 2 hours`, #206); by its id only when no lesson was planned, or when the
planner did not confirm the write.

### How `save_lesson_as_lesfiche` works

It saves the `lesson` (a `planned-lessons/…` id from `list_planner`; an empty
lesson hour or an assignment is refused before anything is sent) with the
library's `saveAsLessonContent` (dartschool#225, `POST
planned-lessons/{platformId}/{id}/save-in-source-module` with `{"newName"}`),
named `name` (checked as `create_lesfiche` checks a name) or, when it is
left out, the lesson's name; a lesson without a name needs `name`. The
library reads the lesson again and refuses one that is not the user's own,
or that the planner does not let the user save (`canUserSaveInSourceModule`).
The planner answers `{}`, which does not name the new lesfiche: the library
reads the lesfiches before and after the save and takes the one new lesson
lesfiche of that name. Seen live: the lesfiche gets the lesson's icon, public
and private info and goals; whether attachments, weblinks and labels are
copied was not seen. The lesson stays as it is and keeps no link to the
lesfiche. The result gives the lesfiche as `read_lesfiche` shows it, with its
goals named, and its id for `plan_lesfiche`.

Marked destructive, for Claude Desktop and Codex to ask approval, and not
idempotent: the module keeps two lesfiches of one name, so a second call
makes a second lesfiche. The library sends the save once, never again after
logging in again. When the list does not confirm it
(`SmartschoolPlannerSaveUnconfirmedError`), the result says the lesfiche
may or may not have been made, and tells Claude to look for it with
`list_lesfiches` before anything else, never to call the tool again for it.

### How `create_lesfiche_label` works

It makes an own label with the library's `createUserLabel`
(dartschool#228): `POST /labels/api/v1/user-labels/{userId}` with the `text`
(at most 50 characters, `maxLabelLength`, without the white space around it)
and the `color` (one of `labelColors`, the web client's 18; `steel`,
`defaultLabelColor`, when it is left out), answered `201` with the new
label. An empty or too long text is refused before anything is sent; the
input schema lists the colours. Marked destructive, for Claude Desktop and
Codex to ask approval, and not idempotent. The library sends it once, never
again after logging in again. The labels module refuses a text one of the
own labels has (`400` with `name.already.used`), and the result says so in
plain words, with `list_lesfiche_labels` to find the label; another refusal
says that nothing was made, and that a text longer than 50 characters is
refused so. A create the module does not confirm is maybe made, with
`list_lesfiche_labels` to check it and not to call again. The result gives
the label with its colour and id, and how to put it on a lesfiche. The
library does not change or remove a label, so neither does the server.

### How the year plans work

The year-plan tools (#191) use the library's `TeachingAssignmentService`
(dartschool#229), under `/lesson-content/api/v1/teaching-assignments`. A
year plan is a teaching assignment; a cluster is a lesson cluster of it.
The tools take a year plan and a cluster by their ids (UUIDs) only, as
`list_year_plans` and `read_year_plan` print them. Every tool reads the
user's year plans first (`getTeachingAssignments`, which gives each plan's
platform and its clusters in short), and refuses a year plan or a cluster
that is not in them, listing the ones there are, before anything is sent.
A text that is not a UUID is refused before any login.

- `read_year_plan` reads the clusters in full (`getClusters`, with their
  counts, teaching hours and goals), the content of each
  (`getClusterContent`, titles and lesfiches in order), and names the goals
  of all clusters with one request to the goal selector (`nameGoals`, at
  `GoalLocation.lessonContent`). The lesfiches of a cluster come without
  course names; `read_lesfiche` reads one in full.
- `create_year_plan` sends `createTeachingAssignment` with the content
  filter `all` (the web client's default), so that every lesfiche of the
  user can be added; with `none` the module refuses each one (seen live).
- `add_lesson_cluster` sends `addCluster`.
- `add_to_lesson_cluster` reads the lesfiches the year plan takes
  (`getLessonContent`) and matches the ids given with them, so that one it
  does not take, one in the trash and one that is not the user's are refused
  before anything is sent. The title (`addTitle`) and the lesfiches
  (`addLessonContent`, one request for all) each go out in a session action
  of their own, so that a repeat after a refused session never sends the
  title again. When the lesfiches fail after the title, the result says
  that the title was added. The module answers a lesfiche it refuses with
  an exception for it (`403`); the library makes that a refusal when it
  added none. The result reads the cluster back, in a session action of its
  own.
- `set_lesson_cluster_goals` reads the cluster (`getCluster`), sends
  nothing when it has those goals already, checks the goals it does not
  have yet with the goal selector (`checkGoals`, as the goal writes of
  #187), and sends `changeClusterGoals`.
- `delete_year_plan` sends `deleteTeachingAssignment` (`DELETE`, answered
  `204`). The lesfiches stay in the library.

The names, the cluster names and the titles are refused above 50
characters (`TeachingAssignmentService.maxNameLength`; the module answers a
longer one with a bare `400`, seen live) before anything is sent. The
creates and adds are not idempotent and the library sends them once, never
again after logging in again: a write the module does not confirm is
reported as maybe made, with `list_year_plans` or `read_year_plan` to check
and not to call again. Setting goals and the delete name what they change,
so the library retries them after logging in again, and they are marked
idempotent. A write the module refuses says so: a `404` that the year plan
or cluster is gone, a `403` that the year plan does not take the lesfiches.
The helpers live in `lib/src/planner/year_plans.dart`; the tests in
`test/year_plan_tools_test.dart`, against `test/support/fake_year_plans.dart`.

Planning a cluster for classes is on the Planner page:
[`plan_lesson_cluster`](planner.md#plan_lesson_cluster) (#196, part two of
#191).

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
id and the kind from `list_lesfiches`", `lesficheNotFound`; and
`readNamedLesficheDetail`, which also names its goals, for `read_lesfiche`
and the read-back of a change, see [Learning goals](goals.md#helpers-and-tests)), the lesfiche as
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

In `lesfiche_bulk.dart`, for the bulk writes (`trash_lesfiches`,
`restore_lesfiches`, `duplicate_lesfiches`, #189): the `lesfiches` argument
(`lesficheIdsSchema`, `lesficheIdsArgument`, at most
`maxLesficheBulkItems`), the lesfiches of a read with those ids
(`findLesfiches`), the refusal of a kind the library cannot write
(`refuseOtherLesficheKinds`), the lesfiches in words (`lesficheTitles`,
`lesficheSubject`), the result of an unconfirmed write from the library's
record of its answer (`lesficheBulkAnswerResult`), and, for an answer that
says nothing usable, the read after it (`readLesficheTrashAfter`,
`readLesfichesAfter`) with its result (`lesficheBulkPartialResult`).

In `lesfiche_labels.dart`, the labels (#188): the `labels` argument of
`create_lesfiche` and `edit_lesfiche` (`lesficheLabelsSchema`,
`lesficheLabelsArgument`, `lesficheLabelsReplaceNote`), matched with the
labels there are and the labels the lesfiche has (`lesficheLabels`) and
compared by id (`sameLabels`); the list of `list_lesfiche_labels`
(`formatLesficheLabels`, `formatLesficheLabel`); and the text and colour of
`create_lesfiche_label` (`lesficheLabelTextArgument`,
`lesficheLabelColorArgument`, `lesficheLabelColors`).

The tests run against the fake planner (`test/support/fake_planner.dart`),
which also serves dartschool's anonymised captures of the Lesfiches list and
the detail of a lesfiche with the download of its attachment
(dartschool#129), with the school's course list, and carries out the writes
of a lesfiche of dartschool#129: the create from the web client's body, with
its attachments from the fake upload step (`fakeLesficheCreatePath`,
`fakeNewLesficheId`), the edits, and the weblinks and attachments added,
changed and removed, and the move of lesfiches to the trash
(`fakeLesficheTrashPath`; a lesfiche in the trash already answered with a
bare `500`, `lesficheTrashExceptions` for an answer with `exceptions` keyed
by the lesfiche, and `lesficheBulkListExceptions` for a move or a restore
answered with exceptions that name no lesfiche),
with a trash (`trashedLesfiches`) whose lesfiches are read but not written,
and no longer listed, as live. The trash is listed
(`fakeLesficheTrashedPath`, with `lesficheTrashDates`), restored from
(`fakeLesficheRestorePath`: a `404` exception for a lesfiche not in it, and
`lesficheRestoreExceptions`) and the lesfiches copied
(`fakeLesficheDuplicatePath`: each copy with the next `fakeNewLesficheId`,
" - kopie", and the lesfiche's labels, goals, weblinks with new ids and
attachments; a `403` exception for one in the trash, and
`lesficheDuplicateUnanswered` for a copy the answer leaves out), each answer
keyed by
the lesfiche as sent (`fakeLesficheRefKey`); these tools are tested in
`test/lesfiche_copy_restore_tools_test.dart`. It serves the labels module too
(`fakeLabelsApi`): the school's labels (`schoolLabels`) and the own ones
(`ownLabels`), each a `FakeLabel` with an id from its text
(`fakeSchoolLabelId`, `fakeOwnLabelId`), the create of an own label
(`name.already.used`, a bare `400` for a long text), and the labels of
`change-labels` and of the create (a bare `500` for a label without its
owner or platform). The label tools are tested in
`test/lesfiche_label_tools_test.dart`. The planner plans a lesfiche into an empty hour
with its info, labels and goals; it replaces a lesson by a lesfiche (`201`
with the new lesson), plans one into several hours at once (the short
lessons and the `exceptions`, with `bulkExceptions` for a target it does not
plan), and saves a lesson as a new lesson lesfiche (`{}`, the lesfiche with
the next `fakeNewLesficheId`). `plan_lesfiche` over several hours and over a
lesson, and `save_lesson_as_lesfiche`, are tested in
`test/plan_lesfiche_hours_tool_test.dart` (#190).
