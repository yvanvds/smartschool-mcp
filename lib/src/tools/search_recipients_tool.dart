import 'package:dart_mcp/server.dart';

import '../messages/message_box.dart';
import '../messages/recipient_search.dart';
import '../session.dart';
import 'server_tool.dart';

/// At most this many recipients are listed; the rest are counted.
const maxListedRecipients = 50;

/// `search_recipients`: the users and groups a new message can go to, found
/// by name with the search of Smartschool's compose form, as `send_message`
/// takes them.
ServerTool searchRecipientsTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'search_recipients',
    title: 'Find Smartschool message recipients',
    description:
        'Finds the users and groups (such as a class) a new Smartschool '
        'message can be sent to, by name, with the search of Smartschool\'s '
        'own compose form. Lists each one as send_message takes it: the '
        'name with "(user <id>)" or "(group <id>)", then after a "|" what '
        'tells people with the same name apart, such as their class. Use it '
        'before send_message to show the user exactly who a message will go '
        'to. When it finds several users or groups for a name, or none, ask '
        'the user who they mean: never choose for them. A message to a '
        'group goes to all its members. Finding recipients changes nothing '
        'in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'The name to look for: a first name, a last name or both, or '
              'the name of a group or class.',
          minLength: 1,
        ),
      },
      required: ['query'],
    ),
    annotations: ToolAnnotations(
      title: 'Find Smartschool message recipients',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _search(session, request.arguments ?? const {}),
);

Future<CallToolResult> _search(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final query = (arguments['query'] as String? ?? '').trim();
  if (query.isEmpty) {
    throw const ToolError('query is empty: pass the name to look for.');
  }
  final found = await withMessages(
    session,
    (messages) => searchRecipients(messages, query),
  );
  return CallToolResult(
    content: [TextContent(text: formatRecipients(query, found))],
  );
}

/// What `search_recipients` answers: [found], the recipients the search for
/// [query] found, one per line, at most [maxListedRecipients].
String formatRecipients(String query, List<Recipient> found) {
  if (found.isEmpty) {
    return 'Smartschool finds no users or groups for "$query". Check the '
        'spelling, or look for a part of the name, such as the last name.';
  }
  final listed = found.take(maxListedRecipients);
  final left = found.length - listed.length;
  return [
    'Smartschool finds ${countRecipients(found)} for "$query":',
    for (final recipient in listed) '- ${recipient.listing}',
    if (left > 0)
      '$left more not listed: look for a longer part of the name to find '
          'fewer.',
  ].join('\n');
}
