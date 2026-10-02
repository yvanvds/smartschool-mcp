import 'package:smartschool_mcp/src/client_app.dart';
import 'package:test/test.dart';

import 'support/mcp.dart';

void main() {
  test('Codex is recognised by the name it gives in initialize; any other '
      'client gets the Claude Desktop wording', () {
    expect(ClientApp.fromClientName('codex-mcp-client'), ClientApp.codex);
    for (final name in ['claude-ai', 'Codex', 'codex', '', 'e2e-test']) {
      expect(
        ClientApp.fromClientName(name),
        ClientApp.claudeDesktop,
        reason: name,
      );
    }
  });

  test('the server records the app the client names on initialize', () async {
    for (final (name, app) in [
      (ClientApp.codexClientName, ClientApp.codex),
      ('claude-ai', ClientApp.claudeDesktop),
    ]) {
      final client = ClientContext(
        app == ClientApp.codex ? ClientApp.claudeDesktop : ClientApp.codex,
      );
      await connect(client: client, clientName: name);
      expect(client.app, app, reason: name);
    }
  });
}
