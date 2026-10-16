import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/soc_gauge.dart';

/// 首页：充电/放电/均衡开关、能量环、状态徽标、指标、电流/功率。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final text = Theme.of(context).colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        // 放电开关（充电/均衡开关已移到参数设置页）
        Row(children: [
          _Switch(k: 'sw_discharge', on: app.discharging, onTap: app.toggleDischarge),
        ]),
        const SizedBox(height: 6),
        _HudPanel(
          child: Column(children: [
            Center(child: SocGauge(
                soc: app.soc, totalVoltage: app.totalVoltage, current: app.current)),
            const SizedBox(height: 8),
            // 能量轴（0-100% 能量刻度条）
            _EnergyAxis(soc: app.soc),
          ]),
        ),
        const SizedBox(height: 10),
        // 状态徽标
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _stateColor(app).withOpacity(.5)),
                boxShadow: [
                  BoxShadow(color: _stateColor(app).withOpacity(.22), blurRadius: 14)
                ]),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _stateColor(app),
                      boxShadow: [
                        BoxShadow(color: _stateColor(app), blurRadius: 8)
                      ]),
                ),
                const SizedBox(width: 7),
                Text(t(app.stateKey),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _stateColor(app))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 告警横幅
        if (app.alarm)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
                color: AppTheme.orange.withOpacity(.14),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.orange.withOpacity(.5))),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 16, color: AppTheme.orange),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(t('alert_ovp'),
                      style: const TextStyle(color: AppTheme.orange, fontSize: 14))),
            ]),
          ),
        const SizedBox(height: 12),
        // 指标两排
        _MetricRow([
          _m(t('m_maxV'), '${app.maxCellV.toStringAsFixed(3)}', text, dim, valueColor: AppTheme.blue),
          _m(t('m_minV'), '${app.minCellV.toStringAsFixed(3)}', text, dim, valueColor: AppTheme.red),
          _m(t('m_delta'), '${(app.maxCellV - app.minCellV).toStringAsFixed(3)}', text, dim),
          _m(t('m_bal'), '${(app.balancing ? 0.639 : 0).toStringAsFixed(3)}', text, dim),
        ]),
        const SizedBox(height: 12),
        _MetricRow([
          _m(t('m_cap'), app.nominal.toStringAsFixed(1), text, dim),
          _m(t('m_rem'), app.remaining.toStringAsFixed(1), text, dim),
          _m(t('m_rem_time'), app.remainingHours.toStringAsFixed(1), text, dim, valueColor: AppTheme.cyan),
          _m(t('m_type'), t('li_iron'), text, dim),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Box(label: t('l_cur'), value: '${app.current.toStringAsFixed(2)}A', color: AppTheme.cyan),
          const SizedBox(width: 8),
          _Box(label: t('l_pow'), value: '${app.power.toStringAsFixed(1)}W', color: AppTheme.orange),
        ]),
        const SizedBox(height: 8),
        // 状态行
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text(t('l_state'),
                style: TextStyle(fontSize: 14, color: dim)),
            const SizedBox(width: 8),
            Text(t(app.stateKey),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _stateColor(app))),
          ]),
        ),
        const SizedBox(height: 14),
        // 历史曲线（SOC / 电压 / 电流）
        _HudPanel(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(t('chart_title'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text('${t('rd_soc')} · ${t('lf_volt')} · ${t('lf_cur')}',
                  style: TextStyle(fontSize: 10, color: dim)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _HomeChartPainter(
                    app.histSoc, app.histVoltage, app.histCurrent),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legend(AppTheme.green, t('rd_soc'), dim),
              const SizedBox(width: 14),
              _legend(AppTheme.blue, t('lf_volt'), dim),
              const SizedBox(width: 14),
              _legend(AppTheme.cyan, t('lf_cur'), dim),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _legend(Color c, String label, Color dim) => Row(children: [
        Container(width: 12, height: 3, decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: c.withOpacity(.5), blurRadius: 4)])),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: dim)),
      ]);

  _Metric _m(String k, String v, Color text, Color dim,
          {Color valueColor = AppTheme.green}) =>
      _Metric(k, v, text, dim, valueColor: valueColor);
}

Color _stateColor(AppState app) {
  if (app.alarm) return AppTheme.red;
  final c = app.current;
  if (c >= 0.2) return AppTheme.green; // 充电中
  if (c <= -0.2) return AppTheme.cyan; // 放电中（同网页预览青色）
  return AppTheme.darkDim;
}

/// 能量轴：0-100% 能量刻度条（对应网页预览能量环下方能量轴）。
class _EnergyAxis extends StatelessWidget {
  final double soc;
  const _EnergyAxis({required this.soc});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final surface = Theme.of(context).colorScheme.surface;
    final pct = soc.clamp(0.0, 100.0) / 100.0;
    return Column(children: [
      Stack(children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(5)),
        ),
        FractionallySizedBox(
          widthFactor: pct,
          child: Container(
            height: 10,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(colors: [
                  AppTheme.green.withOpacity(.55),
                  AppTheme.green,
                  AppTheme.cyan,
                ])),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('0', style: TextStyle(fontSize: 10, color: dim)),
        Text('50', style: TextStyle(fontSize: 10, color: dim)),
        Text('100%', style: TextStyle(fontSize: 10, color: dim)),
      ]),
    ]);
  }
}

class _Switch extends StatelessWidget {
  final String k;
  final bool on;
  final VoidCallback onTap;
  const _Switch({required this.k, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (key) => L.tr(app.isEn, key);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final surface = Theme.of(context).colorScheme.surface;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // 状态文字：放电中（青）/ 关闭（灰）
    final stateText = on
        ? (app.current <= -0.2 ? t('st_discharging') : t('on'))
        : t('off');
    final stateColor = on
        ? (app.current <= -0.2 ? AppTheme.cyan : AppTheme.green)
        : dim;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? AppTheme.green.withOpacity(.55) : surface),
          boxShadow: on
              ? [BoxShadow(color: AppTheme.green.withOpacity(.25), blurRadius: 12)]
              : null,
        ),
        child: Row(children: [
          Text(t(k),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 2)),
          const SizedBox(width: 10),
          Text(stateText,
              style: TextStyle(fontSize: 11, color: stateColor)),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 24,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                color: on
                    ? AppTheme.green.withOpacity(.35)
                    : surface2Of(context),
                borderRadius: BorderRadius.circular(12),
                boxShadow: on
                    ? [BoxShadow(color: AppTheme.green.withOpacity(.4), blurRadius: 10)]
                    : null),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? AppTheme.green : dim,
                    boxShadow: on
                        ? [BoxShadow(color: AppTheme.green, blurRadius: 6)]
                        : null)),
          ),
        ]),
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final Color text;
  final Color dim;
  final Color valueColor;
  _Metric(this.label, this.value, this.text, this.dim, {this.valueColor = AppTheme.green});
}

class _MetricRow extends StatelessWidget {
  final List<_Metric> items;
  const _MetricRow(this.items);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface2Of(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surface2Of(context)),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(width: 1, height: 40, color: surface2Of(context)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
              color: surface,
              child: Column(children: [
                Text(items[i].value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: items[i].valueColor)),
                const SizedBox(height: 2),
                Text(items[i].label,
                    style: TextStyle(fontSize: 10, color: items[i].dim)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Box extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Box({required this.label, required this.value, this.color = AppTheme.green});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: dim)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                  shadows: [Shadow(color: color.withOpacity(.45), blurRadius: 10)])),
        ]),
      ),
    );
  }
}

/// HUD 面板：半透明深色底 + 霓虹描边 + 四角绿色角标。
class _HudPanel extends StatelessWidget {
  final Widget child;
  const _HudPanel({required this.child});

  Widget _corner(bool top, bool left) => Positioned(
        top: top ? 6 : null,
        bottom: top ? null : 6,
        left: left ? 6 : null,
        right: left ? null : 6,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            border: Border(
              top: top ? const BorderSide(color: AppTheme.green, width: 2) : BorderSide.none,
              bottom: top ? BorderSide.none : const BorderSide(color: AppTheme.green, width: 2),
              left: left ? const BorderSide(color: AppTheme.green, width: 2) : BorderSide.none,
              right: left ? BorderSide.none : const BorderSide(color: AppTheme.green, width: 2),
            ),
            borderRadius: BorderRadius.only(
              topLeft: top && left ? const Radius.circular(8) : Radius.zero,
              topRight: top && !left ? const Radius.circular(8) : Radius.zero,
              bottomLeft: !top && left ? const Radius.circular(8) : Radius.zero,
              bottomRight: !top && !left ? const Radius.circular(8) : Radius.zero,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.green.withOpacity(.25)),
      ),
      child: Stack(children: [
        child,
        _corner(true, true),
        _corner(true, false),
        _corner(false, true),
        _corner(false, false),
      ]),
    );
  }
}

/// 历史曲线绘图器：SOC（绿）/ 电压（蓝）/ 电流（青），各线归一化绘制。
class _HomeChartPainter extends CustomPainter {
  final List<double> soc;
  final List<double> voltage;
  final List<double> current;
  _HomeChartPainter(this.soc, this.voltage, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final grid = Paint()..color = const Color(0x22FFFFFF);
    for (var i = 0; i <= 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    void drawLine(List<double> data, Color color) {
      if (data.length < 2) return;
      var minV = data.reduce((a, b) => a < b ? a : b);
      var maxV = data.reduce((a, b) => a > b ? a : b);
      if (maxV - minV < 1e-9) maxV = minV + 1e-9;
      final p = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final x = w * i / (data.length - 1);
        final y = h - h * (data[i] - minV) / (maxV - minV);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }

    drawLine(soc, AppTheme.green);
    drawLine(voltage, AppTheme.blue);
    drawLine(current, AppTheme.cyan);
  }

  @override
  bool shouldRepaint(covariant _HomeChartPainter old) => true;
}

/// 连接诊断卡片已删除（v1.0.15 起不再展示）。
