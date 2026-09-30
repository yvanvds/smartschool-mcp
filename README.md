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
talks to it over stdio.

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

## License

GPL-3.0. See [LICENSE](LICENSE).
