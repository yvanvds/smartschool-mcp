import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_bulk.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiches.dart';
import '../planner/year_plans.dart';
import '../session.dart';
import 'server_tool.dart';

/// `add_to_lesson_cluster`: adds a title, lesfiches, or a title and then
/// lesfiches, to the end of a lesson cluster of one of the user's year
/// plans (`TeachingAssignmentService.addTitle` and `addLessonContent`,
/// dartschool#229, #191).
///
/// Before anything is sent, in the session action of the first write, it
/// reads the user's year plans (the plan and the cluster must be in them)
/// and, for lesfiches, those the year plan takes (`getLessonContent`): an id
/// that is not one of them is refused there. The title and the lesfiches
/// each go out in a session action of their own, so that a repeat of the
/// session for the lesfiches never sends the title again. Marked
/// destructive for approval, and not idempotent: the module adds a title or
/// a lesfiche again on a second call (the same lesfiche can be in a cluster
/// twice, seen live). The result shows the cluster read back.
///
/// When the module's answer to the lesfiches says, lesfiche by lesfiche,
/// which it added and which not, but not that it added all of them, the
/// library throws a `SmartschoolLessonContentBulkSaveUnconfirmedError`
/// (dartschool#244): the result says from that record which were added,
/// which got an exception (with its status and words) and which the answer
/// names neither way ([lesficheBulkAnswerResult], #224), without reading the
/// cluster. Only an answer that says nothing usable about any lesfiche (no
/// answer, another status) is "may or may not have been added", with
/// `read_year_plan` to check.
ServerTool addToLessonClusterTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'add_to_lesson_cluster',
    title: 'Add titles and lesfiches to a Smartschool lesson cluster',
    description:
        'Adds a title (such as "Week 1"), lesfiches, or a title followed by '
        'lesfiches to the end of a lesson cluster of one of the user\'s '
        'year plans in the Smartschool Lesfiches module, by the ids of '
        'read_year_plan. The lesfiches are the user\'s own, by their ids '
        'from list_lesfiches, added in the order given; the lesfiches '
        'themselves are not changed or copied. Before calling this tool, '
        'show the user the cluster, the title and the lesfiches by name, '
        'and only call this tool after the user has explicitly confirmed '
        'it. A title of more than $maxYearPlanNameLength characters, and a '
        'lesfiche the year plan does not take, are refused, and nothing is '
        'added. Every call adds them again, also when they are in the '
        'cluster already. If the result says the module did not confirm the '
        'add, do not call this tool again for what it says was added, nor '
        'for what it says may or may not have been added before checking '
        'the cluster with read_year_plan; tell the user what was added and '
        'what not. The result shows the cluster as it is now. For '
        'requests like "zet mijn lesfiches over lussen in de cluster '
        'Lussen, onder de titel Week 1".',
    inputSchema: Schema.object(
      properties: {
        'year_plan': yearPlanSchema(),
        'cluster': clusterSchema(),
        'title': Schema.string(
          description:
              'Optional: a title to add first, as the user confirmed it: at '
              'most $maxYearPlanNameLength characters.',
        ),
        'lesfiches': lesficheIdsSchema(
          description:
              'Optional: the ids of the lesfiches to add after the title, as '
              'list_lesfiches shows them, in the order they go in the '
              'cluster: 1 to $maxLesficheBulkItems.',
        ),
      },
      required: ['year_plan', 'cluster'],
    ),
    annotations: ToolAnnotations(
      title: 'Add titles and lesfiches to a Smartschool lesson cluster',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _add(session, request.arguments ?? const {}),
);

Future<CallToolResult> _add(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final planId = yearPlanArgument(arguments['year_plan']);
  final clusterId = clusterArgument(arguments['cluster']);
  final title = switch (arguments['title']) {
    null => null,
    final value => yearPlanNameArgument(
      value,
      name: 'title',
      what: 'the title',
    ),
  };
  final ids = arguments['lesfiches'] == null
      ? const <String>[]
      : lesficheIdsArgument(arguments['lesfiches']);
  if (title == null && ids.isEmpty) {
    throw const ToolError(
      'Pass a title, lesfiches, or both: there is nothing to add. Nothing '
      'was sent.',
    );
  }

  // The reads and the title, in one session action.
  TeachingAssignment? plan;
  LessonCluster? cluster;
  var items = const <LessonContentItem>[];
  String? clusterName;
  try {
    await withYearPlanWrite(
      session,
      (client) async {
        final service = TeachingAssignmentService(client);
        plan = await readYearPlan(client, planId);
        cluster = findCluster(plan!, clusterId);
        clusterName = cluster!.name;
        if (ids.isNotEmpty) {
          items = takenLesfiches(
            plan!,
            await service.getLessonContent(plan!),
            ids,
          );
        }
        if (title != null) await service.addTitle(cluster!, title);
      },
      what: title == null
          ? 'the add of lesfiches to the lesson cluster'
          : 'the add of the title "$title" to the lesson cluster',
      nothingDone: 'Nothing was added.',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    return yearPlanWriteNotConfirmed(
      tool: 'add_to_lesson_cluster',
      what: 'The title "$title" of the lesson cluster "$clusterName"',
      done: 'added',
      why: 'a second call could add it twice',
      also: ids.isEmpty ? null : 'The lesfiches were not sent.',
      check:
          'read the cluster with read_year_plan (year_plan $planId, '
          'cluster $clusterId) to see whether it is there',
      error: error,
    );
  }

  final done = <String>[
    if (title != null)
      'Added the title "$title" to the end of the lesson cluster '
          '"$clusterName".',
  ];
  if (items.isNotEmpty) {
    final titleNote = title == null ? '' : ' The title "$title" was added.';
    try {
      await withYearPlanWrite(
        session,
        (client) =>
            TeachingAssignmentService(client).addLessonContent(cluster!, items),
        what: 'the add of ${lesficheTitles(items)} to the lesson cluster',
        nothingDone: 'The lesfiches were not added.$titleNote',
      );
    } on SmartschoolLessonContentBulkSaveUnconfirmedError catch (error) {
      // The answer says lesfiche by lesfiche what the module did.
      final check =
          'read the cluster with read_year_plan (year_plan $planId, cluster '
          '$clusterId): the module adds to its end';
      return lesficheBulkAnswerResult(
        tool: 'add_to_lesson_cluster',
        sent: items.length == 1
            ? 'The add of ${lesficheTitle(items.single)} to the lesson '
                  'cluster "$clusterName"'
            : 'The add of ${items.length} lesfiches to the lesson cluster '
                  '"$clusterName"',
        error: error,
        line: _lesficheLine,
        doneHeader:
            'Added to the end of the cluster (a lesfiche can be in a cluster '
            'twice, so do not add these again):',
        failedHeader:
            'Not added, with the exception the module gave for each (it '
            'answers HTTP 403 for a lesfiche the year plan does not take):',
        unansweredHeader:
            'Not named in the answer, so they may or may not have been added '
            '(before adding one of these again, $check):',
        extra: [if (title != null) 'The title "$title" was added.'],
        advice:
            'Do not call add_to_lesson_cluster again for those added: a '
            'second call adds them to the cluster twice. Tell the user which '
            'were added and which not, and ask before adding the others '
            'again.',
      );
    } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
      // No answer, or one that says nothing usable about any lesfiche.
      return yearPlanWriteNotConfirmed(
        tool: 'add_to_lesson_cluster',
        what: '${lesficheSubject(items)} in the lesson cluster "$clusterName"',
        done: 'added',
        why:
            'a second call could add ${items.length == 1 ? 'it' : 'them'} '
            'twice',
        also: titleNote.isEmpty ? null : titleNote.trim(),
        check:
            'read the cluster with read_year_plan (year_plan $planId, '
            'cluster $clusterId) to see which are there',
        error: error,
      );
    }
    done.add(
      'Added ${lesficheTitles(items)} to the end of the lesson cluster '
      '"$clusterName".',
    );
  }
  log('add_to_lesson_cluster: added to a cluster');
  final shown = await yearPlanClusterReadBack(session, planId, clusterId);
  return CallToolResult(
    content: [
      TextContent(text: [...done, '', shown].join('\n')),
    ],
  );
}

/// One line for [item], a lesfiche of an add the module did not confirm
/// all of, as `read_year_plan` shows a lesfiche of a cluster: kind, name and
/// id.
String _lesficheLine(LessonContentItem item) => [
  formatLesficheKind(item),
  if (item.name.isEmpty) '(no name)' else item.name,
  'id ${item.id}',
].join(' | ');
