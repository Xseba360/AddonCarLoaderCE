// Core checks on the mock game folder (mock_game.dart). Two more read the real game's own data
// files and are skipped unless GTA4_ROOT is set to the game folder (the one with GTAIV.exe).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:addon_car_manager/core/cargrp.dart';
import 'package:addon_car_manager/core/manager.dart';
import 'package:addon_car_manager/core/mod_package.dart';
import 'package:addon_car_manager/core/readme.dart';
import 'package:test/test.dart';

import 'mock_game.dart';

final game = Platform.environment['GTA4_ROOT'] ?? '';
final haveGame = game.isNotEmpty && File('$game\\GTAIV.exe').existsSync();

void main() {
  final mock = mockGame();
  tearDownAll(() => mock.deleteSync(recursive: true));

  test('car3/car4 is detected from the colour groups: every vanilla line agrees', () {
    expect(CarData.carcolsSectionOf('mockgt, 0,0,9,0, 0,0,9,133, 11,11,11,133, 31,0,9,133, 34,34,34,133,'), 'car4');
    expect(CarData.carcolsSectionOf('mockgt,\t\t0,10,9, 7,7,97, 3,3,13, 4,4,25, 6,6,80, 11,11,108,'), 'car3');
    var checked = 0;
    for (final ep in ['', 'TLAD/', 'TBoGT/']) {
      String? section;
      for (final l in File('$game/${ep}common/data/carcols.dat').readAsLinesSync(encoding: latin1)) {
        final t = l.trim().toLowerCase();
        if (RegExp(r'^[a-z0-9]+$').hasMatch(t)) {
          section = t == 'end' ? null : t;
        } else if ((section == 'car3' || section == 'car4') && RegExp(r'^[a-z0-9_]+\s*,').hasMatch(t)) {
          expect(CarData.carcolsSectionOf(l), section, reason: '$ep $l');
          checked++;
        }
      }
    }
    expect(checked, greaterThan(100));
  }, skip: !haveGame);

  test('a sound block is cloned from a vanilla or an add-on car under the new name', () {
    final m = AddonCarManager(mock.path);
    final sultan = m.clonedSound('Sultan', 'mockgt')!;
    expect(sultan.first, '[mockgt]');
    expect(sultan.where((l) => l.startsWith('engineLowSound')), hasLength(1));
    expect(sultan.where((l) => l.startsWith('[')), hasLength(1));
    expect(m.clonedSound('hexer', 'x'), isNotNull); // TLAD
    expect(m.clonedSound('nosuchcar', 'x'), isNull);
    expect(m.clonedSound(r'..\x', 'x'), isNull);
    expect(m.soundModels, containsAll(['sultan', 'admiral']));
    for (final c in m.listCars().where((c) => c.hasSound)) {
      expect(m.clonedSound(c.model, 'x')!.first, '[x]');
    }
  });

  test('LibertyCityPlates: plate types are read, a plate line goes into addoncars.ide only', () {
    final tmp = Directory.systemTemp.createTempSync('addoncars_plates');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final m = AddonCarManager(tmp.path);
    final data = Directory('${tmp.path}/update/common/data')..createSync(recursive: true);
    File('${data.path}/vehicles.ide').writeAsStringSync(mockPlates);
    const car = 'mockgt, mockgt, car, MOCKGT, FEROCI, VEH@STD, NULL, 30';
    final ide = File('${data.path}/addoncars.ide')..writeAsStringSync('cars\n$car\nend\n');
    expect(m.plateTypes(), isEmpty, reason: 'LibertyCityPlates.asi is not installed');

    File('${tmp.path}/plugins/LibertyCityPlates.asi').createSync(recursive: true);
    // taxi has no parent; 1986 stays on rolls 0..15 of 0..99
    // the shown share is the final one: 2008 keeps 86% of rolls, and the 2008 <-> alderney-in-lc loop
    // returns most of the rest to it, 0.86 / (1 - 0.14 * 0.84) = 97%
    expect(m.plateTypes(), [(16, 'taxi', 100), (23, 'liberty 2008', 97), (24, 'alderney in lc', 18), (26, 'liberty 1986', 16)]);
    expect(m.plateOdds(16).odds, {'taxi': 1.0});
    // 1986 keeps 16%; the rest goes to the default car plate: Alderney's inside its area (85%), else the
    // 2008 <-> alderney-in-lc loop, where 2008 stays 86% and takes 0.86 / (1 - 0.14 * 0.84) of what arrives
    final out = m.plateOdds(26), inside = m.plateOdds(26, inAreas: true);
    expect(out.areas, ['alderney']);
    expect(out.odds.keys, ['liberty 1986', 'liberty 2008', 'alderney in lc']);
    expect(out.odds['liberty 1986'], closeTo(0.16, 1e-9));
    expect(out.odds['liberty 2008'], closeTo(0.84 * 0.86 / (1 - 0.14 * 0.84), 1e-4));
    expect(out.odds.values.reduce((a, b) => a + b), closeTo(1, 1e-4));
    expect(inside.odds['alderney'], closeTo(0.84 * 0.85, 1e-9));
    expect(inside.odds.values.reduce((a, b) => a + b), closeTo(1, 1e-4));
    expect(m.plateOf('mockgt'), isNull);
    m.setPlate('mockgt', 26);
    expect(m.plateOf('mockgt'), 26);
    expect(ide.readAsStringSync().trimRight(), 'cars\n$car\nend\n\nused_plates\nmockgt 26\nend');
    m.setPlate('mockgt', 16);
    expect(ide.readAsStringSync().trimRight(), 'cars\n$car\nend\n\nused_plates\nmockgt 16\nend');
    expect(m.listCars().map((c) => c.model), ['mockgt']);
    m.setPlate('mockgt', null);
    expect(m.plateOf('mockgt'), isNull);
    expect(ide.readAsStringSync(), contains(car));
    expect(File('${data.path}/vehicles.ide').readAsStringSync(), contains('used_plates\ntaxi 16\nend'));
  });

  test('police scanner sounds: an episode-only one is dropped from a clone; fields can be set', () {
    final m = AddonCarManager(mock.path);
    final gburrito = m.clonedSound('gburrito', 'mockgt')!; // TLAD: EP1_SFX_E1_SCANNER_MODELS_E1_SCANNER_GANG_BURRITO
    expect(AddonCarManager.soundField(gburrito, 'policeScannerModelSound'), 'NULL_SOUND');
    expect(AddonCarManager.soundField(gburrito, 'policeScannerVehicleCategorySound'), 'POLICE_SCANNER_VEHICLE_CATEGORY_VAN');
    expect(AddonCarManager.episodeOnlySounds(gburrito), isEmpty);
    expect(AddonCarManager.episodeOnlySounds(m.clonedSound('hexer', 'x')!), isNotEmpty); // an episode bike engine

    final models = AddonCarManager.scannerSounds('policeScannerModelSound');
    expect(models.first, 'NULL_SOUND');
    expect(models, contains('POLICE_SCANNER_MODEL_MOD_BURRITO'));
    expect(models.where((s) => AddonCarManager.episodeOf(s) != null), isEmpty);
    final set = AddonCarManager.withSoundFields(gburrito, {'policeScannerModelSound': 'POLICE_SCANNER_MODEL_MOD_BURRITO'});
    expect(AddonCarManager.soundField(set, 'policeScannerModelSound'), 'POLICE_SCANNER_MODEL_MOD_BURRITO');
    expect(set.length, gburrito.length);

    final tmp = Directory.systemTemp.createTempSync('addoncars_scanner');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final t = AddonCarManager(tmp.path);
    File(t.file(Paths.sound('mockgt')).path)
      ..createSync(recursive: true)
      ..writeAsStringSync('${gburrito.join('\r\n')}\r\n');
    t.setSoundFields('mockgt', {'policeScannerModelSound': 'POLICE_SCANNER_MODEL_MOD_BURRITO'});
    expect(AddonCarManager.soundField(t.soundLines('mockgt')!, 'policeScannerModelSound'), 'POLICE_SCANNER_MODEL_MOD_BURRITO');
    expect(t.soundLines('mockgt')!.first, '[mockgt]');
  });

  test('a name key is cut to the 8 characters the game keeps', () {
    final m = AddonCarManager(mock.path);
    CarData car(String key) =>
        CarData('longmodel', 'longmodel, longmodel, car, LONGMODE, $key, VEH@STD, NULL, 30', null, null, null, const [], const []);
    expect(m.withOwnNameKey(car('LONGMODEL'), null).gameName, 'LONGMODE');
    expect(m.withOwnNameKey(car('LONGMODEL'), 'Long Model').gameName, 'LONGMODE');
    expect(m.withOwnNameKey(car('SULTAN'), null).gameName, 'SULTAN'); // unnamed: keeps the vanilla key
    expect(m.withOwnNameKey(car('SULTAN'), 'Long Model').gameName, 'LONGMODE'); // named: own key, 8 characters
    expect(m.vanillaCarWithNameKey('WASHINGT'), 'washington');
  });

  test('.7z opens through the bundled 7-Zip; a broken .rar is refused', () async {
    // a .7z made with the same 7z.exe
    final tmp = Directory.systemTemp.createTempSync('addoncar_7z');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/Sultan Tuned/sultan.wft').createSync(recursive: true);
    File('${tmp.path}/Sultan Tuned/sultan.wtd').writeAsBytesSync([1, 2, 3]);
    final r = Process.runSync(ModPackage.sevenZip, ['a', '${tmp.path}/mod.7z', 'Sultan Tuned'], workingDirectory: tmp.path);
    expect(r.exitCode, 0, reason: '${r.stdout}');
    final pkg = await ModPackage.openArchive(File('${tmp.path}/mod.7z').readAsBytesSync(), 'Sultan Tuned.7z');
    expect(pkg.models, ['sultan']);
    expect(pkg.files['Sultan Tuned/sultan.wtd'], [1, 2, 3]);
    await expectLater(ModPackage.openArchive(Uint8List.fromList([1, 2, 3]), 'broken.rar'), throwsFormatException);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('batch traffic edit: several cars into several groups per episode; a full group writes nothing', () {
    final tmp = Directory.systemTemp.createTempSync('addoncars_traffic');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final ep in ['', 'TBoGT/']) {
      final f = File('${tmp.path}/update/${ep}common/data/cargrp.dat')..parent.createSync(recursive: true);
      f.writeAsBytesSync(File('${mock.path}/${ep}common/data/cargrp.dat').readAsBytesSync());
    }
    final m = AddonCarManager(tmp.path);
    String before(Episode e) => File('${tmp.path}/${e.carGroups}').readAsStringSync(encoding: latin1);
    final tbogtBefore = before(Episode.tbogt);

    m.setTrafficGroups(
      ['mockgt', 'mockgtx2'],
      {
        Episode.iv: {0: true, 3: true},
        Episode.tbogt: {},
      },
    );
    final iv = m.readCarGroups(Episode.iv).groups;
    expect(iv[0].models.sublist(iv[0].models.length - 2), ['mockgt', 'mockgtx2']);
    expect(iv[3].models.sublist(iv[3].models.length - 2), ['mockgt', 'mockgtx2']);
    expect(before(Episode.tbogt), tbogtBefore); // no changes there, no write
    expect(m.listBackups().length, 1);

    m.setTrafficGroups(
      ['mockgt'],
      {
        Episode.iv: {0: false},
      },
    );
    expect(m.readCarGroups(Episode.iv).groups[0].models.last, 'mockgtx2');
    expect(m.readCarGroups(Episode.iv).groups[3].models, contains('mockgt'));

    // too many cars for one group: nothing is written, not even the episode that fit
    final ivNow = before(Episode.iv);
    final many = [for (var i = 0; i < 30; i++) 'car$i'];
    expect(
      () => m.setTrafficGroups(many, {
        Episode.iv: {1: true},
        Episode.tbogt: {0: true},
      }),
      throwsStateError,
    );
    expect(before(Episode.iv), ivNow);
    expect(before(Episode.tbogt), tbogtBefore);
  });

  test('car groups: real files parse to 47 groups; add/remove only touches that line', () {
    for (final ep in ['', 'TLAD\\', 'TBoGT\\']) {
      final text = latin1.decode(File('$game\\${ep}common\\data\\cargrp.dat').readAsBytesSync());
      final g = CarGroups.parse(text);
      expect(g.groups.length, CarGroups.maxGroups, reason: ep);
      // vanilla TBoGT lists 44 in NETWORK; the game reads only the first 35 of a line
      expect(
        g.groups.where((x) => x.models.length > CarGroups.maxCarsPerGroup).map((x) => x.name),
        ep == 'TBoGT\\' ? ['Network'] : isEmpty,
        reason: ep,
      );
      expect(g.toString(), text, reason: 'round-trip $ep');
    }
    final text = latin1.decode(File('$game\\common\\data\\cargrp.dat').readAsBytesSync());
    final g = CarGroups.parse(text);
    expect(g.groups[0].name, 'Harlem');
    g.add(0, 'mockgt');
    expect(g.groups[0].models.last, 'mockgt');
    expect(g.groups[0].comment, 'POPCYCLE_GROUP_HARLEM');
    final changed = [
      for (var i = 0; i < 47; i++)
        if (g.groups[i].models.join() != CarGroups.parse(text).groups[i].models.join()) i,
    ];
    expect(changed, [0]);
    g.remove(0, 'mockgt');
    expect(g.groups[0].models, CarGroups.parse(text).groups[0].models);
    expect(g.groups.where((x) => x.multiplayerOnly).map((x) => x.index), [43]);
    expect(g.groups.where((x) => !x.areaBased).map((x) => x.name), ['Cops', 'Network', 'Boats', 'Boring Saloons', 'Only In Native Zone']);
    final network = g.groups.indexWhere((x) => x.models.length == CarGroups.maxCarsPerGroup);
    expect(() => g.add(network, 'mockgt'), throwsStateError);
  }, skip: !haveGame);
}
