import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 相机扫码页：识别设备二维码里的 MAC/设备名，返回给添加设备页去连接。
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    torchEnabled: false,
  );
  late final AnimationController _line;
  bool _busy = false;
  bool _torch = false;
  String? _hint;
  DateTime _lastBad = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _line = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _line.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 从二维码文本中提取设备标识：优先 MAC，其次设备型号/名称。
  String? _extractCode(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > 120) return null;
    final mac = RegExp(r'(?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}')
        .firstMatch(text)
        ?.group(0);
    if (mac != null) return mac.replaceAll('-', ':').toUpperCase();
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _\-\.]{1,40}$').hasMatch(text)) {
      return text;
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = _extractCode(raw);
      if (code == null) continue;
      _busy = true;
      try {
        await _controller.stop();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(code);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastBad).inMilliseconds > 1800) {
      _lastBad = now;
      final isEn = context.read<AppState>().isEn;
      setState(() => _hint = L.tr(isEn, 'qr_invalid'));
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _hint = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (ctx, error) => _CameraError(
            text: error.errorCode == MobileScannerErrorCode.permissionDenied
                ? t('qr_cam_denied')
                : '${t('qr_cam_denied')}\n${error.errorCode.name}',
            onRetry: () => _controller.start(),
          ),
        ),
        _ScanOverlay(line: _line),
        // 顶部：关闭 + 手电
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                IconButton(
                  onPressed: () async {
                    try {
                      await _controller.toggleTorch();
                      if (mounted) setState(() => _torch = !_torch);
                    } catch (_) {}
                  },
                  icon: Icon(
                      _torch ? Icons.flashlight_on : Icons.flashlight_off,
                      color: _torch ? AppTheme.green : Colors.white),
                  tooltip: t('qr_torch'),
                ),
              ],
            ),
          ),
        ),
        // 底部提示
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.55),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_hint ?? t('qr_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: _hint == null ? Colors.white70 : AppTheme.orange)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 取景框：四周压暗 + 四角霓虹角标 + 扫描线。
class _ScanOverlay extends StatelessWidget {
  final Animation<double> line;
  const _ScanOverlay({required this.line});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const side = 236.0;
      final hole = Rect.fromCenter(
        center: Offset(c.maxWidth / 2, c.maxHeight / 2 - 30),
        width: side,
        height: side,
      );
      final scrim = Colors.black.withOpacity(.55);
      Widget corner(bool top, bool left) => Positioned(
            top: top ? hole.top : null,
            bottom: top ? null : c.maxHeight - hole.bottom,
            left: left ? hole.left : null,
            right: left ? null : c.maxWidth - hole.right,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                border: Border(
                  top: top
                      ? const BorderSide(color: AppTheme.green, width: 3)
                      : BorderSide.none,
                  bottom: top
                      ? BorderSide.none
                      : const BorderSide(color: AppTheme.green, width: 3),
                  left: left
                      ? const BorderSide(color: AppTheme.green, width: 3)
                      : BorderSide.none,
                  right: left
                      ? BorderSide.none
                      : const BorderSide(color: AppTheme.green, width: 3),
                ),
              ),
            ),
          );
      return Stack(children: [
        Positioned(
            top: 0, left: 0, right: 0, height: hole.top,
            child: ColoredBox(color: scrim)),
        Positioned(
            top: hole.bottom, left: 0, right: 0, bottom: 0,
            child: ColoredBox(color: scrim)),
        Positioned(
            top: hole.top, left: 0, width: hole.left, height: hole.height,
            child: ColoredBox(color: scrim)),
        Positioned(
            top: hole.top, right: 0,
            left: hole.right, height: hole.height,
            child: ColoredBox(color: scrim)),
        corner(true, true),
        corner(true, false),
        corner(false, true),
        corner(false, false),
        // 扫描线
        Positioned(
          left: hole.left + 10,
          width: hole.width - 20,
          top: hole.top,
          child: SizedBox(
            height: hole.height,
            child: AnimatedBuilder(
              animation: line,
              builder: (context, _) => Align(
                alignment: Alignment(0, line.value * 2 - 1),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppTheme.green.withOpacity(0),
                      AppTheme.green,
                      AppTheme.green.withOpacity(0),
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.green.withOpacity(.6), blurRadius: 8)
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _CameraError extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _CameraError({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_outlined,
            size: 44, color: Colors.white54),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
              onPressed: onRetry,
              child: const Text('Retry / 重试',
                  style: TextStyle(color: AppTheme.green))),
          TextButton(
              onPressed: openAppSettings,
              child: Text(L.tr(context.watch<AppState>().isEn, 'app_perm'),
                  style: const TextStyle(color: Colors.white70))),
        ]),
      ]),
    );
  }
}
