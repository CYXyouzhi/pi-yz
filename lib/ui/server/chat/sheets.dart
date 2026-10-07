import 'dart:convert';

// 会话页的弹层与提示。
//
// 与 chat/widgets.dart 的分工：那边是渲染块（返回 Widget），
// 这边是「弹层与 SnackBar」这类带副作用的动作 —— 它们返回 Future<void> 或不返回，
// 所以抽成顶层函数而不是组件。同 files/sheets.dart 的做法。
//
// 状态与数据仍由调用方传进来；这里只负责把东西显示出来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../theme/neu.dart';
import '../../../server/chat_models.dart';
import '../../../theme/design_tokens.dart';

/// 「已删除，撤销」提示（5 秒，带撤销按钮）。
///
/// 收 [message] 与 [onUndo]：撤销要做什么由调用方决定（可能是把图片插回去、
/// 也可能是把草稿恢复），这里只负责显示。
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: NeuFonts.bodyMid)),
      duration: Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: I18n.t('ui.bd9fcf46b4'), onPressed: onUndo),
    ),
  );
}

/// 本轮改动速览 + 继续 / 再来一次。
///
/// 依赖为 0：它只用传入的 summary 与自己的局部变量 ——
/// 「继续 / 重做」两个动作通过 Navigator 的返回值交回调用方。
void showTurnSummarySheet(BuildContext context, TurnSummary summary) {
    final t = context.neu;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.fromLTRB(
          NeuSpace.n14,
          0,
          NeuSpace.n14,
          NeuSpace.n14 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        padding: const EdgeInsets.fromLTRB(NeuSpace.n16, NeuSpace.n14, NeuSpace.n16, NeuSpace.n10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.lg),
          gradient: NeuDecorations.raisedGradient(t),
          boxShadow: NeuShadows.raise(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  I18n.t('ui.94d80e751a'),
                  style: TextStyle(
                    fontSize: NeuFonts.bodyLg,
                    fontWeight: FontWeight.w700,
                    color: t.fg,
                  ),
                ),
                SizedBox(width: NeuSpace.n8),
                Text(
                  I18n.tp('ui.064981f079', {'files': summary.files.length, 'added': summary.added, 'removed': summary.removed}),
                  style: TextStyle(fontSize: NeuFonts.label, color: t.accentInk),
                ),
              ],
            ),
            const SizedBox(height: NeuSpace.n8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: summary.files.length,
                itemBuilder: (_, index) {
                  final file = summary.files[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.path,
                          maxLines: 2,
                          // 文件路径可以很长，截断后没有省略号用户会以为路径就这么短
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
                        ),
                        SizedBox(height: NeuSpace.n2),
                        Text(
                          '+${file.added}/-${file.removed}'
                          '${file.writes > 0 ? I18n.tp('ui.eddf38f2db', {'n': file.writes}) : ''}'
                          '${file.edits > 0 ? I18n.tp('ui.038edd57e7', {'n': file.edits}) : ''}',
                          style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: NeuSpace.n6),
            Text(
              summary.basis.isEmpty ? I18n.t('ui.4dc7b743df') : summary.basis,
              style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
            ),
          ],
        ),
      ),
    );
  
}

void showDataSheet(BuildContext context, String title, dynamic payload) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NeuRadii.lg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n18, NeuSpace.n18, NeuSpace.n24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: NeuFonts.sectionTitle,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
            const SizedBox(height: NeuSpace.n12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  formatPayload(payload),
                  style: TextStyle(
                    fontSize: NeuFonts.sub,
                    height: 1.7,
                    fontFamily: 'monospace',
                    color: t.fg,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String formatPayload(dynamic payload) {
  if (payload is Map) {
    final lines = <String>[];
    payload.forEach((key, value) {
      final rendered = (value is Map || value is List)
          ? const JsonEncoder.withIndent('  ').convert(value)
          : '$value';
      lines.add('$key: $rendered');
    });
    return lines.join('\n');
  }
  if (payload is List) {
    return payload.map((e) => '$e').join('\n');
  }
  return payload?.toString() ?? I18n.t('ui.756aadc26d');
}
