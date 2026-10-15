import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 关于页：公司 logo + 名称 + 版本 + 描述。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = (k) => L.tr(app.isEn, k);
    final dim = Theme.of(context).colorScheme.onSurface.withOpacity(.55);
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
            child: Text(t('about_version'),
                style: TextStyle(fontSize: 13, color: dim)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(t('about_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: dim, height: 1.8)),
          ),
        ],
      ),
    );
  }
}
