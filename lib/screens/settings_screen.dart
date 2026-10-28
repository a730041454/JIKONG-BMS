import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../services/inverter/inverter_params.dart';
import '../services/inverter_service.dart';
import '../services/jikong_protocol.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/no_connection.dart';

/// 参数设置页：逆变器设置与 BMS 设置两大可折叠分组。
///
/// 参数值直接点数值即可编辑；密码只在「授权设置」验证一次，
/// 之后本次会话内直接保存（离开参数页重新上锁）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _invOpen = false;
  bool _bmsOpen = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.data == null) return const NoConnection();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);

    void toast(String msg) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _AuthBanner(
          app: app,
          t: t,
          onAuth: () => _authGate(context, toast),
        ),
        _Group(
          title: t('inv_group'),
          icon: Icons.compare_arrows,
          subtitle: app.invProtocolLabel,
          open: _invOpen,
          onToggle: () => setState(() => _invOpen = !_invOpen),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('inv_link'),
                  style: const TextStyle(fontSize: 13)),
            ),
            _Seg(
              values: [('rtu', t('inv_link_rtu')), ('ascii', t('inv_link_ascii'))],
              selected: app.invKind == InvLinkKind.modbus ? 'rtu' : 'ascii',
              onSelect: (v) async {
                if (!app.connected) {
                  toast(t('inv_link_need_gw'));
                }
                await app.setInverterLink(
                    v == 'ascii' ? InvLinkKind.ascii : InvLinkKind.modbus);
                if (mounted) toast(t('inv_link_changed'));
              },
            ),
            const SizedBox(height: 8),
            _QBtn(t('inv_read'), () {
              app.readInverterSettings();
              toast(t('reading_data'));
            }),
            const SizedBox(height: 10),
            for (final p in invParamDefs) _InvRow(def: p),
            _Section(t('inv_ctl'), dim),
            for (final c in invControlDefs)
              _CtlRow(
                label: t(c.key),
                hint: c.commandText,
                enabled: app.invKind == InvLinkKind.ascii,
                onTap: () async {
                  final ok = await app.sendInverterControl(c.commandText);
                  toast(ok ? t('inv_ctl_ok') : t('inv_ctl_fail'));
                },
              ),
            if (app.invKind != InvLinkKind.ascii)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('inv_ascii_only'),
                    style: TextStyle(fontSize: 11.5, color: dim, height: 1.5)),
              ),
          ],
        ),
        _Group(
          title: t('bms_group'),
          icon: Icons.battery_charging_full,
          subtitle: '${app.cells}${t('u_series')} · ${app.nominal.toStringAsFixed(0)}Ah',
          open: _bmsOpen,
          onToggle: () => setState(() => _bmsOpen = !_bmsOpen),
          children: [
            _Section(t('core_title'), dim),
            _ParamRow(
              label: t('core_cells'),
              pkey: 'core_cells',
              onSave: (v) async {
                await context.read<AppState>().saveCore(cellCount: v.round());
                return true;
              },
            ),
            _ParamRow(
              label: t('core_cap'),
              pkey: 'core_cap',
              onSave: (v) async {
                await context.read<AppState>().saveCore(capacity: v);
                return true;
              },
            ),
            _Section(t('bal_title'), dim),
            _ParamRow(label: t('bal_dv'), pkey: 'bal_dv'),
            _ParamRow(label: t('bal_sv'), pkey: 'bal_sv'),
            _ParamRow(label: t('bal_cur'), pkey: 'bal_cur'),
            _Section(t('vp_title'), dim),
            _ParamRow(label: t('vp_ocv'), pkey: 'vp_ocv'),
            _ParamRow(label: t('vp_recv'), pkey: 'vp_recv'),
            _ParamRow(label: t('vp_s100'), pkey: 'vp_s100'),
            _ParamRow(label: t('vp_or'), pkey: 'vp_or'),
            _ParamRow(label: t('vp_ur'), pkey: 'vp_ur'),
            _ParamRow(label: t('vp_s0'), pkey: 'vp_s0'),
            _ParamRow(label: t('vp_uv'), pkey: 'vp_uv'),
            _ParamRow(label: t('vp_off'), pkey: 'vp_off'),
            _Section(t('cp_title'), dim),
            _ParamRow(label: t('cp_cc'), pkey: 'cp_cc'),
            _ParamRow(label: t('cp_cd'), pkey: 'cp_cd'),
            _ParamRow(label: t('cp_cdr'), pkey: 'cp_cdr'),
            _ParamRow(label: t('cp_dc'), pkey: 'cp_dc'),
            _ParamRow(label: t('cp_dd'), pkey: 'cp_dd'),
            _ParamRow(label: t('cp_ddr'), pkey: 'cp_ddr'),
            _Section(t('tp_title'), dim),
            _ParamRow(label: t('tp_cot'), pkey: 'tp_cot'),
            _ParamRow(label: t('tp_cotr'), pkey: 'tp_cotr'),
            _ParamRow(label: t('tp_clt'), pkey: 'tp_clt'),
            _ParamRow(label: t('tp_cltp'), pkey: 'tp_cltp'),
            _ParamRow(label: t('tp_dot'), pkey: t('tp_dot')),
            _ParamRow(label: t('tp_dotr'), pkey: 'tp_dotr'),
            _ParamRow(label: t('tp_dlt')),
            _ParamRow(label: t('tp_dltp')),
            _ParamRow(label: t('tp_mos'), pkey: 'tp_mos'),
            _ParamRow(label: t('tp_mosr'), pkey: 'tp_mosr'),
            _Section(t('sc_title'), dim),
            _ParamRow(label: t('sc_d'), pkey: 'sc_d'),
            _ParamRow(label: t('sc_r'), pkey: 'sc_r'),
            _Section(t('ss_title'), dim),
            _ParamRow(label: t('ss_v'), pkey: 'ss_v'),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t('settings_note'),
              style: TextStyle(fontSize: 11, color: dim, height: 1.6)),
        ),
      ],
    );
  }
}

/// 授权设置：必须输入密码；离开参数页后自动重新上锁。
Future<void> _authGate(BuildContext context, void Function(String) toast) async {
  final app = context.read<AppState>();
  final t = (k) => L.tr(app.isEn, k);
  if (app.pwdUnlocked) {
    toast(t('toast_auth_ok'));
    return;
  }
  final ok = await _askPassword(context, app);
  toast(ok ? t('toast_auth_ok') : t('pwd_wrong'));
}

/// 弹出一次密码框并解锁。
Future<bool> _askPassword(BuildContext context, AppState app) async {
  final t = (k) => L.tr(app.isEn, k);
  final input = TextEditingController();
  var err = false;
  bool accepted() => input.text.trim() == app.password.trim();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(t('pwd_title')),
        content: TextField(
          controller: input,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t('pwd_required'),
            errorText: err ? t('pwd_wrong') : null,
          ),
          onSubmitted: (_) {
            if (accepted()) {
              Navigator.pop(ctx, true);
            } else {
              setS(() => err = true);
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('btn_cancel'))),
          TextButton(
              onPressed: () {
                if (accepted()) {
                  Navigator.pop(ctx, true);
                } else {
                  setS(() => err = true);
                }
              },
              child: Text(t('btn_ok'))),
        ],
      ),
    ),
  );
  input.dispose();
  if (ok == true) app.unlock();
  return ok == true;
}

/// 授权状态提示条：每次进入参数页都处于锁定态，必须授权后才能修改。
class _AuthBanner extends StatelessWidget {
  final AppState app;
  final String Function(String) t;
  final VoidCallback onAuth;
  const _AuthBanner({required this.app, required this.t, required this.onAuth});

  @override
  Widget build(BuildContext context) {
    final unlocked = app.pwdUnlocked;
    final color = unlocked ? AppTheme.green : AppTheme.orange;
    final text = unlocked ? t('auth_ok_hint') : t('auth_lock_hint');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Row(children: [
        Icon(unlocked ? Icons.lock_open : Icons.lock_outline,
            size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.4))),
        if (!unlocked)
          FilledButton(
            onPressed: onAuth,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(t('qf_auth'), style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

/// 可折叠分组：标题行常显，内容点击展开/收起。
class _Group extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;
  const _Group({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.open,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: open
                ? AppTheme.green.withOpacity(.30)
                : dim.withOpacity(.16)),
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(children: [
              Icon(icon, size: 18, color: open ? AppTheme.green : dim),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: dim)),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: dim),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(children: children),
          ),
      ]),
    );
  }
}

/// 分组内的小标题。
class _Section extends StatelessWidget {
  final String text;
  final Color dim;
  const _Section(this.text, this.dim);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
      child: Row(children: [
        Container(
            width: 3, height: 12, color: AppTheme.green.withOpacity(.6)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: dim)),
      ]));
}

class _QBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _QBtn(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    final surface2 = surface2Of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: surface2, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.chevron_right, size: 16, color: AppTheme.darkDim),
        ]),
      ),
    );
  }
}

/// 两项选一的分段控件（逆变器接入方式）。
class _Seg extends StatelessWidget {
  final List<(String, String)> values;
  final String selected;
  final ValueChanged<String> onSelect;
  const _Seg(
      {required this.values, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final surface2 = surface2Of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: surface2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final (v, label) in values)
          Expanded(
            child: InkWell(
              onTap: () => onSelect(v),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: selected == v ? AppTheme.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: selected == v
                            ? Colors.white
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(.6),
                        fontWeight: selected == v
                            ? FontWeight.w600
                            : FontWeight.w400)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 逆变器参数行：枚举项弹选项，数值项点数值直接改。
class _InvRow extends StatelessWidget {
  final InvParamDef def;
  const _InvRow({required this.def});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final label = t(def.key);
    final value = app.invSettingValue(def.key);

    String text() {
      if (value == null) return '--';
      if (def.isEnum) {
        final opt = def.options?[value.round()];
        return opt ?? value.toStringAsFixed(0);
      }
      return value.toStringAsFixed(def.decimals);
    }

    Future<bool> save(double v) => app.writeInverterParam(def.key, v);

    if (def.isEnum) {
      return _ParamRow(
        label: label,
        value: text,
        currentRaw: (a) => a.invSettingValue(def.key),
        pickOptions: def.options,
        onSave: save,
      );
    }
    return _ParamRow(label: label, value: text, onSave: save);
  }
}

/// 控制指令行（开机 / 清除故障 / 锂电激活）。
class _CtlRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool enabled;
  final Future<void> Function() onTap;
  const _CtlRow({
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.5);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: enabled
                    ? AppTheme.green.withOpacity(.28)
                    : dim.withOpacity(.15))),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: enabled ? null : dim,
                      fontWeight: FontWeight.w600))),
          Text(hint, style: TextStyle(fontSize: 12, color: dim)),
          Icon(Icons.send, size: 15, color: enabled ? AppTheme.green : dim),
        ]),
      ),
    );
  }
}

/// 通用参数行：点数值进入编辑，保存后写设备并回读校验。
class _ParamRow extends StatefulWidget {
  final String label;
  final String? pkey; // BMS settings 帧取值/写寄存器 key
  final String Function()? value; // 自定义取值（逆变器）
  final double? Function(AppState app)? currentRaw; // 原始数值，供选项弹窗高亮
  final Future<bool> Function(double value)? onSave;
  final Map<int, String>? pickOptions; // 非空 = 弹选项而非输入数字
  const _ParamRow({
    required this.label,
    this.pkey,
    this.value,
    this.currentRaw,
    this.onSave,
    this.pickOptions,
  });

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  final _ctrl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  JkParamDef? get _def => widget.pkey == null ? null : jkParamDef(widget.pkey!);

  String _current(AppState app) {
    if (widget.value != null) return widget.value!();
    final v = widget.pkey == null ? null : app.settingsValue(widget.pkey!);
    if (v != null) return v.toStringAsFixed(_def?.decimals ?? 2);
    return '--';
  }

  void _startEdit(AppState app) {
    final cur = _current(app);
    _ctrl.text = cur == '--' ? '' : cur;
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    setState(() => _editing = true);
  }

  Future<void> _commit(AppState app, double? value) async {
    final t = (k) => L.tr(app.isEn, k);
    final messenger = ScaffoldMessenger.of(context);
    if (value == null) {
      messenger.showSnackBar(SnackBar(content: Text(t('invalid_value'))));
      return;
    }
    if (!app.pwdUnlocked) {
      messenger.showSnackBar(SnackBar(content: Text(t('need_auth'))));
      return;
    }
    if (!mounted) return;
    setState(() => _editing = false);
    final ok = widget.onSave != null
        ? await widget.onSave!(value)
        : (widget.pkey != null ? await app.writeParam(widget.pkey!, value) : false);
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? (widget.value != null ? t('inv_saved_ok') : t('toast_saved'))
            : (widget.value != null ? t('inv_saved_fail') : t('toast_saved_fail')))));
  }

  void _startEditOrPick(AppState app) {
    if (widget.pickOptions != null) {
      _pick(app);
      return;
    }
    _startEdit(app);
  }

  void _pick(AppState app) {
    final cur = widget.currentRaw?.call(app) ?? app.settingsValue(widget.pkey ?? '');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Text(widget.label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            for (final e in widget.pickOptions!.entries)
              ListTile(
                dense: true,
                leading: Icon(
                    cur != null && cur.round() == e.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: cur != null && cur.round() == e.key
                        ? AppTheme.green
                        : null),
                title: Text(e.value, style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _commit(app, e.key.toDouble());
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final surface = Theme.of(context).colorScheme.surface;
    final surface2 = surface2Of(context);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final editable = widget.value != null || widget.pkey != null;
    final locked = !app.pwdUnlocked;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration:
          BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 13))),
        if (!_editing) ...[
          InkWell(
            onTap:
                editable ? () => _startEditOrPick(app) : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: editable
                          ? AppTheme.green.withOpacity(.28)
                          : Colors.transparent)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(_current(app),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.green,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
                if (editable) ...[
                  const SizedBox(width: 6),
                  Icon(locked ? Icons.lock_outline : Icons.edit,
                      size: 12, color: locked ? AppTheme.orange : dim),
                ],
              ]),
            ),
          ),
        ] else ...[
          SizedBox(
            width: 92,
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              style: const TextStyle(fontSize: 14, color: AppTheme.green),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                filled: true,
                fillColor: surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (_) =>
                  _commit(app, double.tryParse(_ctrl.text.trim().replaceAll(',', '.'))),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _commit(
                app, double.tryParse(_ctrl.text.trim().replaceAll(',', '.'))),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: AppTheme.green.withOpacity(.16),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(t('save'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.green)),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _editing = false),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 15, color: dim),
            ),
          ),
        ],
      ]),
    );
  }
}
