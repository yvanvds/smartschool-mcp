import 'dart:io';

import 'package:flutter_smartschool/flutter_smartschool.dart';

/// The folder that holds the library's per-user cache folders:
/// `~/.cache/smartschool`, on Windows `%USERPROFILE%\.cache\smartschool`
/// (`%HOME%` instead when `HOME` is set).
///
/// The library keeps each user's data, such as the session cookies, in a
/// folder of its own in it ([SmartschoolClient.defaultCacheDir]), and the
/// server its data for a user in that user's folder
/// (`SmartschoolSession.cacheDirectory`). The server keeps data that belongs
/// to no Smartschool user here, such as the update check's state; it needs
/// no settings.
///
/// The library names only the folder of a user, so this is the parent of
/// the default one: worked out by the library, it follows the library if
/// that default ever changes.
String sharedCacheDirectory() =>
    Directory(SmartschoolClient.defaultCacheDir(_anyUsername)).parent.path;

/// A username for [SmartschoolClient.defaultCacheDir]; any name gives the
/// same parent folder.
const _anyUsername = 'user';
