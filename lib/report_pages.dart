import 'package:material_ui/material_ui.dart';

import 'analytics.dart';
import 'charts.dart';
import 'domain.dart';

Widget choose<T>(
  String label,
  T value,
  List<T> values,
  String Function(T) display,
  ValueChanged<T> select,
) => InputDecorator(
  decoration: InputDecoration(labelText: label, isDense: true),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: value,
      isExpanded: true,
      items: [
        for (final v in values)
          DropdownMenuItem<T>(
            value: v,
            child: Text(display(v), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) select(v);
      },
    ),
  ),
);

Widget rankMode(int value, ValueChanged<int> select) => Wrap(
  spacing: 8,
  children: [
    for (var i = 0; i < rankLabels.length; i++)
      ChoiceChip(
        label: Text('${rankLabels[i]}排名'),
        selected: i == value,
        onSelected: (_) => select(i),
      ),
  ],
);
const trendExplanation = '纵轴为名次，第 1 名在最上方。未录入的排名留空断线；不同考试的参评人数可能不同。';
const radarExplanation = '越靠外表示排名越靠前。各科共用本图刻度，未录入不连线。';

class Overview extends StatefulWidget {
  final Student student;
  final List<Exam> exams;
  const Overview(this.student, this.exams, {super.key});
  @override
  State<Overview> createState() => _OverviewState();
}

class _OverviewState extends State<Overview> {
  late String grade;
  String? scope;
  int rankScope = 1;
  @override
  void initState() {
    super.initState();
    grade = widget.exams.any((e) => !e.draft && e.grade == widget.student.grade)
        ? widget.student.grade
        : widget.exams.where((e) => !e.draft).firstOrNull?.grade ??
              widget.student.grade;
  }

  @override
  Widget build(BuildContext context) {
    final pool = widget.exams
        .where(
          (e) => !e.draft && e.student == widget.student.id && e.grade == grade,
        )
        .toList();
    final templates = <String, Exam>{};
    for (final e in pool) {
      templates.putIfAbsent(axisKey(e), () => e);
    }
    final key = templates.containsKey(scope)
        ? scope
        : templates.keys.firstOrNull;
    final ref = templates[key],
        samples = pool.where((e) => axisKey(e) == key).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('总体成绩概览', style: Theme.of(context).textTheme.headlineSmall),
        Text('${widget.student.name} · 不含草稿'),
        Wrap(
          spacing: 6,
          children: [
            for (final g in grades)
              ChoiceChip(
                label: Text(g),
                selected: g == grade,
                onSelected: (_) => setState(() {
                  grade = g;
                  scope = null;
                }),
              ),
          ],
        ),
        if (ref == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('这个年级还没有已保存的考试。'),
          )
        else ...[
          if (templates.length > 1)
            choose(
              '科目组合',
              key!,
              templates.keys.toList(),
              (k) => templates[k]!.marks.map((m) => m.subject).join(' · '),
              (v) => setState(() {
                scope = v;
              }),
            ),
          Text('共 ${samples.length} 场考试 · ${ref.marks.length} 科'),
          rankMode(rankScope, (i) => setState(() => rankScope = i)),
          panel(
            '历次总分排名趋势',
            trendExplanation,
            totalRankPlot(ordered(samples), rankScope),
          ),
          panel(
            '各科历次平均排名',
            '每科只对已录入的${rankLabels[rankScope]}名次取算术平均，并标注场数。$radarExplanation',
            Radar(rankProfile(ref, samples, rankScope), average: true),
          ),
        ],
      ],
    );
  }
}

class ExamDetail extends StatefulWidget {
  final Exam exam;
  final List<Exam> history;
  final String student;
  const ExamDetail(this.exam, this.history, this.student, {super.key});
  @override
  State<ExamDetail> createState() => _ExamDetailState();
}

class _ExamDetailState extends State<ExamDetail> {
  int? compareId;
  int rankScope = 1;
  @override
  Widget build(BuildContext context) {
    final e = widget.exam;
    final prior = earlier(e, widget.history);
    double? subjectRank(Mark? m) => m?.ranks.values[rankScope]?.toDouble();
    final current = e.marks.map(subjectRank).toList();
    final candidates = prior
        .where(
          (p) => e.marks.any(
            (m) =>
                subjectRank(m) != null &&
                p.marks.any(
                  (old) => old.subject == m.subject && subjectRank(old) != null,
                ),
          ),
        )
        .toList();
    final selected =
        candidates.where((p) => p.id == compareId).firstOrNull ??
        candidates.firstOrNull;
    final past = [
      for (final m in e.marks)
        subjectRank(
          selected?.marks.where((old) => old.subject == m.subject).firstOrNull,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('考试详情'),
        actions: [
          IconButton(
            tooltip: '编辑成绩单',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.pop(context, 'edit'),
          ),
          IconButton(
            tooltip: '删除考试',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                e.title.isEmpty ? '未命名草稿' : e.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text('${widget.student} · ${e.grade} · ${e.type} · ${e.date}'),
              const SizedBox(height: 10),
              Text(e.summary, style: Theme.of(context).textTheme.titleLarge),
              Text(e.ranks.empty ? '总分排名：未录入' : '总分排名：${e.ranks.label}'),
              if (e.draft)
                const Text('草稿尚未纳入成绩概览和历史比较。')
              else ...[
                rankMode(
                  rankScope,
                  (i) => setState(() {
                    rankScope = i;
                    compareId = null;
                  }),
                ),
                panel(
                  '本次各科排名',
                  '${rankLabels[rankScope]}排名 · $radarExplanation',
                  Radar(rankProfile(e, [e], rankScope)),
                ),
                panel(
                  '截至本次的总分排名趋势',
                  trendExplanation,
                  totalRankPlot([...prior.reversed, e], rankScope),
                ),
                panel(
                  '本次与历史考试对比',
                  '逐科对比${rankLabels[rankScope]}名次，第 1 名在最上方。可选同年级较早且有共同已录排名科目的考试。',
                  selected == null
                      ? const Text('暂无具有共同单科排名的历史考试。')
                      : Column(
                          children: [
                            choose(
                              '对比考试',
                              selected.id!,
                              candidates.map((p) => p.id!).toList(),
                              (id) {
                                final p = candidates.firstWhere(
                                  (p) => p.id == id,
                                );
                                return '${p.date} · ${p.title}';
                              },
                              (id) => setState(() => compareId = id),
                            ),
                            Lines(
                              e.marks.map((m) => m.subject).toList(),
                              e.marks.map((m) => m.subject).toList(),
                              [
                                PlotSeries('本次', current, ink),
                                PlotSeries('对比考试', past, compareInk),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
              panel(
                '各科明细',
                '单科成绩及排名以实际录入为准。',
                Column(
                  children: [
                    for (final m in e.marks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${m.subject}  ·  ${m.score == null ? m.state : '${fmt(m.score!)}/${fmt(m.max)}'}',
                        ),
                        subtitle: Text(
                          [
                            m.basis,
                            m.ranks.empty ? '排名未录入' : m.ranks.label,
                            if (!e.draft && selected != null)
                              rankAndScoreDelta(m, selected),
                          ].where((s) => s.isNotEmpty).join('\n'),
                        ),
                      ),
                  ],
                ),
              ),
              if (e.note.isNotEmpty) panel('考试备注', '', Text(e.note)),
            ],
          ),
        ),
      ),
    );
  }

  String signed(double n) => '${n > 0 ? '+' : ''}${fmt(n)}';
  String rankAndScoreDelta(Mark now, Exam prior) {
    final old = prior.marks.where((m) => m.subject == now.subject).firstOrNull;
    if (old == null) return '';
    final change = changeFrom(now, old);
    if (change == null) return '';
    return '较 ${prior.title}：${change.points == null ? '' : '${signed(change.points!)} 分，'}得分率 ${signed(change.percentagePoints)} 个百分点';
  }
}
