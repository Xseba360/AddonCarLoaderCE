import 'dart:convert';
import 'dart:typed_data';

const _block = 2048;
const _imgMagic = 0xA94E2A52;
const _rscMagic = 0x05435352;

int _align(int n) => (n + _block - 1) ~/ _block * _block;

class ImgFile {
  ImgFile(this.name, this.data);
  final String name;
  final Uint8List data;
}

/// Builds an unencrypted GTA IV IMG v3 archive with the layout of FusionFix's
/// ImgProcessor::CreateImgV3, the format of the archives FusionFix itself ships.
/// Only RSC resources (.wft/.wtd/.wdr...) are supported; that is all a car needs.
Uint8List buildImg(List<ImgFile> files) {
  final nameTable = <int>[
    for (final f in files) ...[...ascii.encode(f.name), 0],
  ];
  final toc = 20 + 16 * files.length + nameTable.length;
  var block = _align(toc + 32) ~/ _block;
  final total = _align(toc + 32) + files.fold<int>(0, (s, f) => s + _align(f.data.length));
  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);

  bd
    ..setUint32(0, _imgMagic, Endian.little)
    ..setUint32(4, 3, Endian.little)
    ..setUint32(8, files.length, Endian.little)
    ..setUint32(12, 16 * files.length + nameTable.length, Endian.little)
    ..setUint16(16, 16, Endian.little)
    ..setUint16(18, 0xE9, Endian.little);

  var off = 20;
  for (final f in files) {
    if (f.data.length < 12) throw FormatException('${f.name} is too small to be a resource');
    final h = ByteData.sublistView(f.data);
    if (h.getUint32(0, Endian.little) != _rscMagic) throw FormatException('${f.name} is not an RSC resource');
    final type = h.getUint32(4, Endian.little);
    final flags = h.getUint32(8, Endian.little);
    final used = _align(f.data.length);
    bd
      ..setUint32(off, flags, Endian.little)
      ..setUint32(off + 4, type, Endian.little)
      ..setUint32(off + 8, block, Endian.little)
      ..setUint16(off + 12, used ~/ _block, Endian.little)
      ..setUint16(off + 14, ((used - f.data.length) & 0x7FF) | 0x2000, Endian.little);
    out.setRange(block * _block, block * _block + f.data.length, f.data);
    block += used ~/ _block;
    off += 16;
  }
  out.setRange(off, off + nameTable.length, nameTable);
  return out;
}

/// Reads back the entries of an unencrypted IMG v3 (used to verify what [buildImg] wrote).
Map<String, Uint8List> readImg(Uint8List img) {
  final bd = ByteData.sublistView(img);
  if (bd.getUint32(0, Endian.little) != _imgMagic) throw const FormatException('not an unencrypted IMG v3');
  final n = bd.getUint32(8, Endian.little);
  final table = bd.getUint32(12, Endian.little);
  final names = ascii.decode(img.sublist(20 + 16 * n, 20 + table)).split('\x00');
  return {
    for (var i = 0; i < n; i++)
      names[i]: () {
        final e = 20 + 16 * i;
        final start = bd.getUint32(e + 8, Endian.little) * _block;
        final len = bd.getUint16(e + 12, Endian.little) * _block - (bd.getUint16(e + 14, Endian.little) & 0x7FF);
        return img.sublist(start, start + len);
      }(),
  };
}
