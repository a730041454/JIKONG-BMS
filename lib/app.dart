import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/update_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class BmsApp extends StatelessWidget {
  const BmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        return MaterialApp(
          title: 'BMS 监控',
          debugShowCheckedModeBanner: false,
          navigatorKey: UpdateService.navigatorKey,
          theme: app.isDark ? AppTheme.dark() : AppTheme.light(),
          home: const HomeShell(),
        );
      },
    );
  }
}
