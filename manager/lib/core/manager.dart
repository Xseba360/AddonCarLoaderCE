import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cargrp.dart';
import 'img.dart';
import 'readme.dart';

/// Each episode reads its own cargrp.dat (the loader takes the first registered one).
enum Episode {
  iv('GTA IV', ''),
  tlad('The Lost and Damned', 'TLAD/'),
  tbogt('The Ballad of Gay Tony', 'TBoGT/');

  const Episode(this.title, this.folder);
  final String title, folder;
  String get carGroups => 'update/${folder}common/data/cargrp.dat';
  String get originalCarGroups => '${folder}common/data/cargrp.dat';
}

/// Game-relative paths (forward slashes). Everything goes through GTA IV CE's update\ overload folder.
class Paths {
  static const addonIde = 'update/common/data/addoncars.ide';
  static const names = 'update/common/data/addoncars.fxt';
  static const carcols = 'update/common/data/carcols.dat';
  static const handling = 'update/common/data/handling.dat';
  static const vehOff = 'update/common/data/vehOff.csv';
  // plugin file names; AddonCarManager.hasAsi looks in the folders the ASI loader reads
  static const plugin = 'AddonCarLoaderCE.asi';
  static const fusionFix = 'GTAIV.EFLC.FusionFix.asi';
  static const libertyPlates = 'LibertyCityPlates.asi';
  static const plateTypes = 'update/common/data/vehicles.ide';
  static const backups = 'AddonCarBackups';
  static String sound(String model) => 'update/pc/audio/Config/vehicleAudio/$model.ini';
  static String archive(String model) => 'update/AddonCars/$model.img';
}

class InstalledCar {
  InstalledCar({
    required this.model,
    required this.gameName,
    required this.handlingId,
    required this.displayName,
    required this.hasArchive,
    required this.hasSound,
    required this.inCarcols,
    required this.inHandling,
    required this.cameraLines,
  });

  final String model, gameName, handlingId;
  final String? displayName;
  final bool hasArchive, hasSound, inCarcols, inHandling;
  final int cameraLines;

  bool get complete => hasArchive && inCarcols && inHandling && cameraLines > 0;
}

class BackupFile {
  BackupFile(this.path, this.existed);
  final String path;
  final bool existed;
}

class Backup {
  Backup(this.dir, this.action, this.created, this.files);
  final Directory dir;
  final String action;
  final DateTime created;
  final List<BackupFile> files;
  String get name => dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
}

/// A text file split into lines, written back with its original line endings.
class _Lines {
  _Lines(this.lines, this.nl);
  List<String> lines;
  final String nl;

  static _Lines read(File f, {Encoding enc = latin1}) {
    final s = enc.decode(f.readAsBytesSync());
    final nl = s.contains('\r\n') ? '\r\n' : '\n';
    return _Lines(s.split(nl), nl);
  }

  void write(File f, {Encoding enc = latin1}) => f.writeAsBytesSync(enc.encode(lines.join(nl)));
}

class AddonCarManager {
  AddonCarManager(this.root);

  /// The GTAIV folder (the one with GTAIV.exe).
  final String root;

  File file(String rel) => File('$root${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');

  bool get looksLikeGame => file('GTAIV.exe').existsSync();

  /// The ASI loader takes plugins from plugins\, scripts\ and the game folder itself.
  bool hasAsi(String name) => ['plugins/', 'scripts/', ''].any((d) => file('$d$name').existsSync());
  bool get pluginInstalled => hasAsi(Paths.plugin);

  /// The plugin shipped with the app: next to the exe, or the project's build output when run from tests.
  static File get bundledPlugin {
    final shipped = File('${File(Platform.resolvedExecutable).parent.path}\\${Paths.plugin}');
    return shipped.existsSync() ? shipped : File('${Directory.current.path}\\..\\${Paths.plugin}');
  }

  /// Copies the shipped plugin to where it already is, else next to FusionFix, else into plugins\.
  Backup installPlugin() {
    const dirs = ['plugins/', 'scripts/', ''];
    String? dirOf(String name) => dirs.where((d) => file('$d$name').existsSync()).firstOrNull;
    final target = '${dirOf(Paths.plugin) ?? dirOf(Paths.fusionFix) ?? dirs.first}${Paths.plugin}';
    final bytes = bundledPlugin.readAsBytesSync(); // before anything changes: throws when it is not shipped
    final b = backup('install plugin', [target]);
    file(target)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return b;
  }

  /// FusionFix loads the cars' .img archives from update\; without it they have no model.
  bool get fusionFixInstalled => hasAsi(Paths.fusionFix);

  /// The only game version the plugin's addresses are for.
  static const supportedVersion = '1.2.0.59';
  static final _versions = <String, String?>{};

  /// GTAIV.exe's file version ("1.2.0.59"), or null when it has none.
  String? get gameVersion {
    final f = file('GTAIV.exe');
    if (!f.existsSync()) return null;
    return _versions.putIfAbsent('${f.path} ${f.lastModifiedSync()} ${f.lengthSync()}', () {
      final b = f.readAsBytesSync();
      // VS_FIXEDFILEINFO: signature FEEF04BD, struct version, then the file version as four words
      for (var i = b.length - 16; i >= 0; i--) {
        if (b[i] == 0xBD && b[i + 1] == 0x04 && b[i + 2] == 0xEF && b[i + 3] == 0xFE) {
          final d = ByteData.sublistView(b, i + 8, i + 16);
          int w(int at) => d.getUint16(at, Endian.little);
          return '${w(2)}.${w(0)}.${w(6)}.${w(4)}';
        }
      }
      return null;
    });
  }

  static RegExp _modelLine(String model) =>
      RegExp('^\\s*(${RegExp.escape(model)}\\s*,|${RegExp.escape(model)}\\s|vehicle\\s+${RegExp.escape(model)}\\s)', caseSensitive: false);

  // ---------------------------------------------------------------- reading

  List<String> _addonIdeLines() {
    final f = file(Paths.addonIde);
    if (!f.existsSync()) return [];
    return [
      for (final l in _Lines.read(f).lines)
        if (RegExp(r'^\s*[A-Za-z0-9_]+\s*,').hasMatch(l) && l.split(',').length > 4) l, // not a txdp line
    ];
  }

  static String _col(String line, int i) {
    final c = line.split(',');
    return c.length > i ? c[i].trim() : '';
  }

  Map<String, String> readNames() {
    final f = file(Paths.names);
    if (!f.existsSync()) return {};
    final out = <String, String>{};
    for (final raw in _Lines.read(f, enc: utf8).lines) {
      final l = raw.replaceFirst('﻿', '').trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      final m = RegExp(r'^(\S+)\s*(.*)$').firstMatch(l)!;
      out[m.group(1)!.toUpperCase()] = m.group(2)!;
    }
    return out;
  }

  List<InstalledCar> listCars() {
    final names = readNames();
    String readOr(String rel) => file(rel).existsSync() ? latin1.decode(file(rel).readAsBytesSync()) : '';
    final carcols = readOr(Paths.carcols).split(RegExp(r'\r?\n'));
    final handling = readOr(Paths.handling).split(RegExp(r'\r?\n'));
    final vehOff = readOr(Paths.vehOff).split(RegExp(r'\r?\n'));
    return [
      for (final line in _addonIdeLines())
        () {
          final model = _col(line, 0).toLowerCase(), gameName = _col(line, 4), handlingId = _col(line, 3);
          final re = _modelLine(model);
          return InstalledCar(
            model: model,
            gameName: gameName,
            handlingId: handlingId,
            displayName: names[gameName.toUpperCase()],
            hasArchive: file(Paths.archive(model)).existsSync(),
            hasSound: file(Paths.sound(model)).existsSync(),
            inCarcols: carcols.any(re.hasMatch),
            inHandling: handling.any(_modelLine(handlingId).hasMatch),
            cameraLines: vehOff.where(re.hasMatch).length,
          );
        }(),
    ];
  }

  // ---------------------------------------------------------------- backups

  /// Copies [rels] (those that exist) into a new timestamped backup folder, checks every copy,
  /// and records which files did not exist so a restore can delete them again.
  Backup backup(String action, Iterable<String> rels) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var dir = Directory(file('${Paths.backups}/$stamp $action').path);
    for (var i = 2; dir.existsSync(); i++) {
      dir = Directory(file('${Paths.backups}/$stamp $action ($i)').path);
    }
    dir.createSync(recursive: true);
    final files = <BackupFile>[];
    for (final rel in {...rels}) {
      final src = file(rel);
      final existed = src.existsSync();
      if (existed) {
        final dst = File('${dir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
        dst.parent.createSync(recursive: true);
        src.copySync(dst.path);
        if (!_sameBytes(src, dst)) throw FileSystemException('backup copy differs from the original', dst.path);
      }
      files.add(BackupFile(rel, existed));
    }
    File('${dir.path}${Platform.pathSeparator}manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'action': action,
        'created': now.toIso8601String(),
        'files': [
          for (final f in files) {'path': f.path, 'existed': f.existed},
        ],
      }),
    );
    return Backup(dir, action, now, files);
  }

  static bool _sameBytes(File a, File b) {
    final x = a.readAsBytesSync(), y = b.readAsBytesSync();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  List<Backup> listBackups() {
    final d = Directory(file(Paths.backups).path);
    if (!d.existsSync()) return [];
    final out = <Backup>[];
    for (final sub in d.listSync().whereType<Directory>()) {
      final m = File('${sub.path}${Platform.pathSeparator}manifest.json');
      if (!m.existsSync()) continue;
      try {
        final j = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
        out.add(
          Backup(sub, j['action'] as String, DateTime.parse(j['created'] as String), [
            for (final f in j['files'] as List) BackupFile(f['path'] as String, f['existed'] as bool),
          ]),
        );
      } on FormatException {
        continue;
      }
    }
    return out..sort((a, b) => b.created.compareTo(a.created));
  }

  /// Puts every file of [b] back as it was (deleting files that did not exist then).
  /// The current state is backed up first, so a restore can itself be undone.
  void restore(Backup b) {
    backup('before restoring ${b.name}', b.files.map((f) => f.path));
    for (final f in b.files) {
      final target = file(f.path);
      if (f.existed) {
        target.parent.createSync(recursive: true);
        File('${b.dir.path}${Platform.pathSeparator}${f.path.replaceAll('/', Platform.pathSeparator)}').copySync(target.path);
      } else if (target.existsSync()) {
        target.deleteSync();
      }
    }
  }

  void deleteBackup(Backup b) => b.dir.deleteSync(recursive: true);

  // ---------------------------------------------------------------- editing helpers

  /// update\ copy of a data file; created from the game's own copy (or empty for addoncars.ide).
  _Lines _open(String rel) {
    final f = file(rel);
    if (!f.existsSync()) {
      f.parent.createSync(recursive: true);
      if (rel == Paths.addonIde) {
        f.writeAsStringSync('# Add-on cars, loaded after every vanilla .ide by AddonCarLoaderCE.asi\r\ncars\r\nend\r\n');
      } else {
        file(rel.replaceFirst('update/', '')).copySync(f.path);
      }
    }
    return _Lines.read(f);
  }

  static void _insertInSection(_Lines t, String section, String line) {
    final start = t.lines.indexWhere((l) => l.trim().toLowerCase() == section);
    if (start < 0) throw FormatException('no "$section" section');
    var end = -1;
    for (var i = start + 1; i < t.lines.length; i++) {
      if (t.lines[i].trim().toLowerCase() == 'end') {
        end = i;
        break;
      }
    }
    if (end < 0) end = t.lines.lastIndexWhere((l) => l.trim().isNotEmpty) + 1; // section runs to end of file
    t.lines.insert(end, line);
  }

  static void _insertHandling(_Lines t, String line) {
    final last = t.lines.lastIndexWhere((l) => RegExp(r'^[A-Z0-9_]+\s+\d').hasMatch(l));
    t.lines.insert(last + 1, line);
  }

  static void _append(_Lines t, List<String> lines) {
    while (t.lines.isNotEmpty && t.lines.last.trim().isEmpty) {
      t.lines.removeLast();
    }
    t.lines
      ..addAll(lines)
      ..add('');
  }

  /// A gameName that is a vanilla car's and not the car's own model/handling name or another add-on
  /// car's model is borrowed (a hatchback mod using BLISTA); naming it would rename that car too.
  bool borrowsVanillaName(String model, String gameName, String handlingId, {Iterable<String> otherModels = const []}) {
    final g = nameKey(gameName);
    return g != nameKey(model) &&
        g != nameKey(handlingId) &&
        !otherModels.any((m) => nameKey(m) == g) &&
        vanillaCarWithNameKey(gameName) != null; // not a key typed by hand
  }

  /// The game keeps only 8 characters of a name key: "WASHINGTON" is looked up as WASHINGT, so a
  /// name stored under the long key is never found.
  static String nameKey(String s) => (s.length > 8 ? s.substring(0, 8) : s).toUpperCase();

  /// The car as install() writes it: typing a name for a car that borrows a vanilla car's name key
  /// moves it to its own key (its model name), so the vanilla car keeps its name.
  /// Either way the key is cut to the 8 characters the game keeps. [ownKey] is a key typed by hand
  /// and wins over both rules.
  CarData withOwnNameKey(CarData car, String? displayName, {String? ownKey}) {
    if (car.ideLine == null) return car;
    var key = car.gameName;
    final named = displayName != null && displayName.trim().isNotEmpty;
    if (ownKey != null && ownKey.trim().isNotEmpty) {
      key = ownKey.trim();
    } else if (named && borrowsVanillaName(car.model, key, car.handlingId, otherModels: listCars().map((c) => c.model))) {
      key = car.model;
    }
    if (key.length > 8 || key != car.gameName) key = nameKey(key);
    return key == car.gameName ? car : car.withIdeLine(_withGameName(car.ideLine!, key));
  }

  /// Who else shows the name stored under [key]: add-on cars other than [model], and, when a name
  /// is being typed ([named]), the vanilla car it would rename.
  List<String> nameKeySharers(String key, String model, {required bool named}) => [
    for (final c in listCars())
      if (c.model != model.toLowerCase() && nameKey(c.gameName) == nameKey(key)) c.model,
    if (named) ?vanillaCarWithNameKey(key),
  ];

  static String _withGameName(String ideLine, String gameName) {
    final cols = ideLine.split(',');
    final lead = RegExp(r'^\s*').firstMatch(cols[4])!.group(0)!;
    final trail = RegExp(r'\s*$').firstMatch(cols[4])!.group(0)!;
    cols[4] = '$lead$gameName$trail';
    return cols.join(',');
  }

  void _setName(String key, String? displayName) {
    final f = file(Paths.names);
    final t = f.existsSync()
        ? _Lines.read(f, enc: utf8)
        : _Lines([
            '# Add-on car names shown in-game, read by AddonCarLoaderCE.asi',
            '# GXT key (5th column in addoncars.ide)    Text',
            '',
          ], '\r\n');
    t.lines.removeWhere((l) => RegExp('^\\s*${RegExp.escape(key)}(\\s|\$)', caseSensitive: false).hasMatch(l));
    if (displayName != null && displayName.trim().isNotEmpty) {
      _append(t, ['${key.toUpperCase().padRight(12)}${displayName.trim()}']);
    }
    f.parent.createSync(recursive: true);
    t.write(f, enc: utf8);
  }

  // ---------------------------------------------------------------- operations

  static const _gameDataDirs = ['update/common/data', 'common/data', 'TLAD/common/data', 'TBoGT/common/data'];

  // ---------------------------------------------------------------- LibertyCityPlates
  // The mod reads "license_plates" (plate types) and "used_plates" (model -> plate) sections from every
  // .ide the game loads, addoncars.ide included, and keys used_plates by the model name's hash.

  bool get libertyPlates => hasAsi(Paths.libertyPlates);

  /// Plate types a car can be given, as (id, label, percent): the license_plates lines of the update
  /// vehicles.ide, labelled by the comment above each. Ids up to 15 are the defaults per vehicle
  /// type and are left out. Empty when LibertyCityPlates is not installed.
  ///
  /// percent is how often a car given this plate ends up wearing it: not just the first roll, since
  /// a chain of parents can lead back to the plate (Liberty 2008 keeps 86% of rolls but ends at 96%).
  List<(int, String, int)> plateTypes() => [
    for (final p in _plates())
      if (p.id > 15) (p.id, p.label, ((plateOdds(p.id, inAreas: p.zoned).odds[p.label] ?? 0) * 100).round()),
  ];

  /// Every license_plates line: chance is the percentage of rolls on which the plate stays (the mod
  /// rolls 0..99 and moves to the parent when the roll is above the chance column); zoned plates
  /// only stay inside their map areas.
  List<({int id, String label, int? parent, int chance, bool zoned})> _plates() {
    final f = file(Paths.plateTypes);
    if (!libertyPlates || !f.existsSync()) return const [];
    final out = <({int id, String label, int? parent, int chance, bool zoned})>[];
    var inside = false;
    String? label;
    for (final raw in _Lines.read(f).lines) {
      final l = raw.trim();
      if (!inside) {
        inside = l.toLowerCase() == 'license_plates';
        continue;
      }
      if (l.toLowerCase() == 'end') break;
      if (l.startsWith('#')) {
        label = l.substring(1).trim();
        continue;
      }
      final cols = l.split(RegExp(r'\s+'));
      final id = int.tryParse(cols.first);
      if (id != null) {
        final parent = cols.length > 1 ? int.tryParse(cols[1]) : null; // "null": none
        out.add((
          id: id,
          label: label == null || label.isEmpty ? 'Plate $id' : label,
          parent: parent == null || parent < 0 || parent >= 254 ? null : parent, // the mod's MAX_NUM_PLATES
          chance: ((cols.length > 2 ? int.tryParse(cols[2]) ?? 0 : 0) + 1).clamp(0, 100),
          zoned: cols.length > 14 && (int.tryParse(cols[14]) ?? 0) > 0,
        ));
      }
      label = null;
    }
    return out;
  }

  /// What a car given plate [id] ends up wearing: plate label -> share (0..1), following each plate's
  /// chance and parent (parents can loop). [areas] are the zoned plates on the way; [inAreas] says
  /// whether the car is inside their map areas.
  ({Map<String, double> odds, List<String> areas}) plateOdds(int id, {bool inAreas = false}) {
    final plates = {for (final p in _plates()) p.id: p};
    final odds = <String, double>{};
    final areas = <String>{};
    var left = 1.0;
    int? at = id;
    // a loop of parents converges; the cap only guards a loop in which no plate can stay
    for (var step = 0; step < 2000 && at != null && left > 1e-6; step++) {
      final p = plates[at];
      if (p == null) break;
      if (p.zoned && p.parent != null) areas.add(p.label);
      final stay = p.parent == null ? 1.0 : (p.zoned && !inAreas ? 0.0 : p.chance / 100);
      odds[p.label] = (odds[p.label] ?? 0) + left * stay;
      left *= 1 - stay;
      at = p.parent;
    }
    odds.removeWhere((_, share) => share == 0);
    return (odds: odds, areas: areas.toList());
  }

  static RegExp _plateLine(String model) => RegExp('^\\s*${RegExp.escape(model)}\\s+\\d', caseSensitive: false);

  /// Start and end line of addoncars.ide's used_plates section, or null without one.
  static (int, int)? _usedPlates(_Lines t) {
    final start = t.lines.indexWhere((l) => l.trim().toLowerCase() == 'used_plates');
    if (start < 0) return null;
    final end = t.lines.indexWhere((l) => l.trim().toLowerCase() == 'end', start);
    return (start, end < 0 ? t.lines.length : end);
  }

  /// The plate type an add-on car starts from, or null for the default of its vehicle type.
  int? plateOf(String model) {
    final f = file(Paths.addonIde);
    if (!f.existsSync()) return null;
    final t = _Lines.read(f);
    final section = _usedPlates(t);
    if (section == null) return null;
    final line = t.lines.sublist(section.$1, section.$2).where(_plateLine(model).hasMatch).firstOrNull;
    return line == null ? null : int.tryParse(line.trim().split(RegExp(r'\s+'))[1]);
  }

  /// Writes (or with null removes) [model]'s used_plates line, adding the section when it is missing.
  static void _setPlate(_Lines t, String model, int? plate) {
    final section = _usedPlates(t);
    if (section != null) {
      for (var i = section.$2 - 1; i > section.$1; i--) {
        if (_plateLine(model).hasMatch(t.lines[i])) t.lines.removeAt(i);
      }
    }
    if (plate == null) return;
    if (section == null) _append(t, ['', 'used_plates', 'end']);
    _insertInSection(t, 'used_plates', '$model $plate');
  }

  Backup setPlate(String model, int? plate) {
    final b = backup('plate for $model', [Paths.addonIde]);
    final t = _open(Paths.addonIde);
    _setPlate(t, model, plate);
    t.write(file(Paths.addonIde));
    return b;
  }

  static Directory get _soundsDir {
    final bundled = Directory('${File(Platform.resolvedExecutable).parent.path}\\sounds');
    return bundled.existsSync() ? bundled : Directory('${Directory.current.path}\\windows\\sounds');
  }

  /// Vanilla cars' sound blocks by model: FLA's dump of the game's settings, shipped next to the exe
  /// (windows\sounds in the project when run from tests).
  static final Map<String, List<String>> _vanillaSounds = () {
    final dir = _soundsDir;
    final blocks = <String, List<String>>{};
    if (!dir.existsSync()) return blocks;
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.ini'))) {
      String? model;
      for (final line in latin1.decode(f.readAsBytesSync()).split(RegExp(r'\r?\n'))) {
        final head = RegExp(r'^\[(.+)\]').firstMatch(line)?.group(1)?.toLowerCase();
        // the first file wins when a model is in several
        if (head != null) model = blocks.containsKey(head) ? null : head;
        if (model != null && line.trim().isNotEmpty && !line.startsWith(';')) (blocks[model] ??= []).add(line.trimRight());
      }
    }
    return blocks;
  }();

  /// Cars whose sound can be cloned: add-on cars with a sound file, then the vanilla cars.
  List<String> get soundModels => {...listCars().where((c) => c.hasSound).map((c) => c.model), ..._vanillaSounds.keys}.toList();

  /// [from]'s sound block under [model]'s name; null when [from] has no sound to copy.
  List<String>? clonedSound(String from, String model) {
    from = from.trim().toLowerCase();
    if (!RegExp(r'^\w+$').hasMatch(from)) return null;
    final own = file(Paths.sound(from));
    final lines = own.existsSync()
        ? latin1.decode(own.readAsBytesSync()).split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList()
        : _vanillaSounds[from];
    if (lines == null || lines.isEmpty) return null;
    final cloned = ['[$model]', ...lines.skip(1)];
    // an episode's scanner sound does not exist in the other games, and the plugin reports that at startup
    return withSoundFields(cloned, {
      for (final f in scannerFields)
        if (episodeOf(soundField(cloned, f) ?? '') != null) f: 'NULL_SOUND',
    });
  }

  /// What the police radio says about the car: its make, model and type.
  static const scannerFields = ['policeScannerManufacturerSound', 'policeScannerModelSound', 'policeScannerVehicleCategorySound'];

  /// The sounds the base game uses for a scanner [field], which exist in every episode; "none" first.
  static List<String> scannerSounds(String field) => ['NULL_SOUND', ...?_baseScannerSounds[field]];

  static final Map<String, List<String>> _baseScannerSounds = () {
    final f = File('${_soundsDir.path}\\gtaiv_vehicleAudioSettings.ini');
    final values = {for (final k in scannerFields) k: <String>{}};
    if (f.existsSync()) {
      for (final line in latin1.decode(f.readAsBytesSync()).split(RegExp(r'\r?\n'))) {
        final m = RegExp(r'^\s*(\w+)\s*=\s*(\S+)').firstMatch(line);
        if (m != null && m[2] != 'NULL' && m[2] != 'NULL_SOUND') values[m[1]]?.add(m[2]!);
      }
    }
    return {for (final e in values.entries) e.key: e.value.toList()..sort()};
  }();

  /// 'TLAD' or 'TBoGT' for a sound that only exists in that episode (EP1_..., EP2_...), else null.
  static String? episodeOf(String sound) => sound.startsWith('EP1_') ? 'TLAD' : (sound.startsWith('EP2_') ? 'TBoGT' : null);

  static RegExp _soundLine(String field) => RegExp('^\\s*${RegExp.escape(field)}\\s*=\\s*(.*?)\\s*\$');

  static String? soundField(List<String> lines, String field) => lines.map(_soundLine(field).firstMatch).nonNulls.firstOrNull?.group(1);

  static List<String> withSoundFields(List<String> lines, Map<String, String> fields) => [
    for (final l in lines) fields.entries.where((e) => _soundLine(e.key).hasMatch(l)).map((e) => '${e.key} = ${e.value}').firstOrNull ?? l,
  ];

  /// Episodes whose sounds a block uses outside the scanner fields (an episode car's engine); such a
  /// car gives errors in the other games.
  static Set<String> episodeOnlySounds(List<String> lines) => {
    for (final l in lines)
      if (!scannerFields.any((f) => _soundLine(f).hasMatch(l))) ?episodeOf(l.split('=').skip(1).join('=').trim()),
  };

  /// An installed car's own sound block, or null without one.
  List<String>? soundLines(String model) {
    final f = file(Paths.sound(model));
    return f.existsSync() ? latin1.decode(f.readAsBytesSync()).split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList() : null;
  }

  Backup setSoundFields(String model, Map<String, String> fields) {
    final lines = soundLines(model);
    if (lines == null) throw StateError('$model has no sound file');
    final b = backup('sound of $model', [Paths.sound(model)]);
    file(Paths.sound(model)).writeAsBytesSync(latin1.encode('${withSoundFields(lines, fields).join('\r\n')}\r\n'));
    return b;
  }

  /// A vanilla car's data lines from the game's own files (the update\ copy first, then IV, TLAD,
  /// TBoGT), or null when [model] is not a vanilla car. Used to fill in what a replace mod leaves out.
  CarData? gameCar(String model) {
    List<String> lines(String name) => [
      for (final d in _gameDataDirs)
        if (file('$d/$name').existsSync()) ...latin1.decode(file('$d/$name').readAsBytesSync()).split(RegExp(r'\r?\n')),
    ];
    final re = _modelLine(model);
    final ide = lines('vehicles.ide').where((l) => _col(l, 0).toLowerCase() == model.toLowerCase()).firstOrNull;
    if (ide == null) return null;
    final handlingId = _col(ide, 3);

    String? carcols, section;
    String? cur;
    for (final l in lines('carcols.dat')) {
      final t = l.trim().toLowerCase();
      if (RegExp(r'^[a-z0-9]+$').hasMatch(t)) {
        cur = t == 'end' ? null : t; // section headers: col, car3, car4, ...
      } else if (re.hasMatch(l)) {
        (carcols, section) = (l, cur);
        break;
      }
    }
    final vehOff = <String>[];
    for (final d in _gameDataDirs) {
      if (!file('$d/vehOff.csv').existsSync()) continue;
      vehOff.addAll(latin1.decode(file('$d/vehOff.csv').readAsBytesSync()).split(RegExp(r'\r?\n')).where(re.hasMatch));
      if (vehOff.isNotEmpty) break; // one file's set, not the same lines from every copy
    }
    return CarData(
      model.toLowerCase(),
      ide,
      carcols,
      section,
      lines('handling.dat').where(_modelLine(handlingId).hasMatch).firstOrNull,
      vehOff,
      const [],
      txdParent: ModData.txdParentOf(lines('vehicles.ide'), CarData.txdOf(ide)),
    );
  }

  /// Model or handling names [car] would share with a vanilla car (any episode) or an installed add-on.
  /// vehicles.ide lines of the vanilla cars, all episodes.
  List<String> _vanillaIdeLines() => [
    for (final rel in [
      'common/data/vehicles.ide',
      'update/common/data/vehicles.ide',
      'TLAD/common/data/vehicles.ide',
      'TBoGT/common/data/vehicles.ide',
    ])
      if (file(rel).existsSync())
        ...latin1.decode(file(rel).readAsBytesSync()).split(RegExp(r'\r?\n')).where((l) => l.split(',').length > 4),
  ];

  /// The vanilla car whose in-game name uses [key] (5th .ide column), e.g. MINVAN -> minivan; null if none.
  String? vanillaCarWithNameKey(String key) =>
      _vanillaIdeLines().where((l) => nameKey(_col(l, 4)) == nameKey(key)).map((l) => _col(l, 0).toLowerCase()).firstOrNull;

  List<String> nameClashes(CarData car) {
    final ides = _vanillaIdeLines();
    final vanillaModels = {for (final l in ides) _col(l, 0).toLowerCase()};
    final vanillaHandling = {for (final l in ides) _col(l, 3).toUpperCase()};
    final addons = listCars();
    return [
      if (vanillaModels.contains(car.model)) 'model name ${car.model} is a vanilla car',
      if (addons.any((c) => c.model == car.model)) 'model name ${car.model} is already installed',
      // without a line of its own a car may use a vanilla (or another add-on's) handling line as it is
      if (car.handlingLine != null && vanillaHandling.contains(car.handlingId.toUpperCase()))
        'handling name ${car.handlingId} belongs to a vanilla car; rename it to use the handling line from the mod',
      if (car.handlingLine == null &&
          !vanillaHandling.contains(car.handlingId.toUpperCase()) &&
          !addons.any((c) => c.handlingId.toUpperCase() == car.handlingId.toUpperCase()))
        'handling.dat: no line for ${car.handlingId}',
    ];
  }

  /// Installs one car. [wtdName] is the texture dictionary the .ide line asks for (2nd column).
  Backup install(CarData car, Uint8List wft, Uint8List wtd, {String? displayName, String? nameKey, int? plate}) {
    final blockers = [...car.problems, ...nameClashes(car)];
    if (blockers.isNotEmpty) throw StateError(blockers.join('\n'));
    car = withOwnNameKey(car, displayName, ownKey: nameKey);
    final ideLine = car.ideLine!;
    final gameName = car.gameName;
    final named = displayName != null && displayName.trim().isNotEmpty;
    final txd = _col(ideLine, 1).toLowerCase();

    final touched = [
      Paths.addonIde,
      Paths.carcols,
      Paths.handling,
      Paths.vehOff,
      Paths.archive(car.model),
      if (named) Paths.names,
      if (car.audioLines.isNotEmpty) Paths.sound(car.model),
    ];
    final b = backup('install ${car.model}', touched);

    final re = _modelLine(car.model);
    void edit(String rel, void Function(_Lines) change, {RegExp? already}) {
      final t = _open(rel);
      if (t.lines.any((already ?? re).hasMatch)) return; // leftover lines from an earlier install
      change(t);
      t.write(file(rel));
    }

    edit(Paths.addonIde, (t) {
      _insertInSection(t, 'cars', ideLine);
      // shortcut: remove() drops this line by model name, so a txd named differently leaves its line behind
      if (car.txdpLine != null) {
        if (!t.lines.any((l) => l.trim().toLowerCase() == 'txdp')) _append(t, ['', 'txdp', 'end']);
        _insertInSection(t, 'txdp', car.txdpLine!);
      }
      if (plate != null && libertyPlates) _setPlate(t, car.model, plate);
    });
    edit(Paths.carcols, (t) => _insertInSection(t, car.carcolsSection!, car.carcolsLine!));
    if (car.handlingLine != null) edit(Paths.handling, (t) => _insertHandling(t, car.handlingLine!), already: _modelLine(car.handlingId));
    edit(Paths.vehOff, (t) => _append(t, car.vehOffLines));

    if (car.audioLines.isNotEmpty) {
      final s = file(Paths.sound(car.model));
      s.parent.createSync(recursive: true);
      s.writeAsBytesSync(latin1.encode('${car.audioLines.join('\r\n')}\r\n'));
    }
    final img = buildImg([ImgFile('${car.model}.wft', wft), ImgFile('$txd.wtd', wtd)]);
    final a = file(Paths.archive(car.model));
    a.parent.createSync(recursive: true);
    a.writeAsBytesSync(img);
    if (named) _setName(gameName, displayName);
    return b;
  }

  // ---------------------------------------------------------------- traffic groups

  /// The episode's car groups: the update\ copy if it exists, else the game's own file.
  CarGroups readCarGroups(Episode e) {
    final f = file(e.carGroups).existsSync() ? file(e.carGroups) : file(e.originalCarGroups);
    return CarGroups.parse(latin1.decode(f.readAsBytesSync()));
  }

  Backup saveCarGroups(Episode e, CarGroups groups, String action) {
    final b = backup(action, [e.carGroups]);
    final f = file(e.carGroups);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(latin1.encode(groups.toString()));
    return b;
  }

  /// Adds [models] to (true) or removes them from (false) groups by index, per episode. Every episode is
  /// edited in memory first (adding to a full group throws), so nothing is written unless all of it fits.
  void setTrafficGroups(List<String> models, Map<Episode, Map<int, bool>> changes) {
    final edited = <Episode, CarGroups>{};
    for (final MapEntry(key: e, value: groups) in changes.entries) {
      if (groups.isEmpty) continue;
      final g = readCarGroups(e);
      for (final MapEntry(key: i, value: add) in groups.entries) {
        for (final m in models) {
          add ? g.add(i, m) : g.remove(i, m);
        }
      }
      edited[e] = g;
    }
    for (final MapEntry(key: e, value: g) in edited.entries) {
      saveCarGroups(e, g, 'traffic groups for ${models.join(', ')}, ${e.name}');
    }
  }

  /// Traffic groups (per episode) that list [model].
  Map<Episode, List<String>> trafficGroupsOf(String model) => {
    for (final e in Episode.values)
      if (file(e.carGroups).existsSync() || file(e.originalCarGroups).existsSync())
        e: [
          for (final g in readCarGroups(e).groups)
            if (g.models.any((m) => m.toLowerCase() == model)) g.name,
        ],
  };

  Backup remove(String model) {
    final cars = listCars();
    final car = cars.firstWhere((c) => c.model == model);
    final others = cars.where((c) => c.model != model);
    // never drop a vanilla car's handling line, even when only this add-on pointed at it
    final dropHandling =
        !others.any((c) => c.handlingId.toUpperCase() == car.handlingId.toUpperCase()) &&
        !_vanillaIdeLines().any((l) => _col(l, 3).toUpperCase() == car.handlingId.toUpperCase());
    final dropName = !others.any((c) => c.gameName.toUpperCase() == car.gameName.toUpperCase());
    final inTraffic = [
      for (final e in Episode.values)
        if (file(e.carGroups).existsSync()) e,
    ];

    final b = backup('remove $model', [
      Paths.addonIde,
      Paths.carcols,
      Paths.handling,
      Paths.vehOff,
      Paths.names,
      Paths.sound(model),
      Paths.archive(model),
      for (final e in inTraffic) e.carGroups,
    ]);
    for (final e in inTraffic) {
      final groups = readCarGroups(e);
      for (final g in groups.groups) {
        groups.remove(g.index, model);
      }
      file(e.carGroups).writeAsBytesSync(latin1.encode(groups.toString()));
    }
    final re = _modelLine(model);
    for (final rel in [Paths.addonIde, Paths.carcols, Paths.vehOff, if (dropHandling) Paths.handling]) {
      final f = file(rel);
      if (!f.existsSync()) continue;
      final t = _Lines.read(f);
      t.lines.removeWhere(rel == Paths.handling ? _modelLine(car.handlingId).hasMatch : re.hasMatch);
      t.write(f);
    }
    if (dropName && file(Paths.names).existsSync()) _setName(car.gameName, null);
    for (final rel in [Paths.sound(model), Paths.archive(model)]) {
      if (file(rel).existsSync()) file(rel).deleteSync();
    }
    return b;
  }

  /// Sets the in-game name. A car borrowing a vanilla name key first gets its own key; [ownKey] is
  /// a key typed by hand instead (cut to 8 characters).
  Backup rename(String model, String displayName, {String? ownKey}) {
    final cars = listCars();
    final car = cars.firstWhere((c) => c.model == model);
    final others = cars.where((c) => c.model != model);
    final borrowed = borrowsVanillaName(model, car.gameName, car.handlingId, otherModels: others.map((c) => c.model));
    final old = car.gameName;
    final key = ownKey != null && ownKey.trim().isNotEmpty ? nameKey(ownKey.trim()) : (borrowed ? nameKey(model) : old);
    final b = backup('rename $model', [Paths.names, if (key != old) Paths.addonIde]);
    if (key != old) {
      final t = _Lines.read(file(Paths.addonIde));
      final re = _modelLine(model);
      t.lines = [for (final l in t.lines) re.hasMatch(l) ? _withGameName(l, key) : l];
      t.write(file(Paths.addonIde));
      // the name under the old key goes once no add-on car shows it any more
      final unused = vanillaCarWithNameKey(old) == null && !others.any((c) => nameKey(c.gameName) == nameKey(old));
      if (unused && file(Paths.names).existsSync()) _setName(old, null);
    }
    _setName(key, displayName);
    return b;
  }
}
