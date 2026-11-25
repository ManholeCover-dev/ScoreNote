import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:score_note/analytics.dart';
import 'package:score_note/charts.dart';
import 'package:score_note/domain.dart';
import 'package:score_note/main.dart';
import 'package:score_note/report_pages.dart';
import 'package:score_note/store.dart';

Exam sample(
  int id,
  String date, {
  int student = 1,
  String grade = '高二',
  String type = '月考',
  bool draft = false,
  double? math = 80,
  double max = 100,
  String basis = '原始分',
  Ranks total = const Ranks(5, 32, 201),
  Ranks mathRanks = const Ranks(2, 14, 151),
}) => Exam(
  id,
  student,
  grade,
  date,
  '${date.substring(5)}测验',
  type,
  '',
  draft,
  [
    for (final name
        in grade == '高一' ? [...core, ...options] : [...core, '物理', '化学', '地理'])
      name == '数学'
          ? Mark(name, math == null ? '缺考' : '已出分', max, math, basis, mathRanks)
          : Mark(name, '已出分', 100, 70),
  ],
  total,
);
void main() {
  testWidgets('概览全部图表随排名范围切换，满分类型不同仍连线，漏填的联考排名留空', (t) async {
    final a = sample(
          1,
          '2026-10-12',
          grade: '高一',
          max: 190,
          total: const Ranks(8, 52, 323),
        ),
        b = sample(
          2,
          '2026-11-25',
          grade: '高一',
          type: '期中',
          max: 150,
          total: const Ranks(4, 28),
          mathRanks: const Ranks(4, 20, 203),
        );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Overview(const Student(1, 'A', '高一'), [b, a]),
          ),
        ),
      ),
    );
    Lines line() => t.widget<Lines>(find.byType(Lines));
    AxisValue math() => t
        .widget<Radar>(find.byType(Radar))
        .axes
        .firstWhere((m) => m.name == '数学');
    expect(line().series.single.values, [52, 28]);
    expect(math().rank, 17);
    expect(t.widget<Radar>(find.byType(Radar)).axes.length, 9);
    for (final (label, values, mean) in [
      ('班级排名', [8, 4], 3.0),
      ('联考排名', [323, null], 177.0),
    ]) {
      await t.tap(find.widgetWithText(ChoiceChip, label));
      await t.pumpAndSettle();
      expect(line().series.single.values, values);
      expect(math().rank, mean);
    }
  });
  test('排名不由分数推算；跨学生、跨年级、草稿和未填名次不计平均', () {
    final e = sample(
      1,
      '2026-10-12',
      math: null,
      mathRanks: const Ranks(null, 13),
    );
    final samples = [
      e,
      sample(2, '2026-11-12', mathRanks: const Ranks()),
      sample(3, e.date, student: 2),
      sample(4, e.date, grade: '高一'),
      sample(5, e.date, draft: true),
    ];
    final axes = rankProfile(e, samples, 1);
    expect(axes.length, 6);
    expect(axes[1].rank, 13);
    expect(axes[1].count, 1);
    expect(axes.first.rank, isNull);
    expect(rankProfile(e, samples, 0)[1].rank, isNull);
  });
  test('同年级排名历史允许跨类型，排除同日及未来；名次越靠前越高、越靠外', () {
    final e = sample(2, '2026-10-02', type: '期中'), a = sample(1, '2026-10-01');
    expect(
      earlier(e, [
        e,
        a,
        sample(3, e.date),
        sample(4, '2026-10-03'),
        sample(5, a.date, draft: true),
      ]),
      [a],
    );
    final max = rankCeiling([1, 31, null]);
    expect(rankRadius(1, max), 1);
    expect(rankRadius(10, max), greaterThan(rankRadius(31, max)));
  });
  testWidgets('仅有分数时不绘制排名数据', (t) async {
    final e = sample(
      1,
      '2026-10-12',
      total: const Ranks(),
      mathRanks: const Ranks(),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Overview(const Student(1, 'A', '高二'), [e]),
          ),
        ),
      ),
    );
    expect(find.byType(Lines), findsNothing);
    expect(find.textContaining('尚未录入总分年级排名'), findsOneWidget);
    expect(find.text('此范围内未录入单科排名。'), findsOneWidget);
  });
  test('v1 数据库迁移保留考试和旧科目 JSON，可增改清空三类排名并重开', () async {
    final dir = await Directory.systemTemp.createTemp('score-v1-');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/legacy.db');
    var db = Store(NativeDatabase(f));
    await db.add('小林', '高二');
    final legacy = sample(1, '2026-10-01');
    final oldMarks = legacy.marks
        .map((m) => m.json()..remove('ranks'))
        .toList();
    await db.customStatement(
      "INSERT INTO exams(id,student,grade,date,title,type,note,draft,marks) VALUES(1,1,'高二','2026-10-01','旧月考','月考','',0,?)",
      [jsonEncode(oldMarks)],
    );
    await db.customStatement('ALTER TABLE exams DROP COLUMN ranks');
    await db.customStatement('PRAGMA user_version=1');
    await db.close();
    db = Store(NativeDatabase(f));
    final restored = (await db.exams(1)).single;
    expect(restored.title, '旧月考');
    expect(restored.ranks.empty, true);
    expect(restored.marks.every((m) => m.ranks.empty), true);
    await db.save(legacy);
    await db.close();
    db = Store(NativeDatabase(f));
    addTearDown(db.close);
    final ranked = (await db.exams(1)).single;
    expect(ranked.ranks.values, [5, 32, 201]);
    expect(ranked.marks[1].ranks.values, [2, 14, 151]);
    await db.save(restored);
    expect((await db.exams(1)).single.ranks.empty, true);
    expect(const Ranks(-1, 2).valid, false);
  });
  testWidgets('点记录进入整页详情，可返回并切换成绩概览，两页展示对应图表', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final db = Store(NativeDatabase.memory());
    addTearDown(db.close);
    await db.add('小林', '高二');
    for (final date in ['2026-09-01', '2026-10-01']) {
      final e = sample(1, date);
      await db.save(
        Exam(
          null,
          1,
          e.grade,
          e.date,
          e.title,
          e.type,
          '',
          false,
          e.marks,
          e.ranks,
        ),
      );
    }
    await t.pumpWidget(ScoreNote(db));
    await t.pumpAndSettle();
    await t.tap(find.text('10-01测验'));
    await t.pumpAndSettle();
    expect(find.byType(ExamDetail), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('联考第 201 名'), findsOneWidget);
    expect(find.byType(Radar), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('本次与历史考试对比'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('本次与历史考试对比'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('成绩概览'));
    await t.pumpAndSettle();
    expect(find.text('历次总分排名趋势'), findsOneWidget);
    expect(find.text('各科历次平均排名'), findsOneWidget);
    expect(t.widget<Radar>(find.byType(Radar)).axes[1].count, 2);
  });
}
