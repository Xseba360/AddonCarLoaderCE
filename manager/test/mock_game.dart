// A small stand-in for a GTA IV Complete Edition folder, written into a temp folder: only the
// files the manager reads, with made-up values in the game's formats. Nothing here is game data.
import 'dart:io';
import 'dart:typed_data';

import 'package:addon_car_manager/core/manager.dart';
import 'package:addon_car_manager/core/mod_package.dart';
import 'package:archive/archive.dart';

/// (model, handling name, name key, carcols section)
const mockCars = [
  ('sultan', 'SULTAN', 'SULTAN', 'car4'),
  ('sentinel', 'SENTINEL', 'SENTINEL', 'car4'),
  ('minivan', 'MINIVAN', 'MINVAN', 'car3'),
  ('washington', 'WASHINGTON', 'WASHINGTON', 'car3'),
  ('admiral', 'ADMIRAL', 'ADMIRAL', 'car4'),
];

/// LibertyCityPlates' license_plates section, as its update\common\data\vehicles.ide has it.
const mockPlates =
    'cars\nend\nlicense_plates\n# alderney\n0 23 84 2 3 1.4 0.48 0.0 -0.02 0.0 0.0 0.0 1.0 &&&*^^& 1 -2315.0 -750 -1000.0 2100.0\n'
    '# taxi\n16 null 0 5 0\n# regular\n#8 null 0\n# liberty 2008\n23 24 85 0 0\n# alderney in lc\n24 23 15 2 3\n'
    '# liberty 1986\n26 0 15 12 0\nend\n'
    'used_plates\ntaxi 16\nend\n';

String _ide(String model, String handling, String key) =>
    '$model, $model, car, $handling, $key, VEH@STD, NULL, 30, 999, 0.2630, 0.2630, 0, 2, 1.0, 0, ext_all';
String _carcols(String model, String section) => section == 'car4' ? '$model, 0,0,9,0, 1,1,9,133,' : '$model, 0,0,1, 1,1,2,';
String _handling(String id) => '$id 1500.0 8.5 85 0.0 0.0 -0.2 0.0 5 0.2 1.0 140.0 0.3 0.65 0.7 35.0 1.4 1.2 14.5 0.15 0.48 2.0 1.5';
List<String> _vehOff(String model) => ['VEHICLE $model FIELD 0.0 0.0 0.0 0.0 0.0 0.0', 'VEHICLE $model FIELD 1.0 0.0 0.0 0.0 0.0 0.0'];

/// The 47 group lines the game reads: 42 area groups, then the ones code picks by name.
String _carGroups() {
  const special = ['COPS', 'NETWORK', 'BOATS', 'BORING_SALOONS', 'ONLY_IN_NATIVE_ZONE'];
  final lines = ['# mock cargrp.dat'];
  for (var i = 0; i < 47; i++) {
    final name = i == 0 ? 'HARLEM' : (i < 42 ? 'AREA${i + 1}' : special[i - 42]);
    final cars = switch (i) {
      1 => [for (var n = 0; n < 10; n++) 'filler$n'], // little room left
      43 => [for (var n = 0; n < 35; n++) 'net$n'], // full
      _ => ['sultan', 'admiral'],
    };
    lines.add('${cars.join(', ')},  # POPCYCLE_GROUP_$name');
  }
  return '${lines.join('\r\n')}\r\n';
}

/// A fake GTAIV.exe: just the version block the manager looks for.
Uint8List _exe(String version) {
  final v = version.split('.').map(int.parse).toList();
  final d = ByteData(64)
    ..setUint16(0, 0x5A4D, Endian.little)
    ..setUint32(32, 0xFEEF04BD, Endian.little)
    ..setUint32(36, 0x00010000, Endian.little)
    ..setUint32(40, v[0] << 16 | v[1], Endian.little)
    ..setUint32(44, v[2] << 16 | v[3], Endian.little);
  return d.buffer.asUint8List();
}

/// The smallest thing the archive builder takes for a model or texture: an RSC header and one byte.
Uint8List _resource(int content) {
  final d = ByteData(13)
    ..setUint32(0, 0x05435352, Endian.little)
    ..setUint32(4, 0x70, Endian.little)
    ..setUint8(12, content);
  return d.buffer.asUint8List();
}

/// An add-on car mod as modders zip them: a readme with the data lines, a model for plain games,
/// one for LibertyCityPlates, and a texture.
Uint8List mockMod({String model = 'mockgt', String nameKey = 'MOCKGT', String? txdParent}) {
  final up = model.toUpperCase();
  final readme = [
    'Mock GT for GTA IV',
    '',
    'vehicles.ide',
    _ide(model, up, nameKey),
    if (txdParent != null) ...[
      '',
      'You\'ll also need to add this line under the "txdp" section at the bottom of the vehicles.ide file.',
      '',
      '$model, $txdParent',
    ],
    '-----',
    'carcols.dat (car4 section)',
    _carcols(model, 'car4'),
    '-----',
    'handling.dat',
    _handling(up),
    '-----',
    'VehOff.csv',
    ..._vehOff(model),
    '-----',
    'FLA audio',
    '[$model]',
    'structType = 0',
    'engineLowSound = SULTAN_ENGINE_LOW',
    'policeScannerManufacturerSound = NULL_SOUND',
    'policeScannerModelSound = NULL_SOUND',
    'policeScannerVehicleCategorySound = POLICE_SCANNER_VEHICLE_CATEGORY_SEDAN',
  ].join('\r\n');
  final zip = Archive()
    ..add(ArchiveFile.string('Mock GT/ReadME.txt', readme))
    ..add(ArchiveFile.bytes('Mock GT/$model.wft', _resource(1)))
    ..add(ArchiveFile.bytes('Mock GT/LibertyPlates/$model.wft', _resource(2)))
    ..add(ArchiveFile.bytes('Mock GT/$model.wtd', _resource(3)));
  return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
}

/// Creates the folder. [mods] also puts the three plugins in and [car] installs [mockMod] as "Mock GT".
/// Delete it when done (addTearDown(() => dir.deleteSync(recursive: true))).
Directory mockGame({String version = AddonCarManager.supportedVersion, bool mods = true, bool car = true}) {
  final root = Directory.systemTemp.createTempSync('mock_gta4');
  void write(String rel, String text) => File('${root.path}/$rel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  File('${root.path}/GTAIV.exe').writeAsBytesSync(_exe(version));
  String section(String name) => [
    name,
    for (final c in mockCars)
      if (c.$4 == name) _carcols(c.$1, name),
    'end',
  ].join('\r\n');
  write(
    'common/data/vehicles.ide',
    '${['cars', for (final c in mockCars) _ide(c.$1, c.$2, c.$3), 'end', 'txdp', 'vehshare_truck, vehshare', 'minivan, vehshare_truck', 'end'].join('\r\n')}\r\n',
  );
  write('common/data/carcols.dat', '${['col', '0,0,0  # black', 'end', section('car3'), section('car4')].join('\r\n')}\r\n');
  write('common/data/handling.dat', '${['; mock handling.dat', for (final c in mockCars) _handling(c.$2)].join('\r\n')}\r\n');
  write('common/data/vehOff.csv', '${[for (final c in mockCars) ..._vehOff(c.$1)].join('\r\n')}\r\n');
  for (final e in Episode.values) {
    write(e.originalCarGroups, _carGroups());
  }
  if (!mods) return root;

  for (final asi in [Paths.fusionFix, Paths.libertyPlates]) {
    write('plugins/$asi', '');
  }
  // the plugin as the app ships it, so it does not count as out of date
  final shipped = AddonCarManager.bundledPlugin;
  File('${root.path}/plugins/${Paths.plugin}').writeAsBytesSync(shipped.existsSync() ? shipped.readAsBytesSync() : const []);
  write(Paths.plateTypes, mockPlates);
  if (car) {
    final pkg = ModPackage.open(mockMod());
    AddonCarManager(
      root.path,
    ).install(pkg.car('mockgt'), pkg.files['Mock GT/LibertyPlates/mockgt.wft']!, pkg.files['Mock GT/mockgt.wtd']!, displayName: 'Mock GT');
  }
  return root;
}
