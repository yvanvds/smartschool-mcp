# Presences

[Back to the overview](../../README.md)

The half-day presences of Smartschool's Presence module: a morning and an
afternoon per pupil per day, the registration that counts for the
government. Opt-in: offered only when the switch "Aanwezigheden" is on
(`SMARTSCHOOL_PRESENCE`), as recording them needs the rights of a school's
absence administrators (often the pupil secretariat), which most teachers and
all pupils lack. The registration per lesson is not offered. Tools that
change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_presence_classes`](#list_presence_classes) | Lists the classes you may view, and record for | No |
| [`list_class_presences`](#list_class_presences) | Lists a class's pupils with their morning and afternoon | No |
| [`set_pupils_late`](#set_pupils_late) | Marks pupils late for a half-day | Yes, asks approval |
| [`set_pupils_present`](#set_pupils_present) | Marks pupils present for a half-day | Yes, asks approval |

## Tools

### `list_presence_classes`

Lists the classes you may view in the Presence module, each with its class
id and whether you may record presences for it or only view them. A grouping
class is marked, with the official classes it groups when the module names
them: presences are recorded in a pupil's official class.

### `list_class_presences`

Lists the pupils of one class on one day (today by default), with what their
morning and afternoon hold ("Aanwezig", "Te laat", "Doktersattest", or
nothing recorded) and its motivation, and per pupil the id the writes take.
In a grouping class each pupil's official class is named too. When the class
has no pupils, or the day is in the future, the answer gives the module's
reason.

### `set_pupils_late`

Marks 1 to 50 pupils of a class late ("Te laat", or "Te laat zonder geldige
reden") for the morning or the afternoon of a day, with an optional
motivation: a group from a late bus takes one approval. A half-day is an
official record about pupils, so it asks for approval; Claude reads the
class first and shows you the class, the pupils by name, the half-day, the
status and the motivation. It never overwrites another status, such as an
absence the secretariat recorded, and a pupil who already has the status is
left alone. Not for a day in the future, nor for a grouping class: use the
pupil's official class.

### `set_pupils_present`

Marks pupils present ("Aanwezig") likewise, for example to undo a "Te laat"
recorded by mistake. Asks for approval.

## How it works

The presence tools are offered only when the switch "Aanwezigheden" is on
(see [Opt-in tools](../development.md#opt-in-tools)): they need the right to
record half-day presences for classes in Smartschool's Presence module, as
the absence administrators of a school (often the pupil secretariat) have;
most teachers and all pupils lack it. The half-day registration (a morning
and an afternoon per pupil per day, `DayPart`) is the one that counts for
the government; the registration per lesson is a different one and is not
offered. The tools use the library's `PresenceService` (dartschool#2); the
first two only read, the last two change the presences of pupils.

### How `list_presence_classes` works

It lists the classes the account may view in the module (`getConfig`: its
allowed classes, and the active class when it is not among them; not the
placeholder "Uit Planner", class id -2, that the module gives as the active
class of a teacher without a lesson at the moment, #84, which the library
keeps apart as `activePlaceholder`, yvanvds/dartschool#117), one line per
class with its name, class id (`groupID`), and whether the account may
record presences for it (`userCanConfirm`: "may record" or "view only"; not
`userCanRecord`, which a teacher without the absence-administrator rights
has for every class, #95 and yvanvds/dartschool#121).

A grouping class without a school structure is marked, as presences are
recorded in the pupils' official class, with the classes it groups when the
module names them (`downStreamGroupIds`, yvanvds/dartschool#126, #110):
`groups 2A MAW (class id 1652), 2A ECO (class id 1968)`, each by name and
class id, or by class id alone ("not among the classes this account may
view") when the configuration does not list it, as for an account without
the absence-administrator rights, which is listed fewer classes. Seen live
for 6 of the school's 17 grouping classes, the official classes of a year;
for the others (such as "Taalatelier groep 1") and for every official class
nothing is said, not "groups none": the list is not the official classes of
the pupils (the grouping class 2C listed a pupil of 2E ECO).

### How `list_class_presences` works

It reads the pupils of one class (`class_id`) on one day (`date`, default
today) with what their morning and afternoon hold (`getClassPupils`), named
with the codes of the class's structure (`getAllCodes`): a code
(`"Aanwezig"`, `"Te laat"`, `"Doktersattest"`), an alias with its code
(`"Te laat zonder geldige reden" (under "Te laat")`), or "nothing recorded",
with its motivation, and per pupil the pupil id the writes take.

A grouping class has no structure, so the module gives no codes for it,
while its pupils' half-days hold the codes of their official classes (seen
live: every half-day of the grouping class 2A held code id 70, "Aanwezig" in
the official class 2A ECO, #99). Its statuses are named as the module names
them with each record (`PresenceHalfDay.statusName`, given with every record
seen live, yvanvds/dartschool#126), without reading codes; a half-day the
module gives no name with (not seen live) is named with the codes of the
structure of the pupil's official class (`PresencePupil.officialClassId`,
one `getAllCodes` per distinct structure, after the pupils), or by its code
id when the account does not see that class (#101). In a grouping class,
each pupil's line also names the pupil's official class, where the writes
record its presences (`official class: 2A ECO (class id 1968)`; by class id
alone when the account does not see it, or "none given by the module", not
seen live; #110). A half-day of any class whose code is not among the codes
read is named likewise. Rows per lesson are left out (the library ignores
them). When the module lists no pupils, the tool gives the module's reason
(`errorMessage`, yvanvds/dartschool#104), as seen live: "Deze klas bevat
geen leerlingen." for a class without pupils, "Het is niet mogelijk om in de
toekomst afwezigheden op te nemen." for a day in the future.

### How `set_pupils_late` works

It marks pupils (`pupil_ids`, 1 to 50) of a class late for the morning or
the afternoon (`part`) of a day (`date`), with `setLate`: "Te laat", or with
`without_valid_reason` "Te laat zonder geldige reden", with an optional
`motivation` (at most 500 characters), once per pupil, one after the other.
Marked destructive and idempotent: a pupil who already has the status (and
the motivation, when one is given) is left alone, and nothing is saved for
them. Claude is told to read the class with `list_class_presences` first, to
show the user the class, the pupils by name, the half-day, the status and
the motivation, and to wait for the user's confirmation. See
[The writes](#the-writes).

### How `set_pupils_present` works

It marks pupils present ("Aanwezig") with `setPresent` and the same
arguments without `without_valid_reason`. See [The writes](#the-writes).

### The writes

Both writes guard the record (`changePresences` in
`lib/src/presence/presence_writes.dart`). Before anything is sent they read
the class once and refuse, for the whole call: a date in the future, a class
the account may only view (after reading only the configuration), a
grouping class (after reading it: the error names the official class of each
pupil asked for, to call the tool with instead, as the library's `setLate`
and `setPresent` refuse a grouping class too, #110), a class or day the
module refuses to record presences for (its `saveIsAllowed`, with its
reason, yvanvds/dartschool#104), a pupil who is not listed, and a pupil whose
half-day holds anything but nothing, "Aanwezig", "Te laat" or "Te laat
zonder geldige reden", such as an absence the secretariat recorded: the
writes never overwrite another status. A pupil who already has the status
(and the motivation, when one is given) is left alone, as that read shows.

For each other pupil, `setLate` and `setPresent` get those four statuses as
their `onlyReplacing` (yvanvds/dartschool#105): the library reads the class
right before the save and refuses a half-day that changed to another status
meanwhile, without sending anything. It also refuses a pupil that read no
longer lists, with its own error (yvanvds/dartschool#116): the result says
the pupil is no longer listed in the class on that day, with the module's
reason when it lists no pupils at all. They stop at the first pupil that
fails (refused, a save the module refused, a login or connection failure).

The result says per pupil whether the status was set (and what the half-day
held right before), the pupil already had it, or was not changed or not
tried, and what the half-day holds now: as the module answered the save,
which the library returns. The class is read once more only when the change
stopped, or when a save's answer does not show the status (it holds no
record of the half-day, or another status). It is an error when the change
stopped, or when a half-day reported as set does not show the status ("NOT
what was saved"). A save whose answer was lost is reported as maybe saved,
and the class read afterwards shows whether it was. A session that
Smartschool refused for a save means it was not carried out: the library
logs in again and sends it once more, and a repeat of the session action
makes the library read the class again, so a half-day cannot be changed
twice. A save the module refused is reported with the module's reason, which
the library gives without the pupil's name (yvanvds/dartschool#109). Any
other `SmartschoolPresenceError` (the module refused a request with an error
page, or a class, code or pupil could not be found) is reported as "usually
the account lacks the right", with how to get it or turn "Aanwezigheden"
off; the library's message goes to the log only. Other codes and the
registration per lesson (which `userCanRecord` seems to stand for) are not
offered; #77 is the live check.

### Helpers and tests

Presence helpers live in `lib/src/presence/`. In `presence_access.dart`:
`withPresence`, which runs an action with a `PresenceService` on the session
and turns the module's errors into `ToolError`s (`presenceToolError`, whose
details go to the log only), and `runPresence`, which leaves them as they
are; `PresenceServices`, one service per client for a tool call, so the
configuration and the codes are read once per call; `readPresenceDay`, which
reads a class on a day (`PresenceDay`: the configuration, the class, its
codes and its pupils); the `class_id` and `date` arguments (`presenceDay`);
and `checkPresenceAccess`, the access check of `smartschool_status`. In
`presence_format.dart`: what a half-day holds (`PresenceKind`, and
`PresenceCodes`, which names a code or an alias and tells which statuses the
writes may change) and the output lines. In `presence_writes.dart`:
`changePresences`, the guarded change of the half-days of pupils one after
the other, and the arguments of the writes. In `presence_opt_in.dart`: the
presence tools behind their switch (`presenceOptIn`).

The tests run against a fake Presence module
(`test/support/fake_presence.dart`) in the shape of dartschool's trimmed
captures, with fake names: three classes (one the account may only view, one
grouping class, without codes, whose pupil's official class the account does
not see), the codes of a structure ("Aanwezig", "Te laat" with its alias,
"Doktersattest"), and pupils, each with its official class, with half-days
of each kind, each record with the name the module gives it, and a
registration per lesson; a test adds an official class in a second structure
with codes of its own. It carries out a save on the half-days as the live
module did in dartschool#2 and answers it as the module's web client reads
the answer (the records as stored), can answer it without the records,
refuse it with the module's error objects, answer it with an error page,
lose its answer or answer it without carrying it out (`nextSaves`). It
answers `getClass` as the module did live (dartschool#104): every class it
knows with its pupils, also one the account may only view, and a class
without pupils, a class ID it does not know and a day after `today` without
pupils, with `saveIsAllowed: false` and the module's reason.
