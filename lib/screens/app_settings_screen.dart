import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';

/// 应用设置：语言 / 主题 / 密码保护 / 联系方式 / 关于版本。
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});
  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final _pwdCtrl = TextEditingController(text: '123456');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final surface = Theme.of(context).colorScheme.surface;

    void toast(String m) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

    return Scaffold(
      appBar: AppBar(title: Text(t('app_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          _Sec(t('app_lang'), dim),
          _Seg(values: [('zh', '中文'), ('en', 'English')],
              selected: app.isEn ? 'en' : 'zh',
              onSelect: (v) => app.setLanguage(v == 'en')),
          _Sec(t('app_theme'), dim),
          _Seg(values: [('light', t('theme_light')), ('dark', t('theme_dark'))],
              selected: app.isDark ? 'dark' : 'light',
              onSelect: (v) {
                app.setDark(v == 'dark');
                toast(t(v == 'dark' ? 'toast_theme_dark' : 'toast_theme_light'));
              }),
          _Sec(t('app_pwd'), dim),
          _SwitchRow(label: t('app_pwd_on'), on: app.pwdEnabled,
              onTap: () => app.setPwdEnabled(!app.pwdEnabled)),
          _Field(label: t('app_pwd_set'), controller: _pwdCtrl, onChanged: (v) {
            app.setPassword(v);
          }),
          _Sec(t('app_contact'), dim),
          _RowBtn(label: t('app_contact_val'),
              onTap: () => toast(t('app_contact_val'))),
          _Sec(t('app_about'), dim),
          _RowBtn(label: '${t('app')} · v1.0.0', onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()));
          }),
          const SizedBox(height: 16),
          // 连接状态与数据源
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('l_state') + ': ${app.connected ? t('toast_connected') : t('disconnected')}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text('数据源: ${app.useMock ? '模拟数据 (Mock)' : 'BLE · 极空协议 (JK)'}',
                  style: TextStyle(fontSize: 12, color: dim)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Sec extends StatelessWidget {
  final String text;
  final Color dim;
  const _Sec(this.text, this.dim);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dim)));
}

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
                    style: TextStyle(
                        fontSize: 14,
                        color: selected == v
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface.withOpacity(.6),
                        fontWeight: selected == v ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _SwitchRow({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Switch.adaptive(value: on, onChanged: (_) => onTap()),
      ]),
    );
  }
}

class _Field extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _Field(
      {required this.label, required this.controller, required this.onChanged});

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 14))),
        SizedBox(
          width: 150,
          child: TextField(
            controller: widget.controller,
            obscureText: !_show,
            textAlign: TextAlign.right,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RowBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RowBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Icon(Icons.chevron_right,
              size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(.5)),
        ]),
      ),
    );
  }
}
