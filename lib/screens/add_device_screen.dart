import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../services/bms_data_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 添加设备：搜索 / 扫描设备 / 扫码连接。
class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});
  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  List<BmsDevice> _devices = [];
  bool _scanning = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final app = context.read<AppState>();
    if (!await _ensurePermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('需要蓝牙/位置权限才能扫描设备')));
      return;
    }
    setState(() => _scanning = true);
    final list = await app.scan();
    if (!mounted) return;
    setState(() {
      _devices = list;
      _scanning = false;
    });
  }

  Future<bool> _ensurePermission() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final r1 = await Permission.bluetoothScan.request();
      final r2 = await Permission.bluetoothConnect.request();
      final r3 = await Permission.locationWhenInUse.request();
      return r1.isGranted && r2.isGranted && r3.isGranted;
    }
    return true;
  }

  List<BmsDevice> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _devices;
    return _devices
        .where((d) => d.name.toLowerCase().contains(q) || d.id.contains(q))
        .toList();
  }

  Future<void> _connect(BmsDevice dev) async {
    final app = context.read<AppState>();
    final ok = await app.connect(dev.id);
    if (!mounted) return;
    if (ok) {
      app.deviceName = dev.name;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L.tr(app.isEn, 'toast_connected')} · ${dev.name}')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr(app.isEn, 'disconnected'))));
    }
  }

  void _qr() {
    final app = context.read<AppState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.green.withOpacity(.3))),
            child: Stack(alignment: Alignment.center, children: [
              Icon(Icons.qr_code_scanner, size: 120, color: AppTheme.green.withOpacity(.4)),
              const Positioned(top: 6, child: SizedBox(
                width: 120, child: Divider(color: AppTheme.green))),
            ]),
          ),
          const SizedBox(height: 16),
          Text(L.tr(app.isEn, 'qr_scanning'),
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 16),
        ]),
      ),
    );
    // 演示：1.8s 后提示识别成功
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr(app.isEn, 'qr_found'))));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      appBar: AppBar(title: Text(t('dev_title'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: t('dev_search'),
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ),
        Expanded(
          child: _scanning
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.green)),
                    const SizedBox(height: 12),
                    Text(t('dev_scanning'),
                        style: const TextStyle(color: AppTheme.green, fontSize: 14)),
                  ]),
                )
              : _filtered.isEmpty
                  ? Center(child: Text(t('dev_empty'),
                      style: TextStyle(color: dim, fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _filtered.length,
                      itemBuilder: (c, i) {
                        final d = _filtered[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                              color: surface, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            Icon(Icons.bluetooth, size: 22, color: AppTheme.green),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    Text(d.id,
                                        style: TextStyle(fontSize: 11, color: dim)),
                                  ]),
                            ),
                            Text('${d.rssi}',
                                style: TextStyle(fontSize: 12, color: dim)),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => _connect(d),
                              style: TextButton.styleFrom(
                                  backgroundColor: AppTheme.green.withOpacity(.15),
                                  foregroundColor: AppTheme.green),
                              child: Text(t('dev_connect')),
                            ),
                          ]),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scan,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: const Color(0xFF03130A),
                      minimumSize: const Size.fromHeight(44)),
                  icon: const Icon(Icons.radar, size: 18),
                  label: Text(t('dev_scan_btn')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _qr,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(44)),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: Text(t('dev_qr')),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
