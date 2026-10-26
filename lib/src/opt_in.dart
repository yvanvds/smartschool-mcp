import 'settings.dart';
import 'tools/server_tool.dart';

/// A group of tools behind an opt-in switch ([setting], a
/// [Setting.isSwitch]), for one of two reasons:
///
/// - **extra rights**: only accounts with certain rights in Smartschool can
///   use the tools: the Skore tools behind "Skore-beheer" (`skoreOptIn` in
///   `skore/skore_opt_in.dart`), and the presence tools behind
///   "Aanwezigheden" (`presenceOptIn` in `presence/presence_opt_in.dart`);
/// - **sensitive data**: most accounts can use them, but they read data
///   sensitive enough that the user (and their school) must choose to let
///   an AI assistant read it: the tools of the pupil tracking system behind
///   "Leerlingvolgsysteem" (`lvsOptIn` in `lvs/lvs_opt_in.dart`), which
///   says so in its [caution].
///
/// The server offers [tools] only when the switch is on ([offered]), so an
/// account without the rights never sees tools it cannot use, no one gets
/// tools that read sensitive data without choosing them, and they take up
/// no room in the conversations of those who do not want them. The switch
/// is read once, when the server starts ([Switches.read]): changing it
/// takes a restart, as for any setting.
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
    this.caution,
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

  /// Checks with a cheap read (for Skore, one per part of Skore) whether the
  /// account has the [rights].
  ///
  /// Throws a `SmartschoolProblem` when it cannot log in or reach
  /// Smartschool, as `SmartschoolSession.run` does, and a [ToolError] when
  /// the answer cannot tell whether the account has the rights; the status
  /// then says that access could not be checked, with its message.
  final Future<AccessCheck> Function() checkAccess;

  /// For a switch that guards sensitive data: a sentence (or two) on what
  /// turning it on means, which the status adds after how to turn it on,
  /// so that it is not turned on as if it only took rights. Null for a
  /// switch for extra rights.
  final String? caution;

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
