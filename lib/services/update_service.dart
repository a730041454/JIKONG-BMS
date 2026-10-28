import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// 更新源：Gitee 仓库（owner/repo）。发版时在 Release 里附上任意 `.apk` 附件，
/// 标签写成 `v2.0` 即可被 App 识别。
const String kUpdateRepo = 'gnzk/sample_repository';

/// V2 数据线：只认主版本号为 2 的 Release。1.x 的包与 V2 数据结构不兼容，
/// 即使 1.x 版本号更高也不能推给 V2 用户。
const int kUpdateMajor = 2;

/// 可选：自建 version.json 直链，非空时优先于 [kUpdateRepo]。
/// 格式：{"version":"2.1","apkUrl":"https://…/BMS_2.1.apk","size":69174170,"notes":"…"}
const String kUpdateManifestUrl = '';

class UpdateInfo {
  final String version;
  final String notes;
  final String apkUrl;
  final int size;
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    this.size = 0,
  });
}

class _CheckResult {
  final UpdateInfo? info;
  final bool failed;
  const _CheckResult(this.info, {this.failed = false});
}

class UpdateService {
  static const MethodChannel _channel = MethodChannel('bms/update');

  /// 全局导航器：后台下载完成后需要在任意页面弹窗，用它拿到 root context。
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 每次启动只自动提示一次，避免反复弹窗。
  static bool _promptedThisRun = false;

  /// 后台下载进度浮层。
  static OverlayEntry? _progressEntry;

  /// 当前正在下载的任务，避免重复触发。
  static bool _downloading = false;

  static Future<String> _currentVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  /// 检查更新：有更新弹窗询问，无更新只在手动检查时提示。
  static Future<void> checkAndPrompt(BuildContext context,
      {required bool en, bool manual = false}) async {
    if (!manual && _promptedThisRun) return;
    _promptedThisRun = true;
    final t = (k) => L.tr(en, k);
    final messenger = ScaffoldMessenger.of(context);
    if (manual) {
      messenger.showSnackBar(SnackBar(content: Text(t('update_checking'))));
    }
    final result = await _check().timeout(const Duration(seconds: 20),
        onTimeout: () => const _CheckResult(null, failed: true));
    if (!context.mounted) return;
    if (result.failed) {
      messenger.showSnackBar(SnackBar(content: Text(t('update_fail'))));
      return;
    }
    final info = result.info;
    if (info == null) {
      if (manual) {
        messenger.showSnackBar(SnackBar(content: Text(t('update_latest'))));
      }
      return;
    }
    if (!context.mounted) return;
    await _showUpdateDialog(context, en: en, info: info);
  }

  static Future<_CheckResult> _check() async {
    UpdateInfo? info;
    try {
      info = kUpdateManifestUrl.isNotEmpty
          ? await _fromManifest(kUpdateManifestUrl)
          : await _fromGitee();
    } catch (_) {
      return const _CheckResult(null, failed: true);
    }
    if (info == null) return const _CheckResult(null);
    if (!_onUpdateLine(info.version)) return const _CheckResult(null);
    final current = await _currentVersion();
    if (!_isNewer(info.version, current)) return const _CheckResult(null);
    return _CheckResult(info);
  }

  /// 是否属于本 App 的更新线（主版本号为 [kUpdateMajor]）。
  static bool _onUpdateLine(String version) {
    final segs = _segments(version);
    return segs.isNotEmpty && segs.first == kUpdateMajor;
  }

  static Future<UpdateInfo?> _fromManifest(String url) async {
    final decoded = await _fetchJson(url);
    if (decoded is! Map) return null;
    final json = decoded.cast<String, dynamic>();
    final version = _cleanTag((json['version'] ?? json['versionName'] ?? '').toString());
    final apk = (json['apkUrl'] ?? '').toString();
    if (version.isEmpty || apk.isEmpty) return null;
    return UpdateInfo(
      version: version,
      notes: (json['notes'] ?? '').toString(),
      apkUrl: apk,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 列出仓库 Release，取属于本更新线（主版本 [kUpdateMajor]）的最大版本。
  static Future<UpdateInfo?> _fromGitee() async {
    if (kUpdateRepo.isEmpty) return null;
    final decoded = await _fetchJson(
        'https://gitee.com/api/v5/repos/$kUpdateRepo/releases?per_page=100');
    if (decoded is! List) return null;
    Map<String, dynamic>? release;
    var lineVersion = '';
    for (final r in decoded) {
      if (r is! Map) continue;
      final version = _cleanTag((r['tag_name'] ?? '').toString());
      if (version.isEmpty || !_onUpdateLine(version)) continue;
      if (release == null || _isNewer(version, lineVersion)) {
        release = r.cast<String, dynamic>();
        lineVersion = version;
      }
    }
    if (release == null) return null;
    Map<String, dynamic>? apk;
    for (final a in (release['assets'] as List? ?? const [])) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '').toString().toLowerCase();
      if (!name.endsWith('.apk')) continue;
      // 同时有多个 apk 时优先选文件名带 bms 的
      if (apk == null || name.contains('bms')) apk = a.cast<String, dynamic>();
    }
    if (apk == null) {
      return UpdateInfo(
          version: lineVersion,
          notes: (release['body'] ?? '').toString(),
          apkUrl: '');
    }
    return UpdateInfo(
      version: lineVersion,
      notes: (release['body'] ?? '').toString(),
      apkUrl: (apk['browser_download_url'] ?? '').toString(),
      size: (apk['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 取不到该地址时返回 null（404 表示还没有 Release）。
  static Future<Object?> _fetchJson(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'BMS-Update');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static String _cleanTag(String tag) {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final m = RegExp(r'^[0-9]+(\.[0-9]+)*').firstMatch(v);
    return m?.group(0) ?? '';
  }

  /// 逐段比较数字版本号；只要远端有一段更大即为新版本。
  static bool _isNewer(String remote, String current) {
    final a = _segments(remote);
    final b = _segments(current);
    if (a.isEmpty) return false;
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _segments(String v) => _cleanTag(v)
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  static Future<void> _showUpdateDialog(BuildContext context,
      {required bool en, required UpdateInfo info}) async {
    final t = (k) => L.tr(en, k);
    final notes = info.notes.trim();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update, color: AppTheme.green, size: 34),
        title: Text('${t('update_title')} v${info.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Text(
              notes.isEmpty ? t('update_latest') : notes,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('update_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
            child: Text(t('update_now')),
          ),
        ],
      ),
    );
    if (go != true) return;
    // 弹窗关闭后转后台下载，下载完成再弹窗提示安装。
    unawaited(_downloadThenPrompt(en: en, info: info));
  }

  /// 后台下载：关闭弹窗后继续下载，完成后弹窗询问是否安装。
  static Future<void> _downloadThenPrompt(
      {required bool en, required UpdateInfo info}) async {
    if (_downloading) return;
    _downloading = true;
    final t = (k) => L.tr(en, k);
    final path = await _downloadApk(en: en, info: info);
    _downloading = false;
    if (path == null) {
      _toast(t('update_download_fail'));
      return;
    }
    await _promptInstall(en: en, path: path, info: info);
  }

  /// 下载 APK 到应用私有目录，返回文件路径；失败返回 null。
  /// 用 files 目录而不是缓存目录：系统可能随时清理缓存，而安装器读取 APK
  /// 是异步的，文件被清掉就会报「解析软件包时出现问题 / open failed: ENOENT」。
  static Future<String?> _downloadApk(
      {required bool en, required UpdateInfo info}) async {
    final t = (k) => L.tr(en, k);
    if (info.apkUrl.isEmpty) {
      _toast(t('update_no_apk'));
      return null;
    }
    final progress = ValueNotifier<(int, int)>((0, info.size));
    _showProgress(progress, t);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      await _cleanOldApks(dir, keep: 'BMS-${info.version}.apk');
      file = File('${dir.path}/BMS-${info.version}.apk');

      // 已存在部分下载时从断点继续。
      var downloaded = 0;
      if (await file.exists()) {
        downloaded = await file.length();
        if (info.size > 0 && downloaded == info.size) {
          _hideProgress();
          return file.path;
        }
      }

      final req = await client.getUrl(Uri.parse(info.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'BMS-Update');
      if (downloaded > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$downloaded-');
      }
      final resp = await req.close();

      if (resp.statusCode == 206 && downloaded > 0) {
        final total = resp.contentLength > 0
            ? resp.contentLength + downloaded
            : info.size;
        final sink = file.openWrite(mode: FileMode.append);
        var got = downloaded;
        progress.value = (got, total);
        await for (final chunk in resp) {
          sink.add(chunk);
          got += chunk.length;
          progress.value = (got, total);
        }
        await sink.flush();
        await sink.close();
      } else if (resp.statusCode == 200) {
        if (await file.exists()) await file.delete();
        final total = resp.contentLength > 0 ? resp.contentLength : info.size;
        final sink = file.openWrite();
        var got = 0;
        await for (final chunk in resp) {
          sink.add(chunk);
          got += chunk.length;
          progress.value = (got, total);
        }
        await sink.flush();
        await sink.close();
      } else {
        await resp.drain<void>();
        throw const HttpException('download failed');
      }

      // 校验文件大小，防止安装损坏的包。
      final actual = await file.length();
      if (info.size > 0 && actual != info.size) {
        await file.delete();
        throw HttpException('size mismatch: $actual != ${info.size}');
      }
      // 校验 ZIP 头，避免把错误页/半截文件交给安装器（否则只显示「解析失败」）。
      final head = await file.openRead(0, 2).toList();
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
        await file.delete();
        throw HttpException('not an apk file');
      }
      _hideProgress();
      return file.path;
    } catch (e) {
      _hideProgress();
      _toast('${t('update_download_fail')} ($e)');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 清理缓存目录里旧版本的 APK（保留 keep 指定的那个）。
  static Future<void> _cleanOldApks(Directory dir, {required String keep}) async {
    try {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final n = e.uri.pathSegments.last;
        if (n.endsWith('.apk') && n != keep) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  /// 下载完成后弹窗询问是否安装。
  static Future<void> _promptInstall(
      {required bool en, required String path, required UpdateInfo info}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final t = (k) => L.tr(en, k);
    final go = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppTheme.green, size: 34),
        title: Text(t('update_ready_title')),
        content: Text('${t('update_ready_body')} v${info.version}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('update_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
            child: Text(t('update_now')),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _installApk(path, en: en);
  }

  /// 拉起系统安装器。APK 文件不能在拉起后立刻删除——系统安装器是异步读取的，
  /// 提前删除会报「解析软件包时出现问题 / open failed: ENOENT」。
  static Future<void> _installApk(String path, {required bool en}) async {
    final t = (k) => L.tr(en, k);
    String? r;
    try {
      r = await _channel.invokeMethod<String>('installApk', {'path': path});
    } catch (e) {
      _toast('${t('update_install_fail')} ($e)');
      return;
    }
    switch (r) {
      case 'ok':
        break;
      case 'permission':
        _toast(t('update_install_perm'));
      default:
        _toast(t('update_install_fail'));
    }
  }

  /// 全局提示（不依赖具体页面的 context）。
  static void _toast(String msg) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    ScaffoldMessenger.of(nav.context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 底部进度浮层：后台下载时可见，不阻塞页面操作。
  static void _showProgress(
      ValueNotifier<(int, int)> progress, String Function(String) t) {
    _hideProgress();
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _progressEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 16,
        right: 16,
        bottom: 28,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(ctx).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: ValueListenableBuilder<(int, int)>(
              valueListenable: progress,
              builder: (_, v, __) {
                final (got, total) = v;
                final mb = (got / 1048576).toStringAsFixed(1);
                final totalMb =
                    total > 0 ? (total / 1048576).toStringAsFixed(1) : '?';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('update_downloading'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: total > 0 ? got / total : null,
                      color: AppTheme.green,
                      minHeight: 5,
                    ),
                    const SizedBox(height: 6),
                    Text('$mb / $totalMb MB',
                        style: const TextStyle(fontSize: 11)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    overlay.insert(_progressEntry!);
  }

  static void _hideProgress() {
    _progressEntry?.remove();
    _progressEntry = null;
  }
}
