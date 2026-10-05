// 快捷键栏展开态的布局回归。
//
// 用户报的 bug：点 `▤` 展开后，面板里**只有「快捷键」标题，键位全不见**。
// logcat 抓到的是布局断言失败（不是没画出来，是根本没布局完）：
//
//   RenderBox was not laid out: RenderConstrainedBox#...  NEEDS-PAINT
//   Failed assertion: 'hasSize'
//   #3 ChildLayoutHelper.layoutChild   (layout_helper.dart:63)
//   #4 RenderFlex._computeSizes        (flex.dart:1237)
//   #3 RenderAnimatedSize._layoutStable(animated_size.dart:329)
//
// 为什么原来的用例没抓到：`_KeyBarHarness` 用 `Align(bottomCenter)` 包着它，
// 而聊天页里 `NeuKeyBar` 是父 `Column` 的**直接子项**。两者的宽度约束不一样，
// 而问题恰恰出在约束上。所以这个文件按聊天页的真实层级搭。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/server/i18n.dart';
import 'package:pi_mobile/theme/design_tokens.dart';
import 'package:pi_mobile/theme/neu_theme.dart';
import 'package:pi_mobile/ui/key_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNeuTheme(NeuTokens.light, brightness: Brightness.light),
      home: NeuCanvas(
        brightness: Brightness.light,
        child: Scaffold(backgroundColor: Colors.transparent, body: child),
      ),
    );

/// 聊天页传的那套参数：有 `/` 命令键、有 `⏎` 发送键、不显示修饰键。
NeuKeyBar _chatKeyBar({required bool expanded}) => NeuKeyBar(
      visible: true,
      expanded: expanded,
      onExpandedChanged: (_) {},
      onVisibleChanged: (_) {},
      modifiers: const ModifierState(),
      onModifiersChanged: (_) {},
      onKey: (_) {},
      onCommands: () {},
      onEnter: () {},
      showModifiers: false,
    );

void main() {
  testWidgets('折叠态：一排键都能布局出来', (tester) async {
    await tester.pumpWidget(_wrap(
      Column(mainAxisSize: MainAxisSize.min, children: [_chatKeyBar(expanded: false)]),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Tab'), findsOneWidget);
  });

  testWidgets('展开态：标题和键位都要出来（用户报的那一条）', (tester) async {
    await tester.pumpWidget(_wrap(
      Column(mainAxisSize: MainAxisSize.min, children: [_chatKeyBar(expanded: true)]),
    ));
    await tester.pumpAndSettle();

    // 布局异常必须先被抓住 —— 只说「找不到 Esc」会把根因藏起来
    expect(tester.takeException(), isNull);

    expect(find.text(I18n.t('ui.f7d2996639')), findsOneWidget, reason: '标题行');
    expect(find.text('Esc'), findsOneWidget, reason: '展开面板的键位网格');
    expect(find.text('Tab'), findsOneWidget, reason: '展开面板的键位网格');
  });

  testWidgets('折叠 ↔ 展开来回切，不留下布局异常', (tester) async {
    var expanded = false;
    late StateSetter setOuter;

    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [_chatKeyBar(expanded: expanded)],
          );
        },
      ),
    ));
    await tester.pumpAndSettle();

    for (final want in [true, false, true]) {
      setOuter(() => expanded = want);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '切到 expanded=$want 时布局失败');
    }
  });
}
