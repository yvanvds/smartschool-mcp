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
fake Smartschool.

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
timings only; run it with `--name search_messages`.

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

- `smartschool_status`: whether the connection works, or what to fix.
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
  before the subject. A reply to a sent message goes to its recipients. The
  tool is marked destructive, so Claude Desktop asks for approval every
  time, and Claude is told to show the text and recipients and wait for the
  user's confirmation first. It never sends a reply twice by itself: when
  Smartschool does not confirm a send, it says the reply may have been sent
  and to check the sent box. Replies are new messages, not linked to the
  original (yvanvds/dartschool#26).

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

## License

GPL-3.0. See [LICENSE](LICENSE).
