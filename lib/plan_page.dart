import 'package:material_ui/material_ui.dart';

import 'domain.dart';
import 'store.dart';

Future<String?> pickDay(BuildContext c, String value) async {
  final result = await showDatePicker(
    context: c,
    initialDate: DateTime.parse(value),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  return result == null ? null : day(result);
}

Widget section(String text) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 8),
  child: Text(
    text,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
  ),
);

class PlanPage extends StatefulWidget {
  final Store db;
  final Student student;
  final String grade, date;
  final List<Plan> plans;
  const PlanPage(
    this.db,
    this.student,
    this.grade,
    this.date,
    this.plans, {
    super.key,
  });
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late String date, mode;
  late Set<String> selected;
  bool busy = false, inheritedFromGradeTwo = false;
  String? error;
  @override
  void initState() {
    super.initState();
    date = widget.date;
    final p =
        applicable(widget.plans, widget.student.id, widget.grade, date) ??
        (widget.grade == '高三'
            ? applicable(widget.plans, widget.student.id, '高二', date)
            : null);
    inheritedFromGradeTwo = widget.grade == '高三' && p?.grade == '高二';
    mode = p?.mode ?? structured;
    selected = {...?p?.choices};
  }

  Widget choices(Iterable<String> names, int limit) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: names.map((s) {
      final on = selected.contains(s);
      return FilterChip(
        label: Text(s),
        selected: on,
        onSelected: (v) => setState(() {
          if (!v) {
            selected.remove(s);
          } else if (limit == 1) {
            selected.removeAll(names);
            selected.add(s);
          } else if (selected.where(names.contains).length < limit) {
            selected.add(s);
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('本组选满了，请先取消一科')));
          }
        }),
      );
    }).toList(),
  );
  Future<void> confirm() async {
    setState(() => busy = true);
    try {
      final p = Plan(
        widget.student.id,
        widget.grade,
        date,
        mode,
        options.where(selected.contains).toList(),
      );
      await widget.db.setPlan(p);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '保存失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.grade}选科设置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${widget.student.name} · 从 $date 生效'),
            const Text('只影响此日期起新录入的考试，历史成绩单不会改变。'),
            if (inheritedFromGradeTwo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('已带入高二组合。可直接确认沿用，也可重新选科。'),
              ),
            section('选择模式'),
            Wrap(
              spacing: 8,
              children: [structured, free]
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m),
                      selected: mode == m,
                      onSelected: (_) => setState(() {
                        mode = m;
                        if (mode == structured && !validPlan(mode, selected)) {
                          selected.clear();
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
            section('固定科目'),
            Text(core.join('  ·  ')),
            if (mode == structured) ...[
              section('首选科目 · 二选一'),
              choices(options.take(2), 1),
              section('再选科目 · 四选二'),
              choices(options.skip(2), 2),
            ] else ...[
              section('选择三门科目'),
              choices(options, 3),
            ],
            section('成绩单预览'),
            Text([...core, ...options.where(selected.contains)].join('  /  ')),
            const SizedBox(height: 20),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: !busy && validPlan(mode, selected) ? confirm : null,
              child: Text(
                selected.length == 3
                    ? '确认并保存组合'
                    : '还需选择 ${3 - selected.length} 科',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
