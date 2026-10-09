// 宽屏上的内容宽度约束。
//
// ## 为什么需要
//
// 布局是按手机竖屏（360~450dp）设计的。放到 1280dp 的平板横屏上，卡片会被拉到
// 原来的三倍宽 —— 不溢出、也点得到，但读一行要横扫整屏，视觉上很难看。
// 这正是「**不溢出 ≠ 好看**」的典型：断言式测试全绿，是看 golden 基线才发现的
// （`test/goldens/settings_1280x800.png` 生成出来一眼就看到了）。
//
// ## 为什么只约束「超过阈值」的那部分
//
// 窄屏一行都不改。手机端的布局与既有 golden 基线完全不受影响 —— 这条是**可验证的**：
// 接入后跑 `flutter test test/settings_golden_test.dart`，三档手机基线必须仍然通过，
// 只有平板档会变。若手机档也变了，说明这个组件的手伸得太长。
//
// 阈值取 840dp：Material 3 里「中等窗口」的上界。再宽就该上分栏布局了 ——
// 那是另一件事，不在这一步里做。
//
// ## 为什么放在外壳而不是各页面里
//
// 放在 App 外壳的内容区（main.dart 里 `IndexedStack` 外面）一处就够，三个 Tab
// 同时生效，页面自己不用知道屏幕有多宽。

import 'package:flutter/material.dart';

/// 宽屏下把内容收窄居中；窄屏原样返回。
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({super.key, required this.child});

  final Widget child;

  /// 超过这个逻辑宽度就收窄。840 是 Material 3「中等窗口」的上界。
  static const double maxWidth = 840;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;
        // 用 Padding 而不是 Center/Align：后两者会给 child 松约束，
        // 页面高度会塌成「尽可能小」，滚动区与底部对齐都会乱。
        // 加左右内边距能让 child 拿到「宽度正好 840、高度照旧」的紧约束。
        final side = (constraints.maxWidth - maxWidth) / 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: child,
        );
      },
    );
  }
}
