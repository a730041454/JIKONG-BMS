import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 关于页：公司 logo + 名称 + 版本（动态读取）+ 描述。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }).catchError((_) {
      if (mounted) setState(() => _version = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
    final versionText =
        '${t('about_version')} ${_version.isEmpty ? '…' : _version}';
    return Scaffold(
      appBar: AppBar(title: Text(t('about_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/logo.png',
                  width: 280, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(versionText,
                style: TextStyle(fontSize: 13, color: dim)),
          ),
          const SizedBox(height: 20),
          // 版本更新内容
          _Sec(t('about_updates'), dim),
          _UpdateRow('v1.0.15',
              t('about_u15')),
          _UpdateRow('v1.0.14',
              t('about_u14')),
          _UpdateRow('v1.0.13',
              t('about_u13')),
          _UpdateRow('v1.0.12',
              t('about_u12')),
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
      Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 8), child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dim)));
}

class _UpdateRow extends StatelessWidget {
  final String ver;
  final String desc;
  const _UpdateRow(this.ver, this.desc);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: surface, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface2,
              borderRadius: BorderRadius.circular(6)),
          child: Text(ver,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.green)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(desc,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.8))),
        ),
      ]),
    );
  }
}
