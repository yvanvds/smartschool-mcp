import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
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
/// file. The tools that read the parts of the file (#154 to #157) come
/// after these.
OptInTools lvsOptIn(SmartschoolSession session, SwitchState state) =>
    OptInTools(
      setting: Setting.lvs,
      state: state,
      rights: lvsRights,
      caution: lvsCaution,
      tools: [searchLvsPupilsTool(session), readLvsPupilTool(session)],
      checkAccess: () => checkLvsAccess(session),
    );
