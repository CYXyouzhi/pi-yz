// Markdown 渲染（新拟态风格）。
//
// 为什么必须做：pi 的回答大量使用标题/列表/代码块/表格，
// 之前按纯文本显示，表格会变成一堆 `| 线路 | 对象 |`，等于不能读。
//
// 样式全部从 NeuTokens 取，不新造颜色：
//   行内代码 / 代码块 → 凹槽材质 + 等宽字（读作「机器内容」）
//   链接 → accentInk + 下划线
//   引用 → 左侧 accent 竖线 + muted 文字
//   表格 → border 发丝线 + 小字号

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';

class NeuMarkdown extends StatelessWidget {
  const NeuMarkdown({
    super.key,
    required this.data,
    this.baseColor,
    this.fontSize = 14.5,
  });

  final String data;
  final Color? baseColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final fg = baseColor ?? t.fg;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize - 2,
      height: 1.55,
      color: fg,
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, height: 1.7, color: fg),
        a: TextStyle(
          fontSize: fontSize,
          color: t.accentInk,
          decoration: TextDecoration.underline,
        ),
        em: TextStyle(
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
          color: fg,
        ),
        strong: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        del: TextStyle(
          fontSize: fontSize,
          color: t.muted,
          decoration: TextDecoration.lineThrough,
        ),

        h1: TextStyle(
          fontSize: fontSize + 5,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.4,
        ),
        h2: TextStyle(
          fontSize: fontSize + 3,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.4,
        ),
        h3: TextStyle(
          fontSize: fontSize + 1.5,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.4,
        ),
        h4: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: t.accentInk,
        ),
        h5: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: t.muted,
        ),
        h6: TextStyle(
          fontSize: fontSize - 1,
          fontWeight: FontWeight.w600,
          color: t.muted,
        ),

        // 行内代码：浅凹槽，不抢正文
        code: mono.copyWith(backgroundColor: t.well, color: t.accentInk),
        // 代码块：整块凹槽 + 内阴影（文本样式沿用上面的 code）
        codeblockDecoration: BoxDecoration(
          gradient: NeuDecorations.wellGradient(t),
          borderRadius: BorderRadius.circular(NeuRadii.sm),
          boxShadow: NeuShadows.insetSm(t),
        ),
        codeblockPadding: const EdgeInsets.all(NeuSpace.n10),

        blockquote: TextStyle(fontSize: fontSize, height: 1.7, color: t.muted),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.accent, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(
          NeuSpace.n12,
          NeuSpace.n4,
          0,
          NeuSpace.n4,
        ),

        listBullet: TextStyle(
          fontSize: fontSize,
          color: t.accentInk,
          height: 1.7,
        ),
        listIndent: 20,

        tableHead: TextStyle(
          fontSize: fontSize - 1.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        tableBody: TextStyle(fontSize: fontSize - 1.5, height: 1.5, color: fg),
        tableBorder: TableBorder.all(color: t.border, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n8,
          vertical: NeuSpace.n6,
        ),
        // 表格：列宽按比例分配，**不能用 IntrinsicColumnWidth**。
        //
        // 用 IntrinsicColumnWidth 时列宽按内容自然宽算，表格总宽会超出气泡，
        // flutter_markdown_plus 虽然给这种情况套了一层横向 SingleChildScrollView，
        // 但实测在手机上横向拖拽根本不动（手势被可选中的正文/消息列表吃掉），
        // 于是长单元格（如「中国南方（云南、广西一带）」）被硬剪掉且无法查看。
        //
        // FlexColumnWidth：列在可用宽度内平分，长文本在单元格里换行 ——
        // 布局没那么紧凑，但一个字的正文都不会丢。
        tableColumnWidth: const FlexColumnWidth(),

        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        blockSpacing: 8,
      ),
    );
  }
}
