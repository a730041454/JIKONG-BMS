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
        // 充电 / 放电 / 均衡 开关按键
        Row(children: [
          _Switch(k: 'sw_charge', on: app.charging, onTap: app.toggleCharge),
          const SizedBox(width: 8),
          _Switch(k: 'sw_discharge', on: app.discharging, onTap: app.toggleDischarge),
          const SizedBox(width: 8),
          _Switch(k: 'sw_balance', on: app.balancing, onTap: app.toggleBalance),
        ]),
        const SizedBox(height: 6),
        Center(child: SocGauge(
            soc: app.soc, totalVoltage: app.totalVoltage, current: app.current)),
        const SizedBox(height: 8),
        // 状态徽标
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _stateColor(app)),
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
          _m(t('m_maxV'), '${app.maxCellV.toStringAsFixed(3)}', text, dim),
          _m(t('m_minV'), '${app.minCellV.toStringAsFixed(3)}', text, dim),
          _m(t('m_delta'), '${(app.maxCellV - app.minCellV).toStringAsFixed(3)}', text, dim),
          _m(t('m_bal'), '${(app.balancing ? 0.639 : 0).toStringAsFixed(3)}', text, dim),
        ]),
        const SizedBox(height: 12),
        _MetricRow([
          _m(t('m_cap'), app.nominal.toStringAsFixed(1), text, dim),
          _m(t('m_rem'), app.remaining.toStringAsFixed(1), text, dim),
          _m(t('m_temp'), '${app.maxTemp.toStringAsFixed(1)}', text, dim),
          _m(t('m_type'), t('li_iron'), text, dim),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Box(label: t('l_cur'), value: '${app.current.toStringAsFixed(2)}A', green: true),
          const SizedBox(width: 8),
          _Box(label: t('l_pow'), value: '${app.power.toStringAsFixed(1)}W', green: false),
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
      ],
    );
  }

  Widget _m(String k, String v, Color text, Color dim) =>
      _Metric(label: k, value: v, text: text, dim: dim);
}

Color _stateColor(AppState app) {
  if (app.alarm) return AppTheme.red;
  if (app.charging || app.discharging) return AppTheme.green;
  return AppTheme.darkDim;
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(t(k),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? AppTheme.green : dim)),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: on ? AppTheme.green : surface2Of(context),
                  borderRadius: BorderRadius.circular(12)),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: on ? bg : dim)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final Color text;
  final Color dim;
  _Metric(this.label, this.value, this.text, this.dim);
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
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.55))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: green
                      ? AppTheme.green
                      : Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }
}
