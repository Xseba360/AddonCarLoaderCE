import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/update.dart';
import '../main.dart';
import 'ui.dart';

const appVersion = '0.2.0'; // keep in step with pubspec.yaml
const repoUrl = 'https://github.com/Xseba360/AddonCarLoaderCE';

/// What ships with the program, under which license, and where its text is: a bundled asset
/// ("fonts/...") or a file shipped next to the exe. The Dart packages come from Flutter's registry.
const shipped = [
  ('Add-on Car Manager CE', 'GNU GPL v3', 'LICENSE'),
  ('fastman92 limit adjuster', 'MIT', 'licenses/fastman92-limit-adjuster.txt'),
  ('7-Zip', 'LGPL 2.1, unRAR restriction', '7zip/License.txt'),
  ('Switzer', 'ITF Free Font License', 'fonts/Switzer-LICENSE.txt'),
  ('Alte DIN 1451 Mittelschrift', 'SIL Open Font License', 'fonts/din1451alt-OFL.txt'),
];

/// The license text at [source]; the files sit next to the exe, or in the project when run from tests.
Future<String> licenseText(String source) async {
  if (source.startsWith('fonts/')) return rootBundle.loadString(source);
  final exe = File(Platform.resolvedExecutable).parent.path, project = Directory.current.path;
  for (final path in ['$exe\\$source', '$project\\..\\$source', '$project\\windows\\$source']) {
    if (File(path).existsSync()) return latin1.decode(File(path).readAsBytesSync());
  }
  return 'The license file is missing: $source';
}

/// Every license in one place: the list on the left, the picked one's text on the right.
class AboutPage extends StatefulWidget {
  const AboutPage({this.latest = latestRelease, super.key});

  /// Asks GitHub for the newest release (replaced in tests).
  final Future<(String, String)?> Function() latest;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// (name, license, text)
  final _entries = <(String, String, Future<String>)>[for (final (name, license, source) in shipped) (name, license, licenseText(source))];
  int _selected = 0;

  // update check: only when asked
  bool _checking = false;
  String? _status;
  (String, String)? _newer; // (version, release page)

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = 'CHECKING';
    });
    String status;
    (String, String)? newer;
    try {
      final latest = await widget.latest();
      if (latest == null) {
        status = 'NO RELEASES YET';
      } else if (isNewer(latest.$1, appVersion)) {
        (status, newer) = ('${latest.$1} IS OUT', latest);
      } else {
        status = 'UP TO DATE';
      }
    } on Object {
      status = 'COULD NOT REACH GITHUB';
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = status;
      _newer = newer;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  /// Flutter and the Dart packages, from the notices Flutter bundles with the app.
  Future<void> _loadPackages() async {
    final texts = <String, List<String>>{};
    try {
      await for (final entry in LicenseRegistry.licenses) {
        final text = entry.paragraphs.map((p) => p.text).join('\n\n');
        for (final package in entry.packages) {
          (texts[package] ??= []).add(text);
        }
      }
    } on Object {
      return; // no bundled notices (tests): the shipped ones are still listed
    }
    if (!mounted) return;
    final names = texts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() => _entries.addAll([for (final n in names) (n, 'Package', Future.value(texts[n]!.join('\n\n${'-' * 40}\n\n')))]));
  }

  Widget _row(BuildContext context, int i) {
    final c = context.theme.colors;
    final (name, license, _) = _entries[i];
    final selected = i == _selected;
    return FTappable(
      onPress: () => setState(() => _selected = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.card : null,
          border: Border(left: BorderSide(width: 3, color: selected ? gtaOrange : const Color(0x00000000))),
        ),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: context.titleStyle.copyWith(color: selected ? gtaOrange : c.mutedForeground),
            ),
            Text(license.toUpperCase(), overflow: TextOverflow.ellipsis, style: context.smallMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (name, license, text) = _entries[_selected];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        // wraps in a narrow window: the controls drop below the version line
        Wrap(
          alignment: .spaceBetween,
          crossAxisAlignment: .center,
          spacing: 12,
          runSpacing: 8,
          children: [
            // the program's name is already in the window's header
            Text(
              'VERSION $appVersion${_status == null ? '' : '  ·  $_status'}  ·  NOT AFFILIATED WITH ROCKSTAR GAMES',
              style: context.smallMuted,
            ),
            Wrap(
              crossAxisAlignment: .center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // own label: in a row the checkbox gives its label no width
                Row(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    FCheckbox(value: Settings.updatesOnStartup ?? false, onChange: (on) => setState(() => Settings.updatesOnStartup = on)),
                    Text('ON STARTUP', style: context.smallMuted),
                  ],
                ),
                if (_newer == null)
                  FButton(
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    prefix: const Icon(FLucideIcons.refreshCw),
                    onPress: _checking ? null : _check,
                    child: const Text('Check for updates'),
                  )
                else
                  FButton(
                    size: .sm,
                    mainAxisSize: .min,
                    prefix: const Icon(FLucideIcons.download),
                    onPress: () => Process.run('explorer', [_newer!.$2]),
                    child: Text('Get ${_newer!.$1}'),
                  ),
                FButton(
                  variant: .outline,
                  size: .sm,
                  mainAxisSize: .min,
                  prefix: const Icon(FLucideIcons.externalLink),
                  onPress: () => Process.run('explorer', [repoUrl]), // opens the default browser
                  child: const Text('GitHub'),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              SizedBox(
                width: 280,
                child: ListView.builder(primary: true, itemCount: _entries.length, itemBuilder: _row),
              ),
              Expanded(
                child: Container(
                  color: context.theme.colors.card,
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [
                        Text(name, style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
                        Text(license.toUpperCase(), style: context.smallMuted),
                        FutureBuilder(
                          key: ValueKey(_selected),
                          future: text,
                          builder: (context, snapshot) => SelectableText(snapshot.data ?? '', style: context.theme.typography.body.xs),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
