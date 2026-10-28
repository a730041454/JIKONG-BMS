import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 能量环表盘（参照极空 App）：270° 弧，左下角 0、右下角满。
/// 环内为大号 SOC，电压/电流以描边胶囊显示；弧上带刻度点与霓虹发光。
class SocGauge extends StatelessWidget {
  final double soc;
  final double totalVoltage;
  final double current;
  final double power;

  const SocGauge({
    super.key,
    required this.soc,
    required this.totalVoltage,
    required this.current,
    required this.power,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = min(c.maxWidth, 292.0);
      final pct = soc.clamp(0, 100).toDouble();
      final track = surface2Of(context).withOpacity(.85);
      return Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(pct: pct, size: size, trackColor: track),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${pct.round()}%',
                  style: TextStyle(
                      fontSize: 58,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.green,
                      height: 1.05,
                      letterSpacing: -1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(color: AppTheme.green.withOpacity(.55), blurRadius: 18),
                      ])),
              const SizedBox(height: 8),
              _Capsule(text: '${totalVoltage.toStringAsFixed(2)}V', fontSize: 16),
              const SizedBox(height: 5),
              _Capsule(text: '${current.toStringAsFixed(2)}A', fontSize: 15),
              const SizedBox(height: 5),
              _Capsule(text: '${power.toStringAsFixed(1)}W', fontSize: 16),
            ],
          ),
        ],
      );
    });
  }
}

class _Capsule extends StatelessWidget {
  final String text;
  final double fontSize;
  const _Capsule({required this.text, this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: 132,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.green.withOpacity(.55), width: 1.4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: onSurface,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double pct;
  final double size;
  final Color trackColor;

  _GaugePainter({
    required this.pct,
    required this.size,
    required this.trackColor,
  });

  static const double _startDeg = 135; // 左下角为 0
  static const double _sweepDeg = 270; // 右下角为满

  @override
  void paint(Canvas canvas, Size size0) {
    final c = Offset(size / 2, size / 2);
    final r = size * 0.405;
    final arc = Rect.fromCircle(center: c, radius: r);

    // 底轨
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arc, _rad(_startDeg), _rad(_sweepDeg), false, track);

    // 进度弧（绿→青）+ 外发光
    if (pct > 0) {
      final shader = SweepGradient(
        startAngle: _rad(_startDeg),
        endAngle: _rad(_startDeg + _sweepDeg),
        colors: const [AppTheme.green, Color(0xFF19E0B0), AppTheme.cyan],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.6));
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round
        ..color = AppTheme.green.withOpacity(.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      final sweep = _rad(_sweepDeg * pct / 100);
      canvas.drawArc(arc, _rad(_startDeg), sweep, false, glow);
      canvas.drawArc(arc, _rad(_startDeg), sweep, false, paint);
    }

    // 刻度点（5% 一格，25% 大点）
    for (var p = 0; p <= 100; p += 5) {
      final a = _rad(_startDeg + _sweepDeg * p / 100);
      final major = p % 25 == 0;
      final rr = r * (major ? 0.885 : 0.905);
      final dot = Paint()
        ..color = Colors.white.withOpacity(major ? .55 : .22);
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * rr, major ? 1.9 : 1.2, dot);
    }

    // 0 / 100 标签
    final lr = r * 1.19;
    final a0 = _rad(_startDeg), a100 = _rad(_startDeg + _sweepDeg);
    _label(canvas, c + Offset(cos(a0), sin(a0)) * lr, '0');
    _label(canvas, c + Offset(cos(a100), sin(a100)) * lr, '100');
  }

  void _label(Canvas canvas, Offset p, String text) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: Colors.white.withOpacity(.45),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  double _rad(double deg) => deg * pi / 180;

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.pct != pct || old.trackColor != trackColor;
}
