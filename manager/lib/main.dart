import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'core/locate.dart';
import 'core/manager.dart';
import 'core/update.dart';
import 'pages/about.dart';
import 'pages/backups.dart';
import 'pages/cars.dart';
import 'pages/groups.dart';
import 'pages/install.dart';
import 'pages/ui.dart';
import 'theme/theme.dart';

const fusionFixUrl = 'https://fusionfix.io/iv';

void main() => runApp(const Application());

class Application extends StatelessWidget {
  const Application({this.root, super.key});

  /// A game folder to open instead of the saved one (tests).
  final String? root;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    supportedLocales: FLocalizations.supportedLocales,
    localizationsDelegates: const [...FLocalizations.localizationsDelegates],
    // always dark, like the pause menu, whatever Windows is set to
    theme: darkTheme.toApproximateMaterialTheme(),
    builder: (context, child) => FTheme(
      data: darkTheme,
      child: FToaster(child: FTooltipGroup(child: child!)),
    ),
    home: Home(root: root),
  );
}

/// Remembers the game folder between runs (%APPDATA%\AddonCarManager\settings.json).
class Settings {
  static File get _file => File('${Platform.environment['APPDATA']}\\AddonCarManager\\settings.json');

  static Map<String, dynamic> _read() {
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } on Object {
      return {};
    }
  }

  static void _set(String key, Object value) {
    final all = _read()..[key] = value;
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(jsonEncode(all));
  }

  static String load() => _read()['gameRoot'] as String? ?? '';
  static void save(String root) => _set('gameRoot', root);

  /// Whether to ask GitHub for a newer release at startup; null until the user has been asked.
  static bool? get updatesOnStartup => _read()['updatesOnStartup'] as bool?;
  static set updatesOnStartup(bool? on) => _set('updatesOnStartup', on ?? false);
}

class Home extends StatefulWidget {
  const Home({this.root, this.locate = findGameFolders, super.key});

  final String? root;
  final List<String> Function() locate;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late String _root = widget.root ?? Settings.load();
  int _version = 0; // bumped after every change so all tabs re-read the files
  int _tab = 0;
  final _scroll = ScrollController(); // the open tab's list, so the wheel also works over the side margins

  AddonCarManager get _manager => AddonCarManager(_root);

  void _changed() => setState(() => _version++);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  /// One question at a time: the game folder first, and only with a game open the one about updates.
  Future<void> _startup() async {
    if (_root.isEmpty) await _offerFound();
    // a folder handed in (tests) stays offline and leaves the saved settings alone
    if (!mounted || widget.root != null || _root.isEmpty || !_manager.looksLikeGame) return;
    Settings.updatesOnStartup ??= await confirm(
      context,
      'Check for updates on startup?',
      'You can change this on the About tab.',
      ok: 'Yes',
      cancel: 'No',
    );
    if (Settings.updatesOnStartup != true) return;
    try {
      final latest = await latestRelease();
      if (latest == null || !isNewer(latest.$1, appVersion) || !mounted) return;
      showFToast(
        context: context,
        title: Text('Version ${latest.$1} is out'),
        description: const Text('Get it from the About tab.'),
        duration: const Duration(seconds: 10),
      );
    } on Object {
      // offline or GitHub down: the About tab's button says so when asked
    }
  }

  /// No folder saved yet: offers the installs found on this PC instead of taking one unasked.
  Future<void> _offerFound() async {
    final found = widget.locate();
    if (found.isEmpty || !mounted) return;
    var picked = found.first;
    final dir = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                Text('GTA IV found', style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
                // rows, not buttons (a long path has to wrap): click to select, then confirm below
                for (final dir in found)
                  FTappable(
                    onPress: () => setState(() => picked = dir),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.theme.colors.card,
                        border: Border(left: BorderSide(width: 3, color: dir == picked ? gtaOrange : const Color(0x00000000))),
                      ),
                      child: Text(
                        dir,
                        style: context.titleStyle.copyWith(color: dir == picked ? gtaOrange : context.theme.colors.mutedForeground),
                      ),
                    ),
                  ),
                Wrap(
                  alignment: .end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FButton(
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => Navigator.of(context).pop(''),
                      child: const Text('Browse…'),
                    ),
                    FButton(
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => Navigator.of(context).pop(),
                      child: const Text('Not now'),
                    ),
                    FButton(
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => Navigator.of(context).pop(picked),
                      child: const Text('Use this folder'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (dir == null) return;
    dir.isEmpty ? await _pickFolder() : _use(dir);
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Use this folder', initialDirectory: _root.isEmpty ? null : _root);
    if (dir != null) _use(dir);
  }

  void _use(String dir) {
    Settings.save(dir);
    setState(() {
      _root = dir;
      _version++;
    });
  }

  /// A red notice with the one button that fixes it.
  Widget _notice(String title, String? label, VoidCallback onPress) => FAlert(
    variant: .destructive,
    title: Text(title),
    subtitle: label == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FButton(variant: .outline, size: .sm, mainAxisSize: .min, onPress: onPress, child: Text(label)),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final m = _manager;
    final valid = _root.isNotEmpty && m.looksLikeGame;
    const tabs = ['Cars', 'Install', 'Traffic', 'Backups', 'About'];
    final version = valid ? m.gameVersion : null;
    return FScaffold(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // a list under the pointer claims the event first; anywhere else scrolls the tab's list
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          GestureBinding.instance.pointerSignalResolver.register(e, (_) {
            if (_scroll.positions.length == 1) _scroll.position.pointerScroll(e.scrollDelta.dy);
          });
        },
        child: PageWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 14,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        spacing: 2,
                        children: [
                          AppTitle(style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            (_root.isEmpty ? 'No game folder selected' : _root).toUpperCase(),
                            style: context.smallMuted,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    FButton(
                      variant: .outline,
                      size: .sm,
                      mainAxisSize: .min,
                      prefix: const Icon(FLucideIcons.folderOpen),
                      onPress: _pickFolder,
                      child: const Text('Change folder'),
                    ),
                    ActionIcon(FLucideIcons.refreshCw, 'Re-read the game files', _changed),
                  ],
                ),
                if (!valid)
                  const FAlert(
                    variant: .destructive,
                    title: Text('Pick your GTA IV folder'),
                    subtitle: Text('The folder that contains GTAIV.exe.'),
                  )
                else if (version != AddonCarManager.supportedVersion)
                  FAlert(
                    variant: .destructive,
                    title: Text('This game is ${version ?? 'an unknown version'}'),
                    subtitle: const Text('Add-on cars need Complete Edition ${AddonCarManager.supportedVersion}.'),
                  )
                else if (!m.fusionFixInstalled)
                  _notice('FusionFix is not installed', 'Get FusionFix', () => Process.run('explorer', [fusionFixUrl]))
                else if (!m.pluginInstalled)
                  _notice(
                    '${Paths.plugin} is not installed',
                    AddonCarManager.bundledPlugin.existsSync() ? 'Install' : null, // null: built without the plugin beside it
                    () => runAction(context, 'Plugin installed', m.installPlugin, _changed),
                  ),
                // Own tab row: FTabs lays its content out with unbounded height, which the scrolling pages cannot take
                if (valid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Segmented<int>(
                      values: const [0, 1, 2, 3, 4],
                      label: (i) => tabs[i],
                      selected: _tab,
                      onSelect: (i) => setState(() => _tab = i),
                    ),
                  ),
                if (valid)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: PrimaryScrollController(
                        controller: _scroll,
                        child: KeyedSubtree(
                          // not keyed by _version: a change re-reads the files but keeps the selection, episode and open archive
                          key: ValueKey('$_root $_tab'),
                          child: switch (_tab) {
                            0 => CarsPage(manager: m, onChanged: _changed),
                            1 => InstallPage(manager: m, onChanged: _changed),
                            2 => GroupsPage(manager: m, onChanged: _changed),
                            3 => BackupsPage(manager: m, onChanged: _changed),
                            _ => const AboutPage(),
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs a change, then reports it (or the error) as a toast.
void runAction(BuildContext context, String done, void Function() action, VoidCallback onChanged) {
  try {
    action();
    showFToast(context: context, title: Text(done));
  } on Object catch (e) {
    showFToast(
      context: context,
      variant: .destructive,
      title: const Text('That step failed'),
      description: Text('$e\nIf it got as far as changing files, its backup is in the Backups tab.'),
    );
  }
  onChanged();
}

/// A yes/no question in a forui dialog.
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String ok = 'Continue',
  String cancel = 'Cancel',
  bool destructive = false,
}) async =>
    await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Text(title, style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
              Text(body),
              Row(
                mainAxisAlignment: .end,
                spacing: 8,
                children: [
                  FButton(
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(cancel),
                  ),
                  FButton(
                    variant: destructive ? .destructive : .primary,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(ok),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
