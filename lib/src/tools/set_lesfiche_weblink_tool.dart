import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../planner/lesfiche_detail.dart';
import '../planner/lesfiche_writes.dart';
import '../planner/lesfiches.dart';
import '../session.dart';
import 'server_tool.dart';

/// `set_lesfiche_weblink`: adds a weblink to a lesfiche in the user's own
/// library of the Lesfiches module, or, with `weblink_id`, changes one of
/// its weblinks (the library's `LessonContentService.addWeblink` and
/// `changeWeblink`, dartschool#129), and gives the lesfiche back as
/// `read_lesfiche` shows it.
///
/// Marked destructive, as `create_lesfiche` is (its doc comment says why),
/// and not idempotent: a second add adds a second weblink. The library sends
/// an add once, never again after logging in again; when Smartschool refused
/// the session for it, the session repeats the action, and the library logs
/// in again before the repeat's first request (yvanvds/dartschool#134). The
/// tool reads the lesfiche first in the session action of the write: the
/// library takes it as read, and the tool finds the weblink to change in it.
/// A change sends every value of the weblink: the icon and the visibility
/// not given stay as they were.
ServerTool setLesficheWeblinkTool(SmartschoolSession session) => ServerTool(
  definition: Tool(
    name: 'set_lesfiche_weblink',
    title: 'Add or change a weblink of a Smartschool lesfiche',
    description:
        'Adds a weblink to one lesfiche in the user\'s own library ("Mijn '
        'lesfiches") of the Smartschool Lesfiches module, by the id and kind '
        'list_lesfiches shows; or, with weblink_id (as read_lesfiche shows '
        'it at the end of the weblink\'s line), changes that weblink: its '
        'name, its address, and optionally its icon and when pupils see it. '
        'A change keeps the icon and the visibility that are not given. '
        'When pupils see a weblink counts from the lesson the lesfiche is '
        'planned in: $lesficheVisibilityValues. Before calling this tool, '
        'show the user the lesfiche (name and kind) and the weblink as it '
        'will be (name, address, when pupils see it), and only call this '
        'tool after the user has explicitly confirmed it; then call it once '
        'per weblink. Whether a lesson planned from the lesfiche earlier '
        'changes with it is not known. A lesfiche in the trash cannot be '
        'changed. The result gives the lesfiche as changed, with the id of '
        'the weblink. If the result says the weblink may or may not have '
        'been added or changed, do not call this tool again for it (a '
        'second add adds a second weblink): check the lesfiche with '
        'read_lesfiche and tell the user. For requests like "zet de link '
        'naar de oefeningen in mijn lesfiche Lussen".',
    inputSchema: Schema.object(
      properties: {
        'lesfiche': Schema.string(
          description:
              'The id of the lesfiche, as list_lesfiches shows it, like '
              'b0000000-0000-4000-8000-000000000001.',
          minLength: 1,
        ),
        'type': lesficheTypeSchema(),
        'weblink_id': Schema.string(
          description:
              'Only to change a weblink: its id, as read_lesfiche shows it '
              'at the end of the weblink\'s line. Leave it out to add a new '
              'weblink.',
          minLength: 1,
        ),
        'name': Schema.string(
          description: 'The name the weblink shows, as the user confirmed it.',
          minLength: 1,
        ),
        'url': Schema.string(
          description:
              'The address it opens, like https://example.com/oefeningen. '
              'One without http:// or https:// in front gets http://, as '
              'the web client sends it.',
          minLength: 1,
        ),
        'icon': Schema.string(
          description:
              'The icon of the weblink, a name from Smartschool\'s icon set '
              'as read_lesfiche shows it. Default: '
              '${LessonContentService.defaultWeblinkIcon} for a new weblink, '
              'the icon it has for a change. Leave it out unless the user '
              'asks for an icon.',
          minLength: 1,
        ),
        'visibility': lesficheVisibilitySchema(
          description:
              'When pupils see the weblink (default: always for a new '
              'weblink, the visibility it has for a change)',
        ),
      },
      required: ['lesfiche', 'name', 'url'],
    ),
    annotations: ToolAnnotations(
      title: 'Add or change a weblink of a Smartschool lesfiche',
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) => _set(session, request.arguments ?? const {}),
);

Future<CallToolResult> _set(
  SmartschoolSession session,
  Map<String, Object?> arguments,
) async {
  final id = lesficheArgument(arguments['lesfiche']);
  final type = lesficheTypeArgument(arguments['type']);
  final weblinkId = arguments['weblink_id'] == null
      ? null
      : lesfichePartIdArgument(
          arguments['weblink_id'],
          name: 'weblink_id',
          what: 'weblink',
        );
  // The name, the address and the visibility, checked as create_lesfiche
  // checks a weblink.
  final link = lesficheWeblinkArgument({
    'name': arguments['name'],
    'url': arguments['url'],
    'visibility': arguments['visibility'],
  }, where: 'the weblink');
  final icon = switch (arguments['icon']) {
    final String icon when icon.trim().isNotEmpty => icon.trim(),
    _ => null,
  };
  final visibilityGiven = switch (arguments['visibility']) {
    final String text => text.trim().isNotEmpty,
    _ => false,
  };

  LessonContentDetail? lesfiche;
  LessonContentWeblink? old;
  String title() => lesfiche == null
      ? 'the ${lesficheKindName(type)} $id'
      : lesficheTitle(lesfiche!);
  String oldName() => old == null ? '' : ' "${old!.name}"';

  final LessonContentWeblink weblink;
  try {
    weblink = await withLesficheWrite(
      session,
      (client) async {
        final read = lesfiche = (await readLesficheDetail(
          client,
          type,
          id,
          withCourseNames: false,
        )).detail;
        final lesfiches = LessonContentService(client);
        if (weblinkId == null) {
          return lesfiches.addWeblink(
            read,
            NewLessonContentWeblink(
              name: link.name,
              url: link.url,
              icon: icon ?? LessonContentService.defaultWeblinkIcon,
              visibility: link.visibility,
            ),
          );
        }
        final current = old = lesficheWeblinkById(read, weblinkId);
        return lesfiches.changeWeblink(
          read,
          current.id,
          NewLessonContentWeblink(
            name: link.name,
            url: link.url,
            icon:
                icon ??
                (current.icon.trim().isEmpty
                    ? LessonContentService.defaultWeblinkIcon
                    : current.icon),
            visibility: visibilityGiven ? link.visibility : current.visibility,
          ),
        );
      },
      what: () => weblinkId == null
          ? 'the weblink "${link.name}" for ${title()}'
          : 'the change of the weblink${oldName()} of ${title()}',
      nothingDone: lesficheUnchanged,
      orGone: weblinkId == null ? null : 'the weblink was removed meanwhile',
    );
  } on SmartschoolLessonContentSaveUnconfirmedError catch (error) {
    final readIt = 'read the lesfiche with ${readLesficheCall(type, id)}';
    if (weblinkId == null) {
      return lesficheWriteNotConfirmed(
        tool: 'set_lesfiche_weblink',
        what: 'The weblink "${link.name}"',
        done: 'added to ${title()}',
        why: 'a second call without weblink_id adds a second weblink',
        check: '$readIt to see whether it is there',
        error: error,
      );
    }
    return lesficheWriteNotConfirmed(
      tool: 'set_lesfiche_weblink',
      what: 'The change of the weblink${oldName()} of ${title()}',
      done: 'saved',
      check: '$readIt and compare the weblink',
      error: error,
    );
  }
  log('set_lesfiche_weblink: ${weblinkId == null ? 'added' : 'changed'}');
  return lesficheChangedResult(session, type, id, [
    if (weblinkId == null)
      'Added the weblink "${weblink.name}" to ${title()}, with id '
          '${weblink.id}.'
    else
      'Changed the weblink${oldName()} of ${title()} (id ${weblink.id}).',
  ]);
}
