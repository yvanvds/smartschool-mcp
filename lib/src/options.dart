/// The command-line options of the server.
final class ServerOptions {
  const ServerOptions({this.credentialsPath});

  /// Parses [args].
  ///
  /// Throws a [FormatException] for an unknown or incomplete option.
  factory ServerOptions.parse(List<String> args) {
    String? credentialsPath;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
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
    return ServerOptions(credentialsPath: credentialsPath);
  }

  /// The `credentials.yml` to read the Smartschool settings from, or null to
  /// use the extension settings (`SMARTSCHOOL_*` environment variables).
  ///
  /// For development only. The file is never looked up on its own: a
  /// colleague's installed extension must not pick up some other
  /// `credentials.yml`.
  final String? credentialsPath;

  static const usage = '''
Usage: smartschool_mcp [--credentials <path>]

Serves MCP on stdin/stdout. Without options, the Smartschool settings come
from the SMARTSCHOOL_MAIN_URL, SMARTSCHOOL_USERNAME, SMARTSCHOOL_PASSWORD and
SMARTSCHOOL_MFA environment variables (the Claude Desktop extension settings).

  --credentials <path>  Read the settings from this credentials.yml instead
                        (keys: main_url, username, password, mfa, and
                        optionally download_dir). For development.

save_intradesk_file and save_message_attachment save files into the folder in
SMARTSCHOOL_DOWNLOAD_DIR (then download_dir in the credentials file), by
default %USERPROFILE%\\Downloads\\Smartschool. The server deletes the files it
saved there after 7 days and never touches other files.

Once a day the server asks GitHub whether a newer release exists.
SMARTSCHOOL_MCP_UPDATE_CHECK=off turns that off; SMARTSCHOOL_MCP_UPDATE_URL
asks another address instead of the GitHub API. For tests and development.''';
}
