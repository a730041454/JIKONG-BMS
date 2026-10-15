import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

/// 是否使用模拟数据（预览自测）。
/// 生产 / 真实板子：false（默认，走 BLE 极空协议）。
const bool kUseMock = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏顶部系统状态栏（沉浸式），仅保留底部系统导航条
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
      overlays: const [SystemUiOverlay.bottom]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(useMock: kUseMock),
      child: const BmsApp(),
    ),
  );
}
