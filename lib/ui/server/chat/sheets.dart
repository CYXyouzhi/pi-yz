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
import '../../../server/server_types.dart';
import '../../../server/template_store.dart';
import '../../neu_toast.dart';
import 'message_detail.dart';
import '../export_page.dart';
import '../files_page.dart';
import '../usage_page.dart';

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
      content: Text(
        message,
        style: const TextStyle(fontSize: NeuFonts.bodyMid),
      ),
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
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n16,
        NeuSpace.n14,
        NeuSpace.n16,
        NeuSpace.n10,
      ),
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
                I18n.tp('ui.064981f079', {
                  'files': summary.files.length,
                  'added': summary.added,
                  'removed': summary.removed,
                }),
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
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          color: t.muted,
                        ),
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
        padding: const EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n18,
          NeuSpace.n18,
          NeuSpace.n24,
        ),
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
                                style: TextStyle(
                                  fontSize: NeuFonts.bodyTight,
                                  color: t.fg,
                                ),
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
  BuildContext context, {
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
        title: Text(
          title,
          style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
        ),
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
              hintStyle: TextStyle(
                fontSize: NeuFonts.bodySmall,
                color: t.muted,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: NeuSpace.n12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              I18n.t('common.cancel'),
              style: TextStyle(color: t.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(
              I18n.t('common.ok'),
              style: TextStyle(color: t.accentInk),
            ),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool?> askConfirm(BuildContext context, UiRequest request) async {
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
        style: TextStyle(
          color: t.muted,
          fontSize: NeuFonts.bodyMid,
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
            I18n.t('common.ok'),
            style: TextStyle(color: t.accentInk),
          ),
        ),
      ],
    ),
  );
}

Future<String?> askSelect(BuildContext context, UiRequest request) async {
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
        padding: const EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n10,
          NeuSpace.n18,
          NeuSpace.n24,
        ),
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
                      style: TextStyle(
                        fontSize: NeuFonts.bodyTight,
                        color: t.fg,
                      ),
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
      final text = await askText(
        context,
        title: request.title ?? I18n.t('common.input'),
        placeholder: request.placeholder,
        multiline: false,
      );
      await store.respondUi(
        request.id,
        text == null ? {'cancelled': true} : {'value': text},
      );
    case 'editor':
      final text = await askText(
        context,
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

/// 模型切换器里的一行：模型名 + provider/窗口/推理标记，当前项打勾。
///
/// **收 `onTap` 而不是 `StateSetter`** —— 原实现把弹层的 `setState` 直接传进来、
/// 在组件里去改父级状态，那是把「谁负责状态」搅在一起了。现在组件只报告被点了，
/// 切模型、报错、弹 toast 都由弹层函数自己做。
class ModelOptionRow extends StatelessWidget {
  const ModelOptionRow({
    super.key,
    required this.model,
    required this.current,
    required this.onTap,
  });

  final ModelInfo model;

  /// 当前选中的模型 —— 用来判断这一行是不是「正在用的」。
  final ModelInfo? current;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final isCurrent =
        current != null &&
        current!.provider == model.provider &&
        current!.id == model.id;
    return NeuPressable(
      flat: !isCurrent,
      alwaysInset: isCurrent,
      radius: 10,
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n12,
        vertical: NeuSpace.n9,
      ),
      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                ),
                Text(
                  I18n.tp('ui.b7077d029c', {
                        'provider': model.provider,
                        'window': model.contextWindow ?? '?',
                      }) +
                      (model.reasoning ? I18n.t('ui.af181ac8b2') : ''),
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          if (isCurrent) NeuIcon(IconId.check, size: 15, color: t.accentInk),
        ],
      ),
    );
  }
}

/// 模型 + 思考等级的浮动切换器（弹层）。
///
/// **为什么错误行不用 NeuToast**：底部弹层也在 overlay 里且盖在上面，
/// 弹层里弹出的 toast 会被自己挡住 —— 实测症状是「切模型失败但什么都看不到」。
/// 所以错误显示在弹层内部的一行里（`inSheetError`）。
///
/// 按 provider 分组：用户切换时要能一眼看出「这条是官方还是中转」。
/// 高度上限 80% 屏高，内容可滚。
Future<void> showModelSwitcherSheet(
  BuildContext context,
  ServerStore store,
) async {
  final models = await store.availableModels();
  final levels = await store.availableThinkingLevels();
  if (!context.mounted) return;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      // 弹层内部的错误行。
      // 为什么不用 NeuToast：底部弹层也在 overlay 里且盖在上面，
      // 弹层里弹出的 toast 会被自己挡住 —— 实测「切模型失败但什么都看不到」。
      String? inSheetError;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final chat = store.chat;
          final current = chat.model;
          // 按 provider 分组，切换时能一眼看出「这条是官方还是中转」
          final byProvider = <String, List<ModelInfo>>{};
          for (final model in models) {
            byProvider.putIfAbsent(model.provider, () => []).add(model);
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NeuRadii.lg),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              NeuSpace.n18,
              NeuSpace.n12,
              NeuSpace.n18,
              NeuSpace.n24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.t('ui.29f830c6dd'),
                    style: TextStyle(
                      fontSize: NeuFonts.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: t.onBg,
                    ),
                  ),
                  SizedBox(height: NeuSpace.n4),
                  Text(
                    current == null
                        ? I18n.t('ui.6e6f9563b7')
                        : I18n.tp('ui.9fa88d5d6f', {
                            'name': current.name,
                            'provider': current.provider,
                          }),
                    style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                  ),
                  if (inSheetError != null) ...[
                    const SizedBox(height: NeuSpace.n8),
                    Row(
                      children: [
                        NeuIcon(IconId.warn, size: 14, color: t.danger),
                        const SizedBox(width: NeuSpace.n6),
                        Expanded(
                          child: Text(
                            inSheetError!,
                            style: TextStyle(
                              fontSize: NeuFonts.small,
                              color: t.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: NeuSpace.n14),
                  Text(
                    I18n.t('ui.11eead2c33'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final level in levels)
                        NeuPressable(
                          onTap: () async {
                            final ok = await store.setThinkingLevel(level);
                            if (!sheetContext.mounted) return;
                            setSheetState(() {
                              inSheetError = ok ? null : store.lastError;
                            });
                            if (ok) {
                              NeuToast.show(
                                sheetContext,
                                message: I18n.tp('ui.944e771000', {
                                  'level': level,
                                }),
                                icon: IconId.check,
                              );
                            }
                          },
                          flat: chat.thinkingLevel != level,
                          alwaysInset: chat.thinkingLevel == level,
                          radius: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NeuSpace.n12,
                            vertical: NeuSpace.n7,
                          ),
                          child: Text(
                            level,
                            style: TextStyle(
                              fontSize: NeuFonts.sub,
                              color: chat.thinkingLevel == level
                                  ? t.accentInk
                                  : t.fg,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: NeuSpace.n16),
                  Text(
                    I18n.t('ui.41f1f2fb0e'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n8),
                  for (final entry in byProvider.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: NeuSpace.n8,
                        bottom: NeuSpace.n4,
                      ),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: NeuFonts.label,
                          color: t.muted,
                        ),
                      ),
                    ),
                    for (final model in entry.value)
                      ModelOptionRow(
                        model: model,
                        current: current,
                        onTap: () async {
                          final ok = await store.setModel(
                            model.provider,
                            model.id,
                          );
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            inSheetError = ok
                                ? null
                                : (store.lastError ?? I18n.t('ui.2d5fbafe5d'));
                          });
                          if (ok) {
                            NeuToast.show(
                              sheetContext,
                              message: I18n.tp('ui.97523d250a', {
                                'name': model.name,
                                'provider': model.provider,
                              }),
                              icon: IconId.check,
                            );
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 输入菜单里的一格：图标 + 文字。
///
/// 点一下**先收起弹层、再执行动作** —— 顺序不能反：动作会打开相册/文件选择器，
/// 弹层压在上面会挡住它。（组件用自己的 context pop，所以不必从外面传 sheetContext。）
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconId icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Expanded(
      child: NeuPressable(
        onTap: () async {
          Navigator.of(context).pop();
          await onTap();
        },
        radius: 10,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n12,
          vertical: NeuSpace.n11,
        ),
        child: Column(
          children: [
            NeuIcon(icon, size: 18, color: t.accentInk),
            const SizedBox(height: NeuSpace.n6),
            Text(
              label,
              style: TextStyle(fontSize: NeuFonts.label, color: t.fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入菜单（弹层）：素材（图片/文件/剪贴板）+ 常用语模板。
///
/// **一个入口装两类东西**：聊天区拆两个按钮会很挤，手机上也难分。
///
/// 模板增删直接读写 `TemplateStore` 单例，改完把新列表通过
/// `onTemplatesChanged` 回报给页面 —— 页面持有 `templates` 这份状态
/// （下次打开弹层要看到最新的），弹层自己不长期持有。
Future<void> showInputMenuSheet(
  BuildContext context, {
  required TextEditingController input,
  required List<String> templates,
  required ValueChanged<List<String>> onTemplatesChanged,
  required ValueChanged<String> onInsert,
  required Future<void> Function() onPickImage,
  required Future<void> Function() onPickFile,
  required Future<void> Function() onPaste,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            NeuSpace.n18,
            NeuSpace.n14,
            NeuSpace.n18,
            NeuSpace.n24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('ui.54d363afee'),
                  style: TextStyle(
                    fontSize: NeuFonts.sub,
                    fontWeight: FontWeight.w700,
                    color: t.accentInk,
                  ),
                ),
                const SizedBox(height: NeuSpace.n8),
                Row(
                  children: [
                    MenuTile(
                      icon: IconId.download,
                      label: I18n.t('ui.824949be5b'),
                      onTap: onPickImage,
                    ),
                    SizedBox(width: NeuSpace.n8),
                    MenuTile(
                      icon: IconId.folder,
                      label: I18n.t('ui.2a0c4740f1'),
                      onTap: onPickFile,
                    ),
                    SizedBox(width: NeuSpace.n8),
                    MenuTile(
                      icon: IconId.pen,
                      label: I18n.t('ui.32249be96d'),
                      onTap: onPaste,
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n6),
                Text(
                  I18n.t('ui.6b8e604809'),
                  style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                ),
                SizedBox(height: NeuSpace.n16),
                Row(
                  children: [
                    Text(
                      I18n.t('ui.64dfcf277f'),
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        fontWeight: FontWeight.w700,
                        color: t.accentInk,
                      ),
                    ),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.14768ed565'),
                      style: TextStyle(
                        fontSize: NeuFonts.badge,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n8),
                if (templates.isEmpty)
                  Text(
                    I18n.t('ui.d0f489e127'),
                    style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                  )
                else
                  for (final item in templates)
                    NeuPressable(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onInsert(item);
                      },
                      radius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n12,
                        vertical: NeuSpace.n9,
                      ),
                      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: NeuFonts.bodySmall,
                                color: t.fg,
                              ),
                            ),
                          ),
                          NeuPressable(
                            onTap: () async {
                              await TemplateStore.instance.remove(item);
                              final items = await TemplateStore.instance.load();
                              if (!sheetContext.mounted) return;
                              setSheetState(() {});
                              onTemplatesChanged(List.of(items));
                            },
                            radius: 8,
                            flat: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NeuSpace.n14,
                                vertical: NeuSpace.n14,
                              ),
                              child: NeuIcon(
                                IconId.close,
                                size: 13,
                                color: t.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: NeuSpace.n8),
                NeuPressable(
                  onTap: () async {
                    final text = input.text.trim();
                    if (text.isEmpty) {
                      NeuToast.show(
                        sheetContext,
                        message: I18n.t('ui.37dba61d9d'),
                        icon: IconId.warn,
                      );
                      return;
                    }
                    await TemplateStore.instance.add(text);
                    final items = await TemplateStore.instance.load();
                    if (!sheetContext.mounted) return;
                    setSheetState(() {});
                    onTemplatesChanged(List.of(items));
                    NeuToast.show(
                      sheetContext,
                      message: I18n.t('ui.17ab7240c1'),
                      icon: IconId.check,
                    );
                  },
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.plus, size: 14, color: t.accentInk),
                      SizedBox(width: NeuSpace.n6),
                      Text(
                        I18n.t('ui.8551ea0b22'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodySmall,
                          color: t.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 会话详情（弹层）：用量与花费、几个跳转入口、分支树。
///
/// 几处实测得来的约束：
///   · 取数**先接住异常再提示** —— 以前是裸 await，一旦抛错面板「点了没反应」，
///     这类静默失败比报错难查得多。
///   · 用量和分支树**一起拉**，别让面板分两次刷新。
///   · **整张面板可滚动** —— 以前只有分支树那一小块能滑，上面的「用量」一多
///     就把下面的按钮顶出屏幕，怎么滑都够不到（实测三指上推都不动）。
///   · 「重点模式」开关从标题栏下沉到这里：标题栏一行要塞下会话名 + 状态点 + 模型 + 按钮，
///     四个按钮里它最低频，却是把会话名挤到 0 宽的元凶之一。
Future<void> showSessionInfoSheet(
  BuildContext context,
  ServerStore store, {
  required bool focusMode,
  required VoidCallback onToggleFocusMode,
  required void Function(String id, String preview) onFork,
  required void Function(String id, String preview) onNavigate,
}) async {
  // 这里以前是裸 await：一旦取数抛出，面板会「点了没反应」——
  // 这类静默失败比报错难查得多，所以先接住再提示。
  Map<String, dynamic>? tree;
  SessionStats? stats;
  try {
    tree = await store.fetchTree();
    // 用量/花费/上下文占用：跟分支树一起拉，别让面板分两次刷新
    stats = await store.sessionStats();
  } catch (error) {
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: I18n.tp('ui.a6664f495a', {'error': error}),
      icon: IconId.warn,
    );
    return;
  }
  if (!context.mounted) return;
  final chat = store.chat;
  final nodes = tree?['tree'];
  final leafId = tree?['leafId'] as String?;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NeuRadii.lg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n10,
          NeuSpace.n18,
          NeuSpace.n24,
        ),
        // 整张面板可滚动。
        // 以前只有分支树那一小块能滑，上面的「用量」一多就把下面按钮顶出屏幕，
        // 怎么滑都够不到（实测过：三指上推都不动）。
        child: SingleChildScrollView(
          child: Column(
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
                I18n.t('ui.155e26ceeb'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n10),
              InfoLine(
                I18n.t('common.model'),
                chat.model == null
                    ? '—'
                    : '${chat.model!.name} (${chat.model!.provider})',
              ),
              InfoLine(I18n.t('ui.11eead2c33'), chat.thinkingLevel),
              InfoLine(
                I18n.t('ui.ff692f04ac'),
                I18n.tp('ui.7622b8adf0', {
                  'n': chat.messages.length,
                  'total': chat.historyTotal,
                }),
              ),
              InfoLine(I18n.t('settings.workspace'), chat.cwd),
              if (chat.sessionName != null)
                InfoLine(I18n.t('ui.20c94429e5'), chat.sessionName!),
              if (stats != null) ...[
                SizedBox(height: NeuSpace.n6),
                Text(
                  I18n.t('ui.743735721a'),
                  style: TextStyle(
                    fontSize: NeuFonts.small,
                    fontWeight: FontWeight.w700,
                    color: t.accentInk,
                  ),
                ),
                SizedBox(height: NeuSpace.n4),
                InfoLine(
                  I18n.t('ui.50f198f07f'),
                  stats.contextPercent != null
                      ? '${stats.contextPercent!.toStringAsFixed(1)}% · ${formatTokens(stats.contextTokens)} / ${formatTokens(stats.contextWindow)}'
                      : I18n.t('ui.4f23e4de2b'),
                ),
                InfoLine(
                  'tokens',
                  I18n.tp('ui.37e8f35792', {
                    'total': formatTokens(stats.totalTokens),
                    'input': formatTokens(stats.inputTokens),
                    'output': formatTokens(stats.outputTokens),
                    'cr': formatTokens(stats.cacheReadTokens),
                    'cw': formatTokens(stats.cacheWriteTokens),
                  }),
                ),
                if (stats.costTotal > 0)
                  InfoLine(
                    I18n.t('ui.f970d0272c'),
                    '\$${stats.costTotal.toStringAsFixed(4)}',
                  ),
                InfoLine(
                  I18n.t('ui.8fd578b58a'),
                  I18n.tp('ui.d8deeeee4c', {
                    'u': stats.userMessages,
                    'a': stats.assistantMessages,
                    'tc': stats.toolCalls,
                    'tr': stats.toolResults,
                  }),
                ),
                InfoLine(
                  I18n.t('ui.dc0f2e515f'),
                  chat.autoCompactionEnabled
                      ? I18n.t('ui.9db7a84fcd')
                      : I18n.t('ui.9c58505de3'),
                ),
                const SizedBox(height: NeuSpace.n4),
                // 「重点模式」从标题栏下沉到这里：标题栏一行要塞下
                // 会话名 + 状态点 + 模型 + 按钮，四个按钮里它最低频，
                // 却是把会话名挤到 0 宽的元凶之一（实测）。
                NeuPressable(
                  onTap: () {
                    onToggleFocusMode();
                    Navigator.of(sheetContext).pop();
                    NeuToast.show(
                      context,
                      message: !focusMode
                          ? I18n.t('ui.d03d895f04')
                          : I18n.t('ui.13261adf5f'),
                      icon: IconId.bubble,
                    );
                  },
                  radius: NeuRadii.sm,
                  flat: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n6,
                    vertical: NeuSpace.n10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          I18n.t('ui.d03d895f04'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.small,
                            color: t.fg,
                          ),
                        ),
                      ),
                      Text(
                        focusMode
                            ? I18n.t('ui.9db7a84fcd')
                            : I18n.t('ui.9c58505de3'),
                        style: TextStyle(
                          fontSize: NeuFonts.label,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: NeuSpace.n12),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionExportPage(store: store),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n13,
                  vertical: NeuSpace.n13,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.download, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.cb9bf0e70e'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NeuSpace.n8),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UsagePage(
                        store: store,
                        contextPercent: stats?.contextPercent,
                        contextTokens: stats?.contextTokens,
                        contextWindow: stats?.contextWindow,
                        autoCompactEnabled: chat.autoCompactionEnabled,
                      ),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.info, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.f0d15d56eb'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NeuSpace.n8),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          WorkspaceFilesPage(store: store, cwd: chat.cwd),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n13,
                  vertical: NeuSpace.n13,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.folder, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.480b698883'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: NeuSpace.n16),
              Text(
                I18n.t('ui.19b5e0a26e'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n6),
              Text(
                nodes == null
                    ? I18n.t('ui.dd55c97800')
                    : I18n.tp('ui.d7320b9231', {'n': countTree(nodes)}),
                style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
              ),
              const SizedBox(height: NeuSpace.n10),
              if (nodes != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: treeRows(
                    t,
                    nodes,
                    0,
                    leafId,
                    onFork: onFork,
                    onNavigate: onNavigate,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
