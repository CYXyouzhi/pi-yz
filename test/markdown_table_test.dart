// 表格列宽的回归护栏。
//
// 背景（2026-10-09 MuMu 实测）：列宽用 IntrinsicColumnWidth 时，表格总宽按内容
// 自然宽算，会超出气泡；flutter_markdown_plus 虽然给这种情况套了一层横向
// SingleChildScrollView，但真机上横向拖拽根本不动（手势被可选中的正文和消息
// 列表吃掉），长单元格（「中国南方（云南、广西一带）」）就被硬剪掉、永久看不到。
//
// 改成 FlexColumnWidth 后列在可用宽度内平分、长文本在单元格里换行。
// 这个用例钉的就是「别再换回需要横向滚动的列宽策略」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/ui/server/markdown_view.dart';

import 'support/ui_harness.dart';

void main() {
  testWidgets('表格列宽按可用宽度分配，长内容换行而不是被裁', (tester) async {
    setPhoneSurface(tester);
    const md =
        '| 水果 | 原产地 |\n'
        '| --- | --- |\n'
        '| 柑橘 | 中国南方（云南、广西一带的柑橘带） |';

    await tester.pumpWidget(
      harness(const SingleChildScrollView(child: NeuMarkdown(data: md))),
    );
    await settle(tester);

    final table = tester.widget<Table>(find.byType(Table));
    expect(
      table.defaultColumnWidth,
      isA<FlexColumnWidth>(),
      reason: 'IntrinsicColumnWidth 会让表格超出气泡且滚不动，长内容会被剪掉',
    );
    // 长单元格换行不该抛溢出异常
    expect(tester.takeException(), isNull);
  });
}
