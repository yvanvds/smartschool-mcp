import 'package:dart_mcp/server.dart';

import '../presence/presence_access.dart';
import '../presence/presence_writes.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `set_pupils_present`: marks pupils of a class present ("Aanwezig") for a
/// half-day in Smartschool's Presence module, with the library's
/// [PresenceService.setPresent], one pupil after the other
/// ([changePresences]): for example to undo a "Te laat" recorded by mistake.
///
/// Marked destructive and idempotent, as `set_pupils_late`. [now] gives
/// today, to refuse a day in the future.
ServerTool setPupilsPresentTool(
  SmartschoolSession session, {
  DateTime Function() now = DateTime.now,
}) => ServerTool(
  definition: Tool(
    name: 'set_pupils_present',
    title: 'Mark pupils present for a half-day',
    description:
        'Marks one or more pupils of a class present ("Aanwezig") for the '
        "morning or the afternoon of a day in Smartschool's Presence module, "
        'the half-day registration that counts for the government: for '
        'example to undo a "Te laat" recorded by mistake. This changes an '
        'official record about pupils: before calling this tool, read the '
        'class with list_class_presences; show the user the class, the pupils '
        'by name, the day and the half-day, what their half-day holds now and '
        'the motivation, and only call this tool after the user has '
        'explicitly confirmed it. Pass all pupils of one confirmation in one '
        'call. The server only changes a half-day that holds nothing '
        'recorded, "Aanwezig", "Te laat" or "Te laat zonder geldige reden". '
        "It refuses the whole call, before anything is saved, when a pupil's "
        'half-day holds anything else (such as an absence the secretariat '
        'recorded, which is changed in Smartschool itself), when a pupil is '
        'not listed in the class, for a day in the future, for a class the '
        'account may not record presences for, and for a class or day the '
        'Presence module refuses (with its reason); the result says why. It '
        'marks the pupils one after the other and stops at the first that '
        "fails, also when a pupil's half-day changed to another status "
        'meanwhile. The result says per pupil whether the status was set, '
        'the pupil already had it (nothing saved), or was not changed or not '
        'tried, and what the half-day holds now, as Smartschool answered the '
        'save. Pass that on to the user. Only for an account with the right to '
        'record half-day presences, as an absence administrator has.',
    inputSchema: Schema.object(
      properties: {
        'class_id': presenceClassIdSchema(),
        'pupil_ids': presencePupilIdsSchema(),
        'date': presenceWriteDateSchema(),
        'part': presencePartSchema(),
        'motivation': presenceMotivationSchema(),
      },
      required: ['class_id', 'pupil_ids', 'date', 'part'],
    ),
    annotations: ToolAnnotations(
      title: 'Mark pupils present for a half-day',
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
      tool: 'set_pupils_present',
      classId: requiredIntArgument(arguments, 'class_id'),
      pupilIds: {...intListArgument(arguments, 'pupil_ids')}.toList(),
      day: presenceDay(arguments['date'] as String),
      part: presencePartArgument(arguments),
      target: PresenceTarget.present,
      motivation: presenceMotivationArgument(arguments),
      today: presenceToday(now()),
    );
  },
);
