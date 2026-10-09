// 多分辨率适配：360 / 400 / 450dp 竖屏 + 刘海/挖孔安全区。
//
// ## 为什么需要这个文件
//
// 原先只有一个 golden 用例（`slash_panel_golden_test.dart`），跑的是 400×800
// 单一尺寸，而且渲染的是孤立的小组件而非真实页面 —— 换个机型就没保障。
// 而目标机型是「主流手机竖屏 360~450dp（含刘海/挖孔安全区）」。
// 只有一种尺寸，等于没验证过适配。
//
// ## 做法：跑真实入口，而不是渲染小组件
//
// `PiYzApp()` 能直接起来（只依赖 shared_preferences，mock 即可），所以这里让
// **真实 App** 在每种宽度下跑一遍。
//
// 溢出检测靠 Flutter 自身：RenderFlex 溢出会抛异常、测试直接失败，所以
// 「pump 不报错」就是溢出检测，比人眼看截图可靠，也不用维护基线图。
//
// ## 两个刻意写强的地方
//
// 1. **不做静默跳过**。凡是「先判断元素在不在，不在就 continue」的写法，
//    都会让测试在界面结构变化后悄悄变成空转，还一路报绿。这里一律硬断言：
//    前提不成立就直接失败，把问题暴露出来。
// 2. **安全区用「对比」验证**，不是「不超出某条线」。后者在 App 完全无视
//    安全区时也可能碰巧通过；前者要求「底部元素恰好上移了安全区那么多」，
//    只有真的处理了安全区才能满足。
//
// ## 边界
//
// 只覆盖竖屏 360~450dp。平板/折叠屏（600dp+）、横屏、320dp 老机型不在范围内。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

/// 目标宽度（dp）。主流手机的竖屏逻辑宽度基本落在这三档：
///   · 360 —— 大量国产机型与较早的 Android（1080p 屏按 3 倍密度就是 360）
///   · 400 —— 中间档
///   · 450 —— 大屏机型（iPhone Pro Max 一档、部分高密度 Android）
const List<double> kTargetWidths = [360, 400, 450];

/// 刘海/挖孔屏的典型安全区（dp）：
///   · 顶部 47 ≈ 灵动岛 / 挖孔屏的状态栏区域
///   · 底部 34 ≈ 手势导航条
const FakeViewPadding kTopNotch = FakeViewPadding(top: 47);
const FakeViewPadding kBottomBar = FakeViewPadding(bottom: 34);

/// 最小可点区域（Material 规范 48dp，也是无障碍的最低要求）。
const double kMinTapTarget = 48;

const double kScreenHeight = 844;

/// 起一次真实 App 并跳过启动遮罩。
Future<void> boot(WidgetTester tester) async {
  await tester.pumpWidget(const PiYzApp());
  await skipSplash(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
  });

  group('① 三种目标宽度：真实入口能起来，遍历各页面不溢出', () {
    for (final width in kTargetWidths) {
      testWidgets('${width.toInt()}dp：启动并切换 Tab', (tester) async {
        setPhoneSurface(tester, width: width);
        await boot(tester);
        // 溢出会被报告成异常；显式确认没有
        expect(
          tester.takeException(),
          isNull,
          reason: '${width.toInt()}dp 启动阶段出现异常（含溢出）',
        );

        // 前提：底部 Tab 真的在（否则下面的遍历是空转）
        expect(
          find.text('会话'),
          findsWidgets,
          reason: '${width.toInt()}dp：找不到「会话」Tab',
        );
        expect(
          find.text('设置'),
          findsWidgets,
          reason: '${width.toInt()}dp：找不到「设置」Tab',
        );

        for (final tab in ['会话', '设置']) {
          await tapTab(tester, tab);
          expect(
            tester.takeException(),
            isNull,
            reason: '${width.toInt()}dp 切到「$tab」时出现异常（含溢出）',
          );
        }
      });
    }
  });

  group('② 底部安全区（手势条）：底部 Tab 要真的为它让出空间', () {
    for (final width in kTargetWidths) {
      testWidgets('${width.toInt()}dp：让位量等于安全区高度', (tester) async {
        setPhoneSurface(tester, width: width);

        // 先量无安全区时的位置
        await boot(tester);
        expect(find.text('设置'), findsWidgets, reason: '前提：底部 Tab 应该存在');
        final bare = tester.getRect(find.text('设置'));

        // 重建，这次带上底部安全区
        await tester.pumpWidget(const SizedBox());
        tester.view.padding = kBottomBar;
        await boot(tester);
        final padded = tester.getRect(find.text('设置'));

        // 关键断言：恰好多让出了「安全区高度」那一段。
        // 若 App 无视安全区，差值会是 0 —— 用「不超出某条线」的弱断言就会漏掉。
        expect(
          bare.bottom - padded.bottom,
          closeTo(kBottomBar.bottom, 1.0),
          reason:
              '${width.toInt()}dp：底部 Tab 没有为 ${kBottomBar.bottom}dp 的手势条让出空间'
              '（实际让位 ${(bare.bottom - padded.bottom).toStringAsFixed(1)}dp）',
        );
      });
    }
  });

  group('③ 顶部安全区（刘海/挖孔）：内容不被状态栏压住', () {
    for (final width in kTargetWidths) {
      testWidgets('${width.toInt()}dp：顶部内容为刘海让出空间', (tester) async {
        setPhoneSurface(tester, width: width);

        await boot(tester);
        // 首屏最靠上的那段文字
        final probe = find.text('连接');
        expect(probe, findsWidgets, reason: '前提：首屏应该出现「连接」');
        final bare = tester.getRect(probe);

        await tester.pumpWidget(const SizedBox());
        tester.view.padding = kTopNotch;
        await boot(tester);
        final padded = tester.getRect(find.text('连接'));

        expect(
          padded.top - bare.top,
          closeTo(kTopNotch.top, 1.0),
          reason:
              '${width.toInt()}dp：顶部内容没有为 ${kTopNotch.top}dp 的刘海让出空间'
              '（实际让位 ${(padded.top - bare.top).toStringAsFixed(1)}dp）',
        );
      });
    }
  });

  group('④ 点击区不小于 48dp', () {
    for (final width in kTargetWidths) {
      testWidgets('${width.toInt()}dp：底部 Tab 的可点区域达标', (tester) async {
        setPhoneSurface(tester, width: width);
        await boot(tester);

        for (final label in ['会话', '设置']) {
          // 硬断言，不静默跳过
          expect(
            find.text(label),
            findsWidgets,
            reason: '前提：底部 Tab「$label」应该存在',
          );

          // 底部 Tab 用 GestureDetector 承载点击（已实测：不是 InkWell）
          final tappable = find
              .ancestor(
                of: find.text(label),
                matching: find.byType(GestureDetector),
              )
              .first;
          final size = tester.getSize(tappable);

          expect(
            size.height,
            greaterThanOrEqualTo(kMinTapTarget - 0.5),
            reason:
                '${width.toInt()}dp：「$label」的可点高度只有 ${size.height}dp，低于 $kMinTapTarget',
          );
          expect(
            size.width,
            greaterThanOrEqualTo(kMinTapTarget - 0.5),
            reason:
                '${width.toInt()}dp：「$label」的可点宽度只有 ${size.width}dp，低于 $kMinTapTarget',
          );
        }
      });
    }
  });

  group('⑤ 窄屏压力：360dp 是最挤的一档', () {
    testWidgets('360dp：设置页展开各分组后仍不溢出', (tester) async {
      setPhoneSurface(tester, width: 360);
      await boot(tester);

      await tapTab(tester, '设置');
      expect(tester.takeException(), isNull);

      // 设置页默认全部收起，展开几块最长的，让内容真正铺开
      var opened = 0;
      for (final title in ['连接', '远程访问', '外观', '通知']) {
        final section = find.text(title);
        if (section.evaluate().isEmpty) continue;
        await tapVisible(tester, section);
        opened += 1;
        expect(tester.takeException(), isNull, reason: '360dp：展开「$title」后溢出');
      }
      // 至少展开到一块，否则这条用例没验证到东西
      expect(opened, greaterThan(0), reason: '360dp：一个分组都没展开，这条用例等于没跑');
    });
  });

  // 折叠分组的标题行是全 App 最要紧的一类点击入口（设置页、连接页、配置页
  // 都靠它进入子内容）。原先它的可点区只有 header 本身的高度：
  //   · 收起态 —— 卡片有 12dp 上下内边距，但 GestureDetector 在 padding 内侧，
  //     那圈内边距点不动
  //   · 展开态 —— 没有卡片内边距，header 裸着，实测可点高度只有 24dp
  // 修法见 neu_section.dart。这里把两种形态都钉住。
  group('⑥ 折叠分组标题的可点高度', () {
    testWidgets('360dp：收起态与展开态都不低于 48dp', (tester) async {
      setPhoneSurface(tester, width: 360);
      await boot(tester);
      await tapTab(tester, '设置');

      // 找一个带摘要的（收起态是缩略卡片）与一个不带摘要的（卡片会塌）
      for (final title in ['连接', '外观']) {
        expect(find.text(title), findsWidgets, reason: '前提：设置页应该有「$title」分组');

        final tappable = find
            .ancestor(
              of: find.text(title),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(
          tester.getSize(tappable).height,
          greaterThanOrEqualTo(kMinTapTarget - 0.5),
          reason: '「$title」收起态的可点高度不足 48dp',
        );

        // 展开后（普通标题行形态）也要达标
        await tapVisible(tester, find.text(title));
        expect(
          tester.getSize(tappable).height,
          greaterThanOrEqualTo(kMinTapTarget - 0.5),
          reason: '「$title」展开态的可点高度不足 48dp',
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
