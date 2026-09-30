# smartschool-mcp

Local MCP server in Dart that gives Claude Desktop access to Smartschool (messages, Intradesk). It is built on the `flutter_smartschool` library from [yvanvds/dartschool](https://github.com/yvanvds/dartschool), which is maintained by the same author.

## Problems in the library: file an issue in dartschool

Whenever something in `flutter_smartschool` doesn't work, behaves unexpectedly or is missing, **always file an issue in yvanvds/dartschool**. That is how the library gets better. This applies to bugs, missing methods, and errors that can't be told apart. Include:
- steps to reproduce;
- expected and actual behaviour;
- the likely cause, if known;
- the workaround used here, if any, with the file it lives in.

Link the dartschool issue from the related smartschool-mcp issue or PR. A workaround here is temporary: track its removal in a smartschool-mcp issue labelled `blocked` that references the dartschool issues.

## Credentials

`credentials.yml` in the repo root holds real Smartschool credentials for local testing (`--credentials credentials.yml`, see `.mcp.json`). It is git-ignored. Never read, print, log or commit its contents. Keep live logins to a minimum: repeated failed logins can lock the account.
