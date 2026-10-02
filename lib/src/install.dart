/// The installer for ChatGPT and Codex: started with a double-click (or
/// `--install`), the server's executable copies itself to a fixed folder and
/// shows, in Dutch, what to fill in in ChatGPT's form for a custom MCP
/// server.
///
/// It never touches Codex's `config.toml` and never asks for a setting: the
/// teacher enters the settings in that form, as environment variables.
library;

import 'dart:io';
import 'dart:math';

import 'client_app.dart';
import 'clipboard.dart';
import 'settings.dart';
import 'version.dart';

/// The name of the installed executable.
const installedName = 'smartschool-mcp.exe';

/// The colleague guide for ChatGPT.
const chatGptGuideUrl =
    'https://github.com/yvanvds/smartschool-mcp/blob/main/docs/'
    'installatie-chatgpt.md';

/// What each setting holds, in Dutch, for the instructions; the colleague
/// guide's table says the same.
const settingHints = {
  Setting.mainUrl: 'het adres van je school, bv. school.smartschool.be',
  Setting.username: 'je gebruikersnaam voor Smartschool',
  Setting.password: 'je wachtwoord voor Smartschool',
  Setting.mfa: 'je 2FA-sleutel, niet de code van zes cijfers',
  Setting.downloadDir: 'niet verplicht: de map voor bewaarde bestanden',
};

/// The folder the installer puts the server in:
/// `%LOCALAPPDATA%\Programs\smartschool-mcp`, where Windows keeps programs
/// installed for one user (no administrator rights needed). Null without
/// `LOCALAPPDATA`.
String? installDirectory(Map<String, String> environment) {
  final local = environment['LOCALAPPDATA']?.trim() ?? '';
  if (local.isEmpty) return null;
  return [local, 'Programs', 'smartschool-mcp'].join(Platform.pathSeparator);
}

/// What [installExecutable] did.
final class Installation {
  const Installation(this.path, {required this.copied, required this.replaced});

  /// The installed executable.
  final String path;

  /// False when the installer already ran from [path]: nothing was copied.
  final bool copied;

  /// Whether an earlier copy was replaced (an update).
  final bool replaced;
}

/// Copies the executable [source] to [installedName] in [directory] and
/// returns where it is.
///
/// An earlier copy is replaced. A copy that ChatGPT is running cannot be
/// deleted or overwritten on Windows, but it can be renamed: it is moved
/// aside first, under a name [replacedCopy] matches, and deleted when it is
/// no longer running ([deleteReplacedCopies], at the next install or server
/// start). The new copy is written under a temporary name and renamed once
/// complete, so a failed copy leaves the old one in place.
///
/// Throws a [FileSystemException] when copying fails.
Future<Installation> installExecutable(String source, String directory) async {
  final target = [directory, installedName].join(Platform.pathSeparator);
  if (await File(target).exists() &&
      await FileSystemEntity.identical(source, target)) {
    return Installation(target, copied: false, replaced: false);
  }
  await Directory(directory).create(recursive: true);
  await deleteReplacedCopies(directory);

  final suffix = _randomHex();
  final fresh = File('$target.$suffix.new');
  try {
    await File(source).copy(fresh.path);
    final replaced = await File(target).exists();
    if (replaced) {
      await File(target).rename('$target.$suffix.old');
    }
    await fresh.rename(target);
    await deleteReplacedCopies(directory);
    return Installation(target, copied: true, replaced: replaced);
  } finally {
    if (await fresh.exists()) {
      try {
        await fresh.delete();
      } on FileSystemException {
        // Left behind in the program's own folder.
      }
    }
  }
}

/// Matches the name of a copy [installExecutable] moved aside.
final replacedCopy = RegExp(
  '^${RegExp.escape(installedName)}\\.[0-9a-f]{16}\\.old\$',
);

/// Deletes the copies an update moved aside in [directory] (see
/// [installExecutable]); a copy that is still running stays until a later
/// call. Never throws.
Future<void> deleteReplacedCopies(String directory) async {
  try {
    await for (final entity in Directory(directory).list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File || !replacedCopy.hasMatch(name)) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // Still running: deleted next time.
      }
    }
  } on FileSystemException {
    // No folder (yet), or it cannot be read: nothing to delete.
  }
}

/// The lines of the instructions that ask for a paid plan and for model
/// training to be off, before the server can read the teacher's messages;
/// the colleague guide asks the same, in more detail.
const privacyWarning = [
  'Belangrijk: ChatGPT stuurt wat het leest naar OpenAI, ook gevoelige',
  'gegevens over leerlingen. Gebruik dit daarom alleen met een betalend',
  'ChatGPT-abonnement, en zet in ChatGPT eerst "Het model verbeteren voor',
  'iedereen" (Improve the model for everyone) uit, bij het gegevensbeheer.',
];

/// What to do after installing, in Dutch: [privacyWarning], how to add the
/// server in ChatGPT with [path] as its command, and the settings to enter.
String installInstructions(
  Installation installation, {
  required bool onClipboard,
}) {
  final path = installation.path;
  final width = Setting.values
      .map((setting) => setting.envVar.length)
      .reduce(max);
  return [
    'Smartschool voor ChatGPT, versie $packageVersion',
    '',
    if (installation.copied)
      'Geïnstalleerd in: $path'
    else
      'Smartschool is al geïnstalleerd in: $path',
    if (onClipboard) 'Dat pad staat ook op je klembord.',
    '',
    ...privacyWarning,
    '',
    if (installation.replaced) ...[
      'Je instellingen in ChatGPT blijven bewaard. Herstart ChatGPT om de',
      'nieuwe versie te gebruiken.',
      '',
      'Staat Smartschool nog niet in ChatGPT? Voeg het dan zo toe:',
    ] else if (!installation.copied)
      'Staat Smartschool nog niet in ChatGPT? Voeg het dan zo toe:'
    else
      'Voeg Smartschool nu zo toe in de ChatGPT-app:',
    '',
    "1. Open Instellingen, kies Plug-ins en het tabblad MCP's.",
    '2. Kies Toevoegen en dan Aangepaste MCP-server maken.',
    '3. Naam: ${ClientApp.codexServerName}. Kies STDIO als dat gevraagd '
        'wordt.',
    '4. Opdracht om op te starten:'
        '${onClipboard ? ' plak het pad (Ctrl+V)' : ''}',
    '   $path',
    '5. Argumenten: geen.',
    '6. Omgevingsvariabelen: vul bij Sleutel precies deze namen in, en bij',
    '   Waarde je eigen gegevens:',
    for (final setting in Setting.values)
      '   ${setting.envVar.padRight(width)}  ${settingHints[setting]}',
    '7. Bewaar, herstart ChatGPT en vraag in een nieuwe chat:',
    '   Werkt mijn Smartschool-verbinding?',
    '',
    'Uitleg met afbeeldingen: $chatGptGuideUrl',
  ].join('\n');
}

/// Runs the installer: installs this executable ([source], by default
/// [Platform.resolvedExecutable]) into [installDirectory] for
/// [environment], puts the installed path on the clipboard (unless not
/// [clipboard]) and writes the instructions to [out]. When [interactive]
/// (a console window opened by a double-click), it waits for Enter before
/// returning, so the window stays open.
///
/// Returns the process exit code: 0 when installed, 1 when not.
Future<int> runInstaller({
  required IOSink out,
  required bool interactive,
  bool clipboard = true,
  Map<String, String>? environment,
  String? source,
}) async {
  final code = await _install(
    out,
    clipboard: clipboard,
    environment: environment ?? Platform.environment,
    source: source ?? Platform.resolvedExecutable,
  );
  if (interactive) {
    out
      ..writeln()
      ..writeln('Druk op Enter om dit venster te sluiten.');
    await out.flush();
    stdin.readLineSync();
  }
  return code;
}

Future<int> _install(
  IOSink out, {
  required bool clipboard,
  required Map<String, String> environment,
  required String source,
}) async {
  if (!Platform.isWindows) {
    out.writeln('Installeren voor ChatGPT kan alleen op Windows.');
    return 1;
  }
  final name = source.split(Platform.pathSeparator).last.toLowerCase();
  if (name == 'dart.exe') {
    out.writeln(
      'Installeren kan alleen vanuit het gecompileerde $installedName, niet '
      'met dart run. (To serve MCP from a terminal, pipe its input.)',
    );
    return 1;
  }
  final directory = installDirectory(environment);
  if (directory == null) {
    out.writeln(
      'Installeren lukte niet: Windows geeft de map voor programma\'s niet '
      'door (LOCALAPPDATA ontbreekt).',
    );
    return 1;
  }
  final Installation installation;
  try {
    installation = await installExecutable(source, directory);
  } on FileSystemException catch (error) {
    out.writeln(
      'Installeren lukte niet: $installedName kon niet naar $directory '
      'gekopieerd worden (${error.osError?.message ?? error.message}).',
    );
    return 1;
  }
  final onClipboard = clipboard && copyToClipboard(installation.path);
  out.writeln(installInstructions(installation, onClipboard: onClipboard));
  return 0;
}

/// 16 random hex digits, for the names of a new and a replaced copy.
String _randomHex() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 8; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
