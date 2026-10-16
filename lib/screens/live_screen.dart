import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 实时状态：实时数据键值 + 单体电压（最高蓝/最低红）+ 均衡线电阻 + 图表模式。
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool _chart = false; // 图表模式

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final d = app.data;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);

    String fmt(double v, int n) => v.toStringAsFixed(n);
    String dash = '--';

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        // 模式切换：数据 / 图表
        Row(children: [
          _ModeBtn(
              label: t('mode_list'), on: !_chart, onTap: () => setState(() => _chart = false)),
          const SizedBox(width: 8),
          _ModeBtn(
              label: t('mode_chart'), on: _chart, onTap: () => setState(() => _chart = true)),
        ]),
        const SizedBox(height: 10),
        if (_chart) ...[
          _ChartCard(app: app),
        ] else ...[
          // 关键指标：电压（绿）/ 电流（青）/ 功率（橙），发光
          Row(children: [
            _Box(label: t('lf_volt'), value: d == null ? dash : '${fmt(d.totalVoltage, 2)}V', color: AppTheme.green),
            const SizedBox(width: 8),
            _Box(label: t('lf_cur'), value: d == null ? dash : '${fmt(d.current, 2)}A', color: AppTheme.cyan),
            const SizedBox(width: 8),
            _Box(label: t('l_pow'), value: d == null ? dash : '${fmt(d.power, 1)}W', color: AppTheme.orange),
          ]),
          const SizedBox(height: 10),
          // SOC 能量条
          if (d != null) _SocBar(soc: d.soc, remaining: d.remainingCapacity, nominal: app.nominal),
          const SizedBox(height: 10),
          // 容量 / 剩余 / SOC / 温度
          _MetricRow([
            _m(t('rd_cap'), d == null ? dash : '${fmt(app.nominal, 1)}Ah', dim),
            _m(t('rd_rem'), d == null ? dash : '${fmt(d.remainingCapacity, 1)}Ah', dim),
            _m(t('rd_soc'), d == null ? dash : '${fmt(d.soc, 1)}%', dim),
            _m(t('rd_ptemp'), d == null ? dash : '${fmt(d.maxTemp, 1)}℃', dim),
          ]),
          _SecTitle(t('sec_cell'), dim),
          _HudPanel(child: _CellGrid(app: app)),
          // 温度：T1 保护板 / T2 电池 / T3 机箱内部
          if (d != null && d.temperatures.isNotEmpty) ...[
            _SecTitle(t('temp_title'), dim),
            _TempRow(
              temps: d.temperatures,
              dim: dim,
              labels: [
                t('tp_t1'), t('tp_t2'), t('tp_t3'),
                ...List.generate(d.temperatures.length - 3, (i) => 'T${i + 4}'),
              ],
            ),
          ],
          // 均衡线电阻
          _SecTitle(t('sec_res'), dim),
          _HudPanel(child: _ResGrid(app: app)),
          _SecTitle(t('rd_title'), dim),
          _Grid(rows: [
            ('${t('rd_delta')} ·', d == null ? dash : '${fmt(d.maxCellV - d.minCellV, 3)}V', false),
            ('${t('rd_cycles')} ·', '0${t('u_times')}', false),
            ('${t('rd_sleep')} ·', d == null ? dash : '${d.sleepSeconds}s', false),
            ('${t('rd_type')} ·', t('li_iron'), false),
            ('${t('rd_buz')} ·', t('off'), false),
            ('${t('rd_cells')} ·', '${app.cells}${t('u_series')}', false),
          ]),
        ],
      ],
    );
  }

  _Metric _m(String k, String v, Color dim) => _Metric(k, v, dim);
}

class _Metric {
  final String label;
  final String value;
  final Color dim;
  _Metric(this.label, this.value, this.dim);
}

class _MetricRow extends StatelessWidget {
  final List<_Metric> items;
  const _MetricRow(this.items);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    return Container(
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surface2),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 40, color: surface2),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
              color: surface,
              child: Column(children: [
                Text(items[i].value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.green)),
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

class _TempRow extends StatelessWidget {
  final List<double> temps;
  final Color dim;
  final List<String> labels;
  const _TempRow({required this.temps, required this.dim, List<String>? labels})
      : labels = labels ??
            [for (var i = 0; i < temps.length; i++) 'T${i + 1}'];

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Row(children: [
      for (var i = 0; i < temps.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(i < labels.length ? labels[i] : 'T${i + 1}',
                  style: TextStyle(fontSize: 10, color: dim)),
              const SizedBox(height: 3),
              Text(temps[i].toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.green)),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _SecTitle extends StatelessWidget {
  final String text;
  final Color dim;
  const _SecTitle(this.text, this.dim);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dim)));
}

class _Grid extends StatelessWidget {
  final List<(String, String, bool)> rows;
  const _Grid({required this.rows});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      decoration: BoxDecoration(
          color: surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: surface2)),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: i.isEven ? surface : surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(rows[i].$1,
                    style: TextStyle(fontSize: 12, color: dim)),
                Text(rows[i].$2,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: rows[i].$3 ? AppTheme.green : Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: color,
                  shadows: [Shadow(color: color.withOpacity(.45), blurRadius: 10)])),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: dim)),
        ]),
      ),
    );
  }
}

class _CellGrid extends StatelessWidget {
  final AppState app;
  const _CellGrid({required this.app});

  @override
  Widget build(BuildContext context) {
    final d = app.data;
    // 只显示已连接的单体电压（过滤未连接的 0 值）
    final vs = (d?.cellVoltages ?? const <double>[])
        .where((v) => v > 0.1)
        .toList();
    final maxV = app.maxCellV, minV = app.minCellV;
    // 只标记最高/最低的其中一个单体（最高蓝、最低红）
    final maxIdx = vs.indexWhere((x) => x == maxV);
    final minIdx = vs.indexWhere((x) => x == minV);
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      decoration: BoxDecoration(
          color: surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: surface2)),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        children: List.generate(vs.length, (i) {
          final v = vs[i];
          Color c = AppTheme.green;
          if (i == maxIdx) c = AppTheme.blue;
          else if (i == minIdx) c = AppTheme.red;
          return Container(
            color: surface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Text('${(i + 1).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, color: dim)),
              const SizedBox(height: 2),
              Text(v.toStringAsFixed(3),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
            ]),
          );
        }),
      ),
    );
  }
}

class _ResGrid extends StatelessWidget {
  final AppState app;
  const _ResGrid({required this.app});

  @override
  Widget build(BuildContext context) {
    final d = app.data;
    // 只显示已连接单体的均衡线电阻（过滤未连接的 0 值）
    final res = (d?.cellResistances ?? const <double>[])
        .where((r) => r > 0.001)
        .toList();
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      decoration: BoxDecoration(
          color: surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: surface2)),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        children: List.generate(res.length, (i) {
          return Container(
            color: surface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Text('${(i + 1).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, color: dim)),
              const SizedBox(height: 2),
              Text(res[i].toStringAsFixed(3),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.green)),
            ]),
          );
        }),
      ),
    );
  }
}

/// 模式切换按钮（数据 / 图表）。
class _ModeBtn extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: on
                    ? AppTheme.green.withOpacity(.6)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(.12)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? AppTheme.green : dim)),
        ),
      ),
    );
  }
}

/// 图表模式：SOC / 总电压 / 电流 历史曲线。
class _ChartCard extends StatelessWidget {
  final AppState app;
  const _ChartCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final en = app.isEn;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(L.tr(en, 'chart_title'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 190,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              app.histSoc,
              app.histVoltage,
              app.histCurrent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend(AppTheme.green, L.tr(en, 'rd_soc'), dim),
          const SizedBox(width: 14),
          _legend(AppTheme.blue, L.tr(en, 'lf_volt'), dim),
          const SizedBox(width: 14),
          _legend(AppTheme.cyan, L.tr(en, 'lf_cur'), dim),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String label, Color dim) => Row(children: [
        Container(width: 10, height: 3, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: dim)),
      ]);
}

/// 历史曲线绘图器（三条线各自归一化绘制）。
class _ChartPainter extends CustomPainter {
  final List<double> soc;
  final List<double> voltage;
  final List<double> current;
  _ChartPainter(this.soc, this.voltage, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 网格
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
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
        ..strokeJoin = StrokeJoin.round;
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
  bool shouldRepaint(covariant _ChartPainter old) => true;
}

/// SOC 能量条：渐变填充 + 剩余容量 + 0-100 刻度。
class _SocBar extends StatelessWidget {
  final double soc;
  final double remaining;
  final double nominal;
  const _SocBar({required this.soc, required this.remaining, required this.nominal});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final surface = Theme.of(context).colorScheme.surface;
    final pct = soc.clamp(0.0, 100.0) / 100.0;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('SOC', style: TextStyle(fontSize: 12, color: dim)),
          Text('${soc.toStringAsFixed(1)}% · ${remaining.toStringAsFixed(1)}/${nominal.toStringAsFixed(1)}Ah',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.green)),
        ]),
        const SizedBox(height: 8),
        Stack(children: [
          Container(
            height: 9,
            decoration: BoxDecoration(
                color: surface2Of(context), borderRadius: BorderRadius.circular(5)),
          ),
          FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                      colors: [AppTheme.green, AppTheme.cyan]),
                  boxShadow: [
                    BoxShadow(color: AppTheme.green.withOpacity(.5), blurRadius: 8)
                  ]),
            ),
          ),
        ]),
        const SizedBox(height: 5),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0', style: TextStyle(fontSize: 9, color: dim)),
          Text('50', style: TextStyle(fontSize: 9, color: dim)),
          Text('100%', style: TextStyle(fontSize: 9, color: dim)),
        ]),
      ]),
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
      padding: const EdgeInsets.all(12),
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
