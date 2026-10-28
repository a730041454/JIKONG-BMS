import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../models/saved_device.dart';
import '../services/gateway/ble_gateway_link.dart';
import '../services/gateway/gateway_link.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'qr_scan_screen.dart';

/// 网关连接与配网：蓝牙扫描 / 局域网发现 / 手动 IP，外加 ESP32 的 WiFi 配网。
class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});
  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  LinkMode _tab = LinkMode.ble;
  List<GatewayDevice> _found = [];
  bool _scanning = false;
  final _ipCtrl = TextEditingController();

  List<Map<String, dynamic>> _aps = [];
  bool _scanningWifi = false;
  bool _provisioning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  void toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  Future<void> _refreshStatus() async {
    final app = context.read<AppState>();
    if (!app.connected) return;
    await app.gatewayStatus();
  }

  Future<bool> _ensureBlePermission() async {
    if (Theme.of(context).platform != TargetPlatform.android) return true;
    // 清单里 BLUETOOTH_SCAN 声明了 neverForLocation，Android 12+ 不再需要位置授权；
    // 把它当门槛会让「拒绝位置」的手机永远进不了扫描。位置仍然请求一次，
    // 兼容 Android 11 及以下（那时 BLE 扫描按位置权限管），但不参与判定。
    unawaited(Permission.locationWhenInUse.request());
    final r1 = await Permission.bluetoothScan.request();
    final r2 = await Permission.bluetoothConnect.request();
    return r1.isGranted && r2.isGranted;
  }

  Future<void> _search() async {
    final app = context.read<AppState>();
    final lan = _tab != LinkMode.ble;
    if (!lan && !await _ensureBlePermission()) {
      toast('需要「附近的设备/蓝牙」权限才能扫描网关');
      return;
    }
    setState(() => _scanning = true);
    final list = lan ? await app.discoverLan() : await app.scanGateways();
    if (!mounted) return;
    setState(() {
      _found = list;
      _scanning = false;
    });
    if (list.isEmpty && !lan) {
      toast(BleGatewayLink.lastScanError ?? '没扫到网关');
    }
  }

  Future<void> _connect(GatewayDevice dev) async {
    final app = context.read<AppState>();
    final mode = dev.mode;
    final id = mode == LinkMode.ble ? dev.id : (dev.ip ?? dev.id);
    toast(L.tr(app.isEn, 'gw_connecting'));
    final ok = await app.connectGateway(mode: mode, id: id, name: dev.name);
    if (!mounted) return;
    if (ok) {
      toast('${L.tr(app.isEn, 'gw_connected')} · ${app.deviceName}');
      Navigator.of(context).pop();
    } else {
      toast(app.connectError ?? L.tr(app.isEn, 'gw_failed'));
    }
  }

  Future<void> _connectIp() async {
    final app = context.read<AppState>();
    final ip = _ipCtrl.text.trim();
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
      toast(L.tr(app.isEn, 'gw_ip_hint'));
      return;
    }
    toast(L.tr(app.isEn, 'gw_connecting'));
    final ap = _isEspAp(ip);
    final ok = await app.connectGateway(
        mode: ap ? LinkMode.ap : LinkMode.lan, id: ip, name: ip);
    if (!mounted) return;
    toast(ok ? '${L.tr(app.isEn, 'gw_connected')} · $ip' : L.tr(app.isEn, 'gw_failed'));
    if (ok) Navigator.of(context).pop();
  }

  /// ESP32 自建热点的默认网关地址通常是 192.168.4.1。
  bool _isEspAp(String ip) => ip.startsWith('192.168.4.');

  Future<void> _connectSaved(SavedDevice d) async {
    final app = context.read<AppState>();
    toast(L.tr(app.isEn, 'gw_connecting'));
    final ok = await app.connectSaved(d.id, name: d.name);
    if (!mounted) return;
    toast(ok ? '${L.tr(app.isEn, 'gw_connected')} · ${app.deviceName}'
        : (app.connectError ?? L.tr(app.isEn, 'gw_failed')));
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _rename(AppState app) async {
    final t = (k) => L.tr(app.isEn, k);
    final ctrl = TextEditingController(text: app.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(t('gw_rename')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 16,
          decoration: InputDecoration(hintText: t('gw_rename_hint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('btn_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(t('btn_ok'))),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final ok = await app.renameGateway(name);
    toast(ok ? t('gw_connected') : t('gw_failed'));
  }

  Future<void> _scanWifi(AppState app) async {
    setState(() => _scanningWifi = true);
    final list = await app.gatewayScanWifi();
    if (!mounted) return;
    setState(() {
      _aps = list;
      _scanningWifi = false;
    });
    if (list.isEmpty) toast(L.tr(app.isEn, 'prov_no_ap'));
  }

  Future<void> _provision(AppState app, Map<String, dynamic> ap) async {
    final t = (k) => L.tr(app.isEn, k);
    final ssid = (ap['ssid'] ?? ap['name'] ?? '').toString();
    if (ssid.isEmpty) return;
    final passCtrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(ssid),
        content: TextField(
          controller: passCtrl,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(hintText: t('prov_pass_hint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('btn_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, passCtrl.text),
              child: Text(t('prov_connect_btn'))),
        ],
      ),
    );
    passCtrl.dispose();
    if (pass == null || !mounted) return;
    setState(() => _provisioning = true);
    final r = await app.gatewayConnectWifi(ssid, pass);
    if (!mounted) return;
    setState(() => _provisioning = false);
    final ip = r?['result']?['ip'] ?? r?['ip'];
    if (r != null && (r['ok'] == true || ip != null)) {
      toast('${t('prov_done')}${ip == null ? '' : ' · $ip'}');
    } else {
      toast(t('prov_fail'));
    }
  }

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.55))),
      );

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _deviceTile(GatewayDevice d, String Function(String) t) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(d.mode == LinkMode.ble ? Icons.bluetooth : Icons.wifi,
            size: 20, color: AppTheme.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(d.mode == LinkMode.ble ? d.id : (d.ip ?? d.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: dim)),
          ]),
        ),
        if (d.rssi != 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${d.rssi}', style: TextStyle(fontSize: 11, color: dim)),
          ),
        TextButton(
          onPressed: () => _connect(d),
          style: TextButton.styleFrom(
              backgroundColor: AppTheme.green.withOpacity(.15),
              foregroundColor: AppTheme.green),
          child: Text(t('gw_connect')),
        ),
      ]),
    );
  }

  Widget _savedTile(AppState app, SavedDevice d, String Function(String) t) {
    final current = app.connected && app.rememberedDeviceId == d.id;
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: current ? Border.all(color: AppTheme.green.withOpacity(.45)) : null,
      ),
      child: Row(children: [
        Icon(current ? Icons.link : Icons.bookmark_border,
            size: 20, color: AppTheme.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(d.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: dim)),
          ]),
        ),
        TextButton(
          onPressed: () => _connectSaved(d),
          style: TextButton.styleFrom(
              backgroundColor: AppTheme.green.withOpacity(.15),
              foregroundColor: AppTheme.green),
          child: Text(t('gw_connect')),
        ),
        IconButton(
          onPressed: () => app.removeSavedDevice(d.id),
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_outline, size: 19, color: dim),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final info = app.gatewayInfo ?? const {};
    String s(String k) => (info[k] ?? '--').toString();

    return Scaffold(
      appBar: AppBar(title: Text(t('gw_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        children: [
          _card(children: [
            Row(children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app.connected ? AppTheme.green : AppTheme.orange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    app.connected
                        ? '${app.deviceName} · ${t('gw_mode_${app.linkMode.name}')}'
                        : t('disconnected'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (app.connected) ...[
                IconButton(
                  onPressed: () => _rename(app),
                  tooltip: t('gw_rename'),
                  icon: Icon(Icons.drive_file_rename_outline,
                      size: 19, color: dim),
                ),
                TextButton(
                  onPressed: () async {
                    await app.disconnectGateway();
                    toast(t('toast_disconnected'));
                  },
                  child: Text(t('gw_disconnect')),
                ),
              ],
            ]),
            if (app.connected) ...[
              const SizedBox(height: 4),
              Text(
                  '${t('prov_fw')}: ${s('fw')}    ${t('prov_ip')}: ${s('ip')}\n'
                  '${t('prov_mode')}: ${s('mode')}    ${t('prov_mac')}: ${s('mac')}',
                  style: TextStyle(fontSize: 11.5, color: dim, height: 1.6)),
            ],
            if (!app.connected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('gw_intro'),
                    style: TextStyle(fontSize: 12, color: dim, height: 1.5)),
              ),
          ]),

          _head(t('gw_nearby')),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              _Tab(
                  label: t('gw_ble'),
                  icon: Icons.bluetooth,
                  on: _tab == LinkMode.ble,
                  onTap: () => setState(() {
                        _tab = LinkMode.ble;
                        _found = [];
                      })),
              const SizedBox(width: 8),
              _Tab(
                  label: t('gw_lan'),
                  icon: Icons.lan_outlined,
                  on: _tab != LinkMode.ble,
                  onTap: () => setState(() {
                        _tab = LinkMode.lan;
                        _found = [];
                      })),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _search,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: const Color(0xFF03130A),
                      minimumSize: const Size.fromHeight(40)),
                  icon: _scanning
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.radar, size: 17),
                  label: Text(_scanning ? t('dev_scanning') : t('gw_scan')),
                ),
              ),
            ]),
          ),
          if (_found.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('dev_empty'),
                  style: TextStyle(fontSize: 12.5, color: dim)),
            ),
          for (final d in _found) _deviceTile(d, t),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    isDense: true, hintText: t('gw_ip_hint'),
                    prefixIcon: const Icon(Icons.dialpad, size: 18)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _connectIp,
              style: TextButton.styleFrom(
                  backgroundColor: AppTheme.green.withOpacity(.15),
                  foregroundColor: AppTheme.green),
              child: Text(t('gw_connect')),
            ),
          ]),

          if (app.savedDevices.isNotEmpty) ...[
            _head(t('gw_saved')),
            for (final d in app.savedDevices) _savedTile(app, d, t),
          ],

          _head(t('prov_title')),
          _card(children: [
            Text(
                app.connected
                    ? (s('mode') == 'sta' ? t('prov_sta') : t('prov_ap'))
                    : t('inv_link_need_gw'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (app.connected)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanningWifi ? null : () => _scanWifi(app),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.green,
                        minimumSize: const Size.fromHeight(38)),
                    icon: _scanningWifi
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.green))
                        : const Icon(Icons.wifi, size: 16),
                    label: Text(t('prov_scan_wifi')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _provisioning
                        ? null
                        : () async {
                            final r = await app.gatewayDisconnectWifi();
                            toast(r == null ? t('prov_fail') : t('prov_ap'));
                          },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: dim,
                        minimumSize: const Size.fromHeight(38)),
                    icon: const Icon(Icons.wifi_off, size: 16),
                    label: Flexible(child: Text(t('prov_to_ap'),
                        style: const TextStyle(fontSize: 12))),
                  ),
                ),
              ]),
            if (_provisioning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.green)),
                  const SizedBox(width: 10),
                  Text(t('prov_wait'),
                      style: const TextStyle(fontSize: 12, color: AppTheme.green)),
                ]),
              ),
            for (final ap in _aps)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => _provision(app, ap),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: surface2Of(context),
                    child: Row(children: [
                      Icon(Icons.wifi, size: 15, color: dim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text((ap['ssid'] ?? ap['name'] ?? '--').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text('${ap['rssi'] ?? ''}',
                          style: TextStyle(fontSize: 11, color: dim)),
                    ]),
                  ),
                ),
              ),
          ]),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await _ensureBlePermission()) {
                toast('需要蓝牙/位置权限才能连接网关');
                return;
              }
              if (!context.mounted) return;
              final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const QrScanScreen()));
              if (code == null || !mounted) return;
              final ok = await app.connectSaved(code.toUpperCase(), name: code);
              if (!mounted) return;
              toast(ok ? t('gw_connected')
                  : (app.connectError ?? L.tr(app.isEn, 'qr_invalid')));
              if (ok) Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                minimumSize: const Size.fromHeight(42)),
            icon: const Icon(Icons.qr_code, size: 18),
            label: Text(t('dev_qr')),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  const _Tab(
      {required this.label,
      required this.icon,
      required this.on,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppTheme.green.withOpacity(.14) : surface2Of(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? AppTheme.green : dim.withOpacity(.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: on ? AppTheme.green : dim),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? AppTheme.green : dim)),
        ]),
      ),
    );
  }
}
