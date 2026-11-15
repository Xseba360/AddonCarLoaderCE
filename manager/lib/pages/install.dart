import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/manager.dart';
import '../core/mod_package.dart';
import '../core/readme.dart';
import '../main.dart';
import 'cars.dart';
import 'ui.dart';

class InstallPage extends StatefulWidget {
  const InstallPage({required this.manager, required this.onChanged, super.key});

  final AddonCarManager manager;
  final VoidCallback onChanged;

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  ModPackage? _pkg;
  String? _zipName;
  String? _error;
  bool _dragging = false;

  Future<void> _dropped(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final zip = d.files.where((f) => ModPackage.extensions.contains(f.name.toLowerCase().split('.').last)).firstOrNull;
    if (zip == null) {
      setState(() => _error = 'Drop a .zip, .7z or .rar');
      return;
    }
    await openBytes(await zip.readAsBytes(), zip.name);
  }

  Future<void> _open() async {
    final f = await openFile(
      acceptedTypeGroups: [const XTypeGroup(label: 'Mod archive', extensions: ModPackage.extensions)],
    );
    if (f == null) return;
    await openBytes(await f.readAsBytes(), f.name);
  }

  /// Loads a mod archive's contents (separate from the file dialog so tests can call it).
  Future<void> openBytes(Uint8List bytes, String name) async {
    try {
      final pkg = await ModPackage.openArchive(bytes, name);
      setState(() {
        _pkg = pkg;
        _zipName = name;
        _error = null;
      });
    } on Object catch (e) {
      setState(() {
        _pkg = null;
        _zipName = name;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final libertyPlates = widget.manager.libertyPlates;
    final installed = widget.manager.listCars().map((c) => c.model).toSet();
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _dropped,
      child: Container(
        foregroundDecoration: _dragging
            ? BoxDecoration(
                color: context.theme.colors.primary.withValues(alpha: 0.06),
                border: Border.all(color: context.theme.colors.primary, width: 2),
              )
            : null,
        child: ListView(
          primary: true,
          children: [
            Panel(
              child: Row(
                spacing: 14,
                children: [
                  Expanded(child: Text(_zipName ?? 'Install from .zip, .7z or .rar (or drop one here)', style: context.titleStyle)),
                  FButton(
                    variant: _pkg == null ? .primary : .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: _open,
                    child: Text(_pkg == null ? 'Choose archive' : 'Choose another'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FAlert(variant: .destructive, title: const Text('Could not read that archive'), subtitle: Text(_error!)),
            ],
            if (_pkg != null)
              // .wft files without data lines only matter when they replace a vanilla car (or are all there is)
              for (final model in _pkg!.models)
                if (_pkg!.sources.containsKey(model) || _pkg!.sources.isEmpty || widget.manager.gameCar(model) != null) ...[
                  const SizedBox(height: 12),
                  _ModelPanel(
                    key: ValueKey('$_zipName $model'),
                    pkg: _pkg!,
                    model: model,
                    installed: installed.contains(model),
                    libertyPlates: libertyPlates,
                    manager: widget.manager,
                    onChanged: widget.onChanged,
                  ),
                ],
          ],
        ),
      ),
    );
  }
}

/// Flat, padded block (the Install tab's equivalent of a list row).
class Panel extends StatelessWidget {
  const Panel({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), color: context.theme.colors.card, child: child);
}

class _ModelPanel extends StatefulWidget {
  const _ModelPanel({
    required this.pkg,
    required this.model,
    required this.installed,
    required this.libertyPlates,
    required this.manager,
    required this.onChanged,
    super.key,
  });

  final ModPackage pkg;
  final String model;
  final bool installed, libertyPlates;
  final AddonCarManager manager;
  final VoidCallback onChanged;

  @override
  State<_ModelPanel> createState() => _ModelPanelState();
}

class _ModelPanelState extends State<_ModelPanel> {
  late String? _wft = widget.pkg.defaultModel(widget.model, libertyPlates: widget.libertyPlates);
  late String? _wtd = widget.pkg.defaultTexture(widget.model);

  /// Set when the mod replaces a vanilla car: it is installed as a new car, missing lines copied from the game.
  late final CarData? _vanilla = widget.manager.gameCar(widget.model);
  late final CarData _detected = _vanilla == null ? widget.pkg.car(widget.model) : widget.pkg.car(widget.model).filledFrom(_vanilla);
  late final _modelName = TextEditingController(text: _vanilla == null ? widget.model : '${widget.model}2');
  late final _handling = TextEditingController(text: _vanilla == null ? _detected.handlingId : '${_detected.handlingId}2');
  late final _name = TextEditingController(text: widget.manager.readNames()[_detected.gameName.toUpperCase()]);
  final _key = TextEditingController(); // name key typed by hand; empty: the automatic one
  late final _sounds = widget.manager.soundModels..sort();
  // LibertyCityPlates plate types; empty (no picker, nothing written) when the mod is not installed
  late final _plates = widget.manager.plateTypes();
  int _plate = 0; // 0: the default for the vehicle type
  final _scanner = <String, String>{}; // police scanner sounds picked instead of the sound block's own

  String _plateLabel(int id) {
    if (id == 0) return 'Default';
    final (_, label, percent) = _plates.firstWhere((p) => p.$1 == id);
    return '${label[0].toUpperCase()}${label.substring(1)}  ·  $percent%';
  }

  late final _sound = FAutocompleteController(text: _vanilla != null && _sounds.contains(widget.model) ? widget.model : '');
  bool _showLines = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_modelName, _handling, _name, _key]) {
      c.addListener(() => setState(() {}));
    }
    // the autocomplete also notifies while it builds its suggestions: rebuild only for typed text
    var typed = _sound.text;
    _sound.addListener(() {
      if (_sound.text == typed) return;
      typed = _sound.text;
      _scanner.clear(); // picked for the previous car's sound
      setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in [_modelName, _handling, _name, _key, _sound]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // before and after the typed name: a name on a borrowed vanilla key gives the car its own key, as install() does
    final unnamed = _detected.renamed(model: _modelName.text, handlingId: _handling.text, keepNameKey: _vanilla != null);
    final named = widget.manager.withOwnNameKey(unnamed, _name.text, ownKey: _key.text);
    final cloned = named.audioLines.isEmpty ? widget.manager.clonedSound(_sound.text, named.model) : null;
    final sounded = cloned == null ? named : named.withAudio(cloned);
    final car = sounded.audioLines.isEmpty || _scanner.isEmpty
        ? sounded
        : sounded.withAudio(AddonCarManager.withSoundFields(sounded.audioLines, _scanner));
    final problems = [
      ...car.problems,
      if (!widget.installed) ...widget.manager.nameClashes(car),
      if (_key.text.trim().isNotEmpty && !validNameKey(_key.text.trim())) nameKeyRule,
      if (_wft == null) 'no ${widget.model}.wft in the archive',
      if (_wtd == null) 'no texture (.wtd) for ${widget.model} in the archive',
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Row(
            spacing: 14,
            children: [
              Expanded(child: Text(widget.model, style: context.titleStyle)),
              if (_vanilla != null && !widget.installed) Pill('Replaces ${widget.model}'),
              // the game finds a car's sound by its name key, so a borrowed vanilla key brings that car's sound
              if (car.audioLines.isEmpty && !widget.installed)
                switch (widget.manager.vanillaCarWithNameKey(car.gameName)) {
                  final vanilla? => Pill('Sound: $vanilla'),
                  null => const Pill('No sound block', tone: Tone.bad),
                },
              if (widget.installed)
                const Pill('Installed', tone: Tone.ok)
              else if (problems.isNotEmpty)
                const Pill('Incomplete', tone: Tone.bad),
            ],
          ),
          // an installed car needs nothing more here: rename or remove it on the Cars tab
          if (!widget.installed) ..._form(context, car, unnamed, problems),
        ],
      ),
    );
  }

  List<Widget> _form(BuildContext context, CarData car, CarData unnamed, List<String> problems) => [
    if (problems.isNotEmpty) FAlert(variant: .destructive, title: const Text('Cannot install'), subtitle: Text(problems.join('\n'))),
    Row(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Expanded(child: _select('Model (.wft)', widget.pkg.modelVariants(widget.model), _wft, (v) => setState(() => _wft = v))),
        Expanded(child: _select('Texture (.wtd)', widget.pkg.textureVariants(widget.model), _wtd, (v) => setState(() => _wtd = v))),
      ],
    ),
    if (!widget.libertyPlates) Text('LIBERTYCITYPLATES.ASI NOT INSTALLED: LIBERTYPLATES MODELS WILL CRASH.', style: context.smallMuted),
    Row(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Expanded(
          child: FTextField(
            control: .managed(controller: _modelName),
            label: const Text('Model name'),
          ),
        ),
        Expanded(
          child: FTextField(
            control: .managed(controller: _handling),
            label: const Text('Handling name'),
          ),
        ),
        Expanded(
          flex: 2,
          child: FTextField(
            control: .managed(controller: _name),
            label: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                const Text('In-game name'),
                FTooltip(
                  tipBuilder: (_, _) => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Text(_nameTip(unnamed))),
                  child: Icon(FLucideIcons.circleHelp, size: 14, color: context.theme.colors.mutedForeground),
                ),
              ],
            ),
            hint: 'e.g. ${widget.model[0].toUpperCase()}${widget.model.substring(1)}',
          ),
        ),
        Expanded(
          child: FTextField(
            control: .managed(controller: _key),
            label: const Text('Name key'),
            hint: widget.manager.withOwnNameKey(unnamed, _name.text).gameName,
          ),
        ),
      ],
    ),
    // no sound in the mod: clone another car's (a replace mod starts with the replaced car's)
    if (_detected.audioLines.isEmpty)
      FAutocomplete.text(
        items: widget.manager.soundModels..sort(), // re-read: a car just installed from this archive can be cloned
        control: .managed(controller: _sound),
        label: const Text('Sound from'),
        hint: 'e.g. sultan',
        description: _sound.text.trim().isEmpty || car.audioLines.isNotEmpty
            ? null
            : Text('NO SOUND FOR ${_sound.text.trim().toUpperCase()}'),
      ),
    if (car.audioLines.isNotEmpty) ...[
      ScannerSelects(
        key: ValueKey('scanner ${_sound.text}'),
        lines: car.audioLines,
        onChange: (field, value) => setState(() => _scanner[field] = value),
      ),
      if (AddonCarManager.episodeOnlySounds(car.audioLines).isNotEmpty)
        Text(
          '${AddonCarManager.episodeOnlySounds(car.audioLines).join(' AND ').toUpperCase()} ENGINE SOUNDS: ERRORS IN THE OTHER GAMES',
          style: context.smallMuted.copyWith(color: context.theme.colors.destructive),
        ),
    ],
    if (_plates.isNotEmpty)
      FSelect<int>.rich(
        label: const Text('Plate'),
        format: (id) => _plateLabel(id),
        control: .managed(initial: 0, onChange: (v) => setState(() => _plate = v ?? 0)),
        children: [
          for (final id in [0, ..._plates.map((p) => p.$1)]) .item(title: Text(_plateLabel(id)), value: id),
        ],
      ),
    if (_plate != 0) PlateOdds(widget.manager, _plate),
    Row(
      children: [
        FButton(
          variant: .ghost,
          size: .sm,
          mainAxisSize: .min,
          prefix: Icon(_showLines ? FLucideIcons.chevronUp : FLucideIcons.chevronDown),
          onPress: () => setState(() => _showLines = !_showLines),
          child: const Text('Data lines'),
        ),
        const Spacer(),
        FButton(
          size: .sm,
          mainAxisSize: .min,
          onPress: problems.isNotEmpty
              ? null
              : () async {
                  final named = _name.text.trim().isNotEmpty;
                  if (!await confirmSharedKey(context, widget.manager, car.gameName, car.model, named: named)) return;
                  if (!context.mounted) return;
                  runAction(
                    context,
                    '${car.model} installed',
                    () => widget.manager.install(
                      car,
                      widget.pkg.files[_wft]!,
                      widget.pkg.files[_wtd]!,
                      displayName: _name.text,
                      nameKey: car.gameName, // as shown; install() must not work it out again
                      plate: _plate == 0 ? null : _plate,
                    ),
                    widget.onChanged,
                  );
                },
          child: Text('Install ${car.model}'),
        ),
      ],
    ),
    if (_showLines) _DataLines(car),
  ];

  /// What the name field does for this car's name key (5th .ide column), matching install()'s rules.
  String _nameTip(CarData car) {
    final key = car.gameName;
    final vanilla = widget.manager.vanillaCarWithNameKey(key);
    final addon = widget.manager.listCars().where((c) => c.gameName.toUpperCase() == key.toUpperCase()).firstOrNull;
    final intro = 'Shown bottom-right when you get in. Name key: $key';
    if (vanilla != null) {
      return '$intro (the vanilla $vanilla\'s).\n\n'
          'Empty: shows the $vanilla\'s name.\n'
          'Typed: the car gets its own key, ${car.model.toUpperCase()}, with this name. The $vanilla keeps its name.';
    }
    if (addon != null) {
      return '$intro, shared with ${addon.displayName ?? addon.model}.\n\n'
          'Typing a name renames both.';
    }
    return '$intro.\n\nEmpty: the game has no text for this key and shows a placeholder.';
  }

  /// What tells variants apart: their folders below the zip's shared top folder ("Tuner › Rim Option 1 ›
  /// LibertyPlates compatible model"), plus the file name only when it is not the standard one.
  String _pretty(String path) {
    final shared = widget.pkg.files.keys.map((p) => p.split('/').first).toSet();
    var parts = path.split('/');
    if (shared.length == 1 && parts.length > 1) parts = parts.sublist(1);
    final file = parts.removeLast();
    final standard = file.toLowerCase() == '${widget.model}.wft' || file.toLowerCase() == '${widget.model}.wtd';
    final label = [...parts, if (!standard) file].join('  ›  ');
    return label.isEmpty ? 'Default (zip root)' : label;
  }

  Widget _select(String label, List<String> options, String? value, ValueChanged<String?> onChange) => FSelect<String>.rich(
    label: Text(label),
    hint: 'Choose',
    format: _pretty,
    control: .managed(initial: value, onChange: onChange),
    children: [for (final o in options) .item(title: Text(_pretty(o)), value: o)],
  );
}

/// The lines the install will write, after renaming, grouped by file.
class _DataLines extends StatelessWidget {
  const _DataLines(this.car);
  final CarData car;

  @override
  Widget build(BuildContext context) {
    String game(String key) => car.fromGame.contains(key) ? '  (from game files)' : '';
    final sections = {
      'addoncars.ide${game('ide')}': [?car.ideLine],
      if (car.txdpLine != null) 'addoncars.ide, txdp section': [car.txdpLine!],
      'carcols.dat${car.carcolsSection == null ? '' : ' (${car.carcolsSection})'}${game('carcols')}': [?car.carcolsLine],
      'handling.dat${game('handling')}${car.handlingLine == null ? '  (uses the existing ${car.handlingId} line)' : ''}': [
        ?car.handlingLine,
      ],
      'vehOff.csv${game('vehoff')}': car.vehOffLines,
      'vehicleAudio\\${car.model}.ini': car.audioLines,
    };
    final mono = context.theme.typography.body.xs.copyWith(fontFamily: 'Consolas', height: 1.5);
    return Container(
      padding: const EdgeInsets.all(12),
      color: context.theme.colors.background,
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText.rich(
            TextSpan(
              style: mono,
              children: [
                for (final MapEntry(:key, :value) in sections.entries) ...[
                  TextSpan(
                    text: '$key\n',
                    style: mono.copyWith(color: context.theme.colors.mutedForeground),
                  ),
                  TextSpan(text: value.isEmpty ? '(none)\n\n' : '${value.join('\n')}\n\n'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
