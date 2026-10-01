import 'dart:io';

/// The command Claude Desktop runs for an installed extension.
typedef McpConfig = ({
  String command,
  List<String> args,
  Map<String, String> env,
});

/// How Claude Desktop turns an extension's `manifest.json` into the command
/// it starts, after `getMcpConfigForManifest` in `@anthropic-ai/mcpb`
/// (`src/shared/config.ts`, the code Claude Desktop uses):
///
/// - null when a `required` field of `user_config` has no value (an empty
///   string counts as none): Claude Desktop does not start the server then;
/// - `${user_config.KEY}` is the value the user filled in, else the field's
///   `default`; a field with neither stays `${user_config.KEY}`, literally
///   (modelcontextprotocol/mcpb#250);
/// - `${__dirname}` is the folder the extension is installed in, `${HOME}`
///   the user's home folder. A default is used as it is: a `${HOME}` in it
///   is not replaced (modelcontextprotocol/mcpb#251).
McpConfig? claudeDesktopConfig(
  Map<String, Object?> manifest, {
  required String extensionPath,
  required Map<String, String> userConfig,
  required String home,
}) {
  final fields = (manifest['user_config'] as Map? ?? const {})
      .cast<String, Map<String, Object?>>();
  for (final MapEntry(:key, :value) in fields.entries) {
    if (value['required'] == true && (userConfig[key] ?? '').isEmpty) {
      return null;
    }
  }
  final variables = <String, String>{
    '__dirname': extensionPath,
    'pathSeparator': Platform.pathSeparator,
    '/': Platform.pathSeparator,
    'HOME': home,
    for (final MapEntry(:key, :value) in fields.entries)
      if (value['default'] case final Object value)
        'user_config.$key': '$value',
    for (final MapEntry(:key, :value) in userConfig.entries)
      'user_config.$key': value,
  };
  String substitute(String text) {
    for (final MapEntry(:key, :value) in variables.entries) {
      text = text.replaceAll('\${$key}', value);
    }
    return text;
  }

  final server = manifest['server'] as Map<String, Object?>;
  final config = server['mcp_config'] as Map<String, Object?>;
  return (
    command: substitute(config['command'] as String),
    args: [
      for (final arg in config['args'] as List? ?? const [])
        substitute(arg as String),
    ],
    env: {
      for (final MapEntry(:key, :value)
          in (config['env'] as Map? ?? const {}).cast<String, String>().entries)
        key: substitute(value),
    },
  );
}
