import 'package:dart_mcp/server.dart';

import '../presence/presence_access.dart';
import '../presence/presence_format.dart';
import '../session.dart';
import 'server_tool.dart';

/// `list_presence_classes`: the classes the account may view in
/// Smartschool's Presence module, with whether it may record presences for
/// each ([PresenceService.getConfig]).
ServerTool listPresenceClassesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_presence_classes',
    title: 'List the classes of the Presence module',
    description:
        "Lists the classes this account may view in Smartschool's Presence "
        'module, where absence administrators record the half-day presences '
        'of pupils: per morning and per afternoon, the registration that '
        'counts for the government. One line per class: its name, class id, '
        'and whether the account may record presences for it ("may record") '
        'or only view them ("view only"). A grouping class without a school '
        "structure is marked as such: presences are recorded in the pupils' "
        'official class. Pass the class id to list_class_presences, '
        'set_pupils_late and set_pupils_present. Only for an account with '
        'the right to record half-day presences, as an absence administrator '
        'has; without it, the tool says so. Reading changes nothing.',
    inputSchema: Schema.object(),
    annotations: ToolAnnotations(
      title: 'List the classes of the Presence module',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (_) => _list(session),
);

Future<CallToolResult> _list(SmartschoolSession session) async {
  final classes = presenceClasses(
    await withPresence(session, (presence) => presence.getConfig()),
  );
  final String text;
  if (classes.isEmpty) {
    text =
        'The Presence module lists no classes for this account, as for an '
        'account without $presenceRights. If so, '
        '${presenceFix(session.source)}.';
  } else {
    final recordable = classes.where((c) => c.userCanRecord).length;
    final count = classes.length == 1 ? '1 class' : '${classes.length} classes';
    text = [
      'The Presence module lists $count for this account, in its order; it '
          'may record presences for $recordable of them.',
      for (final presenceClass in classes) formatPresenceClass(presenceClass),
    ].join('\n');
  }
  return CallToolResult(content: [TextContent(text: text)]);
}
