import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../session.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `read_skore_gradebook`: one of the user's own gradebooks in Skore, by its
/// id, with its periods, its pupils and whether Skore lets the user change
/// it ([SkoreGradebookService.getGradebook], dartschool#148).
///
/// Offered to every account, without a switch: the gradebook needs no
/// extra rights in Smartschool.
ServerTool readSkoreGradebookTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'read_skore_gradebook',
    title: 'Read a gradebook in Skore',
    description:
        'Reads one of the user\'s own gradebooks in Skore, the Smartschool '
        'module for scores and reports, by its gradebook id from '
        'list_skore_gradebooks. It gives the periods of the gradebook (such '
        'as DW1), in Skore\'s order, each with its period id, whether it is '
        'open (only an open period takes grades), when it closes '
        '(Smartschool time, Belgium), Skore\'s note on it, and which one '
        'Skore opens the gradebook on (active); the pupils of its class, '
        'each with the class number, the name (last name first) and the '
        'pupil id, and whether Skore greys the pupil out as inactive; and '
        'whether Skore lets the user change the gradebook. For a gradebook '
        'of an earlier school year, pass its workyear_id too, as '
        'list_skore_gradebooks lists the school years. Reading changes '
        'nothing in Skore.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description: 'The gradebook id, from list_skore_gradebooks.',
          minimum: 1,
        ),
        'workyear_id': Schema.int(
          description:
              'The school year of the gradebook, by its workyear id from '
              'list_skore_gradebooks. Default: Skore\'s current school '
              'year.',
          minimum: 1,
        ),
      },
      required: ['gradebook_id'],
    ),
    annotations: ToolAnnotations(
      title: 'Read a gradebook in Skore',
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _read(session, request.arguments ?? const {}),
);

Future<CallToolResult> _read(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final workyearId = intArgument(arguments, 'workyear_id');
  final years = SkoreGradebookYears.of(session);
  final (sheet, workyear) = await withSkoreGradebook(session, (
    gradebooks,
  ) async {
    final found = await years.find(
      gradebooks,
      gradebookId,
      workyearId: workyearId,
    );
    return (await gradebooks.getGradebook(found.gradebook), found.workyear);
  });
  return CallToolResult(
    content: [TextContent(text: formatSkoreGradebookSheet(sheet, workyear))],
  );
}

/// What `read_skore_gradebook` answers: the gradebook of [sheet] (of school
/// year [workyear]), whether the user may change it, its periods and its
/// pupils.
String formatSkoreGradebookSheet(
  SkoreGradebookSheet sheet,
  SkoreWorkyear workyear,
) {
  final periods = sheet.periods;
  final pupils = sheet.pupils;
  final inactive = pupils.where((p) => !p.isActive).length;
  final active = sheet.activePeriod;
  return [
    '${formatSkoreGradebookTitle(sheet.gradebook, workyear)}.',
    if (periods.isEmpty)
      'It has no periods yet, so it takes no grades; Skore was not asked '
          'whether the user may change it.'
    else if (sheet.isCoordinator)
      'Skore opens it read-only for the user, in coordinator mode.'
    else if (sheet.writable)
      'Skore lets the user change it'
          '${periods.any((p) => p.isOpen) ? '' : ', but none of its periods is open, so it takes no grades now'}.'
    else
      'Skore opens it read-only for the user: the user may not change it.',
    if (periods.isNotEmpty) ...[
      '${periods.length} ${periods.length == 1 ? 'period' : 'periods'}, in '
          'Skore\'s order; only an open period takes grades'
          '${active == null ? '' : ', and Skore opens the gradebook on '
                    '${active.name} (active)'}:',
      for (final period in periods)
        '- ${formatSkoreGradebookPeriod(period, active: period.id == active?.id)}',
    ],
    if (pupils.isEmpty)
      'No pupils.'
    else ...[
      '${pupils.length} ${pupils.length == 1 ? 'pupil' : 'pupils'}'
          '${inactive == 0 ? '' : ' ($inactive inactive)'}, in Skore\'s '
          'order:',
      for (final pupil in pupils) '- ${formatSkoreGradebookPupil(pupil)}',
    ],
  ].join('\n');
}
