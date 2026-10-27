# smartschool-mcp

A local [MCP](https://modelcontextprotocol.io) server that gives Claude
Desktop, and the ChatGPT app (Codex), access to Smartschool. It is built for
teachers on Windows, and works for students too (they sign in without 2FA).
It is distributed as a Claude Desktop extension (`.mcpb`) and as an
executable that installs itself for ChatGPT (see
[ChatGPT and Codex](docs/development.md#chatgpt-and-codex)).

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

## Tool areas

Each area has a page with its tools: what each one does, whether it changes
Smartschool, and, at the bottom, how it works. An area with a switch is
offered only when the switch is on; every switch is off by default (see
[Opt-in tools](docs/development.md#opt-in-tools)).

| Area | What it covers | Switch | Tools |
| --- | --- | --- | --- |
| [Status](docs/tools/status.md) | Whether the connection works, or what to fix | | 1 |
| [Messages](docs/tools/messages.md) | Read, search, archive, mark, flag and trash messages; reply and send | | 11 |
| [Intradesk](docs/tools/intradesk.md) | Find, read and save files; add folders, weblinks and files; trash | | 8 |
| [Planner](docs/tools/planner.md) | Read planners; plan lessons, tests and tasks in your own | | 9 |
| [Lesfiches](docs/tools/lesfiches.md) | Read, make, change, trash and plan your lesfiches | | 13 |
| [Gradebook (Puntenboek)](docs/tools/gradebook.md) | Your gradebooks in Skore: evaluations, grades, feedback, report comments | | 9 |
| [Skore administration](docs/tools/skore.md) | Teachers per course and shared gradebooks, for Skore administrators | "Skore-beheer" (`SMARTSCHOOL_SKORE`) | 8 |
| [Presences](docs/tools/presences.md) | Half-day presences of classes: late and present | "Aanwezigheden" (`SMARTSCHOOL_PRESENCE`) | 4 |
| [Pupil tracking system (LVS)](docs/tools/lvs.md) | A pupil's file: notes, results, support plan, absences; read only | "Leerlingvolgsysteem" (`SMARTSCHOOL_LVS`) | 6 |

## Changes and approval

Many tools only read. Those that change Smartschool share these rules:

- **Approval at every call.** A tool that changes Smartschool is marked
  destructive: Claude Desktop asks for approval every time it is called,
  and so does Codex, unless it runs with *Full access*. Its description
  tells Claude to show you first what will happen (the recipients and the
  text, every file with its size, the list of grades, each item with its
  path) and to call it only after your explicit yes. The exceptions are
  archiving messages, marking them read or unread and flagging them: Claude
  proposes messages when you ask for advice, and changes them when you ask
  it to.
- **Never sent twice.** A message, and any write that would happen twice if
  it were repeated (a create, an add, a plan), is sent once, also when the
  server has to log in again. When Smartschool does not confirm a write, the
  tool says that it may or may not have gone through and what to read to
  check, and Claude is told not to repeat a write that could then happen
  twice.
- **A trash, not a deletion.** Messages, Intradesk items, lesfiches and
  assignments are moved to a trash in Smartschool, where you restore them
  in Smartschool itself. No tool empties a trash.

## Development

Requires the Dart SDK (3.10.1 or later).

```
dart pub get
dart format .
dart analyze
dart test
```

The tests never contact Smartschool or GitHub: they run against fakes. See
[docs/development.md](docs/development.md) for local credentials, the rules
for pupil data, building, trying it in Claude Desktop and ChatGPT, the opt-in
switches, the caches, reading, saving and uploading files, the login, the
update check, and releases. A change to a tool updates its page under
`docs/tools/`.

## License

GPL-3.0. See [LICENSE](LICENSE).
