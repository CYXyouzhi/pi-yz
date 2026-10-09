// widget 测试的公共脚手架。
//
// 为什么抽出来：原先这些辅助函数只住在 `widget_test.dart` 里。新增多分辨率
// 适配测试（`resolution_test.dart`）也要用同一套「设成手机尺寸 + 跳过启动遮罩
// + 手动推进动画」的步骤 —— 不抽出来就得复制一份，而复制品迟早会走偏
// （一处修了另一处没修）。
//
// 两条踩过的坑，原本记在 widget_test.dart 头部，跟着搬过来：
// 1. `pumpAndSettle` 会被**永久循环**的动画卡死 —— 状态点的呼吸/心跳在设计上
//    就要一直动（设计稿原话：running 是「唯一在动的那个」）。所以手动推进时长。
// 2. 默认测试窗口只有 800×600，长表单里的按钮会落在屏幕外，
//    `tap` 会**静默落空**（只打一条 warning），于是断言看到「校验没生效」的假象。
//    所以先设成手机尺寸，再点之前 `ensureVisible`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/theme/design_tokens.dart';
import 'package:pi_yz/theme/neu_theme.dart';
import 'package:pi_yz/ui/nav_bar_visibility.dart';

/// 把测试窗口设成手机尺寸（默认 800×600 会让长页面的按钮落到屏幕外）。
///
/// [width] / [height] 是**逻辑像素**（dp）。devicePixelRatio 钉成 1.0，
/// 于是 physicalSize 就等于逻辑尺寸 —— 这样读起来是「360dp 宽」而不是
/// 「1080 物理像素 ÷ 3 倍密度」。
void setPhoneSurface(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // 导航栏可见性是全局 static 开关，且**会话页默认收起**：上一个用例留下的
  // 状态会让下一个用例找不到底部 Tab（实测 10 个外壳用例全挂）。
  // 每个用例先复位成「导航栏显示」；用例若要走收起路径，自己再设回去或点把手。
  NavBarVisibility.hidden.value = false;
  // 语言钉成中文：I18n 跟系统 locale，CI/开发机可能是 en，
  // 那样断言里的中文就找不到（环境问题，不是界面问题）。
  // 需要验英文模式的用例自己会覆盖 AppPrefs.lang，不受这里影响。
  tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
  tester.binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
}

/// 手动推进固定时长（不能用 pumpAndSettle，理由见文件头）。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// 跳过启动遮罩。
///
/// 遮罩的退场计时锚在「首帧真的呈现」上（帧时序回调）；测试环境没有真实光栅化，
/// 那个回调不会来，于是走 6 秒兜底计时 —— 这里直接把它推过去，再等淡出动画。
Future<void> skipSplash(WidgetTester tester) async {
  await tester.pump();
  // 遮罩的兜底定时器是 6s，之后还有 420ms 的退场动画 —— 留够时间让它走完
  await tester.pump(const Duration(seconds: 7));
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 800));
}

/// 滚到可见再点 —— 否则离线按钮的 tap 会静默落空。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// 点底部 Tab。会话页默认把导航栏收起（只留屏底把手），所以点 Tab 之前要先
/// 确保导航栏在屏幕上 —— 走用户真实路径：点把手唤出，而不是直接改全局开关。
/// 直接改开关的话，「把手到底能不能唤出导航栏」这条最容易坏的路就没被测到。
Future<void> tapTab(WidgetTester tester, String label) async {
  final handle = find.byKey(navBarHandleKey);
  if (handle.evaluate().isNotEmpty) {
    await tester.tap(handle);
    await settle(tester);
  }
  await tapVisible(tester, find.text(label));
}

/// 展开设置页里的某个分组。
///
/// 设置页现在**默认全部收起**（用户明确要求「默认收起来、点击再展开」），
/// 所以凡是要断言分组内容的用例，都得先把它点开 —— 否则断言的是
/// 「渲染失败」和「默认收起」这两种完全不同的事。
Future<void> openSection(WidgetTester tester, String title) async {
  await tapVisible(tester, find.text(title));
  await settle(tester);
}

/// 收尾：把待触发的定时器推完，避免测试因「pending timer」失败。
Future<void> flushTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
}

/// 给孤立组件套上 App 的皮肤（主题 + 画布），用于不依赖真实入口的用例。
Widget harness(Widget child, {Brightness brightness = Brightness.light}) {
  final tokens = brightness == Brightness.dark
      ? NeuTokens.dark
      : NeuTokens.light;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildNeuTheme(tokens, brightness: brightness),
    home: NeuCanvas(
      brightness: brightness,
      child: Scaffold(backgroundColor: Colors.transparent, body: child),
    ),
  );
}
