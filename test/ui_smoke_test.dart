import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikong_bms_app/app.dart';
import 'package:jikong_bms_app/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面自检：三页导航改名生效、首页逆变器卡可展开、参数页两个分组渲染。
void main() {
  Future<AppState> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(useMock: true);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(value: app, child: const BmsApp()),
    );
    await tester.pump(const Duration(seconds: 2));
    return app;
  }

  testWidgets('默认进首页，含逆变器数据卡且可展开全部测点', (tester) async {
    final app = await boot(tester);

    // 「首页」同时出现在顶栏与底部导航，只要求至少一处
    expect(find.text('首页'), findsAtLeastNWidgets(1));
    expect(find.text('参数设置'), findsAtLeastNWidgets(1));
    expect(find.text('BMS管理'), findsWidgets);

    // 逆变器卡在首页更靠下的位置，先滚到卡片再校验
    final more = find.text('显示全部测点');
    await tester.dragUntilVisible(
        more, find.byType(ListView).first, const Offset(0, -150));
    expect(find.text('逆变器'), findsWidgets);
    await tester.tap(more);
    await tester.pump();
    expect(find.text('电网侧'), findsOneWidget);
    expect(find.text('光伏侧'), findsOneWidget);

    app.dispose();
  });

  testWidgets('参数设置页有「逆变器设置」与「BMS 设置」两个分组', (tester) async {
    final app = await boot(tester);

    await tester.tap(find.text('参数设置'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('逆变器设置'), findsOneWidget);
    expect(find.text('BMS 设置'), findsOneWidget);

    app.dispose();
  });
}
