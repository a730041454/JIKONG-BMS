import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 参数设置页（受密码保护进入）：快捷功能 / 数据配置 / 控制 / 核心参数 / 保护板块。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cellsCtrl = TextEditingController(text: '16');
  final _capCtrl = TextEditingController(text: '100');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);

    void toast(String msg) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _Section(t('qf_title'), dim),
        Row(children: [
          _QBtn(t('qf_auth'), () => toast(t('toast_demo'))),
          const SizedBox(width: 8),
          _QBtn(t('qf_tern'), () => toast(t('toast_demo'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _QBtn(t('qf_iron'), () => toast(t('toast_demo'))),
          const SizedBox(width: 8),
          _QBtn(t('qf_lto'), () => toast(t('toast_demo'))),
        ]),
        _Section(t('dc_title'), dim),
        Row(children: [
          _QBtn(t('dc_imp'), () => toast(t('toast_demo'))),
          const SizedBox(width: 8),
          _QBtn(t('dc_exp'), () => toast(t('toast_demo'))),
        ]),
        _Section(t('ct_title'), dim),
        _SwitchRow(t('ct_chg'), true, null),
        _SwitchRow(t('ct_dis'), true, null),
        _SwitchRow(t('ct_emer'), false, null),
        _SwitchRow(t('ct_gpsc'), false, null),
        _SwitchRow(t('ct_gpsd'), false, null),
        _SwitchRow(t('ct_scr'), true, null),
        _Section(t('core_title'), dim),
        _ParamRow(
            label: t('core_cells'),
            controller: _cellsCtrl,
            onSave: () async {
              final v = int.tryParse(_cellsCtrl.text) ?? app.cells;
              await app.saveCore(cellCount: v);
              toast(t('toast_saved'));
            }),
        _ParamRow(
            label: t('core_cap'),
            controller: _capCtrl,
            onSave: () async {
              final v = double.tryParse(_capCtrl.text) ?? app.nominal;
              await app.saveCore(capacity: v);
              toast(t('toast_saved'));
            }),
        _Section(t('bal_title'), dim),
        _SwitchRow(t('bal_sw'), app.balancing, app.toggleBalance),
        _ParamRow(label: t('bal_dv'), initial: '0.010', demo: true),
        _ParamRow(label: t('bal_sv'), initial: '3.00', demo: true),
        _ParamRow(label: t('bal_cur'), initial: '0.6', demo: true),
        _Section(t('vp_title'), dim),
        _ParamRow(label: t('vp_ocv'), initial: '3.650', demo: true),
        _ParamRow(label: t('vp_recv'), initial: '3.600', demo: true),
        _ParamRow(label: t('vp_s100'), initial: '3.590', demo: true),
        _ParamRow(label: t('vp_or'), initial: '3.450', demo: true),
        _ParamRow(label: t('vp_ur'), initial: '2.900', demo: true),
        _ParamRow(label: t('vp_s0'), initial: '2.700', demo: true),
        _ParamRow(label: t('vp_uv'), initial: '2.500', demo: true),
        _ParamRow(label: t('vp_off'), initial: '2.45', demo: true),
        _Section(t('cp_title'), dim),
        _ParamRow(label: t('cp_cc'), initial: '100.0', demo: true),
        _ParamRow(label: t('cp_cd'), initial: '60', demo: true),
        _ParamRow(label: t('cp_cdr'), initial: '60', demo: true),
        _ParamRow(label: t('cp_dc'), initial: '100.0', demo: true),
        _ParamRow(label: t('cp_dd'), initial: '300', demo: true),
        _ParamRow(label: t('cp_ddr'), initial: '60', demo: true),
        _SwitchRow(t('cp_d2'), true, null),
        _SwitchRow(t('cp_d3'), true, null),
        _Section(t('tp_title'), dim),
        _SwitchRow(t('tp_nobat'), false, null),
        _ParamRow(label: t('tp_cot'), initial: '70.0', demo: true),
        _ParamRow(label: t('tp_cotr'), initial: '60.0', demo: true),
        _ParamRow(label: t('tp_clt'), initial: '0.0', demo: true),
        _ParamRow(label: t('tp_cltp'), initial: '-40.0', demo: true),
        _ParamRow(label: t('tp_dot'), initial: '70.0', demo: true),
        _ParamRow(label: t('tp_dotr'), initial: '50.0', demo: true),
        _ParamRow(label: t('tp_dlt'), initial: '-30', demo: true),
        _ParamRow(label: t('tp_dltp'), initial: '-35', demo: true),
        _ParamRow(label: t('tp_mos'), initial: '80.0', demo: true),
        _ParamRow(label: t('tp_mosr'), initial: '70.0', demo: true),
        _Section(t('sc_title'), dim),
        _ParamRow(label: t('sc_d'), initial: '5', demo: true),
        _ParamRow(label: t('sc_r'), initial: '5', demo: true),
        _Section(t('ae_title'), dim),
        _SwitchRow(t('ae_break'), false, null),
        _ParamRow(label: t('ae_src'), initial: '09-MOS管超温', demo: true),
        _ParamRow(label: t('ae_trig'), initial: '100', demo: true),
        _ParamRow(label: t('ae_rec'), initial: '95', demo: true),
        _ParamRow(label: t('ae_time'), initial: '30', demo: true),
        _Section(t('ss_title'), dim),
        _SwitchRow(t('ss_sw'), false, null),
        _ParamRow(label: t('ss_v'), initial: '3.500', demo: true),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t('app') + ' · 参数写入需接入真实保护板后按寄存器表执行',
              style: TextStyle(fontSize: 11, color: dim, height: 1.6)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  final Color dim;
  const _Section(this.text, this.dim);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dim)));
}

class _QBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _QBtn(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
            const Icon(Icons.chevron_right, size: 16, color: AppTheme.darkDim),
          ]),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const _SwitchRow(this.label, this.on, this.onTap);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Switch.adaptive(value: on, onChanged: (_) => onTap?.call()),
      ]),
    );
  }
}

class _ParamRow extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? initial;
  final bool demo;
  final VoidCallback? onSave;
  const _ParamRow(
      {required this.label, this.controller, this.initial, this.demo = false, this.onSave});

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController(text: widget.initial ?? '');
  bool _editing = false;

  Future<void> _askPassword() async {
    final app = context.read<AppState>();
    final isEn = app.isEn;
    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.tr(isEn, 'app_pwd')),
        content: TextField(
          controller: input,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: L.tr(isEn, 'pwd_required')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L.tr(isEn, 'btn_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.tr(isEn, 'btn_ok'))),
        ],
      ),
    );
    if (ok == true && input.text == app.password) {
      setState(() => _editing = true);
    } else if (ok == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.tr(isEn, 'pwd_wrong'))));
    }
  }

  void _save() {
    (widget.onSave ??
        () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.tr(context.watch<AppState>().isEn, 'toast_demo')))))();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final isEn = context.watch<AppState>().isEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
            child: Text(widget.label,
                style: const TextStyle(fontSize: 13))),
        if (!_editing) ...[
          // 查看模式：直接显示当前值（只读），点"修改"才弹密码
          Text(_ctrl.text,
              style: const TextStyle(fontSize: 14, color: AppTheme.green)),
          const SizedBox(width: 8),
          InkWell(
            onTap: _askPassword,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: surface2, borderRadius: BorderRadius.circular(6)),
              child: Text(L.tr(isEn, 'btn_edit'),
                  style: TextStyle(fontSize: 12, color: dim)),
            ),
          ),
        ] else ...[
          SizedBox(
            width: 82,
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.green),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                filled: true,
                fillColor: surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _save,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: surface2, borderRadius: BorderRadius.circular(6)),
              child: Text(L.tr(isEn, 'save'),
                  style: TextStyle(fontSize: 12, color: dim)),
            ),
          ),
        ],
      ]),
    );
  }
}
