/// What the release notes and the update check share. This file imports
/// nothing, so that `tool/release_notes.dart` compiles in seconds: through
/// `update_check.dart` it would compile all of `flutter_smartschool` for
/// this one heading.
library;

/// The heading of the section of a release's notes that says what is new
/// in it, for the user. `tool/release_notes.dart` puts it at the top of the
/// notes, with that version's section of `CHANGELOG.md` under it; the update
/// check reads that section back (`UpdateChecker.notesSection`).
const notesHeading = '## Nieuw in deze versie';
