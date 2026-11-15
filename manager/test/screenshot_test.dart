// Renders each tab to a PNG (real fonts and icons) so the layout can be reviewed without the window.
// Run: flutter test test/screenshot_test.dart  -> build/screens/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:addon_car_manager/core/manager.dart';
import 'package:addon_car_manager/core/mod_package.dart';
import 'package:addon_car_manager/main.dart';
import 'package:archive/archive.dart';
import 'package:addon_car_manager/pages/install.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'mock_game.dart';

Future<void> loadFont(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('render each tab', (tester) async {
    final game = mockGame().path;
    addTearDown(() => Directory(game).deleteSync(recursive: true));
    // a second car, so that several can be selected
    final second = ModPackage.open(mockMod(model: 'mockgtx2', nameKey: 'MOCKGTX2'));
    AddonCarManager(game).install(
      second.car('mockgtx2'),
      second.files['Mock GT/mockgtx2.wft']!,
      second.files['Mock GT/mockgtx2.wtd']!,
      displayName: 'Mock GT X',
    );
    final pub = '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache\\hosted\\pub.dev';
    await tester.runAsync(() async {
      await loadFont('Switzer', 'fonts/Switzer-Extrabold.ttf');
      await loadFont('DIN1451', 'fonts/din1451alt.ttf');
      await loadFont('packages/forui_lucide/ForuiLucideIcons', '$pub\\forui_lucide-0.27.0\\assets\\lucide.ttf');
    });
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('root'),
        child: Application(root: game),
      ),
    );
    await tester.pumpAndSettle();
    Directory('build/screens').createSync(recursive: true);
    Future<void> shot(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('root')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screens/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    for (final tab in ['Cars', 'Install', 'Traffic', 'Backups', 'About']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      await shot(tab.toLowerCase());
    }

    // Cars tab: select all, open the batch traffic picker (Cancel: nothing is written)
    await tester.tap(find.text('Cars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await shot('cars_selected');
    // a change (here: the refresh button) keeps the selection
    await tester.tap(find.byIcon(FLucideIcons.refreshCw));
    await tester.pumpAndSettle();
    expect(find.textContaining('cars selected'), findsOneWidget);
    // the batch plate dialog (Cancel: nothing is written); only there with LibertyCityPlates
    if (find.text('Plate…').evaluate().isNotEmpty) {
      await tester.tap(find.text('Plate…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Plate for '), findsOneWidget);
      await shot('cars_plate');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Traffic groups…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Traffic groups for '), findsOneWidget);
    await shot('cars_traffic');
    await tester.enterText(find.descendant(of: find.byType(FAutocomplete<String>), matching: find.byType(EditableText)), 'sultan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining("TICKED SULTAN'S GROUPS: GTA IV"), findsOneWidget);
    expect(find.textContaining('The Lost and Damned'), findsWidgets);
    await shot('cars_traffic_copied');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    final install = tester.state(find.byType(InstallPage));
    await tester.runAsync(
      () => (install as dynamic).openBytes(mockMod(model: 'mockgtx3', nameKey: 'MOCKGTX3'), 'Mock GT 3.zip') as Future<void>,
    );
    await tester.pumpAndSettle();
    await shot('install_zip');

    // a replace mod: only sultan.wft/.wtd, lines filled from the game, data lines shown
    final replace = Archive()
      ..add(ArchiveFile.bytes('Sultan Tuned/sultan.wft', Uint8List(4)))
      ..add(ArchiveFile.bytes('Sultan Tuned/sultan.wtd', Uint8List(4)));
    final state = tester.state(find.byType(InstallPage));
    await tester.runAsync(
      () => (state as dynamic).openBytes(Uint8List.fromList(ZipEncoder().encodeBytes(replace)), 'Sultan Tuned.zip') as Future<void>,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data lines'));
    await tester.pumpAndSettle();
    await shot('install_replace');
    // a change elsewhere (here: the refresh button, as an install does) keeps the archive open
    await tester.tap(find.byIcon(FLucideIcons.refreshCw));
    await tester.pumpAndSettle();
    expect(find.text('Sultan Tuned.zip'), findsOneWidget);
  });
}
