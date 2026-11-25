// Optional: flutter test test/preview_test.dart --dart-define=SAVE_PREVIEW=true
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:score_note/domain.dart';
import 'package:score_note/main.dart';
import 'package:score_note/store.dart';

void main() {
  testWidgets('高三可沿用高二选科，但确认前不写入高三方案', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 840);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('SAVE_PREVIEW')) {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final font = const String.fromEnvironment(
        'PREVIEW_FONT',
        defaultValue: r'C:\Windows\Fonts\msyh.ttc',
      );
      await t.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        await ui.loadFontFromList(bytes, fontFamily: 'Microsoft YaHei');
        final icon = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
        await ui.loadFontFromList(
          icon.buffer.asUint8List(),
          fontFamily: 'MaterialIcons',
        );
      });
    }
    final db = Store(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.add('小林', '高三');
    await db.setPlan(
      Plan(id, '高二', '2023-09-01', structured, ['物理', '化学', '地理']),
    );
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: ScoreNote(db)));
    await t.pumpAndSettle();
    await t.tap(find.text('记录新考试'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认年级，下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认考试信息，查看科目'));
    await t.pumpAndSettle();
    expect(find.text('高三选科设置'), findsOneWidget);
    expect(find.text('语文  /  数学  /  英语  /  物理  /  化学  /  地理'), findsOneWidget);
    expect((await db.plans(id)).length, 1);
    if (const bool.fromEnvironment('SAVE_PREVIEW')) {
      await t.runAsync(() async {
        final box =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await box.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/subject-selection.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });
}
