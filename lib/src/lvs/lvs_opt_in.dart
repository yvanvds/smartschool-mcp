import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/read_lvs_notes_tool.dart';
import '../tools/read_lvs_pupil_tool.dart';
import '../tools/search_lvs_pupils_tool.dart';
import 'lvs_access.dart';

/// The tools of Smartschool's pupil tracking system (LVS,
/// "leerlingvolgsysteem"), behind the switch "Leerlingvolgsysteem"
/// ([Setting.lvs]), which [state] says is on or off (#153).
///
/// Not a switch for extra rights: most teachers can read the LVS. It holds
/// the most sensitive data about pupils, so the user (and their school)
/// must choose to let an AI assistant read it ([lvsCaution]). The tools
/// only read, one pupil at a time, and keep nothing on disk or in the log
/// (`lvs_access.dart`): finding a pupil first, then the overview of their
/// file, then the parts of it: the notes (#154). The tools that read the
/// other parts (#155 to #157) come after these. [now] gives today, for the
/// default school year.
OptInTools lvsOptIn(
  SmartschoolSession session,
  SwitchState state, {
  DateTime Function() now = DateTime.now,
}) => OptInTools(
  setting: Setting.lvs,
  state: state,
  rights: lvsRights,
  caution: lvsCaution,
  tools: [
    searchLvsPupilsTool(session),
    readLvsPupilTool(session),
    readLvsNotesTool(session, now: now),
  ],
  checkAccess: () => checkLvsAccess(session),
);
