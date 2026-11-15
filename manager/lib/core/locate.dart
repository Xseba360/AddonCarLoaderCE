import 'dart:io';

String? _registry(String key, String value) {
  try {
    final r = Process.runSync('reg', ['query', key, '/v', value]);
    if (r.exitCode != 0) return null;
    return RegExp(r'REG_\w+\s+(.+)').firstMatch('${r.stdout}')?.group(1)?.trim();
  } on ProcessException {
    return null;
  }
}

/// Folders holding GTAIV.exe, found the way installers look for the game: the Rockstar and
/// Rockstar Games Launcher registry keys, Steam's uninstall key (app 12210) and every Steam library.
/// The Steam release keeps the exe in a GTAIV subfolder of the folder those name.
List<String> findGameFolders({String? Function(String key, String value) registry = _registry}) {
  const uninstall = r'Microsoft\Windows\CurrentVersion\Uninstall';
  final found = <String?>[
    registry(r'HKLM\SOFTWARE\WOW6432Node\Rockstar Games\Grand Theft Auto IV', 'InstallFolder'),
    registry('HKLM\\SOFTWARE\\WOW6432Node\\$uninstall\\GTA IV', 'InstallLocation'),
    registry('HKLM\\SOFTWARE\\$uninstall\\Steam App 12210', 'InstallLocation'),
    registry('HKLM\\SOFTWARE\\WOW6432Node\\$uninstall\\Steam App 12210', 'InstallLocation'),
  ];
  // the uninstall key goes stale when the game is moved; libraryfolders.vdf lists every library
  final steam = registry(r'HKCU\Software\Valve\Steam', 'SteamPath');
  final libraries = File('$steam\\steamapps\\libraryfolders.vdf');
  if (steam != null && libraries.existsSync()) {
    for (final m in RegExp(r'"path"\s+"([^"]+)"').allMatches(libraries.readAsStringSync())) {
      found.add('${m.group(1)!.replaceAll(r'\\', r'\')}\\steamapps\\common\\Grand Theft Auto IV');
    }
  }
  final out = <String>[];
  for (final dir in found.nonNulls) {
    final d = dir.replaceAll('/', r'\').replaceFirst(RegExp(r'\\+$'), '');
    for (final c in [d, '$d\\GTAIV']) {
      if (File('$c\\GTAIV.exe').existsSync() && !out.any((o) => o.toLowerCase() == c.toLowerCase())) out.add(c);
    }
  }
  return out;
}
