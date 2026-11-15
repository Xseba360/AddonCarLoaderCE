import 'dart:math';

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/cargrp.dart';
import '../core/manager.dart';
import '../main.dart';
import 'ui.dart';

/// Master-detail, styled after the pause menu's Stats page: cars on the left (selected in orange),
/// the selection's details and actions on the right. Tick boxes, Ctrl-click or Shift-click select
/// several cars; the arrow keys move the selection.
class CarsPage extends StatefulWidget {
  const CarsPage({required this.manager, required this.onChanged, super.key});

  final AddonCarManager manager;
  final VoidCallback onChanged;

  @override
  State<CarsPage> createState() => _CarsPageState();
}

class _CarsPageState extends State<CarsPage> {
  final _selected = <String>{};
  final _focus = FocusNode();
  String? _anchor; // the last car clicked: where a Shift-click range and the arrow keys start

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _click(List<InstalledCar> cars, String model, {bool toggle = false}) {
    final keys = HardwareKeyboard.instance;
    _focus.requestFocus();
    setState(() {
      final anchor = cars.indexWhere((c) => c.model == _anchor);
      if (keys.isShiftPressed && anchor >= 0) {
        final at = cars.indexWhere((c) => c.model == model);
        if (!keys.isControlPressed) _selected.clear();
        _selected.addAll([for (var i = min(anchor, at); i <= max(anchor, at); i++) cars[i].model]);
        return;
      }
      if (toggle || keys.isControlPressed) {
        if (!_selected.remove(model)) _selected.add(model);
      } else {
        _selected
          ..clear()
          ..add(model);
      }
      _anchor = model;
    });
  }

  KeyEventResult _key(List<InstalledCar> cars, KeyEvent event) {
    final step = event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : event.logicalKey == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (step == 0 || event is KeyUpEvent) return .ignored;
    final at = cars.indexWhere((c) => c.model == _anchor);
    final next = cars[(at + step).clamp(0, cars.length - 1)].model;
    setState(() {
      _selected
        ..clear()
        ..add(next);
      _anchor = next;
    });
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final cars = widget.manager.listCars();
    if (cars.isEmpty) {
      return Center(child: Text('No add-on cars', style: context.mutedStyle));
    }
    _selected.retainAll(cars.map((c) => c.model));
    if (_selected.isEmpty) _selected.add(_anchor = cars.first.model);
    final picked = [
      for (final c in cars)
        if (_selected.contains(c.model)) c,
    ];
    return Row(
      crossAxisAlignment: .start,
      spacing: 32,
      children: [
        SizedBox(
          width: 280,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: (_, event) => _key(cars, event),
            child: ListView(
              primary: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 0, 10, 10),
                  child: Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: FCheckbox(
                          value: picked.length == cars.length,
                          label: const Text('Select all'),
                          onChange: (v) => setState(() {
                            _selected.clear();
                            _selected.addAll(v ? cars.map((c) => c.model) : [_anchor ?? cars.first.model]);
                          }),
                        ),
                      ),
                      Text('${picked.length} OF ${cars.length}', style: context.smallMuted),
                    ],
                  ),
                ),
                for (final c in cars)
                  _CarRow(
                    car: c,
                    selected: _selected.contains(c.model),
                    problem: _problems(c).isNotEmpty,
                    onTap: () => _click(cars, c.model),
                    onToggle: () => _click(cars, c.model, toggle: true),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: SingleChildScrollView(child: picked.length == 1 ? _single(context, picked.single) : _several(context, picked))),
      ],
    );
  }

  /// Title with the model under it, then the actions on their own line.
  Widget _header(BuildContext context, String title, String detail, List<InstalledCar> cars) => Column(
    crossAxisAlignment: .start,
    spacing: 12,
    children: [
      Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(title, style: context.theme.typography.body.xl3),
          if (detail.isNotEmpty) Text(detail.toUpperCase(), style: context.smallMuted),
        ],
      ),
      _actions(context, cars),
    ],
  );

  Widget _single(BuildContext context, InstalledCar car) {
    final problems = _problems(car);
    final traffic = widget.manager.trafficGroupsOf(car.model);
    final plate = widget.manager.plateOf(car.model);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        _header(context, car.displayName ?? car.model, car.model, [car]),
        StatsTable([
          if (problems.isNotEmpty) ('Missing', problems.join(', '), true),
          ('Name key', car.gameName, car.displayName == null),
          ('Handling', car.handlingId, false),
          // without its own file the game uses the sound of the vanilla car whose name key it has
          ('Sound', car.hasSound ? 'Custom' : (widget.manager.vanillaCarWithNameKey(car.gameName) ?? 'Default'), false),
          if (plate != null) ('Plate', _plateLabel(plate), false),
        ]),
        Text('TRAFFIC', style: context.smallMuted),
        StatsTable([
          for (final MapEntry(key: e, value: groups) in traffic.entries)
            (e.title, groups.isEmpty ? 'None' : '${groups.length} ${groups.length == 1 ? 'group' : 'groups'}', false),
        ]),
      ],
    );
  }

  Widget _several(BuildContext context, List<InstalledCar> cars) => Column(
    crossAxisAlignment: .stretch,
    spacing: 16,
    children: [
      _header(context, '${cars.length} cars selected', '', cars),
      StatsTable([for (final c in cars) (c.displayName ?? c.model, c.model, _problems(c).isNotEmpty)]),
    ],
  );

  Widget _actions(BuildContext context, List<InstalledCar> cars) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FButton(
        variant: .outline,
        size: .sm,
        mainAxisSize: .min,
        prefix: const Icon(FLucideIcons.mapPin),
        onPress: () => editTraffic(context, widget.manager, [for (final c in cars) c.model], widget.onChanged),
        child: const Text('Traffic groups…'),
      ),
      if (cars.length == 1)
        FButton(
          variant: .outline,
          size: .sm,
          mainAxisSize: .min,
          prefix: const Icon(FLucideIcons.pencil),
          onPress: () => _rename(context, cars.single),
          child: const Text('Rename…'),
        ),
      if (cars.length == 1 && cars.single.hasSound)
        FButton(
          variant: .outline,
          size: .sm,
          mainAxisSize: .min,
          prefix: const Icon(FLucideIcons.radio),
          onPress: () => _editScanner(context, cars.single),
          child: const Text('Scanner…'),
        ),
      // only with LibertyCityPlates installed
      if (widget.manager.plateTypes().isNotEmpty)
        FButton(
          variant: .outline,
          size: .sm,
          mainAxisSize: .min,
          prefix: const Icon(FLucideIcons.rectangleHorizontal),
          onPress: () => _editPlate(context, cars),
          child: const Text('Plate…'),
        ),
      FButton(
        variant: .outline,
        size: .sm,
        mainAxisSize: .min,
        prefix: Icon(FLucideIcons.trash2, color: context.theme.colors.destructive),
        onPress: () => _remove(cars),
        child: const Text('Remove…'),
      ),
    ],
  );

  static List<String> _problems(InstalledCar car) => [
    if (!car.hasArchive) 'model archive',
    if (!car.inCarcols) 'colours',
    if (!car.inHandling) 'handling',
    if (car.cameraLines == 0) 'cameras',
  ];

  /// One confirm for all given cars; each removal makes its own backup, as a single remove does.
  Future<void> _remove(List<InstalledCar> cars) async {
    final names = cars.map((c) => c.displayName ?? c.model).join(', ');
    if (!await confirm(
      context,
      'Remove ${cars.length == 1 ? names : '${cars.length} cars'}?',
      '${cars.length == 1 ? '' : '$names\n\n'}Removes data lines, archives, sounds, names and traffic entries. Each car is backed up first and can be restored in Backups.',
      ok: 'Remove',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    runAction(context, '${cars.length == 1 ? names : '${cars.length} cars'} removed', () {
      for (final c in cars) {
        widget.manager.remove(c.model);
      }
    }, widget.onChanged);
  }

  /// The police scanner sounds in the car's own sound file.
  Future<void> _editScanner(BuildContext context, InstalledCar car) async {
    final lines = widget.manager.soundLines(car.model);
    if (lines == null) return;
    final changes = <String, String>{};
    final ok = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(maxWidth: 720),
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Text(
                'Police scanner for ${car.displayName ?? car.model}',
                style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600),
              ),
              ScannerSelects(lines: lines, onChange: (field, value) => changes[field] = value),
              Row(
                mainAxisAlignment: .end,
                spacing: 8,
                children: [
                  FButton(
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FButton(size: .sm, mainAxisSize: .min, onPress: () => Navigator.of(context).pop(true), child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && changes.isNotEmpty && context.mounted) {
      runAction(context, 'Scanner saved', () => widget.manager.setSoundFields(car.model, changes), widget.onChanged);
    }
  }

  /// 0 is the default for the vehicle type; other ids are LibertyCityPlates plate types.
  String _plateLabel(int id) {
    if (id == 0) return 'Default';
    final type = widget.manager.plateTypes().where((p) => p.$1 == id).firstOrNull;
    // the percentage: how often a car given this plate keeps it instead of falling back to the plate's parent
    return type == null ? 'Plate $id' : '${type.$2[0].toUpperCase()}${type.$2.substring(1)}  ·  ${type.$3}%';
  }

  /// One plate for all given cars; each change makes its own backup.
  Future<void> _editPlate(BuildContext context, List<InstalledCar> cars) async {
    var plate = cars.length == 1 ? widget.manager.plateOf(cars.single.model) ?? 0 : 0;
    final ids = {0, ...widget.manager.plateTypes().map((p) => p.$1), plate};
    final what = cars.length == 1 ? cars.single.displayName ?? cars.single.model : '${cars.length} cars';
    final ok = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              spacing: 14,
              children: [
                Text('Plate for $what', style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
                FSelect<int>.rich(
                  format: _plateLabel,
                  control: .managed(initial: plate, onChange: (v) => setState(() => plate = v ?? 0)),
                  children: [for (final id in ids) .item(title: Text(_plateLabel(id)), value: id)],
                ),
                PlateOdds(widget.manager, plate),
                Row(
                  mainAxisAlignment: .end,
                  spacing: 8,
                  children: [
                    FButton(
                      variant: .outline,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FButton(size: .sm, mainAxisSize: .min, onPress: () => Navigator.of(context).pop(true), child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true && context.mounted) {
      runAction(context, 'Plate saved', () {
        for (final c in cars) {
          widget.manager.setPlate(c.model, plate == 0 ? null : plate);
        }
      }, widget.onChanged);
    }
  }

  Future<void> _rename(BuildContext context, InstalledCar car) async {
    final controller = TextEditingController(text: car.displayName ?? '');
    final key = TextEditingController(text: car.gameName);
    final ok = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              Text('Rename ${car.model}', style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
              FTextField(
                control: .managed(controller: controller),
                label: const Text('In-game name'),
                hint: 'e.g. Sultan RS',
                autofocus: true,
              ),
              FTextField(
                control: .managed(controller: key),
                label: const Text('Name key'),
                description: const Text('UP TO 8 CHARACTERS. CARS WITH THE SAME KEY SHOW ONE NAME.'),
              ),
              Row(
                mainAxisAlignment: .end,
                spacing: 8,
                children: [
                  FButton(
                    variant: .outline,
                    size: .sm,
                    mainAxisSize: .min,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FButton(size: .sm, mainAxisSize: .min, onPress: () => Navigator.of(context).pop(true), child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    // an untouched key keeps the automatic rule (a borrowed vanilla key becomes the car's own)
    final typed = key.text.trim();
    final ownKey = typed.isEmpty || AddonCarManager.nameKey(typed) == AddonCarManager.nameKey(car.gameName) ? null : typed;
    if (ownKey != null) {
      if (!validNameKey(ownKey)) {
        showFToast(context: context, variant: .destructive, title: const Text(nameKeyRule));
        return;
      }
      final named = controller.text.trim().isNotEmpty;
      if (!await confirmSharedKey(context, widget.manager, ownKey, car.model, named: named) || !context.mounted) return;
    }
    runAction(context, 'Name saved', () => widget.manager.rename(car.model, controller.text, ownKey: ownKey), widget.onChanged);
  }
}

const nameKeyRule = 'Name key: 1 to 8 letters, digits or _';
bool validNameKey(String key) => RegExp(r'^[A-Za-z0-9_]{1,8}$').hasMatch(key);

/// Asks before [model] takes a name key other cars use: true when none do or the user accepts.
Future<bool> confirmSharedKey(BuildContext context, AddonCarManager manager, String key, String model, {required bool named}) async {
  final sharers = manager.nameKeySharers(key, model, named: named);
  if (sharers.isEmpty) return true;
  return confirm(
    context,
    'Shared name key',
    '${AddonCarManager.nameKey(key)} is also the name key of ${sharers.join(', ')}.\nThey will show one name in the game.',
    ok: 'Use it anyway',
  );
}

/// Pickers for what the police radio calls a car (make, model, type), from the three scanner lines
/// of a sound block. Only the base game's sounds are offered: they exist in every episode.
class ScannerSelects extends StatelessWidget {
  const ScannerSelects({required this.lines, required this.onChange, super.key});
  final List<String> lines;
  final void Function(String field, String value) onChange;

  static const _labels = ['Scanner make', 'Scanner model', 'Scanner type'];

  static String _pretty(String sound) {
    if (sound.isEmpty || sound == 'NULL' || sound == 'NULL_SOUND') return 'None';
    final episode = AddonCarManager.episodeOf(sound);
    final words = sound
        .replaceFirst(RegExp(r'^(POLICE_SCANNER_(MANUFACTURER_MAN|MODEL_MOD|VEHICLE_CATEGORY)_|.*_SCANNER_(VEHICLE_MODEL_)?)'), '')
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0]}${w.substring(1).toLowerCase()}');
    return '${words.join(' ')}${episode == null ? '' : ' ($episode only)'}';
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: .start,
    spacing: 12,
    children: [
      for (final (i, field) in AddonCarManager.scannerFields.indexed)
        Expanded(
          child: () {
            final current = AddonCarManager.soundField(lines, field) ?? 'NULL_SOUND';
            return FSelect<String>.rich(
              label: Text(_labels[i]),
              format: _pretty,
              control: .managed(
                initial: current,
                onChange: (v) {
                  if (v != null) onChange(field, v);
                },
              ),
              children: [
                for (final o in {...AddonCarManager.scannerSounds(field), current}) .item(title: Text(_pretty(o)), value: o),
              ],
            );
          }(),
        ),
    ],
  );
}

/// What a car given this plate ends up wearing, since LibertyCityPlates only keeps a plate on some
/// rolls and otherwise passes the car to the plate's parent. Nothing for 0 (the default).
class PlateOdds extends StatelessWidget {
  const PlateOdds(this.manager, this.plate, {super.key});
  final AddonCarManager manager;
  final int plate;

  static String _line(Map<String, double> odds) {
    final shown = odds.entries.where((e) => e.value >= 0.01).toList()..sort((a, b) => b.value.compareTo(a.value));
    final other = odds.values.where((v) => v < 0.01).fold(0.0, (a, b) => a + b);
    return [
      for (final e in shown) '${e.key} ${(e.value * 100).round()}%',
      if (other >= 0.005) 'other ${(other * 100).round()}%',
    ].join('  ·  ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (plate == 0) return const SizedBox.shrink();
    final out = manager.plateOdds(plate);
    if (out.areas.isEmpty) return Text(_line(out.odds), style: context.smallMuted);
    final area = out.areas.join(', ').toUpperCase();
    return Column(
      crossAxisAlignment: .start,
      spacing: 6,
      children: [
        Text('IN $area:  ${_line(manager.plateOdds(plate, inAreas: true).odds)}', style: context.smallMuted),
        Text('ELSEWHERE:  ${_line(out.odds)}', style: context.smallMuted),
      ],
    );
  }
}

/// A car in the left list: tick box, name over model. Selected rows get the orange bar and name.
class _CarRow extends StatefulWidget {
  const _CarRow({required this.car, required this.selected, required this.problem, required this.onTap, required this.onToggle});
  final InstalledCar car;
  final bool selected, problem;
  final VoidCallback onTap, onToggle;

  @override
  State<_CarRow> createState() => _CarRowState();
}

class _CarRowState extends State<_CarRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.theme.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
          decoration: BoxDecoration(
            color: widget.selected || _hover ? c.card : null,
            border: Border(left: BorderSide(width: 3, color: widget.selected ? gtaOrange : const Color(0x00000000))),
          ),
          child: Row(
            spacing: 10,
            children: [
              FCheckbox(value: widget.selected, onChange: (_) => widget.onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      widget.car.displayName ?? widget.car.model,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.md.copyWith(
                        color: widget.selected ? gtaOrange : (_hover ? c.foreground : c.mutedForeground),
                      ),
                    ),
                    Text(widget.car.model.toUpperCase(), overflow: TextOverflow.ellipsis, style: context.smallMuted),
                  ],
                ),
              ),
              if (widget.problem)
                FTooltip(
                  tipBuilder: (_, _) => const Text('Missing files or lines'),
                  child: Icon(FLucideIcons.circleAlert, size: 16, color: c.destructive),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the traffic groups for one or more cars at once, per episode. A group holding only some of
/// the cars is left alone unless it is ticked (adds the rest) or unticked (removes them all).
Future<void> editTraffic(BuildContext context, AddonCarManager manager, List<String> models, VoidCallback onChanged) async {
  final changes = await showFDialog<Map<Episode, Map<int, bool>>>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (context, style) => _TrafficPicker(manager: manager, models: models),
    ),
  );
  if (changes == null || changes.values.every((m) => m.isEmpty) || !context.mounted) return;
  final names = {for (final c in manager.listCars()) c.model: c.displayName ?? c.model};
  runAction(
    context,
    'Traffic groups saved for ${models.map((m) => names[m] ?? m).join(', ')}',
    () => manager.setTrafficGroups(models, changes),
    onChanged,
  );
}

class _TrafficPicker extends StatefulWidget {
  const _TrafficPicker({required this.manager, required this.models});
  final AddonCarManager manager;
  final List<String> models;

  @override
  State<_TrafficPicker> createState() => _TrafficPickerState();
}

class _TrafficPickerState extends State<_TrafficPicker> {
  Episode _episode = Episode.iv;
  final _changes = <Episode, Map<int, bool>>{};
  late final _groups = {for (final e in Episode.values) e: widget.manager.readCarGroups(e).groups};
  final _copyFrom = FAutocompleteController();
  String? _copyNote;

  /// Every car listed in some traffic group, for the copy-from suggestions.
  late final _knownCars = {
    for (final gs in _groups.values)
      for (final g in gs)
        for (final m in g.models) m.toLowerCase(),
  }.where((m) => !widget.models.contains(m)).toList()..sort();

  @override
  void dispose() {
    _copyFrom.dispose();
    super.dispose();
  }

  /// Ticks, in every episode, the groups that list the typed car (adds to what is ticked already).
  void _copy() {
    final from = _copyFrom.text.trim().toLowerCase();
    if (from.isEmpty) return;
    final n = widget.models.length;
    final ticked = <String>[];
    var full = 0;
    for (final e in Episode.values) {
      final changes = _changes[e] ??= {};
      var count = 0;
      for (final g in _groups[e]!) {
        if (!g.usedByGame || g.multiplayerOnly || !g.models.any((m) => m.toLowerCase() == from)) continue;
        final have = widget.models.where((m) => g.models.any((x) => x.toLowerCase() == m)).length;
        count++;
        if (have == n) continue;
        if (g.models.length + (n - have) > CarGroups.maxCarsPerGroup) {
          full++;
        } else {
          changes[g.index] = true;
        }
      }
      if (count > 0) ticked.add('${e.title} $count');
    }
    setState(() {
      _copyNote = ticked.isEmpty
          ? '$from is in no traffic group'
          : 'Ticked $from\'s groups: ${ticked.join(', ')}${full == 0 ? '' : '  ·  $full full, skipped'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes[_episode] ??= {};
    final groups = [
      for (final g in _groups[_episode]!)
        if (g.usedByGame && !g.multiplayerOnly) g,
    ];
    final n = widget.models.length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Text(
            n == 1 ? 'Traffic groups' : 'Traffic groups for $n cars',
            style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Segmented<Episode>(
              values: Episode.values,
              label: (e) => e.title,
              selected: _episode,
              onSelect: (e) => setState(() => _episode = e),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: FAutocomplete.text(
                  items: _knownCars,
                  control: .managed(controller: _copyFrom),
                  hint: 'Copy groups from a car, e.g. sultan',
                  onSubmit: (_) => _copy(),
                ),
              ),
              FButton(variant: .outline, size: .sm, mainAxisSize: .min, onPress: _copy, child: const Text('Copy')),
            ],
          ),
          if (_copyNote != null) Text(_copyNote!.toUpperCase(), style: context.smallMuted),
          // shrinks with the window; the buttons below always stay visible
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [for (final g in groups) SizedBox(width: 220, child: _box(g, changes, n))],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: 8,
            children: [
              FButton(
                variant: .outline,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FButton(
                size: .sm,
                mainAxisSize: .min,
                onPress: _changes.values.every((m) => m.isEmpty) ? null : () => Navigator.of(context).pop(_changes),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(CarGroup g, Map<int, bool> changes, int n) {
    final have = widget.models.where((m) => g.models.any((x) => x.toLowerCase() == m)).length;
    final value = changes[g.index] ?? have == n;
    // adding the cars not in it yet must stay within the game's limit
    final fits = g.models.length + (n - have) <= CarGroups.maxCarsPerGroup;
    return FCheckbox(
      value: value,
      label: Text(g.name),
      description: Text('${g.models.length} / ${CarGroups.maxCarsPerGroup}${have > 0 && have < n ? '  ·  $have of $n in it' : ''}'),
      onChange: value || fits
          ? (v) => setState(() {
              if ((have == 0 && !v) || (have == n && v)) {
                changes.remove(g.index); // back to how it was
              } else {
                changes[g.index] = v;
              }
            })
          : null,
    );
  }
}
