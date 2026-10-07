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
# Optional: true offers the Skore tools (see Opt-in tools below).
skore: false
# Optional: true offers the presence tools (see Opt-in tools below).
presence: false
```

`SMARTSCHOOL_DOWNLOAD_DIR`, when set, comes before `download_dir` (see
*Saving files* below), `SMARTSCHOOL_SKORE` before `skore`, and
`SMARTSCHOOL_PRESENCE` before `presence`.

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
        "SMARTSCHOOL_DOWNLOAD_DIR": "C:\\path\\to\\a\\folder",
        "SMARTSCHOOL_SKORE": "false",
        "SMARTSCHOOL_PRESENCE": "false"
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
`SMARTSCHOOL_DOWNLOAD_DIR` is optional (see *Saving files* below), and so
are `SMARTSCHOOL_SKORE` and `SMARTSCHOOL_PRESENCE`, which offer the Skore
tools and the presence tools when `true` (see *Opt-in tools* below). Restart
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
  command, no arguments and the seven variables. Before those steps it warns
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

- `smartschool_status`: whether the connection works, or what to fix,
  whether each opt-in switch is on and, when it is, whether the account has
  the rights for its tools (see *Opt-in tools* below), the download folder
  and whether it is writable, and whether a newer version is available,
  with its download link and what is new (see *Update check* below).
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
  except those in BCC. Optionally with `attachments`: 1 to 10 files from
  this PC, as `send_message` takes them (below). The tool is marked
  destructive, so Claude Desktop asks for approval every time, and Claude is
  told to show the text, the recipients and every attachment with its name
  and size, and wait for the user's confirmation first. It never sends a
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
  once, as `reply_to_message` does (`submitOnce`). Optionally with
  `attachments`: 1 to 10 full paths of files on this PC (an empty list is
  none), checked before anything is sent, as `upload_intradesk_files`
  checks them (see *Uploading files* below), and uploaded by the library
  (`SendMessageParams.attachmentPaths`) into the compose form's own upload
  directory before the submit. Claude is told to show every file with its
  name and size along with the recipients, subject and text; the result
  names them, and `read_message` lists them on the sent message. A file
  Smartschool's upload step refuses stops the send before the submit, with
  Smartschool's reason: nothing was sent.
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
- `create_intradesk_folder`: adds a folder (`name`, an optional `color` of
  Intradesk's eleven, yellow by default) to an Intradesk folder
  (`folder_id`; the top of Intradesk is not offered), with the library's
  `createFolder` (dartschool#128). With `confidential`, a confidential
  folder, the only kind Intradesk adds inside a confidential folder. The
  three tools that add to Intradesk are marked destructive, so Claude
  Desktop asks for approval every time, and Claude is told to show the user
  what goes where (the folder's path, from `search_intradesk`) and wait for
  the user's confirmation first. Before sending, each reads the folder: its
  path, with the library's `getFolderPath` (its parents, then the listing
  of the top and of each folder above it, dartschool#132), and its listing,
  and refuses a name the folder holds already (any kind, ignoring case and
  spaces: Intradesk would not refuse it, but rename the new item to
  `name (1)`). The library reads the folder's entry again right before it
  sends a create (its parents and the listing of the folder above,
  dartschool#138) and refuses, with nothing sent, a folder the account may
  not add to (`canAdd`) and a folder of the wrong kind for its parent (only
  a confidential folder inside a confidential one); the tool says so in its
  own words, by the library's reason, with the folder's path. None of this
  needs the Intradesk index. The library sends a create once, never again
  after logging in again; a create Intradesk does not confirm is reported
  as maybe made, with how to check it (`list_intradesk_folder`),
  and Claude is told not to call the tool again for it. The result is the
  item as Intradesk made it (its id, the name as stored, the folder's
  path); a name Intradesk changed anyway is pointed out. What was made goes
  into the Intradesk index at once, when one is loaded, so
  `search_intradesk` finds it without walking (see *Intradesk index*
  below).
- `add_intradesk_weblink`: adds a weblink (`name`, `url`, an optional
  `icon`, `earth` by default) to an Intradesk folder, with the library's
  `createWeblink`, as `create_intradesk_folder` adds a folder. The address
  is sent as Intradesk's web client sends it (without white space, with
  `http://` in front when it has no scheme; the library's
  `normalizeWeblinkUrl`), and the result says so; an address the web client
  refuses is refused before sending. A refusal by Intradesk (HTTP 400) is
  reported with its reason, in its own words.
- `upload_intradesk_files`: uploads 1 to 10 files from this PC (`paths`,
  absolute) into an Intradesk folder, each under its own name, with the
  library's `uploadFiles`, as `create_intradesk_folder` adds a folder. The
  server reads any file the user's Windows account can read; Claude is told
  to list the files with their names and sizes and the folder with its path
  for the user's confirmation. Each path must be absolute and name an
  existing file of at most 200 MB with a name Smartschool takes, and no two
  files may have the same name (see *Uploading files* below). A file
  Smartschool's upload step refuses is reported in Smartschool's words, and
  then nothing was added; a file Intradesk did not take is listed with its
  reason next to the files it added.
- `trash_intradesk_items`: moves 1 to 20 folders, files and weblinks on
  Intradesk (`items`, each `{"kind": "folder" | "file" | "weblink", "id"}`,
  with the ids `list_intradesk_folder` and `search_intradesk` show, also a
  weblink's) to Intradesk's trash, with the library's `trashFolder`,
  `trashFile` and `trashWeblink` (dartschool#128). A move, not a deletion:
  Intradesk keeps its trash for 30 days and the user restores from it in
  Intradesk itself; the library neither reads nor restores the trash, and
  never deletes for good. The tool is marked destructive, so Claude Desktop
  asks for approval every time, and Claude is told to show the user each
  item by name and path, say that a folder goes with everything in it and
  how long the trash keeps it, and wait for the user's confirmation. It is
  marked idempotent: Intradesk answers the move of an item in the trash
  already with `204`, as the first time (so the result cannot tell the two
  apart). Before sending, it refuses an id that is not an Intradesk id, an id
  passed with two kinds, and an id the Intradesk index knows as another
  kind. The items are moved one at a time, in order, each in a session call
  of its own (the library sends a move again after logging in again, which
  is harmless); at the first failure it stops, and the result lists what was
  moved, the item that failed and what was not tried. An id Intradesk has no
  item of that kind for (an unknown id, the id of an item of another kind,
  also one in the trash, or of an item that does not exist any more) is
  reported as no such item, not moved: Intradesk answers it with `404` and
  moves nothing, which the library throws as
  `SmartschoolIntradeskItemNotFoundError` (dartschool#133, #124). Any other
  refusal (HTTP 400 to 499) is reported as not moved, with Intradesk's
  reasons; any other failure as maybe moved, with the folder to list to
  check it, as for the writes above. Items are named by their path when the
  index knows them, and the result says what the index had in a folder that
  went along. What was moved leaves the index at once (see *Intradesk index*
  below).
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
  empty lesson hours, meetings, lesson-free days, other; other holds every
  kind not named, such as excursions). The planner is asked only for
  lessons, assignments and empty lesson hours; for any other kind every
  type is read and the kinds asked for are kept (asking the planner for
  meetings or lesson-free days was never tried live). Per day, in date
  order, one line per element: the time
  (`10:20–11:10`, or `08:30 (deadline)` for an assignment), the kind
  (lesson, an assignment with its type, such as `KO Kleine Overhoring`,
  empty lesson hour, meeting, lesson-free day, or the planner's type name
  of any other type, such as `planned-excursions`), name, course,
  classes, organiser (left out in the user's own planner), rooms and the
  element id. The header counts the elements by those kinds. A
  lesson-free day can run over several days (the autumn holiday seen live
  was one element of a week) and is listed on the day it starts. A class
  planner holds a timetable slot for every teacher of every hour (32 in
  one week of a class seen live), so at most 200 elements are shown, with
  a note on how to narrow down; the request itself may span a school
  year. The header names a planner other than
  `me` from the elements read (the class, person or room they name). When
  nothing is planned there and no element read names it, the planner is
  looked up by its id with the library's `getCalendar` (one more request,
  which only reads): the header names it as the lookup does, and marks a
  person the planner counts as deleted. The planner answers a room it does
  not have, and a group its search does not offer, as an empty planner,
  without an error; when the lookup does not know the id, the answer says
  so, and to check the id with `search_planners`. When the lookup fails, a
  note says that the planner could not be named, with the details in the
  server log. The planner answers a person or class it does not have with
  HTTP 500, an error that does not say why: on a 500 for a planner other
  than `me`, the planner is looked up the same way, and when the lookup
  does not know the id either, the answer says that the planner's search
  offers no class, person or room with that id, and to check it with
  `search_planners`, rather than to try again. When the lookup names the
  planner, or fails too, the planner's error stays.
- `read_planned_element`: one element in full, by its id: what its list
  line says, plus its public and private info as plain text (through
  `htmlToText`, never raw HTML), its labels, the names of its attachments
  and its weblinks, and for an assignment from when pupils see it, whether
  it was announced and its status. Private info is hidden from pupils, but
  colleagues who can see the element read it too (dartschool#84). The
  labels, attachments and weblinks are the library's typed lists
  (dartschool#98), and every element is read by its type name, also one of
  a type the library does not know (`getPlannedElement` with `typeName`,
  dartschool#99).
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
  choosing the moment is left to the user, with Claude, and
  `plan_assignment` plans the test.
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
  courses are named as the library names them (`LessonContentCourse.name`,
  dartschool#101), after the school's course list (one request more, when
  any lesfiche has a course); a course the list does not name is an
  "unnamed course". When the course list cannot be read, the library still
  gives the lesfiches (`SmartschoolLessonContentCourseListError.items`,
  dartschool#118), and only the number of courses is shown, with a note
  when a lesfiche listed has a course. A label
  filter that matches nothing lists the labels there are. At most 200
  lines, with a note to narrow the list. An answer
  of the module the server cannot use (`SmartschoolLessonContentError`) is
  "the Lesfiches module gave an answer the server could not use", with the
  details in the log only.
- `read_lesfiche`: one lesfiche in full (`lesfiche`, an id from
  `list_lesfiches`, and `type`: `lesson`, the default, or `assignment`),
  with the library's `LessonContentService.getDetailById`
  (dartschool#129), which reads it at `lessons/{id}` or `assignments/{id}`.
  One field per line: kind (an assignment with its type), name, icon,
  labels, courses (named as `list_lesfiches` names them; when the course
  list cannot be read, `SmartschoolLessonContentCourseListError.items`
  holds the detail, and only the number of courses is shown, with a note),
  visible or hidden in the module, the weblinks (name, address, icon, when
  pupils see it, id) and the attachments (numbered, with file name, size,
  type, when pupils see it, id); then the public and private info as plain
  text (through `htmlToText`, as `read_planned_element`). When pupils see a
  weblink or an attachment (`LessonContentVisibility`) is worded from the
  lesson the lesfiche is planned in: always, never, from its start, from
  its end, or a number of days after its end; an option the library does
  not know, by the module's name for it. Weblinks of publishers and
  deeplinks are counted, not shown. The module answers a made-up id, and a
  lesfiche asked for as the other kind, with `404`
  (`SmartschoolLessonContentNotFoundError`), and an id that is not a UUID
  with a bare `500`, so that one is not sent: both say to take the id and
  the kind from `list_lesfiches`. A lesfiche in the trash is still
  answered, as live. Its description points to `edit_lesfiche` and the
  tools that change the weblinks and attachments, by the ids it shows, and
  to `trash_lesfiches`.
- `read_lesfiche_attachment`: opens one attachment of a lesfiche
  (`lesfiche`, `type`, and `attachment`: its number in `read_lesfiche`, or
  its file name, as `save_message_attachment` takes it; a name that two
  attachments have, which the module allows, asks for the number) and
  returns its text, or an image, as `read_intradesk_file` does (see
  *Reading Intradesk files* below), with the library's
  `downloadAttachmentStream`. It reads the lesfiche first, without the
  course names (one request less), and refuses an attachment that is
  larger than 25 MB by the size the lesfiche gives, or of a type that
  cannot be read by its name, without downloading it. The library sends
  the download without `Accept: application/json`: with it, Smartschool
  answered `503` (seen live).
- `save_lesfiche_attachment`: saves one attachment of a lesfiche, named
  as `read_lesfiche_attachment` names it, into the download folder and
  returns its full path, name and size, as `save_message_attachment` does
  (see *Saving files* below).
- `create_lesfiche`: makes a lesfiche in the user's own library ("Mijn
  lesfiches") of the Lesfiches module in one create, as the web client
  makes one, with the library's `LessonContentService.createLesson` or
  `createAssignment` (dartschool#129): a `name` (at most 255 characters),
  a `type` (`lesson`, the default, or `assignment` with `assignment_type`,
  one of the school's types by abbreviation or name, matched as
  `plan_assignment` matches its `type`), and optionally `public_info` and
  `private_info` (plain text, as `plan_lesson`), `courses` (each by its
  name as the tools show it, or by its id, found in the school's course
  list: one the list does not have is an error that lists the names, and a
  name two courses have one that gives their ids), `weblinks` (`{name, url,
  visibility?}`, the address as the web client sends it,
  `normalizeWeblinkUrl`; one it refuses is refused before sending),
  `attachments` (`{path, visibility?}`, 1 to 10 files from this PC,
  checked as `upload_intradesk_files` checks them, see *Uploading files*
  below) and `icon` (the web client's by default: `document_observation`
  for a lesson, `flags_red_yellow` for an assignment). A visibility is
  `always` (the default), `never`, `at_start`, `at_end` or `after_end:N`,
  N from 1 to 14 days after the end of the lesson the lesfiche is planned
  in (`LessonContentVisibility`). The own library is private to the
  teacher until a lesson is planned from the lesfiche, but the tool is
  still marked destructive (and not idempotent): it is a write that Claude
  is told to show the user first (kind, name, courses, info, each weblink,
  each file with its size, and when pupils see them) and to make once per
  lesfiche after the user's confirmation, a second call makes a second
  lesfiche, and it sends files from this PC; Claude Desktop and Codex ask
  for approval only for a tool marked destructive. Before sending, it
  reads the user's lesfiches (for the note on namesakes below, and so that
  the session's repeat of the call logs in again: the create goes out once
  only, and is refused at once on an expired session, without a login,
  dartschool#134),
  the course list for the courses, and for an assignment the school's
  types (read once per session). The library checks the courses and the
  type again, uploads the files into a new upload directory, sends the
  create once (`POST lessons/` or `assignments/`, answered `201` with the
  id only) and reads the lesfiche back. A name that is taken is kept (the
  module makes a second lesfiche, seen live), and the result names the
  other lesfiches of that name and kind. The result is the lesfiche as
  `read_lesfiche` shows it, with its id for `plan_lesfiche` (a lesson),
  `read_lesfiche` and `edit_lesfiche`, the tools that change its weblinks
  and attachments, and `trash_lesfiches` to undo it (below). Labels are
  not in the library: the description says the user sets them in the
  module. A refusal by the module (a bare `400`)
  and a file Smartschool's upload step refuses (in Smartschool's words)
  say that no lesfiche was made; a create the module does not confirm is
  reported as maybe made, with `list_lesfiches` to check it, and a
  lesfiche that was made but whose read-back failed or did not show
  everything sent (`SmartschoolLessonContentSaveUnconfirmedError` with its
  `lessonContentId`) as made, with its id and `read_lesfiche` (what is
  missing is added with `edit_lesfiche`, `set_lesfiche_weblink` or
  `add_lesfiche_attachments`); for both, Claude is told not to call the
  tool again. When the school's types
  changed since the session read them, the library refuses the type before
  sending, and the error lists the types as they are now, which every tool
  on the session takes from then on.
- `edit_lesfiche`: changes one lesfiche of the user's own library
  (`lesfiche` and `type`, as `read_lesfiche` takes them) with the
  library's edits (dartschool#129), one per field given, in this order:
  `name` (`rename`, at most 255 characters), `icon` (`changeIcon`),
  `public_info` and `private_info` (`changePublicInfo`,
  `changePrivateInfo`; plain text, as `edit_planned_element`: it replaces
  the whole info, and an empty text empties it), `courses`
  (`changeCourses`, by name or id as `create_lesfiche` takes them, in place
  of all its courses; an empty list removes them) and `visible`
  (`setVisible`: shown or hidden in the module; a hidden lesfiche is still
  listed and can still be planned). Marked destructive (as
  `create_lesfiche`, for Claude Desktop and Codex to ask approval) and
  idempotent: each edit sets a value. Claude shows the lesfiche and what
  changes, and calls after the user's confirmation. The tool reads the
  lesfiche first (the edits take it as read) and, for `courses`, the
  school's course list, so that an unknown course is refused before any
  edit; the library checks the courses again. It stops at the first edit
  that fails, and says which fields were changed before it and which were
  not sent, as `edit_planned_element` does; a field that already had the
  value given is sent all the same, and the result says so. The edits
  answer with the whole lesfiche, but only `changeCourses` names its
  courses, so the result reads the lesfiche once more at the end and gives
  it as `read_lesfiche` shows it (`lesficheChangedResult`, in a session
  action of its own); when that read fails, the result says what changed
  and to read it with `read_lesfiche`. A lesfiche in the trash is still
  read, but its edits are answered `404` (seen live,
  `SmartschoolLessonContentNotFoundError`): the error says that it is in
  the trash or no longer exists, and that the user restores it in the
  module; an id or kind that is wrong is the `404` of the read before
  (take them from `list_lesfiches`). An edit the module does not confirm
  (`SmartschoolLessonContentSaveUnconfirmedError`) is reported as maybe
  saved, with what was changed before it and `read_lesfiche` to check it.
  The library retries an edit after logging in again, as a read. Whether a
  lesson planned from the lesfiche earlier changes with it has not been
  checked (#117): the descriptions of these tools do not promise it.
- `set_lesfiche_weblink`: adds a weblink to a lesfiche (`addWeblink`), or,
  with `weblink_id` (as `read_lesfiche` shows it), changes one
  (`changeWeblink`): `name`, `url` (sent as the web client sends it, as
  for `create_lesfiche`), and optionally `icon` (`earth` for a new one)
  and `visibility` (as for `create_lesfiche`). A change sends every value:
  the icon and the visibility that are not given stay as the weblink has
  them. Marked destructive, and not idempotent: a second add adds a second
  weblink. The tool reads the lesfiche first, in the session action of the
  write: the library takes it as read, a weblink id the lesfiche does not
  have is refused before sending (with its weblinks and their ids), and,
  since the library sends an add once only, never again after logging in
  again, it is that read that logs in again when the session repeats the
  call (dartschool#134). The result says what was added or changed, with
  the weblink's id, and gives the lesfiche as `read_lesfiche` shows it. A
  refusal by the module (a bare `400`) says that nothing changed; an add
  the module does not confirm is maybe added, with `read_lesfiche` to check
  it and not to call again; a `404` is the trash, as for `edit_lesfiche`,
  or a weblink removed meanwhile.
- `remove_lesfiche_weblink`: removes one weblink of a lesfiche
  (`weblink_id`) with `removeWeblink` (a `DELETE`, answered `204`). Marked
  destructive and idempotent. It reads the lesfiche first and refuses a
  weblink id it does not have before sending; the result names the weblink
  removed and gives the lesfiche. A removal the module does not confirm is
  maybe removed, with `read_lesfiche` to check it.
- `add_lesfiche_attachments`: adds files from this PC (`attachments`,
  `{path, visibility?}`, 1 to 10, checked as for `create_lesfiche`, see
  *Uploading files* below) to a lesfiche with `addAttachments`: the
  library reads the lesfiche, uploads the files into a new upload
  directory, has the module take them once (never again after logging in
  again), and then sets each visibility other than `always`
  (`changeAttachmentVisibility`): the module gives every new attachment
  `always`, and ignores the visibility sent with them (seen live). Marked
  destructive, and not idempotent: a second call adds the files a second
  time. The tool reads the lesfiche first in the session action, as
  `set_lesfiche_weblink` does (dartschool#134). The result lists the
  attachments added with their ids, notes a name the lesfiche had already
  (the module keeps both), and gives the lesfiche. A file the upload step
  refuses (in Smartschool's words), a refusal and a `404` say that nothing
  changed. When the module took the files and only setting a visibility
  failed (`SmartschoolLessonContentVisibilityNotSetError`, dartschool#135,
  #126), the result is an error that lists the attachments added, with
  their ids and their visibility as far as the library knows, says why the
  visibility was not set (refused: not set; not confirmed: maybe set; the
  session refused: not set), and gives each visibility not set (that one,
  and those after it, which the library did not try) as a call of
  `set_lesfiche_attachment_visibility`, without reading the lesfiche: the
  files are on it, so not to call the tool again. A take the module does
  not confirm (any other `SmartschoolLessonContentSaveUnconfirmedError`)
  says that the files may or may not have been added, or added with
  `always`, and not to call again but to read the lesfiche and set a
  visibility with `set_lesfiche_attachment_visibility`.
- `set_lesfiche_attachment_visibility`: sets when pupils see one
  attachment of a lesfiche (`attachment_id`, as `read_lesfiche` shows it,
  and `visibility`) with `changeAttachmentVisibility`. Marked destructive
  and idempotent. It reads the lesfiche first and refuses an attachment id
  it does not have before sending; the result says what the visibility was
  before, and gives the lesfiche.
- `remove_lesfiche_attachment`: removes one attachment of a lesfiche
  (`attachment_id`) with `removeAttachment` (a `DELETE`, answered `204`).
  Marked destructive and idempotent; the description points to
  `save_lesfiche_attachment` to keep a copy. It reads the lesfiche first
  and refuses an attachment id it does not have before sending; the result
  names the file removed with its size, and gives the lesfiche.
- `trash_lesfiches`: moves lesfiches of the user's Lesfiches module
  (`lesfiches`, 1 to 20 ids from `list_lesfiches`, lessons and assignments
  together) to the module's trash with the library's `trash`
  (dartschool#129): one `POST lesson-content/trash/bulk` for all of them,
  after which `list_lesfiches` no longer lists them (their detail is still
  read). The library takes each lesfiche as listed, with its kind and
  platform, so the tool reads the list first (`getItems`, without the
  course names), in the session action of the move, and matches the ids
  (ignoring case, each once); an id that names no listed lesfiche is
  refused before anything is sent, with a note that a lesfiche in the
  trash is not listed, and so is a lesfiche of a kind the library cannot
  write. A move, not a deletion: the user restores a lesfiche from the
  trash in the module itself, and the library neither restores nor deletes
  for good (`delete/bulk` is left out on purpose). A lesson planned from a
  lesfiche earlier stays in the planner, which copied the lesfiche (#117
  checks how much); the description says so. Marked destructive, for
  Claude Desktop and Codex to ask approval: Claude shows each lesfiche by
  name and kind, and calls once after the user's confirmation. Idempotent,
  as `remove_lesfiche_attachment`: a second call finds the lesfiches no
  longer listed and sends nothing. The result lists the lesfiches moved,
  one line each as `list_lesfiches` shows them (their courses counted).
  The library retries the move after logging in again, as a read. The
  module answers the move of a lesfiche that is in the trash already with
  a bare `500` (seen live; it was moved there after the tool read the
  list), and an answer whose `exceptions` are not empty is not confirmed
  either (`SmartschoolLessonContentSaveUnconfirmedError`): the result says
  that some or all of them may or may not have been moved, and to check
  with `list_lesfiches` which are still listed. A refusal by the module
  (`400` to `499`) says that none was moved.
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
  the user has no lesfiche with and an assignment lesfiche; the tool says so
  in its own words and points to `list_lesfiches`. A hidden lesfiche is
  planned like any other. Its description points to `create_lesfiche` for
  a lesfiche that does not exist yet.
- `plan_assignment`: plans an assignment (a test, a task, something to
  bring along) in one of the user's own lesson hours (`hour`, an empty
  lesson hour or a lesson from `list_planner` with `me`) with the library's
  `planAssignment` (dartschool#89): of a `type`, by abbreviation or name
  (`KO`, `Kleine Overhoring`), matched against the school's types (read
  once per session; one that matches none is an error that lists them),
  with a `name` and optionally `public_info` and `private_info` (plain
  text, as `plan_lesson`). The server reads the hour's detail and takes
  from it the classes (all of them, or those `classes` names, by name or
  planner id; a class that is not the hour's is an error), the course (the
  first), the rooms and the period: the assignment is due at the start of
  the hour and runs to its end, and the hour itself stays as it is. The
  library's create takes no hour, so the server refuses an hour that is not
  the user's own, and one without classes or a course, before sending
  anything. Pupils of the classes see the assignment at once; it is not
  announced (Smartschool's "aankondigen" is not offered). Marked
  destructive, not idempotent: Claude is told to check the class's other
  tests with `list_class_assignments` first, to show the user the classes,
  the date and hour, the type, the name and the info, and to wait for the
  user's confirmation. The library checks the type against the school's
  types again; when the school no longer has it (the types changed since
  the session read them), the error lists the types that check read (the
  library's refusal carries them, dartschool#119), and every tool on the
  session takes them, without reading them again. The library sends the
  create (`POST planned-assignments/blanco?waitForRefresh=true`, answered
  `201`) once. The result gives the assignment as saved, with its id. Its
  name and info change with `edit_planned_element`; its date, type and
  classes do not change.
- `trash_assignment`: moves an assignment of the user's own planner (`id`)
  to the planner's trash (`trashAssignment`, dartschool#89). Smartschool
  keeps it there for 30 days, and it can be restored in Smartschool itself;
  the tool restores nothing and never deletes for good. Marked
  destructive, not idempotent; Claude is told to say that it can be
  restored. The library reads the assignment again and refuses, before
  sending anything, a colleague's assignment, one the planner does not let
  the user trash (`canUserTrash`) and one with a linked Skore evaluation; it
  sends the trash once, and confirms it by reading the assignment again
  (the planner answers `404`).

For the six planner writes, a write that went out without the planner
confirming it (`SmartschoolPlannerSaveUnconfirmedError`) is reported as
maybe saved, with what to read to check it, and Claude is told not to call
the tool again for it, as for a message whose send Smartschool did not
confirm (for a new assignment: the class's assignments, with
`list_class_assignments`). A session that Smartschool refused for a fill, a
clear, a create or a trash means the write was not carried out: the session
repeats the call, which reads the element again (a lesson hour filled
meanwhile is gone, so nothing is sent).

The Skore tools are offered only when the switch "Skore-beheer" is on (see
*Opt-in tools* below): they need the rights for score management in Skore
(Rapporten > Modellen and Puntenboeken), as a Skore administrator has, and
most teachers and all pupils lack them. The first four read Skore with the
library's `SkoreService` (dartschool#70, dartschool#74) and change nothing;
the last four assign teachers to courses (dartschool#71) and share
gradebooks (dartschool#74):

- `list_skore_classes`: the classes of Skore's report models
  (`getClasses`), one line per class with its name, Skore class id, group
  and report model, in Skore's order. `query` keeps the classes whose name
  or group holds every word (ignoring case and accents, as
  `search_messages`), since a school has many classes. The class id is
  Skore's own, not a planner id.
- `list_skore_courses`: the courses of one class (`class_id`, from
  `list_skore_classes`) with the teachers assigned to each, Skore's
  "lesopdrachten" (`getCourses`), in Skore's order and indented by depth.
  Per row: its label, course id, code and depth, and then its teachers
  with their teacher id and assignment id (which is also the gradebook's
  id), or, without any, that it is a group header (which cannot get a
  teacher), a course with sub-courses (which needs no teacher of its own:
  its sub-courses carry the assignments, as a Skore administrator
  confirmed in #100), or a course with no teacher. A row is a course with
  sub-courses when the next row is deeper: the tree tells it, not the
  labels. The first line counts the courses, those that still need a
  teacher (no teacher and no sub-courses), and the group headers; the
  description tells Claude that only the courses marked "no teacher"
  still need one. Course codes are not unique within a
  class (a course and its sub-course can share one), so the description
  tells Claude to name a course by its id. An empty list means a class
  without a course structure or an unknown id; the result says so.
- `list_skore_teachers`: the teachers Skore lets assign to a course
  (`getTeachers`), by name with their teacher id (the Smartschool user id),
  in Skore's order; `query` as for `list_skore_classes`.
- `list_skore_gradebook_shares`: the gradebooks of one teacher
  (`teacher_id`, the owner; `getGradebookShares`), as Skore's "share
  gradebooks" manager shows them (Puntenboeken), one line per gradebook in
  Skore's order: its course, class and gradebook id, and its readers and
  writers by name, joined with `getTeachers` (a teacher Skore no longer
  lists shows by teacher id only). The gradebook id is the assignment id of
  `list_skore_courses`, and the owner the teacher of that assignment. An
  empty list means a teacher without gradebooks or an unknown id; the
  result says so.
- `add_skore_teacher`: assigns a teacher (`teacher_id`, from
  `list_skore_teachers`) to a course (`course_id`) of a class (`class_id`),
  with the library's `addTeacher`: a new assignment, which holds all pupils
  of the class; the teachers already on the course keep theirs. Marked
  destructive, not idempotent: Claude is told to read the class and look up
  the teacher first, to show the user the class, the course's label, its
  teachers now and the teacher to assign, and to wait for the user's
  confirmation; that nothing needs to happen when the teacher is already on
  the course; and to use `replace_skore_teacher`, not this tool, to give a
  course another teacher. The result gives the assignment as saved: the
  course's label, the class id, the teacher and the assignment id.
- `replace_skore_teacher`: gives an assignment (`assignment_id`, from
  `list_skore_courses`) of a course of a class another teacher
  (`teacher_id`), with `replaceTeacher`: the assignment keeps its id, and
  its gradebook stays. Marked destructive, not idempotent, with the same
  confirmation. Before the save the library asks Skore (`getMyGroups`)
  whether the current teacher works with "Mijn lesgroepen" for the course;
  if so, nothing is saved (`SmartschoolSkoreMyGroupsError`), and Claude is
  told to leave those groups to the user in Skore: the library never deletes
  them (`explodeMyGroups`), and the tool tries no other way; the message
  names that teacher, as the library read them. The result also names the
  teacher replaced.
- `share_skore_gradebook`: shares a gradebook (`owner_id`, `gradebook_id`)
  with one or more teachers (`teacher_ids`, 1 to 50) with `read` or `write`
  access (`access`), with `shareGradebook`, once per teacher, one after the
  other: sharing with all teachers of a class takes one confirmation, not
  one per teacher. The teachers it is already shared with keep their
  access; a teacher with the other access moves to the access given.
  Marked destructive (sharing gives colleagues access to pupils' scores),
  and idempotent: sharing again the same way saves nothing. Claude is told
  the typical flow (the class, its courses, the assignment of the
  titularis, then the other teachers of the class, all from
  `list_skore_courses`), to read the gradebook with
  `list_skore_gradebook_shares` first, and to show the user the gradebook
  (course and class), the teachers and the access and wait for the user's
  confirmation.
- `unshare_skore_gradebook`: stops sharing a gradebook with one or more
  teachers, with `unshareGradebook`, likewise; the other teachers keep
  theirs, and a teacher Skore no longer lists can still be taken off.
  Marked destructive and idempotent, with the same confirmation.

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
and class) from the first result; when the save for the first teacher is
not confirmed, from the library's error, which carries the gradebook as it
was read before the save (`SmartschoolSkoreShareSaveUnconfirmedError`,
dartschool#120). So it names the gradebook by its id only when it stopped at
the first teacher before a save, and then gives no readers and writers
either. Before each change the library
reads the gradebooks (and, to share, the teachers) again and refuses the
owner among the teachers, a gradebook that is not the owner's, and, to
share, a teacher Skore does not list
(`SmartschoolSkoreChangeRefusedError`); the tool passes the reason on, and
tells Claude to read the gradebook again. The save (`saveShared`) holds the
complete readers and writers of that one gradebook, the ids as numbers, so
sending it again does not change the outcome: the library sends it again
after logging in again. It reads the gradebooks again after the save, so a
teacher reported as done is certain; a save that Skore or that read does
not confirm (`SmartschoolSkoreSaveUnconfirmedError`) is reported as maybe
saved, with what to look for in `list_skore_gradebook_shares`, and Claude is
told not to call the tool again for it. Sharing from a teacher's own
account, without the rights (Skore's `/SkoreGradebook`), is not offered: the
library does not support it.

For both writes on assignments, the library reads the class (`getCourses`) and the teachers
(`getTeachers`) again and refuses, before saving, a course that is not in the
class or is a group header, an assignment that is not the course's, a
teacher already on the course (for a replace, its current one too) and one
Skore does not let assign (`SmartschoolSkoreChangeRefusedError`); the tool
passes the reason on, says that nothing was changed, and tells Claude to read
the class again. The save (`saveOwner`) is sent once, never again after
logging in again. A save that Skore does not confirm
(`SmartschoolSkoreSaveUnconfirmedError`: another answer, an error page, a
connection lost after it went out) is reported as maybe saved, with what to
look for in `list_skore_courses`, and Claude is told not to call the tool
again for it, as for a message whose send Smartschool did not confirm. A
session that Smartschool refused for the save means the save was not carried
out: the session repeats the call, which reads the class again, so a teacher
who is on the course by then is refused rather than added twice. The writes
return the assignment with the course as the library read it before the
save, and for a replace the assignment as it was (`SkoreSavedAssignment`,
dartschool#102), so the tools name the course and the teacher replaced
without a read of their own. A save that Skore does not confirm returns
nothing, but the library's error carries the same
(`SmartschoolSkoreAssignmentSaveUnconfirmedError`, dartschool#120): its
result names the course by its label, and for a replace the teacher the
assignment had, as the library read them before the save (a read afterwards
cannot tell what was there before a save that may have gone through).
Removing an assignment, choosing its pupils and Skore's import of
assignments are not offered.

Skore refusing a request to the account
(`SmartschoolSkoreAccessDeniedError`) is reported as an account without the
rights, with the part of Skore it was refused, what rights are needed, and
to ask the school's Smartschool administrator for them or turn
"Skore-beheer" off. Skore sends every request of a teacher without the
rights on to Smartschool's start page (seen live, yvanvds/dartschool#91),
never with an empty list, and the library reports that from every call as
that error (as it does HTTP 403). Any other `SmartschoolSkoreError` is an
answer the server could not use, and is reported as such, with "try again
in a moment"; the library's message goes to the log only, as it can quote
the page. From a write, each of these errors also says that nothing was
changed in Skore. What Skore answers a pupil, and an account with only one
of the two parts of the rights, was not captured.

The presence tools are offered only when the switch "Aanwezigheden" is on
(see *Opt-in tools* below): they need the right to record half-day
presences for classes in Smartschool's Presence module, as the absence
administrators of a school (often the pupil secretariat) have; most teachers
and all pupils lack it. The half-day registration (a morning and an
afternoon per pupil per day, `DayPart`) is the one that counts for the
government; the registration per lesson is a different one and is not
offered. The tools use the library's `PresenceService` (dartschool#2); the
first two only read, the last two change the presences of pupils:

- `list_presence_classes`: the classes the account may view in the module
  (`getConfig`: its allowed classes, and the active class when it is not
  among them; not the placeholder "Uit Planner", class id -2, that the
  module gives as the active class of a teacher without a lesson at the
  moment, #84, which the library keeps apart as `activePlaceholder`,
  yvanvds/dartschool#117), one line per
  class with its name, class id (`groupID`), and whether the account may
  record presences for it (`userCanConfirm`: "may record" or "view only";
  not `userCanRecord`, which a teacher without the absence-administrator
  rights has for every class, #95 and yvanvds/dartschool#121); a
  grouping class without a school structure is marked, as presences are
  recorded in the pupils' official class, with the classes it groups when
  the module names them (`downStreamGroupIds`, yvanvds/dartschool#126,
  #110): `groups 2A MAW (class id 1652), 2A ECO (class id 1968)`, each by
  name and class id, or by class id alone ("not among the classes this
  account may view") when the configuration does not list it, as for an
  account without the absence-administrator rights, which is listed fewer
  classes. Seen live for 6 of the school's 17 grouping classes, the
  official classes of a year; for the others (such as "Taalatelier groep
  1") and for every official class nothing is said, not "groups none": the
  list is not the official classes of the pupils (the grouping class 2C
  listed a pupil of 2E ECO).
- `list_class_presences`: the pupils of one class (`class_id`) on one day
  (`date`, default today) with what their morning and afternoon hold
  (`getClassPupils`), named with the codes of the class's structure
  (`getAllCodes`): a code (`"Aanwezig"`, `"Te laat"`, `"Doktersattest"`), an
  alias with its code (`"Te laat zonder geldige reden" (under "Te laat")`),
  or "nothing recorded", with its motivation, and per pupil the pupil id the
  writes take. A grouping class has no structure, so the module gives no
  codes for it, while its pupils' half-days hold the codes of their official
  classes (seen live: every half-day of the grouping class 2A held code id
  70, "Aanwezig" in the official class 2A ECO, #99). Its statuses are named
  as the module names them with each record (`PresenceHalfDay.statusName`,
  given with every record seen live, yvanvds/dartschool#126), without
  reading codes; a half-day the module gives no name with (not seen live)
  is named with the codes of the structure of the pupil's official class
  (`PresencePupil.officialClassId`, one `getAllCodes` per distinct
  structure, after the pupils), or by its code id when the account does not
  see that class (#101). In a grouping class, each pupil's line also names
  the pupil's official class, where the writes record its presences
  (`official class: 2A ECO (class id 1968)`; by class id alone when the
  account does not see it, or "none given by the module", not seen live;
  #110). A half-day of any class whose code is not among
  the codes read is named likewise. Rows per lesson are left out (the
  library ignores them). When the module lists no pupils, the tool gives the
  module's reason
  (`errorMessage`, yvanvds/dartschool#104), as seen live: "Deze klas bevat
  geen leerlingen." for a class without pupils, "Het is niet mogelijk om in
  de toekomst afwezigheden op te nemen." for a day in the future.
- `set_pupils_late`: marks pupils (`pupil_ids`, 1 to 50) of a class late for
  the morning or the afternoon (`part`) of a day (`date`), with `setLate`:
  "Te laat", or with `without_valid_reason` "Te laat zonder geldige reden",
  with an optional `motivation` (at most 500 characters), once per pupil, one
  after the other: a group from a late bus takes one confirmation. Marked
  destructive (a half-day is an official record about pupils) and
  idempotent: a pupil who already has the status (and the motivation, when
  one is given) is left alone, and nothing is saved for them. Claude is told
  to read the class with `list_class_presences` first, to show the user the
  class, the pupils by name, the half-day, the status and the motivation, and
  to wait for the user's confirmation.
- `set_pupils_present`: marks pupils present ("Aanwezig") likewise, with
  `setPresent` and the same arguments without `without_valid_reason`: for
  example to undo a "Te laat" recorded by mistake.

Both writes guard the record (`changePresences` in
`lib/src/presence/presence_writes.dart`). Before anything is sent they read
the class once and refuse, for the whole call: a date in the future, a class
the account may only view (after reading only the configuration), a
grouping class (after reading it: the error names the official class of
each pupil asked for, to call the tool with instead, as the library's
`setLate` and `setPresent` refuse a grouping class too, #110), a class or
day the module refuses to record presences for
(its `saveIsAllowed`, with its reason, yvanvds/dartschool#104), a pupil who
is not listed, and a pupil whose half-day holds anything but nothing,
"Aanwezig", "Te laat" or "Te laat zonder geldige reden", such as an absence
the secretariat recorded: the writes never overwrite another status. A
pupil who already has the status (and the motivation, when one is given) is
left alone, as that read shows. For each other pupil, `setLate` and
`setPresent` get those four statuses as their `onlyReplacing`
(yvanvds/dartschool#105): the library reads the class right before the save
and refuses a half-day that changed to another status meanwhile, without
sending anything. It also refuses a pupil that read no longer lists, with
its own error (yvanvds/dartschool#116): the result says the pupil is no
longer listed in the class on that day, with the module's reason when it
lists no pupils at all. They stop at the first pupil that fails (refused,
a save the module refused, a login or connection failure). The result says per
pupil whether the status was set (and what the half-day held right before),
the pupil already had it, or was not changed or not tried, and what the
half-day holds now: as the module answered the save, which the library
returns. The class is read once more only when the change stopped, or when
a save's answer does not show the status (it holds no record of the
half-day, or another status). It is an error when the change stopped, or
when a half-day reported as set does not show the status ("NOT what was
saved"). A save whose answer was lost is reported as maybe saved, and the
class read afterwards shows whether it was. A session that Smartschool
refused for a save means it was not carried out: the library logs in again
and sends it once more, and a repeat of the session action makes the
library read the class again, so a half-day cannot be changed twice. A save
the module refused is reported with the module's reason, which the library
gives without the pupil's name (yvanvds/dartschool#109). Any other
`SmartschoolPresenceError` (the module refused a request with an error
page, or a class, code or pupil could not be found) is reported as "usually
the account lacks the right", with how to get it or turn "Aanwezigheden"
off; the library's message goes to the log only. Other codes and the
registration per lesson (which `userCanRecord` seems to stand for) are not
offered; #77 is the live check.

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
that send a message (`reply_to_message`, `send_message`) share their
`attachments` argument (`messageAttachmentsSchema`,
`messageAttachmentsArgument`, `messageAttachmentsDescription`, through the
local-file helper), the submit that is never repeated (`submitOnce`, which
also turns a refused upload into a `ToolError` with `uploadToolError`) and
how its outcome is reported (`notConfirmedResult`, `sendSummary`) in
`lib/src/tools/message_sending.dart`. Their tests run against a fake
Messages module (`test/support/fake_messages.dart`) whose compose forms each
open their `randomDir` in the fake upload step, bound to the session the
form was loaded in (an upload into it from another session fails the test),
and whose submit sends the files of that directory with the message.

Intradesk helpers live in `lib/src/intradesk/`: `withIntradesk`, the id
argument (`intradeskIdArgument`) and listing-to-items conversion
(`intradeskItems`) in `intradesk_access.dart`; `IntradeskItem` (kind, id,
name with extension, path, size, date changed, `extension`, `mimeType`) and
`IntradeskIndex` (lookup by id, with `findItem` for a weblink too, the items
inside a folder) in
`intradesk_index.dart`; the tree walk (`buildIntradeskIndex`) in
`intradesk_walk.dart`; the index cache (`IntradeskIndexCache`, with `patch`
for what a write added or removed) in `intradesk_cache.dart`; name matching
in `intradesk_search.dart` and output lines in `intradesk_format.dart`. In
`intradesk_writes.dart`, for the tools that add to Intradesk: the
`folder_id` and `name` arguments (`intradeskFolderArgument`,
`intradeskNameArgument`), the folder read before a write
(`readIntradeskParent`, an `IntradeskParent` with its path and listing,
which refuses a taken name), `withIntradeskWrite` (the library's refusals
as `ToolError`s that say nothing was added, among them its refusal of a
folder without `canAdd` or of the wrong kind, worded by its reason), the
result of a write Intradesk did not confirm
(`intradeskWriteNotConfirmed`) and the index patch after a write
(`addToIntradeskIndex`); a header note says why the session's repeat of a
write cannot add twice. `trash_intradesk_items` reads nothing before its
moves but the index, and keeps its helpers to itself. The tests run against
a fake Intradesk (`test/support/fake_intradesk.dart`) that carries out the
creates, the upload and the moves to the trash of dartschool#128 as the
live Intradesk did (renaming a taken name, the bare `500`s, the `400`s with
`violations`, a `204` for an item in the trash already, and a bare `404`
for the move of an id it has no item of that kind for, as captured in
dartschool#133), behind the fake upload step
(`test/support/fake_uploads.dart`) that the attachments of lesfiches and
messages share.

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
school's assignment types, read once per session (`AssignmentTypes.of`),
and replaced by those the library's check read when it refused a type the
school no longer has (`replace`). In
`planner_format.dart`: dates and times in the time of this PC, a period
(`formatPlannerPeriod`), the kind and time of an element, an assignment
type (`formatAssignmentType`), one line per element (`formatElementLine`),
an element in a few words for a write's result (`formatElementSummary`),
elements per day (`elementsByDay`) and an element's detail
(`formatElementDetail`). In `planner_writes.dart`, for the tools that
change the planner: the info text Claude writes as HTML
(`plainTextToHtml`), the `hour` argument (`emptyHourArgument`), the fill of
an empty lesson hour with its result (`fillLessonHour`, which takes the
library call that fills, so a lesfiche can be planned the same way), the
lesson hour, the classes and the type of a new assignment
(`lessonHourArgument`, `lessonHourClassesArgument`, `lessonHourClasses`,
`assignmentTypeArgument`), `withPlannerWrite` (`withPlanner`, with a note that nothing changed on an
error), and the result of a write the planner did not confirm
(`plannerWriteNotConfirmed`). `plannerToolError` says why the library
refused a write (`SmartschoolPlannerWriteRefusedError`) in the tools' own
words, from its reason (`PlannerWriteRefusalReason`, dartschool#100): the
element by its kind, name, day, time, classes and course, who organises a
colleague's element, which capability the planner does not set, and what
to do next (`list_planner`, `list_lesfiches`, or Smartschool itself). The
library's message, written for a developer, goes to the log only. Its
switch has no default, so a reason a later version of the library adds
fails the build. In
`lesfiches.dart`: the kinds `list_lesfiches` lists (`LesficheKind`), the
`lesfiche` argument (`lesficheArgument`), the filters (`lesficheMatches`),
the order of the names (`compareLesficheNames`), one line per lesfiche
with its courses as the library names them (`formatLesficheLine`), and the
notes on courses the course list does not name or could not name
(`unnamedLesficheCourseNote`, `lesficheCourseListNote`). In
`lesfiche_detail.dart`, one lesfiche in full, for `read_lesfiche` and the
tools that make or change a lesfiche, which give it back in the same
form: the `type` argument of a tool that takes one lesfiche
(`lesficheTypeSchema`, `lesficheTypeArgument`), the read of its detail
(`readLesficheDetail`, which keeps the detail when the course list fails
and turns a `404` into "take the id and the kind from `list_lesfiches`",
`lesficheNotFound`), the lesfiche as text (`formatLesficheDetail`, with
`formatLesficheWeblink`, `formatLesficheAttachment` and
`formatLesficheVisibility`, the wording of a `LessonContentVisibility`), the
`visibility` of a weblink or an attachment that a write takes
(`lesficheVisibilityArgument`, `lesficheVisibilitySchema`,
`lesficheVisibilityValues`: `always`, `never`, `at_start`, `at_end`,
`after_end:N`), the lesfiche in a few words (`lesficheTitle`,
`lesficheKindName`), and the `attachment` argument of the tools that read
or save one (`lesficheAttachmentSchema`, `lesficheAttachmentArgument`,
`pickLesficheAttachment`, `findLesficheAttachment`,
`lesficheAttachmentTitle`). In `lesfiche_writes.dart`, for the tools that
make or change a lesfiche or move it to the trash: the `name`, `courses`,
`weblinks` and `attachments` arguments, checked before anything is sent
(`lesficheNameArgument`; `lesficheCoursesArgument` with `lesficheCourses`,
which finds them by id or name in the school's course list;
`lesficheWeblinksArgument` with `lesficheWeblinkArgument`;
`lesficheAttachmentsArgument`, `{path, visibility?}` through the
local-file helper, with `lesficheAttachments`; and their schemas),
the weblink or attachment a tool names by its id
(`lesfichePartIdArgument`, `lesficheWeblinkById`,
`lesficheAttachmentById`), `withLesficheWrite` (the session runner for a
write, with the library's errors as `ToolError`s that say nothing was made
or changed, `lesficheWriteToolError`; a `404` of a write says that the
lesfiche is in the trash), the result of a write the module did not
confirm (`lesficheWriteNotConfirmed`), and the result of a change, with
the lesfiche read back (`lesficheChangedResult`); a header note says why
the session's repeat of a write cannot make a lesfiche, a weblink or an
attachment twice, and why a read comes before the write. The tests run against a fake
planner (`test/support/fake_planner.dart`), built from dartschool's
anonymised captures of the live planner, its workload view, the Lesfiches
list and the detail of a lesfiche with the download of its attachment
(dartschool#129), with the school's course list, which carries out the
writes of dartschool#87 (fill, rename, change of the info, clear), the plan
of a lesfiche of dartschool#88, the create and the trash of an assignment of
dartschool#89 as the live planner did, and the writes of a lesfiche of
dartschool#129: the create from the web client's body, with its
attachments from the fake upload step (`fakeLesficheCreatePath`,
`fakeNewLesficheId`), the edits, and the weblinks and attachments added,
changed and removed, and the move of lesfiches to the trash
(`fakeLesficheTrashPath`; a lesfiche in the trash already answered with a
bare `500`, and `lesficheTrashExceptions` for an answer with
`exceptions`), with a trash (`trashedLesfiches`) whose lesfiches are read
but not written, and no longer listed, as live.

Skore helpers for later tools live in `lib/src/skore/`. In
`skore_access.dart`: `withSkore`, which runs an action with a
`SkoreService` on the session and turns Skore's errors into `ToolError`s
(`skoreToolError`: no rights, or an answer the server cannot use, whose
details go to the log only), and `checkSkoreAccess`, the access check of
`smartschool_status`; `skoreToolError` also passes on why a check refused a
change (with what to read again: the class, or for a gradebook
`rereadSkoreGradebook`), and says what to do about "Mijn lesgroepen". In
`skore_writes.dart`, for the tools that change Skore: `withSkoreWrite`,
which runs a write and adds to its `ToolError` that nothing was changed,
and `skoreWriteNotConfirmed` (and its text, `skoreNotConfirmed`), the result
of a save Skore did not confirm. In `skore_shares.dart`:
`changeSkoreShares`, which shares a gradebook with teachers or unshares it,
one teacher after the other, and the arguments' schemas. In
`skore_format.dart`: one line per class, course row, assignment, teacher and
gradebook, a course or a teacher in a sentence, and the `query` filter
(`skoreMatches`). In `skore_opt_in.dart`: the Skore tools behind their
switch (`skoreOptIn`). The tests run against a fake Skore
(`test/support/fake_skore.dart`) that serves the endpoints `SkoreService`
reads, in the shape of dartschool's anonymised captures, with fake names;
it can refuse an account without the rights by sending the request on to
the start page, as Skore did live (dartschool#91), or with HTTP 403, for
every request or only for some services (`refusedPaths`), and answer with
an error page instead of data (`unusable`). It carries out the save of an
assignment (`saveOwner`) and answers `getMyGroups` as the live Skore did in
dartschool#71; it gives a
teacher's gradebooks, one per assignment, with their shares (`getCourses`
of the gradebooks service), and carries out the save of their shares
(`saveShared`) as the live Skore did in dartschool#74. It can lose the
answer to a save, answer it with an error page, or (`saveShared`) answer it
as done without carrying it out, also for one save of several
(`nextSaves`); it answers any other RPC method with HTTP 501.

Presence helpers live in `lib/src/presence/`. In `presence_access.dart`:
`withPresence`, which runs an action with a `PresenceService` on the session
and turns the module's errors into `ToolError`s (`presenceToolError`, whose
details go to the log only), and `runPresence`, which leaves them as they
are; `PresenceServices`, one service per client for a tool call, so the
configuration and the codes are read once per call; `readPresenceDay`, which
reads a class on a day (`PresenceDay`: the configuration, the class, its
codes and its pupils);
the `class_id` and `date` arguments (`presenceDay`); and
`checkPresenceAccess`, the access check of `smartschool_status`. In
`presence_format.dart`: what a half-day holds (`PresenceKind`, and
`PresenceCodes`, which names a code or an alias and tells which statuses the
writes may change) and the output lines. In `presence_writes.dart`:
`changePresences`, the guarded change of the half-days of pupils one after
the other, and the arguments of the writes. In `presence_opt_in.dart`: the
presence tools behind their switch (`presenceOptIn`). The tests run against
a fake Presence module (`test/support/fake_presence.dart`) in the shape of
dartschool's trimmed captures, with fake names: three classes (one the
account may only view, one grouping class, without codes, whose pupil's
official class the account does not see), the codes of a structure
("Aanwezig", "Te laat" with its alias, "Doktersattest"), and pupils, each
with its official class, with half-days of each kind, each record with the
name the module gives it, and a registration per lesson; a test adds an
official class in a second structure with codes of its own. It
carries out a save on the half-days as the live module did in dartschool#2
and answers it as the module's web client reads the answer (the records as
stored), can answer it without the records, refuse it with the module's
error objects, answer it with an error page, lose its answer or answer it
without carrying it out (`nextSaves`). It answers `getClass` as the module
did live (dartschool#104): every class it knows with its pupils, also one
the account may only view, and a class without pupils, a class ID it does
not know and a day after `today` without pupils, with `saveIsAllowed:
false` and the module's reason.

Reading documents lives in `lib/src/documents/`, independent of Intradesk so
that message and lesfiche attachments can use it too: `readDocument(bytes,
name: ...)` in `document_reader.dart` returns a `DocumentText`, a
`DocumentImage` or an `UnreadableDocument` with the reason (in
`document_content.dart`); the readers per format are `docx_text.dart`,
`xlsx_text.dart`, `pptx_text.dart`, `pdf_text.dart`, `plain_text.dart` and
`image_content.dart`. The tools that read a file (`read_intradesk_file`,
`read_lesfiche_attachment`) share reading the download, the result and its
log line (`readWholeDownload`, `documentResult`, `describeDocumentForLog`)
in `lib/src/tools/document_result.dart`. Downloads go through
`flutter_smartschool`'s streamed download with a size limit
(`IntradeskService.downloadFileStream`, `MessageAttachment.downloadStream`,
`LessonContentService.downloadAttachmentStream`, all with `maxBytes`),
which also gives the file name from the `Content-Disposition` header.

### Opt-in tools

Some tools only work for accounts with extra rights in Smartschool, such as
the Skore tools and the presence tools. They sit behind an opt-in switch, a
setting that is off by default (`Setting.isSwitch` in
`lib/src/settings.dart`): "Skore-beheer" (`SMARTSCHOOL_SKORE`, `skore` in a
credentials file) and "Aanwezigheden" (`SMARTSCHOOL_PRESENCE`, `presence`).
Each switch turns on its own group. The server only
offers the group's tools when its switch is on (`OptInTools` in
`lib/src/opt_in.dart`), so accounts without the rights never see tools they
cannot use, and those tools take up no context in their conversations. The
switches are read once, at startup (`Switches.read`): the environment
variable when it is set and not empty, else the credentials file's key.
`true`, `1`, `yes`, `on`, `ja` and `aan` (any case) turn a switch on; empty,
`false`, `0`, `no`, `off`, `nee` and `uit` leave it off; anything else
counts as off, and `smartschool_status` says so.

`smartschool_status` has a line per switch: off, with how to turn it on and
for whom; or on, with whether the account has the rights, checked with a
cheap read once the connection works (`OptInTools.checkAccess`; for Skore,
the library's `checkAccess`, which reads the teachers for report management
and the account's own gradebooks for gradebook management: access means
both parts, and the line names the part an account with only one lacks;
for the presences, `getConfig`, where access means that the account may
record presences for at least one class). An answer that cannot tell
(for Skore, one the server could not use) is reported as access that could
not be checked.
Registering the tools only once access is detected
(`notifications/tools/list_changed`) was not chosen: the server logs in at
the first tool call, so the tools would show up only later in the
conversation, and it would cost Skore requests at every start.

To add a group: a `Setting` with `isSwitch: true` (a `boolean` field with
the default `false` in the manifest's `user_config`, its variable in
`mcp_config.env`, a hint in the installer's `settingHints`, and a row in both
colleague guides), an `OptInTools` with its tools, rights and access check,
and the group in the entry point's `optIns`.

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

What the server adds itself (`create_intradesk_folder`,
`add_intradesk_weblink`, `upload_intradesk_files`) goes into the index at
once, under the folder's path, in memory and in the file
(`IntradeskIndexCache.patch`), so a search finds it without waiting for the
next walk. Only an index that is loaded is patched, of any age, also when
it does not know the folder yet; the patch keeps the time the index was
built, so the next walk comes when it would have, and a walk that runs
meanwhile gets the patch too. What `trash_intradesk_items` moved leaves the index the same
way, a folder with everything in it; an item that may or may not have been
moved stays until the next walk.

### Reading Intradesk files

`read_intradesk_file` downloads the file into memory (never to disk), reads
it and forgets it; `read_lesfiche_attachment` reads an attachment of a
lesfiche the same way. What a file is follows from its content, not its
name:

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
index knows the size (for an attachment of a lesfiche, when the lesfiche
gives it), else as soon as Smartschool announces it or the download goes
past it, and `flutter_smartschool` then stops the transfer.
Text longer than 100,000 characters (Claude Desktop accepts about 150,000
per tool result) is cut off with a note, and a PDF stops after 30 seconds of
reading. The log shows formats, sizes and counts, never a name or any text.

### Saving files

`save_intradesk_file`, `save_message_attachment` and
`save_lesfiche_attachment` save a file into the download folder on this PC
instead of returning what is in it. They are meant
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
  result says what changed. No name at all: `intradesk-<id>`,
  `attachment-<message id>-<number>` or `lesfiche-attachment-<number>`.
- **Size limit:** 200 MB (higher than `read_intradesk_file`'s 25 MB: nothing
  goes through the tool result). Refused before downloading when the
  Intradesk index knows the size (or the lesfiche gives it), else as soon
  as Smartschool announces it or the download goes past it;
  `flutter_smartschool`'s streamed download (`downloadFileStream`,
  `MessageAttachment.downloadStream`, `downloadAttachmentStream`, all with
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
in `lib/src/tools/save_intradesk_file_tool.dart`,
`save_message_attachment_tool.dart` and `save_lesfiche_attachment_tool.dart`.

Privacy: saved files are personal or school data, unencrypted, in a folder
of the teacher's choice; the colleague guide (`docs/installatie.md`) says so,
and that they disappear after 7 days.

### Uploading files

`upload_intradesk_files`, `create_lesfiche`, `add_lesfiche_attachments`,
`send_message` and `reply_to_message` send files from this PC to
Smartschool. The tools that upload share the local-file helper in
`lib/src/uploads/local_files.dart` (for Intradesk, the attachments of a
lesfiche and those of a message):

- **Paths:** absolute paths only (`localFilesArgument`, `checkLocalFiles`),
  1 to 10 per call (for a message, `attachments` may also be left out or
  empty). The server reads any file the user's Windows account can
  read, so the tool descriptions tell Claude to show the user every file,
  with its name and size, before calling.
- **Checks before anything is sent:** each path names an existing file, not
  a folder, of at most 200 MB (a sanity limit, as high as what
  `save_intradesk_file` saves: the library reads a file into memory to
  upload it), with a name Smartschool takes (no `/ : * ? " \ < > |`, no dot
  at the start or end; the upload step refuses any other), and no two files
  have the same name, ignoring case. Each error names the path and says what
  to do.
- **Names:** a file goes in under the last part of its path (`localFileName`,
  as the library takes it), described as `"brief.docx" (12 KB)`
  (`LocalFile.description`, `describeLocalFiles`).
- **Refusals:** `uploadToolError` turns the library's refusal of a file (an
  `ArgumentError` about its path) and a failure of Smartschool's upload step
  (`SmartschoolAttachmentUploadError`, with Smartschool's own words in
  `serverMessage` when it gave them) into a `ToolError`, ending in what that
  means for the call (for Intradesk: nothing was added; for a new lesfiche:
  no lesfiche was made; for files added to a lesfiche: the lesfiche was not
  changed; for a message or a reply: nothing was sent, since the uploads
  come before the submit).
- **Sessions:** Intradesk and the Lesfiches module take a new upload
  directory that is not bound to the session, so the uploads into it are
  retried after a new login like a read. A message's attachments go into
  the upload directory of its compose form (`randomDir`), which belongs to
  the form's session: the library uploads them in that session only
  (`retryAfterLogin: false`, `sameSessionAs: form`, dartschool#25, #38).
  When Smartschool refuses the session for such an upload, the session's
  repeat of the send loads a new compose form, logging in first, and
  uploads the files again into its directory (see `submitOnce`).

The log shows counts and timings, never a name or a path.

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
step of the send that Smartschool refused the session for, the upload of
an attachment and the submit included, sent nothing, so `run` may repeat
it (see `submitOnce` in `lib/src/tools/message_sending.dart`).

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

Every optional field has a default on purpose: Claude Desktop passes a field
without a value or a default literally, as `${user_config.download_dir}`
(modelcontextprotocol/mcpb#250), and does not replace `${HOME}` in a default
(modelcontextprotocol/mcpb#251). The default of "2FA-sleutel" and
"Downloadmap" is empty; empty, the server uses its own download folder (see
*Saving files*). "Skore-beheer", a switch, is a `boolean` field with the
default `false`, which Claude Desktop passes as `true` or `false`
(`getMcpConfigForManifest` in `@anthropic-ai/mcpb`).

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
