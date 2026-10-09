import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';

/// 「从这条消息分叉出新会话」的确认框。
///
/// 与「切换分支」的区别要说清楚：切换是同一会话内换路径，
/// 这里是**另开一条会话**从该点往后走，原会话保持不动 —— 用户容易混。
Future<bool?> confirmForkDialog(
  BuildContext context, {
  required String entryId,
  required String preview,
}) {
  final t = context.neu;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.bg,
      title: Text(
        I18n.t('ui.a1c0a7962b'),
        style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
      ),
      content: Text(
        // ignore: prefer_interpolation_to_compose_strings
        '${I18n.tp('ui.124ba57d80', {'preview': preview.isEmpty ? entryId.substring(0, 8) : preview})}'
        '${I18n.t('ui.1263de37a0')}',
        style: TextStyle(
          color: t.muted,
          fontSize: NeuFonts.bodySmall,
          height: 1.6,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            I18n.t('common.cancel'),
            style: TextStyle(color: t.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            I18n.t('ui.bfc04cfda7'),
            style: TextStyle(color: t.accentInk),
          ),
        ),
      ],
    ),
  );
}

/// 「切到树里的另一个节点」的确认框。
///
/// 切换会改变模型上下文（后续对话接在另一条分支上），所以必须先确认；
/// 另给一个可选勾选「生成摘要」—— 把被舍弃的那条分支压缩成摘要带过去
/// （pi 的 editorText 行为之外的一条补偿路径，跑一次模型，耗时明显）。
///
/// 返回值：**null = 取消**；非 null = 确认，`summarize` 带勾选状态。
/// 用记录而不是 (bool, bool) 元组，是为了让调用点读起来知道每个布尔是什么。
Future<({bool summarize})?> confirmNavigateDialog(
  BuildContext context, {
  required String targetId,
  required String preview,
}) {
  final t = context.neu;
  var summarize = false;
  return showDialog<({bool summarize})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(
          I18n.t('ui.4956c9f6d6'),
          style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // ignore: prefer_interpolation_to_compose_strings
              '${I18n.tp('ui.558ac73c08', {'preview': preview.isEmpty ? targetId.substring(0, 8) : preview})}'
              '${I18n.t('ui.68af09ffe6')}',
              style: TextStyle(
                color: t.muted,
                fontSize: NeuFonts.bodySmall,
                height: 1.6,
              ),
            ),
            const SizedBox(height: NeuSpace.n14),
            GestureDetector(
              onTap: () => setDialogState(() => summarize = !summarize),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    summarize ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: summarize ? t.accentInk : t.muted,
                  ),
                  SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      I18n.t('ui.e949f0cedd'),
                      style: TextStyle(
                        color: summarize ? t.fg : t.muted,
                        fontSize: NeuFonts.sub,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(
              I18n.t('common.cancel'),
              style: TextStyle(color: t.muted),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop((summarize: summarize)),
            child: Text(
              I18n.t('ui.bec7e4d621'),
              style: TextStyle(color: t.accentInk),
            ),
          ),
        ],
      ),
    ),
  );
}
