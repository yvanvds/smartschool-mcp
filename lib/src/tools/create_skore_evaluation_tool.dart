import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/message_filter.dart';
import '../session.dart';
import '../skore/skore_format.dart';
import '../skore/skore_gradebook_access.dart';
import '../skore/skore_gradebook_format.dart';
import '../skore/skore_writes.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// The name of the tool, as its messages name it.
const _tool = 'create_skore_evaluation';

/// `create_skore_evaluation`: creates an evaluation (a column of grades) in
/// a period of one of the user's own gradebooks in Skore, always
/// unpublished, with the library's [SkoreGradebookService.createEvaluation]
/// (dartschool#150).
///
/// Offered to every account, without a switch, like the other gradebook
/// tools. A create is not idempotent and Claude Desktop must ask for
/// approval before every call, so the tool is marked destructive. The
/// library reads the gradebook again and refuses a change that does not
/// fit, saving nothing; it sends the save once, never again after logging
/// in again; a save it cannot confirm is reported as maybe created
/// ([skoreWriteNotConfirmed]), and a new evaluation Skore shows as public
/// anyway is reported as created, for the user to check in Smartschool.
/// The library never publishes, and this tool has no way to.
ServerTool createSkoreEvaluationTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: _tool,
    title: 'Create an evaluation in a gradebook in Skore',
    description:
        'Creates an evaluation (a new column of grades, such as a test or a '
        'task) in a period of one of the user\'s own gradebooks in Skore, '
        'the Smartschool module for scores and reports, as the "new '
        'evaluation" dialog of the gradebook does. It is always created '
        'unpublished: the pupils do not see it until the user publishes it '
        'in Smartschool; this tool cannot publish. Before calling this tool, '
        'read the period with list_skore_evaluations: if it already has an '
        'evaluation with the same title and date, do not create it again. '
        'That list also gives the components a new evaluation in the period '
        'can count for, and the default. Show the user the gradebook (class '
        'and course), the period, the title, the short name if any, the '
        'date, the max and the component; say that it will be created '
        'unpublished and that the user publishes it in Smartschool; and only '
        'call this tool after the user has explicitly confirmed it. Only a '
        'gradebook of Skore\'s current school year can be changed. The '
        'server reads the gradebook again before it saves, and refuses a '
        'change that does not fit (a closed period, a date outside the '
        'school year, a gradebook the user may not change, a component Skore '
        'does not offer), saving nothing: the result says why. The result '
        'gives the evaluation as Skore lists it after the save, with its '
        'evaluation id. If the result says it may or may not have been '
        'created, do not call this tool again for it: read the period with '
        'list_skore_evaluations and tell the user what you found. If the '
        'result says it was created but Skore shows it as published or '
        'scheduled, tell the user at once to check it in Smartschool, and '
        'do not create it again.',
    inputSchema: Schema.object(
      properties: {
        'gradebook_id': Schema.int(
          description:
              'The gradebook id, from list_skore_gradebooks: a gradebook of '
              'Skore\'s current school year.',
          minimum: 1,
        ),
        'period_id': Schema.int(
          description:
              'The period, by its period id from read_skore_gradebook or '
              'list_skore_evaluations; it must be open. Default: the period '
              'Skore opens the gradebook on (active).',
          minimum: 1,
        ),
        'title': Schema.string(
          description: 'The title of the evaluation, such as Toets Python.',
        ),
        'short_name': Schema.string(
          description:
              'A short name for the evaluation, such as T1. Default: none.',
        ),
        'date': Schema.string(
          description:
              'The day of the evaluation, like 2026-10-14, in the current '
              'school year (1 September to 31 August).',
        ),
        'max': Schema.int(
          description:
              'The highest grade, a positive whole number, such as 20.',
          minimum: 1,
        ),
        'component': Schema.string(
          description:
              'What the evaluation counts for, by its name (such as DW) or '
              'its component id, as list_skore_evaluations lists them for '
              'the period; geen (component id 0) for none. Default: the '
              'default list_skore_evaluations names.',
        ),
      },
      required: ['gradebook_id', 'title', 'date', 'max'],
    ),
    annotations: ToolAnnotations(
      title: 'Create an evaluation in a gradebook in Skore',
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
  final gradebookId = requiredIntArgument(arguments, 'gradebook_id');
  final periodId = intArgument(arguments, 'period_id');
  final title = (arguments['title'] as String? ?? '').trim();
  final shortName = (arguments['short_name'] as String?)?.trim();
  final date = _day(arguments['date']);
  final max = requiredIntArgument(arguments, 'max');
  final component = switch ((arguments['component'] as String?)?.trim()) {
    '' => null,
    final name => name,
  };
  // Refused before anything is sent: the library refuses them too, but
  // after the reads below.
  if (title.isEmpty) {
    throw const ToolError(
      'title must not be blank: give the title of the evaluation. Nothing '
      'was changed in Skore.',
    );
  }
  if (max < 1) {
    throw ToolError(
      'max must be a positive whole number, such as 20; $max is not. Nothing '
      'was changed in Skore.',
    );
  }

  final years = SkoreGradebookYears.of(session);
  // Where the evaluation goes, for a save Skore did not confirm or a new
  // evaluation that came back public: set before the save is sent.
  var where = 'gradebook id $gradebookId';
  var target = periodId;
  try {
    final (gradebook, period, created) = await withSkoreGradebookWrite(
      session,
      reread: _reread,
      (gradebooks) async {
        final found = await years.findInCurrentYear(gradebooks, gradebookId);
        final sheet = await gradebooks.getGradebook(found.gradebook);
        final period = skoreGradebookPeriod(sheet, periodId);
        if (period == null) {
          throw ToolError(
            'The ${formatSkoreGradebookName(sheet.gradebook)} has no periods '
            'yet, so no evaluation can be created in it.',
          );
        }
        where =
            'period ${formatSkorePeriodName(period)} of the '
            '${formatSkoreGradebookName(sheet.gradebook)}';
        target = period.id;
        final componentId = component == null
            ? null
            : _component(
                await gradebooks.getComponents(sheet.gradebook, period.id),
                component,
                where,
              ).id;
        final created = await gradebooks.createEvaluation(
          sheet.gradebook,
          period.id,
          title: title,
          shortName: shortName,
          date: date,
          max: max,
          componentId: componentId,
        );
        return (sheet.gradebook, period, created);
      },
    );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Created evaluation "${skoreName(created.title)}" in period '
                '${formatSkorePeriodName(period)} of the '
                '${formatSkoreGradebookName(gradebook)}. It is not '
                'published: the pupils do not see it until the user '
                'publishes it in Smartschool.',
            'Created: ${formatSkoreEvaluation(created)}',
          ].join('\n'),
        ),
      ],
    );
  } on SmartschoolSkoreSaveUnconfirmedError catch (error) {
    // Caught as the base type, so that a save Skore did not confirm is never
    // reported as an unexpected error. createEvaluation throws its subtype,
    // with the id Skore answered for the new evaluation when it did.
    final evaluationId = switch (error) {
      SmartschoolSkoreEvaluationCreateUnconfirmedError(:final evaluationId) =>
        evaluationId,
      _ => null,
    };
    final lookFor = evaluationId == null
        ? 'that title on that day'
        : 'evaluation id $evaluationId, the id Skore answered for it';
    return skoreWriteNotConfirmed(
      tool: _tool,
      what:
          'The new evaluation "${skoreName(title)}" (${formatSkoreDay(date)}, '
          'max $max) in $where',
      check:
          'read the period with list_skore_evaluations (gradebook_id '
          '$gradebookId, period_id $target) and look for $lookFor: when it '
          'is listed, it was created, unpublished; when it is not, nothing '
          'was created',
      error: error,
    );
  } on SmartschoolSkoreEvaluationPublicError catch (error) {
    // The library's message names the evaluation: to the log only.
    log(
      '$_tool: created, but public: '
      '${'$error'.replaceAll(RegExp(r'\s+'), ' ')}',
    );
    final created = error.evaluation;
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text: [
            'Evaluation "${skoreName(created.title)}" was created in $where, '
                'but Skore shows it as public, although the server sent it '
                'unpublished: ${formatSkorePublication(created.publication)}. '
                'Its pupils may see it. Tell the user now to check its '
                'publication in Smartschool and change it there: the server '
                'never changes a publication. Do not call $_tool again for '
                'it: it exists, and a second call creates a second '
                'evaluation.',
            'Created: ${formatSkoreEvaluation(created)}',
          ].join('\n'),
        ),
      ],
    );
  }
}

/// What to read again after a change Skore refused, to correct the call.
const _reread =
    'Read the gradebook again with read_skore_gradebook (its periods, and '
    'whether the user may change it) and the period with '
    'list_skore_evaluations (its evaluations, and the components a new one '
    'can count for)';

/// The `date` argument: a day like `2026-10-14`, without a time.
///
/// Throws a [ToolError] for anything else, also a day that does not exist
/// (`2026-02-30`), before anything is sent.
DateTime _day(Object? value) {
  final invalid = ToolError(
    'date must be a day like 2026-10-14, without a time; '
    '${value is String ? '"$value"' : '$value'} is not. Nothing was changed '
    'in Skore.',
  );
  if (value is! String) throw invalid;
  final text = value.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) throw invalid;
  try {
    return parseDateArgument('date', text);
  } on ToolError {
    throw invalid;
  }
}

/// The component of [components] (Skore's offer for a new evaluation in
/// [where]) that [asked] names: by its component id when [asked] is a whole
/// number, else by its name, ignoring case.
///
/// Throws a [ToolError] that lists what Skore offers, and the default, for
/// one it does not offer; nothing is sent.
SkoreEvaluationComponent _component(
  List<SkoreEvaluationComponent> components,
  String asked,
  String where,
) {
  final id = int.tryParse(asked);
  final name = skoreName(asked).toLowerCase();
  for (final component in components) {
    if (id != null
        ? component.id == id
        : skoreName(component.name).toLowerCase() == name) {
      return component;
    }
  }
  if (components.isEmpty) {
    throw ToolError(
      'Skore offers no components for a new evaluation in $where, so none '
      'can be asked for.',
    );
  }
  final byDefault = skoreDefaultComponent(components);
  final orDefault = byDefault == null
      ? ''
      : ', or leave out component for ${skoreName(byDefault.name)} (the '
            'default)';
  throw ToolError(
    'Skore offers no component "$asked" for a new evaluation in $where. It '
    'offers ${formatSkoreComponents(components)}. Pass one of these as '
    'component, by its name or component id$orDefault.',
  );
}
