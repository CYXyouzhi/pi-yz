// 平板与横屏的布局守卫。
//
// ## 为什么用 widget 测试，而不是在模拟器上截几张图
//
// MuMu 的 framebuffer 是固定物理尺寸：`wm size 1920x1080` 确实生效了
// （`wm size` 会显示 `Override size: 1920x1080`），但截图仍然是 1080×1920 ——
// 也就是说它**没法真的模拟平板/横屏**。
//
// 而 widget 测试换个尺寸只是一行赋值，还能把「不许溢出」变成可重复的断言：
// 以后每次改 UI 都会重新验证一遍。人工截图只在那一刻有效。
//
// ## 为什么横屏值得单独列出来
//
// 手机竖屏高度有 640~915dp，横屏只剩 360dp —— **高度直接少一半**。
// 长表单（设置页）、带输入框与底部按钮的页面最容易在这里爆。
//
// ## 判据
//
// 溢出会被 Flutter 报成异常，`takeException()` 拿得到，所以「没有异常」= 没溢出。
// 但**不溢出 ≠ 看得见**：元素可能被挤到屏幕之外，于是横屏单独断言
// 「底部 Tab 完整落在屏内」。
//
// 与 `resolution_test.dart` 的分工：那个管**手机宽度**（360/400/450）与安全区
// （刘海、手势条）、点击区尺寸；这里管**高度与形态**（横屏、平板）。
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

/// 形态：(名字, 逻辑宽, 逻辑高)
const kSurfaces = <(String, double, double)>[
  ('手机竖屏 360×640', 360, 640),
  ('手机横屏 640×360', 640, 360),
  ('平板竖屏 800×1280', 800, 1280),
  ('平板横屏 1280×800', 1280, 800),
  ('小平板横屏 1024×768', 1024, 768),
];

/// 宽 > 高的那几档（横屏专项只对它们有意义）
final kLandscape = kSurfaces.where((s) => s.$2 > s.$3).toList();

/// 起一次真实 App 并跳过启动遮罩（与 resolution_test.dart 一致）
Future<void> boot(WidgetTester tester) async {
  await tester.pumpWidget(const PiYzApp());
  await skipSplash(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
  });

  group('① 平板与横屏：启动 + 遍历各 Tab 不溢出', () {
    for (final (name, w, h) in kSurfaces) {
      testWidgets('$name：启动并切换 Tab', (tester) async {
        setPhoneSurface(tester, width: w, height: h);
        await boot(tester);

        expect(tester.takeException(), isNull, reason: '$name 启动阶段出现异常（含溢出）');
        // 前提：底部 Tab 真的在，否则下面的遍历是空转
        expect(find.text('会话'), findsWidgets, reason: '$name：找不到「会话」Tab');
        expect(find.text('设置'), findsWidgets, reason: '$name：找不到「设置」Tab');

        for (final tab in ['会话', '设置']) {
          await tapTab(tester, tab);
          expect(
            tester.takeException(),
            isNull,
            reason: '$name 切到「$tab」时报了异常（含溢出）',
          );
        }
        await flushTimers(tester);
      });
    }
  });

  group('② 设置页是最长的页面：每档形态都把分组逐个展开', () {
    for (final (name, w, h) in kSurfaces) {
      testWidgets('$name：展开「工作区」与「外观」', (tester) async {
        setPhoneSurface(tester, width: w, height: h);
        await boot(tester);
        await tapTab(tester, '设置');

        for (final section in ['工作区', '外观']) {
          await openSection(tester, section);
          expect(
            tester.takeException(),
            isNull,
            reason: '$name 展开「$section」时报了异常（含溢出）',
          );
        }
        await flushTimers(tester);
      });
    }
  });

  group('③ 横屏专项：底部 Tab 必须真的在屏内（不溢出 ≠ 看得见）', () {
    for (final (name, w, h) in kLandscape) {
      testWidgets('$name：底部 Tab 完整落在屏幕里', (tester) async {
        setPhoneSurface(tester, width: w, height: h);
        await boot(tester);

        final rect = tester.getRect(find.text('设置').last);
        expect(
          rect.top,
          greaterThanOrEqualTo(0.0),
          reason: '$name：「设置」被挤到屏幕上边之外',
        );
        expect(rect.bottom, lessThanOrEqualTo(h), reason: '$name：「设置」掉到屏幕下边之外');
        expect(
          rect.left,
          greaterThanOrEqualTo(0.0),
          reason: '$name：「设置」在屏幕左边之外',
        );
        expect(rect.right, lessThanOrEqualTo(w), reason: '$name：「设置」在屏幕右边之外');
        await flushTimers(tester);
      });
    }
  });
}
