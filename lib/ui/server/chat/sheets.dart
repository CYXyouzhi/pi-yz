// 会话页的弹层与提示。
//
// 与 chat/widgets.dart 的分工：那边是渲染块（返回 Widget），
// 这边是「弹层与 SnackBar」这类带副作用的动作 —— 它们返回 Future<void> 或不返回，
// 所以抽成顶层函数而不是组件。同 files/sheets.dart 的做法。
//
// 状态与数据仍由调用方传进来；这里只负责把东西显示出来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
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
