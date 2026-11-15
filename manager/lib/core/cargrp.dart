/// cargrp.dat: one line per traffic group ("car, car, car,  # POPCYCLE_GROUP_NAME").
/// Limits found in GTA IV CE 1.2.0.59's loader (0xC0BC70): the first 47 group lines are used
/// (popcycle.dat refers to groups by position) and only the first 35 names of a line are read.
/// Unknown names still use up one of the 35.
class CarGroups {
  CarGroups._(this._lines, this.nl);

  static const maxCarsPerGroup = 35;
  static const maxGroups = 47;

  final List<String> _lines;
  final String nl;

  static CarGroups parse(String text) {
    final nl = text.contains('\r\n') ? '\r\n' : '\n';
    return CarGroups._(text.split(nl), nl);
  }

  @override
  String toString() => _lines.join(nl);

  /// Indexes into the file's lines of the group lines, in game order.
  List<int> get _groupLines => [
    for (var i = 0; i < _lines.length; i++)
      if (_lines[i].trim().isNotEmpty && !_lines[i].trimLeft().startsWith('#')) i,
  ];

  List<CarGroup> get groups {
    final idx = _groupLines;
    return [for (var g = 0; g < idx.length; g++) CarGroup._(g, _lines[idx[g]])];
  }

  void add(int group, String model) {
    final g = groups[group];
    if (g.models.any((m) => m.toLowerCase() == model.toLowerCase())) return;
    if (g.models.length >= maxCarsPerGroup) throw StateError('${g.name} already has $maxCarsPerGroup cars, the game limit');
    _set(group, [...g.models, model.toLowerCase()], g.comment);
  }

  void remove(int group, String model) {
    final g = groups[group];
    if (!g.models.any((m) => m.toLowerCase() == model.toLowerCase())) return; // leave untouched lines as they are
    _set(group, [
      for (final m in g.models)
        if (m.toLowerCase() != model.toLowerCase()) m,
    ], g.comment);
  }

  void _set(int group, List<String> models, String? comment) =>
      _lines[_groupLines[group]] = '${models.join(', ')},${comment == null ? '' : '  # $comment'}';
}

class CarGroup {
  CarGroup._(this.index, String line) {
    final hash = line.indexOf('#');
    final head = hash < 0 ? line : line.substring(0, hash);
    comment = hash < 0 ? null : line.substring(hash + 1).trim();
    models = [
      for (final t in head.split(RegExp(r'[,\s]+')))
        if (t.isNotEmpty) t,
    ];
  }

  final int index;
  late final List<String> models;
  late final String? comment;

  /// Group name from the line's comment (POPCYCLE_GROUP_HARLEM -> Harlem).
  String get name {
    final id = (comment ?? '').split(RegExp(r'\s')).first; // some comments add prose after the ID
    final c = id.replaceFirst(RegExp(r'^POPCYCLE_(CAR_)?GROUP_'), '').trim();
    if (c.isEmpty) return 'Group ${index + 1}';
    return c.split('_').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');
  }

  bool get usedByGame => index < CarGroups.maxGroups;

  /// popcycle.dat weights only the first 42 groups (its Harl … G_PuertoR columns) per area and time.
  /// The rest (Cops, Network, Boats, ...) are picked only by code that names them.
  static const areaGroups = 42;
  bool get areaBased => index < areaGroups;

  /// Read only when IS_NETWORK_GAME_RUNNING (0x47C2E0) is true; Complete Edition has no multiplayer.
  bool get multiplayerOnly => (comment ?? '').toUpperCase().startsWith('POPCYCLE_GROUP_NETWORK');
}
