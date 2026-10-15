import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 能量环表盘：270° 弧，左下角为 0、右下角为满（顺时针），
/// ≤50% 红→绿、>50% 绿→青，带表盘刻度与 0/100 标签。
class SocGauge extends StatelessWidget {
  final double soc;
  final double totalVoltage;
  final double current;

  const SocGauge({
    super.key,
    required this.soc,
    required this.totalVoltage,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = min(c.maxWidth, 264.0);
      final pct = soc.clamp(0, 100).toDouble();
      final scheme = Theme.of(context).colorScheme;
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
                painter: _GaugePainter(
                    pct: pct,
                    size: size,
                    trackColor: surface2Of(context),
                    tickColor: scheme.onSurface.withOpacity(.55))),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${pct.round()}%',
                  style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1)),
              const SizedBox(height: 2),
              Text('${totalVoltage.toStringAsFixed(2)}V',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 1),
              Text('${current.toStringAsFixed(2)}A',
                  style: TextStyle(fontSize: 13, color: AppTheme.green)),
            ],
          ),
        ],
      );
    });
  }
}

class _GaugePainter extends CustomPainter {
  final double pct;
  final double size;
  final Color trackColor;
  final Color tickColor;

  _GaugePainter({
    required this.pct,
    required this.size,
    required this.trackColor,
    required this.tickColor,
  });

  @override
  void paint(Canvas canvas, Size size0) {
    final c = Offset(size / 2, size / 2);
    final r = size * 104 / 264;
    const startDeg = 135.0; // 左下角为 0
    const sweepDeg = 270.0; // 右下角为满
    final arc = _arcRect(c, r);

    // 底轨
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    _paintArc(canvas, arc, startDeg, sweepDeg, track);

    // 渐变弧
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    if (pct <= 50) {
      paint.shader = SweepGradient(
        startAngle: _rad(startDeg),
        endAngle: _rad(startDeg + sweepDeg),
        colors: [AppTheme.red, AppTheme.green],
      ).createShader(_gaugeRect(c, r));
    } else {
      paint.shader = SweepGradient(
        startAngle: _rad(startDeg),
        endAngle: _rad(startDeg + sweepDeg),
        colors: [AppTheme.green, AppTheme.cyan],
      ).createShader(_gaugeRect(c, r));
    }
    _paintArc(canvas, arc, startDeg, sweepDeg * pct / 100, paint);

    // 表盘刻度（5% 一格，25% 大刻度）
    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = tickColor;
    for (var p = 0; p <= 100; p += 5) {
      final a = _rad(startDeg + sweepDeg * p / 100);
      final major = p % 25 == 0;
      final r1 = major ? r * 119 / 104 : r * 113 / 104;
      final r2 = major ? r * 106 / 104 : r * 109 / 104;
      tickPaint.strokeWidth = major ? 2.5 : 1;
      tickPaint.color = tickColor.withOpacity(major ? 0.9 : 0.45);
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * r1,
        c + Offset(cos(a), sin(a)) * r2,
        tickPaint,
      );
    }

    // 0 / 100 标签（左下 / 右下）
    final lr = r * 128 / 104;
    final a0 = _rad(startDeg), a100 = _rad(startDeg + sweepDeg);
    _label(canvas, c + Offset(cos(a0), sin(a0)) * lr, '0', tickColor);
    _label(canvas, c + Offset(cos(a100), sin(a100)) * lr, '100', tickColor);

    // 内圈装饰
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppTheme.green.withOpacity(0.08);
    canvas.drawCircle(c, r * 82 / 104, inner);
  }

  void _label(Canvas canvas, Offset p, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2 - 2));
  }

  Rect _arcRect(Offset c, double r) => Rect.fromCircle(center: c, radius: r);
  Rect _gaugeRect(Offset c, double r) => Rect.fromCircle(center: c, radius: r * 1.5);

  void _paintArc(
      Canvas canvas, Rect arc, double startDeg, double sweepDeg, Paint paint) {
    canvas.drawArc(arc, _rad(startDeg), _rad(sweepDeg), false, paint);
  }

  double _rad(double deg) => deg * pi / 180;

  @override
  bool shouldRepaint(_GaugePainter old) => old.pct != pct;
}
