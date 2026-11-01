import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_labels.dart';
import '../planner/planner_access.dart';
import '../session.dart';
import 'server_tool.dart';

/// `create_lesfiche_label`: makes an own label of the user, with a text and
/// one of the web client's colours (`LessonContentService.createUserLabel`,
/// dartschool#228), for `create_lesfiche` and `edit_lesfiche` to put on
/// lesfiches (#188).
///
/// Marked destructive, as the other writes of the Lesfiches module are: a
/// write that Claude is told to show the user first and to make only after
/// the user's confirmation, and Claude Desktop and Codex ask approval only
/// for a tool marked destructive. Not idempotent: a second call with the
/// same text is refused (the labels module refuses a text one of the own
/// labels has, `name.already.used`), which the result says in plain words.
/// The library sends the create once, never again after logging in again.
///
/// The text and the colour are checked before anything is sent
/// ([lesficheLabelTextArgument], [lesficheLabelColorArgument]). The library
/// does not change or remove a label.
ServerTool createLesficheLabelTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'create_lesfiche_label',
    title: 'Make an own Smartschool label',
    description:
        'Makes a new own label of the user, with its text and colour, for '
        'the lesfiches of the Smartschool Lesfiches module (and the other '
        'modules that show labels); the school\'s labels are made by the '
        'school. Use it when the user wants to sort lesfiches with a label '
        'that list_lesfiche_labels does not show yet. Before calling this '
        'tool, show the user the text and the colour, and only call this '
        'tool after the user has explicitly confirmed it. A text of more '
        'than ${LessonContentService.maxLabelLength} characters, or one an '
        'own label has already, is refused, and nothing is made. The result '
        'gives the label; put it on lesfiches with create_lesfiche or '
        'edit_lesfiche. This server does not change or remove a label: the '
        'user does that in Smartschool. If the result says the label may or '
        'may not have been made, do not call this tool again: check with '
        'list_lesfiche_labels, and tell the user. For requests like "maak '
        'een label Herhaling".',
    inputSchema: Schema.object(
      properties: {
        'text': Schema.string(
          description:
              'The text of the label, as the user confirmed it: at most '
              '${LessonContentService.maxLabelLength} characters.',
          minLength: 1,
        ),
        'color': UntitledSingleSelectEnumSchema(
          description:
              'The colour of the label, one of the web client\'s. Default: '
              '${LessonContentService.defaultLabelColor}.',
          values: LessonContentService.labelColors,
        ),
      },
      required: ['text'],
    ),
    annotations: ToolAnnotations(
      title: 'Make an own Smartschool label',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _create(session, request.arguments ?? const {}),
);

Future<CallToolResult> _create(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final text = lesficheLabelTextArgument(arguments['text']);
  final color = lesficheLabelColorArgument(arguments['color']);
  final LessonContentLabel label;
  try {
    label = await session.run(
      (client) =>
          LessonContentService(client).createUserLabel(text, color: color),
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    log(
      'create_lesfiche_label: the labels module did not confirm the label, '
      'not retrying (${error.statusCode == null ? 'no answer' : 'HTTP ${error.statusCode}'})',
    );
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'The own label "$text" may or may not have been made: it was '
              'sent, but Smartschool did not confirm it. Do not call '
              'create_lesfiche_label again for it. First list the labels with '
              'list_lesfiche_labels to see whether it is there. Then tell the '
              'user what you found.',
        ),
      ],
    );
  } on SmartschoolLessonContentWriteRefusedError catch (error) {
    log(
      'create_lesfiche_label: refused (HTTP ${error.statusCode}, '
      '${error.violations.length} reasons)',
    );
    if (error.violations.contains('name.already.used')) {
      throw ToolError(
        'You already have an own label "$text" (Smartschool refuses a text '
        'one of your own labels has, ignoring nothing but the white space '
        'around it): list_lesfiche_labels shows it, with its id. Put that '
        'label on the lesfiche instead, or ask the user for another text. '
        'Nothing was made.',
      );
    }
    throw ToolError(
      'Smartschool refused the own label "$text" (HTTP ${error.statusCode})'
      '${error.violations.isEmpty ? ', without saying why' : ': ${error.violations.map((v) => '"$v"').join(' ')}'}. '
      'A text of more than ${LessonContentService.maxLabelLength} characters '
      'is refused so. Nothing was made.',
    );
  } catch (error) {
    // The labels module's other errors, as the Lesfiches module's.
    final toolError = plannerToolError(error);
    if (toolError == null) rethrow;
    throw ToolError('${toolError.message} Nothing was made.');
  }
  log('create_lesfiche_label: made an own label');
  return CallToolResult(
    content: [
      TextContent(
        text: [
          'Made your own label "${label.text}" (colour '
              '${label.color ?? color}), id ${label.id}.',
          'Put it on a lesfiche with edit_lesfiche (labels: the labels the '
              'lesfiche has, as read_lesfiche shows them, plus '
              '"${label.text}"), or on a new one with create_lesfiche. Its '
              'text and colour are changed, and the label removed, in '
              'Smartschool itself.',
        ].join('\n'),
      ),
    ],
  );
}
