# Status

[Back to the overview](../../README.md)

One tool checks the connection, for everyone, without a switch. Ask Claude
"Werkt mijn Smartschool-verbinding?" to run it.

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`smartschool_status`](#smartschool_status) | Checks the connection and says what to fix | No |

## Tools

### `smartschool_status`

Says whether the settings are complete, whether the login works and who is
logged in, or what to fix. It also shows, for each
[opt-in switch](../../README.md#tool-areas), whether it is on and, when it
is, whether the account can use its tools; the download folder and whether
it is writable; and whether a newer version is available, with its download
link and what is new.

## How it works

### How `smartschool_status` works

Under Codex it names a variable that is close to a setting's name, and the
setting it probably means, never its value (see
[Mistyped keys](../development.md#chatgpt-and-codex)).

Each opt-in switch gets a line: off, with how to turn it on and for whom; or
on, with whether the account has the rights, checked with a cheap read once
the connection works (see [Opt-in tools](../development.md#opt-in-tools)).

It shows the download folder, where it was set, and whether it is writable
(see [Saving files](../development.md#saving-files)).

It always asks GitHub for a newer version, while it checks the login, and
shows the same as the update notice on its `Updates:` lines; its description
asks the model to give the download link and say what is new (see
[Update check](../development.md#update-check)).
