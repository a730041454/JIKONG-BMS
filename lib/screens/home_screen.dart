import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/no_connection.dart';
import '../widgets/soc_gauge.dart';

/// 首页：顶部开关状态条 + 能量环 + 指标卡 + 电流/功率/状态。
///
/// 开关位置：放电、充电、均衡三块并排。
/// 开关值来自保护板 settings 帧的使能位，点击后乐观更新并回读校验。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.data == null) return const NoConnection();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);

    void toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));

    return Column(children: [
      _SwitchBar(app: app, t: t, toast: toast),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _GaugePanel(app: app),
            const SizedBox(height: 10),
            _MetricRow([
              _m(t('m_maxV'), app.maxCellV.toStringAsFixed(3),
                  valueColor: AppTheme.blue),
              _m(t('m_minV'), app.minCellV.toStringAsFixed(3),
                  valueColor: AppTheme.red),
              _m(t('m_delta'),
                  (app.maxCellV - app.minCellV).toStringAsFixed(3)),
              _m(t('m_bal'), app.balanceCurrent.toStringAsFixed(3)),
            ]),
            const SizedBox(height: 10),
            _MetricRow([
              _m(t('m_cap'), app.nominal.toStringAsFixed(1)),
              _m(t('m_rem'), app.remaining.toStringAsFixed(1)),
              _m(t('m_temp'), app.maxTemp.toStringAsFixed(1)),
              _m(t('m_type'), t('li_iron')),
            ]),
            const SizedBox(height: 10),
            _CurrentPowerCard(
              current: app.current,
              power: app.power,
              stateText: t(app.stateKey),
              stateColor: _stateColor(app),
              dim: dim,
            ),
            const SizedBox(height: 12),
            _InverterCard(app: app, t: t, dim: dim),
          ],
        ),
      ),
    ]);
  }
}

_Metric _m(String k, String v, {Color valueColor = AppTheme.green}) =>
    _Metric(k, v, valueColor);

Color _stateColor(AppState app) {
  if (app.alarm) return AppTheme.red;
  final c = app.current;
  if (c >= 0.2) return AppTheme.green; // 充电中
  if (c <= -0.2) return AppTheme.cyan; // 放电中
  return AppTheme.darkDim;
}

/// 顶部开关栏：放电、充电、均衡三个可点击开关（整块可点），下方显示预充状态。
class _SwitchBar extends StatelessWidget {
  final AppState app;
  final String Function(String) t;
  final void Function(String) toast;
  const _SwitchBar({required this.app, required this.t, required this.toast});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void tap(VoidCallback fn) {
      fn();
      toast(t('toast_cmd_sent'));
    }

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _ToggleTile(
              icon: Icons.power_settings_new,
              label: t('sw_discharge'),
              on: app.discharging,
              color: AppTheme.cyan,
              onText: t('on'),
              offText: t('off'),
              onChanged: () => tap(app.toggleDischarge),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToggleTile(
              icon: Icons.bolt,
              label: t('sw_charge'),
              on: app.charging,
              color: AppTheme.green,
              onText: t('on'),
              offText: t('off'),
              onChanged: () => tap(app.toggleCharge),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToggleTile(
              icon: Icons.balance,
              label: t('sw_balance'),
              on: app.balancing,
              color: AppTheme.orange,
              onText: t('on'),
              offText: t('off'),
              onChanged: () => tap(app.toggleBalance),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _MiniState(label: t('sw_precharge'), on: app.precharge),
        ),
      ]),
    );
  }
}

/// 顶部开关卡片：图标 + 名称，状态文字 + 迷你开关（点击整块切换）。
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final Color color;
  final String onText;
  final String offText;
  final VoidCallback onChanged;
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.color,
    required this.onText,
    required this.offText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
        decoration: BoxDecoration(
          color: on ? color.withOpacity(.10) : surface2Of(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? color.withOpacity(.55) : onSurface.withOpacity(.07)),
          boxShadow: on
              ? [BoxShadow(color: color.withOpacity(.22), blurRadius: 12)]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: on ? color : dim),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: on ? color : onSurface)),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text(on ? onText : offText,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: on ? color : dim)),
            const Spacer(),
            _MiniSwitch(on: on, color: color),
          ]),
        ]),
      ),
    );
  }
}

/// 迷你开关：三块并排时比 Material Switch 更省空间。
class _MiniSwitch extends StatelessWidget {
  final bool on;
  final Color color;
  const _MiniSwitch({required this.on, required this.color});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 34,
      height: 19,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: on ? color : onSurface.withOpacity(.14),
        border: Border.all(color: on ? color : onSurface.withOpacity(.20)),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? Colors.white : onSurface.withOpacity(.55),
            boxShadow: on
                ? [BoxShadow(color: Colors.black.withOpacity(.18), blurRadius: 2)]
                : null,
          ),
        ),
      ),
    );
  }
}

/// 只读状态（放电/预充）。
class _MiniState extends StatelessWidget {
  final String label;
  final bool on;
  const _MiniState({required this.label, required this.on});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final color = on ? AppTheme.green : AppTheme.red;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 12, color: dim)),
      const SizedBox(width: 5),
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: on ? [BoxShadow(color: color.withOpacity(.9), blurRadius: 6)] : null,
        ),
      ),
      const SizedBox(width: 4),
      Text(on ? 'ON' : 'OFF',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

/// 表盘面板：四角霓虹角标 + 轻微发光。
class _GaugePanel extends StatelessWidget {
  final AppState app;
  const _GaugePanel({required this.app});

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
              top: top
                  ? const BorderSide(color: AppTheme.green, width: 2)
                  : BorderSide.none,
              bottom: top
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.green, width: 2),
              left: left
                  ? const BorderSide(color: AppTheme.green, width: 2)
                  : BorderSide.none,
              right: left
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.green, width: 2),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: surface,
        border: Border.all(color: AppTheme.green.withOpacity(.18)),
        boxShadow: [
          BoxShadow(color: AppTheme.green.withOpacity(.06), blurRadius: 22),
        ],
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
          child: Center(
            child: SocGauge(
              soc: app.soc,
              totalVoltage: app.totalVoltage,
              current: app.current,
              power: app.power,
            ),
          ),
        ),
        _corner(true, true),
        _corner(true, false),
        _corner(false, true),
        _corner(false, false),
      ]),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final Color valueColor;
  _Metric(this.label, this.value, this.valueColor);
}

class _MetricRow extends StatelessWidget {
  final List<_Metric> items;
  const _MetricRow(this.items);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: surface2Of(context).withOpacity(.7)),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
                width: 1,
                height: 38,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.07)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              child: Column(children: [
                Text(items[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: items[i].valueColor,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 3),
                Text(items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: dim)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// 电流 / 功率 / 状态卡（对应参考图底部区域）。
class _CurrentPowerCard extends StatelessWidget {
  final double current;
  final double power;
  final String stateText;
  final Color stateColor;
  final Color dim;
  const _CurrentPowerCard({
    required this.current,
    required this.power,
    required this.stateText,
    required this.stateColor,
    required this.dim,
  });

  Widget _item(
      BuildContext context, IconData icon, String label, String value) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.green.withOpacity(.45))),
        child: Icon(icon, size: 14, color: AppTheme.green),
      ),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: dim)),
      Text(value,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final t = (k) => L.tr(context.watch<AppState>().isEn, k);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: _item(context, Icons.swap_vert, '${t('l_cur')}: ',
                  current.toStringAsFixed(2))),
          Expanded(
              child: _item(context, Icons.power_settings_new,
                  '${t('l_pow')}: ', power.toStringAsFixed(1))),
        ]),
        const SizedBox(height: 10),
        Container(
          height: 4,
          decoration: BoxDecoration(
              color: surface2Of(context), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text('${t('l_state')}: ',
              style: TextStyle(fontSize: 14, color: dim)),
          Text(stateText,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: stateColor)),
        ]),
      ]),
    );
  }
}

/// 逆变器电气数据面板。
///
/// 默认只显示 8 个常用测点，点标题展开查看全部；
/// 逆变器没接（或网关 INV 口还没取到数据）时只显示引导文案。
class _InverterCard extends StatefulWidget {
  final AppState app;
  final String Function(String) t;
  final Color dim;
  const _InverterCard({required this.app, required this.t, required this.dim});

  @override
  State<_InverterCard> createState() => _InverterCardState();
}

class _InverterCardState extends State<_InverterCard> {
  bool _open = false;

  String _v(double? x, [int d = 1]) =>
      x == null ? '--' : x.toStringAsFixed(d);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = widget.t;
    final dim = widget.dim;
    final inv = app.inv;
    final surface = Theme.of(context).colorScheme.surface;
    final pvW = [
      inv.pv1Power,
      inv.pv2Power,
    ].where((e) => e != null).fold<double?>(null, (a, b) => (a ?? 0) + b!);

    if (!inv.hasData) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.compare_arrows, size: 18, color: dim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('iv_sec')} · ${t('iv_none')}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: dim)),
              const SizedBox(height: 3),
              Text(t('iv_none_hint'),
                  style: TextStyle(fontSize: 11.5, color: dim, height: 1.4)),
            ]),
          ),
        ]),
      );
    }

    final modeColor = inv.fault ? AppTheme.red : AppTheme.cyan;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: modeColor.withOpacity(.18)),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
            child: Row(children: [
              Icon(Icons.compare_arrows, size: 17, color: modeColor),
              const SizedBox(width: 7),
              Text(t('iv_sec'),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(inv.modeText ?? '--',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: modeColor)),
              ),
              const Spacer(),
              Text(_open ? t('iv_less') : t('iv_more'),
                  style: TextStyle(fontSize: 11, color: dim)),
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: dim),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: _MetricRow([
            _m(t('iv_grid_v'), _v(inv.gridVoltage)),
            _m(t('iv_out_w'), _v(inv.outputPower, 0), valueColor: AppTheme.cyan),
            _m(t('iv_pv1_w'), _v(pvW, 0), valueColor: AppTheme.orange),
            _m(t('iv_batt_v'), _v(inv.batteryVoltage)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: _MetricRow([
            _m(t('iv_out_v'), _v(inv.outputVoltage)),
            _m(t('iv_batt_a'), _v(inv.batteryCurrent),
                valueColor: AppTheme.blue),
            _m(t('iv_load'), _v(inv.loadPercent, 0)),
            _m(t('iv_temp'), _v(inv.temperature),
                valueColor: (inv.temperature ?? 0) > 60 ? AppTheme.red : AppTheme.green),
          ]),
        ),
        if (inv.fault)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: AppTheme.red),
              const SizedBox(width: 6),
              Text(inv.faultText ?? t('iv_fault'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.red)),
            ]),
          ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              _InvGroup(label: t('iv_grid'), rows: [
                _Pair(t('iv_grid_v'), _v(inv.gridVoltage)),
                _Pair(t('iv_grid_f'), _v(inv.gridFrequency, 2)),
                _Pair(t('iv_grid_w'), _v(inv.gridPower, 0)),
              ]),
              _InvGroup(label: t('iv_output'), rows: [
                _Pair(t('iv_out_v'), _v(inv.outputVoltage)),
                _Pair(t('iv_out_a'), _v(inv.outputCurrent, 2)),
                _Pair(t('iv_out_f'), _v(inv.outputFrequency, 2)),
                _Pair(t('iv_out_w'), _v(inv.outputPower, 0)),
                _Pair(t('iv_out_va'), _v(inv.outputVa, 0)),
                _Pair(t('iv_load'), _v(inv.loadPercent, 0)),
              ]),
              _InvGroup(label: t('iv_battery'), rows: [
                _Pair(t('iv_batt_v'), _v(inv.batteryVoltage)),
                _Pair(t('iv_batt_a'), _v(inv.batteryCurrent, 1)),
                _Pair(t('iv_batt_soc'), _v(inv.batterySoc, 0)),
                _Pair(t('iv_chg_w'), _v(inv.batteryChargePower, 0)),
              ]),
              _InvGroup(label: t('iv_pv'), rows: [
                _Pair(t('iv_pv1_v'), _v(inv.pv1Voltage)),
                _Pair(t('iv_pv1_w'), _v(inv.pv1Power, 0)),
                _Pair(t('iv_pv2_v'), _v(inv.pv2Voltage)),
                _Pair(t('iv_pv2_w'), _v(inv.pv2Power, 0)),
              ]),
              _InvGroup(label: t('iv_heat'), rows: [
                _Pair(t('iv_temp'), _v(inv.temperature)),
                _Pair(t('iv_fan'), _v(inv.fanDuty, 0)),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Text(app.invProtocolLabel,
                      style: TextStyle(fontSize: 11, color: dim)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Pair {
  final String label;
  final String value;
  const _Pair(this.label, this.value);
}

/// 展开后的分测点分组表。
class _InvGroup extends StatelessWidget {
  final String label;
  final List<_Pair> rows;
  const _InvGroup({required this.label, required this.rows});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.5);
    final base = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: dim)),
        const SizedBox(height: 2),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.5),
            child: Row(children: [
              Expanded(child: Text(r.label, style: TextStyle(fontSize: 12.5, color: dim))),
              Text(r.value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: base,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ]),
    );
  }
}
