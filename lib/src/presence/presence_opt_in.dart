import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/list_class_presences_tool.dart';
import '../tools/list_presence_classes_tool.dart';
import '../tools/set_pupils_late_tool.dart';
import '../tools/set_pupils_present_tool.dart';
import 'presence_access.dart';

/// The presence tools, behind the switch "Aanwezigheden"
/// ([Setting.presence]), which [state] says is on or off: only accounts
/// with [presenceRights] can use them (#47), such as the absence
/// administrators of a school. Most staff and all pupils lack those rights.
///
/// The reads first, then the writes, which change the half-day presences of
/// pupils only after the user confirmed. [now] gives today, for the default
/// day of a read and to refuse a day in the future for a write.
OptInTools presenceOptIn(
  SmartschoolSession session,
  SwitchState state, {
  DateTime Function() now = DateTime.now,
}) => OptInTools(
  setting: Setting.presence,
  state: state,
  rights: presenceRights,
  tools: [
    listPresenceClassesTool(session),
    listClassPresencesTool(session, now: now),
    setPupilsLateTool(session, now: now),
    setPupilsPresentTool(session, now: now),
  ],
  checkAccess: () => checkPresenceAccess(session),
);
