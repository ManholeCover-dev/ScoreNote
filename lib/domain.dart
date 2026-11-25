const grades = ['高一', '高二', '高三'];
const core = ['语文', '数学', '英语'];
const options = ['物理', '历史', '化学', '生物', '政治', '地理'];
const statuses = ['待出分', '已出分', '缺考', '本次未考'];
const examTypes = ['月考', '期中', '期末', '模拟考', '单科测验', '其他'];
const structured = '3+1+2';
const free = '自由选三科';
String day(DateTime d) => d.toIso8601String().split('T').first;
String fmt(num n) => n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
bool validPlan(String mode, Iterable<String> subjects) {
  final set = subjects.toSet();
  return subjects.length == 3 &&
      set.length == 3 &&
      set.every(options.contains) &&
      (mode == free ||
          (mode == structured &&
              set.where(options.take(2).contains).length == 1));
}

class Student {
  final int id;
  final String name, grade;
  const Student(this.id, this.name, this.grade);
}

class Plan {
  final int student;
  final String grade, date, mode;
  final List<String> choices;
  const Plan(this.student, this.grade, this.date, this.mode, this.choices);
}

Plan? applicable(Iterable<Plan> plans, int student, String grade, String date) {
  final matches =
      plans
          .where(
            (p) =>
                p.student == student &&
                p.grade == grade &&
                p.date.compareTo(date) <= 0,
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  return matches.firstOrNull;
}

const rankLabels = ['班级', '年级', '联考'];

class Ranks {
  final int? classroom, grade, joint;
  const Ranks([this.classroom, this.grade, this.joint]);
  List<int?> get values => [classroom, grade, joint];
  bool get valid => values.every((r) => r == null || r > 0);
  bool get empty => values.every((r) => r == null);
  Map<String, dynamic> json() => {
    'class': classroom,
    'grade': grade,
    'joint': joint,
  };
  factory Ranks.read(Map<String, dynamic>? j) =>
      Ranks(j?['class'], j?['grade'], j?['joint']);
  String get label => [
    for (var i = 0; i < 3; i++)
      if (values[i] != null) '${rankLabels[i]}第 ${values[i]} 名',
  ].join(' · ');
}

class Mark {
  final Ranks ranks;
  final String subject, state, basis;
  final double max;
  final double? score;
  const Mark(
    this.subject,
    this.state,
    this.max,
    this.score, [
    this.basis = '原始分',
    this.ranks = const Ranks(),
  ]);
  bool get valid =>
      ranks.valid &&
      max.isFinite &&
      max > 0 &&
      statuses.contains(state) &&
      (state == '已出分'
          ? score != null && score!.isFinite && score! >= 0 && score! <= max
          : score == null);
  Map<String, dynamic> json() => {
    'ranks': ranks.json(),
    'subject': subject,
    'state': state,
    'basis': basis,
    'max': max,
    'score': score,
  };
  factory Mark.read(Map<String, dynamic> m) => Mark(
    m['subject'],
    m['state'],
    (m['max'] as num).toDouble(),
    (m['score'] as num?)?.toDouble(),
    m['basis'],
    Ranks.read(m['ranks']),
  );
}

class Exam {
  final Ranks ranks;
  final int? id;
  final int student;
  final String grade, date, title, type, note;
  final bool draft;
  final List<Mark> marks;
  const Exam(
    this.id,
    this.student,
    this.grade,
    this.date,
    this.title,
    this.type,
    this.note,
    this.draft,
    this.marks, [
    this.ranks = const Ranks(),
  ]);
  List<Mark> get expected => marks.where((m) => m.state != '本次未考').toList();
  int get count => marks.where((m) => m.score != null).length;
  double get subtotal => marks.fold(0.0, (v, m) => v + (m.score ?? 0));
  bool get complete => !draft && count > 0 && expected.length == count;
  bool comparable(Exam prev) =>
      student == prev.student &&
      grade == prev.grade &&
      type == prev.type &&
      complete &&
      prev.complete &&
      expected.length == prev.expected.length &&
      expected.every(
        (m) => prev.expected.any(
          (p) => p.subject == m.subject && p.max == m.max && p.basis == m.basis,
        ),
      );
  String get summary => draft
      ? '未完成的草稿'
      : complete
      ? '总分 ${fmt(subtotal)}'
      : '已出 $count/${expected.length} 科 · 合计 ${fmt(subtotal)} 分';
}

/// Only compare marks that represent the same subject and scoring basis.
({double? points, double percentagePoints})? changeFrom(Mark now, Mark prior) {
  if (now.subject != prior.subject ||
      now.basis != prior.basis ||
      !now.valid ||
      !prior.valid ||
      now.score == null ||
      prior.score == null) {
    return null;
  }
  return (
    points: now.max == prior.max ? now.score! - prior.score! : null,
    percentagePoints: 100 * (now.score! / now.max - prior.score! / prior.max),
  );
}
