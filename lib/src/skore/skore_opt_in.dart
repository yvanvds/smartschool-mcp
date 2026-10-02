import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/list_skore_classes_tool.dart';
import '../tools/list_skore_courses_tool.dart';
import '../tools/list_skore_teachers_tool.dart';
import 'skore_access.dart';

/// The Skore tools, behind the switch "Skore-beheer" ([Setting.skore]),
/// which [state] says is on or off: only accounts with [skoreRights] can
/// use them (#42). Most teachers and all pupils lack those rights.
OptInTools skoreOptIn(SmartschoolSession session, SwitchState state) =>
    OptInTools(
      setting: Setting.skore,
      state: state,
      rights: skoreRights,
      tools: [
        listSkoreClassesTool(session),
        listSkoreCoursesTool(session),
        listSkoreTeachersTool(session),
      ],
      checkAccess: () => checkSkoreAccess(session),
    );
