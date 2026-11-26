// 임시: 화면 PNG 찍기(커밋하지 않는다). SHOTS=dir flutter test test/zz_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:popoling/main.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(File(f).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await l.load();
}

void main() {
  final out = Platform.environment['SHOTS'] ?? '/tmp';
  setUpAll(() async {
    const core = '../core/fonts';
    await _font('packages/popoling_core/IBMPlexSansKR', ['Regular', 'Medium', 'SemiBold', 'Bold'].map((w) => '$core/IBMPlexSansKR-$w.ttf').toList());
    await _font('packages/popoling_core/JetBrainsMono', ['Regular', 'Medium', 'SemiBold'].map((w) => '$core/JetBrainsMono-$w.ttf').toList());
    await _font('MaterialIcons', ['/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      // 그림(Image.asset)이 다 풀리게 잠깐 기다린다.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final (name, route, arg, tab) in [
    ('home', '/home', null, null),
    ('project', '/dashboard', 'my-team-project', null),
    ('project_failed', '/dashboard', 'shop-clone', null),
    ('env', '/dashboard', 'my-team-project', '환경 점검'),
    ('settings', '/dashboard', 'my-team-project', '설정'),
    ('git', '/dashboard', 'my-team-project', 'Git'),
    ('ai', '/ai', null, null),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = PopolingApp(registry: buildRegistry(demo: true));
      await tester.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: app));
      await tester.pump(const Duration(milliseconds: 100));
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route, arguments: arg);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (tab != null) {
        await tester.tap(find.text(tab).first);
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await shot(tester, name);
    });
  }
}
