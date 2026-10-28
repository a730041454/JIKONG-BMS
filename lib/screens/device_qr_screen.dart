import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 生成当前设备的连接二维码（内容 = BLE MAC），可打印贴在电池包上。
class DeviceQrScreen extends StatelessWidget {
  const DeviceQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final id = (app.rememberedDeviceId ?? '').trim();
    final name = app.deviceName.trim();
    return Scaffold(
      appBar: AppBar(title: Text(t('gen_qr'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          if (id.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(children: [
                Icon(Icons.qr_code_2, size: 56, color: dim),
                const SizedBox(height: 12),
                Text(t('gen_qr_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: dim)),
              ]),
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.green.withOpacity(.18), blurRadius: 24)
                  ],
                ),
                child: QrImageView(
                  data: id,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  size: 250,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(name.isEmpty ? id : name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(id,
                  style: TextStyle(
                      fontSize: 13,
                      color: dim,
                      letterSpacing: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface2Of(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t('dev_qr_note'),
                      style: TextStyle(fontSize: 12, color: dim, height: 1.6)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
