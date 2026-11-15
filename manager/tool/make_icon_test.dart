// Renders assets/app_icon.svg (the user's Inkscape drawing, 32x32) into
// windows/runner/resources/app_icon.ico at 16-256 px. The shapes below are that drawing's, by hand:
// edit both together. Run: flutter test tool/make_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const white = ui.Color(0xFFFFFFFF), black = ui.Color(0xFF000000);

void paintIcon(ui.Canvas c, double size) {
  final fill = ui.Paint()..isAntiAlias = true;
  c.scale(size / 32);
  c.drawCircle(const ui.Offset(16, 16), 16, fill..color = white);
  // the car group: transform="matrix(0.83870968,0,0,0.83870968,-3.9193548,-3.7096774)"
  c.translate(-3.9193548, -3.7096774);
  c.scale(0.83870968);
  fill.color = black;
  c.drawRect(const ui.Rect.fromLTWH(11.826923, 28.26923, 4.7692304, 5.3653846), fill); // wheels
  c.drawRect(const ui.Rect.fromLTWH(30.903847, 28.26923, 4.7692304, 5.3653851), fill);
  c.drawRect(const ui.Rect.fromLTWH(10.634615, 27, 26.23077, 1.8653845), fill); // bumper
  c.drawRRect(ui.RRect.fromRectAndRadius(const ui.Rect.fromLTWH(10.634615, 19.923077, 26.23077, 5.9615388), const ui.Radius.circular(1)), fill);
  c.drawRect(const ui.Rect.fromLTWH(10.634615, 25, 26.23077, 0.8846153), fill);
  c.drawRect(const ui.Rect.fromLTWH(14.211538, 19.326923, 19.076923, 0.59615386), fill);
  c.drawPath(
    ui.Path()
      ..moveTo(32.096154, 19.923077)
      ..lineTo(35.076923, 19.923077)
      ..lineTo(32.096154, 12.769231)
      ..lineTo(15.403846, 12.769231)
      ..lineTo(12.423077, 19.923077)
      ..lineTo(15.403846, 19.923077)
      ..lineTo(18.384615, 12.769231)
      ..lineTo(29.115385, 12.769231)
      ..close(),
    fill,
  );
  c.drawRect(const ui.Rect.fromLTWH(15.403846, 12.769231, 16.692308, 2.384615), fill); // roof
  fill.color = white;
  c.drawCircle(const ui.Offset(32.990387, 22.903847), 2.0865378, fill); // headlights
  c.drawCircle(const ui.Offset(14.509615, 22.903847), 2.0865378, fill);
}

Future<Uint8List> png(int size) async {
  final rec = ui.PictureRecorder();
  paintIcon(ui.Canvas(rec), size.toDouble());
  final img = await rec.endRecording().toImage(size, size);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// ICO with PNG entries (supported since Windows Vista).
Uint8List ico(List<(int, Uint8List)> images) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xFF, v >> 8]);
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]);
  u16(0);
  u16(1);
  u16(images.length);
  var offset = 6 + 16 * images.length;
  for (final (size, data) in images) {
    b.add([size >= 256 ? 0 : size, size >= 256 ? 0 : size, 0, 0]);
    u16(1);
    u16(32);
    u32(data.length);
    u32(offset);
    offset += data.length;
  }
  for (final (_, data) in images) {
    b.add(data);
  }
  return b.toBytes();
}

void main() {
  test('write app icon', () async {
    final images = [for (final s in [16, 20, 24, 32, 40, 48, 64, 128, 256]) (s, await png(s))];
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico(images));
    File('build/app_icon_256.png').writeAsBytesSync(images.last.$2);
  });
}
