import 'package:dart_mcp/server.dart';

import '../planner/planner_format.dart';
import '../presence/presence_access.dart';
import '../presence/presence_format.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `list_class_presences`: the pupils of one class in Smartschool's
/// Presence module with what their half-days hold on one day, named with
/// the codes of the class ([PresenceService.getClassPupils],
/// [PresenceService.getAllCodes]).
///
/// [now] gives today, the default day.
ServerTool listClassPresencesTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'list_class_presences',
    title: 'List the presences of a class on a day',
    description:
        "Lists the pupils of one class in Smartschool's Presence module with "
        'what their half-days hold on one day: the morning and the '
        'afternoon, each by the name of its status (such as "Aanwezig", "Te '
        'laat", "Te laat zonder geldige reden" or an absence code), with its '
        'motivation, or "nothing recorded". One line per pupil: name, pupil '
        'id, morning and afternoon. Take class_id from '
        'list_presence_classes. Use it to check who was marked present or '
        'late, and always before set_pupils_late or set_pupils_present: it '
        'gives the pupil ids, and what their half-days hold now. Only the '
        'half-days are shown, not the registrations per lesson. When the '
        'module lists no pupils, the tool gives its reason, such as a class '
        'without pupils or a day in the future. Only for an account with the '
        'right to '
        'record half-day presences, as an absence administrator has; without '
        'it, the tool says so. Reading changes nothing.',
    inputSchema: Schema.object(
      properties: {
        'class_id': presenceClassIdSchema(),
        'date': Schema.string(
          description:
              'The day, like 2026-10-05. Smartschool time (Belgium). '
              'Default: today.',
        ),
      },
      required: ['class_id'],
    ),
    annotations: ToolAnnotations(
      title: 'List the presences of a class on a day',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _list(session, request.arguments ?? const {}, now),
);

Future<CallToolResult> _list(
  SmartschoolSession session,
  Map<String, Object?> arguments,
  DateTime Function() now,
) async {
  final classId = requiredIntArgument(arguments, 'class_id');
  final day = switch (arguments['date']) {
    final String date when date.trim().isNotEmpty => presenceDay(date),
    _ => presenceToday(now()),
  };
  final read = await withPresence(
    session,
    (presence) => readPresenceDay(presence, classId, day),
  );
  return CallToolResult(content: [TextContent(text: formatPresenceDay(read))]);
}

/// What `list_class_presences` answers: a line on the class and the day,
/// then one line per pupil in the module's order.
String formatPresenceDay(PresenceDay read) {
  final presenceClass = read.presenceClass;
  final named = formatPresenceClassName(presenceClass);
  final when = formatPlannerDay(read.day);
  final record = presenceClass.userCanRecord
      ? 'This account may record presences for this class.'
      : 'This account may only view this class: set_pupils_late and '
            'set_pupils_present refuse it.';
  final grouping = presenceClass.structId == null
      ? ' The class is a grouping class without a school structure, so the '
            "statuses are named by their code id; presences are recorded in "
            "the pupils' official class."
      : '';
  if (read.pupils.isEmpty) {
    // The module says why (yvanvds/dartschool#104): a class without pupils,
    // a day in the future.
    final why = switch (read.refusal) {
      final reason? => ': ${formatModuleReason(reason)}',
      null => ', and gives no reason.',
    };
    return 'The Presence module lists no pupils for $named on $when$why '
        '$record$grouping';
  }
  final count = read.pupils.length == 1
      ? '1 pupil'
      : '${read.pupils.length} pupils';
  return [
    '${capitalized(named)}, $when: $count, in the '
        "module's order. $record$grouping",
    for (final pupil in read.pupils)
      formatPresenceLine(pupil, read.date, read.codes),
  ].join('\n');
}
