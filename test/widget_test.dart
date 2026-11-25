import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_note/main.dart';
import 'package:score_note/store.dart';

void main() {
  testWidgets('补录高一考试时用九科模板，不更改学生的当前年级', (t) async {
    final db = Store(NativeDatabase.memory());
    addTearDown(db.close);
    final student = await db.add('小杨', '高三');
    await t.pumpWidget(ScoreNote(db));
    await t.pumpAndSettle();
    await t.tap(find.text('记录新考试'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, '高一'));
    await t.tap(find.text('确认年级，下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认考试信息，查看科目'));
    await t.pumpAndSettle();
    expect(
      find.text('语文 · 数学 · 英语 · 物理 · 历史 · 化学 · 生物 · 政治 · 地理'),
      findsOneWidget,
    );
    await t.scrollUntilVisible(
      find.text('存为草稿'),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('存为草稿'));
    await t.pumpAndSettle();
    final e = (await db.exams(student)).single;
    expect(e.draft, isTrue);
    expect(e.marks.length, 9);
    expect(e.grade, '高一');
    expect((await db.students()).single.grade, '高三');
  });
  testWidgets('高二新档案：先选年级，然后设置选科，再展示六科录入', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final db = Store(NativeDatabase.memory());
    addTearDown(db.close);
    await db.add('测试同学', '高二');
    await t.pumpWidget(ScoreNote(db));
    await t.pumpAndSettle();
    await t.tap(find.text('记录新考试'));
    await t.pumpAndSettle();
    expect(find.text('选择考试所属年级'), findsOneWidget);
    await t.tap(find.text('确认年级，下一步'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '期中');
    await t.tap(find.text('确认考试信息，查看科目'));
    await t.pumpAndSettle();
    expect(find.text('高二选科设置'), findsOneWidget);
    for (final s in ['物理', '化学', '生物']) {
      await t.ensureVisible(find.widgetWithText(FilterChip, s));
      await t.tap(find.widgetWithText(FilterChip, s));
      await t.pumpAndSettle();
    }
    await t.ensureVisible(find.text('确认并保存组合'));
    await t.tap(find.text('确认并保存组合'));
    await t.pumpAndSettle();
    expect(find.text('语文 · 数学 · 英语 · 物理 · 化学 · 生物'), findsOneWidget);
    for (final (key, v) in [
      ('总分-班级', '4'),
      ('总分-年级', '21'),
      ('语文-联考', '103'),
    ]) {
      final field = find.byKey(ValueKey(key));
      await t.scrollUntilVisible(
        field,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(field, v);
    }
    final score = find
        .byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '得分',
        )
        .first;
    await t.ensureVisible(score);
    await t.enterText(score, '0');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('保存到本机'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('保存到本机'));
    await t.pumpAndSettle();
    expect(find.textContaining('已出 1/6 科'), findsOneWidget);
    final saved = (await db.exams((await db.students()).single.id)).single;
    expect(saved.marks.first.score, 0);
    expect(saved.marks.last.score, isNull);
    expect(saved.ranks.values, [4, 21, null]);
    expect(saved.marks.first.ranks.joint, 103);
  });
}
