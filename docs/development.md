# Development

[Back to the overview](../README.md)

How to build, test and release the server, and how its shared parts work:
settings, caches, files and the login. What each tool does, and how, is on
its area's page under [`docs/tools/`](../README.md#tool-areas).

- [Requirements and tests](#requirements-and-tests)
- [Local credentials](#local-credentials)
- [Pupil tracking system (LVS) data](#pupil-tracking-system-lvs-data)
- [Build](#build)
- [Try it in Claude Desktop](#try-it-in-claude-desktop)
- [ChatGPT and Codex](#chatgpt-and-codex)
- [Opt-in tools](#opt-in-tools)
- [Message folders](#message-folders)
- [Message text cache](#message-text-cache)
- [Intradesk index](#intradesk-index)
- [Reading Intradesk files](#reading-intradesk-files)
- [Saving files](#saving-files)
- [Uploading files](#uploading-files)
- [Login](#login)
- [Update check](#update-check)
- [Extension and releases](#extension-and-releases)

## Requirements and tests

Requires the Dart SDK (3.10.1 or later).

```
dart pub get
dart format .
dart analyze
dart test
```

`dart test` includes end-to-end tests that compile the executable and talk
to it over stdio, one of them in the extension folder, started the way
Claude Desktop starts it (see [Extension and releases](#extension-and-releases)).
They never contact Smartschool: the other tests use a fake Smartschool. No
test asks the real GitHub for updates either (see
[Update check](#update-check)).

## Local credentials

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
# Optional: true offers the Skore tools (see Opt-in tools).
skore: false
# Optional: true offers the presence tools (see Opt-in tools).
presence: false
# Optional: true offers the tools of the pupil tracking system (LVS).
lvs: false
```

`SMARTSCHOOL_DOWNLOAD_DIR`, when set, comes before `download_dir` (see
[Saving files](#saving-files)), `SMARTSCHOOL_SKORE` before `skore`,
`SMARTSCHOOL_PRESENCE` before `presence`, and `SMARTSCHOOL_LVS` before
`lvs` (see [Opt-in tools](#opt-in-tools)).

Pass it explicitly with `--credentials credentials.yml`; the server never
looks for the file on its own. The project's `.mcp.json` starts the server
that way, so Claude Code in this repository can use the tools live. Ask it to
call `smartschool_status` to check the login.

`test/live_test.dart` checks the login against the real Smartschool
(password, 2FA, then a second start that must reuse the saved session). It
is skipped unless you opt in:

```
SMARTSCHOOL_LIVE_CREDENTIALS=credentials.yml dart test test/live_test.dart
```

Every run logs in with a fresh cookie cache, so do not run it in a loop. Its
message test only reads (it lists the inbox and archive and reads a few
messages that are already read) and uses your own cookie cache; run just
that one with `--name list_messages`. The search test only reads as well: it
searches for a word of a read message, from that message's date on, twice
(the second time from your message text cache) and for a word that occurs
nowhere, and prints counts and timings only; run it with
`--name search_messages`. The Intradesk test only reads too (no file is
downloaded): it lists the top of Intradesk and a folder, searches with
`refresh: true` (a full walk of Intradesk, a few minutes on a large one) and
then from the index, and prints counts and timings only; run it with
`--name list_intradesk_folder`. The file test downloads (never changes) the
two smallest Word, Excel, PowerPoint, PDF, PNG and JPEG files it finds,
reads them with `read_intradesk_file`, checks that a file above the size
limit is refused without downloading it, and prints formats, sizes,
character counts and timings only; run it with
`--name read_intradesk_file`. The save test saves (never changes) the
smallest PDF and Word file above 5 KB on Intradesk and the first attachment
of a read message (twice, to see the second copy get a name of its own) into
a temporary download folder that is deleted afterwards, checks their sizes
and first bytes, and prints extensions, sizes and timings only; run it with
`--name save_intradesk_file`.

## Pupil tracking system (LVS) data

The LVS tools read the most sensitive data Smartschool has (care, behaviour,
educational needs, sometimes health). **No LVS data from a live school ever
goes into this repository or onto GitHub.** The rules are the library's,
in flutter_smartschool's
[`doc/lvs-privacy.md`](https://github.com/yvanvds/dartschool/blob/main/doc/lvs-privacy.md)
(yvanvds/dartschool#159), and hold here too, for every contributor and every
coding agent:

- The fixtures of the fake LVS (`test/fixtures/lvs/`) are written by hand,
  in the shapes the library's research found, and never derived from a live
  answer by trimming it: an LVS answer is mostly free text about a pupil, and
  a forgotten sentence is a leak. They name only the fakes of
  `test/fixtures/lvs/FAKES.md` (a copy of the library's list: add a fake
  there and here alike), hold ids in 900000–999999 only and free text that
  says "test". `test/lvs_fixtures_guard_test.dart`, a copy of the library's
  guard, checks them, and names a file and a field when it fails, never a
  value.
- Issues, PRs, commit messages, code comments and docs describe an LVS
  answer by its shape: field names, types, nesting and placeholders
  (`<pupil id>`, `<text>`, "Jan Janssens"). Never a value from a live
  answer: no names, no pupil, class or note ids, no dates or texts of a note,
  no category names a school made itself. Example questions in the guides
  use the fakes too.
- A coding agent does not open a pupil's data, and makes no live LVS calls.
  The live check of the tools on a real pupil is the developer's (#159), and
  reports only what worked, shapes and counts, never values. Raw answers
  from research go to a temp folder outside the repository, never to
  `dev_dumps/` or another git-ignored folder in the working tree.
- A bug report holds no pupil data, no LVS answers and no log lines with
  names (the bug template and both guides say so): it describes what
  happened.

The tools themselves only read, keep nothing on disk and log nothing but an
error's type: see [their privacy](tools/lvs.md#privacy) and
[their helpers in `lib/src/lvs/`](tools/lvs.md#helpers-and-tests).

## Build

```
dart compile exe bin/smartschool_mcp.dart
```

This writes `bin/smartschool_mcp.exe` (git-ignored). Use `-o <path>` to put
it elsewhere. To build the Claude Desktop extension instead, see
[Extension and releases](#extension-and-releases).

The server speaks MCP over stdin/stdout, so **stdout is reserved for the
protocol**: log to stderr (`log()` in `lib/src/log.dart`), never `print` to
stdout.

## Try it in Claude Desktop

Build the extension and double-click `smartschool-mcp.mcpb` (see
[Extension and releases](#extension-and-releases)). Or, without packing,
open Claude Desktop's config file via *Settings → Developer → Edit Config*
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
        "SMARTSCHOOL_PRESENCE": "false",
        "SMARTSCHOOL_LVS": "false"
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
`SMARTSCHOOL_DOWNLOAD_DIR` is optional (see [Saving files](#saving-files)),
and so are `SMARTSCHOOL_SKORE`, `SMARTSCHOOL_PRESENCE` and
`SMARTSCHOOL_LVS`, which offer the Skore tools, the presence tools and the
tools of the pupil tracking system when `true` (see
[Opt-in tools](#opt-in-tools)). Restart Claude Desktop after editing the
file. The server's stderr ends up in Claude Desktop's MCP log
(`%APPDATA%\Claude\logs\mcp-server-smartschool.log`).

Then ask Claude "Werkt mijn Smartschool-verbinding?": the
[`smartschool_status`](tools/status.md) tool reports whether the settings are
complete, whether the login works and who is logged in, or what to fix.

## ChatGPT and Codex

The ChatGPT desktop app for Windows, the Codex CLI and the Codex IDE
extension start local MCP servers from `%USERPROFILE%\.codex\config.toml`
(`CODEX_HOME` when set). The ChatGPT app edits it under *Instellingen →
Plug-ins → MCP's → Toevoegen → Aangepaste MCP-server maken*: a name, the
command, its arguments and environment variables, saved as
`[mcp_servers.<name>]` and `[mcp_servers.<name>.env]`. The server runs there
unchanged, with the same `SMARTSCHOOL_*` variables. For development, the
command can be `bin\smartschool_mcp.exe` (or the one in `bundle\server`)
with the arguments `--credentials` and the path to `credentials.yml`.

**Installer.** For colleagues there is no `.mcpb`: Codex plugins cannot ask
for settings. Started with a console on stdin (a double-click) and without
`--credentials`, or with `--install`, the executable installs itself instead
of serving MCP (`lib/src/install.dart`):

- it copies itself to
  `%LOCALAPPDATA%\Programs\smartschool-mcp\smartschool-mcp.exe` (per user,
  no administrator rights). A copy that is running (ChatGPT open) is renamed
  out of the way first. The installer and the next server start delete it
  once it no longer runs;
- it puts that path on the clipboard (`--no-clipboard` for tests). It goes
  through the Windows API (`lib/src/clipboard.dart`), not `clip.exe`, which
  kept a byte order mark in front of the path, and ChatGPT could then not
  start the server (#49). `test/clipboard_test.dart` and a test in
  `test/install_e2e_test.dart` read the clipboard back. They run in CI, and
  locally only with `SMARTSCHOOL_MCP_CLIPBOARD_TEST=on`, since they replace
  what is on the clipboard (they put back the text that was there);
- it shows, in Dutch, what to fill in in ChatGPT: the name `smartschool`,
  the command, no arguments and the seven variables. Before those steps it
  warns that what ChatGPT reads goes to OpenAI, sensitive information about
  pupils included. So: a paid plan only, with *Improve the model for
  everyone* off (#50). It waits for Enter so the window stays open.

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
form's. So a variable that is close to a setting's name
(`SMARTSCHOOL_MAINURL`, `SMARTSCHOOL_MFA ` with a space) or starts with
`SMARTSCHOOL` comes from a mistyped key. `smartschool_status` and the
missing-settings message name it and the setting it probably means
(`MisnamedSetting` in `lib/src/settings.dart`), never its value.
`SMARTSCHOOL_MCP_*` and `SMARTSCHOOL_LIVE_*` are not settings to begin with.
Windows compares names without case, so `smartschool_mfa` is simply the
setting.

Known limits in Codex (2026):

- **Images:** image results (`read_intradesk_file` on a PNG or JPEG) do not
  reliably reach the model (openai/codex#4819, #46927).
- **Long text:** Codex cuts long tool output to the model's budget, about
  10k tokens, well below `read_intradesk_file`'s 100,000 characters.
- **Approval:** Codex asks approval for a tool marked destructive
  (`trash_messages`, `reply_to_message`, `send_message`), unless it runs
  with *Full access*.
- **`HOME`:** Codex does not pass `HOME` on. A user who has `HOME` set gets
  another cache folder under Codex than under Claude Desktop, so the server
  logs in once more there.

`test/install_e2e_test.dart` installs the compiled server into a temporary
`LOCALAPPDATA`, and starts the installed copy with Codex's environment and
client name. It also installs again while that copy runs.

## Opt-in tools

Some tools only work for accounts with extra rights in Smartschool, such as
the [Skore tools](tools/skore.md) and the [presence tools](tools/presences.md);
others read data sensitive enough that the user and their school must choose
to let an AI assistant read it, such as the tools of the
[pupil tracking system (LVS)](tools/lvs.md), which most teachers can read.
They sit behind an opt-in switch, a setting that is off by default
(`Setting.isSwitch` in `lib/src/settings.dart`): "Skore-beheer"
(`SMARTSCHOOL_SKORE`, `skore` in a credentials file), "Aanwezigheden"
(`SMARTSCHOOL_PRESENCE`, `presence`) and "Leerlingvolgsysteem"
(`SMARTSCHOOL_LVS`, `lvs`). Each switch turns on its own group. The server
only offers the group's tools when its switch is on (`OptInTools` in
`lib/src/opt_in.dart`), so accounts without the rights never see tools they
cannot use, no one gets the LVS tools without choosing them, and those tools
take up no context in their conversations. The switches are read once, at
startup (`Switches.read`): the environment variable when it is set and not
empty, else the credentials file's key. `true`, `1`, `yes`, `on`, `ja` and
`aan` (any case) turn a switch on; empty, `false`, `0`, `no`, `off`, `nee`
and `uit` leave it off; anything else counts as off, and
`smartschool_status` says so.

`smartschool_status` has a line per switch: off, with how to turn it on and
for whom; or on, with whether the account has the rights, checked with a
cheap read once the connection works (`OptInTools.checkAccess`; for Skore,
the library's `checkAccess`, which reads the teachers for report management
and the account's own gradebooks for gradebook management: access means
both parts, and the line names the part an account with only one lacks; for
the presences, `getConfig`, where access means that the account may record
presences for at least one class; for the LVS, the library's `checkAccess`,
the root of its class tree, which holds no pupil: access means that the LVS
answers it, as the library does not tell how many classes it lists,
yvanvds/dartschool#184). When the switch is off, the line of a switch for
sensitive data adds what turning it on means (`OptInTools.caution`: for the
LVS, with a link to the guide's privacy section). An answer that cannot tell
(for Skore, one the server could not use) is reported as access that could
not be checked. Registering the tools only once access is detected
(`notifications/tools/list_changed`) was not chosen: the server logs in at
the first tool call, so the tools would show up only later in the
conversation, and it would cost Skore requests at every start.

To add a group: a `Setting` with `isSwitch: true` (a `boolean` field with
the default `false` in the manifest's `user_config`, its variable in
`mcp_config.env`, a hint in the installer's `settingHints`, and a row in both
colleague guides), an `OptInTools` with its tools, rights and access check
(and, for sensitive data, its caution), the group in the entry point's
`optIns`, and a page of its own under `docs/tools/`, linked from the
README's overview with its switch.

## Message folders

Users make their own folders in Smartschool's messages ("Map toevoegen"),
in the inbox and in the sent box, also inside another folder. Their messages
are not in the box itself, so the [message tools](tools/messages.md) look in
them separately, with the folder tree of the library's `getFolders`
(`quickactions` / `requestmovelist`, flutter_smartschool 0.3.7,
yvanvds/dartschool#136), read again at every call that needs it:

- Tool output names a folder by its path after the name of its box, like
  `inbox/Projecten/2026` or `sent/Projecten`: the box to pass to
  `read_message`, `save_message_attachment` and `reply_to_message` (which
  find a message in a folder by its id, as Smartschool does), then the
  folder.
- `list_messages`, `flag_messages`, `mark_messages` and `trash_messages`
  take a `folder` next to `box`: that path, the path from the box
  (`Projecten/2026`, ignoring case and the spaces around a `/`), the
  folder's name, or its id. `box` (inbox or sent) narrows the lookup; with
  the archive it is an error. A name two folders have, or an unknown
  folder, is an error that names the user's folders, before anything is
  listed. `mark_messages` looks only in the folders of the inbox.
- The folder is then listed as the archive is: with its box type and its
  id as `boxId`, a box of its own with its own paging position. Its tree,
  its listing, a search and reading one of its messages were tried live by
  the live test, on the test folder "dartschool test" (inbox folder 30650).
  Marking unread and moving to the trash name its id, as for the archive;
  marking read and flagging name the box type only. These requests are
  documented by the library for a folder, tried live on the archive, not
  yet on a folder the user made (#134).
- `search_messages` searches the folders of a box with it: by default the
  inbox and its folders and the archive; the sent box's folders with
  `sent`. Their messages count toward the 100 texts downloaded per search.
- `archive_messages` does not archive a message from a folder; it says
  which folder the message is in.

## Message text cache

`search_messages` keeps the plain text of every message it downloads, so
each message is downloaded only once (Smartschool messages do not change
once sent). The texts are in

```
%USERPROFILE%\.cache\smartschool\<username>\messages\<school address>\
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set), one small JSON file
per message (`inbox-<id>.json`, also for archived messages, and
`outbox-<id>.json` for sent ones), next to the session cookies. The server
logs the folder on first use.

Privacy: the folder holds the text of your messages, unencrypted, on this
PC. It is inside your own Windows profile, never in the project folder, and
nothing is sent anywhere; anyone who can sign in to your Windows account can
read it, just like the session cookies next to it. Deleting the folder is
safe at any time: the next search downloads the texts again. The log only
shows counts, never a search query or message text. The colleague guide
(`docs/installatie.md`) says where the folder is and what it holds.

## Intradesk index

The library has no Intradesk search (a server-side search endpoint has not
been researched), so `search_intradesk` walks the whole tree (every folder,
4 listings at a time) and keeps an index of the names, paths, ids, sizes and
dates. A walk takes minutes on a large Intradesk: about 3 minutes for one of
5900 folders and 22000 files. A tool call waits at most 40 seconds for it,
within the 60 seconds after which MCP clients such as Claude Desktop usually
give up on a call; the walk then goes on in the background. Until the first
index is ready, a search says how far the walk is and to search again;
while a newer index is built, the old one is searched, with a note.

The index is used for 24 hours, then rebuilt on the next search (which is
answered from the old index meanwhile); `refresh: true` rebuilds it at once.
It is kept in memory and in

```
%USERPROFILE%\.cache\smartschool\<username>\intradesk\<school address>\index.json
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set; about 10 MB for the
Intradesk above). The server logs the folder on first use. It holds the
names and paths of what you can see on Intradesk, not file contents.
Deleting it is safe: the next search builds it again. The log only shows
counts, never a name or a query.

What the server adds itself (`create_intradesk_folder`,
`add_intradesk_weblink`, `upload_intradesk_files`) goes into the index at
once, under the folder's path, in memory and in the file
(`IntradeskIndexCache.patch`), so a search finds it without waiting for the
next walk. Only an index that is loaded is patched, of any age, also when it
does not know the folder yet; the patch keeps the time the index was built,
so the next walk comes when it would have, and a walk that runs meanwhile
gets the patch too. What `trash_intradesk_items` moved leaves the index the
same way, a folder with everything in it; an item that may or may not have
been moved stays until the next walk.

## Reading Intradesk files

`read_intradesk_file` downloads the file into memory (never to disk), reads
it and forgets it; `read_lesfiche_attachment` reads an attachment of a
lesfiche the same way. What a file is follows from its content, not its
name:

- Word (`.docx`), Excel (`.xlsx`) and PowerPoint (`.pptx`), and their macro
  and template variants, as text: paragraphs with `#` headings and `- `
  list items, table rows as `cell | cell`, text boxes; every sheet under its
  name, with dates, times and percentages as Excel shows them; every slide
  with its tables and speaker notes.
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
- Old Office files (`.doc`, `.xls`, `.ppt`), password-protected Office
  files, OpenDocument files and other formats are refused with the reason.

Files larger than 25 MB are not opened: refused before downloading when the
index knows the size (for an attachment of a lesfiche, when the lesfiche
gives it), else as soon as Smartschool announces it or the download goes
past it, and `flutter_smartschool` then stops the transfer. Text longer than
100,000 characters (Claude Desktop accepts about 150,000 per tool result) is
cut off with a note, and a PDF stops after 30 seconds of reading. The log
shows formats, sizes and counts, never a name or any text.

Reading documents lives in `lib/src/documents/`, independent of Intradesk so
that message and lesfiche attachments can use it too:
`readDocument(bytes, name: ...)` in `document_reader.dart` returns a
`DocumentText`, a `DocumentImage` or an `UnreadableDocument` with the reason
(in `document_content.dart`); the readers per format are `docx_text.dart`,
`xlsx_text.dart`, `pptx_text.dart`, `pdf_text.dart`, `plain_text.dart` and
`image_content.dart`. The tools that read a file (`read_intradesk_file`,
`read_lesfiche_attachment`) share reading the download, the result and its
log line (`readWholeDownload`, `documentResult`, `describeDocumentForLog`)
in `lib/src/tools/document_result.dart`. Downloads go through
`flutter_smartschool`'s streamed download with a size limit
(`IntradeskService.downloadFileStream`, `MessageAttachment.downloadStream`,
`LessonContentService.downloadAttachmentStream`, all with `maxBytes`), which
also gives the file name from the `Content-Disposition` header.

## Saving files

`save_intradesk_file`, `save_message_attachment` and
`save_lesfiche_attachment` save a file into the download folder on this PC
instead of returning what is in it. They are meant for a Claude Cowork
project: Claude there reads the files in the project's folders (PDFs, scans,
Word, Excel, images) far better than a tool result can carry them, so point
the download folder at a (temporary) folder inside the project, and Claude
opens the saved file from the path the tool returns. In a plain chat Claude
tells the user where the file is, to open it or drag it into the chat.
`read_intradesk_file` stays the quick option that works in every chat.

The download folder is:

1. `SMARTSCHOOL_DOWNLOAD_DIR`, when set and not empty: the extension setting
   "Downloadmap" (in the extension manifest a `directory` field, so the
   install form shows a folder picker);
2. otherwise, with `--credentials`, the file's `download_dir`;
3. otherwise `%USERPROFILE%\Downloads\Smartschool`
   (`$HOME/Downloads/Smartschool` elsewhere).

`smartschool_status` shows the folder, where it was set, and whether it is
writable (it creates and deletes a test file; a folder that does not exist
yet is created on the first save).

- **Never overwrites:** a name that is taken (also by a folder, or in
  another case) gets ` (2)`, ` (3)`, ... before the extension, and the result
  says so.
- **Safe names:** the name Smartschool gives is made into one Windows
  accepts: `<>:"/\|?*` and control characters become `_` (so a name never
  holds a folder), dots and spaces at the end go, device names such as `CON`
  or `nul.txt` and names like the server's own files get a `_` in front, and
  a name longer than 120 characters is cut short, keeping its extension. The
  result says what changed. No name at all: `intradesk-<id>`,
  `attachment-<message id>-<number>` or `lesfiche-attachment-<number>`.
- **Size limit:** 200 MB (higher than `read_intradesk_file`'s 25 MB: nothing
  goes through the tool result). Refused before downloading when the
  Intradesk index knows the size (or the lesfiche gives it), else as soon as
  Smartschool announces it or the download goes past it;
  `flutter_smartschool`'s streamed download (`downloadFileStream`,
  `MessageAttachment.downloadStream`, `downloadAttachmentStream`, all with
  `maxBytes`) then stops the transfer.
- **Written under a temporary name** (`.smartschool-mcp-<random>.part`) and
  renamed once complete; a failed download leaves nothing behind.
- **Temporary by design:** the folder holds
  `.smartschool-mcp-downloads.json`, the list of the files the server saved
  there (name, time saved, size, time changed). At startup, and at most once
  a day (also on a save), the server deletes the listed files saved more
  than 7 days ago. It never touches any other file in the folder, nor a
  listed file that was changed since it was saved (that is the teacher's
  now: it is taken off the list). Its own temporary files left behind by a
  server that was stopped while saving are deleted after a day. Two servers
  sharing the folder each keep the list up to date; a save one of them
  misses is only never cleaned up.

The log shows sizes, timings and whether a name was changed, never a name.
The code is in `lib/src/downloads/` (`DownloadFolder` in
`download_folder.dart`, `safeFileName` in `file_names.dart`) and the tools
in `lib/src/tools/save_intradesk_file_tool.dart`,
`save_message_attachment_tool.dart` and `save_lesfiche_attachment_tool.dart`.

Privacy: saved files are personal or school data, unencrypted, in a folder
of the teacher's choice; the colleague guide (`docs/installatie.md`) says
so, and that they disappear after 7 days.

## Uploading files

`upload_intradesk_files`, `create_lesfiche`, `add_lesfiche_attachments`,
`send_message` and `reply_to_message` send files from this PC to
Smartschool. The tools that upload share the local-file helper in
`lib/src/uploads/local_files.dart` (for Intradesk, the attachments of a
lesfiche and those of a message):

- **Paths:** absolute paths only (`localFilesArgument`, `checkLocalFiles`),
  1 to 10 per call (for a message, `attachments` may also be left out or
  empty). The server reads any file the user's Windows account can read, so
  the tool descriptions tell Claude to show the user every file, with its
  name and size, before calling.
- **Checks before anything is sent:** each path names an existing file, not
  a folder, of at most 200 MB (a sanity limit, as high as what
  `save_intradesk_file` saves: the library reads a file into memory to
  upload it), with a name Smartschool takes (no `/ : * ? " \ < > |`, no dot
  at the start or end; the upload step refuses any other), and no two files
  have the same name, ignoring case. Each error names the path and says what
  to do.
- **Names:** a file goes in under the last part of its path
  (`localFileName`, as the library takes it), described as
  `"brief.docx" (12 KB)` (`LocalFile.description`, `describeLocalFiles`).
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

## Login

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
step of the send that Smartschool refused the session for, the upload of an
attachment and the submit included, sent nothing, so `run` may repeat it
(see `submitOnce` in `lib/src/tools/message_sending.dart`).

Some tools need the signed-in user, which `flutter_smartschool` reads from
the data a Smartschool page hands to its JavaScript: the own planner and the
planner writes, the gradebooks, and `smartschool_status`. When Smartschool
accepts the session, but its page does not name the user
(`SmartschoolAuthenticatedUserNotFoundError`, yvanvds/dartschool#214), those
tools say that Smartschool probably changed its pages, and that
`smartschool_status` shows whether a newer version is available. That is
not "an unexpected error", and logging in again does not help, so `run` does
not repeat it. It happened in 2026-10, when Smartschool changed the scripts
that hand the data over (yvanvds/dartschool#212, #181).

## Update check

At startup, in the background (startup never waits for it), the server asks
GitHub for the releases of this repository
(`https://api.github.com/repos/yvanvds/smartschool-mcp/releases`,
unauthenticated; the first page, with the 30 newest). GitHub leaves out
drafts; the server ignores pre-releases and tags that are not a version
(`vX.Y.Z`). It compares the highest version with the built-in one
(`lib/src/version.dart`). An empty list means that no release has been
published: nothing to report. A check waits at most 5 seconds; offline, rate
limited or an answer it does not understand is only logged.

It asks at most once a day. The time and the releases of the last
successful check (tag, release page, download links and what is new) are
kept in

```
%USERPROFILE%\.cache\smartschool\smartschool-mcp-update-check.json
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set), so a restart
within 24 hours does not ask again. A file of an older format is ignored. It
needs no Smartschool settings. A server that keeps running asks again after
24 hours, on a tool call.

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

That happens once per server process (Claude Desktop starts one per
session), and not at all after `smartschool_status` showed it. Error results
never get it. `smartschool_status` always asks GitHub (while it checks the
login, so it takes no longer) and shows the same on its `Updates:` lines;
its description asks the model to give the download link and say what is
new. The code is in `lib/src/update_check.dart`; the server adds the notice
in `lib/src/server.dart`.

For tests and development:

- `SMARTSCHOOL_MCP_UPDATE_CHECK=off` turns the check off;
- `SMARTSCHOOL_MCP_UPDATE_URL=<address>` asks that address instead of the
  GitHub API (it must answer the same way, with a list of releases).

The tests use a local fake GitHub (`test/support/fake_github.dart`), whose
releases have notes as the release workflow writes them.
`ServerProcess.start` in `test/support/exe.dart` turns the check off unless
a test asks for it with its own fake, so no test and no CI run asks the real
GitHub.

A release must be tagged `vX.Y.Z` with the version in `pubspec.yaml`, be a
full release (not a draft or pre-release), carry the extension as
`smartschool-mcp.mcpb` and the server as `smartschool-mcp.exe` (the notice
links to those files), and have the `## Nieuw in deze versie` section in its
notes. The release workflow takes care of all of it (see
[Extension and releases](#extension-and-releases)).

## Extension and releases

The Claude Desktop extension is described by `manifest.json` in the project
root ([MCPB manifest 0.3](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)),
next to its icon `icon.png` (a placeholder for now). Claude Desktop runs
`server/smartschool-mcp.exe` from the installed extension and passes the
fields of the install form as the `SMARTSCHOOL_*` variables. Colleagues fill
in that form, so its titles and descriptions are in Dutch, and the titles
are the ones the server's messages use (`Setting.formTitle` in
`lib/src/settings.dart`). `test/manifest_test.dart` checks the manifest
against the server: a field per setting with that title, the variables, the
tools of the [tool pages](../README.md#tool-areas), in the order the README's
overview links the pages (add a tool to both, in the same order, and to the
table at the top of its page) and the icon.

The colleague guide, `docs/installatie.md`, names the same form fields, the
release asset, the question that runs `smartschool_status`, the cache and
download files, and the size and time limits. The guide for ChatGPT,
`docs/installatie-chatgpt.md`, names the release exe, the install folder,
the form with its keys, and `config.toml`. `test/guide_test.dart` checks
those against the server and the installer; it also checks the links
between the guides, and that the README, the release notes and the
manifest's `documentation` link to them. `test/docs_links_test.dart` checks
that every relative link in the README and in `docs/` leads to a file and a
heading that exist. Parts that wait for the manual check in ChatGPT are
marked `TE BEVESTIGEN (#40)`. Parts that wait for the manual install checks
(#30) are marked `TE BEVESTIGEN (#30)` in HTML comments, and missing
screenshots `SCHERMAFBEELDING (#33)`.

Every optional field has a default on purpose: Claude Desktop passes a field
without a value or a default literally, as `${user_config.download_dir}`
(modelcontextprotocol/mcpb#250), and does not replace `${HOME}` in a default
(modelcontextprotocol/mcpb#251). The default of "2FA-sleutel" and
"Downloadmap" is empty; empty, the server uses its own download folder (see
[Saving files](#saving-files)). "Skore-beheer", a switch, is a `boolean`
field with the default `false`, which Claude Desktop passes as `true` or
`false` (`getMcpConfigForManifest` in `@anthropic-ai/mcpb`).

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

`CHANGELOG.md` says what is new in each version, in Dutch and for
colleagues: a section under `## X.Y.Z` with a few lines on what they notice,
without technical details, links or headings of level 1 or 2. Colleagues on
an older version see it in the update notice.

To release:

1. Set the new version in the three files and write its section in
   `CHANGELOG.md`; commit and merge.
2. Tag that commit `vX.Y.Z` and push the tag.

The *Release* workflow (`.github/workflows/release.yml`, on Windows) then
checks the tag against the version, runs the tests, builds the extension,
validates and packs it with `mcpb`, and publishes a full GitHub release with
the extension attached as `smartschool-mcp.mcpb` and the server in it as
`smartschool-mcp.exe` (always those names: the update notice links to them).
`tool/release_notes.dart` writes its notes: the version's section of
`CHANGELOG.md` under `## Nieuw in deze versie` (what the update notice
shows), then `.github/release-notes.md` under `## Installeren of bijwerken`
(how to install, in Dutch, with links to both colleague guides). The
generated release notes follow. `test/release_notes_test.dart` checks that
the update check reads exactly that section back. Both workflows pin the
same `mcpb` version. The executable is not signed.
