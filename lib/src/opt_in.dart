import 'settings.dart';
import 'tools/server_tool.dart';

/// A group of tools that only accounts with certain rights in Smartschool
/// can use, behind an opt-in switch ([setting], a [Setting.isSwitch]): the
/// Skore tools behind "Skore-beheer" (`skoreOptIn` in
/// `skore/skore_opt_in.dart`), and the presence tools behind
/// "Aanwezigheden" (`presenceOptIn` in `presence/presence_opt_in.dart`).
///
/// The server offers [tools] only when the switch is on ([offered]), so an
/// account without the rights never sees tools it cannot use, and they take
/// up no room in the conversations of those who do not want them. The
/// switch is read once, when the server starts ([Switches.read]): changing
/// it takes a restart, as for any setting.
///
/// `smartschool_status` says whether the switch is on, and when it is,
/// checks with [checkAccess] whether the account has the rights.
final class OptInTools {
  const OptInTools({
    required this.setting,
    required this.state,
    required this.rights,
    required this.tools,
    required this.checkAccess,
  });

  /// The switch.
  final Setting setting;

  /// What the switch was set to when the server started.
  final SwitchState state;

  /// The rights the account needs, in a few words for the status, such as
  /// `the rights for score management in Skore (Rapporten > Modellen,
  /// Puntenboeken)`.
  final String rights;

  /// The tools of the group, in the order they are listed.
  final List<ServerTool> tools;

  /// Checks with one cheap read whether the account has the [rights].
  ///
  /// Throws a `SmartschoolProblem` when it cannot log in or reach
  /// Smartschool, as `SmartschoolSession.run` does.
  final Future<AccessCheck> Function() checkAccess;

  /// The tools the server offers: [tools] when the switch is on, else none.
  List<ServerTool> get offered => state.isOn ? tools : const [];
}

/// What [OptInTools.checkAccess] found.
final class AccessCheck {
  /// The account has the rights; [detail] says what the check saw.
  const AccessCheck.granted(this.detail) : granted = true;

  /// The account lacks the rights, or the answer looks like it; [detail]
  /// says why, and what to do.
  const AccessCheck.denied(this.detail) : granted = false;

  final bool granted;
  final String detail;
}
