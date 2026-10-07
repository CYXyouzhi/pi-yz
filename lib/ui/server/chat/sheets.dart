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
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../neu_icons.dart';

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

Future<void> showPickerSheet(
BuildContext context,
ServerStore store,
Map<String, dynamic> builtin,
) async {
  final picker = builtin['picker'] as String?;
  final title = builtin['title'] as String? ?? I18n.t('common.select');
  final options =
      (builtin['options'] as List?)?.whereType<Map>().toList() ?? const [];

  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    // 不打开这个开关，弹层最高只有半屏，小屏手机上内容会被切掉
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NeuRadii.lg),
          ),
        ),
        padding: const EdgeInsets.all(NeuSpace.n18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: NeuFonts.sectionTitle,
                color: t.onBg,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: NeuSpace.n12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, index) {
                  final option = options[index].cast<String, dynamic>();
                  final value = option['value'] as String? ?? '';
                  final label = option['label'] as String? ?? value;
                  final group = option['group'] as String?;
                  final current = option['current'] == true;
                  return NeuPressable(
                    onTap: () => Navigator.of(sheetContext).pop(value),
                    flat: !current,
                    alwaysInset: current,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n12,
                      vertical: NeuSpace.n10,
                    ),
                    margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                              ),
                              if (group != null)
                                Text(
                                  group,
                                  style: TextStyle(
                                    fontSize: NeuFonts.label,
                                    color: t.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (current)
                          NeuIcon(IconId.check, size: 16, color: t.accentInk),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  if (picked == null) return;
  if (picker == 'model') {
    final parts = picked.split('/');
    if (parts.length == 2) await store.setModel(parts[0], parts[1]);
  } else if (picker == 'thinking') {
    await store.setThinkingLevel(picked);
  }
}

Future<String?> askText(
BuildContext context,
{
  required String title,
  String? placeholder,
  String? prefill,
  required bool multiline,
}) async {
  final controller = TextEditingController(text: prefill ?? '');
  final t = context.neu;
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(title, style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: NeuInset(
          radius: NeuRadii.sm,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: multiline ? 4 : 1,
            maxLines: multiline ? 10 : 1,
            style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: placeholder,
              hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
              contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(I18n.t('common.ok'), style: TextStyle(color: t.accentInk)),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool?> askConfirm(
BuildContext context,
UiRequest request,
) async {
  final t = context.neu;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.bg,
      title: Text(
        request.title ?? I18n.t('ui.e83a256e4f'),
        style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
      ),
      content: Text(
        request.message ?? '',
        style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(I18n.t('common.ok'), style: TextStyle(color: t.accentInk)),
        ),
      ],
    ),
  );
}

Future<String?> askSelect(
BuildContext context,
UiRequest request,
) async {
  return showModalBottomSheet<String?>(
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
        padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(NeuRadii.hairline),
                ),
              ),
            ),
            SizedBox(height: NeuSpace.n14),
            Text(
              request.title ?? I18n.t('ui.708c9d6d2a'),
              style: TextStyle(
                fontSize: NeuFonts.sectionTitle,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
            if (request.message != null && request.message!.isNotEmpty) ...[
              const SizedBox(height: NeuSpace.n4),
              Text(
                request.message!,
                style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
              ),
            ],
            const SizedBox(height: NeuSpace.n14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: request.options.length,
                itemBuilder: (_, index) {
                  final option = request.options[index];
                  return NeuPressable(
                    onTap: () => Navigator.of(sheetContext).pop(option),
                    flat: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n14,
                      vertical: NeuSpace.n12,
                    ),
                    margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                    child: Text(
                      option,
                      style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showUiDialog(
BuildContext context,
ServerStore store,
UiRequest request,
) async {
  switch (request.method) {
    case 'select':
      final picked = await askSelect(context, request);
      await store.respondUi(
        request.id,
        picked == null ? {'cancelled': true} : {'value': picked},
      );
    case 'confirm':
      final confirmed = await askConfirm(context, request);
      await store.respondUi(
        request.id,
        confirmed == null ? {'cancelled': true} : {'confirmed': confirmed},
      );
    case 'input':
      final text = await askText(context, 
        title: request.title ?? I18n.t('common.input'),
        placeholder: request.placeholder,
        multiline: false,
      );
      await store.respondUi(
        request.id,
        text == null ? {'cancelled': true} : {'value': text},
      );
    case 'editor':
      final text = await askText(context, 
        title: request.title ?? I18n.t('ui.95b351c862'),
        prefill: request.prefill,
        multiline: true,
      );
      await store.respondUi(
        request.id,
        text == null ? {'cancelled': true} : {'value': text},
      );
    default:
      // 未知类型直接取消：宁可扩展提前退出，也不要它干等
      await store.respondUi(request.id, {'cancelled': true});
  }
}
