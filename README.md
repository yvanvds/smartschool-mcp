# smartschool-mcp

A local [MCP](https://modelcontextprotocol.io) server that gives Claude
Desktop access to Smartschool. It is built for teachers on Windows and
distributed as a Claude Desktop extension (`.mcpb`).

It is written in Dart on top of
[`flutter_smartschool`](https://github.com/yvanvds/dartschool) and
[`dart_mcp`](https://pub.dev/packages/dart_mcp), and compiles to a standalone
Windows executable, so users do not need Node, Python or Dart installed.

## Development

Requires the Dart SDK (3.10.1 or later).

```
dart pub get
dart format .
dart analyze
dart test
```

`dart test` includes an end-to-end test that compiles the executable and
talks to it over stdio. It never contacts Smartschool: the other tests use a
fake Smartschool. No test asks the real GitHub for updates either (see
*Update check* below).

### Local credentials

For development the server can read its Smartschool settings from a
`credentials.yml` in the project root (git-ignored, never commit it):

```yaml
main_url: yourschool.smartschool.be
username: your.username
password: your-password
mfa: YOUR-TOTP-BASE32-SECRET
```

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
searches for a word of a read message twice (the second time from your
message text cache) and for a word that occurs nowhere, and prints counts and
timings only; run it with `--name search_messages`. The Intradesk test only
reads too (no file is downloaded): it lists the top of Intradesk and a folder,
searches with `refresh: true` (a full walk of Intradesk, a few minutes on a
large one) and then from the index, and prints counts and timings only; run
it with `--name list_intradesk_folder`. The file test downloads (never
changes) the two smallest Word, Excel, PowerPoint, PDF, PNG and JPEG files it
finds, reads them with `read_intradesk_file`, checks that a file above the
size limit is refused without downloading it, and prints formats, sizes,
character counts and timings only; run it with `--name read_intradesk_file`.

### Build

```
dart compile exe bin/smartschool_mcp.dart
```

This writes `bin/smartschool_mcp.exe` (git-ignored). Use `-o <path>` to put
it elsewhere.

The server speaks MCP over stdin/stdout, so **stdout is reserved for the
protocol**: log to stderr (`log()` in `lib/src/log.dart`), never `print` to
stdout.

### Try it in Claude Desktop

Open Claude Desktop's config file via *Settings → Developer → Edit Config*
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
        "SMARTSCHOOL_MFA": "YOUR-TOTP-BASE32-SECRET"
      }
    }
  }
}
```

`SMARTSCHOOL_MFA` is the Base32 secret of your authenticator app (TOTP); MFA
is mandatory for teachers. Restart Claude Desktop after editing the file. The
server's stderr ends up in Claude Desktop's MCP log
(`%APPDATA%\Claude\logs\mcp-server-smartschool.log`).

Then ask Claude "Werkt mijn Smartschool-verbinding?": the
`smartschool_status` tool reports whether the settings are complete, whether
the login works and who is logged in, or what to fix.

### Tools

- `smartschool_status`: whether the connection works, or what to fix, and
  whether a newer version is available (see *Update check* below).
- `list_messages`: the headers of the inbox, sent box or archive, newest
  first, filtered by words in subject or sender, unread, and date range.
  Smartschool only returns the newest 50 messages of a box
  (yvanvds/dartschool#15).
- `read_message`: one message with its recipients, attachment names and the
  body as plain text. It does not mark the message as read.
- `search_messages`: searches the text, subject and sender of the messages
  in the inbox and archive (or the boxes named) for words, ignoring case and
  accents, optionally within a date range, and returns the matching messages
  newest first with a snippet around the words. It downloads each message
  text once (at most 100 per search, 4 at a time, newest first) and keeps it
  in the message text cache (see below), so later searches are quick; the
  result says when messages were left unsearched. Like `list_messages` it
  only sees the newest 50 messages of a box.
- `archive_messages`: moves up to 100 inbox messages (ids from
  `list_messages`) to the archive and reports per id whether it was
  archived, was already in the archive, or why not. Only the newest 50 inbox
  messages can be archived, the ones `list_messages` shows. Claude proposes
  candidates when asked for advice and archives when asked to.
- `reply_to_message`: sends a reply (plain text or simple Markdown) to the
  sender of a message, or with `reply_all` to everyone on it, with one `Re:`
  before the subject. A reply to a sent message goes to its recipients,
  except those in BCC. The tool is marked destructive, so Claude Desktop
  asks for approval every time, and Claude is told to show the text and
  recipients and wait for the user's confirmation first. It never sends a
  reply twice by itself: when Smartschool does not confirm a send, it says
  the reply may have been sent and to check the sent box. Replies are new
  messages, not linked to the original (yvanvds/dartschool#26).
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
`intradesk_cache.dart`; name matching in `intradesk_search.dart`, output
lines in `intradesk_format.dart`, and the size-limited download
(`downloadIntradeskFile`) in `intradesk_download.dart`.

Reading documents lives in `lib/src/documents/`, independent of Intradesk so
that message attachments can use it too: `readDocument(bytes, name: ...)` in
`document_reader.dart` returns a `DocumentText`, a `DocumentImage` or an
`UnreadableDocument` with the reason (in `document_content.dart`); the
readers per format are `docx_text.dart`, `xlsx_text.dart`, `pptx_text.dart`,
`pdf_text.dart`, `plain_text.dart` and `image_content.dart`. The
size-limited download itself (`downloadCapped`, for any Smartschool path) is
in `lib/src/capped_download.dart`.

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
counts, never a search query or message text. The colleague guide (#11) must
say where the folder is and what it holds.

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
download goes past it (the library cannot limit a download,
yvanvds/dartschool#41). Text longer than 100,000 characters (Claude Desktop
accepts about 150,000 per tool result) is cut off with a note, and a PDF
stops after 30 seconds of reading. The log shows formats, sizes and counts,
never a name or any text.

### Login

The server logs in automatically on the first tool call, including the 2FA
step (TOTP from `SMARTSCHOOL_MFA`). The session cookies are kept in
`%USERPROFILE%\.cache\smartschool\<username>`, so a restart only logs in
again when the saved session has expired. The log shows which happened.

Tools use the shared `SmartschoolSession` (`lib/src/session.dart`): call
`session.run((client) => ...)` and let its `SmartschoolProblem` propagate;
the server turns it into an error result with a message that tells the
teacher which setting to fix. When Smartschool rejects an expired session,
`run` logs in again and runs the action once more, so an action must be safe
to repeat. Sending is not: `reply_to_message` turns every failure after the
submit into a result that is not retried (see `_send` in
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
page and "download `smartschool-mcp.mcpb` and double-click it", for Claude to
pass on. That happens once per server process (Claude Desktop starts one per
session), and not at all after `smartschool_status` showed it. Error results
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
`smartschool-mcp.mcpb`: the notice names that file and links to the release
page.

## License

GPL-3.0. See [LICENSE](LICENSE).
