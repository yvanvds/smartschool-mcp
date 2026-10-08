/// The version of this server.
///
/// Single source of truth for the version string: the MCP `initialize`
/// handshake, the update check and the packaging all read it from here. Keep
/// it equal to `version:` in `pubspec.yaml` (a test enforces this).
const String packageVersion = '0.4.0';
