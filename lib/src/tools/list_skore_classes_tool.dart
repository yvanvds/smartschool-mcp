import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_access.dart';
import '../skore/skore_format.dart';
import 'server_tool.dart';

/// `list_skore_classes`: the classes of Skore's report models, with the
/// class id `list_skore_courses` takes; optionally only those whose name or
/// group holds some words.
ServerTool listSkoreClassesTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'list_skore_classes',
    title: 'List the classes in Skore',
    description:
        'Lists the classes in Skore, the Smartschool module for scores and '
        'reports, as its report models hold them (Rapporten > Modellen > a '
        'model > Leden): one line per class with its name, its Skore class '
        'id, the group of classes it is listed under and its report model, '
        'in Skore\'s order. Pass the class id to list_skore_courses to see '
        'the courses of the class and who is assigned to each. A school has '
        'many classes: to find one, pass query with (part of) the name of '
        'the class or of its group, such as 3B1 or 5WW. The Skore class id '
        'is Skore\'s own: it is not a planner id. Only for an account with '
        'the rights for score management in Skore; without them, the tool '
        'says so. Reading changes nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words that must all occur in the name of the class or of its '
              'group, ignoring case and accents, also as part of a longer '
              'word: 5WW finds 5WW1 and 5WW2. Default: all classes.',
        ),
      },
    ),
    annotations: ToolAnnotations(
      title: 'List the classes in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final query = (arguments['query'] as String? ?? '').trim();
  final classes = await withSkore(session, (skore) => skore.getClasses());
  return CallToolResult(
    content: [TextContent(text: formatSkoreClasses(classes, query))],
  );
}

/// What `list_skore_classes` answers: the [classes] whose name or group
/// holds every word of [query] (all of them for an empty query), one per
/// line, in Skore's order.
String formatSkoreClasses(List<SkoreClass> classes, String query) {
  if (classes.isEmpty) {
    return 'Skore lists no classes in its report models. A school without '
        'report models in Skore has none.';
  }
  final found = skoreMatches(classes, query, (c) => [c.name, ?c.groupName]);
  final models = {for (final c in classes) c.modelId}.length;
  final all =
      '${classes.length} ${classes.length == 1 ? 'class' : 'classes'} in '
      '$models report ${models == 1 ? 'model' : 'models'}';
  if (query.isEmpty) {
    return [
      'Skore lists $all:',
      for (final skoreClass in classes) '- ${formatSkoreClass(skoreClass)}',
    ].join('\n');
  }
  if (found.isEmpty) {
    return 'None of the $all in Skore has "$query" in the name of the class '
        'or its group. Look for a part of the name, such as 5WW, or leave '
        'out query to list them all.';
  }
  return [
    'Skore finds ${found.length} of its $all for "$query":',
    for (final skoreClass in found) '- ${formatSkoreClass(skoreClass)}',
  ].join('\n');
}
