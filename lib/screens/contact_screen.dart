import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/wechat_service.dart';

/// 微信联系：展示客服二维码，支持保存到相册、点击直接打开微信客服。
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  bool _saving = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openWeChat() async {
    final app = context.read<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    try {
      final r = await WeChatService.openWeChat();
      if (r == WeChatOpenResult.none) _toast(t('wechat_no_app'));
    } catch (_) {
      _toast(t('wechat_jump_fail'));
    }
  }

  Future<void> _saveQr() async {
    if (_saving) return;
    final app = context.read<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    setState(() => _saving = true);
    try {
      await WeChatService.saveQr();
      _toast(t('wechat_saved'));
    } on PlatformException {
      _toast(t('wechat_save_fail'));
    } catch (_) {
      _toast(t('wechat_save_fail'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    return Scaffold(
      appBar: AppBar(title: Text(t('wechat_contact'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Center(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openWeChat,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.green.withOpacity(.16),
                          blurRadius: 22)
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset(kWechatQrAsset, width: 260),
                    const SizedBox(height: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.touch_app_outlined,
                          size: 15, color: Color(0xFF0E8C4B)),
                      const SizedBox(width: 4),
                      Text(t('wechat_tap_hint'),
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0E8C4B),
                              fontWeight: FontWeight.w600)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(t('wechat_support'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(t('wechat_scan_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: dim, height: 1.6)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openWeChat,
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: const Color(0xFF03130A),
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(t('wechat_open')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _saving ? null : _saveQr,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46)),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 18),
            label: Text(t('wechat_save')),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style:
                TextButton.styleFrom(minimumSize: const Size.fromHeight(42)),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(t('btn_back')),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface2Of(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18, color: AppTheme.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('wechat_add_hint'),
                    style: TextStyle(fontSize: 12, color: dim, height: 1.6)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
