// Opens every page of the app against the mock game folder (mock_game.dart) and fails on any
// layout or runtime exception.
import 'dart:io';

import 'package:addon_car_manager/core/manager.dart';
import 'package:addon_car_manager/main.dart';
import 'package:addon_car_manager/pages/install.dart';
import 'package:addon_car_manager/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'mock_game.dart';

void main() {
  final game = mockGame().path;
  tearDownAll(() => Directory(game).deleteSync(recursive: true));

  testWidgets('every tab renders without exceptions', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(Application(root: game));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final tab in ['Install', 'Traffic', 'Backups', 'About', 'Cars']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    expect(find.text('Mock GT'), findsWidgets); // Cars tab lists the installed cars by name

    // About: picking a row shows its license text beside the list (the app's own GPL first)
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget); // not pressed: it would ask GitHub
    for (final (name, start) in [
      (null, 'GNU GENERAL PUBLIC LICENSE'),
      ('7-Zip', '7-Zip'),
      ('fastman92 limit adjuster', 'The MIT License'),
      ('Switzer', 'Fontshare'),
      ('Alte DIN 1451 Mittelschrift', 'Copyright (c) 2017, Peter Wiegel'),
    ]) {
      if (name != null) await tester.tap(find.text(name).first);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // the text is read from disk
      await tester.pumpAndSettle();
      expect(find.textContaining(start), findsWidgets, reason: '$name');
      expect(tester.takeException(), isNull, reason: '$name');
    }

    await tester.tap(find.text('Traffic'));
    await tester.pumpAndSettle();
    expect(find.text('Harlem'), findsOneWidget);
    for (final e in ['The Lost and Damned', 'The Ballad of Gay Tony', 'GTA IV']) {
      await tester.tap(find.text(e));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: e);
    }

    // the mouse wheel over the empty margin left of the list scrolls the list
    ScrollPosition list() =>
        tester.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first).position;
    expect(list().pixels, 0);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(20, 500)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 200)));
    await tester.pumpAndSettle();
    expect(list().pixels, 200);
  });

  testWidgets('install page shows a zip\'s cars and variants', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<State<InstallPage>>();
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: darkTheme,
          child: FToaster(
            child: FScaffold(
              child: InstallPage(key: key, manager: AddonCarManager(game), onChanged: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => (key.currentState! as dynamic).openBytes(mockMod(), 'mock.zip') as Future<void>);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('mockgt'), findsOneWidget);
    expect(find.text('INSTALLED'), findsOneWidget); // an installed car collapses to one line

    // the same mod under another model name: the form, with the name key to type
    await tester.runAsync(
      () => (key.currentState! as dynamic).openBytes(mockMod(model: 'mockgtx2', nameKey: 'MOCKGTX2'), 'mock2.zip') as Future<void>,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Name key'), findsOneWidget);
    expect(find.text('Install mockgtx2'), findsOneWidget);
  });

  testWidgets('small windows: every tab and the traffic dialog fit without overflow', (tester) async {
    // the real fonts: the test font's square glyphs are wider and overflow where the app does not
    await tester.runAsync(() async {
      for (final (family, file) in [('Switzer', 'fonts/Switzer-Extrabold.ttf'), ('DIN1451', 'fonts/din1451alt.ttf')]) {
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())))).load();
      }
    });
    for (final size in const [Size(1000, 520), Size(800, 500), Size(570, 500)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(Application(root: game));
      await tester.pumpAndSettle();
      for (final tab in ['Install', 'Traffic', 'Backups', 'About', 'Cars']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab at $size');
      }
      await tester.ensureVisible(find.text('Traffic groups…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Traffic groups…'));
      await tester.pumpAndSettle();
      expect(find.text('Traffic groups'), findsWidgets, reason: '$size');
      expect(tester.takeException(), isNull, reason: 'dialog at $size');
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    tester.view.reset();
  });
}
