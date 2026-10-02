# smartschool-mcp

A local [MCP](https://modelcontextprotocol.io) server that gives Claude
Desktop, and the ChatGPT app (Codex), access to Smartschool. It is built for
teachers on Windows and distributed as a Claude Desktop extension (`.mcpb`)
and as an executable that installs itself for ChatGPT (see *ChatGPT and
Codex* below).

It is written in Dart on top of
[`flutter_smartschool`](https://github.com/yvanvds/dartschool) and
[`dart_mcp`](https://pub.dev/packages/dart_mcp), and compiles to a standalone
Windows executable, so users do not need Node, Python or Dart installed.

**Colleagues:** the installation guide, in Dutch, is
[docs/installatie.md](docs/installatie.md). It covers what you need, finding
the 2FA key, installing, testing, example questions, updating,
troubleshooting, security and privacy, and uninstalling. For the ChatGPT app
it is [docs/installatie-chatgpt.md](docs/installatie-chatgpt.md).

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

`SMARTSCHOOL_MFA` is the Base32 secret of your authenticator app (TOTP); MFA
is mandatory for teachers. Spaces in it are ignored; a value that is not
Base32 (such as the app's 6-digit code) is reported before any login. `SMARTSCHOOL_DOWNLOAD_DIR` is optional (see
*Saving files* below). Restart Claude Desktop after editing the file. The
server's stderr ends up in Claude Desktop's MCP log
(`%APPDATA%\Claude\logs\mcp-server-smartschool.log`).

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
- it puts that path on the clipboard (`--no-clipboard` for tests);
- it shows, in Dutch, what to fill in in ChatGPT: the name `smartschool`, the
  command, no arguments and the five variables. It waits for Enter so the
  window stays open.

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
- download `smartschool-mcp.exe` and double-click it.

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
  (`reply_to_message`), unless it runs with *Full access*.
- **`HOME`:** Codex does not pass `HOME` on. A user who has `HOME` set gets
  another cache folder under Codex than under Claude Desktop, so the server
  logs in once more there.

`test/install_e2e_test.dart` installs the compiled server into a temporary
`LOCALAPPDATA`, and starts the installed copy with Codex's environment and
client name. It also installs again while that copy runs.

### Tools

- `smartschool_status`: whether the connection works, or what to fix, the
  download folder and whether it is writable, and whether a newer version
  is available (see *Update check* below).
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

Message helpers for later tools live in `lib/src/messages/`: `MessageBox`
(inbox / sent / archive, their headers and one message) and `withMessages`
in `message_box.dart`, the HTML-to-text converter `htmlToText` in
`html_to_text.dart`, the Markdown-to-HTML converter for message text Claude
writes (`markdownToHtml`, which escapes all HTML) in `markdown_to_html.dart`,
who a reply goes to (`loadReplyRecipients`) in `reply_recipients.dart`, the
filters and date-range arguments in `message_filter.dart`, the output lines in
`message_format.dart`, full-text matching and snippets (`SearchQuery`) in
`message_search.dart` and the message text cache (`MessageTextCache`) in
`message_cache.dart`.

Intradesk helpers live in `lib/src/intradesk/`: `withIntradesk`, the id
argument (`intradeskIdArgument`) and listing-to-items conversion
(`intradeskItems`) in `intradesk_access.dart`; `IntradeskItem` (kind, id,
name with extension, path, size, date changed, `extension`, `mimeType`) and
`IntradeskIndex` (lookup by id, the items inside a folder) in
`intradesk_index.dart`; the tree walk (`buildIntradeskIndex`) in
`intradesk_walk.dart`; the index cache (`IntradeskIndexCache`) in
`intradesk_cache.dart`; name matching in `intradesk_search.dart` and output
lines in `intradesk_format.dart`.

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
step (TOTP from `SMARTSCHOOL_MFA`). The session cookies are kept in
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
turns a submit that Smartschool does not confirm
(`SmartschoolSendUnconfirmedError`) into a result that is not retried. A
step of the send that Smartschool refused the session for, the submit
included, sent nothing, so `run` may repeat it (see `_send` in
`lib/src/tools/reply_to_message_tool.dart`).

### Update check

At startup, in the background (startup never waits for it), the server asks
GitHub for the latest release of this repository
(`https://api.github.com/repos/yvanvds/smartschool-mcp/releases/latest`,
unauthenticated; GitHub leaves out drafts and pre-releases) and compares its
tag (`vX.Y.Z`) with the built-in version (`lib/src/version.dart`). A tag that
is not a version is ignored. GitHub answers 404 while no release has been
published: nothing to report. A check waits at most 5 seconds; offline, rate
limited or an answer it does not understand is only logged.

It asks at most once a day. The time and result of the last successful check
are kept in

```
%USERPROFILE%\.cache\smartschool\smartschool-mcp-update-check.json
```

(`%HOME%` instead of `%USERPROFILE%` when `HOME` is set), so a restart within
24 hours does not ask again. It needs no Smartschool settings. A server that
keeps running asks again after 24 hours, on a tool call.

When a newer release exists, the first successful tool result after the
check gets one extra text after its content: the new version, the release
page and "download `smartschool-mcp.mcpb` and double-click it" (under Codex:
download `smartschool-mcp.exe`, double-click it and restart ChatGPT), for the
model to pass on. That happens once per server process (Claude Desktop starts
one per session), and not at all after `smartschool_status` showed it. Error results
never get it. `smartschool_status` always asks GitHub (while it checks the
login, so it takes no longer) and shows the result on its `Updates:` line.
The code is in `lib/src/update_check.dart`; the server adds the notice in
`lib/src/server.dart`.

For tests and development:

- `SMARTSCHOOL_MCP_UPDATE_CHECK=off` turns the check off;
- `SMARTSCHOOL_MCP_UPDATE_URL=<address>` asks that address instead of the
  GitHub API (it must answer the same way).

The tests use a local fake GitHub (`test/support/fake_github.dart`).
`ServerProcess.start` in `test/support/exe.dart` turns the check off unless a
test asks for it with its own fake, so no test and no CI run asks the real
GitHub.

A release must be tagged `vX.Y.Z` with the version in `pubspec.yaml`, be a
full release (not a draft or pre-release), and carry the extension as
`smartschool-mcp.mcpb` and the server as `smartschool-mcp.exe`: the notice
names those files and links to the release page. The release workflow takes care of all three (see below).

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
and with `--tag vX.Y.Z` also when the tag does; CI runs it, and
`test/version_test.dart` checks the same.

To release:

1. Set the new version in the three files; commit and merge.
2. Tag that commit `vX.Y.Z` and push the tag.

The *Release* workflow (`.github/workflows/release.yml`, on Windows) then
checks the tag against the version, runs the tests, builds the extension,
validates and packs it with `mcpb`, and publishes a full GitHub release with
the extension attached as `smartschool-mcp.mcpb` and the server in it as
`smartschool-mcp.exe` (always those names: the update notice names them).
Its notes start with `.github/release-notes.md` (how to install, in Dutch,
with links to both colleague guides), followed by the generated release
notes. Both workflows pin the same `mcpb` version. The
executable is not signed.

## License

GPL-3.0. See [LICENSE](LICENSE).
