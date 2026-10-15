import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 实时状态：实时数据键值 + 单体电压（最高蓝/最低红）+ 均衡线电阻。
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

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
        _SecTitle(t('rd_title'), dim),
        _Grid(rows: [
          ('${t('rd_power')} ·', d == null ? dash : '${fmt(d.power, 1)}W', true),
          ('${t('rd_cap')} ·', d == null ? dash : '${fmt(app.nominal, 1)}Ah', false),
          ('${t('rd_delta')} ·', d == null ? dash : '${fmt(d.maxCellV - d.minCellV, 3)}V', false),
          ('${t('rd_rem')} ·', d == null ? dash : '${fmt(d.remainingCapacity, 1)}Ah', false),
          ('${t('rd_bcur')} ·', d == null ? dash : '${fmt(app.balancing ? 0.639 : 0, 3)}A', false),
          ('${t('rd_ptemp')} ·', d == null ? dash : '${fmt(d.maxTemp, 1)}℃', false),
          ('${t('rd_cycles')} ·', d == null ? dash : '0${t('u_times')}', false),
          ('${t('rd_t1')} ·', d == null ? dash : '${fmt(d.temperatures.isNotEmpty ? d.temperatures.first : 0, 1)}℃', false),
          ('${t('rd_ccap')} ·', d == null ? dash : '${fmt(app.nominal * 0.35, 1)}Ah', false),
          ('${t('rd_t2')} ·', d == null ? dash : '${fmt(d.temperatures.length > 1 ? d.temperatures[1] : 0, 1)}℃', false),
          ('${t('rd_sleep')} ·', d == null ? dash : '${d.sleepSeconds}s', false),
          ('${t('rd_type')} ·', t('li_iron'), false),
          ('${t('rd_buz')} ·', t('off'), false),
          ('${t('rd_bal')} ·', t(app.balancing ? 'on' : 'off'), true),
          ('${t('rd_cells')} ·', '${app.cells}${t('u_series')}', false),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Box(label: t('lf_volt'), value: d == null ? dash : '${fmt(d.totalVoltage, 2)}V', green: true),
          const SizedBox(width: 8),
          _Box(label: t('lf_cur'), value: d == null ? dash : '${fmt(d.current, 2)}A', green: false),
        ]),
        _SecTitle(t('sec_cell'), dim),
        _CellGrid(app: app),
        _SecTitle(t('sec_res'), dim),
        _ResGrid(app: app),
      ],
    );
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
  final bool green;
  const _Box({required this.label, required this.value, required this.green});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(.55))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: green ? AppTheme.green : Theme.of(context).colorScheme.onSurface)),
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
    final vs = d?.cellVoltages ?? const <double>[];
    final maxV = app.maxCellV, minV = app.minCellV;
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
          if (v == maxV) c = AppTheme.blue;
          else if (v == minV) c = AppTheme.red;
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
    final res = d?.cellResistances ?? const <double>[];
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
