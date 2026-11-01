# Learning goals

[Back to the overview](../../README.md)

The learning goals of Smartschool's goal selector, the dialog in which the
Lesfiches module and the planner let you pick the goals of a lesfiche or a
lesson: the eindtermen, the curricula of the philosophies of life and your
school's own mini-databases. For everyone, without a switch. Read only:
nothing here changes Smartschool. [`read_lesfiche`](lesfiches.md#read_lesfiche)
and [`read_planned_element`](planner.md#read_planned_element) show the goals
a lesfiche or a lesson has; [`create_lesfiche`](lesfiches.md#create_lesfiche),
[`edit_lesfiche`](lesfiches.md#edit_lesfiche) and
[`edit_planned_element`](planner.md#edit_planned_element) set them, with the
goals as `read_curriculum` shows them (see [How goals are
set](#how-goals-are-set)).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_curricula`](#list_curricula) | Lists the curricula, in the selector's groups | No |
| [`read_curriculum`](#read_curriculum) | Reads the goals of one curriculum, or finds a goal by words | No |

## Tools

### `list_curricula`

Lists the curricula the goal selector offers, in its groups and order, such
as `Overheid SO` (the eindtermen per grade and finality),
`Levensbeschouwing SO`, `Andere SO` and `Minidatabanken` (your school's
own). One line each: its title, whether it is hidden in the selector or a
favourite, and its id. `query` keeps the curricula whose title holds all its
words.

### `read_curriculum`

Reads the goals of one curriculum, by its id from `list_curricula`: the
goals you can pick, under their headings, each with its number (such as
`01.02`), its text and its id, and whether it is a goal of basic literacy,
an extension goal or deprecated. The answer says once which `leerplanId` and
`type` every goal of the curriculum is stored with. `query` keeps the goals
that hold all its words in their number, text or headings, to find the goal
that fits a lesson. At most 200 goals, with a note to narrow them.

## How it works

### How `list_curricula` works

It reads the list of the selector (the library's `GoalService.getCurricula`,
dartschool#222: `GET /goal/selector/api/v1/leerplannen/lesson-content/list/{today}`)
on every call. Both places the selector is opened from, the Lesfiches module
and the planner, list the same curricula (seen live), so the tool reads the
list of the Lesfiches module. `query` is matched in the title,
case-insensitive; a group without a match is left out. An answer the server
cannot use (`SmartschoolGoalError`) is "the goal selector gave an answer the
server could not use", with the details in the log only; a `403`
(`SmartschoolGoalAccessDeniedError`) says the selector refused the read.

### How `read_curriculum` works

It reads one curriculum as a tree (`GoalService.getCurriculum`) and lists
`Curriculum.goals`: the nodes the selector lets you pick (its
`typesThatCanBeSelected`, such as `goal`, and `goal-basic` and
`goal-extension` for the eindtermen of the first grade), depth first in the
selector's order, deprecated ones too. The headings above the goals are
printed once, indented by depth, the way the selector nests them; a title in
HTML (the eindtermen) is shown as plain text. Each goal line ends with the
goal's id; the head of the answer gives the curriculum's id (the
`leerplanId`) and its `leerplanType` (the `type`), the two other fields of
the `LearningGoalRef` a lesfiche or a lesson stores. `query` is matched in
the number, the text and the headings above the goal, case-insensitive. An
id the selector has no curriculum for (`404`,
`SmartschoolCurriculumNotFoundError`), or one the library refuses before
sending (an `ArgumentError`: another character than a letter, a digit or
`-`), says to take the id from `list_curricula`.

### How the goals of a lesfiche or a lesson are named

A lesfiche (`LessonContentDetail.goals`, dartschool#223) and a planned lesson
(`PlannedElementDetail.goals`, dartschool#226) store their goals as
`LearningGoalRef`s: `id`, `leerplanId` and `type`. `read_lesfiche` and
`read_planned_element` name them with `GoalService.resolve`, which asks the
selector for those goals (`POST`, read only) and gets one tree per
curriculum, pruned to them; the planner's goals are named at
`GoalLocation.plannerLessonContent`, a lesfiche's at `lessonContent`. Each
goal is a line with its curriculum, the headings above it, its number and
text, and its three fields. The modules store made-up ids without
complaint, and the selector leaves out what it does not know (a goal it does
not have, or a curriculum of a source it does not read, such as LLinkid):
such a goal is shown by its fields and said to be unknown. When the selector
cannot name the goals at all (a `SmartschoolGoalError`), the read is not
lost: the goals are shown by their fields, with a note. Without goals,
nothing is sent to the selector.

### How goals are set

`create_lesfiche`, `edit_lesfiche` and `edit_planned_element` (for a lesson)
take `goals`: a list of `{id, leerplanId, type}`, the goal's id from its line
in `read_curriculum` and the `leerplanId` and `type` from the head of that
answer (or the three fields `read_lesfiche` and `read_planned_element` show).
The list replaces the goals, as in the web clients, which send their whole
selection: to add a goal, Claude passes the goals the item has plus the new
one; an empty list clears them. The tools say this in their descriptions.
The writes are the library's `LessonContentService.changeGoals` and the
creates' `goals` (dartschool#223), and `PlannerService.changeGoals`
(dartschool#226), which sends nothing when the lesson has those goals
already.

The Lesfiches module and the planner store any goal id without complaint
(seen live), so before anything is sent the tools check the goals with the
selector (`checkGoals`): one `GoalService.resolve` for the goals the item
does not have yet, at the selector's place for the item (`lessonContent`, or
`plannerLessonContent` for the planner). A goal it does not name in that
curriculum (a made-up id, the id of a heading, a curriculum it does not have)
or that is given with another `type` than its curriculum's is refused, with
the goals listed, and nothing is sent. This costs one request per write and
needs no whole curriculum (a curriculum of the eindtermen is large). The
goals the item already stores are not checked, so that a goal of a source the
selector does not read (LLinkid) stays when a goal is added. A selector that
cannot answer refuses the write too. Before that, the arguments are checked
without a request: each goal an object with the three fields, the id a UUID
(as the library requires), and no id twice with other fields.

The result names the goals the item has after the write, as the reads do:
`create_lesfiche` with the selector's answer to the check (the library
confirms that the lesfiche read back has exactly the goals sent), the
lesfiche edits with the read-back of `read_lesfiche`, and
`edit_planned_element` with `nameGoals` on the lesson it gets back, only when
the goals were among the changes. A write the planner does not confirm
(`SmartschoolPlannerSaveUnconfirmedError`) is reported as maybe saved, as
for the other fields; the library's `ArgumentError`s cannot be reached past
the checks above, and would be a "refused before it was sent" error.

### Helpers and tests

The helpers live in `lib/src/goals/goals.dart`: the session runner with the
selector's errors as `ToolError`s (`withGoals`, `goalToolError`), the words
of a `query` (`goalQueryWords`, `goalMatches`), the answers of the two tools
(`formatCurricula`, `formatCurriculum`, `maxGoalLines`), the three stored
fields of a goal as every tool shows them (`formatGoalRef`: `id …,
leerplanId …, type …`), and the naming of stored goals for the reads of a
lesfiche or a lesson (`nameGoals`, which keeps the read when the selector
fails, and `formatNamedGoals`), and for the goal writes the `goals` argument
(`goalsSchema`, `goalsArgument`, `goalsReplaceNote`), its comparison
(`sameGoals`) and the check with the selector (`checkGoals`).

The tests (`test/goal_tools_test.dart`) call the tools over MCP on the real
server, session and library, against the fake goal selector
(`test/support/fake_goals.dart`), which serves the three routes in the shapes
of dartschool's tests (`test/goal_service_test.dart` there): the list, a
curriculum as a tree, and the naming of a selection, pruned, leaving out
what it does not know. The goals of a lesfiche and of a planned lesson are
tested there too, with the fake planner. The goal writes are tested in
`test/goal_write_tools_test.dart`, against the fake Lesfiches module and
planner, which store the goals of a create or a `change-goals` as sent, also
a made-up one, as live.
