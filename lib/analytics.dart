import 'domain.dart';

/// Chronological order for plotting; same-day exams have no inferred predecessor.
List<Exam> ordered(Iterable<Exam> exams) => exams.toList()
  ..sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
  });
String axisKey(Exam e) =>
    (e.marks.map((m) => m.subject).toList()..sort()).join('|');

class AxisValue {
  final String name;
  final double? rank;
  final int count;
  const AxisValue(this.name, this.rank, this.count);
}

List<AxisValue> rankProfile(Exam template, Iterable<Exam> samples, int scope) =>
    template.marks.map((axis) {
      final values = samples
          .where(
            (e) =>
                !e.draft &&
                e.student == template.student &&
                e.grade == template.grade,
          )
          .expand((e) => e.marks)
          .where((m) => m.subject == axis.subject)
          .map((m) => m.ranks.values[scope])
          .whereType<int>()
          .toList();
      return AxisValue(
        axis.subject,
        values.isEmpty
            ? null
            : values.fold<double>(0, (a, b) => a + b) / values.length,
        values.length,
      );
    }).toList();
List<Exam> earlier(Exam e, Iterable<Exam> exams) => ordered(
  exams.where(
    (p) =>
        p.student == e.student &&
        !p.draft &&
        p.grade == e.grade &&
        p.date.compareTo(e.date) < 0,
  ),
).reversed.toList();
// Five integer ticks, starting at rank 1. Add room at the worst end for radar vertices.
double rankCeiling(Iterable<double?> values) {
  final worst = values.whereType<double>().fold<double>(
    1,
    (a, b) => a > b ? a : b,
  );
  return 1 + 4 * ((worst / 4).ceilToDouble());
}

double rankRadius(double rank, double ceiling) =>
    (ceiling - rank) / (ceiling - 1);
