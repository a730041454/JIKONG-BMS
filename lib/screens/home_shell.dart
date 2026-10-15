import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'add_device_screen.dart';
import 'app_settings_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'settings_screen.dart';

/// 三页导航外壳（实时状态 / 首页 / 参数设置）+ 顶栏 + 状态栏。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 1; // 默认进首页
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _t(BuildContext context, String k) =>
      L.tr(context.watch<AppState>().isEn, k);

  void _goTab(BuildContext context, AppState app, int i) {
    if (i == _index) return;
    // 进入参数设置页不弹密码；修改参数后"保存"时才弹密码确认（见 SettingsScreen._ParamRow）
    setState(() => _index = i);
    _pageCtrl.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tabs = [_t(context, 'nav_live'), _t(context, 'nav_home'), _t(context, 'nav_set')];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppBar(
              title: tabs[_index],
              onAdd: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddDeviceScreen())),
              onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen())),
              connected: app.connected,
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  // 页面切换时向保护板请求当前页对应数据
                  context.read<AppState>().requestPage(i);
                },
                children: const [LiveScreen(), HomeScreen(), SettingsScreen()],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _Nav(
        index: _index,
        onTap: (i) => _goTab(context, app, i),
        labels: tabs,
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  final bool en;
  const _StatusBar({required this.en});
  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  String _clock = '--:--';

  @override
  void initState() {
    super.initState();
    _clock = _now();
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _clock = _now());
    });
  }

  String _now() {
    final d = DateTime.now();
    final p = (n) => n.toString().padLeft(2, '0');
    return '${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_clock, style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.55))),
          Row(children: [
            Icon(Icons.signal_cellular_alt, size: 15, color: _dim(context)),
            const SizedBox(width: 5),
            Icon(Icons.wifi, size: 15, color: _dim(context)),
            const SizedBox(width: 5),
            Icon(Icons.battery_full, size: 16, color: _dim(context)),
          ]),
        ],
      ),
    );
  }

  Color _dim(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withOpacity(.45);
}

class _AppBar extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final bool connected;
  const _AppBar(
      {required this.title,
      required this.onAdd,
      required this.onSettings,
      required this.connected});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.add, size: 22, color: dim),
              onPressed: onAdd,
              tooltip: 'Add device',
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 17, color: AppTheme.green),
              const SizedBox(width: 5),
              Text(title, style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? AppTheme.green : AppTheme.orange,
                    boxShadow: connected
                        ? [BoxShadow(color: AppTheme.green, blurRadius: 8)]
                        : null,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.settings, size: 20, color: dim),
                  onPressed: onSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<String> labels;
  const _Nav({required this.index, required this.onTap, required this.labels});

  @override
  Widget build(BuildContext context) {
    final icons = [Icons.bolt_outlined, Icons.home_outlined, Icons.tune];
    final iconsOn = [Icons.bolt, Icons.home, Icons.tune];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            top: BorderSide(color: scheme.onSurface.withOpacity(.06))),
      ),
      height: 62,
      child: Row(
        children: List.generate(3, (i) {
          final on = i == index;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(on ? iconsOn[i] : icons[i],
                      size: 21, color: on ? AppTheme.green : scheme.onSurface.withOpacity(.5)),
                  const SizedBox(height: 3),
                  Text(labels[i],
                      style: TextStyle(
                          fontSize: 14,
                          color: on ? AppTheme.green : scheme.onSurface.withOpacity(.5))),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 密码弹层（进入参数设置前验证）。
class PasswordGate {
  PasswordGate._();
  static Future<void> show(BuildContext context) async {
    final app = context.read<AppState>();
    final ctrl = TextEditingController();
    var err = '';
    var showPwd = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final t = (k) => L.tr(app.isEn, k);
        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            title: Center(child: Text(t('pwd_title'))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: AppTheme.green, size: 34),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: !showPwd,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                      errorText: err.isEmpty ? null : t('pwd_err'),
                      suffixIcon: IconButton(
                        icon: Icon(showPwd ? Icons.visibility_off : Icons.visibility,
                            size: 20),
                        onPressed: () => setS(() => showPwd = !showPwd),
                      )),
                  onSubmitted: (_) {
                    if (ctrl.text == app.password) {
                      app.pwdUnlocked = true;
                      Navigator.of(ctx).pop();
                    } else {
                      setS(() => err = 'x');
                    }
                  },
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t('pwd_cancel'))),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
                  onPressed: () {
                    if (ctrl.text == app.password) {
                      app.pwdUnlocked = true;
                      Navigator.of(ctx).pop();
                    } else {
                      setS(() => err = 'x');
                    }
                  },
                  child: Text(t('pwd_ok'))),
            ],
          );
        });
      },
    );
  }
}
