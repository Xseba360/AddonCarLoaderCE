import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'readme.dart';

/// A downloaded add-on car mod (.zip): its data-lines files and the .wft/.wtd variants inside.
class ModPackage {
  ModPackage._(this.files, this.sources);

  /// Zip entries by path (forward slashes).
  final Map<String, Uint8List> files;

  /// For each model, the data-lines file that defines it.
  final Map<String, (String path, ModData data)> sources;

  /// Models with data lines, then models that only have a .wft (replace mods without data lines).
  List<String> get models => [
    ...sources.keys,
    ...{
      for (final p in files.keys)
        if (_base(p).endsWith('.wft')) _base(p).substring(0, _base(p).length - 4),
    }.where((m) => !sources.containsKey(m)),
  ];

  static ModPackage open(Uint8List zip) => _fromFiles({
    for (final f in ZipDecoder().decodeBytes(zip).files)
      if (f.isFile) f.name.replaceAll('\\', '/'): f.content,
  });

  static const extensions = ['zip', '7z', 'rar'];

  /// The bundled 7-Zip: next to the app's exe, or windows\7zip in the project when run from tests.
  static String get sevenZip {
    final bundled = '${File(Platform.resolvedExecutable).parent.path}\\7zip\\7z.exe';
    return File(bundled).existsSync() ? bundled : '${Directory.current.path}\\windows\\7zip\\7z.exe';
  }

  /// A .zip is read in memory; .7z and .rar are unpacked by the bundled 7-Zip into a temp folder
  /// (7-Zip drops absolute and '..' paths) that is deleted afterwards.
  static Future<ModPackage> openArchive(Uint8List bytes, String name) async {
    final ext = name.toLowerCase().split('.').last;
    if (ext == 'zip') return open(bytes);
    if (!extensions.contains(ext)) throw FormatException('Not a .zip, .7z or .rar: $name');
    final tmp = Directory.systemTemp.createTempSync('addoncar_mod');
    try {
      final archive = File('${tmp.path}\\mod.$ext')..writeAsBytesSync(bytes);
      final out = '${tmp.path}\\out';
      // -p_ : a password-protected archive fails instead of waiting for a password prompt
      final r = await Process.run(sevenZip, ['x', archive.path, '-o$out', '-y', '-bd', '-p_']);
      if (r.exitCode != 0) throw FormatException('Could not unpack $name: ${'${r.stdout}${r.stderr}'.trim().split('\n').last}');
      final root = out.length + 1;
      return _fromFiles({
        for (final f in Directory(out).listSync(recursive: true).whereType<File>())
          f.path.substring(root).replaceAll('\\', '/'): f.readAsBytesSync(),
      });
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  static ModPackage _fromFiles(Map<String, Uint8List> files) {
    final sources = <String, (String, ModData)>{};
    final txts = files.keys.where((p) => p.toLowerCase().endsWith('.txt')).toList()..sort((a, b) => a.length.compareTo(b.length));
    for (final p in txts) {
      final data = ModData.parse(latin1.decode(files[p]!));
      if (data == null) continue;
      for (final m in data.models) {
        sources.putIfAbsent(m, () => (p, data));
      }
    }
    final pkg = ModPackage._(files, sources);
    if (pkg.models.isEmpty) throw const FormatException('No data lines and no .wft model in this archive.');
    return pkg;
  }

  CarData car(String model) {
    final c = sources[model]?.$2.car(model) ?? CarData.empty(model);
    if (c.handlingLine != null || c.handlingId.isEmpty) return c;
    // a variant may use a sibling's handling line (car4 -> CAR3); installing either writes it once
    final id = RegExp('^\\s*${RegExp.escape(c.handlingId)}\\s', caseSensitive: false);
    final line = sources.values.expand((s) => s.$2.sections['handling'] ?? const <String>[]).where(id.hasMatch).firstOrNull;
    if (line == null) return c;
    return CarData(
      c.model,
      c.ideLine,
      c.carcolsLine,
      c.carcolsSection,
      line,
      c.vehOffLines,
      c.audioLines,
      notes: c.notes,
      fromGame: c.fromGame,
      txdParent: c.txdParent,
    );
  }

  static String _base(String p) => p.split('/').last.toLowerCase();

  /// Model files for [model] (exact name), and texture files for its txd (txd.wtd or txd_*.wtd variants).
  List<String> modelVariants(String model) => [
    for (final p in files.keys)
      if (_base(p) == '$model.wft') p,
  ]..sort(_byLength);

  List<String> textureVariants(String model) {
    final txd = _txd(model);
    // txd.wtd or variants like car_usdm.wtd; not car2.wtd for txd "car"
    return [
      for (final p in files.keys)
        if (_base(p) == '$txd.wtd' || (_base(p).startsWith('${txd}_') && _base(p).endsWith('.wtd'))) p,
    ]..sort(_byLength);
  }

  String _txd(String model) {
    final cols = (car(model).ideLine ?? '').split(',');
    return cols.length > 1 ? cols[1].trim().toLowerCase() : model;
  }

  static int _byLength(String a, String b) => a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b);

  /// LibertyPlates (current, not LEGACY) model when that mod is installed, else the plain one.
  String? defaultModel(String model, {required bool libertyPlates}) {
    final v = modelVariants(model);
    bool lp(String p) => p.toLowerCase().contains('libertyplates') && !p.toLowerCase().contains('legacy');
    return v.where((p) => lp(p) == libertyPlates).firstOrNull ?? v.firstOrNull;
  }

  /// The texture named exactly like the txd, nearest the zip root.
  String? defaultTexture(String model) {
    final v = textureVariants(model);
    return v.where((p) => _base(p) == '${_txd(model)}.wtd').firstOrNull ?? v.firstOrNull;
  }
}
