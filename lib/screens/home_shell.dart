import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../services/gateway/gateway_link.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'app_settings_screen.dart';
import 'gateway_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'settings_screen.dart';

/// 三页导航外壳（BMS管理 / 首页 / 参数设置）+ 顶栏。
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
    // 启动后静默检查一次新版本，有更新才弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        UpdateService.checkAndPrompt(context,
            en: context.read<AppState>().isEn);
      });
    });
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
    final title = app.connected && app.deviceName.isNotEmpty
        ? app.deviceName
        : tabs[_index];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppBar(
              title: title,
              mode: app.linkMode,
              onAdd: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GatewayScreen())),
              onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen())),
              connected: app.connected,
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  final app = context.read<AppState>();
                  // 离开参数设置页即重新上锁：下次进入必须再次授权
                  if (i != 2) app.lock();
                  // 页面切换时向保护板请求当前页对应数据
                  app.requestPage(i);
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

class _AppBar extends StatelessWidget {
  final String title;
  final LinkMode mode;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final bool connected;
  const _AppBar(
      {required this.title,
      required this.mode,
      required this.onAdd,
      required this.onSettings,
      required this.connected});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final scheme = Theme.of(context).colorScheme;
    final icon = !connected
        ? Icons.link_off
        : switch (mode) {
            LinkMode.ble => Icons.bluetooth_connected,
            LinkMode.lan => Icons.wifi,
            LinkMode.ap => Icons.wifi_tethering,
          };
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            bottom: BorderSide(color: scheme.onSurface.withOpacity(.06))),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(icon,
                  size: 22, color: connected ? AppTheme.green : dim),
              onPressed: onAdd,
              tooltip: 'Gateway',
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 17, color: AppTheme.green),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
              ),
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
    final icons = [
      Icons.battery_charging_full_outlined,
      Icons.home_outlined,
      Icons.tune
    ];
    final iconsOn = [Icons.battery_charging_full, Icons.home, Icons.tune];
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
