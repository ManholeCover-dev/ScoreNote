import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'analytics.dart';
import 'domain.dart';

const ink = Color(0xff176b61),
    compareInk = Color(0xff956124),
    gridInk = Color(0xffcfdbd6);
Widget panel(String title, String caption, Widget child) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(caption),
        const SizedBox(height: 14),
        child,
      ],
    ),
  ),
);
void paintText(
  Canvas canvas,
  String text,
  Offset at, {
  double font = 12,
  Color color = const Color(0xff415650),
  String? family,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: font, fontFamily: family),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  tp.dispose();
}

Paint pen(Color color, [double width = 1]) => Paint()
  ..color = color
  ..strokeWidth = width
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round;

class Radar extends StatelessWidget {
  final List<AxisValue> axes;
  final bool average;
  const Radar(this.axes, {this.average = false, super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (axes.every((a) => a.rank == null))
        const Text('此范围内未录入单科排名。')
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AspectRatio(
            aspectRatio: 1.35,
            child: CustomPaint(
              painter: _RadarPainter(
                axes,
                Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
            ),
          ),
        ),
      if (axes.any((a) => a.rank != null))
        Text('外圈：第 1 名 · 中心：第 ${fmt(rankCeiling(axes.map((a) => a.rank)))} 名'),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 5,
        children: axes
            .map(
              (v) => Text(
                '${v.name} ${v.rank == null ? '—' : '第 ${fmt(v.rank!)} 名'}${average ? '（${v.count}场）' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
            .toList(),
      ),
    ],
  );
}

class _RadarPainter extends CustomPainter {
  final List<AxisValue> axes;
  final String? family;
  _RadarPainter(this.axes, this.family);
  @override
  void paint(Canvas c, Size size) {
    final ceiling = rankCeiling(axes.map((a) => a.rank));
    final n = axes.length;
    if (n < 3) return;
    final center = size.center(Offset.zero),
        r = math.min(size.width / 2 - 42, size.height / 2 - 26);
    if (r <= 0) return;
    Offset pos(int i, double f) =>
        center +
        Offset(
              math.cos(-math.pi / 2 + i * 2 * math.pi / n),
              math.sin(-math.pi / 2 + i * 2 * math.pi / n),
            ) *
            r *
            f;
    Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
    for (final f in [.25, .5, .75, 1.0]) {
      c.drawPath(polygon(List.generate(n, (i) => pos(i, f))), pen(gridInk));
    }
    for (var i = 0; i < n; i++) {
      c.drawLine(center, pos(i, 1), pen(gridInk));
      paintText(c, axes[i].name, pos(i, 1 + 18 / r), family: family);
    }
    if (axes.every((a) => a.rank != null)) {
      c.drawPath(
        polygon(
          List.generate(n, (i) => pos(i, rankRadius(axes[i].rank!, ceiling))),
        ),
        Paint()..color = ink.withAlpha(44),
      );
    }
    for (var i = 0; i < n; i++) {
      final v = axes[i].rank;
      if (v == null) continue;
      final next = (i + 1) % n;
      final p = pos(i, rankRadius(v, ceiling));
      if (axes[next].rank != null) {
        c.drawLine(
          p,
          pos(next, rankRadius(axes[next].rank!, ceiling)),
          pen(ink, 2.4),
        );
      }
      c.drawCircle(p, 3.5, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}

class PlotSeries {
  final String label;
  final List<double?> values;
  final Color color;
  const PlotSeries(this.label, this.values, this.color);
}

/// Horizontal scrolling preserves readable labels and shows the latest points first.
class Lines extends StatelessWidget {
  final List<String> labels, descriptions;
  final List<PlotSeries> series;
  double get ceiling => rankCeiling(series.expand((s) => s.values));
  static const unit = '名';
  const Lines(this.labels, this.descriptions, this.series, {super.key});
  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const Text('暂无可绘制的数据。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            for (final s in series)
              Text(
                '● ${s.label}',
                style: TextStyle(color: s.color, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (c, box) {
            final width = math.max(box.maxWidth, labels.length * 58.0 + 66);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: SizedBox(
                width: width,
                height: 202,
                child: CustomPaint(
                  painter: _LinesPainter(
                    labels,
                    series,
                    ceiling,
                    unit,
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                  ),
                ),
              ),
            );
          },
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('查看图表数值'),
          children: [
            for (var i = 0; i < labels.length; i++)
              ListTile(
                dense: true,
                title: Text(descriptions[i]),
                subtitle: Text(
                  series
                      .map(
                        (s) =>
                            '${s.label}：${s.values[i] == null ? '—' : '${fmt(s.values[i]!)}$unit'}',
                      )
                      .join('  ·  '),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinesPainter extends CustomPainter {
  final List<String> labels;
  final List<PlotSeries> series;
  final double ceiling;
  final String unit;
  final String? family;
  _LinesPainter(this.labels, this.series, this.ceiling, this.unit, this.family);
  @override
  void paint(Canvas c, Size size) {
    const left = 49.0, top = 18.0;
    final right = size.width - 22, bottom = size.height - 30;
    final span = right - left;
    double x(int i) => labels.length == 1
        ? (left + right) / 2
        : left + i * span / (labels.length - 1);
    double y(double v) => bottom - (bottom - top) * rankRadius(v, ceiling);
    for (var i = 0; i <= 4; i++) {
      final val = 1 + i * (ceiling - 1) / 4, dy = y(val);
      c.drawLine(Offset(left, dy), Offset(right, dy), pen(gridInk));
      paintText(c, fmt(val), Offset(left / 2, dy), font: 10, family: family);
    }
    paintText(c, unit, Offset(left / 2, 6), font: 10, family: family);
    for (var i = 0; i < labels.length; i++) {
      paintText(
        c,
        labels[i],
        Offset(x(i), bottom + 15),
        font: 11,
        family: family,
      );
    }
    for (final s in series) {
      Offset? last;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          last = null;
          continue;
        }
        final p = Offset(x(i), y(v));
        if (last != null) {
          c.drawLine(last, p, pen(s.color, 2.3));
        }
        c.drawCircle(p, 3.6, Paint()..color = s.color);
        last = p;
      }
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}

Widget totalRankPlot(List<Exam> exams, int scope) {
  final name = rankLabels[scope];
  final values = exams.map((e) => e.ranks.values[scope]?.toDouble()).toList();
  final n = values.whereType<double>().length;
  if (n == 0) return Text('尚未录入总分$name排名。可在考试详情点编辑补录。');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('共 ${exams.length} 场 · $n 场已录入$name排名${n == 1 ? '（显示一个点）' : ''}'),
      Lines(
        exams.map((e) => e.date.substring(5)).toList(),
        exams.map((e) => '${e.date} · ${e.title}（${e.type}）').toList(),
        [PlotSeries('总分$name排名', values, ink)],
      ),
    ],
  );
}
