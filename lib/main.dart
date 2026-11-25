import 'package:material_ui/material_ui.dart';

import 'domain.dart';
import 'editor.dart';
import 'report_pages.dart';
import 'plan_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ScoreNote(Store.local()));
}

class ScoreNote extends StatelessWidget {
  final Store db;
  const ScoreNote(this.db, {super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ScoreNote 成绩手记',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: Theme.of(context).platform == TargetPlatform.windows
          ? 'Microsoft YaHei'
          : null,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff11685c)),
      scaffoldBackgroundColor: const Color(0xfff7f9f6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: Home(db),
  );
}

class Home extends StatefulWidget {
  final Store db;
  const Home(this.db, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Student> people = [];
  Student? current;
  List<Exam> exams = [];
  List<Plan> plans = [];
  bool loading = true;
  String? problem;
  int tab = 0, epoch = 0;
  String filter = '全部';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([int? target]) async {
    final ticket = ++epoch;
    setState(() {
      loading = true;
      problem = null;
    });
    try {
      final p = await widget.db.students();
      final s =
          p.where((i) => i.id == (target ?? current?.id)).firstOrNull ??
          p.firstOrNull;
      final h = s == null ? <Exam>[] : await widget.db.exams(s.id);
      final choices = s == null ? <Plan>[] : await widget.db.plans(s.id);
      if (mounted && ticket == epoch) {
        setState(() {
          people = p;
          current = s;
          exams = h;
          plans = choices;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && ticket == epoch) {
        setState(() {
          loading = false;
          problem = '无法读取本地成绩库，请重试。';
        });
      }
    }
  }

  void toast(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }

  Future<void> addStudent() async {
    String name = '', grade = '高一';
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('新建学生档案'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(labelText: '学生昵称'),
                onChanged: (v) => update(() => name = v),
              ),
              Wrap(
                spacing: 6,
                children: grades
                    .map(
                      (g) => ChoiceChip(
                        label: Text(g),
                        selected: grade == g,
                        onSelected: (_) => update(() => grade = g),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: name.trim().isEmpty
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('建立档案'),
            ),
          ],
        ),
      ),
    );
    if (yes == true) {
      try {
        await load(await widget.db.add(name, grade));
      } catch (e) {
        toast('档案未保存，请重试');
      }
    }
  }

  Future<void> edit([Exam? exam]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => Editor(widget.db, current!, exams, exam: exam),
      ),
    );
    if (ok == true && mounted) {
      await load();
      toast('已保存到本机');
    }
  }

  Future<void> configure(String grade) async {
    final date = await pickDay(context, day(DateTime.now()));
    if (!mounted || date == null) return;
    final plan = await Navigator.push<Plan>(
      context,
      MaterialPageRoute(
        builder: (_) => PlanPage(widget.db, current!, grade, date, plans),
      ),
    );
    if (plan != null && mounted) await load();
  }

  Future<void> detail(Exam e) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ExamDetail(e, exams, current!.name)),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await edit(e);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('删除这场考试？'),
          content: const Text('此操作不可撤销，不会删除选科方案或其他考试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await widget.db.remove(e.id!, e.student);
          if (mounted) await load();
        } catch (e) {
          toast('删除失败，请重试');
        }
      }
    }
  }

  Widget item(Exam e) => Card(
    child: ListTile(
      onTap: () => detail(e),
      leading: Icon(e.draft ? Icons.edit_note : Icons.assignment_outlined),
      title: Text(e.title.isEmpty ? '未命名草稿' : e.title),
      subtitle: Text('${e.date} · ${e.grade} · ${e.type}\n${e.summary}'),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    ),
  );
  Widget body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (problem != null) {
      return Center(
        child: FilledButton(onPressed: load, child: Text('$problem  重试')),
      );
    }
    if (current == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_outlined, size: 54),
              section('建立第一份成绩档案'),
              const Text('用一个昵称开始。无需注册，成绩只保存在本机。', textAlign: TextAlign.center),
              const SizedBox(height: 22),
              FilledButton(onPressed: addStudent, child: const Text('新建学生档案')),
            ],
          ),
        ),
      );
    }
    final s = current!;
    final list = exams
        .where((e) => filter == '全部' || e.grade == filter)
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.person_outline),
                DropdownButton<int>(
                  value: s.id,
                  items: people
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (id) => load(id),
                ),
                Text('${s.grade}  ·  本地档案'),
              ],
            ),
            if (tab == 0) ...[
              section('考试记录'),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('记录新考试'),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: ['全部', ...grades]
                    .map(
                      (v) => ChoiceChip(
                        label: Text(v),
                        selected: filter == v,
                        onSelected: (_) => setState(() => filter = v),
                      ),
                    )
                    .toList(),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('还没有这个年级的考试记录。'),
                ),
              ...list.map(item),
            ] else if (tab == 1) ...[
              Overview(s, exams, key: ValueKey(s.id)),
            ] else ...[
              section('学生档案'),
              ListTile(
                title: const Text('当前年级'),
                subtitle: const Text('升级年级不会修改历史记录'),
                trailing: DropdownButton<String>(
                  value: s.grade,
                  items: grades
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (g) async {
                    try {
                      await widget.db.changeGrade(s.id, g!);
                      if (mounted) await load();
                    } catch (e) {
                      toast('修改失败');
                    }
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: addStudent,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('新增学生档案'),
              ),
              section('选科历史'),
              const Text('高一固定九科。为高二、高三设置组合时，请先选择生效日期。'),
              Wrap(
                spacing: 8,
                children: grades
                    .skip(1)
                    .map(
                      (g) => TextButton(
                        onPressed: () => configure(g),
                        child: Text('设置$g选科'),
                      ),
                    )
                    .toList(),
              ),
              ...plans.map(
                (p) => ListTile(
                  title: Text('${p.grade}  ·  ${p.choices.join(' / ')}'),
                  subtitle: Text('${p.date} 起生效  |  ${p.mode}'),
                ),
              ),
              const Divider(),
              const Text('存储：本机 SQLite 数据库。此版本不会上传成绩。'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final wide = MediaQuery.sizeOf(c).width >= 760;
    return Scaffold(
      appBar: AppBar(title: const Text('ScoreNote  ·  成绩手记')),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.library_books_outlined),
                  label: Text('考试记录'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: Text('成绩概览'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.school_outlined),
                  label: Text('学生与选科'),
                ),
              ],
            ),
          Expanded(child: body()),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  label: '考试记录',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: '成绩概览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  label: '学生与选科',
                ),
              ],
            ),
    );
  }
}
