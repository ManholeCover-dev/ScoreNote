import 'package:material_ui/material_ui.dart';

import 'domain.dart';
import 'store.dart';
import 'plan_page.dart';

class Editor extends StatefulWidget {
  final Store db;
  final Student student;
  final Exam? exam;
  final List<Exam> history;
  const Editor(this.db, this.student, this.history, {this.exam, super.key});
  @override
  State<Editor> createState() => _EditorState();
}

class _RankInput {
  final List<TextEditingController> fields;
  _RankInput(Ranks ranks)
    : fields = ranks.values
          .map((v) => TextEditingController(text: v?.toString() ?? ''))
          .toList();
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
  }

  String? invalid(String prefix) {
    for (var i = 0; i < 3; i++) {
      final s = fields[i].text.trim();
      if (s.isNotEmpty &&
          (!RegExp(r'^[0-9]+$').hasMatch(s) || (int.tryParse(s) ?? 0) < 1)) {
        return '$prefix：${rankLabels[i]}排名须为正整数，未知请留空。';
      }
    }
    return null;
  }

  Ranks get value => Ranks(
    int.tryParse(fields[0].text.trim()),
    int.tryParse(fields[1].text.trim()),
    int.tryParse(fields[2].text.trim()),
  );
  Widget inputs(String label) => Row(
    children: [
      for (var i = 0; i < 3; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
            child: TextField(
              key: ValueKey('$label-${rankLabels[i]}'),
              controller: fields[i],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${rankLabels[i]}排名',
                isDense: true,
              ),
            ),
          ),
        ),
    ],
  );
}

class _Line {
  final _RankInput ranks;
  final String name;
  String state, basis;
  final TextEditingController score, max;
  _Line(Mark m)
    : ranks = _RankInput(m.ranks),
      name = m.subject,
      state = m.state,
      basis = m.basis,
      score = TextEditingController(
        text: m.score == null
            ? ''
            : m.score!.toString().replaceFirst(RegExp(r'\.0$'), ''),
      ),
      max = TextEditingController(
        text: m.max.toString().replaceFirst(RegExp(r'\.0$'), ''),
      );
  void dispose() {
    ranks.dispose();
    score.dispose();
    max.dispose();
  }

  Mark? read() {
    final top = double.tryParse(max.text.trim());
    if (top == null) return null;
    final m = Mark(
      name,
      state,
      top,
      state == '已出分' ? double.tryParse(score.text.trim()) : null,
      basis,
      ranks.value,
    );
    return m.valid ? m : null;
  }
}

class _EditorState extends State<Editor> {
  late String grade, date, type;
  final title = TextEditingController(), note = TextEditingController();
  List<_Line> lines = [];
  int step = 0;
  bool busy = false, leave = false;
  String? error;
  late final _RankInput totalRanks;
  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    totalRanks = _RankInput(e?.ranks ?? const Ranks());
    grade = e?.grade ?? widget.student.grade;
    date = e?.date ?? day(DateTime.now());
    type = e?.type ?? examTypes.first;
    if (e != null) {
      step = 2;
      title.text = e.title;
      note.text = e.note;
      lines = e.marks.map(_Line.new).toList();
    }
  }

  @override
  void dispose() {
    totalRanks.dispose();
    title.dispose();
    note.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> prepare() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      List<String> subjects = [...core, ...options];
      if (grade != '高一') {
        final all = await widget.db.plans(widget.student.id);
        var p = applicable(all, widget.student.id, grade, date);
        if (!mounted) return;
        p ??= await Navigator.push<Plan>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PlanPage(widget.db, widget.student, grade, date, all),
          ),
        );
        if (p == null || !mounted) return;
        subjects = [...core, ...p.choices];
      }
      lines = subjects.map((s) {
        final prev = widget.history
            .where(
              (e) =>
                  !e.draft && e.grade == grade && e.date.compareTo(date) <= 0,
            )
            .expand((e) => e.marks)
            .where((m) => m.subject == s)
            .firstOrNull;
        return _Line(
          Mark(
            s,
            '待出分',
            prev?.max ?? (core.contains(s) ? 150 : 100),
            null,
            prev?.basis ?? '原始分',
          ),
        );
      }).toList();
      setState(() => step = 2);
    } catch (e) {
      if (mounted) setState(() => error = '读取科目失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void close(bool saved) {
    setState(() => leave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> save(bool draft) async {
    if (busy) return;
    final rankError = [
      totalRanks.invalid('总分'),
      ...lines.map((l) => l.ranks.invalid(l.name)),
    ].whereType<String>().firstOrNull;
    if (rankError != null) {
      setState(() => error = rankError);
      return;
    }
    final marks = <Mark>[];
    for (final l in lines) {
      final m = l.read();
      if (m == null) {
        setState(() => error = '${l.name}：请输入正数满分；已出分成绩须在 0 至满分之间。');
        return;
      }
      marks.add(m);
    }
    if (!draft &&
        (title.text.trim().isEmpty || marks.every((m) => m.state == '本次未考'))) {
      setState(() => error = '请填写考试名称，并保留至少一门应考科目。');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.db.save(
        Exam(
          widget.exam?.id,
          widget.student.id,
          grade,
          date,
          title.text.trim(),
          type,
          note.text.trim(),
          draft,
          marks,
          totalRanks.value,
        ),
      );
      if (mounted) close(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '未能写入本机，请重试。';
        });
      }
    }
  }

  Future<void> back() async {
    if (busy || leave) return;
    if (step != 2) {
      if (step == 1) {
        setState(() => step = 0);
      } else {
        close(false);
      }
      return;
    }
    final draft = widget.exam?.draft != false;
    final answer = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('离开成绩录入？'),
        content: Text(draft ? '可以保存草稿，稍后从考试记录继续。' : '原成绩单保持不变，除非保存修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('继续填写'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: Text(draft ? '保存草稿' : '保存修改'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (answer == 'save') {
      await save(draft);
    } else if (answer == 'discard') {
      close(false);
    }
  }

  Widget inputLine(_Line l) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              DropdownButton<String>(
                value: l.state,
                items: statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() {
                  l.state = v!;
                  if (v != '已出分') l.score.clear();
                }),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: l.score,
                  enabled: l.state == '已出分' || l.state == '待出分',
                  decoration: const InputDecoration(labelText: '得分'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => setState(
                    () => l.state = v.trim().isEmpty ? '待出分' : '已出分',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: l.max,
                  decoration: const InputDecoration(labelText: '满分'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: l.basis,
                items: ['原始分', '赋分']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => l.basis = v!),
              ),
            ],
          ),
          const SizedBox(height: 10),
          l.ranks.inputs(l.name),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leave,
    onPopInvokedWithResult: (did, result) {
      if (!did) back();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.exam == null ? '记录新考试' : '编辑成绩单')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('${widget.student.name}  /  第 ${step + 1} 步，共 3 步'),
              section(['选择考试所属年级', '考试信息', '确认科目并填写成绩'][step]),
              if (step == 0) ...[
                const Text('补录旧考试时，请选择考试当天所在的年级。'),
                Wrap(
                  spacing: 8,
                  children: grades
                      .map(
                        (g) => ChoiceChip(
                          label: Text(g),
                          selected: grade == g,
                          onSelected: (_) => setState(() => grade = g),
                        ),
                      )
                      .toList(),
                ),
                FilledButton(
                  onPressed: () => setState(() => step = 1),
                  child: const Text('确认年级，下一步'),
                ),
              ],
              if (step >= 1) ...[
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: '考试名称',
                    hintText: '例如：高二上学期期中考试',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('$grade  ·  $date'),
                  trailing: step == 1 ? const Icon(Icons.calendar_month) : null,
                  onTap: step != 1
                      ? null
                      : () async {
                          final d = await pickDay(context, date);
                          if (d != null && mounted) setState(() => date = d);
                        },
                ),
                DropdownButton<String>(
                  value: type,
                  items: examTypes
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => type = v!),
                ),
              ],
              if (step == 1)
                FilledButton(
                  onPressed: busy ? null : prepare,
                  child: const Text('确认考试信息，查看科目'),
                ),
              if (step == 2) ...[
                Text(lines.map((l) => l.name).join(' · ')),
                section('总分排名（选填）'),
                totalRanks.inputs('总分'),
                const SizedBox(height: 12),
                const Text('每科也可填写班级、年级和联考排名；未公布请留空。'),
                ...lines.map(inputLine),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '备注（选填）'),
                ),
                const SizedBox(height: 16),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (step == 2) ...[
                FilledButton.icon(
                  onPressed: busy ? null : () => save(false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存到本机'),
                ),
                if (widget.exam?.draft != false)
                  TextButton(
                    onPressed: busy ? null : () => save(true),
                    child: const Text('存为草稿'),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
