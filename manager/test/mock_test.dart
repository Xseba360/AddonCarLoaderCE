// Core checks that need no game: they run against the mock folder from mock_game.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:addon_car_manager/core/locate.dart';
import 'package:addon_car_manager/core/manager.dart';
import 'package:addon_car_manager/core/mod_package.dart';
import 'package:addon_car_manager/core/readme.dart';
import 'package:addon_car_manager/core/update.dart';
import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'mock_game.dart';

void main() {
  Directory game({String version = AddonCarManager.supportedVersion, bool mods = true, bool car = true}) {
    final dir = mockGame(version: version, mods: mods, car: car);
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('game checks: exe version, FusionFix, the plugin under its old and new name', () {
    final bare = AddonCarManager(game(mods: false).path);
    expect(bare.looksLikeGame, isTrue);
    expect(bare.gameVersion, '1.2.0.59');
    expect(bare.fusionFixInstalled, isFalse);
    expect(bare.pluginInstalled, isFalse);
    expect(AddonCarManager(game(version: '1.0.7.0', mods: false).path).gameVersion, '1.0.7.0');

    final m = AddonCarManager(game().path);
    expect([m.fusionFixInstalled, m.pluginInstalled, m.libertyPlates], [true, true, true]);
    m.file('plugins/${Paths.plugin}').renameSync(m.file(Paths.plugin).path); // the ASI loader reads the game folder too
    expect(m.pluginInstalled, isTrue);

    File('${bare.root}/GTAIV.exe').writeAsBytesSync([1, 2, 3]);
    expect(AddonCarManager(bare.root).gameVersion, isNull);
  });

  test('one-click plugin install: next to FusionFix, undone by its backup', () {
    final m = AddonCarManager(game(car: false).path);
    final shipped = AddonCarManager.bundledPlugin.readAsBytesSync();
    m.file('plugins/${Paths.plugin}').deleteSync();
    m.file('scripts/x').parent.createSync();
    m.file('plugins/${Paths.fusionFix}').renameSync(m.file('scripts/${Paths.fusionFix}').path);
    expect(m.pluginInstalled, isFalse);

    final b = m.installPlugin();
    expect(m.file('scripts/${Paths.plugin}').readAsBytesSync(), shipped);
    m.installPlugin(); // again: same place, no second copy
    expect(m.file('plugins/${Paths.plugin}').existsSync(), isFalse);

    m.restore(m.listBackups().firstWhere((x) => x.dir.path == b.dir.path));
    expect(m.pluginInstalled, isFalse);
  }, skip: AddonCarManager.bundledPlugin.existsSync() ? null : 'build the plugin first (build.bat)');

  test('update check: release JSON and version order', () {
    expect(parseRelease('{"tag_name": "v0.2.0", "html_url": "https://example.test/r"}'), ('0.2.0', 'https://example.test/r'));
    expect(isNewer('0.2.0', '0.1.0'), isTrue);
    expect(isNewer('0.10.0', '0.9.2'), isTrue);
    expect(isNewer('1.0', '1.0.0'), isFalse);
    expect(isNewer('0.1.0', '0.1.0'), isFalse);
    expect(isNewer('0.1.0', '0.2.0'), isFalse);
    expect(isNewer('0.2.0-beta', '0.1.9'), isTrue);
  });

  test('game folders are found through the registry keys and the Steam library list', () {
    final steam = Directory.systemTemp.createTempSync('mock_steam');
    addTearDown(() => steam.deleteSync(recursive: true));
    File touch(String path) => File(path)..createSync(recursive: true);
    // a Steam library on another drive, known only to libraryfolders.vdf
    final library = '${steam.path}\\Library';
    touch('$library\\steamapps\\common\\Grand Theft Auto IV\\GTAIV\\GTAIV.exe');
    touch('${steam.path}\\steamapps\\libraryfolders.vdf').writeAsStringSync(
      '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"${steam.path.replaceAll(r'\', r'\\')}"\n\t}\n'
      '\t"1"\n\t{\n\t\t"path"\t\t"${library.replaceAll(r'\', r'\\')}"\n\t\t"apps"\n\t\t{\n\t\t\t"12210"\t\t"1"\n\t\t}\n\t}\n}\n',
    );
    // a launcher install with the exe in the folder the key names
    final launcher = '${steam.path}\\Rockstar\\Grand Theft Auto IV';
    touch('$launcher\\GTAIV.exe');

    final keys = {
      r'HKCU\Software\Valve\Steam SteamPath': steam.path.replaceAll(r'\', '/'), // Steam writes forward slashes
      r'HKLM\SOFTWARE\WOW6432Node\Rockstar Games\Grand Theft Auto IV InstallFolder': '$launcher\\',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 12210 InstallLocation': r'X:\moved\away', // stale
    };
    expect(findGameFolders(registry: (key, value) => keys['$key $value']), [
      launcher,
      '$library\\steamapps\\common\\Grand Theft Auto IV\\GTAIV',
    ]);
    expect(findGameFolders(registry: (_, _) => null), isEmpty);
  });

  test('a mod installs into the mock game, removes and restores byte for byte', () {
    final m = AddonCarManager(game().path);
    final car = m.listCars().single;
    expect([car.model, car.displayName, car.gameName, car.complete, car.hasSound], ['mockgt', 'Mock GT', 'MOCKGT', true, true]);
    expect(m.readNames(), {'MOCKGT': 'Mock GT'});
    expect(m.file('common/data/handling.dat').readAsStringSync(), isNot(contains('MOCKGT')), reason: 'only update\\ is written');

    final watched = [
      Paths.addonIde,
      Paths.carcols,
      Paths.handling,
      Paths.vehOff,
      Paths.names,
      Paths.sound('mockgt'),
      Paths.archive('mockgt'),
    ];
    final before = {for (final p in watched) p: m.file(p).readAsBytesSync()};
    final b = m.remove('mockgt');
    expect(m.listCars(), isEmpty);
    expect(m.file(Paths.archive('mockgt')).existsSync(), isFalse);
    m.restore(m.listBackups().firstWhere((x) => x.dir.path == b.dir.path));
    for (final p in watched) {
      expect(m.file(p).readAsBytesSync(), before[p], reason: p);
    }
  });

  test('name keys: typed by hand, cut to 8 characters, sharers are reported', () {
    final m = AddonCarManager(game().path);
    final second = ModPackage.open(mockMod(model: 'mockgtx2', nameKey: 'MOCKGTX2')).car('mockgtx2');
    expect(m.withOwnNameKey(second, 'Mock GT X').gameName, 'MOCKGTX2');
    expect(m.withOwnNameKey(second, 'Mock GT X', ownKey: 'mygtxlong').gameName, 'MYGTXLON');
    expect(m.nameKeySharers('MOCKGTX2', 'mockgtx2', named: true), isEmpty);
    expect(m.nameKeySharers('mockgt', 'mockgtx2', named: false), ['mockgt']);
    expect(m.nameKeySharers('SULTAN', 'mockgtx2', named: false), isEmpty, reason: 'borrowing a vanilla name is fine');
    expect(m.nameKeySharers('SULTAN', 'mockgtx2', named: true), ['sultan'], reason: 'naming it renames the Sultan');
    expect(m.nameKeySharers('WASHINGTON', 'mockgtx2', named: true), ['washington']);

    final pkg = ModPackage.open(mockMod(model: 'mockgtx2', nameKey: 'MOCKGTX2'));
    m.install(second, pkg.files['Mock GT/mockgtx2.wft']!, pkg.files['Mock GT/mockgtx2.wtd']!, displayName: 'Mock GT X', nameKey: 'gtx');
    expect(m.listCars().last.gameName, 'GTX');
    expect(m.readNames(), {'MOCKGT': 'Mock GT', 'GTX': 'Mock GT X'});

    // moving it onto the first car's key: one name for both, and the old key's name goes
    m.rename('mockgtx2', 'Mock GT pair', ownKey: 'MOCKGT');
    expect(m.listCars().map((c) => c.gameName), ['MOCKGT', 'MOCKGT']);
    expect(m.readNames(), {'MOCKGT': 'Mock GT pair'});
    // back to a key of its own: the shared name stays with the other car
    m.rename('mockgtx2', 'Mock GT X', ownKey: 'gtx');
    expect(m.readNames(), {'MOCKGT': 'Mock GT pair', 'GTX': 'Mock GT X'});
    m.rename('mockgtx2', 'Renamed'); // no key given: it keeps the one it has
    expect(m.readNames()['GTX'], 'Renamed');
  });

  test('a txdp line in the readme is not a second car line; it is installed and removed with the car', () {
    final m = AddonCarManager(game().path);
    final pkg = ModPackage.open(mockMod(model: 'mocktruck', nameKey: 'MOCKTRK', txdParent: 'vehshare_truck'));
    final truck = pkg.car('mocktruck');
    expect(truck.problems, isEmpty);
    expect(truck.txdParent, 'vehshare_truck');
    expect(pkg.car('mocktruck').renamed(model: 'bigtruck', handlingId: 'BIGTRUCK').txdpLine, 'bigtruck, vehshare_truck');
    expect(ModPackage.open(mockMod()).car('mockgt').txdpLine, isNull);

    m.install(truck, pkg.files['Mock GT/mocktruck.wft']!, pkg.files['Mock GT/mocktruck.wtd']!);
    final ide = m.file(Paths.addonIde);
    expect(ide.readAsStringSync(), contains('txdp\r\nmocktruck, vehshare_truck\r\nend'));
    expect(m.listCars().map((c) => c.model), ['mockgt', 'mocktruck'], reason: 'the txdp line is not a car');
    m.remove('mocktruck');
    expect(ide.readAsStringSync(), isNot(contains('mocktruck')));
    expect(m.listCars().map((c) => c.model), ['mockgt']);

    // a replace mod of a vanilla truck keeps the vanilla parent
    expect(m.gameCar('minivan')!.txdParent, 'vehshare_truck');
    expect(m.gameCar('sultan')!.txdParent, isNull);
    expect(
      CarData.empty('minivan').filledFrom(m.gameCar('minivan')!).renamed(model: 'minivan2', handlingId: 'MINIVAN2').txdpLine,
      'minivan2, vehshare_truck',
    );
  });

  test('renaming rewrites every data line; clashes with vanilla and installed cars are reported', () {
    final m = AddonCarManager(game().path);
    final orig = ModPackage.open(mockMod(model: 'mockgtx2', nameKey: 'MOCKGT')).car('mockgtx2');
    final car = orig.renamed(model: 'Renamed', handlingId: 'renamed');
    expect(car.model, 'renamed');
    expect(car.handlingId, 'RENAMED');
    // the name key was not the car's own, so it stays
    expect(car.ideLine!.split(',').take(5).map((c) => c.trim()), ['renamed', 'renamed', 'car', 'RENAMED', 'MOCKGT']);
    expect(car.carcolsLine, startsWith('renamed,'));
    expect(car.handlingLine, startsWith('RENAMED '));
    expect(car.vehOffLines, everyElement(startsWith('VEHICLE renamed ')));
    expect(car.audioLines.first, '[renamed]');
    for (final l in [car.ideLine!, car.carcolsLine!, car.handlingLine!, ...car.vehOffLines, ...car.audioLines]) {
      expect(l.toLowerCase(), isNot(contains('mockgtx2')));
    }
    expect(car.problems, isEmpty);
    expect(orig.renamed(model: 'bad name', handlingId: 'X').problems, isNotEmpty);

    expect(m.nameClashes(car), isEmpty);
    expect(m.nameClashes(orig.renamed(model: 'sultan', handlingId: 'RENAMED')), ['model name sultan is a vanilla car']);
    expect(m.nameClashes(orig.renamed(model: 'mockgt', handlingId: 'RENAMED')), ['model name mockgt is already installed']);
    expect(m.nameClashes(orig.renamed(model: 'renamed', handlingId: 'SULTAN')), [
      'handling name SULTAN belongs to a vanilla car; rename it to use the handling line from the mod',
    ]);

    // without a handling line of its own a car may sit on a vanilla one, but not on one nothing defines
    CarData shared(String handling) =>
        CarData('shared', car.ideLine!.replaceAll('RENAMED', handling), car.carcolsLine, 'car4', null, car.vehOffLines, const []);
    expect(m.nameClashes(shared('SULTAN')), isEmpty);
    expect(m.nameClashes(shared('NOSUCHLINE')), ['handling.dat: no line for NOSUCHLINE']);
  });

  test('mod packages: variants, the LibertyPlates default, a .wft-only zip', () {
    final pkg = ModPackage.open(mockMod());
    expect(pkg.models, ['mockgt']);
    expect(pkg.sources['mockgt']!.$1, 'Mock GT/ReadME.txt');
    expect(pkg.modelVariants('mockgt'), ['Mock GT/mockgt.wft', 'Mock GT/LibertyPlates/mockgt.wft']);
    expect(pkg.defaultModel('mockgt', libertyPlates: true), 'Mock GT/LibertyPlates/mockgt.wft');
    expect(pkg.defaultModel('mockgt', libertyPlates: false), 'Mock GT/mockgt.wft');
    expect(pkg.defaultTexture('mockgt'), 'Mock GT/mockgt.wtd');

    final bare = Archive()
      ..add(ArchiveFile.bytes('Sultan Tuned/sultan.wft', [0, 0, 0, 0]))
      ..add(ArchiveFile.bytes('Sultan Tuned/sultan.wtd', [0, 0, 0, 0]));
    final replace = ModPackage.open(Uint8List.fromList(ZipEncoder().encodeBytes(bare)));
    expect(replace.models, ['sultan']);
    expect(replace.car('sultan').problems, isNotEmpty);
    final m = AddonCarManager(game().path);
    final filled = replace
        .car('sultan')
        .filledFrom(m.gameCar('sultan')!)
        .renamed(model: 'sultan2', handlingId: 'SULTAN2', keepNameKey: true);
    expect(filled.gameName, 'SULTAN');
    expect(filled.fromGame, {'ide', 'carcols', 'handling', 'vehoff'});
    expect([...filled.problems, ...m.nameClashes(filled)], isEmpty);
    // typing a name moves a borrowed vanilla key to the car's own
    expect(m.withOwnNameKey(filled, '').gameName, 'SULTAN');
    expect(m.withOwnNameKey(filled, 'Sultan Tuned').gameName, 'SULTAN2');
  });

  test('an episode without cargrp.dat has no traffic groups instead of failing', () {
    final m = AddonCarManager(game().path);
    m.file(Episode.tlad.originalCarGroups).deleteSync();
    expect(m.readCarGroups(Episode.tlad).groups, isEmpty);
    expect(m.readCarGroups(Episode.iv).groups, hasLength(47));
    expect(m.trafficGroupsOf('mockgt').keys, [Episode.iv, Episode.tbogt]);
    m.setTrafficGroups(
      ['mockgt'],
      {
        Episode.iv: {0: true},
        Episode.tlad: {},
      },
    );
    expect(m.trafficGroupsOf('mockgt')[Episode.iv], ['Harlem']);
    m.remove('mockgt'); // walks every episode's groups
  });

  test('replace mods take the missing lines from the game files', () {
    final m = AddonCarManager(game().path);
    expect(m.gameCar('mockgt'), isNull);
    expect(m.vanillaCarWithNameKey('MINVAN'), 'minivan');
    final v = m.gameCar('sultan')!;
    expect(v.problems, isEmpty);
    expect(v.carcolsSection, 'car4');
    expect(m.gameCar('minivan')!.carcolsSection, 'car3');
    expect(m.nameClashes(v), contains('model name sultan is a vanilla car'));
  });
}
