/// The command-line options of the server.
final class ServerOptions {
  const ServerOptions({
    this.credentialsPath,
    this.install = false,
    this.clipboard = true,
  });

  /// Parses [args].
  ///
  /// Throws a [FormatException] for an unknown or incomplete option.
  factory ServerOptions.parse(List<String> args) {
    String? credentialsPath;
    var install = false;
    var clipboard = true;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--install') {
        install = true;
        continue;
      }
      if (arg == '--no-clipboard') {
        clipboard = false;
        continue;
      }
      final String? value;
      if (arg == '--credentials') {
        if (i + 1 >= args.length) {
          throw const FormatException('--credentials needs a path');
        }
        value = args[++i];
      } else if (arg.startsWith('--credentials=')) {
        value = arg.substring('--credentials='.length);
      } else {
        throw FormatException('unknown argument: $arg');
      }
      if (value.trim().isEmpty) {
        throw const FormatException('--credentials needs a path');
      }
      if (credentialsPath != null) {
        throw const FormatException('--credentials given more than once');
      }
      credentialsPath = value;
    }
    if (install && credentialsPath != null) {
      throw const FormatException(
        '--install and --credentials cannot be combined',
      );
    }
    if (!clipboard && !install) {
      throw const FormatException('--no-clipboard only goes with --install');
    }
    return ServerOptions(
      credentialsPath: credentialsPath,
      install: install,
      clipboard: clipboard,
    );
  }

  /// The `credentials.yml` to read the Smartschool settings from, or null to
  /// use the extension settings (`SMARTSCHOOL_*` environment variables).
  ///
  /// For development only. The file is never looked up on its own: a
  /// colleague's installed extension must not pick up some other
  /// `credentials.yml`.
  final String? credentialsPath;

  /// Whether to install the server for ChatGPT and Codex instead of serving
  /// MCP (`lib/src/install.dart`). A double-click does the same without the
  /// option: see [installs].
  final bool install;

  /// Whether the installer puts the installed path on the clipboard; off for
  /// tests.
  final bool clipboard;

  /// Whether to install rather than serve: with `--install`, or when started
  /// without options from a console ([interactive]), as a double-click
  /// does. An MCP client always starts the server with pipes, never a
  /// console.
  bool installs({required bool interactive}) =>
      install || (interactive && credentialsPath == null);

  static const usage = '''
Usage: smartschool_mcp [--credentials <path>]
       smartschool_mcp --install [--no-clipboard]

Serves MCP on stdin/stdout. Without options, the Smartschool settings come
from the SMARTSCHOOL_MAIN_URL, SMARTSCHOOL_USERNAME, SMARTSCHOOL_PASSWORD and
SMARTSCHOOL_MFA environment variables: the Claude Desktop extension settings,
or the environment variables of the MCP server in ChatGPT or Codex.
SMARTSCHOOL_MFA, the 2FA key, is only needed for an account with two-factor
authentication (teachers); students without 2FA leave it empty.

  --credentials <path>  Read the settings from this credentials.yml instead
                        (keys: main_url, username, password, and optionally
                        mfa, download_dir, skore and presence). For
                        development.

  --install             Install for ChatGPT and Codex instead of serving:
                        copy this executable to
                        %LOCALAPPDATA%\\Programs\\smartschool-mcp and show, in
                        Dutch, what to fill in in ChatGPT. Started from a
                        console without options (a double-click), the
                        server does the same.
  --no-clipboard        With --install: leave the clipboard alone.

save_intradesk_file and save_message_attachment save files into the folder in
SMARTSCHOOL_DOWNLOAD_DIR (then download_dir in the credentials file), by
default %USERPROFILE%\\Downloads\\Smartschool. The server deletes the files it
saved there after 7 days and never touches other files.

SMARTSCHOOL_SKORE=true (then skore: true in the credentials file) offers the
Skore tools, for an account with the rights for score management in Skore.
SMARTSCHOOL_PRESENCE=true (then presence: true) offers the presence tools,
for an account that records half-day presences, as an absence administrator
does. Both are off by default.

Once a day the server asks GitHub whether a newer release exists.
SMARTSCHOOL_MCP_UPDATE_CHECK=off turns that off; SMARTSCHOOL_MCP_UPDATE_URL
asks another address instead of the GitHub API. For tests and development.''';
}
