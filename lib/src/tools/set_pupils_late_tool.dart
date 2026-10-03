import 'package:dart_mcp/server.dart';

import '../presence/presence_access.dart';
import '../presence/presence_writes.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `set_pupils_late`: marks pupils of a class late ("Te laat", or "Te laat
/// zonder geldige reden") for a half-day in Smartschool's Presence module,
/// with the library's [PresenceService.setLate], one pupil after the other
/// ([changePresences]).
///
/// A half-day is an official record about pupils, so the tool is marked
/// destructive (for Claude Desktop to ask for approval before every call).
/// It is idempotent: marking a pupil late again saves nothing. [now] gives
/// today, to refuse a day in the future.
ServerTool setPupilsLateTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'set_pupils_late',
    title: 'Mark pupils late for a half-day',
    description:
        'Marks one or more pupils of a class late ("Te laat") for the morning '
        "or the afternoon of a day in Smartschool's Presence module, the "
        'half-day registration that counts for the government; with '
        'without_valid_reason, "Te laat zonder geldige reden". For example '
        'the pupils of a bus that came late. This changes an official record '
        'about pupils: before calling this tool, read the class with '
        'list_class_presences; show the user the class, the pupils by name, '
        'the day and the half-day, the status and the motivation, and only '
        'call this tool after the user has explicitly confirmed it. Pass all '
        'pupils of one confirmation in one call. The server only changes a '
        'half-day that holds nothing recorded, "Aanwezig", "Te laat" or "Te '
        'laat zonder geldige reden". It refuses the whole call, before '
        "anything is saved, when a pupil's half-day holds anything else (such "
        'as an absence the secretariat recorded), when a pupil is not listed '
        'in the class, for a day in the future, and for a class the account '
        'may not record presences for; the result says why. It marks the '
        'pupils one after the other and stops at the first that fails. '
        'Afterwards it reads the class again: the result says per pupil '
        'whether the status was set, the pupil already had it (nothing '
        'saved), or was not changed or not tried, and what the half-day '
        'holds now. Pass that on to the user. To undo a "Te laat" recorded by '
        'mistake, use set_pupils_present. Only for an account with the right '
        'to record half-day presences, as an absence administrator has.',
    inputSchema: Schema.object(
      properties: {
        'class_id': presenceClassIdSchema(),
        'pupil_ids': presencePupilIdsSchema(),
        'date': presenceWriteDateSchema(),
        'part': presencePartSchema(),
        'without_valid_reason': Schema.bool(
          description:
              'true for "Te laat zonder geldige reden" (late without a valid '
              'reason) instead of "Te laat". Default false.',
        ),
        'motivation': presenceMotivationSchema(),
      },
      required: ['class_id', 'pupil_ids', 'date', 'part'],
    ),
    annotations: ToolAnnotations(
      title: 'Mark pupils late for a half-day',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) {
    final arguments = request.arguments ?? const {};
    return changePresences(
      session,
      tool: 'set_pupils_late',
      classId: requiredIntArgument(arguments, 'class_id'),
      pupilIds: {...intListArgument(arguments, 'pupil_ids')}.toList(),
      day: presenceDay(arguments['date'] as String),
      part: presencePartArgument(arguments),
      target: arguments['without_valid_reason'] == true
          ? PresenceTarget.lateWithoutReason
          : PresenceTarget.late,
      motivation: presenceMotivationArgument(arguments),
      today: presenceToday(now()),
    );
  },
);
