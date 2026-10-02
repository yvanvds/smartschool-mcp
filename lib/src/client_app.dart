/// The app that started the server, recognised by the name it gives itself
/// in MCP's `initialize` request (`clientInfo.name`).
///
/// The teacher fixes settings, restarts and updates differently in each app,
/// so the server's messages say how in that app's terms
/// (`ExtensionSettings`, the update notice).
enum ClientApp {
  /// Claude Desktop (`claude-ai`), and any client the server does not know:
  /// the Claude Desktop extension is the main way to install the server.
  claudeDesktop('the Smartschool extension'),

  /// Codex (`codex-mcp-client`): the ChatGPT desktop app, the Codex CLI and
  /// the Codex IDE extension. All three read the same configuration
  /// (`%USERPROFILE%\.codex\config.toml`); the ChatGPT app edits it in its
  /// settings, under Plug-ins → MCP's.
  codex('the Smartschool MCP server');

  const ClientApp(this.product);

  /// What the teacher installed, as messages call it, e.g. `the Smartschool
  /// extension`.
  final String product;

  /// The `clientInfo.name` Codex sends (`codex-rs/codex-mcp/src/
  /// rmcp_client.rs` in openai/codex).
  static const codexClientName = 'codex-mcp-client';

  /// The name the teacher gives the server in ChatGPT (the installer and
  /// the colleague guide say so), which messages use to say where its
  /// settings are. The server cannot know the name actually chosen.
  static const codexServerName = 'smartschool';

  /// The app that calls itself [name] in `initialize`.
  static ClientApp fromClientName(String name) =>
      name == codexClientName ? codex : claudeDesktop;
}

/// The [ClientApp] the server runs in, shared by everything that words a
/// message for the teacher.
///
/// [ClientApp.claudeDesktop] until the client's `initialize` request names
/// another app (`SmartschoolServer` sets [app] then). A tool call always
/// comes after `initialize`, so tool results use the right app; only the
/// startup log, written before, uses the default.
final class ClientContext {
  ClientContext([this.app = ClientApp.claudeDesktop]);

  ClientApp app;
}
