import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

/// 是否使用模拟数据（预览自测）。
/// 生产 / 真实板子：false（默认，走 BLE 极空协议）。
const bool kUseMock = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(useMock: kUseMock),
      child: const BmsApp(),
    ),
  );
}
