import '../opt_in.dart';
import '../session.dart';
import '../settings.dart';
import '../tools/add_skore_teacher_tool.dart';
import '../tools/list_skore_classes_tool.dart';
import '../tools/list_skore_courses_tool.dart';
import '../tools/list_skore_gradebook_shares_tool.dart';
import '../tools/list_skore_teachers_tool.dart';
import '../tools/replace_skore_teacher_tool.dart';
import '../tools/share_skore_gradebook_tool.dart';
import '../tools/unshare_skore_gradebook_tool.dart';
import 'skore_access.dart';

/// The Skore tools, behind the switch "Skore-beheer" ([Setting.skore]),
/// which [state] says is on or off: only accounts with [skoreRights] can
/// use them (#42). Most teachers and all pupils lack those rights.
///
/// The reads first, then the writes: assigning teachers (#43) and sharing
/// gradebooks (#44), which change Skore only after the user confirmed.
OptInTools skoreOptIn(SmartschoolSession session, SwitchState state) =>
    OptInTools(
      setting: Setting.skore,
      state: state,
      rights: skoreRights,
      tools: [
        listSkoreClassesTool(session),
        listSkoreCoursesTool(session),
        listSkoreTeachersTool(session),
        listSkoreGradebookSharesTool(session),
        addSkoreTeacherTool(session),
        replaceSkoreTeacherTool(session),
        shareSkoreGradebookTool(session),
        unshareSkoreGradebookTool(session),
      ],
      checkAccess: () => checkSkoreAccess(session),
    );
