import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../screens/gateway_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 未连接占位：不展示任何保护板数据，引导去连接设备。
///
/// 已连上但还没收到第一帧数据时显示读取中的转圈。
class NoConnection extends StatelessWidget {
  const NoConnection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final waiting = app.connected;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.green.withOpacity(.08),
                border: Border.all(color: AppTheme.green.withOpacity(.28)),
              ),
              child: waiting
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppTheme.green),
                    )
                  : Icon(Icons.link_off,
                      size: 38, color: AppTheme.green.withOpacity(.8)),
            ),
            const SizedBox(height: 18),
            Text(
              waiting ? t('reading_data') : t('no_conn_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              waiting ? t('reading_data_hint') : t('no_conn_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: dim, height: 1.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GatewayScreen())),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: const Color(0xFF03130A),
                minimumSize: const Size(180, 44),
              ),
              icon: const Icon(Icons.radar, size: 18),
              label: Text(t('no_conn_btn')),
            ),
          ],
        ),
      ),
    );
  }
}
