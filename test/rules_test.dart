import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:score_note/domain.dart';
import 'package:score_note/store.dart';

void main() {
  test('80/100 到 108/150 是下降 8 个百分点，不显示原始分差', () {
    final a = Mark('数学', '已出分', 100, 80), b = Mark('数学', '已出分', 150, 108);
    final result = changeFrom(b, a)!;
    expect(result.points, isNull);
    expect(result.percentagePoints, closeTo(-8, 0.0001));
    expect(changeFrom(Mark('数学', '已出分', 100, 88), a)!.points, 8);
    expect(changeFrom(Mark('数学', '已出分', 100, 82, '赋分'), a), isNull);
  });
  test('选科模式：首选二选一，再选四选二；自由选三不受分组限制', () {
    expect(validPlan(structured, ['物理', '化学', '生物']), isTrue);
    expect(validPlan(structured, ['物理', '历史', '生物']), isFalse);
    expect(validPlan(free, ['物理', '历史', '生物']), isTrue);
    expect(validPlan(free, ['化学', '化学', '生物']), isFalse);
    expect(validPlan(free, ['体育', '化学', '生物']), isFalse);
  });
  test('校验零分、缺考与非法输入', () {
    expect(const Mark('数学', '已出分', 150, 0).valid, isTrue);
    expect(const Mark('数学', '缺考', 150, null).valid, isTrue);
    expect(const Mark('数学', '待出分', 150, 0).valid, isFalse);
    for (final n in [-1.0, 151.0, double.nan, double.infinity]) {
      expect(Mark('数学', '已出分', 150, n).valid, isFalse);
    }
  });
  final all = [...core, ...options];
  Exam sample(
    int id, {
    String grade = '高一',
    List<String>? subs,
    bool draft = false,
    String state = '已出分',
    double top = 100,
    int? key,
  }) => Exam(
    key,
    id,
    grade,
    '2026-06-01',
    '期末考试',
    '期末',
    '',
    draft,
    (subs ?? all)
        .map((s) => Mark(s, state, top, state == '已出分' ? 0 : null))
        .toList(),
  );
  test('不同年级、满分、草稿、未出齐、不同学生不能比较总分', () {
    final e = sample(1);
    expect(e.comparable(sample(1)), isTrue);
    for (final other in [
      sample(2),
      sample(1, grade: '高二'),
      sample(1, top: 150),
      sample(1, draft: true),
      sample(1, state: '缺考'),
      sample(1, state: '待出分'),
    ]) {
      expect(e.comparable(other), isFalse);
    }
    expect(e.summary, '总分 0');
  });
  test('按日期匹配选科，隔离学生，换科不改旧考试', () async {
    final db = Store(NativeDatabase.memory());
    addTearDown(db.close);
    final a = await db.add('小林', '高二'), b = await db.add('小张', '高二');
    final old = Plan(a, '高二', '2026-01-01', structured, ['物理', '化学', '生物']);
    final next = Plan(a, '高二', '2026-09-01', structured, ['物理', '化学', '地理']);
    await db.setPlan(old);
    await db.save(sample(a, grade: '高二', subs: [...core, ...old.choices]));
    await db.setPlan(next);
    final history = await db.plans(a);
    expect(applicable(history, a, '高二', '2025-12-01'), isNull);
    expect(applicable(history, a, '高二', '2026-06-01')!.choices, old.choices);
    expect(applicable(history, a, '高二', '2026-09-01')!.choices, next.choices);
    expect(applicable(history, b, '高二', '2026-09-01'), isNull);
    expect((await db.exams(a)).single.marks.last.subject, '生物');
    expect(await db.exams(b), isEmpty);
  });
  test('关闭重开保留草稿、编辑原记录、删除', () async {
    final dir = await Directory.systemTemp.createTemp('score-note-test');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/test.sqlite');
    var db = Store(NativeDatabase(f));
    final id = await db.add('小陈', '高一');
    final key = await db.save(sample(id, draft: true));
    await db.close();
    db = Store(NativeDatabase(f));
    addTearDown(db.close);
    expect((await db.exams(id)).single.draft, isTrue);
    await db.save(sample(id, key: key));
    expect((await db.exams(id)).single.complete, isTrue);
    await db.remove(key, id);
    expect(await db.exams(id), isEmpty);
  });
}
