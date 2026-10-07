// 设置页的渲染基线（golden）。
//
// ## 为什么单独一个文件 + 打 tag
//
// 这些基线是在 **Windows** 上生成的。Ubuntu（CI 机器）的字体与图形栈不同，
// 同一个界面会渲染出不同的像素 —— 直接在 CI 上跑必然全红，而那**不是代码问题**。
// 所以给它们打上 `golden` tag，CI 里用 `flutter test --exclude-tags golden` 跳过；
// 本地（Windows）跑全量时仍然执行，视觉回归照样抓得到。
//
// ## 与断言式用例的分工（这个分工有实证）
//
// · 断言回答「**布局有没有爆**」—— 溢出会抛异常，所以 pump 不报错就是通过
// · golden 回答「**样子变了没有**」—— 颜色、间距、层级、圆角，断言抓不到
//
// 「AI 配置」卡片提到顶层后，它在 360dp 下摘要换行、比旁边分组高出一截
// （没溢出，只是变高），断言式用例全绿 —— 是看图才发现的。两类都要有。
//
// ## 生成 / 更新基线
//
//   flutter test --update-goldens test/settings_golden_test.dart
//
// 换字体或 Flutter 版本可能让基线整体偏移，那属于环境变化，确认无误后重新生成
// 即可 —— 不要为了让它变绿而放宽断言。
//
// ## 已知限制
//
// 测试环境没有中文字体，基线图里文字渲染成占位方块。所以 golden 验证的是
// 布局/间距/层级/圆角/配色；文案正确性由 i18n_integrity_test.dart 等负责。

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

/// 与 resolution_test.dart 一致的三档目标宽度。
const List<double> kGoldenWidths = [360, 400, 450];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
  });

  for (final width in kGoldenWidths) {
    testWidgets('${width.toInt()}dp：设置页渲染基线', (tester) async {
      setPhoneSurface(tester, width: width);
      await tester.pumpWidget(const PiYzApp());
      await skipSplash(tester);
      await tapTab(tester, '设置');
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/settings_${width.toInt()}dp.png'),
      );
    });
  }
}
