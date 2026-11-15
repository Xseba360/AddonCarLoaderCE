/// Parses the data lines that add-on car mods ship in their readme or in a separate
/// "Data Lines.txt". Sections are found by their headings, in any order;
/// a sound block may also start with a bare [model] line.
class ModData {
  ModData._(this.sections, this.carcolsSection);

  final Map<String, List<String>> sections;

  /// carcols.dat section named in the heading ("car3", "car4"), or null if the heading names none.
  final String? carcolsSection;

  static const _headings = {
    'vehicles.ide': 'ide',
    'carcols.dat': 'carcols',
    'handling.dat': 'handling',
    'vehoff': 'vehoff',
    'fla audio': 'audio',
    'cargrp.dat': 'other',
  };

  /// A txdp line: a texture dictionary and its parent, nothing else.
  static final txdpLine = RegExp(r'^\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*$');

  /// The parent a txdp line in [lines] gives the texture dictionary [txd], or null.
  static String? txdParentOf(Iterable<String> lines, String txd) => lines
      .map(txdpLine.firstMatch)
      .nonNulls
      .where((m) => m.group(1)!.toLowerCase() == txd.toLowerCase())
      .map((m) => m.group(2)!.toLowerCase())
      .firstOrNull;

  /// Returns null when [text] has no vehicles.ide section (not a data-lines file).
  static ModData? parse(String text) {
    final sections = <String, List<String>>{};
    String? cur;
    String? carcols;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      final low = line.trim().toLowerCase();
      // camera lines are recognisable under any heading ("these VehOff.dat lines should also help")
      if (RegExp(r'^vehicle\s+\S+\s+field\s').hasMatch(low)) {
        (sections['vehoff'] ??= []).add(line);
        continue;
      }
      final key = _headings.entries.where((e) => low.startsWith(e.key)).map((e) => e.value).firstOrNull;
      if (key != null) {
        cur = key;
        if (key == 'carcols') carcols = RegExp(r'(car\d) section').firstMatch(low)?.group(1);
        continue;
      }
      if (low.startsWith('-----')) {
        cur = null;
        continue;
      }
      // "mytruck, vehshare_truck": the texture parent readmes ask to add to the .ide's txdp section
      if (txdpLine.hasMatch(line)) {
        (sections['txdp'] ??= []).add(line);
        continue;
      }
      if (line.startsWith('[')) cur = 'audio';
      if (cur != null && line.trim().isNotEmpty) (sections[cur] ??= []).add(line);
    }
    if (!sections.containsKey('ide')) return null;
    return ModData._(sections, carcols);
  }

  /// Model names defined in the vehicles.ide section.
  List<String> get models => [
    for (final l in sections['ide'] ?? const <String>[])
      if (RegExp(r'^\s*[A-Za-z0-9_]+\s*,').hasMatch(l)) l.split(',').first.trim().toLowerCase(),
  ];

  CarData car(String model) {
    final re = RegExp('^\\s*(vehicle\\s+)?${RegExp.escape(model)}\\s*[,\\s]', caseSensitive: false);
    List<String> mine(String key) => [
      for (final l in sections[key] ?? const <String>[])
        if (re.hasMatch(l)) l,
    ];

    final ide = mine('ide'), carcols = mine('carcols'), handling = mine('handling'), vehOff = mine('vehoff');
    final allAudio = sections['audio'] ?? const <String>[];
    final start = allAudio.indexWhere((l) => l.trim().toLowerCase() == '[${model.toLowerCase()}]');
    var audio = <String>[];
    if (start >= 0) {
      final end = allAudio.indexWhere((l) => l.startsWith('['), start + 1);
      audio = allAudio.sublist(start, end < 0 ? allAudio.length : end);
    }

    return CarData(
      model.toLowerCase(),
      ide.firstOrNull,
      carcols.firstOrNull,
      carcols.isEmpty ? carcolsSection : (CarData.carcolsSectionOf(carcols.first) ?? carcolsSection),
      handling.firstOrNull,
      vehOff,
      audio,
      txdParent: ide.isEmpty ? null : txdParentOf(sections['txdp'] ?? const [], CarData.txdOf(ide.first)),
      notes: [
        if (ide.length > 1) 'vehicles.ide: expected 1 line, found ${ide.length}',
        if (carcols.length > 1) 'carcols.dat: expected 1 line, found ${carcols.length}',
        if (handling.length > 1) 'handling.dat: expected 1 line, found ${handling.length}',
      ],
    );
  }
}

class CarData {
  CarData(
    this.model,
    this.ideLine,
    this.carcolsLine,
    this.carcolsSection,
    this.handlingLine,
    this.vehOffLines,
    this.audioLines, {
    this.notes = const [],
    this.fromGame = const {},
    this.txdParent,
  });

  /// The texture dictionary an .ide line names (2nd column).
  static String txdOf(String ideLine) {
    final cols = ideLine.split(',');
    return cols.length > 1 ? cols[1].trim().toLowerCase() : '';
  }

  /// Parent of the car's texture dictionary ("vehshare_truck" for trucks, whose interior textures
  /// live there), written as a txdp line; null for the usual cars, which need none.
  final String? txdParent;

  /// The txdp line to write, following the txd through a rename.
  String? get txdpLine => txdParent == null || ideLine == null ? null : '${txdOf(ideLine!)}, $txdParent';

  /// A model with no data lines (a zip with only .wft/.wtd files).
  CarData.empty(String model) : this(model.toLowerCase(), null, null, null, null, const [], const []);

  /// Problems found while parsing (duplicate lines, bad names).
  final List<String> notes;

  /// Which files' lines came from the game's own data ('ide', 'carcols', 'handling', 'vehoff').
  final Set<String> fromGame;

  CarData withAudio(List<String> lines) => CarData(
    model,
    ideLine,
    carcolsLine,
    carcolsSection,
    handlingLine,
    vehOffLines,
    lines,
    notes: notes,
    fromGame: fromGame,
    txdParent: txdParent,
  );

  CarData withIdeLine(String line) => CarData(
    model,
    line,
    carcolsLine,
    carcolsSection,
    handlingLine,
    vehOffLines,
    audioLines,
    notes: notes,
    fromGame: fromGame,
    txdParent: txdParent,
  );

  /// Missing lines taken from [game], the vanilla car's data.
  CarData filledFrom(CarData game) => CarData(
    model,
    ideLine ?? game.ideLine,
    carcolsLine ?? game.carcolsLine,
    carcolsLine == null ? game.carcolsSection : carcolsSection,
    handlingLine ?? game.handlingLine,
    vehOffLines.isEmpty ? game.vehOffLines : vehOffLines,
    audioLines,
    notes: notes,
    txdParent: txdParent ?? (ideLine == null ? game.txdParent : null),
    fromGame: {
      ...fromGame,
      if (ideLine == null && game.ideLine != null) 'ide',
      if (carcolsLine == null && game.carcolsLine != null) 'carcols',
      if (handlingLine == null && game.handlingLine != null) 'handling',
      if (vehOffLines.isEmpty && game.vehOffLines.isNotEmpty) 'vehoff',
    },
  );

  /// car3 lines list colours in threes (body, stripe, ...), car4 lines in fours. The groups are
  /// whitespace-separated after the model name, so the most common group size decides; null if unclear.
  static String? carcolsSectionOf(String line) {
    final counts = <int, int>{};
    for (final g in line.split(',').skip(1).join(',').trim().split(RegExp(r'\s+'))) {
      final n = RegExp(r'\d+').allMatches(g).length;
      if (n > 0) counts[n] = (counts[n] ?? 0) + 1;
    }
    final c3 = counts[3] ?? 0, c4 = counts[4] ?? 0;
    return c3 > c4 ? 'car3' : (c4 > c3 ? 'car4' : null);
  }

  final String model;
  final String? ideLine;
  final String? carcolsLine;
  final String? carcolsSection;
  final String? handlingLine;
  final List<String> vehOffLines;

  /// FLA-format sound block starting with [model]; empty if the mod has none.
  final List<String> audioLines;

  /// Anything that stops an install; empty when the data is complete.
  List<String> get problems => [
    ...notes,
    if (ideLine == null) 'vehicles.ide: no line',
    if (carcolsLine == null) 'carcols.dat: no line',
    if (carcolsLine != null && carcolsSection == null) 'carcols.dat: cannot tell whether it is a car3 or car4 line',
    if (vehOffLines.isEmpty) 'vehOff: no camera lines',
  ];

  /// The same car under another model and handling name, written into every data line. The txd and
  /// name key follow the model (or handling) name when they were the same as it.
  /// [keepNameKey] keeps the 5th column (a replaced vanilla car keeps showing its vanilla name).
  CarData renamed({required String model, required String handlingId, bool keepNameKey = false}) {
    model = model.trim().toLowerCase();
    handlingId = handlingId.trim().toUpperCase();
    final old = this.model;
    final word = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(old)}(?![A-Za-z0-9_])', caseSensitive: false);
    String swap(String line) => line.replaceAllMapped(word, (m) => m[0] == m[0]!.toUpperCase() ? model.toUpperCase() : model);
    String? ide;
    if (ideLine != null) {
      final cols = ideLine!.split(',');
      void set(int i, String Function(String v) f) {
        if (cols.length <= i) return;
        final v = cols[i].trim();
        cols[i] = cols[i].replaceFirst(v, f(v));
      }

      final oldHandling = this.handlingId;
      set(0, (_) => model);
      set(1, (v) => v.toLowerCase() == old ? model : v);
      set(3, (_) => handlingId);
      if (!keepNameKey) {
        set(
          4,
          (v) =>
              v.toUpperCase() == old.toUpperCase() ? model.toUpperCase() : (v.toUpperCase() == oldHandling.toUpperCase() ? handlingId : v),
        );
      }
      ide = cols.join(',');
    }
    final bad = [
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(model)) 'model name: letters, digits and _ only',
      if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(handlingId)) 'handling name: letters, digits and _ only',
    ];
    return CarData(
      model,
      ide,
      carcolsLine == null ? null : swap(carcolsLine!),
      carcolsSection,
      handlingLine?.replaceFirst(RegExp(r'^\s*[A-Za-z0-9_]+'), handlingId),
      vehOffLines.map(swap).toList(),
      audioLines.map(swap).toList(),
      notes: [...notes, ...bad],
      fromGame: fromGame,
      txdParent: txdParent,
    );
  }

  /// 4th and 5th columns of the .ide line.
  String get handlingId => _ideColumn(3);
  String get gameName => _ideColumn(4);
  String _ideColumn(int i) {
    final cols = (ideLine ?? '').split(',');
    return cols.length > i ? cols[i].trim() : '';
  }
}
