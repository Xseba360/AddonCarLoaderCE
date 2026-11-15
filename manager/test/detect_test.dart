// No folder saved: the found installs are offered, and picking one opens it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:addon_car_manager/main.dart';
import 'package:addon_car_manager/theme/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'mock_game.dart';

void main() {
  testWidgets('the detect dialog lists each found folder', (tester) async {
    final game = mockGame().path;
    addTearDown(() => Directory(game).deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('root'),
        child: MaterialApp(
          home: FTheme(
            data: darkTheme,
            child: FToaster(
              child: FTooltipGroup(
                child: Home(root: '', locate: () => [game, r'D:\Other\GTAIV']),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('GTA IV found'), findsOneWidget);
    expect(find.text(game), findsOneWidget);
    expect(find.text(r'D:\Other\GTAIV'), findsOneWidget);
    expect(find.text('Use this folder'), findsOneWidget);
    await tester.tap(find.text(r'D:\Other\GTAIV')); // selects it; the dialog stays for the confirm button
    await tester.pumpAndSettle();
    expect(find.text('GTA IV found'), findsOneWidget);

    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('root')));
    await tester.runAsync(() async {
      final png = await (await boundary.toImage()).toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screens').createSync(recursive: true);
      File('build/screens/detect.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
