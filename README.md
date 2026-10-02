# smartschool-mcp

A local [MCP](https://modelcontextprotocol.io) server that gives Claude
Desktop, and the ChatGPT app (Codex), access to Smartschool. It is built for
teachers on Windows, and works for students too (they sign in without 2FA).
It is distributed as a Claude Desktop extension (`.mcpb`) and as an
executable that installs itself for ChatGPT (see *ChatGPT and Codex* below).

It is written in Dart on top of
[`flutter_smartschool`](https://github.com/yvanvds/dartschool) and
[`dart_mcp`](https://pub.dev/packages/dart_mcp), and compiles to a standalone
Windows executable, so users do not need Node, Python or Dart installed.

**Colleagues:** the installation guide, in Dutch, is
[docs/installatie.md](docs/installatie.md). It covers what you need, finding
the 2FA key (only for an account with 2FA), installing, testing, example
questions, updating, troubleshooting, security and privacy, and uninstalling.
For the ChatGPT app it is
[docs/installatie-chatgpt.md](docs/installatie-chatgpt.md).

## Development

Requires the Dart SDK (3.10.1 or later).

```
dart pub get
dart format .
dart analyze
dart test
```

`dart test` includes end-to-end tests that compile the executable and talk
to it over stdio, one of them in the extension folder, started the way
Claude Desktop starts it (see *Extension and releases* below). They never
contact Smartschool: the other tests use a fake Smartschool. No test asks the
real GitHub for updates either (see *Update check* below).

### Local credentials

For development the server can read its Smartschool settings from a
`credentials.yml` in the project root (git-ignored, never commit it):

```yaml
main_url: yourschool.smartschool.be
username: your.username
password: your-password
# Only for an account with 2FA (teachers): the TOTP secret.
mfa: YOUR-TOTP-BASE32-SECRET
# Optional: where save_intradesk_file and save_message_attachment save.
download_dir: C:\Users\you\Downloads\Smartschool
```

`SMARTSCHOOL_DOWNLOAD_DIR`, when set, comes before `download_dir` (see
*Saving files* below).

Pass it explicitly with `--credentials credentials.yml`; the server never
looks for the file on its own. The project's `.mcp.json` starts the server
that way, so Claude Code in this repository can use the tools live. Ask it to
call `smartschool_status` to check the login.

`test/live_test.dart` checks the login against the real Smartschool (password,
2FA, then a second start that must reuse the saved session). It is skipped
unless you opt in:

```
SMARTSCHOOL_LIVE_CREDENTIALS=credentials.yml dart test test/live_test.dart
```

Every run logs in with a fresh cookie cache, so do not run it in a loop. Its
message test only reads (it lists the inbox and archive and reads a few
messages that are already read) and uses your own cookie cache; run just that
one with `--name list_messages`. The search test only reads as well: it
searches for a word of a read message, from that message's date on, twice
(the second time from your message text cache) and for a word that occurs
nowhere, and prints counts and timings only; run it with
`--name search_messages`. The Intradesk test only
reads too (no file is downloaded): it lists the top of Intradesk and a folder,
searches with `refresh: true` (a full walk of Intradesk, a few minutes on a
large one) and then from the index, and prints counts and timings only; run
it with `--name list_intradesk_folder`. The file test downloads (never
changes) the two smallest Word, Excel, PowerPoint, PDF, PNG and JPEG files it
finds, reads them with `read_intradesk_file`, checks that a file above the
size limit is refused without downloading it, and prints formats, sizes,
character counts and timings only; run it with `--name read_intradesk_file`.
The save test saves (never changes) the smallest PDF and Word file above 5 KB
on Intradesk and the first attachment of a read message (twice, to see the
second copy get a name of its own) into a temporary download folder that is
deleted afterwards, checks their sizes and first bytes, and prints
extensions, sizes and timings only; run it with `--name save_intradesk_file`.

### Build

```
dart compile exe bin/smartschool_mcp.dart
```

This writes `bin/smartschool_mcp.exe` (git-ignored). Use `-o <path>` to put
it elsewhere. To build the Claude Desktop extension instead, see *Extension
and releases* below.

The server speaks MCP over stdin/stdout, so **stdout is reserved for the
protocol**: log to stderr (`log()` in `lib/src/log.dart`), never `print` to
stdout.

### Try it in Claude Desktop

Build the extension and double-click `smartschool-mcp.mcpb` (see *Extension
and releases* below). Or, without packing, open Claude Desktop's config file
via *Settings → Developer → Edit Config*
(`%APPDATA%\Claude\claude_desktop_config.json`) and add the server, pointing
`command` at the executable you built:

```json
{
  "mcpServers": {
    "smartschool": {
      "command": "C:\\path\\to\\smartschool_mcp.exe",
      "env": {
        "SMARTSCHOOL_MAIN_URL": "yourschool.smartschool.be",
        "SMARTSCHOOL_USERNAME": "your.username",
        "SMARTSCHOOL_PASSWORD": "your-password",
        "SMARTSCHOOL_MFA": "YOUR-TOTP-BASE32-SECRET",
        "SMARTSCHOOL_DOWNLOAD_DIR": "C:\\path\\to\\a\\folder"
      }
    }
  }
}
```

`SMARTSCHOOL_MFA` is the Base32 secret of your authenticator app (TOTP). It
is only needed for an account with two-factor authentication, as teachers
have; students who sign in with only their password leave it empty (or leave
the variable out). Spaces and hyphens in it are ignored; a value that is not
Base32 (such as the app's 6-digit code) is reported without sending the
password. When Smartschool asks for a 2FA code and the key is empty, the
server says that the account uses 2FA and that the key must be filled in.
`SMARTSCHOOL_DOWNLOAD_DIR` is optional (see *Saving files* below). Restart
Claude Desktop after editing the file. The server's stderr ends up in Claude
Desktop's MCP log (`%APPDATA%\Claude\logs\mcp-server-smartschool.log`).

Then ask Claude "Werkt mijn Smartschool-verbinding?": the
`smartschool_status` tool reports whether the settings are complete, whether
the login works and who is logged in, or what to fix.

### ChatGPT and Codex

The ChatGPT desktop app for Windows, the Codex CLI and the Codex IDE
extension start local MCP servers from `%USERPROFILE%\.codex\config.toml`
(`CODEX_HOME` when set). The ChatGPT app edits it under *Instellingen →
Plug-ins → MCP's → Toevoegen → Aangepaste MCP-server maken*: a name, the
command, its arguments and environment variables, saved as
`[mcp_servers.<name>]` and `[mcp_servers.<name>.env]`. The server runs there
unchanged, with the same `SMARTSCHOOL_*` variables. For development, the
command can be `bin\smartschool_mcp.exe` (or the one in `bundle\server`) with
the arguments `--credentials` and the path to `credentials.yml`.

**Installer.** For colleagues there is no `.mcpb`: Codex plugins cannot ask
for settings. Started with a console on stdin (a double-click) and without
`--credentials`, or with `--install`, the executable installs itself instead
of serving MCP (`lib/src/install.dart`):

- it copies itself to `%LOCALAPPDATA%\Programs\smartschool-mcp\smartschool-mcp.exe`
  (per user, no administrator rights). A copy that is running (ChatGPT open)
  is renamed out of the way first. The installer and the next server start
  delete it once it no longer runs;
- it puts that path on the clipboard (`--no-clipboard` for tests). It goes
  through the Windows API (`lib/src/clipboard.dart`), not `clip.exe`, which
  kept a byte order mark in front of the path, and ChatGPT could then not
  start the server (#49). `test/clipboard_test.dart` and a test in
  `test/install_e2e_test.dart` read the clipboard back. They run in CI, and
  locally only with `SMARTSCHOOL_MCP_CLIPBOARD_TEST=on`, since they replace
  what is on the clipboard (they put back the text that was there);
- it shows, in Dutch, what to fill in in ChatGPT: the name `smartschool`, the
  command, no arguments and the five variables. Before those steps it warns
  that what ChatGPT reads goes to OpenAI, sensitive information about pupils
  included. So: a paid plan only, with *Improve the model for everyone* off
  (#50). It waits for Enter so the window stays open.

It never touches `config.toml` and never asks for a setting: the teacher
enters the settings in ChatGPT's form, which stores them in `config.toml` in
plain text. An MCP client always starts the server with pipes, never a
console, so serving is unchanged. The release attaches the executable as
`smartschool-mcp.exe`. It is not signed, so SmartScreen warns on the
double-click; the colleague guide says what to do.

**Messages per app.** The client names itself in MCP's `initialize`
(`clientInfo.name`): Codex sends `codex-mcp-client`, Claude Desktop
`claude-ai`. The server records the app (`ClientApp` and `ClientContext` in
`lib/src/client_app.dart`). Its messages then say where to fix a setting,
what to restart and how to update in that app. Under Codex:

- the ChatGPT form, or `[mcp_servers.smartschool.env]` in `config.toml`;
- "restart ChatGPT (or Codex)";
- the download link of `smartschool-mcp.exe`, to double-click it.

Settings are named by their variable first (`SMARTSCHOOL_MFA
("2FA-sleutel")`), as the form shows them. Any other client gets the Claude
Desktop wording.

**Mistyped keys.** Codex starts a server with a cleared environment: a fixed
list of Windows variables (`WINDOWS_CORE_ENV_VARS` in openai/codex) plus the
form's. So a variable that is close to a setting's name (`SMARTSCHOOL_MAINURL`,
`SMARTSCHOOL_MFA ` with a space) or starts with `SMARTSCHOOL` comes from a
mistyped key. `smartschool_status` and the missing-settings message name it
and the setting it probably means (`MisnamedSetting` in
`lib/src/settings.dart`), never its value. `SMARTSCHOOL_MCP_*` and
`SMARTSCHOOL_LIVE_*` are not settings to begin with. Windows compares names
without case, so `smartschool_mfa` is simply the setting.

Known limits in Codex (2026):

- **Images:** image results (`read_intradesk_file` on a PNG or JPEG) do not
  reliably reach the model (openai/codex#4819, #46927).
- **Long text:** Codex cuts long tool output to the model's budget, about 10k
  tokens, well below `read_intradesk_file`'s 100,000 characters.
- **Approval:** Codex asks approval for a tool marked destructive
  (`trash_messages`, `reply_to_message`, `send_message`), unless it runs
  with *Full access*.
- **`HOME`:** Codex does not pass `HOME` on. A user who has `HOME` set gets
  another cache folder under Codex than under Claude Desktop, so the server
  logs in once more there.

`test/install_e2e_test.dart` installs the compiled server into a temporary
`LOCALAPPDATA`, and starts the installed copy with Codex's environment and
client name. It also installs again while that copy runs.

### Tools

- `smartschool_status`: whether the connection works, or what to fix, the
  download folder and whether it is writable, and whether a newer version
  is available, with its download link and what is new (see *Update check*
  below).
- `list_messages`: the headers of the inbox, sent box or archive, newest
  first, filtered by words in subject or sender, unread, and date range.
  Smartschool lists a box 50 messages at a time; the tool asks for the next
  50 only while they can change the result (more messages to show, or not
  yet past `since`), and Claude reaches older messages with `until`.
- `read_message`: one message with its recipients, its attachments
  (numbered, with name and size) and the body as plain text. It does not
  mark the message as read.
- `save_message_attachment`: saves one attachment of a message (by its
  number in `read_message`, or its file name) into the download folder and
  returns its full path, name and size (see *Saving files* below).
- `search_messages`: searches the text, subject and sender of the messages
  in the inbox and archive (or the boxes named) for words, ignoring case and
  accents, optionally within a date range, and returns the matching messages
  newest first with a snippet around the words. It downloads each message
  text once (at most 100 per search, 4 at a time, newest first) and keeps it
  in the message text cache (see below), so later searches are quick; the
  result says when messages were left unsearched. It lists the whole of each
  box searched (with `since`, only back to that date), so a search of a
  large box takes a few searches the first time.
- `archive_messages`: moves up to 100 inbox messages (ids from
  `list_messages`) to the archive and reports per id whether it was
  archived, was already in the archive, or why not. It lists the inbox (and
  the archive, for ids not in the inbox) until it has found every id. Claude
  proposes candidates when asked for advice and archives when asked to.
- `mark_messages`: marks up to 100 messages of the inbox or the archive
  (ids from `list_messages`) as read or unread; the sent box has no read
  state for the user. `read_message` leaves the read state alone: marking a
  message as read is the user's choice. It lists the box until it has found
  every id, changes the messages one at a time and reports per id the new
  state Smartschool confirmed, that the message is not in the box, or that
  Smartschool did not confirm the change. Claude proposes candidates when
  asked for advice and marks them when asked to.
- `flag_messages`: sets the colour flag (green, yellow, red or blue) of up
  to 100 messages of the inbox, the sent box or the archive, or clears it
  (`none`), one message at a time and reporting per id, like
  `mark_messages`.
- `trash_messages`: moves up to 100 messages of the inbox, the sent box or
  the archive to Smartschool's trash, one message at a time. A move, not a
  deletion: the user can restore a message from the trash in Smartschool
  until the trash is emptied, but the server cannot take it out again. So
  the tool is marked destructive (Claude Desktop asks for approval every
  time), and Claude is told to show the list and wait for the user's
  confirmation first. Each message is moved with the library's
  `moveToTrashFrom`, which names its box (the archive with its box id),
  never with `moveToTrash`, whose `quick delete` names no box and deletes a
  copy in the trash for good. Smartschool answers a move the same whether
  it moved the message or not, so each message is read back from its box
  afterwards. The result says per id: moved, not in the box, or still in
  the box after the move. A message the user sent to themselves has the
  same id in the inbox and the sent box: only the copy in the box named is
  moved.
- `reply_to_message`: sends a reply (plain text or simple Markdown) to the
  sender of a message, or with `reply_all` to everyone on it, with one `Re:`
  before the subject. A reply to a sent message goes to its recipients,
  except those in BCC. The tool is marked destructive, so Claude Desktop
  asks for approval every time, and Claude is told to show the text and
  recipients and wait for the user's confirmation first. It never sends a
  reply twice by itself: when Smartschool does not confirm a send, it says
  the reply may have been sent and to check the sent box. The reply is sent
  with the message's own reply form, so Smartschool links it to the
  original.
- `search_recipients`: the users and groups (such as a class) a new message
  can go to, found by name with the search of Smartschool's compose form
  (the library's `searchRecipientsForCompose`). Each is listed as
  `send_message` takes it, its name with its kind and id in brackets, like
  `Sven Lamber (user 146)` or `5GZ (group 298)`, then what tells namesakes
  apart (a class, a co-account, a group's description). It changes nothing
  in Smartschool: the compose form it searches on is left unused.
- `send_message`: sends a new message (plain text or simple Markdown, as
  `reply_to_message`) to recipients in To, CC and BCC, users or groups.
  Claude is told to look every recipient up with `search_recipients`, show
  the user the recipients, subject and text, and wait for the user's
  confirmation first; the tool is marked destructive, so Claude Desktop
  asks for approval every time. Each recipient is a name or a reference as
  `search_recipients` lists it; the tool looks each one up again and sends
  only when each names exactly one user or group (the name exactly,
  ignoring case and extra spaces, and the kind and id of a reference). A
  name that no one has exactly, or that several users or groups have (also
  a user and a group), stops the send before anything is sent, with who the
  search finds, for the user to choose: the tool never picks one. It sends
  once, as `reply_to_message` does (`submitOnce`).
- `search_intradesk`: searches the names of the folders, files and weblinks
  on Intradesk (not what is in the files), ignoring case and accents. Every
  word must occur in the full path and at least one in the name itself, so
  `formulier uitstap` finds `Leerkrachten / Formulieren / uitstap.docx`, while
  `formulieren` finds the folder but not every file in it. Optionally within
  one folder (`folder_id`). Returns the matches with their full path, id, size
  and date changed. It searches the Intradesk index (see below).
- `list_intradesk_folder`: what is in one Intradesk folder (the top level
  without `folder_id`), live from Smartschool: folders, files and weblinks
  with their ids.
- `read_intradesk_file`: opens one Intradesk file (id from
  `search_intradesk` or `list_intradesk_folder`) and returns its text, or an
  image, so Claude can check what is in it, quote from it or summarise it
  (see *Reading Intradesk files* below).
- `save_intradesk_file`: saves one Intradesk file into the download folder
  and returns its full path, name and size, for a file `read_intradesk_file`
  cannot read (a scan, an old Office file, any other format) or when the
  user wants the file itself (see *Saving files* below).
- `search_planners`: finds the planner of a class, a person or a room by
  name, with the planner's own search (the library's `searchCalendars`).
  Each hit is listed with its kind (class, person, room), its name, what
  the planner says about it (a class's full name, a co-account's
  "Interimaris van …", the class a pupil is listed with) and its planner
  id, like `group/4069_4256`, `user/4069_218_0` or `location/4069_<id>`,
  which `list_planner` takes. People are pupils and staff alike: the
  planner's answer does not tell them apart. A hit of another kind is shown
  without a planner id.
- `list_planner`: what is planned in a planner (`me`, the default, or a
  planner id) in a period (`from` and `until`, today to 7 days ahead by
  default), optionally only some kinds (`types`: lessons, assignments,
  empty lesson hours, other). Per day, in date order, one line per element:
  the time (`10:20–11:10`, or `08:30 (deadline)` for an assignment), the
  kind (an assignment with its type, such as `KO Kleine Overhoring`), name,
  course, classes, organiser (left out in the user's own planner), rooms
  and the element id. A class planner holds a timetable slot for every
  teacher of every hour (32 in one week of a class seen live), so at most
  200 elements are shown, with a note on how to narrow down; the request
  itself may span a school year.
- `read_planned_element`: one element in full, by its id: what its list
  line says, plus its public and private info as plain text (through
  `htmlToText`, never raw HTML), its labels, the names of its attachments
  and its weblinks, and for an assignment from when pupils see it, whether
  it was announced and its status. Private info is hidden from pupils, but
  colleagues who can see the element read it too (dartschool#84). The
  labels, attachments and weblinks are read from the detail's raw JSON
  until the library types them (yvanvds/dartschool#98, #70).
- `list_class_assignments`: the assignments (tests and tasks) of 1 to 10
  classes (`classes`, planner ids such as `group/4069_4256`) in a period
  (`from` and `until`, today to 4 weeks ahead by default), of everyone who
  plans them, read in one request (the library's `getAssignmentsOfGroups`,
  the planner's workload view). Per day, in date order, one line per
  assignment as `list_planner` writes it; a weekday without assignments
  reads `no assignments`, so free days show at a glance, and a Saturday or
  Sunday is listed only when something falls on it. When the school set a
  workload limit for a class (`getWorkloadSchedule`, a limit of 0 or more),
  the answer gives it with the planner's own figure for the days it is not
  0, such as `6A1: limit 2 per day (soft); 2026-10-06 is at 2`; the figures
  are not interpreted (at the school seen live every class had `Geen
  limiet`, and every weight was 0). It also lists the school's assignment
  types (`getAssignmentTypes`, read once per session). The tool only reads:
  choosing the moment is left to the user, with Claude.
- `plan_lesson`: fills an empty lesson hour of the user's own planner
  (`hour`, an id `planned-placeholders/…` from `list_planner` with `me`)
  with a lesson: a `name`, and optionally `public_info` (what pupils see)
  and `private_info`, written as plain text (the library's `planLesson`,
  dartschool#87). The server turns the text into the HTML the planner's own
  editor makes, escaping every character (`plainTextToHtml`: a `<p>` per
  paragraph, `<br />` per line break). Pupils of the hour's classes see the
  name and public info at once. The tool is marked destructive, so Claude
  Desktop asks for approval every time, and Claude is told to show the user
  every hour (date and time, class, course, name and info) and wait for
  the user's confirmation first; one confirmation for a week's list is
  enough, with one call per hour. The library reads the hour again and
  refuses, before sending anything, an hour that is not the user's own, or
  that the planner does not let the user fill; an hour that was filled
  since it was listed is gone under its id. It sends the fill once, never
  again after logging in again. The result gives the lesson as saved and
  its new id (the hour's id is gone), and says that `list_planner` can
  show the old state for a few seconds while `read_planned_element` is up
  to date at once.
- `edit_planned_element`: changes the `name`, `public_info` and/or
  `private_info` (plain text, as `plan_lesson`; an empty text empties an
  info) of a lesson or an assignment of the user's own planner, by its id
  (`renameElement`, `changePublicInfo`, `changePrivateInfo`, in that
  order). Marked destructive and idempotent: each change sets a value, and
  the library sends nothing for a value the element already has. The
  library refuses a colleague's element, or a change the planner does not
  allow, before sending it. When one change fails after another was saved,
  the answer says which were saved.
- `clear_lesson`: empties a lesson hour of the user's own planner again
  (`clearLesson`): the lesson, its name and info are gone, and the hour is
  an empty lesson hour with a **new** id, which the result gives. Marked
  destructive. The library refuses a colleague's lesson, and a lesson the
  planner lets the user trash or delete (one outside the timetable, which
  it does not clear), and sends the clear once.
- `list_lesfiches`: the user's lesfiches in the Lesfiches module (the
  library's `LessonContentService.getItems`, dartschool#88), read in full
  on every call: lesson lesfiches by default, or assignments or all
  (`type`), with every `label` given (the whole label, case-insensitive,
  such as `JAAR 6` and `TRIMESTER 1`) and every word of `query` in the
  name. One line per lesfiche, by name with the numbers in order (`Les 2`
  before `Les 10`): kind (an assignment with its type), name, labels,
  courses, visible or hidden in the module, the day it was last changed
  (the module's dates have no offset: Smartschool time) and its id. The
  module names a lesfiche's courses by id only (dartschool#101), so the
  tool names them after the user's own planner of the 4 weeks before and
  after today (`ownCourseNames`, one planner read per call, only when a
  lesfiche listed has a course); a course without a lesson hour there is
  "not in your planner", and when that read fails only the number of
  courses is shown. A label filter that matches nothing lists the labels
  there are. At most 200 lines, with a note to narrow the list. An answer
  of the module the server cannot use (`SmartschoolLessonContentError`) is
  "the Lesfiches module gave an answer the server could not use", with the
  details in the log only.
- `plan_lesfiche`: plans a lesson lesfiche (`lesfiche`, an id from
  `list_lesfiches`) into an empty lesson hour of the user's own planner
  (`hour`, as `plan_lesson`) with the library's `planLessonContent`
  (dartschool#88): the planner names the lesson after the lesfiche and
  takes over its content (seen live: its labels and goals; the info of the
  lesfiche tried was empty, and whether attachments and weblinks come along
  was not checked). It works as `plan_lesson` does: marked destructive, Claude shows the
  mapping of lesfiches onto hours (date and time, class, course, lesfiche)
  and plans after the user's confirmation, one call per hour, in order;
  the result gives the lesson as saved and its new id. The library reads
  the lesfiches before it plans and refuses, before sending anything, an id
  the user has no lesfiche with and an assignment lesfiche; the tool passes
  that reason on. A hidden lesfiche is planned like any other.

For the four planner writes, a write that went out without the planner
confirming it (`SmartschoolPlannerSaveUnconfirmedError`) is reported as
maybe saved, with what to read to check it, and Claude is told not to call
the tool again for it, as for a message whose send Smartschool did not
confirm. A session that Smartschool refused for a fill or a clear means the
write was not carried out: the session repeats the call, which reads the
element again (a lesson hour filled meanwhile is gone, so nothing is sent).

Message helpers for later tools live in `lib/src/messages/`: `MessageBox`
(inbox / sent / archive, their headers and one message) and `withMessages`
in `message_box.dart`, the HTML-to-text converter `htmlToText` in
`html_to_text.dart`, the Markdown-to-HTML converter for message text Claude
writes (`markdownToHtml`, which escapes all HTML) in `markdown_to_html.dart`,
who a reply goes to (`loadReplyRecipients`) in `reply_recipients.dart`, the
recipients of a new message (`searchRecipients`, `RecipientRequest`) in
`recipient_search.dart`, the filters and date-range arguments in
`message_filter.dart`, the output lines in `message_format.dart`, full-text
matching and snippets (`SearchQuery`) in `message_search.dart` and the message
text cache (`MessageTextCache`) in `message_cache.dart`.

The tools that change messages named by id share their `message_ids`
argument (`messageIdsSchema`, `messageIdsArgument`) and, for a change made
one message at a time, the per-id loop and result (`changeEach`,
`changesResult`) in `lib/src/tools/message_changes.dart`. A change that
takes a message out of its box (`trash_messages`) passes `changeEach` a
`started` map, so that a repeat of the call (after Smartschool refused the
session) does not report a message moved before as not in the box. The tools
that send a message (`reply_to_message`, `send_message`) share the submit
that is never repeated (`submitOnce`) and how its outcome is reported
(`notConfirmedResult`, `sendSummary`) in
`lib/src/tools/message_sending.dart`.

Intradesk helpers live in `lib/src/intradesk/`: `withIntradesk`, the id
argument (`intradeskIdArgument`) and listing-to-items conversion
(`intradeskItems`) in `intradesk_access.dart`; `IntradeskItem` (kind, id,
name with extension, path, size, date changed, `extension`, `mimeType`) and
`IntradeskIndex` (lookup by id, the items inside a folder) in
`intradesk_index.dart`; the tree walk (`buildIntradeskIndex`) in
`intradesk_walk.dart`; the index cache (`IntradeskIndexCache`) in
`intradesk_cache.dart`; name matching in `intradesk_search.dart` and output
lines in `intradesk_format.dart`.

Planner helpers for later tools live in `lib/src/planner/`. In
`planner_access.dart`: `withPlanner`, which runs an action on the session
and turns the planner's errors into `ToolError`s (`plannerToolError`: an
element that is gone or got a new id, an answer the server cannot use of
the planner or of the Lesfiches module, whose details go to the log only,
and a request the library refused before sending it), and
`withPlannerClient`, the same with the client itself, for a tool that also
needs the Lesfiches module; the planner ids (`PlannerRef`, `me` or `user/…`, `group/…`,
`location/…`, and `formatPlannerId`); the compound element id
`<plannedElementType>/<platformId>/<id>` (`PlannedElementRef`, which also
reads an element's detail); the `classes` argument, 1 to a maximum of
class planner ids (`classPlannersArgument`); the `from` and `until`
arguments with a default period (`plannerPeriodArguments`); and the
school's assignment types, read once per session (`AssignmentTypes.of`). In
`planner_format.dart`: dates and times in the time of this PC, a period
(`formatPlannerPeriod`), the kind and time of an element, an assignment
type (`formatAssignmentType`), one line per element (`formatElementLine`),
an element in a few words for a write's result (`formatElementSummary`),
elements per day (`elementsByDay`) and an element's detail
(`formatElementDetail`). In `planner_writes.dart`, for the tools that
change the planner: the info text Claude writes as HTML
(`plainTextToHtml`), the `hour` argument (`emptyHourArgument`), the fill of
an empty lesson hour with its result (`fillLessonHour`, which takes the
library call that fills, so a lesfiche can be planned the same way),
`withPlannerWrite` (`withPlanner`, with a note that nothing changed on an
error), and the result of a write the planner did not confirm
(`plannerWriteNotConfirmed`). `plannerToolError` passes on why the library
refused a write (`SmartschoolPlannerWriteRefusedError`). In
`lesfiches.dart`: the kinds `list_lesfiches` lists (`LesficheKind`), the
`lesfiche` argument (`lesficheArgument`), the course names from the own
planner (`ownCourseNames`, a workaround for dartschool#101), the filters
(`lesficheMatches`), the order of the names (`compareLesficheNames`) and one
line per lesfiche (`formatLesficheLine`). The tests run against a fake
planner (`test/support/fake_planner.dart`), built from dartschool's
anonymised captures of the live planner, its workload view and the
Lesfiches list, which carries out the writes of dartschool#87 (fill,
rename, change of the info, clear) and the plan of a lesfiche of
dartschool#88 as the live planner did.

Reading documents lives in `lib/src/documents/`, independent of Intradesk so
that message attachments can use it too: `readDocument(bytes, name: ...)` in
`document_reader.dart` returns a `DocumentText`, a `DocumentImage` or an
`UnreadableDocument` with the reason (in `document_content.dart`); the
readers per format are `docx_text.dart`, `xlsx_text.dart`, `pptx_text.dart`,
`pdf_text.dart`, `plain_text.dart` and `image_content.dart`. Downloads go
through `flutter_smartschool`'s streamed download with a size limit
(`IntradeskService.downloadFileStream`, `MessageAttachment.downloadStream`,
both with `maxBytes`), which also gives the file name from the
`Content-Disposition` header.

### Message text cache

`search_messages` keeps the plain text of every message it downloads, so each
message is downloaded only once (Smartschool messages do not change once
sent). The texts are in

```
%USERPROFILE%\.cache\smartschool\<username>\messages\<school address>\
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set), one small JSON file
per message (`inbox-<id>.json`, also for archived messages, and
`outbox-<id>.json` for sent ones), next to the session cookies. The server
logs the folder on first use.

Privacy: the folder holds the text of your messages, unencrypted, on this PC.
It is inside your own Windows profile, never in the project folder, and
nothing is sent anywhere; anyone who can sign in to your Windows account can
read it, just like the session cookies next to it. Deleting the folder is safe
at any time: the next search downloads the texts again. The log only shows
counts, never a search query or message text. The colleague guide
(`docs/installatie.md`) says where the folder is and what it holds.

### Intradesk index

The library has no Intradesk search (a server-side search endpoint has not
been researched), so `search_intradesk` walks the whole tree (every folder, 4
listings at a time) and keeps an index of the names, paths, ids, sizes and
dates. A walk takes minutes on a large Intradesk: about 3 minutes for one of
5900 folders and 22000 files. A tool call waits at most 40 seconds for it,
within the 60 seconds after which MCP clients such as Claude Desktop usually
give up on a call; the walk then goes on in the background. Until the first index is ready, a search says how
far the walk is and to search again; while a newer index is built, the old
one is searched, with a note.

The index is used for 24 hours, then rebuilt on the next search (which is
answered from the old index meanwhile); `refresh: true` rebuilds it at once.
It is kept in memory and in

```
%USERPROFILE%\.cache\smartschool\<username>\intradesk\<school address>\index.json
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set; about 10 MB for the
Intradesk above). The server logs the folder on first use. It holds the names and paths of what
you can see on Intradesk, not file contents. Deleting it is safe: the next
search builds it again. The log only shows counts, never a name or a query.

### Reading Intradesk files

`read_intradesk_file` downloads the file into memory (never to disk), reads
it and forgets it. What a file is follows from its content, not its name:

- Word (`.docx`), Excel (`.xlsx`) and PowerPoint (`.pptx`), and their
  macro and template variants, as text: paragraphs with `#` headings and
  `- ` list items, table rows as `cell | cell`, text boxes; every sheet under
  its name, with dates, times and percentages as Excel shows them; every
  slide with its tables and speaker notes.
- PDF, as the text of every page under its number, read by the pure-Dart
  `pdf_graphics` package (fonts, encodings and Unicode maps included). A
  scanned PDF has no text, and says so. Claude Desktop is not handed the PDF
  itself: returning it as an MCP embedded resource (`application/pdf` blob)
  did not reach the model reliably in 2026 (Claude read one as a broken
  image, modelcontextprotocol/csharp-sdk#1261; the hosted connectors drop
  the blob, anthropics/claude-ai-mcp#1086), and Anthropic's connector docs
  only promise text and image tool results.
- Text files (`.txt`, `.csv`, `.md`; UTF-8, UTF-16 or Windows-1252) as they
  are, web pages (`.html`) through the same converter as message bodies.
- Images (`.png`, `.jpg`, `.gif`, `.webp`) as MCP image content; one larger
  than 700 KB is scaled down to a JPEG (Claude Desktop refuses a tool result
  over 1 MB).
- Old Office files (`.doc`, `.xls`, `.ppt`), password-protected Office files,
  OpenDocument files and other formats are refused with the reason.

Files larger than 25 MB are not opened: refused before downloading when the
index knows the size, else as soon as Smartschool announces it or the
download goes past it, and `flutter_smartschool` then stops the transfer.
Text longer than 100,000 characters (Claude Desktop accepts about 150,000
per tool result) is cut off with a note, and a PDF stops after 30 seconds of
reading. The log shows formats, sizes and counts, never a name or any text.

### Saving files

`save_intradesk_file` and `save_message_attachment` save a file into the
download folder on this PC instead of returning what is in it. They are meant
for a Claude Cowork project: Claude there reads the files in the project's
folders (PDFs, scans, Word, Excel, images) far better than a tool result can
carry them, so point the download folder at a (temporary) folder inside the
project, and Claude opens the saved file from the path the tool returns. In a
plain chat Claude tells the user where the file is, to open it or drag it into
the chat. `read_intradesk_file` stays the quick option that works in every
chat.

The download folder is:

1. `SMARTSCHOOL_DOWNLOAD_DIR`, when set and not empty: the extension setting
   "Downloadmap" (in the extension manifest a `directory` field, so the
   install form shows a folder picker);
2. otherwise, with `--credentials`, the file's `download_dir`;
3. otherwise `%USERPROFILE%\Downloads\Smartschool` (`$HOME/Downloads/Smartschool`
   elsewhere).

`smartschool_status` shows the folder, where it was set, and whether it is
writable (it creates and deletes a test file; a folder that does not exist
yet is created on the first save).

- **Never overwrites:** a name that is taken (also by a folder, or in another
  case) gets ` (2)`, ` (3)`, ... before the extension, and the result says so.
- **Safe names:** the name Smartschool gives is made into one Windows
  accepts: `<>:"/\|?*` and control characters become `_` (so a name never
  holds a folder), dots and spaces at the end go, device names such as `CON`
  or `nul.txt` and names like the server's own files get a `_` in front, and
  a name longer than 120 characters is cut short, keeping its extension. The
  result says what changed. No name at all: `intradesk-<id>` or
  `attachment-<message id>-<number>`.
- **Size limit:** 200 MB (higher than `read_intradesk_file`'s 25 MB: nothing
  goes through the tool result). Refused before downloading when the
  Intradesk index knows the size, else as soon as Smartschool announces it
  or the download goes past it; `flutter_smartschool`'s streamed download
  (`downloadFileStream`, `MessageAttachment.downloadStream`, both with
  `maxBytes`) then stops the transfer.
- **Written under a temporary name** (`.smartschool-mcp-<random>.part`) and
  renamed once complete; a failed download leaves nothing behind.
- **Temporary by design:** the folder holds `.smartschool-mcp-downloads.json`,
  the list of the files the server saved there (name, time saved, size, time
  changed). At startup, and at most once a day (also on a save), the server
  deletes the listed files saved more than 7 days ago. It never touches any
  other file in the folder, nor a listed file that was changed since it was
  saved (that is the teacher's now: it is taken off the list). Its own
  temporary files left behind by a server that was stopped while saving are
  deleted after a day. Two servers sharing the folder each keep the list up
  to date; a save one of them misses is only never cleaned up.

The log shows sizes, timings and whether a name was changed, never a name.
The code is in `lib/src/downloads/` (`DownloadFolder` in
`download_folder.dart`, `safeFileName` in `file_names.dart`) and the tools
in `lib/src/tools/save_intradesk_file_tool.dart` and
`save_message_attachment_tool.dart`.

Privacy: saved files are personal or school data, unencrypted, in a folder
of the teacher's choice; the colleague guide (`docs/installatie.md`) says so,
and that they disappear after 7 days.

### Login

The server logs in automatically on the first tool call, including the 2FA
step (TOTP from `SMARTSCHOOL_MFA`) when Smartschool asks for one; an account
without 2FA logs in with only the password. The session cookies are kept in
`%USERPROFILE%\.cache\smartschool\<username>`, so a restart only logs in
again when the saved session has expired. The log shows which happened.

That folder is the one `flutter_smartschool` chooses
(`SmartschoolClient.cacheDir`); the server does not work it out itself. Its
own data for the user (the message texts, the Intradesk index) goes in
subfolders of it (`SmartschoolSession.cacheDirectory`), and data that
belongs to no user (the update check) in the folder above it
(`sharedCacheDirectory` in `lib/src/cache_folder.dart`).

Tools use the shared `SmartschoolSession` (`lib/src/session.dart`): call
`session.run((client) => ...)` and let its `SmartschoolProblem` propagate;
the server turns it into an error result with a message that tells the
teacher which setting to fix. When a request finds the session expired,
`flutter_smartschool` logs in again and retries that request; concurrent
requests share that one login. When Smartschool still refuses the session,
`run` runs the action once more, so an action must be safe to repeat.
Sending is not, once Smartschool has handled the submit: `reply_to_message`
and `send_message` turn a submit that Smartschool does not confirm
(`SmartschoolSendUnconfirmedError`) into a result that is not retried. A
step of the send that Smartschool refused the session for, the submit
included, sent nothing, so `run` may repeat it (see `submitOnce` in
`lib/src/tools/message_sending.dart`).

### Update check

At startup, in the background (startup never waits for it), the server asks
GitHub for the releases of this repository
(`https://api.github.com/repos/yvanvds/smartschool-mcp/releases`,
unauthenticated; the first page, with the 30 newest). GitHub leaves out
drafts; the server ignores pre-releases and tags that are not a version
(`vX.Y.Z`). It compares the highest version with the built-in one
(`lib/src/version.dart`). An empty list means that no release has been
published: nothing to report. A check waits at most 5 seconds; offline, rate
limited or an answer it does not understand is only logged.

It asks at most once a day. The time and the releases of the last successful
check (tag, release page, download links and what is new) are kept in

```
%USERPROFILE%\.cache\smartschool\smartschool-mcp-update-check.json
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set), so a restart within
24 hours does not ask again. A file of an older format is ignored. It needs no
Smartschool settings. A server that keeps running asks again after 24 hours,
on a tool call.

When a newer release exists, the first successful tool result after the
check gets one extra text after its content, for the model to pass on:

- the new version and the running one;
- "Give the user this download link": the direct link to the file for the
  app the server runs in (the release asset's `browser_download_url`):
  `smartschool-mcp.mcpb` in Claude Desktop, `smartschool-mcp.exe` under
  Codex. A release without that file gets the link to its release page
  instead;
- what to do with it: double-click it (under Codex also: restart ChatGPT);
- the release page, as a second link;
- what is new: the `## Nieuw in deze versie` section of the notes of every
  release newer than the running one, newest first, with the request to
  summarise it for the user in a few plain words. The notes are treated as
  data: only that section, as plain text (links keep their text; images,
  HTML and control characters go), at most 1,500 characters in all. Releases
  without the section (from before `CHANGELOG.md`) add nothing.

That happens once per server process (Claude Desktop starts one per session),
and not at all after `smartschool_status` showed it. Error results never get
it. `smartschool_status` always asks GitHub (while it checks the login, so it
takes no longer) and shows the same on its `Updates:` lines; its description
asks the model to give the download link and say what is new. The code is in
`lib/src/update_check.dart`; the server adds the notice in
`lib/src/server.dart`.

For tests and development:

- `SMARTSCHOOL_MCP_UPDATE_CHECK=off` turns the check off;
- `SMARTSCHOOL_MCP_UPDATE_URL=<address>` asks that address instead of the
  GitHub API (it must answer the same way, with a list of releases).

The tests use a local fake GitHub (`test/support/fake_github.dart`), whose
releases have notes as the release workflow writes them.
`ServerProcess.start` in `test/support/exe.dart` turns the check off unless a
test asks for it with its own fake, so no test and no CI run asks the real
GitHub.

A release must be tagged `vX.Y.Z` with the version in `pubspec.yaml`, be a
full release (not a draft or pre-release), carry the extension as
`smartschool-mcp.mcpb` and the server as `smartschool-mcp.exe` (the notice
links to those files), and have the `## Nieuw in deze versie` section in its
notes. The release workflow takes care of all of it (see below).

### Extension and releases

The Claude Desktop extension is described by `manifest.json` in the project
root ([MCPB manifest 0.3](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)),
next to its icon `icon.png` (a placeholder for now). Claude Desktop runs
`server/smartschool-mcp.exe` from the installed extension and passes the
fields of the install form as the `SMARTSCHOOL_*` variables. Colleagues fill
in that form, so its titles and descriptions are in Dutch, and the titles are
the ones the server's messages use (`Setting.formTitle` in
`lib/src/settings.dart`). `test/manifest_test.dart` checks the manifest
against the server: a field per setting with that title, the variables, the
tools of *Tools* above (add a tool to both, in the same order) and the icon.

The colleague guide, `docs/installatie.md`, names the same form fields, the
release asset, the question that runs `smartschool_status`, the cache and
download files, and the size and time limits. The guide for ChatGPT,
`docs/installatie-chatgpt.md`, names the release exe, the install folder, the
form with its keys, and `config.toml`. `test/guide_test.dart` checks those
against the server and the installer; it also checks the links between the
guides, and that the README, the release notes and the manifest's
`documentation` link to them. Parts that wait for the manual check in ChatGPT
are marked `TE BEVESTIGEN (#40)`. Parts that wait for the manual
install checks (#30) are marked `TE BEVESTIGEN (#30)` in HTML comments, and
missing screenshots `SCHERMAFBEELDING (#33)`.

"Downloadmap" is the only optional field, and its default is empty on
purpose: Claude Desktop passes a field without a value or a default literally,
as `${user_config.download_dir}` (modelcontextprotocol/mcpb#250), and does not
replace `${HOME}` in a default (modelcontextprotocol/mcpb#251). Empty, the
server uses its own default (see *Saving files*).

Build and pack the extension locally (`npx` needs Node):

```
dart run tool/build_bundle.dart
npx @anthropic-ai/mcpb@2.1.2 validate bundle/manifest.json
npx @anthropic-ai/mcpb@2.1.2 pack bundle smartschool-mcp.mcpb
```

`tool/build_bundle.dart` fills `bundle/` with `manifest.json`, `icon.png`,
`LICENSE` and the server, compiled to the manifest's `server.entry_point`.
`bundle/` and `*.mcpb` are git-ignored. `test/bundle_e2e_test.dart` builds
such a folder and starts the server in it from the manifest, the way Claude
Desktop does.

The version is in three files: `pubspec.yaml`, `lib/src/version.dart` and
`manifest.json`. `dart run tool/check_version.dart` fails when they differ,
with `--tag vX.Y.Z` also when the tag does, and when `CHANGELOG.md` has no
section for the version; CI runs it, and `test/version_test.dart` checks the
same.

`CHANGELOG.md` says what is new in each version, in Dutch and for colleagues:
a section under `## X.Y.Z` with a few lines on what they notice, without
technical details, links or headings of level 1 or 2. Colleagues on an older
version see it in the update notice.

To release:

1. Set the new version in the three files and write its section in
   `CHANGELOG.md`; commit and merge.
2. Tag that commit `vX.Y.Z` and push the tag.

The *Release* workflow (`.github/workflows/release.yml`, on Windows) then
checks the tag against the version, runs the tests, builds the extension,
validates and packs it with `mcpb`, and publishes a full GitHub release with
the extension attached as `smartschool-mcp.mcpb` and the server in it as
`smartschool-mcp.exe` (always those names: the update notice links to
them). `tool/release_notes.dart` writes its notes: the version's section of
`CHANGELOG.md` under `## Nieuw in deze versie` (what the update notice
shows), then `.github/release-notes.md` under `## Installeren of bijwerken`
(how to install, in Dutch, with links to both colleague guides). The
generated release notes follow. `test/release_notes_test.dart` checks that the
update check reads exactly that section back. Both workflows pin the same
`mcpb` version. The executable is not signed.

## License

GPL-3.0. See [LICENSE](LICENSE).
